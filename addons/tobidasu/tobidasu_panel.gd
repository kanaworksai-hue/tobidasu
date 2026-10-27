@tool
class_name TobidasuPanel
extends VBoxContainer
## Tile tagging panel: paint a pop-up mode, height and offset onto the tiles of
## a TileSet (stored in its custom data layers), then rebuild the 3D model.
##
## Left drag paints the brush, right drag clears tags, middle click picks a
## tile's tag into the brush. Tiles without a tag show the mode their rule set
## gives them (faint colour); tagged tiles are drawn strong with a frame.
## Works in the editor (bottom panel, with undo) and at runtime.

signal tags_changed

const MODE_NAMES := ["Untag", "Flat", "Block", "Dome", "Luma", "Roof", "Wall", "Skip", "Water", "Tree", "Prop"]
const MODE_COLORS := [
	Color(0, 0, 0, 0), Color(0.75, 0.75, 0.75), Color(1.0, 0.55, 0.15), Color(0.2, 0.85, 0.3),
	Color(1.0, 0.9, 0.2), Color(0.95, 0.25, 0.25), Color(0.7, 0.35, 0.95), Color(0.1, 0.1, 0.1), Color(0.2, 0.55, 1.0),
	Color(0.05, 0.6, 0.35), Color(0.85, 0.6, 0.35),
]

## Rebuilt after every stroke when `auto_build` is on.
var target: Tobidasu3D:
	set(v):
		target = v
		_refresh_target()
var tile_set: TileSet
## EditorUndoRedoManager when running inside the editor (set by the plugin).
var undo_redo: Object

var brush_mode := 3     # index into MODE_NAMES (0 = untag)
var brush_height := 0.5
var brush_offset := 0.0
var auto_build := true
var zoom := 3.0

var _source_id := -1
var _sources: OptionButton
var _view: Control
var _scroll: ScrollContainer
var _mode_buttons: Array[Button] = []
var _height: SpinBox
var _offset: SpinBox
var _info: Label
var _stroke := {}       # Vector2i atlas -> [old mode, old height, old offset]
var _stroke_erase := false
var _painting := false


func _init() -> void:
	name = "Tobidasu"
	custom_minimum_size = Vector2(0, 260)
	var bar := HBoxContainer.new()
	add_child(bar)
	_sources = OptionButton.new()
	_sources.tooltip_text = "Atlas source"
	_sources.item_selected.connect(func(i: int): _set_source(_sources.get_item_id(i)))
	bar.add_child(_sources)
	var modes := HBoxContainer.new()
	var group := ButtonGroup.new()
	for i in MODE_NAMES.size():
		var b := Button.new()
		b.text = MODE_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == brush_mode
		if i > 0:
			b.add_theme_color_override("font_color", MODE_COLORS[i].lightened(0.2))
			b.add_theme_color_override("font_pressed_color", MODE_COLORS[i].lightened(0.5))
		b.pressed.connect(func(): brush_mode = i)
		modes.add_child(b)
		_mode_buttons.append(b)
	bar.add_child(_label("Height"))
	_height = _spin(-4.0, 8.0, brush_height, func(v: float): brush_height = v)
	bar.add_child(_height)
	bar.add_child(_label("Offset"))
	_offset = _spin(-4.0, 8.0, brush_offset, func(v: float): brush_offset = v)
	bar.add_child(_offset)
	var auto := CheckBox.new()
	auto.text = "Auto build"
	auto.button_pressed = auto_build
	auto.toggled.connect(func(on: bool): auto_build = on)
	bar.add_child(auto)
	var build := Button.new()
	build.text = "Build 3D"
	build.pressed.connect(_build)
	bar.add_child(build)
	add_child(modes)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_view_input)
	_scroll.add_child(_view)
	_info = Label.new()
	_info.text = "Select a Tobidasu3D (or a TileMapLayer) to tag its tiles."
	add_child(_info)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _spin(lo: float, hi: float, v: float, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = v
	s.custom_minimum_size.x = 80
	s.value_changed.connect(cb)
	return s


## Point the panel at a TileSet directly (no rebuild target).
func set_tile_set(ts: TileSet) -> void:
	tile_set = ts
	_refresh_sources()


func _refresh_target() -> void:
	var ts: TileSet = null
	if target != null:
		for l in target.layers:
			if l != null and l.tile_set != null:
				ts = l.tile_set
				break
	set_tile_set(ts)


func _refresh_sources() -> void:
	_sources.clear()
	_source_id = -1
	if tile_set != null:
		for i in tile_set.get_source_count():
			var sid := tile_set.get_source_id(i)
			var s := tile_set.get_source(sid) as TileSetAtlasSource
			if s != null and s.texture != null:
				_sources.add_item("%d: %s" % [sid, s.texture.resource_path.get_file().get_basename() if s.texture.resource_path != "" else "atlas"], sid)
		if _sources.item_count > 0:
			_set_source(_sources.get_item_id(0))
	_update_info()
	_view.queue_redraw()


func _set_source(sid: int) -> void:
	_source_id = sid
	var s := _source()
	_view.custom_minimum_size = Vector2(s.texture.get_size()) * zoom if s != null else Vector2.ZERO
	_view.queue_redraw()


func _source() -> TileSetAtlasSource:
	if tile_set == null or _source_id < 0 or not tile_set.has_source(_source_id):
		return null
	return tile_set.get_source(_source_id) as TileSetAtlasSource


func _update_info() -> void:
	if tile_set == null:
		_info.text = "Select a Tobidasu3D (or a TileMapLayer) to tag its tiles."
	else:
		_info.text = "Left drag: paint   Right drag: clear   Middle click: pick   (tags live in the TileSet's custom data)"


# --- drawing -----------------------------------------------------------------------

func _draw_view() -> void:
	var s := _source()
	if s == null:
		return
	_view.draw_texture_rect(s.texture, Rect2(Vector2.ZERO, Vector2(s.texture.get_size()) * zoom), false)
	var has_tags := tile_set.has_custom_data_layer_by_name(TobidasuRuleSet.MODE_LAYER)
	var rs: TobidasuRuleSet = target.rule_set if target != null else null
	if rs != null:
		rs.clear_cache()
	var font := get_theme_default_font()
	for i in s.get_tiles_count():
		var atlas := s.get_tile_id(i)
		var r := Rect2(Vector2(s.get_tile_texture_region(atlas).position) * zoom, Vector2(s.get_tile_texture_region(atlas).size) * zoom)
		var mode := 0
		var tagged := false
		var h := 0.0
		var off := 0.0
		if has_tags:
			var td := s.get_tile_data(atlas, 0)
			mode = td.get_custom_data(TobidasuRuleSet.MODE_LAYER)
			tagged = mode > 0
			if tagged:
				h = td.get_custom_data(TobidasuRuleSet.HEIGHT_LAYER)
				off = td.get_custom_data(TobidasuRuleSet.OFFSET_LAYER)
		if not tagged and rs != null:
			var rule := rs.find_rule(_source_id, atlas, 1)
			mode = rule.mode + 1
			h = rule.height
		if mode <= 0:
			continue
		var c: Color = MODE_COLORS[mode]
		_view.draw_rect(r, Color(c, 0.42 if tagged else 0.16))
		if tagged:
			_view.draw_rect(r.grow(-1), c, false, 2.0)
		if font != null and zoom >= 2.0:
			var txt := "%.2f" % h if off == 0.0 else "%.2f+%.2f" % [h, off]
			_view.draw_string(font, r.position + Vector2(2, r.size.y - 3), txt, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 2, 9, Color(1, 1, 1, 0.9 if tagged else 0.5))


# --- painting ----------------------------------------------------------------------

func _view_input(event: InputEvent) -> void:
	var s := _source()
	if s == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			_pick(_atlas_at(mb.position))
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if mb.pressed:
				_stroke.clear()
				_painting = true
				_stroke_erase = mb.button_index == MOUSE_BUTTON_RIGHT
				paint(_atlas_at(mb.position), _stroke_erase)
			else:
				_painting = false
				_end_stroke()
		_view.accept_event()
	elif event is InputEventMouseMotion and _painting:
		paint(_atlas_at((event as InputEventMouseMotion).position), _stroke_erase)


func _atlas_at(p: Vector2) -> Vector2i:
	var s := _source()
	if s == null:
		return Vector2i(-1, -1)
	return s.get_tile_at_coords(Vector2i((p / zoom).floor()))


## Paints the brush (or clears the tag) on one tile. Part of the current stroke.
func paint(atlas: Vector2i, erase := false) -> void:
	var s := _source()
	if s == null or atlas == Vector2i(-1, -1) or _stroke.has(atlas):
		return
	TobidasuRuleSet.ensure_tag_layers(tile_set)
	var td := s.get_tile_data(atlas, 0)
	_stroke[atlas] = [td.get_custom_data(TobidasuRuleSet.MODE_LAYER), td.get_custom_data(TobidasuRuleSet.HEIGHT_LAYER), td.get_custom_data(TobidasuRuleSet.OFFSET_LAYER)]
	var m := 0 if erase else brush_mode
	_set_tag(_source_id, atlas, m, brush_height if m > 0 else 0.0, brush_offset if m > 0 else 0.0)


## Commits the stroke (one undo step in the editor) and rebuilds.
func _end_stroke() -> void:
	if _stroke.is_empty():
		return
	if undo_redo != null:
		undo_redo.create_action("Tobidasu: tag tiles")
		for atlas in _stroke:
			var old: Array = _stroke[atlas]
			var td := _source().get_tile_data(atlas, 0)
			undo_redo.add_do_method(self, &"_set_tag", _source_id, atlas, td.get_custom_data(TobidasuRuleSet.MODE_LAYER), td.get_custom_data(TobidasuRuleSet.HEIGHT_LAYER), td.get_custom_data(TobidasuRuleSet.OFFSET_LAYER))
			undo_redo.add_undo_method(self, &"_set_tag", _source_id, atlas, old[0], old[1], old[2])
		undo_redo.add_do_method(self, &"_after_change")
		undo_redo.add_undo_method(self, &"_after_change")
		# Already applied while painting.
		undo_redo.commit_action(false)
	_stroke.clear()
	_after_change()


## A tag belongs to the tile: it is written to all of its alternatives (flipped copies).
func _set_tag(sid: int, atlas: Vector2i, mode: int, h: float, off: float) -> void:
	var s := tile_set.get_source(sid) as TileSetAtlasSource
	for k in s.get_alternative_tiles_count(atlas):
		var td := s.get_tile_data(atlas, s.get_alternative_tile_id(atlas, k))
		td.set_custom_data(TobidasuRuleSet.MODE_LAYER, mode)
		td.set_custom_data(TobidasuRuleSet.HEIGHT_LAYER, h)
		td.set_custom_data(TobidasuRuleSet.OFFSET_LAYER, off)
	_view.queue_redraw()


func _after_change() -> void:
	tile_set.emit_changed()
	if Engine.is_editor_hint():
		# A TileSet saved as its own file is written right away; one embedded
		# in a scene marks the scene unsaved. (Looked up dynamically so the
		# panel also runs in exported games.)
		var path := tile_set.resource_path
		if path != "" and not path.contains("::"):
			ResourceSaver.save(tile_set)
		elif Engine.has_singleton("EditorInterface"):
			Engine.get_singleton("EditorInterface").mark_scene_as_unsaved()
	_view.queue_redraw()
	tags_changed.emit()
	if auto_build:
		_build()


func _pick(atlas: Vector2i) -> void:
	var s := _source()
	if s == null or atlas == Vector2i(-1, -1) or not tile_set.has_custom_data_layer_by_name(TobidasuRuleSet.MODE_LAYER):
		return
	var td := s.get_tile_data(atlas, 0)
	var m: int = td.get_custom_data(TobidasuRuleSet.MODE_LAYER)
	if m <= 0:
		return
	brush_mode = m
	_mode_buttons[m].button_pressed = true
	_height.value = td.get_custom_data(TobidasuRuleSet.HEIGHT_LAYER)
	_offset.value = td.get_custom_data(TobidasuRuleSet.OFFSET_LAYER)


func _build() -> void:
	if target != null and is_instance_valid(target):
		target.build()

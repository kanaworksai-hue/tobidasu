@tool
@icon("res://addons/tobidasu/icon.svg")
class_name Tobidasu3D
extends Node3D
## Builds a pop-up 3D model from 2D TileMapLayers and animates 2D <-> 3D.
##
## Add this node to a 3D scene, point `layers` at your TileMapLayers (bottom
## layer first), pick a rule set and press "Build 3D" in the inspector.
## Animate `pop` (0 = flat 2D map, 1 = 3D) and `shade` (0 = unlit 2D colours).
## `sprites` (Sprite2D / AnimatedSprite2D on the map) follow along as cards
## that lie flat in 2D and stand up facing the camera in 3D.

signal built(stats: Dictionary)

const POP_SHADER := preload("res://addons/tobidasu/tobidasu_pop.gdshader")
const WATER_SHADER := preload("res://addons/tobidasu/tobidasu_water.gdshader")
const CARD_SHADER := preload("res://addons/tobidasu/tobidasu_billboard.gdshader")

## TileMapLayers to convert, bottom layer first.
@export var layers: Array[TileMapLayer] = []
@export var rule_set: TobidasuRuleSet
## Sprite2D / AnimatedSprite2D nodes placed on the map (same coordinates as the layers).
@export var sprites: Array[Node2D] = []
## Center the model on this node's origin instead of starting at the map corner.
@export var center := true
@export var build_on_ready := true
@export_range(0.0, 1.0) var pop := 1.0:
	set(v):
		pop = v
		_set_param(&"pop", v)
@export_range(0.0, 1.0) var shade := 1.0:
	set(v):
		shade = v
		_set_param(&"shade", v)
## Stable pixels in 3D: texels stay crisp up close and stop shimmering in the
## distance (0 = plain nearest sampling). The flat 2D map is never affected.
@export_range(0.0, 1.0) var stable_pixels := 1.0:
	set(v):
		stable_pixels = v
		_set_param(&"stable_pixels", v)
@export_tool_button("Build 3D", "MeshInstance3D") var build_button := build

@export_group("Juice (3D only)")
## Trees bend in the wind (0 = still). Everything in this group is 3D only:
## it fades out before `pop` reaches 0, so the flat map stays pixel-exact.
@export_range(0.0, 3.0) var wind_strength := 1.0:
	set(v):
		wind_strength = v
		_set_param(&"wind_strength", v)
@export_range(0.0, 4.0) var wind_speed := 1.0:
	set(v):
		wind_speed = v
		_set_param(&"wind_speed", v)
## Direction the wind blows on the map (x right, y down the map).
@export var wind_direction := Vector2(1.0, 0.35):
	set(v):
		wind_direction = v
		_set_param(&"wind_direction", v)
## Height-field ambient occlusion: darker ground next to houses, trees and cliffs.
@export_range(0.0, 1.0) var ambient_occlusion := 0.55:
	set(v):
		ambient_occlusion = v
		_set_param(&"ao_strength", v)
## Soft cloud shadows drifting with the wind (sunlight only).
@export_range(0.0, 1.0) var cloud_shadows := 0.0:
	set(v):
		cloud_shadows = v
		_set_param(&"cloud_shadows", v)
## Window panes (see TobidasuRule.glow_colors) and doorways light up (0 = day, 1 = night).
@export_range(0.0, 1.0) var night_lights := 0.0:
	set(v):
		night_lights = v
		_set_param(&"night_lights", v)
## Brighter top pixel row on side faces.
@export_range(0.0, 0.5) var edge_highlight := 0.1:
	set(v):
		edge_highlight = v
		_set_param(&"edge_highlight", v)

@export_group("Moving part")
## Makes this model a moving part of another map (a train car, a cable car).
## Build it from its own small TileMapLayers placed in that map's 2D scene and
## move those layers: the model rides along on `follow`'s map, in 2D and in 3D,
## pops up as one piece and takes pop, shade and the juice settings from it.
@export var follow: Tobidasu3D:
	set(v):
		# no following yourself, or round in a circle
		var up := v
		while up != null:
			if up == self:
				push_warning("Tobidasu3D.follow: that would follow itself.")
				return
			up = up.follow
		if follow != null and is_instance_valid(follow):
			follow._followers.erase(self)
		follow = v
		if follow != null:
			follow._followers.append(self)
			center = false
## Moving part: stand on the followed map's ground (under the bottom middle of
## the part). Off: `elevation` is the height above the map's base (a cable car).
@export var follow_ground := true
## Moving part: extra 3D height (or the whole height when not on the ground).
@export var elevation := 0.0
## Moving part: everything outside this rectangle (tiles of the followed map)
## is cut away, in 2D and 3D: a train going into a tunnel or off the map.
## Empty = nothing is cut.
@export var visible_rect := Rect2()

var mesh_instance: MeshInstance3D
var stats := {}
var _materials: Array[ShaderMaterial] = []
var _builder: TobidasuBuilder
var _cards_root: Node3D
var _cards := {}   # sprite instance id -> [MeshInstance3D, ShaderMaterial, ground y]
var _card_mesh: ArrayMesh
var _mip_cache := {}   # texture instance id -> mipmapped copy
var _params := {}      # shader parameters set so far (passed on to moving parts)
var _followers: Array[Tobidasu3D] = []
var _light_img: Image
var _light_tex: ImageTexture
## Animation clock (seconds) for the well bucket; advanced in _process.
var anim_clock := 0.0


func _ready() -> void:
	if build_on_ready:
		build()


func _exit_tree() -> void:
	if follow != null and is_instance_valid(follow):
		follow._followers.erase(self)


func _enter_tree() -> void:
	if follow != null and is_instance_valid(follow) and not follow._followers.has(self):
		follow._followers.append(self)


func build() -> void:
	var t0 := Time.get_ticks_msec()
	_builder = TobidasuBuilder.new()
	_builder.collapse_sunk = follow != null
	var mesh := _builder.build(layers, rule_set)
	if mesh_instance == null or not is_instance_valid(mesh_instance):
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "PopMesh"
		add_child(mesh_instance, false, Node.INTERNAL_MODE_FRONT)
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_materials.clear()
	var ao_tex: Texture2D = ImageTexture.create_from_image(_builder.ao_image) if _builder.ao_image != null else null
	if _light_img == null or _light_img.get_size() != _builder.map_cells:
		_light_img = Image.create(maxi(_builder.map_cells.x, 1), maxi(_builder.map_cells.y, 1), false, Image.FORMAT_R8)
		_light_img.fill(Color.WHITE)
		_light_tex = ImageTexture.create_from_image(_light_img)
	for i in mesh.get_surface_count():
		var m := ShaderMaterial.new()
		if mesh.get_meta("kind_%d" % i, "atlas") == "water":
			m.shader = WATER_SHADER
			m.render_priority = 1
		else:
			m.shader = POP_SHADER
			m.set_shader_parameter(&"atlas", mesh.get_meta("texture_%d" % i))
			m.set_shader_parameter(&"atlas_mips", _mipmapped(mesh.get_meta("texture_%d" % i)))
			m.set_shader_parameter(&"atlas_grid", mesh.get_meta("grid_%d" % i, Vector4(0, 0, _builder.tile_px, _builder.tile_px)))
			m.set_shader_parameter(&"soil_depth", rule_set.base_thickness if rule_set != null else 0.6)
			m.set_shader_parameter(&"ao_map", ao_tex)
			m.set_shader_parameter(&"map_cells", Vector2(_builder.map_cells))
			m.set_shader_parameter(&"glow_mask", mesh.get_meta("glow_%d" % i) if mesh.has_meta("glow_%d" % i) else null)
			m.set_shader_parameter(&"light_map", _light_tex)
			for p in [[&"wind_strength", wind_strength], [&"wind_speed", wind_speed], [&"wind_direction", wind_direction],
					[&"ao_strength", ambient_occlusion], [&"cloud_shadows", cloud_shadows], [&"night_lights", night_lights],
					[&"edge_highlight", edge_highlight]]:
				m.set_shader_parameter(p[0], p[1])
		m.set_shader_parameter(&"pixels_per_unit", float(_builder.tile_px))
		m.set_shader_parameter(&"pop", pop)
		m.set_shader_parameter(&"shade", shade)
		m.set_shader_parameter(&"stable_pixels", stable_pixels)
		var src_params: Dictionary = follow._params if follow != null and is_instance_valid(follow) else _params
		for p in src_params:
			m.set_shader_parameter(p, src_params[p])
		mesh.surface_set_material(i, m)
		_materials.append(m)
	var size := Vector2(_builder.map_cells)
	mesh_instance.position = Vector3(-size.x * 0.5, 0, -size.y * 0.5) if center else Vector3.ZERO
	_rebuild_cards()
	if not Engine.is_editor_hint():
		_update_follow()
	stats = _builder.get_stats()
	stats["build_ms"] = Time.get_ticks_msec() - t0
	stats["map_size"] = size
	built.emit(stats)


## Map size in tiles (world units) of the last build.
func get_map_size() -> Vector2:
	return stats.get("map_size", Vector2.ZERO)


## Ground height under a point of the 2D map (in layer pixels), in world units.
func ground_height_at_map(map_pos: Vector2) -> float:
	if _builder == null:
		return 0.0
	var p := _map_to_tiles(map_pos)
	return _builder.ground_height(p.x, p.y)


## Buildings of the last build: { rect = Rect2 in local tiles (same space as
## map_to_local without the centering offset), wall_height, ridge, base = height
## the walls rise from (> 0 on a terrace) }.
func get_buildings() -> Array[Dictionary]:
	return _builder.buildings if _builder != null else ([] as Array[Dictionary])


## Trees of the last build: { root = Vector3 in local tiles (x, ground y, z),
## height, radius, color = average canopy colour, cut = half tree on a tile edge }.
func get_trees() -> Array[Dictionary]:
	return _builder.trees if _builder != null else ([] as Array[Dictionary])


## Grass clumps of the last build: { pos = Vector3 in local tiles (base) }.
func get_tufts() -> Array[Dictionary]:
	return _builder.tufts if _builder != null else ([] as Array[Dictionary])


## Wells of the last build: { pos = Vector3 in local tiles (the water), phase }.
func get_wells() -> Array[Dictionary]:
	return _builder.wells if _builder != null else ([] as Array[Dictionary])


## Where a well's bucket is in its 7 s cycle (seconds): 1.0 starts lowering,
## ~2.4 hits the water, 3.3 starts the haul up, ~5.7 is back at the top.
const BUCKET_CYCLE := 7.0
func bucket_time(well: Dictionary) -> float:
	return fposmod(anim_clock / BUCKET_CYCLE + float(well["phase"]), 1.0) * BUCKET_CYCLE


## Local 3D position of a point given in tiles (x, z) on the popped model.
func tiles_to_local(p: Vector2) -> Vector3:
	return mesh_instance.position + Vector3(p.x, _builder.ground_height(p.x, p.y) if _builder != null else 0.0, p.y)


## A 2D map position (layer pixels) -> local 3D position on the popped model.
func map_to_local(map_pos: Vector2) -> Vector3:
	var p := _map_to_tiles(map_pos)
	return mesh_instance.position + Vector3(p.x, ground_height_at_map(map_pos), p.y)


func set_material_param(param: StringName, value: Variant) -> void:
	_set_param(param, value)


## Switches the night lights (window panes, doorways) of a rectangle of cells
## (tiles, the space of get_buildings()) on (1), off (0) or in between: a shop
## that closes for the night while the inn next door stays lit.
func set_lights(cells: Rect2i, amount: float) -> void:
	if _light_img == null:
		return
	var r := cells.intersection(Rect2i(Vector2i.ZERO, _light_img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	_light_img.fill_rect(r, Color(amount, amount, amount))
	_light_tex.update(_light_img)


func _set_param(param: StringName, value: Variant) -> void:
	_params[param] = value
	for m in _materials:
		m.set_shader_parameter(param, value)
	for id in _cards:
		(_cards[id][1] as ShaderMaterial).set_shader_parameter(param, value)
	for f in _followers:
		if is_instance_valid(f):
			f._set_param(param, value)


## Pop-up curve of the pop shader (pop_progress + ease_out_back with the
## default window and overshoot): how far a piece with `delay` has moved.
static func pop_curve(pop_value: float, delay: float, window := 0.35, overshoot := 1.6) -> float:
	var k := clampf((pop_value - delay * (1.0 - window)) / window, 0.0, 1.0)
	var x := k - 1.0
	return 1.0 + (overshoot + 1.0) * x * x * x + overshoot * x * x


## Moving part: puts the model where its layers are on the followed map.
func _update_follow() -> void:
	if follow == null or not is_instance_valid(follow) or follow._builder == null or _builder == null:
		return
	if layers.is_empty() or layers[0] == null or follow.layers.is_empty() or follow.layers[0] == null:
		return
	var xf: Transform2D = follow.layers[0].global_transform.affine_inverse() * layers[0].global_transform
	var tp := float(_builder.tile_px)
	var tl: Vector2 = (xf * (Vector2(_builder.map_origin) * tp)) / tp - Vector2(follow._builder.map_origin)
	var size := Vector2(_builder.map_cells)
	var mid := tl + size * 0.5
	var dl := follow._builder.delay_at(mid.x, mid.y)
	var e := pop_curve(follow.pop, dl, follow._params.get(&"window", 0.35), follow._params.get(&"overshoot", 1.6))
	# ground under the bottom middle, or under the nearest point still shown
	# (a train half in a tunnel stands on the track, not on the hill above it)
	var foot := Vector2(mid.x, tl.y + size.y - 0.05)
	if visible_rect.has_area():
		foot = foot.clamp(visible_rect.position, visible_rect.end - Vector2(0.01, 0.01))
	var y3 := elevation + (follow._builder.ground_height(foot.x, foot.y) if follow_ground else 0.0)
	if not follow_ground:
		e = minf(e, 1.0)   # hanging on a cable: no bounce past it
	# flat: over the whole map, under the sprite cards (flat_top + 2 eps)
	var y0 := follow._builder.flat_top + TobidasuBuilder.FLAT_EPS * 0.5
	var origin := follow.mesh_instance.position + Vector3(tl.x, lerpf(y0, y3, e), tl.y)
	global_transform = follow.global_transform * Transform3D(Basis(), origin)
	var clip := Vector4(-1e9, -1e9, 1e9, 1e9)
	if visible_rect.has_area():
		var a := follow.to_global(follow.mesh_instance.position + Vector3(visible_rect.position.x, 0.0, visible_rect.position.y))
		var b := follow.to_global(follow.mesh_instance.position + Vector3(visible_rect.end.x, 0.0, visible_rect.end.y))
		clip = Vector4(minf(a.x, b.x), minf(a.z, b.z), maxf(a.x, b.x), maxf(a.z, b.z))
	for m in _materials:
		m.set_shader_parameter(&"delay_override", dl)
		m.set_shader_parameter(&"clip_rect", clip)
		# where the part is on the map (clouds, lights climbing up, flicker)
		m.set_shader_parameter(&"part_offset", Vector3(tl.x, y3, tl.y))


func _map_to_tiles(map_pos: Vector2) -> Vector2:
	var tp := float(_builder.tile_px) if _builder != null else 16.0
	return map_pos / tp - Vector2(_builder.map_origin if _builder != null else Vector2i.ZERO)


# --- sprite cards -------------------------------------------------------------------

func _process(_delta: float) -> void:
	anim_clock += _delta
	if follow != null and not Engine.is_editor_hint():
		_update_follow()
	for m in _materials:
		m.set_shader_parameter(&"anim_clock", anim_clock)
	if not _cards.is_empty():
		_update_cards(_delta)


func _rebuild_cards() -> void:
	if _cards_root == null or not is_instance_valid(_cards_root):
		_cards_root = Node3D.new()
		_cards_root.name = "Cards"
		add_child(_cards_root, false, Node.INTERNAL_MODE_FRONT)
	_cards_root.position = mesh_instance.position
	for id in _cards:
		(_cards[id][0] as Node).queue_free()
	_cards.clear()
	if _card_mesh == null:
		_card_mesh = _make_card_mesh()
	for s in sprites:
		if s == null or not (s is Sprite2D or s is AnimatedSprite2D):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _card_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var m := ShaderMaterial.new()
		m.shader = CARD_SHADER
		m.set_shader_parameter(&"pop", pop)
		m.set_shader_parameter(&"shade", shade)
		m.set_shader_parameter(&"stable_pixels", stable_pixels)
		m.set_shader_parameter(&"flat_y", _builder.flat_top + TobidasuBuilder.FLAT_EPS * 2.0)
		mi.material_override = m
		_cards_root.add_child(mi)
		_cards[s.get_instance_id()] = [mi, m, NAN, s]
	_update_cards(0.0)


func _make_card_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader moves the card anywhere on the map.
	m.custom_aabb = AABB(Vector3(-512, -16, -512), Vector3(1024, 64, 1024))
	return m


func _update_cards(delta: float) -> void:
	if _builder == null or layers.is_empty() or layers[0] == null:
		return
	var ref := layers[0]
	for id in _cards:
		var entry: Array = _cards[id]
		var s = entry[3]
		if not is_instance_valid(s):
			continue
		var mi: MeshInstance3D = entry[0]
		var m: ShaderMaterial = entry[1]
		mi.visible = s.visible
		var frame := _sprite_frame(s)
		if frame.is_empty():
			mi.visible = false
			continue
		var tex: Texture2D = frame[0]
		var region: Rect2 = frame[1]
		var local_rect: Rect2 = frame[2]
		# Sprite rectangle in layer pixels (no rotation support).
		var xf: Transform2D = ref.global_transform.affine_inverse() * s.global_transform
		var a: Vector2 = xf * local_rect.position
		var b: Vector2 = xf * local_rect.end
		var r := Rect2(a, Vector2.ZERO).expand(b)
		var tl := _map_to_tiles(r.position)
		var sz := r.size / float(_builder.tile_px)
		var ts := Vector2(tex.get_size())
		var uv0 := region.position / ts
		var uv1 := region.end / ts
		var flip_h: bool = s.flip_h
		var flip_v: bool = s.flip_v
		if flip_h:
			var tmp := uv0.x
			uv0.x = uv1.x
			uv1.x = tmp
		if flip_v:
			var tmp := uv0.y
			uv0.y = uv1.y
			uv1.y = tmp
		var feet := Vector2(tl.x + sz.x * 0.5, tl.y + sz.y)
		var g := _builder.ground_height(feet.x, feet.y - 0.5 / _builder.tile_px)
		var gy: float = entry[2]
		gy = g if is_nan(gy) or delta <= 0.0 else lerpf(gy, g, clampf(delta * 12.0, 0.0, 1.0))
		entry[2] = gy
		m.set_shader_parameter(&"sprite", tex)
		m.set_shader_parameter(&"sprite_mips", _mipmapped(tex))
		m.set_shader_parameter(&"uv_rect", Vector4(uv0.x, uv0.y, uv1.x, uv1.y))
		m.set_shader_parameter(&"flat_rect", Vector4(tl.x, tl.y, sz.x, sz.y))
		m.set_shader_parameter(&"ground_y", gy)
		m.set_shader_parameter(&"delay", _builder.delay_at(feet.x, feet.y))


## [base texture, region in it, local rect of the drawn frame] or [].
func _sprite_frame(s: Node2D) -> Array:
	var tex: Texture2D
	var centered: bool = s.centered
	var offset: Vector2 = s.offset
	if s is Sprite2D:
		var sp := s as Sprite2D
		tex = sp.texture
		if tex == null:
			return []
		var region := Rect2(Vector2.ZERO, tex.get_size())
		if sp.region_enabled:
			region = sp.region_rect
		var fs := region.size / Vector2(sp.hframes, sp.vframes)
		region = Rect2(region.position + fs * Vector2(sp.frame_coords), fs)
		return _resolve_atlas(tex, region, centered, offset)
	var an := s as AnimatedSprite2D
	if an.sprite_frames == null or not an.sprite_frames.has_animation(an.animation):
		return []
	if an.sprite_frames.get_frame_count(an.animation) == 0:
		return []
	tex = an.sprite_frames.get_frame_texture(an.animation, an.frame)
	if tex == null:
		return []
	return _resolve_atlas(tex, Rect2(Vector2.ZERO, tex.get_size()), centered, offset)


func _resolve_atlas(tex: Texture2D, region: Rect2, centered: bool, offset: Vector2) -> Array:
	var size := region.size
	var local := Rect2((-size * 0.5 if centered else Vector2.ZERO) + offset, size)
	while tex is AtlasTexture:
		var at := tex as AtlasTexture
		region = Rect2(at.region.position + region.position, region.size)
		tex = at.atlas
	return [tex, region, local]


## Mipmapped copy of a texture for the stable-pixel filter (box-filtered mips
## stay inside power-of-two tiles of a packed atlas).
func _mipmapped(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var id := tex.get_instance_id()
	if not _mip_cache.has(id):
		var img := tex.get_image()
		if img == null:
			return tex
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		_mip_cache[id] = ImageTexture.create_from_image(img)
	return _mip_cache[id]

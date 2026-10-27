@tool
class_name TobidasuRuleSet
extends Resource
## Ordered list of rules. The first matching rule wins.
##
## Tiles can also be tagged directly in the TileSet (the Tobidasu editor panel
## paints the custom data layers below). A tagged tile overrides the mode and
## height of the matching rule and keeps its other settings; a tile raised by
## its offset gets cliff sides.

const MODE_LAYER := "tobidasu_mode"      ## int: 0 = untagged, otherwise Mode + 1.
const HEIGHT_LAYER := "tobidasu_height"  ## float: height in tiles.
const OFFSET_LAYER := "tobidasu_offset"  ## float: base offset in tiles.

@export var rules: Array[TobidasuRule] = []
## Used when no rule matches. Ground layer (index 0) falls back to FLAT,
## higher layers to this rule; null means BLOCK with `fallback_height`.
@export var fallback: TobidasuRule
@export var fallback_height := 0.25
## Thickness of the diorama base under the map.
@export var base_thickness := 0.6

var _cache := {}
var _tagged := {}
var _fallbacks := {}


func find_rule(src: int, atlas: Vector2i, layer_index: int) -> TobidasuRule:
	var key := Vector3i(src, atlas.x, atlas.y)
	if _cache.has(key):
		var cached: TobidasuRule = _cache[key]
		return cached if cached != null else _fallback_for(layer_index)
	for r in rules:
		if r != null and r.matches(src, atlas):
			_cache[key] = r
			return r
	_cache[key] = null
	return _fallback_for(layer_index)


## Rule for a placed tile, honouring tags painted into the TileSet.
func find_rule_for_tile(tile_set: TileSet, src: int, atlas: Vector2i, alt: int, layer_index: int) -> TobidasuRule:
	var base := find_rule(src, atlas, layer_index)
	if tile_set == null or not tile_set.has_custom_data_layer_by_name(MODE_LAYER):
		return base
	var key := [tile_set.get_instance_id(), src, atlas, alt, layer_index]
	if _tagged.has(key):
		var t: TobidasuRule = _tagged[key]
		return t if t != null else base
	var r: TobidasuRule = null
	var source := tile_set.get_source(src) as TileSetAtlasSource
	if source != null and source.has_tile(atlas) and source.has_alternative_tile(atlas, alt):
		var td := source.get_tile_data(atlas, alt)
		var m: int = td.get_custom_data(MODE_LAYER)
		if m > 0:
			r = base.duplicate()
			r.mode = (m - 1) as TobidasuRule.Mode
			if tile_set.has_custom_data_layer_by_name(HEIGHT_LAYER):
				r.height = td.get_custom_data(HEIGHT_LAYER)
			if tile_set.has_custom_data_layer_by_name(OFFSET_LAYER):
				r.base_offset = td.get_custom_data(OFFSET_LAYER)
				# A tile raised well above the ground is a plateau: its edges are cliffs.
				if r.base_offset >= TobidasuBuilder.CLIFF_MIN_DROP:
					r.cliff = true
			# Tagged tiles of the same mode connect with each other.
			if r.group == "":
				r.group = "tag_%d" % r.mode
	_tagged[key] = r
	return r if r != null else base


func clear_cache() -> void:
	_cache.clear()
	_tagged.clear()


func _fallback_for(layer_index: int) -> TobidasuRule:
	if fallback != null:
		return fallback
	var k := mini(layer_index, 1)
	if _fallbacks.has(k):
		return _fallbacks[k]
	var r := TobidasuRule.new()
	if layer_index == 0:
		r.mode = TobidasuRule.Mode.FLAT
		r.height = 0.0
	else:
		r.mode = TobidasuRule.Mode.BLOCK
		r.height = fallback_height
	_fallbacks[k] = r
	return r


## Adds the custom data layers used for tagging tiles (if missing).
static func ensure_tag_layers(tile_set: TileSet) -> void:
	if not tile_set.has_custom_data_layer_by_name(MODE_LAYER):
		var i := tile_set.get_custom_data_layers_count()
		tile_set.add_custom_data_layer()
		tile_set.set_custom_data_layer_name(i, MODE_LAYER)
		tile_set.set_custom_data_layer_type(i, TYPE_INT)
	if not tile_set.has_custom_data_layer_by_name(HEIGHT_LAYER):
		var i := tile_set.get_custom_data_layers_count()
		tile_set.add_custom_data_layer()
		tile_set.set_custom_data_layer_name(i, HEIGHT_LAYER)
		tile_set.set_custom_data_layer_type(i, TYPE_FLOAT)
	if not tile_set.has_custom_data_layer_by_name(OFFSET_LAYER):
		var i := tile_set.get_custom_data_layers_count()
		tile_set.add_custom_data_layer()
		tile_set.set_custom_data_layer_name(i, OFFSET_LAYER)
		tile_set.set_custom_data_layer_type(i, TYPE_FLOAT)

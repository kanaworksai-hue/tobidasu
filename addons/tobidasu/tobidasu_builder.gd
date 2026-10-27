@tool
class_name TobidasuBuilder
extends RefCounted
## Turns TileMapLayers into one pop-up 3D mesh.
##
## Every vertex carries two positions: its flat position (VERTEX, looks exactly
## like the 2D map from straight above) and its 3D position (CUSTOM0.xyz).
## The pop shader blends between them, so the same mesh is both the 2D map and
## the 3D model. Vertex layout:
##   CUSTOM0.xyz  3D position, CUSTOM0.w start delay of the animation
##   CUSTOM1.xyz  3D normal,   CUSTOM1.w side faces: depth below the top edge,
##                             building lid: wall height
##   COLOR.r      1 = transparent pixels are filled with a dark interior (doorways)
##   COLOR.g      side faces: direction (in the atlas) toward the inside of the shape
##   COLOR.b      kind / 8 (see KIND_*), COLOR.a building lid: wall rows / 8
##   CUSTOM2.xyz  wind pivot (root of a tree, 3D), CUSTOM2.w its height (0 = no wind);
##                w = -1: well bucket / rope (x phase, y points below it move, z drop)
##
## Ground-like tiles go through a pixel heightfield: each pixel of each tile gets
## a height, top faces are greedily merged inside a tile, side walls are emitted
## wherever neighbouring pixels differ in height (so cliffs, fences and
## cross-tile seams come out automatically). ROOF/WALL tiles are grouped into
## buildings: the facade folds up on a hinge, the roof becomes a gable over the
## footprint, "^" tiles become cross gables.

const FLAT_EPS := 0.002
## Side faces of cliff tiles taller than this get rock strata.
const CLIFF_MIN_DROP := 0.15
## A building whose whole footprint stands at least this high (a terrace,
## a plateau) is raised onto it; lower ground (grass bumps) is ignored.
const BUILDING_RAISE_MIN := 0.15
## UV inset (in pixels) that keeps nearest sampling inside the tile.
const UV_INSET := 0.02
## 3D overlap of neighbouring facade tiles (tiles), against hairline cracks.
const FACADE_OVERLAP := 0.006
## 3D outer side faces of TREE shapes sit this far inside their pixel column, so one
## on a tile edge never shares a plane with a building's side wall (the hall's
## corner pillars z-fought with it: flickering red teeth on the white wall).
const TREE_SIDE_INSET := 0.003
## How far (in tiles) top faces reach over their edges.
const SEAM_OVERLAP := 0.0015

const KIND_NORMAL := 0
const KIND_SOIL := 1      # side of the diorama base
const KIND_CLIFF := 2     # tall side of a cliff tile
const KIND_SOIL_CLIFF := 3  # cliff on the edge of the map: rock above ground, soil below
const KIND_HINGE := 4     # building facade / side walls: fold up on a hinge
const KIND_LID := 6       # roof: rides on top of the folding facade
const KIND_WATER := 8     # water bed

const PX_WATER := 1
const PX_CLIFF := 2

var tile_px := 16
var map_origin := Vector2i.ZERO   # first used cell
var map_cells := Vector2i.ZERO    # size in cells
var bounds := AABB()
## Highest flat (2D) height used by the mesh; sprite cards lie above it.
var flat_top := 0.0
## Buildings of the last build: { rect = Rect2 in tiles, wall_height, ridge,
## base = height the walls rise from (> 0 on a terrace) }.
var buildings: Array[Dictionary] = []
## Trees of the last build: { root = Vector3 in tiles (x, ground y, z), height,
## radius (tiles), color = average canopy colour, cut = half tree on a tile edge }.
var trees: Array[Dictionary] = []
## Mean occluder height around every pixel (R8, (h + 1) / 4), for the cheap
## height-field ambient occlusion of the shader. One texel per map pixel.
var ao_image: Image
## source id -> Image (atlas size, R = 1 on window pixels that glow at night,
## G = 1 on bloom pixels).
var glow_masks := {}
## Wells of the last build: { pos = Vector3 (local tiles, the well water), phase = 0..1 }.
var wells: Array[Dictionary] = []
## Grass clumps of the last build: { pos = Vector3 in local tiles (base) }.
var tufts: Array[Dictionary] = []
## Tiles kept flat under standing models (their outline in 2D) shrink away to a
## point in 3D instead of sinking under the ground: for moving parts, which may
## hang in the air (Tobidasu3D.follow).
var collapse_sunk := false

var _rules: TobidasuRuleSet
var _sources := {}        # source_id -> TileSetAtlasSource
var _images := {}         # source_id -> Image
var _tile_cache := {}     # Vector3i(src, ax, ay) -> [alpha, luma, region pos, colours]
var _sink_cache := {}
var _surfaces := {}       # key -> _Surface

# Pixel heightfield (W x H pixels).
var _w := 0
var _h := 0
var _height := PackedFloat32Array()
var _ground := PackedFloat32Array()  # heights after the ground layer (for characters)
var _layer := PackedInt32Array()   # top visible layer at pixel, -1 = empty
var _rx := PackedInt32Array()      # atlas region (tile origin) of the visible pixel
var _ry := PackedInt32Array()
var _flip := PackedByteArray()     # 1 = flip h, 2 = flip v, 4 = transpose
var _src := PackedInt32Array()
var _kind := PackedByteArray()     # PX_* flags
var _wl := PackedFloat32Array()    # water surface level
var _wind := Vector4.ZERO          # CUSTOM2 of the faces being emitted
var _y3d := 0.0                    # added to the 3D height of the faces being emitted (raised buildings)
var _flat := PackedFloat32Array()  # flat (2D) height of the buildings at each pixel
var _windows_done := {}
var _bloom := {}                   # pixel index -> [src, region pos, flip, cell, lx, ly, layer, rule]
var _bloom_cache := {}
var _tuft := {}                    # pixel index -> [src, region pos, flip, cell, lx, ly, layer, rule]
var _tuft_cells := {}              # ground cell -> [src, rule, layer, fallback uv] (extra clumps)
var _tuft_cache := {}
var _covered_cells := {}           # cells under buildings / trees / props (no flowers or grass there)


class _Surface:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var custom2 := PackedFloat32Array()
	var indices := PackedInt32Array()
	var texture: Texture2D
	var src := -1
	var kind := "atlas"
	## Atlas tile grid (margin x, y, step x, y) in texels.
	var grid := Vector4(0, 0, 16, 16)


func build(layers: Array, rules: TobidasuRuleSet) -> ArrayMesh:
	_rules = rules if rules != null else TobidasuRuleSet.new()
	_rules.clear_cache()
	_sink_cache.clear()
	buildings.clear()
	trees.clear()
	wells.clear()
	tufts.clear()
	_tuft.clear()
	_tuft_cells.clear()
	_tuft_cache.clear()
	_covered_cells.clear()
	glow_masks.clear()
	_windows_done.clear()
	_bloom.clear()
	_bloom_cache.clear()
	_wind = Vector4.ZERO
	var valid: Array[TileMapLayer] = []
	for l in layers:
		if l is TileMapLayer and l.tile_set != null:
			valid.append(l)
	if valid.is_empty():
		push_warning("Tobidasu: no TileMapLayer with a TileSet to build from.")
		return ArrayMesh.new()
	tile_px = valid[0].tile_set.tile_size.x
	_collect_sources(valid)
	_compute_rect(valid)
	_w = map_cells.x * tile_px
	_h = map_cells.y * tile_px
	var n := _w * _h
	_height = PackedFloat32Array()
	_height.resize(n)
	_layer = PackedInt32Array()
	_layer.resize(n)
	_layer.fill(-1)
	_rx = PackedInt32Array()
	_rx.resize(n)
	_ry = PackedInt32Array()
	_ry.resize(n)
	_flip = PackedByteArray()
	_flip.resize(n)
	_src = PackedInt32Array()
	_src.resize(n)
	_kind = PackedByteArray()
	_kind.resize(n)
	_wl = PackedFloat32Array()
	_wl.resize(n)
	_flat = PackedFloat32Array()
	_flat.resize(n)
	_surfaces.clear()
	flat_top = FLAT_EPS * (valid.size() + 1)
	bounds = AABB(Vector3(0, -_rules.base_thickness, 0), Vector3(map_cells.x, _rules.base_thickness, map_cells.y))

	var parts := []
	for li in valid.size():
		parts.append(_rasterize_layer(valid[li], li))
		if li == 0:
			_ground = _height.duplicate()
	_emit_top_faces()
	_emit_side_faces()
	for li in parts.size():
		_emit_buildings(parts[li].buildings, li)
		_emit_trees(parts[li].trees, li)
		_emit_props(parts[li].props, li)
	_emit_blooms()
	_emit_tufts()
	_compute_ao()
	return _make_mesh()


## Ground height (after the bottom layer) at a flat position in tiles.
func ground_height(x: float, z: float) -> float:
	var px := clampi(int(x * tile_px), 0, _w - 1)
	var pz := clampi(int(z * tile_px), 0, _h - 1)
	if _ground.is_empty():
		return 0.0
	return _ground[pz * _w + px]


# --- input ---------------------------------------------------------------

func _collect_sources(layers: Array[TileMapLayer]) -> void:
	_sources.clear()
	_images.clear()
	_tile_cache.clear()
	for l in layers:
		var ts := l.tile_set
		for i in ts.get_source_count():
			var sid := ts.get_source_id(i)
			var s := ts.get_source(sid)
			if s is TileSetAtlasSource and not _sources.has(sid) and s.texture != null:
				_sources[sid] = s
				var img: Image = s.texture.get_image()
				if img.is_compressed():
					img.decompress()
				_images[sid] = img


func _compute_rect(layers: Array[TileMapLayer]) -> void:
	var r := Rect2i()
	var first := true
	for l in layers:
		var u := l.get_used_rect()
		if u.size == Vector2i.ZERO:
			continue
		r = u if first else r.merge(u)
		first = false
	map_origin = r.position
	map_cells = r.size


func _tile_pixels(src: int, atlas: Vector2i) -> Array:
	var key := Vector3i(src, atlas.x, atlas.y)
	if _tile_cache.has(key):
		return _tile_cache[key]
	var s: TileSetAtlasSource = _sources[src]
	var region := s.get_tile_texture_region(atlas)
	var img: Image = _images[src]
	var alpha := PackedByteArray()
	var luma := PackedFloat32Array()
	var cols := PackedColorArray()
	alpha.resize(tile_px * tile_px)
	luma.resize(tile_px * tile_px)
	cols.resize(tile_px * tile_px)
	for y in tile_px:
		for x in tile_px:
			var c := img.get_pixel(region.position.x + x, region.position.y + y)
			alpha[y * tile_px + x] = 1 if c.a >= 0.5 else 0
			luma[y * tile_px + x] = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			cols[y * tile_px + x] = c
	var entry := [alpha, luma, region.position, cols]
	_tile_cache[key] = entry
	return entry


## Which pixels of a tile sink (source-local), or an empty array if none do.
func _sink_mask(rule: TobidasuRule, src: int, atlas: Vector2i) -> PackedByteArray:
	var auto_water := rule.mode == TobidasuRule.Mode.WATER and rule.sink_colors.is_empty()
	if rule.sink_colors.is_empty() and not auto_water:
		return PackedByteArray()
	var key := [rule.get_instance_id(), src, atlas]
	if _sink_cache.has(key):
		return _sink_cache[key]
	var cols: PackedColorArray = _tile_pixels(src, atlas)[3]
	var m := PackedByteArray()
	m.resize(cols.size())
	var tol2 := rule.sink_tolerance * rule.sink_tolerance
	for t in cols.size():
		var c := cols[t]
		if c.a < 0.5:
			continue
		if auto_water:
			m[t] = 1 if (c.b > c.r + 0.15 and c.b > 0.45) else 0
			continue
		for s in rule.sink_colors:
			var dr := c.r - s.r
			var dg := c.g - s.g
			var db := c.b - s.b
			if dr * dr + dg * dg + db * db <= tol2:
				m[t] = 1
				break
	# Small highlights inside a sunk area (sparkles on water, pebbles in a
	# road) sink with it: pixels with 3+ sunk neighbours join.
	var fill := PackedInt32Array()
	for y in tile_px:
		for x in tile_px:
			var t := y * tile_px + x
			if m[t] == 1 or cols[t].a < 0.5:
				continue
			var k := 0
			k += 1 if x == 0 or m[t - 1] == 1 else 0
			k += 1 if x == tile_px - 1 or m[t + 1] == 1 else 0
			k += 1 if y == 0 or m[t - tile_px] == 1 else 0
			k += 1 if y == tile_px - 1 or m[t + tile_px] == 1 else 0
			if k >= 3:
				fill.append(t)
	for t in fill:
		m[t] = 1
	_sink_cache[key] = m
	return m


## Tile transform of a placed cell: bit 1 = flip h, 2 = flip v, 4 = transpose.
func _cell_flip(src: int, atlas: Vector2i, alt_raw: int) -> Array:
	var flip := 0
	if alt_raw & TileSetAtlasSource.TRANSFORM_FLIP_H:
		flip ^= 1
	if alt_raw & TileSetAtlasSource.TRANSFORM_FLIP_V:
		flip ^= 2
	if alt_raw & TileSetAtlasSource.TRANSFORM_TRANSPOSE:
		flip ^= 4
	var alt := alt_raw & ~(TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE)
	var s: TileSetAtlasSource = _sources[src]
	if s.has_tile(atlas) and s.has_alternative_tile(atlas, alt):
		var td := s.get_tile_data(atlas, alt)
		if td.flip_h:
			flip ^= 1
		if td.flip_v:
			flip ^= 2
		if td.transpose:
			flip ^= 4
	return [flip, alt]


## Destination pixel inside a placed tile -> pixel of the source tile.
func _src_local(flip: int, lx: int, ly: int) -> Vector2i:
	var x := lx
	var y := ly
	if flip & 1:
		x = tile_px - 1 - x
	if flip & 2:
		y = tile_px - 1 - y
	if flip & 4:
		return Vector2i(y, x)
	return Vector2i(x, y)


## Continuous corner inside a placed tile -> atlas pixel coordinate.
func _corner_uv(rx: int, ry: int, flip: int, cx: float, cy: float) -> Vector2:
	var x := cx
	var y := cy
	if flip & 1:
		x = tile_px - x
	if flip & 2:
		y = tile_px - y
	if flip & 4:
		return Vector2(rx + y, ry + x)
	return Vector2(rx + x, ry + y)


## Direction on the map -> direction in the atlas, encoded for COLOR.g.
func _dir_code(flip: int, d: Vector2i) -> float:
	if flip & 1:
		d.x = -d.x
	if flip & 2:
		d.y = -d.y
	if flip & 4:
		d = Vector2i(d.y, d.x)
	if d.x > 0:
		return 0.25
	if d.x < 0:
		return 0.5
	return 0.75 if d.y > 0 else 1.0


# --- heightfield ---------------------------------------------------------

## Rasterizes the heightfield tiles of a layer; returns the cells that become
## models instead: { buildings, trees, props } (Vector2i -> [rule, src, atlas, flip]).
func _rasterize_layer(layer: TileMapLayer, li: int) -> Dictionary:
	var building_cells := {}
	var tree_cells := {}
	var prop_cells := {}
	var n := _w * _h
	var cov := PackedByteArray()     # 1 = this layer has an opaque pixel here
	cov.resize(n)
	var rid := PackedInt32Array()    # rule index into `rl`
	rid.resize(n)
	var lum := PackedFloat32Array()
	lum.resize(n)
	var below := PackedFloat32Array()
	below.resize(n)
	var dark := PackedByteArray()
	dark.resize(n)
	var sink := PackedByteArray()
	sink.resize(n)
	var rl: Array[TobidasuRule] = []
	var rule_index := {}
	var any_sink := false

	for cell in layer.get_used_cells():
		var src := layer.get_cell_source_id(cell)
		if not _sources.has(src):
			continue
		var atlas := layer.get_cell_atlas_coords(cell)
		var fa := _cell_flip(src, atlas, layer.get_cell_alternative_tile(cell))
		var flip: int = fa[0]
		var rule := _rules.find_rule_for_tile(layer.tile_set, src, atlas, fa[1], li)
		var c := cell - map_origin
		if rule.mode in [TobidasuRule.Mode.ROOF, TobidasuRule.Mode.WALL, TobidasuRule.Mode.TREE, TobidasuRule.Mode.PROP]:
			_covered_cells[c] = true
		match rule.mode:
			TobidasuRule.Mode.SKIP:
				continue
			TobidasuRule.Mode.ROOF, TobidasuRule.Mode.WALL:
				building_cells[c] = [rule, src, atlas, flip]
				continue
			TobidasuRule.Mode.TREE:
				tree_cells[c] = [rule, src, atlas, flip]
				continue
			TobidasuRule.Mode.PROP:
				prop_cells[c] = [rule, src, atlas, flip]
				continue
		if not rule_index.has(rule):
			rule_index[rule] = rl.size()
			rl.append(rule)
		var ri: int = rule_index[rule]
		var tp := _tile_pixels(src, atlas)
		var alpha: PackedByteArray = tp[0]
		var luma: PackedFloat32Array = tp[1]
		var region_pos: Vector2i = tp[2]
		var sm := _sink_mask(rule, src, atlas)
		var has_sink := not sm.is_empty()
		any_sink = any_sink or has_sink
		var bm := _bloom_mask(rule, src, atlas)
		var has_bloom := not bm.is_empty()
		var tm := _color_mask(rule, rule.tuft_colors, src, atlas, 0)
		var has_tuft := not tm.is_empty()
		_tuft_cells.erase(c)
		if rule.tuft_extra > 0.0 and not rule.tuft_colors.is_empty():
			_tuft_cells[c] = [src, rule, li, _corner_uv(region_pos.x, region_pos.y, flip, tile_px / 2.0, tile_px / 2.0)]
		for ly in tile_px:
			var row := (c.y * tile_px + ly) * _w + c.x * tile_px
			for lx in tile_px:
				var sp := _src_local(flip, lx, ly)
				var t := sp.y * tile_px + sp.x
				if alpha[t] == 0:
					continue
				var i := row + lx
				below[i] = _height[i] if (rule.stack_on_below and _layer[i] >= 0) else 0.0
				cov[i] = 1
				rid[i] = ri
				lum[i] = luma[t]
				_bloom.erase(i)
				_tuft.erase(i)
				if has_tuft and tm[t] == 1:
					_tuft[i] = [src, region_pos, flip, c, lx, ly, li, rule]
				if has_bloom and bm[t] == 1.0:
					# Flower heads lift off in 3D; the ground under them keeps grass height.
					_bloom[i] = [src, region_pos, flip, c, lx, ly, li, rule]
					lum[i] = bm[tile_px * tile_px]
					_mask_set(src, region_pos + sp, 1)
				dark[i] = 1 if luma[t] < rule.outline_luma else 0
				sink[i] = sm[t] if has_sink else 0
				_layer[i] = li
				_rx[i] = region_pos.x
				_ry[i] = region_pos.y
				_flip[i] = flip
				_src[i] = src
				_kind[i] = 0

	# Outline pixels: dark pixels on the border of a BLOCK / DOME shape.
	var outline := PackedByteArray()
	outline.resize(n)
	for y in _h:
		for x in _w:
			var i := y * _w + x
			if cov[i] == 0 or dark[i] == 0:
				continue
			var r := rl[rid[i]]
			if not r.lower_outline or not (r.mode == TobidasuRule.Mode.BLOCK or r.mode == TobidasuRule.Mode.DOME):
				continue
			if _touches_outside(cov, x, y):
				outline[i] = 1

	# Distance (in pixels) from a sunk pixel to the nearest ground pixel, for bevels.
	var sd := PackedByteArray()
	if any_sink:
		sd.resize(n)
		for i in n:
			if sink[i] == 1:
				sd[i] = 255
		var ring := 1
		var changed := true
		while changed and ring <= 3:
			changed = false
			for y in _h:
				for x in _w:
					var i := y * _w + x
					if sd[i] != 255:
						continue
					if _near_level(cov, sink, sd, x, y, ring):
						sd[i] = ring
						changed = true
			ring += 1

	var has_dome := false
	for i in n:
		if cov[i] == 0:
			continue
		var r := rl[rid[i]]
		var base := below[i] + r.base_offset
		var hh := base
		match r.mode:
			TobidasuRule.Mode.BLOCK:
				hh += minf(r.outline_height, r.height) if outline[i] == 1 else r.height
			TobidasuRule.Mode.LUMA, TobidasuRule.Mode.WATER:
				hh += r.height * lum[i]
			TobidasuRule.Mode.DOME:
				hh += minf(r.outline_height, r.height) if outline[i] == 1 else 0.0
				has_dome = has_dome or outline[i] == 0
		if any_sink and sink[i] == 1:
			var depth := r.water_depth if r.mode == TobidasuRule.Mode.WATER else r.sink_depth
			var bevel := 0 if r.mode == TobidasuRule.Mode.WATER else r.sink_bevel
			var k := 1.0 if sd[i] == 255 else clampf(float(sd[i]) / float(bevel + 1), 0.0, 1.0)
			hh = base + depth * k
			if r.mode == TobidasuRule.Mode.WATER:
				_kind[i] = PX_WATER
				_wl[i] = base + r.water_level
		if r.cliff and _kind[i] == 0:
			_kind[i] = PX_CLIFF
		_height[i] = hh
	if has_dome:
		_apply_domes(cov, rid, rl, outline, below)
	return {"buildings": building_cells, "trees": tree_cells, "props": prop_cells}


func _touches_outside(cov: PackedByteArray, x: int, y: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
				return true
			if cov[ny * _w + nx] == 0:
				return true
	return false


## A sunk pixel is `ring` steps from ground if a neighbour is ground (ring 1)
## or a neighbour sits at ring - 1.
func _near_level(cov: PackedByteArray, sink: PackedByteArray, sd: PackedByteArray, x: int, y: int, ring: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
				continue
			var j := ny * _w + nx
			if ring == 1:
				if cov[j] == 1 and sink[j] == 0:
					return true
			elif sd[j] == ring - 1:
				return true
	return false


func _apply_domes(cov: PackedByteArray, rid: PackedInt32Array, rl: Array[TobidasuRule], outline: PackedByteArray, below: PackedFloat32Array) -> void:
	# Group id per dome pixel; pixels of other groups count as outside so
	# neighbouring shapes stay apart unless they share a group.
	var groups := {}
	var rule_group := PackedInt32Array()
	rule_group.resize(rl.size())
	for k in rl.size():
		var g := rl[k].group_key()
		if not groups.has(g):
			groups[g] = groups.size() + 1
		rule_group[k] = groups[g]
	var n := _w * _h
	var gid := PackedInt32Array()
	gid.resize(n)
	for i in n:
		if cov[i] == 1 and outline[i] == 0 and rl[rid[i]].mode == TobidasuRule.Mode.DOME:
			gid[i] = rule_group[rid[i]]
	# Two-pass chamfer distance (in pixels) from each dome pixel to the outside.
	var big := 1e9
	var d := PackedFloat32Array()
	d.resize(n)
	for i in n:
		d[i] = big if gid[i] != 0 else 0.0
	var diag := 1.41421
	for y in _h:
		for x in _w:
			var i := y * _w + x
			var g := gid[i]
			if g == 0:
				continue
			var v := d[i]
			v = minf(v, _dn(d, gid, g, x - 1, y) + 1.0)
			v = minf(v, _dn(d, gid, g, x, y - 1) + 1.0)
			v = minf(v, _dn(d, gid, g, x - 1, y - 1) + diag)
			v = minf(v, _dn(d, gid, g, x + 1, y - 1) + diag)
			d[i] = v
	for y in range(_h - 1, -1, -1):
		for x in range(_w - 1, -1, -1):
			var i := y * _w + x
			var g := gid[i]
			if g == 0:
				continue
			var v := d[i]
			v = minf(v, _dn(d, gid, g, x + 1, y) + 1.0)
			v = minf(v, _dn(d, gid, g, x, y + 1) + 1.0)
			v = minf(v, _dn(d, gid, g, x + 1, y + 1) + diag)
			v = minf(v, _dn(d, gid, g, x - 1, y + 1) + diag)
			d[i] = v
	for i in n:
		if gid[i] == 0:
			continue
		var r := rl[rid[i]]
		var x := clampf(d[i] / maxf(r.dome_radius, 0.5), 0.0, 1.0)
		var shape := pow(x, r.dome_exponent)
		_height[i] = below[i] + r.base_offset + r.height * shape


## Distance of a neighbour for the chamfer pass; 0 if it is outside the group.
func _dn(d: PackedFloat32Array, gid: PackedInt32Array, g: int, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return 0.0
	var j := y * _w + x
	return d[j] if gid[j] == g else 0.0


func _px_index(x: int, y: int) -> int:
	return y * _w + x


# --- animation delay ------------------------------------------------------

## 0..1 start delay for a world position (x, z in tiles). Continuous in space so
## neighbouring faces always stay glued together while animating.
func delay_at(x: float, z: float) -> float:
	var cx := map_cells.x * 0.5
	var cz := map_cells.y * 0.5
	var dist := Vector2(x - cx, (z - cz) * 1.3).length()
	var maxd := Vector2(cx, cz * 1.3).length()
	var wobble := 0.5 + 0.25 * sin(x * 0.9 + z * 0.4) + 0.25 * sin(z * 1.1 - x * 0.3)
	return clampf(dist / maxd * 0.8 + wobble * 0.2, 0.0, 1.0)


# --- emission ---------------------------------------------------------------

func _surface(key: String, src := -1) -> _Surface:
	if not _surfaces.has(key):
		var s := _Surface.new()
		if src >= 0:
			s.src = src
			s.texture = (_sources[src] as TileSetAtlasSource).texture
			var a := _sources[src] as TileSetAtlasSource
			s.grid = Vector4(a.margins.x, a.margins.y, a.texture_region_size.x + a.separation.x, a.texture_region_size.y + a.separation.y)
		else:
			s.kind = key
		_surfaces[key] = s
	return _surfaces[key]


## Adds a quad. `flat` and `p3` are 4 corners in order around the quad.
## `delay` may be null (computed from 3D positions) or a single float.
## `kind` is one of KIND_*; `ca` goes to COLOR.a, `c1w` to CUSTOM1.w (unless
## this is a side face, which stores its depth there).
func _quad(src: int, flat: Array, p3: Array, uv: Array, n: Vector3, flag := 0.0, delay = null, side_dir := 0.0, kind := 0, ca := 1.0, c1w := 0.0, surface_key := "") -> void:
	var s := _surface(surface_key if surface_key != "" else "src_%d" % src, src if surface_key == "" else -1)
	var base := s.verts.size()
	if n == Vector3.ZERO:
		n = (p3[2] - p3[0]).cross(p3[1] - p3[0])
		if n.length_squared() < 1e-12:
			n = (p3[3] - p3[0]).cross(p3[2] - p3[0])
		n = n.normalized()
		if n.y < 0.0:
			n = -n
	var tex_size := Vector2(s.texture.get_size()) if s.texture != null else Vector2.ONE
	var kb := kind / 8.0
	# Pull every UV a hair toward the face's centre, so no vertex sits exactly on
	# an atlas tile edge: the shader finds the face's tile from any one vertex
	# (which one differs between renderers) and clamps samples into it.
	var uc: Vector2 = ((uv[0] as Vector2) + uv[1] + uv[2] + uv[3]) * 0.25
	var uvs := []
	for k in 4:
		var d: Vector2 = uc - (uv[k] as Vector2)
		uvs.append((uv[k] as Vector2) + d.limit_length(UV_INSET))
	uv = uvs
	for k in 4:
		var f: Vector3 = flat[k]
		var p: Vector3 = p3[k]
		s.verts.append(f)
		s.normals.append(Vector3.UP)
		s.uvs.append((uv[k] as Vector2) / tex_size)
		s.colors.append(Color(flag, side_dir, kb, ca))
		var dl: float = delay if delay != null else delay_at(p.x, p.z)
		s.custom0.append_array([p.x, p.y + _y3d, p.z, dl])
		var w := ((p3[0] as Vector3).y - p.y) if side_dir > 0.0 else c1w
		if kind == KIND_HINGE:
			w = _y3d   # height of the hinge line
		s.custom1.append_array([n.x, n.y, n.z, w])
		s.custom2.append_array([_wind.x, _wind.y, _wind.z, _wind.w])
		bounds = bounds.expand((p + Vector3(0, _y3d, 0)) * Vector3(1, 1.5, 1))
	# Godot treats clockwise triangles as front-facing.
	var a: Vector3 = p3[0]
	var b: Vector3 = p3[1]
	var c: Vector3 = p3[2]
	var d: Vector3 = p3[3]
	var face := (c - a).cross(b - a)
	if face.length_squared() < 1e-12:
		face = (d - a).cross(c - a)
	if face.length_squared() < 1e-12:
		# collapsed in 3D (a sunk tile of a moving part): wind by the flat face
		var fa: Vector3 = flat[0]
		face = ((flat[2] as Vector3) - fa).cross((flat[1] as Vector3) - fa)
	if face.dot(n) > 0.0:
		s.indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	else:
		s.indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


func _emit_top_faces() -> void:
	var t := tile_px
	var visited := PackedByteArray()
	visited.resize(t * t)
	var water_visited := PackedByteArray()
	water_visited.resize(t * t)
	for cy in map_cells.y:
		for cx in map_cells.x:
			visited.fill(0)
			water_visited.fill(0)
			for ly in t:
				for lx in t:
					var i := _px_index(cx * t + lx, cy * t + ly)
					var lay := _layer[i]
					if lay < 0:
						continue
					if visited[ly * t + lx] == 0:
						var hh := _height[i]
						var kd := _kind[i] & PX_WATER
						var rect := _grow_rect(visited, lx, ly, i, func(j: int) -> bool:
							return _layer[j] == lay and (_kind[j] & PX_WATER) == kd and absf(_height[j] - hh) < 1e-5)
						_emit_top(i, cx, cy, lx, ly, rect, hh, lay, KIND_WATER if kd != 0 else KIND_NORMAL)
					if (_kind[i] & PX_WATER) != 0 and water_visited[ly * t + lx] == 0:
						var wl := _wl[i]
						var wrect := _grow_rect(water_visited, lx, ly, i, func(j: int) -> bool:
							return (_kind[j] & PX_WATER) != 0 and absf(_wl[j] - wl) < 1e-5)
						_emit_water(cx, cy, lx, ly, wrect, wl, lay)


## Greedy rectangle (inside one tile) starting at (lx, ly) of pixels accepted by `ok`.
func _grow_rect(visited: PackedByteArray, lx: int, ly: int, i: int, ok: Callable) -> Vector2i:
	var t := tile_px
	var w := 1
	while lx + w < t and visited[ly * t + lx + w] == 0 and ok.call(i + w):
		w += 1
	var rows := 1
	var grow := true
	while grow and ly + rows < t:
		for k in w:
			if visited[(ly + rows) * t + lx + k] == 1 or not ok.call(i + rows * _w + k):
				grow = false
				break
		if grow:
			rows += 1
	for yy in rows:
		for xx in w:
			visited[(ly + yy) * t + lx + xx] = 1
	return Vector2i(w, rows)


func _emit_top(i: int, cx: int, cy: int, lx: int, ly: int, rect: Vector2i, hh: float, lay: int, kind: int) -> void:
	var t := tile_px
	# Faces overlap their neighbours by a hair so T-junctions between merged
	# rectangles never open into see-through cracks.
	var x0 := float(cx * t + lx) / t - SEAM_OVERLAP
	var z0 := float(cy * t + ly) / t - SEAM_OVERLAP
	var x1 := float(cx * t + lx + rect.x) / t + SEAM_OVERLAP
	var z1 := float(cy * t + ly + rect.y) / t + SEAM_OVERLAP
	var fy := FLAT_EPS * lay
	var rx := _rx[i]
	var ry := _ry[i]
	var fl := _flip[i]
	var e := UV_INSET
	_quad(_src[i],
		[Vector3(x0, fy, z0), Vector3(x1, fy, z0), Vector3(x1, fy, z1), Vector3(x0, fy, z1)],
		[Vector3(x0, hh, z0), Vector3(x1, hh, z0), Vector3(x1, hh, z1), Vector3(x0, hh, z1)],
		[_corner_uv(rx, ry, fl, lx + e, ly + e), _corner_uv(rx, ry, fl, lx + rect.x - e, ly + e),
			_corner_uv(rx, ry, fl, lx + rect.x - e, ly + rect.y - e), _corner_uv(rx, ry, fl, lx + e, ly + rect.y - e)],
		Vector3.UP, 0.0, null, 0.0, kind)


func _emit_water(cx: int, cy: int, lx: int, ly: int, rect: Vector2i, wl: float, lay: int) -> void:
	var t := tile_px
	var x0 := float(cx * t + lx) / t
	var z0 := float(cy * t + ly) / t
	var x1 := x0 + float(rect.x) / t
	var z1 := z0 + float(rect.y) / t
	var fy := FLAT_EPS * (lay + 0.5)
	_quad(-1,
		[Vector3(x0, fy, z0), Vector3(x1, fy, z0), Vector3(x1, fy, z1), Vector3(x0, fy, z1)],
		[Vector3(x0, wl, z0), Vector3(x1, wl, z0), Vector3(x1, wl, z1), Vector3(x0, wl, z1)],
		[Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)],
		Vector3.UP, 0.0, null, 0.0, KIND_WATER, 1.0, 0.0, "water")


func _px_height(x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return -_rules.base_thickness
	var i := _px_index(x, y)
	return _height[i] if _layer[i] >= 0 else -_rules.base_thickness


func _px_inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < _w and y < _h and _layer[_px_index(x, y)] >= 0


func _wall_kind(hi: int, lo_inside: bool, drop: float) -> int:
	# On the map edge the cliff part is what rises above the ground (soil below).
	var rise := drop if lo_inside else _height[hi]
	var cliff := (_kind[hi] & PX_CLIFF) != 0 and rise >= CLIFF_MIN_DROP
	if not lo_inside:
		return KIND_SOIL_CLIFF if cliff else KIND_SOIL
	if cliff:
		return KIND_CLIFF
	return KIND_NORMAL


func _emit_side_faces() -> void:
	# Walls on vertical pixel boundaries (normal +-X), runs along Z.
	for b in _w + 1:
		var run_start := -1
		var run_key := []
		for y in _h + 1:
			var key := []
			if y < _h:
				var hl := _px_height(b - 1, y)
				var hr := _px_height(b, y)
				if absf(hl - hr) > 1e-5:
					var left_high := hl > hr
					var hx := b - 1 if left_high else b
					var hi := _px_index(hx, y)
					var lo_inside := _px_inside(b if left_high else b - 1, y)
					key = [maxf(hl, hr), minf(hl, hr), left_high, _layer[hi], int(hx / tile_px), int(y / tile_px),
						_wall_kind(hi, lo_inside, absf(hl - hr))]
			if run_start >= 0 and key != run_key:
				_emit_x_wall(b, run_start, y, run_key)
				run_start = -1
			if run_start < 0 and not key.is_empty():
				run_start = y
				run_key = key
	# Walls on horizontal pixel boundaries (normal +-Z), runs along X.
	for b in _h + 1:
		var run_start := -1
		var run_key := []
		for x in _w + 1:
			var key := []
			if x < _w:
				var hu := _px_height(x, b - 1)
				var hd := _px_height(x, b)
				if absf(hu - hd) > 1e-5:
					var up_high := hu > hd
					var hy := b - 1 if up_high else b
					var hi := _px_index(x, hy)
					var lo_inside := _px_inside(x, b if up_high else b - 1)
					key = [maxf(hu, hd), minf(hu, hd), up_high, _layer[hi], int(x / tile_px), int(hy / tile_px),
						_wall_kind(hi, lo_inside, absf(hu - hd))]
			if run_start >= 0 and key != run_key:
				_emit_z_wall(b, run_start, x, run_key)
				run_start = -1
			if run_start < 0 and not key.is_empty():
				run_start = x
				run_key = key


func _emit_x_wall(b: int, y0: int, y1: int, key: Array) -> void:
	var t := float(tile_px)
	var hi_h: float = key[0]
	var lo_h: float = key[1]
	var left_high: bool = key[2]
	var hx := b - 1 if left_high else b
	var i := _px_index(hx, y0)
	var x := b / t
	var za := y0 / t
	var zb := y1 / t
	var fy := FLAT_EPS * _layer[i]
	var cell := Vector2i(hx / tile_px, y0 / tile_px)
	var lx := hx - cell.x * tile_px + 0.5
	var ly0 := y0 - cell.y * tile_px
	var ly1 := y1 - cell.y * tile_px
	var fl := _flip[i]
	var uva := _corner_uv(_rx[i], _ry[i], fl, lx, ly0 + UV_INSET)
	var uvb := _corner_uv(_rx[i], _ry[i], fl, lx, ly1 - UV_INSET)
	var n := Vector3(1, 0, 0) if left_high else Vector3(-1, 0, 0)
	_quad(_src[i],
		[Vector3(x, fy, za), Vector3(x, fy, zb), Vector3(x, fy, zb), Vector3(x, fy, za)],
		[Vector3(x, hi_h, za), Vector3(x, hi_h, zb), Vector3(x, lo_h, zb), Vector3(x, lo_h, za)],
		[uva, uvb, uvb, uva],
		n, 0.0, null, _dir_code(fl, Vector2i(-1, 0) if left_high else Vector2i(1, 0)), key[6])


func _emit_z_wall(b: int, x0: int, x1: int, key: Array) -> void:
	var t := float(tile_px)
	var hi_h: float = key[0]
	var lo_h: float = key[1]
	var up_high: bool = key[2]
	var hy := b - 1 if up_high else b
	var i := _px_index(x0, hy)
	var z := b / t
	var xa := x0 / t
	var xb := x1 / t
	var fy := FLAT_EPS * _layer[i]
	var cell := Vector2i(x0 / tile_px, hy / tile_px)
	var ly := hy - cell.y * tile_px + 0.5
	var lx0 := x0 - cell.x * tile_px
	var lx1 := x1 - cell.x * tile_px
	var fl := _flip[i]
	var uva := _corner_uv(_rx[i], _ry[i], fl, lx0 + UV_INSET, ly)
	var uvb := _corner_uv(_rx[i], _ry[i], fl, lx1 - UV_INSET, ly)
	var n := Vector3(0, 0, 1) if up_high else Vector3(0, 0, -1)
	_quad(_src[i],
		[Vector3(xa, fy, z), Vector3(xb, fy, z), Vector3(xb, fy, z), Vector3(xa, fy, z)],
		[Vector3(xa, hi_h, z), Vector3(xb, hi_h, z), Vector3(xb, lo_h, z), Vector3(xa, lo_h, z)],
		[uva, uvb, uvb, uva],
		n, 0.0, null, _dir_code(fl, Vector2i(0, -1) if up_high else Vector2i(0, 1)), key[6])


# --- buildings ----------------------------------------------------------------

func _emit_buildings(cells: Dictionary, li: int) -> void:
	var seen := {}
	for start in cells:
		if seen.has(start):
			continue
		var comp: Array[Vector2i] = []
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for dlt in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = c + dlt
				if cells.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		_emit_building(comp, cells, li)


func _emit_building(comp: Array[Vector2i], cells: Dictionary, li: int) -> void:
	var lo := comp[0]
	var hi := comp[0]
	for c in comp:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var cx0 := lo.x
	var cy0 := lo.y
	var cx1 := hi.x + 1
	var cy1 := hi.y + 1
	var wall_top := cy1
	var wall_rule: TobidasuRule = null
	var roof_rule: TobidasuRule = null
	for c in comp:
		var r: TobidasuRule = cells[c][0]
		if r.mode == TobidasuRule.Mode.WALL:
			wall_top = mini(wall_top, c.y)
			if wall_rule == null:
				wall_rule = r
		elif roof_rule == null:
			roof_rule = r
	var src: int = cells[comp[0]][1]
	var rw := cy1 - wall_top
	var row_h := wall_rule.height if wall_rule != null else 0.5
	var hw := maxf(rw, 0.5) * row_h if rw > 0 else row_h
	var ridge := roof_rule.height if roof_rule != null else 0.0
	var depth := float(cy1 - cy0)
	var rr := float(wall_top - cy0)
	var center := Vector2((cx0 + cx1) * 0.5, (cy0 + cy1) * 0.5)
	var dl := delay_at(center.x, center.y)
	# The whole building shares one delay, so the ground around it may pop
	# first; its flat pieces wait above the highest ground of the footprint
	# (invisible from straight above, where the 2D view looks from).
	var lift := 0.0
	var low := INF
	for c in comp:
		for py in range(c.y * tile_px, (c.y + 1) * tile_px):
			for px in range(c.x * tile_px, (c.x + 1) * tile_px):
				var j := _px_index(px, py)
				if _layer[j] >= 0:
					lift = maxf(lift, _height[j])
					low = minf(low, _height[j])
	# Standing on a terrace: the walls rise from its top, not from the base.
	_y3d = low if low != INF and low >= BUILDING_RAISE_MIN else 0.0
	buildings.append({"rect": Rect2(cx0, cy0, cx1 - cx0, cy1 - cy0), "wall_height": hw, "ridge": ridge, "base": _y3d})
	var fy_roof := lift + FLAT_EPS * (li + 1.5)
	var fy_wall := lift + FLAT_EPS * (li + 1.0)
	flat_top = maxf(flat_top, fy_roof)
	# Things drawn over the building on a higher layer must lie above it.
	for c in comp:
		for py in range(c.y * tile_px, (c.y + 1) * tile_px):
			for px in range(c.x * tile_px, (c.x + 1) * tile_px):
				var j := _px_index(px, py)
				_flat[j] = maxf(_flat[j], fy_roof)
	var ov := roof_rule.roof_overhang if roof_rule != null else 0.08
	# Ground floor standing back under the floor above (a covered walkway).
	var recess := 0.0
	if rw >= 2:
		for c in comp:
			var r: TobidasuRule = cells[c][0]
			if c.y == cy1 - 1 and r.mode == TobidasuRule.Mode.WALL:
				recess = maxf(recess, r.wall_recess)
		recess = minf(recess, minf(depth - 0.25, 0.95))   # (only the ground floor's side walls are cut)
	var lid_a := rw / 8.0
	# Folding walls: a point at height y on the 3D wall starts this far in front
	# of its hinge on the flat map (the facade top starts at the roof's edge).
	var fold := float(rw) / hw if hw > 0.0 else 1.0
	var t := float(tile_px)

	# Wall tile used for the plain sides: first wall cell of the west / east column.
	var west_tile := _first_wall_tile(cells, comp, cx0, wall_top, cy1)
	var east_tile := _first_wall_tile(cells, comp, cx1 - 1, wall_top, cy1)

	for c in comp:
		var info: Array = cells[c]
		var r: TobidasuRule = info[0]
		var region := (_sources[info[1]] as TileSetAtlasSource).get_tile_texture_region(info[2])
		var u0 := Vector2(region.position)
		var x0 := float(c.x)
		var x1 := float(c.x + 1)
		if r.mode == TobidasuRule.Mode.WALL:
			_mark_windows(r, info[1], info[2])
			# Facade folds up from the ground to the south face.
			var ytop := (cy1 - c.y) * row_h
			var ybot := ytop - row_h
			var z := float(cy1) + 0.001 - (recess if c.y == cy1 - 1 else 0.0)
			# In 3D each facade tile overlaps its neighbours a little, so no hairline
			# crack opens between them (at night lit ground showed through as dots).
			var o3 := FACADE_OVERLAP
			_quad(src,
				[Vector3(x0, fy_wall, c.y), Vector3(x1, fy_wall, c.y), Vector3(x1, fy_wall, c.y + 1), Vector3(x0, fy_wall, c.y + 1)],
				[Vector3(x0 - o3, ytop + o3, z), Vector3(x1 + o3, ytop + o3, z), Vector3(x1 + o3, ybot - o3, z), Vector3(x0 - o3, ybot - o3, z)],
				# UVs inset a hair like every other face: on the tile's very edge the
				# sampler can hit the neighbouring atlas tile, and a transparent texel
				# there counts as a doorway (lit at night: dotted seams).
				[u0 + Vector2(UV_INSET, UV_INSET), u0 + Vector2(t - UV_INSET, UV_INSET),
					u0 + Vector2(t - UV_INSET, t - UV_INSET), u0 + Vector2(UV_INSET, t - UV_INSET)],
				Vector3(0, 0, 1), 1.0, dl, 0.0, KIND_HINGE)
			continue
		if rr <= 0.0:
			continue
		var zm := cy0 + rr * 0.5
		if r.gable and c.y + 1 == wall_top and zm <= c.y + 1e-4:
			_emit_cross_gable(c, u0, r.gable_apex, cy0, rr, depth, hw, ridge, ov, fy_roof, dl, src, lid_a)
			continue
		# Roof cell: split at the ridge so each half is planar.
		var cuts: Array[float] = [float(c.y)]
		if zm > c.y + 1e-4 and zm < c.y + 1 - 1e-4:
			cuts.append(zm)
		cuts.append(float(c.y + 1))
		var ex0 := x0 - (ov if c.x == cx0 else 0.0)
		var ex1 := x1 + (ov if c.x == cx1 - 1 else 0.0)
		for k in cuts.size() - 1:
			var za: float = cuts[k]
			var zb: float = cuts[k + 1]
			var pa := _roof_point(za, cy0, rr, depth, hw, ridge, ov)
			var pb := _roof_point(zb, cy0, rr, depth, hw, ridge, ov)
			var va := (za - c.y) * t
			var vb := (zb - c.y) * t
			_quad(src,
				[Vector3(x0, fy_roof, za), Vector3(x1, fy_roof, za), Vector3(x1, fy_roof, zb), Vector3(x0, fy_roof, zb)],
				[Vector3(ex0, pa.y, pa.x), Vector3(ex1, pa.y, pa.x), Vector3(ex1, pb.y, pb.x), Vector3(ex0, pb.y, pb.x)],
				[u0 + Vector2(0, va), u0 + Vector2(t, va), u0 + Vector2(t, vb), u0 + Vector2(0, vb)],
				Vector3.ZERO, 0.0, dl, 0.0, KIND_LID, lid_a, hw)

	# Plain side walls (west, east) and gable ends fold up with the facade:
	# they lie edge-on in the flat map, so they are invisible in 2D.
	for side in [0, 1]:
		var x := float(cx0) if side == 0 else float(cx1)
		var tile: Vector2 = west_tile if side == 0 else east_tile
		var n := Vector3(-1, 0, 0) if side == 0 else Vector3(1, 0, 0)
		for cy in range(cy0, cy1):
			# (the ground floor's walkway leaves the lower front corner open)
			var parts := [[float(cy), float(cy + 1), 0.0, hw]]
			if recess > 0.0 and cy == cy1 - 1:
				parts = [[float(cy), float(cy + 1), row_h, hw], [float(cy), float(cy1) - recess, 0.0, row_h]]
			for pt in parts:
				var za: float = pt[0]
				var zb: float = pt[1]
				var y0: float = pt[2]
				var y1: float = pt[3]
				if zb - za < 1e-3:
					continue
				var ua := (za - cy0) / depth
				var ub := (zb - cy0) / depth
				var va := 15.0 - 12.0 * y1 / hw
				var vb := 15.0 - 12.0 * y0 / hw
				var p3 := [Vector3(x, y1, za), Vector3(x, y1, zb), Vector3(x, y0, zb), Vector3(x, y0, za)]
				_quad(src, _folded(p3, fy_wall, fold), p3,
					[tile + Vector2(2 + ua * 12, va), tile + Vector2(2 + ub * 12, va), tile + Vector2(2 + ub * 12, vb), tile + Vector2(2 + ua * 12, vb)],
					n, 0.0, dl, 0.0, KIND_HINGE)
		if ridge > 0.0 and rr > 0.0:
			var plain := tile + Vector2(8.5, 6.5)
			# (the roof's ridge over the wall line sits lower by the eaves' drop)
			var top := Vector3(x, hw + ridge - _eave_drop(ridge, ov, depth) - 0.004, cy0 + depth * 0.5)
			var p3 := [Vector3(x, hw, cy0), top, top, Vector3(x, hw, cy1)]
			_quad(src, _folded(p3, fy_wall, fold), p3,
				[plain, plain, plain, plain],
				n, 0.0, dl, 0.0, KIND_HINGE)
	# Back wall: hidden under the roof, rides along with it. One plain texel of
	# the end wall (a lit window or doorway here would shine through the seams
	# of the facade at night).
	var back := west_tile + Vector2(8.5, 6.5)
	for cx in range(cx0, cx1):
		_quad(src,
			[Vector3(cx, fy_wall, cy0), Vector3(cx + 1, fy_wall, cy0), Vector3(cx + 1, fy_wall, cy0), Vector3(cx, fy_wall, cy0)],
			[Vector3(cx, hw, cy0), Vector3(cx + 1, hw, cy0), Vector3(cx + 1, 0, cy0), Vector3(cx, 0, cy0)],
			[back, back, back, back],
			Vector3(0, 0, -1), 0.0, dl, 0.0, KIND_LID, lid_a, hw)
	# Soffit: a dark ceiling at the top of the walls under the whole roof, so
	# looking up under the eaves never shows the lit ground behind the building
	# through the roof. Edge-on in the flat map (invisible in 2D).
	if rr > 0.0:
		# The darkest opaque texel of the eave row's bottom line (skipping the
		# "^" gable tiles, which are painted differently).
		var dark := Vector2.ZERO
		var best := INF
		for c in comp:
			if c.y != wall_top - 1 or (cells[c][0] as TobidasuRule).gable:
				continue
			var tp := _tile_pixels(cells[c][1], cells[c][2])
			var rp: Vector2i = tp[2]
			for lx in tile_px:
				var k := (tile_px - 1) * tile_px + lx
				if (tp[0] as PackedByteArray)[k] != 0 and (tp[1] as PackedFloat32Array)[k] < best:
					best = (tp[1] as PackedFloat32Array)[k]
					dark = Vector2(rp) + Vector2(lx + 0.5, tile_px - 0.5)
		# Flat just under the wall tops between the walls, then sloping down
		# under the front and back eaves just beneath the roof (a flat plate at
		# the eaves' lowest point cut through the top of the facade); out under
		# the front and back eaves only (past the gable ends it read as a dark
		# line across them).
		var yw := hw - 0.01
		var ye := hw - _eave_drop(ridge, ov, depth) - 0.01
		var sx0 := cx0 + 0.002
		var sx1 := cx1 - 0.002
		var fl := fy_roof - FLAT_EPS * 0.5
		var strips := [[cy0 - ov, ye, float(cy0), yw], [float(cy0), yw, float(cy1), yw], [float(cy1), yw, cy1 + ov, ye]]
		for n in [Vector3.DOWN, Vector3.UP]:   # both sides: seen from above through gaps, and from below
			for sp in strips:
				if absf(float(sp[2]) - float(sp[0])) < 1e-4:
					continue
				_quad(src,
					[Vector3(cx0, fl, cy0), Vector3(cx1, fl, cy0), Vector3(cx1, fl, cy0), Vector3(cx0, fl, cy0)],
					[Vector3(sx0, sp[1], sp[0]), Vector3(sx1, sp[1], sp[0]), Vector3(sx1, sp[3], sp[2]), Vector3(sx0, sp[3], sp[2])],
					[dark, dark, dark, dark], n, 0.0, dl, 0.0, KIND_LID, lid_a, hw)
		if recess > 0.0:
			# the walkway's ceiling (the underside of the floor above); edge-on in 2D
			var fz := float(cy1 - 1)
			var zr := float(cy1) - recess
			_quad(src,
				[Vector3(cx0, fy_wall, fz), Vector3(cx1, fy_wall, fz), Vector3(cx1, fy_wall, fz), Vector3(cx0, fy_wall, fz)],
				[Vector3(cx0, row_h, zr), Vector3(cx1, row_h, zr), Vector3(cx1, row_h, cy1), Vector3(cx0, row_h, cy1)],
				[dark, dark, dark, dark], Vector3.DOWN, 0.0, dl, 0.0, KIND_HINGE)
	_y3d = 0.0


## Flat positions of a folding wall: each point lies `y * fold` in front of its hinge.
func _folded(p3: Array, fy: float, fold: float) -> Array:
	var out := []
	for p in p3:
		out.append(Vector3(p.x, fy, p.z - p.y * fold))
	return out


## A "^" roof tile: a small gable facing the front, its ridge running back to
## the main ridge. The flat tile is cut into 5 pieces so every pixel lands on
## the face it depicts (main roof, two gable slopes, the triangular gable wall).
func _emit_cross_gable(c: Vector2i, u0: Vector2, apex: float, cy0: int, rr: float, depth: float, hw: float, ridge: float, ov: float, fy: float, dl: float, src: int, lid_a: float) -> void:
	var t := float(tile_px)
	var x0 := float(c.x)
	var x1 := x0 + 1.0
	var xm := x0 + 0.5
	var z0 := float(c.y)
	var z1 := z0 + 1.0
	var pt := _roof_point(z0, cy0, rr, depth, hw, ridge, ov)
	var pe := _roof_point(z1, cy0, rr, depth, hw, ridge, ov)
	# 45 degree gable: its ridge is half a tile above the eave and runs back
	# until it meets the main roof.
	var yc := minf(pt.y, pe.y + 0.5)
	var s := (pt.y - yc) / maxf(pt.y - pe.y, 1e-4)
	var zc := lerpf(pt.x, pe.x, s)
	var TL := Vector3(x0, pt.y, pt.x)
	var TM := Vector3(xm, pt.y, pt.x)
	var TR := Vector3(x1, pt.y, pt.x)
	var CM := Vector3(xm, yc, zc)
	var FL := Vector3(x0, pe.y, pe.x)
	var FR := Vector3(x1, pe.y, pe.x)
	var FM := Vector3(xm, yc, pe.x)
	var zt := z0 + 1.0 / t   # tip of the "^" on the flat tile
	var za := z0 + apex
	var zv := z0 + 0.5
	var pieces := [
		# flat corners, 3D corners, normal
		[[Vector2(x0, z0), Vector2(xm, z0), Vector2(xm, zt), Vector2(x0, zv)], [TL, TM, CM, FL], Vector3.ZERO],
		[[Vector2(xm, zt), Vector2(xm, za), Vector2(x0, z1), Vector2(x0, zv)], [CM, FM, FL, FL], Vector3.ZERO],
		[[Vector2(xm, za), Vector2(x1, z1), Vector2(x0, z1), Vector2(x0, z1)], [FM, FR, FL, FL], Vector3(0, 0, 1)],
		[[Vector2(xm, zt), Vector2(x1, zv), Vector2(x1, z1), Vector2(xm, za)], [CM, FR, FR, FM], Vector3.ZERO],
		[[Vector2(xm, z0), Vector2(x1, z0), Vector2(x1, zv), Vector2(xm, zt)], [TM, TR, FR, CM], Vector3.ZERO],
	]
	for pc in pieces:
		var fl: Array = pc[0]
		var flat := []
		var uv := []
		for f in fl:
			flat.append(Vector3(f.x, fy, f.y))
			uv.append(u0 + Vector2((f.x - x0) * t, (f.y - z0) * t))
		_quad(src, flat, pc[1], uv, pc[2], 0.0, dl, 0.0, KIND_LID, lid_a, hw)


## Roof cross-section: flat z -> (3D z, y).
func _roof_point(z: float, cy0: int, rr: float, depth: float, hw: float, ridge: float, ov: float) -> Vector2:
	var u := (z - cy0) / rr
	var z3 := cy0 - ov + u * (depth + 2.0 * ov)
	var y := hw + ridge * (1.0 - absf(2.0 * u - 1.0)) - _eave_drop(ridge, ov, depth)
	return Vector2(z3, y)


## How far the eaves hang below the wall tops: the roof plane passes a hair
## above the front and back walls (a deeper drop let the top of the facade poke
## through the roof just behind the eaves).
static func _eave_drop(ridge: float, ov: float, depth: float) -> float:
	return maxf(2.0 * ridge * ov / (depth + 2.0 * ov) - 0.006, 0.0)


func _first_wall_tile(cells: Dictionary, comp: Array[Vector2i], cx: int, wall_top: int, cy1: int) -> Vector2:
	for cy in range(wall_top, cy1):
		var c := Vector2i(cx, cy)
		if cells.has(c) and (cells[c][0] as TobidasuRule).mode == TobidasuRule.Mode.WALL:
			var info: Array = cells[c]
			return Vector2((_sources[info[1]] as TileSetAtlasSource).get_tile_texture_region(info[2]).position)
	for c in comp:
		if (cells[c][0] as TobidasuRule).mode == TobidasuRule.Mode.WALL:
			var info: Array = cells[c]
			return Vector2((_sources[info[1]] as TileSetAtlasSource).get_tile_texture_region(info[2]).position)
	var info0: Array = cells[comp[0]]
	return Vector2((_sources[info0[1]] as TileSetAtlasSource).get_tile_texture_region(info0[2]).position)


# --- trees -------------------------------------------------------------------

## TREE tiles are drawn in 3/4 view: rows of the drawing are heights. Each
## shape (4-connected non-outline pixels, so trunk + canopy of one plant) stands
## up from its bottom row and becomes a solid of revolution made of pixel
## voxels: every pixel (x, row) turns into a box whose depth follows the round
## cross-section of its row. Every face is textured by front projection (with
## the pixel it covers when the solid is squashed back onto the drawing) and
## its flat position is that same projection, so at pop = 0 every fragment
## shows exactly its own pixel. The original tile lies underneath (it keeps the
## outline in 2D) and sinks below the ground in 3D.
func _emit_trees(cells: Dictionary, li: int) -> void:
	if cells.is_empty():
		return
	var t := tile_px
	var lo: Vector2i = cells.keys()[0]
	var hi := lo
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var ox := lo.x * t
	var oy := lo.y * t
	var pw := (hi.x - lo.x + 1) * t
	var ph := (hi.y - lo.y + 1) * t
	var n := pw * ph
	var op := PackedByteArray()
	op.resize(n)
	var inner := PackedByteArray()
	inner.resize(n)
	var owner := PackedInt32Array()   # index into `infos` of the cell drawing the pixel
	owner.resize(n)
	var infos := []   # [cell, rule, src, region pos, flip]
	for c in cells:
		var info: Array = cells[c]
		var rule: TobidasuRule = info[0]
		var tp := _tile_pixels(info[1], info[2])
		var alpha: PackedByteArray = tp[0]
		var luma: PackedFloat32Array = tp[1]
		var k := infos.size()
		infos.append([c, rule, info[1], tp[2], info[3]])
		_mark_windows(rule, info[1], info[2])   # e.g. the light window of a stone lantern
		for ly in t:
			for lx in t:
				var sp := _src_local(info[3], lx, ly)
				var tt := sp.y * t + sp.x
				if alpha[tt] == 0:
					continue
				var i: int = (c.y * t + ly - oy) * pw + (c.x * t + lx - ox)
				op[i] = 1
				inner[i] = 1 if (not rule.lower_outline or luma[tt] >= rule.outline_luma) else 0
				owner[i] = k
		_emit_sunk_tile(c, info[1], tp[2], info[3], li, 0.5)

	# Shapes: 4-connected non-outline pixels.
	var lab := PackedInt32Array()
	lab.resize(n)
	lab.fill(-1)
	var shapes: Array[PackedInt32Array] = []
	for i0 in n:
		if inner[i0] == 0 or lab[i0] >= 0:
			continue
		var sid := shapes.size()
		var px := PackedInt32Array()
		var stack: Array[int] = [i0]
		lab[i0] = sid
		while not stack.is_empty():
			var i: int = stack.pop_back()
			px.append(i)
			var x := i % pw
			var y := i / pw
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= pw or ny >= ph:
					continue
				var j := ny * pw + nx
				if inner[j] == 1 and lab[j] < 0:
					lab[j] = sid
					stack.append(j)
		shapes.append(px)

	for sid in shapes.size():
		_emit_tree_shape(shapes[sid], sid, lab, op, owner, infos, pw, ph, ox, oy, li)


func _emit_tree_shape(px: PackedInt32Array, sid: int, lab: PackedInt32Array, op: PackedByteArray, owner: PackedInt32Array, infos: Array, pw: int, ph: int, ox: int, oy: int, li: int) -> void:
	var t := tile_px
	var rows := {}   # row -> Array of x
	var rmin := ph
	var rmax := -1
	for i in px:
		var y := i / pw
		if not rows.has(y):
			rows[y] = []
		rows[y].append(i % pw)
		rmin = mini(rmin, y)
		rmax = maxi(rmax, y)
	var rule: TobidasuRule = infos[owner[px[0]]][1]
	# Ground line: right below the shape, unless its bottom is hidden behind
	# another shape (a plant further front): then assume a short hidden trunk.
	var bottom: Array = rows[rmax]
	var occluded := false
	for x in bottom:
		for k in range(1, 4):
			var y := rmax + k
			if y >= ph:
				break
			var j: int = y * pw + x
			if op[j] == 0:
				break
			if lab[j] >= 0 and lab[j] != sid:
				occluded = true
				break
	var b := rmax + 1
	var bx0: int = bottom[0]
	var bx1: int = bottom[0]
	for x in bottom:
		bx0 = mini(bx0, x)
		bx1 = maxi(bx1, x)
	var axis := (bx0 + bx1 + 1) * 0.5
	if occluded:
		b += rule.tree_hidden_trunk
		# Hidden trunk, 2 pixels wide, only where the drawing is opaque (it
		# projects onto the shape in front, which covers it in 2D).
		for y in range(rmax + 1, mini(b, ph)):
			var xs := []
			for x in [int(axis) - 1, int(axis)]:
				if x >= 0 and x < pw and op[y * pw + x] == 1:
					xs.append(x)
			if not xs.is_empty():
				rows[y] = xs
	# Round cross-section per row (or per layer of rows): centre and radius.
	# Shapes end in an outline; a row that ends in transparency instead is
	# cut off (forest tiles show parts of the trees next to them): it is half
	# of a wider tree centred on the cut. Thin cut-off slivers stay flat
	# (they sink with the tile).
	var span := {}
	var cut := false
	var widest := 0
	for y in rows:
		var xs: Array = rows[y]
		var a: int = xs[0]
		var z: int = xs[0]
		for x in xs:
			a = mini(a, x)
			z = maxi(z, x)
		var left_cut := a == 0 or op[y * pw + a - 1] == 0
		var right_cut := z == pw - 1 or op[y * pw + z + 1] == 0
		widest = maxi(widest, z - a + 1)
		if left_cut != right_cut:
			cut = true
			span[y] = Vector2(a if left_cut else z + 1, z - a + 1)
		else:
			span[y] = Vector2((a + z + 1) * 0.5, (z - a + 1) * 0.5)
	if cut and widest <= 4:
		return
	var layers := maxi(rule.tree_layers, 1)
	if layers > 1:
		var best := {}
		for y in span:
			var L: int = (b - 1 - y) / layers
			if not best.has(L) or (span[y] as Vector2).y > (best[L] as Vector2).y:
				best[L] = span[y]
		for y in span:
			span[y] = best[(b - 1 - y) / layers]
	var zc := b - 1
	# Dome: rows above the widest one get less and less deep toward the top,
	# so a mushroom cap drawn in 3/4 view becomes a rounded cap, not a barrel.
	var widest_row := rmax
	var widest_w := -1.0
	for y in span:
		if (span[y] as Vector2).y > widest_w + 0.01 or ((span[y] as Vector2).y >= widest_w - 0.01 and y > widest_row):
			widest_w = (span[y] as Vector2).y
			widest_row = y
	# Runs: each unbroken run of a row is its own cross-section (centre, half width).
	var run_span := {}
	if rule.tree_runs:
		for y in rows:
			var xs: Array = (rows[y] as Array).duplicate()
			xs.sort()
			var k0 := 0
			for k in xs.size() + 1:
				if k < xs.size() and (k == 0 or int(xs[k]) == int(xs[k - 1]) + 1):
					continue
				var a: int = xs[k0]
				var z: int = xs[k - 1]
				for j in range(k0, k):
					run_span[Vector2i(xs[j], y)] = Vector2((a + z + 1) * 0.5, (z - a + 1) * 0.5)
				k0 = k
	# Frame (hollow) rows: only rows with gaps in them, i.e. lattice; solid rows
	# (a platform, a roof, a beam) stay solid.
	var frame_rows := {}
	if rule.tree_frame:
		for y in rows:
			var xs: Array = (rows[y] as Array).duplicate()
			xs.sort()
			for k in range(1, xs.size()):
				if int(xs[k]) != int(xs[k - 1]) + 1:
					frame_rows[y] = true
					break
	var boxes := {}   # Vector2i(x, row) -> Vector2i(z0, z1), z in pixel rows
	for y in rows:
		for x in rows[y]:
			var cr: Vector2 = run_span[Vector2i(x, y)] if rule.tree_runs else span[y]
			var dx: float = x + 0.5 - cr.x
			var d := (cr.y if rule.tree_square else sqrt(maxf(cr.y * cr.y - dx * dx, 0.0))) * rule.tree_depth
			if rule.tree_thickness > 0.0:
				d = rule.tree_thickness * t * 0.5 if not rule.tree_runs else minf(rule.tree_thickness * t * 0.5, d)
			if rule.tree_dome > 0.0 and y < widest_row:
				var k := float(widest_row - y) / float(widest_row - rmin + 1)
				d *= lerpf(1.0, sqrt(maxf(1.0 - k * k, 0.0)), rule.tree_dome)
			var hd := maxi(1, roundi(d))
			boxes[Vector2i(x, y)] = Vector2i(zc - hd, zc + hd)

	var g := _ground_px(ox + int(axis), oy + b - 1) + rule.base_offset
	var lift := 0.0
	for key in boxes:
		lift = maxf(lift, _ground_px(ox + key.x, oy + key.y))
		lift = maxf(lift, _flat[_px_index(clampi(ox + key.x, 0, _w - 1), clampi(oy + key.y, 0, _h - 1))])
	var fy := lift + FLAT_EPS * (li + 1.0)
	flat_top = maxf(flat_top, fy)
	var dl := delay_at((ox + axis) / t, float(oy + b) / t)
	# Wind bends the whole tree around its root: one pivot per tree, so the
	# offset is a smooth function of the position and the solid stays closed.
	var root := Vector3((ox + axis) / t, g, float(oy + zc) / t)
	var hs := rule.tree_height_scale
	var tree_h := float(b - rmin) / t * hs
	_wind = Vector4(root.x, root.y, root.z, tree_h) if rule.tree_wind > 0.0 else Vector4.ZERO
	var rad := 0.0
	var col_sum := Color(0, 0, 0, 0)
	for key in boxes:
		var zz: Vector2i = boxes[key]
		rad = maxf(rad, (zz.y - zz.x) * 0.5)
		if key.y < rmax - 1:
			col_sum += _pixel_color(infos[owner[key.y * pw + key.x]], ox + key.x, oy + key.y)
	trees.append({"root": root, "height": tree_h, "radius": rad / t, "cut": cut, "wind": rule.tree_wind, "frame": rule.tree_frame,
		"color": col_sum / col_sum.a if col_sum.a > 0.0 else Color(0.4, 0.65, 0.3)})
	var e := UV_INSET
	for key in boxes:
		var x: int = key.x
		var y: int = key.y
		var z: Vector2i = boxes[key]
		var info: Array = infos[owner[y * pw + x]]
		var cell: Vector2i = info[0]
		var src: int = info[2]
		var rp: Vector2i = info[3]
		var fl: int = info[4]
		var lx := ox + x - cell.x * t
		var ly := oy + y - cell.y * t
		var uv := [_corner_uv(rp.x, rp.y, fl, lx + e, ly + e), _corner_uv(rp.x, rp.y, fl, lx + 1 - e, ly + e),
			_corner_uv(rp.x, rp.y, fl, lx + 1 - e, ly + 1 - e), _corner_uv(rp.x, rp.y, fl, lx + e, ly + 1 - e)]
		var uv_c := _corner_uv(rp.x, rp.y, fl, lx + 0.5, ly + 0.5)
		var uvc := [uv_c, uv_c, uv_c, uv_c]
		var X0 := float(ox + x) / t
		var X1 := float(ox + x + 1) / t
		var yt := g + float(b - y) / t * hs
		var yb := g + float(b - y - 1) / t * hs
		var f0 := float(oy + y) / t
		var f1 := float(oy + y + 1) / t
		var Z0 := float(oy + z.x) / t
		var Z1 := float(oy + z.y) / t
		var flat := [Vector3(X0, fy, f0), Vector3(X1, fy, f0), Vector3(X1, fy, f1), Vector3(X0, fy, f1)]
		if frame_rows.has(y) and z.y - z.x > 2:
			# Hollow frame: a 1 px slab at the front and one at the back (a lattice
			# tower gets four legs and two braced faces, and you can see through it).
			for slab in [Vector2i(z.y - 1, z.y), Vector2i(z.x, z.x + 1)]:
				var za := float(oy + slab.x) / t
				var zb := float(oy + slab.y) / t
				_quad(src, flat, [Vector3(X0, yt, zb), Vector3(X1, yt, zb), Vector3(X1, yb, zb), Vector3(X0, yb, zb)],
					uv, Vector3(0, 0, 1), 0.0, dl)
				_quad(src, flat, [Vector3(X0, yt, za), Vector3(X1, yt, za), Vector3(X1, yb, za), Vector3(X0, yb, za)],
					uv, Vector3(0, 0, -1), 0.0, dl)
				for side in [1, -1]:
					if boxes.get(Vector2i(x + side, y)) == z:
						continue
					var sx: float = X1 if side > 0 else X0
					_quad(src, [Vector3(sx, fy, f0), Vector3(sx, fy, f0), Vector3(sx, fy, f1), Vector3(sx, fy, f1)],
						[Vector3(sx, yt, za), Vector3(sx, yt, zb), Vector3(sx, yb, zb), Vector3(sx, yb, za)],
						uvc, Vector3(side, 0, 0), 0.0, dl)
				for up in [true, false]:
					if boxes.get(Vector2i(x, y + (-1 if up else 1))) == z:
						continue
					var yy := yt if up else yb
					var fz := f0 if up else f1
					_quad(src, [Vector3(X0, fy, fz), Vector3(X1, fy, fz), Vector3(X1, fy, fz), Vector3(X0, fy, fz)],
						[Vector3(X0, yy, za), Vector3(X1, yy, za), Vector3(X1, yy, zb), Vector3(X0, yy, zb)],
						uvc, Vector3.UP if up else Vector3.DOWN, 0.0, dl)
			continue
		# Front and back: the pixel itself.
		_quad(src, flat, [Vector3(X0, yt, Z1), Vector3(X1, yt, Z1), Vector3(X1, yb, Z1), Vector3(X0, yb, Z1)],
			uv, Vector3(0, 0, 1), 0.0, dl)
		_quad(src, flat, [Vector3(X0, yt, Z0), Vector3(X1, yt, Z0), Vector3(X1, yb, Z0), Vector3(X0, yb, Z0)],
			uv, Vector3(0, 0, -1), 0.0, dl)
		# Sides, top and bottom where the neighbouring box does not reach;
		# they lie edge-on in the flat map.
		for side in [1, -1]:
			var sx: float = X1 if side > 0 else X0
			var nb = boxes.get(Vector2i(x + side, y))
			if nb != null and frame_rows.has(y) and (nb as Vector2i).y - (nb as Vector2i).x > 2:
				nb = null   # a hollow neighbour does not cover this face
			# (only the shape's outer faces: next to a shallower box the gap would show)
			var sx3: float = sx - side * TREE_SIDE_INSET if nb == null else sx
			for iv in _z_uncovered(z, nb):
				var za := float(oy + iv.x) / t
				var zb := float(oy + iv.y) / t
				_quad(src, [Vector3(sx, fy, f0), Vector3(sx, fy, f0), Vector3(sx, fy, f1), Vector3(sx, fy, f1)],
					[Vector3(sx3, yt, za), Vector3(sx3, yt, zb), Vector3(sx3, yb, zb), Vector3(sx3, yb, za)],
					uvc, Vector3(side, 0, 0), 0.0, dl)
		var above = boxes.get(Vector2i(x, y - 1))
		if above != null and frame_rows.has(y - 1) and (above as Vector2i).y - (above as Vector2i).x > 2:
			above = null
		for iv in _z_uncovered(z, above):
			var za := float(oy + iv.x) / t
			var zb := float(oy + iv.y) / t
			_quad(src, [Vector3(X0, fy, f0), Vector3(X1, fy, f0), Vector3(X1, fy, f0), Vector3(X0, fy, f0)],
				[Vector3(X0, yt, za), Vector3(X1, yt, za), Vector3(X1, yt, zb), Vector3(X0, yt, zb)],
				uvc, Vector3.UP, 0.0, dl)
		if y < b - 1:
			var below_b = boxes.get(Vector2i(x, y + 1))
			if below_b != null and frame_rows.has(y + 1) and (below_b as Vector2i).y - (below_b as Vector2i).x > 2:
				below_b = null
			for iv in _z_uncovered(z, below_b):
				var za := float(oy + iv.x) / t
				var zb := float(oy + iv.y) / t
				_quad(src, [Vector3(X0, fy, f1), Vector3(X1, fy, f1), Vector3(X1, fy, f1), Vector3(X0, fy, f1)],
					[Vector3(X0, yb, za), Vector3(X1, yb, za), Vector3(X1, yb, zb), Vector3(X0, yb, zb)],
					uvc, Vector3.DOWN, 0.0, dl)
	_wind = Vector4.ZERO


## Parts of the z interval `z` not covered by the neighbouring interval `other` (or null).
func _z_uncovered(z: Vector2i, other) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if other == null:
		out.append(z)
		return out
	var o: Vector2i = other
	if o.x > z.x:
		out.append(Vector2i(z.x, mini(o.x, z.y)))
	if o.y < z.y:
		out.append(Vector2i(maxi(o.y, z.x), z.y))
	return out


## Colour of map pixel (x, y) drawn by a tree cell `info` = [cell, rule, src, region pos, flip].
func _pixel_color(info: Array, x: int, y: int) -> Color:
	var c: Vector2i = info[0]
	var sp := _src_local(info[4], x - c.x * tile_px, y - c.y * tile_px)
	var rp: Vector2i = info[3]
	return (_images[info[2]] as Image).get_pixel(rp.x + sp.x, rp.y + sp.y)


# --- ambient occlusion & night windows -----------------------------------------

## Height-field AO: the mean height of everything around a pixel (ground,
## buildings, tree crowns). The shader darkens points that sit below it (the
## ground next to a house, the foot of a cliff, the lower part of a wall), so
## it works without SSAO (Compatibility / Web).
func _compute_ao() -> void:
	var n := _w * _h
	var occ := PackedFloat32Array()
	occ.resize(n)
	for i in n:
		occ[i] = _height[i] if _layer[i] >= 0 else 0.0
	var t := tile_px
	for b in buildings:
		var r: Rect2 = b["rect"]
		var top: float = b["wall_height"] + b.get("ridge", 0.0) * 0.5
		for py in range(int(r.position.y * t), int(r.end.y * t)):
			for px in range(int(r.position.x * t), int(r.end.x * t)):
				var i := _px_index(px, py)
				occ[i] = maxf(occ[i], _ground_px(px, py) + top)
	for tr in trees:
		if tr["cut"] or tr.get("frame", false):   # (see-through frames cast no AO disc)
			continue
		var root: Vector3 = tr["root"]
		var rr: float = tr["radius"] * t
		var top: float = root.y + tr["height"] * 0.7
		for py in range(int(root.z * t - rr), int(root.z * t + rr) + 1):
			for px in range(int(root.x * t - rr), int(root.x * t + rr) + 1):
				if px < 0 or py < 0 or px >= _w or py >= _h:
					continue
				if Vector2(px + 0.5 - root.x * t, py + 0.5 - root.z * t).length() <= rr:
					var i := _px_index(px, py)
					occ[i] = maxf(occ[i], top)
	# Box mean through a summed-area table.
	var w1 := _w + 1
	var sat := PackedFloat64Array()
	sat.resize(w1 * (_h + 1))
	for y in _h:
		var row := 0.0
		for x in _w:
			row += occ[y * _w + x]
			sat[(y + 1) * w1 + x + 1] = sat[y * w1 + x + 1] + row
	const R := 6
	var data := PackedByteArray()
	data.resize(n)
	for y in _h:
		var y0 := maxi(y - R, 0)
		var y1 := mini(y + R + 1, _h)
		for x in _w:
			var x0 := maxi(x - R, 0)
			var x1 := mini(x + R + 1, _w)
			var s := sat[y1 * w1 + x1] - sat[y0 * w1 + x1] - sat[y1 * w1 + x0] + sat[y0 * w1 + x0]
			var m := s / float((x1 - x0) * (y1 - y0))
			data[y * _w + x] = clampi(roundi((m + 1.0) * 63.75), 0, 255)
	ao_image = Image.create_from_data(_w, _h, false, Image.FORMAT_R8, data)


## Marks the window panes of a wall tile in the glow mask of its atlas: pixels
## of the rule's `glow_colors` that are enclosed by other colours (a pane in a
## frame), not the ones that reach the tile border (the wall itself).
func _mark_windows(rule: TobidasuRule, src: int, atlas: Vector2i) -> void:
	if rule.glow_colors.is_empty():
		return
	var key := Vector3i(src, atlas.x, atlas.y)
	if _windows_done.has(key):
		return
	_windows_done[key] = true
	var tp := _tile_pixels(src, atlas)
	var cols: PackedColorArray = tp[3]
	var rp: Vector2i = tp[2]
	var t := tile_px
	var match_ := PackedByteArray()
	match_.resize(t * t)
	for i in t * t:
		for gc in rule.glow_colors:
			var c := cols[i]
			if c.a >= 0.5 and absf(c.r - gc.r) + absf(c.g - gc.g) + absf(c.b - gc.b) < 0.06:
				match_[i] = 1
				break
	# Flood from the border through matching pixels: those are wall, not glass.
	var outside := PackedByteArray()
	outside.resize(t * t)
	var stack: Array[int] = []
	for i in t * t:
		var x := i % t
		var y := i / t
		if match_[i] == 1 and (x == 0 or y == 0 or x == t - 1 or y == t - 1):
			outside[i] = 1
			stack.append(i)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % t
		var y := i / t
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= t or ny >= t:
				continue
			var j := ny * t + nx
			if match_[j] == 1 and outside[j] == 0:
				outside[j] = 1
				stack.append(j)
	for i in t * t:
		if match_[i] == 1 and outside[i] == 0:
			_mask_set(src, rp + Vector2i(i % t, i / t), 0)


## Sets channel `ch` (0 = window pane, 1 = bloom) of an atlas pixel in the source's mask.
func _mask_set(src: int, p: Vector2i, ch: int) -> void:
	if not glow_masks.has(src):
		var size := (_images[src] as Image).get_size()
		glow_masks[src] = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var mask: Image = glow_masks[src]
	var c := mask.get_pixelv(p)
	if ch == 0:
		c.r = 1.0
	else:
		c.g = 1.0
	mask.set_pixelv(p, c)


## Bloom pixels of a tile (source-local, 1 = lifts off) plus, at index
## tile_px * tile_px, the mean luma of the rest (their ground height); empty if none.
func _bloom_mask(rule: TobidasuRule, src: int, atlas: Vector2i) -> PackedFloat32Array:
	if rule.bloom_colors.is_empty():
		return PackedFloat32Array()
	var key := Vector4i(rule.get_instance_id(), src, atlas.x, atlas.y)
	if _bloom_cache.has(key):
		return _bloom_cache[key]
	var tp := _tile_pixels(src, atlas)
	var cols: PackedColorArray = tp[3]
	var luma: PackedFloat32Array = tp[1]
	var n := tile_px * tile_px
	var m := PackedFloat32Array()
	m.resize(n + 1)
	var any := false
	var sum := 0.0
	var cnt := 0
	for i in n:
		var c := cols[i]
		if c.a < 0.5:
			continue
		for b in rule.bloom_colors:
			if absf(c.r - b.r) + absf(c.g - b.g) + absf(c.b - b.b) < 0.06:
				m[i] = 1.0
				any = true
				break
		if m[i] == 0.0:
			sum += luma[i]
			cnt += 1
	m[n] = sum / cnt if cnt > 0 else 0.5
	_bloom_cache[key] = m if any else PackedFloat32Array()
	return _bloom_cache[key]


## Pixels of a tile matching `colors` (source-local, 1 = yes); empty if none.
func _color_mask(rule: TobidasuRule, colors: PackedColorArray, src: int, atlas: Vector2i, tag: int) -> PackedByteArray:
	if colors.is_empty():
		return PackedByteArray()
	var key := [rule.get_instance_id(), src, atlas, tag]
	if _tuft_cache.has(key):
		return _tuft_cache[key]
	var cols: PackedColorArray = _tile_pixels(src, atlas)[3]
	var m := PackedByteArray()
	m.resize(cols.size())
	var any := false
	for i in cols.size():
		var c := cols[i]
		if c.a < 0.5:
			continue
		for b in colors:
			if absf(c.r - b.r) + absf(c.g - b.g) + absf(c.b - b.b) < 0.06:
				m[i] = 1
				any = true
				break
	_tuft_cache[key] = m if any else PackedByteArray()
	return _tuft_cache[key]


func _hash01(a: int, b: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


## A pixel-sized grass blade from `g` up to `top` at pixel (px, py) of the map.
## `flat` = its top face in the flat map (4 corners; a drawn pixel, or a
## collapsed point for extra blades that are not in the drawing).
func _blade(src: int, px: int, py: int, g: float, top: float, uv_top: Array, uv_side: Vector2, flat_top: Array, fp: Vector3, dl: float) -> void:
	var t := float(tile_px)
	var X0 := px / t
	var X1 := (px + 1) / t
	var Z0 := py / t
	var Z1 := (py + 1) / t
	var us := [uv_side, uv_side, uv_side, uv_side]
	_quad(src, flat_top, [Vector3(X0, top, Z0), Vector3(X1, top, Z0), Vector3(X1, top, Z1), Vector3(X0, top, Z1)],
		uv_top, Vector3.UP, 0.0, dl, 0.0, KIND_NORMAL, 0.5)
	var ff := [fp, fp, fp, fp]
	for s in [[Vector2(X0, Z0), Vector2(X1, Z0), Vector3(0, 0, -1)], [Vector2(X1, Z1), Vector2(X0, Z1), Vector3(0, 0, 1)],
			[Vector2(X0, Z1), Vector2(X0, Z0), Vector3(-1, 0, 0)], [Vector2(X1, Z0), Vector2(X1, Z1), Vector3(1, 0, 0)]]:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if flat_top[0] != flat_top[2]:
			# Drawn blade: sides lie edge-on along the pixel's border.
			ff = [Vector3(a.x, fp.y, a.y), Vector3(b.x, fp.y, b.y), Vector3(b.x, fp.y, b.y), Vector3(a.x, fp.y, a.y)]
		_quad(src, ff, [Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, g, b.y), Vector3(a.x, g, a.y)],
			us, s[2], 0.0, dl, 0.0, KIND_NORMAL, 0.5)


## Grass tufts (`tuft_colors` on a ground rule): the tuft pixels of the drawing
## grow up into pixel blades (tops exactly over their pixels, sides edge-on),
## and `tuft_extra` more clumps per tile sprout from plain grass (all their
## faces collapse to a point in the flat map, so 2D is unchanged). Each clump
## sways in the wind around its base.
func _emit_tufts() -> void:
	var t := tile_px
	var e := UV_INSET
	var seen := {}
	var any_uv := Vector2(-1, -1)
	for i0 in _tuft:
		if seen.has(i0):
			continue
		# Pixels within 2 of each other form one clump.
		var blob: Array[int] = []
		var stack: Array[int] = [i0]
		seen[i0] = true
		while not stack.is_empty():
			var i: int = stack.pop_back()
			blob.append(i)
			var x := i % _w
			var y := i / _w
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
						continue
					var j := ny * _w + nx
					if _tuft.has(j) and not seen.has(j):
						seen[j] = true
						stack.append(j)
		var c := Vector2.ZERO
		var lowest := 0
		for i in blob:
			c += Vector2(i % _w + 0.5, i / _w + 0.5)
			lowest = maxi(lowest, i / _w)
		c /= blob.size()
		if _covered_cells.has(Vector2i(i0 % _w, i0 / _w) / tile_px):
			continue
		var rule: TobidasuRule = _tuft[i0][7]
		var li: int = _tuft[i0][6]
		var g := _ground_px(int(c.x), int(c.y))
		var fy := FLAT_EPS * (li + 0.5)
		var dl := delay_at(c.x / t, c.y / t)
		_wind = Vector4(c.x / t, g, c.y / t, rule.tuft_height)
		tufts.append({"pos": Vector3(c.x / t, g, c.y / t)})
		for i in blob:
			var r: Array = _tuft[i]
			var rp: Vector2i = r[1]
			var fl: int = r[2]
			var lx: int = r[4]
			var ly: int = r[5]
			var px := i % _w
			var py := i / _w
			# Lower rows of the drawing are the base of the tuft: shorter blades.
			var k := 0.55 + 0.45 * _hash01(px, py)
			var top := _ground_px(px, py) + rule.tuft_height * k * (1.0 - 0.18 * (py - (lowest - 3)) / 3.0)
			var uv := [_corner_uv(rp.x, rp.y, fl, lx + e, ly + e), _corner_uv(rp.x, rp.y, fl, lx + 1 - e, ly + e),
				_corner_uv(rp.x, rp.y, fl, lx + 1 - e, ly + 1 - e), _corner_uv(rp.x, rp.y, fl, lx + e, ly + 1 - e)]
			var uc := _corner_uv(rp.x, rp.y, fl, lx + 0.5, ly + 0.5)
			if any_uv.x < 0.0:
				any_uv = uc
			var X0 := float(px) / t
			var X1 := float(px + 1) / t
			var Z0 := float(py) / t
			var Z1 := float(py + 1) / t
			_blade(r[0], px, py, _ground_px(px, py), top, uv, uc,
				[Vector3(X0, fy, Z0), Vector3(X1, fy, Z0), Vector3(X1, fy, Z1), Vector3(X0, fy, Z1)], Vector3(X0, fy, Z0), dl)
	_wind = Vector4.ZERO
	# Extra clumps on plain grass, coloured like the drawn tufts.
	for cell: Vector2i in _tuft_cells:
		if _covered_cells.has(cell):
			continue
		var info: Array = _tuft_cells[cell]
		var rule: TobidasuRule = info[1]
		var src: int = info[0]
		var li: int = info[2]
		var uvc: Vector2 = any_uv if any_uv.x >= 0.0 else info[3]
		var n := int(rule.tuft_extra) + (1 if _hash01(cell.x * 7 + 1, cell.y * 13 + 5) < fposmod(rule.tuft_extra, 1.0) else 0)
		for k in n:
			var cx: int = cell.x * t + 3 + int(_hash01(cell.x + k * 31, cell.y) * (t - 6))
			var cy: int = cell.y * t + 3 + int(_hash01(cell.y + k * 17, cell.x + 3) * (t - 6))
			var ci: int = cy * _w + cx
			if _tuft.has(ci) or _bloom.has(ci) or _layer[ci] != li:
				continue
			var g := _ground_px(cx, cy)
			var fy := FLAT_EPS * (li + 0.5)
			var fp := Vector3(float(cx) / t, fy, float(cy) / t)
			var dl := delay_at(fp.x, fp.z)
			_wind = Vector4(fp.x, g, fp.z, rule.tuft_height)
			tufts.append({"pos": Vector3(fp.x, g, fp.z)})
			var uvs := [uvc, uvc, uvc, uvc]
			for b in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(2, -1)]:
				if _hash01(cx + b.x * 5, cy + b.y * 3) < 0.25 and b != Vector2i(0, 0):
					continue
				var bx: int = cx + b.x
				var by: int = cy + b.y
				var hb := rule.tuft_height * (0.45 + 0.55 * _hash01(bx, by)) * (1.0 if b.y <= 0 else 0.7)
				_blade(src, bx, by, _ground_px(bx, by), _ground_px(bx, by) + hb, uvs, uvc, [fp, fp, fp, fp], fp, dl)
	_wind = Vector4.ZERO


## Flowers drawn on a ground tile (`bloom_colors`): every 4-connected patch of
## them becomes a little head floating at `bloom_height` on a 1-pixel stem.
## Head faces lie exactly over their pixels (so 2D is unchanged); sides and
## stem lie edge-on. In 3D the shader paints the ground under them with the
## surrounding colour (bloom mask, channel G). Heads sway in the wind.
func _emit_blooms() -> void:
	var t := tile_px
	var seen := {}
	for i0 in _bloom:
		if seen.has(i0):
			continue
		var blob: Array[int] = []
		var stack: Array[int] = [i0]
		seen[i0] = true
		while not stack.is_empty():
			var i: int = stack.pop_back()
			blob.append(i)
			var x := i % _w
			var y := i / _w
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
					continue
				var j := ny * _w + nx
				if _bloom.has(j) and not seen.has(j):
					seen[j] = true
					stack.append(j)
		var c := Vector2.ZERO
		for i in blob:
			c += Vector2(i % _w + 0.5, i / _w + 0.5)
		c /= blob.size()
		if _covered_cells.has(Vector2i(i0 % _w, i0 / _w) / tile_px):
			continue
		var rule: TobidasuRule = _bloom[i0][7]
		var li: int = _bloom[i0][6]
		var g := _ground_px(int(c.x), int(c.y))
		var top := g + rule.bloom_height
		var bot := top - 1.0 / t
		var fy := FLAT_EPS * (li + 0.5)
		var dl := delay_at(c.x / t, c.y / t)
		_wind = Vector4(c.x / t, g, c.y / t, rule.bloom_height)
		var e := UV_INSET
		var inb := {}
		for i in blob:
			inb[i] = true
		for i in blob:
			var r: Array = _bloom[i]
			var rp: Vector2i = r[1]
			var fl: int = r[2]
			var lx: int = r[4]
			var ly: int = r[5]
			var px := i % _w
			var py := i / _w
			var X0 := float(px) / t
			var X1 := float(px + 1) / t
			var Z0 := float(py) / t
			var Z1 := float(py + 1) / t
			var uv := [_corner_uv(rp.x, rp.y, fl, lx + e, ly + e), _corner_uv(rp.x, rp.y, fl, lx + 1 - e, ly + e),
				_corner_uv(rp.x, rp.y, fl, lx + 1 - e, ly + 1 - e), _corner_uv(rp.x, rp.y, fl, lx + e, ly + 1 - e)]
			var uc := _corner_uv(rp.x, rp.y, fl, lx + 0.5, ly + 0.5)
			var uvc := [uc, uc, uc, uc]
			var flat := [Vector3(X0, fy, Z0), Vector3(X1, fy, Z0), Vector3(X1, fy, Z1), Vector3(X0, fy, Z1)]
			_quad(r[0], flat, [Vector3(X0, top, Z0), Vector3(X1, top, Z0), Vector3(X1, top, Z1), Vector3(X0, top, Z1)],
				uv, Vector3.UP, 0.0, dl, 0.0, KIND_NORMAL, 0.5)
			_quad(r[0], flat, [Vector3(X0, bot, Z0), Vector3(X1, bot, Z0), Vector3(X1, bot, Z1), Vector3(X0, bot, Z1)],
				uv, Vector3.DOWN, 0.0, dl, 0.0, KIND_NORMAL, 0.5)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var j: int = (py + d.y) * _w + px + d.x
				if inb.has(j):
					continue
				var a: Vector2
				var b: Vector2
				if d.x != 0:
					var sx := X1 if d.x > 0 else X0
					a = Vector2(sx, Z0)
					b = Vector2(sx, Z1)
				else:
					var sz := Z1 if d.y > 0 else Z0
					a = Vector2(X0, sz)
					b = Vector2(X1, sz)
				_quad(r[0], [Vector3(a.x, fy, a.y), Vector3(b.x, fy, b.y), Vector3(b.x, fy, b.y), Vector3(a.x, fy, a.y)],
					[Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, bot, b.y), Vector3(a.x, bot, a.y)],
					uvc, Vector3(d.x, 0, d.y), 0.0, dl, 0.0, KIND_NORMAL, 0.5)
		# Stem: one pixel column under the middle, coloured like the darkest
		# non-flower pixel of the tile that is not outline (the leaves).
		var r0: Array = _bloom[i0]
		var cell: Vector2i = r0[3]
		var rp0: Vector2i = r0[1]
		var stem_uv: Vector2 = _corner_uv(rp0.x, rp0.y, r0[2], r0[4] + 0.5, r0[5] + 0.5)
		var best := 9.0
		var img: Image = _images[r0[0]]
		for ly in t:
			for lx in t:
				var mi := (cell.y * t + ly) * _w + cell.x * t + lx
				if _bloom.has(mi):
					continue
				var col := img.get_pixelv(rp0 + _src_local(r0[2], lx, ly))
				var lu := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
				if col.a >= 0.5 and lu > 0.3 and lu < best:
					best = lu
					stem_uv = _corner_uv(rp0.x, rp0.y, r0[2], lx + 0.5, ly + 0.5)
		var su := [stem_uv, stem_uv, stem_uv, stem_uv]
		var sx0 := floorf(c.x) / t
		var sz0 := floorf(c.y) / t
		var s1 := 1.0 / t
		var ff := Vector3(sx0, fy, sz0)
		for side in [[Vector3(0, 0, 0), Vector3(s1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, 0, s1), Vector3(s1, 0, s1), Vector3(0, 0, 1)],
				[Vector3(0, 0, 0), Vector3(0, 0, s1), Vector3(-1, 0, 0)], [Vector3(s1, 0, 0), Vector3(s1, 0, s1), Vector3(1, 0, 0)]]:
			var a3: Vector3 = Vector3(sx0, 0, sz0) + side[0]
			var b3: Vector3 = Vector3(sx0, 0, sz0) + side[1]
			_quad(r0[0], [ff, ff, ff, ff],
				[Vector3(a3.x, bot, a3.z), Vector3(b3.x, bot, b3.z), Vector3(b3.x, g, b3.z), Vector3(a3.x, g, a3.z)],
				su, side[2], 0.0, dl, 0.0, KIND_NORMAL, 0.5)
		_wind = Vector4.ZERO



func _ground_px(x: int, y: int) -> float:
	var i := _px_index(clampi(x, 0, _w - 1), clampi(y, 0, _h - 1))
	return _height[i] if _layer[i] >= 0 else 0.0


## A whole tile drawn flat (exactly like the 2D map) that sinks just below the
## ground when popped: keeps the outline and other pixels a model leaves out.
func _emit_sunk_tile(c: Vector2i, src: int, rp: Vector2i, fl: int, li: int, layer_eps: float) -> void:
	var t := tile_px
	var lift := 0.0
	var low := INF
	for py in range(c.y * t, (c.y + 1) * t):
		for px in range(c.x * t, (c.x + 1) * t):
			var h := _ground_px(px, py)
			lift = maxf(lift, h)
			low = minf(low, h)
	var fy := lift + FLAT_EPS * (li + layer_eps)
	var y3 := low - 0.03
	var e := UV_INSET
	var x0 := float(c.x)
	var z0 := float(c.y)
	var p3 := [Vector3(x0, y3, z0), Vector3(x0 + 1, y3, z0), Vector3(x0 + 1, y3, z0 + 1), Vector3(x0, y3, z0 + 1)]
	if collapse_sunk:
		var mid := Vector3(x0 + 0.5, y3 + 0.1, z0 + 0.5)
		p3 = [mid, mid, mid, mid]
	_quad(src,
		[Vector3(x0, fy, z0), Vector3(x0 + 1, fy, z0), Vector3(x0 + 1, fy, z0 + 1), Vector3(x0, fy, z0 + 1)],
		p3,
		[_corner_uv(rp.x, rp.y, fl, e, e), _corner_uv(rp.x, rp.y, fl, t - e, e),
			_corner_uv(rp.x, rp.y, fl, t - e, t - e), _corner_uv(rp.x, rp.y, fl, e, t - e)],
		Vector3.UP, 0.0, delay_at(x0 + 0.5, z0 + 0.5))


# --- props -------------------------------------------------------------------

func _emit_props(cells: Dictionary, li: int) -> void:
	for c in cells:
		var info: Array = cells[c]
		var r: TobidasuRule = info[0]
		match r.prop:
			"well":
				# Anchored on the bottom tile; the prop tile above is its roof.
				var below = cells.get(c + Vector2i(0, 1))
				if below != null and (below[0] as TobidasuRule).prop == "well":
					continue
				var above = cells.get(c + Vector2i(0, -1))
				if above != null and (above[0] as TobidasuRule).prop != "well":
					above = null
				if tile_px != 16 or info[3] != 0 or (above != null and above[3] != 0):
					push_warning("Tobidasu: the well template needs unflipped 16 px tiles.")
					_emit_sunk_prop(c, info, li, above)
					continue
				_emit_well(c, info, above, li)
			"portal":
				_emit_portal(c, info, li)
			_:
				push_warning("Tobidasu: unknown prop template '%s'." % r.prop)
				_emit_sunk_prop(c, info, li, null)


func _emit_sunk_prop(c: Vector2i, info: Array, li: int, above) -> void:
	_emit_sunk_tile(c, info[1], _tile_pixels(info[1], info[2])[2], info[3], li, 0.5)
	if above != null:
		_emit_sunk_tile(c + Vector2i(0, -1), above[1], _tile_pixels(above[1], above[2])[2], above[3], li, 0.5)


## Well template for a 3/4-view well of two 16 px tiles (Kenney Tiny Town 92
## over 104): stone ring with water, two posts, a beam with a bucket and a
## gabled roof. Coordinates are in pixels of the bottom tile (x right, z down
## the map, y up); the drawing's rows -16..-1 belong to the roof tile.
## The drawing is cut into pieces that each become one face (roof slopes,
## beam, posts, water, the front of the ring); every other face is hidden in
## 2D: it lies under the drawing, projected straight down.
func _emit_well(c: Vector2i, info: Array, above, li: int) -> void:
	var src: int = info[1]
	var rb: Vector2 = Vector2(_tile_pixels(src, info[2])[2])
	var rt: Vector2 = Vector2(_tile_pixels(above[1], above[2])[2]) if above != null else rb
	var g := 0.0
	for py in range((c.y - (1 if above != null else 0)) * 16, (c.y + 1) * 16):
		for px in range(c.x * 16, (c.x + 1) * 16):
			g = maxf(g, _ground_px(px, py))
	var w := {
		"src": src, "o": Vector3(c.x, g, c.y), "rb": rb, "rt": rt, "has_top": above != null,
		"fy": g + FLAT_EPS * (li + 1.5), "fh": g + FLAT_EPS * (li + 1.0),
		"dl": delay_at(c.x + 0.5, c.y + 0.5),
	}
	flat_top = maxf(flat_top, w.fy)
	var STONE := rb + Vector2(5.5, 13.5)
	var RIM := rb + Vector2(5.5, 11.5)
	var DARK := rb + Vector2(2.5, 12.5)
	var WOOD_D := rb + Vector2(3.5, 5.5)
	var WOOD_S := rb + Vector2(3.5, 6.5)
	var WATER := rb + Vector2(6.5, 8.5)
	const RH := 5.0      # ring height
	const WL := 3.5      # water level
	const EAVE := 14.0
	const RIDGE := 19.0
	const BEAM := 12.0   # bottom of the beam
	var S := Vector3(0, 0, 1)

	# Stone ring: pixel voxels between radius 3.4 and 6 around (8, 9).
	var solid := {}
	var water := {}
	for j in 16:
		for i in 16:
			var d := Vector2(i + 0.5 - 8.0, j + 0.5 - 9.0).length()
			if d <= 6.0:
				if d >= 3.4:
					solid[Vector2i(i, j)] = true
				else:
					water[Vector2i(i, j)] = true
	var front := {}   # column -> z of its south face
	for k in solid:
		front[k.x] = maxi(front.get(k.x, 0), k.y + 1)
	for k in solid:
		var x0 := float(k.x)
		var z0 := float(k.y)
		_well_face(w, [Vector3(x0, RH, z0), Vector3(x0 + 1, RH, z0), Vector3(x0 + 1, RH, z0 + 1), Vector3(x0, RH, z0 + 1)], RIM, Vector3.UP)
		for dlt in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = k + dlt
			if solid.has(nb):
				continue
			var n := Vector3(dlt.x, 0, dlt.y)
			# Edge of the cell facing `dlt`: from corner a to corner b.
			var ax := x0 + (1.0 if dlt.x > 0 else 0.0)
			var az := z0 + (1.0 if dlt.y > 0 else 0.0)
			var bx := ax + (0.0 if dlt.x != 0 else 1.0)
			var bz := az + (1.0 if dlt.x != 0 else 0.0)
			if water.has(nb):
				_well_face(w, [Vector3(ax, RH, az), Vector3(bx, RH, bz), Vector3(bx, WL, bz), Vector3(ax, WL, az)], DARK, n)
				continue
			if dlt == Vector2i(0, 1) and k.x >= 2 and k.x <= 13:
				continue   # the front of the ring comes from the drawing
			# Outer stone: a light rim course, then stones with dark joints.
			for row in 5:
				var yt := RH - row
				var col := RIM if row == 0 else STONE
				if row > 0 and (k.x * 3 + k.y * 5 + row * 2) % 7 == 0:
					col = DARK
				_well_face(w, [Vector3(ax, yt, az), Vector3(bx, yt, bz), Vector3(bx, yt - 1, bz), Vector3(ax, yt - 1, az)], col, n)
	for x in range(2, 14):
		var zf := float(front[x])
		_well_piece(w, Rect2(x, 11, 1, 5), [Vector3(x, RH, zf), Vector3(x + 1, RH, zf), Vector3(x + 1, 0, zf), Vector3(x, 0, zf)], S)
	# Water surface (its corners hide inside the ring).
	_well_piece(w, Rect2(5, 6, 6, 5), [Vector3(5, WL, 6), Vector3(11, WL, 6), Vector3(11, WL, 12), Vector3(5, WL, 12)], Vector3.UP)
	# Posts and beam: fronts from the drawing, the rest plain wood.
	for x0 in [3.0, 11.0]:
		_well_piece(w, Rect2(x0, 6, 2, 5), [Vector3(x0, BEAM, 10), Vector3(x0 + 2, BEAM, 10), Vector3(x0 + 2, RH, 10), Vector3(x0, RH, 10)], S)
		_well_box(w, Vector3(x0, RH, 8), Vector3(x0 + 2, BEAM, 10), WOOD_S, WOOD_S, false)
	_well_piece(w, Rect2(2, 4, 12, 2), [Vector3(2, EAVE, 10), Vector3(14, EAVE, 10), Vector3(14, BEAM, 10), Vector3(2, BEAM, 10)], S)
	_well_box(w, Vector3(2, BEAM, 8), Vector3(14, EAVE, 10), WOOD_D, WOOD_D, true)
	# Rope and bucket. In 3D the bucket goes down into the water and back up
	# (CUSTOM2.w < 0: points below CUSTOM2.y drop by up to CUSTOM2.z, cycle
	# phase CUSTOM2.x); the rope's top stays on the beam, so it stretches.
	var o: Vector3 = w.o
	var drop := (RH + 0.5 - 1.0) / 16.0
	var phase := fposmod(c.x * 0.37 + c.y * 0.61, 1.0)
	wells.append({"pos": o + Vector3(8, 3.5, 9) / 16.0, "phase": phase})
	_wind = Vector4(phase, o.y + (BEAM - 0.5) / 16.0, drop, -1.0)
	_well_box(w, Vector3(7.5, 7.5, 8.5), Vector3(8.5, BEAM, 9.5), WOOD_D, WOOD_D, true)
	_wind = Vector4(phase, 1e6, drop, -1.0)
	_well_box(w, Vector3(7, RH + 0.5, 8), Vector3(9, 7.5, 10), WOOD_S, WATER, true)
	_wind = Vector4.ZERO
	# Roof: the left half of the drawing is the west slope, the right half the
	# east slope (ridge running north-south); the dark outline columns hang
	# down as fascia boards. Undersides reuse the drawing.
	var top := -8.0 if above != null else 0.0
	var hgt := 4.0 - top
	var pieces := [
		[Rect2(2, top, 6, hgt), [Vector3(1, EAVE, 1), Vector3(8, RIDGE, 1), Vector3(8, RIDGE, 17), Vector3(1, EAVE, 17)], Vector3(-5, 7, 0).normalized()],
		[Rect2(8, top, 6, hgt), [Vector3(8, RIDGE, 1), Vector3(15, EAVE, 1), Vector3(15, EAVE, 17), Vector3(8, RIDGE, 17)], Vector3(5, 7, 0).normalized()],
		[Rect2(0, top, 2, hgt), [Vector3(1, EAVE - 2, 1), Vector3(1, EAVE, 1), Vector3(1, EAVE, 17), Vector3(1, EAVE - 2, 17)], Vector3(-1, 0, 0)],
		[Rect2(14, top, 2, hgt), [Vector3(15, EAVE, 1), Vector3(15, EAVE - 2, 1), Vector3(15, EAVE - 2, 17), Vector3(15, EAVE, 17)], Vector3(1, 0, 0)],
	]
	for pc in pieces:
		_well_piece(w, pc[0], pc[1], pc[2])
		_well_piece(w, pc[0], pc[1], -(pc[2] as Vector3), true)
	# Dark outline at the sides of the drawing and the thin rim highlights
	# next to the posts: sink below the ground.
	var low := g
	for py in range(c.y * 16, (c.y + 1) * 16):
		for px in range(c.x * 16, (c.x + 1) * 16):
			low = minf(low, _ground_px(px, py))
	var yl := (low - g - 0.03) * 16.0
	for r in [Rect2(0, 4, 2, 12), Rect2(14, 4, 2, 12), Rect2(2, 6, 1, 5), Rect2(13, 6, 1, 5)]:
		var a: Vector2 = r.position
		var b: Vector2 = r.end
		_well_piece(w, r, [Vector3(a.x, yl, a.y), Vector3(b.x, yl, a.y), Vector3(b.x, yl, b.y), Vector3(a.x, yl, b.y)], Vector3.UP)


## Portal template: a stone tunnel mouth in the cliff on the east side of the
## raised tile it sits on (west side if the cell is flipped), for a railway or a
## road going into a hill. The tile itself is the 2D look (the mouth seen from
## above) and sinks under the plateau in 3D; the 3D face is pixel masonry that
## lies edge-on in the flat map. The opening spans the rows of the drawing's
## darkest pixels on the face's edge column. Colours come from the drawing,
## darkest first: inside of the tunnel, soot, joints, stone, light stone; the
## brightest one tops the parapet (snow).
func _emit_portal(c: Vector2i, info: Array, li: int) -> void:
	var t := tile_px
	var src: int = info[1]
	var fl: int = info[3]
	var tp := _tile_pixels(src, info[2])
	var rp: Vector2i = tp[2]
	var alpha: PackedByteArray = tp[0]
	var luma: PackedFloat32Array = tp[1]
	var cols: PackedColorArray = tp[3]
	_emit_sunk_tile(c, src, rp, fl, li, 0.5)
	var west := (fl & 1) != 0
	var dir := -1.0 if west else 1.0
	# Colours of the drawing, darkest first (texel positions in the atlas).
	var seen := {}
	var swatch: Array = []   # [luma, texel centre]
	for ly in t:
		for lx in t:
			var k := ly * t + lx
			if alpha[k] == 0:
				continue
			var key := cols[k].to_html(false)
			if not seen.has(key):
				seen[key] = true
				swatch.append([luma[k], Vector2(rp) + Vector2(lx + 0.5, ly + 0.5)])
	if swatch.size() < 2:
		return
	swatch.sort_custom(func(a: Array, b: Array): return a[0] < b[0])
	var pick := func(i: int) -> Vector2: return swatch[clampi(i, 0, swatch.size() - 1)][1]
	var INSIDE: Vector2 = pick.call(0)
	var SOOT: Vector2 = pick.call(1)
	var JOINT: Vector2 = pick.call(2)
	var STONE: Vector2 = pick.call(3)
	var LIGHT: Vector2 = pick.call(mini(4, swatch.size() - 2))
	var TOP: Vector2 = pick.call(swatch.size() - 1)
	# The opening: rows of the darkest colour on the face's edge column.
	var edge := 0 if west else t - 1
	var m0 := t
	var m1 := -1
	for ly in t:
		var sp := _src_local(fl, edge, ly)
		var k := sp.y * t + sp.x
		if alpha[k] != 0 and luma[k] <= (swatch[0][0] as float) + 0.02:
			m0 = mini(m0, ly)
			m1 = maxi(m1, ly)
	if m1 < 0:
		m0 = 4
		m1 = 11
	var hp := 0.0     # top of the plateau
	for py in range(c.y * t, (c.y + 1) * t):
		for px in range(c.x * t, (c.x + 1) * t):
			hp = maxf(hp, _ground_px(px, py))
	var ox := c.x + 1 if not west else c.x
	var g0 := _ground_px(ox * t + (1 if not west else -2), c.y * t + (m0 + m1) / 2)   # track level outside
	var hpx := maxi(roundi((hp - g0) * t) + 2, 8)   # face height (px), parapet 2 px above the plateau
	var zc := c.y * t + (m0 + m1 + 1) * 0.5          # opening centre (map px)
	var hw := (m1 - m0 + 1) * 0.5                    # half width of the opening (px)
	var W := int(ceil(hw)) * 2 + 10                  # face width (px)
	var u0 := int(floor(zc - W * 0.5))
	var spring := clampf(hpx - 8 - hw, 3.0, hw * 3.5)  # arch springs from here (px above the track)
	var xf := float(ox) + dir * 0.01                 # just proud of the cliff
	var fy := hp + FLAT_EPS * (li + 1.0)
	flat_top = maxf(flat_top, fy)
	var dl := delay_at(float(ox), zc / t)
	# Colour of one pixel of the face: column u (along z, map px), row v (up from the track).
	var face_col := func(u: int, v: int) -> Vector2:
		var dz := u + 0.5 - zc
		var crown := spring + hw
		var inside := absf(dz) < hw and (v + 0.5 < spring or Vector2(dz, v + 0.5 - spring).length() < hw)
		if inside:
			return INSIDE
		var ring := absf(dz) < hw + 2.0 and (v + 0.5 < spring or Vector2(dz, v + 0.5 - spring).length() < hw + 2.0)
		if v >= hpx - 2:
			return LIGHT                                             # coping
		if v == hpx - 5:
			return LIGHT                                             # string course
		if u - u0 <= 1 or u - u0 >= W - 2:
			return LIGHT if v % 4 != 3 else JOINT                    # pilasters
		if ring:
			if v + 0.5 >= spring and absf(dz) < 1.0:
				return LIGHT                                         # keystone
			var a := atan2(v + 0.5 - spring, dz)
			return JOINT if v + 0.5 >= spring and fposmod(a * 5.0, 1.0) < 0.18 else LIGHT
		# Soot of the locomotives above the opening, thinning out upward.
		var sv := v + 0.5 - crown
		if sv > 0.0 and absf(dz) < hw + 3.0 - sv * 0.4 and _hash01(u * 3 + 1, v * 7) > sv * 0.12:
			return SOOT
		var course := v / 3
		if v % 3 == 2:
			return JOINT
		if (u + (course % 2) * 3) % 6 == 0:
			return JOINT
		return STONE if _hash01(u + course * 11, course) > 0.15 else LIGHT
	var n := Vector3(dir, 0, 0)
	for v in hpx:
		var y0 := g0 + float(v) / t
		var y1 := g0 + float(v + 1) / t
		var run_start := 0
		var run_col: Vector2 = face_col.call(u0, v)
		for u in range(1, W + 1):
			var col: Vector2 = face_col.call(u0 + u, v) if u < W else Vector2(-1, -1)
			if col == run_col:
				continue
			var za := float(u0 + run_start) / t
			var zb := float(u0 + u) / t
			_quad(src, [Vector3(xf, fy, za), Vector3(xf, fy, zb), Vector3(xf, fy, zb), Vector3(xf, fy, za)],
				[Vector3(xf, y1, za), Vector3(xf, y1, zb), Vector3(xf, y0, zb), Vector3(xf, y0, za)],
				[run_col, run_col, run_col, run_col], n, 0.0, dl)
			run_start = u
			run_col = col
	# Parapet: 2 px deep, its top (snow) and back above the plateau; ends.
	var yt := g0 + float(hpx) / t
	var xb := xf - dir * 2.0 / t
	var za0 := float(u0) / t
	var zb0 := float(u0 + W) / t
	_quad(src, [Vector3(xf, fy, za0), Vector3(xf, fy, za0), Vector3(xf, fy, zb0), Vector3(xf, fy, zb0)],
		[Vector3(xb, yt, za0), Vector3(xf, yt, za0), Vector3(xf, yt, zb0), Vector3(xb, yt, zb0)],
		[TOP, TOP, TOP, TOP], Vector3.UP, 0.0, dl)
	_quad(src, [Vector3(xb, fy, za0), Vector3(xb, fy, zb0), Vector3(xb, fy, zb0), Vector3(xb, fy, za0)],
		[Vector3(xb, yt, za0), Vector3(xb, yt, zb0), Vector3(xb, hp, zb0), Vector3(xb, hp, za0)],
		[STONE, STONE, STONE, STONE], -n, 0.0, dl)
	for zz in [za0, zb0]:
		var nz := Vector3(0, 0, -1) if zz == za0 else Vector3(0, 0, 1)
		_quad(src, [Vector3(xb, fy, zz), Vector3(xf, fy, zz), Vector3(xf, fy, zz), Vector3(xb, fy, zz)],
			[Vector3(xb, yt, zz), Vector3(xf, yt, zz), Vector3(xf, g0, zz), Vector3(xb, g0, zz)],
			[LIGHT, LIGHT, LIGHT, LIGHT], nz, 0.0, dl)


## A rectangle of the well drawing (pixels; y < 0 is the roof tile) that becomes
## the 3D quad `p3` (pixel coordinates, corners in the rectangle's order).
## `under` = the hidden underside of that face (plain, facing down).
func _well_piece(w: Dictionary, r: Rect2, p3: Array, n: Vector3, under := false) -> void:
	if r.position.y < 0.0 and r.end.y > 0.0:
		var k := -r.position.y / r.size.y
		var m0: Vector3 = (p3[0] as Vector3).lerp(p3[3], k)
		var m1: Vector3 = (p3[1] as Vector3).lerp(p3[2], k)
		_well_piece(w, Rect2(r.position.x, r.position.y, r.size.x, -r.position.y), [p3[0], p3[1], m1, m0], n, under)
		_well_piece(w, Rect2(r.position.x, 0, r.size.x, r.end.y), [m0, m1, p3[2], p3[3]], n, under)
		return
	var o: Vector3 = w.o
	var top := r.position.y < 0.0
	var region: Vector2 = w.rt if top else w.rb
	var dy := 16.0 if top else 0.0
	var fy: float = w.fh if under else w.fy
	var flat := []
	var uv := []
	var e := UV_INSET
	for k in 4:
		var u := r.position.x + (r.size.x if k == 1 or k == 2 else 0.0)
		var v := r.position.y + (r.size.y if k >= 2 else 0.0)
		flat.append(Vector3(o.x + u / 16.0, fy, o.z + v / 16.0))
		var eu := e if (k == 0 or k == 3) else -e
		var ev := e if k < 2 else -e
		uv.append(region + Vector2(u + eu, v + dy + ev))
	var pts := []
	for p in p3:
		pts.append(o + (p as Vector3) / 16.0)
	_quad(w.src, flat, pts, uv, n, 0.0, w.dl)


## A plain face of the well, hidden in 2D (projected straight down under the drawing).
func _well_face(w: Dictionary, p3: Array, texel: Vector2, n: Vector3) -> void:
	var o: Vector3 = w.o
	var flat := []
	var pts := []
	for p in p3:
		flat.append(Vector3(o.x + p.x / 16.0, w.fh, o.z + p.z / 16.0))
		pts.append(o + (p as Vector3) / 16.0)
	_quad(w.src, flat, pts, [texel, texel, texel, texel], n, 0.0, w.dl)


## Box from `a` to `b` (pixels): sides, top, and the south face unless the drawing covers it.
func _well_box(w: Dictionary, a: Vector3, b: Vector3, side: Vector2, top: Vector2, south: bool) -> void:
	_well_face(w, [Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)], top, Vector3.UP)
	_well_face(w, [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)], side, Vector3.DOWN)
	_well_face(w, [Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z)], side, Vector3(0, 0, -1))
	if south:
		_well_face(w, [Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)], side, Vector3(0, 0, 1))
	_well_face(w, [Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z), Vector3(a.x, a.y, a.z)], side, Vector3(-1, 0, 0))
	_well_face(w, [Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z)], side, Vector3(1, 0, 0))


# --- output -------------------------------------------------------------------

func _make_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var fmt := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TEX_UV \
		| Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_INDEX \
		| Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| Mesh.ARRAY_FORMAT_CUSTOM2 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	# Atlas surfaces first, see-through water last.
	var keys := _surfaces.keys()
	keys.sort_custom(func(a, b): return (a == "water") == false and b == "water")
	for key in keys:
		var s: _Surface = _surfaces[key]
		if s.indices.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_COLOR] = s.colors
		arrays[Mesh.ARRAY_CUSTOM0] = s.custom0
		arrays[Mesh.ARRAY_CUSTOM1] = s.custom1
		arrays[Mesh.ARRAY_CUSTOM2] = s.custom2
		arrays[Mesh.ARRAY_INDEX] = s.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		var si := mesh.get_surface_count() - 1
		mesh.surface_set_name(si, key)
		mesh.set_meta("kind_%d" % si, s.kind)
		mesh.set_meta("texture_%d" % si, s.texture)
		mesh.set_meta("grid_%d" % si, s.grid)
		if glow_masks.has(s.src):
			mesh.set_meta("glow_%d" % si, ImageTexture.create_from_image(glow_masks[s.src]))
	mesh.custom_aabb = bounds.grow(0.5)
	return mesh


func get_stats() -> Dictionary:
	var v := 0
	var tri := 0
	for key in _surfaces:
		v += (_surfaces[key] as _Surface).verts.size()
		tri += (_surfaces[key] as _Surface).indices.size() / 3
	return {"vertices": v, "triangles": tri, "cells": map_cells}

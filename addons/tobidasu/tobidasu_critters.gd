@tool
@icon("res://addons/tobidasu/icon.svg")
class_name TobidasuCritters
extends Node3D
## Little ambient life for a Tobidasu3D model: butterflies by day, fireflies
## at night, leaves dropping from the trees, bees, grasshoppers, koi, falling
## snow and smoke / steam. Each kind is one MultiMesh
## animated entirely in the vertex shader (cheap, works on the Compatibility
## renderer / Web). Hidden while the map is flat, so the 2D view never changes.
##
## Add it anywhere in the scene, point `target` at the Tobidasu3D node and
## drive `daylight` / `night` from your time of day.

const SHADER := preload("res://addons/tobidasu/tobidasu_critters.gdshader")
const KINDS := ["butterflies", "fireflies", "leaves", "bees", "grasshoppers", "koi", "snow", "smoke"]

@export var target: Tobidasu3D:
	set(v):
		if target != null and target.built.is_connected(_on_built):
			target.built.disconnect(_on_built)
		target = v
		if target != null and is_inside_tree() and not target.built.is_connected(_on_built):
			target.built.connect(_on_built)
@export_range(0, 200) var butterflies := 14
@export_range(0, 400) var fireflies := 70
@export_range(0, 200) var leaves := 24
## Bees buzz around these spots (tiles), e.g. beehives. Empty = no bees.
@export var bee_spots := PackedVector2Array()
## Bees per spot.
@export_range(0, 20) var bees_per_spot := 3
## Grasshoppers hopping about in the grass at night (homes = Tobidasu3D.get_tufts()).
@export_range(0, 300) var grasshoppers := 30
## Butterflies fly here (map positions in tiles). Empty = around the trees.
@export var butterfly_spots := PackedVector2Array()
## Fireflies gather here (tiles). Empty = around the trees.
@export var firefly_spots := PackedVector2Array()
@export var butterfly_colors := PackedColorArray([Color("ffffff"), Color("fdbe53"), Color("ff706d"), Color("8bb0e0"), Color("e38628")])
@export var firefly_color := Color(0.62, 1.0, 0.22)
## Size of the fireflies (1 = 3 x 3 map pixels).
@export_range(0.1, 2.0) var firefly_size := 1.0
## Koi swim in slow loops under the water around these spots (tiles, on a pond).
@export var koi_spots := PackedVector2Array()
## Koi per spot.
@export_range(0, 20) var koi_per_spot := 2
## Radius of their loops (tiles).
@export var koi_range := 1.2
## Koi colours (body); every second one also gets white patches.
@export var koi_colors := PackedColorArray([Color("f26b1d"), Color("e8392f"), Color("f6c544"), Color("f7f2e8")])
## 0..1: how many butterflies are out (day).
@export_range(0.0, 1.0) var daylight := 1.0
## 0..1: how many fireflies are out (night).
@export_range(0.0, 1.0) var night := 0.0
## 0..1: falling leaves on / off.
@export_range(0.0, 1.0) var leaves_amount := 1.0
## Snowflakes falling over the whole map (1 x 1 or 2 x 2 map pixels each).
@export_range(0, 6000) var snowflakes := 0
## 0..1: how hard it snows.
@export_range(0.0, 1.0) var snow_amount := 1.0
## Height the snow falls from (tiles above the map's base).
@export var snow_height := 7.0
## Smoke and steam, one Dictionary per source:
##   pos = Vector3 (tile x, height above the ground, tile z) on the map, or
##   node = Node3D (+ offset = Vector3 in its space): a moving source, e.g. a
##   locomotive's chimney; its puffs stay where they were puffed out.
##   rate (puffs / s, 3; may change while running, up to max_rate), max_rate
##   (puffs / s the source is built for, default rate), life (s, 3), rise (tiles over the life, 1.2),
##   size (tiles, 0.25), color (Color, alpha = opacity), on (bool, true; read
##   as each puff is born, so a source can be switched off and on).
## The wind carries the puffs (wind_direction / wind_strength of the target).
@export var smoke_sources: Array[Dictionary] = []
@export var random_seed := 1

var _mmi := {}   # kind name -> MultiMeshInstance3D
var _smoke_clock := 0.0
var _puffs: Array = []   # per smoke instance: [source index, phase, life, last birth cycle]


func _ready() -> void:
	if target != null and not target.built.is_connected(_on_built):
		target.built.connect(_on_built)
	if target != null and target.mesh_instance != null:
		rebuild()


func _on_built(_stats: Dictionary) -> void:
	rebuild()


## Re-scatters every critter over the current model.
func rebuild() -> void:
	for k in _mmi:
		(_mmi[k] as Node).queue_free()
	_mmi.clear()
	if target == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var trees: Array[Dictionary] = []
	for tr in target.get_trees():
		if not tr["cut"] and tr.get("wind", 1.0) > 0.0:
			trees.append(tr)
	var around_trees := PackedVector2Array()
	for tr in trees:
		var r: Vector3 = tr["root"]
		around_trees.append(Vector2(r.x, r.z))

	# Butterflies: two wing quads, coloured per instance.
	var spots := butterfly_spots if not butterfly_spots.is_empty() else around_trees
	var data := []
	for i in (butterflies if not spots.is_empty() else 0):
		var p := spots[rng.randi() % spots.size()] + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
		data.append([_home(p), Color(rng.randf(), 6.0 / 16.0, rng.randf_range(0.6, 1.6), rng.randf_range(0.7, 1.2)),
			butterfly_colors[rng.randi() % butterfly_colors.size()]])
	_add_kind(0, _wings_mesh(), data)

	# Fireflies: one tiny camera-facing square each.
	spots = firefly_spots if not firefly_spots.is_empty() else around_trees
	data = []
	for i in (fireflies if not spots.is_empty() else 0):
		var p := spots[rng.randi() % spots.size()] + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
		data.append([_home(p), Color(rng.randf(), 3.0 / 16.0 * firefly_size, rng.randf_range(0.4, 1.0), rng.randf_range(0.6, 1.4)),
			firefly_color.lerp(Color(1.0, 0.85, 0.2), rng.randf() * 0.5)])
	_add_kind(1, _quad_mesh(Vector2(1, 1)), data)

	# Leaves: drop from inside a canopy to the ground under it.
	data = []
	for i in (leaves if not trees.is_empty() else 0):
		var tr: Dictionary = trees[rng.randi() % trees.size()]
		var root: Vector3 = tr["root"]
		var rad: float = tr["radius"]
		var h: float = tr["height"] * rng.randf_range(0.45, 0.8)
		var p := Vector2(root.x, root.z) + Vector2(rng.randf_range(-rad, rad), rng.randf_range(-rad, rad) * 0.5)
		var home := _home(p) + Vector3(0, h, 0)
		var c: Color = tr["color"]
		data.append([home, Color(rng.randf(), 2.0 / 16.0, h + 0.02, rng.randf_range(0.7, 1.3)), c.darkened(rng.randf() * 0.15)])
	_add_kind(2, _quad_mesh(Vector2(1.0, 0.7)), data)

	# Bees: a few per hive, out by day.
	data = []
	for p in bee_spots:
		for i in bees_per_spot:
			data.append([_home(p), Color(rng.randf(), 3.0 / 16.0, rng.randf_range(0.3, 0.7), rng.randf_range(0.8, 1.3)), Color.WHITE])
	_add_kind(3, _quad_mesh(Vector2(1, 1)), data)

	# Grasshoppers: around the grass clumps, out at night.
	data = []
	var tufts := target.get_tufts()
	for i in (grasshoppers if not tufts.is_empty() else 0):
		var tp: Vector3 = tufts[rng.randi() % tufts.size()]["pos"]
		data.append([_home(Vector2(tp.x, tp.z)), Color(rng.randf(), 3.0 / 16.0, rng.randf_range(0.4, 0.8), rng.randf_range(0.7, 1.3)), Color.WHITE])
	_add_kind(4, _quad_mesh(Vector2(1, 1)), data)

	# Koi: flat pixel fish swimming in loops right at the water surface (under
	# it the tinted water would wash their colours out).
	data = []
	var n := 0
	for p in koi_spots:
		for i in koi_per_spot:
			var c: Color = koi_colors[n % koi_colors.size()]
			c.a = 1.0 if n % 2 == 0 else 0.5    # alpha 0.5 = white patches
			data.append([_home(p) + Vector3(0, 0.23, 0), Color(rng.randf(), 7.0 / 16.0, koi_range * rng.randf_range(0.6, 1.0),
				rng.randf_range(0.7, 1.2) * (1.0 if n % 2 == 0 else -1.0)), c])
			n += 1
	_add_kind(5, _quad_mesh(Vector2(1, 3.0 / 7.0)), data)

	# Snow: flakes spread over the map, each falling from snow_height in a loop.
	data = []
	var ms := target.get_map_size()
	for i in snowflakes:
		var p := Vector2(rng.randf() * ms.x, rng.randf() * ms.y)
		var home := to_local(target.to_global(target.mesh_instance.position + Vector3(p.x, 0.0, p.y)))
		data.append([home, Color(rng.randf(), (2.0 if rng.randf() < 0.25 else 1.0) / 16.0, snow_height, rng.randf_range(0.7, 1.3)),
			Color(1, 1, 1).lerp(Color(0.85, 0.9, 1.0), rng.randf())])
	_add_kind(6, _quad_mesh(Vector2(1, 1)), data)

	# Smoke: puffs per source; each moves to its source as it is born (_update_smoke).
	data = []
	_puffs.clear()
	for si in smoke_sources.size():
		var src: Dictionary = smoke_sources[si]
		var life: float = src.get("life", 3.0)
		var count := maxi(1, ceili(float(src.get("max_rate", src.get("rate", 3.0))) * life))
		for j in count:
			var ph := (float(j) + rng.randf() * 0.5) / count
			_puffs.append([si, ph, life, -1, fposmod(j * 0.618034, 1.0)])
			data.append([_smoke_origin(src), Color(ph, 0.0, float(src.get("rise", 1.2)), life),
				src.get("color", Color(0.92, 0.92, 0.92, 0.85))])
	_add_kind(7, _quad_mesh(Vector2(1, 1)), data)
	_update_smoke()
	update_params()


## Pushes pop / time-of-day state to the shaders (called every frame).
func update_params() -> void:
	if target == null:
		return
	var shown := smoothstep(0.85, 1.0, target.pop)
	var amounts := [shown * daylight, shown * night, shown * leaves_amount, shown * daylight, shown * night, shown, shown * snow_amount, shown]
	for k in _mmi:
		var mi: MultiMeshInstance3D = _mmi[k]
		var a: float = amounts[KINDS.find(k)]
		mi.visible = a > 0.001
		var m := mi.material_override as ShaderMaterial
		m.set_shader_parameter(&"amount", a)
		m.set_shader_parameter(&"wind_direction", target.wind_direction)
		m.set_shader_parameter(&"wind_strength", target.wind_strength)
		m.set_shader_parameter(&"smoke_clock", _smoke_clock)


func _process(delta: float) -> void:
	_smoke_clock += delta
	_update_smoke()
	update_params()


## Where a smoke source is now (this node's space).
func _smoke_origin(src: Dictionary) -> Vector3:
	var node = src.get("node")
	if node is Node3D and is_instance_valid(node):
		return to_local((node as Node3D).to_global(src.get("offset", Vector3.ZERO)))
	var p: Vector3 = src.get("pos", Vector3.ZERO)
	return _home(Vector2(p.x, p.z)) + Vector3(0.0, p.y, 0.0)


## Puffs born this frame start at their source, so a moving chimney leaves a
## trail behind it. The clock advances with the frames (captures repeat).
func _update_smoke() -> void:
	if not _mmi.has("smoke"):
		return
	var mm: MultiMesh = (_mmi["smoke"] as MultiMeshInstance3D).multimesh
	for i in _puffs.size():
		var pf: Array = _puffs[i]
		var cycle := floori(_smoke_clock / float(pf[2]) + float(pf[1]))
		if cycle == pf[3]:
			continue
		pf[3] = cycle
		if pf[0] >= smoke_sources.size():
			continue   # sources were replaced without a rebuild()
		var src: Dictionary = smoke_sources[pf[0]]
		# only rate / max_rate of the puffs are born (the source works harder or softer)
		var share := float(src.get("rate", 3.0)) / maxf(float(src.get("max_rate", src.get("rate", 3.0))), 0.001)
		var sz: float = float(src.get("size", 0.25)) if src.get("on", true) and float(pf[4]) < share else 0.0
		mm.set_instance_transform(i, Transform3D(Basis(), _smoke_origin(src)))
		# custom = (phase, size, rise, life); a new seed per birth varies the shape
		mm.set_instance_custom_data(i, Color(float(pf[1]), sz, float(src.get("rise", 1.2)), float(pf[2])))
		var col: Color = src.get("color", Color(0.92, 0.92, 0.92, 0.85))
		mm.set_instance_color(i, Color(col.r, col.g, col.b, col.a))


func _home(tiles: Vector2) -> Vector3:
	return to_local(target.to_global(target.tiles_to_local(tiles)))


func _add_kind(kind: int, mesh: Mesh, data: Array) -> void:
	if data.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = data.size()
	for i in data.size():
		mm.set_instance_transform(i, Transform3D(Basis(), data[i][0]))
		mm.set_instance_custom_data(i, data[i][1])
		mm.set_instance_color(i, data[i][2])
	var mi := MultiMeshInstance3D.new()
	mi.name = KINDS[kind]
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-512, -16, -512), Vector3(1024, 64, 1024))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind in [1, 6, 7] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"kind", kind)
	mi.material_override = m
	add_child(mi, false, Node.INTERNAL_MODE_FRONT)
	_mmi[KINDS[kind]] = mi


## Two wing quads on either side of the body (x), front to back along z. Unit
## size: the per-instance size (in tiles) scales it in the shader.
func _wings_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var v := [Vector3(0, 0, -0.5), Vector3(side, 0, -0.5), Vector3(side, 0, 0.5), Vector3(0, 0, 0.5)]
		# v = 0 on the leading edge (+z is forward).
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[k])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[k])
	return st.commit()


func _quad_mesh(size: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var v := [Vector3(-h.x, -h.y, 0), Vector3(h.x, -h.y, 0), Vector3(h.x, h.y, 0), Vector3(-h.x, h.y, 0)]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[k])
		st.set_normal(Vector3.BACK)
		st.add_vertex(v[k])
	return st.commit()

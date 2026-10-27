@tool
@icon("res://addons/tobidasu/icon.svg")
class_name TobidasuWires
extends Node3D
## Thin 3D-only lines over a popped map: ropeway cables, power lines. Each wire
## sags between its two ends. They have no 2D look, so they are gone while the
## map is flat and fade in once it has popped out.
##
## Add it anywhere in the scene, point `target` at the Tobidasu3D node and fill
## `wires`; call rebuild() after changing them.

const SHADER := preload("res://addons/tobidasu/tobidasu_wires.gdshader")

@export var target: Tobidasu3D:
	set(v):
		if target != null and target.built.is_connected(_on_built):
			target.built.disconnect(_on_built)
		target = v
		if target != null and is_inside_tree() and not target.built.is_connected(_on_built):
			target.built.connect(_on_built)
## One Dictionary per wire:
##   a, b = Vector3 (tile x, height above the ground there, tile z): the ends,
##   sag (tiles the middle hangs below the straight line, 0.08),
##   width (map pixels, 1), color (Color, dark grey).
@export var wires: Array[Dictionary] = []
## Pieces per wire.
@export_range(2, 64) var segments := 24

var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _ends: Array = []   # per wire: [a, b, sag] in this node's space


func _ready() -> void:
	if target != null and not target.built.is_connected(_on_built):
		target.built.connect(_on_built)
	if target != null and target.mesh_instance != null:
		rebuild()


func _on_built(_stats: Dictionary) -> void:
	rebuild()


func rebuild() -> void:
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mi.material_override = _mat
		add_child(_mi, false, Node.INTERNAL_MODE_FRONT)
	_ends.clear()
	if target == null or wires.is_empty():
		_mi.mesh = null
		return
	var verts := PackedVector3Array()
	var cust := PackedFloat32Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for w in wires:
		var a := _point(w["a"])
		var b := _point(w["b"])
		var sag: float = w.get("sag", 0.08)
		_ends.append([a, b, sag])
		var half := float(w.get("width", 1.0)) / 32.0
		var col: Color = w.get("color", Color(0.16, 0.15, 0.16))
		for k in segments + 1:
			var u := float(k) / segments
			var p := _sagged(a, b, sag, u)
			var tan := _sagged(a, b, sag, minf(u + 0.01, 1.0)) - _sagged(a, b, sag, maxf(u - 0.01, 0.0))
			for side in [-1.0, 1.0]:
				verts.append(p)
				cust.append_array([tan.x, tan.y, tan.z, side * half])
				cols.append(col)
			if k > 0:
				var i := verts.size() - 4
				idx.append_array([i, i + 1, i + 3, i, i + 3, i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_CUSTOM0] = cust
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
	mesh.custom_aabb = AABB(Vector3(-512, -16, -512), Vector3(1024, 64, 1024))
	_mi.mesh = mesh
	_update()


## Point at 0..1 along wire `i` (this node's space), e.g. where a cable car hangs.
func point_on(i: int, u: float) -> Vector3:
	if i < 0 or i >= _ends.size():
		return Vector3.ZERO
	var e: Array = _ends[i]
	return _sagged(e[0], e[1], e[2], clampf(u, 0.0, 1.0))


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if _mi == null or target == null:
		return
	var amount := smoothstep(0.85, 1.0, target.pop)
	_mi.visible = amount > 0.001 and _mi.mesh != null
	_mat.set_shader_parameter(&"amount", amount)


func _point(p: Vector3) -> Vector3:
	return to_local(target.to_global(target.tiles_to_local(Vector2(p.x, p.z)))) + Vector3(0.0, p.y, 0.0)


static func _sagged(a: Vector3, b: Vector3, sag: float, u: float) -> Vector3:
	return a.lerp(b, u) - Vector3(0.0, sag * 4.0 * u * (1.0 - u), 0.0)

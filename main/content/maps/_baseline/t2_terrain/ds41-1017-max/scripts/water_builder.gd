class_name WaterBuilder
extends Node3D

## Parametric river surface, lip pool, plunge pool and waterfall curtain.

var field: TerrainField
var material: Material

func build(f: TerrainField, mat: Material) -> void:
	field = f
	material = mat
	_river_section(-1600.0, TerrainField.LIP_Z)
	_river_section(TerrainField.POOL_Z, 1600.0)
	_pool()
	_lip_pool()

func _river_section(z0: float, z1: float) -> void:
	var cols := 7
	var rows := int((z1 - z0) / 5.0) + 1
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols_arr := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(rows * cols)
	uvs.resize(rows * cols)
	cols_arr.resize(rows * cols)
	for r in rows:
		var z: float = lerp(z0, z1, float(r) / float(rows - 1))
		var cx := field.river_x(z)
		var dx := field.river_dx(z)
		var nrm := Vector3(1.0, 0.0, -dx).normalized()
		var w := field.river_halfwidth(z) * 2.12
		var y := field.water_level(z) + 0.10
		for c in cols:
			var t := float(c) / float(cols - 1) * 2.0 - 1.0
			var yy := y + 0.06 * (1.0 - t * t)
			verts[r * cols + c] = Vector3(cx, yy, z) + nrm * (t * w * 0.5)
			uvs[r * cols + c] = Vector2((t + 1.0) * 0.5, z * 0.012)
			cols_arr[r * cols + c] = Color(0.0, 0.0, 0.0, 1.0)
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			var b := a + 1
			var d := a + cols
			var e := d + 1
			idx.append(a); idx.append(d); idx.append(b)
			idx.append(b); idx.append(d); idx.append(e)
	_commit(verts, uvs, cols_arr, idx, "river_%d" % int(z0))

func _pool() -> void:
	var cx := field.river_x(TerrainField.POOL_Z)
	var cz := TerrainField.POOL_Z
	var cy := field.water_level(cz) + 0.12
	var rings := 10
	var seg := 48
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols_arr := PackedColorArray()
	var idx := PackedInt32Array()
	for r in rings + 1:
		var rad := 108.0 * pow(float(r) / float(rings), 0.85)
		for s in seg:
			var a := TAU * float(s) / float(seg)
			verts.append(Vector3(cx + cos(a) * rad, cy, cz + sin(a) * rad))
			uvs.append(Vector2(cos(a) * 0.5 + 0.5, sin(a) * 0.5 + 0.5) * rad * 0.05)
			cols_arr.append(Color(1.0, 0.0, 0.0, 1.0))
	for r in rings:
		for s in seg:
			var a := r * seg + s
			var b := r * seg + (s + 1) % seg
			var c := (r + 1) * seg + s
			var d := (r + 1) * seg + (s + 1) % seg
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)
	_commit(verts, uvs, cols_arr, idx, "plunge_pool")

func _lip_pool() -> void:
	var cx := field.river_x(TerrainField.LIP_Z)
	var cy := field.water_level(TerrainField.LIP_Z) + 0.18
	var z0 := TerrainField.LIP_Z - 15.0
	var z1 := TerrainField.LIP_Z + 9.0
	var half := 38.0
	var cols := 7
	var rows := 7
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in rows:
		var z: float = lerp(z0, z1, float(r) / float(rows - 1))
		for c in cols:
			var u := float(c) / float(cols - 1) * 2.0 - 1.0
			verts.append(Vector3(cx + u * half, cy, z))
			uvs.append(Vector2((u + 1.0) * 0.5, z * 0.012))
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			var b := a + 1
			var d := a + cols
			var e := d + 1
			idx.append(a); idx.append(d); idx.append(b)
			idx.append(b); idx.append(d); idx.append(e)
	_commit(verts, uvs, PackedColorArray(), idx, "lip_pool")

func build_fall(mat: Material) -> void:
	var center := field.river_x(TerrainField.LIP_Z)
	var top := field.water_level(TerrainField.LIP_Z) + 0.05
	var bot := field.water_level(TerrainField.POOL_Z + 2.0)
	var cols := 12
	var rows := 44
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(rows * cols)
	uvs.resize(rows * cols)
	for r in rows:
		var t := float(r) / float(rows - 1)
		var y: float = lerp(top, bot, pow(t, 0.88))
		var z: float = lerp(TerrainField.LIP_Z - 2.0, TerrainField.POOL_Z + 16.0, pow(t, 0.72)) + sin(t * PI) * 7.0
		var w: float = lerp(31.0, 44.0, pow(t, 0.6))
		for c in cols:
			var u := float(c) / float(cols - 1)
			var xx: float = center + (u - 0.5) * w + sin(u * 9.0 + t * 11.0) * (1.2 + t * 2.2)
			var yy: float = y - (1.6 * (1.0 - pow(2.0 * abs(u - 0.5), 2.0)) * (1.0 - t))
			verts[r * cols + c] = Vector3(xx, yy, z)
			uvs[r * cols + c] = Vector2(u * 1.6 - 0.3, t)
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			var b := a + 1
			var d := a + cols
			var e := d + 1
			idx.append(a); idx.append(d); idx.append(b)
			idx.append(b); idx.append(d); idx.append(e)
	_commit(verts, uvs, PackedColorArray(), idx, "waterfall", mat)

func _commit(verts: PackedVector3Array, uvs: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, nm: String, mat: Material = null) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if cols.size() == verts.size():
		arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat != null else material
	mi.name = nm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
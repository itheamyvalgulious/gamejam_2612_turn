class_name TerrainBuilder
extends Node3D

## Builds the terrain as a grid of chunks from the analytic height field.
## Chunks share edge samples, so there are no cracks. Heights are kept in a
## float grid and reused for vegetation / rock placement.

var field: TerrainField
var res := 512
var chunks := 8
var half := TerrainField.EXTENT
var step := 1.0
var heights := PackedFloat32Array()
var normals := PackedVector3Array()
var meshes: Array[MeshInstance3D] = []
var material: Material

func build(f: TerrainField, resolution: int, chunk_count: int, mat: Material) -> void:
	field = f
	res = resolution
	chunks = chunk_count
	material = mat
	step = (2.0 * half) / float(res - 1)
	var t0 := Time.get_ticks_msec()
	# sample the whole field (shared edges)
	heights.resize(res * res)
	normals.resize(res * res)
	for j in res:
		var z := -half + j * step
		for i in res:
			var x := -half + i * step
			heights[j * res + i] = field.height(x, z)
	var k := 3
	for j in res:
		var j0 := maxi(j - k, 0)
		var j1 := mini(j + k, res - 1)
		for i in res:
			var i0 := maxi(i - k, 0)
			var i1 := mini(i + k, res - 1)
			var dx := (heights[j * res + i0] - heights[j * res + i1]) / (2.0 * k * step)
			var dz := (heights[j0 * res + i] - heights[j1 * res + i]) / (2.0 * k * step)
			normals[j * res + i] = Vector3(dx, 1.0, dz).normalized()

	var per := (res - 1) / chunks
	var built := 0
	for cj in chunks:
		for ci in chunks:
			var mi := _build_chunk(ci, cj, per)
			meshes.append(mi)
			built += 1
	print("[terrain] %d×%d grid, %d chunks, %.1f s" % [res, res, built, (Time.get_ticks_msec() - t0) / 1000.0])


func _build_chunk(ci: int, cj: int, per: int) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := per + 1
	verts.resize(n * n)
	norms.resize(n * n)
	uvs.resize(n * n)
	cols.resize(n * n)
	for lj in n:
		var gj := cj * per + lj
		var z := -half + gj * step
		for li in n:
			var gi := ci * per + li
			var x := -half + gi * step
			var k := gj * res + gi
			verts[lj * n + li] = Vector3(x, heights[k], z)
			norms[lj * n + li] = normals[k]
			uvs[lj * n + li] = Vector2(x, z) * 0.02
			var hh := heights[k]
			var d := field.river_dist(x, z)
			var hw := field.river_halfwidth(z)
			var wet := smoothstep(hw * 5.0, hw * 0.75, d)
			var lake := smoothstep(235.0, 165.0, Vector2(x + 553.0, z + 1052.0).length())
			wet = maxf(wet, lake)
			if hh > field.water_level(z) + 8.0:
				wet *= 0.35
			cols[lj * n + li] = Color(wet, 0.0, 0.0, 1.0)
	idx.resize(per * per * 6)
	var w := 0
	for lj in per:
		for li in per:
			var a := lj * n + li
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = c
			idx[w + 3] = b; idx[w + 4] = d; idx[w + 5] = c
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.name = "terrain_%d_%d" % [ci, cj]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# tighten the AABB so culling works
	var aabb := AABB(Vector3(-half + ci * per * step, 0.0, -half + cj * per * step),
		Vector3(per * step, 1.0, per * step))
	for lj in n:
		for li in n:
			var p := verts[lj * n + li]
			aabb = aabb.expand(p)
	mi.custom_aabb = aabb
	add_child(mi)
	return mi


func sample_height(x: float, z: float) -> float:
	var fx := (x + half) / step
	var fz := (z + half) / step
	var i := clampi(int(floor(fx)), 0, res - 2)
	var j := clampi(int(floor(fz)), 0, res - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var h00 := heights[j * res + i]
	var h10 := heights[j * res + i + 1]
	var h01 := heights[(j + 1) * res + i]
	var h11 := heights[(j + 1) * res + i + 1]
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)


func sample_normal(x: float, z: float) -> Vector3:
	var e := maxf(step, 1.0)
	var hl := sample_height(x - e, z)
	var hr := sample_height(x + e, z)
	var hd := sample_height(x, z - e)
	var hu := sample_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func sample_slope(x: float, z: float) -> float:
	return 1.0 - sample_normal(x, z).y
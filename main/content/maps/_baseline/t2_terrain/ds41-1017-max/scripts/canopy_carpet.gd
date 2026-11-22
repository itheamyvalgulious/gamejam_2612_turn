class_name CanopyCarpet
extends Node3D

## A continuous rainforest canopy surface.  Individual high-detail trees poke
## through it; from the air it reads as one dense, undulating canopy instead
## of a field of isolated blobs.

var field: TerrainField
var terrain: TerrainBuilder
var material: Material

func build(f: TerrainField, t: TerrainBuilder, mat: Material) -> void:
	field = f
	terrain = t
	material = mat
	var step := 22.0
	var n := int(3200.0 / step) + 1
	var hgt := PackedFloat32Array()
	var mask := PackedFloat32Array()
	hgt.resize(n * n)
	mask.resize(n * n)
	var noise := FastNoiseLite.new()
	noise.seed = 77113
	noise.frequency = 0.0035
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var fine := FastNoiseLite.new()
	fine.seed = 99221
	fine.frequency = 0.012
	fine.fractal_octaves = 3

	for j in n:
		for i in n:
			var x := -1600.0 + i * step
			var z := -1600.0 + j * step
			var h: float = terrain.sample_height(x, z)
			var sl: float = terrain.sample_slope(x, z)
			var warm: float = smoothstep(-380.0, -110.0, z)
			var low: float = smoothstep(430.0, 250.0, h)
			var flat: float = smoothstep(0.66, 0.33, sl)
			var m: float = warm * low * flat
			var cl: float = 0.55 + 0.45 * noise.get_noise_2d(x, z)
			m *= clampf(cl, 0.0, 1.0)
			var age: float = 0.5 + 0.5 * noise.get_noise_2d(x, z)
			var dr := field.river_dist(x, z)
			var hw := field.river_halfwidth(z)
			if dr < hw * 1.25:
				m = 0.0
			var lake := Vector2(x + 553.0, z + 1052.0).length()
			if lake < 260.0:
				m = 0.0
			mask[j * n + i] = m
			hgt[j * n + i] = h + 11.0 + 7.0 * age + 5.0 * fine.get_noise_2d(x, z) + 4.0 * fine.get_noise_2d(x * 2.6, z * 2.6) + 3.0 * noise.get_noise_2d(x * 2.0, z * 2.0)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var vmap := {}
	for j in n - 1:
		for i in n - 1:
			var m0 := mask[j * n + i]
			var m1 := mask[j * n + i + 1]
			var m2 := mask[(j + 1) * n + i]
			var m3 := mask[(j + 1) * n + i + 1]
			if minf(minf(m0, m1), minf(m2, m3)) < 0.18:
				continue
			var ids := []
			for k in 4:
				var ii := i + (k % 2)
				var jj := j + (k >> 1)
				var key := jj * n + ii
				if not vmap.has(key):
					var x := -1600.0 + ii * step
					var z := -1600.0 + jj * step
					var y := hgt[key]
					var hl := hgt[jj * n + maxi(ii - 1, 0)]
					var hr := hgt[jj * n + mini(ii + 1, n - 1)]
					var hd := hgt[maxi(jj - 1, 0) * n + ii]
					var hu := hgt[mini(jj + 1, n - 1) * n + ii]
					var nm := Vector3((hl - hr) / (2.0 * step), 1.0, (hd - hu) / (2.0 * step)).normalized()
					vmap[key] = verts.size()
					verts.append(Vector3(x, y, z))
					norms.append(nm)
					uvs.append(Vector2(x, z) * 0.03)
					var age: float = 0.5 + 0.5 * noise.get_noise_2d(x, z)
					cols.append(Color(mask[key], age, fine.get_noise_2d(x, z) * 0.5 + 0.5, 1.0))
				ids.append(vmap[key])
			idx.append(ids[0]); idx.append(ids[1]); idx.append(ids[2])
			idx.append(ids[1]); idx.append(ids[3]); idx.append(ids[2])

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
	mi.name = "CanopyCarpet"
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	print("[canopy] ", verts.size(), " verts")
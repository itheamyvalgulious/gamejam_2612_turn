class_name Backdrop
extends Node3D

## Non-playable distant mountain ring outside the 10.24 km² map.
## Hides the world edge and gives the valley a believable horizon.

func build(mat: Material) -> void:
	var seg := 220
	var rings := 26
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var noise := FastNoiseLite.new()
	noise.seed = 31337
	noise.frequency = 0.00065
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 5
	var detail := FastNoiseLite.new()
	detail.seed = 555
	detail.frequency = 0.003
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 4

	var hs := PackedFloat32Array()
	hs.resize((rings + 1) * seg)
	for j in rings + 1:
		var t := float(j) / float(rings)
		var r: float = 2700.0 + 7000.0 * pow(t, 1.3)
		for i in seg:
			var a := TAU * float(i) / float(seg)
			var x := cos(a) * r
			var z := sin(a) * r
			var rise: float = smoothstep(2700.0, 3800.0, r)
			var base: float = -30.0 + 260.0 * rise
			var n := noise.get_noise_2d(x, z)
			var h: float = base + rise * (130.0 * n + 70.0 * detail.get_noise_2d(x, z) + 40.0)
			h *= smoothstep(0.0, 0.20, t)
			hs[j * seg + i] = h
			verts.append(Vector3(x, h, z))
			uvs.append(Vector2(float(i) / float(seg), t))
			cols.append(Color(t, 0.0, 0.0, 1.0))
	for j in rings:
		for i in seg:
			var a := j * seg + i
			var b := j * seg + (i + 1) % seg
			var c := (j + 1) * seg + i
			var d := (j + 1) * seg + (i + 1) % seg
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)
	# normals from the height grid
	for j in rings + 1:
		for i in seg:
			var im := (i - 1 + seg) % seg
			var ip := (i + 1) % seg
			var jm := maxi(j - 1, 0)
			var jp := mini(j + 1, rings)
			var r0: float = 2700.0 + 7000.0 * pow(float(j) / float(rings), 1.3)
			var r1: float = 2700.0 + 7000.0 * pow(float(jp) / float(rings), 1.3)
			var r2: float = 2700.0 + 7000.0 * pow(float(jm) / float(rings), 1.3)
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(ip) / float(seg)
			var a2 := TAU * float(im) / float(seg)
			var pa := Vector3(cos(a0) * r0, hs[j * seg + i], sin(a0) * r0)
			var pb := Vector3(cos(a1) * r0, hs[j * seg + ip], sin(a1) * r0)
			var pc := Vector3(cos(a2) * r0, hs[j * seg + im], sin(a2) * r0)
			var pd := Vector3(cos(a0) * r1, hs[jp * seg + i], sin(a0) * r1)
			var pe := Vector3(cos(a0) * r2, hs[jm * seg + i], sin(a0) * r2)
			var n1 := (pb - pa).cross(pd - pa)
			var n2 := (pc - pa).cross(pe - pa)
			var nn := (n1 + n2).normalized()
			norms.append(nn)

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
	mi.name = "BackdropRing"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	print("[backdrop] ", verts.size(), " verts")
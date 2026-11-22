class_name DetailScenes
extends Node3D

## Hand-placed close-up detail: local high-resolution terrain patches and
## layered rock outcrops.  These only matter within a few metres, so they are
## small, fixed props with a visibility range.

var field: TerrainField
var terrain: TerrainBuilder
var detail_mat: Material
var rock_mat: Material
var rock_face_mat: Material
var foam_mat: Material
var boulder_mesh: ArrayMesh

var rock_center := Vector3(-420.0, 0.0, -180.0)
var close_face_origin := Vector3.ZERO
var tree_pos := Vector3(-62.0, 0.0, 760.0)
var snow_center := Vector3(-750.0, 0.0, -952.0)
var water_center := Vector3(0.0, 0.0, 750.0)

func build(f: TerrainField, t: TerrainBuilder, dmat: Material, rmat: Material, foam: Material, fm: Material = null) -> void:
	field = f
	terrain = t
	detail_mat = dmat
	rock_mat = rmat
	rock_face_mat = fm
	foam_mat = foam
	boulder_mesh = _make_boulder_mesh(77)
	# rock close-up
	# the ground patch is not needed under the baked face: the face itself is
	# the subject, and its coarse triangulation poked through the recesses

	# _rock_wall(Vector3(-420.0, 0.0, -181.0), 15.0, 20.0, 2.4, 31)
	close_face_origin = _baked_rock_face(Vector3(-420.0, 0.0, -179.30))
	_layered_rock(Vector3(-429.0, 0.0, -179.0), 2.6, 7.0, 1.3, 12)
	_layered_rock(Vector3(-411.0, 0.0, -179.5), 2.1, 5.0, 2.1, 13)
	# scree at the foot of the wall: kept behind the close-up cameras
	for i in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = 700 + i
		var px := -427.0 + rng.randf_range(0.0, 14.0)
		var pz := -177.15 + rng.randf_range(0.0, 3.2)
		var py: float = terrain.sample_height(px, pz)
		var s := rng.randf_range(0.22, 1.1)
		if OS.get_environment("NO_BOULDER") == "":
			_add_boulder(px, py + s * 0.22, pz, s, rng)
	# forest close-up ground
	_patch(Vector3(-62.0, 0.0, 762.0), "ground", 36.0, 0.22)
	# snow close-up micro-sastrugi
	_patch(Vector3(-750.0, 0.0, -952.0), "snow", 36.0, 0.22)
	var snow_rock: float = terrain.sample_height(-748.0, -954.0)
	_add_boulder(-748.0, snow_rock + 0.35, -954.0, 0.85, RandomNumberGenerator.new())
	# river bank gravel
	_patch(Vector3(-105.0, 0.0, 760.0), "gravel", 32.0, 0.22)
	_patch(Vector3(-160.0, 0.0, 760.0), "gravel", 26.0, 0.22)
	# river boulders and whitewater at the close-up
	for i in 3:
		var wz := 756.0 + float(i) * 8.0
		var wx: float = field.river_x(wz) + (2.5 if i == 1 else -2.0)
		var wl: float = field.water_level(wz)
		var sz := 1.4 + 0.4 * float(i)
		var rr := RandomNumberGenerator.new()
		rr.seed = 800 + i
		_add_boulder(wx, wl - sz * 0.55, wz, sz, rr)

	# plunge pool whitewater
	# impact foam is drawn by the water shader
	print("[detail] patches + outcrops")

func _patch(center: Vector3, kind: String, size: float, step: float) -> void:
	var n := int(size / step) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var nz := FastNoiseLite.new()
	nz.seed = 4242 + (0 if kind == "rock" else 1)
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 1.8
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 4
	var w := FastNoiseLite.new()
	w.seed = 991
	w.frequency = 0.45
	w.fractal_octaves = 3
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			var x := center.x - size * 0.5 + i * step
			var z := center.z - size * 0.5 + j * step
			var h: float = terrain.sample_height(x, z)
			var micro := 0.0
			if kind == "snow":
				var warp := w.get_noise_2d(x, z) * 1.5
				micro = 0.085 * sin((x * 0.82 + z * 0.42) * TAU / 1.25 + warp) + 0.025 * nz.get_noise_2d(x, z)
			elif kind == "ground":
				micro = 0.035 * nz.get_noise_2d(x, z) + 0.015 * nz.get_noise_2d(x * 3.0, z * 3.0)
			elif kind == "gravel":
				micro = 0.022 * nz.get_noise_2d(x, z) + 0.010 * nz.get_noise_2d(x * 4.0, z * 4.0)
			else:
				micro = 0.045 * nz.get_noise_2d(x, z) + 0.02 * nz.get_noise_2d(x * 3.5, z * 3.5)
			# sink the patch border below the coarse terrain to hide the seam
			var edge := minf(minf(i, n - 1 - i), minf(j, n - 1 - j)) * step
			var sink := 1.2 * (1.0 - smoothstep(0.0, 2.2, edge))
			hs[j * n + i] = h + micro - sink
	for j in n:
		for i in n:
			var x := center.x - size * 0.5 + i * step
			var z := center.z - size * 0.5 + j * step
			var h := hs[j * n + i]
			var hl := hs[j * n + maxi(i - 1, 0)]
			var hr := hs[j * n + mini(i + 1, n - 1)]
			var hd := hs[maxi(j - 1, 0) * n + i]
			var hu := hs[mini(j + 1, n - 1) * n + i]
			verts.append(Vector3(x, h, z))
			norms.append(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
			var wet := 0.0
			if kind == "gravel":
				wet = 0.9
			cols.append(Color(wet, 0.0, 0.0, 1.0))
	var w2 := n - 1
	for j in w2:
		for i in w2:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx.append(a); idx.append(b); idx.append(c)
			idx.append(b); idx.append(d); idx.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = detail_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 80.0
	mi.visibility_range_end_margin = 20.0
	add_child(mi)

func _layered_rock(center: Vector3, radius: float, height: float, angle: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var layers := 7
	var sides := 11
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var base_y: float = terrain.sample_height(center.x, center.z) - 0.7
	var rings: Array = []
	for l in layers + 1:
		var t := float(l) / float(layers)
		var row := []
		var rr := radius * (1.0 - 0.22 * t) + rng.randf_range(-0.12, 0.12)
		var yy := base_y + height * t + rng.randf_range(-0.10, 0.10)
		for s in sides:
			var a := TAU * float(s) / float(sides) + angle
			var r2 := rr * (1.0 + rng.randf_range(-0.14, 0.14))
			row.append(Vector3(center.x + cos(a) * r2, yy, center.z + sin(a) * r2 * 0.72))
		rings.append(row)
	for l in layers:
		for s in sides:
			var a: Vector3 = rings[l][s]
			var b: Vector3 = rings[l][(s + 1) % sides]
			var c: Vector3 = rings[l + 1][s]
			var d: Vector3 = rings[l + 1][(s + 1) % sides]
			for tri in [[a, b, c], [b, d, c]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var nn := (p1 - p0).cross(p2 - p0).normalized()
				if nn.y < 0.0 and absf(nn.y) > 0.6:
					nn = -nn
				var base := verts.size()
				verts.append(p0); verts.append(p1); verts.append(p2)
				norms.append(nn); norms.append(nn); norms.append(nn)
				idx.append(base); idx.append(base + 1); idx.append(base + 2)
	# fan caps
	for l in [0, layers]:
		var cyclic: Array = rings[l]
		var center_p := Vector3.ZERO
		for q in cyclic:
			center_p += q
		center_p /= float(sides)
		for s in sides:
			var p0: Vector3 = cyclic[s]
			var p1: Vector3 = cyclic[(s + 1) % sides]
			var nn := Vector3.UP if l == layers else Vector3.DOWN
			var base := verts.size()
			verts.append(center_p); verts.append(p0); verts.append(p1)
			norms.append(nn); norms.append(nn); norms.append(nn)
			idx.append(base); idx.append(base + 1); idx.append(base + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = rock_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)

func _rock_wall(center: Vector3, width: float, height: float, depth: float, seed: int) -> void:
	var cols := 44
	var rows := 60
	var base_y: float = terrain.sample_height(center.x, center.z) - 0.4
	var front_z: float = center.z + depth * 0.5
	var back_z: float = center.z - depth * 0.5
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var vcount := (cols + 1) * (rows + 1)
	verts.resize(vcount)
	norms.resize(vcount)
	var x0 := center.x - width * 0.5
	var y0 := base_y
	for r in rows + 1:
		var y := y0 + height * float(r) / float(rows)
		for c in cols + 1:
			var x := x0 + width * float(c) / float(cols)
			var edge := smoothstep(0.0, 1.4, minf(x - x0, x0 + width - x))
			edge *= smoothstep(0.0, 1.4, minf(y - y0, y0 + height - y))
			var z := front_z + _wall_relief(x, y, seed) * edge
			var vi := r * (cols + 1) + c
			verts[vi] = Vector3(x, y, z)
			var e := 0.035
			var zx := (_wall_relief(x + e, y, seed) - _wall_relief(x - e, y, seed)) / (2.0 * e)
			var zy := (_wall_relief(x, y + e, seed) - _wall_relief(x, y - e, seed)) / (2.0 * e)
			norms[vi] = Vector3(-zx * edge, -zy * edge, 1.0).normalized()
	for r in rows:
		for c in cols:
			var a := r * (cols + 1) + c
			var b := a + 1
			var cc := a + cols + 1
			var d := cc + 1
			idx.append(a); idx.append(b); idx.append(cc)
			idx.append(b); idx.append(d); idx.append(cc)
	# left / right / top sides
	var lf0 := Vector3(center.x - width * 0.5, base_y, front_z)
	var lf1 := Vector3(center.x - width * 0.5, base_y + height, front_z)
	var lb0 := Vector3(center.x - width * 0.5, base_y, back_z)
	var lb1 := Vector3(center.x - width * 0.5, base_y + height, back_z)
	var rf0 := Vector3(center.x + width * 0.5, base_y, front_z)
	var rf1 := Vector3(center.x + width * 0.5, base_y + height, front_z)
	var rb0 := Vector3(center.x + width * 0.5, base_y, back_z)
	var rb1 := Vector3(center.x + width * 0.5, base_y + height, back_z)
	_quad(verts, norms, idx, lf0, lf1, lb1, lb0, Vector3(-1, 0, 0))
	_quad(verts, norms, idx, rf0, rf1, rb1, rb0, Vector3(1, 0, 0))
	_quad(verts, norms, idx, lf1, rf1, rb1, lb1, Vector3(0, 1, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = rock_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)

func _raw_tex(path: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img)


func _baked_rock_face(center: Vector3) -> Vector3:
	## Offline-baked cliff face (tools/gen_rockface.py): 6.4 x 4.6 m height field
	## with beds, joint-bounded blocks, chipped corners, fractures and baked
	## occlusion.  Placed as a single static mesh, one material, one draw call.
	var base_y: float = terrain.sample_height(center.x, center.z) - 0.25
	var mesh := RockFace.load_mesh("res://assets/meshes/rock_face.bin")
	if mesh == null:
		return center
	var mi := MeshInstance3D.new()
	mi.name = "CloseRockFace"
	mi.mesh = mesh
	mi.material_override = rock_face_mat
	mi.position = Vector3(center.x, base_y, center.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 90.0
	mi.visibility_range_end_margin = 20.0
	add_child(mi)
	print("[rock] baked face placed at ", mi.position, " surfaces=", mesh.get_surface_count())
	return Vector3(center.x, base_y, center.z)

func _wall_relief(x: float, y: float, seed: int) -> float:
	var sx := float(seed) * 0.37
	var sy := float(seed) * 0.19
	var z := 0.0
	# stacked sedimentary layers with sharp undercuts, broken by vertical faults
	var fid := floorf(x / 3.4)
	var lh := 0.37 + 0.10 * _hash2(fid, 4.7)
	var ly := (y + 0.08 * _hash2(fid, 9.1)) / lh
	var li := floorf(ly)
	var lf := ly - li
	var h1 := _hash2(li, sx)
	var h2 := _hash2(li + 7.0, sy)
	z += 0.10 * h1 + 0.05 * h2
	z -= 0.20 * smoothstep(0.76, 0.97, lf) * (0.55 + 0.45 * h1)   # undercut
	z += 0.07 * (1.0 - lf)                                        # base bulge
	# per-column block offsets (0.7 m blocks)
	var cx := floorf(x / 0.72)
	z += 0.055 * _hash2(cx, li * 1.7 + sx)
	# vertical fractures
	var c1: float = absf(sin(x * 1.05 + 0.55 * sin(y * 0.8 + sy) + sx))
	z -= 0.24 * pow(maxf(0.0, 1.0 - c1), 6.0)
	var c2: float = absf(sin(x * 2.55 + 1.1 + 0.4 * sin(y * 1.6 + sx)))
	z -= 0.12 * pow(maxf(0.0, 1.0 - c2), 8.0)
	# pitting
	z -= 0.045 * pow(maxf(0.0, sin(x * 13.7 + y * 9.1 + seed)), 6.0)
	return z


func _hash2(a: float, b: float) -> float:
	return fposmod(sin(a * 127.1 + b * 311.7) * 43758.5453, 1.0)

func _quad(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	var base := verts.size()
	for q in [p0, p1, p2, p3]:
		verts.append(q)
		norms.append(n)
	idx.append(base); idx.append(base + 1); idx.append(base + 2)
	idx.append(base); idx.append(base + 2); idx.append(base + 3)

func _foam_ring(center: Vector3, r0: float, r1: float, mat: Material) -> void:
	var seg := 48
	var rings := 5
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in rings:
		var rad: float = lerp(r0, r1, float(r) / float(rings - 1))
		for s in seg:
			var a := TAU * float(s) / float(seg)
			verts.append(Vector3(center.x + cos(a) * rad, center.y, center.z + sin(a) * rad))
			uvs.append(Vector2(cos(a) * rad / r1 * 0.5 + 0.5, sin(a) * rad / r1 * 0.5 + 0.5))
	for r in rings - 1:
		for s in seg:
			var a := r * seg + s
			var b := r * seg + (s + 1) % seg
			var c := (r + 1) * seg + s
			var d := (r + 1) * seg + (s + 1) % seg
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _foam_disc(center: Vector3, radius: float, mat: Material) -> void:
	var seg := 56
	var rings := 8
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in rings + 1:
		var rad := radius * float(r) / float(rings)
		for s in seg:
			var a := TAU * float(s) / float(seg)
			verts.append(Vector3(center.x + cos(a) * rad, center.y, center.z + sin(a) * rad))
			uvs.append(Vector2(cos(a) * rad / radius * 0.5 + 0.5, sin(a) * rad / radius * 0.5 + 0.5))
	for r in rings:
		for s in seg:
			var a := r * seg + s
			var b := r * seg + (s + 1) % seg
			var c := (r + 1) * seg + s
			var d := (r + 1) * seg + (s + 1) % seg
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _make_boulder_mesh(seed: int) -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 1.7
	n.fractal_octaves = 3
	var lat := 10
	var lon := 16
	var pts: Array = []
	for j in lat + 1:
		var v := float(j) / float(lat)
		var phi := v * PI
		var row: Array = []
		for i in lon:
			var th := TAU * float(i) / float(lon)
			var p := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var d := 1.0 + 0.24 * n.get_noise_3d(p.x, p.y, p.z) + 0.08 * n.get_noise_3d(p.x * 3.0, p.y * 3.0, p.z * 3.0)
			row.append(p * d)
		pts.append(row)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in lat:
		for i in lon:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][(i + 1) % lon]
			var c: Vector3 = pts[j + 1][i]
			var d: Vector3 = pts[j + 1][(i + 1) % lon]
			for tri in [[a, c, b], [b, c, d]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var base := verts.size()
				verts.append(p0); verts.append(p1); verts.append(p2)
				norms.append(p0.normalized()); norms.append(p1.normalized()); norms.append(p2.normalized())
				idx.append(base); idx.append(base + 1); idx.append(base + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _add_boulder(px: float, py: float, pz: float, s: float, rng: RandomNumberGenerator) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = boulder_mesh
	mi.material_override = rock_mat
	mi.position = Vector3(px, py, pz)
	mi.scale = Vector3(s * rng.randf_range(0.8, 1.3), s * rng.randf_range(0.55, 1.0), s * rng.randf_range(0.8, 1.3))
	mi.rotation.y = rng.randf_range(0.0, TAU)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


func _chip_mesh(seed: int, subdiv: int = 1) -> ArrayMesh:
	## Angular rock chip: jittered icosphere, flat shaded so every triangle is
	## a facet that catches light.  ~80 tris - cheap enough to instance hundreds.
	var t := (1.0 + sqrt(5.0)) * 0.5
	var base := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	for i in base.size():
		base[i] = (base[i] as Vector3).normalized()
	for s in subdiv:
		var nf := []
		for f in faces:
			var a: Vector3 = base[f[0]]
			var b: Vector3 = base[f[1]]
			var c: Vector3 = base[f[2]]
			var ab := (a + b).normalized()
			var bc := (b + c).normalized()
			var ca := (c + a).normalized()
			var ia := base.size(); base.append(ab)
			var ib := base.size(); base.append(bc)
			var ic := base.size(); base.append(ca)
			nf.append([f[0], ia, ic])
			nf.append([f[1], ib, ia])
			nf.append([f[2], ic, ib])
			nf.append([ia, ib, ic])
		faces = nf
	var nz := FastNoiseLite.new()
	nz.seed = seed
	nz.frequency = 1.9
	nz.fractal_octaves = 3
	var pts := PackedVector3Array()
	for p in base:
		var d := 1.0 + 0.30 * nz.get_noise_3d(p.x * 1.4, p.y * 1.4, p.z * 1.4)
		pts.append(p * d)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for f in faces:
		var a: Vector3 = pts[f[0]]
		var b: Vector3 = pts[f[1]]
		var c: Vector3 = pts[f[2]]
		var nn := (b - a).cross(c - a)
		if nn.length() < 1e-6:
			continue
		nn = nn.normalized()
		var shade := 0.86 + 0.28 * rng.randf()
		var b0 := verts.size()
		for q in [a, b, c]:
			verts.append(q)
			norms.append(nn)
			cols.append(Color(shade, shade, shade, 1.0))
		idx.append(b0); idx.append(b0 + 1); idx.append(b0 + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _rock_debris(origin: Vector3, seed: int) -> void:
	## Chips and slabs packed into the face: the crisp edges a height field
	## cannot hold.  One MultiMesh per shape -> one draw call each.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var shapes: Array = []
	for i in 3:
		shapes.append(_chip_mesh(seed + i * 17, 2))
	for si in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = shapes[si]
		var count: int = [430, 210, 70][si]
		mm.instance_count = count
		for i in count:
			var px := rng.randf_range(-3.15, 3.15)
			var py := rng.randf_range(0.02, 4.55)
			var sz := 0.0
			if si == 0:
				sz = rng.randf_range(0.045, 0.11)
			elif si == 1:
				sz = rng.randf_range(0.10, 0.22)
			else:
				sz = rng.randf_range(0.20, 0.42)
			var depth := -sz * rng.randf_range(0.45, 0.80)
			var b := Basis()
			b = b.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
			b = b.rotated(Vector3.RIGHT, rng.randf_range(-0.5, 0.5))
			b = b.rotated(Vector3.FORWARD, rng.randf_range(-0.5, 0.5))
			b = b.scaled(Vector3(sz * rng.randf_range(0.75, 1.25),
					sz * rng.randf_range(0.55, 1.0), sz * rng.randf_range(0.35, 0.7)))
			var xf := Transform3D(b, origin + Vector3(px, py, depth))
			mm.set_instance_transform(i, xf)
			var v := rng.randf_range(0.72, 1.15)
			mm.set_instance_color(i, Color(v * rng.randf_range(0.95, 1.05), v, v * rng.randf_range(0.95, 1.04), 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "RockDebris%d" % si
		mmi.multimesh = mm
		mmi.material_override = rock_face_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 90.0
		add_child(mmi)
	print("[rock] debris instances: ", 430 + 210 + 70)

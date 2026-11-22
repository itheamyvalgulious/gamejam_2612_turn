class_name WaterBuilder
extends Node3D

## Parametric river surface, lip pool, plunge pool and waterfall curtain.

var field: TerrainField
var material: Material
var plunge_center := Vector3.ZERO

func build(f: TerrainField, mat: Material) -> void:
	field = f
	material = mat
	_river_section(-1600.0, TerrainField.LIP_Z)
	_river_section(TerrainField.POOL_Z, 1600.0)
	_pool()
	_lip_pool()

func _river_section(z0: float, z1: float) -> void:
	var cols := 17
	var rows := int((z1 - z0) / 1.25) + 1
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
		var slope: float = absf(field.water_level(z + 3.0) - field.water_level(z - 3.0)) / 6.0
		var rapid: float = smoothstep(0.16, 0.42, slope)
		var speed: float = clampf(slope * 6.0, 0.12, 1.0)
		for c in cols:
			var t := float(c) / float(cols - 1) * 2.0 - 1.0
			var yy := y + 0.06 * (1.0 - t * t)
			verts[r * cols + c] = Vector3(cx, yy, z) + nrm * (t * w * 0.5)
			uvs[r * cols + c] = Vector2((t + 1.0) * 0.5, z * 0.012)
			cols_arr[r * cols + c] = Color(0.0, rapid, speed, 1.0)
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
	var rings := 12
	var seg := 56
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols_arr := PackedColorArray()
	var idx := PackedInt32Array()
	# The pool never reaches upstream of the impact: clamping z here keeps the
	# disc from folding up the cliff face (it used to sample the lip water level
	# and throw a 200 m sheet across the fall).
	var z_back := -201.0
	for r in rings + 1:
		var rad := 108.0 * pow(float(r) / float(rings), 0.85)
		for s in seg:
			var a := TAU * float(s) / float(seg)
			var zz: float = maxf(cz + sin(a) * rad, z_back)
			var yy: float = field.water_level(clampf(zz, TerrainField.POOL_Z, 1600.0)) + 0.10
			verts.append(Vector3(cx + cos(a) * rad, yy, zz))
			uvs.append(Vector2(cos(a) * 0.5 + 0.5, sin(a) * 0.5 + 0.5) * rad * 0.05)
			cols_arr.append(Color(1.0, 0.45, 0.35, 1.0))
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

# ---------------------------------------------------------------------------
# Waterfall  (v2.3)
#
# The fall is no longer one cloth.  From back to front:
#   * a dark, near-opaque back wall that fills the mass of the fall so no cliff
#     shows through the gaps
#   * the main folded sheet: a waisted surface whose folds catch the sun and
#     whose bottom edge tears into fingers
#   * narrow extruded tubes (ropes) in front of it - hard silhouettes and real
#     parallax, which is what makes the water read as thick
#   * falling droplet sprites and, at the foot, a layered spray volume
# ---------------------------------------------------------------------------

var fall_top := Vector3(-228.5, 500.0, -231.0)
var fall_bot := Vector3(-203.9, 292.4, -198.0)
var fall_w_top := 27.0
var fall_w_bot := 49.0
var fall_len := 208.0
var fall_texs := {}

func _tex(path: String) -> ImageTexture:
	if fall_texs.has(path):
		return fall_texs[path]
	var t := TextureBank.load_raw(path)
	fall_texs[path] = t
	return t

func _center(t: float) -> Vector3:
	var tt := clampf(t, 0.0, 1.0)
	return Vector3(
		lerpf(fall_top.x, fall_bot.x, pow(tt, 0.92)),
		lerpf(fall_top.y, fall_bot.y, tt),
		lerpf(fall_top.z, fall_bot.z, pow(tt, 0.55)))

func _width(t: float) -> float:
	return lerpf(fall_w_top, fall_w_bot, pow(clampf(t, 0.0, 1.0), 0.75))

func _fold(u: float, t: float) -> float:
	var amp := lerpf(1.1, 3.6, t)
	return amp * (0.62 * sin(u * 3.3 + 0.6 - t * 1.1)
		+ 0.30 * sin(u * 7.1 - 1.7 + t * 2.2)
		+ 0.14 * sin(u * 13.3 + 3.1 + t * 0.7))

func _fall_uniforms(m: ShaderMaterial) -> void:
	m.set_shader_parameter("sheet_tex", _tex("res://assets/textures/fall_sheet.png"))
	m.set_shader_parameter("sheet_normal", _tex("res://assets/textures/fall_sheet_normal.png"))

func build_fall(mat: Material) -> void:
	fall_top = Vector3(field.river_x(TerrainField.LIP_Z), field.water_level(TerrainField.LIP_Z) + 0.05,
		TerrainField.LIP_Z - 1.2)
	fall_bot = Vector3(field.river_x(-198.0), field.water_level(-198.0) + 0.25, -198.0)
	fall_len = fall_top.y - fall_bot.y

	# ---------- back wall: the interior mass of the fall, dark and deep
	var back_mat := ShaderMaterial.new()
	back_mat.shader = load("res://shaders/waterfall.gdshader")
	_fall_uniforms(back_mat)
	back_mat.set_shader_parameter("mode", 1.0)
	back_mat.set_shader_parameter("alpha_gain", 1.0)
	back_mat.set_shader_parameter("tile_x", 26.0)
	back_mat.set_shader_parameter("tile_y", 30.0)
	back_mat.set_shader_parameter("flow_speed", 40.0)
	var back := _make_sheet(46, 40, 0.80, -9.0, 0.45, 2.0, 12.0)
	var bmi := MeshInstance3D.new()
	bmi.name = "FallBackWall"
	bmi.mesh = back
	bmi.material_override = back_mat
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)

	# ---------- the curtain itself: a raymarched volume
	_build_volume()

	# ---------- droplets and spray
	_build_drops()
	_build_mist()
	plunge_center = Vector3(fall_bot.x, field.water_level(-198.0), -198.0)


func _noise3d(size: int = 128, freq: float = 0.06, seed: int = 77) -> NoiseTexture3D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 2
	var t := NoiseTexture3D.new()
	t.width = size
	t.height = size
	t.depth = size
	t.seamless = true
	t.noise = n
	t.normalize = true
	return t


func _build_volume() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fall_volume.gdshader")
	mat.set_shader_parameter("noise_tex", _noise3d())
	mat.set_shader_parameter("sheet_tex", _tex("res://assets/textures/fall_sheet.png"))
	mat.set_shader_parameter("top_pt", fall_top)
	mat.set_shader_parameter("bot_pt", fall_bot)
	var lo := Vector3(-246.0, fall_bot.y - 1.5, -238.0)
	var hi := Vector3(-176.0, fall_top.y + 2.0, -184.0)
	mat.set_shader_parameter("bmin", lo)
	mat.set_shader_parameter("bmax", hi)
	mat.set_shader_parameter("sigma", 0.95)
	mat.set_shader_parameter("steps", 56.0)
	mat.set_shader_parameter("mist_gain", 0.55)
	mat.set_shader_parameter("exposure", 1.0)
	var box := BoxMesh.new()
	box.size = hi - lo
	var mi := MeshInstance3D.new()
	mi.name = "FallVolume"
	mi.mesh = box
	mi.position = (lo + hi) * 0.5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 120.0
	add_child(mi)


func _make_sheet(rows: int, cols: int, width_mul: float, depth_off: float,
		fold_mul: float, ragged: float, fade: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var vcols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(rows * cols)
	uvs.resize(rows * cols)
	vcols.resize(rows * cols)
	var eps := 0.004
	for r in rows:
		var t := float(r) / float(rows - 1)
		var c := _center(t)
		var w := _width(t) * width_mul
		for k in cols:
			var u := float(k) / float(cols - 1) * 2.0 - 1.0
			var fo := _fold(u, t) * fold_mul
			var y := c.y
			var x := c.x + u * w * 0.5
			var z := c.z + fo * width_mul + depth_off
			var i := r * cols + k
			verts[i] = Vector3(x, y, z)
			uvs[i] = Vector2((u * 0.5 + 0.5) * w, fall_top.y - y)
			# baked self-shadow from the fold slope
			var dz: float = (_fold(u + eps, t) - _fold(u - eps, t)) * fold_mul / (2.0 * eps) / maxf(w * 0.5, 0.1)
			var facing := clampf(0.62 + 0.55 * (1.0 / sqrt(1.0 + dz * dz)), 0.0, 1.0)
			# edge feather + ragged, fading bottom edge
			var edge := smoothstep(1.0, 0.55, absf(u) + 0.10 * sin(u * 19.0 + t * 7.0) * sin(u * 7.0 - 1.3))
			var edge_n := 0.75 + 0.25 * sin(u * 41.0 + t * 9.0) * sin(u * 17.0 - 2.1)
			var y_edge: float = fall_bot.y + ragged * (0.30 + 0.70 * (0.5 + 0.5 * sin(u * 23.0 + 1.7) * sin(u * 9.0 + 4.2)))
			var bot_fade := smoothstep(0.0, fade, y - y_edge)
			var a := edge * edge_n * bot_fade
			vcols[i] = Color(facing, fposmod(u * 7.0 + t * 3.0, 1.0), 0.0, clampf(a, 0.0, 1.0))
	for r in rows - 1:
		for k in cols - 1:
			var a0 := r * cols + k
			var b0 := a0 + 1
			var d0 := a0 + cols
			var e0 := d0 + 1
			idx.append(a0); idx.append(d0); idx.append(b0)
			idx.append(b0); idx.append(d0); idx.append(e0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = vcols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _smooth_normals(mesh)


func _make_ropes(count: int) -> ArrayMesh:
	## Independent water strands.  Each is a soft-edged ribbon that bulges in
	## the middle, has its own width, depth, drift and phase, is broken along
	## its length (real air gaps) and dissolves into spray before the pool.
	var rows := 170
	var cols := 7
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var vcols := PackedColorArray()
	var idx := PackedInt32Array()
	var stride := rows * cols
	verts.resize(count * stride)
	norms.resize(count * stride)
	uvs.resize(count * stride)
	vcols.resize(count * stride)
	for i2 in count:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5501 + i2 * 131
		var u := (float(i2) + rng.randf_range(-0.45, 0.45)) / float(count) * 2.0 - 1.0
		u = clampf(u, -1.0, 1.0)
		var phase := rng.randf()
		var wm := lerpf(0.10, 1.15, pow(rng.randf(), 1.8))     # half width, m
		var front := rng.randf_range(-2.5, 2.5)
		var bright := rng.randf_range(0.52, 1.12) * lerpf(1.0, 0.72, (front + 2.5) / 5.0)
		var wob := rng.randf_range(0.3, 1.0)
		var f1 := rng.randf_range(0.8, 2.4)
		var f2 := rng.randf_range(3.0, 8.0)
		var k1 := rng.randf() * TAU
		var k2 := rng.randf() * TAU
		var gapf := rng.randf_range(9.0, 22.0)
		for r in rows:
			var t := float(r) / float(rows - 1)
			var c := _center(t)
			var wfall := _width(t)
			var cx := c.x + u * wfall * 0.5 + sin(t * f2 + k2) * 0.35 * t * wob
			var cz := c.z + _fold(u, t) * 1.05 + front + cos(t * f1 + k1) * 0.5 * t * wob
			var hw := wm * (0.50 + 0.95 * t)
			# broken along the length: this is the air between falling water
			var g := 0.5 + 0.5 * sin(t * gapf + phase * 37.0)
			g = smoothstep(0.18, 0.62, g * 0.7 + 0.3 * (0.5 + 0.5 * sin(t * gapf * 2.7 + k1)))
			var a_long := 0.55 + 0.45 * g
			# the last 22 m above the pool dissolve into drops
			var above: float = c.y - fall_bot.y
			var dissolve := smoothstep(0.0, 26.0, above)
			a_long *= lerpf(0.25, 1.0, dissolve)
			for k in cols:
				var cc := float(k) / float(cols - 1) * 2.0 - 1.0
				var vi := i2 * stride + r * cols + k
				var bulge := (1.0 - cc * cc)
				verts[vi] = Vector3(cx + cc * hw, c.y, cz + bulge * hw * 0.85)
				var nrm := Vector3(cc * 1.25, 0.0, 1.0 - bulge * 0.5).normalized()
				norms[vi] = nrm
				uvs[vi] = Vector2(cc * 0.5 + 0.5, fall_top.y - c.y)
				# soft silhouette from the gaussian cross-section
				var edge := 1.0 - absf(cc)
				var soft := smoothstep(0.0, 0.55, edge)
				vcols[vi] = Color(bright, phase, cc, clampf(soft * a_long, 0.0, 1.0))
		for r in rows - 1:
			for k in cols - 1:
				var a0 := i2 * stride + r * cols + k
				var a1 := a0 + 1
				var b0 := a0 + cols
				var b1 := b0 + 1
				idx.append(a0); idx.append(b0); idx.append(a1)
				idx.append(a1); idx.append(b0); idx.append(b1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = vcols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_drops() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fall_drop.gdshader")
	mat.set_shader_parameter("drop_tex", _tex("res://assets/textures/fall_drop.png"))
	mat.set_shader_parameter("span", 34.0)
	mat.set_shader_parameter("base_y", fall_bot.y)
	mat.set_shader_parameter("drop_speed", 30.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8821
	var n := 620
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var vcols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * 4)
	uvs.resize(n * 4)
	vcols.resize(n * 4)
	for i in n:
		# most droplets live in the plunge cloud, some ride down the face
		var x: float
		var y: float
		var z: float
		if i % 5 == 0:
			var t := rng.randf_range(0.62, 1.0)
			var c := _center(t)
			x = c.x + rng.randf_range(-0.5, 0.5) * _width(t)
			y = c.y + rng.randf_range(-4.0, 2.0)
			z = c.z + rng.randf_range(2.0, 7.0)
		else:
			var a := rng.randf() * TAU
			var rr := pow(rng.randf(), 0.7) * 30.0
			x = fall_bot.x + cos(a) * rr * 1.1
			z = fall_bot.z + 5.0 + sin(a) * rr * 1.15 + rng.randf_range(-3.0, 5.0)
			y = fall_bot.y + rng.randf_range(0.0, 26.0) * (1.0 - rr / 52.0)
		var wd := rng.randf_range(0.015, 0.06) * (2.0 if rng.randf() < 0.10 else 1.0)
		var ht := rng.randf_range(0.25, 1.3)
		var c0 := Color(rng.randf_range(0.4, 1.0), rng.randf(), rng.randf_range(0.7, 1.3), rng.randf_range(0.12, 0.45))
		var base := i * 4
		verts[base] = Vector3(x - wd, y - ht, z)
		verts[base + 1] = Vector3(x + wd, y - ht, z)
		verts[base + 2] = Vector3(x + wd, y, z)
		verts[base + 3] = Vector3(x - wd, y, z)
		uvs[base] = Vector2(0, 1); uvs[base + 1] = Vector2(1, 1)
		uvs[base + 2] = Vector2(1, 0); uvs[base + 3] = Vector2(0, 0)
		for k in 4:
			vcols[base + k] = c0
		idx.append(base); idx.append(base + 1); idx.append(base + 2)
		idx.append(base); idx.append(base + 2); idx.append(base + 3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = vcols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "FallDrops"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_mist() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fall_mist.gdshader")
	mat.set_shader_parameter("mist_tex", _tex("res://assets/textures/fall_mist.png"))
	mat.set_shader_parameter("alpha", 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3391
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var vcols := PackedColorArray()
	var idx := PackedInt32Array()
	var cards: Array = []
	# the plunging cloud: stacked cards that grow with height
	for i in 18:
		var a := rng.randf() * TAU
		var rr := pow(rng.randf(), 0.7) * 30.0
		var c := Vector3(fall_bot.x + cos(a) * rr * 1.25,
			fall_bot.y + rng.randf_range(0.5, 16.0),
			fall_bot.z + 4.0 + sin(a) * rr * 0.95)
		var s := rng.randf_range(16.0, 46.0)
		cards.append([c, Vector2(s * rng.randf_range(0.8, 1.5), s), rng.randf_range(0.035, 0.095), rng.randf()])
	# a higher veil hugging the curtain
	for i in 5:
		var t := rng.randf_range(0.45, 1.0)
		var c := _center(t)
		var s := rng.randf_range(28.0, 70.0)
		cards.append([c + Vector3(rng.randf_range(-14.0, 14.0), rng.randf_range(-6.0, 10.0), rng.randf_range(3.0, 16.0)),
			Vector2(s, s * rng.randf_range(1.0, 1.7)), rng.randf_range(0.008, 0.020), rng.randf()])
	var base := 0
	for card in cards:
		var c: Vector3 = card[0]
		var sz: Vector2 = card[1]
		var al: float = card[2]
		var ph: float = card[3]
		var rot := (ph - 0.5) * 0.5
		var right := Vector3(cos(rot), sin(rot), 0.0) * sz.x * 0.5
		var up := Vector3(-sin(rot), cos(rot), 0.0) * sz.y * 0.5
		var quad := [c - right - up, c + right - up, c + right + up, c - right + up]
		for k in 4:
			verts.append(quad[k])
			uvs.append(Vector2(float(k % 2), float(k / 2)))
			vcols.append(Color(0.92 + 0.08 * ph, ph, 0.0, al))
		idx.append(base); idx.append(base + 1); idx.append(base + 2)
		idx.append(base); idx.append(base + 2); idx.append(base + 3)
		base += 4
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = vcols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "FallMist"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _smooth_normals(m: ArrayMesh) -> ArrayMesh:
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var acc := PackedVector3Array()
	acc.resize(v.size())
	for i in ix.size() / 3:
		var a := ix[i * 3]
		var b := ix[i * 3 + 1]
		var c := ix[i * 3 + 2]
		var n := (v[b] - v[a]).cross(v[c] - v[a])
		acc[a] = acc[a] + n
		acc[b] = acc[b] + n
		acc[c] = acc[c] + n
	for i in acc.size():
		var a2 := acc[i]
		acc[i] = a2.normalized() if a2.length() > 1e-8 else Vector3(0, 0, 1)
	arr[Mesh.ARRAY_NORMAL] = acc
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


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


func build_plunge(mat: Material) -> void:
	## Churning whitewater at the foot of the fall plus the foam skirt that
	## carries the impact white out over the pool surface.
	if plunge_center == Vector3.ZERO:
		return
	mat.set_shader_parameter("sheet_tex", _tex("res://assets/textures/fall_sheet.png"))
	mat.set_shader_parameter("mist_tex", _tex("res://assets/textures/fall_mist.png"))
	mat.set_shader_parameter("center", Vector2(plunge_center.x, plunge_center.z))
	mat.set_shader_parameter("radius", 11.0)
	mat.set_shader_parameter("alpha_gain", 0.62)
	var rings := 26
	var seg := 120
	var radius := 11.0
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols_arr := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize((rings + 1) * seg)
	uvs.resize((rings + 1) * seg)
	cols_arr.resize((rings + 1) * seg)
	for r in rings + 1:
		var rt := float(r) / float(rings)
		var rad := radius * pow(rt, 0.85)
		for s in seg:
			var a := TAU * float(s) / float(seg)
			var x := plunge_center.x + cos(a) * rad
			var z := plunge_center.z + sin(a) * rad * 1.18
			var y: float = field.water_level(clampf(z, TerrainField.LIP_Z + 2.0, 1600.0)) + 0.12
			y += (1.0 - rt) * 0.9
			verts[r * seg + s] = Vector3(x, y, z)
			uvs[r * seg + s] = Vector2(cos(a) * rt * 0.5 + 0.5, sin(a) * rt * 0.5 + 0.5)
			cols_arr[r * seg + s] = Color(rt, 0.0, 0.0, 1.0)
	for r in rings:
		for s in seg:
			var a0 := r * seg + s
			var b0 := r * seg + (s + 1) % seg
			var c0 := (r + 1) * seg + s
			var d0 := (r + 1) * seg + (s + 1) % seg
			idx.append(a0); idx.append(c0); idx.append(b0)
			idx.append(b0); idx.append(c0); idx.append(d0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols_arr
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "PlungeWhitewater"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	_build_foam_ring()


func _build_foam_ring() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foam_ring.gdshader")
	mat.set_shader_parameter("sheet_tex", _tex("res://assets/textures/fall_sheet.png"))
	mat.set_shader_parameter("mist_tex", _tex("res://assets/textures/fall_mist.png"))
	mat.set_shader_parameter("r_in", 10.0)
	mat.set_shader_parameter("center", Vector2(plunge_center.x, plunge_center.z))
	mat.set_shader_parameter("r_out", 108.0)
	mat.set_shader_parameter("strength", 0.0)
	var rings := 22
	var seg := 128
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize((rings + 1) * seg)
	uvs.resize((rings + 1) * seg)
	for r in rings + 1:
		var rt := float(r) / float(rings)
		var rad: float = lerpf(10.0, 62.0, pow(rt, 0.85))
		for s in seg:
			var a := TAU * float(s) / float(seg)
			var x := plunge_center.x + cos(a) * rad
			var z := plunge_center.z + sin(a) * rad * 1.15
			var y: float = field.water_level(clampf(z, TerrainField.LIP_Z + 2.0, 1600.0)) + 0.16
			verts[r * seg + s] = Vector3(x, y, z)
			uvs[r * seg + s] = Vector2(rt, float(s) / float(seg))
	for r in rings:
		for s in seg:
			var a0 := r * seg + s
			var b0 := r * seg + (s + 1) % seg
			var c0 := (r + 1) * seg + s
			var d0 := (r + 1) * seg + (s + 1) % seg
			idx.append(a0); idx.append(c0); idx.append(b0)
			idx.append(b0); idx.append(c0); idx.append(d0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "PlungeFoamRing"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
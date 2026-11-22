class_name RiverWater
extends Node3D
## water.gd — river strip + waterfall + lake for the Vale.
## Pure procedural meshes; all wave/flow motion lives in the shaders (TIME).

const RIVER_SEGS := 900    # ~3 m arc spacing so vertex waves are visible
const FALL_T_TOP := 0.555      # waterfall lip arc t
const FALL_T_BOT := 0.585      # plunge-pool arc t
const FALL_Y_TOP := 34.5       # ≈ water surface at the lip (bed+1.5)
const FALL_Y_BOT := 6.6        # ≈ water surface at the plunge pool
const RIVER_END_T := 0.80      # river merges into lake by here
const RIVER_MOUTH_T := 0.68
const RIVER_END_Y := 2.05
const LAKE_R := 285.0          # slightly inside the terrain basin (320)

const SPRAY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float m = smoothstep(1.0, 0.15, d);
	ALBEDO = COLOR.rgb * m;
	ALPHA = m * COLOR.a;
}
"""

const FOAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_prepass_alpha;

uniform float u_r0 = 3.0;
uniform float u_r1 = 12.0;

float hash21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(11.7, 3.1);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	float r = length(VERTEX.xz);
	float ring = smoothstep(u_r0, u_r0 + 3.0, r) * (1.0 - smoothstep(u_r1 - 3.0, u_r1, r));
	float n = fbm(VERTEX.xz * 0.6 + vec2(TIME * 0.7, -TIME * 0.5));
	float foam = ring * (0.35 + 0.65 * n);
	ALBEDO = mix(vec3(0.78, 0.88, 0.90), vec3(0.90, 0.96, 0.98), foam);
	ALPHA = foam * 0.85;
}
"""

var hf: HeightField
var _rlen := 0.0


func build(h: HeightField) -> void:
	hf = h
	_rlen = _river_len()
	_build_river()
	_build_falls()
	_build_lake()


func update(_dt: float, _cam_pos: Vector3) -> void:
	pass   # all motion is shader-side (TIME-driven)


# ------------------------------------------------------------- helpers ------

func _make_mat(path: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	return mat


func _river_len() -> float:
	var total := 0.0
	for i in range(hf.river_pts.size() - 1):
		total += hf.river_pts[i].distance_to(hf.river_pts[i + 1])
	return total


## Resample the smoothed spline to n+1 uniformly-arc-spaced points.
## Returns [PackedVector2Array pos, PackedFloat32Array arc, PackedFloat32Array t].
func _resample(n: int) -> Array:
	var src := hf.river_pts
	var total := _river_len()
	var pos := PackedVector2Array()
	var arc := PackedFloat32Array()
	var tt := PackedFloat32Array()
	var s := 0.0
	var si := 0
	for k in range(n + 1):
		var target: float = total * float(k) / float(n)
		while si < src.size() - 2:
			var nl: float = src[si].distance_to(src[si + 1])
			if s + nl < target:
				s += nl
				si += 1
			else:
				break
		var a: Vector2 = src[si]
		var b: Vector2 = src[si + 1]
		var segl: float = a.distance_to(b)
		var f: float = clampf((target - s) / maxf(segl, 0.0001), 0.0, 1.0)
		pos.append(a.lerp(b, f))
		arc.append(target)
		tt.append(target / maxf(total, 0.0001))
	return [pos, arc, tt]


## XZ point + tangent at arc fraction t.
func _pt_at_t(t: float) -> Dictionary:
	var src := hf.river_pts
	var target: float = clampf(t, 0.0, 1.0) * _rlen
	var s := 0.0
	for i in range(src.size() - 1):
		var a: Vector2 = src[i]
		var b: Vector2 = src[i + 1]
		var l: float = a.distance_to(b)
		if s + l >= target or i == src.size() - 2:
			var f: float = clampf((target - s) / maxf(l, 0.0001), 0.0, 1.0)
			var p: Vector2 = a.lerp(b, f)
			var tang: Vector2 = (b - a).normalized()
			if tang.length_squared() < 1e-8:
				tang = Vector2(1, 0)
			return {"p": p, "t": tang}
		s += l
	return {"p": src[src.size() - 1], "t": Vector2(1, 0)}


func _tangent_local(pts: PackedVector2Array, j: int) -> Vector2:
	var a: Vector2 = pts[clampi(j - 1, 0, pts.size() - 1)]
	var b: Vector2 = pts[clampi(j + 1, 0, pts.size() - 1)]
	var d := b - a
	if d.length_squared() < 1e-8:
		d = Vector2(1, 0)
	return d.normalized()


## Half-width (m) matching the terrain's river carve: ~14 m in the mountains
## (28 m full) widening to ~34 m (68 m full) in the lowlands, with a subtle
## sinusoidal meander term.
func _w_half(t: float, z: float) -> float:
	var jungle := smoothstep(300.0, 620.0, z)
	# slightly wider than the bed bottom so edges never show dry floor
	# mid-channel
	return lerpf(22.0, 40.0, jungle) + lerpf(2.0, 5.0, jungle) * sin(t * 31.0) * 0.4


func _river_surface_y(t: float, downstream: bool) -> float:
	# Water rides ~0.9 m above the carved bed. Terrain bed =
	# river_water_y(t) − lerp(2.8, 1.6, jungle), so surface =
	# river_water_y − lerp(1.9, 0.7, jungle).
	var jungle: float = smoothstep(300.0, 620.0, _z_at_t(t))
	var y: float = hf.river_water_y(t) - lerpf(1.9, 0.7, jungle)
	if downstream:
		if t < FALL_T_BOT:
			y = FALL_Y_BOT       # flat plunge pool between lip and basin
		if t > RIVER_MOUTH_T:
			y = lerpf(y, RIVER_END_Y, smoothstep(RIVER_MOUTH_T, RIVER_END_T, t))
		y = maxf(y, RIVER_END_Y) # never dip below lake level near the mouth
	return y


var _z_t_cache := {}

func _z_at_t(t: float) -> float:
	if t in _z_t_cache:
		return _z_t_cache[t]
	var d: Dictionary = _pt_at_t(t)
	var z: float = (d["p"] as Vector2).y
	_z_t_cache[t] = z
	return z


# --------------------------------------------------------------- river ------

func _build_river() -> void:
	var mat: ShaderMaterial = _make_mat("res://gfx/river.gdshader")
	var res: Array = _resample(RIVER_SEGS)
	var pos: PackedVector2Array = res[0]
	var arc: PackedFloat32Array = res[1]
	var tt: PackedFloat32Array = res[2]
	_river_strip(pos, arc, tt, 0.0, FALL_T_TOP, false, mat)
	_river_strip(pos, arc, tt, FALL_T_TOP, RIVER_END_T, true, mat)


func _river_strip(pos: PackedVector2Array, arc: PackedFloat32Array, tt: PackedFloat32Array,
		lo: float, hi: float, downstream: bool, mat: ShaderMaterial) -> void:
	var pts := PackedVector2Array()
	var arcs := PackedFloat32Array()
	var tts := PackedFloat32Array()
	for i in range(pos.size()):
		var t: float = tt[i]
		if t >= lo - 0.0001 and t <= hi + 0.0001:
			pts.append(pos[i])
			arcs.append(arc[i])
			tts.append(t)
	if pts.size() == 0:
		return
	# exact boundary points so upstream / falls / downstream meet cleanly
	if tts[0] > lo + 0.0001:
		var d: Dictionary = _pt_at_t(lo)
		pts.insert(0, d["p"])
		arcs.insert(0, lo * _rlen)
		tts.insert(0, lo)
	if tts[tts.size() - 1] < hi - 0.0001:
		var d2: Dictionary = _pt_at_t(hi)
		pts.append(d2["p"])
		arcs.append(hi * _rlen)
		tts.append(hi)
	var m := pts.size()
	# five columns across the strip; per-vertex terrain hug so the sheet
	# follows the carved channel smoothly (no step joints between
	# spline segments)
	const COLS := 5
	var cols_v: Array[PackedVector3Array] = []
	for c in COLS:
		cols_v.append(PackedVector3Array())
	var cols := PackedColorArray()
	for j in range(m):
		var p: Vector2 = pts[j]
		var t: float = tts[j]
		var tang: Vector2 = _tangent_local(pts, j)
		var nrm := Vector2(-tang.y, tang.x)
		var wh: float = _w_half(t, p.y)
		var y: float = _river_surface_y(t, downstream)
		for c in COLS:
			var f2 := lerpf(-1.0, 1.0, float(c) / float(COLS - 1))
			var cx := p.x + nrm.x * wh * f2
			var cz := p.y + nrm.y * wh * f2
			# every vertex hugs its own ground: inside the channel the
			# surface sits just above the bed, outside it sinks under
			# the bank so no floating sheet edge shows
			var cy := maxf(y, hf.h(cx, cz) + 0.25)
			cols_v[c].append(Vector3(cx, cy, cz))
			cols.append(Color(tang.x * 0.5 + 0.5, tang.y * 0.5 + 0.5, 0.0, 1.0))
	var mesh := _strip_mesh(m, COLS, cols_v, arcs, tts, cols)
	var mi := MeshInstance3D.new()
	mi.name = "Water_river_%s" % ("dn" if downstream else "up")
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _strip_mesh(m: int, nc: int, cols_v: Array[PackedVector3Array],
		arcs: PackedFloat32Array, tts: PackedFloat32Array, cols: PackedColorArray) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvv := PackedVector2Array()
	var uvv2 := PackedVector2Array()
	var clr := PackedColorArray()
	var idx := PackedInt32Array()
	for j in range(m):
		for c in range(nc):
			verts.append(cols_v[c][j])
			uvv.append(Vector2(float(c) / float(nc - 1), arcs[j]))
			uvv2.append(Vector2(tts[j], 0.0))
			clr.append(cols[j * nc + c])
			norms.append(Vector3.UP)
	for j in range(m - 1):
		for c in range(nc - 1):
			var a := j * nc + c
			var b := a + 1
			var d := a + nc
			var e := d + 1
			# Godot front faces are CLOCKWISE seen from above
			idx.append(a); idx.append(b); idx.append(d)
			idx.append(b); idx.append(e); idx.append(d)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvv
	arr[Mesh.ARRAY_TEX_UV2] = uvv2
	arr[Mesh.ARRAY_COLOR] = clr
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# --------------------------------------------------------------- falls ------

func _build_falls() -> void:
	var lip_d: Dictionary = _pt_at_t(FALL_T_TOP)
	var lip: Vector2 = lip_d["p"]
	var tang: Vector2 = lip_d["t"]
	var nrm := Vector2(-tang.y, tang.x)
	var wh: float = _w_half(FALL_T_TOP, lip.y)
	var mat: ShaderMaterial = _make_mat("res://gfx/falls.gdshader")
	for layer in range(3):
		var depth: float = (float(layer) - 1.0) * 1.2
		var mi := MeshInstance3D.new()
		mi.name = "Water_falls_%d" % layer
		mi.mesh = _falls_sheet(lip, tang, nrm, wh, depth)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_build_falls_foam(lip, wh)
	_build_falls_spray(lip)


func _falls_sheet(lip: Vector2, tang: Vector2, nrm: Vector2, wh: float, depth: float) -> ArrayMesh:
	var cols := 8
	var rows := 28
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var nrm3 := Vector3(nrm.x, 0.0, nrm.y)
	var tang3 := Vector3(tang.x, 0.0, tang.y)
	for r in range(rows + 1):
		var f: float = float(r) / float(rows)
		var y: float = lerpf(FALL_Y_TOP, FALL_Y_BOT, f)
		var base := Vector3(lip.x, 0.0, lip.y) + tang3 * (f * 3.0 + depth)
		for c in range(cols + 1):
			var u: float = float(c) / float(cols)
			var across: float = (u * 2.0 - 1.0) * wh
			verts.append(base + nrm3 * across + Vector3(0.0, y, 0.0))
			norms.append(tang3)
			uvs.append(Vector2(u, f))
	for r in range(rows):
		for c in range(cols):
			var a := r * (cols + 1) + c
			var b := a + 1
			var d := a + (cols + 1)
			var e := d + 1
			idx.append(a); idx.append(d); idx.append(b)
			idx.append(b); idx.append(d); idx.append(e)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _build_falls_foam(center: Vector2, wh: float) -> void:
	var shader := Shader.new()
	shader.code = FOAM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var r0 := 3.0
	var r1 := wh * 0.9
	mat.set_shader_parameter("u_r0", r0)
	mat.set_shader_parameter("u_r1", r1)
	var segs := 48
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in range(segs):
		var a0: float = TAU * float(k) / float(segs)
		var a1: float = TAU * float(k + 1) / float(segs)
		var i0 := k * 4
		verts.append(Vector3(cos(a0) * r0, 0.0, sin(a0) * r0))
		verts.append(Vector3(cos(a0) * r1, 0.0, sin(a0) * r1))
		verts.append(Vector3(cos(a1) * r0, 0.0, sin(a1) * r0))
		verts.append(Vector3(cos(a1) * r1, 0.0, sin(a1) * r1))
		norms.append(Vector3.UP); norms.append(Vector3.UP)
		norms.append(Vector3.UP); norms.append(Vector3.UP)
		idx.append(i0); idx.append(i0 + 1); idx.append(i0 + 2)
		idx.append(i0 + 2); idx.append(i0 + 1); idx.append(i0 + 3)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Water_foam"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(center.x, FALL_Y_BOT + 0.35, center.y)
	add_child(mi)


func _build_falls_spray(center: Vector2) -> void:
	var shader := Shader.new()
	shader.code = SPRAY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var ppm := ParticleProcessMaterial.new()
	ppm.direction = Vector3(0.0, 1.0, 0.0)
	ppm.spread = 25.0
	ppm.initial_velocity_min = 3.0
	ppm.initial_velocity_max = 8.0
	ppm.gravity = Vector3(0.0, -13.0, 0.0)
	ppm.scale_min = 0.35
	ppm.scale_max = 1.0
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = 3.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(0.82, 0.90, 0.95, 0.85), Color(0.82, 0.90, 0.95, 0.0)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 64
	ppm.color_ramp = gtex
	ppm.color = Color(1.0, 1.0, 1.0, 1.0)
	var qm := QuadMesh.new()
	qm.size = Vector2(2.4, 2.4)
	qm.orientation = PlaneMesh.FACE_Z
	qm.material = mat
	var gp := GPUParticles3D.new()
	gp.name = "Water_spray"
	gp.process_material = ppm
	gp.amount = 160
	gp.lifetime = 1.3
	gp.emitting = true
	gp.draw_pass_1 = qm
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.transform.origin = Vector3(center.x, FALL_Y_BOT + 0.4, center.y)
	add_child(gp)


# --------------------------------------------------------------- lake -------

func _build_lake() -> void:
	var mat: ShaderMaterial = _make_mat("res://gfx/lake.gdshader")
	mat.set_shader_parameter("u_radius", LAKE_R)
	var mi := MeshInstance3D.new()
	mi.name = "Water_lake"
	mi.mesh = _lake_mesh(LAKE_R)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lc: Vector2 = hf.lake["c"]
	var ly: float = hf.lake["y"]
	mi.position = Vector3(lc.x, ly, lc.y)
	add_child(mi)


func _lake_mesh(r: float) -> ArrayMesh:
	var rings := 16
	var segs := 96
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3(0.0, 0.0, 0.0))
	norms.append(Vector3.UP)
	for ri in range(1, rings + 1):
		var rr: float = r * float(ri) / float(rings)
		for s in range(segs):
			var a: float = TAU * float(s) / float(segs)
			verts.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
			norms.append(Vector3.UP)
	for s in range(segs):
		var a := 1 + s
		var b := 1 + ((s + 1) % segs)
		idx.append(0); idx.append(b); idx.append(a)
	for ri in range(1, rings):
		var r0 := 1 + (ri - 1) * segs
		var r1 := 1 + ri * segs
		for s in range(segs):
			var s1 := (s + 1) % segs
			var a := r0 + s
			var b := r0 + s1
			var c := r1 + s
			var d := r1 + s1
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

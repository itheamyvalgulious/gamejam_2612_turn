class_name Vegetation
extends Node3D
## Procedural flora & rock scatter.
## NEAR trees are true 3D: recursive tapered branch skeletons + volumetric leaf-card
## clusters (procedural compound-leaf / needle alpha, baked per-vertex AO, backlit SSS).
## FAR trees use cheap impostor canopies. Rocks sink into the ground; drifts/grass/
## bushes scatter by biome weights, slope, moisture, noise clustering and focus distance.

const TerrainGen := preload("res://scripts/terrain_gen.gd")

var data: TerrainGen
var focuses: Array = []

const DETAIL_R := 700.0
const FAR_R := 1700.0

var _foliage_shader: Shader
var _bark_mat: StandardMaterial3D
var _rock_mat: Material
var _snow_mat: StandardMaterial3D
var _leaf_mat: ShaderMaterial
var _needle_mat: ShaderMaterial
var _cn: FastNoiseLite
var _fn3: FastNoiseLite

func setup(d: TerrainGen, foc: Array) -> void:
	data = d
	focuses = foc
	_foliage_shader = load("res://shaders/foliage.gdshader")
	_bark_mat = StandardMaterial3D.new()
	_bark_mat.albedo_color = Color(0.16, 0.11, 0.07)
	_bark_mat.roughness = 0.95
	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = load("res://shaders/rock.gdshader")
	_snow_mat = StandardMaterial3D.new()
	_snow_mat.albedo_color = Color(0.93, 0.95, 0.99)
	_snow_mat.roughness = 0.5
	_leaf_mat = _foliage_mat(3, Color(0.05, 0.16, 0.04), Color(0.12, 0.30, 0.08), 0.6, 0.4, 0.10)
	_needle_mat = _foliage_mat(4, Color(0.045, 0.12, 0.055), Color(0.09, 0.22, 0.10), 0.6, 0.4, 0.05, 0.40)
	_cn = FastNoiseLite.new()
	_cn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cn.fractal_octaves = 3
	_cn.frequency = 0.004
	_cn.seed = 777
	_fn3 = FastNoiseLite.new()
	_fn3.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_fn3.fractal_octaves = 3
	_fn3.frequency = 1.0
	_fn3.seed = 913

	_scatter("jungle_tree", [_make_broadleaf_detail(10.0)], [_make_broadleaf(10.0)], 9.0, 40.0, 2600, 14000, Callable(self, "_pred_jungle"), 0.35, 0.05)
	_scatter("conifer", [_make_conifer_detail(11.0, 0), _make_conifer_detail(9.5, 1)], [_make_conifer(11.0, 0), _make_conifer(9.0, 1), _make_conifer(13.0, 2)], 13.0, 55.0, 2000, 5000, Callable(self, "_pred_conifer"), 0.75, 0.10)
	_scatter("rock", [_make_rock(2.6), _make_rock(1.6)], [_make_rock(2.6)], 30.0, 110.0, 3000, 1500, Callable(self, "_pred_rock"), 0.6, 0.3, 0.4)
	_scatter("grass", [_make_grass(0.9)], [_make_grass(0.9)], 3.0, 100000.0, 40000, 0, Callable(self, "_pred_grass"), 0.4, 0.0)
	_scatter("bush", [_make_bush(1.6)], [_make_bush(1.6)], 9.0, 30.0, 6000, 2000, Callable(self, "_pred_bush"), 0.5, 0.1)
	_scatter("snowdrift", [_make_drift(2.4), _make_drift(1.5)], [_make_drift(2.4)], 9.0, 40.0, 7000, 2000, Callable(self, "_pred_drift"), 0.7, 0.0, 0.5)
	_scatter("snow_bush", [_make_snowbush(1.1)], [_make_snowbush(1.1)], 7.0, 30.0, 8000, 2000, Callable(self, "_pred_snowbush"), 0.7, 0.12)
	_showcase_rocks()

## A few hand-placed boulders on open ground for deterministic close-up shots.
func _showcase_rocks() -> void:
	var spots := [
		Vector2(data.river_x(2060.0) + 75.0, 2060.0),
		Vector2(data.river_x(1940.0) - 85.0, 1940.0),
		Vector2(data.river_x(2150.0) + 60.0, 2150.0),
	]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = spots.size()
	mm.mesh = _make_rock(2.2)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "rock_show"
	mmi.multimesh = mm
	add_child(mmi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in range(spots.size()):
		var t := Transform3D()
		t.basis = Basis().rotated(Vector3.UP, rng.randf() * TAU)
		var sc := rng.randf_range(0.9, 1.3)
		t.basis = t.basis.scaled(Vector3(sc, sc * 0.8, sc))
		t.origin = Vector3(spots[i].x, data.height_at(spots[i].x, spots[i].y) - 0.5 * sc, spots[i].y)
		mm.set_instance_transform(i, t)

# ------------------------------------------------------------------ predicates
func _focus_factor(p: Vector3) -> float:
	var best := 1e9
	for f in focuses:
		best = minf(best, Vector2(p.x - f.x, p.z - f.z).length())
	return best

func _slope_at(x: float, z: float) -> float:
	return 1.0 - data.normal_at(x, z).y

func _cluster(x: float, z: float, amount: float) -> float:
	if amount <= 0.0:
		return 1.0
	var n := _cn.get_noise_2d(x, z) * 0.5 + 0.5
	return lerpf(1.0, TerrainGen.smoothstep(0.30, 0.62, n), amount)

func _pred_jungle(x: float, z: float) -> bool:
	var s := data.splat_at(x, z)
	if s.x < 0.35 or _slope_at(x, z) > 0.5 or data.height_at(x, z) > 130.0:
		return false
	return data.moist_at(x, z) > 0.35

func _pred_conifer(x: float, z: float) -> bool:
	var s := data.splat_at(x, z)
	var h := data.height_at(x, z)
	if _slope_at(x, z) > 0.7:
		return false
	if s.z > 0.3 and h < 210.0:
		return true
	if s.x > 0.3 and h > 60.0 and h < 200.0:
		return true
	return false

func _pred_rock(x: float, z: float) -> bool:
	var s := data.splat_at(x, z)
	var sl := _slope_at(x, z)
	if data.height_at(x, z) > 180.0:
		return false
	return s.y > 0.5 and sl > 0.35 and sl < 0.85

func _pred_grass(x: float, z: float) -> bool:
	var s := data.splat_at(x, z)
	return s.x > 0.4 and s.z < 0.25 and _slope_at(x, z) < 0.6

func _pred_bush(x: float, z: float) -> bool:
	var s := data.splat_at(x, z)
	return s.x > 0.3 and _slope_at(x, z) < 0.6 and data.moist_at(x, z) > 0.3

func _pred_drift(x: float, z: float) -> bool:
	var s := data.splat_at(x, z)
	return s.z > 0.45 and _slope_at(x, z) < 0.5

func _pred_snowbush(x: float, z: float) -> bool:
	var s := data.splat_at(x, z)
	return s.z > 0.3 and _slope_at(x, z) < 0.6

# ------------------------------------------------------------------ scatter
func _scatter(name: String, near_meshes: Array, far_meshes: Array, sp_detail: float, sp_far: float, cap_near: int, cap_far: int, pred: Callable, cluster: float = 0.0, tilt: float = 0.0, sink: float = 0.0) -> void:
	var near_pos: Array = []
	var far_pos: Array = []
	_collect(near_pos, sp_detail, DETAIL_R, 1.0, pred, cluster, 0.0)
	if cap_far > 0:
		_collect(far_pos, sp_far, FAR_R, 0.5, pred, cluster, DETAIL_R)
	if near_pos.size() > cap_near:
		near_pos.resize(cap_near)
	if far_pos.size() > cap_far:
		far_pos.resize(cap_far)
	var rng := RandomNumberGenerator.new()
	rng.seed = (name.hash() & 0x7fffffff)
	_build_mm(name + "_n", near_meshes, near_pos, rng, tilt, sink)
	if cap_far > 0:
		_build_mm(name + "_f", far_meshes, far_pos, rng, tilt, sink)

func _build_mm(name: String, meshes: Array, positions: Array, rng: RandomNumberGenerator, tilt: float, sink: float) -> void:
	if positions.is_empty() or meshes.is_empty():
		return
	var buckets: Array = []
	for i in range(meshes.size()):
		buckets.push_back([])
	for p in positions:
		buckets[rng.randi_range(0, meshes.size() - 1)].push_back(p)
	for vi in range(meshes.size()):
		var ps: Array = buckets[vi]
		if ps.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = ps.size()
		mm.mesh = meshes[vi]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_v%d" % [name, vi]
		mmi.multimesh = mm
		add_child(mmi)
		for i in range(ps.size()):
			var p: Vector3 = ps[i]
			var t := Transform3D()
			t.basis = Basis().rotated(Vector3.UP, rng.randf() * TAU)
			if tilt > 0.0:
				var ax := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
				t.basis = t.basis.rotated(ax, rng.randf_range(-tilt, tilt))
			var sc := rng.randf_range(0.6, 1.55)
			t.basis = t.basis.scaled(Vector3(sc * rng.randf_range(0.85, 1.15), sc * rng.randf_range(0.8, 1.2), sc * rng.randf_range(0.85, 1.15)))
			t.origin = p - Vector3(0.0, sink * sc, 0.0)
			mm.set_instance_transform(i, t)

func _collect(out: Array, spacing: float, radius: float, prob: float, pred: Callable, cluster: float, min_r: float = 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = (spacing * 1000 + radius) as int
	var z := 0.0
	while z < TerrainGen.WORLD_Z:
		var x := 0.0
		while x < TerrainGen.WORLD_X:
			var px := x + rng.randf_range(-0.75, 0.75) * spacing
			var pz := z + rng.randf_range(-0.75, 0.75) * spacing
			var p := Vector3(px, data.height_at(px, pz), pz)
			var fd := _focus_factor(p)
			if fd < radius and fd >= min_r:
				if rng.randf() < prob * _cluster(px, pz, cluster) and pred.call(px, pz):
					out.push_back(p)
			x += spacing
		z += spacing

# ------------------------------------------------------------------ helpers
func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func _commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()

func _add_cyl(st: SurfaceTool, from: Vector3, to: Vector3, r0: float, r1: float, seg: int) -> void:
	var axis := (to - from)
	var len := axis.length()
	if len < 1e-4:
		return
	axis = axis / len
	var up := Vector3.UP if abs(axis.y) < 0.9 else Vector3.RIGHT
	var t1 := axis.cross(up).normalized()
	var t2 := axis.cross(t1).normalized()
	var ring0: Array = []
	var ring1: Array = []
	for i in range(seg):
		var a := float(i) / seg * TAU
		var dir := t1 * cos(a) + t2 * sin(a)
		ring0.push_back(from + dir * r0)
		ring1.push_back(to + dir * r1)
	for i in range(seg):
		var j := (i + 1) % seg
		st.add_vertex(ring0[i]); st.add_vertex(ring1[i]); st.add_vertex(ring1[j])
		st.add_vertex(ring0[i]); st.add_vertex(ring1[j]); st.add_vertex(ring0[j])
	for i in range(seg):
		var j := (i + 1) % seg
		st.add_vertex(ring1[0]); st.add_vertex(ring1[j]); st.add_vertex(ring1[i])

func _add_sphere(st: SurfaceTool, c: Vector3, r: Vector3, seg: int, rings: int, rng: RandomNumberGenerator, deform: float, dfreq: float = 1.7) -> void:
	var grid: Array = []
	for iy in range(rings + 1):
		var phi := float(iy) / rings * PI
		var row: Array = []
		for ix in range(seg):
			var theta := float(ix) / seg * TAU
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var extra: float = (_fn3.get_noise_3d(dir.x * dfreq + c.x, dir.y * dfreq + c.y, dir.z * dfreq + c.z) * deform) if deform > 0 else 0.0
			row.push_back(c + Vector3(dir.x * r.x, dir.y * r.y, dir.z * r.z) * (1.0 + extra))
		grid.push_back(row)
	for iy in range(rings):
		for ix in range(seg):
			var jx := (ix + 1) % seg
			var a: Vector3 = grid[iy][ix]
			var b: Vector3 = grid[iy][jx]
			var cc: Vector3 = grid[iy + 1][ix]
			var dd: Vector3 = grid[iy + 1][jx]
			st.add_vertex(a); st.add_vertex(cc); st.add_vertex(b)
			st.add_vertex(b); st.add_vertex(cc); st.add_vertex(dd)

## Double-sided leaf/needle card with baked AO + tint in vertex colour.
func _add_card(st: SurfaceTool, center: Vector3, n: Vector3, w: float, hh: float, rng: RandomNumberGenerator, ao: float, tint: float) -> void:
	var ref := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	var t1 := n.cross(ref).normalized()
	t1 = t1.rotated(n, rng.randf() * TAU)
	var t2 := n.cross(t1).normalized()
	var c0 := center - t1 * w * 0.5 - t2 * hh * 0.5
	var c1 := center + t1 * w * 0.5 - t2 * hh * 0.5
	var c2 := center + t1 * w * 0.5 + t2 * hh * 0.5
	var c3 := center - t1 * w * 0.5 + t2 * hh * 0.5
	var col := Color(ao * tint, ao * tint, ao * tint, 1.0)
	st.set_color(col); st.set_uv(Vector2(0, 0)); st.add_vertex(c0)
	st.set_color(col); st.set_uv(Vector2(1, 0)); st.add_vertex(c1)
	st.set_color(col); st.set_uv(Vector2(1, 1)); st.add_vertex(c2)
	st.set_color(col); st.set_uv(Vector2(0, 0)); st.add_vertex(c0)
	st.set_color(col); st.set_uv(Vector2(1, 1)); st.add_vertex(c2)
	st.set_color(col); st.set_uv(Vector2(0, 1)); st.add_vertex(c3)

func _foliage_mat(mode: int, ca: Color, cb: Color, hole: float, thr: float, sway: float, snowtint: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _foliage_shader
	m.set_shader_parameter("u_mode", mode)
	m.set_shader_parameter("u_col_a", ca)
	m.set_shader_parameter("u_col_b", cb)
	m.set_shader_parameter("u_hole_scale", hole)
	m.set_shader_parameter("u_threshold", thr)
	m.set_shader_parameter("u_sway", sway)
	m.set_shader_parameter("u_snowtint", snowtint)
	return m

func _merge_two(trunk: ArrayMesh, fol: ArrayMesh, bark: Material, fmat: Material) -> Mesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, trunk.surface_get_arrays(0))
	m.surface_set_material(0, bark)
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fol.surface_get_arrays(0))
	m.surface_set_material(1, fmat)
	return m

# ------------------------------------------------------------------ NEAR trees (true 3D)
func _branch(st_t: SurfaceTool, st_l: SurfaceTool, from: Vector3, dir: Vector3, len: float, rad: float, depth: int, rng: RandomNumberGenerator, h: float) -> void:
	var to := from + dir * len
	_add_cyl(st_t, from, to, rad, rad * 0.6, 6)
	if depth >= 2:
		_leaf_cluster(st_l, to, dir, h * 0.17, rng)
		return
	var nch := 3 if depth == 0 else 3
	for i in range(nch):
		var nd := (dir + Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 0.8), rng.randf_range(-1, 1)) * 0.75).normalized()
		_branch(st_t, st_l, to, nd, len * 0.62, rad * 0.55, depth + 1, rng, h)

func _leaf_cluster(st_l: SurfaceTool, c: Vector3, dir: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	for k in range(12):
		var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1)).normalized() * (rng.randf() * r)
		var pos := c + off
		var n := (off.normalized() * 0.7 + dir * 0.35 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.35).normalized()
		var ao := 0.45 + 0.55 * clampf(off.length() / r, 0.0, 1.0)
		_add_card(st_l, pos, n, r * 1.05, r * 1.3, rng, ao, rng.randf_range(0.85, 1.15))

func _make_broadleaf_detail(h: float) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1001
	var st_t := _st()
	var st_l := _st()
	_branch(st_t, st_l, Vector3.ZERO, Vector3.UP, h * 0.42, h * 0.045, 0, rng, h)
	var trunk := _commit(st_t)
	var fol := _commit(st_l)
	return _merge_two(trunk, fol, _bark_mat, _leaf_mat)

func _make_conifer_detail(h: float, variant: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2002 + variant * 7
	var st_t := _st()
	var st_n := _st()
	var lean := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
	_add_cyl(st_t, Vector3.ZERO, Vector3(lean.x * h, h * 0.92, lean.z * h), h * 0.030, h * 0.010, 6)
	var layers := 7 + variant
	for i in range(layers):
		var t := float(i) / float(layers)
		var y := h * (0.14 + 0.78 * t)
		var r := h * 0.30 * (1.0 - t * 0.85) * rng.randf_range(0.85, 1.15)
		var nb := 6
		for b in range(nb):
			var az := float(b) / float(nb) * TAU + rng.randf_range(-0.3, 0.3) + t * 2.4
			var bdir := Vector3(cos(az), rng.randf_range(-0.45, -0.15), sin(az)).normalized()
			var base := Vector3(lean.x * y, y, lean.z * y)
			var blen := r * rng.randf_range(0.8, 1.1)
			var tip := base + bdir * blen
			_add_cyl(st_t, base, tip, h * 0.012, h * 0.005, 4)
			var ao1 := 0.55 + 0.45 * rng.randf()
			_add_card(st_n, tip + bdir * blen * 0.15, (bdir + Vector3.UP * 0.5 + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.5).normalized(), blen * 0.9, blen * 0.85, rng, ao1, rng.randf_range(0.85, 1.1))
			_add_card(st_n, base + bdir * blen * 0.55, (bdir + Vector3.UP * 0.3 + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.6).normalized(), blen * 0.8, blen * 0.7, rng, ao1 * 0.85, rng.randf_range(0.85, 1.1))
			_add_card(st_n, base + bdir * blen * 0.8, (bdir + Vector3.UP * 0.7 + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.4).normalized(), blen * 0.7, blen * 0.6, rng, ao1 * 0.9, rng.randf_range(0.85, 1.1))
			_add_card(st_n, base + bdir * blen * 0.35, (bdir.cross(Vector3.UP).normalized() + Vector3.UP * 0.4 + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.4).normalized(), blen * 0.75, blen * 0.65, rng, ao1 * 0.8, rng.randf_range(0.85, 1.1))
			# third crossed layer at the tip for density
			_add_card(st_n, tip - bdir * blen * 0.1, (bdir.cross(Vector3.UP).normalized() * 0.7 + bdir * 0.3 + Vector3.UP * 0.45 + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.35).normalized(), blen * 0.85, blen * 0.8, rng, ao1 * 0.95, rng.randf_range(0.85, 1.1))
	# crown spike
	_add_card(st_n, Vector3(lean.x * h, h * 0.95, lean.z * h), Vector3.UP, h * 0.12, h * 0.16, rng, 1.0, 1.0)
	var trunk := _commit(st_t)
	var fol := _commit(st_n)
	return _merge_two(trunk, fol, _bark_mat, _needle_mat)

# ------------------------------------------------------------------ FAR impostors & others
func _wrap_pi(a: float) -> float:
	while a > PI:
		a -= TAU
	while a < -PI:
		a += TAU
	return a

func _add_cone_noisy(st: SurfaceTool, base: Vector3, h: float, radius: float, seg: int, rings: int, rng: RandomNumberGenerator, amp: float, gap_az: float, gap_w: float, gap_depth: float, nso: Vector3) -> void:
	var grid: Array = []
	for iy in range(rings + 1):
		var t := float(iy) / rings
		var y := base.y + h * t
		var r := radius * (1.0 - t)
		var row: Array = []
		for ix in range(seg):
			var az := float(ix) / seg * TAU
			var n := _fn3.get_noise_3d(cos(az) * 1.7 + nso.x, t * 2.6 + nso.y, sin(az) * 1.7 + nso.z) * 0.5 + 0.5
			var rr := r * (1.0 + amp * (n * 2.0 - 1.0))
			var yy := y + amp * h * 0.30 * (n - 0.5) * (1.0 - t)
			var daz := absf(_wrap_pi(az - gap_az))
			if daz < gap_w:
				rr *= lerpf(gap_depth, 1.0, daz / gap_w)
			row.push_back(Vector3(base.x + cos(az) * rr, yy, base.z + sin(az) * rr))
		grid.push_back(row)
	var tip := Vector3(base.x, base.y + h, base.z)
	for iy in range(rings):
		for ix in range(seg):
			var jx := (ix + 1) % seg
			var a: Vector3 = grid[iy][ix]
			var b: Vector3 = grid[iy][jx]
			var c: Vector3 = grid[iy + 1][ix]
			var d: Vector3 = grid[iy + 1][jx]
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
			st.add_vertex(b); st.add_vertex(c); st.add_vertex(d)
	for ix in range(seg):
		var jx := (ix + 1) % seg
		st.add_vertex(grid[rings][ix]); st.add_vertex(tip); st.add_vertex(grid[rings][jx])

func _make_conifer(h: float, variant: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 + variant * 13
	var st_t := _st()
	var lean := Vector3(rng.randf_range(-0.10, 0.10), 0, rng.randf_range(-0.10, 0.10))
	_add_cyl(st_t, Vector3.ZERO, Vector3(lean.x * h, h * 0.9, lean.z * h), h * 0.032, h * 0.012, 7)
	var trunk := _commit(st_t)
	var st_f := _st()
	var layers: int = [5, 4, 6][variant]
	var width: float = [0.30, 0.38, 0.24][variant]
	var skew := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.05, 0.22)
	for i in range(layers):
		var t: float = float(i) / float(layers)
		var y: float = h * (0.20 + 0.74 * t)
		var r: float = h * width * (1.0 - t * 0.80) * rng.randf_range(0.80, 1.20)
		var off := skew * (y * 0.5) + Vector3(rng.randf_range(-0.10, 0.10) * h * t, 0, rng.randf_range(-0.10, 0.10) * h * t)
		var lh := h * rng.randf_range(0.24, 0.34)
		var base := Vector3(lean.x * y, y, lean.z * y) + off
		var gap_w := 0.0
		var gap_depth := 1.0
		var gap_az := 0.0
		if rng.randf() < 0.5:
			gap_az = rng.randf() * TAU
			gap_w = rng.randf_range(0.5, 1.2)
			gap_depth = rng.randf_range(0.15, 0.4)
		_add_cone_noisy(st_f, base, lh, r, 10, 4, rng, rng.randf_range(0.25, 0.45), gap_az, gap_w, gap_depth, Vector3(rng.randf_range(-50, 50), rng.randf_range(-50, 50), rng.randf_range(-50, 50)))
	var fmat := _foliage_mat(0, Color(0.060, 0.160, 0.060), Color(0.120, 0.280, 0.100), 2.6, 0.46, 0.05, 0.35)
	var fol := _commit(st_f)
	return _merge_two(trunk, fol, _bark_mat, fmat)

func _make_broadleaf(h: float) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var st_t := _st()
	_add_cyl(st_t, Vector3.ZERO, Vector3(0, h * 0.62, 0), h * 0.05, h * 0.028, 7)
	for i in range(4):
		var a := float(i) / 4 * TAU + rng.randf()
		var dir := Vector3(cos(a), rng.randf_range(0.5, 0.9), sin(a)).normalized()
		_add_cyl(st_t, Vector3(0, h * 0.55, 0), Vector3(0, h * 0.55, 0) + dir * h * 0.4, h * 0.025, h * 0.012, 5)
	var trunk := _commit(st_t)
	var st_f := _st()
	for i in range(10):
		var a := rng.randf() * TAU
		var rr := rng.randf_range(0.05, 0.42) * h
		var c := Vector3(cos(a) * rr, h * rng.randf_range(0.62, 1.08), sin(a) * rr)
		_add_sphere(st_f, c, Vector3(h * 0.26, h * 0.20, h * 0.26), 9, 5, rng, 0.35)
	var fmat := _foliage_mat(0, Color(0.03, 0.12, 0.03), Color(0.09, 0.26, 0.06), 0.8, 0.45, 0.12)
	var fol := _commit(st_f)
	return _merge_two(trunk, fol, _bark_mat, fmat)

func _make_bush(h: float) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var st := _st()
	for i in range(3):
		var a := rng.randf() * TAU
		var c := Vector3(cos(a) * h * 0.2, h * 0.4, sin(a) * h * 0.2)
		_add_sphere(st, c, Vector3(h * 0.4, h * 0.35, h * 0.4), 6, 3, rng, 0.3)
	var m := _commit(st)
	m.surface_set_material(0, _foliage_mat(0, Color(0.07, 0.22, 0.06), Color(0.15, 0.36, 0.10), 0.6, 0.42, 0.2))
	return m

func _make_snowbush(h: float) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var st := _st()
	for i in range(3):
		var a := rng.randf() * TAU
		var c := Vector3(cos(a) * h * 0.25, h * 0.3, sin(a) * h * 0.25)
		_add_sphere(st, c, Vector3(h * 0.4, h * 0.3, h * 0.4), 6, 3, rng, 0.35)
	var m := _commit(st)
	m.surface_set_material(0, _foliage_mat(0, Color(0.06, 0.13, 0.06), Color(0.12, 0.22, 0.10), 0.7, 0.44, 0.15, 0.75))
	return m

func _make_drift(r: float) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var st := _st()
	_add_sphere(st, Vector3(0, -r * 0.12, 0), Vector3(r, r * 0.32, r * rng.randf_range(0.7, 1.3)), 9, 4, rng, 0.3)
	var m := _commit(st)
	m.surface_set_material(0, _snow_mat)
	return m

func _make_rock(r: float) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var st := _st()
	_add_sphere(st, Vector3.ZERO, Vector3(r, r * 0.85, r * rng.randf_range(0.8, 1.2)), 14, 10, rng, 0.28, 0.8)
	var m := _commit(st)
	m.surface_set_material(0, _rock_mat)
	return m

func _make_grass(h: float) -> Mesh:
	var st := _st()
	var mat := _foliage_mat(1, Color(0.10, 0.28, 0.06), Color(0.25, 0.45, 0.12), 0.6, 0.4, 0.35)
	for i in range(3):
		var a := float(i) / 3 * PI
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var w := h * 0.35
		var p0 := -side * w
		var p1 := side * w
		var p2 := side * w * 0.4 + Vector3.UP * h
		var p3 := -side * w * 0.4 + Vector3.UP * h
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p2)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p2)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p3)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m

## World position of one scattered instance (for deterministic close-up cameras).
func instance_pos(node_name: String, idx: int = 0) -> Vector3:
	var mmi := get_node_or_null(node_name) as MultiMeshInstance3D
	if mmi == null or mmi.multimesh == null or mmi.multimesh.instance_count == 0:
		return Vector3.ZERO
	return mmi.multimesh.get_instance_transform(idx).origin

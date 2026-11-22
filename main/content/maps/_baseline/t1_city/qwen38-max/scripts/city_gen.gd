class_name CityGen
extends RefCounted
## Procedural cyberpunk megacity generator (~10.5 km^2), orchestrator.
## Modules: CityMath, Districts, BuildingGen, (roads/props/river/landmarks
## are built here or in dedicated passes).

const EXTENT_X := 3500.0
const EXTENT_Z := 3000.0
const CELL := 125.0
const CHUNK := 500.0

const RC_LOCAL := 0
const RC_ARTERIAL := 1

# detail tiers around focus
var R_DETAIL := 520.0
var R_MID := 1050.0
var R_GLASS := 620.0

var params := {}
var rng := RandomNumberGenerator.new()
var noise_pos: FastNoiseLite
var noise_bend: FastNoiseLite
var noise_field: FastNoiseLite

var stat_buildings := 0
var stat_tris := 0

var mats := {}
var _chunks := {}
var _root: Node3D

var nodes := {}
var nx := 0
var nz := 0

var focus := Vector3.ZERO
var districts: Districts
var bgen: BuildingGen
var infra: InfraGen
var sign_targets := []
var interior_targets := []
var cell_info := []
var road_samples := []   # {pts, cls, dir} for props placement

func build(root: Node3D) -> void:
	_root = root
	var sd := int(params.get("seed", 1337))
	focus = params.get("focus", Vector3.ZERO)
	rng.seed = sd
	noise_pos = FastNoiseLite.new()
	noise_pos.seed = sd
	noise_pos.frequency = 1.0 / 900.0
	noise_pos.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_bend = FastNoiseLite.new()
	noise_bend.seed = sd + 17
	noise_bend.frequency = 1.0 / 160.0
	noise_bend.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_field = FastNoiseLite.new()
	noise_field.seed = sd + 91
	noise_field.frequency = 1.0 / 420.0
	noise_field.noise_type = FastNoiseLite.TYPE_SIMPLEX

	districts = Districts.new(sd)
	bgen = BuildingGen.new()
	infra = InfraGen.new()

	_make_materials()
	_make_environment()
	_make_ground()
	_build_nodes()
	_build_roads()
	infra.build_river(self)
	infra.build_elevated(self)
	infra.build_skytrain(self)
	_build_cells()
	PropsGen.new().generate(self)
	LandmarksGen.new().generate(self)
	InteriorsGen.new().generate(self)
	_flush()

# ---------------------------------------------------------------- materials

func _shader(path: String, params_map: Dictionary = {}) -> ShaderMaterial:
	var sh: Shader = load(path)
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params_map:
		m.set_shader_parameter(k, params_map[k])
	return m

func _make_materials() -> void:
	mats["facade"] = _shader("res://shaders/facade.gdshader")
	mats["glass"] = _shader("res://shaders/glass.gdshader")
	mats["interior"] = _shader("res://shaders/interior.gdshader")
	mats["road"] = _shader("res://shaders/road.gdshader", {"show_markings": true})
	mats["asphalt"] = _shader("res://shaders/road.gdshader", {"show_markings": false})
	mats["paint"] = _shader("res://shaders/paint.gdshader")
	mats["sidewalk"] = _shader("res://shaders/sidewalk.gdshader")
	mats["roof"] = _shader("res://shaders/plain.gdshader",
			{"tint": Color(0.10, 0.10, 0.12), "grain": 0.7, "uv_scale": 0.2})
	mats["ground"] = _shader("res://shaders/plain.gdshader",
			{"tint": Color(0.05, 0.05, 0.07), "grain": 0.9, "uv_scale": 0.02})
	mats["grass"] = _shader("res://shaders/grass.gdshader")
	mats["trim"] = _shader("res://shaders/emissive_vc.gdshader", {"energy": 4.0})
	mats["prop_vc"] = _shader("res://shaders/prop_vc.gdshader")
	mats["pool"] = _shader("res://shaders/pool.gdshader")
	mats["sign"] = _shader("res://shaders/neon_sign.gdshader")
	mats["holo"] = _shader("res://shaders/holo.gdshader")
	mats["water"] = _shader("res://shaders/water.gdshader")
	mats["plain_concrete"] = _shader("res://shaders/plain.gdshader",
			{"tint": Color(0.22, 0.22, 0.23), "grain": 0.6, "uv_scale": 0.15})
	mats["beacon"] = _shader("res://shaders/emissive_vc.gdshader", {"energy": 9.0})
	var mech := StandardMaterial3D.new()
	mech.albedo_color = Color(0.25, 0.26, 0.3)
	mech.metallic = 0.7
	mech.roughness = 0.5
	mats["mech"] = mech

func buf(chunk: Vector2i, mat: String) -> MeshBuf:
	if not _chunks.has(chunk):
		_chunks[chunk] = {}
	var d: Dictionary = _chunks[chunk]
	if not d.has(mat):
		d[mat] = MeshBuf.new()
	return d[mat]

func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK)))

func _flush() -> void:
	for ck in _chunks:
		var d: Dictionary = _chunks[ck]
		for mat_name in d:
			var b: MeshBuf = d[mat_name]
			if b.is_empty():
				continue
			var mesh := ArrayMesh.new()
			b.make_surface(mesh, mats[mat_name])
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.name = "chunk_%d_%d_%s" % [ck.x, ck.y, mat_name]
			if mat_name in ["glass"]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(mi)
			stat_tris += b.tri_count()

# ---------------------------------------------------------------- environment

func _make_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.006, 0.008, 0.024)
	sm.sky_horizon_color = Color(0.17, 0.095, 0.26)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sm.ground_horizon_color = Color(0.17, 0.095, 0.26)
	sm.sky_energy_multiplier = 0.9
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.14, 0.13, 0.21)
	env.ambient_light_energy = 0.75
	env.fog_enabled = false
	env.fog_light_color = Color(0.075, 0.055, 0.14)
	env.fog_density = 0.00002
	env.fog_sky_affect = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	_root.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-42, 28, 0)
	moon.light_color = Color(0.55, 0.62, 0.95)
	moon.light_energy = 0.10
	moon.shadow_enabled = false
	_root.add_child(moon)

func _make_ground() -> void:
	# subdivided grid: per-vertex varyings (distance haze) need local quads
	var b := buf(Vector2i(-9999, -9999), "ground")
	var hx := EXTENT_X * 0.5 + 400.0
	var hz := EXTENT_Z * 0.5 + 400.0
	var gn := 26
	for i in gn:
		for j in gn:
			var x0 := lerpf(-hx, hx, float(i) / float(gn))
			var x1 := lerpf(-hx, hx, float(i + 1) / float(gn))
			var z0 := lerpf(-hz, hz, float(j) / float(gn))
			var z1 := lerpf(-hz, hz, float(j + 1) / float(gn))
			b.ground_quad(
				Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1),
				PackedVector2Array([Vector2(x0, z0) * 0.01, Vector2(x1, z0) * 0.01,
					Vector2(x1, z1) * 0.01, Vector2(x0, z1) * 0.01]))

# ---------------------------------------------------------------- road grid

func _build_nodes() -> void:
	nx = int(EXTENT_X / CELL)
	nz = int(EXTENT_Z / CELL)
	for i in nx + 1:
		for j in nz + 1:
			var x := -EXTENT_X * 0.5 + float(i) * CELL
			var z := -EXTENT_Z * 0.5 + float(j) * CELL
			var dx := noise_pos.get_noise_2d(x + 313.0, z - 771.0) * 16.0
			var dz := noise_pos.get_noise_2d(x - 551.0, z + 217.0) * 16.0
			nodes[Vector2i(i, j)] = Vector3(x + dx, 0, z + dz)

func node(i: int, j: int) -> Vector3:
	return nodes[Vector2i(i, j)]

func road_class_h(j: int) -> int:
	return RC_ARTERIAL if j % 4 == 0 else RC_LOCAL

func road_class_v(i: int) -> int:
	return RC_ARTERIAL if i % 4 == 0 else RC_LOCAL

func half_width(cls: int) -> float:
	return 9.0 if cls == RC_ARTERIAL else 5.5

func sw_width(cls: int) -> float:
	return 4.0 if cls == RC_ARTERIAL else 2.5

func _road_polyline(p0: Vector3, p1: Vector3) -> PackedVector3Array:
	var d := p1 - p0
	var length := d.length()
	var perp := Vector3(-d.z, 0, d.x).normalized()
	var sub := maxi(2, int(ceil(length / 30.0)))
	var pts := PackedVector3Array()
	pts.resize(sub + 1)
	for k in sub + 1:
		var t := float(k) / float(sub)
		var p := p0.lerp(p1, t)
		if k > 0 and k < sub:
			var bend := noise_bend.get_noise_2d(p.x * 0.7 + 991.0, p.z * 0.7 - 447.0) * 5.0 * sin(PI * t)
			p += perp * bend
		pts[k] = p
	return pts

func _strip(b: MeshBuf, pts: PackedVector3Array, off0: float, off1: float,
		y: float, uvs_along: float, v0: float, v1: float, u2 := Vector2.ZERO,
		c_col := Color.WHITE, c0 := Vector4.ZERO) -> void:
	var cum := 0.0
	for k in pts.size() - 1:
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var tang := (p1 - p0)
		var seg_len := tang.length()
		tang /= maxf(seg_len, 0.001)
		var perp := Vector3(-tang.z, 0, tang.x)
		var a := p0 + perp * off0 + Vector3.UP * y
		var bq := p0 + perp * off1 + Vector3.UP * y
		var c := p1 + perp * off1 + Vector3.UP * y
		var d := p1 + perp * off0 + Vector3.UP * y
		var uvs := PackedVector2Array([
			Vector2(cum * uvs_along, v0), Vector2(cum * uvs_along, v1),
			Vector2((cum + seg_len) * uvs_along, v1), Vector2((cum + seg_len) * uvs_along, v0)])
		b.quad_o(a, bq, c, d, Vector3.UP, uvs, u2, c_col, c0)
		cum += seg_len

func _build_roads() -> void:
	for i in nx:
		for j in nz + 1:
			var p0 := node(i, j)
			var p1 := node(i + 1, j)
			var cls := road_class_h(j)
			var pts := _road_polyline(p0, p1)
			road_samples.append({"pts": pts, "cls": cls, "axis": 0})
			_road_segment_geo(pts, cls, chunk_of((p0 + p1) * 0.5))
	for i in nx + 1:
		for j in nz:
			var p0 := node(i, j)
			var p1 := node(i, j + 1)
			var cls := road_class_v(i)
			var pts := _road_polyline(p0, p1)
			road_samples.append({"pts": pts, "cls": cls, "axis": 1})
			_road_segment_geo(pts, cls, chunk_of((p0 + p1) * 0.5))
	for i in nx + 1:
		for j in nz + 1:
			_intersection(i, j)

func _road_segment_geo(pts: PackedVector3Array, cls: int, ck: Vector2i) -> void:
	var hw := half_width(cls)
	var sw := sw_width(cls)
	var b := buf(ck, "road")
	_strip(b, pts, -hw, hw, 0.02, 1.0, -1.0, 1.0)
	var sb := buf(ck, "sidewalk")
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var inner := hw * side_f
		var outer := (hw + sw) * side_f
		_strip(sb, pts, inner, outer, 0.16, 1.0, 0.0, sw, Vector2(sw, float(cls)))
		_curb_strip(sb, pts, inner, 0.02, 0.16, side_f)

func _curb_strip(b: MeshBuf, pts: PackedVector3Array, off: float, y0: float,
		y1: float, side: float) -> void:
	for k in pts.size() - 1:
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var tang := p1 - p0
		var l := tang.length()
		tang /= maxf(l, 0.001)
		var perp := Vector3(-tang.z, 0, tang.x) * side
		var a := p0 + perp * off + Vector3.UP * y0
		var bq := p1 + perp * off + Vector3.UP * y0
		var c := p1 + perp * off + Vector3.UP * y1
		var d := p0 + perp * off + Vector3.UP * y1
		var nrm := -perp * 0.35 + Vector3.UP * 0.94
		b.quad_o(a, bq, c, d, nrm.normalized(), PackedVector2Array([
			Vector2.ZERO, Vector2(l, 0), Vector2(l, y1 - y0), Vector2(0, y1 - y0)]))

func _intersection(i: int, j: int) -> void:
	var n0 := node(i, j)
	var arms := []
	if i > 0:
		arms.append(_arm_end(n0, node(i - 1, j), road_class_h(j)))
	if i < nx:
		arms.append(_arm_end(n0, node(i + 1, j), road_class_h(j)))
	if j > 0:
		arms.append(_arm_end(n0, node(i, j - 1), road_class_v(i)))
	if j < nz:
		arms.append(_arm_end(n0, node(i, j + 1), road_class_v(i)))
	if arms.size() < 2:
		return
	var pts := []
	for a in arms:
		pts.append(a[0])
		pts.append(a[1])
	var hull := CityMath.hull2d(pts)
	if hull.size() < 3:
		return
	var b := buf(chunk_of(n0), "asphalt")
	var y := 0.025
	for k in range(1, hull.size() - 1):
		var h0: Vector2 = hull[0]
		var h1: Vector2 = hull[k]
		var h2: Vector2 = hull[k + 1]
		b.tri_o(
			Vector3(h0.x, y, h0.y),
			Vector3(h1.x, y, h1.y),
			Vector3(h2.x, y, h2.y),
			Vector3.UP,
			PackedVector2Array([h0 * 0.2, h1 * 0.2, h2 * 0.2]))

func _arm_end(n0: Vector3, toward: Vector3, cls: int) -> Array:
	var d := toward - n0
	d.y = 0
	d = d.normalized()
	var perp := Vector3(-d.z, 0, d.x)
	var hw := half_width(cls) + 0.5
	return [Vector2(n0.x + perp.x * hw, n0.z + perp.z * hw),
			Vector2(n0.x - perp.x * hw, n0.z - perp.z * hw)]

# ---------------------------------------------------------------- cells & districts

func _build_cells() -> void:
	for i in nx:
		for j in nz:
			var corners := [node(i, j), node(i + 1, j), node(i + 1, j + 1), node(i, j + 1)]
			var center: Vector3 = (corners[0] + corners[2]) * 0.5
			var nxn := (center.x + EXTENT_X * 0.5) / EXTENT_X
			var nzn := (center.z + EXTENT_Z * 0.5) / EXTENT_Z
			nxn += noise_field.get_noise_2d(center.x * 0.5 + 71.0, center.z * 0.5) * 0.025
			nzn += noise_field.get_noise_2d(center.x * 0.5 - 33.0, center.z * 0.5 + 9.0) * 0.025
			var dtype := districts.at(clampf(nxn, 0.0, 1.0), clampf(nzn, 0.0, 1.0))
			var d_h0 := half_width(road_class_h(j)) + sw_width(road_class_h(j)) + 2.0
			var d_h1 := half_width(road_class_h(j + 1)) + sw_width(road_class_h(j + 1)) + 2.0
			var d_v0 := half_width(road_class_v(i)) + sw_width(road_class_v(i)) + 2.0
			var d_v1 := half_width(road_class_v(i + 1)) + sw_width(road_class_v(i + 1)) + 2.0
			var inner := CityMath.inset_poly(corners, [d_h0, d_v1, d_h1, d_v0])
			var dr: float = infra.dist_to_river(center, self)
			var rhw: float = infra.river_half_width(center.x, self)
			if dr < rhw + 20.0:
				continue
			if dr < rhw + 90.0:
				_make_park(inner, center)
				continue
			cell_info.append({"center": center, "dtype": dtype, "inner": inner, "ij": Vector2i(i, j)})
			if dtype == Districts.D.PARK:
				_make_park(inner, center)
				continue
			var P: Dictionary = Districts.params(dtype)
			var lots := CityMath.split_quad(inner, P.lot, rng, 150.0)
			for lot in lots:
				if CityMath.poly_area2(lot) < 120.0:
					continue
				bgen.generate(self, lot, dtype)

func _make_park(inner: Array, center: Vector3) -> void:
	var b := buf(chunk_of(center), "grass")
	var wp := PackedVector2Array()
	for p in inner:
		wp.append(Vector2(p.x, p.z))
	b.prism(wp, 0.02, 0.09, Vector2.ZERO, Color.WHITE, b, 0.05)
	# winding paths (sine curves)
	var pb := buf(chunk_of(center), "sidewalk")
	var c: Vector3 = CityMath.poly_centroid(inner)
	for path in 2:
		var ang := rng.randf() * PI
		var dirv := Vector3(cos(ang), 0, sin(ang))
		var perp := Vector3(-dirv.z, 0, dirv.x)
		var prev_a: Vector3 = Vector3.ZERO
		var prev_b: Vector3 = Vector3.ZERO
		for k in 13:
			var t := float(k) / 12.0 - 0.5
			var off := sin(t * PI * 2.0 + float(path) * 2.0) * 14.0
			var p := c + dirv * (t * 90.0) + perp * off
			var wa := p - perp * 1.4 + Vector3(0, 0.11, 0)
			var wb2 := p + perp * 1.4 + Vector3(0, 0.11, 0)
			if k > 0:
				pb.quad_o(prev_a, prev_b, wb2, wa, Vector3.UP, PackedVector2Array([
					Vector2(0, 0), Vector2(2.25, 0), Vector2(2.25, 0.84), Vector2(0, 0.84)]))
			prev_a = wa
			prev_b = wb2
	# pond
	if rng.randf() < 0.45:
		var wb := buf(chunk_of(center), "water")
		var pc := c + Vector3(rng.randf_range(-20, 20), 0.1, rng.randf_range(-20, 20))
		var r := rng.randf_range(12.0, 22.0)
		wb.quad_o(pc + Vector3(-r, 0, -r * 0.7), pc + Vector3(r, 0, -r * 0.7),
			pc + Vector3(r, 0, r * 0.7), pc + Vector3(-r, 0, r * 0.7), Vector3.UP,
			PackedVector2Array([Vector2(-r, -r) * 0.05, Vector2(r, -r) * 0.05,
				Vector2(r, r) * 0.05, Vector2(-r, r) * 0.05]))
	# park lamps
	var tb := buf(chunk_of(center), "trim")
	for k in 6:
		var lp := c + Vector3(rng.randf_range(-35, 35), 0, rng.randf_range(-35, 35))
		tb.box(lp + Vector3(0, 2.0, 0), Vector3(0.12, 4.0, 0.12), Vector2.ZERO, Color(0.1, 0.1, 0.1, 0.0), 1.0)
		tb.box(lp + Vector3(0, 4.1, 0), Vector3(0.5, 0.3, 0.5), Vector2.ZERO, Color(1.0, 0.8, 0.5, 1.0), 1.0)

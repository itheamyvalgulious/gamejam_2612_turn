class_name HullBuilder
extends RefCounted

## Exterior of the SSV ORION.
##   * superellipse loft with hard shoulder chines and frame bands
##   * appliqué armour patches that float 12 cm off the plating
##   * engine boat-tail with three deep nozzles
##   * cantilevered command tower with a wrap-around canopy
##   * dorsal spine, radiators, sensors, dock ports, service greebles

const SUPER_N := 3.35
const Z_STERN := 150.0
const Z_BOW := -152.0

const PROFILE := [
	Vector4(-152.0, 4.2, 4.6, 0.4),
	Vector4(-146.0, 6.0, 6.6, 0.8),
	Vector4(-138.0, 8.8, 8.8, 1.2),
	Vector4(-128.0, 11.6, 10.8, 1.5),
	Vector4(-112.0, 15.2, 13.4, 1.5),
	Vector4(-96.0, 19.4, 16.0, 1.2),
	Vector4(-76.0, 24.4, 18.6, 0.8),
	Vector4(-56.0, 28.6, 20.4, 0.4),
	Vector4(-30.0, 32.0, 22.0, 0.0),
	Vector4(0.0, 35.0, 23.2, 0.0),
	Vector4(40.0, 35.0, 23.4, 0.0),
	Vector4(70.0, 32.6, 22.2, 0.3),
	Vector4(100.0, 29.0, 20.2, 0.6),
	Vector4(124.0, 25.0, 17.6, 1.0),
	Vector4(148.0, 21.6, 14.2, 1.4),
]

var kit: MeshKit
var cfg: ShipConfig
var details: Node3D
var rng := RandomNumberGenerator.new()


func _init(k: MeshKit, c: ShipConfig) -> void:
	kit = k
	cfg = c
	rng.seed = 77441


func build(parent: Node3D) -> void:
	details = Node3D.new()
	details.name = "HullDetails"
	parent.add_child(details)

	build_loft()
	build_keel_and_chines()
	build_frame_bands()
	build_armour_patches()
	build_stern()
	build_command_tower()
	build_spine()
	build_radiators()
	build_sensors()
	build_ports_and_hatches()
	build_portholes()
	build_greebles()
	build_markings()
	build_running_lights()
	kit.commit(parent, "HullShell", true, 2)


# ---------------------------------------------------------------- surface ---
func profile_at(z: float) -> Vector4:
	var p0: Vector4 = PROFILE[0]
	var p1: Vector4 = PROFILE[PROFILE.size() - 1]
	if z <= p0.x:
		return p0
	if z >= p1.x:
		return p1
	for i in PROFILE.size() - 1:
		var a: Vector4 = PROFILE[i]
		var b: Vector4 = PROFILE[i + 1]
		if z >= a.x and z <= b.x:
			var t := (z - a.x) / (b.x - a.x)
			t = t * t * (3.0 - 2.0 * t)
			return Vector4(z, lerpf(a.y, b.y, t), lerpf(a.z, b.z, t), lerpf(a.w, b.w, t))
	return p1


func section(z: float, theta: float) -> Vector3:
	var pr := profile_at(z)
	var c := cos(theta)
	var s := sin(theta)
	var ex := 2.0 / SUPER_N
	var x: float = pr.y * signf(c) * pow(absf(c), ex)
	var y: float = pr.w + pr.z * signf(s) * pow(absf(s), ex)
	return Vector3(x, y, z)


func section_normal(z: float, theta: float) -> Vector3:
	var a := section(z, theta - 0.01)
	var b := section(z, theta + 0.01)
	var c := section(z - 0.5, theta)
	var d := section(z + 0.5, theta)
	var n := (b - a).cross(d - c).normalized()
	var axis := Vector3(0.0, profile_at(z).w, z)
	if n.dot(section(z, theta) - axis) < 0.0:
		n = -n
	return n


func half_width_at(z: float, y: float) -> float:
	var pr := profile_at(z)
	var t: float = clampf(absf((y - pr.w) / pr.z), 0.0, 0.999)
	return pr.y * pow(maxf(0.0, 1.0 - pow(t, SUPER_N)), 1.0 / SUPER_N)


# ------------------------------------------------------------------- loft ---
func build_loft() -> void:
	var nu := 128
	var nz := 168
	var pts: Array = []
	var norms: Array = []
	for i in nu + 1:
		var theta := TAU * float(i) / float(nu)
		var col: Array = []
		var ncol: Array = []
		for j in nz + 1:
			var z := lerpf(Z_STERN, Z_BOW, float(j) / float(nz))
			col.append(section(z, theta))
			ncol.append(section_normal(z, theta))
		pts.append(col)
		norms.append(ncol)
	# cumulative arc per row for metric U coordinates
	var arcs: Array = []
	for j in nz + 1:
		var row: Array = [0.0]
		var acc := 0.0
		for i in nu:
			acc += (pts[i][j] as Vector3).distance_to(pts[i + 1][j])
			row.append(acc)
		arcs.append(row)

	kit.begin_part(0.5, 0.0)
	kit.set_height_range(-23.0, 23.0)
	for i in nu:
		for j in nz:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			var na: Vector3 = norms[i][j]
			var nb: Vector3 = norms[i + 1][j]
			var nc: Vector3 = norms[i + 1][j + 1]
			var nd: Vector3 = norms[i][j + 1]
			var ua: float = arcs[j][i]
			var ub: float = arcs[j][i + 1]
			var uc: float = arcs[j + 1][i + 1]
			var ud: float = arcs[j + 1][i]
			kit.quad_n("hull", [a, b, c, d], [na, nb, nc, nd],
				[Vector2(ua, a.z), Vector2(ub, b.z), Vector2(uc, c.z), Vector2(ud, d.z)])

	kit.begin_part(0.6, 0.0)
	var cap := []
	for i in nu:
		cap.append(section(Z_STERN, TAU * float(i) / float(nu)))
	kit.poly("hull_soot", cap, Vector3.BACK)
	var nose := []
	for i in nu:
		nose.append(section(Z_BOW, TAU * float(i) / float(nu)))
	kit.poly("hull", nose, Vector3.FORWARD)


# ------------------------------------------------------- chines and keel ---
func build_keel_and_chines() -> void:
	# four longitudinal hard edges: two per flank + a dorsal rail + keel
	var lanes := [
		{"th": 0.34, "w": 0.55, "h": 0.30, "key": "hull_dark"},
		{"th": -0.42, "w": 0.35, "h": 0.22, "key": "hull_dark"},
		{"th": 0.34 + PI, "w": 0.55, "h": 0.30, "key": "hull_dark"},
		{"th": -0.42 + PI, "w": 0.35, "h": 0.22, "key": "hull_dark"},
		{"th": PI * 0.5, "w": 1.1, "h": 0.5, "key": "hull_dark"},
		{"th": -PI * 0.5, "w": 0.9, "h": 0.35, "key": "hull_soot"},
	]
	for lane in lanes:
		var th: float = lane["th"]
		var z := -136.0
		var ci := 0
		while z < 144.0:
			var z2: float = minf(z + 4.0, 144.0)
			var p := section(z2, th)
			var n := section_normal(z2, th)
			var tangent := (section(z2 - 1.0, th) - section(z2 + 1.0, th)).normalized()
			var side := n.cross(tangent).normalized()
			var b := Basis(side, n, tangent)
			kit.push_xf(Transform3D(b, p + n * (lane["h"] as float) * 0.4))
			kit.begin_part(0.35 + float(ci % 6) * 0.04, 2.0)
			kit.box_bevel(lane["key"], Vector3(lane["w"], lane["h"], 4.05), Vector3.ZERO, 0.06)
			if ci % 3 == 0:
				kit.box("metal", Vector3(lane["w"] * 0.45, lane["h"] * 0.55, 1.1), Vector3(0, lane["h"] * 0.8, 1.2))
			kit.pop_xf()
			z = z2
			ci += 1


func build_frame_bands() -> void:
	for z in [-121.0, -101.0, -81.0, -61.0, -41.0, -21.0, -1.0, 19.0, 39.0, 59.0, 79.0, 99.0, 119.0, 139.0]:
		_ridge_ring(z, 0.20, "hull_dark")
		_ridge_ring(z + 0.55, 0.05, "hull_soot")


func _ridge_ring(z: float, width: float, key: String) -> void:
	var nu := 128
	for i in nu:
		var t0 := TAU * float(i) / float(nu)
		var t1 := TAU * float(i + 1) / float(nu)
		var a := section(z - width, t0)
		var b := section(z - width, t1)
		var c := section(z + width, t1)
		var d := section(z + width, t0)
		var n := section_normal(z, (t0 + t1) * 0.5)
		var out := 0.06
		a += section_normal(z - width, t0) * out
		b += section_normal(z - width, t1) * out
		c += section_normal(z + width, t1) * out
		d += section_normal(z + width, t0) * out
		kit.quad(key, [a, b, c, d], n)


# -------------------------------------------------------- armour patches ---
func build_armour_patches() -> void:
	var patches := [
		[-118.0, -100.0, 0.10, 0.55],
		[-92.0, -72.0, -0.62, -0.30],
		[-66.0, -48.0, 0.30, 0.70],
		[-40.0, -18.0, -0.55, -0.18],
		[-14.0, 6.0, 0.55, 0.92],
		[24.0, 44.0, -0.36, 0.02],
		[56.0, 76.0, 0.42, 0.80],
		[86.0, 108.0, -0.58, -0.22],
	]
	for p in patches:
		for side in [1.0, -1.0]:
			_patch(p[0], p[1], p[2] * side, p[3] * side, 0.14, "hull")


func _patch(z0: float, z1: float, th0: float, th1: float, offset: float, key: String) -> void:
	var nu := 6
	var nz := 7
	var grid: Array = []
	var ngrid: Array = []
	for i in nu + 1:
		var row: Array = []
		var nrow: Array = []
		for j in nz + 1:
			var u := float(i) / float(nu)
			var v := float(j) / float(nz)
			var z := lerpf(z0, z1, v)
			var th := lerpf(th0, th1, u)
			var p := section(z, th)
			var n := section_normal(z, th)
			row.append(p + n * offset)
			nrow.append(n)
		grid.append(row)
		ngrid.append(nrow)
	kit.begin_part(0.44, 2.5)
	kit.set_height_range(-22.0, 22.0)
	for i in nu:
		for j in nz:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			kit.quad_n(key, [a, b, c, d],
				[ngrid[i][j], ngrid[i + 1][j], ngrid[i + 1][j + 1], ngrid[i][j + 1]],
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	# skirts around the border give the plate visible thickness
	for i in nu:
		for j in [0, nz]:
			var z := lerpf(z0, z1, float(j) / float(nz))
			var t0 := lerpf(th0, th1, float(i) / float(nu))
			var t1 := lerpf(th0, th1, float(i + 1) / float(nu))
			var p0 := section(z, t0) + section_normal(z, t0) * offset
			var p1 := section(z, t1) + section_normal(z, t1) * offset
			var q0 := section(z, t0)
			var q1 := section(z, t1)
			kit.quad("hull_dark", [p0, q0, q1, p1], (p1 - p0).cross(q0 - p0).normalized())
	for j in nz:
		for i in [0, nu]:
			var za: float = lerpf(z0, z1, float(j) / float(nz))
			var zb: float = lerpf(z0, z1, float(j + 1) / float(nz))
			var t := lerpf(th0, th1, float(i) / float(nu))
			var p0 := section(za, t) + section_normal(za, t) * offset
			var p1 := section(zb, t) + section_normal(zb, t) * offset
			var q0 := section(za, t)
			var q1 := section(zb, t)
			kit.quad("hull_dark", [p0, q0, q1, p1], (p1 - p0).cross(q0 - p0).normalized())


# ------------------------------------------------------------------ stern ---
func build_stern() -> void:
	# boat tail housing
	kit.begin_part(0.7, 1.0)
	kit.set_height_range(-16.0, 16.0)
	kit.box_bevel("hull_dark", Vector3(38.0, 25.0, 5.0), Vector3(0, 3.0, 152.0), 1.2)
	kit.box_bevel("hull_soot", Vector3(30.0, 17.0, 3.0), Vector3(0, 2.0, 155.0), 1.0)
	for i in 3:
		var x := (float(i) - 1.0) * 12.6
		_engine_bell(Vector3(x, 1.2, 150.0), 1.12, i)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.26
		var px := cos(a) * 18.0
		var py := 2.0 + sin(a) * 10.0
		_vernier(Vector3(px, py, 153.5), 0.9)

	# housing details: pipes, tanks, clamps
	kit.begin_part(0.82, 2.0)
	for i in 3:
		var x := (float(i) - 1.0) * 12.6
		for k in 5:
			var ang := TAU * float(k) / 5.0 + 0.15
			kit.box("metal_dark", Vector3(0.55, 0.55, 6.0),
				Vector3(x + cos(ang) * 5.4, 1.2 + sin(ang) * 5.4, 154.0))
		kit.tube("pipe_orange", [
			Vector3(x - 4.8, -7.2, 147.0), Vector3(x - 5.4, -4.0, 152.0),
			Vector3(x - 4.4, 1.0, 155.0), Vector3(x - 2.4, 5.2, 153.5),
		], 0.55, 10)
		kit.tube("pipe_teal", [
			Vector3(x + 4.8, -7.6, 147.0), Vector3(x + 5.6, -4.0, 152.0),
			Vector3(x + 4.4, 1.0, 155.0), Vector3(x + 2.4, 5.2, 153.5),
		], 0.40, 10)
	# dorsal manoeuvring pack
	kit.begin_part(0.36, 3.0)
	kit.box_bevel("hull_dark", Vector3(30.0, 2.4, 6.0), Vector3(0, 14.5, 148.0), 0.4)
	kit.box_bevel("hull_accent", Vector3(5.0, 1.0, 1.6), Vector3(-9.0, 14.8, 150.0), 0.2)
	kit.box_bevel("hull_accent", Vector3(5.0, 1.0, 1.6), Vector3(9.0, 14.8, 150.0), 0.2)
	# aft radiator grille
	kit.begin_part(0.4, 3.0)
	for k in 8:
		kit.box("metal_dark", Vector3(18.0, 0.18, 0.6), Vector3(0, -4.5 + k * 0.55, 155.8))


func _engine_bell(origin: Vector3, scale: float, index: int) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), origin)
	kit.push_xf(xf)
	kit.begin_part(0.62 + index * 0.03, 4.0)
	kit.set_height_range(-6.0, 6.0)
	var prof: Array = []
	for i in 13:
		var t := float(i) / 12.0
		var y := t * 13.0
		var r := (1.85 + 3.55 * (1.0 - exp(-t * 2.35))) * scale
		prof.append(Vector2(r, y))
	kit.lathe("metal_cast", prof, 40, Vector3.ZERO, TAU, 0.0, false)
	var inner: Array = []
	for p in prof:
		inner.append(Vector2(p.x * 0.97, p.y))
	kit.lathe("metal_dark", inner, 40, Vector3.ZERO, TAU, 0.0, false, true)
	# outer cowling
	var cow: Array = []
	for i in 13:
		var t := float(i) / 12.0
		var y := t * 11.0
		var r := (2.15 + 3.55 * (1.0 - exp(-t * 2.35))) * scale
		cow.append(Vector2(r, y))
	kit.lathe("hull_dark", cow, 40, Vector3.ZERO, TAU, 0.0, false)
	kit.torus("metal_dark", 5.55 * scale, 0.34 * scale, 40, 8, Vector3(0, 13.0, 0))
	for k in 4:
		var y := 3.2 + float(k) * 2.6
		var r := (1.85 + 3.55 * (1.0 - exp(-y / 13.0 * 2.35))) * scale
		kit.torus("metal", (r + 0.32) * scale, 0.13 * scale, 32, 6, Vector3(0, y, 0))
	# plasma plume inside the bell
	kit.cyl("plasma_engine", 1.6 * scale, 3.9 * scale, 12.0, 32, Vector3.ZERO, false, 0.4)
	kit.pop_xf()


func _vernier(origin: Vector3, scale: float) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), origin)
	kit.push_xf(xf)
	kit.begin_part(0.9, 3.0)
	var prof: Array = []
	for i in 6:
		var t := float(i) / 5.0
		prof.append(Vector2((0.42 + 0.44 * t) * scale, t * 2.4))
	kit.lathe("metal_cast", prof, 16, Vector3.ZERO, TAU, 0.0, false)
	kit.torus("metal_dark", 0.86 * scale, 0.08 * scale, 16, 6, Vector3(0, 2.4, 0))
	kit.cyl("plasma_engine", 0.4, 0.8, 1.8, 16, Vector3.ZERO, false, 0.2)
	kit.pop_xf()


# ---------------------------------------------------------- command tower ---
func build_command_tower() -> void:
	var sec := [
		{"z": -122.0, "w": 8.8, "ch": 1.0},
		{"z": -128.0, "w": 9.2, "ch": 1.0},
		{"z": -136.0, "w": 8.8, "ch": 0.9},
		{"z": -143.0, "w": 7.6, "ch": 0.7},
		{"z": -147.0, "w": 6.0, "ch": 0.5},
	]
	# three stacked bands: armoured lower hull, glass canopy, armoured roof
	_tower_band(sec, 10.2, 12.9, "hull", true, true)
	_tower_band(sec, 12.95, 16.35, "glass", false, false)
	_tower_band(sec, 16.4, 18.0, "hull", true, true)
	# roof brow and chin
	kit.begin_part(0.48, 5.0)
	kit.box_bevel("hull_dark", Vector3(15.0, 0.8, 13.0), Vector3(0, 17.7, -136.0), 0.25)
	kit.box_bevel("hull_accent", Vector3(6.0, 0.5, 1.4), Vector3(0, 17.9, -145.0), 0.15)
	kit.box_bevel("hull_dark", Vector3(12.0, 0.9, 10.0), Vector3(0, 10.7, -138.0), 0.25)
	kit.box_bevel("hull_soot", Vector3(8.0, 1.4, 4.4), Vector3(0, 10.2, -146.5), 0.3)
	# canopy mullions (vertical posts + mid rail)
	for z in [-129.6, -135.6, -141.0, -145.4]:
		var w: float = 9.2
		if z < -140.0:
			w = 7.6
		if z < -145.0:
			w = 6.0
		kit.begin_part(0.58, 5.0)
		for sx in [-1.0, 1.0]:
			kit.box("hull_dark", Vector3(0.26, 3.5, 0.42), Vector3(sx * w, 14.65, z))
	kit.begin_part(0.6, 5.0)
	for sx in [-1.0, 1.0]:
		kit.box("hull_dark", Vector3(0.2, 0.22, 24.0), Vector3(sx * 7.4, 14.65, -134.0))
	# forward canopy frame
	kit.begin_part(0.62, 5.0)
	kit.box("hull_dark", Vector3(12.4, 0.3, 0.35), Vector3(0, 16.35, -147.0))
	kit.box("hull_dark", Vector3(12.4, 0.3, 0.35), Vector3(0, 12.95, -147.0))
	# pylon fairing into the bow hull
	kit.begin_part(0.52, 5.0)
	var pyl := [
		{"z": -119.0, "w": 6.4, "y0": 7.6, "y1": 11.0},
		{"z": -130.0, "w": 5.2, "y0": 7.0, "y1": 10.8},
		{"z": -139.0, "w": 3.4, "y0": 7.6, "y1": 10.6},
	]
	for i in pyl.size() - 1:
		var za: float = pyl[i]["z"]
		var zb: float = pyl[i + 1]["z"]
		var wa: float = pyl[i]["w"]
		var wb: float = pyl[i + 1]["w"]
		var ya0: float = pyl[i]["y0"]
		var ya1: float = pyl[i]["y1"]
		var yb0: float = pyl[i + 1]["y0"]
		var yb1: float = pyl[i + 1]["y1"]
		kit.quad("hull_dark", [Vector3(wa, ya0, za), Vector3(wa, ya1, za),
			Vector3(wb, yb1, zb), Vector3(wb, yb0, zb)], Vector3.RIGHT)
		kit.quad("hull_dark", [Vector3(-wa, ya0, za), Vector3(-wb, yb0, zb),
			Vector3(-wb, yb1, zb), Vector3(-wa, ya1, za)], Vector3.LEFT)
		kit.quad("hull_dark", [Vector3(-wa, ya0, za), Vector3(wa, ya0, za),
			Vector3(wb, yb0, zb), Vector3(-wb, yb0, zb)], Vector3.DOWN)
		kit.quad("hull_dark", [Vector3(-wa, ya1, za), Vector3(-wb, yb1, zb),
			Vector3(wb, yb1, zb), Vector3(wa, ya1, za)], Vector3.UP)
	# roof sensors
	kit.begin_part(0.72, 5.0)
	for sx in [-1.0, 1.0]:
		kit.sphere("metal_light", 0.95, 18, Vector3(sx * 4.6, 18.4, -131.0))
		kit.cyl("metal_dark", 0.22, 0.14, 3.2, 8, Vector3(sx * 6.2, 18.4, -139.0))
	kit.cyl("metal_dark", 0.30, 0.20, 5.4, 10, Vector3(0, 18.2, -126.6))
	kit.torus("metal", 1.05, 0.09, 24, 6, Vector3(0, 23.4, -126.6))
	# rear collar
	kit.begin_part(0.66, 5.0)
	kit.box_bevel("hull_dark", Vector3(17.8, 8.4, 1.8), Vector3(0, 14.0, -122.4), 0.35)
	kit.box_bevel("hull_accent", Vector3(9.0, 0.5, 0.6), Vector3(0, 18.1, -123.0), 0.2)


func _octagon(w: float, y0: float, y1: float, ch: float, z: float) -> Array:
	return [
		Vector3(w, y0 + ch, z), Vector3(w, y1 - ch, z),
		Vector3(w - ch, y1, z), Vector3(-(w - ch), y1, z),
		Vector3(-w, y1 - ch, z), Vector3(-w, y0 + ch, z),
		Vector3(-(w - ch), y0, z), Vector3(w - ch, y0, z),
	]


func _tower_band(sec: Array, y0: float, y1: float, key: String,
		cap_rear: bool, cap_front: bool) -> void:
	var rings: Array = []
	for r in sec:
		rings.append(_octagon(float(r["w"]), y0, y1, float(r["ch"]), float(r["z"])))
	kit.begin_part(0.45, 5.0)
	kit.set_height_range(10.0, 18.5)
	for i in rings.size() - 1:
		for k in 8:
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][(k + 1) % 8]
			var c: Vector3 = rings[i + 1][(k + 1) % 8]
			var d: Vector3 = rings[i + 1][k]
			var n: Vector3 = (b - a).cross(d - a).normalized()
			var center := Vector3(0.0, (y0 + y1) * 0.5, a.z)
			if n.dot(a - center) < 0.0:
				n = -n
			kit.quad(key, [a, b, c, d], n)
	if cap_front:
		kit.poly(key, rings[rings.size() - 1], Vector3.FORWARD)
	if cap_rear:
		kit.poly(key, rings[0], Vector3.BACK)


# ------------------------------------------------------------------ spine ---
func build_spine() -> void:
	var segments := 32
	for i in segments:
		var z := lerpf(-112.0, 144.0, float(i) / float(segments))
		var pr := profile_at(z)
		var y := pr.w + pr.z
		var s := 1.0 if i % 3 != 2 else 0.82
		kit.begin_part(0.31 + 0.02 * (i % 5), 6.0)
		kit.box_bevel("hull_dark", Vector3(2.4 * s, 0.95, 7.4), Vector3(0, y - 0.5, z + 3.7), 0.2)
		kit.box("metal_dark", Vector3(1.3, 0.25, 3.2), Vector3(0, y + 0.32, z + 2.0))
		if i % 4 == 0:
			kit.box("hull_accent", Vector3(0.65, 0.2, 1.5), Vector3(0.95, y + 0.2, z + 4.1))
	for sz in [-1.0, 1.0]:
		var pts := []
		for i in 20:
			var z := lerpf(-104.0, 140.0, float(i) / 19.0)
			var pr := profile_at(z)
			pts.append(Vector3(sz * 2.6, pr.w + pr.z - 0.25, z))
		kit.begin_part(0.37, 7.0)
		kit.tube("pipe_cream", pts, 0.22, 8)
	# forward sensor boom + mast
	kit.begin_part(0.41, 7.0)
	kit.box_bevel("hull_dark", Vector3(1.1, 1.0, 9.0), Vector3(0, 17.8, -117.0), 0.2)
	kit.cyl("metal_light", 0.22, 0.12, 8.0, 10, Vector3(0, 18.2, -121.0))
	kit.sphere("metal_light", 0.8, 16, Vector3(0, 18.2, -120.5))
	# tail fin
	kit.begin_part(0.45, 7.0)
	var fin := [Vector2(-5.0, 0.0), Vector2(5.0, 0.0), Vector2(1.6, 7.0), Vector2(-1.2, 7.0)]
	kit.push_xf(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 21.0, 128.0)))
	kit.prism("hull_dark", fin, 0.7, Vector3.ZERO)
	kit.pop_xf()


func build_radiators() -> void:
	for side in [-1.0, 1.0]:
		for k in 3:
			var z := 84.0 + k * 14.0
			var pr := profile_at(z)
			var base := Vector3(side * (pr.y * 0.70), pr.w + pr.z * 0.55 - k * 0.35, z)
			var ang: float = side * deg_to_rad(26.0 + k * 4.0)
			var xf := Transform3D(Basis(Vector3.BACK, ang), base)
			kit.push_xf(xf)
			kit.begin_part(0.44 + k * 0.04, 8.0)
			kit.box("hull_soot", Vector3(8.0, 0.14, 2.3), Vector3(side * 3.8, 0, 0))
			kit.box("metal_dark", Vector3(8.4, 0.40, 0.28), Vector3(side * 3.8, 0, 1.1))
			kit.box("metal_dark", Vector3(8.4, 0.40, 0.28), Vector3(side * 3.8, 0, -1.1))
			for m in 5:
				kit.box("metal", Vector3(0.16, 0.28, 2.3), Vector3(side * (0.7 + m * 1.6), 0.09, 0))
			kit.pop_xf()


func build_sensors() -> void:
	for pos in [Vector3(-7.6, 18.4, -108.0), Vector3(9.6, 17.0, 58.0)]:
		var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-38.0)).rotated(Vector3.UP, 0.5), pos)
		kit.push_xf(xf)
		kit.begin_part(0.55, 9.0)
		var prof: Array = []
		for i in 9:
			var r := float(i) / 8.0 * 2.4
			prof.append(Vector2(r, r * r * 0.13))
		kit.lathe("metal_light", prof, 30)
		kit.cyl("metal_dark", 0.18, 0.12, 1.8, 8, Vector3(0, -1.8, 0))
		kit.pop_xf()
	kit.begin_part(0.58, 9.0)
	for i in 3:
		kit.cyl("metal_light", 0.055, 0.02, 6.0 + i * 1.5, 6,
			Vector3(-3.0 + i * 3.0, 12.0, -114.0 + i * 1.5))


func build_ports_and_hatches() -> void:
	for side in [-1.0, 1.0]:
		var z := 22.0
		var y := -2.0
		var x: float = half_width_at(z, y)
		var xf := Transform3D(Basis(Vector3.UP, -side * PI * 0.5), Vector3(x * side, y, z))
		kit.push_xf(xf)
		kit.begin_part(0.63, 10.0)
		kit.box("hull_dark", Vector3(5.6, 5.0, 0.4), Vector3(0, 0, 0.05))
		kit.torus("metal", 1.65, 0.20, 28, 8, Vector3(0, 0, 0.30))
		kit.cyl("metal_dark", 1.55, 1.55, 0.4, 28, Vector3(0, 0, 0.12))
		kit.torus("metal_light", 1.22, 0.09, 24, 6, Vector3(0, 0, 0.36))
		for k in 4:
			var a := TAU * float(k) / 4.0 + 0.4
			kit.box("metal", Vector3(0.5, 0.5, 0.4), Vector3(cos(a) * 2.0, sin(a) * 2.0, 0.2))
		kit.pop_xf()

	# ventral hangar doors
	kit.begin_part(0.68, 11.0)
	var hz := -73.0
	var hy := -17.4
	kit.box("hull_dark", Vector3(20.0, 0.45, 24.0), Vector3(0, hy, hz))
	kit.box("metal_cast", Vector3(9.2, 0.55, 23.0), Vector3(-4.8, hy - 0.12, hz))
	kit.box("metal_cast", Vector3(9.2, 0.55, 23.0), Vector3(4.8, hy - 0.12, hz))
	kit.box("hazard", Vector3(0.55, 0.6, 23.0), Vector3(0, hy - 0.18, hz))
	for k in 6:
		kit.box("metal_dark", Vector3(18.0, 0.2, 0.45), Vector3(0, hy - 0.25, hz - 9.5 + k * 3.8))
	for sz in [-1.0, 1.0]:
		for k in 3:
			kit.box("emit_amber", Vector3(0.34, 0.14, 0.34),
				Vector3(sz * 9.0, hy - 0.3, hz - 6.0 + k * 6.0))


func build_portholes() -> void:
	# habitat band windows (emissive strips behind dark glass)
	for side in [-1.0, 1.0]:
		for k in 11:
			var z := -58.0 + k * 3.6
			var y := 4.0
			var x: float = half_width_at(z, y)
			var b := Basis(Vector3(0, 0, -side), Vector3.UP, Vector3(side, 0, 0))
			kit.push_xf(Transform3D(b, Vector3(x * side, y, z)))
			kit.begin_part(0.5, 15.0)
			kit.box("hull_dark", Vector3(2.4, 0.9, 0.2), Vector3.ZERO)
			kit.box("glass_dark", Vector3(2.0, 0.6, 0.26), Vector3(0, 0, 0.04))
			kit.box("emit_warm", Vector3(1.8, 0.10, 0.05), Vector3(0, 0, 0.16))
			kit.pop_xf()
	# upper observation ports
	for side in [-1.0, 1.0]:
		for k in 4:
			var z := -46.0 + k * 4.0
			var y := 14.0
			var x: float = half_width_at(z, y)
			var b := Basis(Vector3(0, 0, -side), Vector3.UP, Vector3(side, 0, 0))
			kit.push_xf(Transform3D(b, Vector3(x * side, y, z)))
			kit.begin_part(0.56, 15.0)
			kit.torus("metal_dark", 1.05, 0.12, 20, 6, Vector3.ZERO)
			kit.cyl("glass_dark", 1.0, 1.0, 0.18, 24, Vector3(0, 0, -0.09))
			kit.pop_xf()


# --------------------------------------------------------------- greebles ---
func build_greebles() -> void:
	var count := 120
	var placed := 0
	var guard := 0
	while placed < count and guard < 1200:
		guard += 1
		var z := rng.randf_range(-116.0, 146.0)
		var theta := rng.randf_range(0.0, TAU)
		var p := section(z, theta)
		var n := section_normal(z, theta)
		var pr := profile_at(z)
		# keep dorsal ridge, keel and window bands clear
		if absf(p.x) < 3.2 and p.y > pr.w + pr.z - 3.0:
			continue
		if p.y < pr.w - pr.z + 3.0 and absf(p.x) < 11.0:
			continue
		if absf(p.y - 4.0) < 1.6 and absf(p.z + 40.0) < 22.0:
			continue
		var b := _basis_from_normal(n)
		var xf := Transform3D(b, p + n * 0.06)
		kit.push_xf(xf)
		kit.begin_part(0.2 + float(placed % 13) * 0.06, 12.0)
		var kind := placed % 7
		if kind == 0:
			kit.box_bevel("hull_dark", Vector3(rng.randf_range(1.2, 3.6), rng.randf_range(0.8, 2.2), 0.35), Vector3.ZERO, 0.08)
			kit.box("metal", Vector3(0.5, 0.25, 0.18), Vector3(0, 0, 0.22))
		elif kind == 1:
			kit.box("hull_dark", Vector3(rng.randf_range(2.0, 5.4), 0.28, 0.22), Vector3.ZERO)
			for k in 4:
				kit.box("metal", Vector3(0.12, 0.12, 0.30), Vector3(-1.6 + k * 1.05, 0, 0.08))
		elif kind == 2:
			var rr := rng.randf_range(0.25, 0.6)
			kit.cyl("metal_cast", rr, rr, 0.55, 12, Vector3.ZERO)
			kit.torus("metal", rr * 0.8, 0.05, 14, 5, Vector3(0, 0.28, 0))
		elif kind == 3:
			kit.box_bevel("hull_accent", Vector3(0.5, 0.5, 0.32), Vector3.ZERO, 0.05)
			kit.box("emit_white", Vector3(0.2, 0.2, 0.10), Vector3(0, 0, 0.18))
		elif kind == 4:
			for k in 3:
				kit.box("metal_dark", Vector3(0.09, 0.55, 0.18), Vector3(k * 0.38 - 0.38, 0, 0))
		elif kind == 5:
			kit.box_bevel("hull_dark", Vector3(1.9, 1.3, 0.65), Vector3.ZERO, 0.12)
			for k in 4:
				kit.cyl("metal", 0.12, 0.12, 0.15, 8, Vector3(-0.62 + k * 0.42, 0.4, 0.32))
		else:
			kit.tube("pipe_teal", [Vector3(-1.7, 0.0, 0.06), Vector3(0.0, 0.25, 0.12),
				Vector3(1.7, 0.0, 0.06)], 0.10, 6)
		kit.pop_xf()
		placed += 1


func _basis_from_normal(n: Vector3) -> Basis:
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	var t := n.cross(up).normalized()
	var b := n.cross(t).normalized()
	return Basis(t, b, n)


func build_markings() -> void:
	for side in [-1.0, 1.0]:
		var z := 58.0
		var y := 3.0
		var x: float = half_width_at(z, y)
		var basis := Basis(Vector3(0, 0, -side), Vector3.UP, Vector3(side, 0, 0))
		kit.begin_part(0.24, 13.0)
		kit.push_xf(Transform3D(basis, Vector3(x * side + side * 0.16, y, z)))
		kit.box("hull_dark", Vector3(24.0, 5.2, 0.16), Vector3.ZERO)
		kit.box("hull_accent", Vector3(24.0, 0.22, 0.2), Vector3(0, -2.7, 0.02))
		kit.pop_xf()
		_add_text("ORION", Vector3(x * side + side * 0.30, y + 0.55, z + 2.0),
			basis, 0.038, "hull_light_text")
		_add_text("SSV-04", Vector3(x * side + side * 0.30, y - 1.55, z + 3.2),
			basis, 0.016, "hull_light_text")
		_add_text("DEEP SURVEY", Vector3(x * side + side * 0.30, y - 2.35, z + 3.2),
			basis, 0.010, "hull_light_text")


func _add_text(text: String, pos: Vector3, basis: Basis, pixel_size: float, mat_key: String) -> void:
	var tm := TextMesh.new()
	tm.text = text
	tm.font = ThemeDB.fallback_font
	tm.font_size = 64
	tm.pixel_size = pixel_size
	tm.depth = 0.05
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = _text_material(mat_key)
	mi.transform = Transform3D(basis, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 2
	details.add_child(mi)


func _text_material(key: String) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.045, 0.05, 0.055)
	m.roughness = 0.65
	m.metallic = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _surface(dir_hint: Vector3, y: float, z: float) -> Vector3:
	var pr := profile_at(z)
	if absf(dir_hint.y) > 0.5:
		return Vector3(0.0, y, z) + dir_hint * 0.4
	var rr: float = half_width_at(z, y)
	return Vector3(signf(dir_hint.x) * (rr + 0.3), y, z)


func build_running_lights() -> void:
	var spots := [
		{"p": _surface(Vector3(-1, 0, 0), 2.0, 85.0), "c": Color(1.0, 0.08, 0.05), "e": "emit_red"},
		{"p": _surface(Vector3(1, 0, 0), 2.0, 85.0), "c": Color(0.1, 1.0, 0.25), "e": "emit_green"},
		{"p": Vector3(0, 23.6, 96.0), "c": Color(1, 1, 1), "e": "emit_white"},
		{"p": Vector3(0, -21.0, 20.0), "c": Color(1, 1, 1), "e": "emit_white"},
		{"p": Vector3(-12.4, 4.0, 156.0), "c": Color(1, 0.5, 0.15), "e": "emit_amber"},
		{"p": Vector3(12.4, 4.0, 156.0), "c": Color(1, 0.5, 0.15), "e": "emit_amber"},
		{"p": Vector3(-8.5, 17.9, -126.0), "c": Color(1, 1, 1), "e": "emit_white"},
		{"p": Vector3(8.5, 17.9, -126.0), "c": Color(1, 1, 1), "e": "emit_white"},
	]
	kit.begin_part(0.5, 14.0)
	for s in spots:
		kit.box(s["e"], Vector3(0.34, 0.34, 0.34), s["p"])
		var l := OmniLight3D.new()
		l.position = s["p"]
		l.light_color = s["c"]
		l.light_energy = 0.9
		l.omni_range = 6.0
		l.shadow_enabled = false
		l.light_cull_mask = 2
		details.add_child(l)
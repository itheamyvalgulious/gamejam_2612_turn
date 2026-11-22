## Live traffic: ground cars on the grid + cars on the elevated expressway,
## air traffic drones with blinking lights.
class_name Traffic
extends Node3D

var plan: CityPlan
var car_mm: MultiMeshInstance3D
var cars: Array = []
var car_routes: Array = []
var hw_mm: MultiMeshInstance3D
var hw_cars: Array = []
var drone_mm: MultiMeshInstance3D
var ped_mm: MultiMeshInstance3D
var peds: Array = []
var drones: Array = []
var env: Env
var t := 0.0
var enabled := true

const LANE := 2.3

func setup(p: CityPlan, e: Env, route_paths: Array) -> void:
	plan = p
	env = e
	_build_cars(route_paths)
	_build_drones()
	_build_peds()

func _car_mesh(scale := 1.0) -> ArrayMesh:
	var mb := MB.new()
	# lower body
	mb.setm(M.PLASTIC, Color(0.9, 0.9, 0.9), 0.35)
	mb.box(Vector3(0, 0.52, 0), Vector3(1.86, 0.44, 4.35))
	# hood + trunk (slightly lower)
	mb.box(Vector3(0, 0.76, -1.55), Vector3(1.78, 0.16, 1.25))
	mb.box(Vector3(0, 0.79, 1.62), Vector3(1.78, 0.14, 1.1))
	# cabin (tapered by hand)
	var cw := 1.62
	var c0 := -0.75
	var c1 := 1.15
	var b0 := 0.78
	var b1 := 1.30
	# sides
	mb.quad(Vector3(-cw * 0.5, b0, c1), Vector3(-cw * 0.5, b0, c0), Vector3(-cw * 0.42, b1, c0 + 0.25), Vector3(-cw * 0.42, b1, c1 - 0.15))
	mb.quad(Vector3(cw * 0.5, b0, c0), Vector3(cw * 0.5, b0, c1), Vector3(cw * 0.42, b1, c1 - 0.15), Vector3(cw * 0.42, b1, c0 + 0.25))
	# roof
	mb.setm(M.PLASTIC, Color(0.85, 0.85, 0.85), 0.35)
	mb.quad(Vector3(-cw * 0.42, b1, c1 - 0.15), Vector3(cw * 0.42, b1, c1 - 0.15), Vector3(cw * 0.42, b1, c0 + 0.25), Vector3(-cw * 0.42, b1, c0 + 0.25))
	# windscreen / rear glass
	mb.setm(M.GLASS, Color(0.04, 0.06, 0.08), 0.4)
	mb.quad_n(Vector3(-cw * 0.45, b0 + 0.02, c0), Vector3(cw * 0.45, b0 + 0.02, c0), Vector3(cw * 0.42, b1, c0 + 0.25), Vector3(-cw * 0.42, b1, c0 + 0.25), Vector3(0, 0.4, -1))
	mb.quad_n(Vector3(cw * 0.45, b0 + 0.02, c1), Vector3(-cw * 0.45, b0 + 0.02, c1), Vector3(-cw * 0.42, b1, c1 - 0.15), Vector3(cw * 0.42, b1, c1 - 0.15), Vector3(0, 0.4, 1))
	# side windows
	mb.quad_n(Vector3(-cw * 0.5 - 0.01, b0 + 0.08, c0 + 0.1), Vector3(-cw * 0.5 - 0.01, b0 + 0.08, c1 - 0.1), Vector3(-cw * 0.42 - 0.01, b1 - 0.05, c1 - 0.2), Vector3(-cw * 0.42 - 0.01, b1 - 0.05, c0 + 0.3), Vector3(-1, 0, 0))
	mb.quad_n(Vector3(cw * 0.5 + 0.01, b0 + 0.08, c1 - 0.1), Vector3(cw * 0.5 + 0.01, b0 + 0.08, c0 + 0.1), Vector3(cw * 0.42 + 0.01, b1 - 0.05, c0 + 0.3), Vector3(cw * 0.42 + 0.01, b1 - 0.05, c1 - 0.2), Vector3(1, 0, 0))
	# lights
	mb.setm(M.EMIT, Mats.c("fff4e0"), 0.3, 3.4)
	mb.box(Vector3(-0.62, 0.66, -2.19), Vector3(0.46, 0.16, 0.05))
	mb.box(Vector3(0.62, 0.66, -2.19), Vector3(0.46, 0.16, 0.05))
	mb.setm(M.EMIT, Mats.c("ff1424"), 0.5, 2.6)
	mb.box(Vector3(-0.64, 0.72, 2.19), Vector3(0.44, 0.12, 0.05))
	mb.box(Vector3(0.64, 0.72, 2.19), Vector3(0.44, 0.12, 0.05))
	# wheels + arches
	mb.setm(M.RUBBER, Mats.c("101012"), 0.2)
	for sx in [-0.87, 0.87]:
		for sz in [-1.42, 1.38]:
			mb.cyl_y(Vector3(sx, 0.34, sz), 0.34, 0.26, 10, true)
	mb.setm(M.METAL, Mats.c("8a929c"), 0.3)
	for sx in [-0.9, 0.9]:
		for sz in [-1.42, 1.38]:
			mb.cyl_y(Vector3(sx + (0.02 if sx > 0 else -0.02), 0.34, sz), 0.2, 0.28, 8, true)
	# underglow
	mb.setm(M.EMIT, Mats.c("2ff0ff"), 0.5, 1.1)
	mb.box(Vector3(0, 0.22, 0), Vector3(1.66, 0.04, 3.5))
	return mb.commit(Mats.surface, Mats.glass)

func _build_cars(paths: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _car_mesh()
	var total := 1100
	mm.instance_count = total
	car_mm = MultiMeshInstance3D.new()
	car_mm.multimesh = mm
	car_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	car_mm.visible = true
	add_child(car_mm)
	car_routes = paths
	var r := H.rng(41, 991, 3)
	var cols := ["20242a", "3a3f46", "7a1a20", "1a3048", "4a4a4a", "9a9a90", "2a1848",
		"0a5a4a", "6a4a10", "c0c0c0", "1a1a1e"]
	for i in total:
		var route: Dictionary = paths[r.randi() % paths.size()]
		# bias spawn density toward the city core
		if r.randf() < 0.55:
			var rr: Dictionary = paths[r.randi() % paths.size()]
			var pp0 := _path_point(rr, r.randf() * float(rr["len"]))
			if Vector2(pp0.x, pp0.z).length() < 900.0:
				route = rr
		var s: float = r.randf() * float(route["len"])
		var dir: float = 1.0 if r.randf() < 0.5 else -1.0
		var sp: float = r.randf_range(7.0, 15.0)
		var lane: float = LANE * (1.0 if dir > 0.0 else -1.0)
		cars.append({"route": route, "s": s, "dir": dir, "speed": sp, "lane": lane, "y": 0.06})
		var c := Mats.c(cols[r.randi() % cols.size()])
		mm.set_instance_color(i, c)
	# highway cars
	var hw := MultiMesh.new()
	hw.transform_format = MultiMesh.TRANSFORM_3D
	hw.use_colors = true
	hw.mesh = _car_mesh()
	hw.instance_count = 90
	hw_mm = MultiMeshInstance3D.new()
	hw_mm.multimesh = hw
	hw_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hw_mm)
	if paths.size() > 0:
		var hroute: Dictionary = paths[paths.size() - 1]
		for i in 90:
			var dir := 1.0 if i % 2 == 0 else -1.0
			hw_cars.append({"route": hroute, "s": r.randf() * hroute["len"], "dir": dir,
				"speed": r.randf_range(16.0, 26.0), "lane": LANE * 1.4 * (1.0 if dir > 0 else -1.0),
				"y": 14.0})
			hw.set_instance_color(i, Mats.c(cols[r.randi() % cols.size()]))
	_update_cars(0.0)

func _build_drones() -> void:
	var mb := MB.new()
	mb.setm(M.METAL, Mats.c("3a4048"), 0.2)
	mb.box(Vector3.ZERO, Vector3(1.6, 0.5, 2.6))
	mb.setm(M.EMIT, Mats.c("40e8ff"), 0.3, 3.0)
	mb.box(Vector3(0, 0.3, -1.2), Vector3(0.5, 0.12, 0.12))
	mb.setm(M.EMIT, Mats.c("ff2050"), 0.4, 3.0)
	mb.box(Vector3(0, 0.3, 1.2), Vector3(0.5, 0.12, 0.12))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mb.commit(Mats.surface, Mats.glass)
	mm.instance_count = 120
	drone_mm = MultiMeshInstance3D.new()
	drone_mm.multimesh = mm
	drone_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drone_mm)
	var r := H.rng(7, 771, 5)
	for i in 120:
		var a: float = r.randf_range(-1500.0, 1500.0)
		var b: float = r.randf_range(-1500.0, 1500.0)
		var h: float = r.randf_range(35.0, 190.0)
		var sp: float = r.randf_range(0.02, 0.06)
		drones.append({"c": Vector2(a, b), "h": h, "rad": r.randf_range(40.0, 160.0),
			"ph": r.randf_range(0.0, TAU), "sp": sp, "bob": r.randf_range(0.5, 2.0)})

func _ped_mesh() -> ArrayMesh:
	var mb := MB.new()
	mb.setm(M.FABRIC, Color(0.9, 0.9, 0.9), 0.4)
	mb.box(Vector3(0, 1.05, 0), Vector3(0.46, 0.62, 0.28))
	mb.box(Vector3(-0.16, 0.5, 0), Vector3(0.16, 0.55, 0.18))
	mb.box(Vector3(0.16, 0.5, 0), Vector3(0.16, 0.55, 0.18))
	mb.setm(M.PLASTIC, Mats.c("b08060"), 0.3)
	mb.sphere(Vector3(0, 1.55, 0), 0.15, 6, 4)
	mb.setm(M.RUBBER, Mats.c("2a2a2e"), 0.2)
	mb.box(Vector3(-0.16, 0.18, 0), Vector3(0.2, 0.1, 0.3))
	mb.box(Vector3(0.16, 0.18, 0), Vector3(0.2, 0.1, 0.3))
	return mb.commit(Mats.surface, Mats.glass)

func _build_peds() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _ped_mesh()
	mm.instance_count = 520
	ped_mm = MultiMeshInstance3D.new()
	ped_mm.multimesh = mm
	ped_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ped_mm)
	var r := H.rng(97, 331, 8)
	var cols := ["20242a", "3a3f46", "5a2028", "1a3048", "4a4a4a", "8a8a80", "2a1848",
		"0a5a4a", "6a4a10", "c0c0c0", "4a3050", "a05030"]
	var placed := 0
	for blk in plan.blocks:
		if blk.water or placed >= 520:
			continue
		var c := Poly.centroid(blk.poly)
		if Vector2(c.x, c.y).length() > 1250.0:
			continue
		var poly: PackedVector2Array = blk.poly
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var L := a.distance_to(b)
			if L < 8.0:
				continue
			var dir := (b - a) / L
			var n := int(L / 14.0)
			for k in n:
				if placed >= 520:
					break
				var t := (k + 0.5) / n
				var outn := Vector2(dir.y, -dir.x)
				if outn.dot(c - (a + b) * 0.5) < 0.0:
					outn = -outn
				var base := Vector2(a.x, a.y) + dir * (L * t) + outn * 2.0
				peds.append({"base": base, "dir": dir, "speed": r.randf_range(0.8, 1.6),
					"ph": r.randf() * 30.0, "span": r.randf_range(10.0, 22.0)})
				mm.set_instance_color(placed, Mats.c(cols[r.randi() % cols.size()]))
				placed += 1

func _update_peds() -> void:
	var mm := ped_mm.multimesh
	for i in peds.size():
		var p: Dictionary = peds[i]
		var base: Vector2 = p["base"]
		var dir: Vector2 = p["dir"]
		var span: float = p["span"]
		var s: float = fposmod(t * float(p["speed"]) + float(p["ph"]), span) - span * 0.5
		var pos := base + dir * s
		var bob := absf(sin(t * float(p["speed"]) * 5.0)) * 0.05
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y) + (PI if s > 0.0 else 0.0)),
			Vector3(pos.x, 0.17 + bob, pos.y)))

var _acc := 0.0
func _process(delta: float) -> void:
	t += delta
	_acc += delta
	if not enabled:
		return
	if _acc < 0.048:
		return
	var dt := _acc
	_acc = 0.0
	_update_cars(dt)
	_update_drones()
	_update_peds()

func _path_point(route: Dictionary, s: float) -> Vector3:
	var pts: PackedVector3Array = route["pts"]
	var total: float = route["len"]
	var d := fposmod(s, total)
	var acc := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= d:
			var f := (d - acc) / maxf(seg, 0.001)
			return pts[i].lerp(pts[i + 1], f)
		acc += seg
	return pts[pts.size() - 1]

func _path_dir(route: Dictionary, s: float) -> Vector3:
	var a := _path_point(route, s)
	var b := _path_point(route, s + 1.5)
	var d := (b - a)
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD

func _update_cars(delta: float) -> void:
	var mm := car_mm.multimesh
	for i in cars.size():
		var c: Dictionary = cars[i]
		c["s"] = float(c["s"]) + float(c["speed"]) * delta * float(c["dir"])
		var route: Dictionary = c["route"]
		var p := _path_point(route, float(c["s"]))
		var dir := _path_dir(route, float(c["s"])) * float(c["dir"])
		var right := Vector3(-dir.z, 0, dir.x)
		var pos := p + right * float(c["lane"]) + Vector3(0, float(c["y"]), 0)
		var rot := atan2(-dir.x, -dir.z)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rot), pos))
	var hw := hw_mm.multimesh
	for i in hw_cars.size():
		var c: Dictionary = hw_cars[i]
		c["s"] = float(c["s"]) + float(c["speed"]) * delta * float(c["dir"])
		var route: Dictionary = c["route"]
		var p := _path_point(route, float(c["s"]))
		var dir := _path_dir(route, float(c["s"])) * float(c["dir"])
		var right := Vector3(-dir.z, 0, dir.x)
		var pos := p + right * float(c["lane"]) + Vector3(0, float(c["y"]), 0)
		var rot := atan2(-dir.x, -dir.z)
		hw.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rot), pos))

func _update_drones() -> void:
	var mm := drone_mm.multimesh
	for i in drones.size():
		var d: Dictionary = drones[i]
		var a: float = float(d["ph"]) + t * float(d["sp"])
		var c: Vector2 = d["c"]
		var pos := Vector3(c.x + cos(a) * float(d["rad"]), float(d["h"]) + sin(t * float(d["bob"]) + a) * 2.0,
			c.y + sin(a) * float(d["rad"]))
		var nxt := Vector3(c.x + cos(a + 0.05) * float(d["rad"]), pos.y,
			c.y + sin(a + 0.05) * float(d["rad"]))
		var dir := (nxt - pos).normalized()
		var rot := atan2(-dir.x, -dir.z)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rot), pos))
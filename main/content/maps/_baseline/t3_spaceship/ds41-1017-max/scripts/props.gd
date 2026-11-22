class_name Props
extends RefCounted

## Reusable procedural set-dressing: consoles, crates, pipes, catwalks,
## bunks, shop fronts, plants, doors, signage, holo tables, shuttle...

var kit: MeshKit
var lib: MatLib
var cfg: ShipConfig
var root: Node3D          # receives TextMesh signage nodes
var rng := RandomNumberGenerator.new()
var sign_count := 0


func _init(k: MeshKit, l: MatLib, c: ShipConfig, sign_parent: Node3D) -> void:
	kit = k
	lib = l
	cfg = c
	root = sign_parent
	rng.seed = 99182


# ------------------------------------------------------------- primitives ---
func beam(key: String, a: Vector3, b: Vector3, w: float, h: float,
		up_hint: Vector3 = Vector3.UP) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return
	var dir := d / len
	var up := up_hint
	if absf(dir.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var right := dir.cross(up).normalized()
	var up2 := right.cross(dir).normalized()
	kit.push_xf(Transform3D(Basis(right, up2, dir), (a + b) * 0.5))
	kit.box(key, Vector3(w, h, len), Vector3.ZERO)
	kit.pop_xf()


func pipe(path: Array, radius: float, key: String = "metal", flanges: bool = true,
		step: float = 3.0) -> void:
	kit.tube(key, path, radius, 10)
	if flanges:
		var acc := 0.0
		for i in range(1, path.size()):
			var a: Vector3 = path[i - 1]
			var b: Vector3 = path[i]
			var seg := a.distance_to(b)
			var d := (b - a) / maxf(seg, 0.001)
			var t := 0.0
			while t < seg:
				if fmod(acc + t, step) < 0.12:
					var p := a + d * t
					var right := d.cross(Vector3.UP).normalized()
					if right.length() < 0.1:
						right = d.cross(Vector3.RIGHT).normalized()
					var up2 := right.cross(d).normalized()
					kit.push_xf(Transform3D(Basis(right, up2, d), p))
					kit.cyl("metal_dark", radius * 1.28, radius * 1.28, 0.10, 12, Vector3.ZERO)
					kit.pop_xf()
				t += 0.5
			acc += seg


func valve(p: Vector3, dir: Vector3, radius: float = 0.35) -> void:
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
	var right := d.cross(up).normalized()
	var up2 := right.cross(d).normalized()
	kit.push_xf(Transform3D(Basis(right, up2, d), p))
	kit.cyl("metal_cast", 0.10, 0.10, 0.55, 8, Vector3.ZERO)
	kit.torus("metal", radius, 0.05, 16, 5, Vector3(0, 0.55, 0))
	for i in 3:
		var a := TAU * float(i) / 3.0
		kit.push_xf(Transform3D(Basis(Vector3.UP, a), Vector3.ZERO))
		kit.box("metal", Vector3(radius * 1.9, 0.04, 0.05), Vector3(0, 0.55, 0))
		kit.pop_xf()
	kit.pop_xf()


func catwalk(x0: float, x1: float, z0: float, z1: float, y: float,
		rail: bool = true, post_step: float = 2.0) -> void:
	var w := x1 - x0
	var d := z1 - z0
	kit.begin_part(0.4, 20.0)
	kit.set_height_range(y - 1.0, y + 1.4)
	kit.box("floor_grate", Vector3(w, 0.12, d), Vector3((x0 + x1) * 0.5, y - 0.06, (z0 + z1) * 0.5))
	# edge beams
	kit.box("metal_dark", Vector3(0.14, 0.34, d), Vector3(x0 + 0.07, y - 0.22, (z0 + z1) * 0.5))
	kit.box("metal_dark", Vector3(0.14, 0.34, d), Vector3(x1 - 0.07, y - 0.22, (z0 + z1) * 0.5))
	# cross beams
	var z := z0 + 0.5
	while z < z1:
		kit.box("metal_dark", Vector3(w, 0.16, 0.14), Vector3((x0 + x1) * 0.5, y - 0.26, z))
		z += 1.6
	if rail:
		_rail_line(Vector3(x0, y, z0), Vector3(x0, y, z1), post_step)
		_rail_line(Vector3(x1, y, z0), Vector3(x1, y, z1), post_step)


func _rail_line(a: Vector3, b: Vector3, post_step: float) -> void:
	var len := a.distance_to(b)
	var d := (b - a).normalized()
	var n := int(ceil(len / post_step))
	for i in n + 1:
		var p := a + d * minf(float(i) * post_step, len)
		kit.box("metal_dark", Vector3(0.07, 1.05, 0.07), p + Vector3(0, 0.52, 0))
	beam("metal", a + Vector3(0, 1.06, 0), b + Vector3(0, 1.06, 0), 0.06, 0.06)
	beam("metal", a + Vector3(0, 0.56, 0), b + Vector3(0, 0.56, 0), 0.05, 0.05)
	# toe plate
	beam("hazard_worn", a + Vector3(0, 0.12, 0), b + Vector3(0, 0.12, 0), 0.05, 0.22)


func railing(a: Vector3, b: Vector3, height: float = 1.05, key: String = "metal") -> void:
	var len := a.distance_to(b)
	var d := (b - a).normalized()
	var n := int(ceil(len / 1.8))
	for i in n + 1:
		var p := a + d * minf(float(i) * 1.8, len)
		kit.box("metal_dark", Vector3(0.07, height, 0.07), p + Vector3(0, height * 0.5, 0))
	beam(key, a + Vector3(0, height, 0), b + Vector3(0, height, 0), 0.055, 0.055)
	beam(key, a + Vector3(0, height * 0.55, 0), b + Vector3(0, height * 0.55, 0), 0.045, 0.045)


func glass_panel(center: Vector3, width: float, height: float, yaw: float = 0.0,
		frames: bool = true) -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.push_xf(Transform3D(b, center))
	kit.begin_part(0.74, 21.0)
	kit.box("glass", Vector3(width, height, 0.03), Vector3.ZERO)
	if frames:
		for sx in [-0.5, 0.5]:
			kit.box("metal_dark", Vector3(0.10, height + 0.24, 0.18), Vector3(sx * width, 0, 0))
		for sy in [-0.5, 0.5]:
			kit.box("metal_dark", Vector3(width + 0.20, 0.10, 0.18), Vector3(0, sy * height, 0))
		# mullions
		var n := int(width / 1.8)
		for i in range(1, n):
			kit.box("metal_dark", Vector3(0.055, height, 0.1), Vector3(-width * 0.5 + width * float(i) / float(n), 0, 0))
	kit.pop_xf()


# ---------------------------------------------------------------- furniture --
func console(origin: Vector3, yaw: float, width: float = 2.2,
		screen_key: String = "screen_nav", height: float = 1.02) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.31, 22.0)
	kit.set_height_range(0.0, 1.8)
	# carcass + kick plate
	kit.box_bevel("metal_painted", Vector3(width, height, 0.72), Vector3(0, height * 0.5, 0), 0.04)
	kit.box("metal_dark", Vector3(width - 0.2, 0.12, 0.62), Vector3(0, 0.06, 0.02))
	kit.box("hazard_worn", Vector3(width + 0.02, 0.05, 0.74), Vector3(0, 0.16, 0))
	# top surface with a rake
	var top := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0, height + 0.06, -0.02))
	kit.push_xf(top)
	kit.box_bevel("metal", Vector3(width - 0.06, 0.06, 0.76), Vector3.ZERO, 0.02)
	# screens
	var n := 1 if width < 1.8 else 2
	for i in n:
		var x := 0.0 if n == 1 else (float(i) - 0.5) * (width * 0.48)
		kit.box("metal_dark", Vector3(width * 0.42, 0.56, 0.07), Vector3(x, 0.36, -0.10))
		kit.box(screen_key, Vector3(width * 0.37, 0.46, 0.02), Vector3(x, 0.36, -0.065))
		# little buttons
		for k in 5:
			kit.box("emit_amber" if k % 2 == 0 else "emit_cool", Vector3(0.035, 0.02, 0.02),
				Vector3(x - 0.16 + k * 0.08, 0.01, 0.22))
	kit.pop_xf()
	# side panels + under-desk drawers
	kit.box("metal_dark", Vector3(0.05, height - 0.2, 0.7), Vector3(-width * 0.5 + 0.03, height * 0.5, 0))
	kit.box("metal_dark", Vector3(0.05, height - 0.2, 0.7), Vector3(width * 0.5 - 0.03, height * 0.5, 0))
	kit.pop_xf()


func chair(origin: Vector3, yaw: float, seat_y: float = 0.46) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.55, 22.0)
	kit.set_height_range(0.0, 1.4)
	kit.cyl("metal_dark", 0.26, 0.22, 0.10, 12, Vector3(0, 0.02, 0))
	kit.cyl("metal", 0.07, 0.07, seat_y - 0.12, 8, Vector3(0, 0.1, 0))
	kit.box_bevel("metal_painted", Vector3(0.52, 0.10, 0.50), Vector3(0, seat_y, 0), 0.035)
	kit.box_bevel("rubber", Vector3(0.46, 0.07, 0.44), Vector3(0, seat_y + 0.08, 0), 0.03)
	var back := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-10.0)), Vector3(0, seat_y + 0.48, 0.25))
	kit.push_xf(back)
	kit.box_bevel("metal_painted", Vector3(0.48, 0.62, 0.08), Vector3.ZERO, 0.03)
	kit.box_bevel("rubber", Vector3(0.42, 0.52, 0.05), Vector3(0, 0.02, -0.05), 0.02)
	kit.pop_xf()
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.06, 0.06, 0.42), Vector3(sx * 0.28, seat_y + 0.24, 0.02))
	kit.pop_xf()


func crate(origin: Vector3, size: Vector3, key: String = "metal_painted", yaw: float = 0.0) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.42, 23.0)
	kit.set_height_range(0.0, size.y)
	kit.box_bevel(key, size, Vector3(0, size.y * 0.5, 0), 0.03)
	# banding
	for sy in [0.18, 0.82]:
		kit.box("metal_dark", Vector3(size.x + 0.02, 0.06, size.z + 0.02), Vector3(0, size.y * sy, 0))
	for sx in [-0.44, 0.44]:
		kit.box("metal_dark", Vector3(0.05, size.y, size.z + 0.02), Vector3(size.x * sx, size.y * 0.5, 0))
	# label
	kit.box("emit_white", Vector3(size.x * 0.34, size.y * 0.18, 0.01), Vector3(0, size.y * 0.55, size.z * 0.5 + 0.01))
	kit.pop_xf()


func container(origin: Vector3, key: String = "container_a", yaw: float = 0.0,
		size: Vector3 = Vector3(6.1, 2.6, 2.44)) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.33, 24.0)
	kit.set_height_range(0.0, size.y)
	kit.box(key, Vector3(size.x, size.y, size.z), Vector3(0, size.y * 0.5, 0))
	# corner castings
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			for sy in [0.0, 1.0]:
				kit.box("metal_dark", Vector3(0.24, 0.28, 0.24),
					Vector3(sx * (size.x * 0.5 - 0.09), 0.14 + sy * (size.y - 0.28), sz * (size.z * 0.5 - 0.09)))
	# door bars on one end
	for k in 3:
		kit.box("metal", Vector3(0.06, size.y * 0.82, 0.07),
			Vector3(size.x * 0.5 + 0.03, size.y * 0.5, -0.6 + k * 0.6))
	kit.pop_xf()


func barrel(origin: Vector3, key: String = "pipe_teal") -> void:
	kit.push_xf(Transform3D(Basis(), origin))
	kit.begin_part(0.6, 23.0)
	kit.cyl(key, 0.32, 0.32, 1.05, 16, Vector3.ZERO)
	for y in [0.12, 0.9]:
		kit.torus("metal", 0.33, 0.03, 16, 5, Vector3(0, y, 0))
	kit.cyl("metal_dark", 0.30, 0.30, 0.03, 12, Vector3(0, 1.05, 0))
	kit.pop_xf()


func tank(origin: Vector3, radius: float, height: float, key: String = "metal_light") -> void:
	var prof: Array = []
	for i in 9:
		var t := float(i) / 8.0
		var a := t * PI
		prof.append(Vector2(radius * sin(a), height * 0.5 - cos(a) * radius * 0.55))
	kit.push_xf(Transform3D(Basis(), origin))
	kit.begin_part(0.37, 25.0)
	kit.lathe(key, prof, 28)
	for k in 3:
		kit.torus("metal_dark", radius * 1.01, 0.07, 28, 6, Vector3(0, -height * 0.3 + k * height * 0.3, 0))
	kit.cyl("metal_dark", 0.22, 0.22, 0.5, 8, Vector3(0, height * 0.5 + radius * 0.4, 0))
	kit.pop_xf()


func bunk(origin: Vector3, yaw: float, top: bool = false) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.48, 26.0)
	kit.set_height_range(0.0, 2.0)
	# frame
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box("metal_dark", Vector3(0.07, 1.95, 0.07),
				Vector3(sx * 1.0, 0.97, sz * 0.9))
	var levels := [0.42, 1.45] if not top else [0.42]
	for ly in levels:
		kit.box("metal", Vector3(2.06, 0.07, 1.84), Vector3(0, ly, 0))
		kit.box_bevel("wall_pad", Vector3(1.92, 0.16, 1.7), Vector3(0, ly + 0.11, 0), 0.05)
		kit.box_bevel("wall_white", Vector3(0.42, 0.10, 1.3), Vector3(0.66, ly + 0.23, 0.0), 0.04)
		# folded blanket
		kit.box_bevel("wall_atrium", Vector3(1.0, 0.10, 1.64), Vector3(-0.45, ly + 0.22, 0), 0.035)
	# privacy screen
	kit.box("wall_pad", Vector3(2.05, 0.7, 0.05), Vector3(0, 1.95, -0.94))
	kit.pop_xf()


func locker(origin: Vector3, yaw: float, w: float = 0.6, h: float = 1.9) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.62, 26.0)
	kit.set_height_range(0.0, h)
	kit.box_bevel("metal_painted", Vector3(w, h, 0.5), Vector3(0, h * 0.5, 0), 0.025)
	kit.box("metal_dark", Vector3(w * 0.86, 0.04, 0.02), Vector3(0, h * 0.72, 0.255))
	kit.box("metal_dark", Vector3(w * 0.86, 0.04, 0.02), Vector3(0, h * 0.25, 0.255))
	kit.box("emit_cool", Vector3(0.05, 0.05, 0.01), Vector3(w * 0.3, h * 0.55, 0.262))
	kit.pop_xf()


func table(origin: Vector3, w: float = 1.6, d: float = 0.9, h: float = 0.75) -> void:
	kit.push_xf(Transform3D(Basis(), origin))
	kit.begin_part(0.52, 27.0)
	kit.set_height_range(0.0, 1.0)
	kit.box_bevel("metal_painted", Vector3(w, 0.06, d), Vector3(0, h, 0), 0.02)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box("metal_dark", Vector3(0.06, h, 0.06),
				Vector3(sx * (w * 0.5 - 0.1), h * 0.5, sz * (d * 0.5 - 0.1)))
	kit.pop_xf()


func bench(origin: Vector3, yaw: float, w: float = 2.4) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.57, 27.0)
	kit.set_height_range(0.0, 0.9)
	kit.box_bevel("wall_pad", Vector3(w, 0.12, 0.55), Vector3(0, 0.44, 0), 0.04)
	kit.box("metal_dark", Vector3(w * 0.92, 0.06, 0.45), Vector3(0, 0.34, 0))
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.08, 0.44, 0.45), Vector3(sx * (w * 0.5 - 0.2), 0.22, 0))
	kit.pop_xf()


func shelf(origin: Vector3, yaw: float, w: float = 1.8, h: float = 2.0) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.59, 28.0)
	kit.set_height_range(0.0, h)
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.06, h, 0.5), Vector3(sx * w * 0.5, h * 0.5, 0))
	for i in 4:
		var y := 0.15 + i * (h - 0.2) / 3.0
		kit.box("metal", Vector3(w, 0.04, 0.5), Vector3(0, y, 0))
		for k in 4:
			kit.box("container_c", Vector3(0.28, 0.22, 0.3), Vector3(-w * 0.35 + k * 0.24, y + 0.13, 0))
	kit.pop_xf()


func light_fixture(origin: Vector3, size: Vector2, key: String = "emit_white",
		housing: String = "metal_dark") -> void:
	kit.begin_part(0.35, 29.0)
	kit.box(housing, Vector3(size.x + 0.12, 0.10, size.y + 0.12), origin + Vector3(0, 0.06, 0))
	kit.box(key, Vector3(size.x, 0.03, size.y), origin + Vector3(0, 0.0, 0))


func vent(origin: Vector3, yaw: float, size: Vector2, key: String = "metal_dark") -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.4, 29.0)
	kit.box(key, Vector3(size.x, size.y, 0.06), Vector3.ZERO)
	var n := int(size.y / 0.09)
	for i in n:
		kit.box("metal", Vector3(size.x * 0.86, 0.025, 0.025),
			Vector3(0, -size.y * 0.5 + 0.08 + i * 0.09, 0.04))
	kit.pop_xf()


func door(center: Vector3, yaw: float, width: float = 2.0, height: float = 2.4,
		open_amount: float = 0.55, key: String = "metal") -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), center))
	kit.begin_part(0.7, 30.0)
	kit.set_height_range(0.0, height)
	# frame
	kit.box("metal_dark", Vector3(width + 0.36, 0.18, 0.32), Vector3(0, height + 0.09, 0))
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.18, height + 0.18, 0.32), Vector3(sx * (width * 0.5 + 0.09), height * 0.5, 0))
		kit.box("hazard", Vector3(0.14, height, 0.34), Vector3(sx * (width * 0.5 + 0.02), height * 0.5, 0.02))
	# sliding leaves
	var lw := width * 0.5
	for sx in [-1.0, 1.0]:
		var slide: float = sx * (lw * 0.5 + open_amount * lw * 0.5)
		kit.box_bevel(key, Vector3(lw * (1.0 - open_amount), height - 0.06, 0.09),
			Vector3(slide, (height - 0.06) * 0.5, 0.04), 0.02)
		kit.box("emit_strip_cool", Vector3(0.06, height * 0.8, 0.02), Vector3(slide, height * 0.45, 0.10))
	# status light + keypad
	kit.box("emit_green", Vector3(0.14, 0.05, 0.04), Vector3(width * 0.5 + 0.09, height + 0.24, 0.18))
	kit.box("metal_cast", Vector3(0.18, 0.28, 0.05), Vector3(-width * 0.5 - 0.32, 1.25, 0.18))
	kit.box("screen_power", Vector3(0.14, 0.20, 0.02), Vector3(-width * 0.5 - 0.32, 1.25, 0.21))
	kit.pop_xf()


func stairs(a: Vector3, b: Vector3, width: float = 1.6, key: String = "metal") -> void:
	var d := b - a
	var horiz := Vector3(d.x, 0, d.z)
	var run := horiz.length()
	if run < 0.2:
		return
	var dir := horiz / run
	var steps := maxi(4, int(round(absf(d.y) / 0.19)))
	var rise := d.y / float(steps)
	var tread := run / float(steps)
	var right := dir.cross(Vector3.UP).normalized()
	kit.begin_part(0.55, 31.0)
	for i in steps:
		var c := a + dir * (tread * (float(i) + 0.5)) + Vector3(0, rise * float(i) + rise * 0.5, 0)
		kit.box(key, Vector3(width, absf(rise), tread + 0.03), c)
		kit.box("metal_dark", Vector3(width, 0.02, 0.04), c + Vector3(0, absf(rise) * 0.5, -tread * 0.5))
	# stringers
	for sx in [-1.0, 1.0]:
		var off: Vector3 = right * (width * 0.5 + 0.04) * sx
		beam("metal_dark", a + off + Vector3(0, 0.12, 0), b + off + Vector3(0, 0.12, 0), 0.07, 0.32)
		# handrail
		beam("metal", a + off + Vector3(0, 1.02, 0), b + off + Vector3(0, 1.02, 0), 0.05, 0.05)
		var n := maxi(2, int(run / 1.4))
		for i in n + 1:
			var t := float(i) / float(n)
			var p: Vector3 = a + off + d * t
			kit.box("metal_dark", Vector3(0.06, 1.0, 0.06), p + Vector3(0, 0.5, 0))


func ladder(a: Vector3, b: Vector3, width: float = 0.55) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.5:
		return
	var dir := d / len
	var right := dir.cross(Vector3.FORWARD).normalized()
	if right.length() < 0.2:
		right = dir.cross(Vector3.RIGHT).normalized()
	kit.begin_part(0.45, 31.0)
	for sx in [-0.5, 0.5]:
		beam("metal_dark", a + right * width * sx, b + right * width * sx, 0.05, 0.06)
	var n := int(len / 0.32)
	for i in n:
		var p := a + dir * (float(i) * 0.32 + 0.2)
		kit.box("metal", Vector3(width, 0.035, 0.035), p)


# -------------------------------------------------------------------- decor --
func place_sign(text: String, pos: Vector3, yaw: float, size: float = 0.5,
		color: Color = Color(0.7, 0.9, 1.0), dark: bool = true) -> void:
	var tm := TextMesh.new()
	tm.text = text
	tm.font = ThemeDB.fallback_font
	tm.font_size = 64
	tm.pixel_size = size / 64.0 * 0.55
	tm.depth = 0.03
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.025)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	root.add_child(mi)
	sign_count += 1


func sign_board(text: String, center: Vector3, yaw: float, width: float, height: float,
		color: Color = Color(0.55, 0.85, 1.0), board_key: String = "metal_dark") -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.push_xf(Transform3D(b, center))
	kit.begin_part(0.6, 32.0)
	kit.box_bevel(board_key, Vector3(width, height, 0.10), Vector3.ZERO, 0.03)
	kit.box("emit_strip_cool", Vector3(width * 0.98, 0.035, 0.03), Vector3(0, -height * 0.42, 0.07))
	kit.pop_xf()
	place_sign(text, center + b * Vector3(0, 0, 0.08), yaw, minf(height * 0.52, width / maxf(text.length(), 1.0) * 1.5), color)


func planter(origin: Vector3, w: float = 1.6, d: float = 1.6, h: float = 0.55) -> void:
	kit.begin_part(0.5, 33.0)
	kit.set_height_range(0.0, 2.0)
	kit.box_bevel("metal_dark", Vector3(w, h, d), origin + Vector3(0, h * 0.5, 0), 0.04)
	kit.box("floor_dark", Vector3(w - 0.12, 0.08, d - 0.12), origin + Vector3(0, h - 0.02, 0))
	# bushes
	var n := int(w * d * 2.4)
	for i in n:
		var px := origin.x + rng.randf_range(-w * 0.42, w * 0.42)
		var pz := origin.z + rng.randf_range(-d * 0.42, d * 0.42)
		var py := origin.y + h + rng.randf_range(0.05, 0.35)
		_leaf_cluster(Vector3(px, py, pz), rng.randf_range(0.18, 0.34), 4)


func _leaf_cluster(p: Vector3, size: float, count: int) -> void:
	for i in count:
		var a := rng.randf_range(0.0, TAU)
		var tilt := rng.randf_range(-0.15, 1.15)
		var out := Vector3(cos(a) * cos(tilt), sin(tilt), sin(a) * cos(tilt))
		var side := out.cross(Vector3.UP)
		if side.length() < 0.05:
			side = out.cross(Vector3.RIGHT)
		side = side.normalized()
		var bend := out.cross(side).normalized()
		var l := size * rng.randf_range(0.7, 1.25)
		var w := l * rng.randf_range(0.35, 0.55)
		# folded blade: two quads, slight cup
		var base := p + out * rng.randf_range(0.0, size * 0.35)
		var tip := base + out * l + bend * l * 0.12
		var mid := (base + tip) * 0.5 + bend * l * 0.10
		var l0 := base - side * w
		var r0 := base + side * w
		var l1 := tip - side * w * 0.35
		var r1 := tip + side * w * 0.35
		var nl := (side * -0.45 + bend).normalized()
		var nr := (side * 0.45 + bend).normalized()
		kit.begin_part(0.15 + rng.randf() * 0.7, 33.0)
		kit.quad("plant" if rng.randf() > 0.35 else "plant_b", [l0, mid, l1, tip], bend,
			[Vector2(0, 0), Vector2(0.5, 0.5), Vector2(0.2, 0.9), Vector2(0.5, 1.0)])
		kit.quad("plant" if rng.randf() > 0.35 else "plant_b", [r0, tip, r1, mid], bend,
			[Vector2(1, 0), Vector2(0.5, 1.0), Vector2(0.8, 0.9), Vector2(0.5, 0.5)])


func tree(origin: Vector3, height: float = 3.2, spread: float = 1.6, seed: int = 1) -> void:
	var r2 := RandomNumberGenerator.new()
	r2.seed = seed
	var trunk := [origin, origin + Vector3(0.05, height * 0.45, 0.03),
		origin + Vector3(-0.06, height * 0.72, 0.05)]
	kit.begin_part(0.3, 33.0)
	kit.tube("metal_cast", trunk, 0.09, 6)
	for k in 6:
		var dir := Vector3(r2.randf_range(-1, 1), r2.randf_range(0.6, 1.4), r2.randf_range(-1, 1)).normalized()
		var base := origin + Vector3(0, height * r2.randf_range(0.45, 0.8), 0)
		var branch := [base, base + dir * spread * 0.5, base + dir * spread]
		kit.tube("metal_cast", branch, 0.04, 5)
		for m in 8:
			var p := base + dir * spread * r2.randf_range(0.3, 1.0)
			p += Vector3(r2.randf_range(-0.7, 0.7), r2.randf_range(-0.1, 0.6), r2.randf_range(-0.7, 0.7))
			_leaf_cluster(p, r2.randf_range(0.16, 0.30), 5)


func crop_row(origin: Vector3, length: float, yaw: float, magenta: bool = true) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.45, 34.0)
	kit.box("metal_dark", Vector3(0.9, 0.35, length), Vector3(0, 0.18, 0))
	kit.box("floor_dark", Vector3(0.78, 0.06, length - 0.1), Vector3(0, 0.37, 0))
	# grow-light bar
	kit.box("emit_amber" if not magenta else "emit_blue", Vector3(0.10, 0.05, length), Vector3(0, 2.2, 0))
	kit.box("metal", Vector3(0.42, 0.06, length), Vector3(0, 2.3, 0))
	# plants
	var z := -length * 0.5 + 0.35
	while z < length * 0.5 - 0.2:
		for sx in [-0.28, 0.28]:
			var base := Vector3(sx, 0.4, z)
			for k in 5:
				var h := 0.35 + 0.16 * k
				var p := base + Vector3(rng.randf_range(-0.13, 0.13), h, rng.randf_range(-0.1, 0.1))
				var s := 0.16 + 0.03 * k
				var q := [p + Vector3(-s, 0, 0), p + Vector3(s, 0, 0),
					p + Vector3(s * 0.5, s * 0.7, 0.05), p + Vector3(-s * 0.5, s * 0.7, 0.05)]
				kit.quad("plant" if rng.randf() > 0.4 else "plant_b", q, Vector3.UP)
		z += 0.55
	kit.pop_xf()


func holo_table(origin: Vector3) -> void:
	kit.begin_part(0.4, 35.0)
	kit.set_height_range(0.0, 2.0)
	kit.cyl("metal_painted", 1.15, 1.0, 0.12, 28, origin)
	kit.cyl("metal_dark", 0.9, 0.9, 0.16, 24, origin + Vector3(0, 0.66, 0))
	for i in 6:
		var a := TAU * float(i) / 6.0
		kit.box("metal", Vector3(0.07, 0.62, 0.07),
			origin + Vector3(cos(a) * 0.82, 0.34, sin(a) * 0.82))
	kit.torus("metal_light", 1.16, 0.05, 32, 6, origin + Vector3(0, 0.86, 0))
	kit.torus("emit_cool", 1.06, 0.02, 32, 4, origin + Vector3(0, 0.92, 0))
	# projection volume
	kit.push_xf(Transform3D(Basis(), origin + Vector3(0, 1.1, 0)))
	kit.cyl("holo_dim", 0.30, 0.78, 0.85, 28, Vector3.ZERO, false, 0.0)
	kit.cyl("holo_soft", 0.08, 0.42, 1.0, 20, Vector3.ZERO, false, 0.18)
	kit.torus("holo", 0.62, 0.012, 28, 4, Vector3(0, 0.55, 0))
	kit.pop_xf()


func engine_thruster(origin: Vector3, radius: float, height: float) -> void:
	kit.push_xf(Transform3D(Basis(), origin))
	kit.begin_part(0.5, 36.0)
	# base plinth: two stepped rings
	kit.cyl("metal_cast", radius * 1.28, radius * 1.22, 0.55, 36, Vector3.ZERO)
	kit.cyl("metal_dark", radius * 1.10, radius * 1.02, 0.35, 36, Vector3(0, 0.55, 0))
	kit.torus("metal", radius * 1.20, 0.06, 36, 6, Vector3(0, 0.58, 0))
	# main housing
	kit.cyl("metal_cast", radius * 0.86, radius, height * 0.52, 40, Vector3(0, 0.9, 0))
	kit.cyl("metal_dark", radius * 0.82, radius * 0.90, height * 0.34, 36, Vector3(0, 0.9 + height * 0.52, 0))
	# flare collar
	kit.cyl("metal_cast", radius * 1.02, radius * 0.74, height * 0.16, 36, Vector3(0, 0.9 + height * 0.86, 0))
	kit.torus("metal", radius * 1.04, 0.09, 40, 8, Vector3(0, 0.9 + height * 0.86, 0))
	kit.torus("metal_dark", radius * 1.01, 0.12, 40, 8, Vector3(0, 0.9 + height * 0.50, 0))
	# vertical heat-shield ribs
	for k in 14:
		var a := TAU * float(k) / 14.0
		var rr := radius * 0.94
		kit.box("metal_dark", Vector3(0.16, height * 0.46, 0.30),
			Vector3(cos(a) * rr, 0.9 + height * 0.26, sin(a) * rr))
		kit.box("metal", Vector3(0.22, 0.10, 0.36),
			Vector3(cos(a) * rr, 0.9 + height * 0.47, sin(a) * rr))
	# glowing annular conduit + injector pipes
	kit.torus("plasma_conduit", radius * 0.99, 0.055, 40, 6, Vector3(0, 0.9 + height * 0.62, 0))
	for k in 8:
		var a := TAU * float(k) / 8.0 + 0.2
		var pts := [
			Vector3(cos(a) * radius * 1.24, 0.2, sin(a) * radius * 1.24),
			Vector3(cos(a) * radius * 1.13, height * 0.34, sin(a) * radius * 1.13),
			Vector3(cos(a) * radius * 0.95, height * 0.62, sin(a) * radius * 0.95),
			Vector3(cos(a) * radius * 0.78, height * 0.86, sin(a) * radius * 0.78),
		]
		kit.tube("pipe_teal" if k % 2 == 0 else "pipe_orange", pts, 0.055, 6)
	# throttle valve wheel and gauge panel
	kit.begin_part(0.62, 36.0)
	kit.box("metal_dark", Vector3(0.8, 1.1, 0.22), Vector3(radius * 0.9, 1.4, 0.0))
	kit.box("screen_eng", Vector3(0.62, 0.52, 0.03), Vector3(radius * 0.9, 1.55, 0.13))
	kit.box("metal_dark", Vector3(0.55, 0.25, 0.22), Vector3(radius * 0.9, 1.05, 0.0))
	kit.torus("metal", 0.16, 0.03, 14, 5, Vector3(radius * 0.9, 0.85, 0.25))
	kit.box("hazard", Vector3(radius * 1.9, 0.16, 0.05), Vector3(0, 0.28, radius * 1.19))
	# maintenance ladder
	props_ladder_on_housing(Vector3(radius * 1.05, 0.5, -radius * 0.85), 2.4)
	# top glow throat
	kit.cyl("plasma_engine", radius * 0.30, radius * 0.55, height * 0.10, 28,
		Vector3(0, 0.9 + height * 0.98, 0), false)
	# exhaust duct cage above
	for k in 6:
		var a := TAU * float(k) / 6.0
		props_beam_local(Vector3(cos(a) * radius * 0.55, 1.0 + height * 0.98, sin(a) * radius * 0.55),
			Vector3(cos(a) * radius * 0.62, 2.6 + height * 0.98, sin(a) * radius * 0.62), 0.10)
	kit.pop_xf()


func props_beam_local(a: Vector3, b: Vector3, w: float) -> void:
	beam("metal_dark", kit.xf() * a, kit.xf() * b, w, w)


func props_ladder_on_housing(base: Vector3, h: float) -> void:
	var w := 0.45
	for sx in [-0.5, 0.5]:
		kit.box("metal_dark", Vector3(0.05, h, 0.05), base + Vector3(sx * w, h * 0.5, 0))
	var n := int(h / 0.28)
	for i in n:
		kit.box("metal", Vector3(w, 0.03, 0.03), base + Vector3(0, 0.2 + i * 0.28, 0))


func shopfront(x0: float, x1: float, z0: float, z1: float, y: float,
		name: String, accent: Color, warm: bool = true) -> void:
	var zc := (z0 + z1) * 0.5
	var depth := 2.8
	# shop interior shell (behind a glass front)
	kit.begin_part(0.5, 37.0)
	kit.set_height_range(y, y + 3.6)
	kit.box("floor_warm", Vector3(x1 - x0, 0.16, z1 - z0), Vector3((x0 + x1) * 0.5, y + 0.08, zc))
	kit.box("wall_warm", Vector3(x1 - x0, 0.16, z1 - z0), Vector3((x0 + x1) * 0.5, y + 3.5, zc))
	kit.box("wall_warm", Vector3(0.16, 3.6, z1 - z0), Vector3(x1, y + 1.8, zc))
	kit.box("wall_warm", Vector3(0.16, 3.6, 1.0), Vector3(x0, y + 1.8, z0 + 0.5))
	kit.box("wall_warm", Vector3(0.16, 3.6, 1.0), Vector3(x0, y + 1.8, z1 - 0.5))
	# glass frontage
	var front_x := x0 if x0 > 0.0 else x1
	var inward := -1.0 if x0 > 0.0 else 1.0
	kit.box("glass", Vector3(0.05, 2.9, z1 - z0 - 2.2), Vector3(front_x, y + 1.55, zc))
	for k in 3:
		kit.box("metal_dark", Vector3(0.09, 3.1, 0.09),
			Vector3(front_x, y + 1.55, z0 + 1.1 + k * (z1 - z0 - 2.2) / 2.0))
	# sign band
	var sx := x0 + 0.15 if x0 > 0.0 else x1 - 0.15
	kit.begin_part(0.6, 37.0)
	kit.box("metal_dark", Vector3(0.16, 0.7, z1 - z0 - 1.0), Vector3(sx, y + 3.05, zc))
	kit.box("emit_strip_warm" if warm else "emit_cool", Vector3(0.05, 0.06, z1 - z0 - 1.4),
		Vector3(sx + inward * 0.06, y + 2.74, zc))
	var yaw := -PI * 0.5 if x0 > 0.0 else PI * 0.5
	place_sign(name, Vector3(sx + inward * 0.12, y + 3.05, zc), yaw, 0.50, accent)
	# interior fittings: counter + shelves + display
	var inner_x := x0 + 0.9 if x0 > 0.0 else x1 - 0.9
	kit.begin_part(0.7, 37.0)
	kit.box_bevel("metal_painted", Vector3(0.8, 1.0, z1 - z0 - 2.4), Vector3(inner_x, y + 0.5, zc), 0.03)
	kit.box("metal", Vector3(0.9, 0.06, z1 - z0 - 2.2), Vector3(inner_x, y + 1.02, zc))
	shelf(Vector3(inner_x + inward * -1.1, y, zc), PI * 0.5, 1.8, 2.2)
	for k in 4:
		kit.box("emit_warm", Vector3(0.08, 0.04, 1.2), Vector3(inner_x, y + 1.9, z0 + 1.8 + k * 1.4))
	# warm interior light
	var l := OmniLight3D.new()
	l.position = Vector3(inner_x, y + 2.4, zc)
	l.light_color = Color(1.0, 0.78, 0.52) if warm else Color(0.5, 0.85, 1.0)
	l.light_energy = 2.0
	l.omni_range = 8.0
	l.shadow_enabled = false
	root.add_child(l)


func shuttle(origin: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.35, 38.0)
	kit.set_height_range(0.0, 4.0)
	# fuselage: lathed teardrop along local Z
	var prof: Array = []
	for i in 14:
		var t := float(i) / 13.0
		var r := 1.55 * sin(pow(t, 0.62) * PI) * (0.55 + 0.45 * t)
		prof.append(Vector2(maxf(r, 0.04), -4.6 + t * 9.2))
	kit.push_xf(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 1.7, 0)))
	kit.lathe("hull", prof, 24)
	kit.pop_xf()
	# canopy
	kit.box("glass_dark", Vector3(1.4, 0.42, 1.8), Vector3(0, 2.55, -2.2))
	# wings
	for sx in [-1.0, 1.0]:
		var wing := [Vector3(sx * 1.2, 1.5, -0.8), Vector3(sx * 4.6, 1.2, 1.4),
			Vector3(sx * 4.6, 1.35, 2.1), Vector3(sx * 1.2, 1.7, 1.8)]
		kit.quad("hull_dark", wing, Vector3.UP)
		kit.box("metal_dark", Vector3(0.12, 0.5, 1.2), Vector3(sx * 4.4, 1.4, 1.6))
		kit.cyl("metal_cast", 0.45, 0.55, 1.0, 16, Vector3(sx * 2.4, 1.1, 2.2))
	# engines + skids
	for sx in [-1.0, 1.0]:
		kit.cyl("metal_dark", 0.5, 0.62, 1.6, 16, Vector3(sx * 1.5, 1.4, 4.3))
		kit.cyl("plasma_engine", 0.4, 0.5, 1.2, 16, Vector3(sx * 1.5, 1.4, 5.3), false)
		beam("metal_dark", Vector3(sx * 1.3, 0.25, -2.0), Vector3(sx * 1.3, 0.85, -1.2), 0.08, 0.08)
		beam("metal_dark", Vector3(sx * 1.3, 0.25, 2.4), Vector3(sx * 1.3, 0.85, 2.8), 0.08, 0.08)
	kit.pop_xf()

func captain_chair(origin: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.42, 67.0)
	kit.set_height_range(0.0, 2.2)
	# pedestal
	kit.cyl("metal_dark", 0.42, 0.30, 0.28, 20, Vector3(0, 0.0, 0))
	kit.cyl("metal", 0.12, 0.12, 0.34, 10, Vector3(0, 0.28, 0))
	# seat
	kit.box_bevel("metal_painted", Vector3(0.92, 0.22, 0.86), Vector3(0, 0.66, 0), 0.06)
	kit.box_bevel("rubber", Vector3(0.80, 0.10, 0.74), Vector3(0, 0.82, 0), 0.04)
	kit.box("emit_strip_cool", Vector3(0.86, 0.03, 0.06), Vector3(0, 0.68, -0.42))
	# high back + headrest
	var back := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0, 1.30, 0.40))
	kit.push_xf(back)
	kit.box_bevel("metal_painted", Vector3(0.94, 1.02, 0.16), Vector3.ZERO, 0.05)
	kit.box_bevel("rubber", Vector3(0.78, 0.86, 0.08), Vector3(0, 0.02, -0.10), 0.04)
	kit.box("emit_cool", Vector3(0.30, 0.04, 0.03), Vector3(0, 0.40, -0.16))
	kit.box_bevel("metal_painted", Vector3(0.60, 0.24, 0.16), Vector3(0, 0.62, 0.02), 0.05)
	kit.pop_xf()
	# armrests with small command screens
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.12, 0.10, 0.70), Vector3(sx * 0.54, 0.98, 0.02))
		kit.box("metal_dark", Vector3(0.10, 0.30, 0.10), Vector3(sx * 0.54, 0.84, 0.32))
		var arm := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-24.0)), Vector3(sx * 0.62, 1.10, -0.12))
		kit.push_xf(arm)
		kit.box("metal_dark", Vector3(0.22, 0.05, 0.34), Vector3.ZERO)
		kit.box("screen_nav", Vector3(0.18, 0.02, 0.28), Vector3(0, 0.035, 0))
		kit.pop_xf()
	# foot rest + status ring
	kit.box("metal_dark", Vector3(0.5, 0.06, 0.3), Vector3(0, 0.24, -0.52))
	kit.torus("emit_seg_blue", 0.62, 0.012, 28, 4, Vector3(0, 0.06, 0))
	kit.pop_xf()

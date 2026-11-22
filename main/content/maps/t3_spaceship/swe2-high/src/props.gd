extends RefCounted

const GeoKit = preload("res://src/kit.gd")
const ShipLayout = preload("res://src/layout.gd")
const StructGen = preload("res://src/struct.gd")

## Furniture & machinery kit: consoles, racks, crates, tanks, pipes, girders,
## bunks, tables, holo emitters. Everything writes into the shared GeoKit.

var k: GeoKit


func _init(kit: GeoKit) -> void:
	k = kit


# ------------------------------------------------------------- consoles -----
## Console row along a wall: wedge body + tilted screen + edge light.
## dir: which way the console faces (unit-ish Vector3 in XZ).
func console(x: float, y: float, z: float, dir := 1.0, w := 1.6,
		screen := "screen_a") -> void:
	var b := Basis(Vector3.UP, 0.0 if dir > 0 else PI)
	k.push(Transform3D(b, Vector3(x, y, z)))
	k.part(-1.0, 0.0, 1.0)
	# body: sloped pedestal
	k.boxb("metal_a", Vector3(w, 0.85, 0.55), Vector3(0, 0.42, 0), 0.04)
	k.push(Transform3D(Basis(Vector3.RIGHT, -0.42), Vector3(0, 0.9, -0.05)))
	k.box("dark", Vector3(w - 0.08, 0.05, 0.42))
	k.box(screen, Vector3(w - 0.16, 0.02, 0.34), Vector3(0, 0.035, 0))
	k.pop()
	# lower kick light
	k.box("u_light_c", Vector3(w - 0.2, 0.035, 0.03), Vector3(0, 0.12, 0.30))
	k.pop()


## Freestanding control pedestal with holo emitter.
func pedestal(p: Vector3, screen := "screen_b") -> void:
	k.push(Transform3D(Basis(), p))
	k.part(-1.0, 0.0, 1.0)
	k.cyl("metal_d", 0.35, 0.42, 0.9, 12, Vector3.ZERO, true)
	k.cyl("dark", 0.30, 0.30, 0.06, 12, Vector3(0, 0.9, 0), true)
	k.box(screen, Vector3(0.4, 0.02, 0.28), Vector3(0, 0.96, 0))
	k.cyl("u_light_c", 0.18, 0.14, 0.10, 10, Vector3(0, 0.96, 0), true)
	k.pop()


# ---------------------------------------------------------------- racks -----
## Server rack wall: box + vent slats + status LEDs.
func rack(x: float, y: float, z: float, w := 0.8, h := 2.1, d := 0.55) -> void:
	k.push(Transform3D(Basis(), Vector3(x, y, z)))
	k.part(-1.0, 0.0, 1.2)
	k.boxb("metal_a", Vector3(w, h, d), Vector3(0, h * 0.5, 0), 0.02)
	# vent slats on front
	for i in 6:
		var yy := 0.25 + i * 0.28
		k.box("dark", Vector3(w - 0.14, 0.16, 0.02), Vector3(0, yy, d * 0.5 + 0.005))
	# LED column
	for i in 4:
		var c := "u_light" if k.rng.randf() > 0.25 else "u_light_r"
		k.box(c, Vector3(0.05, 0.03, 0.03), Vector3(w * 0.32, 0.4 + i * 0.42, d * 0.5 + 0.01))
	k.pop()


# ---------------------------------------------------------------- crates ----
## Shipping container stack. size ~ 2.4 or 4.8 m module.
func crate(p: Vector3, s := 2.4, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	k.push(Transform3D(b, p))
	k.part(-1.0, 0.0, 0.9)
	var h := s * 0.55
	k.boxb("crate", Vector3(s, h, s * 0.55), Vector3(0, h * 0.5, 0), 0.05)
	# corner castings
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			k.box("dark", Vector3(0.14, 0.14, 0.14),
				Vector3(sx * s * 0.47, h - 0.07, sz * s * 0.24))
	k.pop()


## Small stowage box.
func stow(p: Vector3, s := 0.8, yaw := 0.0) -> void:
	k.push(Transform3D(Basis(Vector3.UP, yaw), p))
	k.part(-1.0, 0.0, 1.1)
	k.boxb("metal_b", Vector3(s, s * 0.55, s * 0.7), Vector3(0, s * 0.28, 0), 0.04)
	k.box("hazard", Vector3(s * 0.9, 0.05, s * 0.65), Vector3(0, 0.03, 0))
	k.pop()


# ----------------------------------------------------------------- tanks ----
## Horizontal cylindrical tank, axis along Z (caps both ends), saddle mounts.
func tank_z(p: Vector3, r := 1.2, len := 4.0, mat := "metal_b") -> void:
	k.push(Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), p))
	k.part(-1.0, 0.0, 1.0)
	k.cyl(mat, r, r, len, 18, Vector3(0, -len * 0.5, 0), true)
	k.pop()
	# saddles
	for d in [-len * 0.3, len * 0.3]:
		k.box("metal_a", Vector3(r * 1.7, 0.35, 0.5),
			Vector3(p.x, p.y - r - 0.15, p.z + d))
	# top valve
	k.cyl("metal_d", 0.12, 0.12, 0.3, 8, Vector3(p.x, p.y + r, p.z), true)


func tank_x(p: Vector3, r := 1.2, len := 4.0, mat := "metal_b") -> void:
	k.push(Transform3D(Basis(Vector3.FORWARD, PI / 2.0) * Basis(Vector3.RIGHT, -PI / 2.0), p))
	k.part(-1.0, 0.0, 1.0)
	k.cyl(mat, r, r, len, 18, Vector3(0, -len * 0.5, 0), true)
	k.pop()
	for d in [-len * 0.3, len * 0.3]:
		k.box("metal_a", Vector3(0.5, 0.35, r * 1.7),
			Vector3(p.x + d, p.y - r - 0.15, p.z))
	k.cyl("metal_d", 0.12, 0.12, 0.3, 8, Vector3(p.x, p.y + r, p.z), true)


## Vertical pressure vessel with legs.
func vessel(p: Vector3, r := 1.0, h := 3.4, mat := "metal_b") -> void:
	k.part(-1.0, 0.0, 1.0)
	var prof := [Vector2(r * 0.6, 0), Vector2(r, 0.5), Vector2(r, h - 0.5),
		Vector2(r * 0.6, h), Vector2(0.0, h + 0.2)]
	k.lathe(mat, prof, 16, p)
	for i in 4:
		var a := TAU * i / 4 + PI / 4
		k.box("metal_a", Vector3(0.18, 0.8, 0.18),
			Vector3(p.x + cos(a) * r * 0.8, p.y + 0.3, p.z + sin(a) * r * 0.8))
	k.cyl("u_light_o", 0.06, 0.06, h + 0.15, 6,
		Vector3(p.x + r + 0.05, p.y, p.z), true)


# ----------------------------------------------------------------- pipes ----
## Pipe run helper: polyline + optional elbow joints + hangers.
func pipe(pts: Array, r := 0.12, mat := "copper", hanger_y := -1.0) -> void:
	k.tube(mat, pts, r, 8, true)
	for i in range(1, pts.size() - 1):
		k.sphere(mat, r * 1.35, 8, pts[i])
	if hanger_y > -100.0:
		# drop hangers every ~3 m along the run
		var d := 0.0
		for i in range(pts.size() - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var seg := a.distance_to(b)
			var n := int(seg / 3.0)
			for j in n:
				var p := a.lerp(b, float(j) / maxf(n, 1.0))
				var top := Vector3(p.x, hanger_y, p.z)
				if top.y > p.y + r:
					k.cyl("metal_a", 0.03, 0.03, top.y - p.y - r, 5, p + Vector3(0, r, 0), true)
			d += seg


## Cable bundle: several parallel sagging curves between two points.
func cable_sag(a: Vector3, b: Vector3, sag := 0.4, n := 3, r := 0.03) -> void:
	for i in n:
		var off := Vector3(0, -0.02 * i, 0.05 * (i - n * 0.5))
		var mid := (a + b) * 0.5 + Vector3(0, -sag, 0) + off * 2.0
		var q1 := a.lerp(mid, 0.5)
		var q2 := mid.lerp(b, 0.5)
		k.tube("dark", [a + off, q1, mid, q2, b + off], r, 6, true)


# ---------------------------------------------------------------- girder ----
## I-beam between two points (flange+web approximation via 3 boxes).
func ibeam(a: Vector3, b: Vector3, w := 0.3, mat := "metal_a") -> void:
	var dir := (b - a)
	var len := dir.length()
	var mid := (a + b) * 0.5
	var b2 := Basis()
	b2 = Basis.looking_at(dir.normalized(), Vector3.UP) if absf(dir.normalized().y) < 0.99 else Basis(Vector3.RIGHT, PI / 2.0)
	k.push(Transform3D(b2, mid))
	k.part(-1.0, 0.0, 1.1)
	k.box(mat, Vector3(w, w * 0.35, len), Vector3(0, w * 0.35, 0))
	k.box(mat, Vector3(w * 0.3, w, len), Vector3(0, 0, 0))
	k.box(mat, Vector3(w, w * 0.35, len), Vector3(0, -w * 0.35, 0))
	k.pop()


## Lattice truss column.
func truss_col(p: Vector3, h := 6.0, s := 0.5) -> void:
	for i in 4:
		var a := TAU * i / 4 + PI / 4
		k.box("metal_a", Vector3(0.09, h, 0.09),
			Vector3(p.x + cos(a) * s, p.y + h * 0.5, p.z + sin(a) * s))
	var n := int(h / 0.9)
	for j in n:
		var y0 := p.y + j * 0.9
		for i in 4:
			var a0 := TAU * i / 4 + PI / 4
			var a1 := TAU * (i + 1) / 4 + PI / 4
			var p0 := Vector3(p.x + cos(a0) * s, y0, p.z + sin(a0) * s)
			var p1 := Vector3(p.x + cos(a1) * s, y0 + 0.9, p.z + sin(a1) * s)
			k.tube("metal_a", [p0, p1], 0.035, 5, true)


# ----------------------------------------------------------------- misc -----
## Ceiling omni fixture: glowing bar + housing.
func lightbar(p: Vector3, len := 1.4, axis_z := true, mat := "u_light") -> void:
	k.part(-1.0, 0.0, 1.0)
	var sz := Vector3(0.5, 0.10, len) if axis_z else Vector3(len, 0.10, 0.5)
	k.box(mat, sz, p)
	var hs := Vector3(0.62, 0.10, len + 0.06) if axis_z else Vector3(len + 0.06, 0.10, 0.62)
	k.box("dark", hs, p + Vector3(0, 0.10, 0))


## Bed / bunk module.
func bunk(p: Vector3, yaw := 0.0, levels := 2) -> void:
	k.push(Transform3D(Basis(Vector3.UP, yaw), p))
	k.part(-1.0, 0.0, 0.9)
	var w := 0.95
	var l := 2.1
	for lvl in levels:
		var yy := 0.35 + lvl * 0.95
		k.boxb("metal_d", Vector3(w, 0.12, l), Vector3(0, yy, 0), 0.02)
		k.boxb("fabric", Vector3(w - 0.1, 0.14, l - 0.15), Vector3(0, yy + 0.12, 0), 0.05)
		k.box("fabric_b", Vector3(w - 0.2, 0.08, 0.4), Vector3(0, yy + 0.2, -l * 0.38))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			k.cyl("metal_d", 0.035, 0.035, 1.55, 6,
				Vector3(sx * w * 0.48, 0.0, sz * l * 0.47), true)
	k.box("u_segm", Vector3(w - 0.3, 0.05, 0.05), Vector3(0, 1.9, l * 0.48))
	k.pop()


## Mess table + bench.
func table(p: Vector3, yaw := 0.0) -> void:
	k.push(Transform3D(Basis(Vector3.UP, yaw), p))
	k.part(-1.0, 0.0, 0.9)
	k.boxb("metal_d", Vector3(1.6, 0.06, 0.9), Vector3(0, 0.76, 0), 0.02)
	for sx in [-0.6, 0.6]:
		k.box("metal_a", Vector3(0.1, 0.72, 0.7), Vector3(sx, 0.38, 0))
	for s in [-1, 1]:
		k.boxb("fabric", Vector3(1.4, 0.08, 0.4), Vector3(0, 0.46, s * 0.75), 0.03)
		k.box("metal_a", Vector3(0.08, 0.42, 0.34), Vector3(0, 0.22, s * 0.75))
	k.pop()


## Chair.
func chair(p: Vector3, yaw := 0.0, mat := "fabric") -> void:
	k.push(Transform3D(Basis(Vector3.UP, yaw), p))
	k.part(-1.0, 0.0, 1.0)
	k.cyl("metal_d", 0.05, 0.16, 0.45, 8, Vector3.ZERO, true)
	k.boxb(mat, Vector3(0.5, 0.09, 0.48), Vector3(0, 0.5, 0), 0.05)
	k.boxb(mat, Vector3(0.5, 0.55, 0.09), Vector3(0, 0.82, -0.24), 0.05)
	k.pop()


## Captain's chair (bigger, with side consoles).
func big_chair(p: Vector3, yaw := 0.0) -> void:
	k.push(Transform3D(Basis(Vector3.UP, yaw), p))
	k.part(-1.0, 0.0, 1.0)
	k.cyl("metal_d", 0.18, 0.5, 0.5, 12, Vector3.ZERO, true)
	k.boxb("metal_a", Vector3(0.85, 0.14, 0.8), Vector3(0, 0.58, 0), 0.06)
	k.boxb("metal_a", Vector3(0.85, 0.9, 0.14), Vector3(0, 1.1, -0.4), 0.06)
	for s in [-1, 1]:
		k.boxb("metal_a", Vector3(0.16, 0.3, 0.7), Vector3(s * 0.5, 0.72, 0.05), 0.04)
		k.box("screen_c", Vector3(0.12, 0.05, 0.4), Vector3(s * 0.5, 0.9, 0.08))
	k.pop()


## Holo emitter column: base + glass column + hologram inside.
func holo_column(p: Vector3, h := 2.2, r := 0.5) -> void:
	k.part(-1.0, 0.0, 1.0)
	k.cyl("metal_d", r + 0.1, r + 0.16, 0.25, 14, p, true)
	k.cyl("u_light_c", r - 0.08, r - 0.14, 0.10, 12, p + Vector3(0, 0.25, 0), true)
	k.cyl("glass", r, r, h - 0.4, 18, p + Vector3(0, 0.3, 0), false)
	# inner hologram: stacked rings + core column
	for i in 5:
		var t := float(i) / 4.0
		var rr := r * (0.2 + sin(t * PI) * 0.5)
		k.torus("holo", rr, 0.03, 14, 5,
			p + Vector3(0, 0.35 + t * (h - 0.8), 0))
	k.cyl("holo", r * 0.1, r * 0.04, h - 0.5, 8, p + Vector3(0, 0.3, 0), true)
	k.cyl("metal_a", r - 0.1, r + 0.05, 0.2, 14, p + Vector3(0, h - 0.1, 0), true)


## Potted plant cluster for habitat areas.
func plant_pot(p: Vector3, s := 1.0) -> void:
	k.part(-1.0, 0.0, 1.0)
	var prof := [Vector2(0.18 * s, 0), Vector2(0.26 * s, 0.18 * s),
		Vector2(0.3 * s, 0.42 * s), Vector2(0.27 * s, 0.44 * s)]
	k.lathe("metal_b", prof, 10, p)
	# foliage cards: crossed quads at random tilts
	var rn := k.rng
	for i in 7:
		var a := TAU * i / 7 + rn.randf() * 0.5
		var tilt := 0.5 + rn.randf() * 0.5
		var hh := 0.35 + rn.randf() * 0.25
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -tilt)
		k.push(Transform3D(b, p + Vector3(0, 0.4 * s, 0)))
		k.part(rn.randf(), 0.0, 1.0)
		k.quad("plant",
			[Vector3(-0.35 * s * hh, 0, 0), Vector3(0.35 * s * hh, 0, 0),
			 Vector3(0.3 * s * hh, 0.8 * s * hh, 0), Vector3(-0.3 * s * hh, 0.8 * s * hh, 0)],
			Vector3.BACK,
			[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		k.pop()


## Bench along a wall.
func bench(p: Vector3, len := 2.2, yaw := 0.0) -> void:
	k.push(Transform3D(Basis(Vector3.UP, yaw), p))
	k.part(-1.0, 0.0, 1.0)
	k.boxb("fabric", Vector3(len, 0.1, 0.5), Vector3(0, 0.45, 0), 0.04)
	for sx in [-len * 0.4, len * 0.4]:
		k.box("metal_a", Vector3(0.1, 0.4, 0.44), Vector3(sx, 0.22, 0))
	k.boxb("fabric", Vector3(len, 0.5, 0.08), Vector3(0, 0.75, -0.24), 0.04)
	k.pop()


## Grated catwalk strip between two points (floor plate + rails both sides).
func catwalk(a: Vector3, b: Vector3, w := 1.6) -> void:
	var d := (b - a)
	var len := d.length()
	var mid := (a + b) * 0.5
	var yaw := atan2(d.x, d.z)
	k.push(Transform3D(Basis(Vector3.UP, yaw), mid))
	k.part(-1.0, 0.0, 1.0)
	k.box("floor_a", Vector3(w, 0.08, len))
	# support corbels
	for t in [0.15, 0.5, 0.85]:
		var zz: float = (t - 0.5) * len
		k.box("metal_a", Vector3(w + 0.3, 0.18, 0.25), Vector3(0, -0.13, zz))
	k.pop()
	var side := Vector3(d.z, 0, -d.x).normalized() * w * 0.5
	var s := StructGen.new(k, ShipLayout.new())
	s.rail("metal_d", a + side + Vector3(0, 0.04, 0), b + side + Vector3(0, 0.04, 0))
	s.rail("metal_d", a - side + Vector3(0, 0.04, 0), b - side + Vector3(0, 0.04, 0))


## Wall-mounted tool board with gear silhouette.
func tool_board(x: float, y: float, z: float, w := 1.4, h := 1.2) -> void:
	k.push(Transform3D(Basis(), Vector3(x, y, z)))
	k.part(-1.0, 0.0, 1.0)
	k.box("metal_b", Vector3(w, h, 0.05), Vector3(0, h * 0.5, 0))
	var rn := k.rng
	for i in 8:
		var gx := -w * 0.4 + rn.randf() * w * 0.8
		var gy := 0.15 + rn.randf() * (h - 0.3)
		k.box("dark", Vector3(0.06 + rn.randf() * 0.14, 0.15 + rn.randf() * 0.2, 0.03),
			Vector3(gx, gy, 0.04))
	k.pop()

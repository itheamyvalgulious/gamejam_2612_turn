class_name PropsCore
extends RefCounted
## Reusable prop assembly helpers (furniture, machinery, fixtures).

var g: Geom
var rng := RandomNumberGenerator.new()

const COL_MACH := Color(0.42, 0.43, 0.47)
const COL_DARK := Color(0.22, 0.23, 0.25)
const COL_LIGHT := Color(0.62, 0.64, 0.68)
const COL_WHITE := Color(0.85, 0.86, 0.88)
const COL_WARM := Color(0.55, 0.42, 0.3)
const COL_FAB := Color(0.45, 0.34, 0.27)
const COL_FAB2 := Color(0.32, 0.4, 0.5)
const COL_GREEN := Color(0.28, 0.52, 0.24)
const COL_GREEN2 := Color(0.35, 0.62, 0.28)
const COL_RED := Color(0.6, 0.16, 0.12)
const COL_BLUE := Color(0.22, 0.36, 0.6)
const COL_YELLOW := Color(0.72, 0.58, 0.16)
const COL_CYAN := Color(0.3, 0.6, 0.75)
const COL_STEEL := Color(0.5, 0.51, 0.55)

func _init(geom: Geom) -> void:
	g = geom

func seed_room(r: Dictionary) -> void:
	rng.seed = hash(r["name"]) + int(float(r["seed"]) * 977.0)

# ---------------------------------------------------------------- basics

func boxf(key: String, x: float, y: float, z: float, sx: float, sy: float, sz: float, col: Color, rot: float = 0.0) -> void:
	g.box(key, Vector3(x, y, z), Vector3(sx, sy, sz), col, rot)

func cylx(key: String, a: Vector3, b: Vector3, r: float, col: Color, seg: int = 12) -> void:
	g.cylinder(key, a, b, r, col, seg)

## Strip light box along x or z.
func strip_along(key: String, a: Vector3, b: Vector3, w: float) -> void:
	if absf(a.z - b.z) < 0.01:
		var len := absf(b.x - a.x)
		g.box(key, Vector3((a.x + b.x) * 0.5, a.y, a.z), Vector3(len, 0.06, w), Color.WHITE)
	else:
		var len := absf(b.z - a.z)
		g.box(key, Vector3(a.x, a.y, (a.z + b.z) * 0.5), Vector3(w, 0.06, len), Color.WHITE)

## Tilted screen quad with unit UVs + bezel frame. facing = yaw of viewer direction.
func screen_panel(key: String, pos: Vector3, rot_y: float, w: float, h: float, tilt: float = 0.0) -> void:
	var b := Basis(Vector3.UP, rot_y)
	var ct := cos(tilt); var st := sin(tilt)
	var bl := pos + b * Vector3(-w * 0.5, 0.0, 0.0)
	var br := pos + b * Vector3(w * 0.5, 0.0, 0.0)
	var tr := pos + b * Vector3(w * 0.5, h * ct, -h * st)
	var tl := pos + b * Vector3(-w * 0.5, h * ct, -h * st)
	g.quad_uv(key, bl, br, tr, tl, Color.WHITE)
	# bezel
	var bez := 0.05
	g.box("metal_dark", pos + b * Vector3(0, h * 0.5 * ct, -h * 0.5 * st + 0.06), Vector3(w + bez * 2.0, h + bez * 2.0, 0.04), COL_DARK, rot_y)

## Wall-mounted flat screen.
func wall_screen(key: String, pos: Vector3, facing: Vector3, w: float, h: float) -> void:
	var rot := atan2(facing.x, facing.z)
	screen_panel(key, pos - Vector3(0, h * 0.5, 0) + facing * 0.0, rot, w, h)

# ---------------------------------------------------------------- furniture

func chair(pos: Vector3, rot_y: float, col: Color) -> void:
	var b := Basis(Vector3.UP, rot_y)
	g.cylinder("metal_dark", pos, pos + Vector3(0, 0.42, 0), 0.05, COL_DARK, 8)
	g.box("metal", pos + b * Vector3(0, 0.45, 0) + Vector3(0, 0, 0), Vector3(0.46, 0.07, 0.46), col, rot_y)
	g.box("metal", pos + b * Vector3(0, 0.72, -0.21), Vector3(0.44, 0.5, 0.07), col, rot_y)
	for k in 4:
		var dx := (0.2 if k % 2 == 0 else -0.2)
		var dz := (0.2 if k < 2 else -0.2)
		var lp := pos + b * Vector3(dx, 0.04, dz)
		g.cylinder("metal_dark", lp, lp + Vector3(0, 0.06, 0), 0.03, COL_DARK, 6)

func stool(pos: Vector3, col: Color) -> void:
	g.cylinder("metal_dark", pos, pos + Vector3(0, 0.52, 0), 0.04, COL_DARK, 6)
	g.cylinder("metal", pos + Vector3(0, 0.55, 0), pos + Vector3(0, 0.6, 0), 0.19, col, 10)
	g.torus("metal_dark", pos + Vector3(0, 0.22, 0), Basis(), 0.16, 0.02, COL_DARK, 10, 6)

## Console desk with tilted screen. rot_y = direction the operator faces.
func console(pos: Vector3, rot_y: float, screen_key: String, w: float = 1.7) -> void:
	var b := Basis(Vector3.UP, rot_y)
	g.box("metal_dark", pos + b * Vector3(0, 0.42, 0), Vector3(w, 0.84, 0.72), COL_MACH, rot_y)
	g.box("metal", pos + b * Vector3(0, 0.86, 0.05), Vector3(w + 0.08, 0.05, 0.8), COL_LIGHT, rot_y)
	# tilted screen at back of desk
	screen_panel(screen_key, pos + b * Vector3(0, 0.92, -0.3), rot_y, w * 0.82, 0.5, 0.0)
	# keyboard slab
	g.box("metal_dark", pos + b * Vector3(0, 0.9, 0.18), Vector3(w * 0.6, 0.03, 0.22), COL_DARK, rot_y)
	# side cheeks + status strip
	g.box("metal_dark", pos + b * Vector3(-w * 0.5 - 0.05, 0.5, 0), Vector3(0.1, 1.0, 0.78), COL_DARK, rot_y)
	g.box("metal_dark", pos + b * Vector3(w * 0.5 + 0.05, 0.5, 0), Vector3(0.1, 1.0, 0.78), COL_DARK, rot_y)
	g.box("strip_cyan", pos + b * Vector3(0, 0.2, 0.37), Vector3(w * 0.7, 0.05, 0.02), Color.WHITE, rot_y)

func desk(pos: Vector3, rot_y: float, screen_key: String, w: float = 1.6) -> void:
	var b := Basis(Vector3.UP, rot_y)
	g.box("metal", pos + b * Vector3(0, 0.74, 0), Vector3(w, 0.05, 0.8), COL_LIGHT, rot_y)
	for s in [-1.0, 1.0]:
		g.box("metal_dark", pos + b * Vector3(s * (w * 0.5 - 0.06), 0.36, 0), Vector3(0.08, 0.72, 0.7), COL_DARK, rot_y)
	screen_panel(screen_key, pos + b * Vector3(0, 0.8, -0.26), rot_y, w * 0.55, 0.36, 0.0)

func locker(pos: Vector3, rot_y: float, n: int, w: float, h: float, d: float, col: Color) -> void:
	var b := Basis(Vector3.UP, rot_y)
	g.box("metal", pos + b * Vector3(0, h * 0.5, 0), Vector3(w, h, d), col, rot_y)
	var cw := w / float(n)
	for i in n:
		var cx := -w * 0.5 + cw * (float(i) + 0.5)
		g.box("metal_dark", pos + b * Vector3(cx, h * 0.55, d * 0.5 + 0.01), Vector3(cw * 0.86, h * 0.8, 0.02), col.darkened(0.12), rot_y)
		g.box("metal_dark", pos + b * Vector3(cx + cw * 0.3, h * 0.55, d * 0.5 + 0.035), Vector3(0.03, 0.16, 0.03), COL_DARK, rot_y)
		g.box("metal_dark", pos + b * Vector3(cx, h * 0.88, d * 0.5 + 0.02), Vector3(cw * 0.5, 0.05, 0.02), COL_DARK, rot_y)

func bunk(pos: Vector3, rot_y: float, tiers: int, col: Color) -> void:
	# pos = floor center of bunk footprint (2.0 x 0.9)
	var b := Basis(Vector3.UP, rot_y)
	var h := 0.85
	for t in tiers:
		var yy := pos.y + 0.35 + float(t) * (h + 0.5)
		g.box("metal_dark", pos + b * Vector3(0, yy - 0.17, 0) + Vector3(0, 0, 0), Vector3(2.0, 0.08, 0.9), COL_DARK, rot_y)
		g.box("metal", pos + b * Vector3(0, yy - 0.06, 0), Vector3(1.92, 0.14, 0.84), col, rot_y)
		g.box("white_mat", pos + b * Vector3(-0.72, yy + 0.06, 0), Vector3(0.4, 0.1, 0.5), COL_WHITE, rot_y)
		g.box("fabric", pos + b * Vector3(0.25, yy + 0.05, 0), Vector3(1.2, 0.06, 0.8), Color(0.4, 0.46, 0.55), rot_y)
		g.box("strip_warm", pos + b * Vector3(0.9, yy + 0.42, 0), Vector3(0.04, 0.05, 0.3), Color.WHITE, rot_y)
	# posts + ladder + privacy curtain
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.box("metal_dark", pos + b * Vector3(sx * 0.95, (0.35 + float(tiers) * (h + 0.5)) * 0.55, sz * 0.4), Vector3(0.06, 0.35 + float(tiers) * (h + 0.5) + 0.2, 0.06), COL_DARK, rot_y)
	g.box("metal_dark", pos + b * Vector3(0.55, 0.9, 0.48), Vector3(0.34, 1.6, 0.04), COL_DARK, rot_y)
	if tiers >= 2:
		g.box("fabric", pos + b * Vector3(-0.3, 1.5, 0.5), Vector3(1.3, 1.0, 0.03), Color(0.5, 0.42, 0.35, 0.9), rot_y)

func bed_double(pos: Vector3, rot_y: float) -> void:
	var b := Basis(Vector3.UP, rot_y)
	g.box("metal_dark", pos + b * Vector3(0, 0.16, 0), Vector3(2.1, 0.32, 1.7), COL_DARK, rot_y)
	g.box("fabric", pos + b * Vector3(0, 0.4, 0), Vector3(2.0, 0.2, 1.6), Color(0.82, 0.8, 0.76), rot_y)
	g.box("fabric", pos + b * Vector3(0.2, 0.52, 0), Vector3(1.5, 0.08, 1.55), Color(0.42, 0.35, 0.3), rot_y)
	g.box("white_mat", pos + b * Vector3(-0.72, 0.52, -0.4), Vector3(0.5, 0.12, 0.65), COL_WHITE, rot_y)
	g.box("white_mat", pos + b * Vector3(-0.72, 0.52, 0.4), Vector3(0.5, 0.12, 0.65), COL_WHITE, rot_y)
	g.box("metal", pos + b * Vector3(-1.05, 0.62, 0), Vector3(0.1, 1.0, 1.75), COL_MACH, rot_y)

func table_round(pos: Vector3, r: float, col: Color) -> void:
	g.cylinder("metal_dark", pos, pos + Vector3(0, 0.7, 0), 0.07, COL_DARK, 8)
	g.cylinder("metal", pos + Vector3(0, 0.73, 0), pos + Vector3(0, 0.78, 0), r, col, 16)
	g.torus("metal_dark", pos + Vector3(0, 0.03, 0), Basis(), r * 0.45, 0.05, COL_DARK, 12, 6)

func plant(pos: Vector3, s: float) -> void:
	g.cylinder("plastic", pos, pos + Vector3(0, 0.34 * s, 0), 0.22 * s, Color(0.5, 0.5, 0.52), 10)
	g.cylinder("metal_dark", pos + Vector3(0, 0.32 * s, 0), pos + Vector3(0, 0.36 * s, 0), 0.19 * s, Color(0.2, 0.16, 0.12), 10)
	for k in 3:
		var a := TAU * float(k) / 3.0 + rng.randf()
		var off := Vector3(cos(a), 0, sin(a)) * 0.12 * s
		g.sphere("rubber", pos + Vector3(0, (0.55 + 0.12 * float(k)) * s, 0) + off,
			Vector3(0.2, 0.26, 0.2) * s * (1.0 - float(k) * 0.15), Color(0.25 + rng.randf() * 0.15, 0.45 + rng.randf() * 0.2, 0.2), 8, 6)

func crate(pos: Vector3, s: Vector3, col: Color, rot: float = 0.0) -> void:
	g.box("plastic", pos + Vector3(0, s.y * 0.5, 0), s, col, rot)
	var b := Basis(Vector3.UP, rot)
	g.box("metal_dark", pos + b * Vector3(0, s.y - 0.04, 0) + Vector3(0, 0.0, 0), Vector3(s.x + 0.04, 0.06, s.z + 0.04), COL_DARK, rot)
	g.box("metal_dark", pos + b * Vector3(0, 0.04, 0), Vector3(s.x + 0.04, 0.06, s.z + 0.04), COL_DARK, rot)

func container(pos: Vector3, rot_y: float, col: Color) -> void:
	# ISO container 6.06 x 2.59 x 2.44 (x=lenght along local x)
	var b := Basis(Vector3.UP, rot_y)
	g.box("metal", pos + Vector3(0, 1.295, 0), Vector3(6.06, 2.59, 2.44), col, rot_y)
	# corrugation ribs on long sides
	for i in 10:
		var xx := -2.7 + float(i) * 0.6
		g.box("metal_dark", pos + b * Vector3(xx, 1.295, 1.225), Vector3(0.1, 2.3, 0.03), col.darkened(0.15), rot_y)
		g.box("metal_dark", pos + b * Vector3(xx, 1.295, -1.225), Vector3(0.1, 2.3, 0.03), col.darkened(0.15), rot_y)
	# corner castings
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.box("metal_dark", pos + b * Vector3(sx * 3.0, 2.53, sz * 1.17), Vector3(0.18, 0.14, 0.18), COL_DARK, rot_y)
			g.box("metal_dark", pos + b * Vector3(sx * 3.0, 0.07, sz * 1.17), Vector3(0.18, 0.14, 0.18), COL_DARK, rot_y)
	# door end detail
	g.box("metal_dark", pos + b * Vector3(-3.04, 1.295, 0), Vector3(0.04, 2.4, 2.2), col.darkened(0.25), rot_y)
	g.box("metal_dark", pos + b * Vector3(-3.08, 1.295, 0), Vector3(0.04, 0.1, 2.2), COL_DARK, rot_y)

func barrel(pos: Vector3, col: Color) -> void:
	g.cylinder("metal", pos, pos + Vector3(0, 0.9, 0), 0.3, col, 12)
	g.torus("metal_dark", pos + Vector3(0, 0.25, 0), Basis(), 0.31, 0.03, COL_DARK, 12, 6)
	g.torus("metal_dark", pos + Vector3(0, 0.65, 0), Basis(), 0.31, 0.03, COL_DARK, 12, 6)

func shelf_rack(pos: Vector3, rot_y: float, len: float, tiers: int, h: float, col: Color, fill: float = 0.6) -> void:
	var b := Basis(Vector3.UP, rot_y)
	var d := 0.7
	for sx in [-1.0, 1.0]:
		g.box("metal_dark", pos + b * Vector3(sx * (len * 0.5 - 0.04), h * 0.5, 0), Vector3(0.08, h, d), COL_DARK, rot_y)
	var nsec := int(len / 1.6)
	for t in tiers + 1:
		var yy := 0.08 + h * float(t) / float(tiers + 1) if t > 0 else 0.06
		if t == tiers + 1 - 1:
			pass
		g.box("metal", pos + b * Vector3(0, 0.06 + (h - 0.1) * float(t) / float(tiers), 0), Vector3(len, 0.06, d), COL_MACH, rot_y)
	# uprights mid
	for i in nsec + 1:
		var xx := -len * 0.5 + float(i) * len / float(nsec)
		g.box("metal_dark", pos + b * Vector3(xx, h * 0.5, 0), Vector3(0.06, h, d), COL_DARK, rot_y)
	# stock boxes
	for t in tiers:
		var yy := 0.09 + (h - 0.1) * float(t) / float(tiers)
		var i := 0
		while i < nsec * 2:
			if rng.randf() < fill:
				var xx := -len * 0.5 + (float(i) + 0.5) * len / float(nsec * 2)
				var s := Vector3(0.5 + rng.randf() * 0.25, 0.25 + rng.randf() * minf(0.3, (h - 0.1) / float(tiers) - 0.12), 0.45)
				var cc: Color = [Color(0.5, 0.44, 0.32), Color(0.4, 0.42, 0.46), Color(0.45, 0.38, 0.3), COL_YELLOW.darkened(0.2)][int(rng.randf() * 4) % 4]
				g.box("plastic", pos + b * Vector3(xx, yy + s.y * 0.5 + 0.02, (rng.randf() - 0.5) * 0.15), s, cc, rot_y)
			i += 1

func cabinet(pos: Vector3, rot_y: float, w: float, h: float, d: float, col: Color) -> void:
	g.box("metal", pos + Vector3(0, h * 0.5, 0), Vector3(w, h, d), col, rot_y)
	var b := Basis(Vector3.UP, rot_y)
	var doors := maxi(int(w / 0.6), 1)
	for i in doors:
		var xx := -w * 0.5 + (float(i) + 0.5) * w / float(doors)
		g.box("metal_dark", pos + b * Vector3(xx, h * 0.55, d * 0.5 + 0.015), Vector3(w / float(doors) * 0.88, h * 0.78, 0.02), col.darkened(0.1), rot_y)
		g.box("metal_dark", pos + b * Vector3(xx, h * 0.55, d * 0.5 + 0.04), Vector3(0.04, 0.2, 0.04), COL_DARK, rot_y)

# ---------------------------------------------------------------- machinery

func pump(pos: Vector3, rot_y: float, s: float) -> void:
	var b := Basis(Vector3.UP, rot_y)
	g.box("metal_dark", pos + b * Vector3(0, 0.1, 0), Vector3(1.4 * s, 0.2, 0.9 * s), COL_DARK, rot_y)
	g.cylinder("metal", pos + b * Vector3(-0.3 * s, 0.2, 0), pos + b * Vector3(-0.3 * s, 0.2, 0) + Vector3(0, 0.6 * s, 0), 0.32 * s, COL_MACH, 12)
	g.sphere("metal", pos + b * Vector3(0.35 * s, 0.45 * s, 0), Vector3.ONE * 0.3 * s, COL_CYAN, 10, 8)
	g.cylinder("metal_dark", pos + b * Vector3(0.35 * s, 0.75 * s, 0), pos + b * Vector3(0.35 * s, 0.75 * s, 0) + b * Vector3(0.6 * s, 0, 0), 0.12 * s, COL_DARK, 8)
	g.box("strip_green", pos + b * Vector3(-0.3 * s, 0.85 * s, 0.33 * s), Vector3(0.1, 0.05, 0.02), Color.WHITE, rot_y)

func tank_v(pos: Vector3, r: float, h: float, col: Color, band: String = "strip_cyan") -> void:
	g.cylinder("metal", pos + Vector3(0, 0.3, 0), pos + Vector3(0, h, 0), r, col, 16)
	g.sphere("metal", pos + Vector3(0, h, 0), Vector3(r, r * 0.55, r), col, 16, 6, 0.0, TAU, 0.0, PI * 0.5)
	g.torus("metal_dark", pos + Vector3(0, h * 0.62, 0), Basis(), r + 0.03, 0.05, COL_DARK, 16, 6)
	g.torus("metal_dark", pos + Vector3(0, h * 0.35, 0), Basis(), r + 0.03, 0.05, COL_DARK, 16, 6)
	g.box(band, pos + Vector3(0, h * 0.8, r + 0.02), Vector3(r * 0.8, 0.06, 0.03), Color.WHITE)
	for k in 3:
		var a := TAU * float(k) / 3.0
		g.strut("metal_dark", pos + Vector3(cos(a) * r * 0.8, 0.0, sin(a) * r * 0.8), pos + Vector3(cos(a) * r * 0.8, 0.32, sin(a) * r * 0.8), 0.08, 0.08, COL_DARK)
	g.cylinder("metal_dark", pos + Vector3(r * 0.7, h * 0.5, 0), pos + Vector3(r * 0.7 + 0.5, h * 0.5, 0), 0.09, COL_DARK, 8)

func machine_box(pos: Vector3, rot_y: float, s: Vector3, col: Color, detail: int = 1) -> void:
	g.box("metal", pos + Vector3(0, s.y * 0.5, 0), s, col, rot_y)
	var b := Basis(Vector3.UP, rot_y)
	g.box("metal_dark", pos + b * Vector3(0, s.y + 0.03, 0), Vector3(s.x * 1.02, 0.06, s.z * 1.02), COL_DARK, rot_y)
	g.box("metal_dark", pos + b * Vector3(0, 0.04, 0), Vector3(s.x * 1.04, 0.08, s.z * 1.04), COL_DARK, rot_y)
	if detail > 0:
		g.box("strip_green", pos + b * Vector3(0, s.y * 0.8, s.z * 0.5 + 0.02), Vector3(s.x * 0.4, 0.04, 0.02), Color.WHITE, rot_y)
	if detail > 1:
		g.box("metal_dark", pos + b * Vector3(0, s.y * 0.55, s.z * 0.5 + 0.03), Vector3(s.x * 0.5, s.y * 0.3, 0.04), col.darkened(0.2), rot_y)
		g.torus("metal_dark", pos + b * Vector3(s.x * 0.3, s.y * 0.55, s.z * 0.5 + 0.05), b, 0.09, 0.02, COL_DARK, 10, 6)
		# bolt row + nameplate + cable gland (close-up granularity)
		for bk in 4:
			g.cylinder("metal_dark", pos + b * Vector3(-s.x * 0.4 + float(bk) * s.x * 0.26, s.y * 0.18, s.z * 0.5 + 0.02),
				pos + b * Vector3(-s.x * 0.4 + float(bk) * s.x * 0.26, s.y * 0.18, s.z * 0.5 + 0.06), 0.028, COL_DARK, 6)
		g.quad_uv("screen_bars", pos + b * Vector3(-s.x * 0.2, s.y * 0.8, s.z * 0.5 + 0.045), pos + b * Vector3(s.x * 0.05, s.y * 0.8, s.z * 0.5 + 0.045),
			pos + b * Vector3(s.x * 0.05, s.y * 0.92, s.z * 0.5 + 0.045), pos + b * Vector3(-s.x * 0.2, s.y * 0.92, s.z * 0.5 + 0.045), Color.WHITE)
		g.cylinder("rubber", pos + b * Vector3(s.x * 0.3, 0.0, s.z * 0.5 + 0.1), pos + b * Vector3(s.x * 0.3, s.y * 0.3, s.z * 0.5 + 0.1), 0.035, Color(0.1, 0.1, 0.11), 6)

func duct_run(a: Vector3, b: Vector3, w: float, hgt: float) -> void:
	g.strut("metal", a, b, w, hgt, COL_MACH)
	var d := b - a
	var n := int(d.length() / 4.0)
	for i in n + 1:
		var p := a + d * (float(i) / float(maxi(n, 1)))
		if absf(d.z) > absf(d.x):
			g.box("metal_dark", p, Vector3(w + 0.1, hgt + 0.1, 0.12), COL_DARK)
		else:
			g.box("metal_dark", p, Vector3(0.12, hgt + 0.1, w + 0.1), COL_DARK)

func pipe_run(a: Vector3, b: Vector3, r: float, col: Color) -> void:
	g.cylinder("metal_dark", a, b, r, col, 8)
	var d := b - a
	var n := int(d.length() / 3.0)
	for i in n + 1:
		var p := a + d * (float(i) / float(maxi(n, 1)))
		g.box("metal_dark", p + Vector3(0, -r * 1.4, 0), Vector3(r * 2.8, r * 1.6, r * 2.8) if absf(d.x) > absf(d.z) else Vector3(r * 2.8, r * 1.6, r * 2.8), COL_DARK)

func ceiling_pipes(r: Dictionary, n: int, y_off: float, r_pipe: float) -> void:
	var y0: float = r["y1"] - y_off
	var along_x: bool = (r["x1"] - r["x0"]) > (r["z1"] - r["z0"])
	for i in n:
		if along_x:
			var zz: float = lerpf(r["z0"] + 0.7, r["z1"] - 0.7, float(i) / maxf(float(n - 1), 1.0))
			g.cylinder("metal_dark", Vector3(r["x0"] + 0.3, y0 - float(i % 2) * 0.22, zz), Vector3(r["x1"] - 0.3, y0 - float(i % 2) * 0.22, zz), r_pipe, COL_MACH, 8)
		else:
			var xx: float = lerpf(r["x0"] + 0.7, r["x1"] - 0.7, float(i) / maxf(float(n - 1), 1.0))
			g.cylinder("metal_dark", Vector3(xx, y0 - float(i % 2) * 0.22, r["z0"] + 0.3), Vector3(xx, y0 - float(i % 2) * 0.22, r["z1"] - 0.3), r_pipe, COL_MACH, 8)

func ceiling_lights(r: Dictionary, key: String, rows: int = 2) -> void:
	if key.begins_with("strip_"):
		key = key.replace("strip_", "emit_")
	var y: float = r["y1"] - 0.12
	var along_x: bool = (r["x1"] - r["x0"]) > (r["z1"] - r["z0"])
	var n := maxi(int((r["x1"] - r["x0"] if along_x else r["z1"] - r["z0"]) / 5.0), 1)
	for i in n:
		var t := lerpf(2.0, (r["x1"] - r["x0"] if along_x else r["z1"] - r["z0"]) - 2.0, float(i) / maxf(float(n - 1), 1.0))
		for k in rows:
			var off := lerpf(-1.0, 1.0, float(k) / maxf(float(rows - 1), 1.0)) * minf((r["z1"] - r["z0"] if along_x else r["x1"] - r["x0"]) * 0.28, 3.0)
			if along_x:
				g.box("metal_dark", Vector3(r["x0"] + t, y + 0.1, (r["z0"] + r["z1"]) * 0.5 + off), Vector3(2.8, 0.1, 0.34), COL_DARK)
				g.box(key, Vector3(r["x0"] + t, y - 0.02, (r["z0"] + r["z1"]) * 0.5 + off), Vector3(2.6, 0.06, 0.26), Color.WHITE)
			else:
				g.box("metal_dark", Vector3((r["x0"] + r["x1"]) * 0.5 + off, y + 0.1, r["z0"] + t), Vector3(0.34, 0.1, 2.8), COL_DARK)
				g.box(key, Vector3((r["x0"] + r["x1"]) * 0.5 + off, y - 0.02, r["z0"] + t), Vector3(0.26, 0.06, 2.6), Color.WHITE)

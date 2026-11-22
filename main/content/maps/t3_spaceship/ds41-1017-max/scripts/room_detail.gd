class_name RoomDetail
extends RefCounted

## Per-room furnishing and life-trace generator.
##
## Every habitable volume gets its own layout variant, wear level, clutter,
## storage and pipe routing. Decorators are seeded per room so two crew cabins
## or two workshops never look identical, while still staying inside the
## room's adjustable width/length envelope.

var kit: MeshKit
var props: Props
var cfg: ShipConfig
var root: Node3D          # TextMesh signage parent
var lum: Node3D           # lights parent (zone node -> streamed with the room)
var rng := RandomNumberGenerator.new()
var wear := 1.0
var variant := 0
var palette := 0


func _init(k: MeshKit, p: Props, c: ShipConfig, sign_parent: Node3D, light_parent: Node3D) -> void:
	kit = k
	props = p
	cfg = c
	root = sign_parent
	lum = light_parent


func setup(seed_key: String, wear_level: float, variant_index: int) -> void:
	var h := 0
	for ch in seed_key:
		h = (h * 31 + ch.unicode_at(0)) & 0x7fffffff
	rng.seed = h + 991
	wear = clampf(wear_level, 0.0, 1.6)
	variant = variant_index
	palette = h % 4
	kit.set_wear(wear)


func light(pos: Vector3, col: Color, energy: float, rng_m: float, shadow: bool = false) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy * 2.4
	l.omni_range = rng_m
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	lum.add_child(l)


func label(text: String, pos: Vector3, yaw: float, size: float = 0.22,
		col: Color = Color(0.55, 0.85, 1.0)) -> void:
	props.place_sign(text, pos, yaw, size, col)


func part(kind: float = 0.0) -> void:
	kit.begin_part(rng.randf(), kind)


# ============================================================== micro props ==
func mug(p: Vector3, yaw: float = 0.0) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(70.0)
	kit.cyl("ceramic", 0.042, 0.046, 0.095, 10, Vector3.ZERO)
	kit.cyl("ceramic_dark", 0.035, 0.035, 0.01, 10, Vector3(0, 0.096, 0))
	kit.torus("ceramic", 0.035, 0.008, 10, 4, Vector3(0.058, 0.05, 0))
	kit.pop_xf()


func bottle(p: Vector3, col: String = "glass_bottle") -> void:
	part(70.0)
	kit.cyl(col, 0.038, 0.040, 0.17, 10, p)
	kit.cyl(col, 0.016, 0.016, 0.06, 8, p + Vector3(0, 0.17, 0))
	kit.cyl("metal_dark", 0.019, 0.019, 0.025, 8, p + Vector3(0, 0.232, 0))


func papers(p: Vector3, yaw: float, count: int = 4) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(71.0)
	for i in count:
		var b := Basis(Vector3.UP, rng.randf_range(-0.4, 0.4))
		kit.push_xf(Transform3D(b, Vector3(rng.randf_range(-0.12, 0.12),
			0.003 + i * 0.002, rng.randf_range(-0.14, 0.14))))
		kit.box("paper" if i % 3 != 0 else "paper_b", Vector3(0.21, 0.002, 0.28), Vector3.ZERO)
		kit.pop_xf()
	kit.pop_xf()


func tablet(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(72.0)
	kit.box_bevel("metal_dark", Vector3(0.26, 0.015, 0.19), Vector3.ZERO, 0.008)
	kit.box("screen_log", Vector3(0.22, 0.006, 0.15), Vector3(0, 0.01, 0))
	kit.pop_xf()


func book_stack(p: Vector3, yaw: float, n: int = 3) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(72.0)
	for i in n:
		kit.box("paper_b" if i % 2 == 0 else "fabric_rust",
			Vector3(0.18 - i * 0.01, 0.028, 0.25), Vector3(rng.randf_range(-0.02, 0.02), 0.014 + i * 0.028, 0))
	kit.pop_xf()


func tool_wrench(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(73.0)
	kit.box("metal_light", Vector3(0.035, 0.012, 0.24), Vector3.ZERO)
	kit.box("metal_light", Vector3(0.075, 0.012, 0.05), Vector3(0, 0, 0.12))
	kit.box("metal_light", Vector3(0.065, 0.012, 0.04), Vector3(0, 0, -0.12))
	kit.pop_xf()


func tool_screwdriver(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(73.0)
	kit.cyl("fabric_rust", 0.016, 0.014, 0.09, 8, Vector3.ZERO)
	kit.cyl("metal_light", 0.006, 0.004, 0.13, 6, Vector3(0, 0.09, 0))
	kit.pop_xf()


func tools_scatter(p: Vector3, yaw: float) -> void:
	tool_wrench(p + Vector3(0.10, 0.006, 0.04), yaw + 0.4)
	tool_wrench(p + Vector3(-0.05, 0.006, -0.10), yaw - 0.3)
	tool_screwdriver(p + Vector3(0.02, 0.006, 0.16), yaw + 0.9)
	tool_screwdriver(p + Vector3(-0.14, 0.006, 0.02), yaw - 0.6)
	part(73.0)
	kit.box("metal_cast", Vector3(0.09, 0.06, 0.16), p + Vector3(0.19, 0.03, -0.10))


func noticeboard(p: Vector3, yaw: float, w: float = 1.3, h: float = 0.9) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(74.0)
	kit.box("metal_dark", Vector3(w + 0.06, h + 0.06, 0.05), Vector3.ZERO)
	kit.box("fabric_grey", Vector3(w, h, 0.02), Vector3(0, 0, 0.03))
	for i in int(w * h * 14.0):
		var b := Basis(Vector3.FORWARD, rng.randf_range(-0.12, 0.12))
		var x := rng.randf_range(-w * 0.42, w * 0.42)
		var yy := rng.randf_range(-h * 0.40, h * 0.40)
		kit.push_xf(Transform3D(b, Vector3(x, yy, 0.045)))
		kit.box("paper" if i % 3 != 0 else "paper_b",
			Vector3(rng.randf_range(0.08, 0.16), rng.randf_range(0.10, 0.19), 0.002), Vector3.ZERO)
		kit.pop_xf()
	# tape strips and a photo
	kit.box("paper_b", Vector3(0.18, 0.12, 0.003), Vector3(w * 0.25, h * 0.2, 0.047))
	kit.box("emit_cool", Vector3(0.01, 0.01, 0.004), Vector3(-w * 0.35, -h * 0.3, 0.048))
	kit.pop_xf()


func poster(p: Vector3, yaw: float, w: float = 0.55, h: float = 0.8, key: String = "fabric_rust") -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(74.0)
	kit.box("metal_dark", Vector3(w + 0.04, h + 0.04, 0.03), Vector3.ZERO)
	kit.box(key, Vector3(w, h, 0.012), Vector3(0, 0, 0.02))
	kit.box("paper", Vector3(w * 0.8, 0.035, 0.004), Vector3(0, h * 0.28, 0.027))
	kit.box("paper_b", Vector3(w * 0.62, 0.02, 0.004), Vector3(0, h * 0.18, 0.027))
	kit.pop_xf()


func photo_wall(p: Vector3, yaw: float, n: int = 5) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	for i in n:
		var px := rng.randf_range(-0.5, 0.5)
		var py := rng.randf_range(-0.28, 0.30)
		part(74.0)
		kit.box("metal_dark", Vector3(0.13, 0.10, 0.015), Vector3(px, py, 0))
		kit.box("paper_b" if i % 2 == 0 else "fabric_teal", Vector3(0.11, 0.08, 0.004),
			Vector3(px, py, 0.012))
	kit.pop_xf()


func fire_extinguisher(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(75.0)
	kit.cyl("hazard", 0.105, 0.105, 0.50, 14, Vector3.ZERO)
	kit.cyl("metal_dark", 0.055, 0.04, 0.10, 10, Vector3(0, 0.50, 0))
	kit.box("metal_dark", Vector3(0.05, 0.05, 0.10), Vector3(0.10, 0.42, 0))
	kit.tube("rubber", [Vector3(0.04, 0.55, 0), Vector3(0.17, 0.50, 0.02),
		Vector3(0.20, 0.28, 0.02)], 0.018, 6)
	kit.box("metal_dark", Vector3(0.24, 0.10, 0.10), Vector3(0, 0.06, 0))
	kit.pop_xf()


func first_aid(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(75.0)
	kit.box("wall_white", Vector3(0.34, 0.28, 0.10), Vector3.ZERO)
	kit.box("emit_green", Vector3(0.16, 0.045, 0.02), Vector3(0, 0.02, 0.06))
	kit.box("emit_green", Vector3(0.045, 0.16, 0.02), Vector3(0, 0.02, 0.06))
	kit.box("metal_dark", Vector3(0.36, 0.03, 0.12), Vector3(0, 0.16, 0))
	kit.pop_xf()


func bin(p: Vector3, kind: int = 0) -> void:
	part(75.0)
	var key := "metal_dark"
	if kind == 1:
		key = "hazard"
	elif kind == 2:
		key = "emit_amber"
	kit.cyl(key, 0.21, 0.24, 0.55, 14, p)
	kit.cyl("metal_dark", 0.25, 0.20, 0.06, 14, p + Vector3(0, 0.55, 0))
	if kind == 1:
		kit.box("emit_green", Vector3(0.12, 0.10, 0.01), p + Vector3(0, 0.34, 0.23))


func janitor_cart(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(76.0)
	kit.box("metal_painted", Vector3(0.55, 0.06, 0.9), Vector3(0, 0.55, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box("metal_dark", Vector3(0.05, 0.55, 0.05), Vector3(sx * 0.24, 0.28, sz * 0.40))
	kit.cyl("hazard", 0.19, 0.17, 0.35, 12, Vector3(-0.12, 0.58, 0.22))
	kit.tube("metal", [Vector3(0.15, 0.6, -0.30), Vector3(0.15, 1.35, -0.30)], 0.018, 6)
	kit.box("fabric_grey", Vector3(0.16, 0.20, 0.06), Vector3(0.15, 0.42, -0.30))
	for i in 3:
		kit.cyl("fabric_teal", 0.05, 0.055, 0.20, 8, Vector3(0.18, 0.64, -0.10 + i * 0.12))
	kit.pop_xf()


func cable_coil(p: Vector3, radius: float = 0.42, turns: int = 4) -> void:
	part(76.0)
	for i in turns:
		kit.torus("rubber", radius * 0.94, 0.035, 24, 5,
			p + Vector3(rng.randf_range(-0.02, 0.02), 0.035 + i * 0.07, rng.randf_range(-0.02, 0.02)))


func cable_sag(a: Vector3, b: Vector3, sag: float = 0.35, key: String = "rubber") -> void:
	var mid := (a + b) * 0.5 + Vector3(0, -sag, 0)
	kit.tube(key, [a, (a + mid) * 0.5 + Vector3(0, -sag * 0.7, 0), mid,
		(b + mid) * 0.5 + Vector3(0, -sag * 0.7, 0), b], 0.022, 5)


func junction(p: Vector3, yaw: float, w: float = 0.52, h: float = 0.8) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(77.0)
	kit.box_bevel("metal_cast", Vector3(w, h, 0.18), Vector3.ZERO, 0.025)
	kit.box("screen_power" if rng.randf() > 0.5 else "screen_log",
		Vector3(w * 0.5, h * 0.36, 0.01), Vector3(0, h * 0.12, 0.10))
	kit.box("emit_green" if rng.randf() > 0.35 else "emit_amber",
		Vector3(0.03, 0.04, 0.02), Vector3(-w * 0.3, -h * 0.28, 0.11))
	for i in 3:
		kit.cyl("metal_dark", 0.035, 0.035, 0.22, 6,
			Vector3(-w * 0.3 + i * w * 0.3, -h * 0.5 - 0.10, 0.02))
	kit.box("metal_dark", Vector3(w * 0.7, 0.035, 0.02), Vector3(0, -h * 0.45, 0.10))
	kit.pop_xf()


func gauge_panel(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(77.0)
	kit.box("metal_dark", Vector3(0.9, 0.5, 0.10), Vector3.ZERO)
	for i in 3:
		var c := Vector3(-0.28 + i * 0.28, 0.04, 0.055)
		kit.cyl("metal_light", 0.10, 0.10, 0.03, 16, c)
		kit.torus("metal", 0.11, 0.012, 16, 4, c + Vector3(0, 0.015, 0))
		kit.box("emit_amber", Vector3(0.01, 0.07, 0.01), c + Vector3(0, 0.02, 0.04))
	kit.box("screen_power", Vector3(0.34, 0.12, 0.01), Vector3(0, -0.18, 0.06))
	kit.pop_xf()


func ppe_cabinet(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(78.0)
	kit.box_bevel("metal_painted", Vector3(0.9, 1.7, 0.45), Vector3(0, 0.85, 0), 0.03)
	kit.box("glass_med", Vector3(0.72, 1.1, 0.02), Vector3(0, 1.05, 0.23))
	kit.sphere("suit_white", 0.20, 14, Vector3(-0.16, 1.42, 0.12))
	kit.box("suit_white", Vector3(0.34, 0.50, 0.16), Vector3(-0.16, 1.0, 0.12))
	kit.box("fabric_orange", Vector3(0.3, 0.10, 0.16), Vector3(0.22, 0.85, 0.12))
	kit.box("metal_dark", Vector3(0.8, 0.06, 0.4), Vector3(0, 1.65, 0))
	kit.box("emit_amber", Vector3(0.2, 0.05, 0.01), Vector3(0, 1.75, 0.2))
	kit.pop_xf()


func eva_suit(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(78.0)
	kit.cyl("metal_dark", 0.05, 0.04, 1.3, 8, Vector3(0, 0.65, 0))
	kit.box("metal_dark", Vector3(0.7, 0.05, 0.05), Vector3(0, 1.55, 0))
	# torso + helmet + limbs
	kit.box_bevel("suit_white", Vector3(0.48, 0.62, 0.30), Vector3(0, 1.02, 0), 0.06)
	kit.box("fabric_orange", Vector3(0.50, 0.10, 0.32), Vector3(0, 0.80, 0))
	kit.sphere("suit_white", 0.19, 16, Vector3(0, 1.50, 0))
	kit.box("glass_dark", Vector3(0.26, 0.14, 0.05), Vector3(0, 1.51, -0.15))
	for sx in [-1.0, 1.0]:
		kit.box("suit_white", Vector3(0.13, 0.55, 0.16), Vector3(sx * 0.30, 1.02, 0))
		kit.box("suit_white", Vector3(0.16, 0.62, 0.18), Vector3(sx * 0.13, 0.40, 0))
		kit.box("rubber_worn", Vector3(0.17, 0.12, 0.24), Vector3(sx * 0.13, 0.10, -0.02))
	kit.pop_xf()


func workbench(p: Vector3, yaw: float, w: float = 2.0) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(79.0)
	kit.set_height_range(0.0, 1.9)
	kit.box_bevel("metal_painted", Vector3(w, 0.08, 0.80), Vector3(0, 0.92, 0), 0.02)
	kit.box("hazard_worn", Vector3(w, 0.04, 0.82), Vector3(0, 0.86, 0))
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.07, 0.92, 0.70), Vector3(sx * (w * 0.5 - 0.08), 0.46, 0))
		kit.box("metal_dark", Vector3(0.07, 0.92, 0.07), Vector3(sx * (w * 0.5 - 0.08), 0.46, -0.35))
	# drawers
	for i in 3:
		kit.box("metal_cast", Vector3(w * 0.42, 0.18, 0.62),
			Vector3(w * 0.22, 0.72 - i * 0.20, 0))
		kit.box("metal", Vector3(w * 0.2, 0.02, 0.02), Vector3(w * 0.22, 0.72 - i * 0.20, 0.32))
	# vise + pegboard + task lamp
	kit.box("metal_cast", Vector3(0.18, 0.14, 0.22), Vector3(-w * 0.36, 1.03, 0.05))
	kit.box("metal", Vector3(0.06, 0.05, 0.26), Vector3(-w * 0.36, 1.12, 0.05))
	kit.box("metal_cast", Vector3(0.05, 0.30, 0.05), Vector3(-w * 0.36, 1.22, 0.12))
	kit.box("metal_dark", Vector3(w * 0.55, 0.7, 0.03), Vector3(w * 0.12, 1.55, 0.36))
	for i in 7:
		kit.box("metal_light", Vector3(0.03, 0.10 + (i % 3) * 0.05, 0.02),
			Vector3(w * 0.12 - 0.32 + i * 0.11, 1.48, 0.39))
	kit.tube("metal", [Vector3(w * 0.34, 0.96, 0.2), Vector3(w * 0.34, 1.55, 0.2),
		Vector3(w * 0.24, 1.62, 0.1)], 0.018, 5)
	kit.cyl("metal_dark", 0.12, 0.09, 0.10, 12, Vector3(w * 0.24, 1.58, 0.08))
	kit.cyl("emit_white", 0.07, 0.07, 0.02, 12, Vector3(w * 0.24, 1.53, 0.08))
	tools_scatter(Vector3(-w * 0.05, 0.96, 0.05), rng.randf_range(-0.4, 0.4))
	papers(Vector3(w * 0.30, 0.96, -0.12), rng.randf_range(-0.3, 0.3), 3)
	kit.pop_xf()


func lathe(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(80.0)
	kit.box_bevel("metal_painted", Vector3(1.05, 0.72, 2.2), Vector3(0, 0.36, 0), 0.04)
	kit.box("metal_cast", Vector3(0.7, 0.22, 2.4), Vector3(0, 0.78, 0))
	kit.box("metal_cast", Vector3(0.55, 0.5, 0.55), Vector3(0, 1.0, -0.85))
	kit.cyl("metal_light", 0.22, 0.22, 0.18, 16, Vector3(0, 1.0, -0.56))
	kit.cyl("metal_dark", 0.09, 0.09, 0.22, 10, Vector3(0, 1.0, -0.44))
	kit.box("metal_cast", Vector3(0.34, 0.34, 0.35), Vector3(0, 1.0, 0.86))
	kit.cyl("metal_light", 0.06, 0.04, 0.20, 8, Vector3(0, 1.0, 0.66))
	kit.box("screen_eng", Vector3(0.30, 0.20, 0.03), Vector3(0.38, 1.10, -0.6))
	for i in 4:
		kit.cyl("metal_dark", 0.035, 0.035, 0.06, 8, Vector3(0.22 + (i % 2) * 0.1, 1.06, -0.3 + (i / 2) * 0.15))
	cable_sag(Vector3(0.3, 1.2, -0.9), Vector3(0.3, 1.1, 0.8), 0.25)
	kit.pop_xf()


func drill_press(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(80.0)
	kit.box("metal_painted", Vector3(0.45, 0.08, 0.55), Vector3(0, 0.04, 0))
	kit.cyl("metal_cast", 0.06, 0.06, 1.7, 10, Vector3(0, 0.85, -0.16))
	kit.box("metal_cast", Vector3(0.22, 0.22, 0.5), Vector3(0, 1.62, -0.02))
	kit.cyl("metal_light", 0.045, 0.045, 0.28, 8, Vector3(0, 1.42, 0.12))
	kit.cyl("metal_dark", 0.03, 0.03, 0.10, 6, Vector3(0, 1.3, 0.12))
	kit.box("metal_dark", Vector3(0.28, 0.05, 0.30), Vector3(0, 0.24, 0.12))
	kit.box("screen_power", Vector3(0.16, 0.10, 0.02), Vector3(0.18, 1.55, -0.28))
	kit.pop_xf()


func parts_rack(p: Vector3, yaw: float, w: float = 2.2) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(81.0)
	kit.set_height_range(0.0, 2.2)
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.08, 2.0, 0.55), Vector3(sx * w * 0.5, 1.0, 0))
	for i in 4:
		var y := 0.30 + i * 0.48
		kit.box("metal", Vector3(w, 0.05, 0.55), Vector3(0, y, 0))
		for k in int(w / 0.32):
			kit.box("container_c" if (k + i) % 2 == 0 else "metal_painted",
				Vector3(0.26, 0.20, 0.38), Vector3(-w * 0.5 + 0.2 + k * 0.32, y + 0.13, 0))
	kit.pop_xf()


func stock_rack(p: Vector3, yaw: float = 0.0) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(81.0)
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.1, 1.9, 0.1), Vector3(sx * 0.9, 0.95, -0.3))
		kit.box("metal_dark", Vector3(0.1, 1.9, 0.1), Vector3(sx * 0.9, 0.95, 0.3))
	for i in 3:
		kit.box("metal", Vector3(1.9, 0.06, 0.7), Vector3(0, 0.3 + i * 0.6, 0))
		kit.box("metal_light", Vector3(1.7, 0.07, 0.06), Vector3(0, 0.36 + i * 0.6, -0.2))
		kit.box("pipe_cream", Vector3(1.5, 0.06, 0.06), Vector3(0, 0.40 + i * 0.6, 0.1))
		kit.box("metal_cast", Vector3(1.2, 0.05, 0.12), Vector3(0, 0.44 + i * 0.6, 0.26))
	kit.pop_xf()


func welder(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(82.0)
	kit.box("metal_dark", Vector3(0.5, 0.06, 0.7), Vector3(0, 0.5, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.cyl("rubber_worn", 0.09, 0.09, 0.05, 8, Vector3(sx * 0.2, 0.05, sz * 0.25))
	kit.box("metal_cast", Vector3(0.4, 0.35, 0.3), Vector3(0, 0.72, 0))
	for i in 2:
		kit.cyl("pipe_teal" if i == 0 else "pipe_orange", 0.11, 0.11, 0.8, 12,
			Vector3(-0.3 + i * 0.16, 0.58, 0.22))
		kit.cyl("metal_dark", 0.06, 0.04, 0.10, 8, Vector3(-0.3 + i * 0.16, 1.40, 0.22))
	kit.tube("rubber", [Vector3(0.15, 0.8, 0.1), Vector3(0.5, 0.9, -0.2),
		Vector3(0.9, 1.0, -0.3)], 0.02, 5)
	kit.sphere("metal_light", 0.16, 12, Vector3(0.9, 1.03, -0.3))
	kit.box("glass_dark", Vector3(0.2, 0.16, 0.12), Vector3(0.9, 1.05, -0.24))
	kit.pop_xf()


func storage_cabinet(p: Vector3, yaw: float, w: float = 1.0, h: float = 1.9) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(83.0)
	kit.box_bevel("metal_painted", Vector3(w, h, 0.5), Vector3(0, h * 0.5, 0), 0.02)
	for i in 2:
		var bx := -w * 0.25 + i * w * 0.5
		kit.box("metal_dark", Vector3(w * 0.45, 0.03, 0.02), Vector3(bx, h * 0.65, 0.26))
		kit.box("metal_dark", Vector3(w * 0.45, 0.03, 0.02), Vector3(bx, h * 0.35, 0.26))
		kit.box("emit_green", Vector3(0.03, 0.02, 0.01), Vector3(bx + w * 0.16, h * 0.5, 0.27))
	kit.box("paper", Vector3(w * 0.5, 0.10, 0.005), Vector3(0, h * 0.85, 0.26))
	kit.pop_xf()


func bunk_pod(p: Vector3, yaw: float, level: int = 0) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	var y := level * 1.15
	part(84.0)
	kit.box_bevel("metal_painted", Vector3(1.05, 0.20, 2.05), Vector3(0, y + 0.10, 0), 0.04)
	kit.box_bevel("fabric_grey", Vector3(0.92, 0.14, 1.85), Vector3(0, y + 0.27, 0), 0.04)
	kit.box("metal_dark", Vector3(1.05, 0.85, 0.08), Vector3(0, y + 0.62, 1.0))
	kit.box("metal_dark", Vector3(1.05, 0.30, 0.08), Vector3(0, y + 0.20, 1.0))
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.06, 0.9, 2.0), Vector3(sx * 0.51, y + 0.5, 0))
	# mattress, pillow, curtain, reading light
	kit.box("fabric_white", Vector3(0.78, 0.08, 1.5), Vector3(0, y + 0.38, 0.05))
	kit.box("fabric_white", Vector3(0.5, 0.12, 0.28), Vector3(0, y + 0.45, 0.58))
	kit.box("fabric_teal", Vector3(0.9, 0.06, 1.1), Vector3(0, y + 0.44, -0.1))
	kit.box("emit_warm", Vector3(0.07, 0.03, 0.05), Vector3(0.38, y + 0.75, 0.35))
	kit.box("fabric_dark", Vector3(0.9, 0.6, 0.02), Vector3(0, y + 0.7, -0.92))
	# personal items
	if rng.randf() > 0.4:
		tablet(Vector3(0.18, y + 0.43, -0.45), yaw + 0.4)
	if rng.randf() > 0.5:
		mug(Vector3(-0.25, y + 0.42, 0.30), 0.2)
	kit.pop_xf()


func bed_single(p: Vector3, yaw: float, messy: bool = true) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(84.0)
	var w := 1.0
	var l := 2.05
	kit.box_bevel("metal_painted", Vector3(w, 0.22, l), Vector3(0, 0.11, 0), 0.03)
	kit.box("fabric_white", Vector3(w - 0.06, 0.16, l - 0.10), Vector3(0, 0.28, 0))
	kit.box("fabric_white", Vector3(w * 0.6, 0.11, 0.34), Vector3(0, 0.38, -l * 0.34))
	if messy:
		kit.box("fabric_grey", Vector3(w - 0.12, 0.10, l * 0.55), Vector3(0.0, 0.37, 0.18))
		kit.box("fabric_grey", Vector3(w * 0.55, 0.10, l * 0.35), Vector3(0.14, 0.42, 0.30))
	else:
		kit.box("fabric_grey", Vector3(w - 0.06, 0.08, l * 0.7), Vector3(0, 0.36, 0.10))
	kit.box("metal_dark", Vector3(w + 0.04, 0.6, 0.06), Vector3(0, 0.5, -l * 0.5))
	kit.pop_xf()


func desk(p: Vector3, yaw: float, w: float = 1.4) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(85.0)
	kit.box_bevel("metal_painted", Vector3(w, 0.06, 0.66), Vector3(0, 0.74, 0), 0.02)
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.06, 0.72, 0.6), Vector3(sx * (w * 0.5 - 0.06), 0.37, 0))
	kit.box("metal_cast", Vector3(w * 0.38, 0.32, 0.5), Vector3(w * 0.22, 0.55, 0))
	kit.box("metal", Vector3(w * 0.22, 0.02, 0.02), Vector3(w * 0.22, 0.66, 0.25))
	# task lamp
	kit.cyl("metal_dark", 0.08, 0.08, 0.03, 10, Vector3(-w * 0.32, 0.79, -0.16))
	kit.tube("metal", [Vector3(-w * 0.32, 0.8, -0.16), Vector3(-w * 0.30, 1.25, -0.10),
		Vector3(-w * 0.18, 1.30, 0.06)], 0.017, 5)
	kit.cyl("metal_dark", 0.08, 0.10, 0.08, 10, Vector3(-w * 0.16, 1.27, 0.08))
	kit.cyl("emit_warm", 0.07, 0.07, 0.01, 10, Vector3(-w * 0.16, 1.22, 0.08))
	papers(Vector3(-w * 0.05, 0.78, 0.05), rng.randf_range(-0.3, 0.3), 4)
	tablet(Vector3(w * 0.16, 0.79, 0.08), yaw + rng.randf_range(-0.3, 0.3))
	mug(Vector3(w * 0.30, 0.78, -0.12), rng.randf() * TAU)
	if rng.randf() > 0.5:
		book_stack(Vector3(-w * 0.3, 0.78, 0.15), rng.randf() * TAU, 2)
	kit.pop_xf()


func sofa(p: Vector3, yaw: float, w: float = 2.0) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(86.0)
	kit.box_bevel("fabric_teal", Vector3(w, 0.32, 0.85), Vector3(0, 0.22, 0), 0.06)
	kit.box_bevel("fabric_teal", Vector3(w, 0.55, 0.20), Vector3(0, 0.58, 0.32), 0.06)
	for sx in [-1.0, 1.0]:
		kit.box_bevel("fabric_teal", Vector3(0.20, 0.38, 0.85), Vector3(sx * (w * 0.5 - 0.1), 0.5, 0), 0.05)
	for i in 2:
		kit.box_bevel("fabric_grey", Vector3(w * 0.42, 0.10, 0.70), Vector3(-w * 0.23 + i * w * 0.46, 0.42, -0.02), 0.04)
	kit.box("fabric_rust", Vector3(0.4, 0.35, 0.12), Vector3(-w * 0.28, 0.62, 0.18))
	kit.pop_xf()


func kitchenette(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(87.0)
	kit.box_bevel("metal_painted", Vector3(2.2, 0.9, 0.62), Vector3(0, 0.45, 0), 0.03)
	kit.box("metal", Vector3(2.24, 0.05, 0.68), Vector3(0, 0.92, 0))
	kit.box("metal_cast", Vector3(0.55, 0.06, 0.4), Vector3(-0.55, 0.95, 0.02))
	kit.cyl("metal_dark", 0.03, 0.02, 0.20, 8, Vector3(-0.55, 1.06, -0.12))
	kit.box("screen_power", Vector3(0.3, 0.16, 0.02), Vector3(0.6, 1.1, -0.2))
	kit.box("metal_dark", Vector3(0.45, 0.55, 0.45), Vector3(0.55, 1.22, 0))
	kit.box("ceramic_dark", Vector3(0.35, 0.02, 0.35), Vector3(0.55, 0.96, 0))
	mug(Vector3(0.1, 0.95, 0.08), 0.3)
	mug(Vector3(0.25, 0.95, 0.12), 2.0)
	bottle(Vector3(-0.2, 0.94, 0.05))
	kit.pop_xf()


func rug(p: Vector3, yaw: float, w: float = 2.0, d: float = 1.4) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(88.0)
	kit.box("fabric_rust" if palette % 2 == 0 else "fabric_teal",
		Vector3(w, 0.012, d), Vector3(0, 0.006, 0))
	kit.box("fabric_dark", Vector3(w + 0.04, 0.006, 0.06), Vector3(0, 0.004, d * 0.5))
	kit.box("fabric_dark", Vector3(w + 0.04, 0.006, 0.06), Vector3(0, 0.004, -d * 0.5))
	kit.pop_xf()


func plant_small(p: Vector3, scale: float = 1.0) -> void:
	part(89.0)
	kit.cyl("ceramic_dark", 0.14 * scale, 0.11 * scale, 0.22 * scale, 12, p)
	kit.cyl("floor_dark", 0.13 * scale, 0.13 * scale, 0.02 * scale, 12, p + Vector3(0, 0.21 * scale, 0))
	for i in 9:
		var a := TAU * float(i) / 9.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), rng.randf_range(0.2, 1.0), sin(a)).normalized()
		var base := p + Vector3(0, 0.22 * scale, 0)
		var tip := base + out * 0.30 * scale
		var side := out.cross(Vector3.UP).normalized() * 0.07 * scale
		kit.quad("plant" if i % 3 else "plant_b", [base - side, base + side, tip + side * 0.4, tip - side * 0.4],
			out, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])


func stain(kind: int, p: Vector3, w: float, d: float, yaw: float = 0.0) -> void:
	var key := "decal_grime"
	if kind == 1:
		key = "decal_oil"
	elif kind == 2:
		key = "decal_dust"
	elif kind == 3:
		key = "decal_scorch"
	var b := Basis(Vector3.UP, yaw)
	var c := p + Vector3(0, 0.006, 0)
	var pts := [c + b * Vector3(-w * 0.5, 0, -d * 0.5), c + b * Vector3(w * 0.5, 0, -d * 0.5),
		c + b * Vector3(w * 0.5, 0, d * 0.5), c + b * Vector3(-w * 0.5, 0, d * 0.5)]
	part(90.0)
	kit.quad(key, pts, Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])


func tape_line(a: Vector3, b: Vector3, width: float = 0.10) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.05:
		return
	var dir := d / len
	var right := dir.cross(Vector3.UP).normalized()
	part(90.0)
	kit.box("hazard_worn", Vector3(width, 0.004, len), (a + b) * 0.5 + Vector3(0, 0.008, 0))
	# worn gaps
	for i in int(len / 1.8):
		var p := a + dir * (0.6 + i * 1.8)
		kit.box("floor_dark", Vector3(width * 1.2, 0.005, 0.22), p + Vector3(0, 0.009, 0))


func footprints(a: Vector3, b: Vector3, n: int = 12) -> void:
	var d := b - a
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		var p := a + d * t
		var side := Vector3(-d.z, 0, d.x).normalized() * (0.09 * (1.0 if i % 2 == 0 else -1.0))
		p += side + Vector3(rng.randf_range(-0.05, 0.05), 0.006, rng.randf_range(-0.05, 0.05))
		var b2 := Basis(Vector3.UP, atan2(d.x, d.z))
		var pts := [p + b2 * Vector3(-0.045, 0, -0.10), p + b2 * Vector3(0.045, 0, -0.10),
			p + b2 * Vector3(0.04, 0, 0.10), p + b2 * Vector3(-0.04, 0, 0.10)]
		part(90.0)
		kit.quad("decal_dust", pts, Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])


func damage_panel(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(91.0)
	# dented plate: two angled halves + exposed edge
	kit.push_xf(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(7.0)), Vector3(0, 0, 0)))
	kit.box("hull_dark", Vector3(0.8, 0.55, 0.03), Vector3(-0.42, 0, 0))
	kit.pop_xf()
	kit.push_xf(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-5.0)), Vector3(0, 0, 0)))
	kit.box("hull_dark", Vector3(0.7, 0.5, 0.03), Vector3(0.40, -0.02, 0.01))
	kit.pop_xf()
	kit.box("hazard", Vector3(0.06, 0.9, 0.04), Vector3(0, 0, 0.02))
	kit.tube("metal_dark", [Vector3(-0.2, 0.3, 0.06), Vector3(-0.1, -0.1, 0.1), Vector3(0.12, -0.3, 0.08)], 0.02, 5)
	kit.tube("pipe_orange", [Vector3(0.15, 0.28, 0.06), Vector3(0.05, 0.0, 0.1), Vector3(0.22, -0.25, 0.08)], 0.015, 5)
	kit.pop_xf()
	stain(3, Vector3(p.x, p.y - 1.4, p.z), 0.9, 0.7, yaw)


func wall_pipe_run(x: float, y0: float, y1: float, z0: float, z1: float, side: float,
		key: String, radius: float = 0.09) -> void:
	# a vertical riser + a horizontal run along the wall with clamps
	var xx := x + side * 0.22
	var pts := [Vector3(xx, y0, z0), Vector3(xx, y0 + 1.2, z0),
		Vector3(xx, y0 + 1.6, z0 + 0.5), Vector3(xx, y0 + 1.6, z1)]
	part(92.0)
	kit.tube(key, pts, radius, 8)
	var z := z0 + 0.6
	while z < z1:
		kit.box("metal_dark", Vector3(0.12, 0.28, 0.10), Vector3(xx, y0 + 1.6, z))
		z += 2.4
	kit.torus("metal", radius * 1.3, 0.035, 12, 4, Vector3(xx, y0 + 1.6, z0 + 0.5))
	kit.cyl("metal_dark", radius * 1.5, radius * 1.5, 0.06, 10, Vector3(xx, y0 + 0.1, z0))


# ================================================================ quarters ==
func quarters(x0: float, x1: float, z0: float, z1: float, y: float, h: float) -> void:
	var w := x1 - x0
	var d := z1 - z0
	setup("quarters", 0.55 + 0.35 * float(variant % 2), variant)
	# floor life
	stain(0, Vector3(x0 + w * 0.5, y, z0 + d * 0.35), 1.8, 1.2, 0.3)
	footprints(Vector3(x0 + 2.0, y, z1 - 1.2), Vector3(x1 - 3.0, y, z0 + 4.0), 14)
	tape_line(Vector3(x0 + 1.2, y, z0 + 2.0), Vector3(x0 + 1.2, y, z1 - 2.0), 0.06)

	if variant % 3 == 0:
		# bunk room: two rows of double bunks + centre table
		for row in 2:
			var bx: float = x1 - 1.4 if row == 0 else x0 + 1.4
			var yaw := -PI * 0.5 if row == 0 else PI * 0.5
			for i in 2:
				var bz := z0 + 4.0 + i * 5.6
				props.bunk(Vector3(bx, y, bz), yaw)
				props.locker(Vector3(bx + 1.2, y, bz + 2.4), yaw, 0.55, 1.75)
				kit.begin_part(0.4, 26.0)
				kit.box("fabric_dark", Vector3(0.02, 0.5, 1.6), Vector3(bx + (-0.9 if row == 0 else 0.9), y + 1.5, bz - 0.2))
		props.table(Vector3(x0 + w * 0.5, y, z0 + d * 0.55), 2.2, 1.0, 0.75)
		for k in 4:
			var a := TAU * float(k) / 4.0 + 0.5
			props.chair(Vector3(x0 + w * 0.5 + cos(a) * 1.5, y, z0 + d * 0.55 + sin(a) * 0.9), a + PI)
		rug(Vector3(x0 + w * 0.5, y, z0 + d * 0.55), 0.0, 3.4, 2.4)
		coffee_zone(Vector3(x0 + w * 0.5 + 2.2, y, z1 - 1.0), PI)
	else:
		# two private cabins + common room
		var cab_z0 := z0 + 1.2
		var cab_z1 := z0 + 7.0
		for sx in [0.0, 1.0]:
			var bx: float = x0 + 0.8 + sx * (w - 3.4)
			# partition walls
			kit.begin_part(0.35, 1)
			kit.box("wall_pad", Vector3(0.14, 2.6, cab_z1 - cab_z0 + 0.4),
				Vector3(bx + (2.0 if sx == 0.0 else 0.0), y + 1.3, (cab_z0 + cab_z1) * 0.5))
			kit.box("wall_pad", Vector3(2.6, 2.6, 0.14),
				Vector3(bx + 0.0, y + 1.3, cab_z1 + 0.2))
			bed_single(Vector3(bx + 0.9, y, cab_z0 + 1.5), 0.0, rng.randf() > 0.5)
			desk(Vector3(bx + 2.1, y, cab_z0 + 3.0), -PI * 0.5, 1.2)
			props.locker(Vector3(bx + 0.4, y, cab_z0 + 0.9), PI * 0.5, 0.5, 1.7)
			kit.box("fabric_dark", Vector3(0.02, 2.4, 2.4), Vector3(bx + 2.05, y + 1.2, cab_z0 + 0.2))
			photo_wall(Vector3(bx + 2.06, y + 1.7, cab_z0 + 1.6), PI * 0.5, 4)
		# common area
		sofa(Vector3(x0 + w * 0.5, y, z1 - 1.2), PI, 2.2)
		rug(Vector3(x0 + w * 0.5, y, z1 - 3.0), 0.0, 2.6, 1.8)
		props.table(Vector3(x0 + w * 0.5, y, z1 - 3.4), 1.8, 0.9, 0.72)
		kitchenette(Vector3(x0 + w * 0.5 - 1.6, y, z1 - 5.4), PI)
		props.table(Vector3(x0 + w * 0.5 + 2.0, y, z1 - 5.2), 1.2, 0.8, 0.72)
		mug(Vector3(x0 + w * 0.5 + 2.2, y + 0.75, z1 - 5.0), 0.4)
		book_stack(Vector3(x0 + w * 0.5 + 1.8, y + 0.76, z1 - 5.3), 0.2, 2)
		noticeboard(Vector3(x0 + w * 0.5, y + 1.7, z1 + 0.02), PI, 1.6, 1.0)
		bin(Vector3(x0 + w - 0.9, y, z1 - 0.9), 0)
		fire_extinguisher(Vector3(x0 + 0.35, y + 1.2, z1 - 2.5), PI * 0.5)
		first_aid(Vector3(x0 + 0.3, y + 1.8, z0 + 2.2), PI * 0.5)

	fill_perimeter(x0, x1, z0, z1, y, h, "hab", 2.5)
	# shared: porthole, signs, small life
	props.glass_panel(Vector3(x1 - 0.06, y + 2.45, z0 + d * 0.62), 3.4, 1.7, PI * 0.5, true)
	poster(Vector3(x1 - 0.02, y + 2.1, z0 + 2.0), PI * 0.5, 0.55, 0.8, "fabric_rust")
	poster(Vector3(x0 + 0.02, y + 2.2, z1 - 6.2), -PI * 0.5, 0.5, 0.7, "fabric_teal")
	label("CREW QUARTERS 04", Vector3(x0 + 0.2, y + 3.45, z0 + 2.0), PI * 0.5, 0.34,
		Color(1.0, 0.8, 0.55))
	planter_small(Vector3(x1 - 1.0, y, z1 - 1.2))
	if wear > 0.7:
		stain(1, Vector3(x0 + 2.4, y, z1 - 4.0), 0.8, 0.6, 0.4)
		damage_panel(Vector3(x1 - 0.05, y + 1.4, z0 + 3.2), PI * 0.5)
	# mood light
	light(Vector3(x0 + w * 0.5, y + 3.4, z0 + d * 0.5), Color(1.0, 0.78, 0.52), 4.2, 11.0, false)
	light(Vector3(x0 + 2.2, y + 3.2, z1 - 3.0), Color(1.0, 0.82, 0.6), 3.0, 9.0, false)
	light(Vector3(x0 + w - 2.5, y + 3.2, z0 + 3.0), Color(1.0, 0.8, 0.55), 2.8, 9.0, false)
	light(Vector3(x0 + 1.6, y + 2.6, z0 + d * 0.5), Color(1.0, 0.7, 0.45), 1.8, 7.0, false)


func coffee_zone(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(87.0)
	kit.box_bevel("metal_painted", Vector3(1.2, 0.9, 0.55), Vector3(0, 0.45, 0), 0.03)
	kit.box("metal", Vector3(1.24, 0.05, 0.6), Vector3(0, 0.92, 0))
	kit.box("metal_dark", Vector3(0.4, 0.5, 0.4), Vector3(-0.25, 1.2, 0))
	kit.box("screen_power", Vector3(0.26, 0.14, 0.02), Vector3(-0.25, 1.3, 0.21))
	kit.box("ceramic_dark", Vector3(0.3, 0.02, 0.3), Vector3(-0.25, 0.96, 0.02))
	kit.cyl("metal_dark", 0.02, 0.02, 0.14, 6, Vector3(-0.1, 1.0, 0.1))
	for i in 3:
		mug(Vector3(0.12 + i * 0.15, 0.94, 0.12), rng.randf_range(0, TAU))
	bottle(Vector3(0.35, 0.94, -0.10), "food_b")
	kit.pop_xf()


func planter_small(p: Vector3) -> void:
	plant_small(p, 1.2)


# ================================================================= medbay ===
func medbay(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("medbay", 0.35 + 0.3 * float(variant_i % 2), variant_i)
	var w := x1 - x0
	var d := z1 - z0
	# clean floor, subtle wear near the door
	stain(2, Vector3(x0 + 3.0, y, z1 - 2.0), 1.4, 1.0, 0.2)
	footprints(Vector3(x0 + 2.2, y, z1 - 2.0), Vector3(x0 + 2.6, y, z0 + 3.0), 8)
	if variant_i % 3 == 0:
		# ward: three beds with curtains
		for i in 3:
			var bz := z0 + 4.0 + i * 4.4
			bed_single(Vector3(x0 + 3.2, y, bz), PI * 0.5, i == 1)
			kit.begin_part(0.4, 21.0)
			kit.box("metal_dark", Vector3(0.05, 2.2, 0.05), Vector3(x0 + 5.1, y + 1.1, bz - 1.2))
			kit.box("metal_dark", Vector3(0.05, 2.2, 0.05), Vector3(x0 + 5.1, y + 1.1, bz + 1.2))
			kit.box("fabric_grey", Vector3(0.02, 2.0, 2.2), Vector3(x0 + 5.08, y + 1.0, bz))
			kit.box("screen_med", Vector3(0.06, 0.6, 0.9), Vector3(x0 + 1.7, y + 1.7, bz))
			overhead_light(Vector3(x0 + 3.2, y + 2.65, bz))
			# stool, chart, IV stand
			pack_stool(Vector3(x0 + 4.2, y, bz + 1.4))
			iv_stand(Vector3(x0 + 2.0, y, bz + 1.5))
			kit.box("paper", Vector3(0.2, 0.01, 0.28), Vector3(x0 + 4.6, y + 0.86, bz - 0.8))
		props.shelf(Vector3(x0 + 0.4, y, z0 + 4.2), PI * 0.5, 2.0, 2.0)
		props.console(Vector3(x0 + w * 0.55, y, z1 - 1.2), PI, 2.0, "screen_med")
		props.chair(Vector3(x0 + w * 0.55, y, z1 - 2.4), PI)
	elif variant_i % 3 == 1:
		# theatre: central surgical table, big light, side carts
		var cz := z0 + d * 0.52
		kit.begin_part(0.5, 62.0)
		kit.box_bevel("metal_light", Vector3(2.2, 0.45, 1.0), Vector3(x0 + w * 0.5, y + 0.55, cz), 0.05)
		kit.box_bevel("wall_white", Vector3(2.0, 0.14, 0.9), Vector3(x0 + w * 0.5, y + 0.82, cz), 0.04)
		kit.cyl("metal_dark", 0.25, 0.30, 0.5, 12, Vector3(x0 + w * 0.5, y + 0.2, cz))
		overhead_light(Vector3(x0 + w * 0.5, y + 2.9, cz), 1.6)
		for sx in [-1.0, 1.0]:
			surgical_cart(Vector3(x0 + w * 0.5 + sx * 2.2, y, cz + 0.4), -sx * PI * 0.5)
		props.console(Vector3(x0 + w * 0.5 - 2.6, y, cz - 2.6), 0.0, 1.8, "screen_med")
		props.console(Vector3(x0 + w * 0.5 + 2.4, y, cz - 2.6), PI, 1.8, "screen_log")
		# recovery beds along the outer wall
		for i in 2:
			bed_single(Vector3(x0 + 2.4, y, z0 + 3.2 + i * 4.0), PI * 0.5, false)
		props.shelf(Vector3(x0 + 0.5, y, z1 - 2.2), PI * 0.5, 1.8, 2.0)
		bin(Vector3(x1 - 1.2, y, z1 - 1.4), 1)
		cabinet_med(Vector3(x1 - 0.7, y + 1.5, z0 + 3.0), PI * 0.5)
	else:
		# clinic / triage
		exam_table(Vector3(x0 + 3.0, y, z0 + 5.0), PI * 0.5)
		desk(Vector3(x0 + w - 2.0, y, z0 + 2.2), 0.0, 1.6)
		props.chair(Vector3(x0 + w - 2.0, y, z0 + 3.2), PI)
		props.bench(Vector3(x0 + w * 0.5, y, z1 - 1.0), PI, 2.0)
		cabinet_med(Vector3(x0 + 0.6, y + 1.6, z0 + 2.2), PI * 0.5)
		props.shelf(Vector3(x0 + 0.4, y, z1 - 3.2), PI * 0.5, 1.6, 2.0)
		bin(Vector3(x1 - 1.0, y, z1 - 0.8), 1)
		water_cooler(Vector3(x1 - 0.8, y, z0 + 1.4))
		overhead_light(Vector3(x0 + 3.0, y + 2.7, z0 + 5.0))
	fill_perimeter(x0, x1, z0, z1, y, h, "med", 2.5)
	label("MEDICAL  ·  BAY 2", Vector3(x0 + 0.2, y + 3.4, z0 + 2.0), PI * 0.5, 0.34,
		Color(0.5, 1.0, 0.7))
	noticeboard(Vector3(x1 - 0.04, y + 1.7, z1 - 2.4), -PI * 0.5, 1.2, 0.9)
	poster(Vector3(x0 + 0.04, y + 2.0, z1 - 3.4), PI * 0.5, 0.45, 0.65, "fabric_teal")
	light(Vector3(x0 + w * 0.5, y + 3.6, z0 + d * 0.5), Color(0.9, 1.0, 1.0), 3.8, 11.0, false)
	light(Vector3(x0 + 2.0, y + 3.2, z1 - 3.0), Color(0.85, 0.95, 1.0), 2.2, 8.0, false)
	light(Vector3(x0 + w - 3.0, y + 3.2, z0 + 3.0), Color(0.9, 1.0, 1.0), 2.0, 7.0, false)


func overhead_light(p: Vector3, size: float = 1.0) -> void:
	part(62.0)
	kit.box("metal", Vector3(size * 1.2, 0.08, 0.6), p)
	kit.box("emit_white", Vector3(size, 0.03, 0.48), p + Vector3(0, -0.055, 0))
	kit.tube("metal", [p + Vector3(0, 0.04, 0), p + Vector3(0, 0.5, 0)], 0.03, 5)
	light(p + Vector3(0, -0.25, 0), Color(0.95, 1.0, 1.0), 2.2, 5.0, false)


func pack_stool(p: Vector3) -> void:
	part(62.0)
	kit.cyl("metal_dark", 0.18, 0.15, 0.06, 12, p + Vector3(0, 0.02, 0))
	kit.cyl("metal", 0.04, 0.04, 0.48, 8, p + Vector3(0, 0.25, 0))
	kit.cyl("rubber_worn", 0.20, 0.20, 0.06, 12, p + Vector3(0, 0.5, 0))


func iv_stand(p: Vector3) -> void:
	part(62.0)
	kit.cyl("metal", 0.02, 0.02, 1.8, 8, p + Vector3(0, 0.9, 0))
	for i in 3:
		var a := TAU * float(i) / 3.0
		kit.box("metal_dark", Vector3(0.04, 0.04, 0.4),
			p + Vector3(cos(a) * 0.18, 0.02, sin(a) * 0.18))
	kit.box("glass", Vector3(0.10, 0.24, 0.10), p + Vector3(0.12, 1.55, 0))
	kit.tube("rubber", [p + Vector3(0.12, 1.45, 0), p + Vector3(0.06, 1.1, 0.05),
		p + Vector3(0.10, 0.8, 0.12)], 0.008, 4)


func surgical_cart(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(62.0)
	kit.box_bevel("metal_light", Vector3(0.7, 0.06, 0.5), Vector3(0, 0.85, 0), 0.02)
	for sx in [-1.0, 1.0]:
		kit.cyl("metal", 0.02, 0.02, 0.8, 6, Vector3(sx * 0.28, 0.42, 0.19))
		kit.cyl("metal", 0.02, 0.02, 0.8, 6, Vector3(sx * 0.28, 0.42, -0.19))
	kit.box("metal_light", Vector3(0.7, 0.04, 0.5), Vector3(0, 0.5, 0))
	for i in 4:
		kit.cyl("metal_light", 0.012, 0.008, 0.18, 6,
			Vector3(-0.2 + i * 0.13, 0.95, 0.05))
	kit.box("metal_cast", Vector3(0.26, 0.12, 0.18), Vector3(0.22, 0.94, -0.1))
	kit.pop_xf()


func cabinet_med(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(62.0)
	kit.box_bevel("wall_white", Vector3(1.1, 0.9, 0.35), Vector3(0, 0.45, 0), 0.03)
	kit.box("glass_med", Vector3(0.95, 0.6, 0.02), Vector3(0, 0.55, 0.19))
	for i in 5:
		kit.cyl("glass_bottle", 0.035, 0.035, 0.12, 8, Vector3(-0.36 + i * 0.16, 0.32, 0.15))
	kit.box("emit_green", Vector3(0.2, 0.04, 0.01), Vector3(0, 0.9, 0.2))
	kit.pop_xf()


func exam_table(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(62.0)
	kit.box_bevel("metal_light", Vector3(2.0, 0.20, 0.8), Vector3(0, 0.75, 0), 0.04)
	kit.cyl("metal_dark", 0.08, 0.08, 0.62, 8, Vector3(-0.6, 0.32, 0))
	kit.cyl("metal_dark", 0.08, 0.08, 0.62, 8, Vector3(0.6, 0.32, 0))
	kit.box("fabric_white", Vector3(1.8, 0.06, 0.7), Vector3(0, 0.86, 0))
	kit.pop_xf()


func water_cooler(p: Vector3) -> void:
	part(62.0)
	kit.cyl("metal_light", 0.22, 0.22, 0.95, 14, p)
	kit.cyl("glass_bottle", 0.18, 0.14, 0.45, 14, p + Vector3(0, 0.95, 0))
	kit.box("metal_dark", Vector3(0.12, 0.06, 0.12), p + Vector3(0, 0.7, 0.2))


# ============================================================ observation ===
func observation(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("observation", 0.4, variant_i)
	var w := x1 - x0
	var d := z1 - z0
	stain(0, Vector3(x0 + w * 0.5, y, z1 - 2.5), 1.6, 1.0, 0.4)
	if variant_i % 2 == 0:
		# bar lounge
		bar_counter(Vector3(x0 + 1.2, y, z1 - 5.2), PI * 0.5, d * 0.6)
		for i in 3:
			var zz := z0 + 4.0 + i * 4.2
			props.table(Vector3(x0 + w * 0.55, y, zz), 1.1, 0.9, 0.72)
			for k in 2:
				props.chair(Vector3(x0 + w * 0.55 + (k * 2 - 1) * 0.9, y, zz), 0.0 if k == 0 else PI)
				mug(Vector3(x0 + w * 0.55 + (k * 2 - 1) * 0.25, y + 0.75, zz + 0.1), rng.randf() * TAU)
			book_stack(Vector3(x0 + w * 0.55 - 0.2, y + 0.76, zz - 0.2), 0.3, 2)
		props.bench(Vector3(x0 + w * 0.5, y, z0 + 2.4), 0.0, 3.6)
	else:
		# sensor observatory
		props.console(Vector3(x0 + 2.4, y, z0 + 4.0), 0.0, 2.2, "screen_nav")
		props.console(Vector3(x0 + 4.8, y, z0 + 4.0), 0.0, 2.2, "screen_power")
		props.chair(Vector3(x0 + 2.4, y, z0 + 5.2), 0.0)
		props.chair(Vector3(x0 + 4.8, y, z0 + 5.2), 0.0)
		telescope(Vector3(x0 + w * 0.5, y, z0 + 8.4))
		props.table(Vector3(x0 + w - 3.0, y, z1 - 3.0), 1.4, 0.9, 0.72)
		sofa(Vector3(x0 + w * 0.5, y, z1 - 1.2), PI, 2.6)
		rug(Vector3(x0 + w * 0.5, y, z1 - 3.2), 0.0, 3.0, 2.0)
	fill_perimeter(x0, x1, z0, z1, y, h, "hab", 2.5)
	planter_small(Vector3(x1 - 1.1, y, z0 + 2.0))
	planter_small(Vector3(x0 + 1.2, y, z0 + 2.0))
	poster(Vector3(x0 + 0.03, y + 2.1, z1 - 2.4), PI * 0.5, 0.5, 0.7, "fabric_teal")
	label("OBSERVATION  ·  LEVEL 03", Vector3(x0 + 0.2, y + 3.5, z0 + 2.0), PI * 0.5, 0.32,
		Color(0.5, 0.85, 1.0))
	light(Vector3(x0 + w * 0.5, y + 4.0, z0 + d * 0.5), Color(1.0, 0.72, 0.45), 4.0, 10.0, false)


func bar_counter(p: Vector3, yaw: float, length: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(87.0)
	kit.box_bevel("fabric_rust", Vector3(0.6, 1.05, length), Vector3(0, 0.52, 0), 0.03)
	kit.box("metal_light", Vector3(0.75, 0.06, length + 0.1), Vector3(0, 1.08, 0))
	kit.box("metal_dark", Vector3(0.7, 0.12, length + 0.1), Vector3(0, 1.14, 0))
	for i in int(length / 1.2):
		var zz := -length * 0.5 + 0.6 + i * 1.2
		kit.cyl("metal", 0.025, 0.02, 0.9, 6, Vector3(0, 1.7, zz))
		kit.cyl("emit_warm", 0.09, 0.06, 0.12, 10, Vector3(0, 2.1, zz))
		for k in 3:
			bottle(Vector3(0.15, 1.17, zz - 0.2 + k * 0.2), "glass_bottle")
		for k in 2:
			mug(Vector3(-0.1 + k * 0.2, 1.17, zz + 0.35), rng.randf() * TAU)
	kit.pop_xf()


func telescope(p: Vector3) -> void:
	part(87.0)
	kit.cyl("metal_dark", 0.34, 0.30, 0.10, 14, p)
	kit.cyl("metal", 0.07, 0.05, 1.2, 8, p + Vector3(0, 0.65, 0))
	kit.push_xf(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-38.0)), p + Vector3(0, 1.3, 0.1)))
	kit.cyl("metal_light", 0.20, 0.14, 1.4, 16, Vector3.ZERO)
	kit.cyl("glass_dark", 0.15, 0.15, 0.03, 16, Vector3(0, 1.4, 0))
	kit.torus("metal", 0.19, 0.02, 18, 4, Vector3(0, 1.35, 0))
	kit.pop_xf()


# =============================================================== machine ====
func machine_shop(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("machine", 1.15 + 0.3 * float(variant_i % 2), variant_i)
	var w := x1 - x0
	var d := z1 - z0
	# floor life: oil, dust, tape, worn walkway
	stain(1, Vector3(x0 + w * 0.35, y, z0 + d * 0.35), 2.0, 1.4, 0.3)
	stain(0, Vector3(x0 + w * 0.62, y, z0 + d * 0.6), 1.2, 1.0, -0.2)
	stain(1, Vector3(x0 + w * 0.7, y, z0 + d * 0.25), 0.9, 0.7, 0.8)
	footprints(Vector3(x0 + 2.0, y, z1 - 2.0), Vector3(x0 + w * 0.55, y, z0 + 4.0), 16)
	tape_line(Vector3(x0 + 1.0, y, z0 + 4.0), Vector3(x1 - 1.0, y, z0 + 4.0))
	tape_line(Vector3(x0 + 1.0, y, z0 + 4.0), Vector3(x0 + 1.0, y, z1 - 3.0))
	if variant_i % 3 == 0:
		lathe(Vector3(x0 + 3.0, y, z0 + d * 0.35), PI * 0.5)
		lathe(Vector3(x0 + 3.0, y, z0 + d * 0.65), PI * 0.5)
		workbench(Vector3(x1 - 2.2, y, z0 + d * 0.5), PI * 0.5, 2.4)
		drill_press(Vector3(x0 + 6.2, y, z1 - 3.0), PI)
		stock_rack(Vector3(x1 - 1.2, y, z0 + 3.0))
		parts_rack(Vector3(x1 - 1.4, y, z1 - 5.0), PI * 0.5, 2.2)
	elif variant_i % 3 == 1:
		# welding / fab bay
		workbench(Vector3(x0 + 3.2, y, z0 + 4.0), 0.0, 2.8)
		welder(Vector3(x0 + 3.0, y, z0 + 7.4), PI)
		kit.begin_part(0.4, 80.0)
		kit.box("metal_cast", Vector3(2.4, 0.9, 1.4), Vector3(x0 + w * 0.55, y + 0.45, z0 + d * 0.62))
		kit.box("metal_light", Vector3(2.2, 0.06, 1.2), Vector3(x0 + w * 0.55, y + 0.93, z0 + d * 0.62))
		stain(3, Vector3(x0 + w * 0.55, y, z0 + d * 0.62), 1.6, 1.2, 0.1)
		stock_rack(Vector3(x1 - 1.3, y, z0 + 3.0))
		parts_rack(Vector3(x1 - 1.3, y, z1 - 5.0), PI * 0.5, 2.0)
		kill_switch(Vector3(x0 + 0.4, y + 1.6, z0 + 2.0), PI * 0.5)
	else:
		# electronics repair
		workbench(Vector3(x0 + 3.0, y, z0 + 4.0), 0.0, 2.2)
		workbench(Vector3(x0 + 3.0, y, z0 + 7.0), 0.0, 2.2)
		props.shelf(Vector3(x0 + 0.5, y, z0 + 5.5), PI * 0.5, 2.0, 2.2)
		parts_rack(Vector3(x1 - 1.4, y, z1 - 5.0), PI * 0.5, 2.0)
		diagnostic_rig(Vector3(x0 + w * 0.55, y, z0 + d * 0.6))
		props.console(Vector3(x0 + w * 0.55, y, z1 - 2.0), PI, 2.4, "screen_log")
	for i in 3:
		cable_coil(Vector3(x0 + rng.randf_range(1.5, w - 1.5), y, z0 + rng.randf_range(2.0, d - 2.0)),
			rng.randf_range(0.3, 0.55), 3)
	bin(Vector3(x1 - 1.0, y, z1 - 1.2), 0)
	fire_extinguisher(Vector3(x0 + 0.35, y + 1.3, z1 - 2.2), PI * 0.5)
	first_aid(Vector3(x0 + 0.3, y + 1.8, z0 + 2.0), PI * 0.5)
	ppe_cabinet(Vector3(x1 - 0.6, y, z0 + 1.2), PI * 0.5)
	noticeboard(Vector3(x0 + 3.0, y + 1.65, z1 - 0.05), PI, 1.6, 1.0)
	fill_perimeter(x0, x1, z0, z1, y, h, "machine", 3.0)
	label("MACHINE SHOP  ·  FAB 3", Vector3(x0 + w * 0.5, y + 5.0, z1 - 0.4), PI, 0.5,
		Color(1.0, 0.65, 0.3))
	light(Vector3(x0 + w * 0.5, y + 5.4, z0 + d * 0.5), Color(0.9, 0.95, 1.0), 4.0, 12.0, false)
	light(Vector3(x0 + 3.0, y + 4.0, z1 - 3.0), Color(1.0, 0.85, 0.6), 3.0, 9.0, false)


func kill_switch(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(80.0)
	kit.box("metal_dark", Vector3(0.4, 0.5, 0.15), Vector3.ZERO)
	kit.box("hazard", Vector3(0.26, 0.16, 0.04), Vector3(0, 0.06, 0.09))
	kit.cyl("emit_red", 0.06, 0.06, 0.05, 12, Vector3(0, -0.12, 0.1))
	kit.pop_xf()


func diagnostic_rig(p: Vector3) -> void:
	part(80.0)
	kit.box("metal_dark", Vector3(1.2, 1.4, 0.5), p + Vector3(0, 0.7, 0))
	kit.box("screen_log", Vector3(1.0, 0.7, 0.02), p + Vector3(0, 0.9, 0.26))
	for i in 4:
		kit.tube("rubber", [p + Vector3(-0.4 + i * 0.25, 0.2, 0.2),
			p + Vector3(-0.6 + i * 0.3, 0.02, 0.8), p + Vector3(-0.5 + i * 0.28, 0.02, 1.2)], 0.012, 4)
	kit.box("emit_green", Vector3(0.3, 0.04, 0.02), p + Vector3(0, 1.33, 0.26))


# ================================================================ officers ===
func officers(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("officers", 0.35, variant_i)
	var w := x1 - x0
	var d := z1 - z0
	stain(0, Vector3(x0 + w * 0.5, y, z0 + 3.0), 1.4, 1.0, 0.2)
	if variant_i % 2 == 0:
		for i in 2:
			for side in [-1.0, 1.0]:
				var cz := z0 + 4.0 + i * 5.0
				bed_single(Vector3(x0 + w * 0.5 + side * (w * 0.5 - 2.0), y, cz), 0.0, true)
				desk(Vector3(x0 + w * 0.5 + side * (w * 0.5 - 2.0), y, cz - 2.4), PI, 1.2)
				props.locker(Vector3(x0 + w * 0.5 + side * (w * 0.5 - 3.2), y, cz + 1.6), PI * 0.5, 0.5, 1.8)
				photo_wall(Vector3(x0 + w * 0.5 + side * 2.0, y + 1.8, cz + 0.4), -side * PI * 0.5, 3)
	else:
		# briefing room + two suites
		props.table(Vector3(x0 + w * 0.5, y, z0 + 3.0), 2.8, 1.3, 0.76)
		for k in 6:
			var a := TAU * float(k) / 6.0
			props.chair(Vector3(x0 + w * 0.5 + cos(a) * 1.9, y, z0 + 3.0 + sin(a) * 1.2), -a + PI * 0.5)
		holo_board(Vector3(x0 + w * 0.5, y + 2.4, z0 + 0.1), 0.0)
		desk(Vector3(x0 + w * 0.5, y, z1 - 4.6), PI, 2.0)
		props.chair(Vector3(x0 + w * 0.5, y, z1 - 3.4), 0.0)
		sofa(Vector3(x0 + w * 0.5, y, z1 - 1.2), PI, 2.4)
		bookshelf(Vector3(x0 + 1.0, y, z1 - 2.0), PI * 0.5, 2.2)
	fill_perimeter(x0, x1, z0, z1, y, h, "hab", 2.5)
	label("OFFICER COUNTRY  ·  LEVEL 03", Vector3(x0 + 0.2, y + 3.8, z1 - 0.4), PI, 0.42,
		Color(1.0, 0.75, 0.5))
	light(Vector3(x0 + w * 0.5, y + 4.2, z0 + d * 0.5), Color(1.0, 0.76, 0.5), 4.2, 11.0, false)
	light(Vector3(x0 + 2.5, y + 3.4, z1 - 3.0), Color(1.0, 0.8, 0.55), 2.4, 8.0, false)


func holo_board(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(92.0)
	kit.box("metal_dark", Vector3(3.0, 1.7, 0.10), Vector3.ZERO)
	kit.box("holo_soft", Vector3(2.7, 1.45, 0.02), Vector3(0, 0, 0.07))
	kit.box("metal", Vector3(3.1, 0.08, 0.14), Vector3(0, 0.9, 0))
	kit.pop_xf()


func bookshelf(p: Vector3, yaw: float, w: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(92.0)
	kit.box("metal_painted", Vector3(w, 2.4, 0.35), Vector3(0, 1.2, 0))
	for i in 4:
		kit.box("metal_dark", Vector3(w - 0.1, 0.04, 0.32), Vector3(0, 0.4 + i * 0.5, 0))
		for k in int(w / 0.09):
			kit.box("paper_b" if (i + k) % 3 else "fabric_rust",
				Vector3(0.06, 0.20 + (k % 3) * 0.03, 0.24),
				Vector3(-w * 0.5 + 0.08 + k * 0.09, 0.52 + i * 0.5, 0))
	kit.pop_xf()


# =============================================================== cargo ======
func cargo_extras(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("cargo", 0.9 + 0.25 * float(variant_i % 2), variant_i)
	var w := x1 - x0
	var d := z1 - z0
	for i in 3:
		stain(1 if i % 2 == 0 else 0,
			Vector3(x0 + rng.randf_range(5.0, w - 5.0), y, z0 + rng.randf_range(4.0, d - 4.0)),
			rng.randf_range(1.0, 2.4), rng.randf_range(0.8, 1.8), rng.randf() * TAU)
	footprints(Vector3(0, y, z0 + 4.0), Vector3(0, y, z1 - 5.0), 22)
	# packing / manifest station
	manifest_station(Vector3(x0 + 3.2, y, z1 - 2.4), 0.0)
	if variant_i % 3 == 0:
		# sealed hazmat corner
		for i in 3:
			for k in 2:
				kit.begin_part(0.4, 75.0)
				kit.cyl("hazard", 0.36, 0.36, 0.95, 14,
					Vector3(x1 - 2.0 - i * 1.0, y + 0.48, z0 + 5.0 + k * 1.2))
				kit.torus("metal_dark", 0.38, 0.03, 16, 4,
					Vector3(x1 - 2.0 - i * 1.0, y + 0.8, z0 + 5.0 + k * 1.2))
		tape_line(Vector3(x1 - 5.5, y, z0 + 3.0), Vector3(x1 - 5.5, y, z0 + 9.0))
		label("HAZMAT  ·  CLASS 4", Vector3(x1 - 5.6, y + 2.2, z0 + 6.0), -PI * 0.5, 0.4,
			Color(1.0, 0.5, 0.15))
	elif variant_i % 3 == 1:
		# palletised spares + forklift
		for i in 4:
			pallet(Vector3(x0 + 8.0 + i * 1.8, y, z1 - 3.0), 0.0, 1.4, 1.2)
			crate(Vector3(x0 + 8.0 + i * 1.8, y + 0.14, z1 - 3.0), 1.2, 0.8, 1.0, "container_c")
		forklift(Vector3(x1 - 4.0, y, z0 + 6.0), PI * 0.5)
		parts_rack(Vector3(x0 + 2.0, y, z0 + 3.0), PI * 0.5, 2.2)
	else:
		# cargo netting + loose crates + a damaged container
		for i in 5:
			crate(Vector3(x0 + 5.0 + rng.randf_range(-1.0, 1.0) + i * 1.2, y,
				z0 + 6.0 + rng.randf_range(-0.4, 0.4)), 0.9, 0.7, 0.8, "metal_painted")
		kit.begin_part(0.4, 24.0)
		kit.box("container_b", Vector3(6.1, 2.6, 2.44),
			Vector3(x1 - 4.0, y + 1.3, z0 + 6.0))
		stain(3, Vector3(x1 - 4.0, y, z0 + 7.4), 1.8, 1.2)
		damage_panel(Vector3(x1 - 0.05, y + 1.5, z1 - 6.0), -PI * 0.5)
	for i in 2:
		bin(Vector3(x0 + 2.5 + i * 1.0, y, z0 + 2.0), 0)
	label("CARGO 02  ·  MANIFEST STATION", Vector3(x0 + 3.2, y + 2.5, z1 - 2.5), 0, 0.34,
		Color(0.5, 0.85, 1.0))


func manifest_station(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(85.0)
	kit.box("metal_painted", Vector3(1.6, 0.9, 0.6), Vector3(0, 0.45, 0))
	kit.box("metal", Vector3(1.66, 0.06, 0.66), Vector3(0, 0.93, 0))
	kit.box("screen_log", Vector3(0.8, 0.45, 0.02), Vector3(0, 1.25, -0.1))
	kit.box("metal_dark", Vector3(0.9, 0.5, 0.08), Vector3(0, 1.25, -0.16))
	papers(Vector3(0.4, 0.96, 0.05), 0.2, 4)
	tablet(Vector3(-0.4, 0.96, 0.06), 0.1)
	mug(Vector3(0.6, 0.94, 0.18), 0.4)
	kit.pop_xf()


func pallet(p: Vector3, yaw: float, w: float, d: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(76.0)
	for i in 4:
		kit.box("metal_painted", Vector3(w, 0.05, 0.12), Vector3(0, 0.10 + i * 0.015, -d * 0.5 + 0.1 + i * d * 0.3))
	for sx in [-1.0, 1.0]:
		kit.box("metal_painted", Vector3(0.12, 0.08, d), Vector3(sx * (w * 0.5 - 0.1), 0.04, 0))
	kit.pop_xf()


func forklift(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(64.0)
	kit.box_bevel("hazard", Vector3(1.2, 0.9, 1.8), Vector3(0, 0.65, 0), 0.05)
	kit.box("metal_dark", Vector3(1.3, 0.35, 0.5), Vector3(0, 0.25, 0.75))
	kit.box("metal_dark", Vector3(0.9, 0.7, 0.9), Vector3(0, 0.7, 0.5))
	kit.box("glass_dark", Vector3(0.7, 0.5, 0.06), Vector3(0, 1.15, -0.25))
	kit.box("metal_dark", Vector3(0.8, 1.2, 0.8), Vector3(0, 1.5, -0.1))
	for sx in [-1.0, 1.0]:
		kit.cyl("rubber_worn", 0.28, 0.28, 0.20, 14, Vector3(sx * 0.55, 0.28, -0.55))
		kit.cyl("rubber_worn", 0.22, 0.22, 0.18, 12, Vector3(sx * 0.55, 0.22, 0.55))
		kit.box("metal_dark", Vector3(0.10, 1.5, 0.12), Vector3(sx * 0.5, 0.85, 1.15))
	kit.box("metal", Vector3(1.1, 0.12, 0.12), Vector3(0, 0.1, 1.2))
	kit.pop_xf()


func crate(p: Vector3, w: float, hh: float, d: float, key: String) -> void:
	kit.begin_part(0.4, 23.0)
	kit.box_bevel(key, Vector3(w, hh, d), p + Vector3(0, hh * 0.5, 0), 0.03)
	kit.box("metal_dark", Vector3(w + 0.02, 0.05, d + 0.02), p + Vector3(0, hh * 0.2, 0))
	kit.box("paper", Vector3(w * 0.35, hh * 0.16, 0.01), p + Vector3(0, hh * 0.6, d * 0.5 + 0.01))


# =============================================================== engine =====
func engine_extras(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("engine", 1.2 + 0.25 * float(variant_i % 2), variant_i)
	var w := x1 - x0
	var d := z1 - z0
	# coolant puddles, footprints, scorch
	stain(1, Vector3(x0 + 5.0, y, z0 + 10.0), 2.2, 1.6, 0.2)
	stain(1, Vector3(x0 + 7.5, y, z0 + 18.0), 1.6, 1.2, 0.8)
	stain(3, Vector3(x0 + w - 6.0, y, z0 + d - 8.0), 1.8, 1.4, 0.5)
	footprints(Vector3(7.0, y, z0 + 8.0), Vector3(7.0, y, z1 - 4.0), 24)
	# spares and tooling around the periphery
	tool_cart(Vector3(x0 + 3.8, y, z0 + d * 0.62), PI * 0.5)
	cable_coil(Vector3(x0 + 2.0, y, z1 - 8.0), 0.55, 4)
	cable_coil(Vector3(x0 + 2.0, y, z1 - 6.8), 0.45, 3)
	spare_nozzle(Vector3(x1 - 3.2, y, z0 + 14.0), PI * 0.5)
	parts_rack(Vector3(x0 + 1.2, y, z0 + 6.0), PI * 0.5, 2.4)
	storage_cabinet(Vector3(x0 + 0.5, y, z0 + 22.0), PI * 0.5, 1.2, 1.9)
	ppe_cabinet(Vector3(x1 - 0.7, y, z0 + 30.0), -PI * 0.5)
	bespoke("INSPECTION CAGE 04", Vector3(x1 - 0.5, y + 4.6, z0 + 26.0), -PI * 0.5, 0.4,
		Color(1.0, 0.55, 0.2))
	# work light on a portable stand
	work_light(Vector3(x1 - 3.0, y, z1 - 10.0))
	# pipe leak + drip stains
	wall_pipe_run(x0, y + 2.0, y + 6.0, z0 + 6.0, z1 - 6.0, 1.0, "pipe_orange", 0.10)
	wall_pipe_run(x0, y + 2.6, y + 6.0, z0 + 9.0, z1 - 9.0, 1.0, "pipe_cream", 0.07)
	label("DRIVE BAY 2  ·  KEEP CLEAR", Vector3(x0 + 0.5, y + 3.2, z0 + 14.0), PI * 0.5, 0.34,
		Color(1.0, 0.62, 0.25))
	light(Vector3(x0 + 4.0, y + 2.6, z0 + d * 0.55), Color(1.0, 0.55, 0.22), 2.6, 9.0, false)


func bespoke(text: String, p: Vector3, yaw: float, size: float, col: Color) -> void:
	label(text, p, yaw, size, col)


func tool_cart(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(76.0)
	for i in 3:
		kit.box("metal_cast", Vector3(0.9, 0.28, 0.55), Vector3(0, 0.22 + i * 0.30, 0))
	for sx in [-1.0, 1.0]:
		kit.cyl("rubber_worn", 0.10, 0.10, 0.06, 8, Vector3(sx * 0.35, 0.05, 0.22))
		kit.cyl("rubber_worn", 0.10, 0.10, 0.06, 8, Vector3(sx * 0.35, 0.05, -0.22))
		kit.box("metal_dark", Vector3(0.05, 1.0, 0.05), Vector3(sx * 0.42, 0.9, -0.24))
	kit.box("metal", Vector3(1.0, 0.04, 0.65), Vector3(0, 1.14, 0))
	kit.box("hazard", Vector3(0.9, 0.04, 0.05), Vector3(0, 0.95, 0.3))
	tools_scatter(Vector3(0, 1.18, 0), yaw + 0.4)
	kit.pop_xf()


func spare_nozzle(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(75.0)
	kit.cyl("metal_cast", 0.55, 0.82, 1.4, 20, Vector3.ZERO)
	kit.torus("metal", 0.86, 0.07, 20, 6, Vector3(0, 1.4, 0))
	kit.torus("metal_dark", 0.6, 0.05, 20, 5, Vector3(0, 0.4, 0))
	kit.pop_xf()


func work_light(p: Vector3) -> void:
	part(75.0)
	kit.cyl("metal_dark", 0.28, 0.24, 0.08, 12, p)
	kit.cyl("metal", 0.035, 0.03, 1.8, 8, p + Vector3(0, 0.9, 0))
	kit.push_xf(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-25.0)), p + Vector3(0, 1.85, 0)))
	kit.cyl("metal_dark", 0.22, 0.12, 0.2, 14, Vector3.ZERO)
	kit.cyl("emit_warm", 0.17, 0.17, 0.02, 14, Vector3(0, 0.20, 0))
	kit.pop_xf()
	light(p + Vector3(0, 1.9, 0.2), Color(1.0, 0.8, 0.5), 1.2, 5.0, false)


# ================================================================ reactor ===
func reactor_extras(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("reactor", 0.6 + 0.2 * float(variant_i % 2), variant_i)
	var w := x1 - x0
	var d := z1 - z0
	stain(2, Vector3(x0 + 5.0, y, z1 - 5.0), 1.8, 1.2, 0.2)
	stain(0, Vector3(x1 - 5.0, y, z0 + d * 0.5), 2.0, 1.4, 0.7)
	footprints(Vector3(6.0, y, z0 + 3.0), Vector3(6.0, y, z1 - 4.0), 18)
	# supervisor alcove with two consoles and a desk
	props.console(Vector3(x0 + 3.0, y, z1 - 2.2), PI, 2.4, "screen_eng")
	props.console(Vector3(x0 + 5.6, y, z1 - 2.2), PI, 2.4, "screen_power")
	props.chair(Vector3(x0 + 3.0, y, z1 - 3.6), PI)
	props.chair(Vector3(x0 + 5.6, y, z1 - 3.6), PI)
	desk(Vector3(x0 + 4.3, y, z1 - 6.0), PI, 1.8)
	noticeboard(Vector3(x0 + 4.3, y + 1.8, z1 - 0.05), PI, 1.6, 1.0)
	# dosimeter + suit rack
	dosimeter(Vector3(x1 - 4.0, y, z0 + 4.0), -PI * 0.5)
	eva_suit(Vector3(x1 - 2.0, y, z0 + 6.0), -PI * 0.5)
	eva_suit(Vector3(x1 - 2.0, y, z0 + 8.2), -PI * 0.5)
	ppe_cabinet(Vector3(x1 - 0.6, y, z0 + 10.5), -PI * 0.5)
	coolant_drums(Vector3(x0 + 2.0, y, z0 + 5.0))
	# floor caution ring around the core
	ring_marking(Vector3(0, y, -39.0), 9.4, "hazard_worn")
	# tool crib
	workbench(Vector3(x1 - 3.4, y, z1 - 3.0), -PI * 0.5, 2.0)
	fire_extinguisher(Vector3(x0 + 0.4, y + 1.2, z0 + 2.0), PI * 0.5)
	label("REACTOR HALL  ·  AUTHORISED PERSONNEL", Vector3(0, y + 2.9, z0 + 0.4), 0, 0.34,
		Color(1.0, 0.6, 0.2))
	light(Vector3(x0 + 4.3, y + 3.0, z1 - 4.0), Color(0.55, 0.8, 1.0), 2.0, 7.0, false)


func dosimeter(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(75.0)
	kit.box("metal_dark", Vector3(0.5, 0.7, 0.2), Vector3(0, 1.3, 0))
	kit.box("screen_med", Vector3(0.36, 0.3, 0.02), Vector3(0, 1.42, 0.12))
	for i in 3:
		kit.box("emit_amber" if i == 0 else "emit_green", Vector3(0.06, 0.04, 0.02),
			Vector3(-0.12 + i * 0.12, 1.15, 0.12))
	kit.box("paper", Vector3(0.3, 0.2, 0.005), Vector3(0, 0.95, 0.11))
	kit.pop_xf()


func coolant_drums(p: Vector3) -> void:
	for i in 3:
		part(75.0)
		kit.cyl("pipe_teal" if i % 2 == 0 else "hazard", 0.27, 0.27, 0.9, 14,
			p + Vector3(i * 0.62, 0.0, 0))
		kit.torus("metal_dark", 0.29, 0.025, 14, 4, p + Vector3(i * 0.62, 0.22, 0))
		kit.torus("metal_dark", 0.29, 0.025, 14, 4, p + Vector3(i * 0.62, 0.7, 0))
		kit.box("paper", Vector3(0.18, 0.12, 0.005), p + Vector3(i * 0.62, 0.5, 0.275))


func ring_marking(center: Vector3, radius: float, key: String) -> void:
	part(90.0)
	var n := 40
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p0 := center + Vector3(cos(a0) * radius, 0.01, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, 0.01, sin(a1) * radius)
		var mid := (p0 + p1) * 0.5
		var right := (p1 - p0).normalized()
		var tang := Vector3(-right.z, 0, right.x)
		kit.quad(key, [p0 - tang * 0.08, p1 - tang * 0.08, p1 + tang * 0.08, p0 + tang * 0.08],
			Vector3.UP)


# ================================================================= hydro ====
func hydro_extras(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("hydro", 0.5, variant_i)
	var w := x1 - x0
	var d := z1 - z0
	stain(2, Vector3(0, y, z0 + 6.0), 2.4, 1.6, 0.0)
	footprints(Vector3(0, y, z1 - 3.0), Vector3(0, y, z0 + 3.0), 18)
	# irrigation manifold + drip trays + harvest crates + tools
	irrigation_manifold(Vector3(x0 + 0.9, y, z0 + 4.0), PI * 0.5)
	irrigation_manifold(Vector3(x1 - 0.9, y, z0 + 4.0), PI * 0.5)
	for i in 3:
		crate(Vector3(x0 + 2.6, y, z1 - 4.0 - i * 1.4), 0.7, 0.5, 0.6, "container_c")
		crate(Vector3(x1 - 2.6, y, z0 + 5.0 + i * 1.4), 0.7, 0.45, 0.6, "container_d")
	tool_cart(Vector3(x1 - 2.2, y, z1 - 6.0), -PI * 0.5)
	kitchen_sink(Vector3(x0 + 2.0, y, z0 + 2.0), PI * 0.5)
	# trellis vines on the walls
	for side in [-1.0, 1.0]:
		var xx: float = x1 - 0.4 if side > 0 else x0 + 0.4
		for i in 4:
			var zz := z0 + 4.0 + i * 5.0
			vine_trellis(Vector3(xx, y + 0.4, zz), side, 2.6)
	# hanging planters + sticky traps + seed cabinet
	for i in 4:
		hanging_planter(Vector3(-3.0 + i * 2.0, y + 5.8, z0 + 8.0))
	seed_cabinet(Vector3(x0 + 0.6, y, z1 - 3.0), PI * 0.5)
	label("BIO DOME 3  ·  NUTRIENT LOOP", Vector3(x0 + 0.3, y + 4.6, z0 + 2.0), PI * 0.5, 0.34,
		Color(0.45, 1.0, 0.55))
	light(Vector3(0, y + 4.0, z0 + d * 0.5), Color(0.55, 0.85, 0.45), 2.0, 9.0, false)


func irrigation_manifold(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(92.0)
	kit.cyl("pipe_teal", 0.14, 0.14, 2.2, 10, Vector3(0, 1.1, 0))
	for i in 4:
		kit.tube("pipe_teal", [Vector3(0, 0.4 + i * 0.5, 0), Vector3(0.5, 0.4 + i * 0.5, 0),
			Vector3(0.5, 0.4 + i * 0.5, 0.6)], 0.045, 5)
		kit.torus("metal", 0.05, 0.012, 10, 4, Vector3(0.5, 0.4 + i * 0.5, 0.55))
	kit.box("metal_dark", Vector3(0.4, 0.5, 0.3), Vector3(0, 1.7, 0.2))
	kit.box("screen_log", Vector3(0.3, 0.24, 0.02), Vector3(0, 1.72, 0.36))
	kit.pop_xf()


func vine_trellis(p: Vector3, side: float, h: float) -> void:
	part(92.0)
	var xx := p.x
	for i in 4:
		kit.tube("metal", [Vector3(xx, p.y, p.z + i * 0.35), Vector3(xx, p.y + h, p.z + i * 0.35)], 0.015, 4)
	for i in 5:
		kit.tube("metal", [Vector3(xx, p.y + i * (h / 4.0), p.z), Vector3(xx, p.y + i * (h / 4.0), p.z + 1.05)], 0.013, 4)
	for i in 10:
		var zz := p.z + rng.randf_range(0.0, 1.0)
		var yy := p.y + rng.randf_range(0.1, h - 0.1)
		kit.begin_part(rng.randf(), 33.0)
		kit.quad("plant", [Vector3(xx - side * 0.02, yy, zz), Vector3(xx - side * 0.18, yy + 0.1, zz + 0.08),
			Vector3(xx - side * 0.30, yy + 0.02, zz + 0.16), Vector3(xx - side * 0.12, yy - 0.06, zz + 0.10)],
			Vector3(side, 0, 0))


func hanging_planter(p: Vector3) -> void:
	part(89.0)
	kit.cyl("metal_dark", 0.18, 0.24, 0.22, 10, p)
	kit.tube("metal", [p + Vector3(0, 0.2, 0), p + Vector3(0, 0.9, 0)], 0.01, 4)
	for i in 5:
		var a := rng.randf_range(0, TAU)
		var base := p + Vector3(0, 0.1, 0)
		var tip := base + Vector3(cos(a) * 0.2, -0.4, sin(a) * 0.2)
		kit.quad("plant_b", [base + Vector3(-0.03, 0, 0), base + Vector3(0.03, 0, 0),
			tip + Vector3(0.02, 0, 0), tip + Vector3(-0.02, 0, 0)], Vector3.UP)


func seed_cabinet(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(83.0)
	kit.box("metal_painted", Vector3(1.0, 1.9, 0.45), Vector3(0, 0.95, 0))
	for i in 4:
		for k in 4:
			kit.cyl("glass_bottle" if (i + k) % 2 == 0 else "food_b", 0.05, 0.04, 0.12, 8,
				Vector3(-0.3 + k * 0.2, 0.35 + i * 0.38, 0.24))
		kit.box("metal_dark", Vector3(0.9, 0.03, 0.3), Vector3(0, 0.28 + i * 0.38, 0.1))
	kit.box("paper", Vector3(0.3, 0.2, 0.005), Vector3(0, 1.55, 0.235))
	kit.pop_xf()


func kitchen_sink(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(87.0)
	kit.box("metal_light", Vector3(1.1, 0.9, 0.6), Vector3(0, 0.45, 0))
	kit.box("metal_dark", Vector3(0.8, 0.04, 0.4), Vector3(0, 0.91, 0.02))
	kit.cyl("metal", 0.025, 0.02, 0.3, 8, Vector3(0, 1.05, -0.12))
	kit.tube("metal", [Vector3(0, 1.2, -0.12), Vector3(0, 1.24, 0.1)], 0.02, 5)
	kit.pop_xf()


# ================================================================= bridge ===
func bridge_extras(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("bridge", 0.4, variant_i)
	var w := x1 - x0
	var d := z1 - z0
	stain(2, Vector3(x0 + 2.0, y, z1 - 3.0), 1.2, 0.9, 0.2)
	footprints(Vector3(0, y, z1 - 2.0), Vector3(0, y, z0 + 6.0), 10)
	# personal items at the forward stations
	for i in 2:
		var zz := z0 + 7.0 + i * 3.0
		mug(Vector3(x0 + 1.6 + i * 0.4, y + 0.78, zz), rng.randf() * TAU)
		tablet(Vector3(x1 - 1.8, y + 0.78, zz + 0.4), -0.4)
	# damage-control locker + coffee station + fire gear
	damage_locker(Vector3(x0 + 1.0, y, z1 - 2.0), PI * 0.5)
	coffee_zone(Vector3(x1 - 2.2, y, z1 - 1.2), -PI * 0.5)
	fire_extinguisher(Vector3(x1 - 0.4, y + 1.2, z0 + 4.0), -PI * 0.5)
	first_aid(Vector3(x0 + 0.4, y + 1.7, z0 + 4.0), PI * 0.5)
	chart_table(Vector3(x1 - 2.4, y, z0 + 13.0))
	label("COMMAND DECK  ·  SECTION 01", Vector3(x0 + 0.2, y + 3.4, z1 - 4.0), PI * 0.5, 0.3,
		Color(0.45, 0.85, 1.0))
	light(Vector3(x0 + 1.0, y + 3.2, z0 + 4.0), Color(0.55, 0.78, 1.0), 1.4, 6.0, false)


func damage_locker(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(83.0)
	kit.box_bevel("hazard", Vector3(1.4, 2.0, 0.55), Vector3(0, 1.0, 0), 0.03)
	kit.box("metal_dark", Vector3(1.3, 0.06, 0.58), Vector3(0, 1.55, 0))
	for i in 2:
		kit.box("metal_dark", Vector3(0.6, 0.05, 0.02), Vector3(-0.33 + i * 0.66, 1.2, 0.29))
		kit.box("emit_green", Vector3(0.12, 0.03, 0.01), Vector3(-0.33 + i * 0.66, 0.9, 0.3))
	kit.pop_xf()


func chart_table(p: Vector3) -> void:
	part(85.0)
	kit.box_bevel("metal_painted", Vector3(1.6, 0.07, 1.0), p + Vector3(0, 0.78, 0))
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.08, 0.76, 0.08), p + Vector3(sx * 0.7, 0.38, 0.4))
		kit.box("metal_dark", Vector3(0.08, 0.76, 0.08), p + Vector3(sx * 0.7, 0.38, -0.4))
	kit.box("screen_nav", Vector3(1.2, 0.03, 0.7), p + Vector3(0, 0.79, 0))
	papers(p + Vector3(-0.4, 0.83, 0.2), 0.3, 3)
	mug(p + Vector3(0.5, 0.82, 0.25), 0.4)
	tools_scatter(p + Vector3(0.1, 0.83, -0.25), 0.7)


# ================================================================== shop ====
func shop_extra(idx: int, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	setup("shop_%d" % idx, 0.6, idx)
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var inward := -1.0 if x0 > 0.0 else 1.0
	var face := x0 if x0 > 0.0 else x1
	match idx % 5:
		0:  # café
			coffee_zone(Vector3(cx + inward * 0.6, y, z0 + 1.6), PI * 0.5 * inward)
			for i in 2:
				props.table(Vector3(cx + inward * 0.8, y, z0 + 3.6 + i * 2.2), 0.8, 0.8, 0.72)
				props.chair(Vector3(cx + inward * 1.6, y, z0 + 3.6 + i * 2.2), -PI * 0.5 * inward)
				mug(Vector3(cx + inward * 0.8, y + 0.75, z0 + 3.6 + i * 2.2), rng.randf() * TAU)
		1:  # supply store
			parts_rack(Vector3(cx, y, cz), PI * 0.5, 2.4)
			for i in 3:
				crate(Vector3(cx + inward * 1.4, y, z0 + 2.0 + i * 1.6), 0.7, 0.6, 0.7, "container_c")
		2:  # bio-synth
			for i in 4:
				kit.begin_part(0.4, 62.0)
				kit.cyl("glass_bottle", 0.14, 0.11, 0.35, 12, Vector3(cx + inward * 1.0, y + 0.95, z0 + 2.0 + i * 1.1))
				kit.cyl("emit_green", 0.04, 0.04, 0.28, 8, Vector3(cx + inward * 1.0, y + 1.0, z0 + 2.0 + i * 1.1))
			plant_small(Vector3(cx + inward * 1.8, y, z1 - 1.0), 1.2)
			label("BIO-SYNTH", Vector3(face, y + 2.6, cz), PI * 0.5 * inward, 0.4, Color(0.45, 1.0, 0.55))
		3:  # salvage
			for i in 4:
				props.barrel(Vector3(cx + inward * 1.2, y, z0 + 2.0 + i * 1.1), "pipe_teal" if i % 2 else "pipe_orange")
			tool_cart(Vector3(cx + inward * 1.6, y, z0 + 6.4), PI * 0.5)
			stock_rack(Vector3(cx, y, cz))
		4:  # nav aids
			props.console(Vector3(cx, y, cz), PI * 0.5 * inward, 1.6, "screen_nav")
			props.console(Vector3(cx + inward * 1.4, y, cz), PI * 0.5 * inward, 1.4, "screen_log")
			chart_table(Vector3(cx, y, z1 - 1.8))
	# common retail clutter
	bin(Vector3(cx - inward * 1.5, y, z1 - 0.9), 0)
	fire_extinguisher(Vector3(cx + inward * 1.9, y + 1.1, z1 - 0.4), PI * 0.5 * inward)
	stain(0, Vector3(cx, y, z1 - 1.6), 1.2, 0.8, rng.randf() * TAU)


# ============================================================== corridor ====
func corridor_life(x0: float, x1: float, z0: float, z1: float, y: float, h: float, variant_i: int) -> void:
	setup("corridor_%d" % variant_i, 0.85, variant_i)
	var side := -1.0 if variant_i % 2 == 0 else 1.0
	var wall_x := x0 + 0.22 if side < 0 else x1 - 0.22
	# life traces on the floor
	footprints(Vector3(0, y, z0 + 2.0), Vector3(0, y, z1 - 2.0), 14)
	tape_line(Vector3(x0 + 0.5, y, z0 + 1.0), Vector3(x0 + 0.5, y, z1 - 1.0), 0.05)
	# wall clutter: noticeboard / poster / fire gear / cable coil
	noticeboard(Vector3(wall_x, y + 1.7, z0 + (z1 - z0) * 0.35), PI * 0.5 * side, 1.3, 0.8)
	poster(Vector3(x0 + 0.03 if side > 0 else x1 - 0.03, y + 2.0, z0 + (z1 - z0) * 0.65),
		PI * 0.5 * side, 0.42, 0.6, "fabric_rust")
	fire_extinguisher(Vector3(x0 + 0.3 if side > 0 else x1 - 0.3, y + 1.1, z1 - 1.8), PI * 0.5 * side)
	first_aid(Vector3(x1 - 0.3 if side > 0 else x0 + 0.3, y + 1.6, z0 + 1.8), PI * 0.5 * side)
	cable_coil(Vector3(wall_x - side * 0.2, y, z0 + (z1 - z0) * 0.8), 0.32, 3)
	janitor_cart(Vector3(wall_x - side * 0.3, y, z0 + (z1 - z0) * 0.55), PI * 0.5 * side)
	# junction boxes with hanging cables
	junction(Vector3(wall_x, y + 1.4, z0 + 2.6), PI * 0.5 * side, 0.42, 0.7)
	cable_sag(Vector3(wall_x, y + 1.8, z0 + 2.4), Vector3(wall_x, y + 1.2, z0 + 3.4), 0.25)
	label("SECTION " + str(20 + variant_i), Vector3(wall_x, y + 3.4, z0 + (z1 - z0) * 0.5),
		PI * 0.5 * side, 0.26, Color(1.0, 0.65, 0.3))


# ================================================================ hangar ====
func hangar_extras(x0: float, x1: float, z0: float, z1: float, y: float, h: float) -> void:
	setup("hangar", 0.95, 0)
	var w := x1 - x0
	var d := z1 - z0
	stain(1, Vector3(x0 + 4.0, y, z0 + 8.0), 2.4, 1.8, 0.2)
	stain(1, Vector3(x1 - 5.0, y, z0 + 12.0), 1.8, 1.2, 0.9)
	stain(3, Vector3(x1 - 3.0, y, z1 - 4.0), 1.4, 1.0, 0.4)
	for i in 4:
		cable_coil(Vector3(x0 + 2.0 + i * 0.8, y, z0 + 3.0), 0.45, 3)
	tool_cart(Vector3(x0 + 3.0, y, z0 + 6.0), 0.0)
	fuel_drum(Vector3(x1 - 2.0, y, z0 + 3.0))
	fuel_drum(Vector3(x1 - 2.0, y, z0 + 4.0))
	tie_down_points(x0 + 2.0, x1 - 2.0, z0 + 5.0, z1 - 5.0, y)
	maintenance_board(Vector3(x0 + 0.3, y + 1.6, z0 + 8.0), PI * 0.5)
	label("HANGAR  ·  BAY 2", Vector3(0, y + 2.0, z1 - 0.4), PI, 0.34, Color(1.0, 0.6, 0.25))


func fuel_drum(p: Vector3) -> void:
	part(75.0)
	kit.cyl("hazard", 0.32, 0.32, 0.95, 14, p)
	kit.torus("metal_dark", 0.34, 0.03, 14, 4, p + Vector3(0, 0.25, 0))
	kit.torus("metal_dark", 0.34, 0.03, 14, 4, p + Vector3(0, 0.7, 0))
	kit.box("paper", Vector3(0.2, 0.14, 0.005), p + Vector3(0, 0.5, 0.33))


func tie_down_points(x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	for i in 4:
		for k in 4:
			var px := lerpf(x0, x1, float(i) / 3.0)
			var pz := lerpf(z0, z1, float(k) / 3.0)
			part(76.0)
			kit.cyl("metal_dark", 0.10, 0.08, 0.06, 8, Vector3(px, y + 0.03, pz))
			kit.torus("metal", 0.09, 0.015, 10, 4, Vector3(px, y + 0.08, pz))


func maintenance_board(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(74.0)
	kit.box("metal_dark", Vector3(1.6, 1.0, 0.05), Vector3.ZERO)
	kit.box("paper_b", Vector3(1.4, 0.8, 0.02), Vector3(0, 0, 0.03))
	for i in 6:
		kit.box("paper", Vector3(0.18, 0.12, 0.005), Vector3(-0.55 + (i % 3) * 0.55, 0.2 - (i / 3) * 0.3, 0.05))
	kit.pop_xf()


# ================================================================== tanks ===
func tanks_extras(x0: float, x1: float, z0: float, z1: float, y: float, h: float) -> void:
	setup("tanks", 1.0, 0)
	stain(1, Vector3(x0 + 6.0, y, z0 + 8.0), 2.0, 1.4, 0.3)
	stain(1, Vector3(x1 - 7.0, y, z0 + 12.0), 1.4, 1.0, 0.8)
	gauge_panel(Vector3(x0 + 0.35, y + 1.6, z0 + 6.0), PI * 0.5)
	gauge_panel(Vector3(x1 - 0.35, y + 1.6, z0 + 14.0), -PI * 0.5)
	valve_station(Vector3(x0 + 2.0, y, z0 + 4.0), PI * 0.5)
	ppe_cabinet(Vector3(x1 - 0.6, y, z1 - 3.0), -PI * 0.5)
	for i in 2:
		cable_coil(Vector3(x0 + 3.0 + i * 1.2, y, z1 - 4.0), 0.35, 3)
	noticeboard(Vector3(x0 + 0.3, y + 1.7, z1 - 2.0), PI * 0.5, 1.2, 0.8)
	label("WATER / LOX PROCESSING", Vector3(0, y + 5.4, z1 - 0.4), PI, 0.38, Color(0.45, 0.85, 1.0))


func valve_station(p: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), p))
	part(92.0)
	kit.box("metal_dark", Vector3(0.5, 1.4, 0.3), Vector3(0, 0.7, 0))
	kit.cyl("pipe_teal", 0.08, 0.08, 1.3, 10, Vector3(0, 0.7, 0.16))
	for i in 3:
		props.valve(Vector3(0, 0.3 + i * 0.4, 0.22), Vector3(0.6, 0.2, 0.75), 0.12)
	kit.pop_xf()

# ======================================================== generic filling ===
## Perimeter clutter pass: every room gets storage, equipment and life along
## its long walls, selected by function style, so no volume reads as empty.
func fill_perimeter(x0: float, x1: float, z0: float, z1: float, y: float, h: float,
		style: String = "hab", skip_near: float = 2.0) -> void:
	var w := x1 - x0
	var d := z1 - z0
	# choose slots along both long walls, alternating to leave the centre open
	var slot := 0
	var zz := z0 + 2.4
	while zz < z1 - 2.0:
		var side := 1.0 if slot % 2 == 0 else -1.0
		var xx := x1 - 0.7 if side > 0 else x0 + 0.7
		# keep clear of the door band at the forward and aft walls
		var near_door := (zz < z0 + skip_near) or (zz > z1 - skip_near)
		if not near_door:
			_place_cluster(Vector3(xx, y, zz), -side * PI * 0.5, style, slot)
		slot += 1
		zz += 3.15
	# a few central clusters in large rooms
	if w * d > 150.0:
		_place_center(Vector3((x0 + x1) * 0.5, y, z0 + d * 0.30), style, 0)
		_place_center(Vector3((x0 + x1) * 0.5, y, z1 - d * 0.25), style, 1)
	# fill light: two soft pools at the quarter points
	light(Vector3(x0 + w * 0.5, y + minf(h - 0.6, 3.4), z0 + d * 0.22),
		Color(1.0, 0.84, 0.62), 2.4, 9.0, false)
	light(Vector3(x0 + w * 0.5, y + minf(h - 0.6, 3.4), z1 - d * 0.22),
		Color(1.0, 0.86, 0.68), 2.4, 9.0, false)


func _place_cluster(p: Vector3, yaw: float, style: String, slot: int) -> void:
	var pick := rng.randi() % 8
	if style == "hab":
		match pick:
			0:
				props.locker(p, yaw, 0.55, 1.8)
			1:
				storage_cabinet(p, yaw, 0.9, 1.7)
			2:
				props.shelf(p, yaw, 1.8, 2.0)
			3:
				crate(p, 0.8, 0.7, 0.8, "container_c" if slot % 2 == 0 else "metal_painted")
			4:
				plant_small(p, 1.1)
			5:
				poster(p + Vector3(0, 1.7, 0), yaw, 0.5, 0.75, "fabric_teal")
			6:
				desk(p, yaw, 1.2)
			7:
				book_stack(p + Vector3(0, 1.24, 0), yaw, 3)
	elif style == "med":
		match pick:
			0:
				cabinet_med(p + Vector3(0, 1.2, 0), yaw)
			1:
				storage_cabinet(p, yaw, 0.8, 1.7)
			2:
				props.shelf(p, yaw, 1.6, 2.0)
			3:
				bin(p, 1 if slot % 3 == 0 else 0)
			4:
				water_cooler(p)
			5:
				plant_small(p, 0.9)
			6:
				props.chair(p, yaw)
			7:
				pack_stool(p)
	elif style == "machine":
		match pick:
			0:
				parts_rack(p, yaw, 1.8)
			1:
				stock_rack(p, yaw)
			2:
				storage_cabinet(p, yaw, 1.0, 1.9)
			3:
				bin(p, 0)
			4:
				props.barrel(p, "pipe_teal" if slot % 2 else "pipe_orange")
			5:
				cable_coil(p, 0.42, 3)
			6:
				crate(p, 0.9, 0.8, 0.8, "container_b")
			7:
				tool_cart(p, yaw)
	else:
		match pick:
			0:
				storage_cabinet(p, yaw, 1.0, 1.8)
			1:
				props.shelf(p, yaw, 1.8, 2.0)
			2:
				bin(p, 0)
			3:
				plant_small(p, 1.0)
			4:
				props.locker(p, yaw, 0.55, 1.8)
			5:
				crate(p, 0.8, 0.7, 0.8, "metal_painted")
			6:
				fire_extinguisher(p + Vector3(0, 1.2, 0), yaw)
			7:
				poster(p + Vector3(0, 1.8, 0), yaw, 0.45, 0.7, "fabric_rust")


func _place_center(p: Vector3, style: String, idx: int) -> void:
	if style == "hab":
		if idx == 0:
			props.table(p, 2.0, 1.0, 0.75)
			rug(p, 0.0, 3.0, 2.2)
			for k in 2:
				props.chair(p + Vector3(0, 0, -0.8 + k * 1.6), 0.0 if k == 0 else PI)
				mug(p + Vector3(0, 0.78, -0.7 + k * 1.4), rng.randf() * TAU)
		else:
			sofa(p, rng.randf() * TAU, 2.2)
	else:
		if idx == 0:
			props.table(p, 1.8, 1.0, 0.75)
			paper_pile(p + Vector3(0, 0.78, 0), 0.2)
		else:
			crate(p, 1.0, 0.8, 0.9, "container_d")
			crate(p + Vector3(1.1, 0, 0), 0.8, 0.6, 0.7, "metal_painted")


func paper_pile(p: Vector3, yaw: float) -> void:
	papers(p, yaw, 5)
	mug(p + Vector3(0.3, 0, 0.2), rng.randf() * TAU)

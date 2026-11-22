extends RefCounted

const GeoKit = preload("res://src/kit.gd")
const ShipLayout = preload("res://src/layout.gd")
const StructGen = preload("res://src/struct.gd")
const PropGen = preload("res://src/props.gd")

## Builds every interior zone: engineered aft section, cargo, atrium,
## habitat ring, command deck and bridge. Side rooms live off corridors with
## a service gap between neighbours; room dims are the table entries below so
## level designers can resize freely without touching wall logic.

var k: GeoKit
var st: StructGen
var pr: PropGen
var L: ShipLayout
var lights: Node3D

# ---- room tables (x0,z0,x1,z1, name, door side) — low-detail branch rooms ---
var habitat_rooms := [
	{"r": Rect2(-14, 4, 9, 3), "n": "Q-A1", "d": "xp"},
	{"r": Rect2(-14, -1, 9, 3), "n": "Q-A2", "d": "xp"},
	{"r": Rect2(-14, -6, 9, 3), "n": "Q-A3", "d": "xp"},
	{"r": Rect2(-14, -11, 9, 4), "n": "MESS", "d": "xp"},
	{"r": Rect2(-14, -16, 9, 4), "n": "GYM", "d": "xp"},
	{"r": Rect2(-14, -22, 9, 3), "n": "MED", "d": "xp"},
	{"r": Rect2(-14, -27, 9, 4), "n": "LAB", "d": "xp"},
	{"r": Rect2(-14, -33, 9, 3), "n": "Q-A7", "d": "xp"},
	{"r": Rect2(5, 4, 9, 3), "n": "Q-B1", "d": "xn"},
	{"r": Rect2(5, -1, 9, 3), "n": "Q-B2", "d": "xn"},
	{"r": Rect2(5, -6, 9, 3), "n": "Q-B3", "d": "xn"},
	{"r": Rect2(5, -11, 9, 5), "n": "GALLEY", "d": "xn"},
	{"r": Rect2(5, -18, 9, 3), "n": "LIBRARY", "d": "xn"},
	{"r": Rect2(5, -23, 9, 4), "n": "OBS-ST", "d": "xn"},
	{"r": Rect2(5, -29, 9, 4), "n": "Q-B7", "d": "xn"},
]
var machine_rooms := [
	{"r": Rect2(-14, 70, 9, 4), "n": "WKSP", "d": "xp"},
	{"r": Rect2(-14, 76, 9, 4), "n": "SUBSTA", "d": "xp"},
	{"r": Rect2(-14, 82, 9, 4), "n": "STOR-A", "d": "xp"},
	{"r": Rect2(5, 70, 9, 5), "n": "LIFESUP", "d": "xn"},
	{"r": Rect2(5, 77, 9, 4), "n": "STOR-B", "d": "xn"},
	{"r": Rect2(5, 83, 9, 3), "n": "DRONE", "d": "xn"},
]
var command_rooms := [
	{"r": Rect2(-11, -80, 6, 6), "n": "BRIEF", "d": "xp"},
	{"r": Rect2(-11, -88, 6, 5), "n": "CIC", "d": "xp"},
	{"r": Rect2(-11, -96, 6, 5), "n": "NAV", "d": "xp"},
	{"r": Rect2(5, -80, 6, 5), "n": "SEC", "d": "xn"},
	{"r": Rect2(5, -88, 6, 6), "n": "READY", "d": "xn"},
	{"r": Rect2(5, -96, 6, 5), "n": "COMMS", "d": "xn"},
]


func _init(kit: GeoKit, struct: StructGen, props: PropGen,
		lay: ShipLayout, lights_node: Node3D) -> void:
	k = kit
	st = struct
	pr = props
	L = lay
	lights = lights_node


func add_light(p: Vector3, col: Color, energy := 600.0, rng := 14.0,
		shadow := false) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.omni_attenuation = 1.4
	lights.add_child(l)


func add_spot(p: Vector3, look: Vector3, col: Color, energy := 900.0,
		rng := 18.0, ang := 55.0, shadow := false) -> void:
	var s := SpotLight3D.new()
	s.position = p
	s.look_at_from_position(p, look, Vector3.UP)
	s.light_color = col
	s.light_energy = energy
	s.spot_range = rng
	s.spot_angle = ang
	s.shadow_enabled = shadow
	lights.add_child(s)


# =============================================================== ENGINE =====
func zone_engine() -> void:
	var z := Rect2(-20, 116, 40, 32)
	var y0 := -13.0
	var y1 := -1.0
	st.slab("floor_a", z.position.x, z.end.x, z.position.y, z.end.y, y0, 0.4,
		[Rect2(-1.5, 124, 3, 14)])                    # sunken drive trench
	st.slab("ceil", z.position.x, z.end.x, z.position.y, z.end.y, y1, 0.4)
	# trench interior: walls + bottom
	st.wall_z("metal_a", -1.5, 124, 138, y0 - 2.4, y0, 0.15)
	st.wall_z("metal_a", 1.5, 124, 138, y0 - 2.4, y0, 0.15)
	st.slab("metal_a", -1.5, 1.5, 124, 138, y0 - 2.4, 0.2)
	st.wall_x("metal_a", 124, -1.5, 1.5, y0 - 2.4, y0, 0.15)
	st.wall_x("metal_a", 138, -1.5, 1.5, y0 - 2.4, y0, 0.15)
	# trench pipes
	pr.pipe([Vector3(-1.0, y0 - 1.6, 138), Vector3(-1.0, y0 - 1.6, 124)],
		0.16, "copper", -100)
	pr.pipe([Vector3(0.0, y0 - 1.9, 138), Vector3(0.0, y0 - 1.9, 124)],
		0.2, "metal_b", -100)
	pr.pipe([Vector3(1.0, y0 - 1.4, 138), Vector3(1.0, y0 - 1.4, 124)],
		0.12, "metal_c", -100)
	# grate bridges over trench
	for gz in [126.0, 132.0, 137.0]:
		k.part(0.4, 0.0, 1.0)
		k.box("floor_a", Vector3(4.6, 0.08, 1.6), Vector3(0, y0 + 0.04, gz))
		st.rail("metal_d", Vector3(-2.3, y0, gz - 0.75), Vector3(2.3, y0, gz - 0.75))
		st.rail("metal_d", Vector3(-2.3, y0, gz + 0.75), Vector3(2.3, y0, gz + 0.75))
	# hazard edge around trench
	for sx in [-1, 1]:
		k.box("hazard", Vector3(0.4, 0.03, 14.0),
			Vector3(sx * 1.75, y0 + 0.02, 131))

	# walls: stern (gate to void = big door), fwd gate to reactor, sides w/ rooms
	st.wall_x("metal_a", 148, -20, 20, y0, y1, 0.5,
		[[0, 6, 0, 9, "gate"]])
	st.wall_x("metal_a", 116, -20, 20, y0, y1, 0.5,
		[[0, 4.5, 0, 8.5, "gate"]])
	st.wall_z("metal_a", -20, 116, 148, y0, y1, 0.5,
		[[136, 2.4, 0.0, 2.6, "door"], [126, 2.4, 0.0, 2.6, "door"]])
	st.wall_z("metal_a", 20, 116, 148, y0, y1, 0.5,
		[[130, 2.4, 0.0, 2.6, "door"], [121, 2.4, 0.0, 2.6, "door"]])

	# thrust frame: massive pylon pair + crosshead + keel beam
	for sx in [-7.5, 7.5]:
		k.part(0.2, 0.0, 1.2)
		k.boxb("metal_a", Vector3(2.4, y1 - y0 - 1.0, 3.2),
			Vector3(sx, (y0 + y1) * 0.5, 131), 0.08)
		k.boxb("metal_d", Vector3(1.0, y1 - y0 - 2.0, 1.2),
			Vector3(sx * 0.82, (y0 + y1) * 0.5 - 0.5, 131), 0.05)
	k.boxb("metal_a", Vector3(17.6, 2.4, 3.0), Vector3(0, y1 - 1.8, 131), 0.1)
	k.boxb("dark", Vector3(17.0, 0.5, 2.6), Vector3(0, y1 - 3.2, 131), 0.05)
	# keel beam running aft into stern wall
	k.boxb("metal_a", Vector3(2.2, 2.2, 26.0), Vector3(0, -4.4, 136), 0.08)
	for i in 5:
		var zz := 146 - i * 4.4
		k.boxb("metal_d", Vector3(3.4, 0.4, 1.0), Vector3(0, -5.6, zz), 0.05)
	# plasma conduits from thrust frame to stern
	for sx in [-2.5, 0, 2.5]:
		k.push(Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(sx, -6.5, 148)))
		k.cyl("plasma_o", 0.32, 0.32, 9.0, 10, Vector3.ZERO, false)
		k.pop()
		for zz in [141.0, 145.5]:
			k.torus("metal_a", 0.42, 0.10, 10, 8, Vector3(sx, -6.5, zz))

	# overhead crane rails
	for sx in [-4.5, 4.5]:
		pr.ibeam(Vector3(sx, y1 - 0.6, 118), Vector3(sx, y1 - 0.6, 146), 0.4)
	pr.ibeam(Vector3(-4.5, y1 - 1.2, 134), Vector3(4.5, y1 - 1.2, 134), 0.5)
	k.box("u_light_o", Vector3(0.12, 0.12, 0.12), Vector3(0, y1 - 1.8, 134))

	# dressing: racks, boards, stowage along walls
	for i in 6:
		pr.rack(-19.4, y0, 120 + i * 4.2, 0.8, 2.2, 0.5)
	for i in 5:
		pr.rack(19.4, y0, 118 + i * 5.0, 0.8, 2.2, 0.5)
	pr.tool_board(-19.6, y0, 142, 1.6, 1.4)
	pr.tool_board(19.6, y0, 137, 1.6, 1.4)
	for i in 4:
		pr.stow(Vector3(-17.5 + i * 1.1, y0, 145.5), 0.8, i * 0.4)
	pr.vessel(Vector3(16.5, y0, 121), 1.1, 3.6, "metal_c")
	pr.vessel(Vector3(14.0, y0, 121), 1.1, 3.6, "metal_c")
	# wall pipe mains
	pr.pipe([Vector3(-19.5, y0 + 0.4, 148), Vector3(-19.5, y0 + 0.4, 120),
		Vector3(-14.0, y0 + 0.4, 118)], 0.18, "copper", -100)
	pr.pipe([Vector3(19.5, y0 + 0.6, 146), Vector3(19.5, y0 + 0.6, 117)],
		0.14, "metal_c", -100)
	# cable droops along walls
	for i in 4:
		pr.cable_sag(Vector3(-19.6, y1 - 1.2, 120 + i * 7),
			Vector3(-19.6, y1 - 1.2, 124 + i * 7), 0.5, 3)
	# ceiling light field
	for zz in range(120, 148, 7):
		for xx in [-10, 0, 10]:
			pr.lightbar(Vector3(xx, y1 - 0.35, zz), 2.2, true, "u_light_o")
	add_light(Vector3(0, -3.0, 132), Color(1.0, 0.68, 0.35), 152, 26, true)
	add_light(Vector3(-12, -4.5, 140), Color(1.0, 0.72, 0.4), 99, 18)
	add_light(Vector3(12, -4.5, 122), Color(1.0, 0.72, 0.4), 99, 18)
	add_light(Vector3(0, -11.5, 131), Color(1.0, 0.5, 0.2), 71, 12)


# ============================================================== REACTOR =====
func zone_reactor() -> void:
	var y0 := -13.0
	var y1 := -1.0
	st.slab("floor_a", -16, 16, 100, 116, y0, 0.4, [Rect2(-3.4, 104.6, 6.8, 6.8)])
	st.slab("ceil", -16, 16, 100, 116, y1, 0.4, [Rect2(-3.4, 104.6, 6.8, 6.8)])
	# torus shaft continues above ceiling — ring walls
	var sh := Rect2(-3.4, 104.6, 6.8, 6.8)
	st.wall_x("metal_a", sh.position.y, sh.position.x, sh.end.x, y0, y1 + 3.5, 0.18,
		[[0, 3.4, 0, 7.2, "open"]])
	st.wall_x("metal_a", sh.end.y, sh.position.x, sh.end.x, y0, y1 + 3.5, 0.18,
		[[0, 3.4, 0, 7.2, "open"]])
	st.wall_z("metal_a", sh.position.x, sh.position.y, sh.end.y, y0, y1 + 3.5, 0.18)
	st.wall_z("metal_a", sh.end.x, sh.position.y, sh.end.y, y0, y1 + 3.5, 0.18)
	# side walls + boundaries
	st.wall_x("metal_a", 116, -16, -3.4, y0, y1, 0.5)
	st.wall_x("metal_a", 116, 3.4, 16, y0, y1, 0.5)
	st.wall_x("metal_a", 100, -16, -3.4, y0, y1, 0.5)
	st.wall_x("metal_a", 100, 3.4, 16, y0, y1, 0.5)
	st.wall_x("metal_a", 100, -3.4, 3.4, y0, y1, 0.5, [[0, 3.0, 0, 7.0, "open"]])
	st.wall_x("metal_a", 116, -3.4, 3.4, y0, y1, 0.5, [[0, 3.0, 0, 7.0, "open"]])
	st.wall_z("metal_a", -16, 100, 116, y0, y1, 0.5,
		[[108, 2.4, 0.0, 2.6, "door"], [112, 2.4, 0.0, 2.6, "door"]])
	st.wall_z("metal_a", 16, 100, 116, y0, y1, 0.5,
		[[104, 2.4, 0.0, 2.6, "door"], [112, 2.4, 0.0, 2.6, "door"]])

	# the torus itself: horizontal ring straddling the route, centre z=108
	# (r, axial) profile pairs; axial is torus thickness direction after xf
	var prof := []
	var prof2 := []
	var prof3 := []
	for i in 17:
		var a := TAU * i / 16.0
		prof.append(Vector2(3.4 + cos(a) * 1.35, sin(a) * 1.35))
		prof2.append(Vector2(3.4 + cos(a) * 1.02, sin(a) * 1.02))
		prof3.append(Vector2(3.4 + cos(a) * 0.72, sin(a) * 0.72))
	k.push(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, 108)))
	k.part(0.15, 0.0, 1.0)
	k.lathe("metal_a", prof, 30)
	k.pop()

	# support pylons under torus
	for sx in [-3.4, 3.4]:
		k.boxb("metal_a", Vector3(1.1, 3.6, 1.6), Vector3(sx, y0 + 1.8, 108), 0.06)
		k.boxb("metal_d", Vector3(0.5, 1.0, 0.9), Vector3(sx, y0 + 3.9, 108), 0.04)
	# overhead busbars feeding the torus
	for sx in [-2.2, 2.2]:
		pr.pipe([Vector3(sx, y1 - 0.8, 116), Vector3(sx, y1 - 0.8, 110),
			Vector3(sx * 0.6, -4.6, 108)], 0.14, "copper", y1 - 0.1)
	# ring catwalk around torus at y=-4
	var cw := 1.4
	for sgn in [-1, 1]:
		k.box("floor_a", Vector3(8.6, 0.08, cw),
			Vector3(0, -4.0, 108 + sgn * (3.4 + cw * 0.5)))
		st.rail("metal_d", Vector3(-4.3, -3.96, 108 + sgn * (3.4 + cw)),
			Vector3(4.3, -3.96, 108 + sgn * (3.4 + cw)))
	# hazard ring on floor
	k.torus("hazard", 4.6, 0.25, 24, 4, Vector3(0, y0 + 0.02, 108))
	# control consoles facing the torus
	for sx in [-8, -5.5, 5.5, 8]:
		pr.console(sx, y0, 111.5, -1.0, 1.5, "screen_a")
	pr.console(-8, y0, 104.5, 1.0, 1.5, "screen_a")
	pr.console(8, y0, 104.5, 1.0, 1.5, "screen_c")
	# side gear
	for i in 3:
		pr.vessel(Vector3(-13.5, y0, 103 + i * 4.0), 0.9, 3.2, "metal_c")
		pr.rack(15.4, y0, 103 + i * 3.8)
	pr.pipe([Vector3(-15.6, y0 + 0.5, 100), Vector3(-15.6, y0 + 0.5, 116)],
		0.15, "metal_c", -100)
	pr.pipe([Vector3(15.6, y0 + 0.7, 100), Vector3(15.6, y0 + 0.7, 116)],
		0.11, "copper", -100)
	for zz in [104.0, 108.0, 112.0]:
		pr.lightbar(Vector3(-8, y1 - 0.3, zz), 2.0, true, "u_light_c")
		pr.lightbar(Vector3(8, y1 - 0.3, zz), 2.0, true, "u_light_c")
	pr.lightbar(Vector3(0, y1 - 0.3, 113), 2.0, false, "u_light_c")
	add_light(Vector3(0, -3.5, 108), Color(0.45, 0.75, 1.0), 165, 22, true)
	add_light(Vector3(-10, -4, 108), Color(0.5, 0.7, 1.0), 85, 14)
	add_light(Vector3(10, -4, 108), Color(0.5, 0.7, 1.0), 85, 14)
	add_light(Vector3(0, -10.5, 108), Color(0.4, 0.6, 1.0), 113, 10)


# =========================================================== FUEL GALLERY ===
func zone_fuel() -> void:
	var y0 := ShipLayout.DECK_ENG
	var y1 := -1.5
	st.slab("floor_a", -14, 14, 88, 100, y0, 0.35)
	st.slab("ceil", -14, 14, 88, 100, y1, 0.3)
	st.wall_x("metal_a", 100, -14, 14, y0, y1, 0.4, [[0, 3.0, 0, 5.4, "gate"]])
	st.wall_x("metal_a", 88, -14, 14, y0, y1, 0.4, [[0, 3.0, 0, 5.4, "gate"]])
	st.wall_z("metal_a", -14, 88, 100, y0, y1, 0.4)
	st.wall_z("metal_a", 14, 88, 100, y0, y1, 0.4)
	# sphere tanks in two rows + manifold spine
	for sx in [-8.5, -4.5, 4.5, 8.5]:
		for zz in [91.0, 96.5]:
			var prof := []
			for i in 13:
				var a := PI * i / 12.0
				prof.append(Vector2(sin(a) * 1.5, y0 + 1.7 + (-cos(a)) * 1.5))
			k.part(-1.0, 0.0, 1.0)
			k.lathe("metal_b" if (absf(sx) < 6.0) else "metal_c", prof, 14, Vector3(sx, 0, zz))
			k.cyl("metal_a", 0.12, 0.12, 1.9, 6, Vector3(sx, y0, zz), true)
			k.cyl("u_light_o", 0.05, 0.05, 0.5, 5, Vector3(sx, y0 + 3.2, zz), true)
	# manifold: horizontal header along spine
	pr.pipe([Vector3(0, y0 + 3.4, 89), Vector3(0, y0 + 3.4, 99)], 0.3, "metal_a", y0 + 3.55)
	for zz in [91.0, 96.5]:
		for sx in [-8.5, -4.5, 4.5, 8.5]:
			pr.pipe([Vector3(0, y0 + 3.4, zz), Vector3(sx, y0 + 3.35, zz)], 0.08,
				"metal_a", -100)
	# fuel pipes along walls
	pr.pipe([Vector3(-13.6, y0 + 0.5, 100), Vector3(-13.6, y0 + 0.5, 88)],
		0.2, "metal_b", -100)
	pr.pipe([Vector3(13.6, y0 + 0.8, 100), Vector3(13.6, y0 + 0.8, 88)],
		0.2, "metal_b", -100)
	for zz in [90.0, 94.0, 98.0]:
		pr.lightbar(Vector3(0, y1 - 0.3, zz), 2.0, true, "u_light_o")
	add_light(Vector3(0, y0 + 4, 94), Color(1.0, 0.7, 0.35), 127, 16)
	add_light(Vector3(-8, y0 + 4, 94), Color(1.0, 0.75, 0.4), 71, 12)
	add_light(Vector3(8, y0 + 4, 94), Color(1.0, 0.75, 0.4), 71, 12)


# ========================================================== MACHINE DECK =====
func zone_machine() -> void:
	var y0 := ShipLayout.DECK_ENG
	var y1 := -2.0
	# door openings at each room's corridor-side centre
	var doors_l := []
	var doors_r := []
	for rm in machine_rooms:
		var r0: Rect2 = rm["r"]
		var op0 := [r0.get_center().y, 1.8, 0.0, 3.0, "open"]
		if rm["d"] == "xp":
			doors_l.append(op0)
		else:
			doors_r.append(op0)
	# central spine corridor
	st.corridor("wall_a", "floor_a", "ceil", -3, 3, 66, 88, y0, y1,
		doors_l, doors_r, "z0z1")
	# boundary gates
	st.wall_x("wall_a", 88, -14, -3, y0, y1, 0.3)
	st.wall_x("wall_a", 88, 3, 14, y0, y1, 0.3)
	st.wall_x("wall_a", 66, -14, -3, y0, y1, 0.3)
	st.wall_x("wall_a", 66, 3, 14, y0, y1, 0.3)
	st.slab("wall_a", -14, -3, 66, 88, y0 + 5.2, 0.25)
	st.slab("wall_a", 3, 14, 66, 88, y0 + 5.2, 0.25)
	# branch rooms (low detail): shell + a few racks/crates
	for rm in machine_rooms:
		var r: Rect2 = rm["r"]
		st.room("wall_a", "floor_a", "ceil", r, y0, y0 + 5.2, rm["d"], 2.0)
		var cx := r.get_center().x
		var cz := r.get_center().y
		if rm["n"].begins_with("STOR") or rm["n"].begins_with("WKSP"):
			pr.stow(Vector3(cx - 1, y0, cz), 0.9, 0.3)
			pr.stow(Vector3(cx + 0.4, y0, cz - 0.8), 0.7, 1.2)
			pr.stow(Vector3(cx + 1.2, y0, cz + 0.6), 0.8, -0.5)
		elif rm["n"] == "SUBSTA" or rm["n"] == "LIFESUP":
			pr.rack(cx - 1.2, y0, cz, 0.8, 2.0)
			pr.rack(cx, y0, cz, 0.8, 2.0)
			pr.vessel(Vector3(cx + 1.4, y0, cz + 0.4), 0.7, 2.2, "metal_c")
		else:
			pr.rack(cx - 0.6, y0, cz, 0.7, 1.8)
			pr.stow(Vector3(cx + 0.8, y0, cz + 0.5), 0.7, 0.8)
		pr.lightbar(Vector3(cx, y0 + 4.7, cz), 1.2, true)
		add_light(Vector3(cx, y0 + 3.5, cz), Color(1.0, 0.85, 0.65), 26, 7)
	# corridor dressing: overhead pipe rack + wall panels
	pr.pipe([Vector3(-2.4, y1 - 0.7, 88), Vector3(-2.4, y1 - 0.7, 66)],
		0.12, "copper", y1 - 0.1)
	pr.pipe([Vector3(-2.0, y1 - 0.9, 88), Vector3(-2.0, y1 - 0.9, 66)],
		0.09, "metal_c", -100)
	pr.pipe([Vector3(2.4, y1 - 0.7, 88), Vector3(2.4, y1 - 0.7, 66)],
		0.15, "metal_b", y1 - 0.1)
	st.light_run("u_light", 0, 88, 66, y1 - 0.15, 0.25, 4.0)
	# wall cable trays
	for zz in range(68, 88, 4):
		k.box("dark", Vector3(0.3, 0.08, 3.4), Vector3(-2.82, y0 + 2.6, zz))
	add_light(Vector3(0, y0 + 4.5, 77), Color(1.0, 0.8, 0.55), 99, 18)
	add_light(Vector3(0, y0 + 5.5, 77), Color(1.0, 0.85, 0.6), 51, 14)
	add_light(Vector3(0, y0 + 4.5, 87), Color(1.0, 0.8, 0.55), 71, 14)


# ============================================================ CARGO HOLD =====
func zone_cargo() -> void:
	var y0 := ShipLayout.DECK_ENG
	var y1 := 4.5
	st.slab("floor_b", -15, 15, 34, 66, y0, 0.4)
	st.slab("ceil", -15, 15, 34, 66, y1, 0.4)
	st.wall_x("metal_a", 66, -15, 15, y0, y1, 0.5, [[0, 3.4, 0, 5.6, "gate"]])
	st.wall_x("metal_a", 34, -15, 15, y0, y1, 0.5, [[6, 4.0, 4.4, 4.6, "open"]])
	st.wall_z("metal_a", -15, 34, 66, y0, y1, 0.5)
	st.wall_z("metal_a", 15, 34, 66, y0, y1, 0.5)
	# gantry crane: rails at top + moving bridge + hook
	for sx in [-11, 11]:
		pr.ibeam(Vector3(sx, y1 - 0.7, 36), Vector3(sx, y1 - 0.7, 64), 0.45)
	pr.ibeam(Vector3(-11, y1 - 1.5, 50), Vector3(11, y1 - 1.5, 50), 0.6)
	k.box("metal_b", Vector3(1.2, 1.0, 1.6), Vector3(2.0, y1 - 2.0, 50))
	k.cyl("dark", 0.04, 0.04, 6.0, 6, Vector3(2.0, y1 - 8.0, 50), true)
	k.boxb("metal_b", Vector3(0.5, 0.4, 0.5), Vector3(2.0, y1 - 8.2, 50), 0.04)
	k.box("u_light_o", Vector3(0.1, 0.1, 0.1), Vector3(2.0, y1 - 2.5, 50))
	# container stacks: 2 sizes, aisles between
	var rng2 := k.rng
	for row in range(3):
		var zz := 42.0 + row * 8.0
		for col in range(4):
			var xx := -11.0 + col * 4.4
			if absf(xx - 6.0) < 2.0 and zz < 52.0:
				continue   # keep ramp lane clear
			var hgt := rng2.randi_range(1, 3)
			for lvl in hgt:
				pr.crate(Vector3(xx, y0 + lvl * 1.35, zz + rng2.randf_range(-0.6, 0.6)),
					2.4, rng2.randf_range(-0.06, 0.06))
	# a couple of big 4.8 m containers on the right
	for i in 2:
		pr.crate(Vector3(10.5, y0 + i * 2.7, 58), 4.8, 0.0)
	pr.crate(Vector3(-10.5, y0, 60), 4.8, 0.06)
	# upper catwalk ring at y=-2.8 (below ramp top) along both walls
	for sx in [-13.2, 13.2]:
		pr.catwalk(Vector3(sx, -2.8, 36.5), Vector3(sx, -2.8, 64.5), 1.6)
		# support struts
		for zz in range(38, 66, 7):
			k.box("metal_a", Vector3(0.14, 6.2, 0.14), Vector3(sx, -6.0, zz))
	# the ramp: z 52..34 rising y -9 -> -1, width 4, x centre 6
	var steps := 24
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var za := lerpf(52.0, 34.0, t0)
		var zb := lerpf(52.0, 34.0, t1)
		var yy := lerpf(y0, -1.0, t1)
		k.box("floor_a", Vector3(4.0, 0.35, za - zb + 0.05),
			Vector3(6, yy - 0.18, (za + zb) * 0.5))
	# ramp side walls + rails
	var slope := atan2(8.0, 18.0)
	var b := Basis(Vector3.RIGHT, slope)
	for sx in [3.7, 8.3]:
		k.push(Transform3D(b, Vector3(sx, (y0 - 1.0) * 0.5 + 0.5, 43)))
		k.box("metal_a", Vector3(0.18, 1.2, 19.5))
		k.pop()
		st.rail("metal_d", Vector3(sx, y0 + 0.4, 51.5), Vector3(sx, -1.0 + 0.4, 34.5))
	# hazard edge at ramp base
	k.box("hazard", Vector3(4.4, 0.04, 0.5), Vector3(6, y0 + 0.03, 52.3))
	# cargo manifest holo pillar near ramp
	pr.holo_column(Vector3(-6, y0, 36.5), 2.4, 0.5)
	# straps / nets: horizontal cables between stacks
	for i in 4:
		pr.cable_sag(Vector3(-12, y0 + 3.6, 40 + i * 6.0),
			Vector3(-2, y0 + 3.4, 40 + i * 6.0), 0.6, 2, 0.04)
	for zz in [40.0, 48.0, 56.0, 63.0]:
		for xx in [-7, 0, 9]:
			pr.lightbar(Vector3(xx, y1 - 0.35, zz), 2.4, false)
	add_light(Vector3(0, y1 - 1.5, 50), Color(1.0, 0.85, 0.6), 114, 26, true)
	add_light(Vector3(-9, y1 - 2, 42), Color(1.0, 0.85, 0.6), 99, 16)
	add_light(Vector3(9, y1 - 2, 58), Color(1.0, 0.85, 0.6), 99, 16)


# ============================================================== ATRIUM ======
func zone_atrium() -> void:
	var y0 := ShipLayout.DECK_MAIN
	var y1 := 11.0
	st.slab("floor_b", -15, 15, 8, 34, y0, 0.4)
	# ceiling slab with skylight hole (z 12..30, x -4..4)
	st.slab("ceil", -15, 15, 8, 34, y1, 0.4, [Rect2(-4, 12, 8, 18)])
	# skylight glass + frame ribs
	k.box("glass", Vector3(8.4, 0.15, 18.4), Vector3(0, y1 + 0.4, 21))
	for i in 7:
		var zz := 12.5 + i * 3.0
		k.box("metal_d", Vector3(8.6, 0.25, 0.18), Vector3(0, y1 + 0.45, zz))
	for i in 3:
		var xx := -2.0 + i * 2.0
		k.box("metal_d", Vector3(0.18, 0.25, 18.4), Vector3(xx, y1 + 0.45, 21))
	st.wall_x("wall_b", 34, -15, 15, y0, y1, 0.5,
		[[6, 4.0, -4.4, 4.6, "open"], [0, 3.0, 0, 4.2, "gate"]])
	st.wall_x("wall_b", 8, -15, 15, y0, y1, 0.5, [[0, 3.0, 0, 4.2, "gate"]])
	st.wall_z("wall_b", -15, 8, 34, y0, y1, 0.5,
		[[16, 2.4, 0.0, 2.6, "door"], [24, 2.4, 0.0, 2.6, "door"]])
	st.wall_z("wall_b", 15, 8, 34, y0, y1, 0.5,
		[[13, 2.4, 0.0, 2.6, "door"], [27, 2.4, 0.0, 2.6, "door"]])
	# mezzanine balcony ring at y=+3.4
	var by := 3.4
	for sx in [-1, 1]:
		k.box("floor_b", Vector3(4.0, 0.3, 22.0), Vector3(sx * 12.4, by, 21))
		st.rail("metal_d", Vector3(sx * 10.4, by + 0.15, 10.5),
			Vector3(sx * 10.4, by + 0.15, 31.5))
	# balcony support columns (fluted: box + corner pipes)
	for sx in [-11.8, 11.8]:
		for zz in [12.0, 21.0, 30.0]:
			k.boxb("wall_b", Vector3(0.7, by - y0, 0.7), Vector3(sx, (by + y0) * 0.5, zz), 0.06)
			k.cyl("metal_d", 0.05, 0.05, by - y0, 6, Vector3(sx + 0.4, y0, zz + 0.4), true)
	# bridge of the balcony across the atrium (z=21)
	k.box("floor_b", Vector3(20.8, 0.3, 3.0), Vector3(0, by, 21))
	st.rail("metal_d", Vector3(-10.4, by + 0.15, 19.6), Vector3(10.4, by + 0.15, 19.6))
	st.rail("metal_d", Vector3(-10.4, by + 0.15, 22.4), Vector3(10.4, by + 0.15, 22.4))
	# central holo-obelisk fountain
	pr.holo_column(Vector3(0, y0, 21), 5.2, 0.9)
	k.torus("metal_d", 1.6, 0.15, 18, 6, Vector3(0, y0 + 0.08, 21))
	# planters flanking the route
	for sx in [-5.5, 5.5]:
		for zz in [15, 27]:
			k.boxb("metal_a", Vector3(3.2, 0.7, 1.1), Vector3(sx, y0 + 0.35, zz), 0.08)
			for j in 5:
				pr.plant_pot(Vector3(sx - 1.2 + j * 0.6, y0 + 0.68, zz), 0.75)
	# benches + info consoles
	pr.bench(Vector3(-8, y0, 18), 2.6, 0.0)
	pr.bench(Vector3(-8, y0, 24), 2.6, 0.0)
	pr.bench(Vector3(8, y0, 15), 2.6, PI)
	pr.console(9, y0, 30.5, -1.0, 1.8, "screen_b")
	pr.console(-9, y0, 30.5, -1.0, 1.8, "screen_b")
	# hanging banners (emissive strips)
	for sx in [-13.5, 13.5]:
		for zz in [16.0, 26.0]:
			k.box("u_segm", Vector3(0.06, 2.6, 0.5), Vector3(sx, y1 - 2.2, zz))
	# sconces + cove lights under balcony
	for sx in [-14.6, 14.6]:
		for zz in range(11, 33, 4):
			k.box("u_light", Vector3(0.08, 0.5, 0.3), Vector3(sx, y0 + 3.0, zz))
	for xx in [-12.4, 12.4]:
		for zz in range(11, 33, 5):
			k.box("u_light", Vector3(0.24, 0.07, 1.4), Vector3(xx, by - 0.22, zz))
	add_light(Vector3(0, y1 - 2.5, 21), Color(0.85, 0.92, 1.0), 140, 30, true)
	add_light(Vector3(-10, y0 + 2.0, 21), Color(0.95, 0.9, 0.8), 57, 12)
	add_light(Vector3(10, y0 + 2.0, 21), Color(0.95, 0.9, 0.8), 57, 12)
	add_light(Vector3(0, y0 + 5.5, 21), Color(0.5, 0.75, 1.0), 51, 10)
	add_light(Vector3(-11, 5.5, 16), Color(0.9, 0.9, 0.8), 71, 12)
	add_light(Vector3(11, 5.5, 26), Color(0.9, 0.9, 0.8), 71, 12)


# ============================================================= HABITAT ======
func zone_habitat() -> void:
	var y0 := ShipLayout.DECK_MAIN
	var y1 := 5.5
	# spine corridor
	var doors_l := []
	var doors_r := []
	for rm in habitat_rooms:
		var r: Rect2 = rm["r"]
		var cz := r.get_center().y
		var op := [cz, 1.8, 0.0, 2.6, "door"]
		if rm["d"] == "xp":
			doors_l.append(op)
		else:
			doors_r.append(op)
	st.corridor("wall_b", "floor_b", "ceil", -3, 3, -38, 8, y0, y1,
		_doors_flip(doors_l), _doors_flip(doors_r), "z0z1")
	st.wall_x("wall_b", 8, -14, -3, y0, y1, 0.3)
	st.wall_x("wall_b", 8, 3, 14, y0, y1, 0.3)
	st.wall_x("wall_b", -38, -14, -3, y0, y1, 0.3)
	st.wall_x("wall_b", -38, 3, 14, y0, y1, 0.3)
	# attic caps seal the room wings against the void
	st.slab("wall_b", -14, -3, -38, 8, y0 + 4.2, 0.25)
	st.slab("wall_b", 3, 14, -38, 8, y0 + 4.2, 0.25)
	# room shells + sparse furnishing
	for rm in habitat_rooms:
		var r: Rect2 = rm["r"]
		st.room("wall_b", "floor_b", "ceil", r, y0, y0 + 4.2, rm["d"], 1.8)
		var cx := r.get_center().x
		var cz := r.get_center().y
		match rm["n"]:
			"MESS":
				pr.table(Vector3(cx - 1.6, y0, cz), 0.0)
				pr.table(Vector3(cx + 1.4, y0, cz), 0.0)
			"GYM":
				pr.bench(Vector3(cx, y0, cz - 0.5), 1.6, 0.0)
				pr.rack(cx + 2.5, y0, cz, 0.7, 1.6)
			"GALLEY":
				pr.console(cx - 2, y0, cz, 1.0, 1.4, "screen_c")
				pr.table(Vector3(cx + 1, y0, cz), 0.0)
			"MED":
				pr.bunk(Vector3(cx - 1.5, y0, cz), 0.0, 1)
				pr.console(cx + 1.5, y0, cz, -1.0, 1.4, "screen_c")
			_:
				pr.bunk(Vector3(cx - 1.8, y0, cz), 0.0, 2)
				pr.stow(Vector3(cx + 1.6, y0, cz + 0.4), 0.7, 0.3)
		pr.lightbar(Vector3(cx, y0 + 3.7, cz), 1.2, true)
		add_light(Vector3(cx, y0 + 3.0, cz), Color(1.0, 0.9, 0.8), 45, 9)
	# spine dressing
	st.light_run("u_light", 0, 8, -38, y1 - 0.15, 0.25, 3.2)
	# mid-scale structure: pilaster ribs between doors + ceiling cable tray,
	# so the corridor reads as built architecture not flat panels
	# door centres L: 5.5,0.5,-4.5,-9,-14,-20.5,-25.5,-31.5 / R: 5.5,0.5,-4.5,
	# -13.5,-19.5,-25,-31 — pilasters sit in the gaps between them
	for sx in [-2.92, 2.92]:
		for zz in [-2.5, -7.0, -11.5, -16.5, -22.5, -28.0, -34.0]:
			k.boxb("wall_b", Vector3(0.22, y1 - y0, 0.3), Vector3(sx, (y0 + y1) * 0.5, zz), 0.03)
			k.box("u_light", Vector3(0.05, 0.5, 0.05), Vector3(sx * 0.99, y0 + 2.7, zz))
	# cable tray: pipes tucked up tight under the ceiling slab — lower and
	# they float mid-air as dark tubes slicing the frame at grazing angle
	for sx in [-2.72, 2.72]:
		pr.pipe([Vector3(sx, y1 - 0.18, 8), Vector3(sx, y1 - 0.18, -38)],
			0.055, "metal_c", y1 - 0.02)
	pr.pipe([Vector3(0, y1 - 0.22, 8), Vector3(0, y1 - 0.22, -38)],
		0.04, "copper", -100)
	for zz in range(6, -38, -9):
		pr.plant_pot(Vector3(-2.4, y0, zz), 0.8)
		pr.plant_pot(Vector3(2.4, y0, zz - 4), 0.8)
	for zz in range(4, -38, -8):
		k.box("u_segm", Vector3(0.35, 0.10, 0.06), Vector3(-2.92, y0 + 2.4, zz))
	add_light(Vector3(0, y0 + 5.0, -4), Color(1.0, 0.9, 0.75), 42, 18)
	add_light(Vector3(0, y0 + 4.0, 0), Color(1.0, 0.92, 0.8), 24, 11)
	add_light(Vector3(0, y0 + 5.0, -22), Color(1.0, 0.9, 0.75), 42, 18)
	add_light(Vector3(0, y0 + 4.0, -34), Color(1.0, 0.92, 0.8), 34, 13)
	# low warm fill at camera height: washes door leaves + jamb faces so
	# grazing faces never crush to black
	add_light(Vector3(0, y0 + 2.2, 4), Color(1.0, 0.9, 0.75), 14, 12)
	# grazing-angle fill: z-faces of door leaves / frames are invisible to the
	# overhead omnis (dot(N,L)≈0) and read as black bars down the corridor;
	# a pair of axis-aligned spots keeps every portal edge readable
	add_spot(Vector3(0, y0 + 3.5, 6), Vector3(0, y0 + 1.0, -38),
		Color(1.0, 0.9, 0.75), 40, 26, 40.0)
	add_spot(Vector3(0, y0 + 3.5, -36), Vector3(0, y0 + 1.0, 8),
		Color(1.0, 0.9, 0.75), 40, 26, 40.0)


static func _doors_flip(doors: Array) -> Array:
	# corridor() expects openings as [centre,w,sill,h,kind] — pass through
	return doors


# =============================================================== LOBBY ======
func zone_lobby() -> void:
	var y0 := ShipLayout.DECK_MAIN
	var y1 := 5.5
	st.slab("floor_c", -12, 12, -48, -38, y0, 0.35)
	st.slab("ceil", -12, 12, -48, -38, y1, 0.3)
	st.wall_x("wall_c", -38, -12, 12, y0, y1, 0.4, [[0, 3.0, 0, 4.0, "gate"]])
	st.wall_x("wall_c", -48, -12, 12, y0, y1, 0.4, [[0, 4.0, 0, 4.6, "open"]])
	st.wall_z("wall_c", -12, -48, -38, y0, y1, 0.4,
		[[-43, 2.2, 0.0, 2.8, "door"]])
	st.wall_z("wall_c", 12, -48, -38, y0, y1, 0.4,
		[[-43, 2.2, 0.0, 2.8, "door"]])
	# reception / security desk
	k.push(Transform3D(Basis(), Vector3(0, y0, -44.5)))
	k.part(-1.0, 0.0, 1.0)
	k.boxb("metal_a", Vector3(4.4, 1.05, 1.0), Vector3(0, 0.52, 0), 0.06)
	k.box("screen_a", Vector3(1.4, 0.02, 0.6), Vector3(-1.0, 1.07, 0))
	k.box("screen_c", Vector3(1.4, 0.02, 0.6), Vector3(1.0, 1.07, 0))
	k.box("u_light_c", Vector3(4.2, 0.05, 0.05), Vector3(0, 0.9, 0.52))
	k.pop()
	# turnstiles
	for sx in [-2.6, 2.6]:
		k.cyl("metal_d", 0.12, 0.12, 1.1, 10, Vector3(sx, y0, -42.5), true)
		k.box("glass", Vector3(0.7, 1.0, 0.04), Vector3(sx, y0 + 0.55, -42.5))
	pr.plant_pot(Vector3(-8, y0, -41), 1.1)
	pr.plant_pot(Vector3(8, y0, -41), 1.1)
	pr.bench(Vector3(-9.5, y0, -46.5), 2.6, PI / 2)
	pr.bench(Vector3(9.5, y0, -46.5), 2.6, -PI / 2)
	for xx in [-6, 0, 6]:
		pr.lightbar(Vector3(xx, y1 - 0.3, -43), 2.0, false, "u_light_c")
	add_light(Vector3(0, y0 + 4.5, -43), Color(0.7, 0.85, 1.0), 150, 20)
	add_light(Vector3(0, y0 + 4.0, -39), Color(0.75, 0.88, 1.0), 70, 10)
	add_light(Vector3(0, y0 + 2.5, -42.5), Color(0.7, 0.85, 1.0), 40, 8)


# ========================================================== STAIR HALL ======
func zone_stair() -> void:
	var y0 := ShipLayout.DECK_MAIN
	var y1 := 13.0
	# floor slab at y0 for z -56..-48 (landing), stairs carry you down into
	# the well; the slab has a hole where the stair runs (z -70..-56)
	st.slab("floor_c", -9, 9, -70, -48, y0, 0.35,
		[Rect2(-4.2, -70, 8.4, 14)])
	# upper walkway at command level around the well
	st.slab("floor_c", -9, 9, -70, -48, 7.0, 0.35,
		[Rect2(-4.2, -70, 8.4, 14)])
	# walls full height; lower gate at z=-48, command opening at z=-70
	st.wall_x("wall_c", -48, -9, 9, y0, y1, 0.4, [[0, 4.0, 0, 4.6, "open"]])
	st.wall_x("wall_c", -70, -9, 9, y0, y1, 0.4, [[0, 3.4, 6.0, 4.4, "open"]])
	st.wall_z("wall_c", -9, -70, -48, y0, y1, 0.4)
	st.wall_z("wall_c", 9, -70, -48, y0, y1, 0.4)
	st.slab("ceil", -9, 9, -70, -48, y1, 0.3)
	# the grand stair: straight flight x-centred, z -56 -> -70 rising to 7
	st.stair("floor_c", 0, -56, -70, y0, 7.0, 8.4)
	# landing rails across the well at both levels
	st.rail("metal_d", Vector3(-4.2, y0, -56), Vector3(-9 + 0.4, y0, -56))
	st.rail("metal_d", Vector3(4.2, y0, -56), Vector3(9 - 0.4, y0, -56))
	st.rail("metal_d", Vector3(-4.2, 7.0, -56), Vector3(-9 + 0.4, 7.0, -56))
	st.rail("metal_d", Vector3(4.2, 7.0, -56), Vector3(9 - 0.4, 7.0, -56))
	# void walls cladding the stair sides inside the well
	st.wall_z("wall_c", -4.3, -70, -56, y0, 7.0, 0.15)
	st.wall_z("wall_c", 4.3, -70, -56, y0, 7.0, 0.15)
	# clerestory light cove
	for zz in [-52, -58, -64]:
		k.box("u_light_c", Vector3(6.0, 0.08, 0.4), Vector3(0, y1 - 0.4, zz))
	for sx in [-8.6, 8.6]:
		for zz in range(-66, -49, 5):
			k.box("u_light", Vector3(0.08, 0.5, 0.3), Vector3(sx, 9.5, zz))
	# memorial plaque on the wall
	k.box("u_segm", Vector3(0.08, 1.2, 2.2), Vector3(-8.8, 2.5, -59))
	add_light(Vector3(0, 11.5, -59), Color(0.7, 0.85, 1.0), 140, 22, true)
	add_light(Vector3(0, 3.5, -52), Color(0.7, 0.85, 1.0), 95, 16)
	add_light(Vector3(0, 1.8, -58), Color(0.75, 0.88, 1.0), 45, 14)
	add_light(Vector3(0, 5.5, -64), Color(0.7, 0.85, 1.0), 70, 12)
	# wall fill so the stair backdrop reads as space, not a black hole
	# behind the rails when viewed from the habitat corridor
	add_light(Vector3(-6, 4.0, -55), Color(0.7, 0.85, 1.0), 35, 12)
	add_light(Vector3(6, 4.0, -55), Color(0.7, 0.85, 1.0), 35, 12)
	add_light(Vector3(0, 3.0, -68), Color(0.7, 0.85, 1.0), 40, 14)


# ============================================================= COMMAND ======
func zone_command() -> void:
	var y0 := ShipLayout.DECK_CMD
	var y1 := 13.0
	var doors_l := []
	var doors_r := []
	for rm in command_rooms:
		var r: Rect2 = rm["r"]
		var cz := r.get_center().y
		var op := [cz, 1.8, 0.0, 3.4, "door"]
		if rm["d"] == "xp":
			doors_l.append(op)
		else:
			doors_r.append(op)
	st.corridor("wall_c", "floor_c", "ceil", -3, 3, -104, -70, y0, y1,
		doors_l, doors_r, "z0z1")
	st.wall_x("wall_c", -70, -11, -3, y0, y1, 0.3)
	st.wall_x("wall_c", -70, 3, 11, y0, y1, 0.3)
	st.wall_x("wall_c", -104, -11, -3, y0, y1, 0.3)
	st.wall_x("wall_c", -104, 3, 11, y0, y1, 0.3)
	st.slab("wall_c", -11, -3, -104, -70, y0 + 4.2, 0.25)
	st.slab("wall_c", 3, 11, -104, -70, y0 + 4.2, 0.25)
	for rm in command_rooms:
		var r: Rect2 = rm["r"]
		st.room("wall_c", "floor_c", "ceil", r, y0, y0 + 4.2, rm["d"], 1.8)
		var cx := r.get_center().x
		var cz := r.get_center().y
		match rm["n"]:
			"BRIEF":
				pr.table(Vector3(cx, y0, cz), 0.0)
				pr.holo_column(Vector3(cx, y0, cz), 1.8, 0.35)
			"CIC", "NAV":
				for i in 2:
					pr.console(cx - 1.6 + i * 1.7, y0, cz - 0.8, 1.0, 1.4, "screen_b")
				pr.rack(cx + 2.2, y0, cz + 0.8)
			_:
				pr.rack(cx - 1, y0, cz)
				pr.stow(Vector3(cx + 0.8, y0, cz + 0.6), 0.7, 0.5)
		pr.lightbar(Vector3(cx, y0 + 3.7, cz), 1.2, true)
		add_light(Vector3(cx, y0 + 3.0, cz), Color(0.7, 0.85, 1.0), 26, 7)
	st.light_run("u_light_c", 0, -70, -104, y1 - 0.2, 0.25, 3.5)
	# wall status strips
	for zz in range(-74, -104, -8):
		k.box("u_segm", Vector3(0.06, 0.5, 1.4), Vector3(-2.9, y0 + 2.2, zz))
		k.box("u_segm", Vector3(0.06, 0.5, 1.4), Vector3(2.9, y0 + 2.2, zz))
	add_light(Vector3(0, y0 + 5.0, -80), Color(0.72, 0.83, 1.0), 113, 18)
	add_light(Vector3(0, y0 + 5.0, -96), Color(0.72, 0.83, 1.0), 113, 18)


# =============================================================== BRIDGE =====
func zone_bridge() -> void:
	var y0 := ShipLayout.DECK_CMD
	var y1 := 13.5
	st.slab("floor_c", -10, 10, -136, -104, y0, 0.4)
	st.slab("ceil", -10, 10, -136, -104, y1, 0.3)
	st.wall_x("wall_c", -104, -10, 10, y0, y1, 0.4, [[0, 3.4, 0, 4.2, "gate"]])
	st.wall_z("wall_c", -10, -136, -104, y0, y1, 0.4)
	st.wall_z("wall_c", 10, -136, -104, y0, y1, 0.4)
	# wrap viewport: 5 slightly-raked panes spanning the bow aperture,
	# y 5.5 -> 10.5 sloping forward, z ~ -128 behind consoles
	for i in 5:
		var x0 := -8.75 + i * 3.5
		var x1 := x0 + 3.5
		var q := [Vector3(x0, 5.4, -127.0), Vector3(x1, 5.4, -127.0),
			Vector3(x1, 10.6, -131.5), Vector3(x0, 10.6, -131.5)]
		var n := Vector3(0, 0.62, 0.79).normalized()   # faces up-stern
		k.quad("glass", q, n)
		k.tube("metal_d", [q[0], q[3]], 0.06, 5, true)
	k.tube("metal_d", [Vector3(-8.75, 5.4, -127), Vector3(8.75, 5.4, -127)], 0.07, 5, true)
	k.tube("metal_d", [Vector3(-8.75, 10.6, -131.5), Vector3(8.75, 10.6, -131.5)], 0.07, 5, true)
	# viewport sill + header
	k.box("metal_d", Vector3(17.6, 0.3, 0.6), Vector3(0, 5.3, -127))
	k.box("metal_d", Vector3(17.6, 0.3, 0.6), Vector3(0, 10.7, -131.4))
	# bow seal: the raked panes sit proud of the stern wall; without a
	# back wall the cavity behind them leaked raw starfield into the room
	st.wall_x("wall_c", -136, -10, 10, y0, y1, 0.4)
	# reveal cavity around the panes: ribs + a dim cold light so the
	# glass reads as a recessed window, not a hole into the void
	for sx in [-9.4, 9.4]:
		k.boxb("metal_d", Vector3(0.5, y1 - y0, 9.0), Vector3(sx, (y0 + y1) * 0.5, -131.5), 0.03)
	k.boxb("metal_d", Vector3(17.6, 0.5, 4.6), Vector3(0, y1 - 0.35, -133.8), 0.03)
	add_light(Vector3(0, 9.5, -133), Color(0.45, 0.6, 0.95), 25, 10)
	# floor tiers: raised command dais + step detail
	k.boxb("floor_c", Vector3(6.0, 0.35, 8.0), Vector3(0, y0 + 0.18, -120), 0.05)
	k.boxb("metal_d", Vector3(6.4, 0.16, 0.5), Vector3(0, y0 + 0.08, -115.9), 0.03)
	k.boxb("metal_d", Vector3(6.4, 0.16, 0.5), Vector3(0, y0 + 0.08, -124.1), 0.03)
	for sx in [-1, 1]:
		k.box("u_light_c", Vector3(0.04, 0.04, 7.6), Vector3(sx * 3.05, y0 + 0.36, -120))
	pr.big_chair(Vector3(0, y0 + 0.35, -121), 0.0)
	# wrap-around console arc at the viewport base
	for i in 9:
		var a := lerpf(-1.1, 1.1, float(i) / 8)
		var px := sin(a) * 6.5
		var pz := -126 - cos(a) * 5.0
		pr.console(px, y0, pz, signf(px) * 0.5 + 0.0, 1.7,
			"screen_b" if i % 3 == 0 else "screen_a")
	# side stations on little plinths + desk rails
	for sx in [-8.6, 8.6]:
		for i in 3:
			var zz := -108.5 - i * 6.5
			pr.console(sx, y0, zz, 0.0, 1.5,
				"screen_c" if i == 1 else "screen_a")
			k.boxb("metal_d", Vector3(0.18, 0.4, 1.8), Vector3(sx * 0.93, y0 + 0.2, zz), 0.03)
		st.rail("metal_d", Vector3(sx * 0.92, y0 + 0.5, -107), Vector3(sx * 0.92, y0 + 0.5, -127), 0.9, 2.2)
	# astrogation holo table mid-deck
	pr.holo_column(Vector3(0, y0, -113), 2.4, 0.7)
	# wall pilasters every ~6 m + sconce strips so the walls read as
	# structure, plus a cable tray along both flanks
	for sx in [-9.75, 9.75]:
		for zz in range(-106, -134, -6):
			k.boxb("wall_c", Vector3(0.5, y1 - y0, 0.35), Vector3(sx, (y0 + y1) * 0.5, zz - 0.5), 0.04)
			k.box("u_light", Vector3(0.06, 0.7, 0.06), Vector3(sx * 0.985, y0 + 2.6, zz))
		pr.pipe([Vector3(sx * 0.97, y1 - 0.6, -105.5), Vector3(sx * 0.97, y1 - 0.6, -132.5)],
			0.10, "metal_c", y1 - 0.15)
		pr.pipe([Vector3(sx * 0.97, y1 - 1.0, -105.5), Vector3(sx * 0.97, y1 - 1.0, -132.5)],
			0.06, "copper", -100)
	# overhead status ring + cross-braced light troughs over the dais
	k.torus("u_light_c", 2.6, 0.09, 24, 5, Vector3(0, y1 - 0.5, -120))
	for sx in [-6, 0, 6]:
		pr.lightbar(Vector3(sx, y1 - 0.3, -110), 2.0, false, "u_light_c")
	for zz in [-114, -122]:
		k.box("dark", Vector3(16.0, 0.22, 0.5), Vector3(0, y1 - 0.4, zz))
		k.box("u_light_c", Vector3(15.4, 0.05, 0.18), Vector3(0, y1 - 0.52, zz))
	# mission displays: tilted overhead boards above the console arc +
	# matching side-wall screens, all visible from the entry gate
	for i in 3:
		var sx := -4.6 + i * 4.6
		var b := Basis(Vector3.RIGHT, -0.6)
		k.push(Transform3D(b, Vector3(sx, y1 - 1.6, -126.5)))
		k.boxb("metal_a", Vector3(3.4, 1.6, 0.14), Vector3(0, 0, 0), 0.03)
		k.box("screen_b" if i != 1 else "screen_a",
			Vector3(3.1, 1.3, 0.05), Vector3(0, 0, 0.09))
		k.pop()
	for sx in [-9.85, 9.85]:
		for zz in [-112, -118, -124]:
			k.boxb("metal_a", Vector3(0.16, 1.5, 2.6), Vector3(sx, y0 + 3.9, zz), 0.03)
			k.box("screen_c", Vector3(0.06, 1.2, 2.3), Vector3(sx * 0.985, y0 + 3.9, zz))
	# wall insignia panel
	k.box("u_segm", Vector3(0.08, 1.6, 3.0), Vector3(-9.9, y0 + 3.4, -120))
	k.box("u_segm", Vector3(0.08, 1.6, 3.0), Vector3(9.9, y0 + 3.4, -120))
	add_light(Vector3(0, y0 + 5.5, -118), Color(0.62, 0.76, 0.98), 95, 26)
	add_light(Vector3(-7, y0 + 4, -126), Color(0.5, 0.7, 1.0), 45, 13)
	add_light(Vector3(7, y0 + 4, -126), Color(0.5, 0.7, 1.0), 45, 13)
	# uplights wash the ceiling slab so it doesn't read as a black void
	add_light(Vector3(-5, y1 - 1.0, -120), Color(0.5, 0.62, 0.9), 40, 12)
	add_light(Vector3(5, y1 - 1.0, -120), Color(0.5, 0.62, 0.9), 40, 12)
	# bow running light: outside the viewport, silhouettes the nose
	add_light(Vector3(0, y0 + 7.0, -142), Color(0.55, 0.7, 1.0), 60, 25)
	add_light(Vector3(0, y0 + 4.0, -108), Color(0.7, 0.78, 0.9), 40, 12)


# ============================================================ ROUTE MARKS ====
## Glowing chevron inlays along the main route + zone name plates.
func route_marks() -> void:
	var R: Array = L.route
	for i in range(R.size() - 1):
		var a: Vector3 = R[i]
		var b: Vector3 = R[i + 1]
		var seg := a.distance_to(b)
		if seg < 2.0:
			continue
		var n := int(seg / 5.0)
		for j in n:
			var p := a.lerp(b, (float(j) + 0.5) / n)
			# skip where a stair/ramp already guides
			k.part(-1.0, 0.0, 1.0)
			k.push(Transform3D(Basis(), p + Vector3(0, 0.025, 0)))
			k.box("u_chev", Vector3(0.34, 0.015, 0.5))
			k.pop()


# ================================================================= BUILD ====
func build(root: Node3D) -> void:
	zone_engine()
	zone_reactor()
	zone_fuel()
	zone_machine()
	zone_cargo()
	zone_atrium()
	zone_habitat()
	zone_lobby()
	zone_stair()
	zone_command()
	zone_bridge()
	route_marks()
	k.commit(root, "Interior", true, 1)

class_name InteriorBuilder
extends RefCounted

## Builds every habitable volume inside the hull.
## Main-route spaces (engine / cargo / spine / reactor / galleria / hydro /
## command) get the full treatment: structural ribs, cable trays, signage,
## furniture and lighting. Off-route rooms are deliberately simpler.

var kit: MeshKit
var lib: MatLib
var cfg: ShipConfig
var lights: Node3D
var props: Props
var rd: RoomDetail
var detail_root: Node3D
var rng := RandomNumberGenerator.new()
var zone_node: Node3D
var zone_key := ""
var zone_wear := 1.0
var zone_variant := 0
var zone_nodes: Array = []
var wall_t := 0.45


func _init(k: MeshKit, l: MatLib, c: ShipConfig, lights_root: Node3D) -> void:
	kit = k
	lib = l
	cfg = c
	lights = lights_root
	rng.seed = 44551


func build(parent: Node3D) -> void:
	detail_root = Node3D.new()
	detail_root.name = "InteriorDetails"
	parent.add_child(detail_root)
	props = Props.new(kit, lib, cfg, detail_root)
	rd = RoomDetail.new(kit, props, cfg, detail_root, detail_root)

	z_engine(parent)
	z_stair_a(parent)
	z_cargo(parent)
	z_corr_aft(parent)
	z_vestibule(parent)
	z_spine(parent)
	z_reactor(parent)
	z_atrium(parent)
	z_hydro(parent)
	z_bridge_approach(parent)
	z_bridge(parent)
	z_quarters(parent)
	z_medbay(parent)
	z_observation(parent)
	z_hangar(parent)
	z_machine(parent)
	z_tanks(parent)
	z_galley(parent)
	z_officers(parent)
	build_route_marks(parent)


# ============================================================== helpers =====
func zone(name: String, label: String = "") -> void:
	zone_key = name
	var h := 7
	for ch in name:
		h = (h * 37 + ch.unicode_at(0)) & 0x7fffffff
	zone_variant = h % 3
	var wear_base := 0.85 + float(h % 45) * 0.01
	match name:
		"engine":
			wear_base = 1.25
		"machine", "tanks":
			wear_base = 1.15
		"medbay":
			wear_base = 0.38
		"bridge", "officers":
			wear_base = 0.5
		"atrium", "hydro", "observation":
			wear_base = 0.62
		"quarters":
			wear_base = 0.7 + float(h % 25) * 0.012
		"cargo":
			wear_base = 1.0 + float(h % 15) * 0.01
	zone_wear = clampf(wear_base, 0.2, 1.35)
	kit.set_wear(zone_wear)
	zone_node = Node3D.new()
	zone_node.name = name
	zone_node.set_meta("zone_name", label if label != "" else name)
	zone_node.set_meta("zone_key", name)
	detail_root.get_parent().add_child(zone_node)
	zone_nodes.append(zone_node)
	props.root = zone_node
	rd.root = zone_node
	rd.lum = zone_node


func commit_zone(name: String) -> void:
	kit.commit(zone_node, name)
	zone_node.set_meta("zone_aabb", _zone_aabb(zone_node))
	zone_node = null
	zone_key = ""


func _zone_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [n]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var a: AABB = mi.get_aabb()
			if first:
				box = a
				first = false
			else:
				box = box.merge(a)
		for c in node.get_children():
			stack.append(c)
	return box


func light(pos: Vector3, col: Color, energy: float, rng_m: float, shadow: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy * 2.8
	l.omni_range = rng_m * 1.3
	l.omni_attenuation = 1.15
	l.shadow_enabled = shadow
	l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	if zone_node != null:
		zone_node.add_child(l)
	else:
		lights.add_child(l)
	return l


## Rectangular room: floor, ceiling, walls with openings, ribs, trims,
## ceiling services and luminaires.
func shell(x0: float, x1: float, z0: float, z1: float, y: float, h: float,
		wall_key: String = "wall", floor_key: String = "floor",
		openings: Array = [], style: int = 0, open_top: bool = false) -> void:
	var ceil := y + h
	kit.set_height_range(y, ceil)
	# ---- floor ----
	kit.begin_part(0.35, style)
	kit.box(floor_key, Vector3(x1 - x0, 0.5, z1 - z0), Vector3((x0 + x1) * 0.5, y - 0.25, (z0 + z1) * 0.5))
	# perimeter trim / gutter
	kit.box("metal_dark", Vector3(x1 - x0, 0.10, 0.24), Vector3((x0 + x1) * 0.5, y + 0.05, z0 + 0.12))
	kit.box("metal_dark", Vector3(x1 - x0, 0.10, 0.24), Vector3((x0 + x1) * 0.5, y + 0.05, z1 - 0.12))
	kit.box("metal_dark", Vector3(0.24, 0.10, z1 - z0), Vector3(x0 + 0.12, y + 0.05, (z0 + z1) * 0.5))
	kit.box("metal_dark", Vector3(0.24, 0.10, z1 - z0), Vector3(x1 - 0.12, y + 0.05, (z0 + z1) * 0.5))
	# ---- ceiling slab ----
	if not open_top:
		kit.begin_part(0.4, style)
		kit.box("wall_dark", Vector3(x1 - x0, 0.4, z1 - z0), Vector3((x0 + x1) * 0.5, ceil + 0.2, (z0 + z1) * 0.5))
	# ---- walls ----
	_wall_side("n", x0, x1, z0, z1, y, h, openings, wall_key)
	_wall_side("s", x0, x1, z0, z1, y, h, openings, wall_key)
	_wall_side("w", x0, x1, z0, z1, y, h, openings, wall_key)
	_wall_side("e", x0, x1, z0, z1, y, h, openings, wall_key)
	# ---- structural ribs + trims ----
	kit.begin_part(0.3, style)
	var z := z0 + 1.6
	while z < z1 - 1.0:
		for side in [0, 1]:
			var key := "metal_dark"
			var xx := x0 + 0.09 if side == 0 else x1 - 0.09
			kit.box(key, Vector3(0.18, h - 0.28, 0.30), Vector3(xx, y + h * 0.5 - 0.1, z))
		# ceiling cross beam
		if not open_top:
			kit.box("metal_dark", Vector3(x1 - x0, 0.28, 0.20), Vector3((x0 + x1) * 0.5, ceil - 0.14, z))
		# floor trim between ribs
		kit.box("hazard_worn", Vector3(1.2, 0.03, 0.12), Vector3(x0 + 1.0, y + 0.015, z))
		kit.box("hazard_worn", Vector3(1.2, 0.03, 0.12), Vector3(x1 - 1.0, y + 0.015, z))
		z += 3.2
	# base + crown trim
	kit.box("metal_dark", Vector3(x1 - x0, 0.16, 0.08), Vector3((x0 + x1) * 0.5, y + 0.30, z0 + 0.05))
	kit.box("metal_dark", Vector3(x1 - x0, 0.16, 0.08), Vector3((x0 + x1) * 0.5, y + 0.30, z1 - 0.05))
	kit.box("metal", Vector3(x1 - x0, 0.10, 0.06), Vector3((x0 + x1) * 0.5, ceil - 0.55, z0 + 0.04))
	kit.box("metal", Vector3(x1 - x0, 0.10, 0.06), Vector3((x0 + x1) * 0.5, ceil - 0.55, z1 - 0.04))
	# ---- wall services / junction boxes / pipes ----
	dress_walls(x0, x1, z0, z1, y, h, openings, style)
	# ---- ceiling services ----
	if open_top:
		return
	kit.begin_part(0.42, style)
	var zz := z0 + 2.4
	var phase := 0
	while zz < z1 - 1.0:
		# luminaire pair
		var lx := (x0 + x1) * 0.5
		props.light_fixture(Vector3(lx - 0.7, ceil - 0.30, zz), Vector2(1.1, 0.32), "emit_white")
		props.light_fixture(Vector3(lx + 0.7, ceil - 0.30, zz), Vector2(1.1, 0.32), "emit_white")
		if phase % 2 == 0:
			light(Vector3(lx, ceil - 1.1, zz), Color(0.95, 0.97, 1.0), 2.6, 9.0, false)
		# cable tray along the west ceiling
		kit.box("metal_dark", Vector3(0.34, 0.09, 3.0), Vector3(x0 + 0.9, ceil - 0.62, zz))
		kit.box("rubber", Vector3(0.26, 0.06, 3.0), Vector3(x0 + 0.9, ceil - 0.70, zz))
		# coolant pipe along the east ceiling
		var pipe_pts: Array = []
		for i in 4:
			pipe_pts.append(Vector3(x1 - 0.9, ceil - 0.62, zz - 1.5 + i))
		kit.tube("pipe_teal", pipe_pts, 0.11, 8)
		zz += 6.0
		phase += 1


## Generic industrial dressing applied to every room: service pipes, cable
## trays, junction boxes, vents, kick strips and section stencils.
func dress_walls(x0: float, x1: float, z0: float, z1: float, y: float, h: float,
		openings: Array, style: int = 0) -> void:
	var mid_y := y + minf(2.6, h * 0.55)
	kit.begin_part(0.38, 2)
	# longitudinal pipe band on both flanks
	for side in [0, 1]:
		var xx: float = x0 + 0.16 if side == 0 else x1 - 0.16
		var z := z0 + 1.0
		var pts: Array = []
		while z <= z1 - 1.0:
			pts.append(Vector3(xx + (0.10 if side == 0 else -0.10), mid_y, z))
			z += 3.0
		if pts.size() > 1:
			kit.tube("pipe_teal", pts, 0.075, 8)
			var pts2: Array = []
			for p in pts:
				pts2.append(p + Vector3(0.0, 0.22, 0.0))
			kit.tube("pipe_cream", pts2, 0.05, 6)
		# clamps
		var zc := z0 + 1.0
		while zc < z1 - 1.0:
			kit.box("metal_dark", Vector3(0.10, 0.36, 0.12), Vector3(xx, mid_y + 0.11, zc))
			zc += 2.2
		# kick strip light
		kit.box("emit_strip_dim" if style != 2 else "emit_strip_warm",
			Vector3(0.05, 0.05, z1 - z0 - 1.4), Vector3(xx, y + 0.36, (z0 + z1) * 0.5))
		# junction boxes + vents at intervals
		var k := 0
		var zj := z0 + 3.0
		while zj < z1 - 2.0:
			var blocked := false
			for o in openings:
				if o["side"] == ("w" if side == 0 else "e") and absf(float(o["c"]) - zj) < 1.8:
					blocked = true
			if not blocked:
				kit.begin_part(0.45 + 0.03 * k, 29.0)
				kit.box("metal_cast", Vector3(0.16, 0.62, 0.46), Vector3(xx, y + 1.55, zj))
				kit.box("screen_power" if k % 3 == 0 else "screen_log", Vector3(0.02, 0.30, 0.34),
					Vector3(xx + (0.09 if side == 0 else -0.09), y + 1.66, zj))
				kit.box("emit_green" if k % 2 == 0 else "emit_amber", Vector3(0.04, 0.05, 0.05),
					Vector3(xx + (0.09 if side == 0 else -0.09), y + 1.36, zj + 0.16))
				if k % 2 == 1:
					kit.box("metal_dark", Vector3(0.10, 0.44, 0.90), Vector3(xx, y + h - 0.75, zj + 1.2))
					for m in 4:
						kit.box("metal", Vector3(0.02, 0.03, 0.78), Vector3(xx + (0.06 if side == 0 else -0.06), y + h - 0.92 + m * 0.10, zj + 1.2))
			zj += 6.5
			k += 1
	# overhead cable tray across the room every 7m
	var zt := z0 + 4.0
	while zt < z1 - 1.0:
		kit.box("metal_dark", Vector3(x1 - x0 - 0.8, 0.10, 0.34), Vector3((x0 + x1) * 0.5, y + h - 0.62, zt))
		for c in 3:
			kit.box("rubber", Vector3(x1 - x0 - 1.0, 0.05, 0.06),
				Vector3((x0 + x1) * 0.5, y + h - 0.56, zt - 0.1 + c * 0.1))
		zt += 7.0


func _wall_side(side: String, x0: float, x1: float, z0: float, z1: float,
		y: float, h: float, openings: Array, key: String) -> void:
	var ops: Array = []
	for o in openings:
		if o["side"] == side:
			ops.append(o)
	ops.sort_custom(func(a, b): return float(a["c"]) < float(b["c"]))
	if side == "n" or side == "s":
		var zc := z0 - wall_t * 0.5 if side == "n" else z1 + wall_t * 0.5
		var u0 := x0 - wall_t
		var u1 := x1 + wall_t
		_wall_run(zc, u0, u1, y, h, ops, key, "z", x0, x1)
	else:
		var xc := x0 - wall_t * 0.5 if side == "w" else x1 + wall_t * 0.5
		var u0 := z0 - wall_t
		var u1 := z1 + wall_t
		_wall_run(xc, u0, u1, y, h, ops, key, "x", z0, z1)


func _wall_run(fixed: float, u0: float, u1: float, y: float, h: float,
		ops: Array, key: String, axis: String, room_a: float, room_b: float) -> void:
	var cur := u0
	kit.begin_part(0.32, 1)
	for o in ops:
		var c: float = o["c"]
		var w: float = o["w"]
		var o0: float = c - w * 0.5
		var o1: float = c + w * 0.5
		var vy0: float = y + float(o.get("h0", 0.0))
		var vy1: float = y + float(o.get("h1", 2.4))
		if o0 > cur:
			_swall(fixed, cur, o0, y, y + h, key, axis)
		if vy1 < y + h:
			_swall(fixed, o0, o1, vy1, y + h, key, axis)
		if vy0 > y:
			_swall(fixed, o0, o1, y, vy0, key, axis)
		cur = o1
	if cur < u1:
		_swall(fixed, cur, u1, y, y + h, key, axis)


func _swall(fixed: float, a: float, b: float, ya: float, yb: float, key: String, axis: String) -> void:
	if b - a < 0.001 or yb - ya < 0.001:
		return
	if axis == "z":
		kit.box(key, Vector3(b - a, yb - ya, wall_t), Vector3((a + b) * 0.5, (ya + yb) * 0.5, fixed))
	else:
		kit.box(key, Vector3(wall_t, yb - ya, b - a), Vector3(fixed, (ya + yb) * 0.5, (a + b) * 0.5))


func ceiling_open(x0: float, x1: float, z0: float, z1: float, y: float,
		trim_key: String = "metal_dark") -> void:
	# framed opening for light wells / stair shafts
	kit.begin_part(0.42, 2)
	kit.box(trim_key, Vector3(x1 - x0 + 0.5, 0.35, 0.3), Vector3((x0 + x1) * 0.5, y, z0 - 0.15))
	kit.box(trim_key, Vector3(x1 - x0 + 0.5, 0.35, 0.3), Vector3((x0 + x1) * 0.5, y, z1 + 0.15))
	kit.box(trim_key, Vector3(0.3, 0.35, z1 - z0), Vector3(x0 - 0.15, y, (z0 + z1) * 0.5))
	kit.box(trim_key, Vector3(0.3, 0.35, z1 - z0), Vector3(x1 + 0.15, y, (z0 + z1) * 0.5))


func door_at(side: String, c: float, x0: float, x1: float, z0: float, z1: float,
		y: float, w: float = 2.2, h: float = 2.4, open_amount: float = 0.55,
		key: String = "metal") -> void:
	var pos: Vector3
	var yaw := 0.0
	match side:
		"n":
			pos = Vector3(c, y, z0 + 0.02)
		"s":
			pos = Vector3(c, y, z1 - 0.02)
		"w":
			pos = Vector3(x0 + 0.02, y, c)
			yaw = PI * 0.5
		"e":
			pos = Vector3(x1 - 0.02, y, c)
			yaw = PI * 0.5
	props.door(pos, yaw, w, h, open_amount, key)


func opening(side: String, c: float, w: float, h0: float = 0.0, h1: float = 2.4) -> Dictionary:
	return {"side": side, "c": c, "w": w, "h0": h0, "h1": h1}


func chevrons(points: Array, y_offset: float = 0.03, width: float = 0.55, gap: float = 3.2) -> void:
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		if absf(b.y - a.y) > 0.25:
			continue
		var d := b - a
		var flat := Vector3(d.x, 0, d.z)
		var len := flat.length()
		if len < 0.4:
			continue
		var dir := flat / len
		var right := dir.cross(Vector3.UP).normalized()
		var t := 0.6
		while t < len - 0.4:
			var p := a + flat * (t / len)
			p.y += y_offset
			var w := width
			var l := 0.85
			var u0 := p - right * w
			var u1 := p + right * w
			var v0 := p - dir * l * 0.5
			var v1 := p + dir * l * 0.5
			kit.begin_part(0.5, 40.0)
			kit.quad("route", [u0 + (v0 - p), u1 + (v0 - p), u1 + (v1 - p), u0 + (v1 - p)],
				Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
			t += gap


# ============================================================== engine =====
func z_engine(parent: Node3D) -> void:
	zone("engine", "ENGINEERING · AFT DRIVE")
	var x0 := -19.0
	var x1 := 19.0
	var z0 := 92.0
	var z1 := 148.0
	var y := cfg.DECK_ENG
	var h := 16.4
	shell(x0, x1, z0, z1, y, h, "wall_struct", "floor_grate",
		[opening("n", 16.0, 3.0)], 0)
	# heavy hazard dado
	kit.begin_part(0.3, 1)
	kit.box("hazard", Vector3(x1 - x0, 0.55, 0.06), Vector3(0, y + 0.62, z0 + 0.04))
	kit.box("metal_dark", Vector3(x1 - x0, 0.10, 0.10), Vector3(0, y + 0.92, z0 + 0.05))
	kit.set_height_range(y, y + h)

	# ---- three main thruster columns ----
	for i in 3:
		var tx := (float(i) - 1.0) * 17.0
		props.engine_thruster(Vector3(tx, y, 137.0), 4.2, 13.5)
		# feed pipes from the aft wall to each thruster
		props.pipe([Vector3(tx - 5.2, y + 1.0, 147.0), Vector3(tx - 5.2, y + 3.2, 144.0),
			Vector3(tx - 4.6, y + 7.0, 140.0), Vector3(tx - 2.4, y + 10.0, 137.0)], 0.42, "pipe_orange")
		props.pipe([Vector3(tx + 5.2, y + 1.0, 147.0), Vector3(tx + 5.2, y + 3.2, 144.0),
			Vector3(tx + 4.6, y + 7.0, 140.0), Vector3(tx + 2.4, y + 10.0, 137.0)], 0.30, "pipe_teal")
		light(Vector3(tx, y + 2.0, 142.0), Color(1.0, 0.42, 0.14), 6.0, 18.0, false)
		light(Vector3(tx, y + 11.0, 137.0), Color(0.6, 0.8, 1.0), 3.2, 12.0, false)
		# support gantry
		for sy in [4.0, 8.0]:
			kit.begin_part(0.4, 20.0)
			kit.box("metal_dark", Vector3(8.4, 0.22, 0.22), Vector3(tx, y + sy, 137.0))
	# ---- side catwalks at two levels ----
	props.catwalk(x0 + 0.9, x0 + 4.4, z0 + 3.0, z1 - 2.0, y + 5.0)
	props.catwalk(x1 - 4.4, x1 - 0.9, z0 + 3.0, z1 - 2.0, y + 5.0)
	props.catwalk(x0 + 0.9, x0 + 4.4, z0 + 3.0, z1 - 2.0, y + 10.0)
	props.catwalk(x1 - 4.4, x1 - 0.9, z0 + 3.0, z1 - 2.0, y + 10.0)
	props.stairs(Vector3(x0 + 3.4, y + 5.0, z0 + 4.0), Vector3(x0 + 3.4, y + 10.0, z0 + 12.0), 1.5)
	props.stairs(Vector3(x1 - 3.4, y + 5.0, z0 + 4.0), Vector3(x1 - 3.4, y + 10.0, z0 + 12.0), 1.5)
	# cross catwalk over the engine centreline
	props.catwalk(x0 + 4.4, x1 - 4.4, 129.0, 131.2, y + 10.0)

	# ---- main deck walkway between the centre and starboard drives ----
	kit.begin_part(0.35, 20.0)
	kit.box("hazard_worn", Vector3(2.6, 0.04, 22.0), Vector3(8.5, y + 0.03, 135.0))
	for sx in [-1.0, 1.0]:
		props.railing(Vector3(8.5 + sx * 1.35, y, 125.0), Vector3(8.5 + sx * 1.35, y, 146.0), 1.05)
	# ---- fuel tanks, pumps, consoles ----
	props.tank(Vector3(-15.0, y + 3.2, 108.0), 2.4, 6.0, "metal_painted")
	props.tank(Vector3(15.0, y + 3.2, 108.0), 2.4, 6.0, "metal_painted")
	props.tank(Vector3(-15.0, y + 3.2, 100.0), 2.4, 6.0, "pipe_teal")
	props.tank(Vector3(15.0, y + 3.2, 100.0), 2.4, 6.0, "pipe_teal")
	for i in 4:
		var px := -15.0 if i < 2 else 15.0
		var pz := 104.0 + float(i % 2) * 8.0
		kit.begin_part(0.5, 25.0)
		kit.cyl("metal_cast", 0.55, 0.55, 1.2, 14, Vector3(px + (4.0 if px > 0 else -4.0), y + 0.6, pz))
		props.pipe([Vector3(px, y + 5.0, pz), Vector3(px + (2.0 if px > 0 else -2.0), y + 4.0, pz),
			Vector3(px + (4.0 if px > 0 else -4.0), y + 1.6, pz)], 0.24, "pipe_cream", true, 2.0)
	# engine control station near the stair
	props.console(Vector3(9.0, y, 96.2), PI, 2.6, "screen_eng")
	props.chair(Vector3(9.0, y, 94.9), PI)
	props.console(Vector3(12.6, y, 96.2), PI, 1.8, "screen_power")
	kit.begin_part(0.5, 22.0)
	kit.box("metal_dark", Vector3(7.0, 0.06, 2.2), Vector3(9.0, y + 2.2, 104.0))
	kit.box("emit_cool", Vector3(6.6, 0.06, 0.5), Vector3(9.0, y + 2.18, 104.0))
	# wall hazard placards / warning beacons
	for i in 5:
		var zz := 100.0 + i * 9.0
		props.sign_board("DRIVE BAY " + str(i + 1), Vector3(x0 + 0.25, y + 3.4, zz), PI * 0.5, 1.5, 0.5,
			Color(1.0, 0.6, 0.25))
		kit.begin_part(0.7, 41.0)
		kit.box("emit_amber", Vector3(0.15, 0.15, 0.15), Vector3(x0 + 0.3, y + 4.4, zz + 3.0))
	# floor grate detail strips + drain
	kit.begin_part(0.4, 20.0)
	for i in 8:
		kit.box("metal_cast", Vector3(28.0, 0.08, 0.30), Vector3(0, y + 0.04, 100.0 + i * 5.0))
	# signage
	props.sign_board("ENGINEERING  ·  AFT DRIVE", Vector3(0, y + 12.2, z0 + 0.3), 0, 4.4, 0.9,
		Color(1.0, 0.62, 0.28))
	props.sign_board("CAUTION  ·  THRUSTER FIELD", Vector3(0, y + 2.6, z0 + 0.3), 0, 3.6, 0.55,
		Color(1.0, 0.45, 0.15))
	# overhead work lights
	light(Vector3(0, y + 6.0, 120.0), Color(0.85, 0.92, 1.0), 10.0, 26.0, true)
	light(Vector3(0, y + 13.0, 108.0), Color(1.0, 0.55, 0.25), 7.0, 22.0, false)
	light(Vector3(7.6, y + 9.0, 102.0), Color(0.80, 0.90, 1.0), 8.0, 22.0, false)
	light(Vector3(-14.0, y + 7.0, 112.0), Color(0.75, 0.88, 1.0), 7.0, 20.0, false)
	light(Vector3(0, y + 2.5, 128.0), Color(1.0, 0.55, 0.3), 5.0, 18.0, false)
	light(Vector3(8.5, y + 9.0, 138.0), Color(0.7, 0.85, 1.0), 8.0, 20.0, true)
	light(Vector3(0, y + 8.0, 144.0), Color(0.85, 0.92, 1.0), 6.0, 16.0, false)
	light(Vector3(-7.0, y + 4.0, 140.0), Color(1.0, 0.72, 0.45), 4.0, 12.0, false)
	light(Vector3(15.0, y + 5.5, 96.0), Color(0.9, 0.95, 1.0), 2.4, 12.0, false)
	door_at("n", 16.0, x0, x1, z0, z1, y, 2.4, 2.4, 0.45)
	rd.setup("engine", zone_wear, zone_variant)
	rd.engine_extras(-19.0, 19.0, 92.0, 148.0, y, h, zone_variant)
	commit_zone("EngineBay")


func z_stair_a(parent: Node3D) -> void:
	zone("stair_a", "MAINTENANCE STAIR")
	var x0 := 13.0
	var x1 := 18.8
	var z0 := 82.0
	var z1 := 92.0
	var y := -20.0
	var h := 8.0
	shell(x0, x1, z0, z1, y, h, "wall_struct", "floor_grate",
		[opening("s", 16.0, 2.4, 0.0, 2.4)], 0)
	# stairs from -20 at z=90.5 up to -12 at z=84.0
	props.stairs(Vector3(16.0, y, 90.5), Vector3(16.0, y + 8.0, 84.0), 2.0)
	props.ladder(Vector3(x0 + 0.6, y, 84.0), Vector3(x0 + 0.6, y + 7.6, 84.0))
	for i in 3:
		props.light_fixture(Vector3(16.0, y + h - 0.3, 84.0 + i * 3.2), Vector2(0.9, 0.26), "emit_white")
	light(Vector3(16.0, y + 6.6, 87.0), Color(1.0, 0.8, 0.55), 2.2, 8.0, true)
	props.sign_board("DECK C  ↑  CARGO 02", Vector3(16.0, y + 5.0, z0 + 0.3), 0, 2.4, 0.45,
		Color(0.4, 1.0, 0.55))
	door_at("s", 16.0, x0, x1, z0, z1, y, 2.2, 2.4, 0.5)
	# landing door at the top is cut into the cargo aft wall
	commit_zone("StairA")


func z_cargo(parent: Node3D) -> void:
	zone("cargo", "CARGO HOLD 2")
	var x0 := -28.0
	var x1 := 28.0
	var z0 := 42.0
	var z1 := 82.0
	var y := cfg.DECK_LOW
	var h := 7.4
	shell(x0, x1, z0, z1, y, h, "wall", "floor",
		[opening("n", 0.0, 5.0, 0.0, 4.6), opening("s", 16.0, 2.4, 0.0, 2.4),
		 opening("s", -16.0, 3.0, 0.0, 3.0)], 0)
	# cavernous roller doors
	kit.begin_part(0.3, 1)
	for side in [z0, z1]:
		kit.box("metal_dark", Vector3(10.4, 5.0, 0.35), Vector3(0, y + 2.5, side + (0.2 if side == z0 else -0.2)))
		kit.box("hazard", Vector3(10.0, 0.22, 0.4), Vector3(0, y + 4.9, side + (0.2 if side == z0 else -0.2)))
		for i in 5:
			kit.box("metal", Vector3(9.6, 0.10, 0.42), Vector3(0, y + 0.6 + i * 0.85, side + (0.2 if side == z0 else -0.2)))
	props.sign_board("CARGO 02  ·  PRESSURISED", Vector3(0, y + 5.6, z0 + 0.35), 0, 4.0, 0.8,
		Color(0.45, 0.85, 1.0))
	# container stacks in two rows, offset aisles
	var stack_keys := ["container_a", "container_b", "container_c", "container_d"]
	for row in 2:
		var bx := -17.0 if row == 0 else 12.0
		for i in 4:
			var bz := z0 + 6.0 + i * 7.0
			props.container(Vector3(bx, y, bz), stack_keys[(row * 3 + i) % 4], 0.0)
			if i % 2 == 0:
				props.container(Vector3(bx, y + 2.6, bz), stack_keys[(row * 3 + i + 1) % 4], 0.0)
			# lashing bars
			kit.begin_part(0.3, 24.0)
			kit.box("metal_dark", Vector3(0.10, 5.2, 0.10), Vector3(bx - 3.1, y + 2.6, bz - 1.3))
			kit.box("metal_dark", Vector3(0.10, 5.2, 0.10), Vector3(bx + 3.1, y + 2.6, bz + 1.3))
	for i in 8:
		var cxx := -23.0 + float(i % 4) * 2.6
		var czz := z0 + 4.0 + float(i / 4) * 24.0
		props.crate(Vector3(cxx, y, czz), Vector3(1.1, 1.0, 0.9), "metal_painted", 0.2 * i)
	# pallets and a load cart in the central aisle
	for i in 3:
		var pz := z0 + 10.0 + i * 8.0
		props.crate(Vector3(-4.6, y, pz), Vector3(1.3, 0.9, 1.1), "container_c", 0.1 + i * 0.2)
		props.crate(Vector3(4.4, y, pz + 2.0), Vector3(0.9, 0.7, 0.8), "metal_painted", 0.4 + i)
	kit.begin_part(0.5, 64.0)
	kit.box("metal_dark", Vector3(2.4, 0.5, 1.3), Vector3(-5.2, y + 0.35, z0 + 27.0))
	kit.box("hazard", Vector3(2.5, 0.08, 1.4), Vector3(-5.2, y + 0.62, z0 + 27.0))
	for sx in [-1.0, 1.0]:
		kit.cyl("rubber", 0.28, 0.28, 0.22, 12, Vector3(-5.2 + sx * 1.0, y + 0.28, z0 + 26.4))
		kit.cyl("rubber", 0.28, 0.28, 0.22, 12, Vector3(-5.2 + sx * 1.0, y + 0.28, z0 + 27.6))
	kit.cyl("metal_dark", 0.07, 0.07, 1.1, 8, Vector3(-6.4, y + 1.1, z0 + 27.0))
	# overhead crane gantry
	kit.begin_part(0.45, 20.0)
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.4, 0.6, z1 - z0 - 2.0), Vector3(sx * 22.0, y + 6.4, (z0 + z1) * 0.5))
	kit.box("metal_dark", Vector3(44.0, 0.35, 1.1), Vector3(0, y + 6.5, 58.0))
	kit.box("metal_cast", Vector3(1.6, 1.2, 1.6), Vector3(6.0, y + 5.7, 58.0))
	kit.tube("metal", [Vector3(6.0, y + 5.1, 58.0), Vector3(6.0, y + 3.4, 58.0)], 0.07, 6)
	kit.box("metal_dark", Vector3(1.0, 0.12, 0.5), Vector3(6.0, y + 3.3, 58.0))
	for k in 5:
		kit.box("emit_amber", Vector3(0.2, 0.12, 0.2), Vector3(-22.0, y + 6.0, z0 + 5.0 + k * 8.0))
	# floor markings
	kit.begin_part(0.5, 40.0)
	kit.box("hazard_worn", Vector3(0.22, 0.02, z1 - z0 - 6.0), Vector3(-6.0, y + 0.02, (z0 + z1) * 0.5))
	kit.box("hazard_worn", Vector3(0.22, 0.02, z1 - z0 - 6.0), Vector3(6.0, y + 0.02, (z0 + z1) * 0.5))
	for i in 5:
		kit.box("metal_dark", Vector3(9.0, 0.02, 0.18), Vector3(0, y + 0.025, z0 + 6.0 + i * 7.0))
	# side consoles + cargo control booth
	props.console(Vector3(-24.5, y, 45.0), 0.0, 2.2, "screen_log")
	props.console(Vector3(24.5, y, 45.0), PI, 2.2, "screen_power")
	kit.begin_part(0.5, 22.0)
	kit.box("metal_dark", Vector3(6.0, 0.1, 3.0), Vector3(-24.0, y + 3.0, 76.0))
	kit.box("glass", Vector3(5.6, 1.4, 0.05), Vector3(-24.0, y + 3.7, 74.5))
	light(Vector3(0, y + 6.0, 46.0), Color(0.9, 0.95, 1.0), 5.0, 18.0, true)
	light(Vector3(0, y + 6.0, 60.0), Color(0.9, 0.95, 1.0), 5.0, 18.0, false)
	light(Vector3(0, y + 6.0, 74.0), Color(0.9, 0.95, 1.0), 5.0, 18.0, false)
	light(Vector3(-17.0, y + 3.5, 58.0), Color(1.0, 0.62, 0.3), 2.4, 10.0, false)
	light(Vector3(12.0, y + 3.5, 70.0), Color(1.0, 0.62, 0.3), 2.4, 10.0, false)
	props.sign_board("BAY 2  ·  BULK CARGO", Vector3(x0 + 0.3, y + 4.2, 62.0), PI * 0.5, 2.8, 0.6,
		Color(0.5, 0.85, 1.0))
	door_at("n", 0.0, x0, x1, z0, z1, y, 5.0, 4.6, 0.85, "metal_painted")
	door_at("s", 16.0, x0, x1, z0, z1, y, 2.4, 2.4, 0.4)
	door_at("s", -16.0, x0, x1, z0, z1, y, 3.0, 3.0, 0.6, "metal_painted")
	rd.setup("cargo", zone_wear, zone_variant)
	rd.cargo_extras(-28.0, 28.0, 42.0, 82.0, y, 7.4, zone_variant)
	commit_zone("CargoHold")


func z_corr_aft(parent: Node3D) -> void:
	zone("corr_aft", "SERVICE SPINE · AFT")
	var x0 := -cfg.corridor_w * 0.5
	var x1 := cfg.corridor_w * 0.5
	var z0 := 16.0
	var z1 := 42.0
	var y := cfg.DECK_LOW
	var h := 4.4
	var opens: Array = [opening("n", 0.0, 5.0, 0.0, 4.2)]
	for i in 3:
		opens.append(opening("w", z0 + 6.0 + i * 8.0, 2.0))
		if i < 2:
			opens.append(opening("e", z0 + 10.0 + i * 8.0, 2.0))
	shell(x0, x1, z0, z1, y, h, "wall", "floor", opens, 0)
	# the corridor is a stack of ribs with services
	for i in 6:
		var z := z0 + 2.4 + i * 4.0
		kit.begin_part(0.3, 1)
		kit.box("metal_dark", Vector3(0.30, 0.55, 0.42), Vector3(x0 + 0.2, y + 3.2, z))
		kit.box("metal_dark", Vector3(0.30, 0.55, 0.42), Vector3(x1 - 0.2, y + 3.2, z))
		kit.box("emit_strip_cool", Vector3(x1 - x0 - 0.8, 0.10, 0.10), Vector3(0, y + h - 0.28, z))
	# ceiling pipe bundle
	props.pipe([Vector3(x0 + 0.55, y + h - 0.55, z0 + 1.0), Vector3(x0 + 0.55, y + h - 0.55, z1 - 1.0)],
		0.14, "pipe_orange", true, 3.5)
	props.pipe([Vector3(x0 + 0.95, y + h - 0.42, z0 + 1.0), Vector3(x0 + 0.95, y + h - 0.42, z1 - 1.0)],
		0.10, "pipe_cream", true, 3.5)
	props.pipe([Vector3(x1 - 0.7, y + h - 0.55, z0 + 1.0), Vector3(x1 - 0.7, y + h - 0.55, z1 - 1.0)],
		0.12, "pipe_teal", true, 4.0)
	# wall lockers / extinguishers / signs
	for i in 3:
		var z := z0 + 6.0 + i * 8.0
		props.door(Vector3(x0 + 0.03, y, z), PI * 0.5, 2.0, 2.2, 0.2, "metal_painted")
		props.sign_board("UTILITY " + str(31 + i), Vector3(x0 + 0.12, y + 2.95, z), PI * 0.5, 1.6, 0.34,
			Color(1.0, 0.55, 0.2))
		if i < 2:
			props.door(Vector3(x1 - 0.03, y, z0 + 10.0 + i * 8.0), PI * 0.5, 2.0, 2.2, 0.45)
	props.console(Vector3(x1 - 0.7, y, 22.5), -PI * 0.5, 1.4, "screen_log")
	kit.begin_part(0.4, 29.0)
	kit.box("emit_green", Vector3(0.2, 0.1, 0.2), Vector3(x1 - 0.35, y + 3.9, 22.5))
	# door to cargo & vestibule
	door_at("n", 0.0, x0, x1, z0, z1, y, 5.0, 4.2, 0.8, "metal_painted")
	door_at("s", 0.0, x0, x1, z0, z1, y, 2.4, 2.4, 0.5)
	props.sign_board("MAIN SPINE  ↑   DECK B", Vector3(0, y + 3.6, z1 - 0.3), PI, 3.0, 0.6,
		Color(0.4, 1.0, 0.55))
	chevrons([Vector3(0, y, 40), Vector3(0, y, 18)], 0.03, 0.45, 3.4)
	for i in 4:
		props.light_fixture(Vector3(0, y + h - 0.3, z0 + 3.0 + i * 6.0), Vector2(1.6, 0.3), "emit_white")
		light(Vector3(0, y + 3.4, z0 + 3.0 + i * 6.0), Color(0.85, 0.92, 1.0), 1.8, 7.0, i == 1)
	rd.setup("corr_aft", zone_wear, zone_variant)
	rd.corridor_life(x0, x1, z0, z1, y, h, zone_variant)
	commit_zone("CorrAft")


func z_vestibule(parent: Node3D) -> void:
	zone("vestibule", "DECK TRANSFER")
	var x0 := -5.2
	var x1 := 5.2
	var z0 := 4.0
	var z1 := 16.0
	var y := cfg.DECK_LOW
	var h := 8.6
	shell(x0, x1, z0, z1, y, h, "wall", "floor",
		[opening("s", 0.0, 2.4, 0.0, 2.4), opening("n", 2.2, 2.4, 8.0, 10.4)], 0)
	# two-storey transfer hall: mezzanine at deck B
	kit.begin_part(0.4, 20.0)
	kit.box("floor", Vector3(3.6, 0.35, 4.0), Vector3(3.4, cfg.DECK_MAIN - 0.18, 9.0))
	props.railing(Vector3(1.6, cfg.DECK_MAIN, 7.0), Vector3(1.6, cfg.DECK_MAIN, 11.0), 1.05)
	props.railing(Vector3(1.6, cfg.DECK_MAIN, 7.0), Vector3(5.2, cfg.DECK_MAIN, 7.0), 1.05)
	props.stairs(Vector3(3.4, y, 14.6), Vector3(3.4, cfg.DECK_MAIN, 10.9), 2.0)
	# upper landing / sign
	props.sign_board("DECK B  ·  MAIN SPINE", Vector3(2.2, cfg.DECK_MAIN + 2.7, z0 + 0.3), 0, 2.6, 0.5,
		Color(0.4, 1.0, 0.55))
	# warning stripes on the stair edge
	kit.begin_part(0.55, 41.0)
	kit.box("hazard", Vector3(0.18, 0.05, 5.4), Vector3(1.9, cfg.DECK_MAIN + 0.03, 12.2))
	# service pipes in the tall shaft
	props.pipe([Vector3(x0 + 0.5, y + 0.4, z1 - 0.5), Vector3(x0 + 0.5, y + 6.2, z1 - 0.5),
		Vector3(x0 + 0.5, y + 7.8, z1 - 1.4)], 0.22, "pipe_orange")
	props.pipe([Vector3(x1 - 0.5, y + 0.4, z1 - 0.5), Vector3(x1 - 0.5, y + 6.2, z1 - 0.5),
		Vector3(x1 - 0.5, y + 7.8, z1 - 1.4)], 0.16, "pipe_teal")
	light(Vector3(0, y + 8.0, 10.0), Color(0.9, 0.95, 1.0), 3.2, 12.0, true)
	light(Vector3(3.0, cfg.DECK_MAIN + 2.6, 14.0), Color(0.4, 1.0, 0.6), 1.6, 7.0, false)
	door_at("s", 0.0, x0, x1, z0, z1, y, 2.4, 2.4, 0.5)
	commit_zone("Vestibule")


func z_spine(parent: Node3D) -> void:
	zone("spine", "MAIN SPINE · DECK B")
	var x0 := -cfg.corridor_w * 0.5
	var x1 := cfg.corridor_w * 0.5
	var z0 := -24.0
	var z1 := 4.0
	var y := cfg.DECK_MAIN
	var h := 4.6
	var opens: Array = [opening("s", 2.2, 2.4, 0.0, 2.4), opening("n", 0.0, 6.0, 0.0, 4.4)]
	for i in 2:
		opens.append(opening("w", -6.0 - i * 8.0, 2.0))
		opens.append(opening("e", -6.0 - i * 8.0, 2.0))
	shell(x0, x1, z0, z1, y, h, "wall", "floor", opens, 0)
	for i in 6:
		var z := z0 + 2.5 + i * 4.4
		kit.begin_part(0.3, 1)
		kit.box("metal_dark", Vector3(x1 - x0 + 0.1, 0.22, 0.30), Vector3(0, y + 3.55, z))
		kit.box("emit_strip_cool", Vector3(x1 - x0 - 0.6, 0.05, 0.08), Vector3(0, y + 3.42, z))
	kit.begin_part(0.42, 1)
	kit.box("metal_dark", Vector3(0.8, 0.32, z1 - z0 - 1.0), Vector3(0, y + h - 0.5, (z0 + z1) * 0.5))
	kit.box("emit_white", Vector3(0.6, 0.06, z1 - z0 - 1.4), Vector3(0, y + h - 0.66, (z0 + z1) * 0.5))
	props.pipe([Vector3(x0 + 0.5, y + h - 0.45, z0 + 0.5), Vector3(x0 + 0.5, y + h - 0.45, z1 - 0.5)],
		0.12, "pipe_teal", true, 3.0)
	props.pipe([Vector3(x1 - 0.5, y + h - 0.4, z0 + 0.5), Vector3(x1 - 0.5, y + h - 0.4, z1 - 0.5)],
		0.10, "pipe_orange", true, 3.0)
	for i in 2:
		var z := -6.0 - i * 8.0
		props.door(Vector3(x0 + 0.02, y, z), PI * 0.5, 2.0, 2.2, 0.25, "metal_painted")
		props.sign_board("MEDBAY" if i == 0 else "SUPPLY", Vector3(x0 + 0.12, y + 2.9, z), PI * 0.5,
			1.5, 0.34, Color(0.4, 0.9, 1.0) if i == 0 else Color(1.0, 0.6, 0.25))
		props.door(Vector3(x1 - 0.02, y, z), PI * 0.5, 2.0, 2.2, 0.4)
	# wall screens / niches
	for i in 3:
		var z := -3.0 - i * 7.0
		kit.begin_part(0.55, 29.0)
		kit.box("metal_dark", Vector3(0.14, 0.9, 1.5), Vector3(x1 - 0.12, y + 2.0, z))
		kit.box("screen_nav" if i == 0 else "screen_log", Vector3(0.02, 0.74, 1.34),
			Vector3(x1 - 0.20, y + 2.0, z))
		kit.box("emit_cool", Vector3(0.05, 0.05, 1.1), Vector3(x1 - 0.18, y + 2.55, z))
	# junction arch into the reactor
	kit.begin_part(0.45, 41.0)
	kit.box("metal_dark", Vector3(x1 - x0 + 0.6, 0.5, 0.7), Vector3(0, y + 4.1, z0 + 0.5))
	kit.box("hazard", Vector3(x1 - x0, 0.3, 0.3), Vector3(0, y + 3.8, z0 + 0.75))
	props.sign_board("REACTOR  →", Vector3(0, y + 3.2, z0 + 0.85), 0, 2.0, 0.42,
		Color(0.4, 0.9, 1.0))
	chevrons([Vector3(0, y, 2.0), Vector3(0, y, -22.0)], 0.03, 0.45, 4.0)
	for i in 5:
		props.light_fixture(Vector3(0, y + h - 0.28, 2.0 - i * 5.0), Vector2(2.2, 0.26), "emit_white")
		light(Vector3(0, y + 3.5, 1.0 - i * 5.5), Color(0.88, 0.94, 1.0), 1.7, 7.5, i == 2)
	door_at("s", 2.2, x0, x1, z0, z1, y, 2.4, 2.4, 0.5)
	door_at("n", 0.0, x0, x1, z0, z1, y, 6.0, 4.4, 0.7, "metal_painted")
	rd.setup("spine", zone_wear, zone_variant)
	rd.footprints(Vector3(0, y, 2.0), Vector3(0, y, -22.0), 20)
	rd.tape_line(Vector3(x0 + 0.55, y, z1 - 2.0), Vector3(x0 + 0.55, y, z0 + 2.0), 0.05)
	rd.stain(2, Vector3(1.2, y, -8.0), 1.2, 0.8, 0.3)
	rd.cable_coil(Vector3(x1 - 0.7, y, z0 + 3.0), 0.28, 3)
	commit_zone("Spine")

func z_reactor(parent: Node3D) -> void:
	zone("reactor", "REACTOR HALL")
	var x0 := -20.0
	var x1 := 20.0
	var z0 := -54.0
	var z1 := -24.0
	var y := cfg.DECK_MAIN
	var h := 13.2
	var ceil := y + h
	shell(x0, x1, z0, z1, y, h, "wall_dark", "floor_dark", [
		opening("n", 0.0, 6.0, 0.0, 4.6),
		opening("s", 0.0, 6.0, 0.0, 4.4),
		opening("w", -40.0, 2.2, 0.0, 2.2),
		opening("e", -38.0, 2.2, 0.0, 2.2),
	], 0)

	# ---------------- core pedestal + torus + plasma ----------------
	kit.begin_part(0.4, 50.0)
	kit.set_height_range(y, ceil)
	kit.cyl("metal_cast", 6.0, 5.2, 1.2, 40, Vector3(0, y, -39.0))
	kit.torus("metal_dark", 5.15, 0.12, 40, 6, Vector3(0, y + 1.22, -39.0))
	for k in 8:
		var a := TAU * float(k) / 8.0
		kit.box("metal_dark", Vector3(1.1, 0.6, 0.4),
			Vector3(cos(a) * 5.7, y + 1.5, -39.0 + sin(a) * 5.7))
	# support struts
	for k in 6:
		var a := TAU * float(k) / 6.0 + 0.2
		props.beam("metal_dark", Vector3(cos(a) * 4.4, y + 1.0, -39.0 + sin(a) * 4.4),
			Vector3(cos(a) * 5.2, y + 6.2, -39.0 + sin(a) * 5.2), 0.32, 0.32)
	# reactor torus
	kit.begin_part(0.5, 51.0)
	kit.torus("metal", 5.2, 1.0, 48, 14, Vector3(0, y + 6.6, -39.0))
	kit.torus("metal_dark", 5.2, 0.18, 48, 8, Vector3(0, y + 6.6, -39.0))
	kit.torus("emit_seg_blue", 6.55, 0.09, 48, 6, Vector3(0, y + 6.6, -39.0))
	# glowing core
	kit.sphere("plasma_reactor", 2.6, 32, Vector3(0, y + 6.6, -39.0))
	kit.sphere("holo_soft", 3.0, 24, Vector3(0, y + 6.6, -39.0))
	# containment cage
	for k in 10:
		var a := TAU * float(k) / 10.0
		props.beam("metal_dark", Vector3(cos(a) * 7.0, y + 1.2, -39.0 + sin(a) * 7.0),
			Vector3(cos(a) * 7.0, ceil - 0.8, -39.0 + sin(a) * 7.0), 0.24, 0.24)
	kit.begin_part(0.6, 52.0)
	for yy in [y + 3.0, y + 9.4]:
		kit.torus("metal", 7.0, 0.12, 40, 6, Vector3(0, yy, -39.0))

	# ---------------- catwalk ring + stairs ----------------
	props.catwalk(-9.0, 9.0, -45.0, -43.6, y + 3.3)
	props.catwalk(-9.0, 9.0, -34.4, -33.0, y + 3.3)
	props.catwalk(-9.0, -7.6, -45.0, -33.0, y + 3.3)
	props.catwalk(7.6, 9.0, -45.0, -33.0, y + 3.3)
	props.stairs(Vector3(-11.5, y, -31.0), Vector3(-11.5, y + 3.3, -34.0), 1.6)
	props.stairs(Vector3(11.5, y, -31.0), Vector3(11.5, y + 3.3, -34.0), 1.6)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		props.light_fixture(Vector3(cos(a) * 5.6, y + 3.25, -39.0 + sin(a) * 5.6), Vector2(0.8, 0.25), "emit_cool")
	# ---------------- coolant plant ----------------
	for sx in [-1.0, 1.0]:
		for k in 2:
			var px: float = sx * 15.5
			var pz := -33.0 - k * 11.0
			props.tank(Vector3(px, y + 3.4, pz), 2.2, 6.2, "metal_light")
			props.pipe([Vector3(px, y + 6.8, pz), Vector3(px - sx * 2.2, y + 6.2, pz),
				Vector3(px - sx * 3.6, y + 2.6, pz - 2.0)], 0.30, "pipe_teal")
			kit.begin_part(0.45, 25.0)
			kit.box("metal_dark", Vector3(2.4, 0.5, 2.4), Vector3(px - sx * 2.6, y + 0.25, pz + 2.8))
			kit.cyl("metal_cast", 0.6, 0.6, 0.8, 14, Vector3(px - sx * 2.6, y + 0.5, pz + 2.8))
	# consoles facing the core
	for i in 3:
		props.console(Vector3(-5.0 + i * 5.0, y, -27.2), PI, 2.4, "screen_eng")
		props.chair(Vector3(-5.0 + i * 5.0, y, -26.0), PI)
	# big wall displays
	for side in [-1.0, 1.0]:
		kit.begin_part(0.55, 29.0)
		kit.box("metal_dark", Vector3(0.16, 3.4, 8.0), Vector3(side * 19.6, y + 6.0, -39.0))
		kit.box("screen_power", Vector3(0.03, 3.0, 7.4), Vector3(side * 19.5, y + 6.0, -39.0))
		kit.box("emit_strip_cool", Vector3(0.06, 0.08, 7.4), Vector3(side * 19.45, y + 7.6, -39.0))
	# warning beacons
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.2
		kit.begin_part(0.7, 41.0)
		kit.box("emit_amber", Vector3(0.25, 0.25, 0.25),
			Vector3(cos(a) * 12.0, y + 10.4, -39.0 + sin(a) * 12.0))
		light(Vector3(cos(a) * 12.0, y + 10.4, -39.0 + sin(a) * 12.0),
			Color(1.0, 0.45, 0.1), 2.2, 8.0, false)
	# floor markings and route
	kit.begin_part(0.5, 40.0)
	kit.box("hazard", Vector3(12.0, 0.03, 0.2), Vector3(0, y + 0.025, -28.6))
	kit.box("hazard", Vector3(12.0, 0.03, 0.2), Vector3(0, y + 0.025, -49.4))
	chevrons([Vector3(7.0, y, -25.0), Vector3(7.0, y, -31.0), Vector3(7.0, y, -48.0), Vector3(7.0, y, -53.0)], 0.03, 0.42, 3.6)
	props.sign_board("REACTOR HALL  ·  MK IV TOROIDAL", Vector3(0, y + 11.4, z0 + 0.4), 0, 5.0, 1.0,
		Color(0.4, 0.85, 1.0))
	props.sign_board("RADIATION  ·  CONTAINMENT ACTIVE", Vector3(0, y + 2.9, -25.0), PI, 3.4, 0.5,
		Color(1.0, 0.5, 0.15))
	# lighting
	light(Vector3(0, y + 6.2, -39.0), Color(0.45, 0.75, 1.0), 10.0, 20.0, true)
	light(Vector3(-10.0, y + 9.0, -32.0), Color(0.55, 0.8, 1.0), 7.0, 18.0, false)
	light(Vector3(10.0, y + 9.0, -46.0), Color(0.55, 0.8, 1.0), 7.0, 18.0, false)
	light(Vector3(0, y + 10.0, -51.0), Color(0.8, 0.9, 1.0), 5.0, 16.0, false)
	door_at("n", 0.0, x0, x1, z0, z1, y, 6.0, 4.6, 0.7, "metal_painted")
	door_at("s", 0.0, x0, x1, z0, z1, y, 6.0, 4.4, 0.7, "metal_painted")
	rd.setup("reactor", zone_wear, zone_variant)
	rd.reactor_extras(-20.0, 20.0, -54.0, -24.0, y, h, zone_variant)
	commit_zone("ReactorHall")


# ============================================================== atrium =====
func escalator(a: Vector3, b: Vector3, width: float) -> void:
	var d := b - a
	var run := Vector3(d.x, 0, d.z)
	var len := run.length()
	if len < 1.0:
		return
	var dir := run / len
	var right := dir.cross(Vector3.UP).normalized()
	var steps := maxi(8, int(absf(d.y) / 0.22))
	kit.begin_part(0.42, 53.0)
	kit.set_height_range(a.y, b.y)
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var p := a + run * t0
		p.y += d.y * t0
		var step := 0.30
		kit.box("metal", Vector3(width, 0.20, step), p + Vector3(0, 0.12, 0))
		if i % 2 == 0:
			kit.box("hazard_worn", Vector3(width, 0.02, step * 0.5), p + Vector3(0, 0.23, 0))
	# side skirts + glass balustrades
	for sx in [-1.0, 1.0]:
		var off: Vector3 = right * (width * 0.5 + 0.12) * sx
		props.beam("metal_dark", a + off + Vector3(0, 0.35, 0), b + off + Vector3(0, 0.35, 0), 0.08, 0.7)
		props.glass_panel(a + off + Vector3(0, 1.25, 0) + run * 0.5 + Vector3(0, d.y * 0.5, 0),
			len * 0.92, 0.9, atan2(-dir.z, dir.x), true)
		props.beam("metal", a + off + Vector3(0, 1.25, 0), b + off + Vector3(0, 1.25, 0), 0.06, 0.06)
	# end landings
	kit.box("floor", Vector3(width + 0.8, 0.25, 1.4), a + dir * -0.7 + Vector3(0, -0.12, 0))
	kit.box("floor", Vector3(width + 0.8, 0.25, 1.4), b + dir * 0.7 + Vector3(0, -0.12, 0))


func z_atrium(parent: Node3D) -> void:
	zone("atrium", "CENTRAL GALLERIA")
	var x0 := -18.0
	var x1 := 18.0
	var z0 := -92.0
	var z1 := -58.0
	var y := cfg.DECK_MAIN
	var h := 20.0
	var ceil := y + h   # +16
	shell(x0, x1, z0, z1, y, h, "wall_atrium", "floor_warm", [
		opening("n", 0.0, 5.0, 4.0, 8.0),
		opening("s", 0.0, 5.6, 0.0, 4.4),
		opening("w", -70.0, 2.2, 0.0, 2.4),
		opening("w", -84.0, 2.2, 0.0, 2.4),
		opening("e", -70.0, 2.2, 0.0, 2.4),
	], 2, true)

	# ---------------- ceilings & skylight well ----------------
	kit.begin_part(0.4, 2)
	kit.set_height_range(y, ceil)
	# slab ring around the light well
	kit.box("wall_dark", Vector3(36.0, 0.4, 8.0), Vector3(0, ceil + 0.2, -88.0))
	kit.box("wall_dark", Vector3(36.0, 0.4, 8.0), Vector3(0, ceil + 0.2, -62.0))
	kit.box("wall_dark", Vector3(12.0, 0.4, 10.0), Vector3(-12.0, ceil + 0.2, -75.0))
	kit.box("wall_dark", Vector3(12.0, 0.4, 10.0), Vector3(12.0, ceil + 0.2, -75.0))
	# light well: metal frame rising to a glass skylight at +19
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.4, 3.2, 18.0), Vector3(sx * 6.0, ceil + 1.6, -75.0))
		kit.box("metal_dark", Vector3(0.4, 3.2, 0.5), Vector3(sx * 6.0, ceil + 1.6, -84.0))
	kit.box("metal_dark", Vector3(12.0, 3.2, 0.4), Vector3(0, ceil + 1.6, -84.0))
	kit.box("metal_dark", Vector3(12.0, 3.2, 0.4), Vector3(0, ceil + 1.6, -66.0))
	# glass roof panels
	kit.begin_part(0.7, 21.0)
	for i in 6:
		var zz := -84.0 + 3.0 + i * 3.0
		kit.box("glass", Vector3(11.6, 0.06, 3.0), Vector3(0, ceil + 3.2, zz))
	for i in 5:
		kit.box("metal_dark", Vector3(12.0, 0.18, 0.14), Vector3(0, ceil + 3.22, -84.0 + i * 4.5))
	# trusses across the whole atrium
	kit.begin_part(0.45, 2)
	for i in 9:
		var zz := -90.0 + i * 4.0
		kit.box("metal_dark", Vector3(36.0, 0.45, 0.28), Vector3(0, ceil - 0.5, zz))
		if i % 2 == 0:
			for sx in [-1.0, 1.0]:
				props.beam("metal_dark", Vector3(sx * 12.0, ceil - 0.5, zz),
					Vector3(sx * 6.0, ceil - 2.6, zz), 0.12, 0.12)
	# central catenary light rings
	for i in 3:
		var zz := -80.0 + i * 6.0
		kit.torus("metal_dark", 3.4, 0.10, 32, 6, Vector3(0, ceil - 3.2, zz))
		kit.torus("emit_warm", 3.2, 0.06, 32, 4, Vector3(0, ceil - 3.24, zz))
		props.beam("metal_dark", Vector3(0, ceil - 0.4, zz), Vector3(0, ceil - 3.2, zz), 0.08, 0.08)

	# ---------------- gallery decks ----------------
	for side in [-1.0, 1.0]:
		# level 1
		kit.begin_part(0.35, 54.0)
		kit.box("floor_warm", Vector3(9.0, 0.4, 28.0), Vector3(side * 13.5, y + 8.2, -74.0))
		kit.box("metal_dark", Vector3(9.0, 0.55, 0.3), Vector3(side * 13.5, y + 8.0, -60.0))
		kit.box("metal_dark", Vector3(0.3, 0.7, 28.0), Vector3(side * 9.0, y + 8.1, -74.0))
		props.railing(Vector3(side * 9.0, y + 8.4, -60.0), Vector3(side * 9.0, y + 8.4, -88.0), 1.1)
		kit.box("emit_strip_warm", Vector3(0.10, 0.06, 27.0), Vector3(side * 9.3, y + 7.7, -74.0))
		kit.box("emit_strip_warm", Vector3(0.10, 0.06, 23.0), Vector3(side * 9.3, y + 15.7, -74.0))
		# level 2
		kit.begin_part(0.35, 54.0)
		kit.box("floor_warm", Vector3(8.0, 0.4, 24.0), Vector3(side * 13.0, y + 16.2, -74.0))
		kit.box("metal_dark", Vector3(0.3, 0.7, 24.0), Vector3(side * 9.0, y + 16.1, -74.0))
		props.railing(Vector3(side * 9.0, y + 16.4, -62.0), Vector3(side * 9.0, y + 16.4, -86.0), 1.1)
	# level 1 landing bridge at the forward end (leads to hydro)
	kit.begin_part(0.35, 54.0)
	kit.box("floor_warm", Vector3(12.0, 0.4, 4.0), Vector3(0, y + 8.2, -90.0))
	kit.box("metal_dark", Vector3(12.0, 0.6, 0.25), Vector3(0, y + 8.0, -88.0))
	props.railing(Vector3(-6.0, y + 8.4, -88.0), Vector3(-1.4, y + 8.4, -88.0), 1.1)
	props.railing(Vector3(1.4, y + 8.4, -88.0), Vector3(6.0, y + 8.4, -88.0), 1.1)
	# glass bridges across the void at level 1 & 2
	for bz in [-70.0, -82.0]:
		kit.begin_part(0.45, 55.0)
		kit.box("floor", Vector3(18.0, 0.22, 3.0), Vector3(0, y + 8.25, bz))
		for sz in [-1.0, 1.0]:
			props.railing(Vector3(-9.0, y + 8.36, bz + sz * 1.5), Vector3(9.0, y + 8.36, bz + sz * 1.5), 1.1)
			kit.box("glass", Vector3(18.0, 0.20, 0.03), Vector3(0, y + 8.6, bz + sz * 1.5))
		kit.box("metal_dark", Vector3(0.2, 0.5, 3.0), Vector3(-9.0, y + 8.2, bz))
		kit.box("metal_dark", Vector3(0.2, 0.5, 3.0), Vector3(9.0, y + 8.2, bz))
	kit.begin_part(0.45, 55.0)
	kit.box("floor", Vector3(16.0, 0.22, 2.6), Vector3(0, y + 16.25, -74.0))

	# ---------------- stairs level1 -> level2 ----------------
	props.stairs(Vector3(15.0, y + 8.4, -86.0), Vector3(13.0, y + 16.4, -80.0), 1.8)
	props.railing(Vector3(12.0, y + 8.4, -86.5), Vector3(12.0, y + 8.4, -84.0), 1.05)

	# ---------------- grand stair (ground -> level 1) ----------------
	props.stairs(Vector3(0.0, y, -77.5), Vector3(0.0, y + 8.0, -89.0), 6.0)
	for side in [-1.0, 1.0]:
		props.railing(Vector3(side * 3.1, y, -77.5), Vector3(side * 3.1, y + 8.0, -89.0), 1.05)
		kit.begin_part(0.45, 41.0)
		kit.box("emit|strip_cool" if false else "emit_strip_cool", Vector3(0.06, 0.06, 11.0), Vector3(side * 3.15, y + 4.0, -83.2))

	# ---------------- ground floor dressing ----------------
	# central holo sculpture
	kit.begin_part(0.4, 56.0)
	kit.cyl("metal_dark", 2.8, 2.6, 0.55, 40, Vector3(0, y, -74.0))
	kit.cyl("glass_dark", 2.55, 2.55, 0.16, 40, Vector3(0, y + 0.45, -74.0))
	kit.torus("metal_light", 2.7, 0.08, 40, 6, Vector3(0, y + 0.58, -74.0))
	for i in 3:
		kit.torus("holo", 0.9 + i * 0.55, 0.02, 40, 4, Vector3(0, y + 2.3 + i * 0.45, -74.0))
	kit.cyl("holo_soft", 0.35, 1.5, 2.8, 26, Vector3(0, y + 1.45, -74.0), false, 0.0)
	kit.sphere("holo", 0.45, 18, Vector3(0, y + 3.1, -74.0))
	light(Vector3(0, y + 3.0, -74.0), Color(0.35, 0.85, 1.0), 8.0, 18.0, true)
	# benches / planters / kiosks
	for side in [-1.0, 1.0]:
		for i in 3:
			var zz := -64.0 - i * 7.0
			props.bench(Vector3(side * 7.0, y, zz), PI * 0.5 * side, 2.4)
			if i < 2:
				props.planter(Vector3(side * 11.5, y, zz - 3.5), 2.0, 2.0, 0.55)
				props.tree(Vector3(side * 11.5, y + 0.5, zz - 3.5), 3.6, 1.7, i * 3 + int(side) + 5)
	# kiosks
	for i in 2:
		kit.begin_part(0.5, 56.0)
		kit.box("metal_dark", Vector3(2.2, 1.1, 2.2), Vector3(-5.0 + i * 10.0, y + 0.55, -68.0))
		kit.box("emit_warm", Vector3(2.0, 0.08, 2.0), Vector3(-5.0 + i * 10.0, y + 1.12, -68.0))
		kit.box("screen_log", Vector3(1.4, 0.8, 0.05), Vector3(-5.0 + i * 10.0, y + 1.6, -66.9))
		props.sign_board("KIOSK 0" + str(i + 1), Vector3(-5.0 + i * 10.0, y + 2.6, -68.0), 0, 1.4, 0.4,
			Color(0.4, 1.0, 0.6))

	# ---------------- shops ----------------
	var shop_names := ["CAFE ORBIT", "SUPPLY 7", "BIO-SYNTH", "SALVAGE CO", "NAV AIDS"]
	var accents := [Color(1.0, 0.6, 0.25), Color(0.4, 0.9, 1.0), Color(0.4, 1.0, 0.55),
		Color(1.0, 0.45, 0.3), Color(0.7, 0.6, 1.0)]
	for side in [-1.0, 1.0]:
		for k in 3:
			var za := -88.0 + k * 9.0
			var zb := za + 8.4
			var sx0: float = 14.0 if side > 0 else -18.0
			var sx1: float = 18.0 if side > 0 else -14.0
			props.shopfront(sx0, sx1, za, zb, y, shop_names[k % shop_names.size()],
				accents[k % accents.size()], k != 1)
			rd.shop_extra(k * 2 + (0 if side > 0 else 1), sx0, sx1, za, zb, y)
			props.shopfront(sx0 + side * 0.0, sx1, za + 0.0, zb, y + 8.0,
				shop_names[(k + 2) % shop_names.size()], accents[(k + 2) % accents.size()], k == 0)
			rd.shop_extra((k + 2) * 2 + (0 if side > 0 else 1), sx0, sx1, za, zb, y + 8.0)
			props.shopfront(sx0, sx1, za + 2.0, zb - 1.0, y + 16.0,
				shop_names[(k + 1) % shop_names.size()], accents[(k + 1) % accents.size()], false)

	# ---------------- signage ----------------
	props.sign_board("CENTRAL GALLERIA", Vector3(0, y + 11.0, z1 - 0.4), PI, 6.0, 1.2,
		Color(1.0, 0.82, 0.5))
	props.sign_board("DECK C  ·  HYDROPONICS" if false else "DECK 1  ↑  HYDROPONICS", Vector3(0, y + 10.0, z0 + 0.5), 0, 4.0, 0.7,
		Color(0.4, 1.0, 0.55))
	props.sign_board("LEVEL 02", Vector3(-9.6, y + 10.4, -62.0), PI * 0.5, 2.0, 0.5, Color(1.0, 0.7, 0.35))
	props.sign_board("LEVEL 03", Vector3(9.6, y + 18.2, -62.0), -PI * 0.5, 2.0, 0.5, Color(0.45, 0.95, 1.0))
	props.sign_board("GALLERIA  ·  LEVEL 01", Vector3(0, y + 2.8, z1 - 0.4), PI, 3.6, 0.5,
		Color(0.5, 0.9, 1.0))
	# route arrows on the ground + level 1
	chevrons([Vector3(0, y, -59.0), Vector3(0, y, -64.0), Vector3(0, y, -77.0)], 0.03, 0.5, 3.8)
	chevrons([Vector3(0, y + 8.0, -89.5), Vector3(0, y + 8.0, -91.5)], 0.03, 0.4, 1.8)
	chevrons([Vector3(0, y + 8.0, -88.0), Vector3(0, y + 8.0, -91.0)], 0.03, 0.4, 2.0)
	# ---------------- lighting ----------------
	light(Vector3(0, ceil - 4.0, -66.0), Color(1.0, 0.86, 0.66), 22.0, 32.0, true)
	light(Vector3(0, ceil - 4.0, -84.0), Color(1.0, 0.86, 0.66), 22.0, 32.0, true)
	light(Vector3(0, ceil + 2.6, -75.0), Color(0.55, 0.72, 1.0), 16.0, 26.0, false)
	light(Vector3(0, y + 3.0, -90.0), Color(0.8, 0.9, 1.0), 4.0, 12.0, false)
	light(Vector3(13.5, y + 10.5, -74.0), Color(1.0, 0.78, 0.5), 8.0, 20.0, false)
	light(Vector3(-13.5, y + 10.5, -74.0), Color(1.0, 0.78, 0.5), 8.0, 20.0, false)
	door_at("s", 0.0, x0, x1, z0, z1, y, 5.6, 4.4, 0.7, "metal_painted")
	rd.setup("atrium", zone_wear, zone_variant)
	# promenade life: bins, floor wear, planters, a cleaners cart
	for side in [-1.0, 1.0]:
		rd.bin(Vector3(side * 7.6, y, -62.0), 0)
		rd.bin(Vector3(side * 7.6, y, -88.0), 0)
		rd.stain(0, Vector3(side * 6.0, y, -72.0), 1.6, 1.0, 0.3)
		rd.footprints(Vector3(side * 2.0, y, -59.0), Vector3(side * 2.0, y, -88.0), 18)
	rd.janitor_cart(Vector3(-4.8, y, -64.0), 0.6)
	rd.planter_small(Vector3(4.8, y, -63.0))
	rd.planter_small(Vector3(-4.8, y, -86.0))
	rd.label("LEVEL 01  ·  GALLERIA", Vector3(0, y + 3.2, -59.0), PI, 0.4, Color(1.0, 0.8, 0.55))
	commit_zone("CentralGalleria")


# ========================================================= hydroponics =====
func z_hydro(parent: Node3D) -> void:
	zone("hydro", "HYDROPONICS / BIO DOME")
	var x0 := -11.0
	var x1 := 11.0
	var z0 := -116.0
	var z1 := -92.0
	var y := cfg.DECK_UPPER
	var h := 8.2
	shell(x0, x1, z0, z1, y, h, "wall_hydro", "floor_med", [
		opening("s", 0.0, 4.6, 0.0, 4.2),
		opening("n", 0.0, 2.6, 0.0, 2.6),
	], 1, true)
	# ---- curved glass roof ----
	kit.begin_part(0.45, 57.0)
	var roof_y := y + h
	for i in 13:
		var zz := z0 + 1.0 + i * 2.0
		# arched ribs
		var pts: Array = []
		for k in 9:
			var t := float(k) / 8.0
			var xx := lerpf(x0 + 0.2, x1 - 0.2, t)
			var yy := roof_y + 1.3 * sin(t * PI)
			pts.append(Vector3(xx, yy, zz))
		kit.tube("metal", pts, 0.075, 6)
		kit.tube("metal_dark", [Vector3(x0 + 0.2, roof_y - 0.25, zz), Vector3(x0 + 0.2, roof_y, zz)], 0.06, 5)
	# glass skin
	for i in 12:
		var za := z0 + 1.0 + i * 2.0
		var zb := za + 2.0
		for k in 8:
			var t0 := float(k) / 8.0
			var t1 := float(k + 1) / 8.0
			var xa := lerpf(x0 + 0.2, x1 - 0.2, t0)
			var xb := lerpf(x0 + 0.2, x1 - 0.2, t1)
			var ya := roof_y + 1.3 * sin(t0 * PI)
			var yb := roof_y + 1.3 * sin(t1 * PI)
			kit.quad("glass", [Vector3(xa, ya, za), Vector3(xb, yb, za),
				Vector3(xb, yb, zb), Vector3(xa, ya, zb)], Vector3.UP)
	# longitudinal spines
	for t in [0.15, 0.5, 0.85]:
		var pts: Array = []
		for i in 13:
			var zz := z0 + 1.0 + i * 2.0
			pts.append(Vector3(lerpf(x0 + 0.2, x1 - 0.2, t), roof_y + 1.3 * sin(t * PI), zz))
		kit.tube("metal_dark", pts, 0.06, 5)
	# grow lights hanging from the trusses
	for i in 5:
		var zz := z0 + 4.0 + i * 4.6
		kit.begin_part(0.5, 57.0)
		kit.box("emit_blue", Vector3(13.0, 0.08, 0.22), Vector3(0, roof_y + 0.9, zz))
		kit.box("metal", Vector3(13.2, 0.12, 0.34), Vector3(0, roof_y + 1.0, zz))
		kit.box("emit_amber", Vector3(13.0, 0.06, 0.18), Vector3(0, roof_y + 0.72, zz))
	# ---- crop rows ----
	for i in 4:
		for side in [-1.0, 1.0]:
			props.crop_row(Vector3(side * 6.0, y, z0 + 6.0 + i * 5.4), 4.4, 0.0, i % 2 == 0)
	# central path + water channel
	kit.begin_part(0.35, 58.0)
	kit.box("floor", Vector3(3.4, 0.05, 20.0), Vector3(0, y + 0.03, -104.0))
	kit.box("glass_dark", Vector3(1.6, 0.06, 20.0), Vector3(0, y + 0.05, -104.0))
	for i in 6:
		kit.box("metal_dark", Vector3(1.7, 0.12, 0.18), Vector3(0, y + 0.1, z0 + 3.0 + i * 3.4))
	# mist pipes along the walls
	props.pipe([Vector3(x0 + 0.5, y + 5.2, z0 + 2.0), Vector3(x0 + 0.5, y + 5.2, z1 - 2.0)], 0.10, "pipe_teal", true, 3.0)
	props.pipe([Vector3(x1 - 0.5, y + 5.0, z0 + 2.0), Vector3(x1 - 0.5, y + 5.0, z1 - 2.0)], 0.10, "pipe_cream", true, 3.0)
	# low planters and vines
	for side in [-1.0, 1.0]:
		for i in 3:
			props.planter(Vector3(side * 3.6, y, z0 + 5.0 + i * 6.0), 1.5, 1.4, 0.45)
			props.tree(Vector3(side * 3.6, y + 0.4, z0 + 5.0 + i * 6.0), 2.8, 1.3, i + 7 + int(side))
	# forward viewport looking into space
	kit.begin_part(0.7, 21.0)
	kit.box("glass", Vector3(7.0, 3.6, 0.06), Vector3(0, y + 3.2, z0 + 0.05))
	kit.box("metal_dark", Vector3(7.4, 0.2, 0.3), Vector3(0, y + 5.0, z0 + 0.1))
	kit.box("metal_dark", Vector3(7.4, 0.2, 0.3), Vector3(0, y + 1.4, z0 + 0.1))
	for k in 3:
		kit.box("metal_dark", Vector3(0.12, 3.6, 0.2), Vector3(-3.3 + k * 3.3, y + 3.2, z0 + 0.1))
	props.sign_board("HYDROPONICS  ·  BIO DOME 3", Vector3(0, y + 6.4, z1 - 0.4), PI, 4.4, 0.8,
		Color(0.45, 1.0, 0.55))
	# ---- lighting ----
	light(Vector3(0, y + 7.6, -98.0), Color(0.55, 0.45, 1.0), 4.0, 16.0, false)
	light(Vector3(0, y + 7.6, -110.0), Color(0.55, 0.45, 1.0), 4.0, 16.0, false)
	light(Vector3(0, y + 5.0, -104.0), Color(0.45, 0.85, 0.6), 7.0, 18.0, true)
	light(Vector3(0, y + 9.5, -104.0), Color(0.6, 0.75, 1.0), 6.0, 22.0, false)
	light(Vector3(0, y + 4.5, -100.0), Color(1.0, 0.92, 0.78), 6.0, 16.0, false)
	light(Vector3(0, y + 4.5, -110.0), Color(1.0, 0.86, 0.72), 5.0, 14.0, false)
	light(Vector3(-8.0, y + 3.0, -104.0), Color(0.85, 0.35, 0.95), 2.0, 8.0, false)
	door_at("s", 0.0, x0, x1, z0, z1, y, 4.6, 4.2, 0.8, "metal_painted")
	rd.setup("hydro", zone_wear, zone_variant)
	rd.hydro_extras(-11.0, 11.0, -116.0, -92.0, y, 8.2, zone_variant)
	commit_zone("Hydro")


# ========================================================= bridge access ===
func z_bridge_approach(parent: Node3D) -> void:
	zone("bridge_approach", "COMMAND ACCESS")
	var x0 := -3.0
	var x1 := 3.0
	var z0 := -124.0
	var z1 := -116.0
	var y := cfg.DECK_UPPER
	var h := 4.6
	shell(x0, x1, z0, z1, y, h, "wall", "floor_med", [
		opening("s", 0.0, 2.6, 0.0, 2.6),
		opening("n", 0.0, 2.4, 0.0, 4.6),
	], 1)
	# security checkpoint arch
	kit.begin_part(0.6, 59.0)
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.34, 2.8, 0.5), Vector3(sx * 1.5, y + 1.4, -119.0))
		kit.box("emit_cool", Vector3(0.06, 2.4, 0.4), Vector3(sx * 1.34, y + 1.4, -119.0))
	kit.box("metal_dark", Vector3(3.4, 0.34, 0.5), Vector3(0, y + 2.9, -119.0))
	kit.box("emit_cool", Vector3(3.0, 0.06, 0.4), Vector3(0, y + 2.74, -119.0))
	props.console(Vector3(-2.3, y, -118.0), PI * 0.5, 1.3, "screen_nav")
	props.locker(Vector3(-2.7, y, -121.0), PI * 0.5, 0.7, 1.8)
	props.locker(Vector3(2.7, y, -121.0), PI * 0.5, 0.7, 1.8)
	props.sign_board("COMMAND BRIDGE  ·  AUTHORISED ONLY", Vector3(0, y + 3.6, z0 + 0.35), 0, 3.4, 0.5,
		Color(1.0, 0.55, 0.25))
	# lift shaft to the tower deck
	kit.begin_part(0.45, 60.0)
	kit.set_height_range(y, 12.6)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			props.beam("metal_dark", Vector3(sx * 1.4, y, -122.6 + sz * 1.2),
				Vector3(sx * 1.4, 12.6, -122.6 + sz * 1.2), 0.12, 0.12)
	kit.box("metal_dark", Vector3(3.2, 0.2, 2.8), Vector3(0, 4.6, -121.4))
	kit.box("emit_cool", Vector3(3.0, 0.06, 2.6), Vector3(0, 4.66, -121.4))
	# ladder + glowing ceiling
	props.ladder(Vector3(2.0, y, -121.6), Vector3(2.0, 12.4, -121.6))
	light(Vector3(0, 12.2, -121.4), Color(0.6, 0.85, 1.0), 4.0, 8.0, false)
	light(Vector3(0, y + 3.8, -118.0), Color(0.9, 0.95, 1.0), 3.4, 7.0, true)
	props.sign_board("BRIDGE DECK  ·  LIFT", Vector3(0, 8.4, -123.4), PI, 2.0, 0.5,
		Color(0.4, 1.0, 0.6))
	door_at("s", 0.0, x0, x1, z0, z1, y, 2.6, 2.6, 0.6, "metal_painted")
	commit_zone("BridgeAccess")


# =============================================================== bridge =====
func z_bridge(parent: Node3D) -> void:
	zone("bridge", "COMMAND BRIDGE")
	var x0 := -7.4
	var x1 := 7.4
	var z0 := -147.0
	var z1 := -124.0
	var y := 12.6
	var h := 4.6
	shell(x0, x1, z0, z1, y, h, "wall_dark", "floor_dark", [
		opening("n", 0.0, 14.8, 0.0, 6.2),          # front canopy
		opening("w", -141.0, 9.0, 0.5, 3.7),        # port canopy
		opening("e", -141.0, 9.0, 0.5, 3.7),        # starboard canopy
		opening("s", 0.0, 2.2, 0.0, 2.2),           # aft door
	], 1)
	# wrap-around canopy glazing
	kit.begin_part(0.7, 21.0)
	kit.box("glass", Vector3(13.6, 4.4, 0.05), Vector3(0, y + 3.4, z0 + 0.08))
	for k in 5:
		kit.box("metal_dark", Vector3(0.14, 4.6, 0.22), Vector3(-6.6 + k * 3.3, y + 3.4, z0 + 0.12))
	kit.box("metal_dark", Vector3(13.8, 0.22, 0.3), Vector3(0, y + 5.6, z0 + 0.12))
	kit.box("metal_dark", Vector3(13.8, 0.30, 0.3), Vector3(0, y + 1.15, z0 + 0.12))
	for sx in [-1.0, 1.0]:
		kit.box("glass", Vector3(0.05, 3.4, 8.6), Vector3(sx * 7.28, y + 3.3, -141.0))
		for k in 4:
			kit.box("metal_dark", Vector3(0.2, 3.6, 0.14), Vector3(sx * 7.3, y + 3.3, -145.0 + k * 2.6))
	# ---------------- command dais ----------------
	kit.begin_part(0.45, 61.0)
	kit.box("floor_dark", Vector3(14.0, 0.35, 11.0), Vector3(0, y + 0.17, -139.5))
	kit.box("emit_strip_cool", Vector3(14.0, 0.04, 0.06), Vector3(0, y + 0.35, -134.0))
	# holo table
	props.holo_table(Vector3(-2.9, y, -133.0))
	# forward console arc
	for i in 5:
		var ang := -0.62 + float(i) * 0.31
		var px := sin(ang) * 6.4
		var pz := -143.4 + cos(ang) * 1.2
		props.console(Vector3(px, y + 0.2, pz), PI - ang, 1.7,
			["screen_nav", "screen_power", "screen_log", "screen_med", "screen_eng"][i])
		props.chair(Vector3(px, y + 0.2, pz + 1.1), PI - ang * 0.5)
	# side consoles
	for sx in [-1.0, 1.0]:
		for k in 2:
			props.console(Vector3(sx * 6.6, y + 0.2, -135.0 - k * 3.6), -sx * PI * 0.5, 1.8, "screen_eng")
			props.chair(Vector3(sx * 5.4, y + 0.2, -135.0 - k * 3.6), sx * PI * 0.5, 0.46)
	# overhead tactical sphere
	kit.begin_part(0.55, 35.0)
	kit.sphere("holo_dim", 1.05, 26, Vector3(0, y + 3.5, -136.0))
	kit.torus("holo", 1.15, 0.012, 36, 4, Vector3(0, y + 3.5, -136.0))
	kit.tube("metal_dark", [Vector3(0, y + h - 0.2, -136.0), Vector3(0, y + 4.55, -136.0)], 0.03, 5)
	# captain's chair on the dais
	props.captain_chair(Vector3(0, y + 0.35, -140.6), 0.0)
	props.chair(Vector3(-1.7, y + 0.35, -140.2), 0.25, 0.46)
	props.chair(Vector3(1.7, y + 0.35, -140.2), -0.25, 0.46)
	# dais steps
	kit.begin_part(0.4, 61.0)
	kit.box("floor_dark", Vector3(7.0, 0.17, 0.9), Vector3(0, y + 0.085, -133.8))
	kit.box("floor_dark", Vector3(9.0, 0.17, 0.9), Vector3(0, y + 0.25, -134.7))
	kit.box("emit_strip_cool", Vector3(6.8, 0.03, 0.05), Vector3(0, y + 0.18, -133.4))
	kit.begin_part(0.5, 61.0)
	kit.box("metal_dark", Vector3(2.4, 0.5, 0.6), Vector3(-3.4, y + 0.6, -141.0))
	kit.box("screen_nav", Vector3(2.0, 0.36, 0.04), Vector3(-3.4, y + 0.62, -140.66))
	kit.box("metal_dark", Vector3(2.4, 0.5, 0.6), Vector3(3.4, y + 0.6, -141.0))
	kit.box("screen_power", Vector3(2.0, 0.36, 0.04), Vector3(3.4, y + 0.62, -140.66))
	# aft status wall
	kit.begin_part(0.55, 29.0)
	kit.box("metal_dark", Vector3(6.4, 2.6, 0.2), Vector3(0, y + 3.4, z1 - 0.35))
	kit.box("screen_eng", Vector3(6.0, 2.3, 0.05), Vector3(0, y + 3.4, z1 - 0.45))
	kit.box("emit_strip_cool", Vector3(6.4, 0.06, 0.06), Vector3(0, y + 4.75, z1 - 0.45))
	# ceiling coves / light bars
	kit.begin_part(0.42, 61.0)
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.5, 0.3, 20.0), Vector3(sx * 4.6, y + h - 0.35, -134.0))
		kit.box("emit_strip_dim", Vector3(0.34, 0.06, 19.6), Vector3(sx * 4.6, y + h - 0.53, -134.0))
	# command path + hazard
	kit.begin_part(0.5, 61.0)
	kit.box("hazard_worn", Vector3(0.2, 0.02, 8.0), Vector3(-7.0, y + 0.02, -136.0))
	kit.box("hazard_worn", Vector3(0.2, 0.02, 8.0), Vector3(7.0, y + 0.02, -136.0))
	props.sign_board("SSV ORION  ·  COMMAND", Vector3(0, y + 5.3, z1 - 0.6), PI, 4.2, 0.6,
		Color(0.45, 0.85, 1.0))
	# lighting: dim, blue, with cyan holo
	light(Vector3(0, y + 3.9, -132.0), Color(0.55, 0.72, 1.0), 1.6, 13.0, true)
	light(Vector3(0, y + 1.4, -143.0), Color(0.55, 0.78, 1.0), 1.7, 11.0, false)
	light(Vector3(-2.9, y + 1.6, -133.0), Color(0.35, 0.9, 1.0), 0.5, 5.0, false)
	light(Vector3(0, y + 4.0, -126.0), Color(1.0, 0.75, 0.45), 1.2, 7.0, false)
	light(Vector3(-6.0, y + 3.0, -140.0), Color(0.45, 0.7, 1.0), 1.1, 7.0, false)
	door_at("s", 0.0, x0, x1, z0, z1, y, 2.2, 2.2, 0.65, "metal_painted")
	rd.setup("bridge", zone_wear, zone_variant)
	rd.bridge_extras(-7.4, 7.4, -147.0, -124.0, y, 4.6, zone_variant)
	commit_zone("CommandBridge")


func z_quarters(parent: Node3D) -> void:
	zone("quarters", "CREW QUARTERS")
	var x0 := 14.0
	var x1 := 14.0 + cfg.side_room_w
	var z0 := -48.0
	var z1 := -30.0
	var y := cfg.DECK_UPPER
	var h := 4.2
	# access corridor from the galleria aft wall
	shell(14.0, 18.0, -58.0, -48.0, y, h, "wall_warm", "floor_warm",
		[opening("n", 16.0, 2.2), opening("s", 16.0, 2.2)], 2)
	door_at("s", 16.0, 14.0, 18.0, -58.0, -48.0, y, 2.2, 2.4, 0.7)
	light(Vector3(16.0, y + 3.4, -53.0), Color(1.0, 0.8, 0.55), 3.0, 8.0, true)
	props.sign_board("CREW QUARTERS", Vector3(16.0, y + 2.9, -57.6), 0, 2.0, 0.4,
		Color(1.0, 0.78, 0.5))
	shell(x0, x1, z0, z1, y, h, "wall_pad", "floor_warm",
		[opening("n", 16.0, 2.2, 0.0, 2.4)], 2)
	door_at("n", 16.0, x0, x1, z0, z1, y, 2.2, 2.4, 0.7)
	rd.setup("quarters", zone_wear, zone_variant)
	rd.quarters(x0, x1, z0, z1, y, h)
	commit_zone("CrewQuarters")


func z_medbay(parent: Node3D) -> void:
	zone("medbay", "MEDICAL BAY")
	var x0 := -14.0 - cfg.side_room_w
	var x1 := -14.0
	var z0 := -48.0
	var z1 := -30.0
	var y := cfg.DECK_UPPER
	var h := 4.2
	shell(-18.0, -14.0, -58.0, -48.0, y, h, "wall_med", "floor_med",
		[opening("n", -16.0, 2.2), opening("s", -16.0, 2.2)], 1)
	door_at("s", -16.0, -18.0, -14.0, -58.0, -48.0, y, 2.2, 2.4, 0.7, "metal_painted")
	light(Vector3(-16.0, y + 3.4, -53.0), Color(0.85, 0.95, 1.0), 3.0, 8.0, true)
	shell(x0, x1, z0, z1, y, h, "wall_med", "floor_med",
		[opening("n", -16.0, 2.2, 0.0, 2.4)], 1)
	door_at("n", -16.0, x0, x1, z0, z1, y, 2.2, 2.4, 0.7, "metal_painted")
	rd.setup("medbay", zone_wear, zone_variant)
	rd.medbay(x0, x1, z0, z1, y, h, zone_variant)
	commit_zone("MedBay")


func z_observation(parent: Node3D) -> void:
	zone("observation", "OBSERVATION LOUNGE")
	var x0 := -11.0
	var x1 := 11.0
	var z0 := -54.0
	var z1 := -30.0
	var y := cfg.DECK_TOP
	var h := 4.9
	# access corridor from the galleria top level
	shell(9.0, 12.5, -58.0, -54.0, y, h, "wall_warm", "floor_warm",
		[opening("n", 10.5, 2.0), opening("s", 10.5, 2.0)], 2)
	door_at("s", 10.5, 9.0, 12.5, -58.0, -54.0, y, 2.0, 2.4, 0.7)
	shell(x0, x1, z0, z1, y, h, "wall_warm", "floor_warm",
		[opening("n", 10.5, 2.0, 0.0, 2.4)], 2)
	door_at("n", 10.5, x0, x1, z0, z1, y, 2.0, 2.4, 0.7)
	# forward panorama window (looks into space through the invisible hull)
	kit.begin_part(0.7, 21.0)
	kit.box("glass", Vector3(13.0, 3.1, 0.05), Vector3(0, y + 2.2, z0 + 0.08))
	kit.box("metal_dark", Vector3(13.4, 0.22, 0.3), Vector3(0, y + 3.85, z0 + 0.12))
	kit.box("metal_dark", Vector3(13.4, 0.3, 0.3), Vector3(0, y + 0.6, z0 + 0.12))
	for k in 5:
		kit.box("metal_dark", Vector3(0.12, 3.2, 0.2), Vector3(-6.4 + k * 3.2, y + 2.2, z0 + 0.12))
	# side windows
	for side in [-1.0, 1.0]:
		kit.box("glass", Vector3(0.05, 2.2, 14.0), Vector3(side * (x1 - 0.06), y + 2.3, -42.0))
		for k in 3:
			kit.box("metal_dark", Vector3(0.2, 2.4, 0.14), Vector3(side * (x1 - 0.1), y + 2.3, -48.0 + k * 4.6))
	rd.setup("observation", zone_wear, zone_variant)
	rd.observation(x0, x1, z0, z1, y, h, zone_variant)
	commit_zone("Observation")


func z_hangar(parent: Node3D) -> void:
	zone("hangar", "SHUTTLE HANGAR")
	var x0 := -13.0
	var x1 := 13.0
	var z0 := -88.0
	var z1 := -58.0
	var y := cfg.DECK_LOW
	var h := 7.6
	shell(x0, x1, z0, z1, y, h, "wall_struct", "floor_grate",
		[opening("n", 0.0, 4.0, 0.0, 4.0), opening("e", 0.0, 2.4)], 0)
	props.shuttle(Vector3(-2.0, y + 0.55, -74.0), PI * 0.5)
	# landing pad
	kit.begin_part(0.5, 40.0)
	kit.box("metal_dark", Vector3(16.0, 0.10, 16.0), Vector3(0, y + 0.05, -74.0))
	for k in 4:
		kit.box("emit_amber", Vector3(0.3, 0.06, 0.3), Vector3(-7.0 + k * 4.6, y + 0.12, -82.0))
		kit.box("emit_amber", Vector3(0.3, 0.06, 0.3), Vector3(-7.0 + k * 4.6, y + 0.12, -66.0))
	kit.box("hazard", Vector3(14.0, 0.02, 0.2), Vector3(0, y + 0.12, -82.5))
	kit.box("hazard", Vector3(14.0, 0.02, 0.2), Vector3(0, y + 0.12, -65.5))
	# crane rails
	kit.begin_part(0.45, 20.0)
	for sx in [-1.0, 1.0]:
		kit.box("metal_dark", Vector3(0.3, 0.5, 28.0), Vector3(sx * 10.5, y + 6.4, -73.0))
	kit.box("metal_dark", Vector3(21.0, 0.35, 0.8), Vector3(0, y + 6.5, -70.0))
	kit.box("metal_cast", Vector3(1.4, 1.0, 1.4), Vector3(3.0, y + 5.8, -70.0))
	kit.tube("metal", [Vector3(3.0, y + 5.3, -70.0), Vector3(3.0, y + 3.0, -70.0)], 0.07, 6)
	# cargo and fuel
	props.container(Vector3(-10.5, y, -62.0), "container_b", 0.0)
	props.container(Vector3(-10.5, y + 2.6, -62.0), "container_c", 0.0)
	props.crate(Vector3(9.5, y, -84.0), Vector3(1.6, 1.4, 1.4), "metal_painted", 0.3)
	props.crate(Vector3(8.0, y, -85.0), Vector3(1.2, 1.0, 1.0), "metal_painted", 0.8)
	props.barrel(Vector3(10.5, y, -80.0), "pipe_teal")
	props.barrel(Vector3(9.6, y, -78.0), "pipe_orange")
	# fuel hose reel
	kit.begin_part(0.5, 64.0)
	kit.cyl("metal_cast", 0.9, 0.9, 0.5, 20, Vector3(9.0, y + 0.5, -66.0))
	kit.tube("rubber", [Vector3(9.0, y + 0.5, -66.0), Vector3(6.0, y + 0.3, -68.0),
		Vector3(4.0, y + 0.3, -70.0)], 0.09, 6)
	# control booth glass
	kit.begin_part(0.45, 21.0)
	kit.box("glass", Vector3(4.0, 1.8, 0.05), Vector3(-9.0, y + 4.4, -60.0))
	kit.box("metal_dark", Vector3(4.4, 0.2, 0.3), Vector3(-9.0, y + 5.4, -60.0))
	props.console(Vector3(-9.0, y + 3.0, -61.0), 0.0, 2.0, "screen_log")
	props.sign_board("HANGAR  ·  BAY 2", Vector3(0, y + 6.9, z1 - 0.35), PI, 3.6, 0.6,
		Color(1.0, 0.6, 0.25))
	light(Vector3(0, y + 6.4, -70.0), Color(0.85, 0.92, 1.0), 12.0, 22.0, true)
	light(Vector3(-9.0, y + 4.6, -62.0), Color(1.0, 0.6, 0.3), 4.0, 9.0, false)
	light(Vector3(9.0, y + 3.0, -82.0), Color(0.6, 0.85, 1.0), 5.0, 12.0, false)
	door_at("n", 0.0, x0, x1, z0, z1, y, 4.0, 4.0, 0.8, "metal_painted")
	rd.setup("hangar", zone_wear, zone_variant)
	rd.hangar_extras(x0, x1, z0, z1, y, h)
	commit_zone("Hangar")


func z_machine(parent: Node3D) -> void:
	zone("machine", "MACHINE SHOP")
	var x0 := -13.0
	var x1 := 13.0
	var z0 := -56.0
	var z1 := -30.0
	var y := cfg.DECK_LOW
	var h := 7.0
	shell(x0, x1, z0, z1, y, h, "wall_struct", "floor_grate", [opening("s", 0.0, 3.0, 0.0, 3.0)], 0)
	door_at("s", 0.0, x0, x1, z0, z1, y, 3.0, 3.0, 0.8, "metal_painted")
	rd.setup("machine", zone_wear, zone_variant)
	rd.machine_shop(x0, x1, z0, z1, y, h, zone_variant)
	commit_zone("MachineShop")


func z_tanks(parent: Node3D) -> void:
	zone("tanks", "PROCESSING & TANKS")
	var x0 := -18.0
	var x1 := 18.0
	var z0 := -28.0
	var z1 := 0.0
	var y := cfg.DECK_LOW
	var h := 7.0
	shell(x0, x1, z0, z1, y, h, "wall_struct", "floor_grate", [opening("n", 0.0, 3.0, 0.0, 3.0)], 0)
	for i in 2:
		for k in 2:
			props.tank(Vector3(-11.0 + i * 22.0, y + 3.4, -22.0 + k * 12.0), 2.6, 6.2, "metal_light")
	kit.begin_part(0.5, 25.0)
	for i in 4:
		var px := -11.0 + (i % 2) * 22.0
		var pz := -22.0 + (i / 2) * 12.0
		kit.cyl("metal_cast", 0.8, 0.8, 1.2, 16, Vector3(px + 4.0, y + 0.6, pz))
		props.pipe([Vector3(px, y + 6.6, pz), Vector3(px + 4.0, y + 5.0, pz),
			Vector3(px + 4.0, y + 1.2, pz)], 0.26, "pipe_teal")
	props.pipe([Vector3(-18.0, y + 6.0, -14.0), Vector3(18.0, y + 6.0, -14.0)], 0.30, "pipe_orange")
	props.pipe([Vector3(-18.0, y + 5.2, -6.0), Vector3(18.0, y + 5.2, -6.0)], 0.22, "pipe_cream")
	props.sign_board("WATER / LOX PROCESSING", Vector3(0, y + 5.6, z1 - 0.35), PI, 4.0, 0.7,
		Color(0.45, 0.85, 1.0))
	light(Vector3(0, y + 5.2, -14.0), Color(0.85, 0.92, 1.0), 10.0, 22.0, true)
	light(Vector3(-14.0, y + 3.0, -20.0), Color(0.4, 0.8, 1.0), 4.0, 10.0, false)
	rd.setup("tanks", zone_wear, zone_variant)
	rd.tanks_extras(x0, x1, z0, z1, y, h)
	commit_zone("Tanks")


func z_galley(parent: Node3D) -> void:
	pass


func z_officers(parent: Node3D) -> void:
	zone("officers", "OFFICER COUNTRY")
	var x0 := -11.0
	var x1 := 11.0
	var z0 := -28.0
	var z1 := -8.0
	var y := cfg.DECK_TOP
	var h := 4.9
	shell(x0, x1, z0, z1, y, h, "wall_warm", "floor_warm",
		[opening("n", 0.0, 2.0, 0.0, 2.4)], 2)
	door_at("n", 0.0, x0, x1, z0, z1, y, 2.0, 2.4, 0.7)
	rd.setup("officers", zone_wear, zone_variant)
	rd.officers(x0, x1, z0, z1, y, h, zone_variant)
	commit_zone("Officers")


func build_route_marks(parent: Node3D) -> void:
	# subtle deck-level beacons at every route waypoint so the main line is
	# readable even in the large halls
	zone("route_marks", "ROUTE")
	var i := 0
	for p in cfg.route:
		if i % 2 == 0:
			kit.begin_part(0.4, 40.0)
			kit.box("emit_green", Vector3(0.22, 0.03, 0.22), p + Vector3(0, 0.02, 0))
			light(p + Vector3(0, 0.5, 0), Color(0.3, 1.0, 0.5), 0.5, 2.2, false)
		i += 1
	commit_zone("RouteMarks")
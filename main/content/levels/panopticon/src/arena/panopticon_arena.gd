extends RefCounted
## Research deck. All dimensions below use the campaign's world units.

const Kit = preload("res://src/arena/kit.gd")
const PhaseExperiment = preload("res://panopticon/src/arena/phase_experiment.gd")
const TANK_BASE_RADIUS := 8.9
const TANK_SCALE := Vector3(2.84, 1.95, 2.84)
const TANK_RADIUS := TANK_BASE_RADIUS * TANK_SCALE.x
const TANK_HEIGHT := 13.45 * TANK_SCALE.y
const CONTROL_SHIFT := Vector3(0, 0, -36.0)
const ARCHIVE_ART: Array[Texture2D] = [
	preload("res://panopticon/assets/archive/reconstruction.svg"),
	preload("res://panopticon/assets/archive/interrupted_transfer.svg"),
	preload("res://panopticon/assets/archive/eye_briefing.svg"),
]

var root := Node3D.new()
var solids: Array[AABB] = []
var materials: Dictionary = {}
var checkpoint: Dictionary = {}


static func build(origin := Vector3.ZERO) -> Dictionary:
	var room := new()
	room.root.name = "ResearchDeck"
	room.root.position = origin
	room._materials()
	room._shell()
	room._bulkhead_services()
	var experiment := room._containment()
	var experiment_panel := room._experiment_console(experiment)
	room._observation()
	room._service_ring()
	room._work_zones()
	room._service_links()
	room._utilities()
	var archives := room._archives()
	var control := room._control_room()
	room._lighting()
	return {
		"node": room.root, "kind": "panopticon", "name_cn": "回廊实验舱", "hint": "",
		"bounds": AABB(Vector3(-64, 0, -76), Vector3(128, 28, 154)),
		"inner_hall": Vector3(120, 27.10, 120),
		"floor_y": 0.0, "solids": room.solids, "walls": [],
		"cover": [{"c": Vector3.ZERO, "r": TANK_RADIUS, "h": TANK_HEIGHT, "cam": false}],
		"blade_center_cylinder": Vector2(TANK_RADIUS, TANK_HEIGHT),
		"player_spawn": Transform3D(Basis.IDENTITY, Vector3(0, 0, 71.6)),
		"anchors": [
			Vector3(-13, 0, 34), Vector3(34, 0, 7), Vector3(-9, 0, -34),
			Vector3(3, 0, 35), Vector3(23, 0, 28), Vector3(35, 0, 22),
			Vector3(33, 0, -9), Vector3(28, 0, -24), Vector3(14, 0, -34),
			Vector3(-25, 0, -26), Vector3(-35, 0, -12), Vector3(-35, 0, 8),
			Vector3(-23, 0, 27), Vector3(27, 0, -43), Vector3(-32, 0, -42),
			Vector3(22, 0, 45), Vector3(-25, 0, 45),
		],
		"archives": archives, "control": control, "scan": room.checkpoint, "experiment_panel": experiment_panel,
	}


static func nav_spec(arena: Dictionary) -> Dictionary:
	var tank: Vector2 = arena["blade_center_cylinder"]
	var ring := PackedVector2Array()
	for i in 24:
		ring.append(Vector2.from_angle(TAU * i / 24.0) * tank.x)
	return {"floor_margin": 0.0, "cover_obstacles": false, "obstacles": [{"poly": ring, "y0": 0.0,
		"y1": tank.y, "pad": "actor", "sight": true}]}


func _materials() -> void:
	var deck := ShaderMaterial.new()
	deck.shader = preload("res://gfx/tile_floor.gdshader")
	deck.set_shader_parameter("base_col", Color("566169"))
	deck.set_shader_parameter("grout_col", Color("3e4950"))
	deck.set_shader_parameter("stain_col", Color("50575a"))
	deck.set_shader_parameter("tile", 4.30)
	deck.set_shader_parameter("grout", 0.032)
	deck.set_shader_parameter("stain", 0.15)
	deck.set_shader_parameter("wet", 0.04)
	deck.set_shader_parameter("rough", 0.46)
	deck.set_shader_parameter("metal", 0.42)
	materials = {
		"floor": deck,
		"frame": Kit.std(Color("394348"), 0.44, 0.52),
		"metal": Kit.std(Color("828d91"), 0.37, 0.58, {"bump": 0.04}),
		"dark": Kit.std(Color("202a31"), 0.48, 0.30, {"grime": 0.09}),
		"teal": Kit.std(Color("374b4e"), 0.50, 0.45),
		"pale": Kit.std(Color("8e9798"), 0.46, 0.39),
		"rubber": Kit.std(Color("343332"), 0.76, 0.05),
		"amber_paint": Kit.std(Color("94816a"), 0.48, 0.32),
		"white": Kit.emissive(Color("e2ece8"), 2.3),
		"cyan": Kit.emissive(Color("91c8cd"), 1.5),
		"archive": Kit.emissive(Color("aebed4"), 1.1),
		"amber": Kit.emissive(Color("fac286"), 1.5),
		"red": Kit.emissive(Color("eb655b"), 2.2),
		"glass": Kit.glass(Color("81b6bc"), 0.20),
	}


func _box(key: String, size: Vector3, at: Vector3, solid := false,
		yaw := 0.0, parent: Node3D = null) -> MeshInstance3D:
	if solid:
		solids.append(AABB(at - size * 0.5, size))
	return Kit.box(root if parent == null else parent, size, at, materials[key], Vector3(0, yaw, 0))


func _cylinder(key: String, radius: float, height: float, at: Vector3,
		rot := Vector3.ZERO) -> MeshInstance3D:
	return Kit.cylinder(root, radius, height, at, materials[key], rot)


func _pipe(key: String, points: Array[Vector3], radius: float) -> void:
	for i in points.size() - 1:
		Kit.tube(root, points[i], points[i + 1], radius, materials[key])
	for i in range(1, points.size() - 1):
		_cylinder("frame", radius * 1.35, radius * 2.5, points[i])


func _fixture(at: Vector3, width: float) -> void:
	_box("dark", Vector3(width, 0.32, 0.68), at)
	_box("metal", Vector3(width - 0.15, 0.13, 0.55), at - Vector3.UP * 0.18)
	_box("white", Vector3(width - 0.40, 0.048, 0.34), at - Vector3.UP * 0.26)


func _sill(at: Vector3, width: float) -> void:
	_box("dark", Vector3(width, 0.025, 0.56), at)
	for i in 4:
		_box("metal", Vector3(width - 0.36, 0.021, 0.037),
			at + Vector3(0, 0.022, (i - 1.5) * 0.115))


func _shell() -> void:
	_box("floor", Vector3(120, 0.52, 120), Vector3(0, -0.26, 0))
	_box("floor", Vector3(10.2, 0.52, 14), Vector3(0, -0.26, 67.0))
	_box("floor", Vector3(22, 0.52, 12.5), Vector3(0, -0.26, -66.25))
	_box("frame", Vector3(121.0, 0.64, 121.0), Vector3(0, 27.42, 0), true)
	for side in [-1.0, 1.0]:
		var x: float = side * 60.40
		var inward: float = -side
		_box("teal", Vector3(0.80, 27.10, 121), Vector3(x, 13.55, 0), true)
		for i in 12:
			var z := -57.5 + i * 10.0
			_box("dark", Vector3(1.12, 26.9, 0.88), Vector3(x + inward * 0.32, 13.45, z), true)
			_box("metal", Vector3(0.14, 23.72, 0.42), Vector3(x + inward * 0.98, 13.45, z))
			_box("teal", Vector3(0.27, 3.38, 9.38), Vector3(x + inward * 0.45, 24.65, z + 4.0))
		_box("dark", Vector3(0.46, 0.53, 120), Vector3(x + inward * 0.48, 0.27, 0))
		_box("metal", Vector3(0.12, 0.16, 120), Vector3(x + inward * 0.76, 0.57, 0))
		_box("pale", Vector3(55, 27.1, 0.72), Vector3(side * 32.5, 13.55, 60.36), true)
		_box("teal", Vector3(53, 27.1, 0.72), Vector3(side * 33.5, 13.55, -60.36), true)
		_box("frame", Vector3(0.50, 8.0, 14.4), Vector3(side * 5.15, 4, 67.0), true)
		_box("teal", Vector3(0.18, 7.70, 14.24), Vector3(side * 4.97, 3.93, 67.0))
		for z in [60.7, 64.8, 69.05, 73.0]:
			_box("frame", Vector3(0.64, 7.85, 0.64), Vector3(side * 4.91, 3.94, z), true)
			_box("cyan", Vector3(0.11, 0.76, 0.091), Vector3(side * 4.57, 2.18, z))
			_box("metal", Vector3(0.29, 0.40, 0.79), Vector3(side * 4.74, 0.24, z))
	for z in [-47.0, -29.0, 29.0, 47.0]:
		_box("frame", Vector3(120.0, 1.12, 1.78), Vector3(0, 26.48, z), true)
		_box("metal", Vector3(119, 0.18, 1.42), Vector3(0, 25.85, z))
		for x in [-48.0, -25.0, 25.0, 48.0]:
			_box("frame", Vector3(0.69, 1.07, 1.54), Vector3(x, 25.62, z))
			_fixture(Vector3(x, 24.95, z), 11.6)
	_box("teal", Vector3(10.6, 0.64, 14.35), Vector3(0, 8.32, 67.15), true)
	_box("dark", Vector3(10.6, 8.1, 0.60), Vector3(0, 4.05, 74.22), true)
	_box("frame", Vector3(10.75, 19.10, 0.74), Vector3(0, 17.58, 60.36), true)
	_box("frame", Vector3(14.05, 12.5, 0.74), Vector3(0, 20.88, -60.36), true)
	for z in [60.7, 64.8, 69.05, 73.0]:
		_fixture(Vector3(0, 7.63, z), 6.24)
		_sill(Vector3(0, 0.015, z), 9.06)


func _containment() -> PhaseExperiment:
	# The lower clamp and the roof manifold carry the chamber. Nothing hangs in free space.
	var first_part := root.get_child_count()
	_cylinder("dark", TANK_BASE_RADIUS, 0.48, Vector3(0, 0.24, 0))
	_cylinder("frame", 8.72, 1.44, Vector3(0, 0.90, 0))
	_cylinder("metal", 8.76, 0.23, Vector3(0, 1.56, 0))
	var glazing := _cylinder("glass", 8.21, 8.45, Vector3(0, 5.90, 0))
	glazing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glazing.material_override = Kit.glass(Color("9db9bd"), 0.105)
	_cylinder("frame", 8.74, 0.86, Vector3(0, 10.40, 0))
	_cylinder("metal", 8.66, 0.22, Vector3(0, 10.90, 0))
	_cylinder("dark", 7.14, 0.57, Vector3(0, 11.13, 0))
	_cylinder("frame", 3.50, 3.2, Vector3(0, 12.30, 0))
	_cylinder("metal", 3.73, 0.28, Vector3(0, 13.84, 0))
	Kit.annulus(root, 8.93, 9.21, 48, 0.032, materials["dark"])
	Kit.annulus(root, 9.24, 9.31, 48, 0.036, materials["metal"])
	for corner in [-65.0, -43.0, 43.0, 65.0, 112.0, 156.0, 204.0, 248.0]:
		var angle := deg_to_rad(corner)
		var radial := Vector3(sin(angle), 0, cos(angle))
		var base := Transform3D(Basis(Vector3.UP, angle), radial * 8.24)
		for at in [1.02, 10.30]:
			_box("dark", Vector3(1.51, 0.67, 0.68), base * Vector3(0, at, 0.21), false, angle)
			_box("metal", Vector3(1.24, 0.27, 0.15), base * Vector3(0, at + 0.12, 0.59), false, angle)
		_box("frame", Vector3(0.61, 8.76, 0.60), base * Vector3(0, 5.86, 0.07), false, angle)
		_box("metal", Vector3(0.19, 8.21, 0.13), base * Vector3(0, 5.86, 0.40), false, angle)
		_box("cyan", Vector3(0.068, 1.30, 0.049), base * Vector3(0, 4.05, 0.49), false, angle)
	_heat_exchangers()
	var scale := Transform3D(Basis.from_scale(TANK_SCALE), Vector3.ZERO)
	for i in range(first_part, root.get_child_count()):
		var part: Node3D = root.get_child(i)
		part.transform = scale * part.transform

	var lab := PhaseExperiment.new()
	lab.name = "PhaseExperiment"
	lab.palette = materials
	lab.position = Vector3(0, 3.29, 10.65)
	lab.rotation.y = deg_to_rad(-28.0)
	root.add_child(lab)
	return lab


func _experiment_console(lab: PhaseExperiment) -> Dictionary:
	var at := Vector3(-8.65, 0, 31.6)
	_box("dark", Vector3(6.14, 0.18, 2.36), at + Vector3(0, 0.09, 0), true)
	for side in [-1.0, 1.0]:
		var leg: Vector3 = at + Vector3(side * 2.31, 0, -0.02)
		_box("frame", Vector3(1.24, 1.52, 1.86), leg + Vector3.UP * 0.94, true)
		_box("metal", Vector3(1.08, 1.35, 0.15), leg + Vector3(0, 0.95, 0.96))
		_box("dark", Vector3(0.88, 0.68, 0.13), leg + Vector3(0, 1.12, 1.04))
		for i in 5:
			_box("frame", Vector3(0.76, 0.047, 0.073), leg + Vector3(0, 0.88 + i * 0.118, 1.13))
		for x in [-0.39, 0.39]:
			_cylinder("metal", 0.055, 0.09, leg + Vector3(x, 0.61, 1.10), Vector3(PI / 2.0, 0, 0))
	_box("dark", Vector3(5.91, 1.45, 0.47), at + Vector3(0, 1.03, -0.66), true)
	_box("frame", Vector3(6.27, 0.31, 2.39), at + Vector3(0, 1.79, 0.03), true)
	_box("metal", Vector3(6.12, 0.115, 2.29), at + Vector3(0, 1.99, 0.04), true)
	_box("dark", Vector3(5.91, 0.15, 0.16), at + Vector3(0, 1.85, 1.238))
	_box("cyan", Vector3(0.29, 0.057, 0.054), at + Vector3(-2.42, 1.83, 1.33))
	_box("frame", Vector3(2.84, 0.12, 1.01), at + Vector3(-1.07, 2.09, 0.48), true)
	for row in 3:
		for i in 12:
			var key := "metal" if i in [0, 11] or (row == 0 and i % 3 == 0) else "dark"
			_box(key, Vector3(0.163, 0.083, 0.19),
				at + Vector3(-2.26 + i * 0.213, 2.204, 0.23 + row * 0.238))
	_box("teal", Vector3(0.69, 0.11, 0.86), at + Vector3(0.93, 2.09, 0.49), true)
	_cylinder("dark", 0.21, 0.078, at + Vector3(0.93, 2.20, 0.46))
	_cylinder("metal", 0.12, 0.12, at + Vector3(0.93, 2.26, 0.46))
	for i in 3:
		_box("metal", Vector3(0.077, 0.034, 0.12), at + Vector3(0.75 + i * 0.18, 2.18, 0.83))

	var display := at + Vector3(-1.04, 3.20, -0.49)
	_box("frame", Vector3(0.59, 0.57, 0.49), display + Vector3(0, -0.90, -0.17), true)
	_box("dark", Vector3(3.95, 1.78, 0.39), display, true)
	_box("metal", Vector3(3.78, 1.59, 0.083), display + Vector3(0, 0.01, 0.21))
	_box("dark", Vector3(3.56, 1.40, 0.045), display + Vector3(0, 0, 0.263))
	for i in 11:
		_box("teal", Vector3(0.010, 1.06, 0.009), display + Vector3(-1.54 + i * 0.308, 0.024, 0.290))
	for i in 7:
		_box("teal", Vector3(3.08, 0.010, 0.009), display + Vector3(0, -0.50 + i * 0.179, 0.290))
	var screen := MeshInstance3D.new()
	screen.name = "ExternalScope"
	screen.mesh = lab.scope_mesh
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.scale = Vector3(0.402, 0.432, 1.0)
	screen.position = display + Vector3(0, 0.025, 0.306)
	root.add_child(screen)
	_box("cyan", Vector3(0.13, 0.049, 0.025), display + Vector3(1.58, -0.765, 0.257))
	_pipe("dark", [display + Vector3(-1.43, -0.77, -0.20), display + Vector3(-1.43, -1.151, -0.26),
		at + Vector3(-2.10, 1.92, -0.73), at + Vector3(-2.10, 0.42, -0.81)], 0.073)

	var panel := at + Vector3(1.95, 2.99, -0.49)
	_box("frame", Vector3(0.37, 0.48, 0.40), panel + Vector3(0, -0.69, -0.10), true)
	_box("dark", Vector3(1.34, 1.32, 0.33), panel, true)
	_box("teal", Vector3(1.17, 1.13, 0.048), panel + Vector3(0, 0, 0.18))
	for y in [-0.37, 0.36]:
		_box("metal", Vector3(0.88, 0.026, 0.027), panel + Vector3(0, y, 0.212))
	var pilot := Node3D.new()
	pilot.name = "LeverPilotAnimation"
	pilot.position = panel + Vector3(0, 0, 0.225)
	root.add_child(pilot)
	var open_lamp := _box("cyan", Vector3(0.55, 0.072, 0.052), Vector3(0, 0.19, 0), false, 0, pilot)
	var closed_lamp := _box("amber", Vector3(0.55, 0.072, 0.052), Vector3(0, -0.18, 0), false, 0, pilot)
	for side in [-1.0, 1.0]:
		_box("dark", Vector3(0.107, 0.76, 0.042), panel + Vector3(side * 0.39, 0, 0.23))
		_box("metal", Vector3(0.047, 0.60, 0.023), panel + Vector3(side * 0.39, 0.03, 0.261))

	var mount := at + Vector3(2.15, 2.13, 0.54)
	_box("frame", Vector3(1.31, 0.28, 1.15), mount, true)
	_box("metal", Vector3(1.16, 0.09, 1.03), mount + Vector3.UP * 0.177)
	_box("dark", Vector3(0.33, 0.057, 0.95), mount + Vector3.UP * 0.234)
	for side in [-1.0, 1.0]:
		var gate: Vector3 = mount + Vector3(side * 0.29, 0.27, 0)
		_cylinder("dark", 0.20, 0.31, gate, Vector3(0, 0, PI / 2.0))
		_cylinder("metal", 0.15, 0.042, gate + Vector3(side * 0.169, 0, 0), Vector3(0, 0, PI / 2.0))
	for z in [-0.42, 0.42]:
		_box("amber_paint", Vector3(0.54, 0.045, 0.073), mount + Vector3(0, 0.26, z))
	var lever := Node3D.new()
	lever.name = "OpticsLeverAnimation"
	lever.position = mount + Vector3.UP * 0.27
	root.add_child(lever)
	_box("metal", Vector3(0.15, 0.79, 0.15), Vector3(0, 0.40, 0), false, 0, lever)
	_box("frame", Vector3(0.25, 0.26, 0.24), Vector3(0, 0.18, 0), false, 0, lever)
	_box("amber_paint", Vector3(0.90, 0.24, 0.24), Vector3(0, 0.83, 0), false, 0, lever)
	for x in [-0.27, 0.27]:
		_box("rubber", Vector3(0.115, 0.245, 0.252), Vector3(x, 0.83, 0), false, 0, lever)
	lab.connect_console(lever, open_lamp, closed_lamp)

	var key := _key_plate(at + Vector3(2.15, 1.81, 1.345), 0.0)
	_box("frame", Vector3(0.55, 0.033, 5.76), at + Vector3(-2.14, 0.037, -4.04))
	for z in [-1.43, -3.08, -4.72, -6.68]:
		_box("metal", Vector3(0.69, 0.059, 0.25), at + Vector3(-2.14, 0.051, z))
	_light(at + Vector3(-0.24, 4.39, 1.16), Color("cbe2e2"), 1.38, 9.2)
	return {"experiment": lab, "prompt_label": key, "stand": at + Vector3(1.63, 0, 3.51),
		"screen": screen, "lever": lever}


func _heat_exchangers() -> void:
	# The old liquid vessel becomes two smaller, legible coolant loops around the test article.
	var fluid := ShaderMaterial.new()
	fluid.shader = preload("res://panopticon/gfx/liquid.gdshader")
	fluid.set_shader_parameter("top_col", Color("759b98"))
	fluid.set_shader_parameter("deep_col", Color("304f58"))
	fluid.set_shader_parameter("alpha", 0.53)
	fluid.set_shader_parameter("glow", 0.24)
	fluid.set_shader_parameter("base_y", 6.5)
	fluid.set_shader_parameter("span", 10.0)
	for side in [-1.0, 1.0]:
		var p := Vector3(side * 4.62, 0, -2.42)
		_cylinder("metal", 0.91, 0.42, p + Vector3.UP * 2.66)
		_cylinder("glass", 0.83, 6.17, p + Vector3.UP * 5.80).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var liquid := Kit.cylinder(root, 0.71, 4.82, p + Vector3.UP * 5.23, fluid)
		liquid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := liquid.mesh as CylinderMesh
		mesh.cap_bottom = false
		_cylinder("frame", 0.91, 0.44, p + Vector3.UP * 8.80)
		for dz in [-0.8, 0.8]:
			_box("metal", Vector3(0.12, 5.97, 0.13), p + Vector3(0, 5.75, dz))
		_pipe("metal", [p + Vector3.UP * 8.98, p + Vector3.UP * 10.4,
			Vector3(side * 2.65, 10.67, -0.67)], 0.13)


func _probe(at: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	var pedestal := Vector3(2.23, 0.43, 2.38)
	_box("dark", pedestal, xf * Vector3(0, 0.18, 0), true)
	_box("metal", Vector3(0.60, 2.37, 0.64), xf * Vector3(0, 1.34, 0), true, yaw)
	var joint := _cylinder("frame", 0.48, 0.36, xf * Vector3(0, 2.61, 0))
	joint.basis = xf.basis * Basis(Vector3.FORWARD, PI / 2.0)
	_pipe("metal", [xf * Vector3(0, 2.55, 0), xf * Vector3(0, 3.18, 0.44),
		xf * Vector3(0, 3.18, 1.25)], 0.17)
	_box("frame", Vector3(0.74, 0.53, 0.65), xf * Vector3(0, 3.17, 1.38), false, yaw)
	_box("dark", Vector3(0.63, 0.43, 0.12), xf * Vector3(0, 3.16, 1.75), false, yaw)
	_box("cyan", Vector3(0.26, 0.16, 0.075),
		xf * Vector3(0, 3.18, 1.84), false, yaw)
	# The articulated head is fixed for this room. Its actual volume also blocks the player.
	var size := Vector3(0.74, 0.56, 1.77)
	if absf(sin(yaw)) > 0.90:
		size = Vector3(size.z, size.y, size.x)
	solids.append(AABB(xf * Vector3(0, 3.17, 0.91) - size * 0.5, size))


func _observation() -> void:
	# Original observation windows now form two identifiable instrument galleries.
	for side in [-1.0, 1.0]:
		var x: float = side * 56.8
		var inward: float = -side
		_box("frame", Vector3(6.12, 0.93, 85.4), Vector3(x, 14.92, 0), true)
		_box("teal", Vector3(5.79, 8.22, 84.96), Vector3(x + side * 0.05, 19.5, 0), true)
		_box("metal", Vector3(6.06, 0.42, 85.09), Vector3(x, 23.72, 0), true)
		var arch_side: bool = side < 0.0
		for i in (7 if arch_side else 5):
			var z := -36.0 + i * (12.0 if arch_side else 18.0)
			var facade := Vector3(x + inward * 3.00, 19.65, z)
			_box("frame", Vector3(0.63, 6.75, 10.7), facade)
			_box("dark", Vector3(0.48, 5.09, 9.27), facade + Vector3(inward * 0.40, 0.16, 0))
			_box("metal", Vector3(0.13, 0.13, 9.17), facade + Vector3(inward * 0.68, -0.30, 0))
			if not arch_side:
				for j in 7:
					_box("metal", Vector3(0.31, 0.11, 8.86),
						facade + Vector3(inward * 0.71, -1.55 + j * 0.56, 0))
				_box("amber", Vector3(0.058, 0.134, 0.51), facade + Vector3(inward * 0.91, -1.89, 3.86))
			for j in ([-1, 0, 1] if arch_side else []):
				_box("teal", Vector3(0.14, 4.12, 2.72), facade + Vector3(inward * 0.69, 0.56, j * 2.93))
				_box("metal", Vector3(0.15, 3.88, 0.094), facade + Vector3(inward * 0.82, 1.03, j * 2.93 + 0.45))
				_box("cyan", Vector3(0.065, 0.075, 1.37), facade + Vector3(inward * 0.88, -0.81, j * 2.93))
			_box("metal", Vector3(0.44, 0.31, 10.4), facade + Vector3(inward * 0.55, -2.87, 0))
			_box("dark", Vector3(1.17, 3.98, 0.94), Vector3(x + inward * 2.33, 12.45, z + 5.15))
			_box("frame", Vector3(4.21, 1.95, 0.86), Vector3(x + side * 0.85, 12.87, z + 5.15))
			if i % 2 == 1:
				_light(Vector3(x + inward * 4.72, 18.0, z), Color("94b3bf"), 1.25, 14.5)
		# Wall-mounted supply pair wraps the tall hull into the equipment banks below.
		for y in [10.30, 11.28]:
			_pipe("metal", [Vector3(x + side * 3.20, y, -53.40),
				Vector3(x + side * 1.85, y, -53.40), Vector3(x + side * 1.85, y, 53.40),
				Vector3(x + side * 3.20, y, 53.40)], 0.20)
			for z in [-53.40, 53.40]:
				_box("frame", Vector3(0.47, 0.68, 0.71), Vector3(x + side * 3.01, y, z))
			for z in [-52.0, -39.0, -26.0, -13.0, 0.0, 13.0, 26.0, 39.0, 52.0]:
				_box("frame", Vector3(1.92, 0.53, 0.35), Vector3(x + side * 2.65, y, z))


func _service_ring() -> void:
	# Floor tracks and suspended conduits pick up the original concentric layout.
	Kit.annulus(root, 25.94, 27.40, 96, 0.024, materials["dark"])
	Kit.annulus(root, 26.25, 26.32, 96, 0.033, materials["metal"])
	Kit.annulus(root, 40.82, 41.08, 96, 0.026, materials["frame"])
	Kit.annulus(root, 41.37, 41.42, 96, 0.033, materials["metal"])
	for radius: float in [23.80, 37.50]:
		Kit.torus(root, radius, 0.42, Vector3.UP * 25.22, materials["frame"], 96)
		Kit.torus(root, radius, 0.13, Vector3.UP * 24.97, materials["metal"], 96)
		for i in 8:
			var rot := TAU * i / 8.0
			var p := Vector3(sin(rot), 0, cos(rot)) * radius
			_box("frame", Vector3(0.78, 2.08, 0.84), p + Vector3.UP * 26.15, false, rot)
			_box("metal", Vector3(1.08, 0.37, 1.09), p + Vector3.UP * 25.13, false, rot)
	for i in 12:
		var a := TAU * (i + 0.5) / 12.0
		var radial := Vector3(sin(a), 0, cos(a))
		var strip := radial * 32.80 + Vector3.UP * 0.035
		_box("frame", Vector3(0.80, 0.033, 9.50), strip, false, a)
		_box("metal", Vector3(0.16, 0.020, 8.90), strip + Vector3.UP * 0.025, false, a)
	_probe(Vector3(-17.1, 0, 42.3), 0.0)
	_probe(Vector3(19.5, 0, -40.1), PI)


func _work_zones() -> void:
	checkpoint = _scan_checkpoint(Vector3(-39.5, 0, 34.0))
	_archive_bench(Vector3(-39.5, 0, -32.0))
	_phase_calibration(Vector3(40.5, 0, -32.5))
	_repair_bay(Vector3(41.0, 0, 32.5))


func _bay_floor(at: Vector3, width: float, depth: float, warm: bool) -> void:
	_box("dark", Vector3(width, 0.024, depth), at + Vector3.UP * 0.012)
	_box("rubber" if warm else "teal", Vector3(width - 0.65, 0.027, depth - 0.58), at + Vector3.UP * 0.018)
	for x in [-width * 0.48, width * 0.48]:
		_box("metal", Vector3(0.058, 0.024, depth - 0.34), at + Vector3(x, 0.042, 0))
	for z in [-depth * 0.48, depth * 0.48]:
		_box("metal", Vector3(width - 0.34, 0.024, 0.058), at + Vector3(0, 0.043, z))
		for i in 4:
			_box("amber_paint" if warm else "metal", Vector3(0.48, 0.024, 0.135),
				at + Vector3(-0.84 + i * 0.56, 0.056, z - signf(z) * 0.21))
	for z in [-depth * 0.27, depth * 0.27]:
		for x in [-width * 0.45, width * 0.45]:
			_box("frame", Vector3(0.35, 0.022, 1.18), at + Vector3(x, 0.041, z))


func _plinth(at: Vector3, size: Vector2, height: float, finish := "frame") -> void:
	_box("dark", Vector3(size.x - 0.22, 0.18, size.y - 0.22), at + Vector3.UP * 0.09, true)
	_box(finish, Vector3(size.x, height - 0.18, size.y), at + Vector3.UP * ((height + 0.18) * 0.5), true)
	for x in [-size.x * 0.39, size.x * 0.39]:
		for z in [-size.y * 0.38, size.y * 0.38]:
			_cylinder("metal", 0.076, 0.04, at + Vector3(x, height + 0.014, z))
	for x in [-size.x * 0.5, size.x * 0.5]:
		_box("metal", Vector3(0.049, 0.09, size.y - 0.25), at + Vector3(x, height - 0.091, 0))


func _scan_checkpoint(at: Vector3) -> Dictionary:
	_bay_floor(at, 14.0, 14.7, false)
	# A floor-level passage, paired optical heads and a moving plane distinguish the inspection gate.
	var half_width := 3.76
	for side in [-1.0, 1.0]:
		var x: float = side * half_width
		var neck := at + Vector3(x, 0, 0)
		_plinth(neck, Vector2(1.83, 4.12), 0.43)
		_box("frame", Vector3(1.21, 5.23, 2.46), neck + Vector3.UP * 3.00, true)
		_box("pale", Vector3(1.12, 4.62, 0.22), neck + Vector3(0, 3.11, 1.31))
		_box("teal", Vector3(0.86, 2.31, 0.31), neck + Vector3(0, 3.10, 1.44))
		_box("dark", Vector3(0.26, 4.82, 1.75), neck + Vector3(-side * 0.67, 3.05, 0))
		for y in [1.29, 2.59, 3.89, 5.19]:
			var eye: Vector3 = neck + Vector3(-side * 0.84, y, 0)
			var orient := Vector3(0, 0, PI * 0.5)
			_cylinder("metal", 0.318, 0.24, eye, orient)
			_cylinder("dark", 0.234, 0.060, eye + Vector3(-side * 0.15, 0, 0), orient)
			_cylinder("cyan", 0.146, 0.037, eye + Vector3(-side * 0.195, 0, 0), orient)
		for dz in [-0.59, 0.59]:
			_box("metal", Vector3(0.077, 4.21, 0.13), neck + Vector3(-side * 0.85, 3.11, dz))
		_box("metal", Vector3(0.80, 0.27, 0.45), neck + Vector3(0, 5.48, 1.35))
		_box("cyan", Vector3(0.43, 0.070, 0.040), neck + Vector3(0, 5.48, 1.60))
	_box("frame", Vector3(8.87, 0.67, 2.5), at + Vector3.UP * 5.87, true)
	_box("dark", Vector3(4.24, 0.75, 0.29), at + Vector3(0, 5.76, 1.34))
	_label(at + Vector3(0, 5.73, 1.496), 0, "光学检测", 0.011)
	_box("frame", Vector3(5.85, 0.081, 2.58), at + Vector3.UP * 0.042)
	for z in [-1.15, 1.15]:
		_sill(at + Vector3(0, 0.083, z), 5.67)
		_box("cyan", Vector3(4.80, 0.047, 0.052), at + Vector3(0, 0.099, z + signf(z) * 0.24))
	for x in [-2.7, 2.7]:
		_box("metal", Vector3(0.14, 0.038, 4.95), at + Vector3(x, 0.047, 0))
	for side in [-1.0, 1.0]:
		_box("metal", Vector3(0.53, 0.037, 0.10), at + Vector3(side * 0.40, 0.05, 2.60), false, side * 0.61)
		_box("metal", Vector3(0.53, 0.037, 0.10), at + Vector3(side * 0.40, 0.05, 3.32), false, side * 0.61)
	_light(at + Vector3(0, 4.25, 0.15), Color("a2d9de"), 2.5, 10.2)
	var scan := Node3D.new()
	scan.name = "OpticalScanAnimation"
	scan.position = at
	root.add_child(scan)
	var optics := MeshInstance3D.new()
	var sheet := QuadMesh.new()
	sheet.size = Vector2(5.33, 1.34)
	optics.mesh = sheet
	optics.rotation.x = -PI * 0.5
	var beam := StandardMaterial3D.new()
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.albedo_color = Color(0.34, 0.83, 0.91, 0.22)
	optics.material_override = beam
	optics.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scan.add_child(optics)
	for z in [-0.66, 0.66]:
		_box("cyan", Vector3(5.33, 0.026, 0.029), Vector3(0, 0, z), false, 0, scan)
	for x in [-2.69, 2.69]:
		_box("archive", Vector3(0.13, 0.155, 1.58), Vector3(x, 0, 0), false, 0, scan)
	scan.hide()
	return {"beam": scan, "center": at}


func _archive_bench(at: Vector3) -> void:
	_bay_floor(at, 14.0, 15.4, false)
	var bank := at + Vector3(-3.45, 0, -3.58)
	_plinth(bank, Vector2(2.61, 7.34), 0.31)
	_box("frame", Vector3(1.65, 3.67, 7.07), bank + Vector3(0, 2.16, 0), true)
	for i in 3:
		var reader := bank + Vector3(0, 0, -2.30 + i * 2.30)
		_box("pale", Vector3(0.18, 3.28, 2.08), reader + Vector3(0.89, 2.22, 0))
		_box("dark", Vector3(0.13, 2.75, 1.67), reader + Vector3(1.02, 2.26, 0))
		for row in 5:
			var height := 1.26 + row * 0.41
			_box("frame", Vector3(0.12, 0.27, 1.48), reader + Vector3(1.11, height, 0))
			_box("metal", Vector3(0.07, 0.085, 0.69), reader + Vector3(1.20, height, -0.22))
			_box("cyan", Vector3(0.062, 0.045, 0.17), reader + Vector3(1.20, height, 0.51))
		_box("teal", Vector3(0.034, 2.43, 0.11), reader + Vector3(1.23, 2.24, -0.94))
	_box("frame", Vector3(1.26, 0.48, 7.30), bank + Vector3(-0.61, 4.20, 0))
	for z in [-2.93, 2.93]:
		_pipe("metal", [bank + Vector3(0.48, 3.86, z), bank + Vector3(0.48, 4.19, z),
			bank + Vector3(-0.32, 4.19, z)], 0.081)
	var desk := at + Vector3(2.65, 0, 1.95)
	_plinth(desk, Vector2(4.50, 2.84), 1.37)
	_box("metal", Vector3(4.64, 0.16, 2.95), desk + Vector3.UP * 1.46, true)
	_box("dark", Vector3(2.77, 0.103, 1.41), desk + Vector3(0, 1.56, -0.35))
	for i in 3:
		var x := -0.87 + i * 0.86
		_box("teal", Vector3(0.62, 0.25, 1.05), desk + Vector3(x, 1.72, -0.35))
		_box("cyan", Vector3(0.39, 0.043, 0.19), desk + Vector3(x, 1.86, -0.41))
		_box("metal", Vector3(0.51, 0.072, 0.14), desk + Vector3(x, 1.84, 0.05))
	_box("frame", Vector3(0.37, 3.04, 0.35), desk + Vector3(-2.03, 2.67, -1.27), true)
	_box("frame", Vector3(3.99, 0.26, 0.38), desk + Vector3(-0.20, 4.05, -1.27), true)
	_box("archive", Vector3(3.54, 0.044, 0.19), desk + Vector3(-0.20, 3.89, -1.27))
	_light(desk + Vector3(0, 3.75, 0.36), Color("ced6e6"), 1.87, 8.65)
	_light(bank + Vector3(2.11, 3.67, 0), Color("9ec2d1"), 1.70, 10.2)


func _phase_calibration(at: Vector3) -> void:
	_bay_floor(at, 16.6, 17.5, false)
	_plinth(at, Vector2(7.50, 7.48), 1.26)
	_cylinder("frame", 2.48, 0.78, at + Vector3.UP * 1.65)
	_cylinder("metal", 1.73, 2.18, at + Vector3.UP * 2.68)
	_cylinder("dark", 1.89, 0.38, at + Vector3.UP * 3.89)
	Kit.torus(root, 3.03, 0.21, at + Vector3.UP * 4.82, materials["metal"], 40)
	Kit.torus(root, 2.64, 0.097, at + Vector3.UP * 4.74, materials["cyan"], 40)
	for side in [-1.0, 1.0]:
		var feed := at + Vector3(side * 2.98, 0, 0)
		_box("frame", Vector3(1.30, 3.84, 1.36), feed + Vector3.UP * 3.17, true)
		_box("metal", Vector3(1.72, 0.41, 1.47), feed + Vector3.UP * 4.70, true)
		_box("dark", Vector3(0.61, 3.00, 0.27), feed + Vector3(0, 3.17, 0.74))
		_box("cyan", Vector3(0.14, 2.03, 0.055), feed + Vector3(0, 3.18, 0.89))
		_pipe("metal", [feed + Vector3(0, 1.40, 1.06), feed + Vector3(0, 2.72, 1.06),
			feed + Vector3(-side * 0.69, 3.13, 1.06)], 0.16)
		_box("dark", Vector3(0.59, 0.37, 0.71), feed + Vector3(0, 2.01, 1.03))
	_box("frame", Vector3(3.7, 1.90, 3.7), at + Vector3.UP * 2.20, true)
	_box("metal", Vector3(3.65, 0.19, 0.18), at + Vector3(0, 3.27, 1.89))
	_box("cyan", Vector3(2.78, 0.057, 0.09), at + Vector3(0, 3.29, 2.01))
	_light(at + Vector3(0, 5.13, 1.24), Color("9fcecc"), 3.25, 13.0)
	var meter := at + Vector3(1.7, 0, 6.15)
	_plinth(meter, Vector2(4.07, 2.29), 1.40, "teal")
	_box("frame", Vector3(3.38, 0.48, 0.71), meter + Vector3(0, 1.60, -0.44), true)
	for i in 6:
		_box("cyan" if i < 4 else "amber", Vector3(0.23, 0.075, 0.045),
			meter + Vector3(-1.28 + i * 0.46, 1.62, -0.05))


func _repair_bay(at: Vector3) -> void:
	_bay_floor(at, 16.2, 17.0, true)
	# The player can jump onto the working deck and the low set-down pad.
	var deck := at + Vector3(0.82, 0, 0)
	_plinth(deck, Vector2(8.48, 6.12), 1.22)
	for x in [-3.34, 3.34]:
		_box("amber_paint", Vector3(0.14, 0.026, 5.63), deck + Vector3(x, 1.234, 0))
	var pad := deck + Vector3(-3.43, 0, 4.52)
	_plinth(pad, Vector2(4.05, 2.62), 0.69, "teal")
	for x in [-1.08, 1.08]:
		_box("dark", Vector3(0.27, 0.043, 2.44), pad + Vector3(x, 0.73, 0))
	var gantry := at + Vector3(3.82, 0, -1.79)
	_plinth(gantry, Vector2(2.72, 3.16), 0.38)
	_box("frame", Vector3(1.06, 7.55, 1.31), gantry + Vector3.UP * 4.15, true)
	_box("metal", Vector3(0.22, 6.65, 0.88), gantry + Vector3(-0.64, 3.89, 0))
	_box("frame", Vector3(7.28, 0.75, 0.86), gantry + Vector3(-3.28, 7.58, 0), true)
	_box("metal", Vector3(7.16, 0.24, 0.71), gantry + Vector3(-3.31, 7.07, 0), true)
	_box("amber_paint", Vector3(1.36, 0.48, 1.36), gantry + Vector3(-4.57, 6.72, 0), true)
	var hook := gantry + Vector3(-4.57, 5.15, 0)
	_pipe("dark", [hook, hook + Vector3.UP * 1.40], 0.083)
	_box("metal", Vector3(0.41, 0.45, 0.36), hook)
	_pipe("metal", [hook, hook + Vector3(-0.24, -0.53, 0), hook + Vector3(0, -0.75, 0),
		hook + Vector3(0.22, -0.53, 0)], 0.115)
	_fixture(gantry + Vector3(-2.85, 7.14, 0.72), 3.87)
	_light(gantry + Vector3(-3.90, 5.63, 0.82), Color("e6cbaa"), 3.45, 13.8, true)
	# Removed phase-device parts on a portable trolley.
	var trolley := at + Vector3(-3.84, 0, -4.13)
	_plinth(trolley, Vector2(2.74, 4.47), 0.92)
	_box("dark", Vector3(2.48, 0.06, 4.25), trolley + Vector3.UP * 0.95)
	for z in [-1.49, 1.49]:
		for x in [-1.04, 1.04]:
			_cylinder("rubber", 0.26, 0.15, trolley + Vector3(x, 0.27, z), Vector3(0, 0, PI / 2.0))
	var part := trolley + Vector3(0, 1.24, -0.73)
	_cylinder("metal", 0.86, 0.49, part)
	_cylinder("frame", 0.60, 0.55, part)
	Kit.torus(root, 0.58, 0.13, part + Vector3.UP * 0.29, materials["cyan"], 24)
	for i in 5:
		var angle := TAU * i / 5.0
		_box("metal", Vector3(0.13, 0.062, 0.49),
			part + Vector3(sin(angle) * 0.47, 0.29, cos(angle) * 0.47), false, angle)
	_box("amber_paint", Vector3(1.15, 0.32, 0.89), trolley + Vector3(0, 1.14, 1.14))
	_box("metal", Vector3(0.64, 0.055, 0.14), trolley + Vector3(0, 1.32, 1.18))


func _service_links() -> void:
	# The archive partition is low enough to see over and open at both ends.
	var wall := Vector3(-44, 0, -0.3)
	_plinth(wall, Vector2(1.10, 12.9), 0.95, "teal")
	var pane := _box("glass", Vector3(0.17, 1.66, 12.41),
		wall + Vector3.UP * 1.80, true)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box("metal", Vector3(0.45, 0.18, 12.97), wall + Vector3.UP * 2.72, true)
	for z in [-6.20, -2.08, 2.08, 6.20]:
		_box("frame", Vector3(0.69, 1.94, 0.25), wall + Vector3(0, 1.89, z), true)
		_box("metal", Vector3(0.078, 1.47, 0.081), wall + Vector3(0.40, 1.85, z))
		_box("frame", Vector3(0.36, 0.27, 0.48), wall + Vector3(0.30, 1.00, z))
	for z in [-10.7, 10.7]:
		_box("frame", Vector3(0.60, 0.036, 3.10), Vector3(-47.3, 0.025, z))
		_box("metal", Vector3(0.11, 0.029, 2.35), Vector3(-47.3, 0.048, z))
	# The east wall's common supply trunk branches into a single service manifold.
	var pump := Vector3(49.0, 0, 0.25)
	_bay_floor(pump, 8.8, 12.9, true)
	_plinth(pump, Vector2(5.48, 9.28), 0.46)
	for z in [-2.67, 2.67]:
		_box("frame", Vector3(3.96, 0.78, 2.09), pump + Vector3(0, 0.80, z), true)
		_box("metal", Vector3(4.31, 0.18, 2.32), pump + Vector3(0, 1.21, z), true)
		_cylinder("teal", 1.47, 3.53, pump + Vector3(0, 2.71, z), Vector3(0, 0, PI / 2.0))
		_box("frame", Vector3(3.58, 2.65, 2.18), pump + Vector3(0, 2.65, z), true)
		for x in [-1.70, 1.70]:
			_cylinder("metal", 1.53, 0.21, pump + Vector3(x, 2.71, z), Vector3(0, 0, PI / 2.0))
		_cylinder("frame", 0.83, 0.35, pump + Vector3(-1.98, 2.71, z), Vector3(0, 0, PI / 2.0))
		_cylinder("amber_paint", 0.54, 0.17, pump + Vector3(-2.15, 2.71, z),
			Vector3(0, 0, PI / 2.0))
		_box("metal", Vector3(0.21, 0.095, 0.78), pump + Vector3(-2.24, 2.71, z))
		_pipe("metal", [pump + Vector3(1.04, 4.08, z), pump + Vector3(1.04, 5.05, z),
			pump + Vector3(5.5, 5.05, z), pump + Vector3(5.5, 7.81, z),
			pump + Vector3(8.28, 7.81, z)], 0.16)
	_box("frame", Vector3(5.05, 0.39, 0.57), pump + Vector3(2.9, 5.26, -2.67), true)
	_box("frame", Vector3(5.05, 0.39, 0.57), pump + Vector3(2.9, 5.26, 2.67), true)
	_light(pump + Vector3(-2.30, 5.44, 0), Color("d5c1a8"), 1.84, 10.0)


func _utilities() -> void:
	# Starboard coolant rack. Hoses terminate in floor glands and the high supply trunk.
	_box("frame", Vector3(1.03, 0.85, 64.4), Vector3(57.6, 7.88, -1.0), true)
	_box("metal", Vector3(0.22, 0.47, 64.65), Vector3(57.04, 7.88, -1.0))
	for z in [-27.5, -21.3, -15.1, 15.0, 21.2, 27.4]:
		var at := Vector3(55.1, 0, z)
		_box("dark", Vector3(4.23, 0.31, 4.91), at + Vector3(0, 0.15, 0), true)
		_box("frame", Vector3(3.16, 4.85, 4.50), at + Vector3(0.25, 2.69, 0), true)
		_rack_face(at)
		_box("pale", Vector3(0.24, 4.42, 3.95), at + Vector3(-1.40, 2.68, 0))
		_box("dark", Vector3(0.19, 2.17, 2.94), at + Vector3(-1.54, 2.92, 0))
		for i in 9:
			_box("metal", Vector3(0.10, 0.082, 2.69), at + Vector3(-1.67, 2.13 + i * 0.19, 0))
		for side in [-1.0, 1.0]:
			var offset := Vector3(0, 0, side * 1.20)
			_box("frame", Vector3(0.88, 0.38, 0.65), at + offset + Vector3(0.81, 5.20, 0))
			_pipe("metal", [at + offset + Vector3(0.81, 5.37, 0),
				at + offset + Vector3(0.81, 6.91, 0), at + offset + Vector3(2.36, 7.45, 0)], 0.13)
		_box("cyan", Vector3(0.07, 0.12, 0.52), at + Vector3(-1.60, 4.41, 1.10))
	for z in [-34.4, 34.25]:
		_box("dark", Vector3(3.33, 1.38, 3.59), Vector3(54.6, 0.69, z), true)
		_box("teal", Vector3(3.48, 0.21, 3.70), Vector3(54.6, 1.39, z), true)
		_box("metal", Vector3(0.09, 0.18, 0.77), Vector3(52.88, 0.66, z))


	for z in [-31.5, -3.2, 2.7, 31.5]:
		_box("frame", Vector3(1.08, 8.37, 0.95), Vector3(57.55, 4.19, z), true)
		_box("metal", Vector3(1.74, 0.35, 1.32), Vector3(57.55, 0.175, z), true)


func _archives() -> Array:
	# Three independent readers along the outside of the circulation loop.
	_box("dark", Vector3(9.9, 0.043, 49.50), Vector3(-51.20, 0.013, 0))
	_box("frame", Vector3(0.71, 0.69, 49.60), Vector3(-54.1, 6.7, 0.0), true)
	var stations: Array = []
	for i in 3:
		var z := 17.70 - i * 17.70
		var at := Vector3(-53.11, 0, z)
		_box("frame", Vector3(2.34, 4.72, 5.60), at + Vector3(0, 2.36, 0), true)
		_box("pale", Vector3(0.27, 4.22, 5.32), at + Vector3(1.24, 2.48, 0))
		_box("dark", Vector3(0.17, 2.28, 3.84), at + Vector3(1.42, 3.02, 0))
		_box("metal", Vector3(0.93, 0.24, 5.52), at + Vector3(1.34, 1.63, 0), true)
		_box("frame", Vector3(0.66, 0.27, 0.70), at + Vector3(1.57, 1.83, 1.80), true)
		_box("archive", Vector3(0.22, 0.037, 0.23), at + Vector3(1.60, 1.98, 1.80))
		_box("frame", Vector3(1.85, 0.39, 5.84), at + Vector3(0.57, 5.22, 0), true)
		_box("archive", Vector3(0.37, 0.06, 5.41), at + Vector3(1.36, 4.99, 0))
		_box("dark", Vector3(0.31, 0.54, 0.63), at + Vector3(-1.35, 6.67, 0))
		_pipe("metal", [at + Vector3(-0.27, 5.41, 0), at + Vector3(-0.27, 6.13, 0),
			at + Vector3(-0.79, 6.45, 0)], 0.12)
		var display := _display(at + Vector3(1.52, 3.06, 0), PI / 2.0, i)
		_box("frame", Vector3(0.071, 0.52, 0.76), at + Vector3(1.397, 4.33, 2.08))
		var label := _label(at + Vector3(1.438, 4.33, 2.08), PI / 2.0, "%02d" % (i + 1), 0.0074)
		label.modulate = Color("b7d3d1")
		var key := _key_plate(at + Vector3(1.907, 1.81, 1.80), PI / 2.0)
		stations.append({"panel": display, "prompt_label": key,
			"stand": at + Vector3(2.45, 0, 0)})
		_light(Vector3(-50.0, 5.57, z), Color("d2ddeb"), 1.0, 8.2)
	for z in [-24.35, -9.0, 9.0, 24.35]:
		_box("frame", Vector3(0.95, 6.88, 0.85), Vector3(-54.1, 3.44, z), true)
		_box("metal", Vector3(1.45, 0.24, 1.28), Vector3(-54.1, 0.12, z), true)
	return stations


func _control_room() -> Dictionary:
	var first_part := root.get_child_count()
	var first_solid := solids.size()
	_box("floor", Vector3(21.45, 0.039, 11.2), Vector3(0, 0.011, -30.0))
	_box("dark", Vector3(22.85, 0.65, 12.7), Vector3(0, 8.64, -30.25), true)
	_box("teal", Vector3(22.75, 8.35, 0.60), Vector3(0, 4.17, -36.3), true)
	for side in [-1.0, 1.0]:
		_box("frame", Vector3(0.74, 8.35, 12.25), Vector3(side * 11.17, 4.17, -30.22), true)
		_box("dark", Vector3(3.08, 8.35, 0.88), Vector3(side * 9.49, 4.17, -24.08), true)
		_box("metal", Vector3(0.42, 7.65, 0.96), Vector3(side * 7.75, 3.99, -24.02), true)
		_box("amber", Vector3(0.07, 1.42, 0.06), Vector3(side * 7.48, 4.30, -23.49))
		_box("frame", Vector3(3.51, 5.46, 2.33), Vector3(side * 6.87, 2.74, -34.64), true)
		_box("pale", Vector3(3.19, 5.0, 0.17), Vector3(side * 6.87, 2.72, -33.39))
		for i in 7:
			_box("dark", Vector3(2.53, 0.09, 0.06), Vector3(side * 6.87, 3.69 + i * 0.17, -33.28))
		_pipe("metal", [Vector3(side * 6.87, 5.47, -34.60), Vector3(side * 6.87, 6.99, -34.60),
			Vector3(side * 3.08, 7.66, -34.60)], 0.22)
	_box("dark", Vector3(6.62, 0.62, 0.62), Vector3(0, 7.67, -34.6), true)
	_box("metal", Vector3(1.36, 0.43, 1.33), Vector3(0, 7.72, -35.04))
	_box("frame", Vector3(15.15, 6.5, 0.88), Vector3(0, 11.6, -24.08), true)
	_box("metal", Vector3(15.4, 0.40, 1.0), Vector3(0, 8.12, -24.02), true)
	_box("dark", Vector3(7.12, 3.98, 1.05), Vector3(0, 5.64, -35.49), true)
	_box("frame", Vector3(6.67, 3.51, 0.22), Vector3(0, 5.63, -34.86))
	var status := _control_display(Vector3(0, 5.61, -34.72))
	_box("frame", Vector3(5.10, 1.76, 1.75), Vector3(0, 0.88, -31.67), true)
	_box("metal", Vector3(5.26, 0.24, 1.87), Vector3(0, 1.87, -31.67), true)
	_box("dark", Vector3(1.17, 0.32, 0.79), Vector3(0, 2.12, -31.13), true)
	for side in [-1.0, 1.0]:
		_box("frame", Vector3(0.73, 1.69, 1.85), Vector3(side * 2.17, 0.86, -31.64), true)
		_box("metal", Vector3(0.47, 1.39, 0.10), Vector3(side * 2.17, 0.86, -30.65))
		_box("dark", Vector3(0.77, 0.18, 0.16), Vector3(side * 1.92, 1.99, -31.24))
		_box("amber_paint", Vector3(0.12, 0.16, 0.65), Vector3(side * 0.66, 2.19, -31.10))
	_box("frame", Vector3(2.68, 0.39, 0.14), Vector3(0, 1.04, -30.72))
	_box("amber_paint", Vector3(0.57, 0.12, 0.53), Vector3(0, 2.33, -31.10))
	var indicator := _box("amber", Vector3(0.12, 0.085, 0.30), Vector3(0, 2.43, -31.10))
	indicator.name = "ControlStatusLight"
	var animation := Node3D.new()
	animation.name = "ControlAnimation"
	root.add_child(animation)
	indicator.reparent(animation, false)
	for z in [-26.4, -30.0, -34.25]:
		_fixture(Vector3(0, 8.07, z), 6.9)
	_sill(Vector3(0, 0.052, -24.52), 14.56)
	for i in 8:
		_box("amber_paint", Vector3(0.41, 0.015, 0.14),
			Vector3(-6.32 + i * 1.81, 0.074, -24.52))
	_box("frame", Vector3(3.48, 0.68, 0.31), Vector3(0, 7.75, -23.63), true)
	_label(Vector3(0, 7.73, -23.468), 0.0, "应急控制", 0.0104)
	var key := _key_plate(Vector3(0, 2.11, -30.718), 0)
	for i in range(first_part, root.get_child_count()):
		var part: Node3D = root.get_child(i)
		part.position += CONTROL_SHIFT
	for i in range(first_solid, solids.size()):
		var bounds := solids[i]
		bounds.position += CONTROL_SHIFT
		solids[i] = bounds
	status.merge({"stand": Vector3(0, 0, -29.94) + CONTROL_SHIFT,
		"prompt_label": key, "indicator": indicator,
		"ready_material": materials["amber"], "active_material": materials["red"],
		"film_camera": Vector3(-0.26, 3.98, -27.98) + CONTROL_SHIFT,
		"switch_aim": Vector3(0, 2.25, -31.09) + CONTROL_SHIFT,
		"screen_aim": Vector3(0.86, 5.4, -34.72) + CONTROL_SHIFT})
	return status


func _control_display(at: Vector3) -> Dictionary:
	var display := Node3D.new()
	display.name = "ControlScreenAnimation"
	display.position = at
	root.add_child(display)
	_box("dark", Vector3(6.10, 2.63, 0.07), Vector3.ZERO, false, 0, display)
	_box("teal", Vector3(2.82, 1.84, 0.025), Vector3(-1.47, -0.10, 0.053), false, 0, display)
	_box("teal", Vector3(2.82, 1.84, 0.025), Vector3(1.47, -0.10, 0.053), false, 0, display)
	_box("frame", Vector3(0.052, 1.83, 0.031), Vector3(0, -0.10, 0.061), false, 0, display)
	_box("metal", Vector3(5.55, 0.033, 0.031), Vector3(0, 1.08, 0.056), false, 0, display)
	var heading := _label(Vector3(-1.47, 0.51, 0.081), 0, "飞船自爆", 0.0067, display)
	heading.modulate = Color("dcc9b8")
	var recovery := _label(Vector3(1.47, 0.51, 0.081), 0, "技术简报", 0.0067, display)
	recovery.modulate = Color("a7d8dc")
	var arming := _label(Vector3(-1.47, -0.16, 0.081), 0, "待设定", 0.0093, display)
	arming.modulate = Color("ebba8a")
	var trace := _label(Vector3(1.47, -0.16, 0.081), 0, "资料索引", 0.0093, display)
	trace.modulate = Color("c2e6e7")
	var slots: Array[MeshInstance3D] = []
	for i in 5:
		_box("frame", Vector3(0.40, 0.112, 0.039),
			Vector3(-2.48 + i * 0.50, -0.69, 0.079), false, 0, display)
		slots.append(_box("frame", Vector3(0.40, 0.112, 0.039),
			Vector3(0.47 + i * 0.50, -0.69, 0.079), false, 0, display))
	var alarm := _box("red", Vector3(2.58, 0.042, 0.031),
		Vector3(-1.47, 0.94, 0.078), false, 0, display)
	alarm.hide()
	return {"alarm": alarm, "arming": arming, "memory_label": trace, "memory_slots": slots,
		"slot_off": materials["frame"], "slot_on": materials["cyan"]}


func _key_plate(at: Vector3, yaw: float) -> Label3D:
	_box("teal", Vector3(0.30, 0.235, 0.034), at, false, yaw)
	var normal := Vector3(sin(yaw), 0, cos(yaw))
	var key := _label(at + normal * 0.021, yaw, "", 0.0039)
	key.modulate = Color("e2eeef")
	key.hide()
	return key


func _display(at: Vector3, yaw: float, variant: int) -> Node3D:
	var display := Node3D.new()
	display.position = at
	display.rotation.y = yaw
	display.name = "PanelAnimation_%d" % root.get_child_count()
	root.add_child(display)
	_box("teal", Vector3(3.64, 2.00, 0.04), Vector3.ZERO, false, 0, display)
	for x in [-1.57, 1.57]:
		_box("frame", Vector3(0.035, 1.64, 0.052), Vector3(x, 0, 0.035), false, 0, display)
	for side in [-1.0, 1.0]:
		_box("frame", Vector3(0.36, 0.049, 0.04), Vector3(side * 1.30, 0.72, 0.005), false, 0, display)
	_box("archive", Vector3(0.10, 0.030, 0.028), Vector3(1.38, -0.68, 0.008), false, 0, display)
	var diagram := Node3D.new()
	diagram.name = "Schematic"
	display.add_child(diagram)
	_archive_diagram(diagram, variant)
	diagram.hide()
	return display


func _archive_diagram(diagram: Node3D, variant: int) -> void:
	var screen := QuadMesh.new()
	screen.size = Vector2(3.60, 1.95)
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_texture = ARCHIVE_ART[variant]
	ink.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var quad := MeshInstance3D.new()
	quad.mesh = screen
	quad.material_override = ink
	quad.position.z = 0.037
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	diagram.add_child(quad)
	match variant:
		0:
			_archive_caption(diagram, "躯壳重建", Vector2(-0.93, 0.69), 55)
			_archive_caption(diagram, "流程图", Vector2(1.10, 0.69), 31, Color("a7c4c9"))
			_archive_caption(diagram, "地面扫描", Vector2(-0.91, -0.74), 42)
			_archive_caption(diagram, "舱内打印", Vector2(0.91, -0.74), 42)
		1:
			_archive_caption(diagram, "意识独立上传", Vector2(-0.76, 0.69), 51)
			_archive_caption(diagram, "断线示意", Vector2(1.10, 0.69), 31, Color("d4bab3"))
			_archive_caption(diagram, "意识数据", Vector2(-1.00, -0.74), 40)
			_archive_caption(diagram, "传输断线", Vector2(0.04, -0.74), 37, Color("f2b39a"))
			_archive_caption(diagram, "可能缺失", Vector2(1.05, -0.74), 39)
		2:
			_archive_caption(diagram, "企业技术简报", Vector2(-0.76, 0.69), 51)
			_archive_caption(diagram, "麦克斯韦之瞳", Vector2(1.02, 0.69), 31, Color("d4bab3"))
			_archive_caption(diagram, "脱敏题解", Vector2(-0.87, -0.74), 42)
			_archive_caption(diagram, "红眼列装", Vector2(0.87, -0.74), 42, Color("eec49c"))


func _archive_caption(parent: Node3D, caption: String, point: Vector2, size: int,
		tint := Color("dce9ef")) -> void:
	var label := Label3D.new()
	label.text = caption
	label.font_size = size
	label.pixel_size = 0.00465
	label.outline_size = 0
	label.modulate = tint
	label.position = Vector3(point.x, point.y, 0.048)
	parent.add_child(label)


func _label(at: Vector3, yaw: float, caption: String, pixels: float,
		parent: Node3D = null) -> Label3D:
	var label := Label3D.new()
	label.position = at
	label.rotation.y = yaw
	label.text = caption
	label.font_size = 52
	label.pixel_size = pixels
	label.outline_size = 0
	label.modulate = Color("c6ccca")
	(root if parent == null else parent).add_child(label)
	return label


func _light(at: Vector3, tint: Color, energy: float, reach: float, shadows := false) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.05
	light.shadow_enabled = shadows
	root.add_child(light)



func _bulkhead_services() -> void:
	for z in [-59.57, 59.57]:
		var facing: float = -signf(z)
		_box("frame", Vector3(118.4, 2.32, 1.21), Vector3(0, 20.26, z), true)
		_box("metal", Vector3(117.8, 0.30, 0.34), Vector3(0, 19.04, z + facing * 0.59))
		for x in [-58.2, -41.0, -16.6, 16.6, 41.0, 58.2]:
			_box("frame", Vector3(1.41, 17.70, 1.38), Vector3(x, 11.73, z + facing * 0.07), true)
			_box("metal", Vector3(0.21, 13.01, 0.099), Vector3(x, 11.72, z + facing * 0.81))
			_box("dark", Vector3(1.77, 0.81, 1.55), Vector3(x, 18.79, z + facing * 0.07), true)
		for x in [-49.2, -33.1, 33.1, 49.2]:
			_box("frame", Vector3(1.03, 7.58, 0.69), Vector3(x, 15.11, z + facing * 0.15))
			_box("dark", Vector3(0.75, 2.84, 0.49), Vector3(x, 15.79, z + facing * 0.47))
			_box("cyan", Vector3(0.11, 1.05, 0.09), Vector3(x, 16.0, z + facing * 0.76))
		for x in [-9.95, 9.95]:
			_box("metal", Vector3(0.46, 1.46, 1.01), Vector3(x, 20.25, z + facing * 0.52))
	# Recessed distribution panels on both transverse bulkheads feed the floor and ceiling trays.
	for z in [-59.79, 59.79]:
		var facing := 1.0 if z < 0.0 else -1.0
		for x in [-49.0, -33.0, 33.0, 49.0]:
			_box("frame", Vector3(6.85, 11.80, 0.38), Vector3(x, 5.9, z), true)
			var skin := Vector3(x, 0, z + facing * 0.23)
			_box("pale", Vector3(6.58, 5.38, 0.13), skin + Vector3(0, 7.95, 0))
			_box("teal", Vector3(6.58, 4.96, 0.13), skin + Vector3(0, 2.64, 0))
			_box("dark", Vector3(6.05, 0.91, 0.17), skin + Vector3(0, 6.45, facing * 0.10))
			for i in 7:
				_box("metal", Vector3(5.75, 0.034, 0.048),
					skin + Vector3(0, 6.15 + i * 0.095, facing * 0.20))
			for side in [-1.0, 1.0]:
				var h := skin + Vector3(side * 2.53, 0, facing * 0.21)
				_box("frame", Vector3(0.52, 4.87, 0.24), h + Vector3.UP * 2.66)
				_box("metal", Vector3(0.45, 0.28, 0.30), h + Vector3.UP * 5.09)
				_pipe("metal", [h + Vector3.UP * 5.16,
					h + Vector3.UP * 5.64, h + Vector3(side * 0.37, 5.73, -facing * 0.11)], 0.084)
			_box("dark", Vector3(2.11, 2.52, 0.21), skin + Vector3(0, 2.53, facing * 0.12))
			_box("metal", Vector3(1.86, 2.24, 0.055), skin + Vector3(0, 2.53, facing * 0.25))
			_box("frame", Vector3(0.24, 0.45, 0.076), skin + Vector3(x * 0.028, 2.55, facing * 0.29))
			_box("cyan", Vector3(0.08, 0.12, 0.05), skin + Vector3(x * 0.028, 2.77, facing * 0.35))
	for x in [-23.0, 23.0]:
		_box("metal", Vector3(1.23, 0.61, 59.45), Vector3(x, 26.45, 0), true)
		_box("dark", Vector3(0.93, 0.22, 59.2), Vector3(x, 26.02, 0))
		for z in [-23.5, -14.1, -4.7, 4.7, 14.1, 23.5]:
			_box("frame", Vector3(1.72, 0.48, 0.25), Vector3(x, 25.86, z))
		for side in [-1.0, 1.0]:
			_box("metal", Vector3(0.68, 0.91, 0.76), Vector3(x, 26.24, side * 29.1))
	for x in [-31.25, 31.25]:
		for z in [-39.6, 39.6]:
			_box("dark", Vector3(2.28, 0.04, 5.39), Vector3(x, 0.014, z))
			for i in 17:
				_box("frame", Vector3(2.07, 0.024, 0.11),
					Vector3(x, 0.042, z + (i - 8) * 0.29))
			for side in [-1.0, 1.0]:
				_box("metal", Vector3(0.075, 0.030, 5.18), Vector3(x + side * 1.10, 0.047, z))
		_box("dark", Vector3(0.55, 0.018, 73.6), Vector3(x, 0.022, -0.4))
		_box("metal", Vector3(0.12, 0.018, 73.5), Vector3(x, 0.032, -0.4))


func _rack_face(at: Vector3) -> void:
	# Raised corners and removable cartridge separate the pump face from its rack.
	for side in [-1.0, 1.0]:
		var edge := at + Vector3(-1.61, 2.62, side * 1.91)
		_box("metal", Vector3(0.14, 4.19, 0.13), edge)
		for y in [-1.68, 1.68]:
			_cylinder("frame", 0.07, 0.14, edge + Vector3(-0.08, y, 0), Vector3(0, 0, PI / 2.0))
	_box("frame", Vector3(0.21, 0.44, 3.38), at + Vector3(-1.59, 1.08, 0))
	_box("dark", Vector3(0.083, 0.16, 1.32), at + Vector3(-1.72, 1.10, 0))
	_box("metal", Vector3(0.077, 0.09, 0.91), at + Vector3(-1.79, 1.10, 0))
	_box("frame", Vector3(3.28, 0.24, 4.70), at + Vector3(0.17, 5.14, 0))
	_box("metal", Vector3(3.31, 0.13, 0.40), at + Vector3(0.17, 5.33, -1.91))
	_box("metal", Vector3(3.31, 0.13, 0.40), at + Vector3(0.17, 5.33, 1.91))


func _lighting() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("31383d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4cdd1")
	env.ambient_light_energy = 0.82
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.34
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	for x in [-48.0, -23.0, 23.0, 48.0]:
		for z in [-47.0, -24.0, 0.0, 24.0, 47.0]:
			_light(Vector3(x, 16.8, z), Color("e4eeeb"), 3.75, 36.0, absf(x) == 23 and z == 24)
	_light(Vector3(0, 5.6, 67.0), Color("d7e8e6"), 2.4, 12)
	_light(Vector3(0, 8.0, 55.5), Color("d5e5e5"), 2.28, 22)
	_light(Vector3(0, 7.25, -65.2), Color("e5cfb5"), 3.40, 17, true)
	_light(Vector3(-6.0, 6.9, -67.6), Color("e0b88d"), 1.05, 10.0)
	_light(Vector3(0, 12.0, 0), Color("b8cbd1"), 2.10, 29)

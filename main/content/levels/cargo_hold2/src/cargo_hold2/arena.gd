extends RefCounted
## Cargo bay dimensions and prop placement are shared with the chapter choreography.
const Kit = preload("res://src/cargo_hold2/mesh_kit.gd")
const CargoContainer = preload("res://src/cargo_hold2/container.gd")
const NormalMap = preload("res://src/cargo_hold2/container_normal.gd")

const HALF_WIDTH := 42.0
const HALF_DEPTH := 46.0
const CEILING := 20.0
const PLAYER_SPAWN := Vector3(-18, 0, 39)
const BASIC_SPAWN := Vector3(1, 0, -18)
const TARGET := Vector3(-22, 2.6, 21)
const EXIT_X := 27.0
const EXIT_DOOR_Z := -32.0
const EXIT_TRIGGER := Rect2(23.5, -43.0, 7.0, 4.5)
const EXIT_ROOF_Y := 8.475

var _root := Node3D.new()
var _kit := Kit.new()
# Ground obstacles feed navigation. The full set also includes boxes above the ground.
var _solids: Array[AABB] = []
var _camera_solids: Array[AABB] = []
var _blade_boxes: Array[AABB] = []
var _walls: Array = []
var _beacons: Array[OmniLight3D] = []
var _beacon_material: StandardMaterial3D


static func build() -> Dictionary:
	return new()._build()


static func nav_spec() -> Dictionary:
	return {
		"floor_margin": 3.0,
		"walls_obstacles": false,
		"platforms": false,
	}


func _build() -> Dictionary:
	_root.name = "CargoHold02"
	_materials(_kit)
	_shell()
	_recovery_container()
	_work_bay()
	_threshold()
	_loading_deck()
	_service_wall()
	var gate := _airlock()
	var guide := _guide()
	_build_alarm_fixtures()
	_kit.commit(_root, "CargoStructure")
	_lighting()
	return {
		"node": _root, "kind": "cargo_hold2", "name_cn": "货舱 02",
		"hint": "适应义体，突破巡检哨兵，沿指引撤离。",
		"floor_y": 0.0, "bounds": AABB(Vector3(-HALF_WIDTH, 0, -HALF_DEPTH),
			Vector3(HALF_WIDTH * 2, CEILING, HALF_DEPTH * 2)),
		"walls": _walls, "cover": [], "solids": _solids, "camera_solids": _camera_solids,
		"blade_boxes": _blade_boxes,
		"player_spawn": Transform3D(Basis.IDENTITY, PLAYER_SPAWN),
		"gate": gate, "guide": guide, "beacons": _beacons, "beacon_material": _beacon_material,
	}


static func _shader(file: String, values: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://gfx/cargo_hold2/" + file + ".gdshader")
	for key in values:
		mat.set_shader_parameter(key, values[key])
	return mat


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.35
	return mat


static func _materials(kit: CargoMeshKit) -> void:
	kit.material("floor", _shader("plate", {"base_col": Color("797d82"), "tile_m": 2.7,
		"metal_base": 0.46, "rough_bias": -0.17}))
	kit.material("wall", _shader("wall", {"base_col": Color("74787d"), "trim_col": Color("363a40"),
		"accent_col": Color("8f8273"), "style": 4, "grime": 0.32, "rough_bias": -0.13}))
	for pair in [["metal", "a6adb5", 0.29], ["metal_dark", "34383e", 0.38],
		["orion_frame", "585d64", 0.36], ["track", "767a81", 0.33]]:
		kit.material(pair[0], _shader("metal", {"tint": Color(pair[1]), "rough_base": pair[2],
			"rust_amount": 0.05, "oil_grime": 0.13}))
	kit.material("bare_steel", _shader("metal", {"tint": Color("acb4bd"), "rough_base": 0.23,
		"rust_amount": 0.06, "oil_grime": 0.19}))
	kit.material("safety_yellow", _shader("metal", {"tint": Color("aa9375"), "rough_base": 0.42,
		"metal_amount": 0.31, "pattern": 1}))
	kit.material("tread", _shader("plate", {"base_col": Color("4b4e54"), "grate": 1.0,
		"tile_m": 1.4, "rough_bias": 0.02}))
	var normal := NormalMap.texture()
	for i in 3:
		kit.material("container_" + str(i), _shader("container", {
			"paint": [Color("626b74"), Color("737078"), Color("807a70")][i],
			"seed": float(i + 2), "rust": 0.06, "surface_normal": normal}))
	for detail in [["cyan", "83bdc5", 1.15], ["violet", "aea4c4", 0.80], ["amber", "d9b590", 0.68],
		["white", "e5e7eb", 1.53], ["paint", "a99787", 0.08]]:
		kit.material(detail[0], _glow(Color(detail[1]), detail[2]))


func _shell() -> void:
	var floor_size := Vector3(85, 0.55, 93)
	_kit.box("floor", floor_size, Vector3(0, -0.275, 0))
	_body(Vector3(0, -0.275, 0), floor_size)
	_box("metal_dark", Vector3(0, 20.25, 0), Vector3(85, 0.5, 93), true, false)
	for side in [-1.0, 1.0]:
		_box("wall", Vector3(side * 42.4, 10, 0), Vector3(0.8, 20, 93), true)
		_box("wall", Vector3(0, 10, side * 46.4), Vector3(84, 20, 0.8), true)
		for y in [4.8, 15.8]:
			_kit.tube("orion_frame", [Vector3(side * 41.3, y, -44), Vector3(side * 41.3, y, 44)], 0.18, 8)
		for z in range(-39, 40, 9):
			_kit.box_bevel("orion_frame", Vector3(0.95, 19.6, 0.64), Vector3(side * 41.5, 9.8, z), 0.07)
			_kit.box_bevel("metal_dark", Vector3(0.55, 2.9, 5.5), Vector3(side * 41.45, 5.8, z + 2.9), 0.10)
			for groove in 6:
				_kit.box("metal", Vector3(0.12, 0.10, 3.5), Vector3(side * 41.1, 4.85 + groove * 0.24, z + 2.9))
			_kit.box("violet", Vector3(0.09, 1.7, 0.14), Vector3(side * 40.96, 5.5, z))
	for z in range(-36, 43, 13):
		_kit.box_bevel("orion_frame", Vector3(82, 1.1, 0.65), Vector3(0, 18.9, z), 0.12)
		for x in [-26.0, -11.0, 11.0, 26.0]:
			_kit.box_bevel("metal_dark", Vector3(5.3, 0.42, 1.2), Vector3(x, 17.8, z), 0.06)
			_kit.box("white", Vector3(4.65, 0.045, 0.4), Vector3(x, 17.55, z))


func _recovery_container() -> void:
	var x := PLAYER_SPAWN.x
	for side in [-1.0, 1.0]:
		_box("container_1", Vector3(x + side * 4.5, 3.25, 36), Vector3(0.40, 6.5, 14), true)
		_box("orion_frame", Vector3(x + side * 4.18, 2.2, 29.05), Vector3(0.36, 4.3, 0.52), true)
		for z in range(30, 43, 2):
			_kit.box_bevel("orion_frame", Vector3(0.20, 5.5, 0.24), Vector3(x + side * 4.23, 3.1, z), 0.04)
			_kit.box("metal", Vector3(0.12, 0.12, 0.12), Vector3(x + side * 4.08, 2.1, z))
		_kit.tube("metal", [Vector3(x + side * 4.13, 5.65, 30), Vector3(x + side * 4.13, 5.65, 41.8)], 0.088, 8)
		_kit.box("violet", Vector3(0.095, 0.10, 2.6), Vector3(x + side * 4.09, 4.12, 31))
	_box("container_1", Vector3(x, 3.25, 43.08), Vector3(9.4, 6.5, 0.40), true)
	_box("orion_frame", Vector3(x, 6.72, 36), Vector3(9.4, 0.47, 14.3), true, false)
	_box("metal_dark", Vector3(x, 5.98, 29.05), Vector3(9.5, 0.52, 0.60), true, false)
	_kit.box("white", Vector3(6.7, 0.05, 0.24), Vector3(x, 5.68, 29.1))
	for z in [30.4, 35.1, 39.5]:
		_kit.box_bevel("metal_dark", Vector3(7.4, 0.07, 3.8), Vector3(x, 0.025, z), 0.05)
		for lane in [-3.38, 3.38]:
			_kit.box("track", Vector3(0.24, 0.04, 3.4), Vector3(x + lane, 0.085, z))
	for side in [-1.0, 1.0]:
		_kit.box_bevel("metal_dark", Vector3(0.65, 2.9, 3.6), Vector3(x + side * 3.75, 1.55, 41.2), 0.10)
		_kit.box("cyan", Vector3(0.04, 0.15, 0.64), Vector3(x + side * 3.40, 2.51, 40.45))
		_kit.box_bevel("orion_frame", Vector3(0.40, 1.4, 2.3), Vector3(x + side * 3.39, 1.97, 40.44), 0.09)
		_kit.box("metal_dark", Vector3(0.05, 0.9, 1.64), Vector3(x + side * 3.16, 1.97, 40.44))
		for pin in 4:
			_kit.box("amber" if pin == 0 else "cyan", Vector3(0.048, 0.085, 0.24),
				Vector3(x + side * 3.12, 2.14, 39.9 + pin * 0.29))
		_kit.tube("track", [Vector3(x + side * 3.65, 1.48, 39.30),
			Vector3(x + side * 3.34, 0.99, 39.14), Vector3(x + side * 3.33, 0.30, 37.68),
			Vector3(x + side * 3.68, 0.28, 36.44)], 0.084, 10)
	_kit.box_bevel("orion_frame", Vector3(5.78, 0.82, 0.19), Vector3(x, 4.98, 42.80), 0.10)
	_panel("RECOVERY / C-02", Vector3(x, 5.03, 42.66), 0.105, PI)
	for z in [30.2, 36.0, 41.7]:
		_kit.box_bevel("orion_frame", Vector3(8.82, 0.27, 0.28), Vector3(x, 6.42, z), 0.05)
	_kit.box_bevel("metal_dark", Vector3(2.6, 0.20, 5.8), Vector3(x, 6.37, 37.1), 0.08)
	_kit.box("violet", Vector3(0.19, 0.045, 4.75), Vector3(x, 6.24, 37.1))
	_panel("C-02", Vector3(x, 6.04, 28.72), 0.14, PI)
	_recovery_rack(x)


func _recovery_rack(x: float) -> void:
	var station_z := 33.6
	for side in [-1.0, 1.0]:
		var upright := Vector3(x + side * 3.78, 2.25, station_z)
		_box("metal_dark", upright, Vector3(0.76, 4.50, 1.62), true)
		_kit.box_bevel("orion_frame", Vector3(0.60, 4.23, 0.25), upright + Vector3(0, 0, 0.83), 0.075)
		_kit.box_bevel("bare_steel", Vector3(0.073, 3.32, 0.32),
			upright + Vector3(-side * 0.39, 0.15, 0.27), 0.027)
		for y in [1.42, 3.28]:
			var hinge := Vector3(upright.x - side * 0.46, y, station_z + 0.43)
			_kit.tube("safety_yellow", [hinge + Vector3(side * 0.12, 0, 0), hinge,
				hinge + Vector3(-side * 0.17, 0.20, 0.51),
				hinge + Vector3(-side * 0.17, 0.44, 0.77)], 0.105, 8)
			_kit.box_bevel("metal_dark", Vector3(0.25, 0.26, 0.22),
				hinge + Vector3(-side * 0.17, 0.49, 0.77), 0.05)
			_obstacle(hinge + Vector3(-side * 0.11, 0.23, 0.39), Vector3(0.42, 0.80, 1.02), false)
		_kit.box("cyan", Vector3(0.22, 0.10, 0.045), upright + Vector3(0, 1.82, 0.98))
		_kit.box("safety_yellow", Vector3(0.15, 0.013, 7.0), Vector3(x + side * 2.1, 0.078, 36.4))
	_box("orion_frame", Vector3(x, 5.14, station_z), Vector3(8.22, 0.43, 1.28), true, false)
	_kit.box_bevel("metal_dark", Vector3(2.84, 0.28, 0.80), Vector3(x, 4.83, station_z + 0.03), 0.075)
	_kit.box("white", Vector3(1.88, 0.036, 0.18), Vector3(x, 4.68, station_z + 0.35))
	_panel("RELEASED", Vector3(x, 4.79, station_z + 0.45), 0.052)
	_kit.tube("track", [Vector3(x - 3.96, 4.48, 36.8), Vector3(x - 3.76, 4.03, 36.4),
		Vector3(x - 3.48, 3.58, 35.66), Vector3(x - 3.28, 3.61, 35.06),
		Vector3(x - 3.30, 3.78, 34.92)], 0.098, 9)
	_kit.box_bevel("safety_yellow", Vector3(0.20, 0.23, 0.32), Vector3(x - 3.30, 3.76, 34.85), 0.044)
	_kit.box("tread", Vector3(4.02, 0.026, 1.50), Vector3(x, 0.097, station_z + 0.16))


func _work_bay() -> void:
	# A low work bay controls the first view into the much taller loading hall.
	_box("wall", Vector3(-24, 4.2, 11), Vector3(34.5, 8.4, 1.2), true)
	_box("metal_dark", Vector3(-22.4, 8.43, 19), Vector3(37.4, 0.46, 17.0), true, false)
	for x in [-37.0, -29.0, -18.0, -9.0]:
		_box("orion_frame", Vector3(x, 3.25, 11.7), Vector3(0.62, 6.5, 0.56), true)
		_kit.box_bevel("metal_dark", Vector3(5.5, 2.3, 0.37), Vector3(x, 3.1, 12.04), 0.09)
		_kit.box_bevel("orion_frame", Vector3(5.45, 0.75, 0.55), Vector3(x, 6.8, 12), 0.06)
		_kit.tube("metal", [Vector3(x - 2.45, 6.64, 12.32), Vector3(x + 2.18, 6.64, 12.32),
			Vector3(x + 2.39, 6.37, 12.32), Vector3(x + 2.39, 5.9, 12.32)], 0.077, 8)
		for segment in 5:
			_kit.box("metal", Vector3(4.25, 0.08, 0.10), Vector3(x, 2.36 + segment * 0.27, 12.28))
		_kit.box("violet", Vector3(0.16, 1.7, 0.08), Vector3(x - 2.32, 3.14, 12.28))
	_kit.box_bevel("metal_dark", Vector3(13.2, 0.86, 0.49), Vector3(-18, 5.59, 12.32), 0.09)
	_kit.box("violet", Vector3(11.81, 0.064, 0.11), Vector3(-18, 5.31, 12.58))
	_panel("CARGO 02   /   LOADING DECK  >", Vector3(-18, 5.60, 12.62), 0.12)
	_terminal(Vector3(-33, 0, 20))
	_pallet(Vector3(-32.5, 0, 31))
	_pallet(Vector3(-27.5, 0, 30.5))
	_pallet(Vector3(-34.5, 0, 24.6))
	_kit.box_bevel("metal_dark", Vector3(2.6, 0.12, 5.25), Vector3(-27.8, 0.05, 15.5), 0.08)
	for index in 7:
		_kit.box("paint", Vector3(0.28, 0.025, 0.12), Vector3(-27.8, 0.125, 13.55 + index * 0.53))
	_practice_fixture()
	for x in [-4.4, 6.4]:
		for z in [8.0, 11.0, 14.0, 17.0, 20.0, 23.0]:
			_kit.box("paint", Vector3(0.15, 0.022, 1.35), Vector3(x, 0.024, z))
	for x in [-30.0, -12.0]:
		_kit.box_bevel("metal_dark", Vector3(6.7, 0.24, 0.45), Vector3(x, 8.04, 20), 0.05)
		_kit.box("white", Vector3(6.2, 0.04, 0.24), Vector3(x, 7.89, 20))
	for z in [14.6, 23.8, 26.0]:
		_kit.box_bevel("orion_frame", Vector3(35.7, 0.52, 0.74), Vector3(-22.9, 8.02, z), 0.08)
		_kit.box("metal_dark", Vector3(35.1, 0.14, 0.42), Vector3(-22.9, 7.7, z))
	for x in [-24.8, -11.2]:
		_kit.tube("metal", [Vector3(x, 7.69, 26), Vector3(x, 7.69, 15.3),
			Vector3(x, 6.86, 13.46), Vector3(x, 6.55, 12.14)], 0.12, 10)
	for i in 3:
		var place := Vector3(-38.1 + i * 3.03, 0.0, 15.0)
		_box("metal_dark", place + Vector3.UP * 1.46, Vector3(2.78, 2.91, 1.46), true)
		_kit.box_bevel("orion_frame", Vector3(2.49, 2.62, 0.13), place + Vector3(0, 1.48, 0.77), 0.08)
		_kit.box("metal", Vector3(0.07, 0.55, 0.16), place + Vector3(0.92, 1.47, 0.87))
		_kit.box("cyan", Vector3(0.61, 0.065, 0.07), place + Vector3(-0.64, 2.32, 0.89))


func _practice_fixture() -> void:
	# Keep the replaceable plate centered on TARGET for the tutorial's blade sweep.
	_box("metal_dark", Vector3(TARGET.x, 0.35, TARGET.z), Vector3(1.85, 0.7, 1.35), true)
	_kit.box_bevel("orion_frame", Vector3(1.58, 0.24, 1.04), Vector3(TARGET.x, 0.61, TARGET.z), 0.07)
	for side in [-1.0, 1.0]:
		_kit.tube("track", [TARGET + Vector3(side * 0.63, -1.96, -0.26),
			TARGET + Vector3(side * 0.44, -0.78, -0.27),
			TARGET + Vector3(side * 0.44, 0.55, -0.27)], 0.16, 8)
		for y in [-0.62, 0.62]:
			var pin := TARGET + Vector3(side * 0.94, y, 0.09)
			_kit.box_bevel("safety_yellow", Vector3(0.35, 0.28, 0.45), pin, 0.055)
			_kit.box_bevel("metal_dark", Vector3(0.16, 0.15, 0.12), pin + Vector3.BACK * 0.26, 0.025)
	_kit.box_bevel("metal_dark", Vector3(2.21, 1.62, 0.28), TARGET - Vector3.BACK * 0.06, 0.13)
	_kit.prism("bare_steel", [Vector2(-0.83, -0.64), Vector2(0.83, -0.64),
		Vector2(1.0, -0.47), Vector2(1.0, 0.47), Vector2(0.83, 0.64), Vector2(-0.83, 0.64),
		Vector2(-1.0, 0.47), Vector2(-1.0, -0.47)], 0.19, TARGET + Vector3.BACK * 0.14)
	for cut in [[-0.85, -0.13, -0.21, 0.01], [-0.24, -0.30, 0.63, 0.10], [0.02, 0.04, 0.81, 0.34]]:
		var start := TARGET + Vector3(cut[0], cut[1], 0.238)
		var end := TARGET + Vector3(cut[2], cut[3], 0.238)
		var deep := start.lerp(end, 0.38) + Vector3.UP * 0.021
		_kit.poly("metal_dark", [start, deep, end], Vector3.BACK)
		_kit.poly("track", [start, end, deep - Vector3.UP * 0.036], Vector3.BACK)
	_kit.box_bevel("orion_frame", Vector3(1.44, 0.28, 0.18), TARGET + Vector3(0, 0.96, 0.01), 0.04)
	_kit.box("amber", Vector3(0.20, 0.055, 0.035), TARGET + Vector3(-0.5, 0.96, 0.12))
	_panel("ARM CHECK", TARGET + Vector3(0.11, 0.96, 0.12), 0.041)


func _threshold() -> void:
	var z := 8.75
	for side in [-1.0, 1.0]:
		var x: float = side * 6.45
		_box("orion_frame", Vector3(x, 4.7, z), Vector3(1.02, 9.4, 1.20), true)
		_kit.box_bevel("metal_dark", Vector3(0.75, 7.0, 0.29), Vector3(x, 3.75, z + 0.68), 0.08)
		_kit.tube("cyan", [Vector3(x, 1.35, z + 0.86), Vector3(x, 6.65, z + 0.86),
			Vector3(x - side * 0.34, 7.20, z + 0.86)], 0.057, 10)
		_kit.box("paint", Vector3(1.32, 0.27, 0.20), Vector3(x, 0.45, z + 0.71))
	_box("orion_frame", Vector3(0, 9.1, z), Vector3(14.1, 1.1, 1.4), true, false)
	_kit.box_bevel("metal_dark", Vector3(9.3, 0.77, 0.19), Vector3(0, 9.07, z + 0.75), 0.09)
	_kit.box("violet", Vector3(8.75, 0.067, 0.1), Vector3(0, 8.71, z + 0.88))
	_panel("TURN  /  LOADING 02", Vector3(0, 9.12, z + 0.88), 0.095)


func _loading_deck() -> void:
	var crates := CargoContainer.new(_kit)
	var groups := [
		[Vector3(-25, 0, 0), 0, Vector3(10, 5.5, 6), true],
		[Vector3(-28, 0, -14), 1, Vector3(11, 5.6, 6.5), false],
		[Vector3(-16, 0, -25), 2, Vector3(9, 5.0, 6.2), false],
		[Vector3(20, 0, 5), 1, Vector3(10, 5.6, 6.3), true],
		[Vector3(12.5, 0, -5), 0, Vector3(6.5, 4.5, 5.2), false],
		[Vector3(23, 0, -14), 2, Vector3(10.5, 5.6, 6.2), false],
		[Vector3(31, 0, 26), 0, Vector3(11, 5.0, 6.5), true],
		[Vector3(13, 0, 28), 1, Vector3(9, 4.8, 6.2), false],
	]
	for entry in groups:
		var at: Vector3 = entry[0]
		var size: Vector3 = entry[2]
		crates.container(at, "container_%d" % entry[1], 0, size)
		_obstacle(at + Vector3.UP * size.y * 0.5, size + Vector3(0.32, 0.0, 0.23), true)
		if entry[3]:
			var upper := Vector3(size.x - 0.55, 4.6, size.z - 0.35)
			crates.container(at + Vector3.UP * size.y, "container_%d" % ((int(entry[1]) + 1) % 3), 0, upper)
			_obstacle(at + Vector3.UP * (size.y + upper.y * 0.5), upper, false)
		_panel("H02 / %02d" % (groups.find(entry) + 1), at + Vector3(-size.x * 0.23, size.y - 1.1, size.z * 0.5 + 0.30), 0.09)
	for x in [-8.0, 8.0]:
		for z in range(-26, 9, 4):
			_kit.box("paint", Vector3(0.16, 0.028, 2.3), Vector3(x, 0.028, z))
		for z in [-21.0, -11.0, -1.0, 8.0]:
			_kit.box_bevel("metal_dark", Vector3(1.9, 0.07, 1.05), Vector3(x, 0.029, z), 0.07)
			for rib in 5:
				_kit.box("metal", Vector3(1.6, 0.027, 0.06), Vector3(x, 0.083, z - 0.34 + rib * 0.17))
	for x in [-18.5, 19.0]:
		_kit.box_bevel("track", Vector3(0.52, 0.85, 54), Vector3(x, 14.65, -3), 0.07)
		_kit.box("metal_dark", Vector3(0.26, 0.32, 54), Vector3(x, 15.13, -3))
		for z in [-26.0, -13.0, 0.0, 13.0, 23.0]:
			_kit.box("orion_frame", Vector3(0.36, 3.7, 0.32), Vector3(x, 16.55, z))
	_kit.box_bevel("orion_frame", Vector3(38.7, 0.95, 1.8), Vector3(0.25, 14.08, -4), 0.10)
	_cargo_spreader(crates)
	for x in [-17.0, 17.0]:
		_kit.box("violet", Vector3(2.9, 0.07, 0.12), Vector3(x, 13.55, -3.04))
	_box("wall", Vector3(0, 5.0, -27.5), Vector3(14, 10, 1.05), true)
	_kit.box_bevel("metal_dark", Vector3(10.5, 7.9, 0.38), Vector3(0, 4.0, -26.66), 0.16)
	for j in 10:
		_kit.box("orion_frame", Vector3(9.1, 0.35, 0.09), Vector3(0, 1.0 + j * 0.62, -26.42))
	for side in [-1.0, 1.0]:
		_kit.box("cyan", Vector3(0.12, 5.6, 0.09), Vector3(side * 4.9, 4.2, -26.41))
		_kit.box_bevel("orion_frame", Vector3(0.95, 6.44, 0.20), Vector3(side * 6.34, 3.58, -26.89), 0.12)
		_kit.box_bevel("metal_dark", Vector3(0.64, 1.34, 0.17), Vector3(side * 6.34, 3.36, -26.75), 0.09)
		_kit.box("amber", Vector3(0.31, 0.078, 0.04), Vector3(side * 6.34, 3.70, -26.64))
		_kit.tube("bare_steel", [Vector3(side * 6.34, 5.45, -26.70),
			Vector3(side * 6.34, 7.54, -26.70), Vector3(side * 5.85, 8.05, -26.71),
			Vector3(side * 5.21, 8.05, -26.73)], 0.087, 8)
	_kit.box_bevel("metal_dark", Vector3(7.9, 0.47, 0.50), Vector3(0, 7.93, -26.65), 0.08)
	_kit.box("white", Vector3(6.7, 0.055, 0.18), Vector3(0, 7.68, -26.55))
	_panel("SECURITY / D-03", Vector3(0, 8.94, -26.85), 0.16)
	_elevated_service_gallery()
	for group in [Vector3(-20, 0, -31), Vector3(-31, 0, -30), Vector3(17.1, 0, -31)]:
		_pallet(group)
		_kit.box_bevel("orion_frame", Vector3(4.8, 0.055, 3.6), group + Vector3.UP * 0.025, 0.04)
		for side in [-1.0, 1.0]:
			_kit.box("paint", Vector3(0.15, 0.018, 3.03), group + Vector3(2.23 * side, 0.065, 0))
	_pallet(Vector3(34, 0, 15))
	_terminal(Vector3(34.5, 0, 9.5))


func _cargo_spreader(crates: CargoContainer) -> void:
	var trolley := Vector3(-9.4, 13.85, -4.0)
	_box("metal_dark", trolley, Vector3(5.0, 1.18, 3.0), true, false)
	for side in [-1.0, 1.0]:
		_kit.box_bevel("safety_yellow", Vector3(4.54, 0.92, 0.24),
			trolley + Vector3(0, -0.04, side * 1.52), 0.09)
		for mark in [-1.75, 1.75]:
			_kit.box("metal_dark", Vector3(0.22, 0.76, 0.035),
				trolley + Vector3(mark, -0.03, side * 1.66))
		_kit.box("amber", Vector3(0.67, 0.10, 0.046),
			trolley + Vector3(0, -0.19, side * 1.66))
		for x in [-2.06, 2.06]:
			_kit.tube("track", [trolley + Vector3(x * 0.67, -0.60, side * 0.81),
				Vector3(trolley.x + x, 11.93, trolley.z + side * 1.01)], 0.088, 8)
	var spreader := Vector3(trolley.x, 11.80, trolley.z)
	_box("orion_frame", spreader, Vector3(5.2, 0.32, 2.45), true, false)
	for x in [-2.20, 2.20]:
		for z in [-1.04, 1.04]:
			var lock := spreader + Vector3(x, -0.21, z)
			_kit.box_bevel("safety_yellow", Vector3(0.54, 0.46, 0.44), lock, 0.06)
			_kit.box_bevel("bare_steel", Vector3(0.26, 0.25, 0.24), lock - Vector3.UP * 0.22, 0.036)
	var crate := Vector3(trolley.x, 9.19, trolley.z)
	var size := Vector3(4.92, 2.25, 2.31)
	crates.container(crate, "container_2", 0.0, size)
	_obstacle(crate + Vector3.UP * size.y * 0.5, size + Vector3(0.48, 0.04, 0.30), false)
	_panel("H02 / LIFT 01", crate + Vector3(0, 1.09, 1.35), 0.077)
	for side in [-1.0, 1.0]:
		_kit.box_bevel("metal_dark", Vector3(2.1, 0.23, 0.81), spreader + Vector3(0, -0.11, side * 0.61), 0.06)
		_kit.box("white", Vector3(1.49, 0.05, 0.16), spreader + Vector3(0, -0.23, side * 0.61))


func _elevated_service_gallery() -> void:
	# The inhabited deck over the freight machinery gives the bay a second visual scale.
	_box("orion_frame", Vector3(-31, 10.34, -18.7), Vector3(9.2, 0.6, 28.0), true, false)
	_kit.box_bevel("metal_dark", Vector3(0.56, 0.93, 28.3), Vector3(-26.55, 10.27, -18.7), 0.07)
	_kit.box("violet", Vector3(0.065, 0.082, 25.5), Vector3(-26.23, 10.09, -18.7))
	_kit.box("cyan", Vector3(0.061, 0.069, 7.2), Vector3(-26.20, 10.34, -9.3))
	for z in [-31.0, -25.0, -19.0, -13.0, -7.0]:
		_kit.box_bevel("orion_frame", Vector3(9.0, 0.46, 0.37), Vector3(-31, 9.82, z), 0.07)
		_kit.box_bevel("metal", Vector3(0.15, 1.46, 0.16), Vector3(-26.54, 11.31, z), 0.024)
		_kit.tube("metal_dark", [Vector3(-35.15, 8.39, z), Vector3(-29.5, 10.04, z)], 0.13, 8)
		_kit.box("white", Vector3(3.8, 0.042, 0.24), Vector3(-29.60, 9.57, z))
	_kit.tube("metal", [Vector3(-26.54, 12.02, -32.6), Vector3(-26.54, 12.02, -5.2)], 0.08, 8)
	_kit.tube("orion_frame", [Vector3(-26.54, 11.39, -32.6), Vector3(-26.54, 11.39, -5.2)], 0.055, 8)
	_panel("SERVICE  /  03", Vector3(-26.18, 10.45, -14.2), 0.098, PI * 0.5)


func _service_wall() -> void:
	for side in [-1.0, 1.0]:
		for z in [-23.0, -7.0, 9.0, 25.0]:
			var x: float = side * 40.8
			_kit.box_bevel("orion_frame", Vector3(0.92, 7.3, 7.7), Vector3(x, 5.48, z), 0.12)
			_kit.box_bevel("metal_dark", Vector3(0.17, 6.1, 5.95), Vector3(x - side * 0.47, 5.29, z), 0.10)
			for band in [-1.5, 0.0, 1.5]:
				_kit.box("metal", Vector3(0.18, 1.15, 0.07), Vector3(x - side * 0.58, 5.61 + band, z - 2.15))
			_kit.tube("track", [Vector3(x - side * 0.53, 2.2, z + 3.0),
				Vector3(x - side * 0.63, 6.53, z + 3.0),
				Vector3(x - side * 0.63, 8.06, z + 1.87),
				Vector3(x - side * 0.63, 8.06, z - 2.74)], 0.13, 8)
			_kit.box("cyan", Vector3(0.065, 0.10, 1.7), Vector3(x - side * 0.65, 7.58, z - 0.21))
			for dz in [-2.65, 2.65]:
				_kit.box("amber", Vector3(0.07, 0.15, 0.25), Vector3(x - side * 0.56, 2.55, z + dz))


func _airlock() -> Dictionary:
	for side in [-1.0, 1.0]:
		var x: float = EXIT_X + side * 5.5
		_box("wall", Vector3(x, 4.35, -38.1), Vector3(0.88, 8.7, 12.6), true)
		_box("orion_frame", Vector3(x, 4.72, EXIT_DOOR_Z), Vector3(1.1, 9.44, 0.95), true)
		_kit.box("cyan", Vector3(0.12, 4.8, 0.095), Vector3(x, 4.3, EXIT_DOOR_Z + 0.51))
		for z in [-35.7, -40.0]:
			_kit.box_bevel("metal_dark", Vector3(0.34, 2.5, 2.85), Vector3(x - side * 0.52, 4.25, z), 0.08)
			_kit.box("violet", Vector3(0.095, 0.12, 2.34), Vector3(x - side * 0.74, 4.9, z))
	_box("orion_frame", Vector3(EXIT_X, EXIT_ROOF_Y + 0.275, -38.1), Vector3(11.8, 0.55, 12.6), true, false)
	_box("metal_dark", Vector3(EXIT_X, 8.28, EXIT_DOOR_Z), Vector3(12.4, 1.05, 1.2), true, false)
	_kit.box_bevel("orion_frame", Vector3(11.8, 7.5, 0.82), Vector3(EXIT_X, 12.55, EXIT_DOOR_Z + 0.70), 0.18)
	_kit.box("metal_dark", Vector3(9.4, 5.8, 0.17), Vector3(EXIT_X, 12.65, EXIT_DOOR_Z + 1.14))
	for x in [-4.0, 4.0]:
		_kit.box("violet", Vector3(0.12, 4.3, 0.08), Vector3(EXIT_X + x, 12.6, EXIT_DOOR_Z + 1.25))
	_panel("GALLERIA   /   EGRESS", Vector3(EXIT_X, 8.25, EXIT_DOOR_Z + 0.63), 0.135)
	_kit.box_bevel("orion_frame", Vector3(9.43, 7.2, 0.34), Vector3(EXIT_X, 3.68, -45.55), 0.16)
	_kit.box_bevel("metal_dark", Vector3(7.89, 6.14, 0.14), Vector3(EXIT_X, 3.34, -45.32), 0.10)
	_kit.box("cyan", Vector3(6.24, 0.075, 0.08), Vector3(EXIT_X, 1.02, -45.20))
	_panel("DECK 02", Vector3(EXIT_X, 5.6, -45.21), 0.104)
	_panel("CENTRAL GALLERIA", Vector3(EXIT_X, 4.94, -45.21), 0.083)
	_pressure_hatch_detail()
	_plate(Vector3(EXIT_X, 0.03, EXIT_DOOR_Z + 0.5), 9.7)
	for z in [-35.9, -41.0]:
		_kit.box("white", Vector3(7.4, 0.04, 0.36), Vector3(EXIT_X, 8.44, z))
		_kit.box_bevel("metal_dark", Vector3(11.0, 0.46, 0.68), Vector3(EXIT_X, 8.23, z + 0.44), 0.08)
		for side in [-1.0, 1.0]:
			_kit.box_bevel("orion_frame", Vector3(0.36, 7.9, 0.61), Vector3(EXIT_X + side * 4.88, 4, z + 0.44), 0.06)
			_kit.box("violet", Vector3(0.115, 3.03, 0.08), Vector3(EXIT_X + side * 4.78, 4.2, z + 0.81))
		_kit.box("track", Vector3(8.6, 0.026, 0.21), Vector3(EXIT_X, 0.031, z + 0.43))
	var frame := Node3D.new()
	frame.name = "EvacuationGate"
	frame.position = Vector3(EXIT_X, 0, EXIT_DOOR_Z)
	_root.add_child(frame)
	var leaf := Kit.new()
	for key in ["orion_frame", "metal_dark", "metal", "violet"]:
		leaf.material(key, _kit.mats[key])
	leaf.box_bevel("orion_frame", Vector3(9.92, 7.7, 0.58), Vector3(0, 3.85, 0), 0.14)
	for x in [-2.28, 2.28]:
		leaf.box_bevel("metal_dark", Vector3(4.21, 6.9, 0.16), Vector3(x, 3.83, 0.35), 0.16)
		for y in [1.15, 4.45, 6.55]:
			leaf.box("metal", Vector3(3.28, 0.11, 0.06), Vector3(x, y, 0.45))
		leaf.box("violet", Vector3(2.32, 0.065, 0.05), Vector3(x, 4.18, 0.46))
	leaf.commit(frame, "GatePanel")
	var at := frame.position + Vector3.UP * 3.85
	var size := Vector3(9.96, 7.7, 0.68)
	var collider := _body(at, size)
	return {"panel": frame, "collider": collider, "box": AABB(at - size * 0.5, size)}


func _pressure_hatch_detail() -> void:
	var rear_z := -44.83
	for side in [-1.0, 1.0]:
		var jamb_x: float = EXIT_X + side * 4.91
		_box("orion_frame", Vector3(jamb_x, 3.89, rear_z), Vector3(0.40, 7.78, 0.85), true)
		_kit.box_bevel("bare_steel", Vector3(0.13, 6.68, 0.18), Vector3(jamb_x - side * 0.12, 3.83, rear_z + 0.46), 0.032)
		_kit.box("cyan", Vector3(0.072, 3.32, 0.11), Vector3(jamb_x - side * 0.23, 4.02, rear_z + 0.25))
		for y in [1.39, 3.49, 5.59]:
			var socket := Vector3(jamb_x, y, rear_z + 0.36)
			_kit.box_bevel("metal_dark", Vector3(0.70, 0.47, 0.43), socket, 0.086)
			_kit.box_bevel("bare_steel", Vector3(0.38, 0.25, 0.24),
				socket + Vector3(-side * 0.14, 0, 0.27), 0.046)
			_kit.box("amber", Vector3(0.14, 0.054, 0.055), socket + Vector3(side * 0.18, 0, 0.25))
		var runner_x: float = EXIT_X + side * 3.95
		_kit.box("bare_steel", Vector3(0.16, 0.016, 11.0), Vector3(runner_x, 0.025, -38.63))
		_kit.box("metal_dark", Vector3(0.14, 0.019, 11.0), Vector3(runner_x + side * 0.17, 0.024, -38.63))
		for y in [2.18, 6.2]:
			_kit.tube("track", [Vector3(jamb_x, y, -44.35), Vector3(jamb_x, y, -41.35),
				Vector3(jamb_x + side * 0.27, y + 0.45, -40.92)], 0.087, 8)
	_box("orion_frame", Vector3(EXIT_X, 7.62, rear_z), Vector3(10.46, 0.54, 0.85), true, false)
	_kit.box("white", Vector3(6.12, 0.057, 0.25), Vector3(EXIT_X, 7.32, rear_z + 0.16))
	_kit.box("tread", Vector3(9.25, 0.042, 1.45), Vector3(EXIT_X, 0.036, -43.82))
	for z in [-43.15, -44.43]:
		_kit.box("bare_steel", Vector3(9.18, 0.025, 0.13), Vector3(EXIT_X, 0.06, z))
	_kit.box_bevel("orion_frame", Vector3(0.12, 5.92, 0.11), Vector3(EXIT_X, 3.36, -45.17), 0.026)


func _guide() -> Node3D:
	var route := Node3D.new()
	route.name = "EvacuationRoute"
	_root.add_child(route)
	var route_kit := Kit.new()
	route_kit.material("route", _glow(Color("62e1e9"), 1.8))
	var waypoints := [
		Vector3(5.7, 0.08, -12), Vector3(8.2, 0.08, -19),
		Vector3(27, 0.08, -23), Vector3(27, 0.08, -41)]
	for i in range(1, waypoints.size()):
		var start: Vector3 = waypoints[i - 1]
		var end: Vector3 = waypoints[i]
		var forward := (end - start).normalized()
		var side := forward.cross(Vector3.UP)
		var steps := ceili(start.distance_to(end) / 2.6)
		for j in steps:
			var point := start.lerp(end, (float(j) + 0.3) / steps)
			route_kit.tube("route", [point - side * 0.47 - forward * 0.35, point + forward * 0.34,
				point + side * 0.47 - forward * 0.35], 0.048, 6)
	route_kit.commit(route, "FloorArrows", false)
	route.hide()
	return route


func _terminal(at: Vector3) -> void:
	_box("metal_dark", at + Vector3(0, 0.9, 0), Vector3(2.9, 1.8, 1.38), true)
	_kit.box_bevel("orion_frame", Vector3(3.5, 0.26, 1.65), at + Vector3.UP * 1.92, 0.11)
	_kit.box_bevel("metal_dark", Vector3(2.1, 1.1, 0.28), at + Vector3(0, 2.49, -0.51), 0.11)
	for stripe in 4:
		_kit.box("cyan", Vector3(1.35 - stripe * 0.21, 0.064, 0.02),
			at + Vector3(-0.22 - stripe * 0.11, 2.18 + stripe * 0.17, -0.35))
	_kit.box("violet", Vector3(0.83, 0.08, 0.12), at + Vector3(0.77, 1.74, 0.9))
	for x in [-0.78, 0.78]:
		_kit.tube("metal", [at + Vector3(x, 1.15, 0.67), at + Vector3(x, 0.77, 0.75),
			at + Vector3(x, 0.43, 0.69)], 0.063, 8)


func _pallet(at: Vector3) -> void:
	_box("orion_frame", at + Vector3.UP * 0.4, Vector3(3.3, 0.8, 2.8), true)
	# The base stays a ground obstacle for Sentinel. The deck and crate provide actual upper contacts.
	for x in [-1.1, 0.0, 1.1]:
		var center := at + Vector3(x, 0.8, 0)
		var size := Vector3(0.49, 0.28, 2.84)
		_kit.box_bevel("metal_dark", size, center, 0.045)
		_obstacle(center, size, false)
	var cargo_at := at + Vector3(-0.45, 1.34, -0.25)
	var cargo_size := Vector3(1.82, 0.83, 1.68)
	_kit.box_bevel("container_2", cargo_size, cargo_at, 0.08)
	_obstacle(cargo_at, cargo_size, false)
	for x in [-1.04, 0.14]:
		_kit.box("metal", Vector3(0.115, 0.89, 1.72), at + Vector3(x, 1.34, -0.25))


func _plate(at: Vector3, width: float) -> void:
	_kit.box_bevel("metal_dark", Vector3(width, 0.09, 1.12), at, 0.05)
	for x in range(-4, 5):
		_kit.box("paint", Vector3(0.46, 0.03, 0.78), at + Vector3(x, 0.06, 0))


func _panel(content: String, at: Vector3, scale: float, facing := 0.0) -> void:
	var sign_label := Label3D.new()
	sign_label.text = content
	sign_label.font_size = 58
	sign_label.pixel_size = 0.01 * scale / 0.13
	sign_label.outline_size = 3
	sign_label.outline_modulate = Color("26292e")
	sign_label.modulate = Color("d3d5d9")
	sign_label.position = at
	sign_label.rotation.y = facing
	_root.add_child(sign_label)


func _lighting() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("171a1e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d5d8dd")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.13
	env.glow_enabled = true
	env.glow_intensity = 0.23
	env.ssao_enabled = true
	env.ssao_radius = 0.85
	env.ssao_intensity = 1.08
	env.ssr_enabled = true
	env.ssr_max_steps = 24
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.8
	env.ssr_depth_tolerance = 0.30
	env.fog_enabled = true
	env.fog_light_color = Color("282d34")
	env.fog_density = 0.0012
	world.environment = env
	_root.add_child(world)
	_light(Vector3(-18, 5.0, 32.0), Color("e1e5e9"), 1.87, 13.0)
	_light(Vector3(-20, 6.9, 20), Color("f4e8dc"), 3.1, 21.0)
	_light(Vector3(-5, 7.5, 9), Color("e0e6ee"), 3.0, 21.0)
	for z in [-23.0, -9.0, 5.0, 24.0, 37.0]:
		for x in [-27.0, 0.0, 23.0, 36.0]:
			var color := Color("e1e5ed") if x != -27.0 else Color("d8d7e4")
			_light(Vector3(x, 9.5 if x != 0.0 else 11.0, z), color, 3.8, 26.0)
	_light(Vector3(27, 6.6, -38), Color("d4e2e8"), 2.8, 16.0)
	_light(Vector3(-18, 4.85, 34.7), Color("faead6"), 1.48, 9.1)
	_work_light(Vector3(-16.8, 7.65, 25.3), TARGET, Color("fbefe4"), 3.45, 13.5)
	_work_light(Vector3(5.6, 11.8, -11.5), BASIC_SPAWN + Vector3.UP, Color("f1e7de"), 4.15, 21.0)
	for at in [Vector3(-9, 6.65, 11.9), Vector3(7.9, 7.0, -26.1), Vector3(26.8, 7.55, -31.2),
		Vector3(EXIT_X, 6.85, -43.8)]:
		var lamp := _light(at, Color("ff3159"), 0.0, 19.0)
		lamp.light_specular = 0.22
		_beacons.append(lamp)


func _work_light(at: Vector3, target: Vector3, tint: Color, power: float, reach: float) -> void:
	var lamp := SpotLight3D.new()
	lamp.transform = Transform3D(Basis.looking_at((target - at).normalized(), Vector3.UP), at)
	lamp.light_color = tint
	lamp.light_energy = power
	lamp.light_specular = 0.82
	lamp.spot_range = reach
	lamp.spot_angle = 43.0
	lamp.spot_attenuation = 0.9
	lamp.shadow_enabled = true
	_root.add_child(lamp)


func _build_alarm_fixtures() -> void:
	_beacon_material = _glow(Color("ff3458"), 0.16)
	_kit.material("alarm", _beacon_material)
	for origin in [Vector3(-9, 7.39, 11.89), Vector3(7.9, 7.95, -26.6), Vector3(26.8, 9.48, -31.1),
		Vector3(EXIT_X, 6.74, -45.07)]:
		_kit.box_bevel("metal_dark", Vector3(1.58, 0.41, 0.32), origin, 0.09)
		_kit.box_bevel("alarm", Vector3(1.29, 0.23, 0.15), origin + Vector3(0, 0, 0.17), 0.05)
		for x in [-0.77, 0.77]:
			_kit.box("metal", Vector3(0.085, 0.26, 0.08), origin + Vector3(x, 0, 0.18))


func _light(at: Vector3, tint: Color, power: float, reach: float) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = tint
	lamp.light_energy = power
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.2
	lamp.light_specular = 0.72
	_root.add_child(lamp)
	return lamp


func _box(key: String, at: Vector3, size: Vector3, physical: bool, ground_obstacle := true) -> void:
	_kit.box_bevel(key, size, at, 0.06)
	if physical:
		_obstacle(at, size, ground_obstacle)


func _obstacle(at: Vector3, size: Vector3, ground_obstacle: bool) -> void:
	_body(at, size)
	var bounds := AABB(at - size * 0.5, size)
	_camera_solids.append(bounds)
	if not ground_obstacle:
		_blade_boxes.append(bounds)
		return
	_solids.append(bounds)
	var low := Vector2(bounds.position.x, bounds.position.z)
	var high := Vector2(bounds.end.x, bounds.end.z)
	var corners := [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]
	for i in corners.size():
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		var edge := b - a
		_walls.append({"a": a, "b": b, "h": bounds.end.y, "n": Vector2(-edge.y, edge.x).normalized()})


func _body(at: Vector3, size: Vector3) -> StaticBody3D:
	var node := StaticBody3D.new()
	node.position = at
	var volume := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	volume.shape = shape
	node.add_child(volume)
	_root.add_child(node)
	return node

extends RefCounted
## Cargo bay dimensions and prop placement are shared with the chapter choreography.
const Kit = preload("res://src/cargo_hold2/mesh_kit.gd")
const CargoContainer = preload("res://src/cargo_hold2/container.gd")
const Inspection = preload("res://src/cargo_hold2/inspection_crate.gd")
const FabricatorFx = preload("res://src/cargo_hold2/fabricator_fx.gd")
const DisplayShader = preload("res://gfx/cargo_hold2/fabricator_display.gdshader")
const NormalMap = preload("res://src/cargo_hold2/container_normal.gd")
const ArcRig = preload("res://team/arc/scripts/ch/arc_rig.gd")
const ArcKin = preload("res://team/arc/scripts/ch/arc_kin.gd")
const ArcMaterials = preload("res://team/arc/scripts/ch/arc_materials.gd")
const ArcShapes = preload("res://team/arc/scripts/kit/shape_kit.gd")

const HALF_WIDTH := 42.0
const HALF_DEPTH := 46.0
const CEILING := 20.0
const PLAYER_SPAWN := Vector3(-18, 0, 39)
const PRINT_BED_HEIGHT := 0.14
const PRINT_BED_FRONT := 35.9
const SECURITY_X := -7.50
const SECURITY_DOOR_Z := -24.80
const BASIC_SPAWN := Vector3(SECURITY_X, 0, -30.8)
const EXIT_X := 27.0
const EXIT_DOOR_Z := -32.0
const EXIT_TRIGGER := Rect2(23.5, -43.0, 7.0, 4.5)
const EXIT_ROOF_Y := 8.475
const WORK_BULKHEAD_Z := 11.60
const WORK_PILLAR_FACE_Z := 11.98
const WORK_CEILING_Y := 8.20
const LIFT_CENTER := Vector3(-14.25, 0.0, -5.70)
const LIFT_FAR_Z := -18.25
const LIFT_PARK_Y := 7.80
const SERVICE_DECK_Y := 10.64
const SERVICE_LADDER := Vector3(-33.7, 0.0, -4.11)
const LADDER_HALF_WIDTH := 1.07
const LADDER_FIRST_RUNG := 0.44
const LADDER_RUNG_PITCH := 0.446
const LADDER_RUNG_COUNT := 23

var _root := Node3D.new()
var _kit := Kit.new()
# Ground obstacles feed navigation. The full set also includes boxes above the ground.
var _solids: Array[AABB] = []
var _camera_solids: Array[AABB] = []
var _blade_boxes: Array[AABB] = []
var _service_treads: Array[AABB] = []
var _inspection_crates: Array[Inspection] = []
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
	var printer := _birth_container()
	_work_bay()
	_threshold()
	var crane := _loading_deck()
	_service_wall()
	var security := _security_berth()
	var gate := _airlock()
	var approach_guide := _guide("LoadingDeckRoute", [
		Vector3(-18.0, 0.08, 28.40), Vector3(-18.0, 0.08, 17.2),
		Vector3(-4.3, 0.08, 17.2), Vector3(-2.6, 0.08, 15.7), Vector3(-2.6, 0.08, 8.8)])
	var guide := _guide("EvacuationRoute", [
		Vector3(5.7, 0.08, -12), Vector3(8.2, 0.08, -19),
		Vector3(27, 0.08, -23), Vector3(27, 0.08, -41)])
	_build_alarm_fixtures()
	_kit.commit(_root, "CargoStructure")
	_lighting()
	return {
		"node": _root, "kind": "cargo_hold2", "name_cn": "货舱 02",
		"hint": "适应义体，突破巡检哨兵，沿指引撤离。",
		"floor_y": 0.0, "bounds": AABB(Vector3(-HALF_WIDTH, 0, -HALF_DEPTH),
			Vector3(HALF_WIDTH * 2, CEILING, HALF_DEPTH * 2)),
		"walls": _walls, "cover": [], "solids": _solids, "camera_solids": _camera_solids,
		"blade_boxes": _blade_boxes, "service_treads": _service_treads,
		"inspection_crates": _inspection_crates, "interact_hint": _world_interact_hint(),
		"player_spawn": Transform3D(Basis.IDENTITY, PLAYER_SPAWN),
		"printer": printer, "security": security, "gate": gate, "crane": crane,
		"approach_guide": approach_guide, "guide": guide, "beacons": _beacons, "beacon_material": _beacon_material,
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
	kit.material("work_ceiling", _shader("metal", {"tint": Color("51565f"), "rough_base": 0.63,
		"metal_amount": 0.47, "rust_amount": 0.03, "oil_grime": 0.05}))
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
			_kit.box("violet", Vector3(0.09, 1.7, 0.14), Vector3(side * 40.99, 5.5, z))
	for z in range(-36, 43, 13):
		_kit.box_bevel("orion_frame", Vector3(82, 1.1, 0.65), Vector3(0, 18.9, z), 0.12)
		for x in [-26.0, -11.0, 11.0, 26.0]:
			for offset in [-1.82, 1.82]:
				_kit.box_bevel("orion_frame", Vector3(0.28, 0.42, 0.46), Vector3(x + offset, 18.18, z), 0.036)
			_kit.box_bevel("metal_dark", Vector3(5.3, 0.42, 1.2), Vector3(x, 17.80, z), 0.06)
			_kit.box("white", Vector3(4.65, 0.052, 0.4), Vector3(x, 17.57, z))


func _birth_container() -> Dictionary:
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
	_kit.box("white", Vector3(6.7, 0.05, 0.24), Vector3(x, 5.70, 29.1))
	for z in [30.5, 33.2]:
		_kit.box_bevel("tread", Vector3(7.4, 0.07, 2.58), Vector3(x, 0.025, z), 0.05)
		for lane in [-3.38, 3.38]:
			_kit.box("track", Vector3(0.24, 0.04, 2.35), Vector3(x + lane, 0.06, z))
	for z in [30.2, 36.0, 41.7]:
		_kit.box_bevel("orion_frame", Vector3(8.82, 0.27, 0.28), Vector3(x, 6.42, z), 0.05)
	_panel("C-02", Vector3(x, 6.04, 28.72), 0.14, PI)
	return _fabricator(x)


func _fabricator(x: float) -> Dictionary:
	var bed_back := 42.55
	var bed_z := (PRINT_BED_FRONT + bed_back) * 0.5
	var bed_size := Vector3(6.0, PRINT_BED_HEIGHT, bed_back - PRINT_BED_FRONT)
	_box("tread", Vector3(x, bed_size.y * 0.5, bed_z), bed_size, true, false)
	for z in [37.35, 40.34]:
		for side in [-1.0, 1.0]:
			var pad := Vector3(x + side * 1.62, PRINT_BED_HEIGHT + 0.012, z)
			_kit.box("bare_steel", Vector3(1.26, 0.022, 1.22), pad)
			for edge in [-1.0, 1.0]:
				_kit.box("metal_dark", Vector3(0.09, 0.024, 1.10), pad + Vector3(edge * 0.48, 0.003, 0))
	for side in [-1.0, 1.0]:
		var rail_x: float = x + side * 3.36
		_box("orion_frame", Vector3(rail_x, 0.23, bed_z), Vector3(0.48, 0.46, 7.02), true)
		_kit.box("amber", Vector3(0.09, 0.027, 6.32), Vector3(rail_x, 0.473, bed_z))
		for z in [35.0, 42.02]:
			_box("orion_frame", Vector3(rail_x, 2.52, z), Vector3(0.42, 5.04, 0.48), true)
			_kit.box("safety_yellow", Vector3(0.48, 0.18, 0.52), Vector3(rail_x, 0.65, z))
		_box("metal_dark", Vector3(rail_x, 5.22, 38.53), Vector3(0.47, 0.45, 7.53), true, false)
		_kit.box("bare_steel", Vector3(0.22, 0.075, 7.38), Vector3(rail_x, 4.99, 38.53))
		_kit.box("white", Vector3(0.08, 0.047, 6.40), Vector3(rail_x - side * 0.22, 5.462, 38.72))
		for i in 4:
			var bumper := Vector3(rail_x, 5.24, 35.58 + i * 1.53)
			_kit.box_bevel("bare_steel", Vector3(0.53, 0.26, 0.115), bumper, 0.032)
			_kit.box("track", Vector3(0.11, 0.08, 0.17), bumper + Vector3(-side * 0.25, 0.09, 0))
	# Material feed and power share the rear mast. Both end at the moving carriage.
	var feed := Vector3(x - 3.91, 1.48, 41.1)
	_box("metal_dark", feed, Vector3(0.82, 2.96, 2.11), true)
	for i in 3:
		var cartridge := feed + Vector3(0.43, 0.88 - i * 0.65, -0.06)
		_kit.box_bevel("bare_steel", Vector3(0.22, 0.50, 1.51), cartridge, 0.08)
		_kit.box("amber", Vector3(0.035, 0.065, 0.38), cartridge + Vector3(0.125, 0.093, 0.29))
	for i in 3:
		var off := Vector3(0.0, i * 0.11, 0.0)
		_kit.tube("track", [feed + Vector3(0.21, 1.41, 0.62) + off,
			Vector3(x - 3.95, 4.27, 41.97) + off, Vector3(x - 3.31, 5.09, 42.03) + off], 0.064, 8)

	var bridge := Node3D.new()
	bridge.name = "FabricatorGantry"
	bridge.position = Vector3(x, 4.96, 38.9)
	_root.add_child(bridge)
	var moving := Kit.new()
	for key in ["metal_dark", "orion_frame", "bare_steel", "metal", "safety_yellow", "cyan"]:
		moving.material(key, _kit.mats[key])
	moving.box_bevel("orion_frame", Vector3(6.82, 0.45, 0.49), Vector3.ZERO, 0.076)
	moving.box("bare_steel", Vector3(5.87, 0.10, 0.22), Vector3(0, -0.25, 0))
	for side in [-1.0, 1.0]:
		moving.box_bevel("metal_dark", Vector3(0.78, 0.59, 0.94), Vector3(side * 3.33, 0.09, 0), 0.09)
		moving.box("safety_yellow", Vector3(0.60, 0.10, 0.046), Vector3(side * 3.16, 0.11, -0.48))
		for i in 5:
			moving.box_bevel("metal", Vector3(0.10, 0.19, 0.44),
				Vector3(side * (0.96 + 0.33 * i), -0.03, -0.20), 0.022)
		moving.box("cyan", Vector3(1.40, 0.045, 0.052), Vector3(side * 1.76, 0.15, -0.254))
	moving.commit(bridge, "Crossfeed")

	var head := Node3D.new()
	head.name = "FabricatorNozzle"
	bridge.add_child(head)
	var tool := Kit.new()
	for key in ["metal_dark", "orion_frame", "bare_steel", "cyan"]:
		tool.material(key, _kit.mats[key])
	tool.box_bevel("metal_dark", Vector3(1.52, 0.47, 1.08), Vector3(0, -0.30, 0), 0.16)
	tool.box_bevel("bare_steel", Vector3(1.34, 0.13, 0.98), Vector3(0, -0.46, 0), 0.04)
	for side in [-1.0, 1.0]:
		var guide := Vector3(side * 0.42, -0.52, 0)
		tool.lathe("orion_frame", [Vector2(0.13, -0.34), Vector2(0.13, 0.18)], 16, guide)
		tool.lathe("bare_steel", [Vector2(0.15, -0.34), Vector2(0.15, -0.27)], 16, guide)
	tool.commit(head, "DepositionHousing")

	var spindle := Node3D.new()
	spindle.name = "DepositionRam"
	head.add_child(spindle)
	var shafts := Kit.new()
	shafts.material("bare_steel", _kit.mats["bare_steel"])
	for side in [-1.0, 1.0]:
		shafts.lathe("bare_steel", [Vector2(0.075, -1.0), Vector2(0.075, 0.0)], 16, Vector3(side * 0.42, 0, 0))
	shafts.commit(spindle, "RamShafts")

	var optic := Node3D.new()
	optic.name = "RotatingDepositionOptic"
	head.add_child(optic)
	var iris := Kit.new()
	for key in ["metal_dark", "orion_frame", "bare_steel", "amber"]:
		iris.material(key, _kit.mats[key])
	iris.lathe("orion_frame", [Vector2(0.24, -0.24), Vector2(0.36, -0.09),
		Vector2(0.43, 0.10), Vector2(0.43, 0.17)], 28)
	iris.lathe("bare_steel", [Vector2(0.15, -0.43), Vector2(0.24, -0.33),
		Vector2(0.25, -0.27), Vector2(0.23, -0.23)], 28)
	iris.lathe("metal_dark", [Vector2(0.09, -0.47), Vector2(0.16, -0.42)], 28)
	for i in 6:
		var angle := TAU * i / 6.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		iris.tube("bare_steel", [radial * 0.36 + Vector3.UP * 0.125,
			radial * 0.43 + Vector3.UP * 0.055, radial * 0.42 + Vector3.DOWN * 0.085], 0.029, 6)
		iris.sphere("amber", 0.026, 8, radial * 0.36 - Vector3.UP * 0.077)
	iris.commit(optic, "DepositionCartridge")
	var scan_lamp := OmniLight3D.new()
	scan_lamp.position.y = -0.45
	scan_lamp.omni_range = 3.45
	scan_lamp.light_color = Color("ffd6b0")
	scan_lamp.light_energy = 1.05
	optic.add_child(scan_lamp)
	_work_light(Vector3(x + 0.55, 6.04, 39.6), Vector3(x - 0.7, 2.0, 39.1), Color("e8f0ed"), 1.37, 8.6)

	# The carriage only moves during the cutscene. Its parked geometry is solid during play.
	_obstacle(Vector3(x, 4.96, 41.64), Vector3(6.82, 0.50, 0.49), false)
	_obstacle(Vector3(x + 2.30, 3.79, 41.64), Vector3(1.02, 1.36, 0.93), false)
	var screen := Vector3(x + 4.01, 3.37, 38.42)
	_box("metal_dark", screen, Vector3(0.40, 1.92, 3.32), true, false)
	# A recessed glass cartridge sits in a machined, chamfered frame.
	_kit.box_bevel("orion_frame", Vector3(0.24, 1.86, 3.26), screen - Vector3.RIGHT * 0.10, 0.11)
	_kit.box_bevel("bare_steel", Vector3(0.116, 1.70, 3.10), screen - Vector3.RIGHT * 0.210, 0.054)
	_kit.box_bevel("metal_dark", Vector3(0.058, 1.56, 2.95), screen - Vector3.RIGHT * 0.248, 0.027)
	for edge in [-1.0, 1.0]:
		var cover := screen + Vector3(-0.246, 0.0, edge * 1.558)
		_kit.box_bevel("metal_dark", Vector3(0.086, 1.42, 0.13), cover, 0.026)
		_kit.box_bevel("violet", Vector3(0.018, 0.49, 0.038),
			cover + Vector3(-0.042, 0.22, 0.0), 0.006)
		for y in [-0.763, 0.763]:
			var screw := screen + Vector3(-0.27, y, edge * 1.462)
			_kit.tube("track", [screw, screw - Vector3.RIGHT * 0.022], 0.028, 6)
			_kit.box("metal_dark", Vector3(0.008, 0.027, 0.009), screw - Vector3.RIGHT * 0.025)
	for y in [-0.5, 0.5]:
		_kit.box_bevel("orion_frame", Vector3(0.24, 0.29, 0.19), screen + Vector3(-0.14, y, 1.63), 0.04)
	var display := MeshInstance3D.new()
	var glass := QuadMesh.new()
	glass.size = Vector2(2.80, 1.38)
	display.mesh = glass
	var display_mat := ShaderMaterial.new()
	display_mat.shader = DisplayShader
	display.material_override = display_mat
	display.position = screen - Vector3.RIGHT * 0.284
	display.rotation.y = -PI * 0.5
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(display)
	var feed_at := screen + Vector3(-0.43, -0.23, 1.70)
	_kit.box_bevel("orion_frame", Vector3(0.43, 0.32, 0.39), feed_at + Vector3.RIGHT * 0.06, 0.069)
	_kit.box("track", Vector3(0.06, 0.098, 0.14), feed_at - Vector3.RIGHT * 0.17)
	_readout_label(screen, Vector2(0.141, 0.881), "C-02", 0.038, HORIZONTAL_ALIGNMENT_CENTER, Color("faf0ff"))
	_readout_label(screen, Vector2(0.277, 0.881), "/   FABRICATION", 0.032, HORIZONTAL_ALIGNMENT_LEFT, Color("ebdef9"))
	_readout_label(screen, Vector2(0.105, 0.685), "义体成形", 0.033, HORIZONTAL_ALIGNMENT_LEFT, Color("e1f8fa"))
	_readout_label(screen, Vector2(0.105, 0.344), "意识传输", 0.033, HORIZONTAL_ALIGNMENT_LEFT, Color("f2e9ff"))
	var fabrication := _readout_label(screen, Vector2(0.797, 0.685), "处理中", 0.027,
		HORIZONTAL_ALIGNMENT_CENTER, Color("acf0f0"))
	var transfer := _readout_label(screen, Vector2(0.797, 0.344), "接收中", 0.027,
		HORIZONTAL_ALIGNMENT_CENTER, Color("e7d7ff"))

	_kit.tube("track", [screen + Vector3(0, -0.97, 0.92), screen + Vector3(0, -1.37, 0.87),
		Vector3(x + 4.05, 0.73, 41.06)], 0.079, 8)
	var fx := FabricatorFx.new()
	fx.name = "FabricationEffects"
	_root.add_child(fx)
	return {"bridge": bridge, "head": head, "lamp": scan_lamp, "screen": screen,
		"optic": optic, "spindle": spindle, "effects": fx, "feed_at": feed_at - Vector3.RIGHT * 0.20,
		"fabrication": fabrication, "transfer": transfer, "display": display_mat}


func _readout_label(screen: Vector3, uv: Vector2, content: String, scale: float,
		alignment: HorizontalAlignment, tint: Color) -> Label3D:
	var offset := Vector3(-0.299, (uv.y - 0.5) * 1.38, (uv.x - 0.5) * 2.80)
	var label := _panel(content, screen + offset, scale, -PI * 0.5)
	label.horizontal_alignment = alignment
	label.outline_size = 0
	label.modulate = tint
	return label


func _work_bay() -> void:
	_work_bay_structure()
	_work_bay_ventilation()
	_power_isolator(Vector3(-8.03, 3.04, WORK_BULKHEAD_Z + 0.33))
	_receiving_station()
	_sorting_bench()
	for x in [-8.4, -7.77, -7.14, -6.51, -5.88, -5.25]:
		_kit.box("paint", Vector3(0.23, 0.018, 1.15), Vector3(x, 0.038, 17.88))


func _work_bay_structure() -> void:
	var wall_z := WORK_BULKHEAD_Z
	var ceiling := WORK_CEILING_Y
	# The split bulkhead panels sit on the structural wall. Pillars meet the deck plate and header.
	_box("metal_dark", Vector3(-24.0, 4.2, wall_z - 0.60), Vector3(34.5, 8.4, 1.2), true)
	for x in [-37.62, -30.80, -23.98, -17.16, -10.34]:
		_kit.box_bevel("orion_frame", Vector3(6.77, 3.95, 0.15),
			Vector3(x, 4.99, wall_z), 0.056)
		_kit.box_bevel("wall", Vector3(6.77, 2.60, 0.15), Vector3(x, 1.59, wall_z), 0.049)
	_kit.box_bevel("track", Vector3(34.38, 0.24, 0.19), Vector3(-24.0, 2.93, wall_z + 0.04), 0.036)
	_kit.box_bevel("metal_dark", Vector3(34.44, 0.34, 0.22), Vector3(-24.0, 0.18, wall_z + 0.03), 0.046)
	for x in [-37.0, -29.0, -18.0, -9.0]:
		_box("orion_frame", Vector3(x, 4.1, WORK_PILLAR_FACE_Z - 0.33),
			Vector3(0.62, 8.2, 0.66), true)
		for y in [0.28, 7.87]:
			var bracket := Vector3(x, y, WORK_PILLAR_FACE_Z - 0.12)
			_kit.box_bevel("metal_dark", Vector3(0.88, 0.45, 0.56), bracket, 0.064)
			for side in [-1.0, 1.0]:
				var bolt := bracket + Vector3(side * 0.30, 0.0, 0.27)
				_kit.tube("bare_steel", [bolt, bolt + Vector3.BACK * 0.035], 0.043, 6)
	_box("orion_frame", Vector3(-24.0, 7.93, wall_z + 0.02),
		Vector3(34.48, 0.59, 1.12), true, false)

	# The inner ceiling is flanged to the bulkhead and the longitudinal edge frame.
	_box("work_ceiling", Vector3(-23.05, ceiling + 0.23, 19.0), Vector3(38.70, 0.46, 17.0), true, false)
	_box("orion_frame", Vector3(-3.98, 8.02, 19.0), Vector3(0.52, 0.62, 17.0), true, false)
	for z in [16.25, 22.05, 27.08]:
		_box("orion_frame", Vector3(-23.18, 8.00, z), Vector3(38.76, 0.59, 0.61), true, false)
		_kit.box_bevel("track", Vector3(38.55, 0.11, 0.38), Vector3(-23.18, 7.68, z), 0.039)
		for x in [-37.0, -18.0, -9.0]:
			_kit.box_bevel("metal_dark", Vector3(0.55, 0.33, 0.69), Vector3(x, 7.87, z), 0.049)
	for x in [-36.0, -23.0, -10.0]:
		for z in [13.78, 19.14, 24.60]:
			_kit.box_bevel("work_ceiling", Vector3(10.6, 0.12, 2.75),
				Vector3(x, ceiling + 0.02, z), 0.050)
	for x in [-35.35, -13.25]:
		var fixture := Vector3(x, 7.54, 22.05)
		_kit.box_bevel("metal_dark", Vector3(6.65, 0.27, 0.50), fixture, 0.057)
		_kit.box_bevel("bare_steel", Vector3(6.36, 0.093, 0.33), fixture - Vector3.UP * 0.13, 0.031)
		_kit.box("white", Vector3(6.10, 0.041, 0.25), fixture - Vector3.UP * 0.179)

	# The wayfinding panel is carried by the bulkhead. Its face clears the centre pillar.
	for x in [-22.75, -13.25]:
		_kit.box_bevel("orion_frame", Vector3(0.56, 0.62, 0.50), Vector3(x, 5.56, wall_z + 0.19), 0.050)
	var sign_at := Vector3(-18.0, 5.56, wall_z + 0.49)
	_kit.box_bevel("metal_dark", Vector3(12.50, 0.89, 0.25), sign_at, 0.097)
	_kit.box("white", Vector3(11.25, 0.048, 0.048), sign_at + Vector3(0, 0.30, 0.13))
	_panel("CARGO 02   /   LOADING DECK  >", sign_at + Vector3(0, -0.045, 0.156), 0.118)


func _work_bay_ventilation() -> void:
	var wall_z := WORK_BULKHEAD_Z
	var header_y := 7.30
	var header_z := wall_z + 0.54
	# Both grilles feed a duct under the deckhead. The duct rises into the ceiling return.
	var vents := [Vector3(-34.30, 5.44, 4.46), Vector3(-27.15, 5.92, 3.39)]
	for i in vents.size():
		var vent: Vector3 = vents[i]
		var face := Vector3(vent.x, vent.y, wall_z)
		_box("orion_frame", face + Vector3.BACK * 0.08,
			Vector3(vent.z + 0.25, 1.22, 0.32), true, false)
		_kit.box_bevel("bare_steel", Vector3(vent.z, 1.03, 0.37), face + Vector3.BACK * 0.21, 0.065)
		_kit.box_bevel("metal_dark", Vector3(vent.z - 0.25, 0.80, 0.12),
			face + Vector3.BACK * 0.396, 0.036)
		for slat in 6:
			var fin := face + Vector3(0, -0.289 + slat * 0.116, 0.49)
			_kit.box_bevel("track", Vector3(vent.z - 0.44, 0.072, 0.146), fin, 0.020)
			_kit.box("bare_steel", Vector3(vent.z - 0.52, 0.017, 0.029), fin + Vector3(0, 0.038, 0.066))
		for x in [-0.31, 0.31]:
			_kit.box("orion_frame", Vector3(0.046, 0.72, 0.025), face + Vector3(x * vent.z, 0.0, 0.532))
		var tag := face + Vector3(0, -0.58, 0.430)
		_kit.box_bevel("orion_frame", Vector3(1.31, 0.24, 0.078), tag, 0.029)
		_panel("RETURN / R-%02d" % (i + 1), tag + Vector3.BACK * 0.043, 0.020)
		for side in [-1.0, 1.0]:
			for y in [-0.42, 0.42]:
				var bolt := face + Vector3(side * (vent.z * 0.5 - 0.085), y, 0.36)
				_kit.tube("metal_dark", [bolt, bolt + Vector3.BACK * 0.050], 0.044, 6)
		var branch_bottom: float = vent.y + 0.43
		var branch_height: float = header_y - branch_bottom
		_kit.box_bevel("metal_dark", Vector3(1.02, branch_height, 0.54),
			Vector3(vent.x, branch_bottom + branch_height * 0.5, header_z - 0.08), 0.054)
		_kit.box_bevel("track", Vector3(1.19, 0.15, 0.65),
			Vector3(vent.x, branch_bottom + 0.13, header_z - 0.08), 0.031)
	_box("metal_dark", Vector3(-30.72, header_y, header_z), Vector3(9.2, 0.66, 0.86), true, false)
	for x in [-35.20, -26.23]:
		_kit.box_bevel("orion_frame", Vector3(0.15, 0.79, 0.99), Vector3(x, header_y, header_z), 0.053)

	var trunk_x := -31.14
	_box("metal_dark", Vector3(trunk_x, header_y, 18.70), Vector3(1.23, 0.66, 13.12), true, false)
	for z in [12.63, 16.25, 22.05, 24.54]:
		_kit.box_bevel("track", Vector3(1.39, 0.78, 0.17), Vector3(trunk_x, header_y, z), 0.045)
	for z in [16.25, 22.05]:
		for side in [-1.0, 1.0]:
			_kit.box_bevel("orion_frame", Vector3(0.145, 0.40, 0.27),
				Vector3(trunk_x + side * 0.63, 7.62, z), 0.032)
	_box("orion_frame", Vector3(trunk_x, 7.68, 25.24), Vector3(1.56, 1.13, 1.57), true, false)
	_kit.box_bevel("track", Vector3(1.87, 0.16, 1.84),
		Vector3(trunk_x, WORK_CEILING_Y - 0.04, 25.24), 0.045)


func _power_isolator(at: Vector3) -> void:
	var wall_z := WORK_BULKHEAD_Z
	_box("orion_frame", Vector3(at.x, at.y, wall_z + 0.055), Vector3(1.58, 2.44, 0.34), true, false)
	_box("orion_frame", at, Vector3(1.44, 2.22, 0.45), true, false)
	_kit.box_bevel("metal_dark", Vector3(1.19, 1.93, 0.15), at + Vector3.BACK * 0.265, 0.05)
	for x in [-0.34, 0.34]:
		_kit.box_bevel("track", Vector3(0.22, 0.84, 0.16), at + Vector3(x, -0.18, 0.37), 0.03)
		_kit.box("amber", Vector3(0.16, 0.057, 0.025), at + Vector3(x, 0.46, 0.363))
		for y in [-0.83, 0.82]:
			_kit.tube("bare_steel", [at + Vector3(x, y, 0.37), at + Vector3(x, y, 0.408)], 0.038, 6)
	_panel("CARGO POWER", at + Vector3(0, 0.71, 0.377), 0.025)
	_panel("PWR-02", at + Vector3(0, -0.76, 0.357), 0.023)
	for i in 2:
		var lever := at + Vector3(-0.34 + i * 0.68, -0.21, 0.503)
		_kit.box_bevel("bare_steel", Vector3(0.25, 0.125, 0.108), lever, 0.030)
		_kit.box("safety_yellow", Vector3(0.15, 0.028, 0.022), lever + Vector3(0, 0.021, 0.06))
		_panel(["A", "B"][i], lever + Vector3(0, 0.45, -0.146), 0.018)
	var badge := at + Vector3(0.0, 0.23, 0.362)
	_kit.quad("safety_yellow", [badge + Vector3(-0.12, -0.09, 0), badge + Vector3(0.12, -0.09, 0),
		badge + Vector3(0.006, 0.112, 0), badge + Vector3(-0.006, 0.112, 0)], Vector3.BACK)
	_kit.box("metal_dark", Vector3(0.024, 0.11, 0.014), badge + Vector3(0, -0.014, 0.010))

	var junction := Vector3(at.x, 6.79, wall_z + 0.24)
	_kit.box_bevel("orion_frame", Vector3(1.18, 0.72, 0.57), junction, 0.083)
	_kit.box_bevel("track", Vector3(0.94, 0.52, 0.075), junction + Vector3.BACK * 0.30, 0.042)
	var feed := Vector3(at.x, 7.72, 22.05)
	_kit.box_bevel("metal_dark", Vector3(1.26, 0.44, 1.10), feed, 0.058)
	_kit.box_bevel("track", Vector3(1.46, 0.13, 1.24), feed + Vector3.UP * 0.21, 0.039)
	for dx in [-0.22, 0.22]:
		var rise := Vector3(at.x + dx, at.y + 1.10, wall_z + 0.36)
		_kit.tube("track", [rise, Vector3(rise.x, junction.y - 0.20, rise.z)], 0.085, 12)
		_kit.tube("bare_steel", [rise, rise + Vector3.UP * 0.14], 0.145, 12)
		for y in [4.83, 5.82]:
			_kit.box_bevel("orion_frame", Vector3(0.31, 0.135, 0.50),
				Vector3(rise.x, y, wall_z + 0.18), 0.031)
		var outlet := Vector3(rise.x, junction.y + 0.33, junction.z + 0.14)
		_kit.tube("track", [outlet, Vector3(rise.x, 7.41, outlet.z),
			Vector3(rise.x, 7.62, 12.35), Vector3(rise.x, 7.62, 21.67)], 0.085, 12)
		_kit.tube("bare_steel", [outlet, outlet + Vector3.UP * 0.13], 0.141, 12)
		_kit.tube("bare_steel", [Vector3(rise.x, 7.62, 21.42),
			Vector3(rise.x, 7.62, 21.54)], 0.141, 12)
		for z in [13.92, 16.25, 19.02]:
			_kit.box_bevel("orion_frame", Vector3(0.255, 0.68, 0.15),
				Vector3(rise.x, 7.87, z), 0.033)


func _sorting_bench() -> void:
	var at := Vector3(-27.8, 0.0, 15.9)
	# The braced table is for separating removed plate, fittings and tools.
	for x in [-2.27, 2.27]:
		for z in [-0.69, 0.69]:
			_box("orion_frame", at + Vector3(x, 0.94, z), Vector3(0.28, 1.88, 0.29), true)
	_box("metal_dark", at + Vector3(0, 1.94, 0), Vector3(5.12, 0.28, 1.93), true, false)
	_box("orion_frame", at + Vector3(0, 0.42, 0), Vector3(4.8, 0.16, 1.53), true)
	_sorting_parts(at)
	_sorting_light(at)
	_panel("SALVAGE  /  SORTING", at + Vector3(0, 2.04, 1.03), 0.034)


func _sorting_parts(at: Vector3) -> void:
	var dimensions := ArcKin.new({})
	var display_scale := Vector3.ONE * 1.83
	var copper := ArcMaterials.orange_panel()

	# The triangular drive module is parked in two rubber chocks for disassembly.
	var bed := at + Vector3(-0.70, 2.13, -0.04)
	_kit.box_bevel("orion_frame", Vector3(2.77, 0.11, 1.51), bed, 0.052)
	for x in [-0.90, 0.85]:
		_kit.box_bevel("tread", Vector3(0.43, 0.11, 0.67), bed + Vector3(x, 0.099, 0.04), 0.035)
	var track := ArcRig.service_track()
	track.name = "SentinelRecoveredTrack"
	track.transform = Transform3D(Basis(Vector3.UP, -1.26).scaled(display_scale),
		at + Vector3(-0.70, 2.275, -0.02))
	_root.add_child(track)
	_finish_salvage(track)

	# The spare idler and the removed emitter sit in the parts tray alongside the drive.
	var tray := at + Vector3(1.46, 2.135, -0.04)
	_kit.box_bevel("track", Vector3(1.66, 0.12, 1.42), tray, 0.035)
	for z in [-0.65, 0.65]:
		_kit.box_bevel("metal_dark", Vector3(1.62, 0.12, 0.09),
			tray + Vector3(0, 0.078, z), 0.023)
	_kit.box_bevel("tread", Vector3(0.58, 0.075, 0.57), tray + Vector3(-0.37, 0.076, -0.23), 0.027)
	var wheel_pose := Transform3D(Basis(Vector3.BACK, PI * 0.5).scaled(display_scale),
		tray + Vector3(-0.37, 0.29, -0.23))
	_bench_parts("SentinelSpareIdler", wheel_pose, ArcRig.track_wheel_parts(dimensions.wheel_r, copper, copper))

	for x in [0.10, 0.43]:
		_kit.box_bevel("tread", Vector3(0.14, 0.10, 0.39), tray + Vector3(x, 0.102, 0.27), 0.027)
	var tool_basis := Basis(Vector3.UP, -0.28) * Basis(Vector3.BACK, PI * 0.5)
	var tool_pose := Transform3D(tool_basis.scaled(display_scale), tray + Vector3(0.03, 0.24, 0.23))
	_bench_parts("SentinelBladeEmitter", tool_pose, ArcRig.emitter_parts(dimensions.L3))


func _sorting_light(at: Vector3) -> void:
	var base := at + Vector3(2.10, 2.12, -0.66)
	_kit.box_bevel("orion_frame", Vector3(0.43, 0.15, 0.42), base, 0.041)
	_kit.tube("track", [base, at + Vector3(2.10, 3.51, -0.66),
		at + Vector3(1.86, 3.98, 0.22), at + Vector3(0.60, 3.98, 0.22)], 0.067, 10)
	for y in [2.22, 3.51]:
		_kit.box_bevel("metal_dark", Vector3(0.19, 0.19, 0.19),
			at + Vector3(2.10, y, -0.66), 0.034)
	var lamp := at + Vector3(0.38, 3.95, 0.22)
	_kit.box_bevel("metal_dark", Vector3(0.97, 0.22, 0.54), lamp, 0.048)
	_kit.box_bevel("white", Vector3(0.77, 0.045, 0.32), lamp - Vector3.UP * 0.113, 0.014)
	_work_light(lamp - Vector3.UP * 0.16, at + Vector3(-0.55, 2.52, 0.12), Color("f3e8db"), 2.8, 3.7)


func _bench_parts(part_name: String, pose: Transform3D, parts: Array) -> void:
	var part := Node3D.new()
	part.name = part_name
	part.transform = pose
	_root.add_child(part)
	for baked in ArcShapes.bake(parts):
		var mesh := MeshInstance3D.new()
		mesh.mesh = baked["mesh"]
		mesh.material_override = baked["mat"]
		part.add_child(mesh)
	_finish_salvage(part)


func _finish_salvage(part: Node3D) -> void:
	var finishes: Dictionary[Material, Material] = {}
	for geometry in part.find_children("*", "GeometryInstance3D", true, false):
		var original: Material = geometry.material_override
		if not (original is ShaderMaterial):
			continue
		if not finishes.has(original):
			var worn := original.duplicate() as ShaderMaterial
			var coat: Color = worn.get_shader_parameter("albedo_color")
			var roughness: float = worn.get_shader_parameter("roughness_base")
			worn.set_shader_parameter("albedo_color", coat.lightened(0.125))
			worn.set_shader_parameter("roughness_base", minf(roughness + 0.16, 0.80))
			worn.set_shader_parameter("metallic", 0.58)
			finishes[original] = worn
		geometry.material_override = finishes[original]


func _receiving_station() -> void:
	var island := Vector3(-12.05, 0, 22.25)
	_kit.box("safety_yellow", Vector3(5.0, 0.025, 0.095), island + Vector3(0, 0.016, 2.45))
	for side in [-1.0, 1.0]:
		var x: float = side * 2.44
		_kit.box("safety_yellow", Vector3(0.095, 0.025, 4.8), island + Vector3(x, 0.017, 0))
	_box("orion_frame", island + Vector3(0, 0.31, 0.15), Vector3(4.1, 0.62, 2.95), true)
	for i in 9:
		var z: float = -1.20 + i * 0.32
		_kit.tube("bare_steel", [island + Vector3(-1.91, 0.64, z), island + Vector3(1.91, 0.64, z)], 0.10, 10)
	for side in [-1.0, 1.0]:
		var x: float = side * 2.04
		_box("orion_frame", island + Vector3(x, 1.82, -0.62), Vector3(0.34, 2.37, 0.45), true)
		_kit.box("safety_yellow", Vector3(0.36, 0.22, 0.48), island + Vector3(x, 0.81, -0.62))
	_box("orion_frame", island + Vector3(0, 3.07, -0.62), Vector3(4.42, 0.46, 0.55), true, false)
	var lot := "017"
	var case_size := Vector3(2.55, 0.85, 1.30)
	var case_base := island + Vector3(-0.52, 0.76, 0.08)
	_supply_case(case_base, case_size, "")
	_receiving_readout(island + Vector3(-0.52, 3.24, -0.275), lot)
	_receiving_tags(case_base + Vector3.UP * case_size.y * 0.5, case_size, lot)

	for x in [-1.61, -0.52, 1.09]:
		var head := island + Vector3(x, 2.77, -0.44)
		_kit.box_bevel("metal_dark", Vector3(0.65, 0.17, 0.47), head, 0.057)
		var lamp := "cyan" if is_equal_approx(x, -0.52) else "amber"
		_kit.box(lamp, Vector3(0.41, 0.030, 0.28), head - Vector3.UP * 0.089)
	var active_head := island + Vector3(-0.52, 2.664, -0.44)
	_work_light(active_head, case_base + Vector3(0, case_size.y, 0.28), Color("8ae3df"), 1.72, 2.28)
	_kit.box_bevel("bare_steel", Vector3(0.53, 0.075, 0.19), island + Vector3(1.33, 0.736, 0.15), 0.025)
	_kit.box("cyan", Vector3(0.37, 0.02, 0.06), island + Vector3(1.33, 0.78, 0.15))

	var rack := Vector3(-28.2, 0, 24.8)
	for x in [-2.65, 2.65]:
		for z in [-0.95, 0.95]:
			_box("orion_frame", rack + Vector3(x, 1.67, z), Vector3(0.20, 3.34, 0.24), true)
	for y in [0.37, 1.72, 3.24]:
		_box("metal_dark", rack + Vector3(0, y, 0), Vector3(5.5, 0.18, 2.05), true, y < 0.5)
		_kit.box("bare_steel", Vector3(5.24, 0.065, 0.09), rack + Vector3(0, y + 0.02, 1.04))
	for shelf in [Vector2(-1.35, 0.46), Vector2(1.42, 1.81)]:
		var height: float = shelf.y
		_box("track", rack + Vector3(0, height + 0.066, -0.91), Vector3(5.27, 0.16, 0.18), true, false)
		for x in [-2.49, 2.49]:
			_box("track", rack + Vector3(x, height + 0.083, -0.04),
				Vector3(0.20, 0.18, 1.68), true, false)
		for side in [-1.0, 1.0]:
			var stop := rack + Vector3(shelf.x + side * 0.78, height + 0.065, 0.877)
			_box("orion_frame", stop, Vector3(0.34, 0.15, 0.19), true, false)
			_kit.box_bevel("safety_yellow", Vector3(0.23, 0.044, 0.10), stop + Vector3.UP * 0.071, 0.016)
	_supply_case(rack + Vector3(-1.35, 0.46, 0), Vector3(2.08, 1.02, 1.62), "H02  /  018")
	_supply_case(rack + Vector3(1.42, 1.81, 0), Vector3(1.83, 0.96, 1.58), "H02  /  019")
	# The intake-facing end of the top shelf carries the staging sign.
	var sign_at := rack + Vector3(2.75, 3.235, 0)
	_kit.box_bevel("metal_dark", Vector3(0.18, 0.46, 2.08), sign_at, 0.05)
	_kit.box("paint", Vector3(0.044, 0.040, 1.86), sign_at + Vector3(0.081, -0.147, 0))
	_panel("H02   /   STAGING", sign_at + Vector3(0.105, 0.029, 0), 0.044, PI * 0.5)
	var pallet := Vector3(-24.23, 0, 20.35)
	_staging_pallet(pallet)
	_cargo_pad(pallet + Vector3.UP * 0.025, Vector2(3.99, 3.48))


func _receiving_readout(at: Vector3, lot: String) -> void:
	# The display shares the scanner crossbeam and sits over the center of the active load.
	_box("orion_frame", at, Vector3(2.38, 0.77, 0.29), true, false)
	_kit.box_bevel("bare_steel", Vector3(2.24, 0.66, 0.089), at + Vector3.BACK * 0.140, 0.038)
	_kit.box_bevel("metal_dark", Vector3(2.12, 0.56, 0.058), at + Vector3.BACK * 0.186, 0.023)
	_kit.box("cyan", Vector3(0.021, 0.28, 0.023), at + Vector3(-0.985, -0.045, 0.219))
	_kit.box("cyan", Vector3(0.021, 0.28, 0.023), at + Vector3(0.985, -0.045, 0.219))
	_panel("SURFACE SUPPLY / RECEIVING", at + Vector3(0, 0.174, 0.221), 0.021)
	_panel(lot, at + Vector3(-0.565, -0.068, 0.222), 0.063).modulate = Color("a9f4ed")
	var status := _panel("验收中", at + Vector3(0.37, -0.070, 0.222), 0.047)
	status.outline_size = 0
	status.modulate = Color("e1f2ee")


func _receiving_tags(at: Vector3, size: Vector3, lot: String) -> void:
	var front := at + Vector3(0.0, -0.04, size.z * 0.5)
	var approach_side := at + Vector3(-size.x * 0.5, -0.04, 0.06)
	_kit.box_bevel("metal_dark", Vector3(1.02, 0.35, 0.060), front + Vector3.BACK * 0.017, 0.028)
	_kit.box_bevel("metal_dark", Vector3(0.060, 0.35, 1.02), approach_side + Vector3.LEFT * 0.017, 0.028)
	_panel(lot, front + Vector3.BACK * 0.052, 0.055).modulate = Color("a9f4ed")
	_panel(lot, approach_side + Vector3.LEFT * 0.052, 0.055, -PI * 0.5).modulate = Color("a9f4ed")


func _supply_case(base: Vector3, size: Vector3, marking: String) -> void:
	var at := base + Vector3.UP * size.y * 0.5
	_box("container_0", at, size, true, false)
	var front := at + Vector3.BACK * (size.z * 0.5 + 0.025)
	for x in [-0.83, 0.83]:
		_kit.box_bevel("metal_dark", Vector3(0.21, 0.34, 0.09), front + Vector3(x, 0.18, 0), 0.028)
	_kit.box("paint", Vector3(0.13, 0.22, 0.03), front + Vector3(0.60, 0.19, 0.06))
	if not marking.is_empty():
		_panel(marking, front + Vector3(-0.16, 0.02, 0.06), 0.026)


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
	_panel("CARGO HOLD  /  02", Vector3(0, 9.12, z + 0.88), 0.095)


func _loading_deck() -> Dictionary:
	var crates := CargoContainer.new(_kit)
	var groups := [
		[Vector3(-25, 0, 0), 0, Vector3(10, 5.5, 6), true],
		[Vector3(-28, 0, -14), 1, Vector3(11, 5.6, 6.5), false],
		[Vector3(-16, 0, -25), 2, Vector3(6.3, 5.0, 6.2), false],
		[Vector3(20, 0, 5), 1, Vector3(10, 5.6, 6.3), true],
		[Vector3(12.5, 0, -5), 0, Vector3(6.5, 4.5, 5.2), false],
		[Vector3(23, 0, -14), 2, Vector3(10.5, 5.6, 6.2), false],
		[Vector3(31, 0, 26), 0, Vector3(11, 5.0, 6.5), true],
		[Vector3(13, 0, 28), 1, Vector3(9, 4.8, 6.2), false],
	]
	for index in groups.size():
		var entry: Array = groups[index]
		var at: Vector3 = entry[0]
		var size: Vector3 = entry[2]
		_cargo_pad(at + Vector3.UP * 0.025, Vector2(size.x + 1.25, size.z + 1.15))
		var key := "container_%d" % entry[1]
		var lot := "H02 / %02d" % (index + 1)
		if index in [4, 5, 7]:
			crates.container(at, key, 0, size, true)
			_inspection_crate(at, size, key, lot, index)
		else:
			crates.container(at, key, 0, size)
			_obstacle(at + Vector3.UP * size.y * 0.5, size + Vector3(0.32, 0.0, 0.23), true)
		if entry[3]:
			var upper := Vector3(size.x - 0.55, 4.6, size.z - 0.35)
			crates.container(at + Vector3.UP * size.y, "container_%d" % ((int(entry[1]) + 1) % 3), 0, upper)
			_obstacle(at + Vector3.UP * (size.y + upper.y * 0.5), upper, false)
			for side in [-1.0, 1.0]:
				for front in [-1.0, 1.0]:
					_kit.box_bevel("bare_steel", Vector3(0.56, 0.17, 0.34),
						at + Vector3(side * (upper.x * 0.5 - 0.22), size.y + 0.026, front * (upper.z * 0.5 - 0.06)), 0.045)
		_panel(lot, at + Vector3(-size.x * 0.23, size.y - 1.1, size.z * 0.5 + 0.30), 0.09)
	for x in [-8.0, 8.0]:
		for z in range(-26, 9, 4):
			_kit.box("paint", Vector3(0.16, 0.028, 2.3), Vector3(x, 0.028, z))
		for z in [-21.0, -11.0, -1.0, 8.0]:
			_kit.box_bevel("metal_dark", Vector3(1.9, 0.07, 1.05), Vector3(x, 0.029, z), 0.07)
			for rib in 5:
				_kit.box("metal", Vector3(1.6, 0.027, 0.06), Vector3(x, 0.083, z - 0.34 + rib * 0.17))
	var crane := _cargo_crane()
	_elevated_service_gallery()
	for group in [Vector3(-20, 0, -31), Vector3(-31, 0, -30), Vector3(17.1, 0, -31), Vector3(34, 0, 15)]:
		_pallet(group)
		_cargo_pad(group + Vector3.UP * 0.026, Vector2(4.8, 3.6))
	return crane


func _inspection_crate(at: Vector3, size: Vector3, key: String, lot: String, index: int) -> void:
	var crate := Inspection.new()
	crate.position = at
	crate.name = "InspectionCrate%02d" % (index + 1)
	_root.add_child(crate)
	crate.build(size, key, lot, index, _kit)
	_inspection_crates.append(crate)
	for box in crate.fixed_boxes:
		var world_center := at + box.get_center()
		_obstacle(world_center, box.size, box.position.y < 0.25)


func _cargo_pad(at: Vector3, size: Vector2) -> void:
	# Open corners mark where freight is tied down, leaving a gap for pallet forks.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := at + Vector3(size.x * 0.5 * sx, 0, size.y * 0.5 * sz)
			_kit.box("paint", Vector3(0.90, 0.018, 0.10), corner - Vector3(sx * 0.45, 0, 0))
			_kit.box("paint", Vector3(0.10, 0.018, 0.69), corner - Vector3(0, 0, sz * 0.345))


func _cargo_crane() -> Dictionary:
	var at := LIFT_CENTER
	var runway_z := -3.0
	# Runways are hung from existing roof beams. Cross-bridge trucks ride the lower flanges.
	for x in [-18.65, 19.05]:
		_box("track", Vector3(x, 15.10, runway_z), Vector3(0.39, 0.72, 54.0), true, false)
		for y in [14.72, 15.46]:
			_box("orion_frame", Vector3(x, y, runway_z), Vector3(0.84, 0.15, 54.0), true, false)
		for z in [-23.0, -10.0, 3.0, 16.0]:
			_kit.box_bevel("orion_frame", Vector3(0.58, 2.89, 0.66), Vector3(x, 16.94, z), 0.067)
			_kit.box_bevel("bare_steel", Vector3(1.08, 0.23, 0.83), Vector3(x, 18.34, z), 0.047)
			_kit.box_bevel("metal_dark", Vector3(1.08, 0.21, 0.73), Vector3(x, 15.56, z), 0.033)
	var bridge := Node3D.new()
	bridge.name = "TravellingCraneBridge"
	bridge.position.z = at.z
	_root.add_child(bridge)
	var bridge_kit := Kit.new()
	for key in ["track", "orion_frame", "bare_steel", "metal_dark", "safety_yellow", "amber"]:
		bridge_kit.material(key, _kit.mats[key])
	for x in [-18.65, 19.05]:
		bridge_kit.box_bevel("metal_dark", Vector3(1.17, 0.73, 4.0), Vector3(x, 14.20, 0), 0.064)
		for z in [-1.34, 1.34]:
			for dx in [-0.43, 0.43]:
				var wheel := Vector3(x + dx, 14.61, z)
				bridge_kit.tube("bare_steel", [wheel - Vector3.RIGHT * 0.17, wheel + Vector3.RIGHT * 0.17], 0.30, 16)
				bridge_kit.tube("track", [wheel + Vector3.RIGHT * 0.15, wheel + Vector3.RIGHT * 0.22], 0.145, 12)
	for dz in [-0.98, 0.98]:
		var girder := Vector3(0.20, 14.03, dz)
		bridge_kit.box_bevel("safety_yellow", Vector3(37.75, 1.17, 0.44), girder, 0.065)
		for y in [-0.55, 0.55]:
			bridge_kit.box_bevel("orion_frame", Vector3(37.78, 0.17, 0.86), girder + Vector3.UP * y, 0.032)
		for x in range(-17, 19, 4):
			bridge_kit.box_bevel("metal_dark", Vector3(0.15, 1.04, 0.50),
				Vector3(x, girder.y, girder.z), 0.031)
	var bridge_tag := Vector3(at.x + 0.05, 14.08, 1.25)
	bridge_kit.box_bevel("metal_dark", Vector3(3.12, 0.70, 0.13), bridge_tag, 0.052)

	var trolley := Vector3(at.x, 13.18, 0.0)
	bridge_kit.box_bevel("metal_dark", Vector3(4.75, 1.07, 2.54), trolley, 0.063)
	bridge_kit.box_bevel("safety_yellow", Vector3(4.38, 0.50, 0.22),
		trolley + Vector3(0, -0.22, 1.25), 0.057)
	for x in [-1.72, 1.72]:
		for z in [-1.02, 1.02]:
			var axle := trolley + Vector3(x, 0.46, z)
			bridge_kit.tube("track", [axle - Vector3.BACK * 0.34, axle + Vector3.BACK * 0.34], 0.26, 16)
			bridge_kit.tube("bare_steel", [axle, axle + Vector3.BACK * 0.42], 0.101, 12)
	var drum := trolley + Vector3(0, 0.04, 1.36)
	bridge_kit.tube("metal_dark", [drum - Vector3.RIGHT * 1.18, drum + Vector3.RIGHT * 1.18], 0.32, 18)
	for x in [-1.19, -0.7, -0.54, 0.54, 0.7, 1.19]:
		bridge_kit.tube("track", [drum + Vector3.RIGHT * (x - 0.045),
			drum + Vector3.RIGHT * (x + 0.045)], 0.37, 18)
	var ropes := Node3D.new()
	ropes.name = "LiftRopes"
	ropes.position = Vector3(at.x, 12.66, 0)
	bridge.add_child(ropes)
	var cable_kit := Kit.new()
	cable_kit.material("track", _kit.mats["bare_steel"])
	for x in [-1.72, 1.72]:
		for z in [-0.87, 0.87]:
			var anchor := Vector3(x, 0, z)
			cable_kit.tube("track", [anchor, anchor - Vector3.UP], 0.057, 10)
			bridge_kit.box_bevel("track", Vector3(0.24, 0.31, 0.24),
				ropes.position + anchor + Vector3.UP * 0.108, 0.043)
	cable_kit.commit(ropes, "FourHoistLines")
	bridge_kit.commit(bridge, "BridgeAndHoist")
	var bridge_label := _panel("LIFT 01", bridge_tag + Vector3.BACK * 0.076, 0.087)
	_root.remove_child(bridge_label)
	bridge.add_child(bridge_label)

	var load := Node3D.new()
	load.name = "LiftSpreaderAndCargo"
	load.position = at
	_root.add_child(load)
	var load_kit := Kit.new()
	for key in ["bare_steel", "track", "container_2", "metal_dark", "metal", "orion_frame", "cyan", "safety_yellow"]:
		load_kit.material(key, _kit.mats[key])
	var crate_size := Vector3(5.55, 2.60, 2.70)
	CargoContainer.new(load_kit).container(Vector3.ZERO, "container_2", 0.0, crate_size)
	var spreader_at := Vector3.UP * (crate_size.y + 0.48)
	var spreader_size := Vector3(5.87, 0.42, 3.04)
	load_kit.box_bevel("safety_yellow", spreader_size, spreader_at, 0.073)
	for x in [-1.72, 1.72]:
		for z in [-0.87, 0.87]:
			load_kit.box_bevel("track", Vector3(0.53, 0.25, 0.40),
				spreader_at + Vector3(x, 0.24, z), 0.041)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lock := Vector3(sx * (crate_size.x * 0.5 - 0.09),
				crate_size.y + 0.18, sz * (crate_size.z * 0.5 - 0.09))
			load_kit.box_bevel("metal_dark", Vector3(0.48, 0.40, 0.42), lock, 0.048)
			load_kit.tube("bare_steel", [lock - Vector3.UP * 0.20, lock - Vector3.UP * 0.076], 0.133, 12)
	load_kit.box_bevel("metal_dark", Vector3(3.44, 0.78, 0.18), Vector3(0, 1.36, 1.45), 0.047)
	load_kit.commit(load, "SpreaderAndLockedFreight")
	var tag := _panel("H02 / LIFT 01", Vector3(0, 1.38, 1.551), 0.085)
	_root.remove_child(tag)
	load.add_child(tag)

	var near_dock := at
	var far_dock := Vector3(at.x, 0.0, LIFT_FAR_Z)
	_lift_dock(near_dock, "A")
	_lift_dock(far_dock, "B")
	var control := at + Vector3(-4.75, 0, -0.3)
	var readout := _lift_console(control)
	var cargo_volumes: Array[Dictionary] = []
	for item in [[Vector3(0, crate_size.y * 0.5, 0), crate_size + Vector3(0.36, 0, 0.21)],
			[spreader_at, spreader_size]]:
		var center: Vector3 = at + item[0]
		var size: Vector3 = item[1]
		cargo_volumes.append({"base": AABB(center - size * 0.5, size), "body": _body(center, size)})
	var bridge_volumes: Array[Dictionary] = []
	for item in [[Vector3(0.20, 14.03, at.z - 0.98), Vector3(37.78, 1.31, 0.86)],
			[Vector3(0.20, 14.03, at.z + 0.98), Vector3(37.78, 1.31, 0.86)],
			[trolley + Vector3.BACK * at.z, Vector3(4.75, 1.07, 2.54)]]:
		var center: Vector3 = item[0]
		var size: Vector3 = item[1]
		bridge_volumes.append({"base": AABB(center - size * 0.5, size), "body": _body(center, size)})
	return {"load": load, "bridge": bridge, "ropes": ropes, "seat_height": spreader_at.y + 0.27,
		"volumes": cargo_volumes, "bridge_volumes": bridge_volumes,
		"station": control, "status": readout, "docks": [near_dock, far_dock],
		"interact_at": control + Vector3(-0.68, 2.02, 0.65)}


func _lift_dock(at: Vector3, bay: String) -> void:
	# Matching recessed pads sit in the freight bay, west of the through aisle.
	var pad_center := at + Vector3.UP * 0.021
	_kit.box("work_ceiling", Vector3(7.4, 0.016, 5.05), pad_center)
	_cargo_pad(pad_center + Vector3.UP * 0.018, Vector2(7.69, 5.32))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_kit.box_bevel("track", Vector3(0.62, 0.026, 0.46),
				pad_center + Vector3(sx * 2.68, 0.027, sz * 1.26), 0.012)
	for x in range(-3, 4):
		var mark := pad_center + Vector3(x * 0.91, 0.022, 2.29)
		_kit.quad("paint", [mark + Vector3(-0.32, 0, 0.14), mark + Vector3(-0.08, 0, -0.14),
			mark + Vector3(0.32, 0, -0.14), mark + Vector3(0.08, 0, 0.14)], Vector3.UP)
	var ground_tag := _panel("LIFT 01   /   " + bay, pad_center + Vector3(0, 0.020, 1.53), 0.17)
	ground_tag.rotation.x = -PI * 0.5


func _lift_console(at: Vector3) -> Label3D:
	_box("orion_frame", at + Vector3(0, 0.76, 0), Vector3(2.15, 1.52, 1.22), true)
	_kit.box_bevel("metal_dark", Vector3(2.35, 0.16, 1.46), at + Vector3.UP * 0.10, 0.073)
	for x in [-0.52, 0.52]:
		var access := at + Vector3(x, 0.78, 0.624)
		_kit.box_bevel("metal_dark", Vector3(0.96, 1.05, 0.096), access, 0.052)
		_kit.box_bevel("bare_steel", Vector3(0.31, 0.055, 0.065),
			access + Vector3(0, 0.354, 0.06), 0.021)
		for vent in 3:
			_kit.box("track", Vector3(0.62, 0.045, 0.011),
				access + Vector3(0, -0.34 + vent * 0.094, 0.055))
	_box("track", at + Vector3(0, 1.52, 0), Vector3(2.45, 0.21, 1.45), true, false)
	_box("orion_frame", at + Vector3(0, 2.18, -0.27), Vector3(2.16, 1.24, 0.45), true, false)
	_kit.box_bevel("bare_steel", Vector3(2.025, 1.067, 0.12), at + Vector3(0, 2.20, -0.042), 0.053)
	_kit.box_bevel("metal_dark", Vector3(1.93, 0.98, 0.092), at + Vector3(0, 2.20, -0.015), 0.052)
	var header := _panel("LIFT CONTROL / 01", at + Vector3(0, 2.49, 0.040), 0.034)
	header.modulate = Color("cabd9f")
	_kit.box("amber", Vector3(1.65, 0.028, 0.025), at + Vector3(0, 2.33, 0.047))
	for x in [-0.12, 0.20, 0.52]:
		_kit.box_bevel("bare_steel", Vector3(0.19, 0.072, 0.24), at + Vector3(x, 1.66, 0.36), 0.03)
	_kit.box_bevel("safety_yellow", Vector3(0.37, 0.11, 0.37), at + Vector3(-0.68, 1.67, 0.38), 0.04)
	_kit.tube("metal_dark", [at + Vector3(-0.68, 1.69, 0.38),
		at + Vector3(-0.68, 1.82, 0.38)], 0.125, 14)
	var indicator := at + Vector3(0.78, 2.94, -0.20)
	_kit.box_bevel("track", Vector3(0.45, 0.31, 0.34), indicator, 0.039)
	_kit.box_bevel("amber", Vector3(0.32, 0.14, 0.099), indicator + Vector3.BACK * 0.152, 0.026)
	var status := _panel("A 位待机", at + Vector3(-0.10, 2.08, 0.052), 0.052)
	status.outline_size = 0
	return status


func _elevated_service_gallery() -> void:
	var deck_y := SERVICE_DECK_Y
	_box("orion_frame", Vector3(-31, 10.34, -18.7), Vector3(9.2, 0.6, 28.0), true, false)
	_kit.box_bevel("metal_dark", Vector3(0.56, 0.93, 28.3),
		Vector3(-26.55, 10.27, -18.7), 0.07)
	# Cantilevers land on the existing ribs at z = -39 + 9n, clear of the freight aisle.
	for z in [-30.0, -21.0, -12.0]:
		_box("orion_frame", Vector3(-34.31, 10.12, z), Vector3(14.69, 0.60, 0.70), true, false)
		_kit.box_bevel("track", Vector3(0.87, 3.92, 0.98), Vector3(-41.19, 8.32, z), 0.098)
		for side in [-1.0, 1.0]:
			var offset: float = side * 0.26
			_steel_member(Vector3(-41.02, 6.52, z + offset),
				Vector3(-28.56, 10.11, z + offset), 0.29, 0.43)
			for y in [6.72, 9.54]:
				var pin := Vector3(-40.70, y, z + offset)
				_kit.tube("bare_steel", [pin, pin + Vector3.RIGHT * 0.073], 0.068, 8)
	for z in [-30.0, -24.0, -18.0, -12.0, -6.0]:
		var light := Vector3(-30.01, 9.94, z)
		_kit.box_bevel("metal_dark", Vector3(3.94, 0.23, 0.42), light, 0.038)
		_kit.box("white", Vector3(3.63, 0.050, 0.22), light - Vector3.UP * 0.127)

	# The main rail opens onto the staircase at the fixed runway inspection point.
	for interval in [Vector2(-32.63, -29.57), Vector2(-26.23, -4.82)]:
		_service_rail(Vector3(-26.49, deck_y, interval.x), Vector3(-26.49, deck_y, interval.y))
	_service_rail(Vector3(-35.4, deck_y, -32.58), Vector3(-35.4, deck_y, -4.88))
	_service_rail(Vector3(-35.40, deck_y, -32.58), Vector3(-26.49, deck_y, -32.58))
	_panel("SERVICE  /  03", Vector3(-26.18, 10.45, -14.2), 0.098, PI * 0.5)
	_service_ladder(deck_y)
	_runway_service_point(deck_y)


func _service_ladder(deck_y: float) -> void:
	var at := SERVICE_LADDER
	# Ladder stiles stay outside the platform edge and meet a dedicated landing.
	var landing := Vector3(at.x, deck_y - 0.13, -4.52)
	_box("track", landing, Vector3(2.72, 0.26, 0.70), true, false)
	_kit.box_bevel("safety_yellow", Vector3(1.77, 0.081, 0.22),
		landing + Vector3(0, 0.095, 0.24), 0.030)
	for z in [-4.43, -4.59, -4.75]:
		_kit.box("tread", Vector3(1.77, 0.035, 0.072), Vector3(at.x, deck_y + 0.012, z))
	for side in [-1.0, 1.0]:
		var x: float = at.x + side * LADDER_HALF_WIDTH
		_box("track", Vector3(x, 5.62, at.z), Vector3(0.19, 11.24, 0.23), true, false)
		_kit.box_bevel("orion_frame", Vector3(0.44, 0.20, 0.50), Vector3(x, 0.11, at.z), 0.04)
		_kit.box_bevel("track", Vector3(0.40, 0.47, 0.68), Vector3(x, 10.52, at.z - 0.14), 0.047)
		_kit.tube("bare_steel", [Vector3(x, 10.79, at.z), Vector3(x, 11.61, at.z),
			Vector3(x, 11.87, at.z - 0.24), Vector3(x, 11.87, at.z - 0.83),
			Vector3(x, 10.63, at.z - 0.83)], 0.073, 10)
	for i in LADDER_RUNG_COUNT:
		var y := LADDER_FIRST_RUNG + i * LADDER_RUNG_PITCH
		_kit.tube("bare_steel", [Vector3(at.x - LADDER_HALF_WIDTH, y, at.z),
			Vector3(at.x + LADDER_HALF_WIDTH, y, at.z)], 0.056, 8)
	var bottom_grip := ladder_interact_at(0.0) + Vector3(0, -0.30, -0.21)
	var upper_grip := ladder_interact_at(deck_y) + Vector3(0, -0.28, 0.17)
	for grip in [bottom_grip, upper_grip]:
		_kit.box_bevel("safety_yellow", Vector3(0.25, 0.35, 0.25), grip, 0.047)
	for sides in [Vector2(-35.40, -35.08), Vector2(-32.32, -26.49)]:
		_service_rail(Vector3(sides.x, deck_y, -4.82), Vector3(sides.y, deck_y, -4.82))


static func ladder_interact_at(height: float) -> Vector3:
	if height < SERVICE_DECK_Y * 0.5:
		return SERVICE_LADDER + Vector3(-LADDER_HALF_WIDTH, 2.47, 0.30)
	return SERVICE_LADDER + Vector3(LADDER_HALF_WIDTH, SERVICE_DECK_Y + 1.42, -1.0)


func _world_interact_hint() -> Label3D:
	var cue := Label3D.new()
	cue.name = "WorldInteractHint"
	cue.font_size = 44
	cue.pixel_size = 0.0047
	cue.modulate = Color("dedfe3")
	cue.outline_size = 7
	cue.outline_modulate = Color("24272d")
	cue.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cue.hide()
	_root.add_child(cue)
	return cue


func _runway_service_point(deck_y: float) -> void:
	var z := -27.90
	var rise := 0.207
	var run := 0.35
	var step_count := 12
	var top := deck_y + float(step_count) * rise
	for i in step_count:
		var y := deck_y + float(i + 1) * rise
		var size := Vector3(run + 0.07, 0.145, 3.12)
		var stair := Vector3(-26.45 + (float(i) + 0.5) * run, y - size.y * 0.5, z)
		_box("track", stair, size, true, false)
		_service_treads.append(_camera_solids.back())
		_kit.box("paint", Vector3(0.055, 0.021, 2.96), stair + Vector3(-0.11, 0.073, 0.0))
	for side in [-1.0, 1.0]:
		var edge: float = z + side * 1.57
		_steel_member(Vector3(-26.59, deck_y - 0.19, edge), Vector3(-22.18, top - 0.19, edge), 0.17, 0.32)
		_steel_member(Vector3(-27.04, deck_y - 0.42, edge), Vector3(-19.56, top - 0.30, edge), 0.29, 0.36)
		_service_rail(Vector3(-26.46, deck_y, edge), Vector3(-22.25, top, edge))
		_service_rail(Vector3(-22.25, top, edge), Vector3(-19.40, top, edge))
	_box("orion_frame", Vector3(-20.83, top - 0.15, z), Vector3(2.87, 0.30, 3.22), true, false)
	_service_rail(Vector3(-19.42, top, z - 1.57), Vector3(-19.42, top, z + 1.57))
	# The cutoff enclosure bolts to the fixed rail, clear of the moving bridge.
	var cutoff := Vector3(-19.26, 14.92, z)
	for y in [14.73, 15.45]:
		_kit.box_bevel("bare_steel", Vector3(0.85, 0.16, 0.78), Vector3(-19.12, y, z), 0.03)
	_kit.box_bevel("track", Vector3(0.69, 1.42, 1.38), cutoff, 0.07)
	_kit.box_bevel("metal_dark", Vector3(0.21, 1.08, 1.12), cutoff + Vector3.LEFT * 0.35, 0.039)
	_kit.box("amber", Vector3(0.043, 0.10, 0.48), cutoff + Vector3(-0.47, 0.33, 0))
	_kit.tube("track", [cutoff + Vector3(0, 0.64, 0), Vector3(-19.30, 15.78, z),
		Vector3(-18.68, 15.78, z - 0.55), Vector3(-18.65, 15.40, z - 0.55)], 0.080, 10)
	_kit.box_bevel("metal_dark", Vector3(2.80, 0.54, 0.16), Vector3(-20.85, top - 0.025, z + 1.61), 0.043)
	_panel("LIFT 01 / SERVICE", Vector3(-20.85, top - 0.01, z + 1.70), 0.056)


func _steel_member(a: Vector3, b: Vector3, thickness: float, depth: float) -> void:
	_kit.push_xf(Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) * 0.5))
	_kit.box_bevel("orion_frame", Vector3(thickness, depth, a.distance_to(b) + 0.065), Vector3.ZERO, 0.040)
	_kit.pop_xf()


func _service_rail(start: Vector3, end: Vector3) -> void:
	for height in [0.66, 1.35]:
		_kit.tube("bare_steel", [start + Vector3.UP * height, end + Vector3.UP * height], 0.052, 8)
	var steps := maxi(1, ceili(start.distance_to(end) / 3.5))
	for i in steps + 1:
		var post := start.lerp(end, float(i) / steps)
		_box("track", post + Vector3.UP * 0.68, Vector3(0.13, 1.36, 0.15), true, false)


func _service_wall() -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * 40.68
		_kit.tube("track", [Vector3(x, 8.15, -39.0), Vector3(x, 8.15, 38.0)], 0.14, 9)
		for z in [-30.0, -12.0, 6.0, 24.0]:
			_kit.box_bevel("orion_frame", Vector3(1.56, 0.22, 0.36),
				Vector3(x + side * 0.69, 7.99, z), 0.040)
			_kit.tube("bare_steel", [Vector3(x, 8.15, z - 0.08), Vector3(x, 8.15, z + 0.08)], 0.196, 12)
		var bays := [-22.0, 7.0, 29.0]
		for i in bays.size():
			var z: float = bays[i]
			_box("orion_frame", Vector3(x, 2.43, z), Vector3(0.86, 4.86, 3.12), true)
			_kit.box_bevel("metal_dark", Vector3(0.14, 4.09, 2.66),
				Vector3(x - side * 0.45, 2.47, z), 0.10)
			for dz in [-0.66, 0.66]:
				_kit.box_bevel("track", Vector3(0.08, 2.78, 1.12),
					Vector3(x - side * 0.53, 2.24, z + dz), 0.05)
				var handle := Vector3(x - side * 0.65, 2.34, z + dz * 0.25)
				_kit.tube("bare_steel", [handle + Vector3(side * 0.10, -0.24, 0),
					handle - Vector3.UP * 0.17, handle + Vector3.UP * 0.17,
					handle + Vector3(side * 0.10, 0.24, 0)], 0.055, 10)
				for y in [1.26, 3.27]:
					var hinge := Vector3(x - side * 0.548, y, z + signf(dz) * 1.24)
					_kit.tube("bare_steel", [hinge - Vector3.UP * 0.16, hinge + Vector3.UP * 0.16], 0.068, 10)
				for row in 3:
					_kit.box("metal_dark", Vector3(0.022, 0.074, 0.74),
						Vector3(x - side * 0.579, 1.08 + row * 0.114, z + dz))
			var tag := Vector3(x - side * 0.571, 3.88, z)
			_kit.box_bevel("metal_dark", Vector3(0.070, 0.42, 2.20), tag, 0.035)
			_panel("UTILITY / U-%02d" % (i + 1), tag - Vector3.RIGHT * (side * 0.043),
				0.030, -side * PI * 0.5)
			_kit.tube("track", [Vector3(x - side * 0.17, 4.81, z - 0.92),
				Vector3(x - side * 0.17, 7.41, z - 0.92), Vector3(x, 8.15, z - 0.28)], 0.098, 8)
			_kit.box("amber", Vector3(0.037, 0.088, 0.34), Vector3(x - side * 0.535, 4.22, z + 0.68))


func _security_berth() -> Dictionary:
	var door := Vector3(SECURITY_X, 0, SECURITY_DOOR_Z)
	# An old patrol unit occupies the inset beside the freight stacks. The doorway
	# looks across the service aisle and has its own amber local warning.
	_box("wall", door + Vector3(0, 4.55, -9.08), Vector3(9.9, 9.1, 0.60), true)
	for side in [-1.0, 1.0]:
		_box("wall", door + Vector3(side * 4.72, 3.88, -4.5), Vector3(0.52, 7.76, 9.4), true)
		_box("orion_frame", door + Vector3(side * 4.54, 3.94, 0.09), Vector3(0.74, 7.88, 0.92), true)
		_kit.box_bevel("track", Vector3(0.18, 6.72, 0.25),
			door + Vector3(side * 4.17, 3.56, 0.24), 0.03)
		_kit.box_bevel("safety_yellow", Vector3(0.79, 0.61, 0.28),
			door + Vector3(side * 4.54, 0.57, 0.64), 0.04)
	_box("orion_frame", door + Vector3(0, 8.09, -4.5), Vector3(9.96, 0.73, 9.6), true, false)
	_box("metal_dark", door + Vector3(0, 8.04, 0.06), Vector3(9.97, 0.83, 1.13), true, false)
	var hoist_at := door + Vector3(0, 11.95, -0.04)
	var hoist_size := Vector3(8.93, 6.91, 0.67)
	_kit.box_bevel("orion_frame", hoist_size, hoist_at, 0.11)
	_patrol_back_note(hoist_at + Vector3(0.30, 0.10, -hoist_size.z * 0.5 - 0.012))
	_kit.box_bevel("metal_dark", Vector3(8.04, 0.65, 0.14), door + Vector3(0, 8.65, 0.481), 0.05)
	_panel("PATROL SERVICE   /   D-03", door + Vector3(0, 8.67, 0.561), 0.094)
	_kit.box("tread", Vector3(8.56, 0.038, 1.16), door + Vector3(0, 0.021, -0.14))
	_cargo_pad(Vector3(BASIC_SPAWN.x, 0.025, BASIC_SPAWN.z), Vector2(5.5, 3.95))
	for side in [-1.0, 1.0]:
		_kit.box_bevel("metal_dark", Vector3(1.1, 2.09, 0.36),
			door + Vector3(side * 3.59, 1.04, -8.68), 0.10)
		_kit.tube("bare_steel", [door + Vector3(side * 3.56, 2.16, -8.60),
			door + Vector3(side * 3.56, 4.10, -8.60), door + Vector3(side * 2.75, 4.42, -8.60)], 0.083, 8)
		var roof_fixture := door + Vector3(side * 1.89, 7.665, -6.75)
		_kit.box_bevel("metal_dark", Vector3(3.48, 0.17, 0.31), roof_fixture, 0.034)
		_kit.box("white", Vector3(3.23, 0.044, 0.18), roof_fixture - Vector3.UP * 0.098)
	_light(door + Vector3(0, 6.94, -5.09), Color("ecdfc8"), 1.51, 9.3)
	var fixture := door + Vector3(3.34, 8.01, 0.625)
	var lamp := _door_indicator(fixture)
	var warning := _light(fixture + Vector3(0, -0.16, 0.33), Color("ecab54"), 0.0, 6.1)

	var frame := Node3D.new()
	frame.name = "PatrolServiceShutter"
	frame.position = door
	_root.add_child(frame)
	var leaf := Kit.new()
	for key in ["metal_dark", "orion_frame", "track", "bare_steel", "safety_yellow"]:
		leaf.material(key, _kit.mats[key])
	leaf.box_bevel("metal_dark", Vector3(8.48, 7.38, 0.46), Vector3(0, 3.69, 0), 0.08)
	for i in 9:
		leaf.box_bevel("orion_frame", Vector3(8.31, 0.72, 0.23), Vector3(0, 0.61 + i * 0.765, 0.24), 0.045)
	for x in [-4.05, 4.05]:
		leaf.box_bevel("track", Vector3(0.19, 7.15, 0.29), Vector3(x, 3.66, 0.25), 0.055)
	leaf.box_bevel("safety_yellow", Vector3(8.32, 0.22, 0.14), Vector3(0, 0.26, 0.39), 0.04)
	leaf.commit(frame, "ServiceShutterLeaf")
	var size := Vector3(8.48, 7.38, 0.55)
	var at := door + Vector3.UP * 3.69
	var collider := _body(at, size)
	return {"panel": frame, "collider": collider, "box": AABB(at - size * 0.5, size),
		"stroke": 7.50, "lamp": lamp, "warning": warning}


func _patrol_back_note(at: Vector3) -> void:
	var chalk := _panel("下一轮巡检，轮到你了。", at, 0.054, PI)
	chalk.name = "PatrolBackNote"
	chalk.rotation.z = -0.033
	chalk.outline_size = 0
	chalk.modulate = Color("c8baa6")
	var signature := _panel("—— 上一班留", at + Vector3(-0.85, -0.48, -0.005), 0.028, PI)
	signature.rotation.z = -0.033
	signature.outline_size = 0
	signature.modulate = Color("a99d8e")


func _door_indicator(mount: Vector3) -> StandardMaterial3D:
	_kit.box_bevel("metal_dark", Vector3(1.08, 0.25, 0.16), mount + Vector3.BACK * 0.063, 0.035)
	var light_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.67, 0.099, 0.046)
	light_mesh.mesh = mesh
	light_mesh.position = mount + Vector3.BACK * 0.152
	var mat := _glow(Color("b0834b"), 0.42)
	light_mesh.material_override = mat
	_root.add_child(light_mesh)
	return mat


func _airlock() -> Dictionary:
	for side in [-1.0, 1.0]:
		var x: float = EXIT_X + side * 5.5
		_box("wall", Vector3(x, 4.35, -38.1), Vector3(0.88, 8.7, 12.6), true)
		_box("orion_frame", Vector3(x, 4.72, EXIT_DOOR_Z), Vector3(1.1, 9.44, 0.95), true)
		_kit.box_bevel("bare_steel", Vector3(0.19, 6.6, 0.14), Vector3(x - side * 0.44, 3.81, EXIT_DOOR_Z + 0.50), 0.03)
		_kit.box("safety_yellow", Vector3(0.50, 0.47, 0.19), Vector3(x - side * 0.04, 0.53, EXIT_DOOR_Z + 0.54))
		for z in [-35.7, -40.0]:
			_box("metal_dark", Vector3(x - side * 0.55, 4.46, z), Vector3(0.34, 2.0, 2.72), true, false)
			_kit.box_bevel("track", Vector3(0.12, 1.55, 2.49),
				Vector3(x - side * 0.74, 4.43, z), 0.055)
			_kit.box_bevel("metal_dark", Vector3(0.095, 1.19, 2.28),
				Vector3(x - side * 0.789, 4.38, z), 0.042)
			for i in 6:
				_kit.box("bare_steel", Vector3(0.061, 0.047, 2.12),
					Vector3(x - side * 0.857, 4.0 + i * 0.135, z))
			for shift in [-1.09, 1.09]:
				var catch := Vector3(x - side * 0.823, 4.93, z + shift)
				_kit.box_bevel("orion_frame", Vector3(0.065, 0.18, 0.095), catch, 0.023)
			_panel("PRESSURE / RETURN", Vector3(x - side * 0.83, 5.00, z),
				0.021, -side * PI * 0.5)
	_box("orion_frame", Vector3(EXIT_X, EXIT_ROOF_Y + 0.275, -38.1), Vector3(11.8, 0.55, 12.6), true, false)
	_box("metal_dark", Vector3(EXIT_X, 8.28, EXIT_DOOR_Z), Vector3(12.4, 1.05, 1.2), true, false)
	_kit.box_bevel("orion_frame", Vector3(11.8, 7.5, 0.82), Vector3(EXIT_X, 12.55, EXIT_DOOR_Z + 0.70), 0.18)
	_kit.box("metal_dark", Vector3(9.4, 5.8, 0.17), Vector3(EXIT_X, 12.65, EXIT_DOOR_Z + 1.14))
	for x in [-4.0, 4.0]:
		_kit.box("track", Vector3(0.16, 4.6, 0.11), Vector3(EXIT_X + x, 12.6, EXIT_DOOR_Z + 1.25))
	_panel("PERSONNEL AIRLOCK", Vector3(EXIT_X, 8.36, EXIT_DOOR_Z + 0.673), 0.112)
	var interlock := Vector3(EXIT_X + 5.05, 3.15, EXIT_DOOR_Z + 0.71)
	_box("orion_frame", interlock, Vector3(0.70, 1.05, 0.30), true, false)
	_kit.box_bevel("metal_dark", Vector3(0.58, 0.84, 0.10), interlock + Vector3.BACK * 0.181, 0.032)
	_panel("INTERLOCK", interlock + Vector3(0, 0.31, 0.24), 0.012)
	for i in 2:
		var row := interlock + Vector3(0, 0.16 - float(i) * 0.17, 0.235)
		_kit.box("track", Vector3(0.43, 0.13, 0.022), row)
		_kit.box(["cyan", "amber"][i], Vector3(0.069, 0.040, 0.025), row + Vector3(0.15, 0, 0.020))
		_panel(["SEAL", "LINK"][i], row + Vector3(-0.062, 0, 0.019), 0.010)
	_kit.box_bevel("safety_yellow", Vector3(0.26, 0.16, 0.09), interlock + Vector3(0, -0.24, 0.22), 0.04)
	_kit.box("metal_dark", Vector3(0.13, 0.052, 0.026), interlock + Vector3(0, -0.243, 0.277))
	_kit.tube("track", [interlock + Vector3(0.17, 0.56, 0), interlock + Vector3(0.17, 2.95, 0),
		interlock + Vector3(-0.63, 3.64, 0)], 0.066, 8)
	var lamp := _door_indicator(Vector3(EXIT_X + 4.3, 8.05, EXIT_DOOR_Z + 0.60))
	_kit.box_bevel("orion_frame", Vector3(9.43, 7.2, 0.34), Vector3(EXIT_X, 3.68, -45.55), 0.16)
	_kit.box_bevel("metal_dark", Vector3(7.89, 6.14, 0.14), Vector3(EXIT_X, 3.34, -45.32), 0.10)
	_kit.box("track", Vector3(6.24, 0.10, 0.08), Vector3(EXIT_X, 1.02, -45.20))
	_panel("CENTRAL GALLERIA", Vector3(EXIT_X, 7.65, -44.34), 0.086)
	_pressure_hatch_detail()
	_plate(Vector3(EXIT_X, 0.03, EXIT_DOOR_Z + 0.5), 9.7)
	for z in [-35.9, -41.0]:
		_kit.box_bevel("metal_dark", Vector3(7.78, 0.16, 0.52), Vector3(EXIT_X, 8.421, z), 0.046)
		_kit.box("white", Vector3(7.4, 0.045, 0.36), Vector3(EXIT_X, 8.328, z))
		_kit.box_bevel("metal_dark", Vector3(11.0, 0.46, 0.68), Vector3(EXIT_X, 8.23, z + 0.44), 0.08)
		for side in [-1.0, 1.0]:
			_kit.box_bevel("orion_frame", Vector3(0.36, 7.9, 0.61), Vector3(EXIT_X + side * 4.88, 4, z + 0.44), 0.06)
			_kit.box("track", Vector3(0.115, 3.03, 0.08), Vector3(EXIT_X + side * 4.78, 4.2, z + 0.81))
		_kit.box("track", Vector3(8.6, 0.026, 0.21), Vector3(EXIT_X, 0.031, z + 0.43))
	var frame := Node3D.new()
	frame.name = "EvacuationGate"
	frame.position = Vector3(EXIT_X, 0, EXIT_DOOR_Z)
	_root.add_child(frame)
	var leaf := Kit.new()
	for key in ["orion_frame", "metal_dark", "metal", "safety_yellow"]:
		leaf.material(key, _kit.mats[key])
	leaf.box_bevel("orion_frame", Vector3(9.92, 7.7, 0.58), Vector3(0, 3.85, 0), 0.14)
	for x in [-2.28, 2.28]:
		leaf.box_bevel("metal_dark", Vector3(4.21, 6.9, 0.16), Vector3(x, 3.83, 0.35), 0.16)
		for y in [1.15, 4.45, 6.55]:
			leaf.box("metal", Vector3(3.28, 0.11, 0.06), Vector3(x, y, 0.45))
		for rib in [-1.35, 1.35]:
			leaf.box_bevel("metal", Vector3(0.095, 5.79, 0.095), Vector3(x + rib, 3.67, 0.47), 0.025)
		leaf.box_bevel("safety_yellow", Vector3(3.87, 0.18, 0.09), Vector3(x, 0.46, 0.45), 0.035)
	leaf.commit(frame, "GatePanel")
	var at := frame.position + Vector3.UP * 3.85
	var size := Vector3(9.94, 7.7, 0.84)
	at.z += 0.13
	var collider := _body(at, size)
	return {"panel": frame, "collider": collider, "box": AABB(at - size * 0.5, size),
		"stroke": 7.95, "lamp": lamp}


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
	_kit.box("white", Vector3(6.12, 0.057, 0.25), Vector3(EXIT_X, 7.327, rear_z + 0.16))
	_kit.box("tread", Vector3(9.25, 0.042, 1.45), Vector3(EXIT_X, 0.036, -43.82))
	for z in [-43.15, -44.43]:
		_kit.box("bare_steel", Vector3(9.18, 0.025, 0.13), Vector3(EXIT_X, 0.06, z))
	_kit.box_bevel("orion_frame", Vector3(0.12, 5.92, 0.11), Vector3(EXIT_X, 3.36, -45.17), 0.026)


func _guide(route_name: String, waypoints: Array[Vector3]) -> Node3D:
	var route := Node3D.new()
	route.name = route_name
	_root.add_child(route)
	var route_kit := Kit.new()
	route_kit.material("route", _glow(Color("62e1e9"), 1.8))
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


func _terminal(at: Vector3, title: String, record: String) -> void:
	_box("metal_dark", at + Vector3(0, 0.90, 0), Vector3(2.9, 1.8, 1.38), true)
	_box("orion_frame", at + Vector3.UP * 1.92, Vector3(3.38, 0.24, 1.61), true, false)
	_box("orion_frame", at + Vector3(0, 2.48, -0.43), Vector3(2.43, 1.07, 0.43), true, false)
	_kit.box_bevel("metal_dark", Vector3(2.18, 0.78, 0.085), at + Vector3(0, 2.49, -0.188), 0.04)
	_panel(title, at + Vector3(0, 2.63, -0.132), 0.035)
	_panel(record, at + Vector3(0, 2.398, -0.130), 0.028).modulate = Color("96aaa6")
	_kit.box("cyan", Vector3(1.73, 0.025, 0.025), at + Vector3(0, 2.31, -0.138))
	for x in [-1.0, -0.77, -0.54, -0.31, -0.08, 0.15, 0.38]:
		_kit.box_bevel("track", Vector3(0.18, 0.072, 0.22), at + Vector3(x, 2.069, 0.36), 0.023)
	_kit.box_bevel("safety_yellow", Vector3(0.27, 0.086, 0.26), at + Vector3(1.01, 2.078, 0.36), 0.03)
	for x in [-0.76, 0.76]:
		_kit.tube("track", [at + Vector3(x, 1.34, 0.70), at + Vector3(x, 0.83, 0.81),
			at + Vector3(x, 0.29, 0.71)], 0.061, 8)


func _staging_pallet(at: Vector3) -> void:
	# Three full-length runners carry the deck and leave two open fork channels.
	for z in [-1.24, 0.0, 1.24]:
		_box("orion_frame", at + Vector3(0, 0.34, z), Vector3(3.28, 0.68, 0.37), true)
		_kit.box_bevel("metal_dark", Vector3(3.34, 0.12, 0.44), at + Vector3(0, 0.063, z), 0.031)
	_box("track", at + Vector3(0, 0.715, 0), Vector3(3.3, 0.17, 2.82), true, false)
	for side in [-1.0, 1.0]:
		var face_x: float = side * 1.60
		for channel_z in [-0.62, 0.62]:
			_kit.box_bevel("bare_steel", Vector3(0.14, 0.095, 0.93),
				at + Vector3(face_x, 0.627, channel_z), 0.024)
			for z in [channel_z - 0.457, channel_z + 0.457]:
				_kit.box_bevel("bare_steel", Vector3(0.14, 0.55, 0.107),
					at + Vector3(face_x, 0.354, z), 0.023)
		for z in [-1.24, 1.24]:
			_kit.box_bevel("safety_yellow", Vector3(0.061, 0.34, 0.24),
				at + Vector3(side * 1.645, 0.388, z), 0.026)

	for x in [-1.06, 0.15]:
		_box("metal_dark", at + Vector3(x, 0.855, 0), Vector3(0.28, 0.14, 2.72), true, false)
	var case_at := at + Vector3(-0.45, 1.34, -0.19)
	var case_size := Vector3(1.82, 0.83, 1.68)
	_box("container_2", case_at, case_size, true, false)
	for strap_z in [-0.52, 0.52]:
		var strap := case_at + Vector3(0, 0, strap_z)
		_kit.box("track", Vector3(1.825, 0.035, 0.125), strap + Vector3.UP * 0.416)
		for side in [-1.0, 1.0]:
			_kit.box("track", Vector3(0.036, 0.837, 0.125), strap + Vector3(side * 0.912, 0, 0))
			var buckle := strap + Vector3(side * 1.025, -0.424, 0)
			_kit.box_bevel("metal_dark", Vector3(0.27, 0.245, 0.24), buckle, 0.041)
			_kit.box_bevel("safety_yellow", Vector3(0.225, 0.084, 0.175),
				buckle + Vector3(0, 0.108, 0.026), 0.028)
			_kit.tube("bare_steel", [buckle + Vector3(0, 0.071, -0.146),
				buckle + Vector3(0, 0.071, 0.146)], 0.037, 8)


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


func _panel(content: String, at: Vector3, scale: float, facing := 0.0) -> Label3D:
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
	return sign_label


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
	_work_light(Vector3(-0.25, 11.8, -15.5), Vector3(-5.3, 0.15, -24.2), Color("f1e7de"), 2.26, 18.0)


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
	# Mounts are on the receiving bulkhead, the D-03 hoist casing and the
	# outer and inner airlock lintels. The light follows the visible fixture.
	var mounts := [
		Vector3(-9.0, 7.30, WORK_PILLAR_FACE_Z),
		Vector3(SECURITY_X + 2.72, 10.12, SECURITY_DOOR_Z + 0.295),
		Vector3(EXIT_X - 0.2, 9.23, EXIT_DOOR_Z + 1.11),
		Vector3(EXIT_X + 3.69, 7.62, -44.405),
	]
	for mount: Vector3 in mounts:
		var housing := mount + Vector3.BACK * 0.143
		_kit.box_bevel("metal_dark", Vector3(1.58, 0.41, 0.32), housing, 0.073)
		_kit.box_bevel("alarm", Vector3(1.29, 0.23, 0.15), housing + Vector3.BACK * 0.17, 0.05)
		for x in [-0.77, 0.77]:
			_kit.box("metal", Vector3(0.085, 0.26, 0.08), housing + Vector3(x, 0, 0.18))
		var light := _light(housing + Vector3(0, -0.23, 0.41), Color("ff3159"), 0.0, 19.0)
		light.light_specular = 0.22
		_beacons.append(light)

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

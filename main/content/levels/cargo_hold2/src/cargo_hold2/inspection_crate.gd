extends Node3D
## A hollow cargo module with a vertical shutter and fixed interior equipment.

const Kit = preload("res://src/cargo_hold2/mesh_kit.gd")
const Rig = preload("res://team/vesper/scripts/mech/mech_rig.gd")
const FabricatorFx = preload("res://src/cargo_hold2/fabricator_fx.gd")
const ArcRig = preload("res://team/arc/scripts/ch/arc_rig.gd")
const OPEN_TIME := 1.25
const FABRICATION_TIME := 18.0
const SLATS := 12
const DOOR_BOTTOM := 0.035

var fixed_boxes: Array[AABB] = []
var shut_bounds: AABB
var current_bounds := AABB()
var collider: CollisionShape3D
var shutter: StaticBody3D
var opened := false
var interact_at := Vector3.ZERO
var opening_elapsed := 0.0

var _slats: Array[Node3D] = []
var _slat_pitch: float
var _header_y: float
var _clear_width: float
var _interior_light: OmniLight3D
var _is_fabricator: bool
var _print_head: Node3D
var _gantry: Node3D
var _ram: Node3D
var _print_lamp: OmniLight3D
var _readout: Label3D
var _print_fx: Node3D
var _shell: Node3D
var _deposited_armor: Array[MeshInstance3D] = []
var _fabrication_elapsed := 0.0


func _ready() -> void:
	_apply_shutter(0.0)


func build(size: Vector3, key: String, lot: String, index: int, source: CargoMeshKit) -> void:
	var kit := Kit.new()
	for material in ["orion_frame", "bare_steel", "track", "metal_dark", "metal", "tread", "white",
			"cyan", "amber", "paint", "safety_yellow", key]:
		kit.material(material, source.mats[material])
	var face := size.x * 0.5
	var half_width := size.z * 0.5
	_header_y = size.y - 0.48
	_clear_width = size.z - 0.64
	_is_fabricator = index == 5
	var manifest := "SHIP STORES" if index == 4 else ("FAB-02" if _is_fabricator else "CHASSIS SPARES")

	for side in [-1.0, 1.0]:
		var edge: float = side * (half_width - 0.125)
		_solid(Vector3(0, size.y * 0.5, edge), Vector3(size.x, size.y, 0.25))
		kit.box_bevel("orion_frame", Vector3(0.50, _header_y, 0.26),
			Vector3(face, _header_y * 0.5, side * (_clear_width * 0.5 + 0.12)), 0.035)
		_solid(Vector3(face, _header_y * 0.5, side * (_clear_width * 0.5 + 0.12)),
			Vector3(0.50, _header_y, 0.26))
		kit.box("track", Vector3(0.064, _header_y - 0.45, 0.052),
			Vector3(face + 0.265, _header_y * 0.5, side * (_clear_width * 0.5 + 0.12)))
	_solid(Vector3(-face + 0.15, size.y * 0.5, 0), Vector3(0.30, size.y, size.z))
	_solid(Vector3(0, size.y - 0.15, 0), Vector3(size.x, 0.30, size.z))
	kit.box_bevel("metal_dark", Vector3(0.79, 0.54, size.z - 0.12),
		Vector3(face - 0.18, _header_y + 0.27, 0), 0.055)
	_solid(Vector3(face - 0.18, _header_y + 0.27, 0), Vector3(0.79, 0.54, size.z - 0.12))
	kit.box("track", Vector3(0.12, 0.021, _clear_width), Vector3(face, 0.014, 0))
	_label(lot + "  /  " + manifest, Vector3(face + 0.232, _header_y + 0.25, 0), 0.010)
	var latch := Vector3(face + 0.25, 2.65, _clear_width * 0.5 + 0.12)
	interact_at = position + latch + Vector3(0.27, 0.37, 0)
	kit.box_bevel("metal_dark", Vector3(0.26, 0.42, 0.22), latch, 0.034)
	kit.box("cyan", Vector3(0.028, 0.07, 0.11), latch + Vector3(0.142, 0.07, 0))

	for z in [-0.94, 0.94]:
		var lamp := Vector3(-0.35, size.y - 0.34, z)
		kit.box_bevel("metal_dark", Vector3(size.x - 1.25, 0.15, 0.30), lamp, 0.035)
		kit.box("white", Vector3(size.x - 1.6, 0.037, 0.19), lamp - Vector3.UP * 0.091)
	_interior_light = _light(Vector3(face - 2.0, size.y - 0.78, 0.26), Color("e9eeff"), 4.0)
	_interior_light.hide()
	if _is_fabricator:
		_fabricator(kit, face)
	else:
		_stores(kit, face, index == 7)
	kit.commit(self, "Fittings")
	_build_shutter(source, key, face)


func _build_shutter(source: CargoMeshKit, key: String, face: float) -> void:
	var slat := Kit.new()
	for material in [key, "orion_frame", "bare_steel"]:
		slat.material(material, source.mats[material])
	_slat_pitch = (_header_y - DOOR_BOTTOM) / SLATS
	slat.box_bevel(key, Vector3(0.155, _slat_pitch + 0.004, _clear_width),
		Vector3.ZERO, 0.026)
	slat.box_bevel("orion_frame", Vector3(0.076, 0.075, _clear_width - 0.12),
		Vector3(0.093, -_slat_pitch * 0.39, 0), 0.020)
	slat.box("bare_steel", Vector3(0.025, 0.018, _clear_width - 0.20),
		Vector3(0.115, -_slat_pitch * 0.18, 0))
	var section := Node3D.new()
	section.name = "ShutterSlat"
	slat.commit(section, "RollProfile")
	add_child(section)
	_slats.append(section)
	for i in range(1, SLATS):
		var repeat := section.duplicate() as Node3D
		add_child(repeat)
		_slats.append(repeat)
	shutter = StaticBody3D.new()
	shutter.name = "ShutterCollider"
	collider = CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	shutter.add_child(collider)
	add_child(shutter)
	shut_bounds = AABB(Vector3(face - 0.09, DOOR_BOTTOM, -_clear_width * 0.5),
		Vector3(0.23, _header_y - DOOR_BOTTOM, _clear_width))


func standing_at_control(at: Vector3, facing: Vector3) -> bool:
	var local := at - global_position
	var dx := local.x - shut_bounds.position.x
	return not opened and absf(local.y) < 0.75 and dx > 0.45 and dx < 4.4 		and absf(local.z) < _clear_width * 0.5 + 0.65 and facing.dot(Vector3.LEFT) > 0.30


func start_opening() -> void:
	if _is_fabricator:
		if not is_instance_valid(_shell):
			_prepare_shell()
		_shell.show()
	opened = true


func reset() -> void:
	opened = false
	opening_elapsed = 0.0
	_fabrication_elapsed = 0.0
	_interior_light.hide()
	if is_instance_valid(_shell):
		_shell.hide()
		_print_fx.finish_print()
		_print_lamp.light_energy = 0.0
		_readout.text = "待机"
		_update_deposited_armor()
		_place_print_head(Vector3(-0.66, 3.66, 0.88))
	_apply_shutter(0.0)


func step(dt: float) -> bool:
	if not opened:
		return false
	var moving := opening_elapsed < OPEN_TIME
	if moving:
		opening_elapsed = minf(opening_elapsed + dt, OPEN_TIME)
		_apply_shutter(smoothstep(0.0, OPEN_TIME, opening_elapsed))
		_interior_light.visible = opening_elapsed > 0.19
	if _is_fabricator and opening_elapsed > 0.62 and _fabrication_elapsed < FABRICATION_TIME:
		_fabrication_elapsed = minf(_fabrication_elapsed + dt, FABRICATION_TIME)
		_print(dt)
	return moving


func _apply_shutter(t: float) -> void:
	var bottom := lerpf(DOOR_BOTTOM, _header_y, t)
	for i in _slats.size():
		var y := bottom + (float(i) + 0.5) * _slat_pitch
		var node := _slats[i]
		node.position = Vector3(shut_bounds.position.x + 0.09, y, 0)
		# The top slats disappear inside the reel housing.
		node.visible = y - _slat_pitch * 0.5 < _header_y - 0.002
	var thickness := _header_y - bottom
	collider.set_deferred("disabled", thickness <= 0.012)
	if thickness <= 0.012:
		current_bounds = AABB()
		return
	var local := AABB(Vector3(shut_bounds.position.x, bottom, shut_bounds.position.z),
		Vector3(shut_bounds.size.x, thickness, shut_bounds.size.z))
	shutter.position = local.get_center()
	(collider.shape as BoxShape3D).size = local.size
	current_bounds = AABB(global_position + local.position, local.size)


func _stores(kit: CargoMeshKit, face: float, spare: bool) -> void:
	var shelf_x := -face + 1.34
	for y in [0.35, 1.77, 3.10]:
		var deck := Vector3(shelf_x, y, 0)
		kit.box_bevel("orion_frame", Vector3(1.92, 0.14, 3.9), deck, 0.058)
		kit.box("safety_yellow", Vector3(0.065, 0.085, 3.72), deck + Vector3(0.95, -0.023, 0))
	for z in [-1.86, 1.86]:
		kit.box_bevel("orion_frame", Vector3(1.97, 3.56, 0.17), Vector3(shelf_x, 1.78, z), 0.043)
	_solid(Vector3(shelf_x, 1.78, 0), Vector3(1.98, 3.56, 3.91))
	var tray_size := Vector3(1.35, 0.45, 1.35)
	for z in [-0.92, 0.92]:
		_case(kit, Vector3(shelf_x, 0.64, z), tray_size, "bare_steel")
		_case(kit, Vector3(shelf_x, 3.40, z), Vector3(1.21, 0.44, 1.16), "track")
	var plinth := Vector3(0.32, 0.38, 0)
	kit.box_bevel("track", Vector3(1.53, 0.76, 2.55), plinth, 0.093)
	_solid(plinth, Vector3(1.53, 0.76, 2.55))
	if spare:
		var drive := ArcRig.service_track()
		drive.name = "ServiceDriveInTransit"
		drive.rotation.y = 0.30
		drive.scale = Vector3.ONE * 1.70
		drive.position = plinth + Vector3(0, 0.45, 0)
		add_child(drive)
		_solid(drive.position + Vector3.UP * 0.22, Vector3(1.36, 0.52, 1.95))
		for z in [-0.92, 0.92]:
			kit.box_bevel("tread", Vector3(1.2, 0.18, 0.20), plinth + Vector3(0, 0.45, z), 0.03)
		_label("ARC / DRIVE", plinth + Vector3(0.80, 0.07, 0), 0.007)
	else:
		for z in [-0.75, 0.75]:
			_case(kit, Vector3(shelf_x, 2.12, z), Vector3(1.24, 0.58, 1.18), "metal")
		_case(kit, plinth + Vector3(0, 0.74, -0.50), Vector3(1.35, 0.70, 1.25), "safety_yellow")
		_case(kit, plinth + Vector3(0, 0.65, 0.63), Vector3(1.20, 0.52, 0.81), "bare_steel")
		_label("SEALS  /  FILTERS", plinth + Vector3(0.80, 0.07, 0), 0.007)


func _case(kit: CargoMeshKit, at: Vector3, size: Vector3, key: String) -> void:
	kit.box_bevel(key, size, at, 0.068)
	_solid(at, size)
	kit.box("metal_dark", Vector3(size.x + 0.012, 0.060, size.z + 0.012),
		at + Vector3.UP * size.y * 0.28)
	for side in [-1.0, 1.0]:
		var clasp := at + Vector3(size.x * 0.5 + 0.031, size.y * 0.19, side * size.z * 0.27)
		kit.box_bevel("orion_frame", Vector3(0.078, 0.17, 0.15), clasp, 0.025)


func _fabricator(kit: CargoMeshKit, face: float) -> void:
	var bed := Vector3(-0.82, 0.28, 0)
	kit.box_bevel("orion_frame", Vector3(4.50, 0.56, 4.08), bed, 0.095)
	_solid(bed, Vector3(4.50, 0.56, 4.08))
	kit.box_bevel("tread", Vector3(3.98, 0.055, 3.61), bed + Vector3.UP * 0.288, 0.03)
	for z in [-1.73, 1.73]:
		for x in [-2.62, 0.74]:
			kit.box_bevel("orion_frame", Vector3(0.34, 4.0, 0.36), Vector3(x, 2.52, z), 0.06)
		kit.box_bevel("bare_steel", Vector3(3.72, 0.24, 0.38), Vector3(-0.86, 4.45, z), 0.052)
		kit.box("cyan", Vector3(3.15, 0.055, 0.045), Vector3(-0.86, 4.48, z * 0.885))
	var screen := Vector3(face - 1.22, 1.85, -1.92)
	var pedestal := screen - Vector3.UP * 1.10
	kit.box_bevel("orion_frame", Vector3(0.42, 1.50, 0.86), pedestal, 0.085)
	_solid(pedestal, Vector3(0.42, 1.50, 0.86))
	kit.box_bevel("orion_frame", Vector3(0.26, 0.70, 1.68), screen, 0.075)
	kit.box_bevel("metal_dark", Vector3(0.055, 0.57, 1.55), screen + Vector3.RIGHT * 0.131, 0.038)
	_label("FAB-02", screen + Vector3(0.168, 0.12, 0), 0.006)
	_readout = _label("待机", screen + Vector3(0.169, -0.116, 0), 0.0047)
	_readout.modulate = Color("b4dadb")
	kit.box_bevel("metal_dark", Vector3(0.18, 0.18, 2.85), Vector3(face - 1.25, 0.94, 0.12), 0.028)
	for z in [-1.20, 1.44]:
		kit.box_bevel("track", Vector3(0.21, 1.05, 0.20), Vector3(face - 1.25, 0.53, z), 0.04)
	_solid(Vector3(face - 1.25, 0.53, 0), Vector3(0.22, 1.06, 3.72))
	_gantry = Node3D.new()
	_gantry.name = "MovingPrintBridge"
	add_child(_gantry)
	var gantry_kit := Kit.new()
	for key in ["metal_dark", "orion_frame", "bare_steel", "cyan"]:
		gantry_kit.material(key, kit.mats[key])
	gantry_kit.box_bevel("metal_dark", Vector3(0.62, 0.42, 4.02), Vector3.ZERO, 0.053)
	gantry_kit.box("bare_steel", Vector3(0.18, 0.115, 3.54), Vector3(0, -0.23, 0))
	for z in [-1.67, 1.67]:
		gantry_kit.box_bevel("orion_frame", Vector3(0.74, 0.47, 0.55), Vector3(0, 0.04, z), 0.045)
	gantry_kit.commit(_gantry, "Bridge")
	_ram = Node3D.new()
	_gantry.add_child(_ram)
	var ram_kit := Kit.new()
	ram_kit.material("bare_steel", kit.mats["bare_steel"])
	for z in [-0.17, 0.17]:
		ram_kit.tube("bare_steel", [Vector3(0, 0, z), Vector3(0, -1, z)], 0.074, 8)
	ram_kit.commit(_ram, "RamGuide")
	_print_head = Node3D.new()
	_print_head.name = "DepositionHead"
	add_child(_print_head)
	var head_kit := Kit.new()
	for key in ["metal_dark", "orion_frame", "bare_steel", "cyan"]:
		head_kit.material(key, kit.mats[key])
	head_kit.box_bevel("orion_frame", Vector3(0.63, 0.37, 0.69), Vector3.ZERO, 0.067)
	head_kit.lathe("bare_steel", [Vector2(0.13, -0.51), Vector2(0.23, -0.31),
		Vector2(0.25, -0.22), Vector2(0.25, -0.11)], 18)
	head_kit.box("cyan", Vector3(0.037, 0.078, 0.40), Vector3(0.33, 0.037, 0))
	head_kit.commit(_print_head, "DepositionTool")
	_print_lamp = _light(Vector3.DOWN * 0.55, Color("ffb083"), 0.0, _print_head)
	_place_print_head(Vector3(-0.66, 3.66, 0.88))


func _place_print_head(at: Vector3) -> void:
	_print_head.position = at
	_gantry.position = Vector3(at.x, 4.36, 0)
	_ram.position = Vector3(0.0, -0.16, at.z)
	_ram.scale.y = maxf(0.05, 4.20 - at.y - 0.11)


func _prepare_shell() -> void:
	_shell = Rig.new()
	_shell.name = "UnpoweredReplacementShell"
	_shell.position = Vector3(-0.82, 0.59, 0)
	_shell.rotation.y = -PI * 0.5
	_shell.scale = Vector3.ONE * 1.43
	_shell.auto_step = false
	add_child(_shell)
	_shell.advance(1.0 / 60.0)
	_shell.weapon_root.hide()
	_shell.weapon_light.hide()
	_shell.hair.hide()
	_shell.chest_light.light_energy = 0
	_shell.lens_light.light_energy = 0
	_shell.thruster_light.light_energy = 0
	for arm in _shell.arms:
		var shoulder: Vector3 = arm["shoulder"].position
		var side: float = arm["side"]
		_shell._solve_arm(arm, shoulder + Vector3(side * 0.17, -0.70, -0.05), Vector3.UP, Vector3.RIGHT)
	_print_fx = FabricatorFx.new()
	add_child(_print_fx)
	_print_fx.begin(_shell)
	var cuirass := _shell.torso.get_node("TorsoCuirassWhite") as MeshInstance3D
	_deposited_armor.append(cuirass)
	for bridge_name in ["ShoulderBridgeR", "ShoulderBridgeL"]:
		var armor := _shell.torso.get_node(bridge_name).get_child(1) as MeshInstance3D
		_deposited_armor.append(armor)
	_update_deposited_armor()


func _update_deposited_armor() -> void:
	for i in _deposited_armor.size():
		var armor := _deposited_armor[i]
		var pass_age := _fabrication_elapsed - float(i) * 6.0
		var metal := smoothstep(2.65, 4.2, pass_age)
		armor.visible = metal > 0.01
		armor.transparency = 1.0 - metal


func _print(dt: float) -> void:
	var t := _fabrication_elapsed
	_update_deposited_armor()
	if t >= FABRICATION_TIME:
		_readout.text = "成形完成"
		_print_lamp.light_energy = 0.0
		_print_fx.finish_print()
		return
	_readout.text = "外壳成形 %d%%" % int(72.0 + 27.0 * t / FABRICATION_TIME)
	var pass_t := fposmod(t + 0.46, 4.2) / 4.2
	var scan := 0.5 - 0.5 * cos(pass_t * TAU)
	var contact: Vector3 = _print_fx.sample_seam(mini(2, int(t / 6.0)), scan)
	if not contact.is_finite():
		contact = global_position + Vector3(-0.59, 2.37, lerpf(-0.50, 0.51, scan))
	var nozzle := to_local(contact) + Vector3(-0.10, 0.22, 0.0)
	_place_print_head(nozzle + Vector3.UP * 0.50)
	var power := 0.23 + smoothstep(0.08, 0.18, scan) * (1.0 - smoothstep(0.88, 0.99, scan)) * 0.64
	_print_lamp.light_energy = 0.48 + power * 1.32
	_print_fx.machine(dt, to_global(nozzle), contact, power)


func _solid(center: Vector3, size: Vector3) -> void:
	fixed_boxes.append(AABB(center - size * 0.5, size))


func _label(message: String, at: Vector3, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = message
	label.font_size = 39
	label.outline_size = 2
	label.pixel_size = pixel
	label.position = at
	label.rotation.y = PI * 0.5
	add_child(label)
	return label


func _light(at: Vector3, tint: Color, energy: float, parent: Node3D = self) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = 6.2 if parent == self else 2.1
	parent.add_child(light)
	return light

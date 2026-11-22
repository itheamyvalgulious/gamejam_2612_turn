extends Node3D
## 人形刀客的机体几何。肩、肘、腕、髋、膝、踝保留独立节点，供后续动作使用。

const MeshKit = preload("res://src/vesper/mesh_kit.gd")
const Blade = preload("res://src/enemies/duelist/duelist_blade.gd")
const Shell = preload("res://src/enemies/duelist/duelist_shell.gd")
const Parts = preload("res://src/enemies/duelist/duelist_parts.gd")
const Fuselage = preload("res://src/enemies/duelist/duelist_fuselage.gd")
const Casing = preload("res://src/enemies/duelist/duelist_casing.gd")
const Armor = preload("res://src/enemies/duelist/duelist_armor.gd")
const Rig = preload("res://src/enemies/duelist/duelist_rig.gd")
const Hand = preload("res://src/enemies/duelist/duelist_hand.gd")
const Hardware = preload("res://src/enemies/duelist/duelist_hardware.gd")
const Charge = preload("res://src/enemies/duelist/duelist_charge.gd")
const COMPOSITE = preload("res://gfx/duelist_composite.gdshader")
const CHARGE_INLAY = preload("res://gfx/duelist_charge_inlay.gdshader")
const DisplayPose = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const BLADE_START := 0.22
const BLADE_LENGTH := 2.42
const SWEEP_EXTENSION := 0.85
const SWEEP_END := BLADE_START + BLADE_LENGTH + SWEEP_EXTENSION
const BLADE_WIDTH := 0.210
const HIP_HEIGHT := 2.51
const THIGH := 1.19
const SHIN := 1.25
const UPPER_ARM := 0.89
const FOREARM := 0.87
const CORE_TINT := Color("6dffe5")
const OPTIC_TINT := Color("8cffe1")
const SIGNAL_TINT := Color("ff2417")
const STATUS_TINT := Color("4ce1c2")
const ARM_TINT := Color("54ebd0")
const SHOULDER_TINT := Color("64f9d6")
const EXHAUST_TINT := Color("6ae7d5")

var body: Node3D
var torso: Node3D
var head: Node3D
var weapon_root: Node3D
var weapon_spin: Node3D
var sword_grip_cant := 0.0
var kerb := Vector2(INF, 0.0)
var legs: Array[Dictionary] = []
var arms: Array[Dictionary] = []
var blade_discs: Array = []
var _lamp: Node3D
var _warning_spill: OmniLight3D
var _core_spill: OmniLight3D
var _visor_spill: OmniLight3D
var _blade_spill: OmniLight3D
var _blade_mount: Node3D
var _thrusters: Array[Node3D] = []
var _skeleton := Rig.new()
var _lumbar: Array[Node3D] = []
var _neck: Array[Node3D] = []
var _armor := StandardMaterial3D.new()
var _dark := StandardMaterial3D.new()
var _alloy := StandardMaterial3D.new()
var _trim := StandardMaterial3D.new()
var _signal := StandardMaterial3D.new()
var _blade := StandardMaterial3D.new()
var _blade_inlay := ShaderMaterial.new()
var _warm := StandardMaterial3D.new()
var _edge := StandardMaterial3D.new()
var _titanium := StandardMaterial3D.new()
var _ceramic := ShaderMaterial.new()
var _hood := ShaderMaterial.new()
var _sensor := StandardMaterial3D.new()
var _optic := StandardMaterial3D.new()
var _temple := StandardMaterial3D.new()
var _status := StandardMaterial3D.new()
var _core := StandardMaterial3D.new()
var _arm_power := StandardMaterial3D.new()
var _shoulder_power := StandardMaterial3D.new()
var _exhaust_glow := StandardMaterial3D.new()


func _ready() -> void:
	_metal(_armor, Color("414b50"), 0.60, 0.43)
	_metal(_dark, Color("23272e"), 0.49, 0.52)
	_metal(_alloy, Color("afa997"), 0.62, 0.34)
	_metal(_blade, Color("83949e"), 0.84, 0.26)
	_metal(_trim, Color("678782"), 0.60, 0.38)
	_metal(_edge, Color("b4b8b6"), 0.79, 0.28)
	_metal(_titanium, Color("5e6669"), 0.70, 0.44)
	_metal(_warm, Color("936a47"), 0.65, 0.38)
	_metal(_sensor, Color("1d3438"), 0.58, 0.28)
	_ceramic.shader = COMPOSITE
	_ceramic.set_shader_parameter("coating", Color("9da39f"))
	_ceramic.set_shader_parameter("metalness", 0.48)
	_ceramic.set_shader_parameter("finish_roughness", 0.42)
	_hood.shader = COMPOSITE
	_hood.set_shader_parameter("coating", Color("606f72"))
	_hood.set_shader_parameter("finish_roughness", 0.43)
	_alloy.clearcoat_enabled = true
	_alloy.clearcoat = 0.16
	_alloy.clearcoat_roughness = 0.47
	_emissive(_signal, Color(1.0, 0.035, 0.02), 4.4)
	_emissive(_optic, OPTIC_TINT, 3.8)
	_emissive(_temple, OPTIC_TINT, 2.0)
	_emissive(_status, STATUS_TINT, 2.15)
	_emissive(_core, CORE_TINT, 3.75)
	_emissive(_arm_power, ARM_TINT, 2.3)
	_emissive(_shoulder_power, SHOULDER_TINT, 2.15)
	_emissive(_exhaust_glow, EXHAUST_TINT, 2.9)
	_blade_inlay.shader = CHARGE_INLAY
	_blade_inlay.set_shader_parameter("blade_length", BLADE_LENGTH)
	_build_core()
	for side in [-1.0, 1.0]:
		_build_leg(side)
		_build_arm(side)
	var surfaces := _casing_materials()
	for leg in legs:
		Hardware.build_leg(leg, surfaces)
	for arm in arms:
		Hardware.build_arm(arm, surfaces)
	_build_sword()
	_rig_geometry()
	set_effects(0.0, 0.0)
	set_charge_state(-1.0)
	DisplayPose.apply(self)
	_skeleton.sync(true)


func _metal(material: StandardMaterial3D, color: Color, metal: float, rough: float) -> void:
	material.albedo_color = color
	material.metallic = metal
	material.roughness = rough


func _emissive(material: StandardMaterial3D, color: Color, energy: float) -> void:
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy


func _light(parent: Node3D, label: String, at: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var glow := OmniLight3D.new()
	glow.name = label
	glow.position = at
	glow.light_color = color
	glow.light_energy = energy
	glow.light_specular = 0.20
	glow.omni_range = reach
	glow.omni_attenuation = 1.85
	parent.add_child(glow)
	return glow


func _plate(parent: Node3D, size: Vector3, at: Vector3, material: Material, rotation_deg := Vector3.ZERO) -> MeshInstance3D:
	return MeshKit.add(parent, MeshKit.slab(size.x, size.z, size.y, 0.045), material, at, rotation_deg)


func _shell(parent: Node3D, sections: Array, at: Vector3, material: Material, rotation_deg := Vector3.ZERO) -> MeshInstance3D:
	return MeshKit.add(parent, Shell.loft(sections), material, at, rotation_deg)


func _joint(parent: Node3D, radius: float, breadth: float) -> void:
	_shell(parent, [
		[-breadth * 0.42, radius * 0.75, radius * 0.75, 0, 0],
		[-breadth * 0.28, radius * 0.94, radius * 0.94, 0, 0],
		[-breadth * 0.10, radius, radius, 0, 0],
		[breadth * 0.10, radius, radius, 0, 0],
		[breadth * 0.28, radius * 0.94, radius * 0.94, 0, 0],
		[breadth * 0.42, radius * 0.75, radius * 0.75, 0, 0],
	], Vector3.ZERO, _dark, Vector3(0, 0, -90))
	for side: float in [-1.0, 1.0]:
		var axial := side * breadth * 0.36
		Parts.axle(parent, Vector3(axial, 0, 0), radius * 0.86, breadth * 0.16, _titanium)
		Parts.axle(parent, Vector3(axial + side * breadth * 0.095, 0, 0), radius * 0.62, breadth * 0.083, _armor)
		Parts.axle(parent, Vector3(axial + side * breadth * 0.143, 0, 0), radius * 0.27, breadth * 0.071, _alloy)
		for i in range(4):
			var angle := PI * (float(i) * 0.5 + 0.25)
			var point := Vector3(axial + side * breadth * 0.087, sin(angle) * radius * 0.72, cos(angle) * radius * 0.72)
			_fastener(parent, point, radius * 0.092, side * Vector3.RIGHT)


func _vents(parent: Node3D, at: Vector3, count: int, width: float, depth: float, spacing: float,
		rotation := Vector3.ZERO) -> void:
	var housing := MeshKit.pivot(parent, at)
	housing.set_meta(&"joint_detail", true)
	housing.rotation_degrees = rotation
	_plate(housing, Vector3(width + 0.032, count * spacing + 0.018, depth), Vector3.ZERO, _dark)
	for i in count:
		var height := (float(i) - float(count - 1) * 0.5) * spacing
		_plate(housing, Vector3(width, spacing * 0.39, depth * 0.68), Vector3(0, height, -depth * 0.57),
			_titanium, Vector3(21, 0, 0))


func _fastener(parent: Node3D, at: Vector3, radius: float, axis := Vector3.FORWARD) -> void:
	Parts.axle(parent, at, radius, radius * 0.72, _titanium, axis)
	Parts.axle(parent, at + axis * radius * 0.37, radius * 0.47, radius * 0.16, _dark, axis)


func _piston(parent: Node3D, mount: Vector3, end: Vector3, radius: float) -> void:
	var span := end - mount
	var direction := span.normalized()
	var travel := span.length()
	Parts.axle(parent, mount + span * 0.50, radius * 0.43, travel, _edge, direction)
	Parts.axle(parent, mount + span * 0.26, radius, travel * 0.54, _titanium, direction)
	Parts.axle(parent, mount + span * 0.55, radius * 1.15, radius * 0.65, _dark, direction)
	Parts.axle(parent, mount, radius * 1.28, radius * 0.88, _armor, direction)
	Parts.axle(parent, end, radius * 0.82, radius * 0.72, _armor, direction)


func _casing_materials() -> Dictionary:
	return {"frame": _dark, "steel": _titanium, "coat": _armor,
		"ceramic": _ceramic, "hood": _hood, "sensor": _sensor, "optic": _optic, "status": _status,
		"warm": _warm, "core": _core, "arm_power": _arm_power,
		"shoulder_power": _shoulder_power, "temple": _temple}


func _build_core() -> void:
	body = MeshKit.pivot(self, Vector3(0, HIP_HEIGHT, 0), "Pelvis")
	_shell(body, [
		[-0.174, 0.175, 0.130, 0, 0.028], [-0.122, 0.294, 0.173, 0, 0.028],
		[-0.054, 0.353, 0.190, 0, 0.027], [0.029, 0.371, 0.202, 0, 0.028],
		[0.092, 0.308, 0.177, 0, 0.022], [0.160, 0.221, 0.137, 0, 0.024],
	], Vector3.ZERO, _dark)
	Fuselage.pelvis(body, _casing_materials())
	torso = MeshKit.pivot(body, Vector3(0, 0.25, 0.0), "Chest")
	_shell(torso, [
		[-0.152, 0.188, 0.121, 0, 0.019], [-0.075, 0.210, 0.139, 0, 0.023],
		[0.061, 0.205, 0.142, 0, 0.026], [0.192, 0.216, 0.151, 0, 0.032],
		[0.31, 0.256, 0.162, 0, 0.037], [0.435, 0.314, 0.191, 0, 0.042],
		[0.557, 0.390, 0.212, 0, 0.046], [0.711, 0.441, 0.222, 0, 0.050],
		[0.856, 0.448, 0.194, 0, 0.061], [0.969, 0.350, 0.152, 0, 0.053],
		[1.095, 0.132, 0.126, 0, 0.009],
	], Vector3.ZERO, _dark)
	Fuselage.thorax(torso, _casing_materials())
	Hardware.build_chest(torso, _casing_materials())
	_core_spill = _light(torso, "ReactorSpill", Vector3(0, 0.73, -0.62), Color("68efdb"), 0.65, 2.05)
	for i in 4:
		var y := -0.035 + 0.086 * i
		var size := 0.208 + 0.015 * i
		var ring := MeshKit.pivot(torso, Vector3(0, y, 0), "Lumbar%d" % (i + 1))
		_lumbar.append(ring)
		for side: float in [-1.0, 1.0]:
			Armor.fit(ring, [
				[-0.036, size - 0.01, 0.155 + 0.008 * i, 0, -0.014, 7, 86, 0.043],
				[0.002, size + 0.029, 0.172 + 0.009 * i, 0, -0.010, 5, 121, 0.053],
				[0.039, size + 0.018, 0.163 + 0.009 * i, 0, -0.007, 8, 131, 0.037],
			], _armor if i < 2 else _titanium, _dark, _dark, 0.016, side)
			Armor.fit(ring, [
				[-0.043, size - 0.003, 0.150 + 0.006 * i, 0, 0.016, 136, 174, -0.015],
				[0.009, size + 0.019, 0.157 + 0.010 * i, 0, 0.020, 135, 175, -0.026],
				[0.041, size + 0.001, 0.153 + 0.009 * i, 0, 0.012, 145, 174, -0.018],
			], _titanium, _dark, _dark, 0.012, side)
	for side: float in [-1.0, 1.0]:
		_piston(torso, Vector3(side * 0.204, -0.103, 0.125), Vector3(side * 0.277, 0.312, 0.132), 0.026)
		_piston(torso, Vector3(side * 0.157, -0.083, 0.159), Vector3(side * 0.215, 0.271, 0.186), 0.019)
	_lamp = MeshKit.pivot(torso, Vector3(0, 0.971, -0.243), "DashWarning")
	_plate(torso, Vector3(0.094, 0.054, 0.035), Vector3(0, 0.971, -0.221), _sensor)
	_plate(_lamp, Vector3(0.049, 0.044, 0.014), Vector3.ZERO, _signal)
	_warning_spill = _light(_lamp, "WarningSpill", Vector3(0, 0.005, -0.112), Color("ff3e29"), 0.0, 2.35)
	_shell(torso, [
		[1.019, 0.111, 0.115, 0, 0.003], [1.112, 0.092, 0.094, 0, -0.017],
		[1.217, 0.081, 0.081, 0, -0.037],
	], Vector3.ZERO, _dark)
	for i in 3:
		var y := 1.052 + i * 0.052
		var segment := MeshKit.pivot(torso, Vector3(0, y, -0.015 - i * 0.007), "Neck%d" % (i + 1))
		_neck.append(segment)
		Armor.fit(segment, [
			[-0.020, 0.098 - i * 0.007, 0.103, 0, 0.005, 66, 294, 0.0],
			[0.004, 0.106 - i * 0.006, 0.113, 0, 0.005, 60, 300, 0.0],
			[0.030, 0.091 - i * 0.006, 0.101, 0, 0.003, 74, 286, 0.0],
		], _titanium, _dark, _dark, 0.017)
	head = MeshKit.pivot(torso, Vector3(0, 1.18, -0.04), "Helmet")
	Fuselage.helmet(head, _casing_materials())
	Hardware.build_helmet(head, _casing_materials())
	_visor_spill = _light(head, "OpticBounce", Vector3(0, 0.30, -0.38), OPTIC_TINT, 0.22, 1.65)


func _build_leg(side: float) -> void:
	var hip := MeshKit.pivot(self, Vector3.ZERO, "Hip")
	var knee := MeshKit.pivot(self, Vector3.ZERO, "Knee")
	var ankle := MeshKit.pivot(self, Vector3.ZERO, "Foot")
	_joint(hip, 0.131, 0.254)
	_shell(hip, [
		[-1.156, 0.081, 0.088, 0, 0.0], [-1.020, 0.112, 0.121, 0, 0.015],
		[-0.824, 0.150, 0.146, 0, 0.017], [-0.607, 0.176, 0.162, 0, 0.014],
		[-0.365, 0.187, 0.169, 0, 0.022], [-0.179, 0.151, 0.135, 0, 0.026],
		[-0.081, 0.119, 0.115, 0, 0.0],
	], Vector3.ZERO, _dark)
	Armor.fit_split(hip, [
		[-1.055, 0.124, 0.128, -0.014, -0.005, -39, 45, 0.061],
		[-0.913, 0.164, 0.177, -0.009, -0.012, -44, 70, 0.082],
		[-0.683, 0.206, 0.206, -0.003, -0.012, -49, 83, 0.109],
		[-0.459, 0.221, 0.212, 0.006, -0.013, -44, 85, 0.139],
		[-0.292, 0.214, 0.193, 0.009, -0.011, -29, 81, 0.166],
		[-0.195, 0.146, 0.136, 0.014, -0.014, 3, 57, 0.114],
	], _armor, _titanium, _titanium, _dark, 0.029, side)
	Armor.fit(hip, [
		[-1.008, 0.111, 0.128, -0.014, 0.004, -61, -46, -0.027],
		[-0.855, 0.169, 0.178, -0.008, 0.002, -101, -51, -0.069],
		[-0.642, 0.189, 0.197, -0.013, 0.001, -116, -54, -0.092],
		[-0.416, 0.199, 0.192, -0.005, 0.008, -122, -52, -0.076],
		[-0.248, 0.172, 0.157, -0.002, 0.008, -105, -60, -0.059],
	], _armor, _titanium, _dark, 0.023, side)
	Armor.fit(hip, [
		[-0.544, 0.201, 0.180, 0.002, 0.006, 88, 119, 0.088],
		[-0.434, 0.219, 0.193, 0.008, 0.013, 91, 147, 0.065],
		[-0.319, 0.214, 0.190, 0.010, 0.015, 98, 165, 0.051],
		[-0.198, 0.173, 0.146, 0.011, 0.013, 79, 154, 0.038],
		[-0.130, 0.135, 0.130, 0.008, 0.015, 87, 117, 0.025],
	], _titanium, _armor, _dark, 0.022, side)
	Armor.fit(hip, [
		[-0.889, 0.150, 0.151, 0, 0.017, 99, 132, 0.073],
		[-0.721, 0.201, 0.181, 0.004, 0.020, 92, 151, 0.072],
		[-0.465, 0.213, 0.192, 0.009, 0.022, 98, 166, 0.046],
		[-0.299, 0.161, 0.164, 0.008, 0.027, 115, 167, 0.044],
	], _titanium, _dark, _dark, 0.023, side)
	_piston(hip, Vector3(side * 0.108, -0.259, 0.144), Vector3(side * 0.086, -1.030, 0.100), 0.040)
	_piston(hip, Vector3(side * -0.075, -0.344, 0.140), Vector3(side * -0.065, -1.049, 0.076), 0.029)

	_joint(knee, 0.137, 0.231)
	_shell(knee, [
		[-1.200, 0.058, 0.062, 0, 0.0], [-1.090, 0.079, 0.080, 0, 0.030],
		[-0.851, 0.097, 0.108, 0, 0.055], [-0.628, 0.129, 0.133, 0, 0.082],
		[-0.406, 0.144, 0.141, 0, 0.076], [-0.211, 0.114, 0.110, 0, 0.032],
		[-0.074, 0.094, 0.095, 0, 0.014],
	], Vector3.ZERO, _dark)
	Armor.fit_split(knee, [
		[-1.122, 0.080, 0.082, -0.008, -0.016, -29, 36, 0.030],
		[-0.983, 0.098, 0.115, -0.006, -0.010, -42, 49, 0.062],
		[-0.775, 0.116, 0.137, 0.002, -0.004, -48, 61, 0.086],
		[-0.521, 0.138, 0.161, 0.005, -0.002, -49, 70, 0.100],
		[-0.291, 0.155, 0.175, 0.003, -0.011, -46, 73, 0.092],
		[-0.157, 0.121, 0.165, 0.001, -0.014, -44, 66, 0.025],
	], _ceramic, _armor, _titanium, _dark, 0.026, side)
	var patella := MeshKit.pivot(knee, Vector3.ZERO, "Patella")
	Armor.fit(patella, [
		[-0.187, 0.103, 0.143, 0, -0.010, -39, 45, 0.029],
		[-0.110, 0.123, 0.149, 0, -0.026, -57, 62, 0.055],
		[-0.019, 0.136, 0.152, 0, -0.026, -62, 68, 0.041],
		[0.046, 0.102, 0.125, 0, -0.015, -48, 55, 0.021],
	], _titanium, _dark, _dark, 0.021, side)
	Armor.fit(knee, [
		[-0.937, 0.101, 0.119, 0.004, 0.057, 108, 149, 0.109],
		[-0.725, 0.149, 0.145, 0.007, 0.087, 98, 163, 0.099],
		[-0.518, 0.179, 0.153, 0.007, 0.083, 91, 169, 0.083],
		[-0.307, 0.166, 0.138, 0.004, 0.072, 98, 158, 0.096],
		[-0.196, 0.116, 0.105, 0.003, 0.052, 111, 148, 0.069],
	], _armor, _titanium, _dark, 0.027, side)
	Armor.fit(knee, [
		[-0.934, 0.096, 0.102, 0, 0.046, -123, -79, -0.039],
		[-0.718, 0.149, 0.137, -0.003, 0.076, -161, -71, -0.060],
		[-0.481, 0.163, 0.145, -0.004, 0.080, -169, -66, -0.066],
		[-0.302, 0.142, 0.129, -0.005, 0.065, -153, -82, -0.053],
	], _titanium, _armor, _dark, 0.021, side)
	_piston(knee, Vector3(side * 0.052, -0.273, 0.192), Vector3(side * 0.059, -1.077, 0.100), 0.036)
	_vents(knee, Vector3(side * 0.056, -0.52, 0.231), 4, 0.065, 0.019, 0.043, Vector3(0, side * 162, 0))
	_plate(knee, Vector3(0.065, 0.113, 0.027), Vector3(0, -0.666, 0.236), _trim)
	_plate(knee, Vector3(0.029, 0.014, 0.010), Vector3(0, -0.699, 0.252), _status)
	var exhaust := MeshKit.pivot(knee, Vector3(0, -0.58, 0.242), "Booster")
	_plate(exhaust, Vector3(0.043, 0.066, 0.018), Vector3(0, -0.070, 0.011), _exhaust_glow)
	_light(exhaust, "ExhaustSpill", Vector3(0, -0.11, 0.18), Color("6ae7d5"), 1.25, 1.60)
	_thrusters.append(exhaust)

	_joint(ankle, 0.074, 0.122)
	_shell(ankle, [
		[-0.173, 0.103, 0.168, 0, -0.037], [-0.146, 0.108, 0.176, 0, -0.035],
		[-0.114, 0.105, 0.175, 0, -0.034], [-0.075, 0.101, 0.168, 0, -0.041],
		[-0.021, 0.080, 0.150, 0, -0.060], [0.034, 0.066, 0.096, 0, -0.012],
	], Vector3.ZERO, _dark)
	var toe := MeshKit.pivot(ankle, Rig.TOE_HINGE, "Forefoot")
	_shell(toe, [
		[-0.071, 0.088, 0.113, 0, -0.072], [-0.053, 0.098, 0.113, 0, -0.071],
		[-0.023, 0.098, 0.104, 0, -0.069], [0.017, 0.084, 0.073, 0, -0.045],
	], Vector3.ZERO, _dark)
	Casing.panel(toe, PackedVector3Array([
		Vector3(-0.083, -0.014, -0.119), Vector3(-0.076, 0.019, -0.042),
		Vector3(-0.036, 0.029, -0.008), Vector3(0.056, 0.027, -0.014),
		Vector3(0.086, 0.001, -0.076), Vector3(0.079, -0.019, -0.120),
		Vector3(0.031, -0.031, -0.174), Vector3(-0.041, -0.031, -0.169),
	]), Vector3(0, 0.93, -0.37), 0.026, _armor, _titanium)
	for z: float in [-0.101, 0.038, 0.097]:
		_plate(ankle, Vector3(0.163, 0.019, 0.059), Vector3(0, -0.164, z), _dark)
	legs.append({"hip": hip, "knee": knee, "ankle": ankle, "toe": toe, "patella": patella, "side": side})


func _build_arm(side: float) -> void:
	var shoulder := MeshKit.pivot(self, Vector3.ZERO, "Shoulder")
	var elbow := MeshKit.pivot(self, Vector3.ZERO, "Elbow")
	var wrist := MeshKit.pivot(self, Vector3.ZERO, "Hand")
	var clavicle := MeshKit.pivot(torso, Vector3(side * 0.36, 0.86, 0.02), "Clavicle")
	var scapula := MeshKit.pivot(torso, Vector3(side * 0.30, 0.74, 0.194), "Scapula")
	var cap := MeshKit.pivot(shoulder, Vector3.ZERO, "ShoulderCap")
	var twist := MeshKit.pivot(elbow, Vector3.ZERO, "ForearmTwist")
	Armor.fit(scapula, [
		[-0.259, 0.058, 0.070, -0.148, 0.017, 135, 172, -0.055],
		[-0.139, 0.132, 0.108, -0.124, 0.018, 115, 192, -0.067],
		[-0.035, 0.179, 0.140, -0.111, 0.015, 107, 207, -0.061],
		[0.080, 0.182, 0.140, -0.116, 0.008, 102, 205, -0.053],
		[0.160, 0.159, 0.107, -0.118, 0.001, 112, 194, -0.038],
		[0.208, 0.087, 0.051, -0.104, 0.010, 126, 170, -0.025],
	], _ceramic, _armor, _dark, 0.029, side)
	Casing.panel(scapula, PackedVector3Array([
		Vector3(side * -0.150, -0.119, 0.129), Vector3(side * -0.133, 0.044, 0.149),
		Vector3(side * -0.061, 0.146, 0.126), Vector3(side * 0.001, 0.118, 0.121),
		Vector3(side * -0.028, 0.012, 0.151), Vector3(side * -0.114, -0.160, 0.127),
	]), Vector3(side * -0.18, 0, 1), 0.018, _armor, _titanium)
	_piston(clavicle, Vector3(side * -0.14, -0.026, 0.038), Vector3(side * 0.13, 0.012, 0.028), 0.029)
	_joint(shoulder, 0.119, 0.224)
	_shell(shoulder, [
		[-0.853, 0.055, 0.055, 0, 0.005], [-0.726, 0.080, 0.081, 0, 0.013],
		[-0.494, 0.110, 0.107, 0, 0.021], [-0.270, 0.123, 0.117, 0, 0.022],
		[-0.116, 0.106, 0.104, 0, 0.009], [0.062, 0.081, 0.081, 0, 0],
	], Vector3.ZERO, _dark)
	var cap_shift := 0.020 if side < 0.0 else 0.0
	Armor.fit(cap, [
		[-0.505, 0.102, 0.102, cap_shift, -0.006, 26, 83, 0.101],
		[-0.342, 0.148, 0.151, cap_shift, 0, -12, 121, 0.143],
		[-0.206, 0.168, 0.174, cap_shift, 0.007, -24, 147, 0.111],
		[-0.082, 0.153, 0.152, cap_shift, 0.010, -16, 147, 0.067],
		[0.017, 0.113, 0.115, cap_shift, 0.009, 1, 124, 0.053],
		[0.084, 0.057, 0.064, cap_shift, 0.006, 32, 95, 0.023],
	], _ceramic, _armor, _dark, 0.027, side)
	if side < 0.0:
		Armor.fit(cap, [
			[-0.380, 0.124, 0.140, 0.035, 0.004, 90, 129, 0.083],
			[-0.262, 0.154, 0.161, 0.030, 0.009, 62, 142, 0.106],
			[-0.154, 0.167, 0.170, 0.027, 0.012, 47, 130, 0.060],
			[-0.092, 0.143, 0.154, 0.028, 0.008, 68, 119, 0.042],
		], _alloy, _titanium, _dark, 0.021, side)
		_fastener(cap, Vector3(-0.179, -0.194, 0.010), 0.018, Vector3.LEFT)
	Armor.fit(shoulder, [
		[-0.738, 0.081, 0.070, 0, 0.004, 4, 42, 0.028],
		[-0.598, 0.120, 0.111, 0.003, 0.003, -27, 68, 0.083],
		[-0.439, 0.130, 0.124, 0.005, 0.001, -29, 62, 0.064],
		[-0.358, 0.111, 0.094, 0.005, 0.002, -12, 31, 0.051],
	], _armor, _titanium, _dark, 0.018, side)
	Armor.fit(shoulder, [
		[-0.746, 0.080, 0.092, 0, 0.019, 133, 178, 0.024],
		[-0.585, 0.111, 0.122, 0.003, 0.021, 103, 198, 0.061],
		[-0.436, 0.122, 0.133, 0.005, 0.030, 108, 206, 0.051],
		[-0.289, 0.114, 0.123, 0.002, 0.032, 128, 192, 0.055],
	], _titanium, _armor, _dark, 0.021, side)
	Parts.tube(shoulder, PackedVector3Array([
		Vector3(side * 0.058, -0.752, 0.056), Vector3(side * 0.061, -0.528, 0.081),
		Vector3(side * 0.074, -0.390, 0.108), Vector3(side * 0.082, -0.301, 0.108),
	]), 0.017, _titanium)

	_joint(elbow, 0.090, 0.175)
	_shell(elbow, [
		[-0.824, 0.047, 0.052, 0, 0.002], [-0.748, 0.058, 0.064, 0, 0.004],
		[-0.624, 0.082, 0.083, 0, 0.007], [-0.429, 0.100, 0.098, 0, 0.018],
		[-0.245, 0.105, 0.104, 0, 0.022], [-0.104, 0.077, 0.079, 0, 0.006],
	], Vector3.ZERO, _dark)
	Armor.fit_split(twist, [
		[-0.742, 0.066, 0.073, 0, -0.002, -22, 65, 0.055],
		[-0.609, 0.088, 0.103, 0.003, -0.007, -37, 83, 0.093],
		[-0.482, 0.118, 0.130, 0.003, -0.013, -38, 93, 0.113],
		[-0.335, 0.136, 0.136, 0.009, -0.010, -31, 97, 0.122],
		[-0.232, 0.115, 0.108, 0.009, -0.005, -10, 86, 0.089],
		[-0.157, 0.089, 0.090, 0.005, 0.0, 29, 69, 0.072],
	], _ceramic, _armor, _titanium, _dark, 0.025, side)
	Armor.fit(twist, [
		[-0.696, 0.078, 0.073, 0.001, 0.016, 110, 147, 0.056],
		[-0.570, 0.092, 0.100, 0.004, 0.026, 107, 158, 0.071],
		[-0.396, 0.106, 0.113, 0.005, 0.029, 112, 165, 0.063],
		[-0.275, 0.102, 0.100, 0.005, 0.022, 123, 166, 0.044],
	], _armor, _titanium, _dark, 0.022, side)
	_piston(elbow, Vector3(side * -0.058, -0.199, 0.095), Vector3(side * -0.039, -0.721, 0.052), 0.026)
	_fastener(twist, Vector3(side * 0.108, -0.419, -0.065), 0.017, Vector3(side * 0.80, 0.0, -0.60))
	_shell(twist, [
		[-0.834, 0.049, 0.048, 0, 0], [-0.808, 0.062, 0.057, 0, 0],
		[-0.775, 0.062, 0.057, 0, 0], [-0.759, 0.053, 0.052, 0, 0],
	], Vector3.ZERO, _titanium)
	_joint(wrist, 0.046, 0.071)
	var fingers := Hand.build(wrist, side > 0.0, _casing_materials())
	arms.append({"shoulder": shoulder, "elbow": elbow, "wrist": wrist, "side": side,
		"clavicle": clavicle, "scapula": scapula, "cap": cap, "twist": twist, "fingers": fingers})


func _build_sword() -> void:
	weapon_root = MeshKit.pivot(self, Vector3.ZERO, "SwordGrip")
	weapon_spin = MeshKit.pivot(weapon_root, Vector3.ZERO, "SwordBlade")
	_mesh_blade()
	_plate(weapon_spin, Vector3(0.290, 0.053, 0.145), Vector3(0.036, 0.151, 0), _titanium, Vector3(0, 0, -19))
	_plate(weapon_spin, Vector3(0.208, 0.079, 0.137), Vector3(0.040, 0.207, 0), _armor, Vector3(0, 0, -14))
	for side: float in [-1.0, 1.0]:
		var z := side * 0.061
		var toward := Vector3.BACK * side
		Casing.panel(weapon_spin, PackedVector3Array([
			Vector3(-0.089, 0.188, z), Vector3(-0.073, 0.308, z),
			Vector3(-0.026, 0.480, z * 0.73), Vector3(0.048, 0.625, z * 0.61),
			Vector3(0.085, 0.451, z * 0.75), Vector3(0.106, 0.311, z), Vector3(0.099, 0.196, z),
		]), toward, 0.022, _armor, _titanium)
		_fastener(weapon_spin, Vector3(0.052, 0.387, side * 0.069), 0.011, toward)
		_fastener(weapon_spin, Vector3(-0.037, 0.254, side * 0.076), 0.012, toward)
	_plate(weapon_spin, Vector3(Hand.GRIP_WIDTH, 0.354, Hand.GRIP_DEPTH), Vector3(0, -0.032, 0), _dark)
	_plate(weapon_spin, Vector3(0.125, 0.072, 0.112), Vector3(0, -0.224, 0), _alloy)
	_plate(weapon_spin, Vector3(0.029, 0.053, 0.020), Vector3(0.114, 0.165, -0.069), _warm)
	for i in range(5):
		_plate(weapon_spin, Vector3(Hand.GRIP_WIDTH + 0.004, 0.016, Hand.GRIP_DEPTH + 0.004), Vector3(0, 0.079 - i * 0.059, 0), _armor)


func _mesh_blade() -> void:
	var mesh := Blade.body(BLADE_LENGTH, BLADE_WIDTH)
	_blade_mount = MeshKit.pivot(weapon_spin, Vector3(0, BLADE_START, 0), "ResonatingBlade")
	_blade_mount.set_meta(&"joint_detail", true)
	var sword := MeshKit.add(_blade_mount, mesh, null)
	sword.set_surface_override_material(0, _blade)
	sword.set_surface_override_material(1, _edge)
	MeshKit.add(_blade_mount, Blade.channels(BLADE_LENGTH, BLADE_WIDTH), _armor)
	var inlay := MeshKit.add(_blade_mount, Blade.inlays(BLADE_LENGTH, BLADE_WIDTH), _blade_inlay)
	inlay.name = "BladeInlay"
	inlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var energized_edge := MeshKit.add(_blade_mount, Blade.charge_edge(BLADE_LENGTH, BLADE_WIDTH), _blade_inlay)
	energized_edge.name = "EnergizedEdge"
	energized_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blade_spill = _light(_blade_mount, "BladeSpill", Vector3(0.015, 0.88, 0), Color("67ffd4"), 1.30, 2.6)
	var radii := PackedFloat32Array()
	radii.resize(Blade.SLICES + 1)
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var index := clampi(roundi(vertex.y * Blade.SLICES / BLADE_LENGTH), 0, Blade.SLICES)
			radii[index] = maxf(radii[index], Vector2(vertex.x, vertex.z).length())
	for i in range(radii.size()):
		blade_discs.append({"y": BLADE_START + BLADE_LENGTH * float(i) / Blade.SLICES, "r": radii[i]})


func _rig_geometry() -> void:
	_skeleton.name = "DuelistSkeleton"
	add_child(_skeleton)
	var pelvis := _skeleton.attach(body, "Pelvis", -1)
	var lower := pelvis
	for i in _lumbar.size():
		lower = _skeleton.attach(_lumbar[i], "Lumbar_%d" % (i + 1), lower)
	var chest := _skeleton.attach(torso, "Chest", lower)
	var cervical := chest
	for i in _neck.size():
		cervical = _skeleton.attach(_neck[i], "Cervical_%d" % (i + 1), cervical)
	_skeleton.attach(head, "Head", cervical)
	for leg in legs:
		var suffix := "_L" if leg["side"] < 0.0 else "_R"
		var thigh := _skeleton.attach(leg["hip"], "Thigh" + suffix, pelvis)
		var shin := _skeleton.attach(leg["knee"], "Shin" + suffix, thigh)
		_skeleton.attach(leg["patella"], "Patella" + suffix, shin)
		var ankle := _skeleton.attach(leg["ankle"], "Ankle" + suffix, shin)
		_skeleton.attach(leg["toe"], "Forefoot" + suffix, ankle)
	for arm in arms:
		var suffix := "_L" if arm["side"] < 0.0 else "_R"
		var clavicle := _skeleton.attach(arm["clavicle"], "Clavicle" + suffix, chest)
		_skeleton.attach(arm["scapula"], "Scapula" + suffix, clavicle)
		var shoulder := _skeleton.attach(arm["shoulder"], "UpperArm" + suffix, clavicle)
		_skeleton.attach(arm["cap"], "Pauldron" + suffix, shoulder)
		var elbow := _skeleton.attach(arm["elbow"], "Elbow" + suffix, shoulder)
		var roll := _skeleton.attach(arm["twist"], "ForearmRoll" + suffix, elbow)
		var wrist := _skeleton.attach(arm["wrist"], "Wrist" + suffix, roll)
		var palm := _skeleton.attach(arm["wrist"].get_meta(&"palm"), "Palm" + suffix, wrist)
		for finger: Dictionary in arm["fingers"]:
			var joint := palm
			var links: Array[Node3D] = finger["joints"]
			for index in links.size():
				joint = _skeleton.attach(links[index], "%s_%d%s" % [finger["label"], index + 1, suffix], joint)
		if arm["side"] > 0.0:
			_skeleton.attach(weapon_spin, "Blade", wrist)


func shoulder_anchor(arm: Dictionary, hand_target: Vector3) -> Vector3:
	var side: float = arm["side"]
	var trunk := body.transform * torso.transform
	var local := trunk.affine_inverse() * hand_target
	var lift := smoothstep(0.27, 1.43, local.y)
	var reach := smoothstep(0.15, 1.35, -local.z)
	var clavicle := arm["clavicle"] as Node3D
	clavicle.position = Vector3(side * (0.34 + reach * 0.032), 0.861 + lift * 0.060, 0.02 - reach * 0.063)
	clavicle.rotation_degrees = Vector3(0, side * reach * 10.0, side * lift * 17.0)
	var scapula := arm["scapula"] as Node3D
	scapula.position = Vector3(side * (0.30 + reach * 0.035), 0.74 + lift * 0.046, 0.194 - reach * 0.014)
	scapula.rotation_degrees = Vector3(-8.0 * lift, side * 11.0 * reach, side * 15.0 * lift)
	var cap := arm["cap"] as Node3D
	cap.rotation_degrees = Vector3(-9.0 * reach, side * 10.0 * reach, side * -16.0 * lift)
	return trunk * (clavicle.transform * Vector3(side * 0.195, 0, 0))


func sword_wrist_basis(arm: Dictionary, forearm_roll_deg: float, ulnar_deviation_deg := 0.0) -> Basis:
	var elbow := arm["elbow"] as Node3D
	var forearm_axis := elbow.basis.y
	var upper_arm: Vector3 = arm["shoulder"].position - elbow.position
	var neutral := upper_arm.slide(forearm_axis).normalized()
	var roll := deg_to_rad(clampf(forearm_roll_deg, -76.0, 76.0))
	var thumb_axis := neutral.rotated(forearm_axis, roll)
	return Basis(thumb_axis, forearm_axis, thumb_axis.cross(forearm_axis)) * sword_wrist_offset(ulnar_deviation_deg)


func sword_wrist_offset(ulnar_deviation_deg: float, flexion_deg := -14.0) -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(flexion_deg)) * Basis(Vector3.BACK, deg_to_rad(-ulnar_deviation_deg))


func sword_wrist_deviation() -> float:
	var arm := arms[1]
	var proximal: Vector3 = arm["wrist"].basis.inverse() * arm["elbow"].basis.y
	return rad_to_deg(atan2(-proximal.x, proximal.y))


func sword_wrist_flexion() -> float:
	var arm := arms[1]
	var proximal: Vector3 = arm["wrist"].basis.inverse() * arm["elbow"].basis.y
	return rad_to_deg(-asin(clampf(proximal.z, -1.0, 1.0)))


func sword_arm_angles(deviation: float, flexion_deg := -14.0) -> Vector2:
	var arm := arms[1]
	var wrist := arm["wrist"] as Node3D
	var elbow := arm["elbow"] as Node3D
	var upper: Vector3 = (elbow.position - arm["shoulder"].position).normalized()
	var forearm := wrist.basis * sword_wrist_offset(deviation, flexion_deg).inverse()
	var neutral := (-upper).slide(forearm.y).normalized()
	return Vector2(upper.angle_to(-forearm.y), neutral.signed_angle_to(forearm.x, forearm.y))


func pose_sword_arm(weapon_basis: Basis, flex: float, roll: float, deviation: float,
		flexion_deg := -14.0, grip_cant := 0.0) -> void:
	var arm := arms[1]
	var wrist := arm["wrist"] as Node3D
	var wrist_basis := weapon_basis * Hand.sword_socket(grip_cant).basis.inverse()
	var forearm := wrist_basis * sword_wrist_offset(deviation, flexion_deg).inverse()
	var lower := -forearm.y
	var neutral := forearm.x.rotated(forearm.y, -roll)
	var upper := lower * cos(flex) - neutral * sin(flex)
	_position_sword_arm(arm, upper, lower)
	wrist.basis = wrist_basis


func pose_sword_links(upper: Vector3, lower: Vector3, roll: float, deviation: float) -> void:
	var arm := arms[1]
	_position_sword_arm(arm, upper, lower)
	arm["wrist"].basis = sword_wrist_basis(arm, rad_to_deg(roll), deviation)


func _position_sword_arm(arm: Dictionary, upper: Vector3, lower: Vector3) -> void:
	var wrist := arm["wrist"] as Node3D
	var reach := upper * UPPER_ARM + lower * FOREARM
	var near_shoulder := shoulder_anchor(arm, body.transform * torso.transform * Vector3(0.53, 0.88, 0) + reach)
	var shoulder := shoulder_anchor(arm, near_shoulder + reach)
	DisplayPose.solve_chain(arm["shoulder"], arm["elbow"], wrist, shoulder, shoulder + reach, upper, UPPER_ARM, FOREARM)


func floor_height(point: Vector3) -> float:
	return kerb.y if absf(point.x) >= kerb.x else 0.0


func keep_sole_above_floor(foot: Transform3D) -> Transform3D:
	var heel := foot * Pace.HEEL
	var toe := foot * Pace.TOE
	foot.origin.y += maxf(0.0, maxf(floor_height(heel) - heel.y, floor_height(toe) - toe.y))
	return foot


func finish_pose(hand_open := 0.24, blade_grip := 1.0, toe_angles := Vector2.ZERO,
		support_roll := 0.0, shoulder_armor_clearance := 0.0, grip_cant := 0.0) -> void:
	sword_grip_cant = grip_cant
	var waist_rotation := torso.quaternion
	for i in _lumbar.size():
		var share := 0.38 + 0.14 * i
		_lumbar[i].quaternion = waist_rotation.inverse().slerp(Quaternion.IDENTITY, share)
	var head_rotation := head.quaternion
	for i in _neck.size():
		_neck[i].quaternion = Quaternion.IDENTITY.slerp(head_rotation, 0.21 + 0.24 * i)
	for i in legs.size():
		var leg := legs[i]
		var thigh := leg["hip"] as Node3D
		var shin := leg["knee"] as Node3D
		var flex := 1.0 - thigh.basis.y.dot(shin.basis.y)
		leg["patella"].position = Vector3(0, 0.046 * flex, -0.031 * flex)
		leg["patella"].rotation_degrees.x = 13.0 * flex
		leg["toe"].rotation_degrees.x = toe_angles[i]
	for i in arms.size():
		var arm := arms[i]
		var gripping: bool = arm["side"] > 0.0
		var wrist := arm["wrist"] as Node3D
		if gripping:
			var upper_arm := arm["shoulder"] as Node3D
			var forearm := arm["elbow"] as Node3D
			# Both ends of the elbow hinge share the same axis. The cuff twists independently.
			var hinge := upper_arm.basis.y.cross(forearm.basis.y).normalized()
			if not hinge.is_zero_approx():
				upper_arm.basis = Basis(hinge, upper_arm.basis.y, hinge.cross(upper_arm.basis.y))
				forearm.basis = Basis(hinge, forearm.basis.y, hinge.cross(forearm.basis.y))
			# Convert the outward armor slide using the finalized elbow hinge orientation.
			var outward := (body.basis * torso.basis).x * shoulder_armor_clearance
			arm["cap"].position = upper_arm.basis.inverse() * outward
			var thumb := wrist.basis.x.slide(forearm.basis.y).normalized()
			arm["twist"].rotation.y = forearm.basis.x.signed_angle_to(thumb, forearm.basis.y)
			weapon_root.transform = wrist.transform * Hand.sword_socket(grip_cant)
		else:
			arm["twist"].rotation_degrees.y = support_roll
		Hand.curl(arm["fingers"], blade_grip if gripping else hand_open, gripping, grip_cant if gripping else 0.0)
	_skeleton.sync()


func set_effects(warning: float, thrust: float) -> void:
	var cue := clampf(warning, 0.0, 1.0)
	var boost := clampf(thrust, 0.0, 1.0)
	_lamp.visible = cue > 0.0
	_lamp.scale = Vector3.ONE * lerpf(0.42, 1.0, cue)
	_warning_spill.light_energy = cue * 2.2
	for jet in _thrusters:
		jet.visible = boost > 0.0
		jet.scale = Vector3.ONE * lerpf(0.45, 1.0, boost)


func set_charge_state(age: float, blade_discharge := 0.0, attack_glow := 0.0) -> void:
	if age >= Charge.BLADE_FILLED_AT and age < Charge.DURATION:
		attack_glow = 1.0
	var remaining := 1.0 - smoothstep(Charge.DURATION + Charge.FLASH_DURATION, Charge.DURATION + 0.86, age)
	var contact := smoothstep(0.0, 0.035, age) * remaining
	var dip := contact * (1.0 - smoothstep(0.05, 0.21, age))
	var feed := smoothstep(0.10, 0.535, age) * remaining
	var shoulder := smoothstep(0.33, 0.715, age) * remaining
	var arm := smoothstep(0.47, 0.915, age) * remaining
	var red_heat := smoothstep(1.11, 1.81, age) * remaining
	var flash := Charge.red_flash_at(age)

	var signal_mix := maxf(attack_glow, flash)
	var front := smoothstep(0.465, Charge.BLADE_FILLED_AT, age)
	var core_pulse := 0.25 * sin(TAU * (3.6 * age + 1.44 * age * age)) * feed * (1.0 - smoothstep(1.74, Charge.QUIET_AT, age))

	_tint_lamp(_core, CORE_TINT, signal_mix)
	_tint_lamp(_optic, OPTIC_TINT, signal_mix)
	_tint_lamp(_temple, OPTIC_TINT.lerp(Color("ad211a"), red_heat), signal_mix)
	_tint_lamp(_shoulder_power, SHOULDER_TINT, attack_glow)
	_tint_lamp(_arm_power, ARM_TINT, attack_glow)
	_tint_lamp(_status, STATUS_TINT, attack_glow)
	_tint_lamp(_exhaust_glow, EXHAUST_TINT, attack_glow)
	var core_idle := 3.75 - dip * 3.15 + feed * 2.2 + core_pulse
	_core.emission_energy_multiplier = lerpf(lerpf(core_idle, 7.3, attack_glow), 12.0, flash)
	_shoulder_power.emission_energy_multiplier = lerpf(2.15, 4.6, maxf(shoulder, attack_glow))
	_arm_power.emission_energy_multiplier = lerpf(2.3, 6.0, maxf(arm, attack_glow))
	_temple.emission_energy_multiplier = lerpf(lerpf(2.0, 4.7, maxf(red_heat * 0.43, attack_glow)), 8.0, flash)
	_optic.emission_energy_multiplier = lerpf(lerpf(3.8, 6.1, attack_glow), 12.0, flash)
	_core_spill.light_color = _core.emission
	_core_spill.light_energy = lerpf(lerpf(0.65 - dip * 0.50 + feed * 0.45, 1.7, attack_glow), 3.15, flash)
	_visor_spill.light_color = _optic.emission
	_visor_spill.light_energy = lerpf(lerpf(0.22, 1.25, attack_glow), 2.65, flash)

	_blade_inlay.set_shader_parameter("baseline", lerpf(lerpf(3.2, 0.48, contact), 1.15, blade_discharge))
	_blade_inlay.set_shader_parameter("leading_edge", lerpf(0.14, 1.12, front))
	_blade_inlay.set_shader_parameter("charged_power", (4.2 + red_heat * 4.3) * contact * lerpf(1.0, 0.20, blade_discharge))
	_blade_inlay.set_shader_parameter("white_heat", red_heat * 0.82)
	_blade_inlay.set_shader_parameter("moving_wave", arm * (1.0 - smoothstep(0.90, 1.0, front)))
	_blade_inlay.set_shader_parameter("attack_glow", attack_glow)
	_blade_spill.light_energy = 1.12 - 0.86 * contact + (front * front) * contact * lerpf(2.1, 0.90, blade_discharge)
	_blade_spill.light_color = Color("67ffd4").lerp(Color("c7fff4"), red_heat).lerp(SIGNAL_TINT, attack_glow)
	_blade_spill.position.y = lerpf(0.88, lerpf(0.25, 1.35, front), contact)
	_blade_mount.rotation_degrees = Charge.vibration_at(age)


func _tint_lamp(material: StandardMaterial3D, idle: Color, red: float) -> void:
	var color := idle.lerp(SIGNAL_TINT, red)
	material.albedo_color = color
	material.emission = color


func cue_origin() -> Vector3:
	return _lamp.global_position


func replay_nodes() -> Array:
	var nodes: Array = [self, body, torso, head, weapon_root, weapon_spin, _lamp]
	for leg in legs:
		nodes.append_array([leg["hip"], leg["knee"], leg["ankle"]])
	for arm in arms:
		nodes.append_array([arm["shoulder"], arm["elbow"], arm["wrist"]])
	nodes.append_array(_thrusters)
	return nodes

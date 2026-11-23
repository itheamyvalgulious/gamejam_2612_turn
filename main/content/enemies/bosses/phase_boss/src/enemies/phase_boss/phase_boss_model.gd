extends Node3D
## Ground is y = 0 and the machine faces -Z. Dimensions use the ACT prototype scale.

const Kit = preload("res://scripts/mech/mesh_kit.gd")
const Palette = preload("res://scripts/mech/materials.gd")
const Loft = preload("res://src/geometry/loft_shell.gd")
const Armor = preload("res://src/geometry/armor_panel.gd")
const Cannon = preload("res://src/enemies/phase_boss/phase_boss_cannon.gd")

enum LightZone { TAIL_TIP, TAIL_ROOT, HIPS, BACK, REAR_RIBS, FRONT_RIBS, SHOULDERS, EYES }

var chest: Node3D
var pelvis: Node3D
var neck: Node3D
var head: Node3D
var jaw: Node3D
var cannon: Cannon
var legs: Array[Dictionary] = []
var tail: Array[Node3D] = []
var tail_fin: Node3D
var emitters: Array[Node3D] = []
var _actuators: Array[Dictionary] = []
var _plate: StandardMaterial3D
var _cut: Material
var _dark: StandardMaterial3D
var _steel: StandardMaterial3D
var _copper: Material
var _joint: Material
var _glass: Material
var _motion_lamps: Array[StandardMaterial3D] = []
var _amber: StandardMaterial3D
var _charge_lights: Array[StandardMaterial3D] = []


func _ready() -> void:
	_plate = Palette.armor().duplicate()
	_plate.albedo_color = Color("676e6c")
	_plate.roughness = 0.46
	_cut = Palette.armor_edge()
	_dark = Palette.frame().duplicate()
	_dark.roughness = 0.46
	_steel = Palette.frame_light().duplicate()
	_steel.roughness = 0.47
	_copper = Palette.copper()
	_joint = Palette.armor_shadow()
	_glass = Palette.glass()
	for i in LightZone.size():
		var tint := Color("65e6ff") if i == LightZone.EYES else Color("24cee7")
		var energy := 2.6 if i == LightZone.EYES else 2.15
		_motion_lamps.append(Palette.emissive(tint, energy).duplicate())
	_amber = Palette.emissive(Color("ffaa55"), 1.35).duplicate()
	for i in 5:
		_charge_lights.append(_amber.duplicate())
	chest = Kit.pivot(self, Vector3(0, 3.73, -1.27), "Chest")
	pelvis = Kit.pivot(chest, Vector3(0, 0.04, 3.64), "Pelvis")
	_build_body()
	cannon = Cannon.new()
	cannon.name = "DorsalCannon"
	cannon.position = Vector3(0, 2.08, -0.04)
	chest.add_child(cannon)
	cannon.build(_plate, _cut, _dark, _steel, _copper, _motion_lamps[LightZone.BACK])
	_build_head()
	for side: float in [-1.0, 1.0]:
		_build_leg(side, true)
		_build_leg(side, false)
		_build_emitter(side)
	_build_tail()
	set_jaw_open(0)
	update_actuators()


func _build_body() -> void:
	_hull(chest, [[-2.86, 1.04, 0.85, -0.20], [-2.39, 1.57, 1.27, -0.09],
		[-1.65, 2.08, 1.61, 0.19], [-0.71, 2.39, 1.80, 0.14],
		[0.27, 2.25, 1.62, 0.04], [1.32, 1.84, 1.36, -0.04],
		[2.32, 1.56, 1.13, -0.07], [2.96, 1.51, 0.90, -0.14]], _steel, Vector2i(2, 5))
	_hull(pelvis, [[-1.25, 1.51, 0.95, 0.22], [-0.65, 1.81, 1.15, 0.18],
		[0.32, 1.85, 1.27, 0.26], [1.18, 1.63, 1.05, 0.25],
		[1.77, 1.11, 0.70, 0.21], [2.14, 0.69, 0.56, 0.17]], _dark)
	_hull(chest, [[-2.25, 0.72, 0.42, -1.19], [-1.53, 1.05, 0.52, -1.37],
		[-0.66, 1.35, 0.55, -1.53], [0.32, 1.39, 0.49, -1.45],
		[1.10, 1.08, 0.41, -1.30], [1.63, 0.78, 0.34, -1.10]], _joint)
	for side: float in [-1.0, 1.0]:
		_build_flank(side)
		_swept_scale(chest, side, Vector3(1.18, 1.45, -0.43), 1.31)
		_swept_scale(chest, side, Vector3(1.12, 1.38, 0.68), 1.14)
		_swept_scale(pelvis, side, Vector3(0.94, 1.09, -0.30), 0.89)
		_side_panel(pelvis, side, [Vector3(1.51, 0.66, -0.88), Vector3(1.62, 1.26, -0.49),
			Vector3(1.91, 1.38, 0.43), Vector3(1.95, 0.89, 1.28), Vector3(1.41, 0.41, 1.82),
			Vector3(1.48, -0.28, 1.32), Vector3(1.87, -0.44, 0.64),
			Vector3(1.87, 0.14, -0.25)], 0.31, _plate, _motion_lamps[LightZone.HIPS], 0.61)
		_side_panel(pelvis, side, [Vector3(1.12, 0.63, 1.70), Vector3(1.40, 0.41, 1.51),
			Vector3(1.35, -0.21, 1.52), Vector3(0.84, -0.32, 2.06),
			Vector3(0.71, 0.25, 2.16)], 0.22, _joint)
	_spine_plate(chest, -2.09, 1.25, 0.83)
	_spine_plate(chest, 1.62, 1.48, 1.18)
	for i in 3:
		_spine_plate(pelvis, -0.44 + i * 0.83, [1.36, 1.44, 1.09][i], [1.03, 1.13, 0.76][i], i == 1)


func _build_flank(side: float) -> void:
	_side_panel(chest, side, [Vector3(1.88, 0.76, -2.03), Vector3(2.29, 0.76, -1.35),
		Vector3(2.40, 0.52, -0.34), Vector3(2.07, 0.41, 0.91), Vector3(1.50, 0.30, 2.21),
		Vector3(1.45, -0.66, 2.27), Vector3(1.72, -1.38, 1.03), Vector3(1.83, -1.66, 0.03),
		Vector3(1.66, -1.44, -1.02), Vector3(1.38, -0.86, -2.31)], 0.27, _joint)
	for i in 3:
		var z := 0.05 + i * 0.74
		var w: float = [2.37, 2.14, 1.91][i]
		var high: float = [1.27, 1.14, 1.08][i]
		_side_panel(chest, side, [Vector3(w * 0.71, high, z - 0.39),
			Vector3(w * 0.87, high - 0.12, z + 0.03), Vector3(w, 0.86, z + 0.29),
			Vector3(w * 1.10, 0.50, z + 0.72), Vector3(w * 1.01, 0.39, z + 0.31),
			Vector3(w * 0.98, -0.37, z + 0.30), Vector3(w * 0.89, -0.92 + i * 0.12, z + 0.51),
			Vector3(w * 0.80, -1.30 + i * 0.16, z - 0.05),
			Vector3(w * 0.86, -0.89 + i * 0.16, z - 0.30), Vector3(w * 0.96, -0.10, z - 0.42)],
			0.26, _plate, _steel, 0.57)
		_side_panel(chest, side, [Vector3(w * 0.92 + 0.15, 0.67, z - 0.19),
			Vector3(w * 1.02 + 0.13, 0.64, z + 0.17), Vector3(w * 1.11 + 0.04, 0.52, z + 0.56),
			Vector3(w * 1.01 + 0.115, 0.41, z + 0.23), Vector3(w * 0.94 + 0.14, 0.41, z - 0.08)],
			0.09, _joint, _motion_lamps[LightZone.FRONT_RIBS if i == 0 else LightZone.REAR_RIBS], 0.28)
		_bearing(chest, Vector3(side * (w * 1.01 + 0.12), -0.34, z + 0.14),
			Vector3(side, 0, 0), 0.062, 0.061, _cut)
		_line(chest, Vector3(side * (w * 1.02 + 0.14), 0.37, z + 0.21),
			Vector3(side * (w * 1.01 + 0.15), 0.20, z + 0.13), 0.028, _amber)
	_side_panel(chest, side, [Vector3(1.49, -1.20, -1.55), Vector3(1.88, -1.08, -0.77),
		Vector3(1.89, -1.25, 0.20), Vector3(1.70, -1.38, 0.96), Vector3(1.23, -1.72, 0.94),
		Vector3(1.18, -1.99, -0.13), Vector3(1.06, -1.76, -1.16)], 0.30, _plate, _joint, 0.55)


func _spine_plate(parent: Node3D, z: float, y: float, width: float, powered := false,
		marker_light: Material = null) -> void:
	Armor.panel(parent, PackedVector3Array([
		Vector3(-width * 0.74, y - 0.17, z - 0.29), Vector3(0, y + 0.20, z - 0.42),
		Vector3(width * 0.74, y - 0.17, z - 0.29), Vector3(width, y - 0.14, z + 0.08),
		Vector3(width * 0.52, y + 0.11, z + 0.28), Vector3(0, y + 0.27, z + 0.26),
		Vector3(-width * 0.52, y + 0.11, z + 0.28), Vector3(-width, y - 0.14, z + 0.08),
	]), Vector3.UP, 0.21, _plate, _cut)
	if powered:
		var housing := Kit.slab(width * 0.49, 0.47, 0.115, 0.04)
		Kit.add(parent, housing, _dark, Vector3(0, y + 0.29, z - 0.055))
		for side: float in [-1.0, 1.0]:
			var strip := Kit.slab(width * 0.15, 0.32, 0.039, 0.014)
			Kit.add(parent, strip, _motion_lamps[LightZone.HIPS], Vector3(side * width * 0.12, y + 0.353, z - 0.035))
	else:
		Kit.add(parent, Kit.slab(0.24, 0.38, 0.095, 0.035), _dark, Vector3(0, y + 0.34, z - 0.05))
		_line(parent, Vector3(0, y + 0.40, z - 0.15), Vector3(0, y + 0.40, z + 0.05),
			0.033, _amber if marker_light == null else marker_light)


func _swept_scale(parent: Node3D, side: float, at: Vector3, size: float) -> void:
	var well := Vector3(side * at.x, at.y, at.z)
	var points := PackedVector3Array()
	for point: Vector3 in [Vector3(-0.20, -0.06, -0.33), Vector3(0.26, 0.01, -0.36),
		Vector3(0.52, 0.21, -0.04), Vector3(0.97, 0.47, 0.78),
		Vector3(0.46, 0.28, 0.56), Vector3(0.24, 0.21, 0.64),
		Vector3(-0.15, 0.13, 0.18)]:
		points.append(well + Vector3(side * point.x, point.y, point.z) * size)
	Armor.panel(parent, points, Vector3(side * 0.43, 1, -0.2), size * 0.24, _plate, _cut)


func _build_head() -> void:
	neck = Kit.pivot(chest, Vector3(0, -0.49, -2.32), "Neck")
	_hull(neck, [[-2.08, 0.90, 0.57, -0.53], [-1.49, 1.21, 0.74, -0.34],
		[-0.89, 1.39, 1.01, 0.05], [-0.08, 1.65, 1.29, 0.28],
		[0.44, 1.60, 1.22, 0.30]], _dark)
	for side: float in [-1.0, 1.0]:
		_side_panel(neck, side, [Vector3(0.81, -0.19, -1.86),
			Vector3(1.05, 0.29, -1.26), Vector3(1.37, 1.18, -0.49),
			Vector3(1.57, 1.31, 0.07), Vector3(1.62, 0.21, 0.36),
			Vector3(1.49, -0.39, 0.07), Vector3(1.13, -0.87, -0.73),
			Vector3(0.94, -0.76, -1.57)], 0.34, _joint, _dark, 0.52)
		_swept_scale(neck, side, Vector3(0.53, 0.31, -1.70), 0.89)
		_swept_scale(neck, side, Vector3(0.77, 0.93, -0.84), 1.07)
	head = Kit.pivot(neck, Vector3(0, -0.70, -1.68), "Head")
	_build_skull()
	_build_jaw()


func _build_skull() -> void:
	_hull(head, [[-2.04, 0.24, 0.08, -0.055], [-1.79, 0.56, 0.18, 0.01],
		[-1.37, 0.73, 0.35, 0.10], [-0.81, 0.96, 0.56, 0.19],
		[-0.27, 1.10, 0.70, 0.21], [0.39, 0.83, 0.61, 0.11]], _dark)
	for side: float in [-1.0, 1.0]:
		var normal := Vector3(side, 0, 0)
		# Opposing planes make a ridged, split brow above the optical slit.
		Armor.panel(head, PackedVector3Array([
			Vector3(side * 0.055, 0.085, -2.25), Vector3(side * 0.48, 0.10, -2.11),
			Vector3(side * 0.82, 0.30, -1.61), Vector3(side * 1.11, 0.59, -0.88),
			Vector3(side * 1.18, 0.86, -0.22), Vector3(side * 0.64, 1.02, -0.02),
			Vector3(side * 0.12, 0.79, -0.58), Vector3(side * 0.16, 0.49, -1.39),
		]), Vector3(side * 0.31, 1, -0.23), 0.27, _plate, _cut)
		_side_panel(head, side, [Vector3(0.43, 0.06, -2.14),
			Vector3(0.76, 0.29, -1.66), Vector3(1.07, 0.62, -0.91),
			Vector3(1.27, 0.85, -0.26), Vector3(1.22, 0.50, 0.25),
			Vector3(1.21, 0.47, -0.50), Vector3(1.04, 0.17, -1.25),
			Vector3(0.67, -0.19, -1.84)], 0.20, _joint)
		Armor.panel(head, PackedVector3Array([
			Vector3(side * 0.66, -0.035, -1.81), Vector3(side * 0.90, 0.15, -1.42),
			Vector3(side * 1.18, 0.42, -0.82), Vector3(side * 1.21, 0.25, -0.77),
			Vector3(side * 1.02, -0.055, -1.24), Vector3(side * 0.83, -0.16, -1.72),
		]), Vector3(side, 0, -0.33), 0.17, _glass, _steel)
		Armor.panel(head, PackedVector3Array([
			Vector3(side * 0.77, -0.020, -1.78), Vector3(side * 1.00, 0.17, -1.39),
			Vector3(side * 1.24, 0.33, -0.88), Vector3(side * 1.22, 0.234, -0.92),
			Vector3(side * 1.02, 0.085, -1.36), Vector3(side * 0.81, -0.073, -1.76),
		]), Vector3(side, 0, -0.32), 0.048, _motion_lamps[LightZone.EYES], _motion_lamps[LightZone.EYES])
		_side_panel(head, side, [Vector3(0.87, -0.16, -1.49),
			Vector3(1.16, 0.095, -0.96), Vector3(1.42, 0.33, -0.33),
			Vector3(1.40, 0.72, 0.35), Vector3(1.31, 0.34, 0.58),
			Vector3(1.32, -0.18, 0.37), Vector3(1.15, -0.53, -0.03),
			Vector3(1.02, -0.41, -0.71)], 0.32, _plate, _joint, 0.57)
		for i in 3:
			var z := -0.24 + i * 0.17
			_line(head, Vector3(side * (1.44 + i * 0.010), 0.28 + i * 0.065, z),
				Vector3(side * (1.43 + i * 0.010), 0.13 + i * 0.07, z + 0.10), 0.029, _dark)
		for i in 4:
			var tooth := Vector3(0.405 + i * 0.126, -0.23 - i * 0.029, -1.93 + i * 0.375)
			_fang(head, side, tooth, -0.51 if i == 1 else -0.24 - i * 0.018,
				0.30 if i == 1 else 0.19)
	Armor.panel(head, PackedVector3Array([
		Vector3(-0.36, -0.13, -2.14), Vector3(-0.48, 0.08, -2.14),
		Vector3(0, 0.12, -2.27), Vector3(0.48, 0.08, -2.14),
		Vector3(0.36, -0.13, -2.14), Vector3(0, -0.27, -2.27),
	]), Vector3.FORWARD, 0.14, _joint, _steel)


func _build_jaw() -> void:
	jaw = Kit.pivot(head, Vector3(0, -0.43, 0.13), "Jaw")
	_hull(jaw, [[-2.02, 0.29, 0.073, -0.13], [-1.73, 0.56, 0.10, -0.15],
		[-1.29, 0.72, 0.16, -0.17], [-0.56, 0.89, 0.22, -0.13],
		[0.19, 0.75, 0.26, 0.016]], _steel)
	for side: float in [-1.0, 1.0]:
		var normal := Vector3(side, 0, 0)
		_side_panel(jaw, side, [Vector3(0.29, -0.05, -2.13),
			Vector3(0.63, -0.015, -1.78), Vector3(0.88, 0.04, -1.15),
			Vector3(1.03, 0.28, -0.32), Vector3(1.10, 0.39, 0.13),
			Vector3(1.10, 0.02, 0.35), Vector3(0.98, -0.38, 0.06),
			Vector3(0.91, -0.47, -0.72), Vector3(0.63, -0.37, -1.50),
			Vector3(0.24, -0.22, -2.04)], 0.30, _plate)
		Armor.panel(jaw, PackedVector3Array([
			Vector3(side * 0.10, -0.19, -2.14), Vector3(side * 0.52, -0.29, -1.73),
			Vector3(side * 0.80, -0.44, -1.03), Vector3(side * 0.46, -0.40, -0.93),
			Vector3(side * 0.17, -0.32, -1.41),
		]), Vector3(side * 0.61, -1, 0), 0.17, _joint, _cut)
		var hinge := Vector3(side * 1.04, 0.015, 0.0)
		_bearing(jaw, hinge + normal * 0.11, normal, 0.29, 0.24, _dark)
		_bearing(jaw, hinge + normal * 0.24, normal, 0.19, 0.12, _steel)
		_bearing(jaw, hinge + normal * 0.30, normal, 0.087, 0.065, _cut)
		for i in 3:
			var tooth := Vector3(0.54 + i * 0.125, 0.02 + i * 0.038, -1.72 + i * 0.43)
			_fang(jaw, side, tooth, 0.28 if i == 1 else 0.17, 0.18)


func _fang(parent: Node3D, side: float, base: Vector3, height: float, span: float) -> void:
	_side_panel(parent, side, [base + Vector3(0, 0, -span * 0.48),
		base + Vector3(0, 0, span * 0.52),
		base + Vector3(-0.025, height * 0.57, span * 0.48),
		base + Vector3(-0.062, height, span * 0.62)], span * 0.46, _cut)


func _build_leg(side: float, front: bool) -> void:
	var name_suffix := "L" if side < 0 else "R"
	var stagger := side * (-0.70 if front else -0.46)
	var anchor := Vector3(side * 1.96, 0.28, -1.64) if front else Vector3(side * 1.64, -0.14, 0.86)
	var root := Kit.pivot(chest if front else pelvis, anchor,
		("Shoulder" if front else "Hip") + name_suffix)
	var normal := Vector3(side, 0, 0)
	var upper := Vector3(side * 0.54, -1.44, 0.68 + stagger * 0.48) if front else (
		Vector3(side * 0.51, -1.37, -1.16 + stagger * 0.48))
	var middle := Vector3(side * 0.31, -1.50, -1.62 + stagger * 0.31) if front else (
		Vector3(side * 0.28, -1.10, 1.29 + stagger * 0.31))
	var lower := Vector3(side * 0.10, -0.65, -0.55 + stagger * 0.21) if front else (
		Vector3(side * 0.11, -0.74, -0.49 + stagger * 0.21))
	var joint := Kit.pivot(root, upper, ("Elbow" if front else "Knee") + name_suffix)
	var distal := Kit.pivot(joint, middle, ("Wrist" if front else "Hock") + name_suffix)
	var paw := Kit.pivot(distal, lower, "Paw" + name_suffix)
	legs.append({"front": front, "side": side, "root": root, "joint": joint, "distal": distal, "paw": paw})
	_limb_shell(root, upper, normal, 1.73 if front else 1.51, 1.21)
	_limb_shell(joint, middle, normal, 1.42 if front else 1.05, 0.82 if front else 0.72,
		_motion_lamps[LightZone.SHOULDERS] if front else null)
	_limb_shell(distal, lower, normal, 0.79, 0.52)
	_joint_stack(root, normal, 0.78 if front else 0.72, 0.47)
	_joint_stack(joint, normal, 0.49 if front else 0.52, 0.33)
	_joint_stack(distal, normal, 0.29 if front else 0.41, 0.30)
	_add_actuator(root, joint, upper * 0.49 - normal * 0.37 + Vector3.BACK * 0.25,
		middle * 0.65 - normal * 0.30 + Vector3.BACK * 0.22, 0.16 if front else 0.13)
	_add_actuator(joint, distal, middle * 0.30 + normal * 0.27 + Vector3.FORWARD * 0.32,
		lower * 0.54 + normal * 0.17 + Vector3.FORWARD * 0.19, 0.10)
	_build_foot(paw, side, front)
	if front:
		_build_shoulder_armor(root, side)
	else:
		_leg_armor(root, upper, side, 1.49)


func _build_shoulder_armor(root: Node3D, side: float) -> void:
	# The swept tip sits outside the chest and moves with the shoulder pivot.
	Armor.panel(root, PackedVector3Array([
		Vector3(side * -0.42, 1.10, -1.15), Vector3(side * 0.39, 1.32, -1.01),
		Vector3(side * 0.97, 1.50, -0.57), Vector3(side * 1.55, 1.81, 0.98),
		Vector3(side * 0.95, 1.56, 0.69), Vector3(side * 0.74, 1.38, 1.24),
		Vector3(side * 0.05, 1.39, 0.65), Vector3(side * -0.52, 1.32, 0.08),
	]), Vector3(side * 0.34, 1, 0), 0.36, _plate, _cut)
	_side_panel(root, side, [Vector3(0.51, 1.06, -1.20), Vector3(1.01, 1.26, -0.68),
		Vector3(1.27, 1.46, -0.03), Vector3(1.51, 1.51, 0.88), Vector3(1.31, 0.71, 0.48),
		Vector3(1.38, 0.23, 1.04), Vector3(1.13, -0.18, 0.43),
		Vector3(1.04, -0.68, 0.20), Vector3(0.96, -0.79, -0.14),
		Vector3(0.64, -0.24, -0.92)], 0.38, _plate, _motion_lamps[LightZone.SHOULDERS], 0.50)
	_side_panel(root, side, [Vector3(1.08, 0.10, -0.55), Vector3(1.39, 0.40, -0.16),
		Vector3(1.43, 0.34, 0.24), Vector3(1.33, 0.11, 0.88),
		Vector3(1.16, -0.47, 0.50), Vector3(1.14, -0.78, -0.02),
		Vector3(1.01, -0.45, -0.41)], 0.24, _joint, _steel, 0.58)
	_side_panel(root, side, [Vector3(1.24, 0.91, -0.38), Vector3(1.43, 1.14, 0.14),
		Vector3(1.54, 1.38, 0.69), Vector3(1.43, 1.02, 0.31),
		Vector3(1.32, 0.60, -0.16)], 0.09, _steel)
	Armor.panel(root, PackedVector3Array([
		Vector3(side * 0.49, 0.96, -1.17),
		Vector3(side * 0.80, 0.86, -1.06),
		Vector3(side * 1.01, 0.29, -0.91),
		Vector3(side * 0.85, 0.11, -0.96),
		Vector3(side * 0.65, 0.26, -1.09),
		Vector3(side * 0.57, 0.55, -1.16),
	]), Vector3(side * 0.31, 0, -1), 0.17, _joint, _steel, _motion_lamps[LightZone.SHOULDERS], 0.28)
	_line(root, Vector3(side * 1.45, 0.40, 0.50),
		Vector3(side * 1.44, 0.52, 0.74), 0.037, _amber)
	_bearing(root, Vector3(side * 1.41, -0.11, 0.31), Vector3(side, 0, 0), 0.098, 0.09, _cut)


func _limb_shell(parent: Node3D, delta: Vector3, normal: Vector3, wide: float, narrow: float,
		insert_light: Material = null) -> void:
	var length := delta.length()
	var axis := delta / length
	var flat := (normal.slide(axis)).normalized()
	var edge := flat.cross(axis).normalized()
	var frame := Basis(axis, edge, axis.cross(edge))
	Kit.add(parent, Kit.beam_x(length * 0.88, wide * 0.76, wide * 0.66, narrow * 0.72,
		narrow * 0.65), _dark, delta * 0.055).basis = frame
	Kit.add(parent, Kit.beam_x(length * 0.59, wide * 1.08, wide * 0.73, narrow * 0.91,
		narrow * 0.82), _joint, delta * 0.16).basis = frame
	var a := delta * 0.14 + flat * wide * 0.49
	var b := delta * 0.80 + flat * narrow * 0.43
	Armor.panel(parent, PackedVector3Array([
		a - edge * wide * 0.47, a - axis * wide * 0.12 + edge * wide * 0.10,
		a + axis * wide * 0.14 + edge * wide * 0.50,
		b + edge * narrow * 0.38, b + axis * narrow * 0.13 - edge * narrow * 0.19,
		b - edge * narrow * 0.41, a + axis * wide * 0.27 - edge * wide * 0.53,
	]), flat, wide * 0.24, _plate, _cut, _joint if insert_light == null else insert_light, 0.41)
	if insert_light == null:
		var mid := a.lerp(b, 0.41) + flat * wide * 0.115
		_line(parent, mid - edge * wide * 0.06, mid + axis * wide * 0.24 - edge * wide * 0.06,
			wide * 0.033, _amber)
	for i in 3:
		var bolt := a.lerp(b, 0.18 + i * 0.28) + edge * lerpf(wide, narrow, i * 0.32) * 0.33
		_bearing(parent, bolt + flat * wide * 0.10, flat, wide * 0.045, wide * 0.088, _steel)


func _leg_armor(parent: Node3D, delta: Vector3, side: float, width: float) -> void:
	var normal := Vector3(side, 0, 0)
	var axis := delta.normalized()
	var back := axis.cross(normal).normalized() * side
	var root := delta * 0.18 + normal * width * 0.32
	var middle := delta * 0.42 + normal * width * 0.43
	var tip := delta * 0.81 + normal * width * 0.37
	Armor.panel(parent, PackedVector3Array([
		root + back * width * 0.21,
		root + back * width * 0.46,
		middle + back * width * 0.60,
		tip + back * width * 0.34,
		tip + back * width * 0.15,
		middle + back * width * 0.27,
	]), normal, width * 0.18, _joint, _cut)
	var start := root + back * width * 0.51 + normal * width * 0.075
	var finish := tip + back * width * 0.41 + normal * width * 0.075
	_line(parent, start, finish, width * 0.041, _copper)
	for index in 3:
		var point := start.lerp(finish, 0.20 + 0.21 * index)
		_bearing(parent, point, back, width * 0.063, width * 0.22, _steel)


func _joint_stack(parent: Node3D, normal: Vector3, radius: float, length: float) -> void:
	_bearing(parent, normal * length * 0.14, normal, radius, length * 1.92, _dark)
	_bearing(parent, normal * length * 0.78, normal, radius * 0.83, length * 0.54, _steel)
	_bearing(parent, normal * length * 1.072, normal, radius * 0.63, length * 0.26, _cut)
	_bearing(parent, normal * length * 1.22, normal, radius * 0.50, length * 0.16, _joint)
	_bearing(parent, normal * length * 1.32, normal, radius * 0.21, length * 0.08, _copper)
	for i in 6:
		var angle := TAU * float(i) / 6.0
		var point := normal * length * 1.32 + Vector3(0, cos(angle), sin(angle)) * radius * 0.36
		_bearing(parent, point, normal, radius * 0.078, length * 0.14, _cut)


func _build_foot(parent: Node3D, side: float, front: bool) -> void:
	var foot := Kit.pivot(parent, Vector3.ZERO, "Foot")
	foot.rotation.y = -side * 0.08
	Kit.add(foot, Kit.slab(1.63 if front else 1.44, 1.12, 0.32, 0.09), _steel, Vector3(0, -0.16, -0.21))
	Kit.add(foot, Kit.slab(1.28 if front else 1.12, 0.91, 0.25, 0.055), _plate, Vector3(0, 0.03, -0.25))
	for i in 3:
		var x := (i - 1) * (0.49 if front else 0.43)
		var toe := Kit.pivot(foot, Vector3(x, -0.16, -0.49), "Toe%d" % (i + 1))
		toe.rotation.y = -x * 0.68
		var length := 0.91 if i == 1 else 0.76
		_hull(toe, [[-length, 0.040, 0.044, -0.20], [-length * 0.74, 0.117, 0.068, -0.16],
			[-0.21, 0.166, 0.12, -0.064], [0.10, 0.148, 0.122, 0.018]], _cut)
		_bearing(toe, Vector3(0, 0, 0.065), Vector3.RIGHT, 0.12, 0.29, _dark)
	var heel := Kit.pivot(foot, Vector3(0, -0.16, 0.22), "HeelClaw")
	_hull(heel, [[-0.10, 0.25, 0.13, 0.09], [0.29, 0.21, 0.11, -0.02],
		[0.56, 0.079, 0.070, -0.15], [0.68, 0.039, 0.032, -0.20]], _joint)


func _build_emitter(side: float) -> void:
	var normal := Vector3(side, 0, 0)
	var pivot := Kit.pivot(chest, Vector3(side * 0.86, 1.51, 0.67 + side * 0.22),
		"PhaseVane" + ("L" if side < 0 else "R"))
	pivot.rotation_degrees = Vector3(-12, -side * 6.0, -side * 6.0)
	emitters.append(pivot)
	_bearing(pivot, normal * 0.12, normal, 0.33, 0.81, _dark)
	_side_panel(pivot, side, [Vector3(0.10, 0.08, -0.55), Vector3(0.26, 0.50, -0.35),
		Vector3(0.49, 0.88, 0.31), Vector3(0.91, 0.81, 1.58),
		Vector3(0.48, 0.41, 1.19), Vector3(0.35, 0.13, 0.63),
		Vector3(0.20, -0.12, 0.21)], 0.37, _joint, _steel, 0.42)
	Armor.panel(pivot, PackedVector3Array([
		Vector3(side * 0.03, 0.38, -0.44), Vector3(side * 0.36, 0.47, -0.31),
		Vector3(side * 0.64, 0.84, 0.33), Vector3(side * 0.94, 0.81, 1.62),
		Vector3(side * 0.23, 0.57, 0.88), Vector3(side * 0.06, 0.47, 0.25),
	]), Vector3(0, 1, -0.10), 0.20, _plate, _cut, _motion_lamps[LightZone.BACK], 0.53)
	for i in 5:
		var z := -0.12 + i * 0.18
		var at := Vector3(side * (0.46 + i * 0.037), 0.34 + i * 0.040, z)
		_line(pivot, at, at + Vector3(side * 0.03, 0.05, 0.095), 0.05, _charge_lights[i])


func _build_tail() -> void:
	var parent := pelvis
	var next := Vector3(0, 0.31, 1.95)
	for i in 9:
		var ratio := float(i) / 8.0
		var height := lerpf(0.55, 0.095, ratio)
		var width := lerpf(0.70, 0.15, ratio)
		var length := lerpf(0.78, 0.53, ratio)
		var segment := Kit.pivot(parent, next, "Tail%02d" % (i + 1))
		segment.rotation_degrees.x = [12.0, 6.0, -5.0, -6.0, -6.0, -7.0, -8.0, -5.0, -3.0][i]
		tail.append(segment)
		_bearing(segment, Vector3(0, 0, -0.01), Vector3.BACK, width * 0.75, 0.34, _steel)
		_hull(segment, [[-0.08, width * 0.80, height * 0.74, 0], [0.21, width, height, 0.04],
			[length * 0.63, width * 0.92, height * 0.77, 0.02],
			[length - 0.07, width * 0.63, height * 0.60, 0.01]], _dark)
		for side: float in [-1.0, 1.0]:
			_side_panel(segment, side, [Vector3(width * 0.76, height * 0.60, 0.06),
				Vector3(width * 1.04, height * 0.45, length * 0.27),
				Vector3(width * 0.94, -height * 0.33, length * 0.39),
				Vector3(width * 0.65, -height * 0.52, length * 0.86),
				Vector3(width * 0.70, height * 0.48, length * 0.75)],
				lerpf(0.20, 0.08, ratio), _plate)
		_spine_plate(segment, length * 0.44, height * 0.83, width * 0.74, false,
			_motion_lamps[LightZone.TAIL_TIP if i >= 5 else LightZone.TAIL_ROOT])
		parent = segment
		next = Vector3(0, 0, length)
	tail_fin = Kit.pivot(parent, next * 0.72, "TailFin")
	for side: float in [-1.0, 1.0]:
		Armor.panel(tail_fin, PackedVector3Array([Vector3(side * 0.12, -0.02, -0.24),
			Vector3(side * 0.25, 0.02, 0.10), Vector3(side * 0.39, 0.27, 0.74),
			Vector3(side * 0.22, 0.26, 0.74), Vector3(side * 0.08, 0.08, 0.35)]),
			Vector3(side * 0.12, 1, 0), 0.16, _plate, _cut)
		_line(tail_fin, Vector3(side * 0.20, 0.206, 0.33), Vector3(side * 0.26, 0.23, 0.57),
			0.031, _motion_lamps[LightZone.TAIL_TIP])


func tail_contact_path() -> PackedVector3Array:
	var points := PackedVector3Array()
	for joint: Node3D in tail:
		points.append(joint.global_position)
	points.append(tail_fin.global_position)
	points.append(tail_fin.to_global(Vector3(0, 0.26, 0.74)))
	return points


func replay_nodes() -> Array:
	var nodes: Array = [self, chest, pelvis, neck, head, jaw]
	for leg: Dictionary in legs:
		nodes.append_array([leg["root"], leg["joint"], leg["distal"], leg["paw"]])
	nodes.append_array(tail)
	nodes.append(tail_fin)
	nodes.append_array(emitters)
	nodes.append_array(cannon.replay_nodes())
	return nodes


func set_motion_lights(charge: float, flash: float, burst: float, cannon_heat := 0.0,
		phase := 0.0, lamp_power := 1.0) -> void:
	var heating := clampf(charge, 0.0, 1.0)
	var white := Color("f1faff")
	var dormant := Color("101820")
	var amber_albedo := Color("ffaa55").darkened(0.55)
	var marker_power := smoothstep(0.32, 0.88, lamp_power)
	_amber.albedo_color = dormant.lerp(amber_albedo, marker_power)
	_amber.emission_energy_multiplier = 1.35 * marker_power
	for i in _charge_lights.size():
		var lamp := _charge_lights[i]
		var segment := clampf(charge * _charge_lights.size() - i, 0.0, 1.0)
		var lit := smoothstep(0.35 + i * 0.05, 0.74 + i * 0.05, lamp_power)
		lamp.albedo_color = dormant.lerp(amber_albedo, lit)
		lamp.emission_energy_multiplier = (lerpf(0.95, 7.4, segment) + burst * 7.0) * lit
		lamp.emission = Color("52c5ff").lerp(white, maxf(segment, burst))
	for i in _motion_lamps.size():
		var eyes := i == LightZone.EYES
		var base := Color("65e6ff") if eyes else Color("24cee7")
		var heated := base.lerp(white, maxf(heating, 0.64 * phase))
		var warning := Color("ff2417") if eyes else Color("ff311d")
		var onset := float(i) * 0.116
		var wave := smoothstep(onset, onset + 0.18, cannon_heat)
		var lamp := _motion_lamps[i]
		var start := float(LightZone.EYES - i) * 0.083
		var lit := smoothstep(start, start + 0.40, lamp_power)
		lamp.albedo_color = dormant.lerp(heated.lerp(warning, wave).darkened(0.55), lit)
		lamp.emission = heated.lerp(warning, flash * (1.0 if eyes else 0.93)).lerp(white, burst).lerp(warning, wave)
		var energy := (2.6 if eyes else 2.15) + 3.0 * heating
		lamp.emission_energy_multiplier = lerpf(energy, 4.5 if eyes else 4.1, flash) + burst * (7.0 if eyes else 9.0)
		lamp.emission_energy_multiplier = (lamp.emission_energy_multiplier + wave * 1.7) * lit


func set_jaw_open(amount: float) -> void:
	jaw.rotation.x = lerpf(deg_to_rad(-12.0), deg_to_rad(-34.0), clampf(amount, 0.0, 1.0))


func _add_actuator(mount: Node3D, next: Node3D, start: Vector3, end: Vector3, radius: float) -> void:
	_actuators.append({
		"start": Kit.pivot(mount, start, "CylinderAnchor"),
		"end": Kit.pivot(next, end, "RodAnchor"),
		"barrel": _unit_cylinder(mount, radius, _joint),
		"rod": _unit_cylinder(mount, radius * 0.54, _cut),
	})


func update_actuators() -> void:
	for actuator in _actuators:
		var barrel: MeshInstance3D = actuator["barrel"]
		var rod: MeshInstance3D = actuator["rod"]
		var base: Vector3 = barrel.get_parent().to_local(actuator["start"].global_position)
		var end: Vector3 = barrel.get_parent().to_local(actuator["end"].global_position)
		var split := base.lerp(end, 0.60)
		_set_cylinder(barrel, base, split)
		_set_cylinder(rod, split, end)


func _hull(parent: Node3D, profiles: Array, material: Material, dorsal_opening := Vector2i.ZERO) -> void:
	var rings := []
	for profile in profiles:
		rings.append([profile[0], profile[1], profile[2], 0.0, -profile[3]])
	Kit.add(parent, Loft.loft(rings, dorsal_opening), material, Vector3.ZERO, Vector3(90, 0, 0))


func _side_panel(parent: Node3D, side: float, points: Array[Vector3], depth: float,
		face: Material, insert: Material = null, insert_margin := 0.36) -> void:
	var mirrored := PackedVector3Array()
	for point in points:
		mirrored.append(Vector3(side * point.x, point.y, point.z))
	Armor.panel(parent, mirrored, Vector3(side, 0, 0), depth, face, _cut, insert, insert_margin)


func _bearing(parent: Node3D, at: Vector3, axis: Vector3, radius: float, depth: float, mat: Material) -> void:
	_line(parent, at - axis * depth * 0.5, at + axis * depth * 0.5, radius, mat)


func _unit_cylinder(parent: Node3D, radius: float, mat: Material, tip := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 0
	mesh.bottom_radius = radius
	mesh.top_radius = radius if tip < 0.0 else tip
	return Kit.add(parent, mesh, mat)


func _line(parent: Node3D, start: Vector3, end: Vector3, radius: float, mat: Material, tip := -1.0) -> void:
	_set_cylinder(_unit_cylinder(parent, radius, mat, tip), start, end)


func _set_cylinder(mesh: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var delta := end - start
	var direction := delta.normalized()
	var reference := Vector3.BACK if absf(direction.dot(Vector3.UP)) > 0.94 else Vector3.UP
	var x := direction.cross(reference).normalized()
	mesh.transform = Transform3D(Basis(x, delta, x.cross(direction)), (start + end) * 0.5)

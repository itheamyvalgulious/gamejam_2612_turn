extends Node3D
## Model front is local -Z. Travel and aiming have separate pivots.

const MeshKit = preload("res://src/vesper/mesh_kit.gd")
const Materials = preload("res://src/vesper/materials.gd")
const Casing = preload("res://src/geometry/armor_panel.gd")
const Shell = preload("res://src/geometry/loft_shell.gd")
const WHEEL_RADIUS := 1.32
const AXLE_HEIGHT := WHEEL_RADIUS
const UPPER_LINK := 1.00
const LOWER_LINK := 1.04

var wheel_frame: Node3D
var wheel: Node3D
var turret: Node3D
var shot_origin: Marker3D
var intercept_origin: Marker3D
var is_attacking := false

var _shutters: Array[Node3D] = []
var _supports: Array[Dictionary] = []
var _charge: Node3D
var _launch_light: OmniLight3D
var _armor: StandardMaterial3D
var _edge: StandardMaterial3D
var _inset: StandardMaterial3D
var _accent: StandardMaterial3D
var _purple: StandardMaterial3D
var _cyan: StandardMaterial3D


func _ready() -> void:
	_armor = Materials.armor().duplicate()
	_armor.albedo_color = Color("77808a")
	_edge = Materials.armor_edge().duplicate()
	_edge.albedo_color = Color("aeb8bb")
	_inset = Materials.armor_shadow().duplicate()
	_inset.albedo_color = Color("3c454f")
	_accent = Materials.paint().duplicate()
	_accent.albedo_color = Color("482b65")
	_purple = Materials.emissive(Color("9759f3"), 3.2)
	_cyan = Materials.emissive(Color("6adafb"), 2.1)
	_build_wheel()
	_build_suspension()
	_build_turret()
	set_deployment(0.0)


func set_deployment(amount: float) -> void:
	var pose := clampf(amount, 0.0, 1.0)
	var opening := smoothstep(0.27, 0.94, pose)
	for shutter in _shutters:
		var side: float = shutter.get_meta(&"side")
		shutter.position.x = side * (0.11 + 0.17 * opening)
		shutter.rotation.y = side * opening * 0.23
	for support in _supports:
		_place_support(support, smoothstep(0.0, 0.78, pose))
	turret.position.y = 2.88 - 0.14 * pose
	_charge.visible = opening > 0.55
	_charge.scale = Vector3.ONE * lerpf(0.48, 1.0, opening)
	_launch_light.light_energy = opening * 0.72
	_launch_light.light_color = Color("b17efa")


func set_attack_charge(power: float, heavy: bool) -> void:
	_charge.visible = power > 0.0 and not heavy
	_charge.scale = Vector3.ONE * lerpf(0.38, 1.0, power)
	_launch_light.light_color = Color("ff7137") if heavy else Color("b17efa")
	_launch_light.light_energy = power * (2.2 if heavy else 0.72)


func in_hit_window() -> bool:
	return false


func replay_nodes() -> Array:
	var nodes: Array = [self, wheel_frame, wheel, turret]
	for shutter in _shutters:
		nodes.append(shutter)
	for support: Dictionary in _supports:
		nodes.append_array([support["arm"], support["rail"], support["shoe"]])
	return nodes


func _build_wheel() -> void:
	wheel_frame = MeshKit.pivot(self, Vector3.ZERO, "WheelHeading")
	wheel = MeshKit.pivot(wheel_frame, Vector3.UP * AXLE_HEIGHT, "RollingWheel")
	_build_airless_tire()
	for side: float in [-1.0, 1.0]:
		_build_wheel_face(side)


func _build_airless_tire() -> void:
	var tire := MeshKit.pivot(wheel, Vector3.ZERO, "AirlessTire")
	var shoulder := Materials.frame_light().duplicate() as StandardMaterial3D
	shoulder.albedo_color = Color("4b5266")
	shoulder.metallic = 0.56
	shoulder.roughness = 0.42
	# The open lattice carries the drive surface and its optical channels.
	var shear_band: Array[Vector2] = [
		Vector2(-0.365, 1.227), Vector2(-0.411, 1.243), Vector2(-0.341, 1.254),
		Vector2(-0.278, 1.255), Vector2(-0.104, 1.266), Vector2(0.104, 1.266),
		Vector2(0.278, 1.255), Vector2(0.341, 1.254), Vector2(0.411, 1.243),
		Vector2(0.365, 1.227), Vector2(-0.365, 1.227),
	]
	MeshKit.add(tire, _wheel_shell(shear_band, 96), Materials.frame())
	const CELL_COUNT := 20
	var pitch := TAU / CELL_COUNT
	var cell_guide := Materials.emissive(Color("6f62fd"), 1.75)
	for side: float in [-1.0, 1.0]:
		_build_tire_web(tire, side, CELL_COUNT, shoulder)
		var bead := Vector3.RIGHT * side
		_ring(tire, bead * 0.416, 1.064, 1.091, _inset, Vector3(0, 0, 90))
		_ring(tire, bead * 0.389, 1.256, 1.279, shoulder, Vector3(0, 0, 90))
		_ring(tire, bead * 0.225, 1.125, 1.174, Materials.frame(), Vector3(0, 0, 90))
		for i in CELL_COUNT:
			var angle := pitch * i
			if i % 5 != 4:
				_wheel_strip(tire, 0.254, side, 1.138, 1.163, angle - pitch * 0.32, pitch * 0.61, cell_guide)
	for i in CELL_COUNT:
		var cross_pin := _radial((float(i) + 0.5) * pitch, 1.149)
		_rod(tire, cross_pin - Vector3.RIGHT * 0.382, cross_pin + Vector3.RIGHT * 0.382, 0.026, _inset)
	_build_drive_surface(tire, shoulder)


func _build_tire_web(tire: Node3D, side: float, cells: int, shoulder: Material) -> void:
	# Vector2 stores the angle within a cell and the radius. The hexagonal opening has depth.
	var cell := PackedVector2Array([
		Vector2(-0.53, 1.149), Vector2(-0.35, 1.018), Vector2(0.34, 1.018),
		Vector2(0.53, 1.149), Vector2(0.30, 1.257), Vector2(-0.30, 1.257),
	])
	var vent := PackedVector2Array([
		Vector2(-0.35, 1.149), Vector2(-0.224, 1.091), Vector2(0.205, 1.091),
		Vector2(0.365, 1.149), Vector2(0.203, 1.217), Vector2(-0.184, 1.217),
	])
	var web := SurfaceTool.new()
	web.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pitch := TAU / cells
	var face := Vector3.RIGHT * side
	for index in cells:
		var angle := pitch * index
		var center := _radial(angle, 1.153)
		for i in cell.size():
			var next := (i + 1) % cell.size()
			var outer_a := _tire_web_point(cell[i], side, angle, pitch, 0.0)
			var outer_b := _tire_web_point(cell[next], side, angle, pitch, 0.0)
			var lip_a := _tire_web_point(vent[i], side, angle, pitch, 0.0)
			var lip_b := _tire_web_point(vent[next], side, angle, pitch, 0.0)
			var floor_a := _tire_web_point(vent[i].lerp(Vector2(0, 1.153), 0.13), side, angle, pitch, 0.075)
			var floor_b := _tire_web_point(vent[next].lerp(Vector2(0, 1.153), 0.13), side, angle, pitch, 0.075)
			Shell.tri(web, outer_a, outer_b, lip_b, face)
			Shell.tri(web, outer_a, lip_b, lip_a, face)
			var inward := (center - (lip_a + lip_b) * 0.5).slide(face).normalized()
			Shell.tri(walls, lip_a, lip_b, floor_b, inward)
			Shell.tri(walls, lip_a, floor_b, floor_a, inward)
	MeshKit.add(tire, web.commit(), shoulder)
	MeshKit.add(tire, walls.commit(), _inset)


func _tire_web_point(section: Vector2, side: float, angle: float, pitch: float, setback: float) -> Vector3:
	var width := lerpf(0.408, 0.437, inverse_lerp(1.018, 1.257, section.y)) - setback
	return Vector3.RIGHT * (width * side) + _radial(angle + section.x * pitch, section.y)


func _build_drive_surface(tire: Node3D, shoulder: Material) -> void:
	var ceramic := Materials.frame_light().duplicate() as StandardMaterial3D
	ceramic.albedo_color = Color("29344a")
	ceramic.metallic = 0.38
	ceramic.roughness = 0.46
	var outer_plate := ceramic.duplicate() as StandardMaterial3D
	outer_plate.albedo_color = Color("3b4055")
	var panel_insert := ceramic.duplicate() as StandardMaterial3D
	panel_insert.albedo_color = Color("151e31")
	panel_insert.roughness = 0.35
	var center_light := Materials.emissive(Color("68d5fa"), 2.5)
	var outer_light := Materials.emissive(Color("9b5aff"), 2.65)
	_build_drive_channel(tire, 0.0, 1.273, 0.025, center_light)
	for side: float in [-1.0, 1.0]:
		_build_drive_channel(tire, side * 0.276, 1.265, 0.036, outer_light)

	# The two strips of contact plates curve around the ring and leave the light channels recessed.
	var contact := PackedVector3Array([
		Vector3(0.042, 0.0, -0.193), Vector3(0.166, 0.0, -0.210),
		Vector3(0.246, -0.008, -0.128), Vector3(0.245, -0.008, 0.149),
		Vector3(0.185, 0.0, 0.205), Vector3(0.050, 0.0, 0.178),
		Vector3(0.031, 0.0, 0.055), Vector3(0.031, 0.0, -0.131),
	])
	var shoulder_plate := PackedVector3Array([
		Vector3(0.310, -0.014, -0.171), Vector3(0.380, -0.024, -0.194),
		Vector3(0.429, -0.056, -0.115), Vector3(0.429, -0.056, 0.133),
		Vector3(0.384, -0.026, 0.183), Vector3(0.308, -0.014, 0.145),
	])
	const PLATE_COUNT := 18
	var pitch := TAU / PLATE_COUNT
	var seat_radius := WHEEL_RADIUS - 0.025
	var ceramic_tab := MeshKit.slab(0.068, 0.053, 0.008, 0.003)
	var tab_light := Materials.emissive(Color("a586ed"), 1.8)
	for i in PLATE_COUNT:
		var angle := pitch * i
		for side: float in [-1.0, 1.0]:
			var offset := angle + side * pitch * 0.075
			var sector := MeshKit.pivot(tire, _radial(offset, seat_radius))
			sector.rotation.x = offset
			Casing.panel(sector, _curved_drive_plate(contact, side, seat_radius), Vector3.UP,
				0.044, ceramic, shoulder, panel_insert, 0.47)
			Casing.panel(sector, _curved_drive_plate(shoulder_plate, side, seat_radius), Vector3.UP,
				0.045, outer_plate, _inset)
			if i % 3 == 0:
				MeshKit.add(sector, ceramic_tab, tab_light, Vector3(side * 0.218, 0.016, 0.075),
					Vector3(0.5, side * 19.0, 0))


func _curved_drive_plate(outline: PackedVector3Array, side: float, radius: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for point in outline:
		var tangency := sqrt(radius * radius - point.z * point.z) - radius
		points.append(Vector3(point.x * side, point.y + tangency, point.z))
	return points


func _build_drive_channel(tire: Node3D, axial: float, radius: float, width: float, lamp: Material) -> void:
	var base: Array[Vector2] = [
		Vector2(axial - width * 0.96, radius - 0.013), Vector2(axial - width * 0.82, radius),
		Vector2(axial + width * 0.82, radius), Vector2(axial + width * 0.96, radius - 0.013),
	]
	MeshKit.add(tire, _wheel_shell(base, 96), Materials.frame())
	var glass: Array[Vector2] = [
		Vector2(axial - width * 0.53, radius + 0.001), Vector2(axial - width * 0.42, radius + 0.005),
		Vector2(axial + width * 0.42, radius + 0.005), Vector2(axial + width * 0.53, radius + 0.001),
	]
	MeshKit.add(tire, _wheel_shell(glass, 96), lamp)


func _build_wheel_face(side: float) -> void:
	var axle := Vector3(0, 0, 90)
	var outward := Vector3.RIGHT * side
	var driver := Materials.emissive(Color("7250fc"), 1.9)
	var status := Materials.emissive(Color("f59352"), 1.15)
	var alloy := Materials.frame_light().duplicate() as StandardMaterial3D
	alloy.albedo_color = Color("47576d")
	alloy.metallic = 0.72
	alloy.roughness = 0.38
	_disk(wheel, outward * 0.259, 0.839, 0.106, Materials.frame(), axle, 48)
	_ring(wheel, outward * 0.306, 0.768, 0.813, _inset, axle)
	var rim_profile: Array[Vector2] = [
		Vector2(-0.043, 0.843), Vector2(-0.046, 0.865), Vector2(-0.046, 1.014),
		Vector2(-0.026, 1.031), Vector2(0.026, 1.031), Vector2(0.044, 1.013),
		Vector2(0.044, 0.865), Vector2(0.021, 0.843), Vector2(-0.043, 0.843),
	]
	MeshKit.add(wheel, _wheel_shell(rim_profile, 72), alloy, outward * 0.385)
	_ring(wheel, outward * 0.440, 1.012, 1.043, _edge, axle)
	_ring(wheel, outward * 0.451, 1.048, 1.068, _inset, axle)

	# Each armoured sector leaves an exposed motor winding between its edges.
	var plate := PackedVector3Array([
		outward * 0.390 + Vector3(0, 0.27, -0.10),
		outward * 0.372 + Vector3(0, 0.43, -0.24),
		outward * 0.394 + Vector3(0, 0.70, -0.24),
		outward * 0.412 + Vector3(0, 0.889, -0.095),
		outward * 0.414 + Vector3(0, 0.905, 0.119),
		outward * 0.401 + Vector3(0, 0.805, 0.170),
		outward * 0.380 + Vector3(0, 0.476, 0.135),
		outward * 0.386 + Vector3(0, 0.290, 0.08),
	])
	for i in 6:
		var angle := TAU * float(i) / 6.0
		var sector := MeshKit.pivot(wheel, Vector3.ZERO)
		sector.rotation.x = angle
		Casing.panel(sector, plate, outward, 0.066, alloy, _edge, _inset, 0.41)
		var copper := Materials.copper()
		for winding in 4:
			var row := 0.574 + winding * 0.066
			_rod(sector, outward * 0.374 + Vector3(0, row, 0.172),
				outward * 0.374 + Vector3(0, row + 0.016, 0.310 + winding * 0.022),
				0.027, copper)
		for radius: float in [0.486, 0.768]:
			_disk(sector, outward * 0.432 + _radial(-0.08, radius),
				0.023, 0.027, _edge, axle, 6)
		_wheel_strip(sector, 0.433, side, 0.885, 0.972, -0.265, 0.535, Materials.frame())
		_wheel_strip(sector, 0.439, side, 0.910, 0.943, -0.234, 0.440, driver)
		_wheel_strip(sector, 0.443, side, 0.960, 0.985, 0.29, 0.105, status if i % 3 == 0 else alloy)
		for angle_offset: float in [-0.30, 0.25]:
			_disk(sector, outward * 0.436 + _radial(angle_offset, 0.986),
				0.030, 0.045, _inset, axle, 6)
	_disk(wheel, outward * 0.350, 0.364, 0.179, _inset, axle, 12)
	_ring(wheel, outward * 0.446, 0.260, 0.290, _accent, axle)
	for i in 6:
		_wheel_strip(wheel, 0.461, side, 0.286, 0.302, i * TAU / 6.0 + 0.08, 0.36, driver)
	_disk(wheel, outward * 0.483, 0.224, 0.20, alloy, axle, 16)
	_disk(wheel, outward * 0.603, 0.119, 0.064, Materials.frame(), axle, 8)


func _wheel_strip(parent: Node3D, axial: float, side: float, inner: float, outer: float,
		start: float, sweep: float, mat: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outward := Vector3.RIGHT * side
	var base := outward * axial
	const SEGMENTS := 10
	for index in SEGMENTS:
		var angle := start + sweep * float(index) / SEGMENTS
		var next := start + sweep * float(index + 1) / SEGMENTS
		var a := base + _radial(angle, inner)
		var b := base + _radial(angle, outer)
		var c := base + _radial(next, outer)
		var d := base + _radial(next, inner)
		Shell.tri(surface, a, b, c, outward)
		Shell.tri(surface, a, c, d, outward)
	MeshKit.add(parent, surface.commit(), mat)


func _build_suspension() -> void:
	var frame := wheel_frame
	_plate(frame, Vector3(0, 2.54, 0.08), 1.30, 1.44, 0.28, _inset)
	_disk(frame, Vector3(0, 2.71, 0.075), 0.59, 0.22, Materials.frame_light())
	_ring(frame, Vector3(0, 2.76, 0.075), 0.56, 0.61, _edge)
	for side: float in [-1.0, 1.0]:
		var name_suffix := "R" if side > 0 else "L"
		var axle := Vector3(side * 0.64, AXLE_HEIGHT, 0)
		var mount := Vector3(side * 0.647, 2.52, 0.13)
		_link(frame, axle, mount, 0.27, 0.17, Materials.frame())
		var out := Vector3.RIGHT * side
		_disk(frame, axle, 0.28, 0.14, _inset, Vector3(0, 0, 90), 10)
		_disk(frame, axle + out * 0.083, 0.19, 0.085, _armor, Vector3(0, 0, 90), 10)
		_ring(frame, axle + out * 0.131, 0.105, 0.135, _edge, Vector3(0, 0, 90))
		_disk(frame, axle + out * 0.14, 0.075, 0.03, _inset, Vector3(0, 0, 90), 6)
		_rod(frame, Vector3(side * 0.555, 1.49, -0.21), Vector3(side * 0.555, 2.24, 0.034), 0.092, _inset)
		_rod(frame, Vector3(side * 0.555, 2.11, -0.01), Vector3(side * 0.555, 2.62, 0.15), 0.048, _edge)
		_side_panel(frame, side, [
			Vector3(0.62, 1.50, -0.22), Vector3(0.69, 1.64, -0.40),
			Vector3(0.72, 2.29, -0.36), Vector3(0.67, 2.58, -0.02),
			Vector3(0.67, 2.42, 0.66), Vector3(0.72, 2.14, 0.72),
			Vector3(0.69, 1.98, 0.29), Vector3(0.63, 1.67, 0.23),
		], 0.15, _armor, Materials.frame_light())
		var vent := MeshKit.slab(0.12, 0.052, 0.022, 0.007)
		for i in 4:
			MeshKit.add(frame, vent, Materials.frame(), Vector3(side * 0.786, 2.23 - i * 0.080, 0.10),
				Vector3(-24, 0, 90))
		_link(frame, Vector3(side * 0.778, 2.25, -0.28), Vector3(side * 0.754, 2.43, -0.12),
			0.042, 0.043, _purple)
		_build_support(side, name_suffix)


func _build_support(side: float, suffix: String) -> void:
	var root := MeshKit.pivot(wheel_frame, Vector3(side * 0.69, 2.02, 0.38), "BraceMount" + suffix)
	var arm := MeshKit.pivot(root, Vector3.ZERO, "BraceArm")
	var rail := MeshKit.pivot(root, Vector3.ZERO, "BraceRail")
	var shoe := MeshKit.pivot(root, Vector3.ZERO, "BraceShoe")
	_disk(root, Vector3(side * 0.03, 0, 0), 0.148, 0.165, Materials.frame(), Vector3(0, 0, 90), 12)
	_disk(root, Vector3(side * 0.128, 0, 0), 0.105, 0.067, _edge, Vector3(0, 0, 90), 8)
	_plate(arm, Vector3.UP * (UPPER_LINK * 0.48), 0.246, 0.286, UPPER_LINK * 0.95, _inset, 0.038)
	_plate(arm, Vector3(side * 0.071, UPPER_LINK * 0.49, 0), 0.158, 0.248, UPPER_LINK * 0.79, _armor, 0.031)
	_rod(arm, Vector3(0, 0.17, -0.163), Vector3(0, 0.69, -0.163), 0.056, Materials.frame_light())
	_rod(arm, Vector3(0, 0.62, -0.163), Vector3(0, 0.91, -0.163), 0.034, _edge)
	_disk(arm, Vector3(0, UPPER_LINK, 0), 0.149, 0.327, _inset, Vector3(0, 0, 90), 12)
	_disk(arm, Vector3(side * 0.182, UPPER_LINK, 0), 0.100, 0.054, _edge, Vector3(0, 0, 90), 8)
	_plate(rail, Vector3.UP * (LOWER_LINK * 0.37), 0.15, 0.186, LOWER_LINK * 0.69, Materials.frame_light())
	_rod(rail, Vector3(0, 0.56, 0), Vector3(0, LOWER_LINK, 0), 0.050, _edge)
	_rod(rail, Vector3(side * 0.083, 0.18, 0.056), Vector3(side * 0.083, 0.68, 0.056),
		0.025, Materials.copper())
	for level in 3:
		_plate(rail, Vector3(side * 0.075, 0.31 + level * 0.087, -0.018),
			0.036, 0.115, 0.036, _inset)
	_disk(shoe, Vector3.ZERO, 0.114, 0.223, _inset, Vector3(0, 0, 90), 12)
	_plate(shoe, Vector3(0, -0.115, -0.06), 0.375, 0.54, 0.168, _armor, 0.035)
	for offset: float in [-0.100, 0.100]:
		_plate(shoe, Vector3(offset, -0.177, -0.16), 0.108, 0.56, 0.046, Materials.rubber())
	_supports.append({"root": root, "arm": arm, "rail": rail, "shoe": shoe, "side": side})


func _place_support(support: Dictionary, amount: float) -> void:
	var side: float = support["side"]
	var arm: Node3D = support["arm"]
	var rail: Node3D = support["rail"]
	var shoe: Node3D = support["shoe"]
	var closed := Vector3(side * 0.219, -0.12, 0.70)
	var open := Vector3(side * 0.786, -1.82, 0.17)
	var end := closed.lerp(open, amount)
	var span := end.length()
	var axis := end / span
	# The two links keep their lengths from the tucked pose to floor contact.
	var along := (UPPER_LINK ** 2 - LOWER_LINK ** 2 + span ** 2) / (2.0 * span)
	var pole := Vector3(side * 0.57, -1, 0.12).slide(axis).normalized()
	var knee := axis * along + pole * sqrt(maxf(0.0, UPPER_LINK ** 2 - along ** 2))
	arm.basis = _brace_basis(knee)
	rail.position = knee
	rail.basis = _brace_basis(end - knee)
	shoe.position = end
	shoe.rotation_degrees = Vector3(lerpf(-65.0, 0.0, amount), side * -13.0 * amount, 0)


func _build_turret() -> void:
	turret = MeshKit.pivot(self, Vector3(0, 2.88, 0), "AimingRing")
	var hull := turret
	_plate(hull, Vector3(0, 0.035, -0.16), 1.33, 2.03, 0.35, Materials.frame(), 0.072)
	_plate(hull, Vector3(0, 0.24, -0.25), 1.35, 1.73, 0.425, _inset, 0.081)
	_plate(hull, Vector3(0, 0.37, 0.38), 1.32, 1.22, 0.53, Materials.frame_light(), 0.091)
	# The low rear casing overhangs the tire, counterbalancing the optical pod.
	Casing.panel(hull, PackedVector3Array([
		Vector3(-0.65, 0.62, 0.01), Vector3(-0.39, 0.62, -0.21), Vector3(0.39, 0.62, -0.21),
		Vector3(0.65, 0.62, 0.01), Vector3(0.61, 0.51, 0.90), Vector3(0.38, 0.45, 1.14),
		Vector3(-0.38, 0.45, 1.14), Vector3(-0.61, 0.51, 0.90),
	]), Vector3.UP, 0.17, _armor, _edge, _inset, 0.40)
	_plate(hull, Vector3(0, 0.667, 0.32), 0.52, 0.55, 0.125, _accent, 0.022)
	for i in 6:
		_plate(hull, Vector3(0, 0.721, 0.15 + 0.075 * i), 0.37, 0.026, 0.034,
			_edge if i == 0 or i == 5 else Materials.frame())
	_disk(hull, Vector3(0, 0.315, 1.018), 0.355, 0.235, _inset, Vector3(90, 0, 0), 6)
	_disk(hull, Vector3(0, 0.315, 1.154), 0.285, 0.085, _edge, Vector3(90, 0, 0), 6)
	_disk(hull, Vector3(0, 0.315, 1.204), 0.228, 0.055, Materials.frame(), Vector3(90, 0, 0), 6)
	_ring(hull, Vector3(0, 0.315, 1.241), 0.134, 0.162, _purple, Vector3(90, 0, 0))
	_disk(hull, Vector3(0, 0.315, 1.220), 0.116, 0.052, _accent, Vector3(90, 0, 0), 12)
	for side: float in [-1.0, 1.0]:
		_build_body_side(hull, side)
	_build_face(hull)


func _build_body_side(hull: Node3D, side: float) -> void:
	var outer := Vector3.RIGHT * side
	_side_panel(hull, side, [
		Vector3(0.54, 0.53, -0.67), Vector3(0.64, 0.54, -0.28),
		Vector3(0.79, 0.48, 0.14), Vector3(0.74, 0.22, 0.50),
		Vector3(0.69, 0.10, 0.13), Vector3(0.59, 0.11, -0.57), Vector3(0.48, 0.30, -0.90),
	], 0.128, _armor, Materials.frame_light(), 0.40)
	_side_panel(hull, side, [
		Vector3(0.69, 0.49, 0.37), Vector3(0.65, 0.49, 0.79), Vector3(0.54, 0.36, 1.04),
		Vector3(0.54, 0.17, 1.02), Vector3(0.70, 0.12, 0.77), Vector3(0.77, 0.19, 0.51),
	], 0.09, _inset, _accent)
	var port := Vector3(side * 0.725, 0.327, 0.727)
	_disk(hull, port, 0.123, 0.079, Materials.frame(), Vector3(0, 0, 90), 10)
	_ring(hull, port + outer * 0.054, 0.066, 0.085, _edge, Vector3(0, 0, 90))
	_disk(hull, port + outer * 0.065, 0.041, 0.02, _purple, Vector3(0, 0, 90), 8)
	for i in 4:
		var rib := Vector3(side * (0.682 + i * 0.015), 0.18 + i * 0.060, -0.178)
		_rod(hull, rib - Vector3.BACK * 0.28, rib + Vector3.BACK * 0.32, 0.024,
			Materials.copper() if i == 0 else Materials.frame())
	_link(hull, Vector3(side * 0.566, 0.475, -0.70), Vector3(side * 0.655, 0.474, -0.42),
		0.038, 0.044, _purple)
	var heel := Vector3(side * 0.42, 0.10, 1.10)
	_rod(hull, heel, heel + Vector3(side * 0.17, 0.035, -0.29), 0.035, Materials.copper())
	_disk(hull, heel + Vector3(side * 0.14, 0.027, -0.24), 0.054, 0.060, Materials.frame(),
		Vector3(70, 0, -13 * side), 8)
	for mark: Vector3 in [Vector3(0.596, 0.40, -0.65), Vector3(0.730, 0.40, 0.43), Vector3(0.641, 0.27, 0.97)]:
		_disk(hull, Vector3(side * mark.x, mark.y, mark.z), 0.034, 0.06, _edge, Vector3(0, 0, 90), 6)


func _build_face(hull: Node3D) -> void:
	var eye := Vector3(0, 0.382, -1.095)
	var front_axis := Vector3(90, 0, 0)
	_disk(hull, eye, 0.338, 0.25, Materials.frame(), front_axis, 10)
	_disk(hull, eye + Vector3.FORWARD * 0.143, 0.273, 0.107, _edge, front_axis, 12)
	_disk(hull, eye + Vector3.FORWARD * 0.204, 0.221, 0.087, _inset, front_axis, 16)
	_ring(hull, eye + Vector3.FORWARD * 0.251, 0.180, 0.215, _purple, front_axis)
	_disk(hull, eye + Vector3.FORWARD * 0.254, 0.180, 0.08, Materials.glass(), front_axis, 32)
	_disk(hull, eye + Vector3.FORWARD * 0.298, 0.099, 0.019, _accent, front_axis, 16)
	_ring(hull, eye + Vector3.FORWARD * 0.311, 0.059, 0.072, _cyan, front_axis)
	_disk(hull, eye + Vector3.FORWARD * 0.318, 0.039, 0.013, _purple, front_axis, 12)
	for i in 6:
		var angle := TAU * float(i) / 6.0
		_disk(hull, eye + Vector3(cos(angle) * 0.245, sin(angle) * 0.245, -0.21),
			0.021, 0.021, _inset, front_axis, 6)
	Casing.panel(hull, PackedVector3Array([
		Vector3(-0.57, 0.635, -0.89), Vector3(-0.395, 0.722, -1.19), Vector3(0.395, 0.722, -1.19),
		Vector3(0.57, 0.635, -0.89), Vector3(0.51, 0.671, -0.53), Vector3(-0.51, 0.671, -0.53),
	]), Vector3.UP, 0.16, _armor, _edge, _inset, 0.41)
	for side: float in [-1.0, 1.0]:
		_side_panel(hull, side, [
			Vector3(0.22, 0.651, -1.153), Vector3(0.41, 0.690, -1.102),
			Vector3(0.51, 0.552, -0.930), Vector3(0.460, 0.357, -1.048),
			Vector3(0.327, 0.43, -1.127),
		], 0.066, _inset, _armor, 0.51)
	var chamber := MeshKit.pivot(hull, Vector3(0, -0.024, -1.11), "LaunchChamber")
	_plate(chamber, Vector3(0, -0.046, 0.095), 0.584, 0.515, 0.386, Materials.frame(), 0.047)
	_plate(chamber, Vector3(0, -0.215, -0.07), 0.68, 0.54, 0.142, _inset, 0.031)
	for side: float in [-1.0, 1.0]:
		_plate(chamber, Vector3(side * 0.172, -0.034, -0.143), 0.058, 0.36, 0.256, _accent, 0.022)
		_plate(chamber, Vector3(side * 0.188, -0.04, -0.316), 0.044, 0.036, 0.21, _purple)
		var shutter := MeshKit.pivot(chamber, Vector3(side * 0.11, 0, -0.260), "LaunchShutter")
		shutter.set_meta(&"side", side)
		_shutters.append(shutter)
		Casing.panel(shutter, PackedVector3Array([
			Vector3(side * -0.095, 0.15, 0.008), Vector3(side * 0.087, 0.14, 0.034),
			Vector3(side * 0.140, 0.066, 0.052), Vector3(side * 0.126, -0.135, 0.057),
			Vector3(side * 0.061, -0.195, 0.032), Vector3(side * -0.092, -0.168, 0.010),
		]), Vector3.FORWARD, 0.096, _armor, _edge)
		_plate(shutter, Vector3(side * 0.043, -0.054, -0.05), 0.050, 0.024, 0.154, _inset)
	var side_emitter := Vector3(0.475, 0.174, -1.017)
	_disk(hull, side_emitter, 0.114, 0.28, _inset, front_axis, 10)
	_disk(hull, side_emitter + Vector3.FORWARD * 0.15, 0.095, 0.052, _edge, front_axis, 10)
	_disk(hull, side_emitter + Vector3.FORWARD * 0.19, 0.069, 0.019, Materials.frame(), front_axis, 8)
	_ring(hull, side_emitter + Vector3.FORWARD * 0.205, 0.048, 0.060, _cyan, front_axis)
	intercept_origin = Marker3D.new()
	intercept_origin.name = "InterceptMuzzle"
	intercept_origin.position = side_emitter + Vector3.FORWARD * 0.22
	hull.add_child(intercept_origin)
	shot_origin = Marker3D.new()
	shot_origin.name = "PrimaryMuzzle"
	shot_origin.position = Vector3(0, -0.068, -1.47)
	hull.add_child(shot_origin)
	_charge = MeshKit.pivot(shot_origin, Vector3(0, 0, 0.04), "LoadedBolt")
	MeshKit.add(_charge, MeshKit.gem(0.113, 3, 5), Materials.emissive(Color("b777ff"), 5.6),
		Vector3.FORWARD * 0.333, Vector3(90, 0, 0), Vector3(0.70, 2.25, 0.70))
	_rod(_charge, Vector3(0, 0, -0.315), Vector3(0, 0, 0.09), 0.033, _purple)
	_launch_light = OmniLight3D.new()
	_launch_light.position = Vector3.FORWARD * 0.27
	_launch_light.light_color = Color("b17efa")
	_launch_light.omni_range = 1.2
	shot_origin.add_child(_launch_light)


func _side_panel(parent: Node3D, side: float, outline: Array[Vector3], thickness: float,
		face: Material, inlay: Material, margin := 0.45) -> void:
	var points := PackedVector3Array()
	for point in outline:
		points.append(Vector3(side * point.x, point.y, point.z))
	Casing.panel(parent, points, Vector3.RIGHT * side, thickness, face, _edge, inlay, margin)


func _plate(parent: Node3D, at: Vector3, width: float, depth: float, height: float,
		mat: Material, bevel := 0.018) -> void:
	MeshKit.add(parent, MeshKit.slab(width, depth, height, bevel), mat, at)


func _disk(parent: Node3D, at: Vector3, radius: float, depth: float, mat: Material,
		rotation := Vector3.ZERO, sides := 32) -> void:
	MeshKit.add(parent, MeshKit.prism(sides, radius, radius * 0.94, depth), mat, at, rotation)


func _ring(parent: Node3D, at: Vector3, inner: float, outer: float, mat: Material,
		rotation := Vector3.ZERO) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 40
	mesh.ring_segments = 9
	MeshKit.add(parent, mesh, mat, at, rotation)


func _link(parent: Node3D, start: Vector3, end: Vector3, width: float, depth: float, mat: Material) -> void:
	var delta := end - start
	var part := MeshKit.add(parent, MeshKit.slab(width, depth, delta.length() + 0.035, 0.025),
		mat, (start + end) * 0.5)
	part.basis = _length_basis(delta)


func _rod(parent: Node3D, start: Vector3, end: Vector3, radius: float, mat: Material) -> void:
	var delta := end - start
	var part := MeshKit.add(parent, MeshKit.prism(12, radius, radius, delta.length()),
		mat, (start + end) * 0.5)
	part.basis = _length_basis(delta)


func _length_basis(delta: Vector3) -> Basis:
	var y := delta.normalized()
	var reference := Vector3.BACK if absf(y.z) < 0.90 else Vector3.UP
	var z := reference.slide(y).normalized()
	return Basis(y.cross(z), y, z)


func _brace_basis(delta: Vector3) -> Basis:
	var y := delta.normalized()
	var x := Vector3.RIGHT.slide(y).normalized()
	return Basis(x, y, x.cross(y))


func _radial(angle: float, radius: float) -> Vector3:
	return Vector3(0, cos(angle) * radius, sin(angle) * radius)


func _wheel_shell(profile: Array[Vector2], steps: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var p := profile[i]
		var q := profile[i + 1]
		var p_tangent := q - profile[maxi(0, i - 1)]
		var q_tangent := profile[mini(i + 2, profile.size() - 1)] - p
		var pn := Vector2(-p_tangent.y, p_tangent.x).normalized()
		var qn := Vector2(-q_tangent.y, q_tangent.x).normalized()
		for j in steps:
			var a := TAU * float(j) / float(steps)
			var b := TAU * float(j + 1) / float(steps)
			var p0 := Vector3(p.x, 0, 0) + _radial(a, p.y)
			var p1 := Vector3(p.x, 0, 0) + _radial(b, p.y)
			var q0 := Vector3(q.x, 0, 0) + _radial(a, q.y)
			var q1 := Vector3(q.x, 0, 0) + _radial(b, q.y)
			var np0 := Vector3(pn.x, 0, 0) + _radial(a, pn.y)
			var np1 := Vector3(pn.x, 0, 0) + _radial(b, pn.y)
			var nq0 := Vector3(qn.x, 0, 0) + _radial(a, qn.y)
			var nq1 := Vector3(qn.x, 0, 0) + _radial(b, qn.y)
			Shell.soft_tri(surface, p0, p1, q1, np0, np1, nq1)
			Shell.soft_tri(surface, p0, q1, q0, np0, nq1, nq0)
	return surface.commit()

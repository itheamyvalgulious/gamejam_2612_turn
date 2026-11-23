extends RefCounted
## Articulated fingers and a thumb with an independent base joint.

const MeshKit = preload("res://src/vesper/mesh_kit.gd")
const Shell = preload("res://src/enemies/duelist/duelist_shell.gd")
const Parts = preload("res://src/enemies/duelist/duelist_parts.gd")
const DIGITS := ["Index", "Middle", "Ring", "Little", "Thumb"]
const PALM_ORIGIN := Vector3(0, -0.030, 0)
const GRIP_CENTER := Vector3(0.006, -0.147, -0.066)
const GRIP_WIDTH := 0.078
const GRIP_DEPTH := 0.068
# Knuckle, two hinges and fingertip in sword space. Four fingers wrap the
# edge side of the hilt, and the thumb closes on the opposite face.
const GRIP_PATHS := [
	[Vector3(0.055, 0.046, -0.070), Vector3(-0.012, 0.046, -0.060),
		Vector3(-0.057, 0.046, -0.040), Vector3(-0.050, 0.045, 0.019)],
	[Vector3(0.046, 0.009, -0.070), Vector3(-0.020, 0.009, -0.061),
		Vector3(-0.059, 0.008, -0.034), Vector3(-0.048, 0.008, 0.023)],
	[Vector3(0.032, -0.028, -0.070), Vector3(-0.021, -0.028, -0.060),
		Vector3(-0.057, -0.028, -0.033), Vector3(-0.048, -0.028, 0.019)],
	[Vector3(0.024, -0.065, -0.070), Vector3(-0.021, -0.065, -0.057),
		Vector3(-0.055, -0.065, -0.036), Vector3(-0.048, -0.065, 0.012)],
	[Vector3(0.108, -0.017, -0.077), Vector3(0.071, 0.028, -0.051),
		Vector3(0.056, 0.061, -0.012), Vector3(0.051, 0.064, 0.021)],
]


static func sword_socket(cant_deg := 0.0) -> Transform3D:
	# +Y of the sword exits on the thumb side. The dull spine faces the wrist.
	var blade_axis := Vector3(0.85, -0.527, 0.0).normalized()
	var spine := Vector3.UP.slide(blade_axis).normalized()
	return Transform3D(Basis(Vector3.BACK, deg_to_rad(-cant_deg))
		* Basis(spine, blade_axis, spine.cross(blade_axis)), GRIP_CENTER)


static func build(wrist: Node3D, gripping: bool, materials: Dictionary) -> Array[Dictionary]:
	var palm := MeshKit.pivot(wrist, PALM_ORIGIN, "Palm")
	MeshKit.add(palm, Shell.loft([
		[-0.086, 0.078, 0.028, 0, 0.003], [-0.050, 0.075, 0.034, 0, 0.004],
		[-0.010, 0.061, 0.031, 0, 0.002], [0.024, 0.044, 0.025, 0, 0],
	]), materials["frame"])
	var back_plate := Vector3(0, -0.048, 0.028 if gripping else -0.028)
	MeshKit.add(palm, MeshKit.slab(0.118, 0.018, 0.065, 0.007), materials["steel"], back_plate)
	var socket := sword_socket()
	var fingers: Array[Dictionary] = []
	# The left support palm faces +Z and the right grip faces -Z.
	# Both wrist frames put the index and thumb on local +X.
	for i in DIGITS.size():
		var thumb: bool = DIGITS[i] == "Thumb"
		var x := 0.058 - i * 0.038
		var anchor := Vector3(x, -0.081 + absf(x) * 0.13, 0.004)
		var root_basis := Basis(Vector3.BACK, deg_to_rad((1.45 - float(i)) * 4.6))
		var length: float = [0.126, 0.141, 0.131, 0.111, 0.104][i]
		var proportions := [0.43, 0.32, 0.25]
		if thumb:
			anchor = Vector3(0.061, -0.013, 0.020)
			root_basis = Basis.from_euler(Vector3(0.40, 0.17, 0.12))
			if not gripping:
				# Recess the metacarpal into the palm and leave two links free.
				anchor = Vector3(0.053, -0.018, 0.018)
				root_basis = Basis.from_euler(Vector3(0.17, -0.05, 0.88))
				proportions = [0.49, 0.30, 0.21]
		var joints: Array[Node3D] = []
		var bases: Array[Basis] = []
		var closed_bases: Array[Basis] = []
		var previous_basis := Basis.IDENTITY
		var parent := palm
		if gripping:
			anchor = socket * GRIP_PATHS[i][0] - palm.position
		for link in 3:
			var size: float = length * proportions[link]
			if gripping:
				var segment: Vector3 = socket.basis * (GRIP_PATHS[i][link + 1] - GRIP_PATHS[i][link])
				size = segment.length()
				var up := -segment / size
				var hinge := socket.basis.y.slide(up).normalized()
				var closed_basis := Basis(hinge, up, hinge.cross(up))
				closed_bases.append(previous_basis.inverse() * closed_basis)
				previous_basis = closed_basis
			var radius := (0.0150 if not thumb else 0.017) * (1.0 - link * 0.16)
			var joint := MeshKit.pivot(parent, anchor, "%s%d" % [DIGITS[i], link + 1])
			joint.basis = root_basis if link == 0 else Basis.IDENTITY
			Parts.axle(joint, Vector3.ZERO, radius * 0.95, radius * 2.06, materials["frame"])
			MeshKit.add(joint, Shell.loft([
				[-size + 0.004, radius * 0.69, radius * 0.65, 0, 0],
				[-size * 0.75, radius * 0.98, radius * 0.82, 0.0, -0.002],
				[-size * 0.29, radius, radius * 0.89, 0.0, -0.002],
				[-0.004, radius * 0.81, radius * 0.72, 0, 0],
			]), materials["ceramic"] if link == 0 else materials["steel"])
			joints.append(joint)
			bases.append(joint.basis)
			parent = joint
			anchor = Vector3(0, -size, 0)
		fingers.append({"label": DIGITS[i], "joints": joints, "rest": bases, "closed": closed_bases,
			"thumb": thumb, "root_anchor": joints[0].position})
	wrist.set_meta(&"palm", palm)
	return fingers


static func curl(fingers: Array[Dictionary], amount: float, gripping: bool, cant_deg := 0.0) -> void:
	var grip_turn := Basis(Vector3.BACK, deg_to_rad(-cant_deg))
	var grip_center := GRIP_CENTER - PALM_ORIGIN
	for finger in fingers:
		var joints: Array[Node3D] = finger["joints"]
		var rest: Array[Basis] = finger["rest"]
		if gripping:
			var closed: Array[Basis] = finger["closed"]
			for index in joints.size():
				joints[index].basis = rest[index].slerp(closed[index], amount)
			joints[0].position = grip_center + grip_turn * ((finger["root_anchor"] as Vector3) - grip_center)
			joints[0].basis = grip_turn * joints[0].basis
		else:
			var bend := [-9.0, -14.0, -9.0] if finger["thumb"] else [-4.0, -8.0, -4.0]
			for index in joints.size():
				joints[index].basis = rest[index] * Basis(Vector3.RIGHT, deg_to_rad(bend[index] * amount))

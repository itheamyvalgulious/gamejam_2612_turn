extends RefCounted
## Faceted armor, recessed equipment and running lights. Each piece follows its existing joint.

const MeshKit = preload("res://src/vesper/mesh_kit.gd")
const Casing = preload("res://src/enemies/duelist/duelist_casing.gd")
const Parts = preload("res://src/enemies/duelist/duelist_parts.gd")


static func build_chest(torso: Node3D, mat: Dictionary) -> void:
	for side: float in [-1.0, 1.0]:
		var plate := PackedVector3Array([
			Vector3(0.094, 0.552, -0.335), Vector3(0.258, 0.550, -0.358),
			Vector3(0.444, 0.657, -0.314), Vector3(0.472, 0.785, -0.263),
			Vector3(0.348, 0.924, -0.256), Vector3(0.128, 0.906, -0.307),
			Vector3(0.086, 0.820, -0.337),
		])
		var outward := Vector3(0.24 * side, 0.08, -1).normalized()
		Casing.panel(torso, _mirror(plate, side), outward, 0.101, mat["ceramic"], mat["steel"])
		for j in 2:
			var point := Vector3(side * (0.217 + j * 0.075), 0.710 + j * 0.040, -0.403 + j * 0.023)
			_insert(torso, point, Vector3(0.082, 0.026, 0.015), mat["status"], mat,
				Vector3(0, side * -17.0, side * 22.0))
		Parts.axle(torso, Vector3(side * 0.370, 0.825, -0.321), 0.024, 0.014, mat["warm"], outward)
		_plate(torso, Vector3(0.235, 0.44, 0.24), Vector3(side * 0.218, 0.704, 0.300), mat["frame"], Vector3(-6, 0, side * -12))
		_plate(torso, Vector3(0.189, 0.35, 0.129), Vector3(side * 0.232, 0.724, 0.435), mat["ceramic"], Vector3(-6, 0, side * -12))
		for j in 4:
			var height := 0.613 + j * 0.059
			_plate(torso, Vector3(0.126, 0.031, 0.020), Vector3(side * 0.232, height, 0.507), mat["frame"])
			_plate(torso, Vector3(0.089, 0.011, 0.005), Vector3(side * 0.232, height, 0.519), mat["status"])
		Parts.tube(torso, PackedVector3Array([
			Vector3(side * 0.14, 0.502, 0.363), Vector3(side * 0.12, 0.445, 0.303),
			Vector3(side * 0.075, 0.409, 0.249),
		]), 0.023, mat["warm"])
	var collar := MeshKit.add(torso, MeshKit.prism(6, 0.150, 0.125, 0.074, PI / 6.0),
		mat["steel"], Vector3(0, 0.727, -0.375))
	collar.quaternion = Quaternion(Vector3.UP, Vector3.FORWARD)
	_reactor(torso, Vector3(0, 0.727, -0.392), Vector3.FORWARD, 0.104, mat, mat["core"])
	_reactor(torso, Vector3(0, 0.761, 0.392), Vector3.BACK, 0.087, mat, mat["status"])


static func build_helmet(head: Node3D, mat: Dictionary) -> void:
	for side: float in [-1.0, 1.0]:
		var temple := PackedVector3Array([
			Vector3(0.177, 0.224, 0.031), Vector3(0.215, 0.280, -0.073),
			Vector3(0.211, 0.394, -0.068), Vector3(0.177, 0.432, 0.029),
			Vector3(0.162, 0.375, 0.138), Vector3(0.146, 0.268, 0.125),
		])
		Casing.panel(head, _mirror(temple, side), Vector3.RIGHT * side, 0.072,
			mat["hood"], mat["steel"])
		_reactor(head, Vector3(side * 0.223, 0.329, 0.032), Vector3.RIGHT * side, 0.045, mat, mat["temple"])
		_insert(head, Vector3(side * 0.113, 0.409, -0.259), Vector3(0.045, 0.016, 0.010),
			mat["temple"], mat, Vector3(0, side * -31.0, side * 22.0))
		var jaw := PackedVector3Array([
			Vector3(0.057, 0.116, -0.244), Vector3(0.136, 0.153, -0.208),
			Vector3(0.170, 0.215, -0.131), Vector3(0.117, 0.185, -0.186),
			Vector3(0.066, 0.143, -0.261),
		])
		Casing.panel(head, _mirror(jaw, side), Vector3(0.45 * side, -0.18, -0.87), 0.033,
			mat["coat"], mat["steel"])


static func build_arm(arm: Dictionary, mat: Dictionary) -> void:
	var side: float = arm["side"]
	var cap := arm["cap"] as Node3D
	var shoulder := PackedVector3Array([
		Vector3(0.095, -0.035, -0.151), Vector3(0.156, 0.079, -0.095),
		Vector3(0.222, 0.052, 0.075), Vector3(0.250, -0.096, 0.139),
		Vector3(0.240, -0.267, 0.131), Vector3(0.191, -0.356, 0.048),
		Vector3(0.170, -0.279, -0.132), Vector3(0.128, -0.140, -0.172),
	])
	Casing.panel(cap, _mirror(shoulder, side), Vector3(0.90 * side, 0.27, -0.20),
		0.097, mat["ceramic"], mat["steel"], mat["coat"], 0.66)
	_insert(cap, Vector3(side * 0.238, -0.115, -0.089), Vector3(0.021, 0.049, 0.114),
		mat["shoulder_power"] if side > 0 else mat["status"], mat, Vector3(-10, side * 26.0, 0))
	Parts.axle(cap, Vector3(side * 0.268, -0.196, 0.073), 0.023, 0.013, mat["warm"], Vector3.RIGHT * side)

	var forearm := arm["twist"] as Node3D
	var guard := PackedVector3Array([
		Vector3(0.086, -0.716, -0.039), Vector3(0.134, -0.659, 0.108),
		Vector3(0.177, -0.426, 0.121), Vector3(0.163, -0.263, 0.067),
		Vector3(0.127, -0.234, -0.087), Vector3(0.119, -0.390, -0.153),
		Vector3(0.101, -0.568, -0.130),
	])
	Casing.panel(forearm, _mirror(guard, side), Vector3.RIGHT * side, 0.086,
		mat["ceramic"], mat["steel"], mat["coat"], 0.66)
	_insert(forearm, Vector3(side * 0.159, -0.476, -0.139), Vector3(0.027, 0.227, 0.018),
		mat["arm_power"] if side > 0 else mat["status"], mat, Vector3(0, -29.0 * side, -5.0 * side))
	_reactor(arm["elbow"], Vector3(side * 0.110, 0, 0), Vector3.RIGHT * side, 0.065, mat, mat["status"])


static func build_leg(leg: Dictionary, mat: Dictionary) -> void:
	var side: float = leg["side"]
	var thigh := leg["hip"] as Node3D
	var shin := leg["knee"] as Node3D
	var shoe := leg["ankle"] as Node3D
	_reactor(thigh, Vector3(side * 0.175, -0.082, 0.023), Vector3.RIGHT * side, 0.061, mat, mat["status"])
	var hip_guard := PackedVector3Array([
		Vector3(0.154, -0.183, 0.054), Vector3(0.220, -0.292, -0.062),
		Vector3(0.237, -0.480, -0.042), Vector3(0.193, -0.595, 0.060),
		Vector3(0.182, -0.453, 0.131), Vector3(0.147, -0.245, 0.112),
	])
	Casing.panel(thigh, _mirror(hip_guard, side), Vector3.RIGHT * side, 0.066,
		mat["coat"], mat["steel"])
	var thigh_plate := PackedVector3Array([
		Vector3(0.035, -0.298, -0.234), Vector3(0.150, -0.316, -0.209),
		Vector3(0.219, -0.432, -0.167), Vector3(0.181, -0.658, -0.201),
		Vector3(0.105, -0.824, -0.208), Vector3(0.032, -0.780, -0.218),
		Vector3(0.011, -0.435, -0.241),
	])
	Casing.panel(thigh, _mirror(thigh_plate, side), Vector3(0.29 * side, 0, -0.96),
		0.086, mat["ceramic"], mat["steel"], mat["coat"], 0.73)
	_insert(thigh, Vector3(side * 0.175, -0.457, -0.215), Vector3(0.023, 0.104, 0.012),
		mat["status"], mat, Vector3(0, side * -31.0, side * 12.0))
	Parts.axle(thigh, Vector3(side * 0.090, -0.615, -0.247), 0.017, 0.012, mat["warm"], Vector3.FORWARD)
	var greave := PackedVector3Array([
		Vector3(0.034, -1.037, -0.118), Vector3(0.118, -0.961, -0.142),
		Vector3(0.172, -0.580, -0.196), Vector3(0.181, -0.376, -0.158),
		Vector3(0.124, -0.271, -0.184), Vector3(0.016, -0.323, -0.181),
		Vector3(0.009, -0.785, -0.163),
	])
	Casing.panel(shin, _mirror(greave, side), Vector3(0.41 * side, 0, -0.91), 0.090,
		mat["ceramic"], mat["steel"], mat["coat"], 0.68)
	_insert(shin, Vector3(side * 0.148, -0.570, -0.220), Vector3(0.035, 0.239, 0.018),
		mat["status"], mat, Vector3(5, -30.0 * side, -8.0 * side))
	_reactor(shin, Vector3(side * 0.131, -0.011, 0.006), Vector3.RIGHT * side, 0.090, mat, mat["status"])
	_plate(shoe, Vector3(0.189, 0.065, 0.112), Vector3(0, -0.117, 0.070), mat["steel"])
	_plate(shoe, Vector3(0.059, 0.021, 0.014), Vector3(0, -0.100, 0.127), mat["status"])


static func _reactor(parent: Node3D, at: Vector3, axis: Vector3, radius: float, mat: Dictionary,
		lens: Material) -> void:
	Parts.axle(parent, at, radius * 1.17, radius * 0.48, mat["frame"], axis)
	Parts.axle(parent, at + axis * radius * 0.25, radius, radius * 0.33, mat["steel"], axis)
	Parts.axle(parent, at + axis * radius * 0.44, radius * 0.72, radius * 0.115, lens, axis)
	Parts.axle(parent, at + axis * radius * 0.52, radius * 0.37, radius * 0.14, mat["sensor"], axis)


static func _insert(parent: Node3D, point: Vector3, size: Vector3, lens: Material, mat: Dictionary, euler: Vector3) -> void:
	_plate(parent, size + Vector3(0.018, 0.022, 0.012), point, mat["frame"], euler)
	var face := Basis.from_euler(euler * (PI / 180.0)) * Vector3.FORWARD
	_plate(parent, size, point + face * (size.z * 0.52 + 0.010), lens, euler)


static func _plate(parent: Node3D, size: Vector3, position: Vector3, material: Material,
		euler := Vector3.ZERO) -> void:
	MeshKit.add(parent, MeshKit.slab(size.x, size.z, size.y, 0.036), material, position, euler)


static func _mirror(points: PackedVector3Array, side: float) -> PackedVector3Array:
	var shaped := PackedVector3Array()
	for point in points:
		shaped.append(Vector3(point.x * side, point.y, point.z))
	return shaped

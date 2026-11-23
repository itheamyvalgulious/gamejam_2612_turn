extends RefCounted
## 机体轴承、短管和外露连杆。

const MeshKit = preload("res://src/vesper/mesh_kit.gd")

static func axle(parent: Node3D, at: Vector3, radius: float, depth: float,
		material: Material, axis := Vector3.RIGHT) -> void:
	var part := MeshKit.add(parent, MeshKit.prism(20, radius, radius, depth), material, at)
	part.quaternion = Quaternion(Vector3.UP, axis.normalized())


static func tube(parent: Node3D, points: PackedVector3Array, radius: float, material: Material) -> void:
	for i in range(1, points.size()):
		var distance := points[i - 1].distance_to(points[i])
		axle(parent, (points[i - 1] + points[i]) * 0.5, radius, distance + radius * 0.4,
			material, points[i] - points[i - 1])

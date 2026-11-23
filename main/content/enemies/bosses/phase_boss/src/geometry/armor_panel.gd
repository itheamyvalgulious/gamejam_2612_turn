extends RefCounted
## Beveled plates and recessed inserts used on the helmet, arms and legs.
## Control points describe the exterior perimeter. Direction points away from the chassis.

const MeshKit = preload("res://scripts/mech/mesh_kit.gd")
const Shell = preload("res://src/geometry/loft_shell.gd")


static func panel(parent: Node3D, outline: PackedVector3Array, direction: Vector3,
		depth: float, face: Material, bevel: Material, insert: Material = null, insert_margin := 0.36) -> void:
	var normal := direction.normalized()
	var center := Vector3.ZERO
	for point in outline:
		center += point
	center /= outline.size()
	var rear := SurfaceTool.new()
	var rim := SurfaceTool.new()
	var front := SurfaceTool.new()
	rear.begin(Mesh.PRIMITIVE_TRIANGLES)
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	front.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := SurfaceTool.new()
	inner.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var j := (i + 1) % outline.size()
		var a := outline[i]
		var b := outline[j]
		var back_a := a - normal * depth * 0.56
		var back_b := b - normal * depth * 0.56
		var lip_a := a.lerp(center, 0.12) + normal * depth * 0.42
		var lip_b := b.lerp(center, 0.12) + normal * depth * 0.42
		var face_a := _face_normal(lip_a, center, normal, 0.19)
		var face_b := _face_normal(lip_b, center, normal, 0.19)
		var outward := ((a + b) * 0.5 - center).slide(normal).normalized()
		_quad(rear, back_a, back_b, b, a, outward)
		Shell.tri(rear, center - normal * depth * 0.56, back_a, back_b, -normal)
		_quad(rim, a, b, lip_b, lip_a, normal + outward)
		if insert == null:
			Shell.soft_tri(front, center + normal * depth * 0.63, lip_a, lip_b, normal, face_a, face_b)
		else:
			var opening_a := a.lerp(center, insert_margin) + normal * depth * 0.48
			var opening_b := b.lerp(center, insert_margin) + normal * depth * 0.48
			var seat_a := a.lerp(center, insert_margin + 0.055) + normal * depth * 0.27
			var seat_b := b.lerp(center, insert_margin + 0.055) + normal * depth * 0.27
			var inset_a := _face_normal(opening_a, center, normal, 0.11)
			var inset_b := _face_normal(opening_b, center, normal, 0.11)
			Shell.soft_tri(front, lip_a, lip_b, opening_b, face_a, face_b, inset_b)
			Shell.soft_tri(front, lip_a, opening_b, opening_a, face_a, inset_b, inset_a)
			_quad(rear, opening_a, opening_b, seat_b, seat_a, normal - outward)
			Shell.soft_tri(inner, center + normal * depth * 0.31, seat_a, seat_b, normal, inset_a, inset_b)
	MeshKit.add(parent, rear.commit(), bevel)
	MeshKit.add(parent, rim.commit(), bevel)
	MeshKit.add(parent, front.commit(), face)
	if insert != null:
		MeshKit.add(parent, inner.commit(), insert)


static func _face_normal(point: Vector3, center: Vector3, normal: Vector3, falloff: float) -> Vector3:
	return (normal + (point - center).slide(normal).normalized() * falloff).normalized()


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	Shell.tri(tool, a, b, c, normal)
	Shell.tri(tool, a, c, d, normal)

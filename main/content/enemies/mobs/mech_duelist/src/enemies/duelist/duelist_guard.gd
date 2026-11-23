extends RefCounted
## Sword guard layered onto the current footwork pose.

const RECOVER_AT := 0.51
const DURATION := 0.75


static func apply(model, age: float, focus: Vector3, freedom: float) -> void:
	var lift := smoothstep(0.0, 0.083, age)
	var lower := 1.0 - smoothstep(RECOVER_AT, DURATION, age)
	var weight := lift * lower * freedom
	if weight <= 0.0:
		return

	var chest := model.torso as Node3D
	var body := model.body as Node3D
	var trunk := body.transform * chest.transform
	var target: Vector3 = model.to_local(focus) - trunk.origin
	var forward := target.slide(Vector3.UP).normalized()
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	var across := forward.cross(Vector3.UP)
	var recoil := smoothstep(0.072, 0.112, age) * (1.0 - smoothstep(0.112, 0.212, age)) * freedom

	var deviation: float = model.sword_wrist_deviation()
	var angles: Vector2 = model.sword_arm_angles(deviation)
	var shaft := (Vector3.UP * 0.83 - across * (0.54 + 0.08 * recoil) + forward * 0.08).normalized()
	var edge := forward.slide(shaft).normalized()
	var blade := Basis(-edge, shaft, shaft.cross(edge))
	var start := model.weapon_root.basis as Basis

	# The shoulder brings the guard forward, then the elbow folds under contact.
	if recoil > 0.0:
		var axis := (body.basis.inverse() * across).normalized()
		chest.basis = Basis(axis, deg_to_rad(4.0) * recoil) * chest.basis
	var flex := deg_to_rad(92.0 + 9.0 * recoil)
	model.pose_sword_arm(start.slerp(blade, weight), lerpf(angles.x, flex, weight),
		lerp_angle(angles.y, deg_to_rad(19.0), weight), lerpf(deviation, 11.0, weight))
	var toes := Vector2(model.legs[0]["toe"].rotation_degrees.x, model.legs[1]["toe"].rotation_degrees.x)
	var support_roll: float = model.arms[0]["twist"].rotation_degrees.y
	model.finish_pose(0.29, 1.0, toes, support_roll)
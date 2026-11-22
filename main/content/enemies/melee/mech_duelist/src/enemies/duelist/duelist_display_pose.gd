extends RefCounted
## 展示用站姿。几何在 duelist_model.gd 中，战斗动作可独立替换这层姿态。


static func apply(model) -> void:
	# 前后错开的双脚支撑髋部，给持刀侧肩关节留出空间。
	model.body.position = Vector3(-0.046, model.HIP_HEIGHT - 0.029, -0.067)
	model.body.rotation_degrees = Vector3(0, -10, -2)
	model.torso.rotation_degrees = Vector3(2, 16, 2)
	model.head.rotation_degrees = Vector3(1, -4, -1)
	var body := model.body as Node3D
	var dominant_hand := Vector3(0.71, 2.47, -0.31)
	for leg: Dictionary in model.legs:
		var side: float = leg["side"]
		var hip := body.transform * Vector3(side * 0.319, -0.028, 0)
		var foot := Vector3(-0.38, 0.175, -0.48) if side < 0.0 else Vector3(0.39, 0.175, 0.52)
		solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, foot,
			Vector3(side * 0.16, 0, -1), model.THIGH, model.SHIN)
		leg["ankle"].rotation_degrees = Vector3(0, side * -12.0, 0)
	for arm: Dictionary in model.arms:
		var side: float = arm["side"]
		var hand := dominant_hand if side > 0.0 else Vector3(-0.59, 2.09, -0.16)
		var shoulder: Vector3 = model.shoulder_anchor(arm, hand)
		solve_chain(arm["shoulder"], arm["elbow"], arm["wrist"], shoulder, hand,
			Vector3(side * 0.32, -0.16, 0.83), model.UPPER_ARM, model.FOREARM)
		if side > 0.0:
			arm["wrist"].basis = model.sword_wrist_basis(arm, -63.0)
		else:
			arm["wrist"].rotation_degrees = Vector3(11, -17, -8)
	model.finish_pose()


static func solve_chain(upper: Node3D, lower: Node3D, end: Node3D, start: Vector3,
		target: Vector3, pole: Vector3, first: float, second: float) -> void:
	var axis := (target - start).normalized()
	var span := clampf(start.distance_to(target), absf(first - second) + 0.001, first + second - 0.001)
	var center := (first * first - second * second + span * span) / (2.0 * span)
	var height := sqrt(maxf(0.0, first * first - center * center))
	var joint := start + axis * center + pole.slide(axis).normalized() * height
	var finish := start + axis * span
	upper.transform = Transform3D(_limb_basis(start - joint), start)
	lower.transform = Transform3D(_limb_basis(joint - finish), joint)
	end.transform = Transform3D(Basis.IDENTITY, finish)


static func _limb_basis(up: Vector3) -> Basis:
	var y := up.normalized()
	var z := Vector3.BACK.slide(y).normalized()
	return Basis(y.cross(z).normalized(), y, z)

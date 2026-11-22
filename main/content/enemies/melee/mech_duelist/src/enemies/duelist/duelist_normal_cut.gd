extends RefCounted
## Compact horizontal cut from the combat guard, with both feet anchored.

const Rig = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")

const RANGE := 6.15
const MIN_FACING := 0.86
const TRAIL_START := 0.205
const HIT_START := 0.218
const HIT_END := 0.359
const DURATION := 0.60
const GUARD_DEVIATION := 16.0
const DISPLAY_NAME := "快横斩"


static func can_start(model: Node3D, focus: Vector3) -> bool:
	var offset := (focus - model.global_position).slide(Vector3.UP)
	return offset.length_squared() <= RANGE * RANGE and -model.global_basis.z.normalized().dot(offset.normalized()) >= MIN_FACING


static func begin(model, focus: Vector3) -> Dictionary:
	var feet: Array[Transform3D] = []
	var knees: Array[Vector3] = []
	var toes := Vector2.ZERO
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var ankle := leg["ankle"] as Node3D
		feet.append(ankle.transform)
		knees.append(_pole(leg["hip"], leg["knee"], ankle))
		toes[i] = leg["toe"].rotation_degrees.x

	var torso: Transform3D = model.body.transform * model.torso.transform
	var arm: Dictionary = model.arms[0]
	var wrist := arm["wrist"] as Node3D
	var right: Dictionary = model.arms[1]
	var deviation: float = model.sword_wrist_deviation()
	var flexion: float = model.sword_wrist_flexion()
	return {
		"hip": model.body.transform, "chest": model.torso.basis, "focus": focus,
		"feet": feet, "knees": knees, "toes": toes,
		"support_hand": torso.affine_inverse() * wrist.position,
		"support_pole": _pole(arm["shoulder"], arm["elbow"], wrist),
		"support_wrist": (arm["elbow"] as Node3D).basis.inverse() * wrist.basis,
		"sword_hand": torso.affine_inverse() * right["wrist"].position,
		"sword_pole": torso.basis.inverse() * _pole(right["shoulder"], right["elbow"], right["wrist"]),
		"sword_roll": rad_to_deg(model.sword_arm_angles(GUARD_DEVIATION).y),
		"blade": model.weapon_root.basis, "angles": model.sword_arm_angles(deviation, flexion),
		"deviation": deviation, "wrist_flexion": flexion, "grip_cant": model.sword_grip_cant,
	}


static func apply(model, state: Dictionary, time: float) -> void:
	var recover := smoothstep(HIT_END, DURATION, time)
	var weight := 1.0 - recover
	var hip_load := smoothstep(0.025, 0.143, time)
	var hip_cut := smoothstep(0.151, 0.31, time)
	var chest_load := smoothstep(0.068, 0.176, time)
	var chest_cut := smoothstep(0.186, 0.345, time)
	var hip: Transform3D = state["hip"]
	var body := model.body as Node3D
	var chest := model.torso as Node3D
	body.position = hip.origin + (Vector3(0.08, -0.08, 0.05) * hip_load
		+ Vector3(-0.18, -0.045, -0.38) * hip_cut) * weight
	body.basis = Basis(Vector3.UP, deg_to_rad((-12.0 * hip_load + 25.0 * hip_cut) * weight)) * hip.basis
	chest.basis = Basis(Vector3.UP, deg_to_rad((-15.0 * chest_load + 31.0 * chest_cut) * weight)) * (state["chest"] as Basis)

	pose_legs(model, state["feet"], state["knees"])
	Pace.aim_head(model, state["focus"])
	pose_support(model, state, Vector3(-0.07, -0.065, 0.10) * chest_load * weight
		+ Vector3(-0.16, -0.12, 0.15) * chest_cut * weight)
	_pose_sword(model, state, time, recover)
	model.finish_pose(0.29, 1.0, state["toes"])


static func pose_legs(model, feet: Array[Transform3D], knees: Array[Vector3]) -> void:
	var body := model.body as Node3D
	var root: Transform3D = model.global_transform
	var local := root.affine_inverse()
	var targets: Array[Transform3D] = []
	var reach: float = model.THIGH + model.SHIN - 0.012
	var ceiling := INF
	for i in feet.size():
		var target := local * (model.keep_sole_above_floor(root * feet[i]) as Transform3D)
		targets.append(target)
		var side: float = model.legs[i]["side"]
		var offset := body.basis * Vector3(side * 0.319, -0.028, 0.0)
		var flat := (target.origin - body.position - offset).slide(Vector3.UP)
		ceiling = minf(ceiling, target.origin.y - offset.y + sqrt(maxf(0.0, reach * reach - flat.length_squared())))
	body.position.y = minf(body.position.y, ceiling)
	for i in feet.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var hip := body.transform * Vector3(side * 0.319, -0.028, 0.0)
		Rig.solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, targets[i].origin,
			knees[i], model.THIGH, model.SHIN)
		leg["ankle"].basis = targets[i].basis


static func pose_support(model, state: Dictionary, offset: Vector3) -> void:
	var arm: Dictionary = model.arms[0]
	var torso: Transform3D = model.body.transform * model.torso.transform
	var hand := torso * ((state["support_hand"] as Vector3) + offset)
	Rig.solve_chain(arm["shoulder"], arm["elbow"], arm["wrist"], model.shoulder_anchor(arm, hand),
		hand, state["support_pole"], model.UPPER_ARM, model.FOREARM)
	arm["wrist"].basis = arm["elbow"].basis * state["support_wrist"]


static func pose_sword_grip(model, hand: Vector3, pole: Vector3, shaft: Vector3, deviation: float) -> void:
	var arm: Dictionary = model.arms[1]
	var wrist := arm["wrist"] as Node3D
	var shoulder: Vector3 = model.shoulder_anchor(arm, hand)
	Rig.solve_chain(arm["shoulder"], arm["elbow"], wrist, shoulder, hand, pole, model.UPPER_ARM, model.FOREARM)
	# Aim by rolling about the solved forearm. A sword direction must not pull the elbow through the armor.
	var axis: Vector3 = arm["elbow"].basis.y
	var socket_axis: Vector3 = model.Hand.sword_socket().basis.y
	var neutral: Basis = model.sword_wrist_basis(arm, 0.0, deviation)
	var source := (neutral * socket_axis).slide(axis).normalized()
	var wanted := shaft.slide(axis).normalized()
	var roll := rad_to_deg(source.signed_angle_to(wanted, axis))
	wrist.basis = model.sword_wrist_basis(arm, roll, deviation)


static func _pose_sword(model, state: Dictionary, time: float, recover: float) -> void:
	var arm: Dictionary = model.arms[1]
	var wrist := arm["wrist"] as Node3D
	var trunk: Transform3D = model.body.transform * model.torso.transform
	var guard: Vector3 = state["sword_hand"]
	var wind := smoothstep(0.078, 0.195, time)
	var sweep := smoothstep(0.199, HIT_END, time)
	var ready := Vector3(0.96, 0.07, -0.56)
	var finish := Vector3(-0.21, 0.02, -0.94)
	var front := ready.lerp(finish, sweep) + Vector3(0.13, 0.03, -0.44) * sin(PI * sweep)
	# The hand travels around the front of the armour on the cut and on the return.
	var hand := guard.lerp(front, wind).lerp(guard, recover)
	hand.x += 0.14 * smoothstep(0.0, 0.06, time) * (1.0 - smoothstep(0.084, 0.16, time))
	hand.z -= 0.28 * sin(PI * recover)
	hand = trunk * hand
	var shoulder: Vector3 = model.shoulder_anchor(arm, hand)

	var reach := (hand - shoulder).normalized()
	var down := (trunk.basis * Vector3.DOWN).slide(reach).normalized()
	var elbow_turn := -28.0 + 31.0 * smoothstep(0.207, 0.261, time) - 21.0 * smoothstep(0.28, HIT_END, time)
	var swing_pole := down.rotated(reach, deg_to_rad(elbow_turn))
	var guard_pole: Vector3 = trunk.basis * state["sword_pole"]
	var release := wind * (1.0 - recover)
	var pole := guard_pole.lerp(swing_pole, release)
	Rig.solve_chain(arm["shoulder"], arm["elbow"], wrist, shoulder, hand, pole, model.UPPER_ARM, model.FOREARM)
	var roll := lerpf(state["sword_roll"], -73.0, release)
	wrist.basis = model.sword_wrist_basis(arm, roll, lerpf(GUARD_DEVIATION, 12.0, release))


static func _pole(upper: Node3D, lower: Node3D, end: Node3D) -> Vector3:
	return (lower.position - upper.position).slide((end.position - upper.position).normalized()).normalized()

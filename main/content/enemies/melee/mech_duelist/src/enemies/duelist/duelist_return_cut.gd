extends RefCounted
## A right-foot step into the reverse cut, starting at the actual end pose of the lunge.

const Rig = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const SkeletonLayout = preload("res://src/enemies/duelist/duelist_rig.gd")
const DURATION := 0.55
const STEP_START := 0.103
const RIGHT_LAND := 0.236
const HIP_TURN_START := 0.12
const CHEST_TURN_START := 0.17
const TRAIL_START := 0.220
const HIT_START := 0.240
const HIT_END := 0.442
const MIN_KNEE_FLEX := deg_to_rad(13.0)


static func begin(model, watch: Vector3) -> Dictionary:
	var feet: Array[Transform3D] = []
	var knees: Array[Vector3] = []
	var toes := Vector2.ZERO
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var foot := leg["ankle"] as Node3D
		feet.append(foot.transform)
		knees.append(_bend_plane(leg["hip"], leg["knee"], foot))
		toes[i] = leg["toe"].rotation_degrees.x
	var trunk: Transform3D = model.body.transform * model.torso.transform
	var support: Dictionary = model.arms[0]
	var wrist := support["wrist"] as Node3D
	var sword: Dictionary = model.arms[1]
	var upper: Vector3 = sword["elbow"].position - sword["shoulder"].position
	var lower: Vector3 = sword["wrist"].position - sword["elbow"].position
	return {
		"hip": model.body.transform, "chest": model.torso.basis, "watch": watch,
		"feet": feet, "knees": knees, "toes": toes,
		"support_hand": trunk.affine_inverse() * wrist.position,
		"support_wrist": (support["elbow"] as Node3D).basis.inverse() * wrist.basis,
		"support_plane": _bend_plane(support["shoulder"], support["elbow"], wrist),
		"blade": model.weapon_root.basis,
		"blade_on_chest": trunk.basis.inverse() * model.weapon_root.basis,
		"sword_upper": trunk.basis.inverse() * upper.normalized(),
		"sword_lower": trunk.basis.inverse() * lower.normalized(),
		"sword_angles": model.sword_arm_angles(3.0),
	}


static func apply(model, state: Dictionary, time: float) -> void:
	var hip_start: Transform3D = state["hip"]
	var body := model.body as Node3D
	var chest := model.torso as Node3D
	var settle := smoothstep(0.0, 0.085, time) * (1.0 - smoothstep(HIP_TURN_START, 0.25, time))
	var hip_turn := smoothstep(HIP_TURN_START, 0.298, time)
	var shoulder_turn := smoothstep(CHEST_TURN_START, 0.425, time)
	var shift := smoothstep(0.176, 0.379, time)
	var rise := smoothstep(0.148, 0.468, time)
	var straighten := smoothstep(RIGHT_LAND, 0.478, time)
	var brake := smoothstep(RIGHT_LAND, 0.268, time) * (1.0 - smoothstep(0.268, 0.325, time))
	body.position = hip_start.origin + Vector3(-0.079, -0.081, -0.045) * settle
	body.position += Vector3(0.26, 0.0, -0.33) * shift
	body.position.y = lerpf(body.position.y, model.HIP_HEIGHT + 0.030, rise) - 0.048 * brake
	body.basis = Basis(Vector3.UP, deg_to_rad(2.4 * settle - 27.0 * hip_turn)) * hip_start.basis
	body.basis *= Basis(Vector3.BACK, deg_to_rad(-7.0 * shift))
	chest.basis = Basis(Vector3.UP, deg_to_rad(3.1 * settle - 20.0 * shoulder_turn)) * (state["chest"] as Basis)
	chest.basis *= Basis(Vector3.BACK, deg_to_rad(-8.0 * shoulder_turn))
	body.basis = body.basis.slerp(Basis(Vector3.UP, body.rotation.y), 0.84 * straighten)
	chest.basis = chest.basis.slerp(Basis(Vector3.UP, chest.rotation.y), 0.77 * straighten)

	var toes := _pose_legs(model, state, time, hip_turn, shift)
	Pace.aim_head(model, state["watch"])
	_pose_support(model, state, time)
	_pose_sword(model, state, time)
	model.finish_pose(0.24, 1.0, toes)


static func _pose_legs(model, state: Dictionary, time: float, turn: float, weight: float) -> Vector2:
	var initial_toes: Vector2 = state["toes"]
	var toes := initial_toes
	var step := smoothstep(STEP_START, RIGHT_LAND, time)
	var press := smoothstep(0.098, 0.252, time) * (1.0 - 0.71 * smoothstep(0.32, 0.52, time))
	var feet: Array[Transform3D] = []
	var planes: Array[Vector3] = []
	var body := model.body as Node3D
	var thigh: float = model.THIGH
	var shin: float = model.SHIN
	var reach_sq := thigh * thigh + shin * shin + 2.0 * thigh * shin * cos(MIN_KNEE_FLEX)
	var root: Transform3D = model.global_transform
	var local := root.affine_inverse()
	var ceiling := INF
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var start: Transform3D = state["feet"][i]
		var ball := start * _toe_contact(initial_toes[i])
		var foot: Transform3D
		var plane: Vector3 = state["knees"][i]
		if side < 0.0:
			# The left foot drives the step from a fixed contact point.
			toes[i] += 13.0 * press
			var pivot := Basis(Vector3.UP, deg_to_rad(-10.0 * turn))
			var ankle := pivot * start.basis * Basis(Vector3.RIGHT, deg_to_rad(-16.0 * press))
			foot = Transform3D(ankle, ball - ankle * _toe_contact(toes[i]))
			plane = plane.rotated(Vector3.UP, deg_to_rad(-10.0 * turn))
			plane.x -= 0.10 * weight
		else:
			toes[i] = lerpf(initial_toes[i], 0.0, step)
			var landing := root * Vector3(0.82, 0.0, -0.49)
			landing.y = model.floor_height(landing)
			foot = _right_step(start, (local * landing).y, time, step)
			var forward := -foot.basis.z.slide(Vector3.UP).normalized()
			plane = plane.lerp(forward + Vector3.RIGHT * 0.18, step)

		foot = local * (model.keep_sole_above_floor(root * foot) as Transform3D)
		feet.append(foot)
		planes.append(plane)
		var offset := body.basis * Vector3(side * 0.319, -0.028, 0.0)
		var horizontal := (foot.origin - body.position - offset).slide(Vector3.UP)
		ceiling = minf(ceiling, foot.origin.y - offset.y + sqrt(maxf(0.0, reach_sq - horizontal.length_squared())))

	# Stop the rise before a locked knee would pull either planted foot off the floor.
	var blend_width := 0.035
	var blend := maxf(0.0, blend_width - absf(body.position.y - ceiling)) / blend_width
	body.position.y = minf(body.position.y, ceiling) - blend * blend * blend_width * 0.25
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var hip := body.transform * Vector3(side * 0.319, -0.028, 0.0)
		Rig.solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, feet[i].origin, planes[i], thigh, shin)
		leg["ankle"].basis = feet[i].basis
	return toes


static func _right_step(start: Transform3D, floor_height: float, time: float, step: float) -> Transform3D:
	var flatten := smoothstep(RIGHT_LAND, 0.283, time)
	var yaw := Basis(Vector3.UP, deg_to_rad(-19.0))
	var ankle := yaw * Basis(Vector3.RIGHT, deg_to_rad(9.0 * (1.0 - flatten)))
	var heel := Vector3(0.82, floor_height, -0.49)
	var landing := Transform3D(ankle, heel - ankle * Pace.HEEL)
	var foot := start.interpolate_with(landing, step)
	var flight := clampf(inverse_lerp(STEP_START, RIGHT_LAND, time), 0.0, 1.0)
	var clearance := sin(PI * flight) * sin(PI * flight)
	foot.origin += Vector3(0.12, 0.38, 0.0) * clearance
	return foot


static func _toe_contact(angle: float) -> Vector3:
	var hinge := SkeletonLayout.TOE_HINGE
	return hinge + Basis(Vector3.RIGHT, deg_to_rad(angle)) * (Pace.TOE - hinge)


static func _pose_support(model, state: Dictionary, time: float) -> void:
	var arm: Dictionary = model.arms[0]
	var trunk: Transform3D = model.body.transform * model.torso.transform
	var balance := smoothstep(CHEST_TURN_START, 0.35, time)
	var settle := smoothstep(0.39, DURATION, time)
	var hand := trunk * ((state["support_hand"] as Vector3) + Vector3(-0.22, 0.18, -0.21) * balance
		+ Vector3(0.09, -0.09, 0.13) * settle)
	var plane: Vector3 = (state["support_plane"] as Vector3).lerp(Vector3(-0.94, -0.30, 0.42), balance)
	Rig.solve_chain(arm["shoulder"], arm["elbow"], arm["wrist"], model.shoulder_anchor(arm, hand), hand,
		plane, model.UPPER_ARM, model.FOREARM)
	arm["wrist"].basis = arm["elbow"].basis * state["support_wrist"]


static func _pose_sword(model, state: Dictionary, time: float) -> void:
	var trunk: Basis = model.body.basis * model.torso.basis
	var held: Basis = trunk * state["blade_on_chest"]
	var start: Basis = state["blade"]
	var start_yaw := atan2(-start.y.z, start.y.x)
	var held_yaw := atan2(-held.y.z, held.y.x)
	var load := smoothstep(HIP_TURN_START, 0.241, time)
	var cut := smoothstep(0.217, HIT_END, time)
	var coiled_yaw := lerp_angle(start_yaw, held_yaw, 0.05) + deg_to_rad(4.0 * load)
	var theta := lerp_angle(coiled_yaw, start_yaw - deg_to_rad(104.0), cut)
	var pitch := lerpf(asin(held.y.y) + deg_to_rad(4.0 * load), deg_to_rad(-30.0), cut)
	var shaft := Vector3(cos(theta) * cos(pitch), sin(pitch), -sin(theta) * cos(pitch))
	var held_edge := Vector3.UP.cross(held.y).normalized()
	var held_roll := held_edge.signed_angle_to(-held.x, held.y)
	# Fold the arm while the blade rolls over, then extend into the falling arc.
	var turn_edge := smoothstep(CHEST_TURN_START, 0.272, time)
	var edge := Vector3.UP.cross(shaft).normalized().rotated(shaft, lerpf(held_roll, deg_to_rad(-160.0), turn_edge))
	var angles: Vector2 = state["sword_angles"]
	var elbow_load := smoothstep(0.149, 0.203, time) * (1.0 - smoothstep(0.221, 0.307, time))
	var flex := lerpf(angles.x, deg_to_rad(75.0), cut) + deg_to_rad(28.0 * elbow_load)
	flex += deg_to_rad(9.0) * smoothstep(HIT_END, DURATION, time)
	var roll := lerpf(angles.y, deg_to_rad(22.0), smoothstep(0.112, 0.19, time))
	roll = lerpf(roll, deg_to_rad(-10.0), smoothstep(0.27, 0.39, time))
	var deviation := 3.0 + 7.0 * smoothstep(0.194, 0.325, time)
	var follow := smoothstep(0.211, 0.240, time)
	if follow >= 1.0:
		model.pose_sword_arm(Basis(-edge, shaft, shaft.cross(edge)), flex, roll, deviation)
		return

	# Guide the elbow around the armour before blending into the blade-led sweep.
	var prepare := smoothstep(HIP_TURN_START, 0.214, time)
	var upper := trunk * (state["sword_upper"] as Vector3).slerp(Vector3(0.16, -0.92, -0.36).normalized(), prepare)
	var lower := trunk * (state["sword_lower"] as Vector3).slerp(Vector3(-0.59, -0.08, -0.80).normalized(), prepare)
	if follow > 0.0:
		model.pose_sword_arm(Basis(-edge, shaft, shaft.cross(edge)), flex, roll, deviation)
		var arm: Dictionary = model.arms[1]
		var goal_upper: Vector3 = arm["elbow"].position - arm["shoulder"].position
		var goal_lower: Vector3 = arm["wrist"].position - arm["elbow"].position
		upper = upper.slerp(goal_upper.normalized(), follow)
		lower = lower.slerp(goal_lower.normalized(), follow)
	model.pose_sword_links(upper, lower, roll, deviation)


static func _bend_plane(upper: Node3D, lower: Node3D, end: Node3D) -> Vector3:
	return (lower.position - upper.position).slide((end.position - upper.position).normalized()).normalized()

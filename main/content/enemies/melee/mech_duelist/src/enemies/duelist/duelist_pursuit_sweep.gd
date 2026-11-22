extends RefCounted
## Side and front takes from the reference define the two strokes and their foot contacts.

const NormalCut = preload("res://src/enemies/duelist/duelist_normal_cut.gd")
const DoubleCut = preload("res://src/enemies/duelist/duelist_double_cut.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Rig = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const Alert = preload("res://src/enemies/duelist/duelist_alert_pose.gd")
const Units = preload("res://src/core/units.gd")

const DISPLAY_NAME := "横扫挥斩"
const MIN_RANGE := 2.7 / Units.M_PER_UNIT
const RANGE := 7.40
const PREP_RANGE := 4.5 / Units.M_PER_UNIT
const WINDUP_END := 0.39
const LEAD_STEP_START := 0.24
const LEAD_LAND := 0.45
const TRAIL_START := 0.42
const HIT_START := 0.46
const HIT_END := 0.65
const SECOND_WINDUP := 0.94
const SECOND_TRAIL_START := 1.47
const SECOND_HIT_START := 1.51
const SECOND_HIT_END := 1.75
const SECOND_LAND := 1.62
const GUARD_RETURN := 2.96
const DURATION := 3.26
const THRUST_BLADE_ANGLES := Vector3(0, -15, -22)
const THRUST_GRIP_CANT := 30.0
const STRIKES := [
	Vector4(0.0, TRAIL_START, HIT_START, HIT_END),
	Vector4(SECOND_WINDUP, SECOND_TRAIL_START, SECOND_HIT_START, SECOND_HIT_END),
]
const FOOTFALLS := [Vector3(LEAD_LAND, 1, 0.53), Vector3(SECOND_LAND, 0, 0.64)]

# Time, sword yaw/pitch/edge bank, then elbow flexion/forearm roll/wrist deviation.
# During the first strike, hold the point on one axis while the hilt advances.
const BLADE_KEYS := [
	[0.25, Vector3(29, 43, -43), Vector3(122, -62, 17)],
	[WINDUP_END, THRUST_BLADE_ANGLES, Vector3(81, -68, 27)],
	[0.45, THRUST_BLADE_ANGLES, Vector3(18, -68, 27)],
	[0.52, THRUST_BLADE_ANGLES, Vector3(12, -68, 27)],
	[0.59, THRUST_BLADE_ANGLES, Vector3(5, -68, 27)],
	[0.66, THRUST_BLADE_ANGLES, Vector3(5, -68, 27)],
	[0.80, Vector3(0, 14, -78), Vector3(59, -62, 24)],
	[0.88, Vector3(0, 17, -52), Vector3(118, -64, 24)],
	[1.07, Vector3(-28, 72, -33), Vector3(123, -63, 13)],
	[1.24, Vector3(-111, 61, -73), Vector3(99, -74, 19)],
	[1.43, Vector3(-156, 19, -136), Vector3(101, -74, 19)],
	[1.54, Vector3(-54, 20, -112), Vector3(116, -74, 19)],
	[1.66, Vector3(80, 9, -124), Vector3(101, -74, 19)],
	[1.80, Vector3(142, 21, -153), Vector3(60, -74, 19)],
	[2.11, Vector3(219, 32, -39), Vector3(22, -74, 19)],
	[2.48, Vector3(219, 32, -39), Vector3(23, -74, 19)],
	[2.72, Vector3(150, 48, -51), Vector3(69, -74, 19)],
	[GUARD_RETURN, Vector3(70, 40, -24), Vector3(125, -74, 19)],
]

# Empty hand travels from the chest to the side of the face, then opens toward the landing.
const SUPPORT_KEYS := [
	[0.24, Alert.SUPPORT_HAND, Alert.SUPPORT_POLE],
	[0.63, Vector3(-0.30, 0.72, -0.78), Vector3(-0.62, -0.70, 0.19)],
	[1.10, Vector3(-0.42, 0.99, -0.54), Vector3(-0.73, -0.54, 0.22)],
	[1.39, Vector3(-0.52, 1.40, -0.42), Vector3(-0.71, -0.64, 0.19)],
	[1.55, Vector3(-0.72, 1.26, -0.48), Vector3(-0.74, -0.56, 0.24)],
	[1.65, Vector3(-1.06, 0.67, -0.61), Vector3(-0.72, -0.60, 0.26)],
	[1.86, Vector3(-1.47, 0.17, -0.48), Vector3(-0.64, -0.66, 0.22)],
	[2.49, Vector3(-1.53, 0.14, -0.43), Vector3(-0.65, -0.64, 0.22)],
	[DURATION, Alert.SUPPORT_HAND, Alert.SUPPORT_POLE],
]


static func can_start(model: Node3D, focus: Vector3, reach := RANGE) -> bool:
	var offset := (focus - model.global_position).slide(Vector3.UP)
	var distance := offset.length()
	return distance >= MIN_RANGE and distance <= reach \
		and -model.global_basis.z.normalized().dot(offset.normalized()) >= 0.88


static func begin(model, focus: Vector3, cover: Array, bounds: AABB) -> Dictionary:
	var state := NormalCut.begin(model, focus)
	var origin: Transform3D = model.global_transform
	var size := origin.basis.get_scale().x
	var forward := -origin.basis.z.normalized()
	var gap := (focus - origin.origin).slide(Vector3.UP).length()
	var distance := minf(1.85 * size, maxf(0.0, gap - 3.4))
	var goal := origin.origin + forward * distance
	for obstacle: Dictionary in cover:
		var radius := maxf(0.35, float(obstacle["r"]) - 1.2) + 1.1 * size
		goal = Hit.slide_around_body(origin.origin, goal, obstacle["c"], radius)
	goal = _keep_inside(goal, bounds)
	var shift := origin.affine_inverse() * goal

	state["root"] = origin
	state["root_shift"] = shift
	state["right_plant"] = DoubleCut._foot_at(model, origin, Vector3(0.61, 0.0, shift.z * 0.44 - 0.42), -8.0, cover, bounds)
	state["left_plant"] = DoubleCut._foot_at(model, origin, Vector3(shift.x - 0.94, 0.0, shift.z - 1.12), -17.0, cover, bounds)
	state["right_finish"] = DoubleCut._foot_at(model, origin, Vector3(shift.x + 0.55, 0.0, shift.z - 0.19), -8.0, cover, bounds)
	return state


static func apply(model, state: Dictionary, time: float) -> void:
	var origin: Transform3D = state["root"]
	var shift: Vector3 = state["root_shift"]
	var gather := smoothstep(0.10, 0.28, time)
	var first := smoothstep(0.22, 0.70, time)
	var coil := smoothstep(0.90, 1.38, time)
	var pelvis_open := smoothstep(1.41, 1.70, time)
	var chest_open := smoothstep(1.49, 1.81, time)
	var settle := smoothstep(SECOND_LAND, 1.98, time)
	var recover := smoothstep(2.49, DURATION, time)
	var follow := 1.0 - recover
	var step_in := smoothstep(LEAD_STEP_START, WINDUP_END, time)
	var travel := first * 0.44 * step_in + coil * 0.12 + pelvis_open * 0.44
	var drift := shift * travel
	var root_turn := Basis(Vector3.UP, deg_to_rad(-42.0) * pelvis_open * follow)
	var unturn := root_turn.inverse()
	model.global_transform = Transform3D(origin.basis * root_turn, origin * drift)

	var hip: Transform3D = state["hip"]
	var body := model.body as Node3D
	var chest := model.torso as Node3D
	var set_height: float = model.HIP_HEIGHT - Alert.HIP_DROP
	body.position = Vector3(hip.origin.x, lerpf(hip.origin.y, set_height, gather), hip.origin.z)
	body.position += Vector3(-0.29, -0.08, 0.04) * gather * (1.0 - first)
	body.position += Vector3(0.18, -0.16, -0.12) * first * (1.0 - coil)
	# The torso lowers as the elbow opens so the point advances on the shaft's line.
	var thrust_lower := smoothstep(0.445, 0.61, time) * (1.0 - smoothstep(0.66, 0.90, time))
	body.position += Vector3(-0.075, -0.32, 0.0) * thrust_lower
	body.position += Vector3(0.13, 0.085, 0.06) * coil * (1.0 - pelvis_open)
	body.position += unturn * Vector3(-0.53, -0.56, -0.48) * settle * follow
	var hip_angles := Vector3(-8 - 4 * first + 5 * coil - 9 * settle, 12 * first + 13 * coil - 49 * pelvis_open, 14 * settle) * follow
	var chest_angles := Vector3(-8 - 5 * first + 7 * coil - 13 * settle, 15 * first + 14 * coil - 58 * chest_open, 10 * settle) * follow
	body.basis = hip.basis.slerp(Basis.from_euler(hip_angles * (PI / 180.0)), gather)
	chest.basis = (state["chest"] as Basis).slerp(Basis.from_euler(chest_angles * (PI / 180.0)), gather)
	body.basis = body.basis.slerp(Basis(Vector3.RIGHT, Alert.HIP_PITCH), recover)
	chest.basis = chest.basis.slerp(Basis(Vector3.RIGHT, Alert.CHEST_PITCH), recover)

	_pose_feet(model, state, time, Transform3D(unturn, -(unturn * drift)))
	Pace.aim_head(model, state["focus"])
	model.head.rotate_object_local(Vector3.RIGHT, -0.13 * settle * follow)
	_pose_support(model, state, time)
	var thrust_grip := smoothstep(0.29, LEAD_LAND, time) * (1.0 - smoothstep(0.66, 0.88, time))
	_pose_sword(model, state, time, unturn, thrust_grip)
	model.finish_pose(lerpf(0.30, 0.15, chest_open * follow), 1.0, Vector2.ZERO, 0.0, 0.07,
		THRUST_GRIP_CANT * thrust_grip)


static func _pose_feet(model, state: Dictionary, time: float, local: Transform3D) -> void:
	var feet: Array[Transform3D] = state["feet"].duplicate()
	var right_plant: Transform3D = state["right_plant"]
	var left_plant: Transform3D = state["left_plant"]
	var right := _stride(feet[1], right_plant, LEAD_STEP_START, LEAD_LAND, time, 0.17)
	var left := _stride(feet[0], left_plant, 0.99, SECOND_LAND, time, 0.92)
	var toe_pivot := smoothstep(1.47, 1.80, time)
	var ball := right * Pace.TOE
	right.basis = Basis(Vector3.UP, deg_to_rad(-34.0) * toe_pivot) * right.basis \
		* Basis(Vector3.RIGHT, deg_to_rad(-15.0) * toe_pivot)
	right.origin = ball - right.basis * Pace.TOE
	right = _stride(right, state["right_finish"], 2.62, 3.14, time, 0.24)
	feet[0] = local * left
	feet[1] = local * right
	var knees: Array[Vector3] = state["knees"].duplicate()
	for i in feet.size():
		var knee_forward := -feet[i].basis.z.slide(Vector3.UP).normalized()
		knees[i] = knees[i].lerp(knee_forward + Vector3(float(model.legs[i]["side"]) * 0.22, 0, 0),
			smoothstep(0.0, 0.32, time))
	NormalCut.pose_legs(model, feet, knees)


static func _stride(from: Transform3D, to: Transform3D, start: float, end: float, time: float, lift: float) -> Transform3D:
	var phase := clampf(inverse_lerp(start, end, time), 0.0, 1.0)
	var foot := from.interpolate_with(to, smoothstep(0.0, 1.0, phase))
	foot.origin.y += lift * pow(maxf(0.0, sin(PI * phase)), 1.15)
	return foot


static func _pose_support(model, state: Dictionary, time: float) -> void:
	var arm: Dictionary = model.arms[0]
	var trunk: Transform3D = model.body.transform * model.torso.transform
	var ready := smoothstep(0.0, 0.24, time)
	var hand := trunk * (state["support_hand"] as Vector3).lerp(_sample(SUPPORT_KEYS, time, 1), ready)
	var pole := (state["support_pole"] as Vector3).lerp(trunk.basis * _sample(SUPPORT_KEYS, time, 2), ready)
	Rig.solve_chain(arm["shoulder"], arm["elbow"], arm["wrist"], model.shoulder_anchor(arm, hand),
		hand, pole, model.UPPER_ARM, model.FOREARM)
	var wrist_open := Basis.from_euler(Vector3(-0.17, -0.25, 0.10))
	arm["wrist"].basis = arm["elbow"].basis * (state["support_wrist"] as Basis).slerp(wrist_open, ready)


static func _pose_sword(model, state: Dictionary, time: float, unturn: Basis, thrust_grip: float) -> void:
	var blade := _sample(BLADE_KEYS, time, 1, true)
	var angles := _sample(BLADE_KEYS, time, 2) * (PI / 180.0)
	var ready := smoothstep(0.0, 0.25, time)
	var previous: Basis = state["blade"]
	var entry_angles: Vector2 = state["angles"]
	var weapon := previous.slerp(unturn * _blade_basis(blade), ready)
	var flex := lerpf(entry_angles.x, angles.x, ready)
	var roll := lerp_angle(entry_angles.y, angles.y, ready)
	var deviation := lerpf(state["deviation"], rad_to_deg(angles.z), ready)
	if time > GUARD_RETURN:
		var weight := smoothstep(GUARD_RETURN, DURATION, time)
		Alert.pose_weapon(model)
		if weight >= 1.0:
			return
		var wrist_basis: Basis = model.arms[1]["wrist"].basis
		var guard_blade: Basis = wrist_basis * model.Hand.sword_socket().basis
		var guard_angles: Vector2 = model.sword_arm_angles(Alert.WRIST_DEVIATION)
		weapon = weapon.slerp(guard_blade, weight)
		flex = lerpf(flex, guard_angles.x, weight)
		roll = lerp_angle(roll, guard_angles.y, weight)
		deviation = lerpf(deviation, Alert.WRIST_DEVIATION, weight)
	# The fingers angle the hilt in the palm so the blade can align without folding the wrist.
	var wrist_flexion := lerpf(state["wrist_flexion"], lerpf(-14.0, 0.0, thrust_grip), ready)
	model.pose_sword_arm(weapon, flex, roll, deviation, wrist_flexion, THRUST_GRIP_CANT * thrust_grip)


static func _blade_basis(angles: Vector3) -> Basis:
	var yaw := deg_to_rad(angles.x)
	var pitch := deg_to_rad(angles.y)
	var shaft := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var edge := Vector3.UP.cross(shaft).normalized().rotated(shaft, deg_to_rad(angles.z))
	return Basis(-edge, shaft, shaft.cross(edge))


static func _sample(keys: Array, time: float, channel: int, carry_yaw := false) -> Vector3:
	for i in range(1, keys.size()):
		var current: Array = keys[i]
		if time <= float(current[0]):
			var previous: Array = keys[i - 1]
			var span: float = float(current[0]) - float(previous[0])
			var u := clampf((time - float(previous[0])) / span, 0.0, 1.0)
			var value := (previous[channel] as Vector3).lerp(current[channel], u * u * (3.0 - 2.0 * u))
			if carry_yaw:
				# Preserve angular velocity across successive blade keys. Only reverse at the ends of the arc.
				var tangent_from := _yaw_speed(keys, i - 1) * span
				var tangent_to := _yaw_speed(keys, i) * span
				value.x += u * (1.0 - u) * (tangent_from * (1.0 - u) - tangent_to * u)
			return value
	return keys.back()[channel]


static func _yaw_speed(keys: Array, index: int) -> float:
	if index == 0 or index == keys.size() - 1:
		return 0.0
	var before: Array = keys[index - 1]
	var current: Array = keys[index]
	var after: Array = keys[index + 1]
	var incoming: float = (current[1].x - before[1].x) / (current[0] - before[0])
	var outgoing: float = (after[1].x - current[1].x) / (after[0] - current[0])
	return 2.0 * incoming * outgoing / (incoming + outgoing) if incoming * outgoing > 0.0 else 0.0


static func _keep_inside(point: Vector3, bounds: AABB) -> Vector3:
	if bounds.size.length_squared() <= 0.1:
		return point
	return Vector3(clampf(point.x, bounds.position.x + 3.0, bounds.end.x - 3.0), point.y,
		clampf(point.z, bounds.position.z + 3.0, bounds.end.z - 3.0))

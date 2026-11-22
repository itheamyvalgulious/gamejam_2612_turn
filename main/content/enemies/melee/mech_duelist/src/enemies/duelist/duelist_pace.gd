extends RefCounted
## 围绕对手的侧身踱步。双脚踩在固定的弧形足迹上，头部单独跟踪对手。

const Rig = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const SkeletonLayout = preload("res://src/enemies/duelist/duelist_rig.gd")

const DURATION := 9.30
const TRAVEL := 3.60
const RADIUS := 5.52
const START_ANGLE := -TRAVEL / (2.0 * RADIUS)
const BODY_ANGLE := deg_to_rad(64.0)
const SWORD_ROLL := 53.77
const SWORD_DEVIATION := 24.0
const SWORD_POLE := Vector3(-0.4595, 0.0421, 0.8872)
const SOLE_HEIGHT := 0.174
const HEEL := Vector3(0, -SOLE_HEIGHT, 0.13)
const TOE := Vector3(0, -SOLE_HEIGHT, -0.386)
const START_FEET := Vector2(-0.21, 0.22)
# 交替迈步。脚触地到另一只脚离地之间留出换重心的时间。
const STEPS := [
	Vector2(0.72, 1.90), Vector2(2.56, 3.76),
	Vector2(4.45, 5.66), Vector2(6.43, 7.48),
]
const LANDINGS := [0.90, 1.89, 3.36, 3.80]
# 时间、累计位移、速度。用每个时刻的速度连续连接起步、踱步和制动。
const ADVANCE := [
	Vector3(0.0, 0.0, 0.0), Vector3(0.68, 0.026, 0.16), Vector3(1.90, 0.55, 0.49),
	Vector3(3.76, 1.51, 0.55), Vector3(5.66, 2.56, 0.56),
	Vector3(7.48, 3.47, 0.29), Vector3(8.28, TRAVEL, 0.0),
]


static func apply(model, elapsed: float, center := Vector3.ZERO, eye_height := 3.80,
		watch := Vector3.INF, reverse := false) -> void:
	var time := clampf(elapsed, 0.0, DURATION)
	var travel := _distance(time)
	var angle := _angle(TRAVEL - travel if reverse else travel)
	model.position = center + Vector3(sin(angle), 0, cos(angle)) * RADIUS
	model.rotation.y = angle - BODY_ANGLE
	var world_to_body: Transform3D = model.transform.affine_inverse()
	var rig_scale: float = model.scale.x
	var motion := smoothstep(0.30, 1.35, time) * (1.0 - smoothstep(6.70, 8.28, time))
	var phase := (_step_turn(time) + (1.0 if reverse else 0.0)) * PI
	var stride := cos(phase) * motion
	var weight := cos(phase - 1.12) * motion
	var accept := cos(phase * 2.0 - 0.88) * motion
	var body := model.body as Node3D
	var torso := model.torso as Node3D
	var hip_height: float = model.HIP_HEIGHT - 0.020 + 0.026 * motion - 0.020 * accept
	body.position = Vector3(0.036 * weight, hip_height, -0.012 * motion)
	body.rotation_degrees = Vector3(-1.8 * motion, 2.1 * stride, 1.1 * weight)
	torso.rotation_degrees = Vector3(0.6 - motion * 0.7, 5.0 - 2.5 * stride, -0.8 * weight)

	# Keep the pelvis below the geometric reach of either leg without a hard snap at full extension.
	var max_height := INF
	var feet: Array[Transform3D] = []
	var toes := Vector2.ZERO
	for index in model.legs.size():
		var leg: Dictionary = model.legs[index]
		var side: float = leg["side"]
		var sample := _foot_at(time, side, reverse)
		sample.w *= smoothstep(0.0, 2.0, -sample.z)
		var target := world_to_body * _ankle(sample, side, center, rig_scale)
		feet.append(target)
		toes[index] = sample.w
		var offset := body.basis * Vector3(side * 0.319, -0.028, 0)
		var delta := target.origin - body.position - offset
		var length: float = model.THIGH + model.SHIN - 0.012
		var ceiling := target.origin.y - offset.y + sqrt(maxf(0.0, length * length - delta.x * delta.x - delta.z * delta.z))
		max_height = minf(max_height, ceiling)
	var width := 0.025
	var excess := maxf(0.0, width - absf(hip_height - max_height)) / width
	hip_height = minf(hip_height, max_height) - excess * excess * width * 0.25
	body.position.y = hip_height
	for index in model.legs.size():
		var leg: Dictionary = model.legs[index]
		var side: float = leg["side"]
		var target := feet[index]
		var hip := body.transform * Vector3(side * 0.319, -0.028, 0)
		Rig.solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, target.origin,
			Vector3(0.24 + side * 0.13, 0, -1), model.THIGH, model.SHIN)
		leg["ankle"].basis = target.basis

	var focus := watch if watch.is_finite() else center + Vector3.UP * eye_height
	aim_head(model, focus)

	var grip := Vector3(0.88 + 0.007 * weight, hip_height - 0.48, 0.24 + 0.01 * stride)
	for arm: Dictionary in model.arms:
		var side: float = arm["side"]
		var hand := grip if side > 0.0 else Vector3(-0.610 + 0.014 * weight,
			hip_height - 0.537 + 0.012 * absf(stride), -0.060 - 0.057 * stride)
		var shoulder: Vector3 = model.shoulder_anchor(arm, hand)
		var pole := SWORD_POLE if side > 0.0 else Vector3(-0.18, 0, 1)
		Rig.solve_chain(arm["shoulder"], arm["elbow"], arm["wrist"], shoulder, hand,
			pole, model.UPPER_ARM, model.FOREARM)
		if side > 0.0:
			arm["wrist"].basis = model.sword_wrist_basis(arm, SWORD_ROLL + stride, SWORD_DEVIATION)
		else:
			arm["wrist"].rotation_degrees = Vector3(-3.0 + stride * 2.0, -21.0, -6.0)
	model.finish_pose(0.29 + 0.02 * stride, 1.0, toes, -stride * 3.0)


static func brace_time(time: float) -> float:
	# Finish the current step and its toe/heel roll before loading both feet.
	for step: Vector2 in STEPS:
		if time > step.x - 0.24 and time < step.y + 0.24:
			return step.y + 0.24
	return time


static func aim_head(model, focus: Vector3) -> void:
	var body := model.body as Node3D
	var torso := model.torso as Node3D
	var head := model.head as Node3D
	var trunk := body.transform * torso.transform
	var eyes := head.position + Vector3(0, 0.23, 0)
	var ray: Vector3 = trunk.affine_inverse() * model.to_local(focus) - eyes
	var turn := clampf(atan2(-ray.x, -ray.z), -deg_to_rad(70), deg_to_rad(70))
	var tilt := clampf(atan2(ray.y, Vector2(ray.x, ray.z).length()), -deg_to_rad(36), deg_to_rad(36))
	head.basis = Basis.from_euler(Vector3(tilt, turn, 0))


static func _distance(time: float) -> float:
	for i in range(1, ADVANCE.size()):
		var end: Vector3 = ADVANCE[i]
		if time <= end.x:
			var start: Vector3 = ADVANCE[i - 1]
			var span := end.x - start.x
			var t := (time - start.x) / span
			var blend := t * t * (3.0 - 2.0 * t)
			var tangent := span * t * (1.0 - t) * (start.z * (1.0 - t) - end.z * t)
			return lerpf(start.y, end.y, blend) + tangent
	return TRAVEL


static func _step_turn(time: float) -> float:
	var last := 0.0
	for index in STEPS.size():
		var next: float = STEPS[index].y
		if time < next:
			return float(index - 1) + clampf(inverse_lerp(last, next, time), 0, 1)
		last = next
	return float(STEPS.size() - 1) + clampf(inverse_lerp(last, DURATION, time), 0, 1)


# 足迹距离、脚尖离地高度、脚掌俯仰、前脚掌关节角。
static func _foot_at(time: float, side: float, reverse: bool) -> Vector4:
	var home := START_FEET.x if side > 0.0 else START_FEET.y
	var last_landing: float = LANDINGS[2] if side > 0.0 else LANDINGS[3]
	var distance := last_landing if reverse else home
	var pitch := 0.0
	var flex := 0.0
	var first := 0 if (side > 0.0) != reverse else 1
	var lift_pitch := 7.0 if reverse else -11.0
	var land_pitch := -7.0 if reverse else 6.0
	var lift_flex := 0.0 if reverse else 9.0
	var land_flex := 5.0 if reverse else 0.0
	for i in range(first, STEPS.size(), 2):
		var step: Vector2 = STEPS[i]
		if time < step.x:
			var push := smoothstep(step.x - 0.24, step.x, time)
			return Vector4(distance, 0.0, lerpf(pitch, lift_pitch, push), lerpf(flex, lift_flex, push))
		var reverse_landing := STEPS.size() - 3 - i
		var destination: float = (LANDINGS[reverse_landing] if reverse_landing >= 0 else home) if reverse else LANDINGS[i]
		if time < step.y:
			var flight := inverse_lerp(step.x, step.y, time)
			var swing := smoothstep(0.0, 1.0, flight)
			var lift := pow(sin(PI * flight), 1.25) * (0.076 if i == STEPS.size() - 1 else 0.103)
			return Vector4(lerpf(distance, destination, swing), lift,
				lerpf(lift_pitch, land_pitch, swing), lerpf(lift_flex, land_flex, swing))
		distance = destination
		var roll := 1.0 - smoothstep(step.y, step.y + 0.24, time)
		pitch = land_pitch * roll
		flex = land_flex * roll
	return Vector4(distance, 0.0, pitch, flex)


static func _angle(distance: float) -> float:
	return START_ANGLE + distance / RADIUS


static func _ankle(sample: Vector4, side: float, center: Vector3, rig_scale: float) -> Transform3D:
	var angle := _angle(sample.x)
	var yaw := Basis(Vector3.UP, angle + deg_to_rad(-73.0 - side * 7.0))
	var foot := yaw * Basis(Vector3.RIGHT, deg_to_rad(sample.z))
	var pivot := HEEL if sample.z > 0.0 else TOE
	var contact := pivot
	if sample.z <= 0.0:
		var hinge := SkeletonLayout.TOE_HINGE
		contact = hinge + Basis(Vector3.RIGHT, deg_to_rad(sample.w)) * (pivot - hinge)
	var footprint := center + Vector3(sin(angle), 0, cos(angle)) * (RADIUS + side * 0.275 * rig_scale)
	footprint.y += (SOLE_HEIGHT + sample.y) * rig_scale
	return Transform3D(foot.scaled(Vector3.ONE * rig_scale), footprint + (yaw * pivot - foot * contact) * rig_scale)

extends RefCounted
## Continuous collapse from the live pose. All targets are in the rig's floor space.

const IK = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const SkeletonLayout = preload("res://src/enemies/duelist/duelist_rig.gd")
const RELEASE := 0.52
const KNEEL := 0.43
const WEAPON_LAND := 0.93
const BODY_LAND := 1.02
const DURATION := 1.27
const BRACED_HIP := Vector3(-0.26, 1.06, 0.19)
const BRACED_ANGLES := Vector3(-4, -7, 17)

var age := 0.0
var _pelvis: Transform3D
var _torso: Basis
var _head: Basis
var _feet: Array[Transform3D] = []
var _hands: Array[Transform3D] = []
var _leg_poles: Array[Vector3] = []
var _arm_poles: Array[Vector3] = []
var _released_weapon: Transform3D
var _wrist_deviation := 0.0
var _grip_cant := 0.0
var _toes := Vector2.ZERO
var _impulse := Vector3.ZERO
var _tilt_axis := Vector3.RIGHT


func begin(model, world_impulse := Vector3.ZERO) -> void:
	_pelvis = model.body.transform
	_torso = model.torso.basis
	_head = model.head.basis
	_wrist_deviation = model.sword_wrist_deviation()
	_grip_cant = model.sword_grip_cant
	var local: Vector3 = (model.global_basis.inverse() * world_impulse).slide(Vector3.UP)
	_impulse = local.normalized() if local.length_squared() > 0.0001 else Vector3(-0.65, 0.0, 0.76).normalized()
	_tilt_axis = Vector3.UP.cross(_impulse)
	for leg: Dictionary in model.legs:
		_feet.append(leg["ankle"].transform)
		_leg_poles.append(_bend(leg["hip"], leg["knee"], leg["ankle"]))
		_toes[_feet.size() - 1] = leg["toe"].rotation_degrees.x
	for arm: Dictionary in model.arms:
		_hands.append(arm["wrist"].transform)
		_arm_poles.append(_bend(arm["shoulder"], arm["elbow"], arm["wrist"]))


func advance(model, dt: float) -> void:
	if age >= DURATION:
		return
	var next := minf(age + dt, DURATION)
	if age < RELEASE and next >= RELEASE:
		_pose(model, RELEASE)
		_released_weapon = model.weapon_root.transform
	age = next
	_pose(model, age)
	if age >= RELEASE:
		_pose_dropped_sword(model)
	var power := (1.0 - smoothstep(0.18, 1.12, age)) * (0.9 + 0.1 * cos(age * 59.0))
	model.set_knockdown_power(power)


func _pose(model, time: float) -> void:
	var buckle := smoothstep(0.07, KNEEL, time)
	var topple := pow(smoothstep(KNEEL, BODY_LAND, time), 1.17)
	var recoil := smoothstep(0.0, 0.066, time) * (1.0 - smoothstep(0.084, 0.35, time))
	var settle := sin(PI * smoothstep(BODY_LAND, DURATION, time)) * 0.026
	var hip_pos := _pelvis.origin.lerp(BRACED_HIP, buckle)
	hip_pos = hip_pos.lerp(Vector3(-0.84, 0.64 + settle, 0.36), topple)
	hip_pos += (_impulse * 0.31 - Vector3.UP * 0.052) * recoil
	var hip_basis := _pelvis.basis.slerp(_rotation(BRACED_ANGLES), buckle)
	hip_basis = Basis(_tilt_axis, deg_to_rad(7.0) * recoil) * hip_basis
	model.body.transform = Transform3D(hip_basis.slerp(_rotation(Vector3(5, -16, 83)), topple), hip_pos)
	var chest := _torso.slerp(_rotation(Vector3(-10, 9, 4)), smoothstep(0.0, 0.38, time))
	model.torso.basis = Basis(_tilt_axis, deg_to_rad(25.0) * recoil) * chest.slerp(_rotation(Vector3(5, 2, 6)), topple)
	var head_lag := smoothstep(0.035, 0.095, time) * (1.0 - smoothstep(0.10, 0.24, time))
	model.head.basis = _head.slerp(_rotation(Vector3(14, -8, 9)), smoothstep(0.13, 1.08, time)) * _rotation(Vector3(9, -10, 5) * head_lag)
	_pose_legs(model, time, topple)
	_pose_arms(model, time, topple, recoil)


func _pose_legs(model, time: float, topple: float) -> void:
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var knee_weight := smoothstep(0.05 if i == 0 else 0.28, KNEEL, time)
		var braced := Vector3(-0.57, 0.175, 0.89) if i == 0 else Vector3(0.60, 0.175, -0.57)
		var landed := Vector3(1.19, 0.18, 1.17) if i == 0 else Vector3(1.46, 0.19, -0.45)
		var ankle := _feet[i].origin.lerp(braced, knee_weight).lerp(landed, topple)
		ankle.y += 0.08 * sin(PI * knee_weight)
		if i == 1:
			# The trailing foot attempts to catch the displaced weight before the left knee gives way.
			var catch_step := smoothstep(0.06, 0.22, time)
			ankle += _impulse * 0.31 * catch_step * (1.0 - knee_weight)
			ankle.y += 0.12 * sin(PI * catch_step) * (1.0 - knee_weight)
		var planted := _rotation(Vector3(0, 18.0 * side, 0))
		var foot_basis := _feet[i].basis.slerp(planted, knee_weight)
		foot_basis = foot_basis.slerp(_rotation(Vector3(-8, -37, 8 * side)), topple)
		var toe_angle := _toes[i] * (1.0 - smoothstep(0.05, KNEEL, time))
		var hinge := SkeletonLayout.TOE_HINGE
		var toe := hinge + Basis(Vector3.RIGHT, deg_to_rad(toe_angle)) * (Pace.TOE - hinge)
		ankle.y += maxf(0.0, -minf(ankle.y + (foot_basis * Pace.HEEL).y, ankle.y + (foot_basis * toe).y))
		var socket := Vector3(side * 0.319, -0.028, 0)
		var hip: Vector3 = model.body.transform * socket
		var bent := Vector3(side * 1.12, -0.32 if i == 0 else 0.28, -0.62).normalized()
		var pole := _leg_poles[i].slerp(bent, knee_weight)
		if time > KNEEL:
			# Sweep the knee around the leg axis. Interpolating raw poles here can
			# send the pole along the axis and flip the knee between frames.
			var braced_axis := (BRACED_HIP + _rotation(BRACED_ANGLES) * socket).direction_to(braced)
			var braced_up := Vector3.UP.slide(braced_axis).normalized()
			var angle := atan2(bent.dot(braced_up.cross(braced_axis)), bent.dot(braced_up))
			angle = lerpf(angle, deg_to_rad(40.0 if i == 0 else -18.0), topple)
			var axis := hip.direction_to(ankle)
			var up := Vector3.UP.slide(axis).normalized()
			pole = cos(angle) * up + sin(angle) * up.cross(axis)
		pole = _clear_knee(hip, ankle, pole, model.THIGH, model.SHIN)
		IK.solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, ankle, pole, model.THIGH, model.SHIN)
		leg["ankle"].basis = foot_basis


func _clear_knee(hip: Vector3, ankle: Vector3, pole: Vector3, thigh: float, shin: float) -> Vector3:
	# The joint lies on a circle around the hip-to-ankle axis. Limit its lowest point
	# by moving around that circle so thigh and shin keep their authored lengths.
	var axis := (ankle - hip).normalized()
	var span := clampf(hip.distance_to(ankle), absf(thigh - shin) + 0.001, thigh + shin - 0.001)
	var offset := (thigh * thigh - shin * shin + span * span) / (2.0 * span)
	var radius := sqrt(maxf(0.0, thigh * thigh - offset * offset))
	var up := Vector3.UP.slide(axis)
	var bend := pole.slide(axis).normalized()
	var center := hip + axis * offset
	if center.y + bend.y * radius >= 0.245 or up.length_squared() < 0.0001 or radius < 0.001:
		return pole
	var lifted := up.normalized()
	var tangent := lifted.cross(axis)
	var height := clampf((0.245 - center.y) / (radius * up.length()), -1.0, 1.0)
	var side := -1.0 if tangent.dot(bend) < 0.0 else 1.0
	return lifted * height + tangent * side * sqrt(1.0 - height * height)


func _pose_arms(model, time: float, topple: float, recoil: float) -> void:
	var brace := smoothstep(0.08, 0.49, time)
	var release := smoothstep(RELEASE - 0.04, RELEASE + 0.19, time)
	for i in model.arms.size():
		var arm: Dictionary = model.arms[i]
		var hand := arm["wrist"] as Node3D
		var brace_target := Vector3(-1.58, 0.14, -0.69) if i == 0 else Vector3(0.96, 1.72, 0.39)
		var rest := Vector3(-1.89, 0.22, -0.74) if i == 0 else Vector3(0.02, 0.45, -0.66)
		var target := _hands[i].origin.lerp(brace_target, brace).lerp(rest, topple)
		target += (_impulse * (0.34 if i == 1 else 0.26) + Vector3.UP * 0.08) * recoil
		var shoulder: Vector3 = model.shoulder_anchor(arm, target)
		var pole := _arm_poles[i].lerp(Vector3(-0.7, 1.0, 0.8) if i == 0 else Vector3(0.8, 0.12, 0.7), brace)
		IK.solve_chain(arm["shoulder"], arm["elbow"], hand, shoulder, target, pole, model.UPPER_ARM, model.FOREARM)
		if i == 0:
			var palm_down := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
			hand.basis = _hands[i].basis.slerp(palm_down, brace)
		else:
			var wrist: Basis = model.sword_wrist_basis(arm, lerpf(38.0, 25.0, brace),
				lerpf(_wrist_deviation, 13.0, brace))
			hand.basis = _hands[i].basis.slerp(wrist, brace)
	var toe_weight := 1.0 - smoothstep(0.05, KNEEL, time)
	model.finish_pose(lerpf(0.25, 0.08, brace), 1.0 - 0.8 * release, _toes * toe_weight,
		34.0 * brace, 0.0, _grip_cant * (1.0 - release))


func _pose_dropped_sword(model) -> void:
	var flight := clampf(inverse_lerp(RELEASE, WEAPON_LAND, age), 0.0, 1.0)
	var slide := smoothstep(WEAPON_LAND, DURATION, age)
	var axis := Vector3(0.89, 0, 0.46).normalized()
	var flat := Basis(axis.cross(Vector3.UP), axis, Vector3.UP)
	var basis := _released_weapon.basis.slerp(flat, smoothstep(0.0, 1.0, flight))
	var origin := _released_weapon.origin.lerp(Vector3(1.43, 0.088, 0.6), flight)
	origin.y = lerpf(_released_weapon.origin.y, 0.088, flight * flight)
	var near := origin + basis.y * -0.28
	var far: Vector3 = origin + basis.y * (model.BLADE_START + model.BLADE_LENGTH)
	origin.y += maxf(0.0, 0.088 - minf(near.y, far.y))
	origin += Vector3(0.25, 0, 0.14) * slide
	model.weapon_root.transform = Transform3D(basis, origin)
	model.sync_replay_pose()


func _bend(start: Node3D, joint: Node3D, end: Node3D) -> Vector3:
	var axis := (end.position - start.position).normalized()
	return (joint.position - start.position).slide(axis).normalized()


func _rotation(degrees: Vector3) -> Basis:
	return Basis.from_euler(degrees * (PI / 180.0))

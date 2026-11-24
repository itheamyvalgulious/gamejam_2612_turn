extends RefCounted
## Continuous collapse from the live pose. All targets are in the rig's floor space.

const IK = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const SkeletonLayout = preload("res://src/enemies/duelist/duelist_rig.gd")
const DefeatBody = preload("res://src/enemies/duelist/duelist_defeat_body.gd")
const RELEASE := 0.52
const KNEEL := 0.43
const WEAPON_LAND := 0.93
const BODY_LAND := 1.02
const DURATION := 1.27
const LIFT_OFF := 0.045
const ARMOR_RELEASE := 0.056
const HIT_LIFT_OFF := ARMOR_RELEASE
const FLIGHT_ACCELERATION := 0.125
const AIR_LAND := 0.86
const BRACED_HIP := Vector3(-0.26, 1.06, 0.19)
const BRACED_ANGLES := Vector3(-4, -7, 17)

var age := 0.0
var launched := false
var landing := Vector3.ZERO
var body_contact_time := BODY_LAND
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
var _launch_start := Vector3.ZERO
var _launch_basis := Basis.IDENTITY
var _world_impulse := Vector3.ZERO
var _landing_facing := Vector3.ZERO
var _contact_offset := Vector3.ZERO
var _hit_part := ""
var _hit_leg := -1
var _hit_arm := -1
var _terrain_path: Array[Vector3] = []
var _start_basis := Basis.IDENTITY
var _slope := Quaternion.IDENTITY
var _travel_strength := 0.0
var _compact := false
var _support_lift := 0.0
var _sword_body: DefeatBody
var _sword_balance := Vector3.ZERO
var _sword_scale := Vector3.ONE
var _sword_impact := false
var _sword_contact_seen := false


func begin(model, world_impulse := Vector3.ZERO, path: Dictionary = {}, part := "", side := 0.0) -> void:
	_world_impulse = world_impulse
	_hit_part = part
	var side_index := 0 if side < 0.0 else 1
	if part in ["thigh", "shin", "foot"]:
		_hit_leg = side_index
	elif part in ["upper_arm", "forearm"]:
		_hit_arm = side_index
	_launch_start = model.global_position
	_terrain_path.assign(path.get("samples", []))
	landing = _launch_start if _terrain_path.is_empty() else _terrain_path[-1]
	_travel_strength = clampf((landing - _launch_start).slide(Vector3.UP).length() / 4.8, 0.0, 1.0)
	launched = _travel_strength >= 0.175
	if not _terrain_path.is_empty():
		_landing_facing = path["facing"]
		_slope = Quaternion(Vector3.UP, path["normal"])
		_compact = path["compact"]
		_support_lift = path["support_lift"]
		body_contact_time = lerpf(0.68, AIR_LAND, _travel_strength)
	capture_contact_pose(model)


func capture_contact_pose(model) -> void:
	_pelvis = model.body.transform
	_torso = model.torso.basis
	_head = model.head.basis
	_wrist_deviation = model.sword_wrist_deviation()
	_grip_cant = model.sword_grip_cant
	_start_basis = model.global_basis
	_contact_offset = model.global_position - _launch_start
	var inverse := _start_basis.inverse()
	var local := (inverse * _world_impulse).slide(Vector3.UP)
	_impulse = local.normalized() if local.length_squared() > 0.0001 else Vector3(-0.65, 0.0, 0.76).normalized()
	_tilt_axis = Vector3.UP.cross(_impulse)
	if not _terrain_path.is_empty():
		var side := -(inverse * _landing_facing).slide(Vector3.UP).normalized()
		_launch_basis = Basis(side, Vector3.UP, side.cross(Vector3.UP))
	_feet.clear()
	_leg_poles.clear()
	_hands.clear()
	_arm_poles.clear()
	for leg: Dictionary in model.legs:
		_feet.append(leg["ankle"].transform)
		_leg_poles.append(_bend(leg["hip"], leg["knee"], leg["ankle"]))
		_toes[_feet.size() - 1] = leg["toe"].rotation_degrees.x
	for arm: Dictionary in model.arms:
		_hands.append(arm["wrist"].transform)
		_arm_poles.append(_bend(arm["shoulder"], arm["elbow"], arm["wrist"]))


func advance(model, dt: float, rate := 1.0) -> void:
	if age >= DURATION:
		if is_instance_valid(_sword_body):
			_sync_sword(model, rate)
		return
	var next := minf(age + dt, DURATION)
	if age < RELEASE and next >= RELEASE:
		_set_pose(model, RELEASE)
		if _terrain_path.is_empty():
			_released_weapon = model.weapon_root.transform
		else:
			_release_sword(model, rate)
	age = next
	_set_pose(model, age)
	if age >= RELEASE:
		if is_instance_valid(_sword_body):
			_sync_sword(model, rate)
		else:
			_pose_dropped_sword(model)
	var power := (1.0 - smoothstep(0.18, 1.12, age)) * (0.9 + 0.1 * cos(age * 59.0))
	if model.armor_breached:
		power *= (1.0 - smoothstep(0.02, 0.25, age)) * (0.16 + 0.14 * sin(age * 103.0))
	model.set_knockdown_power(power)


func _set_pose(model, time: float) -> void:
	if not _terrain_path.is_empty():
		_airborne_pose(model, time)
	else:
		_pose(model, time)


func _airborne_pose(model, time: float) -> void:
	var lift_off := HIT_LIFT_OFF if not _hit_part.is_empty() else LIFT_OFF
	var arc := clampf(inverse_lerp(lift_off, body_contact_time, time), 0.0, 1.0)
	# Integrate the acceleration ramp so speed never surges and dips as the body takes off.
	var ramp := minf(arc / FLIGHT_ACCELERATION, 1.0)
	arc = (FLIGHT_ACCELERATION * ramp * ramp * ramp * (1.0 - 0.5 * ramp) \
		+ maxf(0.0, arc - FLIGHT_ACCELERATION)) / (1.0 - 0.5 * FLIGHT_ACCELERATION)
	var forward := 0.89 * (1.0 - pow(1.0 - arc, 1.55))
	forward += 0.11 * smoothstep(body_contact_time, DURATION, time)
	var height := 4.0 * lerpf(0.16, 1.08, _travel_strength) * arc * (1.0 - arc)
	var bounce := 0.08 * sin(PI * clampf((time - body_contact_time) / 0.22, 0.0, 1.0))
	var sample := forward * (_terrain_path.size() - 1)
	var index := mini(floori(sample), _terrain_path.size() - 1)
	var support := _terrain_path[index].lerp(_terrain_path[mini(index + 1, _terrain_path.size() - 1)], sample - index)
	var contact_weight := smoothstep(0.47, body_contact_time, time)
	model.global_position = support + _contact_offset * (1.0 - smoothstep(0.0, 0.22, arc)) \
		+ Vector3.UP * (height + bounce + _support_lift * contact_weight)

	var hip_recoil := _body_recoil(time, 0.026, 0.135)
	var chest_recoil := _body_recoil(time, 0.043, 0.166)
	var turn := smoothstep(0.060, 0.51, time)
	var drop := smoothstep(0.32, body_contact_time, time)
	model.global_basis = Basis(Quaternion.IDENTITY.slerp(_slope, drop)) * _start_basis
	var hip_end := _launch_basis * _rest_offset(Vector3(-0.72, 0.69, 0.22))
	var hip_position := _pelvis.origin.lerp(hip_end, drop) + _impulse * (0.29 * hip_recoil)
	if _hit_part == "pelvis":
		hip_position += _impulse * 0.21 * _contact_jolt(time)
	hip_position.y += 0.16 * sin(PI * arc)
	var tilt := _launch_basis * _rotation(Vector3(4, -12, 74 if _compact else 83))
	var hip_basis := Basis(_tilt_axis, deg_to_rad(8.0) * hip_recoil) * _pelvis.basis.slerp(tilt, turn)
	model.body.transform = Transform3D(hip_basis, hip_position)
	model.torso.basis = Basis(_tilt_axis, deg_to_rad(19.0) * chest_recoil) * _torso.slerp(_rotation(Vector3(8, 3, 5)), turn)
	model.head.basis = _head.slerp(_rotation(Vector3(17, -6, 9)), smoothstep(0.085, 0.67, time))
	_apply_chassis_recoil(model, time)
	_airborne_legs(model, time, drop)
	_airborne_arms(model, time, drop, chest_recoil)


func _airborne_legs(model, time: float, drop: float) -> void:
	var toe_weight := 1.0 - smoothstep(0.08, 0.39, time)
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var tuck_start := 0.050 if i == _hit_leg else 0.103
		var tuck := smoothstep(tuck_start, 0.40, time)
		var lifted := Vector3(0.50, 0.94, 0.58) if i == 0 else Vector3(1.01, 0.70, -0.41)
		var laid := Vector3(1.10, 0.180, 1.16) if i == 0 else Vector3(1.47, 0.195, -0.44)
		var ankle := _feet[i].origin.lerp(_launch_basis * lifted, tuck).lerp(_launch_basis * _rest_offset(laid), drop)
		ankle += _leg_recoil(i, time)
		var air_angle := _launch_basis * _rotation(Vector3(-15, 11.0 * side, 9.0 * side))
		var laid_angle := _launch_basis * _rotation(Vector3(-8, -37, 8.0 * side))
		var foot_basis := _feet[i].basis.slerp(air_angle, tuck).slerp(laid_angle, drop)
		if i == _hit_leg:
			foot_basis *= _rotation(Vector3(-19.0, 0.0, 0.0) * _contact_jolt(time))
		ankle.y += _foot_clearance(ankle.y, foot_basis, _toes[i] * toe_weight)
		var hip: Vector3 = model.body.transform * Vector3(side * 0.319, -0.028, 0)
		var pole := _leg_poles[i].slerp(_launch_basis * Vector3(side * 0.40, 0.75, -1.0).normalized(), tuck)
		if i == _hit_leg:
			pole += _impulse * (0.60 * _contact_jolt(time))
		pole = _clear_knee(hip, ankle, pole, model.THIGH, model.SHIN)
		IK.solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, ankle, pole, model.THIGH, model.SHIN)
		leg["ankle"].basis = foot_basis


func _airborne_arms(model, time: float, drop: float, recoil: float) -> void:
	var spread := smoothstep(0.085, 0.39, time)
	var release := smoothstep(RELEASE - 0.04, RELEASE + 0.16, time)
	for i in model.arms.size():
		var arm: Dictionary = model.arms[i]
		var hand := arm["wrist"] as Node3D
		var airborne := Vector3(-1.30, 1.32, -0.63) if i == 0 else Vector3(0.77, 1.78, 0.62)
		var laid := Vector3(-1.83, 0.26, -0.70) if i == 0 else Vector3(0.04, 0.46, -0.65)
		var target := _hands[i].origin.lerp(_launch_basis * airborne, spread).lerp(_launch_basis * _rest_offset(laid), drop)
		target += (_impulse * 0.38 + Vector3.UP * 0.16) * recoil
		target += _arm_recoil(i, time)
		var shoulder: Vector3 = model.shoulder_anchor(arm, target)
		var bend := Vector3(-0.7, 1.0, 0.8) if i == 0 else Vector3(0.8, 0.35, 0.7)
		var pole := _arm_poles[i].lerp(_launch_basis * bend, spread)
		if i == _hit_arm:
			pole += _impulse * (0.54 * _contact_jolt(time))
		IK.solve_chain(arm["shoulder"], arm["elbow"], hand, shoulder, target, pole, model.UPPER_ARM, model.FOREARM)
		var wrist: Basis = model.sword_wrist_basis(arm, 32.0, lerpf(_wrist_deviation, 13.0, spread))
		if i == 0:
			wrist = _launch_basis * Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
		hand.basis = _hands[i].basis.slerp(wrist, spread)
	model.finish_pose(lerpf(0.25, 0.09, spread), 1.0 - 0.8 * release, _toes * (1.0 - spread),
		30.0 * spread, 0.0, _grip_cant * (1.0 - release))


func _rest_offset(offset: Vector3) -> Vector3:
	return offset * Vector3(0.57, 1.0, 0.64) if _compact else offset


func _release_sword(model, rate: float) -> void:
	var blade_end: float = model.BLADE_START + model.BLADE_LENGTH
	_sword_balance = Vector3(0.02, (blade_end - 0.27) * 0.5, 0.0)
	_sword_scale = model.weapon_root.global_basis.get_scale()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.31, blade_end + 0.29, 0.111) * _sword_scale
	var basis: Basis = model.weapon_root.global_basis.orthonormalized()
	var pose := Transform3D(basis, model.weapon_root.to_global(_sword_balance))
	var travel := (landing - _launch_start).slide(Vector3.UP) * 0.55
	_sword_body = DefeatBody.new()
	_sword_body.name = "DroppedBlade"
	_sword_body.contact_monitor = true
	_sword_body.max_contacts_reported = 2
	_sword_body.body_entered.connect(_sword_hit_world)
	model.add_child(_sword_body)
	_sword_body.launch(pose, shape, travel + Vector3.DOWN * 1.2, basis.x * 3.4 + basis.y * 0.9, rate)


func _sword_hit_world(_surface: Node) -> void:
	if not _sword_contact_seen:
		_sword_contact_seen = true
		_sword_impact = true


func take_sword_impact(previous: float) -> bool:
	if not is_instance_valid(_sword_body):
		return previous < WEAPON_LAND and age >= WEAPON_LAND
	var hit := _sword_impact
	_sword_impact = false
	return hit


func _sync_sword(model, rate: float) -> void:
	_sword_body.simulation_rate = rate
	var basis := _sword_body.global_basis.scaled_local(_sword_scale)
	var at := _sword_body.global_position - basis * _sword_balance
	model.weapon_root.global_transform = Transform3D(basis, at)
	model.sync_replay_pose()


func _pose(model, time: float) -> void:
	var buckle := smoothstep(0.07, KNEEL, time)
	var topple := pow(smoothstep(KNEEL, BODY_LAND, time), 1.17)
	var hip_recoil := _body_recoil(time, 0.026, 0.114)
	var chest_recoil := _body_recoil(time, 0.043, 0.146)
	var settle := sin(PI * smoothstep(BODY_LAND, DURATION, time)) * 0.026
	var hip_pos := _pelvis.origin.lerp(BRACED_HIP, buckle)
	hip_pos = hip_pos.lerp(Vector3(-0.84, 0.64 + settle, 0.36), topple)
	hip_pos += (_impulse * 0.31 - Vector3.UP * 0.052) * hip_recoil
	if _hit_part == "pelvis":
		hip_pos += _impulse * 0.21 * _contact_jolt(time)
	var hip_basis := _pelvis.basis.slerp(_rotation(BRACED_ANGLES), buckle)
	hip_basis = Basis(_tilt_axis, deg_to_rad(7.0) * hip_recoil) * hip_basis
	model.body.transform = Transform3D(hip_basis.slerp(_rotation(Vector3(5, -16, 83)), topple), hip_pos)
	var chest := _torso.slerp(_rotation(Vector3(-10, 9, 4)), smoothstep(0.0, 0.38, time))
	model.torso.basis = Basis(_tilt_axis, deg_to_rad(19.0) * chest_recoil) * chest.slerp(_rotation(Vector3(5, 2, 6)), topple)
	var head_lag := smoothstep(0.035, 0.095, time) * (1.0 - smoothstep(0.10, 0.24, time))
	model.head.basis = _head.slerp(_rotation(Vector3(14, -8, 9)), smoothstep(0.13, 1.08, time)) * _rotation(Vector3(9, -10, 5) * head_lag)
	_apply_chassis_recoil(model, time)
	_pose_legs(model, time, topple)
	_pose_arms(model, time, topple, chest_recoil)


func _pose_legs(model, time: float, topple: float) -> void:
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var knee_weight := smoothstep(0.05 if i == 0 else 0.28, KNEEL, time)
		var braced := Vector3(-0.57, 0.175, 0.89) if i == 0 else Vector3(0.60, 0.175, -0.57)
		var landed := Vector3(1.19, 0.18, 1.17) if i == 0 else Vector3(1.46, 0.19, -0.45)
		var ankle := _feet[i].origin.lerp(braced, knee_weight).lerp(landed, topple)
		ankle += _leg_recoil(i, time)
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
		ankle.y += _foot_clearance(ankle.y, foot_basis, toe_angle)
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
		if i == _hit_leg:
			pole += _impulse * (0.60 * _contact_jolt(time))
		pole = _clear_knee(hip, ankle, pole, model.THIGH, model.SHIN)
		IK.solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, ankle, pole, model.THIGH, model.SHIN)
		leg["ankle"].basis = foot_basis


func _foot_clearance(ankle_height: float, basis: Basis, toe_angle: float) -> float:
	var hinge := SkeletonLayout.TOE_HINGE
	var toe := hinge + Basis(Vector3.RIGHT, deg_to_rad(toe_angle)) * (Pace.TOE - hinge)
	return maxf(0.0, -minf(ankle_height + (basis * Pace.HEEL).y, ankle_height + (basis * toe).y))


func _contact_jolt(time: float) -> float:
	# Let the hit joint settle into the pelvis and chest response while both are moving.
	return smoothstep(0.0, 0.025, time) * (1.0 - smoothstep(0.035, 0.225, time))


func _body_recoil(time: float, begin_at: float, peak_at: float) -> float:
	return smoothstep(begin_at, peak_at, time) * (1.0 - smoothstep(peak_at, 0.37, time))


func _leg_recoil(index: int, time: float) -> Vector3:
	if index != _hit_leg:
		return Vector3.ZERO
	return (_impulse * 0.34 + Vector3.UP * 0.20) * _contact_jolt(time)


func _arm_recoil(index: int, time: float) -> Vector3:
	if index != _hit_arm:
		return Vector3.ZERO
	return (_impulse * 0.43 + Vector3.UP * 0.08) * _contact_jolt(time)


func _apply_chassis_recoil(model, time: float) -> void:
	if _hit_part == "chest":
		model.torso.basis = Basis(_tilt_axis, deg_to_rad(12.0) * _contact_jolt(time)) * model.torso.basis
	elif _hit_part == "head":
		model.head.basis = Basis(_tilt_axis, deg_to_rad(15.0) * _contact_jolt(time)) * model.head.basis


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
		target += _arm_recoil(i, time)
		var shoulder: Vector3 = model.shoulder_anchor(arm, target)
		var pole := _arm_poles[i].lerp(Vector3(-0.7, 1.0, 0.8) if i == 0 else Vector3(0.8, 0.12, 0.7), brace)
		if i == _hit_arm:
			pole += _impulse * (0.54 * _contact_jolt(time))
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

extends RefCounted
## Keeps each support foot planted while the second cut flows into combat footwork.

const Rig = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Alert = preload("res://src/enemies/duelist/duelist_alert_pose.gd")
const Units = preload("res://src/core/units.gd")
const RECOVERY := 0.28
const MIN_REACH_MARGIN := 0.035
const RUN_RANGE := 10.0 / Units.M_PER_UNIT
const RUN_ENTRY_RANGE := 10.45 / Units.M_PER_UNIT
const SUPPORT_REACH := 1.45

enum Step { ORBIT, PURSUE, CLOSE, RETREAT, TURN, BRAKE, PRESS }

const MOVE_NAMES := ["侧步绕行", "追击", "短步抢进", "撤半步", "换脚转身", "落脚急停", "举刀抢进"]
const STEP_DURATIONS := [0.34, 0.22, 0.27, 0.32, 0.37, 0.28, 0.25]
const FOOT_LIFTS := [0.18, 0.43, 0.20, 0.15, 0.18, 0.105, 0.26]
const FORWARD_LEANS := [0.0, 0.265, 0.16, -0.065, 0.025, -0.068, 0.185]

var motion := Step.ORBIT
var age := 0.0
var active := false
var moving := false
var landed := false
var press_range := 0.0
var press_haste := 0.0
var next_foot: int:
	get:
		return _swing
var recovery_age: float:
	get:
		return maxf(0.0, age - _recovery_delay)

var _step_age := 0.0
var _step_duration := 0.34
var _running := false
var _wait := 0.0
var _recovery_delay := 0.0
var _swing := 0
var _orbit := -1.0
var _root_from := Vector3.ZERO
var _root_to := Vector3.ZERO
var _entry_speed := 0.0
var _exit_velocity := Vector3.ZERO
var _entry_lean := 0.0
var _exit_lean := 0.0
var _entry_run := 0.0
var _exit_run := 0.0
var _foot_to := Transform3D.IDENTITY
var _yaw_from := 0.0
var _yaw_to := 0.0
var _entry_yaw_speed := 0.0
var _exit_yaw_speed := 0.0
var _feet: Array[Transform3D] = []
var _knees: Array[Vector3] = []
var _toes := Vector2.ZERO
var _hip := Transform3D.IDENTITY
var _chest := Basis.IDENTITY
var _head := Basis.IDENTITY
var _arms: Array[Dictionary] = []
var _wrist_roll := 0.0
var _wrist_deviation := 10.0


func reset() -> void:
	active = false
	moving = false
	landed = false
	age = 0.0
	motion = Step.ORBIT
	press_range = 0.0
	press_haste = 0.0
	_running = false
	_entry_speed = 0.0
	_exit_velocity = Vector3.ZERO
	_entry_yaw_speed = 0.0
	_exit_yaw_speed = 0.0
	_entry_lean = 0.0
	_exit_lean = 0.0
	_entry_run = 0.0
	_exit_run = 0.0
	_feet.clear()
	_knees.clear()
	_arms.clear()


func begin(model, wait: float, next_foot := 0, wrist_deviation := 10.0) -> void:
	reset()
	active = true
	_swing = next_foot
	_recovery_delay = wait
	_wait = wait
	_step_age = 0.0
	_root_from = model.global_position
	_root_to = _root_from
	_yaw_from = model.global_rotation.y
	_yaw_to = _yaw_from
	_hip = model.body.transform
	_chest = model.torso.basis
	_head = model.head.basis
	var trunk: Transform3D = model.body.transform * model.torso.transform
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var foot := leg["ankle"] as Node3D
		_feet.append(model.keep_sole_above_floor(foot.global_transform))
		var hip: Vector3 = leg["hip"].position
		var knee: Vector3 = leg["knee"].position
		_knees.append((knee - hip).slide((foot.position - hip).normalized()).normalized())
		_toes[i] = leg["toe"].rotation_degrees.x
	for arm: Dictionary in model.arms:
		var shoulder := arm["shoulder"] as Node3D
		var elbow := arm["elbow"] as Node3D
		var wrist := arm["wrist"] as Node3D
		var bend := (elbow.position - shoulder.position).slide((wrist.position - shoulder.position).normalized())
		_arms.append({
			"hand": trunk.affine_inverse() * wrist.position,
			"shoulder": trunk.affine_inverse() * shoulder.position,
			"bend": trunk.basis.inverse() * bend.normalized(),
			"wrist": elbow.basis.inverse() * wrist.basis,
		})
	var angles: Vector2 = model.sword_arm_angles(wrist_deviation)
	_wrist_roll = rad_to_deg(angles.y)
	_wrist_deviation = wrist_deviation
	_foot_to = _feet[_swing]


func motion_label() -> String:
	return MOVE_NAMES[motion] if moving else "收势 · 戒备"


func advance(model, dt: float, focus: Vector3, cover: Array, bounds: AABB, stop_on_landing := false) -> float:
	landed = false
	if dt <= 0.0:
		return 0.0
	age += dt
	var motion_dt := dt
	if not moving:
		var waiting := minf(_wait, motion_dt)
		_wait -= waiting
		motion_dt -= waiting
		if _wait <= 0.0:
			moving = true
			_start_step(model, focus, cover, bounds)
	_step_age += motion_dt
	var unused := 0.0
	while _step_age >= _step_duration:
		var remainder := _step_age - _step_duration
		model.global_position = _root_to
		model.global_rotation.y = _yaw_to
		_feet[_swing] = _foot_to
		_feet[1 - _swing] = _support_foot(1.0)
		_toes[_swing] = 0.0
		var emphatic := _is_forward_step(motion) or motion == Step.BRAKE
		Snd.play_at("step", _foot_to.origin, {"gain": 0.49 if emphatic else 0.34})
		_swing = 1 - _swing
		landed = true
		_start_step(model, focus, cover, bounds)
		if stop_on_landing:
			unused = remainder
			age -= unused
			break
		_step_age = remainder

	if age > _recovery_delay:
		_pose(model, focus)
	return unused


func _start_step(model, focus: Vector3, cover: Array, bounds: AABB) -> void:
	var scale: float = model.global_basis.get_scale().x
	_root_from = model.global_position
	var sight := (focus - _root_from).slide(Vector3.UP)
	var distance := sight.length()
	_yaw_from = model.global_rotation.y
	var wanted := atan2(-sight.x, -sight.z) if distance > 0.10 else _yaw_from
	var turn := angle_difference(_yaw_from, wanted)
	var previous := motion
	motion = _choose_step(distance, turn)
	if _is_forward_step(previous) and not _is_forward_step(motion):
		motion = Step.BRAKE
	# Open the foot on the side of the turn, then collect the other foot on the next step.
	if motion == Step.TURN and previous != Step.TURN:
		_swing = 0 if turn > 0.0 else 1
	var angle_limit := 42.0 if motion == Step.TURN else 25.0
	if motion == Step.BRAKE:
		angle_limit = 8.0
	angle_limit = deg_to_rad(angle_limit)
	_yaw_to = _yaw_from + clampf(turn, -angle_limit, angle_limit)
	var facing := Basis(Vector3.UP, _yaw_to)
	var forward := -facing.z
	var across := facing.x

	var stride := _stride(distance, scale)
	if motion == Step.BRAKE and absf(turn) > deg_to_rad(38.0):
		stride = Vector2.ZERO
	var move := forward * stride.x + across * (_orbit * stride.y)
	var radius := 1.1 * scale
	_root_to = _clear_travel(_root_from + move * scale, cover, bounds, radius)
	if motion != Step.TURN and motion != Step.BRAKE and _root_to.distance_squared_to(_root_from) < 0.045:
		_orbit *= -1.0
		move = forward * stride.x + across * _orbit * maxf(stride.y, 0.39)
		_root_to = _clear_travel(_root_from + move * scale, cover, bounds, radius)

	_step_duration = float(STEP_DURATIONS[motion])
	if motion == Step.PRESS:
		_step_duration = lerpf(_step_duration, 0.195, press_haste)
	var travel := _root_to - _root_from
	var carries_momentum := motion != Step.BRAKE and motion != Step.TURN
	_entry_speed = maxf(0.0, _exit_velocity.dot(travel.normalized()))
	_exit_velocity = travel / _step_duration if carries_momentum else Vector3.ZERO
	_entry_yaw_speed = _exit_yaw_speed
	_exit_yaw_speed = (_yaw_to - _yaw_from) / _step_duration if carries_momentum else 0.0
	_entry_lean = _exit_lean
	_entry_run = _exit_run
	_exit_run = 1.0 if motion == Step.PURSUE else 0.0
	var forward_step := _is_forward_step(motion)
	_exit_lean = float(FORWARD_LEANS[motion]) if forward_step else 0.0

	var side := -1.0 if _swing == 0 else 1.0
	var lead := 0.29 if motion == Step.BRAKE else 0.16
	var stance := 0.47 if motion == Step.PURSUE else 0.60
	var center := _root_to + (across * side * stance + forward * lead + move * 0.22) * scale
	var spread := side * (center - _feet[1 - _swing].origin).dot(across)
	center += across * side * clampf((stance + 0.24) * scale - spread, 0.0, 0.46 * scale)
	center = _clear_position(center, cover, bounds, 0.23 * scale)
	center.y = model.global_position.y + Pace.SOLE_HEIGHT * scale
	var yaw := _yaw_to - side * deg_to_rad(9.0)
	_foot_to = model.keep_sole_above_floor(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), center))

	_step_age = 0.0


func _is_forward_step(step: int) -> bool:
	return step == Step.PURSUE or step == Step.CLOSE or step == Step.PRESS


func left_can_support(model) -> bool:
	var foot := _feet[0]
	var toe := foot * Pace.TOE
	return toe.y <= model.floor_height(toe) + 0.09 and model.to_local(foot.origin).z <= SUPPORT_REACH


func _choose_step(distance: float, turn: float) -> int:
	# Clear the running stance at ten metres, with room to settle before re-entry.
	var threshold := RUN_RANGE if _running else RUN_ENTRY_RANGE
	_running = distance > threshold
	if absf(turn) > deg_to_rad(38.0):
		return Step.TURN
	if _running:
		return Step.PURSUE
	var press_margin := 0.0 if motion == Step.PRESS else lerpf(0.40, 0.15, press_haste)
	if press_range > 0.0 and distance > press_range + press_margin:
		return Step.PRESS
	var close_range := 6.20 if motion == Step.CLOSE else 6.65
	if distance >= close_range:
		return Step.CLOSE
	var retreat_range := 4.55 if motion == Step.RETREAT else 4.10
	if distance < retreat_range:
		return Step.RETREAT
	return Step.ORBIT


func _stride(distance: float, scale: float) -> Vector2:
	match motion:
		Step.TURN:
			return Vector2.ZERO
		Step.BRAKE:
			return Vector2(clampf((distance - 4.8) * 0.19 / scale, 0.0, 0.24), 0.0)
		Step.PURSUE:
			return Vector2(2.62, 0.08)
		Step.PRESS:
			var reach := lerpf(1.59, 2.34, press_haste)
			# A still target gets a shorter last step. Carry speed when chasing a retreat.
			var step := clampf((distance - press_range) / scale + press_haste * reach, 0.50, reach)
			return Vector2(step, 0.055)
		Step.CLOSE:
			return Vector2(clampf((distance - 5.65) / scale, 0.62, 1.10), 0.09)
		Step.RETREAT:
			return Vector2(-clampf((4.95 - distance) / scale, 0.44, 0.72), 0.19)
		_:
			return Vector2(clampf((distance - 5.55) * 0.32, -0.32, 0.38), 0.61)


func _root_progress(stride: float, duration: float) -> float:
	var distance := _root_from.distance_to(_root_to)
	if distance < 0.001:
		return stride
	if motion == Step.BRAKE:
		# Spend the remaining travel while braking, then hold the root until the foot settles.
		var stop_time := minf(duration, 2.0 * distance / maxf(_entry_speed, 0.001))
		var braking := minf(1.0, stride * duration / stop_time)
		return braking * (2.0 - braking)
	# Carry the outgoing speed into the next step, including the side and retreat steps.
	var entry := minf(_entry_speed * duration / distance, 1.8)
	var exit := _exit_velocity.length() * duration / distance
	return _step_progress(stride, entry, exit)


func _step_progress(stride: float, entry: float, exit: float) -> float:
	var tangent := stride * (1.0 - stride)
	return stride * stride * (3.0 - 2.0 * stride) + tangent * (entry * (1.0 - stride) - exit * stride)


func _support_foot(stride: float) -> Transform3D:
	var foot := _feet[1 - _swing]
	if motion != Step.PRESS and motion != Step.PURSUE:
		return foot
	var toe := foot * Pace.TOE
	var heel := smoothstep(0.50, 1.0, stride)
	foot.basis *= Basis(Vector3.RIGHT, deg_to_rad(-20.0) * heel)
	foot.origin = toe - foot.basis * Pace.TOE
	# At long strides the rear toe releases into the next swing, before the hips
	# would have to sink to keep both legs in reach.
	var travel := (_root_to - _root_from).slide(Vector3.UP)
	if not travel.is_zero_approx():
		var forward := travel.normalized()
		var scale := foot.basis.get_scale().y
		var overreach := maxf(0.0, (_root_to - foot.origin).dot(forward) - SUPPORT_REACH * scale)
		var release := smoothstep(0.62, 1.0, stride)
		foot.origin += (forward + Vector3.UP * 0.24) * (overreach * release)
	return foot


func _pose(model, focus: Vector3) -> void:
	var duration := _step_duration
	var stride := clampf(_step_age / duration, 0.0, 1.0)
	var travel := smoothstep(0.0, 1.0, stride)
	model.global_position = _root_from.lerp(_root_to, _root_progress(stride, duration))
	var turn := _yaw_to - _yaw_from
	var body_turn := travel
	if motion == Step.TURN:
		body_turn = smoothstep(0.16, 1.0, stride)
	elif absf(turn) > 0.001 and motion != Step.BRAKE:
		var entry := clampf(_entry_yaw_speed * duration / turn, 0.0, 1.8)
		body_turn = _step_progress(stride, entry, _exit_yaw_speed * duration / turn)
	model.global_rotation.y = _yaw_from + turn * body_turn
	var scale: float = model.global_basis.get_scale().x
	var feet := _feet.duplicate()
	feet[1 - _swing] = _support_foot(stride)
	var toes := _toes
	var raised := sin(PI * stride)
	var foot: Transform3D = _feet[_swing].interpolate_with(_foot_to, travel)
	var clearance := raised * raised
	foot.origin.y += clearance * float(FOOT_LIFTS[motion]) * scale
	# Point the toe on lift-off, then open the ankle for the next contact.
	var pitch := -cos(PI * stride) * clearance
	pitch *= -9.0 if motion == Step.RETREAT else (6.0 if motion == Step.TURN else 13.0)
	foot.basis *= Basis(Vector3.RIGHT, deg_to_rad(pitch))
	feet[_swing] = foot
	toes[_swing] *= 1.0 - travel

	var blend := smoothstep(0.0, RECOVERY, recovery_age)
	var support := -1.0 if _swing == 1 else 1.0
	var body := model.body as Node3D
	var chest := model.torso as Node3D
	var tilt := raised * support
	var lean := lerpf(_entry_lean, _exit_lean, smoothstep(0.0, 0.8, stride))
	if not _is_forward_step(motion):
		lean += float(FORWARD_LEANS[motion]) * raised
	# The hips take the load after the lead foot reaches forward to brake.
	var weight_catch := smoothstep(0.29, 0.61, stride) * (1.0 - smoothstep(0.65, 1.0, stride)) if motion == Step.BRAKE else 0.0
	var run := lerpf(_entry_run, _exit_run, smoothstep(0.0, 1.0, stride))
	var hip_drop := lerpf(Alert.HIP_DROP, 0.105, run)
	var ready_hip := Vector3(0.054 * tilt, model.HIP_HEIGHT - hip_drop + 0.026 * clearance - 0.25 * absf(lean),
		-0.02 - lean * 0.46) + Vector3(0.03 * support, -0.12, 0.08) * weight_catch
	body.position = _hip.origin.lerp(ready_hip, blend)
	var load_right := smoothstep(0.0, 0.065, recovery_age) * (1.0 - smoothstep(0.09, 0.22, recovery_age))
	body.position.x += 0.075 * load_right
	var hip_pitch := lerpf(Alert.HIP_PITCH, -0.055, run)
	var chest_pitch := lerpf(Alert.CHEST_PITCH, -0.046, run)
	body.basis = _hip.basis.slerp(Basis.from_euler(Vector3(hip_pitch - lean, 0.06 * tilt, 0.05 * tilt)), blend)
	chest.basis = _chest.slerp(Basis.from_euler(Vector3(chest_pitch - lean * 0.55, -0.08 * tilt, -0.032 * tilt)), blend)
	_pose_feet(model, feet, blend)
	Pace.aim_head(model, focus)
	model.head.basis = _head.slerp(model.head.basis, smoothstep(0.0, 0.16, recovery_age))
	# Each swing ends where the opposite swing begins, including across a foot plant.
	var arm_swing := -cos(PI * stride) * support
	_pose_arms(model, blend, tilt, lean, run, arm_swing)
	var carrying := run * blend
	var armor_clearance := 0.085 * carrying + 0.045 * sin(PI * carrying)
	model.finish_pose(lerpf(0.24, 0.29, blend), 1.0, toes, 0.0, armor_clearance)


func _pose_feet(model, feet: Array[Transform3D], blend: float) -> void:
	var local: Transform3D = model.global_transform.affine_inverse()
	var body := model.body as Node3D
	var targets: Array[Transform3D] = []
	var ceiling := INF
	var reach: float = model.THIGH + model.SHIN - MIN_REACH_MARGIN
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var target := local * (model.keep_sole_above_floor(feet[i]) as Transform3D)
		targets.append(target)
		var offset := body.basis * Vector3(side * 0.319, -0.028, 0.0)
		var planar := (target.origin - body.position - offset).slide(Vector3.UP)
		ceiling = minf(ceiling, target.origin.y - offset.y + sqrt(maxf(0.0, reach * reach - planar.length_squared())))

	# The sweep finishes with longer legs than the mobile stance. Blend the reach margin in with the pose.
	body.position.y = minf(body.position.y, ceiling + 0.028 * (1.0 - blend))
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var hip := body.transform * Vector3(side * 0.319, -0.028, 0.0)
		var forward := -targets[i].basis.z.slide(Vector3.UP).normalized()
		var pole := _knees[i].lerp(forward + Vector3(side * 0.18, 0.0, 0.0), blend)
		Rig.solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, targets[i].origin, pole, model.THIGH, model.SHIN)
		leg["ankle"].basis = targets[i].basis


func _pose_arms(model, blend: float, tilt: float, lean: float, run: float, arm_swing: float) -> void:
	var pelvis: Transform3D = model.body.transform
	var trunk: Transform3D = pelvis * model.torso.transform
	var carrying := run * blend
	for i in model.arms.size():
		var arm: Dictionary = model.arms[i]
		var start := _arms[i]
		var right: bool = i == 1
		var wrist := arm["wrist"] as Node3D
		var guard := Alert.WEAPON_HAND if right else Alert.SUPPORT_HAND
		guard.y += lean * (0.18 if right else 0.43)
		guard.z -= lean * (0.48 if right else 0.52)
		if right:
			guard.x += maxf(0.0, lean) * 0.88
			# Keep the grip beside the hip as the chest pitches forward and counter-rotates.
			var side_carry := pelvis.origin + Vector3(1.06, -0.26, 0.23 - 0.10 * arm_swing)
			guard = guard.lerp(trunk.affine_inverse() * side_carry, run)
			# Raise the hilt briefly while the blade passes in front of the leg.
			guard += Vector3(0.21, 0.12, -0.18) * sin(PI * run)
		else:
			var running_hand := Vector3(-0.70, -0.21 - 0.10 * arm_swing, -0.48 + 0.30 * arm_swing)
			guard = guard.lerp(running_hand, smoothstep(0.0, 0.78, run))
		var hand := (start["hand"] as Vector3).lerp(guard, blend)
		if right:
			hand.x += 0.13 * sin(PI * blend)
		hand = trunk * hand
		var bend := Alert.WEAPON_POLE if right else Alert.SUPPORT_POLE
		if not right:
			bend = bend.lerp(Vector3(-0.42, -0.25, 0.81), run)
		var pole := trunk.basis * (start["bend"] as Vector3).lerp(bend, blend)
		var shoulder := (trunk * (start["shoulder"] as Vector3)).lerp(model.shoulder_anchor(arm, hand), blend)
		if right and carrying > 0.0:
			# Blend elbow directions around the reach axis so the hinge never flips sides.
			var reach := (hand - shoulder).normalized()
			var outside := Vector3.RIGHT.slide(reach).normalized()
			var relaxed := outside.rotated(reach, deg_to_rad(128.0))
			pole = pole.slide(reach).normalized().slerp(relaxed, smoothstep(0.0, 0.86, carrying))
		Rig.solve_chain(arm["shoulder"], arm["elbow"], wrist, shoulder, hand, pole, model.UPPER_ARM, model.FOREARM)
		if right:
			var deviation := lerpf(lerpf(_wrist_deviation, Alert.WRIST_DEVIATION, blend), 23.0, carrying)
			var roll := lerpf(lerpf(_wrist_roll, Alert.WRIST_ROLL, blend), -64.0, carrying)
			wrist.basis = model.sword_wrist_basis(arm, roll, deviation)
		else:
			var open := Basis.from_euler(Vector3(-0.08, -0.27, 0.08))
			wrist.basis = arm["elbow"].basis * (start["wrist"] as Basis).slerp(open, blend)


func _clear_travel(destination: Vector3, cover: Array, bounds: AABB, radius: float) -> Vector3:
	for obstacle: Dictionary in cover:
		var physical_radius := maxf(0.35, float(obstacle["r"]) - 1.2)
		destination = Hit.slide_around_body(_root_from, destination, obstacle["c"], physical_radius + radius)
	return _clear_position(destination, cover, bounds, radius)


func _clear_position(position: Vector3, cover: Array, bounds: AABB, radius: float) -> Vector3:
	var floor_position := Hit.resolve_circles(position, radius, cover, position.y)
	if bounds.size.length_squared() > 0.1:
		var edge := bounds.end
		floor_position.x = clampf(floor_position.x, bounds.position.x + 3.0, edge.x - 3.0)
		floor_position.z = clampf(floor_position.z, bounds.position.z + 3.0, edge.z - 3.0)
	return floor_position

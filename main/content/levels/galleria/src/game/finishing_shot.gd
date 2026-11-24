extends RefCounted
## One animation clock connects the recorded lead-in to the live follow-through.

const CONTACT_RATE := 0.17
const CONTACT_DURATION := 1.12
const SPEED_RECOVERY := 0.72
const SWING_START_RATE := 0.055
const SWING_END_RATE := 1.15
const SWING_ACCELERATION := 14.0
const MAX_LEAD := 0.30
const FOLLOW_TIME := 2.70

var age := 0.0
var hit_at := 0.0
var active := false
var impact_now := false
var windup_now := false
var early_reaction_dt := 0.0
var point := Vector3.ZERO
var normal := Vector3.UP
var impact_force := Vector3.ZERO
var _pose_start := 0.0
var _pose_contact := 0.0
var _pose_end := 0.0
var _focus := Vector3.ZERO
var _fall_focus := Vector3.ZERO
var _approach := Vector3.ZERO
var _close := Vector3.ZERO
var _exit := Vector3.ZERO
var target: Node3D
var _foe_start := Vector3.ZERO
var _air_distance := Vector3.ZERO


func begin(event: Dictionary, player, level, replay) -> bool:
	if replay.frame_times.size() < 3:
		return false
	var foe = event["enemy"]
	var from: Vector3 = player.rig.global_position + Vector3.UP * 2.15
	var to: Vector3 = foe.center()
	var along := (to - from).slide(Vector3.UP).normalized()
	if along.is_zero_approx():
		return false
	var side := along.cross(Vector3.UP)
	_focus = from.lerp(to, 0.56)
	target = foe
	_foe_start = foe.ground_position()
	_air_distance = Vector3.ZERO
	if foe.has_method("knockdown_landing_position"):
		_air_distance = foe.knockdown_landing_position() - _foe_start
	_fall_focus = _focus.lerp(to, 0.20) + _air_distance * 0.58 - Vector3.UP * 0.74
	point = event.get("contact", event["pos"])
	var travel: Vector3 = event.get("travel", Vector3.ZERO)
	normal = (travel.normalized() + event.get("normal", Vector3.UP) * 0.28).normalized()
	impact_force = event.get("force", travel)
	# Keep the camera side stable when the entry is resolved on an earlier frame.
	var camera_side_hint: Vector3 = event["pos"]
	var near_side := -1.0 if (camera_side_hint - to).dot(side) < -0.11 else 1.0
	for side_sign: float in [near_side, -near_side]:
		var offset := side * side_sign * 8.45 - along * 1.6
		_approach = _focus + offset.rotated(Vector3.UP, -side_sign * 0.30) * 1.18 + Vector3.UP * 2.95
		_close = _focus + offset * 0.82 + Vector3.UP * 1.73
		var pull_back := minf(_air_distance.length() * 0.045, 0.22)
		_exit = _fall_focus + offset.rotated(Vector3.UP, side_sign * 0.18) * (1.08 + pull_back) + Vector3.UP * 1.26
		if not _clear_camera_track(level, from, to):
			continue
		_pose_end = replay.frame_times[-1]
		var buildup := minf(MAX_LEAD, player.rig.attack_elapsed)
		_pose_start = maxf(replay.frame_times[0], _pose_end - buildup)
		var confirmed := lerpf(replay.frame_times[-2], _pose_end, event.get("contact_fraction", 1.0))
		_pose_contact = clampf(event.get("contact_time", confirmed), replay.frame_times[0], _pose_end)
		_pose_start = minf(_pose_start, maxf(replay.frame_times[0], _pose_contact - 0.027))
		var lead := _pose_contact - _pose_start
		if lead < 0.001:
			return false
		var average_rate := SWING_START_RATE + (SWING_END_RATE - SWING_START_RATE) / (SWING_ACCELERATION + 1.0)
		hit_at = lead / average_rate
		age = 0.0
		active = true
		return true
	return false


func _clear_camera_track(level, from: Vector3, to: Vector3) -> bool:
	var previous := _approach
	for sample in 9:
		var eye := _camera_position(float(sample) / 8.0)
		if not level.melee_clear(eye, from) or not level.melee_clear(eye, to):
			return false
		if sample >= 4 and not _air_distance.is_zero_approx() and not level.melee_clear(eye, to + _air_distance - Vector3.UP):
			return false
		if sample > 0 and not level.melee_clear(previous, eye):
			return false
		previous = eye
	return true


func advance(delta: float, replay) -> float:
	var before := age
	age += delta
	impact_now = before < hit_at and age >= hit_at
	windup_now = before < hit_at * 0.82 and age >= hit_at * 0.82
	var previous := _animation_time(before)
	var now := _animation_time(age)
	early_reaction_dt = 0.0
	if previous <= _pose_end:
		var pose_time := minf(now, _pose_end)
		if target.has_method("advance_fatal_reaction"):
			# The player still needs the recorded swing while the enemy reacts live.
			var live_rig: Node3D = target.rig if before >= hit_at else null
			replay.apply_shot_pose(_pose_contact if impact_now else pose_time, live_rig)
			early_reaction_dt = maxf(0.0, pose_time - maxf(previous, _pose_contact))
		else:
			replay.apply_shot_pose(pose_time)
	return maxf(0.0, now - maxf(previous, _pose_end))


func _animation_time(at: float) -> float:
	if at <= hit_at:
		var u := at / hit_at
		# Integrate the speed ramp so the last pre-hit pose is the exact contact pose.
		var surge := (SWING_END_RATE - SWING_START_RATE) * pow(u, SWING_ACCELERATION + 1.0) / (SWING_ACCELERATION + 1.0)
		return _pose_start + hit_at * (SWING_START_RATE * u + surge)
	var past := at - hit_at
	var recovering := clampf(past - CONTACT_DURATION, 0.0, SPEED_RECOVERY)
	var u := recovering / SPEED_RECOVERY
	var speed_blend := SPEED_RECOVERY * u * u * u * (1.0 - 0.5 * u)
	return _pose_contact + CONTACT_RATE * minf(past, CONTACT_DURATION + SPEED_RECOVERY) \
		+ (1.0 - CONTACT_RATE) * speed_blend + maxf(0.0, past - CONTACT_DURATION - SPEED_RECOVERY)


func rate() -> float:
	if age < hit_at:
		return lerpf(SWING_START_RATE, SWING_END_RATE, pow(age / hit_at, SWING_ACCELERATION))
	return lerpf(CONTACT_RATE, 1.0, smoothstep(hit_at + CONTACT_DURATION, hit_at + CONTACT_DURATION + SPEED_RECOVERY, age))


func complete() -> bool:
	return age >= hit_at + FOLLOW_TIME


func _camera_position(progress: float) -> Vector3:
	return _approach.lerp(_close, progress).lerp(_close.lerp(_exit, progress), progress)


func frame(camera: Camera3D, ground_shake: float) -> void:
	var elapsed := maxf(0.0, age - hit_at)
	var retreat := smoothstep(0.18, 2.34, elapsed)
	var kick := smoothstep(0.0, 0.044, elapsed) * (1.0 - smoothstep(0.044, 0.24, elapsed))
	var u := clampf(age / (hit_at + FOLLOW_TIME), 0.0, 1.0)
	var progress := u * (1.55 - 0.55 * u)
	var lean_in := smoothstep(0.0, 0.42, progress)
	var aim := _focus.lerp(point, 0.36 * lean_in).lerp(_fall_focus, retreat)
	var eye := _camera_position(progress)
	if is_instance_valid(target) and not _air_distance.is_zero_approx():
		var motion: Vector3 = target.ground_position() - _foe_start
		aim += (motion - _air_distance * retreat) * 0.53
	eye += Vector3.UP * (0.20 * kick + 0.024 * ground_shake * sin(age * 48.0) * retreat)
	camera.fov = lerpf(lerpf(53.0, 44.0, lean_in), 50.0, retreat)
	camera.look_at_from_position(eye, aim)
	camera.rotate_object_local(Vector3.BACK, deg_to_rad(-2.3 * lean_in * (1.0 - retreat) + 2.1 * kick))

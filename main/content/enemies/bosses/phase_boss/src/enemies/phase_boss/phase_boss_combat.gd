extends Node3D
## Animation-driven arena opponent. Coordinates are in ACT units (0.547 m per unit).

signal attack_hit(amount: float, blockable: bool, source: Vector3)
signal impact_shake(source: Vector3, strength: float)
signal footfall_shake(source: Vector3, strength: float)

const Body = preload("res://src/enemies/phase_boss/phase_boss_body.gd")
const Model = preload("res://scenes/phase_boss/phase_boss_model.tscn")
const Motion = preload("res://src/enemies/phase_boss/phase_boss_motion.gd")
const PhaseState = preload("res://src/enemies/phase_boss/phase_boss_state.gd")
const FX = preload("res://src/preview/phase_boss_motion_fx.gd")
const METERS_PER_UNIT := 0.547
const WORLD_MASK := 1
const PLAYER_RADIUS := 0.75
const BOSS_SCALE := 1.35
const MAX_HP := 300.0
const CLOSE_REPOSITION_METERS := 5.2
const FRONT_MELEE_MAX_METERS := 10.3
const RUSH_PLAY_RATE := 1.48
const RUSH_ACCEL_TIME := 0.85
const RUSH_SPEED_GAIN := 0.42
const RUSH_TURN_RATE := PI * 125.0 / 180.0
const RUSH_MIN_METERS := 14.0
const RUSH_STOP_METERS := 5.6
const RUSH_HIT_BEGIN := 0.20
const RUSH_HIT_RADIUS := 0.95
const RUSH_REUSE_DELAY := 1.15
const POUNCE_LANDING_GAP := 4.7
const RUN_POUNCE_MIN_TRAVEL_METERS := 3.2
const RUN_POUNCE_MAX_APPROACH_METERS := 15.4
const RUN_POUNCE_FLIGHT_RATE := 1.27
const RECOVERY_BEGIN := {
	"sweep": 0.84 + Motion.MELEE_WINDUP_EXTENSION,
	"stomp": Motion.STOMP_WAVE_END + 0.04,
	"tail": Motion.TAIL_CONTACT_END,
	"tail_left": Motion.TAIL_CONTACT_END,
	"pounce": 1.30,
	"high_pounce": 1.83,
	"run_pounce": Motion.RUN_IN + 1.83,
	"phase": 2.40,
	"back_cannon": Motion.CANNON_RELEASE,
}
const FLANK_DAMAGE_WINDOW := 3.5
const FLANK_DAMAGE_THRESHOLD := 3.0
const FLANK_RETREAT_COOLDOWN := 3.6
const FLANK_SIDE_COS := 0.70
const FLANK_HULL := [
	Vector3(-1.0, 0, -7.8), Vector3(1.0, 0, -7.8),
	Vector3(-3.3, 0, -3.6), Vector3(3.3, 0, -3.6),
	Vector3(-3.3, 0, 3.0), Vector3(3.3, 0, 3.0),
	Vector3(-1.36, 0, 9.8), Vector3(1.36, 0, 9.8),
]
const ORBIT_FACING_HOLD := 1.25
const ORBIT_ATTACKS := ["sweep", "stomp", "tail", "tail_left"]
const MOVE_CLIPS := ["walk", "sprint"]
const HEAVY_CLIPS := ["high_pounce", "run_pounce", "back_cannon"]
const POUNCE_CLIPS := ["pounce", "high_pounce", "run_pounce"]
const DAMAGE := {"sweep": 18.0, "stomp": 22.0, "tail": 20.0, "tail_left": 20.0,
	"pounce": 24.0, "high_pounce": 32.0, "run_pounce": 32.0, "phase": 17.0, "sprint": 26.0}
const NAMES := {"idle": "低伏警戒", "walk": "低伏踱步", "sprint": "低头冲撞", "reposition": "低伏让位", "flank_leap": "侧跳后撤",
	"turn": "换脚转身", "rush_turn": "腾起转身", "sweep": "低颚横扫", "stomp": "压肩踏爪", "tail": "向右扫尾",
	"tail_left": "向左扫尾", "pounce": "低伏短扑", "high_pounce": "长距离高扑",
	"run_pounce": "飞奔接高扑", "back_cannon": "背炮激光", "phase": "虚化交叉扫",
	"phase_enter": "转入虚化", "phase_roar": "仰天咆哮", "phase_exit": "复实", "wake_intro": "苏醒"}

var hp := MAX_HP
var max_hp := MAX_HP
var trace_world: Callable
var phase := PhaseState.new()
var visible_to_player := false
var arena_half_extent := 21.0
var action := "idle"
var action_time := 0.0
var model: Node3D
var _actor: Node3D
var _motion: Motion
var _fx: FX
var _landing: MeshInstance3D
var _duration := {}
var _contacts := {}
var _rate := 1.0
var _rush_elapsed := 0.0
var _rush_can_pounce := true
var _pounce_entry_rate := 1.0
var _clock := 0.0
var _rest := 0.0
var _next_rush := 0.0
var _orbit_time := 0.0
var _hold_facing_until := 0.0
var _movement_end := 0.0
var _heavy_rest := 0.0
var _cannon_tick := 0.0
var _last_heavy := ""
var _last_near_attack := ""
var _phase_special_used := false
var _turn_degrees := 0.0
var _reposition_direction := Vector3.BACK
var _flank_hits: Array[Vector3] = []
var _flank_retreat_until := -INF
var _flank_retry_at := 0.0
var _flank_ready_at := 0.0
var _flank_hop := Vector3.ZERO
var _flank_backstep := Vector3.ZERO
var _flank_turn_degrees := 0.0
var _pounce_turn_degrees := 0.0
var _cannon_turn_degrees := 0.0
var _aim_angles := Vector2(-10.9, 0.0)
var _jump_scale := 1.0
var _jump_locked := false
var _hit_windows := {}
var _previous_feet := PackedVector3Array()
var _previous_pose: Motion.Pose
var _pose: Motion.Pose
var _blend_time := 0.0
var _last_player := Vector3.INF
var _player_velocity := Vector3.ZERO


func _ready() -> void:
	_actor = Node3D.new()
	_actor.name = "ActionFrame"
	_actor.scale = Vector3.ONE * BOSS_SCALE
	add_child(_actor)
	model = Model.instantiate()
	_actor.add_child(model)
	_motion = Motion.new(model)
	_fx = FX.new()
	_actor.add_child(_fx)
	_fx.configure(model)
	for clip: Array in Motion.CLIPS:
		_duration[clip[0]] = clip[2]
	_build_contact_catalog()
	for clip: String in Motion.CONTACT_WINDOWS:
		if clip not in POUNCE_CLIPS:
			_fx.prepare_clip(_motion, clip)
	_build_landing_marker()
	reset_at(global_position, global_rotation.y)


func reset_at(at: Vector3, facing: float) -> void:
	_actor.global_transform = Transform3D(_action_basis(facing), at)
	phase = PhaseState.new()
	hp = max_hp
	_rest = 0.0
	_next_rush = 0.0
	_pounce_entry_rate = 1.0
	_orbit_time = 0.0
	_hold_facing_until = 0.0
	_heavy_rest = 0.0
	_clock = 0.0
	_last_near_attack = ""
	_last_heavy = ""
	visible_to_player = false
	_phase_special_used = false
	_flank_hits.clear()
	_flank_retreat_until = -INF
	_flank_retry_at = 0.0
	_flank_ready_at = 0.0
	_last_player = Vector3.INF
	_player_velocity = Vector3.ZERO
	_pose = null
	_begin("idle", facing)
	_apply_pose(at, 0.0)


func activity_label() -> String:
	if action == "wake_intro":
		return _pose.signal_name
	return NAMES[action]


func begin_intro() -> void:
	_begin("wake_intro", model.global_rotation.y)
	_blend_time = 0.22
	_apply_pose(ground_position(), 0.0)


func advance_intro(delta: float) -> void:
	if action != "wake_intro":
		return
	var previous := action_time
	action_time = minf(action_time + delta, Motion.INTRO_DURATION)
	_clock += delta
	_fx.advance_audio(action, previous, action_time)
	_apply_pose(ground_position(), delta)


func finish_intro() -> bool:
	if action != "wake_intro" or action_time < Motion.INTRO_DURATION:
		return false
	_begin("idle", model.global_rotation.y)
	return true


func hit_parts() -> Array:
	var parts := []
	for volume: Array in _hurt_volumes():
		parts.append({"a": volume[0], "b": volume[1], "r": volume[2]})
	return parts


func contact_radius() -> float:
	if action == "sprint" and action_time >= RUSH_HIT_BEGIN:
		return RUSH_HIT_RADIUS * BOSS_SCALE
	for window: Array in Motion.CONTACT_WINDOWS.get(action, []):
		if action_time >= window[1] and action_time <= window[2]:
			return _attack_radius(action, window, action_time) * BOSS_SCALE
	return 0.0


func melee_forecast(capsule: Dictionary, margin: float, lead: float) -> Dictionary:
	var bottom: Vector3 = capsule["a"]
	var top: Vector3 = capsule["b"]
	var radius: float = capsule["r"]
	var center := (bottom + top) * 0.5
	if action == "sprint" and not _hit_windows.has(0):
		return _rush_forecast(bottom, top, radius, margin, lead)
	var side := Motion.tail_sweep_direction(action)
	if side != 0.0 and _motion.tail_sweep_side_distance(center, side) < 0.0:
		return {}
	for entry: Array in _contacts.get(action, []):
		var rate := _pounce_playback((entry[2] + action_time) * 0.5) if action == "run_pounce" else _rate
		var eta: float = (entry[2] - action_time) / rate
		if eta < -0.045 or eta > lead:
			continue
		var shift := 0.0
		if action in POUNCE_CLIPS:
			shift = _pounce_warp(entry[3])
		var path := PackedVector3Array()
		for point: Vector3 in entry[0]:
			path.append(_actor.to_global(point + Vector3.BACK * shift))
		var source := _strike_source(path, bottom, top, float(entry[1]) * BOSS_SCALE + radius + margin, entry[4])
		if not source.is_finite():
			continue
		var threat := _contact_threat(source, bottom, top, radius + margin * 0.45, eta)
		if not threat.is_empty():
			return threat
	return {}


func _contact_threat(source: Vector3, bottom: Vector3, top: Vector3, reach: float, eta: float) -> Dictionary:
	var axis_point := Geometry3D.get_closest_point_to_segment(source, bottom, top)
	var outward := source - axis_point
	if outward.length_squared() < 0.001:
		outward = source - (bottom + top) * 0.5
	if outward.length_squared() < 0.001:
		outward = _actor.global_basis.z
	outward = outward.normalized()
	var point := axis_point + outward * reach
	if not _ray(source, point).is_empty():
		return {}
	var axis := outward.cross(Vector3.UP).normalized()
	return {"ok": true, "point": point, "axis": axis if axis.length_squared() > 0.01 else Vector3.RIGHT,
		"normal": outward, "eta": maxf(0.0, eta), "kind": "melee"}


func _rush_forecast(bottom: Vector3, top: Vector3, radius: float, margin: float, lead: float) -> Dictionary:
	var from_time := maxf(action_time, RUSH_HIT_BEGIN)
	var lead_motion := _rush_advance(lead)
	var to_time := minf(action_time + lead_motion, _movement_end)
	if to_time < from_time:
		return {}
	var velocity := -_actor.global_basis.z * Motion.SPRINT_SPEED
	var at := ground_position()
	var reach := RUSH_HIT_RADIUS * BOSS_SCALE + radius + margin
	for nose: Vector3 in _attack_path("head"):
		var a := nose + velocity * (from_time - action_time)
		var b := nose + velocity * (to_time - action_time)
		var contact := Geometry3D.get_closest_points_between_segments(a, b, bottom, top)
		if contact[0].distance_squared_to(contact[1]) > reach * reach:
			continue
		var travel_time := nose.distance_to(contact[0]) / velocity.length()
		var eta := lead * travel_time / maxf(0.001, lead_motion)
		if _has_runway(at, at + velocity * travel_time, 2.6):
			var threat := _contact_threat(contact[0], bottom, top, radius + margin * 0.45, eta)
			if not threat.is_empty():
				return threat
	return {}


func ground_position() -> Vector3:
	var at := model.global_position
	at.y = _actor.global_position.y
	return at


static func _action_basis(facing: float) -> Basis:
	return Basis(Vector3.UP, facing).scaled(Vector3.ONE * BOSS_SCALE)


func aim_at_camera(camera: Camera3D) -> bool:
	var eye := camera.global_position
	for volume: Array in _hurt_volumes():
		for sample_point: Vector3 in [volume[0], (volume[0] + volume[1]) * 0.5, volume[1]]:
			if camera.is_position_in_frustum(sample_point) and _ray(eye, sample_point).is_empty():
				return true
	return false


func receive_blade(base: Vector3, tip: Vector3, damage: float, camera: Camera3D) -> float:
	if hp <= 0.0:
		return -1.0
	for volume: Array in _hurt_volumes():
		if _within(base, tip, volume[0], volume[1], volume[2] + 0.16):
			var contact := Geometry3D.get_closest_points_between_segments(base, tip, volume[0], volume[1])
			if not _ray(base, contact[1]).is_empty():
				continue
			visible_to_player = aim_at_camera(camera)
			return take_damage(damage, visible_to_player, base)
	return -1.0


func take_damage(amount: float, visible: bool, attacker: Vector3) -> float:
	var dealt := maxf(0.0, amount) * damage_multiplier(visible)
	var before := hp
	hp = maxf(0.0, hp - dealt)
	if hp > 0.0 and hp < before:
		_record_flank_hit(before - hp, attacker)
	return dealt


func _record_flank_hit(damage: float, attacker: Vector3) -> void:
	if _clock < _flank_ready_at or _clock <= _flank_retreat_until:
		return
	var to_attacker := (attacker - ground_position()).slide(Vector3.UP).normalized()
	var side := to_attacker.dot(model.global_basis.x.normalized())
	if absf(side) < FLANK_SIDE_COS:
		return
	while not _flank_hits.is_empty() and _clock - _flank_hits[0].x > FLANK_DAMAGE_WINDOW:
		_flank_hits.pop_front()
	var flank := signf(side)
	_flank_hits.append(Vector3(_clock, damage, flank))
	var total := 0.0
	for hit in _flank_hits:
		if hit.z == flank:
			total += hit.y
	if total > FLANK_DAMAGE_THRESHOLD + 0.0001:
		_flank_hits.clear()
		_flank_retreat_until = _clock + 4.0


func damage_multiplier(visible: bool) -> float:
	if action == "wake_intro" or (phase.stage == PhaseState.Stage.PHASED and action == "back_cannon"):
		return 0.0
	return phase.damage_multiplier(visible)


func step(delta: float, player: Vector3, camera: Camera3D, capsule := {}) -> void:
	if hp <= 0.0:
		return
	_clock += delta
	if _last_player.is_finite():
		_player_velocity = _player_velocity.lerp((player - _last_player) / maxf(delta, 0.001),
			1.0 - exp(-12.0 * delta))
	_last_player = player
	var offset := (player - ground_position()).slide(Vector3.UP)
	var radial := _player_velocity.dot(offset.normalized())
	var angular_speed := _orbit_speed(offset)
	var lateral := absf(angular_speed) * offset.length()
	var circling := absf(angular_speed) > 0.25 and lateral > maxf(2.2, absf(radial) * 1.1)
	_orbit_time = clampf(_orbit_time + delta * (1.0 if circling else -1.6), 0.0, 0.65)
	if _orbit_time >= 0.26:
		_hold_facing_until = _clock + ORBIT_FACING_HOLD
	visible_to_player = aim_at_camera(camera)
	var previous_stage := phase.stage
	phase.advance(delta, visible_to_player, _committed())
	_heavy_rest = maxf(0.0, _heavy_rest - delta)
	_rest = maxf(0.0, _rest - delta)
	if phase.stage != previous_stage:
		match phase.stage:
			PhaseState.Stage.ENTERING:
				_begin("phase_enter", model.global_rotation.y)
			PhaseState.Stage.RETURNING:
				_begin("phase_exit", model.global_rotation.y)
			PhaseState.Stage.PHASED:
				_phase_special_used = false
				_rest = 0.0
				_begin("phase_roar", model.global_rotation.y)
			PhaseState.Stage.SOLID:
				_rest = 0.80
				_begin("idle", model.global_rotation.y)
	var before := action_time
	if action in ["phase_enter", "phase_exit"]:
		action_time = phase.age
	else:
		if action == "run_pounce" and action_time >= Motion.RUN_IN and not _jump_locked:
			var launch := _actor.to_global(Vector3.FORWARD * Motion.RUN_APPROACH_DISTANCE)
			if _run_pounce_travel(launch, player) < RUN_POUNCE_MIN_TRAVEL_METERS / METERS_PER_UNIT:
				_resume_rush_after_gather()
				before = action_time
		var advance := _advance_action(delta)
		if action == "sprint":
			advance = _rush_advance(delta)
			_steer_rush(player, advance)
			_rush_elapsed += delta
		action_time += advance
		if action in MOVE_CLIPS:
			action_time = minf(action_time, _movement_end)
		elif action != "idle":
			action_time = minf(action_time, _duration[action])
	var past_nose := _attack_path("head") if action == "sprint" else PackedVector3Array()
	_fx.advance_audio(action, before, action_time)
	_apply_pose(player, delta)
	_emit_impact_shake(before)
	_resolve_attack(player, delta, capsule, past_nose)
	if action in ["phase_enter", "phase_exit"]:
		return
	var interruptible := action in ["idle", "walk"] or (action != "sprint" and action_time >= float(_duration[action]))
	if interruptible and action != "flank_leap" and _try_flank_retreat(player):
		return
	if action == "idle" or action == "walk":
		if action == "walk" and action_time >= _movement_end:
			_begin("idle", model.global_rotation.y)
		if _rest <= 0.0:
			_choose(player, capsule)
		return
	if action == "sprint":
		if action_time >= _movement_end:
			_next_rush = _clock + RUSH_REUSE_DELAY
			if not _try_flank_retreat(player):
				_start_breather(player)
		else:
			_try_sprint_pounce(player, before)
		return
	if action_time < float(_duration[action]):
		return
	if action == "rush_turn":
		_begin_rush(player, model.global_rotation.y)
		return
	if action in ["turn", "reposition", "phase_roar", "flank_leap"]:
		_choose(player, capsule, action == "flank_leap")
		return
	if action == "stomp" or action == "sweep":
		_last_near_attack = action
	if action in HEAVY_CLIPS:
		_heavy_rest = _heavy_cooldown()
	_start_breather(player)


func _start_breather(player: Vector3) -> void:
	_rest = randf_range(0.14, 0.27) if _phased() else randf_range(0.28, 0.47)
	_settle(player)


func _settle(player: Vector3) -> void:
	var at := ground_position()
	var offset := (player - at).slide(Vector3.UP)
	var yaw := model.global_rotation.y
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var walking := action == "walk"
	var distance := 5.4 if walking else 6.3
	var alignment := 0.30 if walking else 0.55
	var walk_clear := (offset.length() * METERS_PER_UNIT >= distance and forward.dot(offset.normalized()) >= alignment
		and _has_runway(at, at + forward * (1.2 if walking else 3.0), 2.3))
	var next := "walk" if walk_clear else "idle"
	if next != action:
		_begin(next, yaw)


func _phased() -> bool:
	return phase.stage == PhaseState.Stage.PHASED and phase.age < PhaseState.ACTIVE_TIME


func _sprint_rate() -> float:
	return RUSH_PLAY_RATE * (Motion.PHASE_MOVE_RATE if _phased() else 1.0) / BOSS_SCALE


func _rush_ramp_integral(time: float) -> float:
	var progress := clampf(time / RUSH_ACCEL_TIME, 0.0, 1.0)
	return RUSH_ACCEL_TIME * progress * progress * progress * (1.0 - 0.5 * progress) + maxf(0.0, time - RUSH_ACCEL_TIME)


func _rush_advance(delta: float) -> float:
	var ramp := _rush_ramp_integral(_rush_elapsed + delta) - _rush_ramp_integral(_rush_elapsed)
	return _rate * (delta + RUSH_SPEED_GAIN * ramp)


func _advance_action(delta: float) -> float:
	var rate := _pounce_playback(action_time) if action == "run_pounce" else _rate
	var recovery := action_time - float(RECOVERY_BEGIN.get(action, INF))
	var acceleration := 1.85 if _phased() else 1.72
	return delta * rate * lerpf(1.0, acceleration, smoothstep(0.0, 0.12, recovery))


func _pounce_playback(time: float) -> float:
	var takeoff := Motion.RUN_IN + Motion.LEAP_TAKEOFF
	var landing := Motion.RUN_IN + Motion.LEAP_CONTACT
	var flight_rate := _pounce_entry_rate * RUN_POUNCE_FLIGHT_RATE
	var rate := lerpf(_pounce_entry_rate, flight_rate, smoothstep(Motion.RUN_IN, takeoff, time))
	return lerpf(rate, _rate, smoothstep(landing, landing + 0.22, time))


func _heavy_cooldown() -> float:
	return 1.25 if _phased() else 2.15


func _begin_rush(player: Vector3, yaw: float) -> void:
	var gap := (player - ground_position()).slide(Vector3.UP).length()
	_begin("sprint", yaw)
	var travel := maxf(0.0, gap - RUSH_STOP_METERS / METERS_PER_UNIT)
	_movement_end = travel / (Motion.SPRINT_SPEED * BOSS_SCALE)


func _steer_rush(player: Vector3, advance: float) -> void:
	var at := ground_position()
	var offset := (player - at).slide(Vector3.UP)
	var remaining := offset.length() - RUSH_STOP_METERS / METERS_PER_UNIT
	var stop := action_time + maxf(0.0, remaining) / (Motion.SPRINT_SPEED * BOSS_SCALE)
	if _hit_windows.has(0):
		_movement_end = minf(_movement_end, stop)
		return
	_movement_end = stop
	if remaining <= 0.0:
		return
	var yaw := _actor.global_rotation.y
	var target_yaw := atan2(-offset.x, -offset.z)
	var error := angle_difference(yaw, target_yaw)
	var turn_limit := RUSH_TURN_RATE * advance * BOSS_SCALE / RUSH_PLAY_RATE
	var next_yaw := yaw + clampf(error, -turn_limit, turn_limit)
	if absf(error) < 0.0001:
		return
	var basis := _action_basis(next_yaw)
	var lookahead := at - basis.z * maxf(1.25, Motion.SPRINT_SPEED * advance)
	if not _has_runway(at, lookahead, 2.6):
		return
	# Advance the next stride from the current world position as the run curves.
	var previous_transform := model.global_transform
	var traveled := Vector3.FORWARD * (Motion.SPRINT_SPEED * action_time)
	_actor.global_transform = Transform3D(basis, at - basis * traveled)
	model.global_transform = previous_transform


func _committed() -> bool:
	match action:
		"rush_turn", "sprint", "flank_leap":
			return true
		"pounce":
			return action_time >= Motion.SHORT_POUNCE_TAKEOFF and action_time < 1.30
		"high_pounce":
			return action_time >= Motion.LEAP_TAKEOFF and action_time < 1.83
		"run_pounce":
			return action_time < Motion.RUN_IN + 1.83
		"back_cannon":
			if phase.stage == PhaseState.Stage.PHASED:
				return action_time < Motion.CANNON_DURATION
			return action_time >= Motion.CANNON_FIRE and action_time < Motion.CANNON_RELEASE
		"phase":
			return action_time >= 0.27 and action_time < 2.34
	var windows: Array = Motion.CONTACT_WINDOWS.get(action, [])
	return not windows.is_empty() and action_time >= windows[0][1] and action_time < windows[-1][2]


func _try_sprint_pounce(player: Vector3, before: float) -> bool:
	if not _rush_can_pounce or _heavy_rest > 0.0 or _hit_windows.has(0) or action_time < Motion.SPRINT_PERIOD:
		return false
	var cut_phase := fposmod(Motion.RUN_IN, Motion.SPRINT_PERIOD)
	var past_cut := fposmod(action_time - cut_phase, Motion.SPRINT_PERIOD)
	if past_cut >= action_time - before:
		return false
	var at := ground_position()
	var facing := _actor.global_rotation.y
	var forward := Basis(Vector3.UP, facing) * Vector3.FORWARD
	var offset := (player - at).slide(Vector3.UP)
	var ahead := offset.dot(forward)
	var meters := ahead * METERS_PER_UNIT
	if meters > RUN_POUNCE_MAX_APPROACH_METERS or (offset - forward * ahead).length() * METERS_PER_UNIT > 2.0:
		return false
	var gather_left := Motion.RUN_APPROACH_DISTANCE + _motion.sample("run_pounce", Motion.RUN_IN + past_cut).position.z
	var launch := at + forward * (gather_left * BOSS_SCALE)
	var flight_distance := _run_pounce_travel(launch, player)
	if (flight_distance < RUN_POUNCE_MIN_TRAVEL_METERS / METERS_PER_UNIT
			or not _has_runway(at, launch + forward * flight_distance, 3.15)
			or not _ray(at + Vector3.UP * 2.0, player + Vector3.UP * 1.4).is_empty()):
		return false
	# The connector starts at the same footfall as the live stride. Rebase its root
	# at the current position so the gather carries forward instead of restarting the run.
	_pounce_entry_rate = _rate * (1.0 + RUSH_SPEED_GAIN * smoothstep(0.0, RUSH_ACCEL_TIME, _rush_elapsed))
	_begin("run_pounce", facing)
	action_time = Motion.RUN_IN + past_cut
	_actor.global_position = at - _actor.global_basis * _motion.sample("run_pounce", action_time).position
	_blend_time = 0.22
	return true


func _run_pounce_travel(launch: Vector3, player: Vector3) -> float:
	var forward := -_actor.global_basis.z.normalized()
	return (player - launch).dot(forward) - POUNCE_LANDING_GAP * BOSS_SCALE


func _resume_rush_after_gather() -> void:
	var at := ground_position()
	var elapsed := _rush_elapsed
	var stride_time := action_time
	_begin("sprint", _actor.global_rotation.y)
	_rush_elapsed = elapsed
	_rush_can_pounce = false
	_heavy_rest = 0.0
	action_time = stride_time
	_actor.global_position = at - _actor.global_basis * (Vector3.FORWARD * Motion.SPRINT_SPEED * stride_time)


func _try_flank_retreat(player: Vector3) -> bool:
	if (_clock > _flank_retreat_until or _clock < _flank_retry_at
			or phase.stage != PhaseState.Stage.SOLID or phase.charge >= 1.0):
		return false
	_flank_retry_at = _clock + 0.12
	var at := ground_position()
	var to_player := (player - at).slide(Vector3.UP)
	if to_player.length() * METERS_PER_UNIT > 12.0:
		return false
	var yaw := model.global_rotation.y
	var facing := Basis(Vector3.UP, yaw)
	var away := Vector3.LEFT if to_player.dot(facing.x) >= 0.0 else Vector3.RIGHT
	var directions := [away, (away + Vector3.BACK * 1.25).normalized(),
		(away + Vector3.FORWARD * 1.25).normalized(), (away * 0.30 + Vector3.BACK).normalized(),
		(away * 0.30 + Vector3.FORWARD).normalized(),
		(-away * 0.45 + Vector3.BACK).normalized(), (-away * 0.45 + Vector3.FORWARD).normalized()]
	# Give an open-floor retreat a straight counterattack stance. Near a wall, angle the backsteps along it.
	for bias: float in [0.0, 30.0, -30.0, 57.0, -57.0, 80.0, -80.0]:
		for scale: float in [1.0, 0.72, 0.49]:
			for direction: Vector3 in directions:
				var hop := direction * (Motion.FLANK_LEAP_DISTANCE * scale)
				var landing := at + facing * hop * BOSS_SCALE
				var near_player := Geometry3D.get_closest_point_to_segment(at + to_player, at, landing)
				var clear_of_player := (at + to_player).distance_to(near_player)
				if clear_of_player < minf(to_player.length(), 5.5) - 0.05 or not _has_runway(at, landing, 2.75):
					continue
				var aim := (player - landing).slide(Vector3.UP)
				var turn := angle_difference(yaw, atan2(-aim.x, -aim.z) + deg_to_rad(bias))
				turn = clampf(turn, deg_to_rad(-132.0), deg_to_rad(132.0))
				var retreat := Basis(Vector3.UP, turn) * Vector3.BACK * (Motion.FLANK_BACKSTEP_DISTANCE * lerpf(0.62, 1.0, scale))
				var end := landing + facing * retreat * BOSS_SCALE
				if ((player - end).slide(Vector3.UP).length() < to_player.length() + 0.9
						or not _has_runway(landing, end, 2.75)
						or not _has_rush_turn_room(end, yaw + turn, 0.0)
						or not _flank_sweep_fits(at, facing, hop, retreat, rad_to_deg(turn))):
					continue
				_flank_retreat_until = -INF
				_flank_ready_at = _clock + FLANK_RETREAT_COOLDOWN
				_hold_facing_until = _clock
				_orbit_time = 0.0
				_rest = 0.0
				_flank_hop = hop
				_flank_backstep = retreat
				_flank_turn_degrees = rad_to_deg(turn)
				_begin("flank_leap", yaw)
				return true
	return false


func _flank_sweep_fits(at: Vector3, facing: Basis, hop: Vector3, retreat: Vector3, turn: float) -> bool:
	var limit := arena_half_extent - 0.18
	# Track both the hull and the planted feet as the body rotates around the corner.
	if maxf(absf(at.x), absf(at.z)) + (hop.length() + retreat.length() + 10.8) * BOSS_SCALE < limit:
		return true
	var anchor := Transform3D(facing.scaled(Vector3.ONE * BOSS_SCALE), at)
	var initial := _flank_footprint(anchor, _motion.sample_flank_leap(0.0, hop, retreat, turn))
	var limits := Rect2(Vector2(-limit, -limit), Vector2.ONE * (2.0 * limit))
	var permitted := initial.merge(limits).grow(0.04)
	for i in range(1, 19):
		var t := Motion.FLANK_LEAP_DURATION * float(i) / 18.0
		var hull := _flank_footprint(anchor, _motion.sample_flank_leap(t, hop, retreat, turn))
		if not (limits if i == 18 else permitted).encloses(hull):
			return false
	return true


func _flank_footprint(anchor: Transform3D, pose: Motion.Pose) -> Rect2:
	var body := anchor * Transform3D(Basis(Vector3.UP, deg_to_rad(pose.yaw)), pose.position)
	var area := Rect2(Vector2(body.origin.x, body.origin.z), Vector2.ZERO)
	for corner: Vector3 in FLANK_HULL:
		var at := body * corner
		area = area.expand(Vector2(at.x, at.z))
	for paw: Vector3 in pose.paw_positions:
		var at := anchor * paw
		area = area.expand(Vector2(at.x, at.z) + Vector2.ONE * 0.68)
		area = area.expand(Vector2(at.x, at.z) - Vector2.ONE * 0.68)
	return area


func _choose(player: Vector3, capsule: Dictionary, after_flank_retreat := false) -> void:
	var at := ground_position()
	var flat := player - at
	flat.y = 0.0
	var distance := flat.length() * METERS_PER_UNIT
	var target_yaw := atan2(-flat.x, -flat.z)
	var yaw := model.global_rotation.y
	var error := wrapf(target_yaw - yaw, -PI, PI)
	var local_basis := Basis(Vector3.UP, -yaw).scaled(Vector3.ONE / BOSS_SCALE)
	var local := local_basis * flat
	var bottom: Vector3 = local_basis * (capsule.get("a", player + Vector3.UP * 0.38) - at)
	var top: Vector3 = local_basis * (capsule.get("b", player + Vector3.UP * 2.48) - at)
	var radius: float = capsule.get("r", PLAYER_RADIUS) / BOSS_SCALE
	var clear := _ray(at + Vector3.UP * 2.0, player + Vector3.UP * 1.4).is_empty()
	var may_attack := phase.charge < 1.0 and (phase.stage != PhaseState.Stage.PHASED or _phased())
	var circling := _clock < _hold_facing_until
	if circling and may_attack and clear and distance <= 8.4:
		var counter := _orbit_counter(local, bottom, top, radius, _orbit_speed(flat))
		if not counter.is_empty():
			_begin(counter, yaw)
			return
		if distance < CLOSE_REPOSITION_METERS and _make_close_space(at, player, yaw):
			return
	if (may_attack and clear and _phased() and not _phase_special_used and distance >= 3.8 and distance <= 6.2 * BOSS_SCALE
			and absf(error) < deg_to_rad(29.0) and _covers("phase", bottom, top, radius)):
		_phase_special_used = true
		_begin("phase", yaw)
		return
	if may_attack and clear and distance <= FRONT_MELEE_MAX_METERS:
		var side := "tail_left" if local.x < 0.0 else "tail"
		if distance <= 6.2 * BOSS_SCALE and local.z > -0.05 and _covers(side, bottom, top, radius):
			_begin(side, yaw)
			return
		if absf(error) < 1.17:
			var sidestepping := absf((Basis(Vector3.UP, -yaw) * _player_velocity).x) > 2.6
			var primary := "sweep" if sidestepping or _last_near_attack == "stomp" else "stomp"
			var secondary := "sweep" if primary == "stomp" else "stomp"
			for choice: String in [primary, secondary]:
				if _covers(choice, bottom, top, radius):
					_begin(choice, yaw)
					return
	var rush_available := may_attack and clear and distance >= RUSH_MIN_METERS and _clock >= _next_rush
	if rush_available and absf(error) >= deg_to_rad(29.0):
		var jump_turn := clampf(rad_to_deg(error), -Motion.RUSH_TURN_MAX_DEGREES, Motion.RUSH_TURN_MAX_DEGREES)
		var rush_forward := Basis(Vector3.UP, yaw + deg_to_rad(jump_turn)) * Vector3.FORWARD
		if _can_rush_from(at, rush_forward) and _has_rush_turn_room(at, yaw, jump_turn):
			_begin("rush_turn", yaw)
			_turn_degrees = jump_turn
			return
	var aligned := absf(error) < deg_to_rad(29.0)
	var can_turn_into_pounce := (after_flank_retreat and absf(error) <= deg_to_rad(53.0)
		and _has_rush_turn_room(at, yaw, rad_to_deg(error)))
	if may_attack and clear and (aligned or can_turn_into_pounce):
		var heavy_ready := _heavy_rest <= 0.0 or after_flank_retreat
		var cannon_ok := aligned and distance >= 11.8 and distance <= 17.3 and heavy_ready
		var jump_ok := distance >= 8.0 and distance <= 13.3 and heavy_ready
		var jump_end := at + flat.normalized() * clampf(flat.length() - 4.8 * BOSS_SCALE, 0.0, 19.5)
		jump_ok = jump_ok and _has_runway(at, jump_end, 3.15)
		if cannon_ok and (not jump_ok or _last_heavy != "back_cannon"):
			_begin("back_cannon", yaw)
			_cannon_turn_degrees = rad_to_deg(error)
			return
		if jump_ok:
			_begin("high_pounce", target_yaw)
			_pounce_turn_degrees = rad_to_deg(error)
			return
		if (distance >= 5.2 and distance <= 8.2
				and (distance >= RUSH_STOP_METERS + 1.0 or _clock >= _next_rush)
				and _has_runway(at, at + flat.normalized() * 6.0, 2.6)):
			_begin("pounce", target_yaw)
			_pounce_turn_degrees = rad_to_deg(error)
			return
		if aligned and rush_available and _can_rush_from(at, flat.normalized()):
			_begin_rush(player, yaw)
			return
	if not aligned and not circling and (clear or distance < 7.0):
		_begin("turn", yaw)
		_turn_degrees = clampf(rad_to_deg(error), -55.0, 55.0)
		if after_flank_retreat:
			_rate *= 1.72
		return
	if may_attack and distance < CLOSE_REPOSITION_METERS and _make_close_space(at, player, yaw):
		return
	_settle(player)


func _can_rush_from(at: Vector3, direction: Vector3) -> bool:
	var stride := Motion.SPRINT_SPEED * Motion.SPRINT_PERIOD * BOSS_SCALE
	return _has_runway(at, at + direction * stride, 2.6)


func _has_rush_turn_room(at: Vector3, yaw: float, degrees: float) -> bool:
	var slices := maxi(1, ceili(absf(degrees) / 15.0))
	var height := at + Vector3.UP * 2.0
	for i in range(1, slices + 1):
		var forward := Basis(Vector3.UP, yaw + deg_to_rad(degrees * i / slices)) * Vector3.FORWARD
		if (not _ray(height, height + forward * (7.5 * BOSS_SCALE)).is_empty()
				or not _ray(height, height - forward * (9.0 * BOSS_SCALE)).is_empty()):
			return false
	return true


func _make_close_space(at: Vector3, player: Vector3, yaw: float) -> bool:
	var facing := Basis(Vector3.UP, yaw)
	var offset := (player - at).slide(Vector3.UP)
	var away := Vector3.LEFT if offset.dot(facing.x) >= 0.0 else Vector3.RIGHT
	for direction: Vector3 in [Vector3.BACK, away]:
		var travel := facing * direction * (Motion.REPOSITION_DISTANCE * BOSS_SCALE)
		if (offset - travel).length() <= offset.length() + 0.65:
			continue
		if _has_runway(at, at + travel, 2.3):
			_begin("reposition", yaw)
			_reposition_direction = direction
			return true
	return false


func _orbit_speed(offset: Vector3) -> float:
	return offset.cross(_player_velocity).y / maxf(1.0, offset.length_squared())


func _orbit_counter(local: Vector3, bottom: Vector3, top: Vector3, radius: float, angular_speed: float) -> String:
	var rate := Motion.PHASE_ATTACK_RATE if _phased() else 1.0
	var soonest := INF
	var next := ""
	for clip: String in ORBIT_ATTACKS:
		var tail_side := Motion.tail_sweep_direction(clip)
		for entry: Array in _contacts[clip]:
			var time: float = entry[2] / rate
			if time >= soonest:
				break
			var angle := clampf(angular_speed * time, -PI, PI)
			var expected := local.rotated(Vector3.UP, angle)
			if tail_side != 0.0 and expected.x * tail_side < 0.0:
				continue
			var shift := expected - local
			if _path_hits(entry[0], bottom + shift, top + shift, float(entry[1]) + radius):
				soonest = time
				next = clip
				break
	return next


func _begin(clip: String, facing: float) -> void:
	var at := _actor.global_position if _pose == null else ground_position()
	var last_transform := model.global_transform
	_previous_pose = _pose
	_previous_feet.clear()
	if _previous_pose != null:
		for leg: Dictionary in model.legs:
			_previous_feet.append(leg["paw"].global_position)
	_actor.global_transform = Transform3D(_action_basis(facing), at)
	action = clip
	action_time = 0.0
	_blend_time = 0.0
	_rate = Motion.phase_rate(clip) if _phased() else 1.0
	_movement_end = 0.0
	if clip == "walk":
		_movement_end = INF
		_rate *= 0.75 / BOSS_SCALE
	elif clip == "sprint":
		_rate = _sprint_rate()
		_rush_elapsed = 0.0
		_rush_can_pounce = true
	if clip in HEAVY_CLIPS:
		_last_heavy = clip
		_heavy_rest = _heavy_cooldown()
	_hit_windows.clear()
	_cannon_tick = 0.0
	_aim_angles = Vector2(-10.9, 0.0)
	_pounce_turn_degrees = 0.0
	_jump_scale = 1.0
	_jump_locked = false
	_landing.hide()
	_fx.prepare_clip(_motion, "" if clip in POUNCE_CLIPS else clip, _previous_pose != null)
	if _previous_pose != null:
		model.global_transform = last_transform


func _apply_pose(player: Vector3, delta: float) -> void:
	var p: Motion.Pose
	match action:
		"turn":
			p = _motion.sample_turn(action_time, _turn_degrees)
		"rush_turn":
			p = _motion.sample_rush_turn(action_time, _turn_degrees)
		"reposition":
			p = _motion.sample_reposition(action_time, _reposition_direction)
		"flank_leap":
			p = _motion.sample_flank_leap(action_time, _flank_hop, _flank_backstep, _flank_turn_degrees)
		"pounce", "high_pounce":
			p = _motion.sample_aimed_pounce(action, action_time, _pounce_turn_degrees)
		"back_cannon":
			p = _motion.sample_cannon(action_time, _cannon_turn_degrees)
		_:
			p = _motion.sample(action, action_time)
	if action in POUNCE_CLIPS:
		_place_pounce(p, player)
	elif action in MOVE_CLIPS:
		var destination := _actor.to_global(p.position)
		var clearance := 2.6 if action == "sprint" else 1.9
		if not _has_runway(ground_position(), destination, clearance):
			_actor.global_position += ground_position() - destination
			_movement_end = action_time
		if action == "sprint":
			p.flash = smoothstep(0.03, 0.16, action_time) * 0.85
			if _previous_pose != null:
				p.flash = maxf(p.flash, _previous_pose.flash * (1.0 - smoothstep(0.0, 0.16, action_time)))
	elif action in ["sweep", "stomp", "phase", "reposition", "flank_leap"]:
		var at := ground_position()
		var destination := _actor.to_global(p.position)
		if not _has_runway(at, destination, 2.3):
			var correction := _actor.to_local(at) - p.position
			p.position += correction
			p.impact_position += correction
			for i in p.paw_positions.size():
				p.paw_positions[i] += correction
	if phase.stage == PhaseState.Stage.PHASED:
		p.phase = 1.0
		p.fin = maxf(0.9, p.fin)
	elif phase.stage == PhaseState.Stage.SOLID:
		p.charge = phase.charge
		if phase.charge > 0.90:
			p.fin = maxf(p.fin, 0.28 * smoothstep(0.90, 1.0, phase.charge))
	_blend_time += delta
	var blend_duration := 0.14 if action == "flank_leap" else 0.22
	if _previous_pose != null and _blend_time < blend_duration:
		var blend := smoothstep(0.0, blend_duration, _blend_time)
		p.chest = _previous_pose.chest.lerp(p.chest, blend)
		p.chest_angles = _previous_pose.chest_angles.lerp(p.chest_angles, blend)
		p.pelvis_offset = _previous_pose.pelvis_offset.lerp(p.pelvis_offset, blend)
		p.hip_angles = _previous_pose.hip_angles.lerp(p.hip_angles, blend)
		p.neck_angles = _previous_pose.neck_angles.lerp(p.neck_angles, blend)
		p.head_angles = _previous_pose.head_angles.lerp(p.head_angles, blend)
		for i in p.paw_positions.size():
			p.paw_positions[i] = _actor.to_local(_previous_feet[i]).lerp(p.paw_positions[i], blend)
			p.paw_angles[i] = lerpf(_previous_pose.paw_angles[i], p.paw_angles[i], blend)
	_motion.apply(p)
	if action == "back_cannon":
		_aim_cannon(p, player, delta)
	_pose = p
	_fx.show_pose(p, true, _clock, true)


func _place_pounce(p: Motion.Pose, player: Vector3) -> void:
	var flight := Motion.SHORT_POUNCE_TAKEOFF if action == "pounce" else Motion.LEAP_TAKEOFF
	var span := 7.35 if action == "pounce" else 19.5
	var run := Motion.RUN_APPROACH_DISTANCE if action == "run_pounce" else 0.0
	if run > 0.0:
		flight += Motion.RUN_IN
	var launch := _actor.to_global(Vector3(0, 0, -run))
	var local_target := _actor.to_local(player)
	if not _jump_locked:
		var min_scale := 0.08 if action == "run_pounce" else 0.18
		_jump_scale = clampf((-local_target.z - run - POUNCE_LANDING_GAP) / span, min_scale, 1.0 / BOSS_SCALE)
	if not _jump_locked and action_time >= flight:
		_jump_locked = true
		var forward := -_actor.global_basis.z
		var limit := launch + forward * span * _jump_scale
		if not _has_runway(launch, limit, 3.1):
			var clear_scale := 0.0
			for i in 10:
				var fraction := float(i + 1) * 0.1 * _jump_scale
				if not _has_runway(launch, launch + forward * span * fraction, 3.1):
					break
				clear_scale = fraction
			_jump_scale = clear_scale
	var displacement := _pounce_warp(p.position.z)
	p.position.z += displacement
	p.impact_position.z += displacement
	for i in p.paw_positions.size():
		p.paw_positions[i].z += displacement
	_landing.visible = p.marker == "pounce"
	if _landing.visible:
		_landing.position = Vector3(0, 0.035, -run - span * _jump_scale - 4.3)


func _pounce_warp(z: float) -> float:
	var traveled := maxf(0.0, -z)
	var run := Motion.RUN_APPROACH_DISTANCE if action == "run_pounce" else 0.0
	return maxf(0.0, traveled - run) * (1.0 - _jump_scale)


func _aim_cannon(p: Motion.Pose, player: Vector3, delta: float) -> void:
	var muzzle: Marker3D = model.cannon.muzzle
	if action_time < Motion.CANNON_LOCK:
		var towards := model.global_basis.inverse() * (player + Vector3.UP * 1.45 - muzzle.global_position)
		var pitch := rad_to_deg(atan2(towards.y, Vector2(towards.x, towards.z).length()))
		var yaw := rad_to_deg(atan2(-towards.x, -towards.z))
		_aim_angles.x = move_toward(_aim_angles.x, clampf(pitch, -18.0, 2.0), delta * 22.0)
		_aim_angles.y = move_toward(_aim_angles.y, clampf(yaw, -12.0, 12.0), delta * 34.0)
	var track := p.cannon_raise * p.cannon_extend
	p.cannon_pitch = lerpf(p.cannon_pitch, _aim_angles.x, track)
	p.cannon_yaw = _aim_angles.y * track
	_motion.apply(p)
	var source := muzzle.global_position
	var direction := -muzzle.global_basis.z.normalized()
	var floor_range := Motion.cannon_floor_range(source, direction, ground_position().y)
	# The search ray reaches beyond any wall of the arena, even along a diagonal.
	var trace_range := 4.0 * arena_half_extent / maxf(0.01, direction.slide(Vector3.UP).length())
	var limit := minf(floor_range, trace_range)
	var obstacle := _ray(source, source + direction * limit)
	p.cannon_range = limit if obstacle.is_empty() else source.distance_to(obstacle["position"])
	p.cannon_surface_hit = not obstacle.is_empty() or floor_range <= trace_range


func _emit_impact_shake(before: float) -> void:
	for foot in Motion.sprint_footfalls(action, before, action_time):
		footfall_shake.emit(model.legs[foot]["paw"].global_position, Motion.SPRINT_FOOT_SHAKES[foot])
	var strength := Motion.impact_shake(action, before, action_time)
	if strength <= 0.0:
		return
	var source := _actor.to_global(_pose.impact_position)
	match action:
		"back_cannon":
			source = model.cannon.muzzle.global_position
		"rush_turn":
			var front_paw := 2 if _turn_degrees > 0.0 else 0
			source = model.legs[front_paw]["paw"].global_position
	impact_shake.emit(source, strength)


func _resolve_attack(player: Vector3, delta: float, capsule: Dictionary, past_nose: PackedVector3Array) -> void:
	var bottom: Vector3 = capsule.get("a", player + Vector3.UP * 0.38)
	var top: Vector3 = capsule.get("b", player + Vector3.UP * 2.48)
	var body_radius: float = capsule.get("r", PLAYER_RADIUS)
	if action == "sprint":
		if action_time < RUSH_HIT_BEGIN or _hit_windows.has(0):
			return
		var reach := RUSH_HIT_RADIUS * BOSS_SCALE + body_radius
		var center := (bottom + top) * 0.5
		var nose := _attack_path("head")
		for i in nose.size():
			var pair := Geometry3D.get_closest_points_between_segments(past_nose[i], nose[i], bottom, top)
			if pair[0].distance_squared_to(pair[1]) <= reach * reach and _ray(pair[0], center).is_empty():
				_hit_windows[0] = true
				attack_hit.emit(DAMAGE["sprint"], true, pair[0])
				return
		return
	if action == "back_cannon":
		_cannon_tick = maxf(0.0, _cannon_tick - delta)
		if action_time >= Motion.CANNON_FIRE and action_time < Motion.CANNON_RELEASE and _cannon_tick <= 0.0:
			var muzzle: Marker3D = model.cannon.muzzle
			var source := muzzle.global_position
			var end := source - muzzle.global_basis.z.normalized() * _pose.cannon_range
			var contact := Geometry3D.get_closest_points_between_segments(source, end, bottom, top)
			var reach := body_radius + 0.44 * BOSS_SCALE
			if contact[0].distance_squared_to(contact[1]) <= reach * reach and _ray(source, contact[1]).is_empty():
				_cannon_tick = 0.28
				attack_hit.emit(15.0, false, source)
		return
	var windows: Array = Motion.CONTACT_WINDOWS.get(action, [])
	for i in windows.size():
		var window: Array = windows[i]
		if action_time < window[1] or action_time > window[2] or _hit_windows.has(i):
			continue
		var center := (bottom + top) * 0.5
		var directional_tail := Motion.tail_sweep_direction(action) != 0.0
		if directional_tail and not _motion.tail_sweep_overlaps(action, action_time, bottom, top, body_radius):
			continue
		for shape: Array in _attack_shapes(window[0], _attack_radius(action, window, action_time)):
			var path: PackedVector3Array = shape[0]
			var reach := float(shape[1]) * BOSS_SCALE + body_radius
			var source := _nearest_contact(path, center) if directional_tail else _strike_source(path, bottom, top, reach, shape[2])
			if source.is_finite() and _ray(source, center).is_empty():
				_hit_windows[i] = true
				attack_hit.emit(DAMAGE[action], true, source)
				break


func _build_contact_catalog() -> void:
	for clip: String in Motion.CONTACT_WINDOWS:
		var entries := []
		for window: Array in Motion.CONTACT_WINDOWS[clip]:
			for sample in 12:
				var at := lerpf(window[1], window[2], float(sample) / 11.0)
				var pose := _motion.sample(clip, at)
				_motion.apply(pose)
				for shape: Array in _attack_shapes(window[0], _attack_radius(clip, window, at)):
					var points: PackedVector3Array = shape[0]
					for i in points.size():
						points[i] = _actor.to_local(points[i])
					entries.append([points, shape[1], at, pose.position.z, shape[2]])
		_contacts[clip] = entries


func _covers(clip: String, bottom: Vector3, top: Vector3, radius: float) -> bool:
	for item: Array in _contacts[clip]:
		if _path_hits(item[0], bottom, top, float(item[1]) + radius):
			return true
	return false


func _attack_radius(clip: String, window: Array, time: float) -> float:
	return Motion.stomp_radius_at(time) if clip == "stomp" else float(window[3])


func _attack_shapes(kind: String, radius: float) -> Array:
	var shapes := [[_attack_path(kind), radius, false]]
	if kind == "pounce":
		for part: Body.Capsule in Body.posed_capsules(model):
			shapes.append([PackedVector3Array([part.a, part.b]), part.radius / BOSS_SCALE, true])
	return shapes


func _attack_path(kind: String) -> PackedVector3Array:
	if kind == "tail":
		return model.tail_contact_path()
	if kind == "paw":
		return PackedVector3Array([model.legs[2]["paw"].to_global(Vector3(0, -0.25, -0.75))])
	if kind == "pounce":
		return PackedVector3Array([model.legs[0]["paw"].to_global(Vector3(0, -0.25, -0.96)),
			model.jaw.to_global(Vector3(0, -0.1, -2.04)), model.legs[2]["paw"].to_global(Vector3(0, -0.25, -0.96))])
	return PackedVector3Array([model.head.to_global(Vector3(-0.68, -0.22, -1.52)),
		model.jaw.to_global(Vector3(0, -0.1, -2.04)), model.head.to_global(Vector3(0.68, -0.22, -1.52))])


func _hurt_volumes() -> Array:
	var volumes := [
		[model.chest.to_global(Vector3(0, -0.25, -1.7)), model.chest.to_global(Vector3(0, 0.22, 1.4)), 1.36],
		[model.pelvis.global_position, model.pelvis.to_global(Vector3(0, 0.25, 1.35)), 1.12],
		[model.head.global_position, model.head.to_global(Vector3(0, -0.35, -1.66)), 0.85],
	]
	for leg: Dictionary in model.legs:
		volumes.append([leg["root"].global_position, leg["joint"].global_position, 0.57])
		volumes.append([leg["joint"].global_position, leg["paw"].global_position, 0.48])
	var tail: PackedVector3Array = model.tail_contact_path()
	for i in tail.size() - 1:
		volumes.append([tail[i], tail[i + 1], lerpf(0.40, 0.22, float(i) / float(tail.size() - 2))])
	for volume: Array in volumes:
		volume[2] = float(volume[2]) * BOSS_SCALE
	return volumes


static func _strike_source(path: PackedVector3Array, bottom: Vector3, top: Vector3,
		reach: float, downward: bool) -> Vector3:
	var center := (bottom + top) * 0.5
	if not downward:
		return _nearest_contact(path, center) if _path_hits(path, bottom, top, reach) else Vector3.INF
	# A landing part hits down to the floor, including players below the raised chassis.
	if bottom.y > maxf(path[0].y, path[1].y) + reach:
		return Vector3.INF
	var a := Vector3(path[0].x, center.y, path[0].z)
	var b := Vector3(path[1].x, center.y, path[1].z)
	var source := Geometry3D.get_closest_point_to_segment(center, a, b)
	return source if source.distance_squared_to(center) <= reach * reach else Vector3.INF


static func _path_hits(points: PackedVector3Array, bottom: Vector3, top: Vector3, radius: float) -> bool:
	if points.size() == 1:
		return points[0].distance_squared_to(Geometry3D.get_closest_point_to_segment(points[0], bottom, top)) <= radius * radius
	for i in points.size() - 1:
		if _within(points[i], points[i + 1], bottom, top, radius):
			return true
	return false


static func _within(a: Vector3, b: Vector3, bottom: Vector3, top: Vector3, radius: float) -> bool:
	var contact := Geometry3D.get_closest_points_between_segments(a, b, bottom, top)
	return contact[0].distance_squared_to(contact[1]) <= radius * radius


static func _nearest_contact(points: PackedVector3Array, target: Vector3) -> Vector3:
	var nearest := points[0]
	var distance := nearest.distance_squared_to(target)
	for i in points.size() - 1:
		var point := Geometry3D.get_closest_point_to_segment(target, points[i], points[i + 1])
		var candidate := point.distance_squared_to(target)
		if candidate < distance:
			distance = candidate
			nearest = point
	return nearest


func _has_runway(start: Vector3, end: Vector3, width: float) -> bool:
	var clearance := width * BOSS_SCALE
	if maxf(absf(end.x), absf(end.z)) > arena_half_extent - clearance:
		return false
	var direction := (end - start).slide(Vector3.UP)
	if direction.length_squared() < 0.00001:
		return true
	var side := direction.normalized().cross(Vector3.UP) * clearance
	for shift: Vector3 in [Vector3.ZERO, -side, side]:
		if not _ray(start + shift + Vector3.UP * 1.2, end + shift + Vector3.UP * 1.2).is_empty():
			return false
	return true


func _ray(start: Vector3, end: Vector3) -> Dictionary:
	if trace_world.is_valid():
		return trace_world.call(start, end)
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, WORLD_MASK))


func _build_landing_marker() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 1.98
	ring.outer_radius = 2.12
	ring.rings = 48
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ed6737")
	_landing = MeshInstance3D.new()
	_landing.mesh = ring
	_landing.material_override = material
	_landing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_actor.add_child(_landing)
	_landing.hide()

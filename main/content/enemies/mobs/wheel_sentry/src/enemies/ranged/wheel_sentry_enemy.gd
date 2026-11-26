extends EnemyUnit
## Uses the original projectile parry for light bolts and a fixed world-space lane for the heavy beam.

const Model = preload("res://scenes/ranged/wheel_sentry_model.tscn")
const Beam = preload("res://src/enemies/ranged/wheel_sentry_beam.gd")
const Knockdown = preload("res://src/enemies/ranged/wheel_sentry_knockdown.gd")
const Units = preload("res://src/core/units.gd")

enum Phase { PATROL, BRAKE, LIGHT, CHARGE, FIRING, RECOVERY }

const BEAM_CHARGE := 1.85
const BEAM_DURATION := 0.76
const BEAM_RADIUS := 0.84
const BEAM_COOLDOWN := 2.65
const LIGHTS_PER_BEAM := 2
const BRAKE_DURATION := 0.37
const RECOVER_DURATION := 0.34
const DRIVE_ACCELERATION := 24.0
const RETREAT_ACCELERATION := 64.0
const BRAKE_DECELERATION := 68.0
const STEERING_SPEED := 4.25
const RETREAT_STEERING_SPEED := 7.4
const RETREAT_LOOKAHEAD := 6.0 / Units.M_PER_UNIT
const EVASION_ANGLES := [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]
const APPROACH_SPEED := 1.4 / Units.M_PER_UNIT
const OVERLAP_DISTANCE := 1.6 / Units.M_PER_UNIT
const MIN_FIRE_DISTANCE := 3.8 / Units.M_PER_UNIT
const PRESSURED_BEAM_DISTANCE := 5.6 / Units.M_PER_UNIT
const ORBIT_STEER := deg_to_rad(34.0)
const BRACE_DURATION := 0.18
const MAX_GUN_PITCH := deg_to_rad(36.0)
const RETREAT_REPLAN := 0.12

var phase := Phase.PATROL
var phase_age := 0.0
var beam
var _fire_cd := 0.0
var _light_count := 0
var _light_duration := 0.55
var _strafe := 1.0
var _orbit_gear := 1.0
var _retreating := false
var _steer_delay := 0.0
var _escape_yaw := 0.0
var _ground_roll: Callable
var _wheel_speed := 0.0
var _brace_amount := 0.0
var _beam_hit := false
var _charge_sound := 0
var _recorded_audio: Node
var _charge_player: AudioStreamPlayer3D
var _locked_turret := Transform3D.IDENTITY
var _locked_position := Vector3.ZERO
var _locked_wheel_yaw := 0.0
var _knockdown: Knockdown
var _fatal_contact: Dictionary = {}
var _spawn_yaw := 0.0
var _spawn_delay := 0.95
var _spawn_model_pose := Transform3D.IDENTITY


func setup_sentry(yaw: float, first_shot_delay := 0.95) -> void:
	kind = "archer"
	_spawn_yaw = yaw
	_spawn_delay = first_shot_delay
	_recorded_audio = get_node_or_null("/root/TurnEnemyAudio")
	_fire_cd = first_shot_delay
	max_hp = P.getf("archer.hp")
	hp = max_hp
	if rig == null:
		rig = Model.instantiate()
		add_child(rig)
		_spawn_model_pose = rig.transform
	rig.turret.rotation.y = yaw
	rig.wheel_frame.rotation.y = yaw
	if level != null and level.has_method("sentry_ground_move"):
		_ground_roll = level.sentry_ground_move
		rig.support_ground = level.duelist_floor


func _on_respawn() -> void:
	_enter(Phase.PATROL)
	_fire_cd = _spawn_delay
	_light_count = 0
	_steer_delay = 0.0
	_escape_yaw = _spawn_yaw
	_fatal_contact.clear()
	_strafe = 1.0
	_orbit_gear = 1.0
	_retreating = false
	_wheel_speed = 0.0
	_brace_amount = 0.0
	_beam_hit = false
	_locked_turret = Transform3D.IDENTITY
	_locked_position = Vector3.ZERO
	_locked_wheel_yaw = 0.0
	_clear_beam()
	if _recorded_audio != null:
		_recorded_audio.stop_one_shots(self)
	if _knockdown != null:
		_knockdown.restore(rig, self)
		_knockdown = null
	if rig != null:
		# reparent(..., keep_global=false) in Knockdown.restore used to leave the
		# rig carrying the wreck's final tilt; force the spawn transform so a
		# respawn always starts upright regardless of how it died.
		if rig.get_parent() != self:
			rig.reparent(self, false)
		rig.transform = _spawn_model_pose
		rig.global_transform = spawn_xf * _spawn_model_pose
		rig.wheel_frame.rotation.y = _spawn_yaw
		rig.wheel.rotation = Vector3.ZERO
		rig.set_deployment(0.0)
		rig.set_aim(_spawn_yaw, 0.0)
		rig.set_attack_charge(0.0, false)
		rig.set_defeat_power(0.0)


func center() -> Vector3:
	return rig.turret.to_global(Vector3(0, 0, -0.15))


func mark_radius() -> float:
	return 1.62


func fire_origin() -> Vector3:
	return rig.shot_origin.global_position


func counter_origin() -> Vector3:
	return rig.intercept_origin.global_position


func can_counter() -> bool:
	return P.getb("archer.parry_counter")


func counter_in_view(observer: Camera3D) -> bool:
	for part: Dictionary in hit_parts():
		for point: Vector3 in [part["a"], part["b"]]:
			if Vision.is_visible(observer, point, part["r"]):
				return true
	return false


func hit_parts() -> Array:
	var axle: Vector3 = rig.wheel.global_position
	var wheel_axis: Vector3 = rig.wheel_frame.global_basis.z
	var parts: Array = [
		{"a": rig.turret.to_global(Vector3(0, 0.24, -0.83)),
			"b": rig.turret.to_global(Vector3(0, 0.25, 0.75)), "r": 0.61, "label": "turret"},
		{"a": axle - Vector3.UP * 0.67, "b": axle + Vector3.UP * 0.65, "r": 0.62, "label": "wheel"},
		{"a": axle - wheel_axis * 0.70, "b": axle + wheel_axis * 0.70, "r": 0.61, "label": "wheel"},
		{"a": rig.turret.to_global(Vector3(0, -0.07, -1.31)),
			"b": rig.turret.to_global(Vector3(0, 0.40, -1.30)), "r": 0.29, "label": "optic"},
	]
	for support: Dictionary in rig._supports:
		var shoe: Node3D = support["shoe"]
		if shoe.position.y < -1.1:
			parts.append({"a": shoe.to_global(Vector3(0, -0.09, -0.22)),
				"b": shoe.to_global(Vector3(0, -0.09, 0.13)), "r": 0.21,
				"label": "shoe_left" if support["side"] < 0.0 else "shoe_right"})
	return parts


func status_text() -> String:
	if phase == Phase.CHARGE:
		return "长束蓄力  ·  方向已锁定  ·  横移避开红色光道"
	if phase == Phase.FIRING:
		return "长束持续照射  ·  不可弹反"
	return ""


func step(dt: float, ctx: Dictionary) -> void:
	player = ctx.get("player")
	projectiles = ctx.get("projectiles")
	arena = ctx.get("arena", {})
	if not alive:
		advance_fatal_reaction(dt, Fx.time_scale)
		return
	if player == null or dt <= 0.0:
		return
	_fire_cd = maxf(0.0, _fire_cd - dt)
	_steer_delay = maxf(0.0, _steer_delay - dt)
	phase_age += dt
	match phase:
		Phase.PATROL:
			_patrol(dt)
		Phase.BRAKE:
			_brake(dt)
		Phase.LIGHT:
			if player.alive:
				_navigate(dt)
			_charge_light(dt)
		Phase.CHARGE:
			_charge_beam(dt)
		Phase.FIRING:
			_fire_beam()
		Phase.RECOVERY:
			var pose := 1.0 - smoothstep(0.0, RECOVER_DURATION, phase_age)
			rig.set_deployment(pose)
			rig.set_attack_charge(0.0, true)
			if player.alive and pose <= 0.68:
				var target := _target_point()
				var flat: Vector3 = (target - rig.global_position).slide(Vector3.UP)
				_aim_at(target, 1.0 - exp(-7.0 * dt))
				if _wants_retreat(flat):
					_back_away(_target_yaw(flat), dt)
				elif not is_zero_approx(_wheel_speed):
					_drive(_target_yaw(flat), 0.0, 0.0, dt)
			if phase_age >= RECOVER_DURATION:
				_enter(Phase.PATROL)


func _patrol(dt: float) -> void:
	if not player.alive:
		return
	_aim_at(_target_point(), 1.0 - exp(-7.0 * dt))
	var distance := _navigate(dt)
	if distance >= P.getf("archer.aggro_range"):
		return
	if level != null and level.state != "fight":
		return
	# A pursuer cutting off a retreat can prompt the long beam after the first light shot.
	var beam_due := _light_count >= LIGHTS_PER_BEAM and _fire_cd <= 0.0
	var pressured := _retreating and _light_count > 0 and distance <= PRESSURED_BEAM_DISTANCE
	var wants_beam := distance >= MIN_FIRE_DISTANCE and (beam_due or pressured)
	var wants_light := _light_count < LIGHTS_PER_BEAM and _fire_cd <= 0.0
	if not (wants_beam or wants_light) or not _has_shot(_target_point()):
		return
	if wants_beam:
		_enter(Phase.BRAKE)
	else:
		_light_duration = maxf(0.05, P.getf("archer.telegraph"))
		_enter(Phase.LIGHT)


func _navigate(dt: float) -> float:
	var flat: Vector3 = (_target_point() - rig.global_position).slide(Vector3.UP)
	var distance := flat.length()
	var keep := P.getf("archer.keep_dist")
	var approach := distance > keep * 1.35
	var facing := _target_yaw(flat)
	if _wants_retreat(flat):
		_back_away(facing, dt)
	else:
		if distance < keep * 0.90:
			_orbit_gear = -1.0
		elif distance > keep * 1.10:
			_orbit_gear = 1.0
		var steer := deg_to_rad(14.0) if approach else ORBIT_STEER
		var pace := P.getf("sentry.speed") * (1.0 if approach else 0.62)
		_drive(facing, -_strafe * _orbit_gear * steer, pace * _orbit_gear, dt)
		if randf() < dt * 0.4:
			_strafe = -_strafe
	return distance


func _wants_retreat(flat: Vector3) -> bool:
	var keep := P.getf("archer.keep_dist")
	# 用实际水平速度（含冲刺的真实瞬时速度），比 move_command 目标值更准
	var velocity: Vector3 = player.rig._vel_h
	var pressing := velocity.dot(-flat.normalized()) >= APPROACH_SPEED
	var factor := 0.94
	if pressing:
		factor = 1.28
	if _retreating:
		factor += 0.10
	_retreating = flat.length_squared() < pow(keep * factor, 2)
	return _retreating


func _back_away(facing: float, dt: float) -> void:
	_orbit_gear = -1.0
	var yaw: float = rig.wheel_frame.rotation.y
	var gap: Vector3 = (player.rig.global_position - rig.global_position).slide(Vector3.UP)
	# Retain the wheel's heading when player overlap makes the bearing unstable.
	if gap.length_squared() < OVERLAP_DISTANCE * OVERLAP_DISTANCE:
		facing = yaw
	if _steer_delay <= 0.0:
		_steer_delay = RETREAT_REPLAN
		_escape_yaw = facing
		var straight := Vector3(sin(facing), 0.0, cos(facing)) * RETREAT_LOOKAHEAD
		if _clear_roll(straight) < 0.98 or absf(angle_difference(yaw, facing)) > deg_to_rad(50.0):
			var best := -INF
			for angle: float in EVASION_ANGLES:
				var turn := deg_to_rad(angle * _strafe)
				var heading := facing + turn
				var rear := Vector3(sin(heading), 0.0, cos(heading)) * RETREAT_LOOKAHEAD
				var clearance := _clear_roll(rear)
				if not _ground_roll.is_valid():
					clearance = minf(clearance, _clear_roll(rear * 0.5))
				var score := clearance * 2.1 + cos(angle_difference(yaw, heading)) * 0.60 + cos(turn) * 0.32
				if score > best:
					best = score
					_escape_yaw = heading
	_drive(facing, angle_difference(facing, _escape_yaw), -P.getf("sentry.retreat_speed"), dt, true)


func _brake(dt: float) -> void:
	var target := _target_point()
	var offset: Vector3 = target - rig.global_position
	if _brace_amount < 0.63:
		_drive(_target_yaw(offset), 0.0, 0.0, dt)
	_aim_at(target, 1.0 - exp(-10.0 * dt))
	if not is_zero_approx(_wheel_speed):
		return
	_brace_amount = move_toward(_brace_amount, 1.0, dt / BRACE_DURATION)
	rig.set_deployment(smoothstep(0.0, 1.0, _brace_amount))
	rig.set_attack_charge(0.0, true)
	if phase_age < BRAKE_DURATION or _brace_amount < 1.0:
		return
	if not player.alive or not _has_shot(target):
		_recover(0.30)
	else:
		_begin_beam()


func _target_yaw(offset: Vector3) -> float:
	if Vector2(offset.x, offset.z).length_squared() < 0.0001:
		return rig.wheel_frame.rotation.y
	return atan2(-offset.x, -offset.z)


func _drive(facing: float, steer: float, desired_speed: float, dt: float, evading := false) -> void:
	var changing_gear := _wheel_speed * desired_speed < 0.0
	var heading := facing if changing_gear else facing + steer
	var turn_speed := RETREAT_STEERING_SPEED if evading else STEERING_SPEED
	var yaw := rotate_toward(float(rig.wheel_frame.rotation.y), heading, turn_speed * dt)
	rig.wheel_frame.rotation.y = yaw
	# If the player crosses behind the machine, slow to realign before accelerating again.
	var deviation := absf(angle_difference(heading if evading else facing, yaw))
	var alignment := 1.0 - smoothstep(deg_to_rad(39.0), deg_to_rad(69.0), deviation)
	var speed := 0.0 if changing_gear else desired_speed * alignment
	var acceleration := RETREAT_ACCELERATION if evading else DRIVE_ACCELERATION
	if is_zero_approx(speed) or absf(speed) < absf(_wheel_speed):
		acceleration = BRAKE_DECELERATION
	_wheel_speed = move_toward(_wheel_speed, speed, acceleration * dt)
	if is_zero_approx(_wheel_speed):
		return
	var forward := -Vector3(sin(yaw), 0.0, cos(yaw))
	var travel := forward * _wheel_speed * dt
	var from: Vector3 = rig.global_position
	var goal: Vector3 = _ground_roll.call(from, from + travel) if _ground_roll.is_valid() \
		else from + travel * _clear_roll(travel)
	rig.global_position = goal
	var distance := from.distance_to(goal) * signf(_wheel_speed)
	rig.wheel.rotation.x = wrapf(rig.wheel.rotation.x - distance / rig.WHEEL_RADIUS, -PI, PI)


func _clear_roll(travel: Vector3) -> float:
	if level == null:
		return 1.0
	var from: Vector3 = rig.global_position
	var goal := from + travel
	if _ground_roll.is_valid():
		if travel.is_zero_approx():
			return 1.0
		var reachable: Vector3 = _ground_roll.call(from, goal)
		return clampf((reachable - from).dot(travel) / travel.length_squared(), 0.0, 1.0)
	if level.clamp_enemy_position(goal, scale_factor).is_equal_approx(goal):
		return 1.0
	# Stop along the wheel's forward axis at a wall instead of sliding along it.
	var safe := 0.0
	var blocked := 1.0
	for i in 6:
		var share := (safe + blocked) * 0.5
		var point := from + travel * share
		if level.clamp_enemy_position(point, scale_factor).is_equal_approx(point):
			safe = share
		else:
			blocked = share
	return safe


func _target_point() -> Vector3:
	return player.rig.global_position + Vector3(0, 2.30, 0)


func _aim_at(point: Vector3, weight: float) -> void:
	var aim := _gun_angles(point)
	rig.set_aim(lerp_angle(rig.turret.rotation.y, aim.y, weight),
		lerpf(rig.turret.rotation.x, clampf(aim.x, -MAX_GUN_PITCH, MAX_GUN_PITCH), weight))


func _gun_angles(point: Vector3) -> Vector2:
	var offset: Vector3 = point - rig.global_position
	var yaw := _target_yaw(offset)
	var horizontal := offset.slide(Vector3.UP).length()
	var muzzle_y: float = rig.shot_origin.position.y
	var pitch := 0.0
	# Account for the muzzle below the pivot and the lift of the aiming ring.
	for _sample in 3:
		offset.y = point.y - rig.global_position.y - rig.gun_height(pitch)
		pitch = atan2(offset.y, horizontal) - asin(clampf(muzzle_y / maxf(0.08, offset.length()), -1.0, 1.0))
	return Vector2(pitch, yaw)


func _has_shot(point: Vector3) -> bool:
	var aim := _gun_angles(point)
	if absf(aim.x) > MAX_GUN_PITCH:
		return false
	var axes := Basis.from_euler(Vector3(aim.x, aim.y, 0.0))
	var muzzle: Vector3 = rig.global_position + Vector3.UP * rig.gun_height(aim.x) + axes * rig.shot_origin.position
	var offset := point - muzzle
	return offset.dot(-axes.z) > 0.10 and Beam.trace_obstruction(muzzle, -axes.z, arena) >= offset.length()


func _charge_light(dt: float) -> void:
	if not player.alive:
		stop_charge_sound()
		rig.set_attack_charge(0.0, false)
		_enter(Phase.PATROL)
		return
	var origin := fire_origin()
	var target := _target_point()
	var speed := P.getf("archer.arrow_speed")
	target += player.rig.move_command * (origin.distance_to(target) / maxf(speed, 1.0)) * P.getf("archer.aim_lead")
	_aim_at(target, 1.0 - exp(-12.0 * dt))
	var progress := clampf(phase_age / _light_duration, 0.0, 1.0)
	rig.set_attack_charge(progress, false)
	if phase_age < _light_duration:
		_update_charge_sound(progress, false)
		return
	stop_charge_sound()
	if projectiles != null and not _has_shot(target):
		target = _target_point()
	if projectiles != null and _has_shot(target):
		_aim_at(target, 1.0)
		origin = fire_origin()
		var direction: Vector3 = -rig.turret.global_basis.z.normalized()
		var shot: Dictionary = projectiles.spawn_arrow(origin, direction, speed, P.getf("archer.arrow_damage"),
			"enemy", Color("b27dff"), true)
		shot["source"] = self
		_light_count += 1
		Fx.sentry_bolt_flash(origin, direction)
		Fx.shake(0.24)
		_play_sound("laser_small", "laser", origin, {"gain": 0.40})
	rig.set_attack_charge(0.0, false)
	_fire_cd = P.getf("archer.fire_interval")
	_enter(Phase.PATROL)


func _begin_beam() -> void:
	# The supports are already down. Nothing in CHARGE or FIRING tracks the player.
	rig.set_deployment(1.0)
	_aim_at(_target_point(), 1.0)
	_locked_turret = rig.turret.global_transform
	_locked_position = rig.global_position
	_locked_wheel_yaw = rig.wheel_frame.rotation.y
	var start := fire_origin()
	var direction: Vector3 = -rig.turret.global_basis.z.normalized()
	beam = Beam.new()
	add_child(beam)
	beam.configure(start, direction, BEAM_RADIUS, arena)
	_beam_hit = false
	_enter(Phase.CHARGE)
	_update_charge_sound(0.0, true)


func _charge_beam(dt: float) -> void:
	if not player.alive:
		_clear_beam()
		_recover(BEAM_COOLDOWN)
		return
	_hold_beam_pose()
	var progress := clampf(phase_age / BEAM_CHARGE, 0.0, 1.0)
	beam.show_warning(progress)
	rig.set_attack_charge(progress, true)
	if phase_age >= BEAM_CHARGE * 0.78 and phase_age - dt < BEAM_CHARGE * 0.78:
		_play_sound("laser_warning", "ping", beam.start, {"gain": 1.05, "rate": 1.32})
	if phase_age < BEAM_CHARGE:
		_update_charge_sound(progress, true)
		return
	stop_charge_sound()
	_light_count = 0
	_enter(Phase.FIRING)
	var direction: Vector3 = beam.direction
	Fx.spark(beam.start, direction, 1.85)
	Fx.impact_ring(rig.global_position, 2.0, 1.7)
	Fx.shake(1.42)
	_play_sound("laser_heavy", "laser", beam.start, {"gain": 1.45, "rate": 0.8, "prio": 4})
	_fire_beam()


func _fire_beam() -> void:
	if phase_age >= BEAM_DURATION:
		_clear_beam()
		_recover(BEAM_COOLDOWN)
		return
	_hold_beam_pose()
	beam.show_fire(phase_age, BEAM_DURATION)
	rig.set_attack_charge(1.0 - phase_age / BEAM_DURATION, true)
	if _beam_hit or not player.alive or player.invuln > 0.0:
		return
	var cap := player.capsule()
	var from: Vector3 = beam.start
	var direction: Vector3 = beam.direction
	var limit: float = beam.obstruction_distance
	if limit <= 0.0:
		return
	var end_at: Vector3 = beam.end
	if not is_finite(limit):
		# Test far enough to cover the target capsule, even past the visual mesh.
		var a: Vector3 = cap["a"]
		var b: Vector3 = cap["b"]
		var reach := maxf((a - from).dot(direction), (b - from).dot(direction))
		end_at = from + direction * maxf(reach, 0.0)
	var impact := Hit.sweep_sphere(from, end_at, beam.radius, cap["a"], cap["b"], cap["r"])
	if not impact.get("hit", false):
		return
	var contact: Vector3 = impact["point"]
	# The rounded sweep can still touch a capsule just behind a wall.
	var distance := (contact - from).dot(direction)
	if distance < 0.0 or distance > limit:
		return
	_beam_hit = true
	player.hurt(P.getf("archer.arrow_damage"), impact.get("normal", Vector3.UP), "被长激光束击中")


func _hold_beam_pose() -> void:
	rig.global_position = _locked_position
	rig.set_deployment(1.0)
	rig.turret.global_transform = _locked_turret
	rig.wheel_frame.rotation.y = _locked_wheel_yaw


func _enter(next: Phase) -> void:
	phase = next
	phase_age = 0.0
	if next == Phase.BRAKE:
		_brace_amount = 0.0


func _recover(cooldown: float) -> void:
	rig.set_attack_charge(0.0, true)
	_fire_cd = cooldown
	_enter(Phase.RECOVERY)


func _play_sound(cue: String, fallback: String, at: Vector3, options: Dictionary) -> void:
	if _recorded_audio != null and _recorded_audio.play_at(self, "wheel", cue, fallback, at, options, Snd):
		return
	Snd.play_at(fallback, at, options)


func _update_charge_sound(progress: float, heavy: bool) -> void:
	var gain := lerpf(0.32, 1.55, progress) if heavy else lerpf(0.28, 0.74, progress)
	var rate := lerpf(0.80, 2.10, progress * progress) if heavy else lerpf(1.50, 2.20, progress)
	if _recorded_audio != null:
		var recording: AudioStream = _recorded_audio.stream("wheel", "charge_loop", true)
		if recording != null:
			if _charge_player == null:
				_charge_player = AudioStreamPlayer3D.new()
				_charge_player.stream = recording
				rig.shot_origin.add_child(_charge_player)
			_recorded_audio.mix(_charge_player, Snd, "sentry_charge", gain, rate)
			if not _charge_player.playing:
				_charge_player.play()
			return
	if not Snd.set_loop_mix(_charge_sound, gain, rate):
		_charge_sound = Snd.loop_on("sentry_charge", rig.shot_origin, {"gain": gain, "rate": rate, "prio": 3})


func stop_charge_sound() -> void:
	if _charge_player != null:
		_charge_player.stop()
	if _charge_sound != 0:
		Snd.stop(_charge_sound)
		_charge_sound = 0


func _clear_beam() -> void:
	stop_charge_sound()
	if is_instance_valid(beam):
		beam.hide()
		beam.queue_free()
	beam = null


func hurt(amount: float, normal := Vector3.UP, knock := 0.0) -> void:
	var planted := phase == Phase.CHARGE or phase == Phase.FIRING
	if alive and amount >= hp:
		if _fatal_contact.is_empty():
			_fatal_contact = {"point": center(), "force": -normal, "part": ""}
		knock = 0.0
	super.hurt(amount, normal, 0.0 if planted else knock)


func hurt_by_blade(amount: float, normal: Vector3, knock: float, travel: Vector3, contact: Dictionary) -> void:
	if not alive or amount <= 0.0:
		return
	if amount >= hp:
		var cut := travel.normalized()
		var inward := -normal.normalized()
		if cut.is_zero_approx():
			cut = inward
		elif cut.dot(inward) > 0.0:
			cut = cut.lerp(inward, 0.40).normalized()
		var force: Vector3 = contact.get("force", cut)
		var point: Vector3 = contact.get("contact", contact.get("blade_point", center()))
		var part: String = contact.get("part", "")
		var on_turret: Vector3 = rig.turret.to_local(point)
		if part == "turret" and on_turret.z < -1.10 and absf(on_turret.x) < 0.40:
			part = "optic"
		_fatal_contact = {"point": point, "force": force, "part": part}
	hurt(amount, normal, knock)


func die() -> void:
	if not alive:
		return
	alive = false
	_clear_beam()
	rig.set_attack_charge(0.0, false)
	var point: Vector3 = _fatal_contact.get("point", center())
	var force: Vector3 = _fatal_contact.get("force", Vector3.ZERO)
	_knockdown = Knockdown.new()
	var supports := smoothstep(0.0, 0.78, float(rig.deployment))
	_knockdown.begin(rig, arena, point, force, _fatal_contact.get("part", ""), _wheel_speed, supports)
	if level != null:
		level.on_enemy_died(self)


func advance_fatal_reaction(dt: float, rate: float) -> void:
	if _knockdown == null or dt <= 0.0:
		return
	if is_zero_approx(_knockdown.age):
		Fx.spark(_fatal_contact.get("point", center()), _knockdown.force, 1.72)
	_knockdown.advance(rig, self, dt, rate)
	for event in _knockdown.take_contacts():
		var point: Vector3 = event["point"]
		match event["kind"]:
			"break":
				_play_sound("armor_break", "sentry_break", point, {"pos": point, "gain": 1.32, "prio": 4})
				Fx.spark(point, _knockdown.force, 1.18)
				var arc := point + Vector3.UP * 0.16 + _knockdown.force * 0.12
				Fx.beam(point, arc, 0.043, Color("c5aaff"), 0.075)
				Fx.beam(arc, arc + rig.global_basis.x.normalized() * 0.17, 0.029, Color("cae6ff"), 0.065)
			"rim":
				var normal: Vector3 = event["normal"]
				_play_sound("rim_scrape", "clang", point, {"pos": point, "gain": 1.05, "rate": 0.78})
				Fx.spark(point + normal * 0.045, normal * 0.7 - _knockdown.force * 0.75, 1.40)
				Fx.shake(0.16)
			"rim_spark":
				var normal: Vector3 = event["normal"]
				Fx.spark(point + normal * 0.045, normal * 0.7 - _knockdown.force * 0.75, 0.60)
			"shell":
				_play_sound("body_impact", "hit", point, {"pos": point, "gain": 1.7, "rate": 0.72, "prio": 4})
				Fx.spark(point + Vector3.UP * 0.055, Vector3.UP, 1.38)
				Fx.shake(0.50)


func _exit_tree() -> void:
	stop_charge_sound()


func hud_alert(target: PlayerUnit) -> bool:
	if phase != Phase.CHARGE or phase_age < BEAM_CHARGE - 0.55 or not is_instance_valid(beam):
		return false
	var cap := target.capsule()
	var stop: Vector3 = beam.end
	if not is_finite(beam.obstruction_distance):
		var edge: Vector3 = cap["b"]
		stop = beam.start + beam.direction * (edge.distance_to(beam.start) + float(cap["r"]))
	var hit := Hit.sweep_sphere(beam.start, stop, beam.radius, cap["a"], cap["b"], cap["r"])
	return hit.get("hit", false)

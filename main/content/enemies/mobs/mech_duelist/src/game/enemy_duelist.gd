extends "res://src/game/enemy_base.gd"
## The elite duelist opens with one combo, then switches to melee pursuit.

const Units = preload("res://src/core/units.gd")
const HitMath = preload("res://src/core/hitgd.gd")
const CombatRig = preload("res://src/enemies/duelist/duelist_combat_rig.gd")
const Sequence = preload("res://src/enemies/duelist/duelist_sequence.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Brace = preload("res://src/enemies/duelist/duelist_ground_brace.gd")
const Lunge = preload("res://src/enemies/duelist/duelist_lunge.gd")
const ReturnCut = preload("res://src/enemies/duelist/duelist_return_cut.gd")
const PursuitSweep = preload("res://src/enemies/duelist/duelist_pursuit_sweep.gd")
const Knockdown = preload("res://src/enemies/duelist/duelist_knockdown.gd")
const Wreckage = preload("res://src/enemies/duelist/duelist_wreckage.gd")
const MODEL_SCALE := 1.36
const PACE_CENTER := Vector3(0.0, 0.0, 5.60)
const WAKE_RANGE := 20.0 / Units.M_PER_UNIT
const NORMAL_ATTACK_RATE := 2.0
const ROUTED_STRIKE_REACH := 5.05
const STAIR_STRIKE_CLEARANCE := 2.85
const STAIR_MELEE_CLEARANCE := 3.05

enum Phase { PACING, SETTLING, OPENING, MELEE }

var sequence := Sequence.new()
var phase := Phase.PACING
var _normal_strike := 0
var _knockdown: Knockdown
var _wreckage: Wreckage
var _blade_impulse := Vector3.ZERO
var _blade_part := ""
var _blade_side := 0.0
var _pending_armor_break := false
var _break_point := Vector3.ZERO
var _pace_center := PACE_CENTER
var _cover: Array = []
var _bounds := AABB()
var _opening_pursuit := false
var _used_ground_motion := false
var _player_floor := Vector3.ZERO


func setup_duelist(p_player: PlayerUnit, cover: Array, bounds := AABB(), spawn := Vector3.INF, health := 3.0) -> void:
	player = p_player
	kind = "duelist"
	max_hp = health
	hp = max_hp
	damage = 35.0
	scale_factor = MODEL_SCALE
	if rig == null:
		rig = CombatRig.new()
		rig.name = "Duelist"
		rig.scale = Vector3.ONE * MODEL_SCALE
		if level != null:
			rig.kerb = level.arena.get("kerb", Vector2(INF, 0.0))
		add_child(rig)
	if sequence.get_parent() == null:
		add_child(sequence)
	sequence.normal_attack_rate = NORMAL_ATTACK_RATE
	var pace_center := PACE_CENTER
	if spawn.is_finite():
		pace_center = spawn - Vector3(sin(Pace.START_ANGLE), 0, cos(Pace.START_ANGLE)) * Pace.RADIUS
	_pace_center = pace_center
	_cover = cover
	_bounds = bounds
	sequence.setup(rig, pace_center, cover, bounds, Snd, func() -> float: return P.getf("audio.master"))
	if level != null and level.has_method("duelist_ground_move"):
		rig.ground_sampler = level.duelist_floor
		rig.attack_ground_move = level.duelist_ground_move
		rig.stair_lane = level.duelist_stair_lane
		rig.attack_blade_clear = level.duelist_blade_clear
		sequence.can_strike_from = func(at: Vector3) -> bool: return level.duelist_can_strike(at, _player_floor)
		sequence.patrol.route_point = level.duelist_route_point
		sequence.patrol.ground_move = level.duelist_ground_move
		sequence.patrol.on_stairs = level.duelist_on_stairs
	_player_floor = player.rig.global_position
	sequence.advance_pacing(0.0, _focus(), false)


## 死亡演出是物理性的：碎甲剥成独立刚体、佩剑脱手、灯效被压低。
## 重建 rig 要 ~370ms（_ready 全量生成网格），所以重生做物理还原：
## 碎板挂回原父节点、碎片刚体销毁、灯效按基线重赋，关节姿态交给
## seek(0)+advance_pacing 逐帧重写（finish_pose 每帧把剑写回腕部）。
func _on_respawn() -> void:
	phase = Phase.PACING
	_opening_pursuit = false
	_used_ground_motion = false
	_player_floor = player.rig.global_position
	rig.cancel_strike()
	_normal_strike = 0
	_blade_impulse = Vector3.ZERO
	_blade_part = ""
	_blade_side = 0.0
	_pending_armor_break = false
	if _knockdown != null:
		_knockdown.restore()
		_knockdown = null
	if _wreckage != null:
		_wreckage.restore(rig)
		_wreckage = null
	rig.restore_power()
	sequence.seek(0.0, _focus())
	sequence.advance_pacing(0.0, _focus(), false)
	sequence.show()


func ground_position() -> Vector3:
	return rig.global_position


func uses_ground_motion() -> bool:
	return _used_ground_motion


func hit_parts() -> Array:
	return rig.hit_parts()


func center() -> Vector3:
	return rig.torso.to_global(Vector3(0, 0.52, 0))


func mark_radius() -> float:
	return 2.8


func is_in_view(camera: Camera3D) -> bool:
	return rig.body_in_view(camera)


func blocks_when_seen() -> bool:
	return true


func constrain_player_motion(start: Vector3, goal: Vector3, radius: float) -> Vector3:
	if minf(start.y, goal.y) > rig.head.global_position.y + 0.45 * scale_factor:
		return goal
	return HitMath.slide_around_body(start, goal, rig.global_position, radius + 1.1 * scale_factor)


func on_attack_blocked() -> void:
	if phase == Phase.PACING or phase == Phase.SETTLING:
		sequence.begin_guard()
	elif phase == Phase.MELEE and sequence.patrol.moving and sequence.normal_pose.is_empty() \
			and sequence.rebound_pose.is_empty():
		sequence.begin_guard()


func on_attack_parried(normal: Vector3) -> void:
	if phase == Phase.MELEE and _normal_strike == sequence.normal_move.STRIKES.size() - 1 \
			and sequence.begin_rebound(_focus(), normal):
		rig.cancel_strike()


func step(dt: float, ctx: Dictionary) -> void:
	_used_ground_motion = false
	if not alive:
		_step_knockdown(dt, Fx.time_scale)
		return
	player = ctx.get("player")
	if not player.alive:
		sequence.sync_audio(true)
		return
	if player.rig.jump_state != "AIR":
		_player_floor = player.rig.global_position
	sequence.show()
	match phase:
		Phase.PACING, Phase.SETTLING:
			var to_player: Vector3 = player.rig.global_position - rig.global_position
			if phase == Phase.PACING and to_player.slide(Vector3.UP).length() <= WAKE_RANGE:
				phase = Phase.SETTLING
			if sequence.advance_pacing(dt, _focus(), phase == Phase.SETTLING):
				phase = Phase.OPENING
		Phase.OPENING:
			if not _step_opening_route(dt):
				_step_opening(dt)
			if sequence.finished:
				phase = Phase.MELEE
		Phase.MELEE:
			_set_melee_route()
			_step_normal(dt)
			_used_ground_motion = rig.has_attack_lane(rig.global_position) or (sequence.patrol.ground_move.is_valid() \
				and sequence.normal_pose.is_empty() and not sequence.sprint_flashing \
				and sequence.sprint_windup < 0.0 and sequence.rebound_pose.is_empty())
	sequence.advance_guard(dt, _focus())


func _step_opening_route(dt: float) -> bool:
	if not sequence.patrol.route_point.is_valid():
		return false
	if not _opening_pursuit:
		var charging := Sequence.ATTACK_AT - sequence.time
		if charging <= 0.0 or charging > dt or not sequence.dash.is_empty() \
			or not level.duelist_needs_route(rig.global_position, _player_floor):
			return false
		sequence.advance(charging, _focus())
		sequence.begin_routed_opening()
		sequence.sync_audio(true)
		_opening_pursuit = true
		dt -= charging
	_used_ground_motion = true
	var can_approach: bool = level.duelist_can_strike(rig.global_position, _player_floor)
	var gap: float = (rig.global_position - _player_floor).slide(Vector3.UP).length()
	var clearance := Lunge.TARGET_CLEARANCE if can_approach and gap < 12.0 else 0.0
	if gap < 12.0 and rig.has_attack_lane(rig.global_position) and rig.has_attack_lane(_player_floor):
		clearance = STAIR_STRIKE_CLEARANCE
	sequence.advance_routed_opening(dt, _focus(), _player_floor, clearance)
	if sequence.patrol.landed and player.rig.jump_state != "AIR" \
		and (rig.global_position - _player_floor).slide(Vector3.UP).length() <= ROUTED_STRIKE_REACH \
		and level.duelist_can_strike(rig.global_position, _player_floor):
		sequence.begin_routed_strike(_focus())
		_opening_pursuit = false
	return true


func _set_melee_route() -> void:
	if not sequence.patrol.route_point.is_valid():
		return
	var at: Vector3 = rig.global_position
	sequence.climbing = rig.has_attack_lane(at)
	sequence.seeking_level = not level.duelist_can_strike(at, _player_floor)
	var gap := (at - _player_floor).slide(Vector3.UP).length()
	sequence.stair_rush_ready = sequence.climbing and gap > Sequence.STAIR_SPRINT_MIN \
		and gap <= Sequence.STAIR_SPRINT_MAX and player.rig.jump_state != "AIR" \
		and level.duelist_can_rush(at, _player_floor, Sequence.STAIR_FLASH_CLEARANCE)
	sequence.patrol.route_goal = _player_floor if sequence.seeking_level or sequence.climbing else Vector3.INF
	sequence.patrol.route_clearance = STAIR_MELEE_CLEARANCE if sequence.climbing and not sequence.seeking_level else 0.0


func _step_opening(dt: float) -> void:
	var blade_before: Transform3D = rig.weapon_spin.global_transform
	var before := sequence.time - Sequence.ATTACK_AT
	var previous_end: Vector3 = sequence.dash.get("end", Vector3.INF)
	var previous_aim: float = sequence.dash.get("aim", INF)
	sequence.advance(dt, _focus())
	var after := sequence.time - Sequence.ATTACK_AT
	if before < 0.0 and after >= 0.0:
		swung_serial += 1
		if not sequence.dash.is_empty():
			rig.start_strike(sequence.dash, after)
	# A long frame can cross the first cut and the handoff. Resolve the first sweep before switching.
	if swung_serial == 1 and before >= Lunge.CUT_END and not sequence.return_pose.is_empty():
		swung_serial += 1
		rig.start_return(sequence.return_pose, after)
	elif before >= 0.0 and after < Lunge.DURATION and not sequence.dash.is_empty():
		var new_end: Vector3 = sequence.dash["end"]
		var new_aim: float = sequence.dash["aim"]
		if not previous_end.is_equal_approx(new_end) or not is_equal_approx(previous_aim, new_aim):
			rig.start_strike(sequence.dash, after)
	rig.update_strike(before, after, dt, blade_before)
	sequence.sync_audio(sequence.finished)


func _step_normal(dt: float) -> void:
	var blade_before: Transform3D = rig.weapon_spin.global_transform
	var serial := sequence.normal_serial
	var before := sequence.normal_time
	sequence.advance(dt, _focus())
	if sequence.normal_serial != serial:
		swung_serial += 1
		_normal_strike = 0
		before = 0.0
		rig.start_normal(sequence.normal_move, sequence.normal_pose, sequence.normal_time,
			sequence.normal_attack_rate, _normal_strike, sequence.normal_windup_extension)
	if not sequence.normal_pose.is_empty():
		var strikes: Array = sequence.normal_move.STRIKES
		var next := _normal_strike + 1
		# Resolve the current sweep before publishing the next hit serial.
		if next < strikes.size() and before >= strikes[_normal_strike].w and sequence.normal_time >= strikes[next].x:
			swung_serial += 1
			_normal_strike = next
			before = minf(before, strikes[next].z)
			rig.start_normal(sequence.normal_move, sequence.normal_pose, sequence.normal_time,
				sequence.normal_attack_rate, next, sequence.normal_windup_extension)
		rig.update_strike(before, sequence.normal_time, dt, blade_before)
	else:
		var end := Lunge.DURATION + ReturnCut.DURATION
		rig.update_strike(end, end, dt)


func hurt(amount: float, normal := Vector3.UP, _knock := 0.0) -> void:
	# Valid off-screen hits can weaken the opening, but cannot cancel the two cuts by killing the duelist.
	if max_hp > 1.0 and (phase == Phase.SETTLING or phase == Phase.OPENING):
		amount = minf(amount, maxf(0.0, hp - 1.0))
	super.hurt(amount, normal, 0.0)


func hurt_by_blade(amount: float, normal: Vector3, knock: float, travel: Vector3, contact: Dictionary) -> void:
	_blade_impulse = contact.get("force", travel if travel.slide(Vector3.UP).length_squared() > 0.001 else -normal)
	_blade_part = contact.get("part", "")
	_blade_side = contact.get("side", 0.0)
	hurt(amount, normal, knock)
	if alive:
		_blade_impulse = Vector3.ZERO
		_blade_part = ""
		_blade_side = 0.0


func die() -> void:
	if not alive:
		return
	alive = false
	rig.cancel_strike()
	sequence.sync_audio(true)
	sequence.hide()
	_knockdown = Knockdown.new()
	var path := {}
	var launch_dir := _blade_impulse.slide(Vector3.UP).normalized()
	if level != null and level.has_method("duelist_defeat_path") and not launch_dir.is_zero_approx():
		path = level.duelist_defeat_path(rig.global_position, launch_dir)
	_knockdown.begin(rig, _blade_impulse, path, _blade_part, _blade_side)
	if level != null:
		level.on_enemy_died(self)


func knockdown_landing_position() -> Vector3:
	return _knockdown.landing if _knockdown != null and _knockdown.launched else rig.global_position


func show_fatal_damage(point: Vector3) -> void:
	if alive or _pending_armor_break or _wreckage != null or _blade_part.is_empty():
		return
	_knockdown.capture_contact_pose(rig)
	_break_point = rig.to_local(point)
	_pending_armor_break = true


func advance_fatal_reaction(dt: float, rate: float) -> void:
	if not alive and _knockdown != null:
		_step_knockdown(dt, rate)


func _break_armor(rate: float) -> void:
	_pending_armor_break = false
	_wreckage = Wreckage.new()
	var point: Vector3 = rig.to_global(_break_point)
	if not _wreckage.begin(rig, point, _blade_impulse, _blade_part, _blade_side, rate):
		_wreckage = null
		return
	var source := _wreckage.breach.global_position
	Snd.play_at("armor_snap", source, {"pos": source, "gain": 1.48, "prio": 5})


func _step_knockdown(dt: float, rate: float) -> void:
	var before := _knockdown.age
	_knockdown.advance(rig, dt, rate)
	var sound_time := Knockdown.HIT_LIFT_OFF if not _blade_part.is_empty() else 0.0
	if before <= sound_time and _knockdown.age > sound_time:
		Snd.play_at("death", center(), {"gain": 0.62})
	if _wreckage != null:
		var previous := _wreckage.age
		_wreckage.step(dt, rate)
		for pulse: float in [0.082, 0.26, 0.51, 0.91]:
			if previous < pulse and _wreckage.age >= pulse:
				_short_circuit()
	elif _pending_armor_break and _knockdown.age >= Knockdown.ARMOR_RELEASE:
		_break_armor(rate)
	if _knockdown.body_contact_time == Knockdown.BODY_LAND and before < Knockdown.KNEEL and _knockdown.age >= Knockdown.KNEEL:
		var knee_contact: Vector3 = rig.legs[0]["knee"].global_position
		knee_contact.y = rig.global_position.y + 0.08
		Snd.play_at("step", knee_contact, {"gain": 1.00, "rate": 0.84})
		Fx.spark(knee_contact, -rig.global_basis.z, 0.35)
	if _knockdown.take_sword_impact(before):
		var contact: Vector3 = rig.weapon_root.global_position
		Snd.play_at("clang", contact, {"gain": 0.86})
		Fx.spark(contact, Vector3.UP, 0.52)
	if before < _knockdown.body_contact_time and _knockdown.age >= _knockdown.body_contact_time:
		var shoulder_contact: Vector3 = rig.arms[0]["shoulder"].global_position
		shoulder_contact.y = rig.global_position.y + 0.12
		var power := 1.0 if _knockdown.launched else 0.62
		Snd.play_at("hit", shoulder_contact, {"gain": 0.82 + power, "rate": 0.70})
		Fx.spark(shoulder_contact, -rig.global_basis.x, power)
		Fx.shake(0.6 + power)


func _short_circuit() -> void:
	var housing: Node3D = _wreckage.breach
	var socket := housing.to_global(Vector3(0.05, -0.07, -0.11))
	var bend := housing.to_global(Vector3(-0.10, 0.03, -0.16))
	var wire := housing.to_global(Vector3(0.04, 0.13, -0.10))
	Fx.beam(socket, bend, 0.068, Color("bef5ff"), 0.06)
	Fx.beam(bend, wire, 0.049, Color("a2d9ff"), 0.06)
	Fx.spark(socket, -housing.global_basis.z, 0.62)


func pause_for_replay() -> void:
	sequence.sync_audio(true)
	sequence.hide()


func status_text() -> String:
	if not alive:
		return ""
	if sequence.guarding:
		return "架刀 · 格挡"
	if phase == Phase.PACING:
		return "侧身踱步 · 20 米内触发"
	if phase == Phase.SETTLING:
		return "落脚 · 准备蓄力"
	if not sequence.rebound_pose.is_empty():
		return "刀身回弹 · 收势"
	if sequence.sprint_flashing:
		return "闪进 · 冲刺斩"
	if sequence.sprint_windup >= 0.0:
		return "出刀预备 · 冲刺斩"
	if not sequence.normal_pose.is_empty():
		if sequence.normal_time < sequence.normal_move.WINDUP_END:
			return "出刀预备 · " + sequence.normal_move.DISPLAY_NAME
		if sequence.normal_move == PursuitSweep and sequence.normal_time < PursuitSweep.SECOND_WINDUP:
			return "追击 · 直刺"
		return "普通攻击 · " + sequence.normal_move.DISPLAY_NAME
	if sequence.patrol.active:
		return sequence.patrol.motion_label()
	if sequence.time >= Sequence.RETURN_AT + ReturnCut.TRAIL_START:
		return "第二刀 · 斜落回斩"
	if sequence.time >= Sequence.RETURN_AT:
		return "换重心 · 回斩预备"
	if sequence.time >= Sequence.ATTACK_AT:
		return "闪进斜斩"
	if sequence.time >= Pace.DURATION + Brace.CONTACT_TIME:
		return "低位蓄力 · 核心锁定"
	return "低位撑地"


func _focus() -> Vector3:
	return player.rig.global_position + Vector3.UP * P.getf("cam.first_height")

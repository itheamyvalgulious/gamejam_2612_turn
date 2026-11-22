extends "res://src/game/enemy_base.gd"
## The elite duelist opens with one combo, then switches to melee pursuit.

const Units = preload("res://src/core/units.gd")
const CombatRig = preload("res://src/enemies/duelist/duelist_combat_rig.gd")
const Sequence = preload("res://src/enemies/duelist/duelist_sequence.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Brace = preload("res://src/enemies/duelist/duelist_ground_brace.gd")
const Lunge = preload("res://src/enemies/duelist/duelist_lunge.gd")
const ReturnCut = preload("res://src/enemies/duelist/duelist_return_cut.gd")
const PursuitSweep = preload("res://src/enemies/duelist/duelist_pursuit_sweep.gd")
const MODEL_SCALE := 1.36
const PACE_CENTER := Vector3(0.0, 0.0, 5.60)
const WAKE_RANGE := 20.0 / Units.M_PER_UNIT
const NORMAL_ATTACK_RATE := 2.0

enum Phase { PACING, SETTLING, OPENING, MELEE }

var sequence := Sequence.new()
var phase := Phase.PACING
var _normal_strike := 0


func setup_duelist(p_player: PlayerUnit, cover: Array, bounds := AABB()) -> void:
	player = p_player
	kind = "duelist"
	max_hp = 3.0
	hp = max_hp
	damage = 35.0
	scale_factor = MODEL_SCALE
	rig = CombatRig.new()
	rig.name = "Duelist"
	rig.scale = Vector3.ONE * MODEL_SCALE
	if level != null:
		rig.kerb = level.arena.get("kerb", Vector2(INF, 0.0))
	add_child(rig)
	add_child(sequence)
	sequence.normal_attack_rate = NORMAL_ATTACK_RATE
	sequence.setup(rig, PACE_CENTER, cover, bounds)
	sequence.advance_pacing(0.0, _focus(), false)


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
	return Hit.slide_around_body(start, goal, rig.global_position, radius + 1.1 * scale_factor)


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
	if not alive:
		_dead_t = maxf(0.0, _dead_t - dt)
		if _dead_t <= 0.0:
			hide()
		return
	player = ctx.get("player")
	if not player.alive:
		sequence.sync_audio(true)
		return
	sequence.show()
	match phase:
		Phase.PACING, Phase.SETTLING:
			if phase == Phase.PACING and dist_to_player() <= WAKE_RANGE:
				phase = Phase.SETTLING
			if sequence.advance_pacing(dt, _focus(), phase == Phase.SETTLING):
				phase = Phase.OPENING
		Phase.OPENING:
			_step_opening(dt)
			if sequence.finished:
				phase = Phase.MELEE
		Phase.MELEE:
			_step_normal(dt)
	sequence.advance_guard(dt, _focus())


func _step_opening(dt: float) -> void:
	var before := sequence.time - Sequence.ATTACK_AT
	var previous_end: Vector3 = sequence.dash.get("end", Vector3.INF)
	var previous_aim: float = sequence.dash.get("aim", INF)
	sequence.advance(dt, _focus())
	var after := sequence.time - Sequence.ATTACK_AT
	if before < 0.0 and after >= 0.0:
		swung_serial += 1
	# A long frame can cross the first cut and the handoff. Resolve the first sweep before switching.
	if swung_serial == 1 and before >= Lunge.CUT_END and not sequence.return_pose.is_empty():
		swung_serial += 1
		rig.start_return(sequence.return_pose, after)
	elif after < Lunge.DURATION and not sequence.dash.is_empty():
		var new_end: Vector3 = sequence.dash["end"]
		var new_aim: float = sequence.dash["aim"]
		if not previous_end.is_equal_approx(new_end) or not is_equal_approx(previous_aim, new_aim):
			rig.start_strike(sequence.dash, after)
	rig.update_strike(before, after, dt)
	sequence.sync_audio(sequence.finished)


func _step_normal(dt: float) -> void:
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
		rig.update_strike(before, sequence.normal_time, dt)
	else:
		var end := Lunge.DURATION + ReturnCut.DURATION
		rig.update_strike(end, end, dt)


func hurt(amount: float, normal := Vector3.UP, _knock := 0.0) -> void:
	# Valid off-screen hits can weaken the opening, but cannot cancel the two cuts by killing the duelist.
	if phase == Phase.SETTLING or phase == Phase.OPENING:
		amount = minf(amount, maxf(0.0, hp - 1.0))
	super.hurt(amount, normal, 0.0)


func die() -> void:
	if not alive:
		return
	alive = false
	_dead_t = 0.85
	sequence.sync_audio(true)
	sequence.hide()
	Snd.play_at("death", center(), {"gain": 1.0})
	Fx.death_burst(center())
	if level != null:
		level.on_enemy_died(self)


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

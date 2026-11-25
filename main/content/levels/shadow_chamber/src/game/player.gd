extends Node3D
class_name PlayerUnit
## 玩家：四足机甲 + 武士刀。
##
## 输入映射（全部可在 Esc 面板重绑）：
##   鼠标 = 视角         WASD = 相机相对移动        空格 = 跳       Shift = 冲刺
##   左键 = 攻击（配合 A/D/S 出 左斩/右斩/回身斩，不按 = 正前斩）
##   右键 = 架招：读威胁的轨迹 → 规划一条机械臂路径把刀送到它必经之路上
##          （剑挡剑：免伤 + 被击退；接箭：原路弹回）   Q = 重斩   E = 回旋斩
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const Rig = preload("res://team/vesper/integration/campaign_rig.gd")
# 直接 preload：不依赖全局类缓存，headless / 首次 clone 都能跑
const InterceptS = preload("res://src/game/intercept.gd")
const Units = preload("res://src/core/units.gd")
const IMPACT_SLIDE_TIME := 0.52
const IMPACT_BRACE_TIME := 0.28

var rig
var cam: GameCam
var alive := true
var parry_timer := 0.0        # 剩余弹反窗口
var parry_cd := 0.0
var block_push := Vector3.ZERO   # 格挡成功后被推开的残余速度
var _impact_slide := Vector3.ZERO
var _impact_elapsed := IMPACT_SLIDE_TIME
var last_attack := ""
var pending_hitstop := 0.0
var hurt_flash := 0.0
var swing_serial := 0
var hurt_serial := -1
var last_cause := ""
var hp := 100.0
var invuln := 0.0
var air_jumps := 0
var jump_buffer_dt := 0.0
var coyote_left := 0.0
var _was_in_window := false
var projectiles = null

# 弹反拦截规划的运行状态
var _intercept_on := false
var _intercept_kind := ""
var _plan_point := Vector3.ZERO
var _plan_body_yaw := 0.0
var _plan_left := 0.0
var _plan_idle := 0.0      # 已经多久没看到威胁了（收势的触发条件）
var _return_left := 0.0

var _last_swing_before := Transform3D.IDENTITY
var _swing_prev_xf := Transform3D.IDENTITY
var _swing_cur_xf := Transform3D.IDENTITY


func _ready() -> void:
	rig = Rig.new()
	rig.name = "Mech"
	rig.auto_step = false
	rig.set_process(false)
	rig.scale = Vector3.ONE * Units.to_units(1.0)
	add_child(rig)
	rig.footstep.connect(_on_footstep)
	_sync_params()
	rig.facing_override = true


func set_camera(c: GameCam) -> void:
	cam = c


func _sync_params() -> void:
	rig.jump_vel = P.jump_velocity()
	rig.grav = P.getf("jump.gravity")
	rig.takeoff_time = P.getf("jump.takeoff_time")
	rig.land_time = P.getf("jump.land_time")
	rig.dash_distance = P.getf("dash.distance")
	rig.dash_duration = P.getf("dash.duration")
	rig.dash_cd = P.getf("dash.cooldown")
	rig.accel_rate = P.getf("move.accel")
	rig.decel_rate = P.getf("move.decel")
	rig.air_accel_rate = P.getf("move.air_accel")
	rig.air_decel_rate = P.getf("move.air_decel")
	rig.move_speed = P.getf("move.speed")
	var t := {}
	for id in ["slash_fwd", "slash_left", "slash_right", "slash_back", "heavy", "spin"]:
		t[id] = {
			"duration": P.getf("attack.%s.duration" % id),
			"windup": P.getf("attack.%s.windup" % id),
			"active": P.attack_active(id),
			"recovery": P.getf("attack.%s.recovery" % id),
		}
	rig.set_timings(t)


func step(dt: float, arena: Dictionary, enemies: Array = []) -> void:
	_sync_params()
	if not alive:
		return
	parry_timer = maxf(0.0, parry_timer - dt)
	parry_cd = maxf(0.0, parry_cd - dt)
	hurt_flash = maxf(0.0, hurt_flash - dt)
	invuln = maxf(0.0, invuln - dt)
	jump_buffer_dt = maxf(0.0, jump_buffer_dt - dt)

	var mv := B.move_vector()
	var cam_yaw: float = cam.yaw if cam != null else rig.heading
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var dir := right * mv.x + fwd * (-mv.y)

	var impact_control := smoothstep(IMPACT_BRACE_TIME, IMPACT_SLIDE_TIME, _impact_elapsed)
	# 单一移动速度：没有走/跑/冲刺分层，也没有持续移动自动提速。
	if dir.length() > 0.15:
		rig.move_command = dir.normalized() * P.getf("move.speed") * impact_control
	else:
		rig.move_command = Vector3.ZERO

	# 朝向：相机前方 or 移动方向
	if P.gets("move.facing_mode") == "camera":
		rig.facing_override = true
		rig.facing_heading = cam_yaw
	else:
		rig.facing_override = dir.length() > 0.15

	# ---------------- 输入
	# 跳跃：输入缓冲 + 二段跳 + 落地宽容
	if rig.jump_state == "GROUND":
		air_jumps = 0
		coyote_left = P.getf("jump.coyote_time")
	else:
		coyote_left = maxf(0.0, coyote_left - dt)
	if B.just("jump"):
		jump_buffer_dt = P.getf("jump.buffer_time")
		if P.getb("jump.double_jump") and rig.jump_state == "AIR" and air_jumps < 1:
			air_jumps += 1
			rig.vertical_velocity = P.jump_velocity()
			rig.jump_state = "AIR"
			rig.jump_t = 0.0
			jump_buffer_dt = 0.0
	if jump_buffer_dt > 0.0 and (rig.jump_state == "GROUND"
			or (rig.jump_state == "LANDING" and rig.jump_t <= coyote_left)):
		rig.jump_vel = P.jump_velocity()
		rig.request_jump()
		jump_buffer_dt = 0.0
	if B.just("dash") and _impact_elapsed >= IMPACT_BRACE_TIME:
		rig.request_dash(rig.global_transform.basis.inverse() * dir)
	if B.just("parry"):
		_begin_parry()
	if B.just("attack_light"):
		_attack_from_input(mv)
	if B.just("attack_heavy"):
		_attack("heavy")
	if B.just("attack_spin"):
		_attack("spin")

	# 举刀 / 架招：先把刀规划到威胁的必经之路上（读招 → 落点 → 机械臂过渡）
	# 窗口内一定在规划；窗口过了只要威胁还在、刀还架着，就继续跟着它走。
	if parry_timer > 0.0 or (_intercept_on and _plan_idle < P.getf("parry.pose_time")):
		_return_left = 0.0
		if P.getb("parry.auto_aim"):
			rig.guard = 0.0
			_plan_intercept(dt, enemies)
		else:
			rig.guard = 1.0 if parry_timer > 0.0 else 0.0
	elif _intercept_on:
		# 威胁没了：规划一条收势，把刀平滑地放回自然持刀位
		rig.guard = 0.0
		if _return_left <= 0.0:
			_return_left = maxf(P.getf("parry.pose_time"), 0.08)
			rig.plan_blade_return(_return_left)
		_return_left -= dt
		if _return_left <= 0.0:
			_end_intercept()
	else:
		rig.guard = 0.0
	if P.getf("dash.invuln") > 0.0 and rig.dash_time > 0.0:
		invuln = maxf(invuln, P.getf("dash.invuln"))

	# ---------------- 推进（记录刀的扫掠）
	_last_swing_before = rig.weapon_xf
	rig.advance(dt)
	# 格挡击退：被架住的那一刀把人推开
	if block_push.length_squared() > 0.0001:
		rig.position += block_push * dt
		block_push *= exp(-7.0 * dt)
		if block_push.length() < 0.05:
			block_push = Vector3.ZERO
	step_impact(dt, arena)
	_swing_prev_xf = _last_swing_before
	_swing_cur_xf = rig.weapon_xf

	# 挥剑风声：判定窗口打开的那一帧起风
	var in_win: bool = rig.in_hit_window()
	if in_win and not _was_in_window:
		var heavy: bool = rig.attack_name in ["HEAVY", "SPIN"]
		var blade: Vector3 = rig.weapon_xf * Vector3(0, 1.4, 0)
		Snd.play_at("swing_heavy" if heavy else "swing_light", blade,
			{"gain": 1.0 if heavy else 0.85})
	_was_in_window = in_win
	_clamp_to_arena(arena)


## 弹反拦截规划：找出最紧迫的威胁，把刀按规划好的路径送过去。
##
## 近战走 InterceptS.melee_threat（读敌人这一刀未来几帧的刀位姿），
## 远程走 InterceptS.projectile_threat（箭/刀气直线外推），两者共用同一套落点算法。
func _plan_intercept(dt: float, enemies: Array) -> void:
	var lead := P.getf("parry.plan_lead")
	var margin := P.getf("parry.intercept_margin")
	var best := {}
	# ---- 近战：读它的出剑轨迹
	if P.getb("parry.melee_block"):
		for e in enemies:
			if e == null or not is_instance_valid(e) or not e.alive:
				continue
			var t: Dictionary = InterceptS.melee_threat(self, e, margin)
			if not bool(t.get("ok", false)):
				continue
			if float(t["eta"]) > lead:
				continue
			if best.is_empty() or float(t["eta"]) < float(best["eta"]) - 0.02:
				best = t
	# ---- 远程：箭 / 刀气
	if projectiles != null:
		for it in projectiles.items:
			if not bool(it["alive"]) or String(it["owner"]) != "enemy" or bool(it["spent"]):
				continue
			var t2: Dictionary = InterceptS.projectile_threat(self, it,
				P.getf("parry.radius"), P.getf("parry.plan_speed"), P.getf("parry.arc_deg"))
			if not bool(t2.get("ok", false)):
				continue
			if float(t2["eta"]) > lead:
				continue
			if best.is_empty() or float(t2["eta"]) < float(best["eta"]) - 0.02:
				best = t2
	if best.is_empty():
		_plan_idle += dt
		_plan_left -= dt
		return
	_plan_idle = 0.0
	var point: Vector3 = best["point"]
	var eta: float = float(best["eta"])
	# 躯干在世界里的朝向（机体 + 腰环）：身体还在转的时候，刀要跟着重新规划
	var body_yaw: float = rig.heading + rig.torso.rotation.y
	var turned: float = absf(wrapf(body_yaw - _plan_body_yaw, -PI, PI))
	# 新威胁 / 落点跑掉了 / 身体转过角度了 / 上一条路径已经走完 → 重新规划
	if _intercept_on and _plan_left > 0.0 and _plan_point.distance_to(point) <= 0.22 \
			and turned <= 0.12:
		_plan_left -= dt
		return
	var dur := clampf(eta * 0.9, 0.05, 0.20)
	var res: Dictionary = rig.plan_blade_intercept(point, best["axis"], best["normal"],
		P.getf("parry.torso_turn"), dur, P.getf("parry.plan_speed"))
	if res.is_empty():
		# 规划失败也要保持架着并立刻重试；否则刀停在上一帧的落点，
		# 会眼睁睁看着敌刀从旁边擦过去（_intercept_on 已是 true）。
		_plan_left = 0.0
		return
	_intercept_on = true
	_intercept_kind = String(best["kind"])
	_plan_point = point
	_plan_body_yaw = body_yaw
	_plan_left = float(res.get("dur", dur))


func _end_intercept() -> void:
	_intercept_on = false
	_intercept_kind = ""
	_plan_left = 0.0
	_plan_idle = 999.0
	_return_left = 0.0
	rig.clear_blade_path()


## 格挡成功：免伤，但被这一刀推开
func on_block(push_dir: Vector3, speed: float) -> void:
	if not alive:
		return
	var d := push_dir
	d.y = 0.0
	if d.length_squared() < 0.0001:
		d = -rig.global_transform.basis.z
	block_push = d.normalized() * maxf(speed, 0.0)


func launch_impact(push_dir: Vector3, distance_meters: float) -> void:
	_impact_slide = push_dir.slide(Vector3.UP).normalized() * Units.to_units(distance_meters)
	_impact_elapsed = 0.0
	block_push = Vector3.ZERO
	rig.speed = 0.0
	rig.dash_time = 0.0


func step_impact(dt: float, arena: Dictionary) -> void:
	if _impact_elapsed >= IMPACT_SLIDE_TIME:
		return
	var previous := 1.0 - _impact_elapsed / IMPACT_SLIDE_TIME
	_impact_elapsed = minf(_impact_elapsed + dt, IMPACT_SLIDE_TIME)
	var remaining := 1.0 - _impact_elapsed / IMPACT_SLIDE_TIME
	# Integrate the easing curve so the displacement is the same at different frame rates.
	var from: Vector3 = rig.global_position
	rig.global_position += _impact_slide * (previous * previous * previous - remaining * remaining * remaining)
	_clamp_to_arena(arena)
	rig.weapon_xf = rig.weapon_xf.translated(rig.global_position - from)


func _on_footstep(pos: Vector3, strength: float) -> void:
	Snd.play_at("step", pos, {"gain": 0.30 + 0.25 * clampf(strength, 0.0, 1.5)})


func _clamp_to_arena(arena: Dictionary) -> void:
	if arena.is_empty():
		return
	var b: AABB = arena.get("bounds", AABB())
	if b.size.length() > 0.1:
		var p: Vector3 = rig.position
		p.x = clampf(p.x, b.position.x + 3.0, b.position.x + b.size.x - 3.0)
		p.z = clampf(p.z, b.position.z + 3.0, b.position.z + b.size.z - 3.0)
		p = Hit.resolve_circles(p, 1.1, arena.get("cover", []), p.y)
		rig.position = p


func _begin_parry() -> void:
	if parry_cd > 0.0 or rig.is_attacking:
		return
	parry_timer = P.getf("parry.window")
	parry_cd = P.getf("parry.cooldown") + P.getf("parry.window")
	# 不清 _intercept_on：上一刀可能还架着，刀还在外面就该继续挡
	_plan_left = 0.0
	_return_left = 0.0


## 「正对/侧/背」由按下瞬间按住的 WASD 决定
func _attack_from_input(mv: Vector2) -> void:
	if absf(mv.x) > 0.5 and absf(mv.x) >= absf(mv.y):
		if mv.x < 0.0:
			_attack("slash_left")
		else:
			_attack("slash_right")
	elif mv.y > 0.5:
		_attack("slash_back")
	else:
		_attack("slash_fwd")


func _attack(move_id: String) -> void:
	if not alive or rig.is_attacking:
		return
	rig.play_action(move_id, P.getf("attack.%s.lunge" % move_id))
	last_attack = move_id
	swing_serial += 1


func is_parrying() -> bool:
	return parry_timer > 0.0


## 刀现在是不是「架着的」：规划中 / 等它撞上来 / 收势中（刀还在外面）都算。
## 判定用的是刀的真实几何，所以只要是举着刀这个状态，物理上就该挡得住。
func is_guard_up() -> bool:
	return _intercept_on


## 当前正在架什么（HUD 显示用）：""=没在架，"它的刀"=近战，"飞行物"=远程
func parry_plan_label() -> String:
	if not _intercept_on:
		return ""
	return "它的刀" if _intercept_kind == "melee" else "飞行物"


func parry_progress() -> float:
	var w := maxf(P.getf("parry.window"), 0.001)
	return clampf(1.0 - parry_timer / w, 0.0, 1.0)


func apply_body_collision(position_after_collision: Vector3) -> void:
	var correction: Vector3 = position_after_collision - rig.global_position
	if correction.is_zero_approx():
		return
	rig.global_position = position_after_collision
	rig.weapon_xf = rig.weapon_xf.translated(correction)
	_swing_cur_xf = rig.weapon_xf


func capsule() -> Dictionary:
	return rig.combat_capsule()


func hurt(_amount: float, _from_dir := Vector3.FORWARD, cause := "") -> void:
	if not alive or P.getb("rules.god_mode"):
		return
	if _amount <= 0.0:
		return          # 0 伤害的攻击不该致死（一击必死模式也一样）
	if invuln > 0.0:
		return
	last_cause = cause if cause != "" else "被斩中"
	if not P.getb("rules.one_hit_kill"):
		# 非一击必死：按最大血量比例扣血 + 无敌帧
		var dmg: float = P.getf("rules.hit_damage_scale") * maxf(1.0, P.getf("rules.player_hp"))
		hp = maxf(0.0, hp - dmg)
		invuln = P.getf("rules.invuln_time")
		hurt_flash = 0.2
		if Fx != null:
			Fx.screen_flash(0.22, Color(0.85, 0.08, 0.08))
			Fx.shake(0.6)
		if hp > 0.0:
			return
	alive = false
	rig.move_command = Vector3.ZERO
	Snd.play_at("player_death", rig.global_position + Vector3(0, 2.0, 0))
	if Fx != null:
		Fx.death_burst(rig.global_position + Vector3(0, 2.0, 0))
		Fx.screen_flash(0.55, Color(0.8, 0.05, 0.05))
		Fx.shake(1.2)


func reset(pos: Transform3D) -> void:
	alive = true
	hp = P.getf("rules.player_hp")
	invuln = 0.0
	air_jumps = 0
	jump_buffer_dt = 0.0
	hurt_serial = -1
	swing_serial = 0
	parry_timer = 0.0
	parry_cd = 0.0
	block_push = Vector3.ZERO
	_impact_slide = Vector3.ZERO
	_impact_elapsed = IMPACT_SLIDE_TIME
	last_cause = ""
	_end_intercept()
	rig.reset_demo(pos.origin, pos.basis.get_euler().y)
	rig.facing_override = true
	rig.heading = pos.basis.get_euler().y
	rig.rotation.y = rig.heading
	if cam != null:
		cam.yaw = rig.heading
		cam.pitch = -0.16
		cam.set_first_person(P.gets("cam.mode") == "first")

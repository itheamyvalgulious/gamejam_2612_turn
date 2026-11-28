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
const Units = preload("res://src/core/units.gd")
# 直接 preload：不依赖全局类缓存，headless / 首次 clone 都能跑
const InterceptS = preload("res://src/game/intercept.gd")
const ActiveParry = preload("res://core/active_parry.gd")
const PlayerBladeTerrain = preload("res://core/player_blade_terrain.gd")

var rig
var cam: GameCam
var alive := true
var parry_timer := 0.0        # 剩余弹反窗口
var parry_cd := 0.0
var block_push := Vector3.ZERO   # 格挡成功后被推开的残余速度
var last_attack := ""
var enemies: Array = []
var pending_hitstop := 0.0
var hurt_flash := 0.0
var swing_serial := 0
var hurt_serial := -1
var hurt_serials := {}
var measured_velocity := Vector3.ZERO
var _prev_rig_pos := Vector3.ZERO
var _plan_vel := Vector3.ZERO
var last_cause := ""
var hp := 100.0
var invuln := 0.0
var air_jumps := 0
var jump_buffer_dt := 0.0
var coyote_left := 0.0
var _was_in_window := false
var blade_terrain := PlayerBladeTerrain.new()
var projectiles = null
var _platform_grace := 0.0
var _last_platform := 0.0

# 弹反拦截规划的运行状态
var _intercept_on := false
var _intercept_kind := ""
var _plan_point := Vector3.ZERO
var _plan_body_yaw := 0.0
var _plan_left := 0.0
var _plan_idle := 0.0      # 已经多久没看到威胁了（收势的触发条件）
var _reach_enemy := 0      # 换刀路径搜索的缓存：敌人 instance id
var _reach_serial := -1
var _reach_from := -1.0    # 该刀的判定窗口起点
var _reach_to := -1.0      # 该刀的判定窗口终点
var _reach_alt := {}       # 该刀的可达拦截点（搜一次，全刀复用，空=用原方案）
var _return_left := 0.0
var _lock_key := []        # 锁定迎击签名 [eid, serial, win_from, win_to]
var _lock_P := Vector3.ZERO
var _lock_hilt := Vector3.ZERO
var _lock_axis_w := Vector3.ZERO
var _parry_committed := false
var _parry_hold := 0.0

# 迎击/格挡统计（parry bench + HUD 诊断）：swings=敌人挥刀数、blocks=挡下、
# hits=被打中、strikes=规划出的主动迎击、fallback=退回「架住等它来」次数
var parry_stats := {"swings": 0, "blocks": 0, "hits": 0, "strikes": 0, "fallback": 0}
var _swing_seen := {}
var _last_strike := {}      # 最近一次迎击方案 {P, e, enemy, plan_ms, eta}
var parry_contact := {}     # on_block 接触帧数值（play_bench 定格截图用）

var _last_swing_before := Transform3D.IDENTITY
var _swing_prev_xf := Transform3D.IDENTITY
var _swing_cur_xf := Transform3D.IDENTITY


func _ready() -> void:
	rig = Rig.new()
	rig.name = "Mech"
	rig.auto_step = false
	rig.terrain_blade_enabled = true
	rig.follow_platform_height = true
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


func step(dt: float, arena: Dictionary, p_enemies: Array = []) -> void:
	enemies = p_enemies
	_sync_params()
	if not alive:
		measured_velocity = Vector3.ZERO
		return
	if dt > 0.0001 and _prev_rig_pos != Vector3.ZERO:
		measured_velocity = (rig.global_position - _prev_rig_pos) / dt
	else:
		measured_velocity = Vector3.ZERO
	_prev_rig_pos = rig.global_position
	blade_terrain.begin_player_step(rig)
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

	# 单一移动速度：没有走/跑/冲刺分层，也没有持续移动自动提速。
	if dir.length() > 0.15:
		rig.move_command = dir.normalized() * P.getf("move.speed")
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
	if B.just("dash"):
		# Shift = 沿当前移动输入方向冲刺（含前/后/左/右）；无输入默认朝前
		rig.request_dash(rig.global_transform.basis.inverse() * dir)
	if B.just("parry"):
		_begin_parry()
	if B.just("attack_light"):
		_attack_from_input(mv)
	if B.just("attack_heavy"):
		if rig.is_attacking:
			_interrupt_swing(true)
		else:
			_attack("heavy")
	elif B.just("attack_spin"):
		if rig.is_attacking:
			_interrupt_swing(false)
		else:
			_attack("spin")

	# 举刀 / 架招：单次格挡仅规划一次轨迹、挥出一次刀，不中途反复重算抽搐。
	if _parry_committed:
		rig.guard = 0.0
		var still_running := false
		if rig.strike_active():
			still_running = not rig._swing_path.done
		elif rig.blade_path_active():
			if not rig._blade_path.done:
				still_running = true
			elif _parry_hold > 0.0:
				_parry_hold -= dt
				still_running = true
		if not still_running:
			_parry_committed = false
			_return_left = maxf(P.getf("parry.pose_time"), 0.12)
			rig.plan_blade_return(_return_left)
	elif _return_left > 0.0:
		rig.guard = 0.0
		_return_left -= dt
		if parry_timer > 0.0 and P.getb("parry.auto_aim"):
			_plan_intercept(dt, enemies)
		if _parry_committed:
			_return_left = 0.0
		elif _return_left <= 0.0:
			_end_intercept()
	elif parry_timer > 0.0:
		_return_left = 0.0
		if P.getb("parry.auto_aim"):
			rig.guard = 0.0
			_plan_intercept(dt, enemies)
		else:
			rig.guard = 1.0
	else:
		rig.guard = 0.0
	if P.getf("dash.invuln") > 0.0 and rig.dash_time > 0.0:
		invuln = maxf(invuln, P.getf("dash.invuln"))

	# ---------------- 推进（记录刀的扫掠）
	_last_swing_before = rig.weapon_xf
	var ph := _platform_height(arena)
	if ph > 0.01:
		_last_platform = ph
		_platform_grace = 0.16
		rig.ground_height = ph
	elif _platform_grace > 0.0 and rig.jump_state == "GROUND":
		# 刚走出箱沿：给 0.16s 缓冲，避免“一只脚还在箱上”就被判掉下去
		_platform_grace = maxf(0.0, _platform_grace - dt)
		rig.ground_height = _last_platform
	else:
		_platform_grace = 0.0
		rig.ground_height = 0.0
	rig.advance(dt)
	# 格挡击退：被架住的那一刀把人推开
	if block_push.length_squared() > 0.0001:
		rig.position += block_push * dt
		block_push *= exp(-7.0 * dt)
		if block_push.length() < 0.05:
			block_push = Vector3.ZERO
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
			var serial := int(e.get("swung_serial")) if e.get("swung_serial") != null else -1
			if serial >= 0 and int(_swing_seen.get(e.get_instance_id(), -1)) != serial:
				_swing_seen[e.get_instance_id()] = serial
				parry_stats["swings"] += 1
			var _t0 := Time.get_ticks_usec()
			var t: Dictionary = InterceptS.melee_threat(self, e, margin)
			parry_stats["ms_threat"] = maxf(float(parry_stats.get("ms_threat", 0.0)),
				(Time.get_ticks_usec() - _t0) / 1000.0)
			parry_stats["n_threat"] = int(parry_stats.get("n_threat", 0)) + 1
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
	# 本击签名：一刀只搜一次可达拦截点（连段里每一击窗口不同）。
	# 用 instance id + 判定窗口做键（纯整数比较，零分配）。
	var erig = null
	if String(best["kind"]) == "melee":
		var enemy = best.get("enemy")
		if enemy != null and enemy.has_method("predict_weapon_xf"):
			erig = enemy
		elif enemy != null and enemy.has_method("get"):
			erig = enemy.get("rig")
	var eid := 0
	var cur_serial := -1
	var win_from := -1.0
	var win_to := -1.0
	if erig != null:
		eid = erig.get_instance_id()
		var _enemy_obj = best.get("enemy")
		if _enemy_obj != null and _enemy_obj.get("swung_serial") != null:
			cur_serial = int(_enemy_obj.get("swung_serial"))
		var _wf = erig.get("attack_hit_from")
		var _wt = erig.get("attack_hit_to")
		win_from = float(_wf) if _wf != null else -1.0
		win_to = float(_wt) if _wt != null else -1.0
	# 陈旧方案归因清理：敌刀新一击/挥砍结束很久后 _last_strike 不再有效，
	# 后续格挡应记 kind=fallback 而不是挂在过期方案上。
	if not _last_strike.is_empty() \
			and (eid != 0 and eid != int(_last_strike.get("eid", 0)) \
				or (not rig.strike_active() and Time.get_ticks_msec()
					- int(_last_strike.get("plan_ms", 0)) > 900)):
		_last_strike = {}
	# 换了一击必须重新规划，哪怕接触点位置几乎没变。
	if String(best["kind"]) == "melee" and eid != 0 and _lock_key == [eid, cur_serial, win_from, win_to]:
		return
	var new_strike := eid != 0 and (eid != _reach_enemy or cur_serial != _reach_serial \
		or not is_equal_approx(win_from, _reach_from) or not is_equal_approx(win_to, _reach_to))
	var vel_changed := (measured_velocity - _plan_vel).length() > 1.5
	var urgent_shot := String(best["kind"]) == "shot" and eta < 0.30
	# ================= 主动迎击（近战）=================
	# 单次格挡只规划一次轨迹、挥出一次刀，不中途反复重算。
	if String(best["kind"]) == "melee" and eta <= lead:
		if eta > 0.28 and parry_timer > 0.06:
			return
		rig.set_strike_speed(P.getf("parry.plan_speed"))
		var _f0 := Time.get_ticks_usec()
		var strike: Dictionary = ActiveParry.find(self, best["enemy"], margin,
			P.getf("parry.torso_turn"), P.getf("parry.plan_speed"))
		parry_stats["ms_find"] = maxf(float(parry_stats.get("ms_find", 0.0)),
			(Time.get_ticks_usec() - _f0) / 1000.0)
		if strike.has("contact"):
			var cand_contact: Dictionary = strike["contact"]
			cand_contact["t_need"] = float(strike.get("t_need", 0.0))
			cand_contact["e_sample"] = float(strike.get("e_sample", -1.0))
			var _p0 := Time.get_ticks_usec()
			var res2: Dictionary = rig.plan_strike(cand_contact, strike["e_world"],
				float(strike["eta"]), 0.35, 0.55, strike.get("src"),
				strike.get("b_world", Vector3.ZERO))
			parry_stats["ms_strike"] = maxf(float(parry_stats.get("ms_strike", 0.0)),
				(Time.get_ticks_usec() - _p0) / 1000.0)
			if not res2.is_empty():
				parry_stats["strikes"] += 1
				_last_strike = {"P": strike.get("P", point),
					"e": strike["e_world"], "enemy": best["enemy"],
					"eid": eid,
					"plan_ms": Time.get_ticks_msec(), "eta": float(strike["eta"])}
				var cd: float = cand_contact.get("dist", 0.0)
				if cd > 0.0:
					parry_stats["contact_d"] = parry_stats.get("contact_d", [])
					parry_stats["contact_d"].append(snappedf(cd, 0.01))
				var evd: Dictionary = strike.get("eval", {})
				parry_stats["rej_self"] = int(parry_stats.get("rej_self", 0)) + int(evd.get("self", 0))
				parry_stats["rej_joints"] = int(parry_stats.get("rej_joints", 0)) + int(evd.get("joints", 0))
				parry_stats["rej_reach"] = int(parry_stats.get("rej_reach", 0)) + int(evd.get("reach", 0))
				parry_stats["rej_spin"] = int(parry_stats.get("rej_spin", 0)) + int(evd.get("spin", 0))
				_reach_enemy = eid
				_reach_serial = cur_serial
				_reach_from = win_from
				_reach_to = win_to
				_reach_alt = {}
				_lock_key = [eid, cur_serial, win_from, win_to]
				_lock_P = strike.get("P", point)
				_lock_hilt = cand_contact["hilt"]
				_lock_axis_w = strike.get("axis_w", cand_contact.get("axis_w", Vector3.ZERO))
				_intercept_on = true
				_intercept_kind = "melee"
				_parry_committed = true
				_parry_hold = 0.0
				parry_timer = 0.0
				_plan_point = point
				_plan_body_yaw = body_yaw
				_plan_vel = measured_velocity
				_plan_left = float(res2.get("dur", 0.12))
				parry_stats["_plan_stamp"] = Time.get_ticks_msec()
				return
			# plan_strike 自身失败（世界→局部退化）也走 fallback
			parry_stats["fallback"] += 1
		else:
			var gk := "gate_" + String(strike.get("gate", "?"))
			parry_stats[gk] = int(parry_stats.get(gk, 0)) + 1
			var ev2: Dictionary = strike.get("eval", strike)
			parry_stats["rej_self"] = int(parry_stats.get("rej_self", 0)) + int(ev2.get("self", 0))
			parry_stats["rej_joints"] = int(parry_stats.get("rej_joints", 0)) + int(ev2.get("joints", 0))
			parry_stats["rej_reach"] = int(parry_stats.get("rej_reach", 0)) + int(ev2.get("reach", 0))
			parry_stats["rej_spin"] = int(parry_stats.get("rej_spin", 0)) + int(ev2.get("spin", 0))
			parry_stats["fallback"] += 1
	# 没有可行迎击候选 → 回退到旧的「架住等它来」并在 HUD 标注
	var _fb_kind := "melee_fallback" if String(best["kind"]) == "melee" else ""
	var dur := clampf(eta * 0.9, 0.05, 0.20)
	# 接触点够不到时（突进下劈等差离的招），在敌刀路径上换可达拦截点。
	# 搜索按「敌人 + 第几刀」缓存，一次出刀只搜一次：全帧搜索会拖垮帧率，
	# 而敌刀轨迹（predict 采样表）在整刀内不变，一个解可以一直用到刀走完。
	var plan_point := point
	var plan_axis: Vector3 = best["axis"]
	var plan_eta := eta
	if String(best["kind"]) == "shot":
		var tt: float = P.getf("parry.torso_turn")
		var nrm: Vector3 = best["normal"]
		var best_m := 1e9
		for ang in [0.0, 0.785398, -0.785398]:
			var cand_ax: Vector3 = best["axis"] if ang == 0.0 else (best["axis"] as Vector3).rotated(nrm, ang)
			var m2: float = rig.blade_reach_miss(plan_point, cand_ax, nrm, tt)
			if m2 < best_m:
				best_m = m2
				plan_axis = cand_ax
	# 整条格挡路径墙钟预算：_find_reachable_intercept（8段×件×gap）+
	# plan_blade_intercept（IK）实测可达 140ms，是格挡卡顿主犯。
	var _r0 := Time.get_ticks_usec()
	if rig.has_method("intercept_blade_segment") and eid != 0:
		if new_strike:
			_reach_enemy = eid
			_reach_serial = cur_serial
			_reach_from = win_from
			_reach_to = win_to
			_reach_alt = _find_reachable_intercept(erig, best, P.getf("parry.torso_turn"))
			parry_stats["ms_reach"] = maxf(float(parry_stats.get("ms_reach", 0.0)),
				(Time.get_ticks_usec() - _r0) / 1000.0)
			# 可达点搜索超 6ms 后不再复核/规划：保持现刀（上一帧方案或持刀），
			# 这帧直接 return，后续帧缓存在，零回归。
			if (Time.get_ticks_usec() - _r0) / 1000.0 > 6.0:
				parry_stats["gate_budget_reach"] = int(parry_stats.get("gate_budget_reach", 0)) + 1
		# 每次重规划都复核，缓存也要验：替换点只是「敌刀路径上有静态交点」
		# 远远不够 —— 换到机械臂够不到的点，表现就是格挡手被放到错误位置
		# （横斩举到头顶、上段劈垂到腰），刀明明举了却挡不住。
		if not _reach_alt.is_empty():
			# 只要求「机械臂够得着」：落点是否合适由 _find_reachable_intercept
			# 内部约束（判定窗、敌我之间、离原威胁点的距离）保证。
			var tt: float = P.getf("parry.torso_turn")
			var alt_miss: float = rig.blade_reach_miss(_reach_alt["point"], _reach_alt["axis"],
				best["normal"], tt)
			if alt_miss > 0.32:
				_reach_alt = {}
		# 缓存命中时也要每个重规划都用它，否则路径走完重新规划会退回原落点。
		if not _reach_alt.is_empty():
			plan_point = _reach_alt["point"]
			plan_axis = _reach_alt["axis"]
			plan_eta = float(_reach_alt["eta"])
	var dur2 := clampf(plan_eta * 0.65, 0.015, 0.10) if String(best["kind"]) == "melee" else clampf(plan_eta * 0.9, 0.02, 0.20)
	var _p1 := Time.get_ticks_usec()
	var prefer_ax := _lock_axis_w if not new_strike else Vector3.ZERO
	var res: Dictionary = rig.plan_blade_intercept(plan_point, plan_axis, best["normal"],
		P.getf("parry.torso_turn"), dur2, P.getf("parry.plan_speed"), prefer_ax)
	parry_stats["ms_planb"] = maxf(float(parry_stats.get("ms_planb", 0.0)),
		(Time.get_ticks_usec() - _p1) / 1000.0)
	if (Time.get_ticks_usec() - _p1) / 1000.0 > 6.0:
		parry_stats["gate_budget_planb"] = int(parry_stats.get("gate_budget_planb", 0)) + 1
	if res.is_empty():
		# 规划失败也要保持架着并立刻重试；否则刀停在上一帧的落点，
		# 会眼睁睁看着敌刀从旁边擦过去（_intercept_on 已是 true）。
		_plan_left = 0.0
		return
	_intercept_on = true
	_intercept_kind = _fb_kind if _fb_kind != "" else String(best["kind"])
	_parry_committed = true
	_parry_hold = clampf(plan_eta + 0.16, 0.20, 0.38)
	parry_timer = 0.0
	if eid != 0:
		_lock_key = [eid, cur_serial, win_from, win_to]
	if _lock_axis_w == Vector3.ZERO:
		_lock_axis_w = plan_axis.normalized()
	_plan_point = plan_point
	_plan_body_yaw = body_yaw
	_plan_vel = measured_velocity
	_plan_left = float(res.get("dur", dur2))
	parry_stats["_plan_stamp"] = Time.get_ticks_msec()



## 在敌刀剩余预测路径上找「真碰撞可达」的拦截点（一次出刀算一次）。
##
## 格挡不是把刀架在接触点，而是挥刀砍向敌刀来路把它打歪。所以落点取
## 敌刀扫掠体与机械臂可达域的交集——时刻 × 刀身 disc × 刀轴联合搜索，
## 且只保留「敌刀砍到胶囊之前」的点。返回的候选必须比原落点的预测
## 段距明显更好才采用，否则返回空（调用方保持原方案，零回归）。
func _find_reachable_intercept(erig, best: Dictionary, torso_turn: float, t_start := -1.0) -> Dictionary:
	var _outer0 := Time.get_ticks_usec()
	if erig == null or not erig.has_method("predict_weapon_xf"):
		return {}
	var hit_to: float = float(erig.get("attack_hit_to"))
	# 落点优先落在「判定窗内」：窗外的交叠不算格挡，刀架到窗外经过的
	# 位置，等窗口打开敌刀早已掠过去 → 看起来举刀了却没挡住。
	var hit_from: float = float(erig.get("attack_hit_from"))
	var t_elapsed: float = float(erig.get("attack_elapsed"))
	var t_now := t_start
	if t_now < 0.0:
		var strict := _find_reachable_intercept(erig, best, torso_turn,
			maxf(t_elapsed, hit_from))
		if not strict.is_empty() or hit_from <= t_elapsed + 0.001:
			return strict
		# 递归两遍=预算翻倍；strict 已耗时超 10ms 时不再放宽重搜
		if (Time.get_ticks_usec() - _outer0) / 1000.0 > 10.0:
			return {}
		# 窗内没有可达解（连段窗口极短）时才放宽到「从此刻起」。
		t_now = t_elapsed
	var eproxy: BladeProxy = erig.get("blade_proxy")
	if hit_to <= t_now or eproxy == null or eproxy.pieces.is_empty():
		return {}
	var out_dir: Vector3 = best["normal"]
	# Multi-cilindro del jugador: el contacto se estima contra las piezas
	# reales (requirement #2); la hoja enemiga se mide via BladeProxy (req #1).
	var parts: Array = rig.hit_parts() if rig.has_method("hit_parts") else []
	# 敌刀参与判定的轴区间：有 blade_span() 就用（duelist 的开刀扫掠段），
	# 否则取凸体代理自身的包围区间（arc sentinel）。
	var espan: Vector2 = erig.blade_span() if erig.has_method("blade_span") else eproxy.span
	# 敌刀全程刀位姿缓存 + 部件接触时刻（第一次有刀体碰到任一部件胶囊）。

	const STEPS := 8
	var dl := Time.get_ticks_usec() + 20000   # 全程 20ms 硬顶：超时返回空（保持现刀）
	var e_times: Array = []
	var e_xfs: Array = []
	var e_segs: Array = []
	var e_contact := hit_to
	for i in STEPS + 1:
		if Time.get_ticks_usec() > dl:
			return {}
		var e: float = lerpf(t_now, hit_to, float(i) / float(STEPS))
		var xf: Transform3D = erig.predict_weapon_xf(e)
		e_times.append(e)
		e_xfs.append(xf)
		e_segs.append([xf * Vector3(0.0, espan.x, 0.0), xf * Vector3(0.0, espan.y, 0.0)])
		if i > 0 and e_contact >= hit_to:
			var es0: Vector3 = e_segs[i][0]
			var es1: Vector3 = e_segs[i][1]
			for part: Dictionary in parts:
				if _seg_seg_dist(es0, es1, part["a"], part["b"]) - float(part["r"]) <= 0.25:
					e_contact = e
					break

	if e_contact <= t_now + 0.02:
		return {}
	# 不回归的判据：原方案若静止姿态就能切进敌刀路径（gap≈0），一律不动。
	# 只有原方案静态不相交、而新候选静态真相交（gap≈0）时才替换。
	var orig_gap := _predicted_gap(rig, best["point"], best["axis"], out_dir,
		torso_turn, e_xfs, e_segs, eproxy, espan)
	# 与剑挡剑同口径：凸体表面间隙 ≤ 0.04 才算真正切进敌刀扫掠体。
	const CLASH_GAP := 0.04
	if orig_gap <= CLASH_GAP:
		return {}
	var best_gap := CLASH_GAP
	# 由上到下（时间升序）找第一个可行解就返回：越早拦越安全，也省算力。
	# 落点离胸口超过 ~2.7u（刀柄可达 + 整条刀长）时直接跳过，不做完整求解。
	var chest: Vector3 = rig.global_position + Vector3(0, 2.2, 0)
	# ── 优先：落点不动，只改刀轴 ──
	# 手要留在「敌刀真正威胁身体的位置」，只把刀转成横切来路。这样既挡得住，
	# 又不会出现「横斩把手举到头顶 / 上劈把刀垂到腰」这种明显错误的位置。
	var pick := {}
	var pick_miss := 1e9
	var base_pt: Vector3 = best["point"]
	var base_reach: float = rig.blade_reach_miss(base_pt, best["axis"], out_dir, torso_turn)
	var max_shift: float = 1.80 if base_reach > 0.30 else 0.90
	var base_axes: Array = [best["axis"]]
	if erig.has_method("predict_weapon_xf"):
		var b_ax0: Vector3 = ((e_xfs[0] as Transform3D).basis * Vector3(0, 1, 0)).normalized()
		var p_ax0: Vector3 = b_ax0.cross(out_dir)
		if p_ax0.length_squared() > 0.01:
			base_axes.append(p_ax0.normalized())
	base_axes.append_array([Vector3.UP, Vector3.FORWARD, Vector3.RIGHT])
	for ax0 in base_axes:
		if Time.get_ticks_usec() > dl:
			return {}
		if ax0.length_squared() < 0.01:
			continue
		if _predicted_gap(rig, base_pt, ax0, out_dir, torso_turn, e_xfs, e_segs,
				eproxy, espan) > CLASH_GAP:
			continue
		var m0: float = rig.blade_reach_miss(base_pt, ax0, out_dir, torso_turn)
		if m0 <= 0.32 and m0 < pick_miss:
			pick_miss = m0
			pick = {"point": base_pt, "axis": ax0, "eta": maxf(float(best.get("eta", 0.05)), 0.04)}
	if not pick.is_empty():
		return pick
	pick_miss = 1e9
	const CANDIDATE_RANGE := 2.9
	# 贴脸点不许要：落在身体周围 1.45u 以内的话，刀放过去也来不及、
	# 而且会被身体自身挡住，表现就是「举起来了但没挡住」。
	const MIN_CANDIDATE_GAP := 1.45
	var cand_pts: Array = eproxy.sample_points(0.05)
	var best_cand := {}
	var best_cand_gap := orig_gap
	for i in e_times.size():
		var e: float = e_times[i]
		if e >= e_contact:
			continue
		var xf: Transform3D = e_xfs[i]
		# 凸体顶点抽稀采样：逐帧全枚举会卡顿；抽稀后仍能覆盖整条刀身。
		for pi in range(0, cand_pts.size(), 8):
			if Time.get_ticks_usec() > dl:
				return best_cand
			var pt: Vector3 = xf * (cand_pts[pi] as Vector3)
			var chest_gap := pt.distance_to(chest)
			if chest_gap > CANDIDATE_RANGE or chest_gap < MIN_CANDIDATE_GAP:
				continue
			# 必须在我和敌人之间：跑到敌人身后（或超出敌我距离）的点
			# 看起来就是「手放到错误位置」，而且根本拦不到朝我来的刀。
			var mine_flat: Vector3 = (pt - rig.global_position).slide(Vector3.UP)
			var to_enemy_flat: Vector3 = (erig.global_position - rig.global_position).slide(Vector3.UP)
			if mine_flat.length() > to_enemy_flat.length() - 0.20:
				continue
			# 局部范围约束：原落点本来就够得到时只许微调（手不许乱跑）；
			# 原落点够不到时才放开半径去找真正可达的交点。
			if pt.distance_to(best["point"]) > max_shift:
				continue
			# 刀尖前指 / 横切来路摆前面：这是拦预接触路径最有效的两个姿态
			var daxes: Array = []
			var jab: Vector3 = pt - chest
			if jab.length_squared() > 0.01:
				daxes.append(jab.normalized())
				var step_t: float = minf(e + 0.016, hit_to)
				var xf2: Transform3D = erig.predict_weapon_xf(step_t)
				var motion: Vector3 = xf2 * Vector3(0, 1.2, 0) - xf * Vector3(0, 1.2, 0)
				if motion.length_squared() > 0.0001:
					var chop: Vector3 = motion.normalized().cross(jab.normalized())
					if chop.length_squared() > 0.01:
						daxes.append(chop.normalized())
			daxes.append(best["axis"])
			var b_ax: Vector3 = (xf.basis * Vector3(0, 1, 0)).normalized()
			if jab.length_squared() > 0.01:
				var p_ax: Vector3 = b_ax.cross(jab.normalized())
				if p_ax.length_squared() > 0.01:
					daxes.append(p_ax.normalized())
			if daxes.is_empty():
				daxes.append(Vector3.UP)
			for ax in daxes:
				if Time.get_ticks_usec() > dl:
					return best_cand
				if ax.length_squared() < 0.01:
					continue
				var gap := _predicted_gap(rig, pt, ax, out_dir, torso_turn,
					e_xfs, e_segs, eproxy, espan)
				if gap < best_cand_gap:
					best_cand_gap = gap
					best_cand = {"point": pt, "axis": ax, "eta": clampf(e - t_now, 0.04, 0.20)}
				if gap < best_gap:
					# 兜底路径：沿敌刀路径取最早可达的交点（改刀轴失败的极端情况）
					return best_cand
	return best_cand


## 预测「刀架在该落点后，敌刀全程扫过来」的最小真实间隙。
## 先按刀轴线段距离粗筛（凸体半径上界），过关的候选再用凸体最短距离
## 精确度量——「架在那里都碰不到」才算挡不住，避免线模型把格挡判死。
func _predicted_gap(rig, point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float, e_xfs: Array, e_segs: Array,
		eproxy: BladeProxy, espan: Vector2) -> float:
	var seg: Array = rig.intercept_blade_segment(point, axis, face, torso_turn)
	if seg.is_empty():
		return 1e9
	# 粗筛：刀轴线段最小距离超过包络上界就肯定交不上
	const PRUNE := 0.55
	var min_axis := 1e9
	for k in e_segs.size():
		min_axis = minf(min_axis, _seg_seg_dist(seg[0], seg[1], e_segs[k][0], e_segs[k][1]))
	if min_axis > PRUNE:
		return min_axis
	var res: Dictionary = rig.intercept_blade_xf(point, axis, face, torso_turn)
	if res.is_empty():
		return 1e9
	var wx: Transform3D = res["xf"]
	var own: BladeProxy = rig.blade_proxy
	if own == null or own.pieces.is_empty():
		return min_axis
	var ospan: Vector2 = rig.blade_span()
	var gap := 1e9
	var x_step := 2 if e_xfs.size() > 6 else 1
	for xi in range(0, e_xfs.size(), x_step):
		var g := BladeProxy.closest_gap(wx, own, e_xfs[xi], eproxy, ospan, espan)
		gap = minf(gap, float(g["gap"]))
		if gap <= 0.02:
			break
	return gap


static func _pt_seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return (p - (a + ab * t)).length()


## 两线段最短距离（Ericson, Real-Time Collision Detection）
static func _seg_seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.000001 and e <= 0.000001:
		return r.length()
	if a <= 0.000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 0.000001 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()


func _end_intercept() -> void:
	_intercept_on = false
	_intercept_kind = ""
	_parry_committed = false
	_parry_hold = 0.0
	_plan_left = 0.0
	_plan_idle = 999.0
	_return_left = 0.0
	rig.clear_blade_path()


## 格挡成功：免伤，但被这一刀推开
func on_block(push_dir: Vector3, speed: float) -> void:
	if not alive:
		return
	parry_stats["blocks"] += 1
	if _parry_committed:
		_parry_hold = minf(_parry_hold, 0.06)
	_capture_parry_contact()
	var d := push_dir
	d.y = 0.0
	if d.length_squared() < 0.0001:
		d = -rig.global_transform.basis.z
	block_push = d.normalized() * maxf(speed, 0.0)


## 接触帧数值：我方刀轴 a、敌刀轴 b、出刃向 e、速度 v、以及和预测接触
## 点/时刻的偏差。play_bench 用它定格截图 + 打日志。
func _swing_phase() -> String:
	if not rig.strike_active():
		return "idle"
	return ["approach", "strike", "recover"][rig._swing_path.phase()]


func _capture_parry_contact() -> void:
	var enemy = _last_strike.get("enemy")
	if enemy == null or not is_instance_valid(enemy):
		# fallback/旧路径格挡也记录（kind=fallback，无计划可对照）
		for e in enemies:
			if e != null and is_instance_valid(e) and e.get("alive") \
					and ActiveParry.strike_source(e) != null:
				enemy = e
				break
	if enemy == null or not is_instance_valid(enemy):
		return
	var src = ActiveParry.strike_source(enemy)
	if src == null or not src.has_method("predict_weapon_xf"):
		return
	var a_w: Vector3 = rig.weapon_spin.global_transform.basis.y.normalized()
	var my_span: Vector2 = rig.blade_span()
	var xf_my: Transform3D = rig.weapon_spin.global_transform
	var s0: Vector3 = xf_my * Vector3(0, my_span.x, 0)
	var s1: Vector3 = xf_my * Vector3(0, my_span.y, 0)
	# 敌刀轴优先真值（weapon_spin / _blade_now / weapon_xf），
	# 预测表兜底 —— 与 tracker 同源，量「实际」的 a·b。
	var xf_e := Transform3D.IDENTITY
	var live_spin = src.get("weapon_spin")
	if live_spin != null and is_instance_valid(live_spin):
		xf_e = live_spin.global_transform
	else:
		var live_xf = src.get("_blade_now")
		if live_xf is Transform3D and not live_xf.is_equal_approx(Transform3D.IDENTITY):
			xf_e = live_xf
		elif src.get("weapon_xf") is Transform3D \
				and not src.get("weapon_xf").is_equal_approx(Transform3D.IDENTITY):
			xf_e = src.get("weapon_xf")
		else:
			var v_t = src.get("attack_elapsed")
			if v_t == null:
				return
			xf_e = src.predict_weapon_xf(float(v_t))
	var b_w: Vector3 = (xf_e.basis * Vector3(0, 1, 0)).normalized()
	var es: Vector2 = src.blade_span() if src.has_method("blade_span") else src.get("blade_proxy").span
	var e0: Vector3 = xf_e * Vector3(0, es.x, 0)
	var e1: Vector3 = xf_e * Vector3(0, es.y, 0)
	var near := ActiveParry._seg_seg(s0, s1, e0, e1)
	var P_w: Vector3 = near["c0"]
	var chest: Vector3 = rig.global_position + Vector3(0, 2.2, 0)
	var n_dir: Vector3 = (P_w - chest)
	var v_w: Vector3 = Vector3(_last_strike.get("e", Vector3.ZERO))
	if v_w.length_squared() < 0.01:
		v_w = a_w.cross(b_w)
		if v_w.length_squared() < 0.01:
			v_w = n_dir
	v_w = v_w.normalized()
	var va: Vector3 = v_w.cross(a_w)
	var t_err := (Time.get_ticks_msec() - int(_last_strike.get("plan_ms", 0))) / 1000.0 \
		- float(_last_strike.get("eta", 0.0)) if not _last_strike.is_empty() else 99.0
	var ab := a_w.dot(b_w)
	# 实测刀速：连续两帧 weapon_xf 原点差分（不只是计划值）
	var v_meas := 0.0
	var ve_dot := 0.0
	if _swing_prev_xf != Transform3D.IDENTITY and _swing_cur_xf != Transform3D.IDENTITY:
		var v_vec: Vector3 = (_swing_cur_xf.origin - _swing_prev_xf.origin) \
			/ maxf(get_process_delta_time(), 0.001)
		v_meas = v_vec.length()
		ve_dot = v_vec.dot(v_w)
	var pos_err := P_w.distance_to(_last_strike.get("P", P_w))
	# 归因 = 这次格挡发生时是否有迎击计划在飞（kind=="melee" 只有 strike
	# 计划置位，fallback 是 "melee_fallback"）+ 接触时刻基本吻合。
	# pos_err 只作指标不进 gate：敌刀是长段，两刃实际交点可以合理偏离 P。
	var tracked: bool = rig.strike_active() and _intercept_kind == "melee" \
		and absf(t_err) < 1.0 and not _last_strike.is_empty()
	# 主动迎击有效：|a·b|≤0.25（a⊥b）、e 朝敌（≥0.30）、接触时刻/位置偏差小
	var valid: bool = tracked and absf(ab) <= 0.25 \
		and v_w.dot(n_dir.normalized() if n_dir.length_squared() > 0.001 else Vector3.FORWARD) >= 0.30
	if valid:
		parry_stats["ab_ok"] = int(parry_stats.get("ab_ok", 0)) + 1
		parry_stats["active_valid"] = int(parry_stats.get("active_valid", 0)) + 1
	elif tracked:
		parry_stats["ab_bad"] = int(parry_stats.get("ab_bad", 0)) + 1
		parry_stats["active_invalid"] = int(parry_stats.get("active_invalid", 0)) + 1
	if _last_strike.is_empty():
		parry_stats["blocks_fb"] = int(parry_stats.get("blocks_fb", 0)) + 1
	parry_contact = {
		"seq": parry_stats["blocks"], "tracked": tracked, "valid": valid,
		"kind": "fallback" if _last_strike.is_empty() else "active",
		"phase": _swing_phase(),
		"tk": (rig._swing_path._track_b.is_valid()
			if rig._swing_path != null else false),
		"v_meas": snappedf(v_meas, 0.1),
		"ve_dot": snappedf(ve_dot, 0.1),
		"ab_dot": snappedf(ab, 0.001),
		"en_dot": snappedf(v_w.dot(n_dir.normalized()) if n_dir.length_squared() > 0.001 else 0.0, 0.001),
		"va_deg": snappedf(rad_to_deg(va.angle_to(v_w)), 0.1),
		"v_mag": snappedf(P.getf("parry.plan_speed"), 0.1),
		"pos_err": snappedf(P_w.distance_to(_last_strike.get("P", P_w)), 0.01),
		"t_err": snappedf(t_err, 0.01),
	}


func _on_footstep(pos: Vector3, strength: float) -> void:
	Snd.play_at("step", pos, {"gain": 0.30 + 0.25 * clampf(strength, 0.0, 1.5)})


func _platform_height(arena: Dictionary) -> float:
	var best := 0.0
	# 四足机甲不是质点：中心离台面边缘 0.6 u 以内仍算有支撑（约 0.33 m）
	const SUPPORT_MARGIN := 0.6
	for p in arena.get("platforms", []):
		var c: Vector3 = p["c"]
		var hx: float = float(p["hx"])
		var hz: float = float(p["hz"])
		var top: float = float(p["h"])
		# strict：窄面（栏杆顶这种）用机体中心判定，不加支撑余量
		var mx: float = hx if bool(p.get("strict", false)) else hx + SUPPORT_MARGIN
		var mz: float = hz if bool(p.get("strict", false)) else hz + SUPPORT_MARGIN
		if absf(rig.position.x - c.x) <= mx and absf(rig.position.z - c.z) <= mz:
			if rig.position.y >= top - 0.10 and top >= best:
				best = top
	return best


func _clamp_to_arena(arena: Dictionary) -> void:
	if arena.is_empty():
		return
	# 圆形场地：按半径夹紧（AABB 的四个角会跑到圆外）
	var rc: float = float(arena.get("bounds_circle", 0.0))
	if rc > 0.01:
		var flat := Vector2(rig.position.x, rig.position.z)
		if flat.length() > rc:
			flat = flat.normalized() * rc
			rig.position.x = flat.x
			rig.position.z = flat.y
	# 头顶不能穿出天花板（引擎没有天花板碰撞，这里按机体高度夹一下）
	var ceil_h: float = float(arena.get("ceiling", 0.0))
	if ceil_h > 0.1:
		rig.position.y = minf(rig.position.y, ceil_h - 4.60)
	var b: AABB = arena.get("bounds", AABB())
	if b.size.length() > 0.1:
		var p: Vector3 = rig.position
		p.x = clampf(p.x, b.position.x + 3.0, b.position.x + b.size.x - 3.0)
		p.z = clampf(p.z, b.position.z + 3.0, b.position.z + b.size.z - 3.0)
		p = Hit.resolve_circles(p, 1.1, arena.get("cover", []), p.y)
		rig.position = p


func _begin_parry() -> void:
	if parry_cd > 0.0 or rig.is_attacking or blade_terrain.recovering:
		return
	parry_timer = P.getf("parry.window")
	parry_cd = P.getf("parry.cooldown") + P.getf("parry.window")
	_parry_committed = false
	_parry_hold = 0.0
	_lock_key.clear()
	_plan_left = 0.0
	_return_left = 0.0


## 「正对/侧/背」由按下瞬间按住的 WASD 决定；前向再按敌人位置细分 4 种。
func _attack_from_input(mv: Vector2) -> void:
	if absf(mv.x) > 0.5 and absf(mv.x) >= absf(mv.y):
		if mv.x < 0.0:
			_attack("slash_left")
		else:
			_attack("slash_right")
	elif mv.y > 0.5:
		_attack("slash_back")
	else:
		_attack(_front_attack_id())


## 4 种前向挥砍里选「能打到最近敌人」的那个；都够不到就默认 FRONT_R。
func _front_attack_id() -> String:
	var best: Node = null
	var best_d := 1e9
	for e in enemies:
		if e == null or not e.alive or e.rig == null:
			continue
		var d: float = rig.global_position.distance_to(e.rig.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null or best_d > 4.5:
		return "slash_fwd"
	var target: Vector3 = best.center() if best.has_method("center") \
		else best.rig.global_position + Vector3(0, 1.2, 0)
	var clip: String = rig.pick_front_clip(target, P.getf("attack.slash_fwd.lunge"))
	return "slash_fwd:" + clip


## Q/E 挥剑中强制停下立正；Q 同时破掉最近格挡怪的架刀（无视格挡）。
func _interrupt_swing(break_guard: bool) -> void:
	rig.cancel_attack()
	last_attack = ""
	if not break_guard:
		return
	var best: Node = null
	var best_d := 1e9
	for e in enemies:
		if e == null or not e.alive or e.rig == null:
			continue
		var d: float = rig.global_position.distance_to(e.rig.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best != null and best_d < 4.2 and best.has_method("break_guard"):
		best.break_guard(rig.global_position)


func _attack(move_id: String) -> void:
	if not alive or rig.is_attacking or blade_terrain.recovering:
		return
	# "slash_fwd:CLIP" = 按敌人位置细分出的前向 clip（slash_fwd_xx 系列）
	var clip := ""
	if move_id.begins_with("slash_fwd:"):
		clip = move_id.split(":", true, 1)[1]
		move_id = "slash_fwd"
	if clip != "":
		rig.play_action_clip(move_id, clip, P.getf("attack.%s.lunge" % move_id))
	else:
		rig.play_action(move_id, P.getf("attack.%s.lunge" % move_id))
	last_attack = move_id
	swing_serial += 1


func is_parrying() -> bool:
	return parry_timer > 0.0 or _parry_committed


## 刀现在是不是「架着的」：规划中 / 等它撞上来 / 收势中（刀还在外面）都算。
## 判定用的是刀的真实几何，所以只要是举着刀这个状态，物理上就该挡得住。
func is_guard_up() -> bool:
	# auto_aim 开时看刀是否真的送出去；手动格挡（auto_aim 关）下整个举刀窗口都算。
	return _intercept_on or (parry_timer > 0.0 and not P.getb("parry.auto_aim"))


## 当前正在架什么（HUD 显示用）：""=没在架，"它的刀"=近战，"飞行物"=远程
func parry_plan_label() -> String:
	if not _intercept_on:
		return ""
	if _intercept_kind == "melee_fallback":
		return "它的刀（守）"
	return "它的刀" if _intercept_kind == "melee" else "飞行物"


func parry_progress() -> float:
	var w := maxf(P.getf("parry.window"), 0.001)
	return clampf(1.0 - parry_timer / w, 0.0, 1.0)


## ⚠ Sólo cápsula de contorno para queries gruesas (cámara/distancia).
## Prohibido usarla para daño o bloqueo: eso va por rig.hit_parts()
## (multi-cilindro, requirement #2).
func capsule() -> Dictionary:
	return rig.combat_capsule()


func hurt(_amount: float, _from_dir := Vector3.FORWARD, cause := "") -> void:
	if _amount > 0.0:
		parry_stats["hits"] += 1     # 统计先于无敌：god_mode 也要知道漏了几刀
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
	blade_terrain.reset()
	alive = true
	hp = P.getf("rules.player_hp")
	invuln = 0.0
	air_jumps = 0
	jump_buffer_dt = 0.0
	hurt_serial = -1
	hurt_serials = {}
	measured_velocity = Vector3.ZERO
	_prev_rig_pos = pos.origin
	_plan_vel = Vector3.ZERO
	swing_serial = 0
	parry_stats = {"swings": 0, "blocks": 0, "hits": 0, "strikes": 0, "fallback": 0}
	_swing_seen = {}
	parry_timer = 0.0
	parry_cd = 0.0
	block_push = Vector3.ZERO
	last_cause = ""
	_end_intercept()
	rig.ground_height = 0.0
	rig.reset_demo(pos.origin, pos.basis.get_euler().y)
	rig.facing_override = true
	rig.heading = pos.basis.get_euler().y
	rig.rotation.y = rig.heading
	if cam != null:
		cam.yaw = rig.heading
		cam.pitch = -0.16
		cam.set_first_person(P.gets("cam.mode") == "first")

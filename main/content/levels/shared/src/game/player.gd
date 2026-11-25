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

var rig
var cam: GameCam
var alive := true
var parry_timer := 0.0        # 剩余弹反窗口
var parry_cd := 0.0
var block_push := Vector3.ZERO   # 格挡成功后被推开的残余速度
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
var _platform_grace := 0.0
var _last_platform := 0.0

# 弹反拦截规划的运行状态
var _intercept_on := false
var _intercept_kind := ""
var _plan_point := Vector3.ZERO
var _plan_body_yaw := 0.0
var _plan_left := 0.0
var _plan_idle := 0.0      # 已经多久没看到威胁了（收势的触发条件）
var _fallback_lock := {}     # 锁定的可达域内拦截点（不可达落点的替代方案）
var _return_left := 0.0

var _last_swing_before := Transform3D.IDENTITY
var _swing_prev_xf := Transform3D.IDENTITY
var _swing_cur_xf := Transform3D.IDENTITY


func _ready() -> void:
	rig = Rig.new()
	rig.name = "Mech"
	rig.auto_step = false
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
	var axis: Vector3 = best["axis"]
	var eta: float = float(best["eta"])
	# 接触点可达性检查：敌刀的接触点在机械臂可达域外时（如过顶刺/高劈），
	# 在敌刀剩余预测路径上换可达拦截点——格挡是挥刀砍向敌刀路径把对方
	# 打歪的扫掠动作，刀轴按可达性重选，不再被 threat 轴锁死。
	if rig.has_method("blade_reach_miss"):
		var torso_turn := P.getf("parry.torso_turn")
		var miss: float = rig.blade_reach_miss(point, axis, best["normal"], torso_turn)
		if miss > 0.12:
			# 落点不可达：重扫敌刀路径找可达拦截点。锁定机制带滞后——
			# 已有锁时只有新候选明显更优（分数 < 0.6 倍）才换，避免逐帧
			# 跳变让 blade_path 永远走不到；锁定后刀架住等敌刀扫过来。
			var alt := _reachable_intercept(best, margin, torso_turn)
			if not alt.is_empty():
				var lock_ok := not _fallback_lock.is_empty() \
						and _plan_point.distance_to(_fallback_lock["point"]) <= 0.25
				if not lock_ok or float(alt.get("score", 0.0)) \
						< float(_fallback_lock.get("score", 0.0)) * 0.6:
					point = alt["point"]
					axis = alt["axis"]
					eta = float(alt["eta"])
					_fallback_lock = {"point": point, "axis": axis, "eta": eta,
						"score": float(alt.get("score", 0.0))}
				else:
					point = _fallback_lock["point"]
					axis = _fallback_lock["axis"]
					eta = _fallback_lock["eta"]
		else:
			_fallback_lock = {}
	# 躯干在世界里的朝向（机体 + 腰环）：身体还在转的时候，刀要跟着重新规划
	var body_yaw: float = rig.heading + rig.torso.rotation.y
	var turned: float = absf(wrapf(body_yaw - _plan_body_yaw, -PI, PI))
	# 新威胁 / 落点跑掉了 / 身体转过角度了 / 上一条路径已经走完 → 重新规划
	if _intercept_on and _plan_left > 0.0 and _plan_point.distance_to(point) <= 0.22 \
			and turned <= 0.12:
		_plan_left -= dt
		return
	var dur := clampf(eta * 0.9, 0.05, 0.20)
	var res: Dictionary = rig.plan_blade_intercept(point, axis, best["normal"],
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



## 在敌刀剩余预测路径上找「真碰撞可达」的拦截点。
##
## 原理：格挡不是把刀架在敌刀接触点，而是挥刀砍向敌刀路径把对方打歪。
## 所以落点可以取敌刀扫掠体与机械臂可达域的交集里的任意一点——只要
## 我方刀能赶在敌刀经过那里时到位，就形成真实碰撞。算法：时刻 ×
## 敌刀刀身点 × 我方刀轴联合搜索，按「敌刀到达该点时刻 - 我方到位所需
## 时间」挑最早可行解；全不可达则返回 miss 最小的保底，至少贴近路径。
func _reachable_intercept(best: Dictionary, margin: float, torso_turn: float) -> Dictionary:
	var enemy = best.get("enemy")
	var erig = enemy
	if erig != null and not erig.has_method("predict_weapon_xf"):
		erig = erig.get("rig") if erig.has_method("get") else null
	if erig == null or not erig.has_method("predict_weapon_xf"):
		return {}
	var hit_to: float = float(erig.get("attack_hit_to"))
	var t_now: float = float(erig.get("attack_elapsed"))
	var discs: Array = erig.get("blade_discs")
	var weapon_scale2: float = float(erig.get("weapon_scale"))
	if hit_to <= t_now or discs.is_empty():
		return {}
	# 敌刀真正砍到胶囊的时刻：拦在它「砍到人」之后才到的路径点没意义。
	var cap: Dictionary = capsule()
	var e_contact := hit_to
	var out_dir: Vector3 = best["normal"]
	var espan := _disc_span(discs)
	# 先把敌刀剩余全程的刀身线段缓存下来：格挡刀到位后静止保持，
	# 碰撞发生在敌刀扫到我刀位置的那一刻，所以评分是
	# min over 所有 e' of dist(我方刀段, 敌刀段(e'))。
	const STEPS := 10
	var e_times: Array = []
	var e_segs: Array = []
	for i in STEPS + 1:
		var et: float = lerpf(t_now, hit_to, float(i) / float(STEPS))
		var xft: Transform3D = erig.predict_weapon_xf(et)
		e_times.append(et)
		e_segs.append([xft * Vector3(0.0, espan.x, 0.0),
			xft * Vector3(0.0, espan.y, 0.0)])
	# 胶囊接触时刻：第一个有 disc 圆盘碰到胶囊的时刻（近似）。
	for i in e_times.size():
		var xft: Transform3D = erig.predict_weapon_xf(e_times[i])
		var touched := false
		for d in discs:
			var dp: Vector3 = xft * Vector3(0.0, float(d["y"]), 0.0)
			var rr: float = float(d["r"]) * weapon_scale2 + float(cap["r"])
			if _pt_seg_dist(dp, cap["a"], cap["b"]) <= rr:
				touched = true
				break
		if touched:
			e_contact = e_times[i]
			break
	var my_span: Vector2 = rig.blade_span()
	var _my_p0: Vector3 = rig.weapon_xf * Vector3(0.0, my_span.x, 0.0)
	var _my_p1: Vector3 = rig.weapon_xf * Vector3(0.0, my_span.y, 0.0)
	var fallback := {}
	var fallback_gap := 1e9
	var pick := {}
	var pick_score := 1e9
	for i in STEPS + 1:
		var e: float = e_times[i]
		var xf: Transform3D = erig.predict_weapon_xf(e)
		var axes: Array = [best["axis"], Vector3.UP, Vector3.FORWARD, Vector3.RIGHT]
		axes.append((xf.basis * Vector3(0, 1, 0)).normalized())
		var step_t: float = minf(e + maxf(float(erig.get("last_dt")), 1.0 / 120.0), hit_to)
		var motion: Vector3 = erig.predict_weapon_xf(step_t) * Vector3(0, 1.2, 0) \
			- xf * Vector3(0, 1.2, 0)
		if motion.length_squared() > 0.0001:
			var ax2: Vector3 = motion.normalized().cross(out_dir)
			if ax2.length_squared() > 0.0001:
				axes.append(ax2.normalized())
		for d in discs:
			var y: float = float(d["y"])
			if y < 0.05:
				continue
			# 拦截点取在敌刀刀身 disc 本身：格挡是挥刀砍向敌刀路径的
			# 扫掠动作，落点必须在路径上，不能像接触点那样朝玩家偏移。
			var pt: Vector3 = xf * Vector3(0.0, y, 0.0)
			var axes2: Array = axes.duplicate()
			# 刀尖前指轴：刀沿「胸口→拦截点」方向探出，把整条刀长 1.6u
			# 都叠进探身距离——够到敌刀预接触路径的关键姿态。
			var jab: Vector3 = pt - rig.global_position - Vector3(0, 1.6, 0)
			if jab.length_squared() > 0.01:
				axes2.append(jab.normalized())
			# 横切来路轴：垂直于敌刀运动方向，把刀横在它的来路上削过去。
			if motion.length_squared() > 0.0001:
				var chop: Vector3 = motion.normalized().cross(jab.normalized())
				if chop.length_squared() > 0.01:
					axes2.append(chop.normalized())
			for ax in axes2:
				if ax.length_squared() < 0.01:
					continue
				# 真碰撞分数：规划后我方刀线段 vs 「敌刀扫到该点时刻 e 的
				# 刀线段」的段段距。零分=两把刀在 e 时刻真实相交；我方刀
				# 到位后保持不动，敌刀扫到 e 时必然碰上。
				var seg: Array = rig.intercept_blade_segment(pt, ax, out_dir, torso_turn)
				if seg.is_empty():
					continue
				var e_seg: Array = e_segs[i]
				var gap := _seg_seg_dist(seg[0], seg[1], e_seg[0], e_seg[1])
				if gap < fallback_gap:
					fallback_gap = gap
					fallback = {"point": pt, "axis": ax,
						"eta": maxf(e - t_now, 0.0), "score": gap}
				# 要赶在敌刀到达 e 之前到位才选它；且 e 不能晚于敌刀
				# 砍到胶囊的 e_contact——拦在「已经砍到人」之后的点上
				# 挡不住伤害。
				if e - t_now >= 0.05 and e < e_contact - 0.01 and gap < pick_score:
					pick_score = gap
					pick = {"point": pt, "axis": ax,
						"eta": maxf(e - t_now, 0.0), "score": gap}
	if not pick.is_empty():
		return pick
	return fallback


## 敌刀 discs 的 y 范围 → 刀身线段端点
static func _disc_span(discs: Array) -> Vector2:
	var lo := 1e9
	var hi := -1e9
	for d in discs:
		var y: float = float(d["y"])
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector2(lo, hi)


## 点到线段距离
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
	_fallback_lock = {}
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

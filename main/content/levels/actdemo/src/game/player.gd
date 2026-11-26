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
var enemies: Array = []
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
var _reach_enemy := 0      # 换刀路径搜索的缓存：敌人 instance id
var _reach_from := -1.0    # 该刀的判定窗口起点
var _reach_to := -1.0      # 该刀的判定窗口终点
var _reach_alt := {}       # 该刀的可达拦截点（搜一次，全刀复用，空=用原方案）
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


func step(dt: float, arena: Dictionary, p_enemies: Array = []) -> void:
	enemies = p_enemies
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
		if rig.is_attacking:
			_interrupt_swing(true)
		else:
			_attack("heavy")
	elif B.just("attack_spin"):
		if rig.is_attacking:
			_interrupt_swing(false)
		else:
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
	var win_from := -1.0
	var win_to := -1.0
	if erig != null:
		eid = erig.get_instance_id()
		win_from = float(erig.get("attack_hit_from"))
		win_to = float(erig.get("attack_hit_to"))
	# 换了一击必须重新规划，哪怕接触点位置几乎没变。
	var new_strike := eid != 0 and (eid != _reach_enemy \
		or not is_equal_approx(win_from, _reach_from) or not is_equal_approx(win_to, _reach_to))
	# 新威胁 / 落点跑掉了 / 身体转过角度了 / 上一条路径已经走完 → 重新规划
	if not new_strike and _intercept_on and _plan_left > 0.0 \
			and _plan_point.distance_to(point) <= 0.22 and turned <= 0.12:
		_plan_left -= dt
		return
	var dur := clampf(eta * 0.9, 0.05, 0.20)
	# 接触点够不到时（突进下劈等差离的招），在敌刀路径上换可达拦截点。
	# 搜索按「敌人 + 第几刀」缓存，一次出刀只搜一次：全帧搜索会拖垮帧率，
	# 而敌刀轨迹（predict 采样表）在整刀内不变，一个解可以一直用到刀走完。
	var plan_point := point
	var plan_axis: Vector3 = best["axis"]
	var plan_eta := eta
	if rig.has_method("intercept_blade_segment") and eid != 0:
		if new_strike:
			_reach_enemy = eid
			_reach_from = win_from
			_reach_to = win_to
			_reach_alt = _find_reachable_intercept(erig, best, P.getf("parry.torso_turn"))
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
	var dur2 := clampf(plan_eta * 0.9, 0.05, 0.20)
	var res: Dictionary = rig.plan_blade_intercept(plan_point, plan_axis, best["normal"],
		P.getf("parry.torso_turn"), dur2, P.getf("parry.plan_speed"))
	if res.is_empty():
		# 规划失败也要保持架着并立刻重试；否则刀停在上一帧的落点，
		# 会眼睁睁看着敌刀从旁边擦过去（_intercept_on 已是 true）。
		_plan_left = 0.0
		return
	_intercept_on = true
	_intercept_kind = String(best["kind"])
	_plan_point = plan_point
	_plan_body_yaw = body_yaw
	_plan_left = float(res.get("dur", dur2))



## 在敌刀剩余预测路径上找「真碰撞可达」的拦截点（一次出刀算一次）。
##
## 格挡不是把刀架在接触点，而是挥刀砍向敌刀来路把它打歪。所以落点取
## 敌刀扫掠体与机械臂可达域的交集——时刻 × 刀身 disc × 刀轴联合搜索，
## 且只保留「敌刀砍到胶囊之前」的点。返回的候选必须比原落点的预测
## 段距明显更好才采用，否则返回空（调用方保持原方案，零回归）。
func _find_reachable_intercept(erig, best: Dictionary, torso_turn: float, t_start := -1.0) -> Dictionary:
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
		# 窗内没有可达解（连段窗口极短）时才放宽到「从此刻起」。
		t_now = t_elapsed
	var discs: Array = erig.get("blade_discs")
	var wscale: float = float(erig.get("weapon_scale"))
	if hit_to <= t_now or discs.is_empty():
		return {}
	var out_dir: Vector3 = best["normal"]
	var cap: Dictionary = capsule()
	var espan := _piece_span(discs)
	# 敌刀全程刀段缓存 + 胶囊接触时刻（第一次有 disc 碰到胶囊）。
	const STEPS := 8
	var e_times: Array = []
	var e_segs: Array = []
	var e_contact := hit_to
	for i in STEPS + 1:
		var e: float = lerpf(t_now, hit_to, float(i) / float(STEPS))
		var xf: Transform3D = erig.predict_weapon_xf(e)
		e_times.append(e)
		e_segs.append([xf * Vector3(0.0, espan.x, 0.0), xf * Vector3(0.0, espan.y, 0.0)])
		if i > 0 and e_contact >= hit_to:
			for d in discs:
				var dp: Vector3 = xf * Vector3(0.0, float(d["y"]), 0.0)
				if _pt_seg_dist(dp, cap["a"], cap["b"]) <= float(d["r"]) * wscale + float(cap["r"]):
					e_contact = e
					break
	if e_contact <= t_now + 0.02:
		return {}
	# 不回归的判据：原方案若静止姿态就能切进敌刀路径（gap≈0），一律不动。
	# 只有原方案静态不相交、而新候选静态真相交（gap≈0）时才替换。
	var orig_gap := _predicted_gap(rig, best["point"], best["axis"], out_dir, torso_turn, e_segs, e_times)
	# 与 blade_vs_blade 同口径：刀轴间距 ≤ 双方刀半径和 + slack 就算「切进去了」。
	# 之前用 0.06（几乎要刀轴重合）会把本来挡得住的落点误判成挡不住，
	# 于是把刀换到远处够不到的位置 —— 那就是「手放错位置还挡不住」。
	const CLASH_GAP := 0.30
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
	var base_axes: Array = [best["axis"], Vector3.UP, Vector3.FORWARD, Vector3.RIGHT]
	if erig.has_method("predict_weapon_xf"):
		base_axes.append((erig.predict_weapon_xf(t_now).basis * Vector3(0, 1, 0)).normalized())
	for ax0 in base_axes:
		if ax0.length_squared() < 0.01:
			continue
		if _predicted_gap(rig, base_pt, ax0, out_dir, torso_turn, e_segs, e_times) > CLASH_GAP:
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
	for i in e_times.size():
		var e: float = e_times[i]
		if e >= e_contact:
			continue
		var xf: Transform3D = erig.predict_weapon_xf(e)
		# disc 抽稀采样（每 3 个取 1）：34 个 disc 全枚举会让这一次搜索
		# 变成一帧卡顿；抽稀后仍能覆盖整条刀身，精度足够。
		for di in range(0, discs.size(), 3):
			var y: float = float(discs[di]["y"])
			if y < 0.05:
				continue
			var pt: Vector3 = xf * Vector3(0.0, y, 0.0)
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
			daxes.append((xf.basis * Vector3(0, 1, 0)).normalized())
			daxes.append(Vector3.UP)
			daxes.append(Vector3.FORWARD)
			daxes.append(Vector3.RIGHT)
			for ax in daxes:
				if ax.length_squared() < 0.01:
					continue
				var gap := _predicted_gap(rig, pt, ax, out_dir, torso_turn, e_segs, e_times)
				if gap < best_gap:
					# 兜底路径：沿敌刀路径取最早可达的交点（改刀轴失败的极端情况）
					return {"point": pt, "axis": ax, "eta": clampf(e - t_now, 0.04, 0.20)}
	return {}


## 预测「刀架在该落点后，敌刀全程扫过来」的最小刀段间隙。
## 只算刀最终停在落点上的静止姿态——这是「真碰撞」的保守判据：
## 刀停在那里都碰不到敌刀路径，就肯定挡不住；能碰到（≈0）才是真架住。
func _predicted_gap(rig, point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float, e_segs: Array, _e_times: Array) -> float:
	var seg: Array = rig.intercept_blade_segment(point, axis, face, torso_turn)
	if seg.is_empty():
		return 1e9
	var gap := 1e9
	for k in e_segs.size():
		gap = minf(gap, _seg_seg_dist(seg[0], seg[1], e_segs[k][0], e_segs[k][1]))
	return gap


## 刀身 discs 的 y 范围 → 刀段端点参数
static func _piece_span(discs: Array) -> Vector2:
	var lo := 1e9
	var hi := -1e9
	for d in discs:
		lo = minf(lo, float(d["y"]))
		hi = maxf(hi, float(d["y"]))
	return Vector2(lo, hi)


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
	if not alive or rig.is_attacking:
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
	rig.reset_demo(pos.origin, pos.basis.get_euler().y)
	rig.facing_override = true
	rig.heading = pos.basis.get_euler().y
	rig.rotation.y = rig.heading
	if cam != null:
		cam.yaw = rig.heading
		cam.pitch = -0.16
		cam.set_first_person(P.gets("cam.mode") == "first")

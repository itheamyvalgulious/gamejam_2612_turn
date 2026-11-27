extends RefCounted
## 主动迎击：把敌方这一刀看成一条扫掠线段轨迹，在其上枚举「我方迎击接触」
## 候选，按   可行（不穿模、IK 可达、关节不硬超限）→ 尽量远 → 关节自然度
## 选出最好的一刀。
##
## 与旧路径（InterceptS.melee_threat + rig.plan_blade_intercept）的差别：
## 旧路径把刀静止地「放」在敌刀必经之路上等它来；这里刀在接触瞬间以
##   v = e·speed  的速度横切（e = 我方迎击方向，v ⟂ 我方刀轴 a），
## 主动把敌刀砍歪。几何仍走 BladeProxy 凸体，自穿模判定走
## rig.hit_parts() 的多圆柱体件（requirement #1/#2），不用单胶囊。
##
## 单位：世界单位（u），速度 u/s，弧度制。
const JL = preload("res://core/joint_limits.gd")

const SAMPLES := 10            # 敌刀轨迹采样数
const TRAVERSE := 0.55         # 我方剑穿过接触面后还顺势走出的世界行程
const PRE_TRAVEL := 0.35       # 我方剑在接触前的反向行程（strike 段总长 = 两者和）
const U_OPTIONS := [0.62, 0.40, 0.80]                # 接触点落在我方刀身的比例（刀柄=0）
const E_VARIANTS := [0.0, 0.70, -0.70]               # e 绕敌刀轴 b 的偏转（rad）
const MIN_DIST := 0.48
const OMEGA_INFO := 12.0      # 敌刀轴角速度遥测阈值 rad/s（只计数，不 gate）
const BUDGET_MS := 10.0       # find() 墙钟预算：超时立即退出枚举
const REACH_HARD := 0.24       # IK 不可达硬阈值
const SELF_HIT_SLACK := -0.008 # 扫掠自碰容差：> 该值才算碰（BladeProxy 体胀已含边距）

# 性能遥测：parry_bench 汇总 find() 的调用频率与耗时
static var calls := 0
static var usec_total := 0.0
static var usec_list: Array = []


## 从敌人节点取「这条刀的预测来源」：encounter 本身或它的 rig
## （duelist 是 combat rig，arc sentinel 是 encounter 节点）。
static func strike_source(enemy):
	if enemy == null or not is_instance_valid(enemy):
		return null
	if enemy.has_method("predict_weapon_xf"):
		return enemy
	var rig = enemy.get("rig")
	if rig != null and is_instance_valid(rig) and rig.has_method("predict_weapon_xf"):
		return rig
	return null


## 枚举敌刀轨迹上的全部可行迎击候选，按 可行→距离降序→关节分升序→eta 返回最优。
## 返回 {} = 没有可行候选（调用方回退到「架住等它来」的旧方案）。
static func find(player, enemy, margin: float, torso_turn: float, speed: float) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	calls += 1
	var out := _find_inner(player, enemy, margin, torso_turn, speed)
	var dt_ms := (Time.get_ticks_usec() - t0) / 1000.0
	usec_total += dt_ms
	usec_list.append(snappedf(dt_ms, 0.01))
	return out


static func _find_inner(player, enemy, margin: float, torso_turn: float, speed: float) -> Dictionary:
	var t_deadline := Time.get_ticks_usec() + int(BUDGET_MS * 1000.0)
	var src = strike_source(enemy)
	var rig = player.rig
	if src == null or rig == null:
		return {"gate": "no_src"}
	var eproxy: BladeProxy = src.get("blade_proxy")
	if eproxy == null or eproxy.pieces.is_empty() or not bool(src.get("is_attacking")):
		return {"gate": "idle"}
	# boss 等异构敌人的 attack_* 字段可能缺失：get 返回 null，
	# float(null) 直接抛错 —— 任一缺失就不生成主动迎击。
	var v_elapsed = src.get("attack_elapsed")
	var v_from = src.get("attack_hit_from")
	var v_to = src.get("attack_hit_to")
	if v_elapsed == null or v_from == null or v_to == null:
		return {"gate": "no_window"}
	var t_now: float = float(v_elapsed)
	var hit_from: float = float(v_from)
	var hit_to: float = float(v_to)
	var e_end := minf(hit_to, hit_to)
	if e_end <= t_now + 0.015:
		return {"gate": "late"}
	var parts: Array = rig.hit_parts() if rig.has_method("hit_parts") else []
	if parts.is_empty():
		return {"gate": "no_parts"}
	var espan: Vector2 = src.blade_span() if src.has_method("blade_span") else eproxy.span
	var v_p: Vector3 = Vector3.ZERO
	if player.get("measured_velocity") is Vector3:
		v_p = player.get("measured_velocity")
	var chest: Vector3 = rig.global_position + Vector3(0, 2.2, 0)

	# ---- 沿敌刀轨迹采样 [t_now..e_end]：位姿、刀段、刀轴、运动方向、首触时刻 ----
	var e0: float = maxf(t_now, hit_from - 0.001)
	if e0 >= e_end:
		e0 = t_now
	var times: Array = []
	var xfs: Array = []
	var segs: Array = []
	var e_contact := e_end + 1.0
	var step_dt := 0.0
	for i in SAMPLES + 1:
		var e: float = lerpf(e0, e_end, float(i) / float(SAMPLES))
		var xf: Transform3D = src.predict_weapon_xf(e)
		times.append(e)
		xfs.append(xf)
		var seg := [xf * Vector3(0.0, espan.x, 0.0), xf * Vector3(0.0, espan.y, 0.0)]
		segs.append(seg)
		if i > 0:
			step_dt = e - times[i - 1]
		if e_contact > e_end:
			var p_shift: Vector3 = v_p * maxf(e - t_now, 0.0)
			for part: Dictionary in parts:
				var r := _seg_seg(seg[0], seg[1], (part["a"] as Vector3) + p_shift, (part["b"] as Vector3) + p_shift)
				if float(r["d"]) - float(part["r"]) <= margin * 0.45 + 0.14:
					e_contact = e
					break
	if e_contact <= e0:
		return {"gate": "touching"}
	var n := times.size()

	# ---- 第一遍：枚举 + 廉价过滤（IK 可达 + 关节限位），收集可行候选 ----
	var to_enemy: Vector3 = src.global_position - rig.global_position
	var feas: Array = []
	var c_self := 0
	var c_joints := 0
	var c_reach := 0
	var c_seen := 0
	var c_spin := 0
	var enum_over := false
	for i in range(1, n):
		if Time.get_ticks_usec() > t_deadline:
			enum_over = true
			break
		var e: float = times[i]
		if e >= e_contact:
			break
		var xf: Transform3D = xfs[i]
		var xf_prev: Transform3D = xfs[i - 1]
		var b: Vector3 = (xf.basis * Vector3(0, 1, 0)).normalized()
		var b_prev: Vector3 = (xf_prev.basis * Vector3(0, 1, 0)).normalized()
		# 敌刀轴自转统计（weapon_spin 的刃向滚转 ~10+rad/s 是常态，不做 gate；
		# b 与 e 近平行的退化由 swing_path 的 a_des 跳过 tracking 处理）。
		var omega := acos(clampf(b.dot(b_prev), -1.0, 1.0)) / maxf(step_dt, 1e-4)
		if omega > OMEGA_INFO:
			c_spin += 1
		var m: Vector3 = (xf * Vector3(0, espan.y * 0.66, 0)) \
			- (xf_prev * Vector3(0, espan.y * 0.66, 0))
		# 敌刀轴线段上离身件最近的点 → 接触点 P（解析近似，够规划用）
		var P_raw := _nearest_on_seg(segs[i][0], segs[i][1], parts)
		var P := P_raw - v_p * maxf(e - t_now, 0.0)
		var n_dir := P - chest
		n_dir.y *= 0.55                       # 迎击优先横切；上段劈时自然抬起
		if n_dir.length_squared() < 0.0001:
			continue
		# 方向性走廊：P 必须落在「敌人→我」这条走廊里，不许绕到敌人背后
		# 也不许穿到我身后。
		var ep_flat := Vector3(rig.global_position.x - src.global_position.x,
			0.0, rig.global_position.z - src.global_position.z)
		if ep_flat.length_squared() >= 0.25:
			var t_param: float = Vector3(P_raw.x - src.global_position.x, 0.0,
				P_raw.z - src.global_position.z).dot(ep_flat.normalized())
			if t_param < -0.55 or t_param > ep_flat.length() + 1.1:
				continue
		var dist := P.distance_to(chest)
		if dist < MIN_DIST or dist > 3.65:
			continue
		for ev in E_VARIANTS:
			var e_base := n_dir.normalized().slide(b).normalized()
			if e_base.length_squared() < 0.5:
				continue
			var e_dir: Vector3 = e_base.rotated(b, ev).normalized()
			if e_dir.dot(n_dir.normalized()) < 0.30:
				continue
			var a_dir: Vector3 = b.cross(e_dir).normalized()
			if a_dir.length_squared() < 0.5:
				continue
			for u in U_OPTIONS:
				# 内层墙钟：IK solve 是大头，预算耗尽就停枚举（早候选=接触更早
				# 通常更想要，保留已收集的 feas 继续 pass-2，不算 budget gate）。
				if Time.get_ticks_usec() > t_deadline:
					enum_over = true
					break
				c_seen += 1
				var cand := _try_contact(rig, P, a_dir, b, e_dir, u, torso_turn, dist)
				if cand.is_empty():
					continue
				if cand.get("reject", "") == "joints":
					c_joints += 1
					continue
				if cand.get("reject", "") == "reach":
					c_reach += 1
					continue
				feas.append({"contact": cand, "e_world": e_dir, "P": P,
					"eta": e - t_now, "e_sample": e,
					"m_world": m / maxf(step_dt, 1e-4), "src": src,
					"dist": cand["dist"], "score": cand["joint_score"],
					"miss": float(cand["miss"])})
			if enum_over:
				break
		if enum_over:
			break
	if feas.is_empty():
		return {"gate": "budget" if enum_over else "none",
			"seen": c_seen, "self": c_self,
			"joints": c_joints, "reach": c_reach, "spin": c_spin}
	# 排序：先保必中（miss ≤ 0.10），再距离降序 → 关节分升序 → eta 升序
	feas.sort_custom(func(x, y):
		var xm_ok := float(x["miss"]) <= 0.10
		var ym_ok := float(y["miss"]) <= 0.10
		if xm_ok != ym_ok:
			return xm_ok
		if absf(x["dist"] - y["dist"]) > 0.001:
			return x["dist"] > y["dist"]
		if absf(x["score"] - y["score"]) > 0.001:
			return x["score"] < y["score"]
		return x["eta"] < y["eta"])
	# ---- 第二遍：只在头部候选上跑自碰（解析粗判 + 凸体精验）----
	# 每个候选前先查墙钟：预算耗尽就停，没验过自碰的候选不能选
	# （验过的时间不足以走完本轮队列时 gate=budget 走 fallback）。
	var best := {}
	var gjk_tries := 0
	var checked := 0
	var budget_hit := false
	for c in feas:
		if checked >= 3 and Time.get_ticks_usec() > t_deadline:
			budget_hit = true
			break
		checked += 1
		if _self_sweep_hit(rig, c["contact"], c["e_world"], parts):
			c_self += 1
			continue
		# 真几何复核：解析判定过了的前排候选做凸体距离精验（pose 采样
		# gap_to_capsule，便宜；上限 3 次 + find() 6ms 墙钟兜底）。
		if gjk_tries < 3 and Time.get_ticks_usec() <= t_deadline:
			gjk_tries += 1
			if _self_sweep_hit_gjk(rig, c["contact"], c["e_world"], parts):
				c_self += 1
				continue
		best = c
		break
	if best.is_empty():
		return {"gate": "budget" if budget_hit else "self",
			"seen": c_seen, "self": c_self,
			"joints": c_joints, "reach": c_reach, "spin": c_spin}
	best["eval"] = {"seen": c_seen, "self": c_self, "joints": c_joints,
		"reach": c_reach, "spin": c_spin}
	return best


const BLADE_R_EST := 0.34     # 敌刀刃厚度粗估：扫描阶段的保守外扩


## 敌刀轴线段上离身件并集最近的点（解析近似版 _nearest_on_blade）
static func _nearest_on_seg(s0: Vector3, s1: Vector3, parts: Array) -> Vector3:
	var best_pt := s0
	var best_d := 1e9
	for part: Dictionary in parts:
		var r := _seg_seg(s0, s1, part["a"], part["b"])
		if float(r["d"]) - float(part["r"]) < best_d:
			best_d = float(r["d"]) - float(part["r"])
			best_pt = r["c0"]
	return best_pt


## 两线段最近点（与 player._seg_seg_dist 同源，返回两端最近点）
static func _seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Dictionary:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.000001 and e <= 0.000001:
		return {"d": r.length(), "c0": p1, "c1": p2}
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
	var c0 := p1 + d1 * s
	var c1 := p2 + d2 * t
	return {"d": c0.distance_to(c1), "c0": c0, "c1": c1}


## 评估一个接触位姿：IK 可达 + 不穿模自身 + 关节限位。
## 返回 {hilt,basis,yaw,miss,joint_score,dist,u} 或 {}。
static func _try_contact(rig, P: Vector3, a_dir: Vector3, b_dir: Vector3,
		e_dir: Vector3, u: float, torso_turn: float, dist: float) -> Dictionary:
	# 把「刀身 u 处落在 P」钉在求解器里：u_lock 之后 miss = 刀身 u 处到 P
	# 的真实残差，不再是「离落点最近的那一段刀刃」。
	var span: Vector2 = rig.blade_span()
	var hilt_scale: float = rig.weapon_root.scale.y
	var along_target := (span.x + (span.y - span.x) * u) * hilt_scale
	var res: Dictionary = rig.solve_intercept_debug(P, a_dir, b_dir, torso_turn, along_target)
	if res.is_empty():
		return {}
	if float(res["miss"]) > REACH_HARD:
		return {"reject": "reach"}
	var hilt_w: Vector3 = _hilt_world(rig, res)
	var hilt_y_w: Vector3 = _blade_axis_world(rig, res)
	# ---- 关节自然度 ----
	var joints := _joint_eval(rig, res, u)
	if not bool(joints["hard_ok"]):
		return {"reject": "joints"}
	return {"hilt": res["hilt"], "basis": res["basis"], "yaw": res["yaw"],
		"miss": res["miss"], "joint_score": joints["score"], "dist": dist,
		"violations": joints["violations"], "u": u, "along": float(res["along"]),
		"hilt_w": hilt_w, "axis_w": hilt_y_w}


## 接触解的剑世界变换（weapon_spin 全局系 = 凸体代理判定系）
static func _weapon_xf_world(rig, res: Dictionary) -> Transform3D:
	var target_torso: Transform3D = rig._torso_transform(
		Vector3(rig.torso.rotation.x, float(res["yaw"]), rig.torso.rotation.z))
	return target_torso * Transform3D(res["basis"], res["hilt"]) * rig.weapon_spin.transform


static func _hilt_world(rig, res: Dictionary) -> Vector3:
	var xf := _weapon_xf_world(rig, res)
	return xf.origin


static func _blade_axis_world(rig, res: Dictionary) -> Vector3:
	var xf := _weapon_xf_world(rig, res)
	return (xf.basis * Vector3(0, 1, 0)).normalized()


## strike 段扫掠会不会扫到自己（躯干/头/腿/肩甲；手与前臂握刀件放宽）。
## 用解析 seg-seg 近似：我方刀很薄，身件都是粗圆柱，线段模型加一层
## 刃厚余量足够保守 —— 比逐件 GJK 扫掠便宜约三个数量级。
static func _self_sweep_hit(rig, res: Dictionary, e_dir: Vector3, parts: Array) -> bool:
	var xf_c := _weapon_xf_world(rig, res)
	var span: Vector2 = rig.blade_span()
	var s0: Vector3 = xf_c * Vector3(0.0, span.x, 0.0)
	var s1: Vector3 = xf_c * Vector3(0.0, span.y, 0.0)
	var pre := -e_dir * PRE_TRAVEL
	var post := e_dir * TRAVERSE
	for p: Dictionary in parts:
		var label := String(p.get("label", ""))
		if label in ["upper_arm", "forearm", "hand", "finger"]:
			continue
		var pa: Vector3 = p["a"]
		var pb: Vector3 = p["b"]
		var pr: float = float(p["r"]) + SELF_BLADE_R
		# 采样 5 个位姿（pre 起 — post 止）的刀段与身件最近距
		for k in 5:
			var off: Vector3 = pre + (post - pre) * (float(k) / 4.0)
			var r := _seg_seg(s0 + off, s1 + off, pa, pb)
			if float(r["d"]) <= pr - SELF_HIT_CLEAR:
				return true
	return false


const SELF_BLADE_R := 0.10    # 我方刃厚粗估（叠在身件半径上的余量）
const SELF_HIT_CLEAR := 0.06  # 自碰判定的安全空隙：小于它也算擦到


## 真几何自碰复核：沿 pre→post 扫掠采样 2 个位姿，对每个位姿跑
## gap_to_capsule（凸体刀件 vs 身件胶囊的真实最近距，非线段近似）。
## 只精验 AABB 离扫掠盒最近的 4 件 —— 比 sweep_capsule_parts 整段扫掠
## 便宜一个数量级；每 replan 最多 2 次，且有 find() 墙钟预算兜底。
static func _self_sweep_hit_gjk(rig, res: Dictionary, e_dir: Vector3, parts: Array) -> bool:
	if rig.blade_proxy == null:
		return false
	var xf_c := _weapon_xf_world(rig, res)
	var span: Vector2 = rig.blade_span()
	var sw_lo: Vector3 = xf_c * Vector3(0.0, span.x, 0.0)
	var sw_hi: Vector3 = xf_c * Vector3(0.0, span.y, 0.0)
	var pre_v: Vector3 = -e_dir * PRE_TRAVEL
	var post_v: Vector3 = e_dir * TRAVERSE
	var blo: Vector3 = sw_lo.min(sw_hi).min(sw_lo + pre_v).min(sw_hi + pre_v) \
		.min(sw_lo + post_v).min(sw_hi + post_v) - Vector3.ONE * GJK_SLACK
	var bhi: Vector3 = sw_lo.max(sw_hi).max(sw_lo + pre_v).max(sw_hi + pre_v) \
		.max(sw_lo + post_v).max(sw_hi + post_v) + Vector3.ONE * GJK_SLACK
	var body_parts: Array = []
	for p: Dictionary in parts:
		var label := String(p.get("label", ""))
		if label in ["upper_arm", "forearm", "hand", "finger"]:
			continue
		var pa: Vector3 = p["a"]
		var pb: Vector3 = p["b"]
		var pr: float = float(p["r"])
		if minf(pa.x, pb.x) - pr > bhi.x or maxf(pa.x, pb.x) + pr < blo.x:
			continue
		if minf(pa.y, pb.y) - pr > bhi.y or maxf(pa.y, pb.y) + pr < blo.y:
			continue
		if minf(pa.z, pb.z) - pr > bhi.z or maxf(pa.z, pb.z) + pr < blo.z:
			continue
		body_parts.append(p)
	if body_parts.is_empty():
		return false
	var bxc: Vector3 = (blo + bhi) * 0.5
	body_parts.sort_custom(func(x, y):
		var cx: Vector3 = (x["a"] + x["b"]) * 0.5
		var cy: Vector3 = (y["a"] + y["b"]) * 0.5
		return cx.distance_squared_to(bxc) < cy.distance_squared_to(bxc))
	if body_parts.size() > 4:
		body_parts.resize(4)
	for k in 2:
		var off: Vector3 = pre_v + (post_v - pre_v) * (float(k) / 1.0)
		var xf_k := Transform3D(xf_c.basis, xf_c.origin + off)
		for p: Dictionary in body_parts:
			var g: Dictionary = BladeProxy.gap_to_capsule(xf_k, rig.blade_proxy,
				p["a"], p["b"], float(p["r"]))
			if float(g["gap"]) <= GJK_SLACK:
				return true
	return false


const GJK_SLACK := 0.03      # 凸体表面间距 < 3cm 即视为会擦到（宁紧勿松）
const INF_V2_G := Vector2(-INF, INF)


## 复制 mech_rig._solve_arm 的解析逆解（不写节点），算出关节角供限位评估。
## 返回 [{dir, elbow, fore_dir, hilt_y}]（全部躯干局部）。
static func _joint_eval(rig, res: Dictionary, _u: float) -> Dictionary:
	var root_basis: Basis = res["basis"]
	var hilt_pos: Vector3 = res["hilt"]
	# 刀柄轴 = weapon_root 的局部 Y（剑刃轴包含 weapon_spin 的扭转补偿，
	# 握点按 root 轴 ±GRIP 取，与 _update_arms 一致）。
	var hilt_y: Vector3 = (root_basis * Vector3(0, 1, 0)).normalized()
	var grip: float = rig.GRIP
	var yaw: float = res["yaw"]
	var score := 0.0
	var hard := true
	var viols: Array = []
	for i in rig.arms.size():
		var arm: Dictionary = rig.arms[i]
		# 异构 rig 的 arm 字段可能缺失 —— 缺关键字段就跳过该臂评估
		var sh_node = arm.get("shoulder")
		var v_side = arm.get("side")
		var v_upper = arm.get("upper")
		var v_fore = arm.get("fore")
		if sh_node == null or v_side == null or v_upper == null or v_fore == null:
			continue
		var g: Vector3 = hilt_pos + hilt_y * (grip if i == 1 else -grip)
		var S: Vector3 = (sh_node as Node3D).position
		var d: Vector3 = g - S
		var upper: float = float(v_upper)
		var fore: float = float(v_fore)
		var side_f: float = float(v_side)
		var dist := clampf(d.length(), 0.10, upper + fore - 0.006)
		var dir: Vector3 = d.normalized()
		# 肘角：上臂方向 dir、肘在 dir 法平面内 —— 直接复用 _solve_arm 的余弦解
		var a: float = (upper * upper - fore * fore + dist * dist) / (2.0 * dist)
		var h: float = sqrt(maxf(upper * upper - a * a, 0.0))
		var pole: Vector3 = (Vector3(0.95, -0.85, -0.25) if side_f > 0.0
			else Vector3(-0.95, -0.55, -0.30))
		var perp: Vector3 = pole - dir * pole.dot(dir)
		if perp.length_squared() < 0.001:
			perp = Vector3(side_f, 0, 0)
		perp = perp.normalized()
		var elbow_pos: Vector3 = S + dir * a + perp * h
		var up_dir: Vector3 = (elbow_pos - S).normalized()
		var fore_dir: Vector3 = (S + dir * dist - elbow_pos).normalized()
		var elbow_ang := acos(clampf(up_dir.dot(fore_dir), -1.0, 1.0))
		var sh := JL.shoulder(dir)
		var el := JL.elbow(elbow_ang)
		var wr := JL.wrist(fore_dir, hilt_y)
		if not (bool(sh["hard_ok"]) and bool(el["hard_ok"]) and bool(wr["hard_ok"])):
			hard = false
			if not bool(sh["hard_ok"]):
				viols.append("shoulder%d" % i)
			if not bool(el["hard_ok"]):
				viols.append("elbow%d" % i)
			if not bool(wr["hard_ok"]):
				viols.append("wrist%d" % i)
		score += float(sh["over"]) * 1.4 + float(el["over"]) * 0.9 + float(wr["over"]) * 0.8
	var t := JL.torso(yaw, rig.torso.rotation.x, rig.torso.rotation.z)
	if not bool(t["hard_ok"]):
		hard = false
		viols.append("torso")
	score += float(t["over"]) * 0.7
	return {"hard_ok": hard, "score": score, "violations": viols}


## 敌刀位姿 xf 下离我方身件最近的敌刀表面点（与 intercept.gd 同口径，
## 但这里只需要 blade_pt，不需要体侧最近点）。
static func _nearest_on_blade(xf: Transform3D, src, parts: Array) -> Dictionary:
	var best := {"gap": 1e9, "blade_pt": xf.origin}
	var proxy: BladeProxy = src.get("blade_proxy")
	if proxy == null or proxy.pieces.is_empty():
		return best
	var span := Vector2(0.2, INF)
	for part: Dictionary in parts:
		var res: Dictionary = BladeProxy.gap_to_capsule(xf, proxy,
			part["a"], part["b"], float(part["r"]), span)
		if float(res["gap"]) < float(best["gap"]):
			best = {"gap": float(res["gap"]), "blade_pt": res["blade_pt"]}
	return best

extends RefCounted
class_name Intercept

const ActiveParry = preload("res://core/active_parry.gd")
## 兵器拦截规划：读威胁的轨迹 → 决定「刀该压住哪个点、刀轴朝哪」。
##
## 两类威胁共用一套输出（全部世界坐标）：
##   point  = 刀身要压住的落点（在机体胶囊之外，也就是敌人还没打到你身上）
##   axis   = 刀轴方向（横在威胁的来路上）
##   normal = 威胁来的方向（刀面朝它）
##   eta    = 还有多久到（秒）
##
## 近战：敌人这一刀的姿势是闭式动画，能直接解出未来任意时刻刀在哪
##       （mech_rig.predict_weapon_xf），所以是「读招」，不是猜。
## 远程：箭/刀气是直线飞行，用速度外推即可。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

## 拦截落点尽量落在刀身的这个比例处（0 = 护手，1 = 刀尖），够不着时沿刀轴滑动
const COVER := 0.62


## 近战：这一刀什么时候会碰到我、碰到哪 → 拦截点/刀轴
static func melee_threat(player, enemy, margin: float) -> Dictionary:
	if player == null or enemy == null or not player.alive or not enemy.alive:
		return {"ok": false}
	if enemy.has_method("melee_threat"):
		return enemy.melee_threat(player, margin)
	var rig = enemy.rig
	var prig = player.rig
	if rig == null or prig == null or not rig.is_attacking:
		return {"ok": false}
	if rig.blade_proxy == null or rig.blade_proxy.pieces.is_empty():
		return {"ok": false}
	var t_now: float = rig.attack_elapsed
	var t_end: float = rig.attack_hit_to
	if t_now > t_end:
		return {"ok": false}
	# Multi-cilindro del jugador: el arco de amenaza se evalúa contra cada
	# pieza real (requirement #2), no contra una sola capsulota.
	var parts: Array = player.rig.hit_parts() if player.rig != null \
		and player.rig.has_method("hit_parts") else []
	# 在剩余判定窗口里往前扫：刀最早什么时候进到「身上 + margin」以内
	var e0: float = maxf(t_now, rig.attack_hit_from)
	var n := 8
	var lo := -1.0
	var hi := -1.0
	var prev := e0
	# 全程 6ms 墙钟：每次 nearest_on_blade 前查；超时按「已算出的最好」
	# 早退（扫描中断=取已扫到的最近边界），防 margin 边沿 GJK 爆迭代。
	var dl := Time.get_ticks_usec() + 6000
	var pr_hit := margin + 0.6
	for i in n + 1:
		if Time.get_ticks_usec() > dl:
			break
		var e: float = lerpf(e0, t_end, float(i) / float(n))
		var near: Dictionary = nearest_on_blade(rig.predict_weapon_xf(e), rig, parts, pr_hit)
		if float(near["gap"]) <= margin:
			lo = prev
			hi = e
			break
		prev = e
	if lo < 0.0:
		return {"ok": false}          # 这一刀根本够不到我 → 不用架
	# 二分细化「第一次进入 margin」的时刻：落点才不会在帧间跳来跳去
	for i in 4:
		if Time.get_ticks_usec() > dl:
			break
		var mid: float = (lo + hi) * 0.5
		var nm: Dictionary = nearest_on_blade(rig.predict_weapon_xf(mid), rig, parts, pr_hit)
		if float(nm["gap"]) <= margin:
			hi = mid
		else:
			lo = mid
	var e_hit := hi
	# 迎击时刻：不要等敌刀贴到身上才架。e_hit 那一刻敌刀离身体只剩 margin，
	# 落点会落到「贴脸死角」——刀放过去也来不及、也挡不住。
	# 往敌刀来路上提前到「还差 lead_gap」的位置迎上去。
	var e_meet := e_hit
	var lead_gap: float = clampf(0.85 + 0.30 * rig.weapon_scale, margin + 0.12, 1.8)
	if lead_gap > margin + 0.02:
		var lo2 := e0
		var pr_lead := lead_gap + 0.6
		for i2 in n + 1:
			if Time.get_ticks_usec() > dl:
				break
			var e2: float = lerpf(e0, e_hit, float(i2) / float(n))
			var nm2: Dictionary = nearest_on_blade(rig.predict_weapon_xf(e2), rig, parts, pr_lead)
			if float(nm2["gap"]) <= lead_gap:
				var l2 := lo2
				var h2 := e2
				for k in 4:
					if Time.get_ticks_usec() > dl:
						break
					var m2: float = (l2 + h2) * 0.5
					var n3: Dictionary = nearest_on_blade(rig.predict_weapon_xf(m2), rig, parts, pr_lead)
					if float(n3["gap"]) <= lead_gap:
						h2 = m2
					else:
						l2 = m2
				e_meet = h2
				break
			lo2 = e2
	var near: Dictionary = nearest_on_blade(rig.predict_weapon_xf(e_meet), rig, parts)
	var blade_pt: Vector3 = near["blade_pt"]
	var body_pt: Vector3 = near["body_pt"]
	var y: float = near["y"]
	var out_dir: Vector3 = blade_pt - body_pt
	# 上段劈 / 下段扫的来向主要在竖直方向：压太多会把落点摊到侧面，
	# 刀架在头旁边、劈下来的刀从头顶过去 —— 看起来举刀了却没挡住。
	out_dir.y *= 0.85
	if out_dir.length_squared() < 0.0001:
		out_dir = blade_pt - (prig.global_position + Vector3(0, 2.2, 0))
	if out_dir.length_squared() < 0.0001:
		out_dir = -prig.global_transform.basis.z
	out_dir = out_dir.normalized()
	# 落点必须压住敌刀本身：从「敌刀接触点」往「离我方向」退一点，
	# 而不是从我方表面往外让 —— 后者在敌刀间隙(gap)>0 时把刀架在敌刀后面，
	# 会出现「刀举上去了、也在路径上，但没挡住」的漏判。
	var rr: float = 0.24 * rig.weapon_scale + 0.14
	var ip: Vector3 = blade_pt - out_dir * clampf(rr, 0.05, margin)
	# 那一刻敌人的刀在往哪走 → 刀轴横在它前面
	var step := maxf(rig.last_dt, 1.0 / 120.0)
	var p0: Vector3 = rig.predict_weapon_xf(e_meet) * Vector3(0.0, y, 0.0)
	var p1: Vector3 = rig.predict_weapon_xf(e_meet + step) * Vector3(0.0, y, 0.0)
	return _finish(ip, p1 - p0, out_dir, e_meet - t_now, "melee", enemy)


## 远程：飞行物下一步会飞到哪 → 拦截点/刀轴（计入玩家 3D 速度）
static func projectile_threat(player, it: Dictionary, reach: float, blade_speed: float,
		arc_deg := 160.0) -> Dictionary:
	if player == null or not player.alive:
		return {"ok": false}
	var pos: Vector3 = it["pos"]
	var vel: Vector3 = it["vel"]
	var v_p := Vector3.ZERO
	if player.get("measured_velocity") is Vector3:
		v_p = player.get("measured_velocity")
	var v_rel: Vector3 = vel - v_p
	var sp_rel := v_rel.length()
	if sp_rel < 0.2:
		return {"ok": false}
	var chest: Vector3 = player.rig.global_position + Vector3(0, 2.2, 0)
	var r0 := pos - chest
	var dist := r0.length()
	if dist < 0.2 or dist > maxf(reach, sp_rel * 0.45):
		return {"ok": false}
	var vdir := v_rel / sp_rel
	var closing := -vdir.dot(r0.normalized())
	if closing < cos(deg_to_rad(clampf(arc_deg, 30.0, 360.0)) * 0.5):
		return {"ok": false}
	var t_cpa := clampf(-r0.dot(v_rel) / (sp_rel * sp_rel), 0.0, 2.0)
	var miss_cpa := (r0 + v_rel * t_cpa).length()
	if miss_cpa > 2.4:
		return {"ok": false}
	var d_target := clampf(dist - 0.9, 1.35, minf(reach, 2.4))
	var bq := r0.dot(vdir)
	var cq := dist * dist - d_target * d_target
	var disc := bq * bq - cq
	var s := 0.0
	if dist <= d_target:
		s = t_cpa * sp_rel
	elif disc >= 0.0:
		s = maxf(-bq - sqrt(disc), 0.0)
	else:
		s = maxf(-bq, 0.0)
	var t_hit := s / sp_rel
	# 关键：plan_blade_intercept 立刻把 point 转成当前躯干局部坐标，而击中时玩家移动了 v_p * t_hit，
	# 所以传入的目标点必须是 chest + r0 + v_rel * t_hit（等价于 pos + v_rel * t_hit）。
	var ip := pos + v_rel * t_hit
	var od := ip - chest
	if od.length() > reach:
		od = od.normalized() * reach
		ip = chest + od
		t_hit = maxf((ip - pos).dot(vdir) / sp_rel, 0.0)
	var out_dir: Vector3 = od.normalized() if od.length_squared() > 0.0001 else r0.normalized()
	return _finish(ip, v_rel, out_dir, t_hit, "shot", null)


## 机体多段胶囊（parts: [{a,b,r,...}]）离敌人刀身最近的那一对点（凸体代理版）
## Blade geometry goes through BladeProxy; the defender body is the
## multi-cylinder set from hit_parts() — never a single fat capsule.
static func nearest_on_blade(xf: Transform3D, rig, parts: Array, prune := 1e9, shift := Vector3.ZERO) -> Dictionary:
	var best := {"gap": 1e9, "blade_pt": xf.origin, "body_pt": xf.origin, "y": 1.2}
	var proxy: BladeProxy = rig.blade_proxy
	if proxy == null or proxy.pieces.is_empty():
		return best
	var espan: Vector2 = rig.blade_span() if rig.has_method("blade_span") else proxy.span
	var y_lo: float = maxf(espan.x, 0.2)
	var y_hi: float = maxf(espan.y, y_lo + 0.1)
	var s0: Vector3 = xf * Vector3(0.0, y_lo, 0.0)
	var s1: Vector3 = xf * Vector3(0.0, y_hi, 0.0)
	var ws: Variant = rig.get("weapon_scale")
	var blade_r := 0.24 * (float(ws) if ws != null else 1.0)
	for part: Dictionary in parts:
		var pa: Vector3 = (part["a"] as Vector3) + shift
		var pb: Vector3 = (part["b"] as Vector3) + shift
		var pr: float = float(part["r"])
		var r2 := ActiveParry._seg_seg(s0, s1, pa, pb)
		var gap := float(r2["d"]) - pr - blade_r
		if gap < float(best["gap"]):
			var bp: Vector3 = r2["c0"]
			var q: Vector3 = r2["c1"]
			var dir := bp - q
			var surf := q + (dir.normalized() * pr if dir.length_squared() > 0.0001 else Vector3.ZERO)
			var y_val := lerpf(y_lo, y_hi, clampf((bp - s0).length() / maxf((s1 - s0).length(), 1e-4), 0.0, 1.0))
			best = {"gap": gap, "blade_pt": bp, "body_pt": surf, "y": y_val}
	return best



## 收尾：由威胁的运动方向 + 来向决定刀轴与刀面
static func _finish(point: Vector3, motion: Vector3, out_dir: Vector3, eta: float,
		kind: String, enemy) -> Dictionary:
	var axis: Vector3 = motion.cross(out_dir)
	if axis.length_squared() < 0.05:
		# 直刺/刀气正对着来：刀轴横向展开即可（垂直威胁来向）
		axis = out_dir.cross(Vector3.UP)
		if axis.length_squared() < 0.05:
			axis = Vector3.RIGHT
	return {"ok": true, "point": point, "axis": axis.normalized(), "normal": out_dir.normalized(),
		"eta": maxf(eta, 0.0), "kind": kind, "enemy": enemy}

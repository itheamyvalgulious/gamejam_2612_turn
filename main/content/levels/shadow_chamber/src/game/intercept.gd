extends RefCounted
class_name Intercept
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
	if rig.blade_discs.is_empty():
		return {"ok": false}
	var t_now: float = rig.attack_elapsed
	var t_end: float = rig.attack_hit_to
	if t_now > t_end:
		return {"ok": false}
	var cap: Dictionary = player.capsule()
	var a: Vector3 = cap["a"]
	var b: Vector3 = cap["b"]
	var r: float = cap["r"]
	# 在剩余判定窗口里往前扫：刀最早什么时候进到「身上 + margin」以内
	var e0: float = maxf(t_now, rig.attack_hit_from)
	var n := 8
	var lo := -1.0
	var hi := -1.0
	var prev := e0
	for i in n + 1:
		var e: float = lerpf(e0, t_end, float(i) / float(n))
		var near: Dictionary = nearest_on_blade(rig.predict_weapon_xf(e), rig, a, b, r)
		if float(near["gap"]) <= margin:
			lo = prev
			hi = e
			break
		prev = e
	if lo < 0.0:
		return {"ok": false}          # 这一刀根本够不到我 → 不用架
	# 二分细化「第一次进入 margin」的时刻：落点才不会在帧间跳来跳去
	for i in 4:
		var mid: float = (lo + hi) * 0.5
		var nm: Dictionary = nearest_on_blade(rig.predict_weapon_xf(mid), rig, a, b, r)
		if float(nm["gap"]) <= margin:
			hi = mid
		else:
			lo = mid
	var e_hit := hi
	var near: Dictionary = nearest_on_blade(rig.predict_weapon_xf(e_hit), rig, a, b, r)
	var blade_pt: Vector3 = near["blade_pt"]
	var body_pt: Vector3 = near["body_pt"]
	var y: float = near["y"]
	var out_dir: Vector3 = blade_pt - body_pt
	out_dir.y *= 0.45                      # 别为了架头顶/脚下的刀把机体拧断
	if out_dir.length_squared() < 0.0001:
		out_dir = blade_pt - (prig.global_position + Vector3(0, 2.2, 0))
	if out_dir.length_squared() < 0.0001:
		out_dir = -prig.global_transform.basis.z
	out_dir = out_dir.normalized()
	# 落点：机体表面再往外让一点 —— 敌人还没打到我
	var ip: Vector3 = body_pt + out_dir * clampf(float(near["gap"]) * 0.6, 0.18, margin)
	# 那一刻敌人的刀在往哪走 → 刀轴横在它前面
	var step := maxf(rig.last_dt, 1.0 / 120.0)
	var p0: Vector3 = rig.predict_weapon_xf(e_hit) * Vector3(0.0, y, 0.0)
	var p1: Vector3 = rig.predict_weapon_xf(e_hit + step) * Vector3(0.0, y, 0.0)
	return _finish(ip, p1 - p0, out_dir, e_hit - t_now, "melee", enemy)


## 远程：飞行物下一步会飞到哪 → 拦截点/刀轴
static func projectile_threat(player, it: Dictionary, reach: float, blade_speed: float,
		arc_deg := 160.0) -> Dictionary:
	if player == null or not player.alive:
		return {"ok": false}
	var pos: Vector3 = it["pos"]
	var vel: Vector3 = it["vel"]
	var sp := vel.length()
	if sp < 0.2:
		return {"ok": false}
	var chest: Vector3 = player.rig.global_position + Vector3(0, 2.2, 0)
	var to := pos - chest
	var dist := to.length()
	if dist > reach or dist < 0.3:
		return {"ok": false}
	var vdir := vel / sp
	# arc_deg = 「冲着我来」的最大夹角：正对我飞来算 1.0，飞走的算负数
	var closing := -vdir.dot(to.normalized())
	if closing < cos(deg_to_rad(clampf(arc_deg, 30.0, 360.0)) * 0.5):
		return {"ok": false}
	# 落点：在飞行物自己的航路上，挑一个「离身体够近、但还没打到」的点
	var d_target := clampf(dist - 1.2, 1.6, minf(reach, 2.6))
	var bq := to.dot(vdir)                     # 航路投影（朝我飞来时 < 0）
	var cq := dist * dist - d_target * d_target
	var disc := bq * bq - cq
	var s := 0.0
	if disc >= 0.0:
		s = clampf(-bq - sqrt(disc), 0.0, dist)
	else:
		s = clampf(-bq, 0.0, dist)             # 擦身而过：取最近点
	var ip := pos + vdir * s
	var eta := s / sp
	var od := ip - chest
	if od.length() > reach:
		od = od.normalized() * reach
		ip = chest + od
		eta = maxf((ip - pos).dot(vdir) / sp, 0.0)
	var out_dir: Vector3 = (ip - chest).normalized() if (ip - chest).length_squared() > 0.0001 else to.normalized()
	return _finish(ip, vel, out_dir, eta, "shot", null)


## 机体胶囊（线段 a-b，半径 r）离敌人刀身最近的那一对点
static func nearest_on_blade(xf: Transform3D, rig, a: Vector3, b: Vector3, cap_r: float) -> Dictionary:
	var discs: Array = rig.blade_discs
	var best := {"gap": 1e9, "blade_pt": xf.origin, "body_pt": a, "y": 1.2}
	if discs.is_empty():
		return best
	var scale: float = rig.weapon_scale
	var stride := maxi(1, int(round(float(discs.size()) / 12.0)))
	var i := 0
	while i < discs.size():
		var d: Dictionary = discs[i]
		var y: float = float(d["y"])
		if y < 0.2:                       # 跳过刀柄/配重，只测刀身
			i += stride
			continue
		var p: Vector3 = xf * Vector3(0.0, y, 0.0)
		var q: Vector3 = Hit.closest_on_segment(p, a, b)
		var dir := p - q
		var rr: float = float(d["r"]) * scale
		var gap := dir.length() - rr - cap_r
		if gap < float(best["gap"]):
			var surf := q
			if dir.length_squared() > 0.0001:
				surf = q + dir.normalized() * cap_r
			best = {"gap": gap, "blade_pt": p, "body_pt": surf, "y": y}
		i += stride
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

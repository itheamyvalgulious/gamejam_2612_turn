extends RefCounted
class_name Hit
## 真实碰撞数学。
##
## 「剑」不是一个粗胶囊：rig 把建模网格顶点拟合成「少顶点凸体」代理
## （BladeProxy，见 res://core/blade_proxy.gd）。这里把这些凸体在
## 「上一帧变换 → 当前帧变换」之间扫掠，与目标的胶囊做 GJK 最短距离检测。
## 所以挥砍/格挡/用刀挡箭都是真几何，不是射线或球形近似。
## 机体不是单个胶囊：敌人按关节拆成多段判定件（MechRig.hit_parts），
## 用 sweep_blade_parts / sweep_sphere_parts 逐件取最深接触。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const EPS := 1e-6


## 线段 p0-p1 与 q0-q1 的最近点对（Ericson, Real-Time Collision Detection 5.1.9）
static func seg_seg(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> Dictionary:
	var d1 := p1 - p0
	var d2 := q1 - q0
	var r := p0 - q0
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= EPS and e <= EPS:
		return {"d": r.length(), "s": 0.0, "t": 0.0, "c0": p0, "c1": q0}
	if a <= EPS:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= EPS:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > EPS:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var c0 := p0 + d1 * s
	var c1 := q0 + d2 * t
	return {"d": c0.distance_to(c1), "s": s, "t": t, "c0": c0, "c1": c1}


## 一次挥砍：凸体代理沿 prev_xf→cur_xf 扫掠（子采样），与目标胶囊求最深接触。
## disc_scale 参数已废弃：缩放通过变换本身表达。
static func sweep_blade(prev_xf: Transform3D, cur_xf: Transform3D, proxy: BladeProxy,
		cap_a: Vector3, cap_b: Vector3, cap_r: float) -> Dictionary:
	if proxy == null or proxy.pieces.is_empty():
		return {"hit": false}
	return BladeProxy.sweep_capsule(prev_xf, cur_xf, proxy, cap_a, cap_b, cap_r)


## 飞行物这一帧的位移线段 prev→pos 是否穿过刀身（凸体代理）
static func segment_vs_blade(prev: Vector3, pos: Vector3, xf: Transform3D,
		proxy: BladeProxy, sphere_r: float) -> Dictionary:
	return BladeProxy.segment_vs_proxy(prev, pos, xf, proxy, sphere_r)


static func segment_vs_blade_swept(prev_p: Vector3, cur_p: Vector3,
		prev_xf: Transform3D, cur_xf: Transform3D,
		proxy: BladeProxy, sphere_r: float) -> Dictionary:
	return BladeProxy.segment_vs_proxy_swept(prev_p, cur_p, prev_xf, cur_xf, proxy, sphere_r)


## 剑挡剑：两把凸体刀求表面最短距离（不再有圆盘半径和）。
## 只要两把刀真的交在一起就算挡住 —— 与「谁在谁的画面里」毫无关系。
static func blade_vs_blade(xf_a: Transform3D, proxy_a: BladeProxy,
		xf_b: Transform3D, proxy_b: BladeProxy, slack := 0.03,
		span_a := Vector2(-INF, INF), span_b := Vector2(-INF, INF)) -> Dictionary:
	return BladeProxy.blade_vs_blade(xf_a, proxy_a, xf_b, proxy_b, slack, span_a, span_b)


## 扫掠版剑挡剑：两把刀这一帧各自从 prev 扫到 cur，3×4 子采样。
## 快刀单帧能扫过 2 m，只比「当前一瞬间」会漏判，所以格挡必须用扫掠。
static func blade_vs_blade_swept(prev_a: Transform3D, cur_a: Transform3D,
		proxy_a: BladeProxy, prev_b: Transform3D, cur_b: Transform3D,
		proxy_b: BladeProxy, slack := 0.03,
		span_a := Vector2(-INF, INF), span_b := Vector2(-INF, INF),
		steps_a := 3, steps_b := 4, deadline := -1) -> Dictionary:
	return BladeProxy.blade_vs_blade_swept(prev_a, cur_a, proxy_a,
		prev_b, cur_b, proxy_b, slack, span_a, span_b,
		steps_a, steps_b, deadline)


## 静止姿态下的刀身是否碰到某个球（用于「用刀挡箭」的即时接触判定）
static func blade_vs_sphere(xf: Transform3D, proxy: BladeProxy,
		center: Vector3, radius: float) -> Dictionary:
	return BladeProxy.proxy_vs_sphere(xf, proxy, center, radius)


## 多段胶囊版挥砍：机体被拆成若干判定件（躯干/头/四肢），逐件取最深接触。
## 这样打腿、打手、打肩甲都能算命中，而不是只有躯干中心那个大胶囊。
static func sweep_blade_parts(prev_xf: Transform3D, cur_xf: Transform3D,
		proxy: BladeProxy, parts: Array) -> Dictionary:
	return BladeProxy.sweep_capsule_parts(prev_xf, cur_xf, proxy, parts)


## 球体扫掠 vs 胶囊（箭矢/刀气/冲撞用），返回进入时间
static func sweep_sphere(p0: Vector3, p1: Vector3, r: float,
		cap_a: Vector3, cap_b: Vector3, cap_r: float) -> Dictionary:
	var res := seg_seg(p0, p1, cap_a, cap_b)
	if float(res["d"]) <= r + cap_r:
		return {"hit": true, "t": float(res["s"]), "point": res["c1"], "blade_point": res["c0"],
			"normal": (res["c0"] - res["c1"]).normalized()}
	return {"hit": false}


## 两个运动球体（箭对箭）是否在本帧相撞
static func sphere_pair(p0: Vector3, p1: Vector3, r0: float,
		q0: Vector3, q1: Vector3, r1: float) -> Dictionary:
	var res := seg_seg(p0, p1, q0, q1)
	var rr := r0 + r1
	if float(res["d"]) <= rr:
		return {"hit": true, "t": float(res["s"]), "point": res["c0"],
			"normal": (res["c0"] - res["c1"]).normalized()}
	return {"hit": false}


## 球体扫掠 vs 一组判定件（弹回的飞行物打怪）
static func sweep_sphere_parts(p0: Vector3, p1: Vector3, r: float, parts: Array) -> Dictionary:
	var best := {"hit": false, "depth": 0.0}
	for p in parts:
		var res := seg_seg(p0, p1, p["a"], p["b"])
		var rr: float = r + float(p["r"])
		var dist: float = float(res["d"])
		if dist > rr:
			continue
		var depth := rr - dist
		if bool(best["hit"]) and depth <= float(best["depth"]):
			continue
		var n: Vector3 = (res["c0"] as Vector3) - (res["c1"] as Vector3)
		if n.length_squared() < EPS:
			n = Vector3.UP
		best = {"hit": true, "depth": depth, "t": float(res["s"]),
			"point": res["c1"], "blade_point": res["c0"], "normal": n.normalized(),
			"part": String(p.get("label", ""))}
	return best


## 小组件：把 rig 变成一个碰撞胶囊（躯干核心，不含四条展开的腿）
static func rig_capsule(rig: Node3D, radius := 1.1, height := 3.4) -> Dictionary:
	var base := rig.global_position
	var sc := rig.global_transform.basis.get_scale().x
	return {
		"a": base + Vector3(0, 1.0 * sc, 0),
		"b": base + Vector3(0, (1.0 + height) * sc, 0),
		"r": radius * sc,
		"scale": sc,
	}


## 圆形掩体推出：pos 被推到所有圆柱/箱体之外（cover.r 是给相机用的膨胀半径）
static func resolve_circles(pos: Vector3, radius: float, cover: Array, y := 0.0) -> Vector3:
	for c in cover:
		var cc: Vector3 = c["c"]
		var h: float = float(c.get("h", 3.0))
		if y < cc.y - 0.25:
			continue          # 还在掩体底面以下（如二层环廊的护栏，不挡一层）
		if y > cc.y + h + 0.2:
			continue          # 已经在掩体顶上（跳过去了）
		var phys: float = maxf(0.35, float(c["r"]) - 1.2)
		var need: float = phys + radius
		var d := Vector2(pos.x - cc.x, pos.z - cc.z)
		var dl := d.length()
		if dl < need:
			if dl < 0.001:
				d = Vector2(1, 0)
				dl = 1.0
			d = d / dl * need
			pos.x = cc.x + d.x
			pos.z = cc.z + d.y
	return pos


## 点到线段距离（AI 用）
static func dist_point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	return p.distance_to(closest_on_segment(p, a, b))


## 线段 a-b 上离 p 最近的那个点
static func closest_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), EPS), 0.0, 1.0)
	return a + ab * t

extends RefCounted
class_name Hit
## 真实碰撞数学。
##
## 「剑」不是一个粗胶囊：rig 会把它建模出来的每个剑网格的顶点读出来，滚筒式地
## 切成 30 段圆盘剖面 [{y, r}]（见 mech_rig.build_blade_discs）。这里把这些圆盘
## 在「上一帧变换 → 当前帧变换」之间连成扫掠线段，与目标的胶囊做线段-线段最近
## 距离检测。所以挥砍/格挡/用刀挡箭都是真几何，不是射线或球形近似。
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


## 一次挥砍：把刀的圆盘剖面沿 prev_xf→cur_xf 扫掠，与目标胶囊求最深的接触
## disc_scale = rig 的世界缩放（大怪 ×2）
##
## 圆盘中心沿直线 prev→cur 移动，所以整段扫掠就是「一条线段」：细分采样不会
## 改变覆盖范围，只会把同一次线-线最近距离重复算 N 遍，所以每个圆盘只算一次。
static func sweep_blade(prev_xf: Transform3D, cur_xf: Transform3D, discs: Array,
		disc_scale: float, cap_a: Vector3, cap_b: Vector3, cap_r: float) -> Dictionary:
	if discs.is_empty():
		return {"hit": false}
	var best := {"hit": false, "depth": 0.0}
	for d in discs:
		var y: float = float(d["y"])
		var r: float = float(d["r"]) * disc_scale + cap_r
		var a := prev_xf * Vector3(0.0, y, 0.0)
		var b := cur_xf * Vector3(0.0, y, 0.0)
		var res := seg_seg(a, b, cap_a, cap_b)
		var dist: float = float(res["d"])
		if dist <= r:
			var depth := r - dist
			if depth > float(best["depth"]):
				var n: Vector3 = (res["c0"] - res["c1"])
				if n.length_squared() < EPS:
					n = (b - a)
				if n.length_squared() < EPS:
					n = Vector3.UP
				best = {"hit": true, "depth": depth, "point": res["c1"],
					"blade_point": res["c0"], "normal": n.normalized(),
					"t": float(res["s"]), "disc_r": r}
	return best


## 飞行物这一帧的位移线段 prev→pos 是否穿过刀身（用真实圆盘剖面）
static func segment_vs_blade(prev: Vector3, pos: Vector3, xf: Transform3D, discs: Array,
		disc_scale: float, sphere_r: float) -> Dictionary:
	var best := 0.0
	var point := Vector3.ZERO
	for d in discs:
		var r: float = float(d["r"]) * disc_scale + sphere_r
		var c: Vector3 = xf * Vector3(0, float(d["y"]), 0)
		var dist := dist_point_segment(c, prev, pos)
		if dist <= r and (r - dist) > best:
			best = r - dist
			point = c
	return {"hit": best > 0.0, "depth": best, "point": point}


## 剑挡剑：两把刀用各自真实刀身剖面（半径随刀身位置变化）求最近接触。
## span = 刀身（护手 → 刀尖）在刀自身空间的 y 区间，由 mech_rig.blade_span() 给。
## 只要两把刀真的交在一起就算挡住 —— 与「谁在谁的画面里」毫无关系。
static func blade_vs_blade(xf_a: Transform3D, discs_a: Array, scale_a: float, span_a: Vector2,
		xf_b: Transform3D, discs_b: Array, scale_b: float, span_b: Vector2,
		slack := 0.03) -> Dictionary:
	if discs_a.is_empty() or discs_b.is_empty():
		return {"hit": false}
	var a0: Vector3 = xf_a * Vector3(0.0, span_a.x, 0.0)
	var a1: Vector3 = xf_a * Vector3(0.0, span_a.y, 0.0)
	var b0: Vector3 = xf_b * Vector3(0.0, span_b.x, 0.0)
	var b1: Vector3 = xf_b * Vector3(0.0, span_b.y, 0.0)
	var res := seg_seg(a0, a1, b0, b1)
	var y_a: float = lerpf(span_a.x, span_a.y, float(res["s"]))
	var y_b: float = lerpf(span_b.x, span_b.y, float(res["t"]))
	var rr: float = (blade_radius_at(discs_a, y_a) * scale_a
		+ blade_radius_at(discs_b, y_b) * scale_b)
	var gap: float = float(res["d"]) - rr
	var n: Vector3 = (res["c0"] as Vector3) - (res["c1"] as Vector3)
	if n.length_squared() < EPS:
		n = (a1 - a0)
	if n.length_squared() < EPS:
		n = Vector3.UP
	return {"hit": gap <= slack, "gap": gap, "depth": -gap,
		"point": ((res["c0"] as Vector3) + (res["c1"] as Vector3)) * 0.5,
		"normal": n.normalized()}


## 扫掠版剑挡剑：两把刀这一帧各自从 prev 扫到 cur，用插值采样把扫掠体近似出来。
## 快刀单帧能扫过 2 m，只比「当前一瞬间」会漏判，所以格挡必须用扫掠。
static func blade_vs_blade_swept(prev_a: Transform3D, cur_a: Transform3D, discs_a: Array,
		scale_a: float, span_a: Vector2, prev_b: Transform3D, cur_b: Transform3D, discs_b: Array,
		scale_b: float, span_b: Vector2, steps_a := 3, steps_b := 4, slack := 0.03) -> Dictionary:
	var best := {"hit": false, "gap": 1e9, "point": Vector3.ZERO, "normal": Vector3.UP}
	var na := maxi(steps_a, 2)
	var nb := maxi(steps_b, 2)
	for i in na:
		var xa := _lerp_xf(prev_a, cur_a, float(i) / float(na - 1))
		for j in nb:
			var xb := _lerp_xf(prev_b, cur_b, float(j) / float(nb - 1))
			var r := blade_vs_blade(xa, discs_a, scale_a, span_a, xb, discs_b, scale_b, span_b, slack)
			if bool(r.get("hit", false)):
				return r
			if float(r.get("gap", 1e9)) < float(best["gap"]):
				best = r
	return best


static func _lerp_xf(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	if t <= 0.0:
		return a
	if t >= 1.0:
		return b
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	if qa.dot(qb) < 0.0:
		qb = Quaternion(-qb.x, -qb.y, -qb.z, -qb.w)
	var sa := a.basis.get_scale()
	var sb := b.basis.get_scale()
	return Transform3D(Basis(qa.slerp(qb, t)).scaled(sa.lerp(sb, t)), a.origin.lerp(b.origin, t))


## 刀身在某个 y（刀自身空间）处的半径（取最近的圆盘剖面）
static func blade_radius_at(discs: Array, y: float) -> float:
	var best := 0.0
	var bd := 1e9
	for d in discs:
		var dy := absf(float(d["y"]) - y)
		if dy < bd:
			bd = dy
			best = float(d["r"])
	return best


## 静止姿态下的刀身是否碰到某个球（用于「用刀挡箭」的即时接触判定）
static func blade_vs_sphere(xf: Transform3D, discs: Array, disc_scale: float,
		center: Vector3, radius: float) -> Dictionary:
	var best := 0.0
	var point := Vector3.ZERO
	for d in discs:
		var r: float = float(d["r"]) * disc_scale + radius
		var p: Vector3 = xf * Vector3(0, float(d["y"]), 0)
		var dist := p.distance_to(center)
		if dist <= r and (r - dist) > best:
			best = r - dist
			point = p
	return {"hit": best > 0.0, "depth": best, "point": point}


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


## 多段胶囊版挥砍：机体被拆成若干判定件（躯干/头/四肢），逐件取最深接触。
## 这样打腿、打手、打肩甲都能算命中，而不是只有躯干中心那个大胶囊。
##
## 性能：这一帧所有刀的圆盘扫掠线段只算一次（不是每件重算），再用扫掠 AABB
## 先剔掉离刀很远的判定件。单帧 30 圆盘 × 24 判定件也只要 ~0.2 ms。
static func sweep_blade_parts(prev_xf: Transform3D, cur_xf: Transform3D, discs: Array,
		disc_scale: float, parts: Array) -> Dictionary:
	if discs.is_empty() or parts.is_empty():
		return {"hit": false, "depth": 0.0}
	var segs: Array = []
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var max_r := 0.0
	for d in discs:
		var y: float = float(d["y"])
		var r: float = float(d["r"]) * disc_scale
		var a := prev_xf * Vector3(0.0, y, 0.0)
		var b := cur_xf * Vector3(0.0, y, 0.0)
		segs.append({"a": a, "b": b, "r": r})
		lo = lo.min(a).min(b)
		hi = hi.max(a).max(b)
		max_r = maxf(max_r, r)
	lo -= Vector3.ONE * max_r
	hi += Vector3.ONE * max_r
	var best := {"hit": false, "depth": 0.0}
	for p in parts:
		var pa: Vector3 = p["a"]
		var pb: Vector3 = p["b"]
		var pr: float = float(p["r"])
		# 粗筛：判定件整个在刀扫过的盒子之外
		if minf(pa.x, pb.x) - pr > hi.x or maxf(pa.x, pb.x) + pr < lo.x:
			continue
		if minf(pa.y, pb.y) - pr > hi.y or maxf(pa.y, pb.y) + pr < lo.y:
			continue
		if minf(pa.z, pb.z) - pr > hi.z or maxf(pa.z, pb.z) + pr < lo.z:
			continue
		for s in segs:
			var rr: float = float(s["r"]) + pr
			var res := seg_seg(s["a"], s["b"], pa, pb)
			var dist: float = float(res["d"])
			if dist > rr:
				continue
			var depth := rr - dist
			if bool(best["hit"]) and depth <= float(best["depth"]):
				continue
			var n: Vector3 = (res["c0"] - res["c1"])
			if n.length_squared() < EPS:
				n = ((s["b"] as Vector3) - (s["a"] as Vector3))
			if n.length_squared() < EPS:
				n = Vector3.UP
			best = {"hit": true, "depth": depth, "point": res["c1"],
				"blade_point": res["c0"], "normal": n.normalized(),
				"t": float(res["s"]), "disc_r": rr, "part": String(p.get("label", ""))}
	return best


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

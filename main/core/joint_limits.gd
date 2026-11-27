extends RefCounted
## 关节自然度限位评估（requirement #2 主动迎击的第三层筛选）。
##
## 为每个关节定义「生理上自然」的活动范围：
##   · 球形关节（肩）→ 2D 限位区域：方向锥在 (方位角, 仰角) 平面上的凸多边形，
##     落在区域外按距离扣分，超出硬边界直接淘汰；
##   · 铰链关节（肘）→ 一维角度区间 [lo, hi]，逼近/超出区间端点扣分；
##   · 腰环 yaw 与躯干 pitch/roll → 一维角度区间。
##
## 返回 {hard_ok, score, violations}：
##   hard_ok=false → 候选直接淘汰；score 越小越自然（0 = 完全在舒适区内）。
##
## 输入都来自解析逆解（campaign_rig._arm_ik_chain / _torso_transform），
## 不读节点姿态 —— 规划器在真正写 weapon_root 之前就能评估一个候选姿态。

# ---- 肩（球形关节）：目标方向锥，局部系 = 躯干空间，-Z 朝前 ----
# 区域用 (azimuth = atan2(x, -z), elevation = asin(y)) 的凸多边形描述：
#   前下舒适区最大，向后/过头顶收窄。
const SHOULDER_POLY := [
	Vector2(-1.45, -1.20), Vector2(-0.10, -1.30), Vector2(1.45, -1.20),
	Vector2(1.85, -0.35), Vector2(1.55, 0.55), Vector2(0.90, 1.10),
	Vector2(0.05, 1.15), Vector2(-0.90, 1.10), Vector2(-1.55, 0.55),
	Vector2(-1.85, -0.35),
]
# 圆锥近似硬边界：目标方向相对「前方」的最大张角（rad），超出直接淘汰。
const SHOULDER_HARD_YAW := 2.05
# 肩域软边距：多边形外 ≤ 此距离不硬淘汰，只扣分（rad）
const SHOULDER_SOFT := 0.28

# ---- 肘（铰链）：上臂/前臂夹角（rad）。0 = 完全伸直，PI = 完全折叠 ----
const ELBOW_COMFY := Vector2(0.22, 2.35)   # 舒适区间（fold 不至于上臂穿前臂）
const ELBOW_HARD := Vector2(0.06, 2.80)    # 硬限位（IK 物理上永远 ≤ 2.83）

# ---- 腕（铰链近似）：前臂轴线偏离刀柄轴的程度 |cos|。
# 双手握柄的标准姿态是「前臂 ⊥ 刀柄」：|cos|≈0；|cos|→1 表示腕强拧。 ----
const WRIST_COMFY := 0.78
const WRIST_HARD := 0.94

# ---- 腰环 / 躯干 ----
const TORSO_YAW := Vector2(-2.75, 2.75)    # 与 campaign_rig 的 yaw clamp 同边界
const TORSO_YAW_HARD := 2.80
const TORSO_PITCH := Vector2(-0.62, 0.55)
const TORSO_ROLL := Vector2(-0.55, 0.55)


## 单个 1D 角度区间的打分：返回 [超出量(rad), 舒适区内为 0]。
static func _range_over(value: float, comfy: Vector2) -> float:
	if value < comfy.x:
		return comfy.x - value
	if value > comfy.y:
		return value - comfy.y
	return 0.0


## 点在凸多边形内？（2D 叉积一致性；多边形按逆时针时全正）
static func _poly_signed(poly: Array, p: Vector2) -> float:
	# 返回点到多边形的有符号距离：>0 在外（近似，取各边最大半平面违反量的正值），
	# ≤0 在内（到最近边的距离为负）。凸多边形用「逐边半平面」精确。
	var max_violation := -1e9
	var n := poly.size()
	# 先判内外：所有边同号即内部（统一按逆时针算；本常量即逆时针）
	var inside := true
	var min_edge := 1e9
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var edge := b - a
		var d: float = edge.x * (p.y - a.y) - edge.y * (p.x - a.x)  # cross(edge, p-a)
		# 逆时针多边形内部在每条边左侧（d ≥ 0）
		if d < -1e-9:
			inside = false
		# 到边的垂距（点-线段取最近点）
		var t: float = clampf((p - a).dot(edge) / maxf(edge.length_squared(), 1e-9), 0.0, 1.0)
		var dist: float = (p - (a + edge * t)).length()
		if dist < min_edge:
			min_edge = dist
		if d > max_violation:
			max_violation = d
	if inside:
		return -min_edge
	# 外部：返回最近边/顶点距离（正）
	return min_edge


## 肩部（球形）2D 限位：方向向量 dir（躯干局部，单位化）→ {over, inside}
static func shoulder(dir: Vector3) -> Dictionary:
	var az: float = atan2(dir.x, -dir.z)
	var el: float = asin(clampf(dir.y, -1.0, 1.0))
	# 圆锥硬边界：与「正前」的夹角。躯干局部 -Z 是前方。
	var cone: float = dir.angle_to(Vector3(0.0, 0.0, -1.0))
	var outside: float = _poly_signed(SHOULDER_POLY, Vector2(az, el))
	var over := maxf(outside - 0.0, cone - SHOULDER_HARD_YAW * 0.0)
	var hard_ok: bool = outside <= SHOULDER_SOFT and cone <= SHOULDER_HARD_YAW
	var over_r: float = maxf(outside, 0.0) + maxf(cone - SHOULDER_HARD_YAW, 0.0) * 3.0
	if not hard_ok:
		over_r += 1.0
	return {"over": over_r, "hard_ok": hard_ok, "az": az, "el": el}


## 肘部（铰链）：上臂→前臂折角 ang（rad）
static func elbow(ang: float) -> Dictionary:
	var over := _range_over(ang, ELBOW_COMFY)
	var hard_ok: bool = ang >= ELBOW_HARD.x and ang <= ELBOW_HARD.y
	return {"over": over, "hard_ok": hard_ok}


## 腕部（铰链近似）：前臂方向 fore_dir 与刀柄轴 hilt_y 的对齐度
static func wrist(fore_dir: Vector3, hilt_y: Vector3) -> Dictionary:
	var align: float = absf(fore_dir.normalized().dot(hilt_y.normalized()))
	var over := maxf(align - WRIST_COMFY, 0.0)
	return {"over": over, "hard_ok": align <= WRIST_HARD, "align": align}


## 躯干：yaw 额外转角（相对当前）+ pitch/roll（保持现状则 0）
static func torso(yaw: float, pitch: float, roll: float) -> Dictionary:
	var over := _range_over(yaw, TORSO_YAW) * 0.6 \
		+ _range_over(pitch, TORSO_PITCH) + _range_over(roll, TORSO_ROLL)
	var hard_ok: bool = absf(yaw) <= TORSO_YAW_HARD \
		and pitch >= TORSO_PITCH.x - 0.35 and pitch <= TORSO_PITCH.y + 0.35 \
		and roll >= TORSO_ROLL.x - 0.35 and roll <= TORSO_ROLL.y + 0.35
	return {"over": over, "hard_ok": hard_ok}


## 汇总一条手臂链 + 躯干的自然度。
## arms: [{"dir": 肩→握目标(躯干局部), "elbow": rad, "fore_dir": 前臂方向, "hilt_y": 刀柄轴}]
## torso_yaw: 候选躯干 yaw（rad, 躯干局部）
static func pose(arm_descs: Array, torso_yaw: float, torso_pitch := 0.0,
		torso_roll := 0.0) -> Dictionary:
	var score := 0.0
	var hard_ok := true
	var violations: Array = []
	var t := torso(torso_yaw, torso_pitch, torso_roll)
	if not bool(t["hard_ok"]):
		hard_ok = false
		violations.append("torso")
	score += float(t["over"]) * 0.7
	for i in arm_descs.size():
		var a: Dictionary = arm_descs[i]
		var sh := shoulder(a["dir"])
		var el := elbow(float(a["elbow"]))
		var wr := wrist(a["fore_dir"], a["hilt_y"])
		if not bool(sh["hard_ok"]):
			hard_ok = false
			violations.append("shoulder%d" % i)
		if not bool(el["hard_ok"]):
			hard_ok = false
			violations.append("elbow%d" % i)
		if not bool(wr["hard_ok"]):
			hard_ok = false
			violations.append("wrist%d" % i)
		score += float(sh["over"]) * 1.4 + float(el["over"]) * 0.9 + float(wr["over"]) * 0.8
	return {"hard_ok": hard_ok, "score": score, "violations": violations}

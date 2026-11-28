extends RefCounted
## MoveSolver —— 玩家移动的统一解析解算器。
##
## 模型就一颗圆柱胶囊（半径 radius × 高度 height，脚底在 pos.y），对
## arena 里一组 AABB solids 做三阶段解算：
##   1. 垂直：y 位移被箱顶（落上）和箱底（撞头）直接夹住；
##   2. 水平：位移按轴拆分逐子步推进，挡住的轴丢弃（滑墙）；目标贴箱边
##      且箱顶在 step_up 以内时先试抬脚踩上去；
##   3. 去穿透：若圆柱仍与某盒相交，选推开距离最小的轴推出（箱顶 ≤ step_up
##      优先抬上去，否则水平挤出最近侧面）。每帧结束一定不嵌在盒内，
##      所以不存在「水平寸步难行、只能跳出去」的状态。
## 圆形挡柱走 spec["circles"]（{c:Vector2,r:float,y0:float,y1:float}）。
## 返回落点；跳跃状态切换由 levels 的 constrain_player 负责（接、落、摔坑）。

const EPS := 0.025
## 穿透容差：胶囊沿边/角擦过时 XZ 重叠量在毫米级浮动，当作接触不算穿透。
const SKIN := 0.002


## 一次完整移动：from → target，输出可安全落的位置。
## spec: {solids:[AABB], radius:float, height:float, step_up:float,
##        clamp_xz:Vector4(可选), clamp_y:Vector2(可选), circles:[](可选),
##        ground_margin:float(可选, support 的 XZ 收进,默认 0)}
static func solve(from: Vector3, target: Vector3, spec: Dictionary) -> Vector3:
	var solids: Array = spec.get("solids", [])
	var radius := float(spec.get("radius", 1.1))
	var height := float(spec.get("height", 3.8))
	var step_up := float(spec.get("step_up", 0.45))
	var pos := from

	# ---- 1. 垂直移动（一次到位：AABB 线性垂直滑轨无中间态）----
	if not is_equal_approx(pos.y, target.y):
		pos.y = _clip_y(pos, target.y, radius, height, step_up, solids, spec.get("circles", []))

	# ---- 2. 水平移动：子步 + 轴分离滑墙；贴矮箱先抬脚 ----
	var flat := Vector2(target.x - pos.x, target.z - pos.z)
	var steps := maxi(1, ceili(flat.length() / 0.25))
	var d := flat / float(steps)
	for i in steps:
		# 水平位移: 先合轴, 不行再逐轴
		var next := Vector3(pos.x + d.x, pos.y, pos.z + d.y)
		if _body_clear(next, radius, height, solids, spec.get("circles", [])):
			pos = next
			continue
		next = Vector3(pos.x + d.x, pos.y, pos.z)
		if _body_clear(next, radius, height, solids, spec.get("circles", [])):
			pos = next
		next = Vector3(pos.x, pos.y, pos.z + d.y)
		if _body_clear(next, radius, height, solids, spec.get("circles", [])):
			pos = next
			continue
		# 台阶: 目标 Y 升到箱顶再试一次（同一子步内完成，低箱矮台一路平推）
		var stepped: Dictionary = _try_step_up(pos, Vector3(d.x, 0, d.y), radius, height, step_up, solids, spec.get("circles", []))
		if bool(stepped.get("ok", false)):
			pos = stepped["pos"]
	pos.y = _clamp_axis(pos.y, spec.get("clamp_y"))
	pos.x = _clamp_axis(pos.x, spec.get("clamp_x"))
	pos.z = _clamp_axis(pos.z, spec.get("clamp_z"))
	if spec.has("clamp_xz"):
		var c: Vector4 = spec["clamp_xz"]
		pos.x = clampf(pos.x, c.x, c.y)
		pos.z = clampf(pos.z, c.z, c.w)

	# ---- 3. 去穿透：仍相交就选最小推出距离的轴 ----
	pos = _depenetrate(pos, radius, height, step_up, solids, spec.get("circles", []))
	return pos


## 脚踩的支撑面高度：只认胶囊 footprint 内的盒顶，取 pos.y+EPS 以下最高者。
static func floor_at(pos: Vector3, solids: Array, radius: float, max_y := INF) -> float:
	var best := -INF
	for box: AABB in solids:
		if box.end.y > minf(pos.y + EPS, max_y):
			continue
		if _foot_overlaps(box, pos, radius * 0.9) and box.end.y > best:
			best = box.end.y
	return best


# ============================================================ 内部

## y 位移被盒顶/盒底夹住：往上撞顶 → 截到箱底-height；往下落脚 → 截到箱顶。
static func _clip_y(pos: Vector3, target_y: float, radius: float, height: float,
		step_up: float, solids: Array, circles: Array) -> float:
	var y := target_y
	var rising := target_y > pos.y
	for box: AABB in solids:
		if not _foot_overlaps(box, pos, radius):
			continue
		if rising:
			var head_limit := box.position.y - height
			if pos.y <= head_limit + EPS and y > head_limit:
				y = minf(y, head_limit)
		else:
			if pos.y >= box.end.y - EPS and y < box.end.y:
				y = maxf(y, box.end.y)
	for c in circles:
		var dc := _circle_dist(pos, c)
		if dc >= radius + float(c.get("r", 0.0)):
			continue
		var y1 := float(c.get("y1", INF))
		var y0 := float(c.get("y0", -INF))
		if rising:
			var head_limit := y0 - height
			if pos.y <= head_limit + EPS and y > head_limit:
				y = minf(y, head_limit)
		else:
			if pos.y >= y1 - EPS and y < y1:
				y = maxf(y, y1)
	# 抬升出去的步进：落点要是仍浅嵌（顶-脚 ≤ step_up）直接站上箱顶。
	if not rising:
		for box: AABB in solids:
			if not _foot_overlaps(box, pos, radius):
				continue
			var embed := box.end.y - y
			if embed > EPS and embed <= step_up and pos.y >= box.position.y - EPS:
				y = box.end.y
	return y


static func _try_step_up(pos: Vector3, move: Vector3, radius: float, height: float,
		step_up: float, solids: Array, circles: Array) -> Dictionary:
	# 找挡住去路的盒里最矮的顶：能在 step_up 内抬上去就抬。
	var goal := pos + move
	var need_y := -INF
	for box: AABB in solids:
		if goal.y >= box.end.y - EPS or goal.y + height <= box.position.y:
			continue
		if not _foot_overlaps(box, goal, radius):
			continue
		need_y = maxf(need_y, box.end.y)
	if need_y == -INF:
		return {"ok": false}
	if need_y - pos.y > step_up:
		return {"ok": false}
	var up := Vector3(pos.x, need_y, pos.z)
	if not _body_clear(up, radius, height, solids, circles):
		return {"ok": false}
	var fwd := up + move
	if not _body_clear(fwd, radius, height, solids, circles):
		return {"ok": false}
	return {"ok": true, "pos": fwd}


## 最小的去穿透位移：上抬 ≤ step_up 优先（站上），其次水平最近侧面。
## 末尾才考虑下压（高度大的盒几乎不走这条，避免把人压进地板以下）。
static func _depenetrate(pos: Vector3, radius: float, height: float, step_up: float,
		solids: Array, circles: Array) -> Vector3:
	for _pass in 4:  # 多个盒相交时多推几轮；单盒一轮即出
		var best_push := Vector3.ZERO
		var best_cost := INF
		var hit := false
		for box: AABB in solids:
			var p := _box_push(pos, radius, height, box, step_up)
			if p.is_empty():
				continue
			hit = true
			var cost: float = p["cost"]
			if cost < best_cost:
				best_cost = cost
				best_push = p["vec"]
		for c in circles:
			var p := _circle_push(pos, radius, height, c, step_up)
			if p.is_empty():
				continue
			hit = true
			var cost: float = p["cost"]
			if cost < best_cost:
				best_cost = cost
				best_push = p["vec"]
		if not hit or best_push.length_squared() < SKIN * SKIN:
			break
		pos += best_push
	return pos


## 圆柱(底 pos.y 高 height 半径 radius) 与 AABB 的最小逃逸位移。
## {vec, cost} 或 {}。三轴候选：顶抬/底压（位移即距离），四侧（XZ 余量）。
static func _box_push(pos: Vector3, radius: float, height: float, box: AABB, step_up: float) -> Dictionary:
	# XZ 交叠（圆 vs 矩形）才有穿透; y 带也要相交
	var dx := pos.x - clampf(pos.x, box.position.x, box.end.x)
	var dz := pos.z - clampf(pos.z, box.position.z, box.end.z)
	var r2 := radius * radius
	if dx * dx + dz * dz >= r2 or radius - sqrt(maxf(dx * dx + dz * dz, 0.0)) <= SKIN:
		return {}
	if pos.y + height <= box.position.y + EPS or pos.y >= box.end.y - EPS:
		return {}
	var candidates: Array = []
	# 顶抬：站上箱顶（位移 = 嵌入深度）。最小逃逸原则：低箱薄栏 → 上去；
	# 墙柱深嵌 → 顶抬位移大,自动输给水平推出。
	var up_cost := box.end.y - pos.y
	candidates.append({"vec": Vector3(0, up_cost, 0), "cost": up_cost})
	# 底压：按天花板处理（位移一般远大于上抬/侧推，默认垫底）
	var down_cost := (pos.y + height) - box.position.y
	candidates.append({"vec": Vector3(0, -down_cost, 0), "cost": down_cost + 0.5})
	# 水平推：推向圆心外法线，把 footprint 推出圆外
	var overlap := radius - sqrt(maxf(dx * dx + dz * dz, 0.0))
	if dx * dx + dz * dz < 1e-8:
		# 圆心已进盒内：推到最近侧面外一个半径（位移 = 到面的距离 + 半径）。
		var left := pos.x - box.position.x
		var right := box.end.x - pos.x
		var back := pos.z - box.position.z
		var front := box.end.z - pos.z
		var m := minf(minf(left, right), minf(back, front))
		var v := Vector3(-left - radius, 0, 0) if m == left else \
			(Vector3(right + radius, 0, 0) if m == right else \
			(Vector3(0, 0, -back - radius) if m == back else Vector3(0, 0, front + radius)))
		candidates.append({"vec": v, "cost": m + radius + 250.0})
	else:
		var n := Vector2(dx, dz).normalized()
		candidates.append({"vec": Vector3(n.x, 0, n.y) * overlap, "cost": overlap})
	var best: Dictionary = candidates[0]
	for c: Dictionary in candidates:
		if float(c["cost"]) < float(best["cost"]):
			best = c
	return best


static func _circle_push(pos: Vector3, radius: float, height: float, c: Dictionary, step_up: float) -> Dictionary:
	var y0 := float(c.get("y0", -INF))
	var y1 := float(c.get("y1", INF))
	if pos.y + height <= y0 + EPS or pos.y >= y1 - EPS:
		return {}
	var r := float(c.get("r", 0.0)) + radius
	var dv := _circle_dist(pos, c)
	if dv >= r:
		return {}
	var center: Vector2 = c["c"]
	var d := Vector2(pos.x - center.x, pos.z - center.y)
	var n := d.normalized() if d.length_squared() > 1e-8 else Vector2(1, 0)
	var overlap := r - d.length()
	var up_cost := y1 - pos.y
	if up_cost <= step_up and up_cost < overlap:
		return {"vec": Vector3(0, up_cost, 0), "cost": up_cost}
	return {"vec": Vector3(n.x, 0, n.y) * overlap, "cost": overlap}


static func _body_clear(pos: Vector3, radius: float, height: float, solids: Array, circles: Array) -> bool:
	for box: AABB in solids:
		if pos.y + height <= box.position.y + EPS or pos.y >= box.end.y - EPS:
			continue
		if _foot_overlaps(box, pos, radius):
			return false
	for c in circles:
		var y0 := float(c.get("y0", -INF))
		var y1 := float(c.get("y1", INF))
		if pos.y + height <= y0 + EPS or pos.y >= y1 - EPS:
			continue
		if _circle_dist(pos, c) < radius + float(c.get("r", 0.0)):
			return false
	return true


static func _foot_overlaps(box: AABB, pos: Vector3, radius: float) -> bool:
	var dx := pos.x - clampf(pos.x, box.position.x, box.end.x)
	var dz := pos.z - clampf(pos.z, box.position.z, box.end.z)
	return dx * dx + dz * dz < radius * radius


static func _circle_dist(pos: Vector3, c: Dictionary) -> float:
	var center: Vector2 = c["c"]
	return Vector2(pos.x - center.x, pos.z - center.y).length()


static func _clamp_axis(v: float, range_v) -> float:
	if range_v == null:
		return v
	return clampf(v, range_v.x if range_v is Vector2 else range_v[0],
		range_v.y if range_v is Vector2 else range_v[1])

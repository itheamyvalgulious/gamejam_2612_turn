extends RefCounted
## LevelGeometry —— 关卡地形的解析碰撞体（纯解析，无物理引擎）。
##
## 替代旧 `blade_terrain.gd` 里 PhysicsDirectSpaceState3D + CapsuleShape3D
## + get_rest_info 那一套：本文件不引用 PhysicsServer / ShapeQuery /
## StaticBody3D，一切判定都在 arena 元信息生成的凸体上走解析几何：
##
##   障碍统一为凸体 {v, planes, aabb, kind}：
##     * solids / blade_boxes 的 AABB            → OBB（轴对齐盒）
##     * walls 的 {a,b,h,base_y,n} 2D 墙段        → OBB（0.24 厚、沿 n 外移半厚，
##                                                与旧 PlayerBladeWalls 一致）
##     * cover 的 {c,r,h} 圆（半径已含 1.2 避让膨胀）→ 保守多棱柱（半径还原，
##                                                再向外放 0.06）
##     * blade_center_cylinder (r,top)           → 保守多棱柱
##
##   判定：
##     * 凸体-凸体最近距离复用 BladeProxy 的 GJK（piece 顶点 vs 障碍顶点），
##       每个 piece 也可以退化成「外接胶囊」（线段 + 半径，全包含不缺面）。
##     * 线段净空 / 射线用 Cyrus-Beck 平面裁剪（radius=0 时精确），
##       radius>0 时平面整体外放 radius（保守，不会漏挡）。
##     * XZ 2m 均匀网格做宽相；接触法线用 MTV（最小推出平移）近似，
##       吻合「刀碰到墙面/踏面/栏杆就停」的手感。
##
## 构建约定：所有输入坐标都是「arena 根节点局部 = 世界」尺度（各关
## build(origin=Vector3.ZERO) 时成立；非零 origin 时应先平移 arena 数据）。

const BladeProxyRef = preload("res://core/blade_proxy.gd")

const CONTACT_MARGIN := 0.02          # 进入此间隙即算接触（替代旧 margin 0.012+skin）
const WALL_DEPTH := 0.24              # 与旧 PlayerBladeWalls 的墙厚一致
const COVER_SHRINK := 1.2             # cover.r 里烘焙的玩家/相机避让球半径
const COVER_EXTRA := 0.06             # 还原物理半径后向外多放一点（保守含住圆柱）
const CYL_SIDES := 10                 # 圆柱/掩体的棱柱边数
const GRID_CELL := 2.0
const EPS := 1e-6

var obstacles: Array = []             # [{v:PackedVector3Array, planes:Array[Plane], aabb:AABB, kind:String}]
var _grid := {}                       # Vector2i -> Array[int]
var _seen: PackedInt32Array
var _stamp := 0


# ============================================================== 构建

static func build(arena: Dictionary) -> RefCounted:
	var geo = new()
	var floor_y := float(arena.get("floor_y", 0.0))
	var bounds: AABB = arena.get("bounds", AABB())
	if bounds.size.x > 0.1 and bounds.size.z > 0.1:
		geo._add_obb(
			Vector3(bounds.position.x + bounds.size.x * 0.5, floor_y - 0.2, bounds.position.z + bounds.size.z * 0.5),
			Basis.IDENTITY,
			Vector3(bounds.size.x * 0.5 + 4.0, 0.2, bounds.size.z * 0.5 + 4.0),
			"floor")

	# ---- AABB 盒：solids（含 walkables）与 blade_boxes ----
	for box: AABB in arena.get("solids", []):
		if box.size.x < 0.02 or box.size.y < 0.02 or box.size.z < 0.02:
			continue
		geo._add_obb(box.get_center(), Basis.IDENTITY, box.size * 0.5, "solid")
	for box: AABB in arena.get("blade_boxes", []):
		geo._add_obb(box.get_center(), Basis.IDENTITY, box.size * 0.5, "solid")

	# ---- 墙段 → OBB：线段中点沿 -n 外移半厚，X 轴沿线，Z 轴指场内 ----
	for wall: Dictionary in arena.get("walls", []):
		var a: Vector2 = wall["a"]
		var b: Vector2 = wall["b"]
		var edge := b - a
		var base: float = wall.get("base_y", floor_y)
		var height: float = float(wall["h"]) - base
		if edge.length_squared() < 0.0004 or height <= 0.05:
			continue
		var inward: Vector2 = wall.get("n", Vector2.ZERO)
		var center := (a + b) * 0.5 - inward * (WALL_DEPTH * 0.5)
		var along := Vector3(edge.x, 0.0, edge.y).normalized()
		var in3 := Vector3(inward.x, 0.0, inward.y).normalized()
		if in3.is_zero_approx():
			in3 = along.cross(Vector3.UP).normalized()
		geo._add_obb(Vector3(center.x, base + height * 0.5, center.y),
			Basis(along, Vector3.UP, in3),
			Vector3(edge.length() * 0.5, height * 0.5, WALL_DEPTH * 0.5), "wall")

	# ---- cover 圆：半径含 1.2 避让膨胀，还原后再小幅外放，多棱柱保守包住 ----
	for c: Dictionary in arena.get("cover", []):
		var center: Vector3 = c["c"]
		var r := maxf(0.15, float(c["r"]) - COVER_SHRINK) + COVER_EXTRA
		var base: float = c.get("base_y", center.y)
		var top := base + float(c["h"])
		if top - base < 0.05:
			continue
		geo._add_prism(_circle_ring(Vector2(center.x, center.z), r, CYL_SIDES),
			base, top, "cover")

	# ---- 中央圆柱（panopticon 玻璃罐等）：半径是物理尺寸，外放即可 ----
	var dims: Vector2 = arena.get("blade_center_cylinder", Vector2.ZERO)
	if dims.x > 0.01 and dims.y > 0.05:
		geo._add_prism(_circle_ring(Vector2.ZERO, dims.x + COVER_EXTRA, CYL_SIDES + 2),
			floor_y, dims.y, "cover")

	geo._index()
	return geo


static func _circle_ring(center: Vector2, radius: float, sides: int) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for i in sides:
		var ang := TAU * float(i) / float(sides)
		ring.append(center + Vector2(cos(ang), sin(ang)) * radius)
	return ring


## 构造一个凸体障碍：verts + 朝外的支撑平面（内部 = 所有平面负半空间）。
func _add_convex(verts: PackedVector3Array, planes: Array, kind: String) -> void:
	var lo := verts[0]
	var hi := verts[0]
	for p in verts:
		lo = lo.min(p)
		hi = hi.max(p)
	obstacles.append({"v": verts, "planes": planes,
		"aabb": AABB(lo, hi - lo), "kind": kind})


## OBB：center + basis（各轴单位向量）+ 半尺寸。
func _add_obb(center: Vector3, basis: Basis, half: Vector3, kind: String) -> void:
	var verts := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				verts.append(center + basis * Vector3(sx * half.x, sy * half.y, sz * half.z))
	var planes: Array = []
	var axes := [basis.x, basis.y, basis.z]
	var halves := [half.x, half.y, half.z]
	for i in 3:
		var a: Vector3 = axes[i]
		if a.length_squared() < EPS:
			continue
		# 该轴面到中心的距离：= |a·c| + 此轴自身半长（a 是 OBB 轴时
		# 其余轴对 support 无贡献）。
		var e: float = float(halves[i]) * a.length()
		var d := a.dot(center)
		planes.append(Plane(a, d + e))
		planes.append(Plane(-a, -d + e))
	_add_convex(verts, planes, kind)


## 直立棱柱：XZ 凸环（顺序任意，内部会统一为俯视顺时针）从 y0 拉到 y1。
func _add_prism(ring: PackedVector2Array, y0: float, y1: float, kind: String) -> void:
	if ring.size() < 3 or y1 - y0 < 0.05:
		return
	# 俯视顺时针 → 边外法线 = (d.y, -d.x)
	var n := ring.size()
	var area := 0.0
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var seq: Array = []
	if area > 0.0:
		for i in range(n - 1, -1, -1):
			seq.append(ring[i])
	else:
		seq = Array(ring)
	var centroid := Vector2.ZERO
	for p in seq:
		centroid += p
	centroid /= float(n)
	var verts := PackedVector3Array()
	for p in seq:
		verts.append(Vector3(p.x, y0, p.y))
	for p in seq:
		verts.append(Vector3(p.x, y1, p.y))
	var planes: Array = [Plane(Vector3.DOWN, -y0), Plane(Vector3.UP, y1)]
	for i in n:
		var a: Vector2 = seq[i]
		var b: Vector2 = seq[(i + 1) % n]
		var d := b - a
		var out2 := Vector2(d.y, -d.x)
		if out2.length_squared() < EPS:
			continue
		out2 = out2.normalized()
		if out2.dot(centroid - a) > 0.0:
			out2 = -out2
		planes.append(Plane(Vector3(out2.x, 0.0, out2.y), out2.x * a.x + out2.y * a.y))
	_add_convex(verts, planes, kind)


func _index() -> void:
	_grid.clear()
	for i in obstacles.size():
		var box: AABB = obstacles[i]["aabb"]
		for gx in range(int(floor(box.position.x / GRID_CELL)),
				int(floor(box.end.x / GRID_CELL)) + 1):
			for gz in range(int(floor(box.position.z / GRID_CELL)),
					int(floor(box.end.z / GRID_CELL)) + 1):
				var key := Vector2i(gx, gz)
				if not _grid.has(key):
					_grid[key] = []
				(_grid[key] as Array).append(i)
	_seen.resize(obstacles.size())
	_seen.fill(0)
	_stamp = 0


# ============================================================== 宽相

## XZ 矩形内候选障碍下标（含 AABB 的 y 过滤在窄相做）。
func _candidates_rect(rect: Rect2) -> Array:
	_stamp += 1
	if _stamp >= 0x3FFFFFFF:
		_seen.fill(0)
		_stamp = 1
	var out: Array = []
	for gx in range(int(floor(rect.position.x / GRID_CELL)),
			int(floor(rect.end.x / GRID_CELL)) + 1):
		for gz in range(int(floor(rect.position.y / GRID_CELL)),
				int(floor(rect.end.y / GRID_CELL)) + 1):
			var cell: Array = _grid.get(Vector2i(gx, gz), [])
			for i in cell:
				if _seen[i] == _stamp:
					continue
				_seen[i] = _stamp
				out.append(i)
	return out


func _candidates_aabb(box: AABB, grow := 0.0) -> Array:
	var b := box.grow(grow)
	return _candidates_rect(Rect2(Vector2(b.position.x, b.position.z),
		Vector2(maxf(b.size.x, 0.01), maxf(b.size.z, 0.01))))


# ============================================================== 窄相

static func _verts_aabb(verts: PackedVector3Array) -> AABB:
	var lo := verts[0]
	var hi := verts[0]
	for p in verts:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


## 点是否在凸体内（含边界）。
static func _inside(o: Dictionary, p: Vector3, margin := 1e-4) -> bool:
	for plane: Plane in o["planes"]:
		if plane.distance_to(p) > margin:
			return false
	return true


## 凸体 piece（世界顶点）vs 障碍的接触判定。
## 返回 {} 无接触；{point, normal, gap} 有接触（gap<0 为穿透深度）。
## radius>0 把 piece 顶点集视作外接胶囊的轴心凸包 —— 判定胶囊 vs 障碍。
func _piece_contact(wverts: PackedVector3Array, o: Dictionary, radius := 0.0,
		hint := Vector3.ZERO) -> Dictionary:
	var res := BladeProxyRef._gjk(wverts, o["v"])
	var d: float = res["d"]
	if d > radius + CONTACT_MARGIN:
		return {}
	var inside: Array = []
	for v in wverts:
		if _inside(o, v):
			inside.append(v)
	if d <= 0.0 and inside.is_empty():
		# GJK 判相交但没有顶点在障碍内：障碍顶点陷入 piece / 棱边穿插。
		# 用 hint 反方向与障碍平面挑一个保守的退出法线。
		var n := _fallback_normal(o, hint)
		if n.is_zero_approx():
			n = Vector3.UP
		return {"point": res["pa"], "normal": n, "gap": -CONTACT_MARGIN}
	if inside.is_empty():
		# 未穿透但在 margin 内：用 GJK 见证点法线（障碍侧朝刀）。
		var n: Vector3 = (res["pa"] as Vector3) - (res["pb"] as Vector3)
		if n.length_squared() < EPS * EPS:
			n = _fallback_normal(o, hint)
		if n.is_zero_approx():
			n = Vector3.UP
		return {"point": res["pb"], "normal": n.normalized(), "gap": d - radius}
	# MTV：对每面，把所有内部顶点推出该面所需位移 = -min_v dist_i(v)；
	# 取位移最小的面为接触面（最近出口）。胶囊再加 radius 富余。
	# 薄墙被穿透过半时「最小出口」会是远侧面 —— 手感上刀应该从进来的
	# 那一侧被弹回，所以优先在与 -hint（接近方向）同侧的平面里选。
	var approach := -hint
	var aligned := approach.length_squared() > EPS * EPS
	var best_t := INF
	var best_n := Vector3.UP
	var best_d := 0.0
	var best_pt: Vector3 = inside[0]
	var best_aligned := false
	for plane: Plane in o["planes"]:
		var t := INF
		var deep_d := -INF
		var deep: Vector3 = inside[0]
		for v in inside:
			var dist := plane.distance_to(v)
			t = minf(t, dist)
			if dist > deep_d:
				deep_d = dist
				deep = v
		t = -t + radius
		var face_aligned := aligned and plane.normal.dot(approach.normalized()) > 0.2
		# 同向面优先；同向面之间 / 非同向面之间仍按推出距离取最小。
		if face_aligned and not best_aligned:
			best_aligned = true
			best_t = INF
		if face_aligned == best_aligned and t < best_t:
			best_t = t
			best_n = plane.normal
			best_d = deep_d
			best_pt = deep
	if best_t >= INF * 0.5:
		return {"point": inside[0], "normal": Vector3.UP, "gap": -radius}
	# 接触点取「最深内部顶点投影到接触面」——贴墙时落在墙皮上。
	var point := best_pt - best_n * (best_d + radius)
	return {"point": point, "normal": best_n, "gap": -(best_t - radius)}


static func _fallback_normal(o: Dictionary, hint: Vector3) -> Vector3:
	# 偏好与运动方向相反的障碍面；没有 hint 时取最贴合 UP 的轴面。
	var dir := -hint
	if dir.length_squared() < EPS:
		dir = Vector3.UP
	dir = dir.normalized()
	var best_n := Vector3.UP
	var best := -INF
	for plane: Plane in o["planes"]:
		var s := plane.normal.dot(dir)
		if s > best:
			best = s
			best_n = plane.normal
	return best_n


# ============================================================== 刀身扫掠

## 单个姿态下的接触检测（世界坐标凸体块列表）。
## pieces: [{v, aabb?}] —— 顶点已含缩放；radius>0 时每块按外接胶囊判定。
## 返回 {} 或 {point, normal, gap}（取各块最糟糕接触）。
func contact_at(pieces: Array, radius := 0.0, hint := Vector3.ZERO) -> Dictionary:
	var union := AABB()
	var has_union := false
	for piece in pieces:
		var pb: AABB = piece["aabb"] if piece.has("aabb") else _verts_aabb(piece["v"])
		pb = pb.grow(radius + CONTACT_MARGIN)
		union = pb if not has_union else union.merge(pb)
		has_union = true
	if not has_union:
		return {}
	var best := {}
	var best_gap := INF
	for i in _candidates_aabb(union):
		var o: Dictionary = obstacles[i]
		var oaabb: AABB = o["aabb"]
		if oaabb.end.y < union.position.y or oaabb.position.y > union.end.y:
			continue
		for piece in pieces:
			var pb: AABB = piece["aabb"] if piece.has("aabb") else _verts_aabb(piece["v"])
			pb = pb.grow(radius + CONTACT_MARGIN)
			if not pb.intersects(oaabb):
				continue
			var hit := _piece_contact(piece["v"], o, radius, hint)
			if hit.is_empty():
				continue
			var gap := float(hit["gap"])
			if gap < best_gap:
				best_gap = gap
				best = hit
	return best


## 刀身刚体扫掠：prev_xf→cur_xf 之间按「平移 + 旋转×刀长」细分，
## 首个接触步二分回退到表面。pieces: [{v:PackedVector3Array, aabb?}]，
## 顶点为刀身局部坐标（已含缩放），每个姿态用 xf 直接变换。
## 返回 {t, pose, point, normal}；全程无接触返回 {"t": 1.0, "pose": cur_xf}。
func sweep_blade(prev_xf: Transform3D, cur_xf: Transform3D, pieces: Array,
		radius := 0.0, tip_len := 0.0, hint := Vector3.ZERO) -> Dictionary:
	var rotation := prev_xf.basis.get_rotation_quaternion() \
		.angle_to(cur_xf.basis.get_rotation_quaternion())
	var travel := prev_xf.origin.distance_to(cur_xf.origin) + rotation * tip_len
	var steps := clampi(ceili(travel / 0.12), 1, 80)
	var clear := prev_xf
	for i in range(1, steps + 1):
		var next := prev_xf.interpolate_with(cur_xf, float(i) / steps)
		var hit := contact_at(_world_pieces(next, pieces), radius, hint)
		if hit.is_empty():
			clear = next
			continue
		for _r in 6:
			var middle := clear.interpolate_with(next, 0.5)
			if contact_at(_world_pieces(middle, pieces), radius, hint).is_empty():
				clear = middle
			else:
				next = middle
		return {"t": (clear.origin - prev_xf.origin).length() \
				/ maxf(prev_xf.origin.distance_to(cur_xf.origin), EPS),
			"pose": clear, "point": hit["point"], "normal": hit["normal"]}
	return {"t": 1.0, "pose": cur_xf}


## pieces 局部顶点 → 世界顶点（每块记录世界 AABB，省一次重建）。
static func _world_pieces(xf: Transform3D, pieces: Array) -> Array:
	var out: Array = []
	for piece in pieces:
		var wv := PackedVector3Array()
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p: Vector3 in piece["v"]:
			var w := xf * p
			wv.append(w)
			lo = lo.min(w)
			hi = hi.max(w)
		out.append({"v": wv, "aabb": AABB(lo, hi - lo)})
	return out


# ============================================================== 线段 / 射线

## 线段与凸体的参数区间（Cyrus-Beck）。radius>0 时平面外放 radius（保守）。
## 返回 {t0, t1, n0} —— t0 进入参数与其穿入面法线；null = 不相交。
static func _seg_clip(a: Vector3, b: Vector3, o: Dictionary, radius: float) -> Variant:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var n0 := Vector3.ZERO
	var start_inside := _inside(o, a)
	for plane: Plane in o["planes"]:
		var pd := plane.d + radius
		var da := plane.normal.dot(a) - pd
		var db := plane.normal.dot(b) - pd
		var den := db - da
		if absf(den) < EPS:
			if da > 0.0:
				return null
			continue
		var t := -da / den
		if den < 0.0:
			if t > t0:
				t0 = t
				n0 = plane.normal
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return null
	if start_inside:
		return {"t0": 0.0, "t1": t1,
			"n0": -d.normalized() if d.length_squared() > EPS else Vector3.UP}
	return {"t0": t0, "t1": t1, "n0": n0}


## 线段是否完全净空（不穿任何障碍）。radius=0 等价旧 intersect_ray。
func segment_clear(a: Vector3, b: Vector3, radius := 0.0) -> bool:
	if a.is_equal_approx(b):
		return point_clear(a, radius)
	var box := AABB(a, Vector3.ZERO).expand(b).grow(radius + 0.05)
	for i in _candidates_aabb(box):
		var o: Dictionary = obstacles[i]
		if String(o["kind"]) == "floor":
			continue
		var oaabb: AABB = o["aabb"]
		if oaabb.end.y < box.position.y or oaabb.position.y > box.end.y:
			continue
		if _seg_clip(a, b, o, radius) != null:
			return false
	return true


## 射线/线段命中：返回 {point, normal, t} 或 {}。
## hit_from_inside 等价旧语义（起点在障碍内也算命中起点）。
func raycast(a: Vector3, b: Vector3, radius := 0.0) -> Dictionary:
	var best := {}
	var best_t := INF
	var box := AABB(a, Vector3.ZERO).expand(b).grow(radius + 0.05)
	for i in _candidates_aabb(box):
		var o: Dictionary = obstacles[i]
		if String(o["kind"]) == "floor":
			continue
		var oaabb: AABB = o["aabb"]
		if oaabb.end.y < box.position.y or oaabb.position.y > box.end.y:
			continue
		var hit = _seg_clip(a, b, o, radius)
		if hit == null:
			continue
		var t := float(hit["t0"])
		if t < best_t:
			best_t = t
			best = {"t": t, "point": a.lerp(b, t), "normal": hit["n0"]}
	return best


func point_clear(p: Vector3, radius := 0.0) -> bool:
	var box := AABB(p, Vector3.ZERO).grow(radius + 0.02)
	for i in _candidates_aabb(box):
		var o: Dictionary = obstacles[i]
		if String(o["kind"]) == "floor":
			continue
		var oaabb: AABB = o["aabb"]
		if p.y < oaabb.position.y - radius or p.y > oaabb.end.y + radius:
			continue
		if radius <= 0.0:
			if _inside(o, p):
				return false
		else:
			var single := PackedVector3Array([p])
			var res := BladeProxyRef._gjk(single, o["v"])
			if float(res["d"]) <= radius:
				return false
	return true


## 统计信息（调试/自测）。
func stats() -> Dictionary:
	var walls := 0
	var solids := 0
	var cover := 0
	for o in obstacles:
		match String(o["kind"]):
			"wall":
				walls += 1
			"solid":
				solids += 1
			"cover":
				cover += 1
	return {"obstacles": obstacles.size(), "walls": walls,
		"solids": solids, "cover": cover}

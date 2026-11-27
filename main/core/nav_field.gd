extends RefCounted
## NavField —— 关卡内预定义的导航元信息（纯数据 + 解析）。
##
## 用「线 + 区域」描述怪物可走的区域，不再处理场景碰撞：
##   regions   : 可走面，XZ 凸多边形 + 高度/法线 + id，支持多层（栈）。
##   lines     : 台阶/坡道中线 {a,b,y0,y1,width,kind,connects}，跨高度，
##               上下楼必须沿 line 插值高度。
##   obstacles : 路面上障碍的面拼装（凸多边形棱柱，带 y0/y1）/ AABB，
##               含 pad 模式（actor 半径膨胀 / 无膨胀）与 sight（挡视线）标志。
##
## 本文件没有任何 PhysicsDirectSpaceState / ShapeQuery / NavigationAgent /
## AStarGrid2D 引用：一切判定都只在元信息上做解析几何。

const GRID_CELL := 4.0
const STANCE_HEIGHT := 4.6        # 怪物身高（与旧 resolve_motion 一致）
const ADJACENT_STEP := 0.55       # 同层邻接默认允许的抬升上限（调用方也可传 step_height）
const SAMPLE_STEP := 0.24
const DEFAULT_STEP_HEIGHT := 0.45

var level_key := ""
var floor_default := 0.0
var regions: Array = []           # {id,poly(Vector2[],CCW),y0,y1,normal,center,aabb}
var lines: Array = []             # {a,b,y0,y1,width,kind,connects,len,dir,perp,aabb}
var obstacles: Array = []         # {poly(Vector2[])/aabb(AABB),y0,y1,pad,sight}
var _region_grid := {}            # Vector2i -> Array[int]
var _obstacle_grid := {}          # Vector2i -> Array[int]
var _adj := {}                    # region index -> Array[{to:int, link:String, line:int}]
var _adjacent_step := ADJACENT_STEP

## --nav-profile：打点累加器 {name:{"us","n","max"}}。未启用时每次查询一次
## cmdline（惰性一次），启用后每调用两次字典查找 —— 平时零开销。
var _prof := {}
var _prof_on := false
var _prof_asked := false


func _prof_tick() -> bool:
	if not _prof_asked:
		_prof_asked = true
		_prof_on = "--nav-profile" in OS.get_cmdline_user_args()
	return _prof_on


func _prof_add(name: String, start_us: int) -> void:
	var e: Dictionary = _prof.get(name, {"us": 0, "n": 0, "max": 0})
	var us := Time.get_ticks_usec() - start_us
	e["us"] = int(e["us"]) + us
	e["n"] = int(e["n"]) + 1
	e["max"] = maxi(int(e["max"]), us)
	_prof[name] = e


func prof_active() -> bool:
	return _prof_on


func prof_dump() -> String:
	var out := PackedStringArray()
	var keys := _prof.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = _prof[k]
		out.append("%s=%.1fms/%d/max%.1f" % [k, float(e["us"]) / 1000.0,
			int(e["n"]), float(e["max"]) / 1000.0])
	_prof.clear()
	return ", ".join(out)


# ============================================================== 构建
## spec（可选的每关预定义数据）：
##   floor_poly    : Array[Vector2] 主地面多边形（缺省用 arena.bounds 矩形）。
##   floor_circle  : float 圆形地面半径（bounds_circle 之外的写法）。
##   floor_margin  : float 主地面半径内缩。
##   regions       : Array[{poly,y0,y1?/h?,id?}] 额外面片（多层）。
##   platforms     : bool 把 arena["platforms"]（{c,hx,hz,h,strict?}）转 region。
##   lines         : Array[{a,b,y0,y1,width,kind,connects,lane_axis?,widen?,...}]
##   ignore_box    : AABB/Array[AABB] 命中 solids 的盒中心即忽略（楼梯踏面等）。
##   walls_obstacles / walls_sight : 把 arena["walls"] 段转为障碍（默认 true/false）。
##   cover_obstacles: bool 把 arena["cover"] 圆转障碍（默认 true）。
##   cover_shrink  : float 从 cover.r 减掉的避让球膨胀量。
##   obstacles     : Array[{poly|aabb,y0,y1,pad?}] 额外手写障碍。
##   floor_default : float 完全无支撑时的兜底高度。
static func build(arena: Dictionary, spec: Dictionary = {}) -> RefCounted:
	var field = new()
	field.floor_default = float(spec.get("floor_default", arena.get("floor_y", 0.0)))
	var walkables := _box_set(arena.get("walkables", []))
	var ignore_boxes: Array = []
	for ib in spec.get("ignore_box", []):
		ignore_boxes.append(ib)

	# ---- 区域：显式 regions / arena.platforms / walkables 顶面 / 主地面 ----
	for item in spec.get("regions", []):
		var poly: PackedVector2Array = item["poly"]
		var y0: float = float(item.get("y0", 0.0))
		var y1: float = float(item.get("y1", item.get("h", y0)))
		field._add_region(poly, y0, y1, String(item.get("id", "")))
	if bool(spec.get("platforms", true)):
		for p in arena.get("platforms", []):
			var c: Vector3 = p["c"]
			var hx := float(p["hx"])
			var hz := float(p["hz"])
			var top := float(p["h"])
			field._add_region(PackedVector2Array([
				Vector2(c.x - hx, c.z - hz), Vector2(c.x + hx, c.z - hz),
				Vector2(c.x + hx, c.z + hz), Vector2(c.x - hx, c.z + hz)]), top, top, "")
	var solids: Array = arena.get("solids", [])
	for box: AABB in solids:
		if not walkables.has(box):
			continue
		if _ignored(box, ignore_boxes):
			continue
		if box.size.x < 0.35 or box.size.z < 0.35:
			continue
		field._add_region(PackedVector2Array([
			Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z),
			Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z)]), box.end.y, box.end.y, "")

	var floor_y: float = field.floor_default
	var floor_polys: Array = []
	if spec.has("floor_polys"):
		for item in spec["floor_polys"]:
			floor_polys.append(item)
	elif spec.has("floor_poly"):
		floor_polys.append(spec["floor_poly"])
	for item in floor_polys:
		var poly := _to_poly(item)
		field._add_region(poly, floor_y, floor_y, "floor")
	if floor_polys.is_empty() and spec.has("floor_circle"):
		var poly := PackedVector2Array()
		var radius := float(spec["floor_circle"]) - float(spec.get("floor_margin", 0.0))
		for i in 32:
			var a := TAU * float(i) / 32.0
			poly.append(Vector2(cos(a), sin(a)) * radius)
		field._add_region(poly, floor_y, floor_y, "floor")
	if floor_polys.is_empty() and not spec.has("floor_circle"):
		var bounds: AABB = arena.get("bounds", AABB())
		if bounds.size.length_squared() > 0.1:
			var m := float(spec.get("floor_margin", 0.0))
			field._add_region(PackedVector2Array([
				Vector2(bounds.position.x + m, bounds.position.z + m),
				Vector2(bounds.end.x - m, bounds.position.z + m),
				Vector2(bounds.end.x - m, bounds.end.z - m),
				Vector2(bounds.position.x + m, bounds.end.z - m)]), floor_y, floor_y, "floor")

	# ---- 线：楼梯/坡道/攀爬 ----
	for item in spec.get("lines", []):
		field._add_line(item)

	# ---- 障碍：solids（非 walkable 顶面为障碍体、walkable 侧面为可踩侧边）----
	var cover_shrink := float(spec.get("cover_shrink", 1.2))
	for box: AABB in solids:
		if _ignored(box, ignore_boxes):
			continue
		var walk := walkables.has(box)
		var pad := "none" if walk else "actor"
		if walk and box.end.y <= field.floor_default + 0.06:
			continue	# 贴地面的装饰板既不是面也不是障碍
		if box.end.y <= field.floor_default + DEFAULT_STEP_HEIGHT and not walk:
			continue	# 低于台阶高度的散件：脚下支持自然越过
		field._add_obstacle_box(box, pad, true)
	for item in spec.get("obstacles", []):
		field._add_obstacle(item)
	if bool(spec.get("walls_obstacles", true)):
		var wall_h := float(spec.get("wall_thickness", 0.6))
		for w in arena.get("walls", []):
			field._add_wall(w, wall_h, bool(spec.get("walls_sight", false)))
	if bool(spec.get("cover_obstacles", true)):
		for c in arena.get("cover", []):
			var center: Vector3 = c["c"]
			var r := maxf(0.15, float(c["r"]) - cover_shrink)
			var base := float(c.get("base_y", center.y))
			var poly := _circle_poly(Vector2(center.x, center.z), r, 8)
			field._add_obstacle_poly(poly, base, base + float(c["h"]), "actor", true)

	field._index()
	field._adjacent_step = float(spec.get("adjacent_step", ADJACENT_STEP))
	field._build_adjacency()
	field.prewarm_graph(1.20, 0.38)
	return field


static func _box_set(list: Array) -> Dictionary:
	var set := {}
	for box: AABB in list:
		set[box] = true
	return set


static func _ignored(box: AABB, ignore_boxes: Array) -> bool:
	for ib: AABB in ignore_boxes:
		if ib.has_point(box.get_center()):
			return true
	return false


static func _to_poly(points: Variant) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in points:
		poly.append(p if p is Vector2 else Vector2(p[0], p[1]))
	return poly


static func _circle_poly(center: Vector2, radius: float, sides: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		poly.append(center + Vector2(cos(a), sin(a)) * radius)
	return poly


func _add_region(poly: PackedVector2Array, y0: float, y1: float, id: String) -> int:
	if poly.size() < 3:
		return -1
	poly = _ccw(poly)
	var top := maxf(y0, y1)
	var mid := Vector2.ZERO
	for v in poly:
		mid += v
	mid /= float(poly.size())
	var region := {
		"id": id if not id.is_empty() else "r%d" % regions.size(),
		"poly": poly, "y0": y0, "y1": y1,
		"normal": Vector3.UP, "center": mid,
		"aabb": _poly_aabb(poly),
	}
	regions.append(region)
	return regions.size() - 1


func _add_line(item: Dictionary) -> int:
	var a := _v2(item["a"])
	var b := _v2(item["b"])
	var dir := (b - a)
	var length := dir.length()
	if length < 0.05:
		return -1
	dir /= length
	var perp := Vector2(-dir.y, dir.x)
	var line := item.duplicate()
	line["a"] = a
	line["b"] = b
	line["y0"] = float(item.get("y0", floor_default))
	line["y1"] = float(item.get("y1", floor_default))
	line["width"] = float(item.get("width", 2.4))
	line["kind"] = String(item.get("kind", "stair"))
	line["dir"] = dir
	line["perp"] = perp
	line["len"] = length
	line["aabb"] = Rect2(a, Vector2.ZERO).expand(b).grow(line["width"] * 0.5)
	lines.append(line)
	return lines.size() - 1


func _add_obstacle_box(box: AABB, pad: String, sight: bool) -> void:
	var poly := PackedVector2Array([
		Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z),
		Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z)])
	_add_obstacle_poly(poly, box.position.y, box.end.y, pad, sight)


func _add_obstacle(item: Dictionary) -> void:
	if item.has("aabb"):
		var box: AABB = item["aabb"]
		_add_obstacle_box(box, String(item.get("pad", "actor")), bool(item.get("sight", true)))
	else:
		_add_obstacle_poly(_to_poly(item["poly"]), float(item.get("y0", 0.0)),
			float(item["y1"]), String(item.get("pad", "actor")), bool(item.get("sight", true)))


func _add_wall(w: Dictionary, thickness: float, sight: bool) -> void:
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	var base := float(w.get("base_y", 0.0))
	var top := float(w.get("h", 8.0))
	if top <= base + 0.2:
		return
	var d := (b - a)
	if d.length() < 0.05:
		return
	var perp := Vector2(-d.y, d.x).normalized() * (thickness * 0.5)
	var poly := PackedVector2Array([a - perp, b - perp, b + perp, a + perp])
	_add_obstacle_poly(poly, base, top, "actor", sight)


func _add_obstacle_poly(poly: PackedVector2Array, y0: float, y1: float, pad: String, sight: bool) -> void:
	if poly.size() < 3 or y1 - y0 < 0.05:
		return
	poly = _ccw(poly)
	obstacles.append({
		"poly": poly, "y0": y0, "y1": y1, "pad": pad, "sight": sight,
		"aabb": _poly_aabb(poly),
	})


static func _poly_aabb(poly: PackedVector2Array) -> Rect2:
	var rect := Rect2(poly[0], Vector2.ZERO)
	for i in range(1, poly.size()):
		rect = rect.expand(poly[i])
	return rect


## 统一环绕方向：XZ 平面上 _poly_margin 的内法线是 (d.y,-d.x)，
## 内部在边的右手侧（俯视 +Y 即顺时针）。shoelace > 0 说明是逆时针，翻转成顺时针。
static func _ccw(poly: PackedVector2Array) -> PackedVector2Array:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	if area > 0.0:
		var out := PackedVector2Array()
		out.resize(poly.size())
		for i in poly.size():
			out[i] = poly[poly.size() - 1 - i]
		return out
	return poly


static func _v2(p: Variant) -> Vector2:
	return p if p is Vector2 else Vector2(p[0], p[1])


# ============================================================== 索引/邻接
func _index() -> void:
	_region_grid = _grid_index(regions, func(r: Dictionary) -> Rect2: return r["aabb"])
	_obstacle_grid = _grid_index(obstacles, func(o: Dictionary) -> Rect2: return o["aabb"])


static func _grid_index(list: Array, aabb: Callable) -> Dictionary:
	var grid := {}
	for i in list.size():
		var rect: Rect2 = aabb.call(list[i])
		for gx in range(int(floor(rect.position.x / GRID_CELL)), int(floor(rect.end.x / GRID_CELL)) + 1):
			for gz in range(int(floor(rect.position.y / GRID_CELL)), int(floor(rect.end.y / GRID_CELL)) + 1):
				var key := Vector2i(gx, gz)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(i)
	return grid


func _region_candidates(p: Vector2) -> Array:
	return _region_grid.get(Vector2i(int(floor(p.x / GRID_CELL)), int(floor(p.y / GRID_CELL))), [])


func _r_obstacle_candidates(rect: Rect2) -> Array:
	var out: Array = []
	for gx in range(int(floor(rect.position.x / GRID_CELL)), int(floor(rect.end.x / GRID_CELL)) + 1):
		for gz in range(int(floor(rect.position.y / GRID_CELL)), int(floor(rect.end.y / GRID_CELL)) + 1):
			var cell: Array = _obstacle_grid.get(Vector2i(gx, gz), [])
			for i in cell:
				if not out.has(i):
					out.append(i)
	return out


func _obstacle_candidates(rect: Rect2) -> Array:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Array = _r_obstacle_candidates(rect)
		_prof_add("_obstacle_candidates", _t0)
		return _r
	return _r_obstacle_candidates(rect)


func _build_adjacency() -> void:
	_adj.clear()
	for i in regions.size():
		_adj[i] = []
	for i in regions.size():
		for j in range(i + 1, regions.size()):
			var link := _region_link(regions[i], regions[j])
			if link.is_empty():
				continue
			_adj[i].append(link)
			_adj[j].append({"to": i, "link": link["link"], "line": link.get("line", -1)})
	for li in lines.size():
		var line: Dictionary = lines[li]
		for tag in ["a", "b"]:
			var end: Vector2 = line[tag]
			var y := float(line["y0" if tag == "a" else "y1"])
			for ri in regions.size():
				var region: Dictionary = regions[ri]
				if absf(float(region["y0"]) - y) > 0.55:
					continue
				if _poly_margin(region["poly"], end) < -float(line["width"]) * 0.75 - 0.7:
					continue
				_adj[ri].append({"to": ri, "link": "line", "line": li, "tag": tag})


## 同层两区域的邻接：XZ 包围盒相接/重叠 + 共边 >0.05m + 高度差在可步范围内。
func _region_link(a: Dictionary, b: Dictionary) -> Dictionary:
	if absf(float(a["y0"]) - float(b["y0"])) > _adjacent_step:
		return {}
	var ra: Rect2 = a["aabb"]
	var rb: Rect2 = b["aabb"]
	if ra.end.x < rb.position.x - 0.02 or rb.end.x < ra.position.x - 0.02 \
		or ra.end.y < rb.position.y - 0.02 or rb.end.y < ra.position.y - 0.02:
		return {}
	# 共边判定：一轴方向边相贴，另一轴投影重叠 > 0.05（凸多边形用包围盒近似）。
	var share_x := minf(ra.end.x, rb.end.x) - maxf(ra.position.x, rb.position.x)
	var share_z := minf(ra.end.y, rb.end.y) - maxf(ra.position.y, rb.position.y)
	var touch_x := absf(ra.end.x - rb.position.x) < 0.05 or absf(rb.end.x - ra.position.x) < 0.05
	var touch_z := absf(ra.end.y - rb.position.y) < 0.05 or absf(rb.end.y - ra.position.y) < 0.05
	if (touch_x and share_z > 0.05) or (touch_z and share_x > 0.05):
		return {"to": regions.find(b), "link": "edge", "line": -1}
	return {}


# ============================================================== 查询
## 位置支撑（取最高点）：region 包含点则返回其高度；line 走廊内则插值高度。
## ceiling 之上的支撑被忽略；无支撑返回 -INF。
func _r_support_at(pos: Vector3, ceiling := INF) -> float:
	var p := Vector2(pos.x, pos.z)
	var best := -INF
	for i in _region_candidates(p):
		var region: Dictionary = regions[i]
		var h := float(region["y0"])
		if h > ceiling or h <= best:
			continue
		if _poly_contains(region["poly"], p):
			best = h
	for line in lines:
		var info := _line_info(line, p)
		if info.is_empty():
			continue
		var h := lerpf(float(line["y0"]), float(line["y1"]), float(info["t"]))
		if h <= ceiling and h > best:
			best = h
	return best


func support_at(pos: Vector3, ceiling := INF) -> float:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: float = _r_support_at(pos, ceiling)
		_prof_add("support_at", _t0)
		return _r
	return _r_support_at(pos, ceiling)


func height_at(pos: Vector3, ceiling := INF) -> float:
	var h := support_at(pos, ceiling)
	return h if h > -INF * 0.5 else floor_default


func _r_region_at(pos: Vector3) -> int:
	var p := Vector2(pos.x, pos.z)
	var best := -1
	var best_h := -INF
	for i in _region_candidates(p):
		var region: Dictionary = regions[i]
		if float(region["y0"]) > pos.y + 0.55:
			continue
		if not _poly_contains(region["poly"], p):
			continue
		if float(region["y0"]) > best_h:
			best_h = float(region["y0"])
			best = i
	return best


## 位置是否落在某条楼梯/坡道走廊内；返回 line 索引或 -1。
func region_at(pos: Vector3) -> int:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: int = _r_region_at(pos)
		_prof_add("region_at", _t0)
		return _r
	return _r_region_at(pos)


func _r_stair_at(pos: Vector3, margin := 0.0) -> int:
	var p := Vector2(pos.x, pos.z)
	for i in lines.size():
		var info := _line_info(lines[i], p, margin)
		if not info.is_empty():
			return i
	return -1


func stair_at(pos: Vector3, margin := 0.0) -> int:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: int = _r_stair_at(pos, margin)
		_prof_add("stair_at", _t0)
		return _r
	return _r_stair_at(pos, margin)


func _line_info(line: Dictionary, p: Vector2, margin := 0.0) -> Dictionary:
	var rel := p - (line["a"] as Vector2)
	var dir: Vector2 = line["dir"]
	var perp: Vector2 = line["perp"]
	var t := rel.dot(dir)
	var s := rel.dot(perp)
	if t < -margin or t > float(line["len"]) + margin:
		return {}
	if absf(s) > float(line["width"]) * 0.5 + margin:
		return {}
	return {"t": clampf(t / float(line["len"]), 0.0, 1.0), "s": s}


func line_height(line: Dictionary, p: Vector2) -> float:
	var info := _line_info(line, p, INF)
	var t := 0.0 if info.is_empty() else float(info["t"])
	return lerpf(float(line["y0"]), float(line["y1"]), t)


## 凸多边形的符号距离：>0 在内部，<0 在外（返回离边的距离，未归一化误差可接受）。
static func _poly_margin(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := b - a
		var n := Vector2(d.y, -d.x).normalized()
		best = minf(best, (p - a).dot(n))
	return best


static func _poly_contains(poly: PackedVector2Array, p: Vector2) -> bool:
	return _poly_margin(poly, p) >= 0.0


## 凸多边形的精确欧氏有符号距离：<0 在内部，>=0 在外部（圆角 Minkowski 膨胀用）。
static func _poly_signed_dist(poly: PackedVector2Array, p: Vector2) -> float:
	var margin := _poly_margin(poly, p)
	if margin >= 0.0:
		return -margin
	var best_d2 := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := b - a
		var t := clampf((p - a).dot(d) / maxf(d.length_squared(), 1e-6), 0.0, 1.0)
		var q := a + d * t
		best_d2 = minf(best_d2, q.distance_squared_to(p))
	return sqrt(best_d2)


func _nearest_on_poly(poly: PackedVector2Array, p: Vector2) -> Vector2:
	var best := p
	var dist := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := b - a
		var t := clampf((p - a).dot(d) / maxf(d.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + d * t
		var ds := q.distance_squared_to(p)
		if ds < dist:
			dist = ds
			best = q
	return best


## 障碍阻挡判定：feet 高度 + 体高内与棱柱相交；pad=actor 按精确欧氏圆半径膨胀（圆角）。
func _r_blocked_at(pos: Vector3, radius: float, step_height: float) -> bool:
	var p := Vector2(pos.x, pos.z)
	var head := pos.y + STANCE_HEIGHT
	for i in _obstacle_candidates(Rect2(p, Vector2.ZERO).grow(radius + 0.1)):
		var o: Dictionary = obstacles[i]
		if pos.y >= float(o["y1"]) - step_height or head <= float(o["y0"]) + 0.02:
			continue
		var pad := radius if String(o["pad"]) == "actor" else 0.0
		if _poly_signed_dist(o["poly"], p) < pad:
			return true
	return false


## 竖直圆柱净空（旧 _duelist_body_clear 的元信息版）。
func _blocked_at(pos: Vector3, radius: float, step_height: float) -> bool:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: bool = _r_blocked_at(pos, radius, step_height)
		_prof_add("_blocked_at", _t0)
		return _r
	return _r_blocked_at(pos, radius, step_height)


func _r_column_clear(at: Vector3, radius: float, bottom: float, top: float) -> bool:
	var p := Vector2(at.x, at.z)
	for i in _obstacle_candidates(Rect2(p, Vector2.ZERO).grow(radius + 0.1)):
		var o: Dictionary = obstacles[i]
		if at.y + top <= float(o["y0"]) or at.y + bottom >= float(o["y1"]):
			continue
		var pad := radius if String(o["pad"]) == "actor" else 0.0
		if _poly_signed_dist(o["poly"], p) < pad:
			return false
	return true


func column_clear(at: Vector3, radius: float, bottom: float, top: float) -> bool:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: bool = _r_column_clear(at, radius, bottom, top)
		_prof_add("column_clear", _t0)
		return _r
	return _r_column_clear(at, radius, bottom, top)


func can_stand(pos: Vector3, radius: float, step_height := DEFAULT_STEP_HEIGHT) -> bool:
	var support := support_at(pos, pos.y + step_height + 0.05)
	if support < -INF * 0.5 or absf(support - pos.y) > 0.5:
		return false
	return not _blocked_at(Vector3(pos.x, support, pos.z), radius, step_height)


## 采样路径（0.2–0.3u）只查元信息：每步必须有支撑、升程 ≤ step_height、
## 下降 > max_drop 视为边缘；棱柱上才有意义的阻挡在侧面上。
## upper != null 时附加一截「上半身圆柱」净空（{radius, bottom, top}，
## 相对支撑面高度），复刻旧 duelist 的体积分段检查。
func _r_move_supported(from: Vector3, to: Vector3, radius: float,
		step_height := DEFAULT_STEP_HEIGHT, max_drop := 0.6,
		upper: Dictionary = {}) -> Vector3:
	var offset := (to - from).slide(Vector3.UP)
	var steps := maxi(1, ceili(offset.length() / SAMPLE_STEP))
	var pos := from
	for i in range(1, steps + 1):
		var target := from + offset * (float(i) / steps)
		var support := support_at(target, pos.y + step_height)
		if support < -INF * 0.5:
			break
		target.y = support
		if pos.y - support > max_drop:
			break
		if _blocked_at(target, radius, step_height):
			break
		if not upper.is_empty() and not column_clear(target, float(upper["radius"]),
				float(upper["bottom"]), float(upper["top"])):
			break
		pos = target
	return pos


## move_supported 的判定版：整段都可走才算通（供 can_strike / segment 决策）。
func move_supported(from: Vector3, to: Vector3, radius: float,
		step_height := DEFAULT_STEP_HEIGHT, max_drop := 0.6,
		upper: Dictionary = {}) -> Vector3:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Vector3 = _r_move_supported(from, to, radius, step_height, max_drop, upper)
		_prof_add("move_supported", _t0)
		return _r
	return _r_move_supported(from, to, radius, step_height, max_drop, upper)


func move_clear(from: Vector3, to: Vector3, radius: float,
		step_height := DEFAULT_STEP_HEIGHT, max_drop := 0.6,
		upper: Dictionary = {}) -> bool:
	var landed := move_supported(from, to, radius, step_height, max_drop, upper)
	return landed.slide(Vector3.UP).distance_squared_to((to as Vector3).slide(Vector3.UP)) < 0.04 \
		and absf(landed.y - to.y) <= step_height + 0.15


## 若起点被推入障碍膨胀区或悬空边缘，沿最短脱离方向推回合法站立点。
func depenetrate(pos: Vector3, radius: float, step_height := DEFAULT_STEP_HEIGHT,
		upper: Dictionary = {}) -> Vector3:
	var sup0 := support_at(pos, pos.y + step_height)
	var cur := Vector3(pos.x, sup0 if sup0 > -INF * 0.5 else pos.y, pos.z)
	if sup0 > -INF * 0.5 and not _blocked_at(cur, radius, step_height) \
			and (upper.is_empty() or column_clear(cur, float(upper["radius"]),
				float(upper["bottom"]), float(upper["top"]))):
		return cur
	var p := Vector2(cur.x, cur.z)
	var head := cur.y + STANCE_HEIGHT
	for i in _obstacle_candidates(Rect2(p, Vector2.ZERO).grow(radius + 0.5)):
		var o: Dictionary = obstacles[i]
		if cur.y >= float(o["y1"]) - step_height or head <= float(o["y0"]) + 0.02:
			continue
		var pad := radius if String(o["pad"]) == "actor" else 0.0
		var sd := _poly_signed_dist(o["poly"], p)
		if sd < pad:
			var q := _nearest_on_poly(o["poly"], p)
			var out_n := (p - q)
			if out_n.length_squared() > 1e-6:
				p = q + out_n.normalized() * (pad + 0.03)
			else:
				# 在多边形内部：找最近边外法线推出
				var poly: PackedVector2Array = o["poly"]
				var best_d := INF
				var best_n := Vector2.RIGHT
				for ei in poly.size():
					var ea := poly[ei]
					var eb := poly[(ei + 1) % poly.size()]
					var ed := eb - ea
					var n := Vector2(-ed.y, ed.x).normalized()
					var dist_e := (p - ea).dot(-n)
					if dist_e >= 0.0 and dist_e < best_d:
						best_d = dist_e
						best_n = n
				p += best_n * (best_d + pad + 0.03)
	var cand := Vector3(p.x, cur.y, p.y)
	var s_cand := support_at(cand, cur.y + step_height)
	if s_cand > -INF * 0.5:
		cand.y = s_cand
		if not _blocked_at(cand, radius, step_height) and (upper.is_empty()
				or column_clear(cand, float(upper["radius"]), float(upper["bottom"]), float(upper["top"]))):
			return cand
	# 兜底：8 方向小半径采样最近可站点
	for r_off in [0.35, 0.75, 1.35]:
		for k in 8:
			var ang := TAU * float(k) / 8.0
			var probe := Vector3(pos.x + cos(ang) * r_off, pos.y, pos.z + sin(ang) * r_off)
			var sp := support_at(probe, pos.y + step_height)
			if sp < -INF * 0.5:
				continue
			probe.y = sp
			if not _blocked_at(probe, radius, step_height) and (upper.is_empty()
					or column_clear(probe, float(upper["radius"]), float(upper["bottom"]), float(upper["top"]))):
				return probe
	return pos


func _step_valid(cur: Vector3, target_xz: Vector3, radius: float,
		step_height: float, max_drop: float, upper: Dictionary) -> Vector3:
	var support := support_at(target_xz, cur.y + step_height)
	if support < -INF * 0.5 or cur.y - support > max_drop:
		return Vector3.INF
	var cand := Vector3(target_xz.x, support, target_xz.z)
	if _blocked_at(cand, radius, step_height):
		return Vector3.INF
	if not upper.is_empty() and not column_clear(cand, float(upper["radius"]),
			float(upper["bottom"]), float(upper["top"])):
		return Vector3.INF
	return cand


## 带贴边滑行的地面移动：遇障或区域边缘时沿切向滑行，避免直角卡死。
func move_slide(from: Vector3, to: Vector3, radius: float,
		step_height := DEFAULT_STEP_HEIGHT, max_drop := 0.6,
		upper: Dictionary = {}) -> Vector3:
	var cur := depenetrate(from, radius, step_height, upper)
	var offset := (to - cur).slide(Vector3.UP)
	var total := offset.length()
	if total < 1e-4:
		return cur
	var dir := offset / total
	var steps := maxi(1, ceili(total / SAMPLE_STEP))
	var step_len := total / float(steps)
	for _i in steps:
		var cand := _step_valid(cur, cur + dir * step_len, radius, step_height, max_drop, upper)
		if cand.is_finite():
			cur = cand
			continue
		var slid := false
		for ang in [0.45, -0.45, 0.90, -0.90, 1.30, -1.30]:
			var sdir := dir.rotated(Vector3.UP, ang)
			var sc := _step_valid(cur, cur + sdir * (step_len * 0.85),
				radius, step_height, max_drop, upper)
			if sc.is_finite():
				cur = sc
				slid = true
				break
		if not slid:
			break
	return cur


## 支撑面法线：line 上为坡面法线，其余为 UP。
func normal_at(pos: Vector3) -> Vector3:
	var p := Vector2(pos.x, pos.z)
	for line in lines:
		if _line_info(line, p, 0.3).is_empty():
			continue
		var dir: Vector2 = line["dir"]
		var rise := float(line["y1"]) - float(line["y0"])
		return Vector3(-dir.x * rise, float(line["len"]), -dir.y * rise).normalized()
	return Vector3.UP


## 搁置高度（跌倒/摆放）：可走支撑优先；没有支撑时允许落在障碍棱柱顶面上，
## 复刻旧 floor_at「任何实体顶面都能接住」的行为。
func rest_at(pos: Vector3, ceiling: float) -> float:
	var walk := support_at(pos, ceiling)
	if walk > -INF * 0.5:
		return walk
	var p := Vector2(pos.x, pos.z)
	var best := -INF
	for i in _obstacle_candidates(Rect2(p, Vector2.ZERO).grow(0.05)):
		var o: Dictionary = obstacles[i]
		var h := float(o["y1"])
		if h > ceiling or h <= best:
			continue
		if _poly_margin(o["poly"], p) >= 0.0:
			best = h
	return best


## 沿算好的路线前进 pull 距离后的目标点（route_point 的 flowing 模式）。
func _r_route_pull(from: Vector3, goal: Vector3, radius: float, pull: float,
		step_height := DEFAULT_STEP_HEIGHT, upper: Dictionary = {}) -> Vector3:
	var pts := path(from, goal, radius, step_height, upper)
	if pts.is_empty():
		return from
	var anchor := from
	var left := pull
	for p in pts:
		var seg: float = (p - anchor).slide(Vector3.UP).length()
		if seg > left:
			return anchor + (p - anchor).slide(Vector3.UP).normalized() * left
		left -= seg
		anchor = p
	return pts[-1]


## 视线/刀线：只看带 sight 的障碍棱柱是否与线段相交（XZ 射线 × Y 区间）。
func route_pull(from: Vector3, goal: Vector3, radius: float, pull: float,
		step_height := DEFAULT_STEP_HEIGHT, upper: Dictionary = {}) -> Vector3:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Vector3 = _r_route_pull(from, goal, radius, pull, step_height, upper)
		_prof_add("route_pull", _t0)
		return _r
	return _r_route_pull(from, goal, radius, pull, step_height, upper)


func _r_segment_clear(a: Vector3, b: Vector3) -> bool:
	for i in _obstacle_candidates(Rect2(
			Vector2(minf(a.x, b.x), minf(a.z, b.z)),
			Vector2(absf(b.x - a.x), absf(b.z - a.z))).grow(0.5)):
		var o: Dictionary = obstacles[i]
		if not bool(o["sight"]):
			continue
		if _segment_hits_prism(a, b, o):
			return false
	return true


func segment_clear(a: Vector3, b: Vector3) -> bool:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: bool = _r_segment_clear(a, b)
		_prof_add("segment_clear", _t0)
		return _r
	return _r_segment_clear(a, b)


func _segment_hits_prism(a: Vector3, b: Vector3, o: Dictionary) -> bool:
	var y0 := float(o["y0"])
	var y1 := float(o["y1"])
	var lo := minf(a.y, b.y)
	var hi := maxf(a.y, b.y)
	if hi <= y0 + 0.02 or lo >= y1 - 0.02:
		return false
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dist := d.length()
	var pa := Vector2(a.x, a.z)
	var poly: PackedVector2Array = o["poly"]
	# 与凸多边形做 2D slab 射线（Cyrus-Beck）。
	var t0 := 0.0
	var t1 := 1.0
	if dist < 0.0001:
		return _poly_contains(poly, pa)
	var d2 := Vector2(d.x, d.z)
	for i in poly.size():
		var e0 := poly[i]
		var e1 := poly[(i + 1) % poly.size()]
		var ed := e1 - e0
		var n := Vector2(ed.y, -ed.x).normalized()
		var num := (e0 - pa).dot(n)
		var den := d2.dot(n)
		if absf(den) < 0.00001:
			if num < 0.0:
				return false	# 平行且在外侧
			continue
		var t := num / den
		if den < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return false
	if t0 > t1 or t1 < 0.0 or t0 > 1.0:
		return false
	var tt := clampf(maxf(t0, 0.0), 0.0, 1.0)
	var yy := a.y + (b.y - a.y) * tt
	return yy > y0 + 0.01 and yy < y1 - 0.01


# ============================================================== 寻路
## _detour 工作预算：绕行的递归分支因子是 4 角 × 6 层（最坏 ~4^6 次
## move_supported 扫描，实测病态单调用 125–173ms → 帧尖峰）。每次 path()
## 重置共享预算；耗尽即放弃绕行，退回「走得到的最远点」——追击行为不退化。
const DETOUR_BUDGET := 22            # 一次 path() 允许的绕行腿验证次数
const DETOUR_DEADLINE_US := 6000     # 兜底墙钟上限（µs）
var _detour_budget := 0
var _detour_deadline := 0

## path() 结果缓存：key = (起/终点量化到 0.5u 格, 半径×2, 是否带 upper)。
## 与 arc_encounter 的 0.6u/0.12s 寻路点复用同粒度，预期命中 ~75%+。
const PATH_CACHE_CELL := 0.5
const PATH_CACHE_MAX := 96
var _path_cache := {}


func _path_cache_key(from: Vector3, goal: Vector3, radius: float,
		upper: Dictionary, step_height: float) -> Array:
	return [int(floor(from.x / PATH_CACHE_CELL)), int(floor(from.y * 0.5)), int(floor(from.z / PATH_CACHE_CELL)),
		int(floor(goal.x / PATH_CACHE_CELL)), int(floor(goal.y * 0.5)), int(floor(goal.z / PATH_CACHE_CELL)),
		int(round(radius * 20.0)), not upper.is_empty(), int(round(step_height * 20.0))]


## 返回 from→goal 的 3D 路点（不含 from；含折线途径点 + 拉直后的终点）。
## 不可达返回 []；goal 落在不可走位置时先投影回可走面。
func _r_path(from: Vector3, goal: Vector3, radius: float,
		step_height := DEFAULT_STEP_HEIGHT, upper: Dictionary = {}) -> Array:
	var key := _path_cache_key(from, goal, radius, upper, step_height)
	if _path_cache.has(key):
		return _path_cache[key]
	_detour_budget = DETOUR_BUDGET
	_detour_deadline = Time.get_ticks_usec() + DETOUR_DEADLINE_US
	var out: Array = _path_uncached(from, goal, radius, step_height, upper)
	if _path_cache.size() >= PATH_CACHE_MAX:
		_path_cache.clear()
	_path_cache[key] = out
	return out


var _graphs := {}   # gkey -> {nodes: Array[Dictionary], r_cells: Dictionary, l_cells: Dictionary}
const GRAPH_CELL := 1.6


func prewarm_graph(radius: float, step_height := DEFAULT_STEP_HEIGHT, upper: Dictionary = {}) -> void:
	_get_graph(radius, step_height, upper)


func _get_graph(radius: float, step_height: float, upper: Dictionary) -> Dictionary:
	var gkey := "%d|%d|%d" % [int(round(radius * 20.0)), int(round(step_height * 20.0)),
		1 if not upper.is_empty() else 0]
	if _graphs.has(gkey):
		return _graphs[gkey]
	var nodes: Array = []
	var r_cells: Dictionary = {}   # ri -> {Vector2i: node_id}
	var l_cells: Dictionary = {}   # li -> Array[node_id]
	var has_upper := not upper.is_empty()
	var u_rad := float(upper.get("radius", 0.0))
	var u_bot := float(upper.get("bottom", 0.0))
	var u_top := float(upper.get("top", 0.0))

	# 1. 每个 region 采样网格点
	for ri in regions.size():
		var region: Dictionary = regions[ri]
		var aabb: Rect2 = region["aabb"]
		var ry := float(region["y0"])
		var poly: PackedVector2Array = region["poly"]
		var grid := {}
		var gx0 := int(floor(aabb.position.x / GRAPH_CELL))
		var gx1 := int(ceil(aabb.end.x / GRAPH_CELL))
		var gz0 := int(floor(aabb.position.y / GRAPH_CELL))
		var gz1 := int(ceil(aabb.end.y / GRAPH_CELL))
		for gx in range(gx0, gx1 + 1):
			for gz in range(gz0, gz1 + 1):
				var p2 := Vector2((float(gx) + 0.5) * GRAPH_CELL, (float(gz) + 0.5) * GRAPH_CELL)
				if not _poly_contains(poly, p2):
					continue
				var p3 := Vector3(p2.x, ry, p2.y)
				if _blocked_at(p3, radius, step_height):
					continue
				if has_upper and not column_clear(p3, u_rad, u_bot, u_top):
					continue
				var nid := nodes.size()
				nodes.append({"pos": p3, "ri": ri, "li": -1, "nbrs": []})
				grid[Vector2i(gx, gz)] = nid
		if grid.is_empty():
			var c2: Vector2 = region["center"]
			var c3 := Vector3(c2.x, ry, c2.y)
			if not _blocked_at(c3, radius, step_height) and (not has_upper or column_clear(c3, u_rad, u_bot, u_top)):
				var nid := nodes.size()
				nodes.append({"pos": c3, "ri": ri, "li": -1, "nbrs": []})
				grid[Vector2i(0, 0)] = nid
		r_cells[ri] = grid
		# 同 region 8 邻接（对角线要求两侧正交邻点都在，杜绝切角）
		for k: Vector2i in grid:
			var id_a: int = grid[k]
			var pa: Vector3 = nodes[id_a]["pos"]
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
				var nk := k + d
				if not grid.has(nk):
					continue
				if d.x != 0 and d.y != 0:
					if not (grid.has(k + Vector2i(d.x, 0)) and grid.has(k + Vector2i(0, d.y))):
						continue
				var id_b: int = grid[nk]
				var pb: Vector3 = nodes[id_b]["pos"]
				var mid := (pa + pb) * 0.5
				var ok := not _blocked_at(mid, radius, step_height) and (not has_upper or column_clear(mid, u_rad, u_bot, u_top))
				if ok and d.x != 0 and d.y != 0:
					var q1 := pa.lerp(pb, 0.25)
					var q3 := pa.lerp(pb, 0.75)
					ok = not _blocked_at(q1, radius, step_height) and not _blocked_at(q3, radius, step_height)
					if ok and has_upper:
						ok = column_clear(q1, u_rad, u_bot, u_top) and column_clear(q3, u_rad, u_bot, u_top)
				if ok:
					var cost := pa.distance_to(pb)
					(nodes[id_a]["nbrs"] as Array).append({"to": id_b, "cost": cost})
					(nodes[id_b]["nbrs"] as Array).append({"to": id_a, "cost": cost})

	# 2. 跨同层相邻 region 连接
	for ri in regions.size():
		var ga: Dictionary = r_cells.get(ri, {})
		if ga.is_empty():
			continue
		var ra: Rect2 = (regions[ri]["aabb"] as Rect2).grow(GRAPH_CELL * 2.0)
		for e in _adj.get(ri, []):
			if String(e["link"]) != "edge":
				continue
			var rj := int(e["to"])
			if rj <= ri:
				continue
			var gb: Dictionary = r_cells.get(rj, {})
			if gb.is_empty():
				continue
			var rb: Rect2 = (regions[rj]["aabb"] as Rect2).grow(GRAPH_CELL * 2.0)
			var overlap := ra.intersection(rb)
			if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
				continue
			var ca_near: Array = []
			for ka in ga:
				var ida: int = ga[ka]
				var pa: Vector3 = nodes[ida]["pos"]
				if overlap.has_point(Vector2(pa.x, pa.z)):
					ca_near.append(ida)
			var cb_near: Array = []
			for kb in gb:
				var idb: int = gb[kb]
				var pb: Vector3 = nodes[idb]["pos"]
				if overlap.has_point(Vector2(pb.x, pb.z)):
					cb_near.append(idb)
			var max_d2 := GRAPH_CELL * GRAPH_CELL * 3.5
			for ida: int in ca_near:
				var pa: Vector3 = nodes[ida]["pos"]
				for idb: int in cb_near:
					var pb: Vector3 = nodes[idb]["pos"]
					if pa.distance_squared_to(pb) <= max_d2:
						if move_clear(pa, pb, radius, step_height, 0.6, upper):
							var cost := pa.distance_to(pb)
							(nodes[ida]["nbrs"] as Array).append({"to": idb, "cost": cost})
							(nodes[idb]["nbrs"] as Array).append({"to": ida, "cost": cost})

	# 3. 楼梯/坡道 line 采样点与端点连接
	for li in lines.size():
		var line: Dictionary = lines[li]
		var steps := maxi(2, ceili(float(line["len"]) / GRAPH_CELL))
		var l_ids: Array = []
		for si in steps + 1:
			var t := float(si) / float(steps)
			var p2 := (line["a"] as Vector2).lerp(line["b"] as Vector2, t)
			var p3 := Vector3(p2.x, lerpf(float(line["y0"]), float(line["y1"]), t), p2.y)
			if _blocked_at(p3, radius, step_height):
				continue
			if has_upper and not column_clear(p3, u_rad, u_bot, u_top):
				continue
			var nid := nodes.size()
			nodes.append({"pos": p3, "ri": -1, "li": li, "nbrs": []})
			l_ids.append(nid)
		for k in range(1, l_ids.size()):
			var ia: int = l_ids[k - 1]
			var ib: int = l_ids[k]
			var pa: Vector3 = nodes[ia]["pos"]
			var pb: Vector3 = nodes[ib]["pos"]
			var cost := pa.distance_to(pb) * 1.2
			(nodes[ia]["nbrs"] as Array).append({"to": ib, "cost": cost})
			(nodes[ib]["nbrs"] as Array).append({"to": ia, "cost": cost})
		l_cells[li] = l_ids
		# 将 line 端点与附近同层 region 节点连接
		for end_id in ([l_ids[0], l_ids[-1]] if not l_ids.is_empty() else []):
			var pe: Vector3 = nodes[int(end_id)]["pos"]
			for ri in regions.size():
				if absf(float(regions[ri]["y0"]) - pe.y) > 0.65:
					continue
				var ga: Dictionary = r_cells.get(ri, {})
				var best_r := -1
				var best_d := 16.0
				for ka in ga:
					var idr: int = ga[ka]
					var pr: Vector3 = nodes[idr]["pos"]
					var d2 := pe.distance_squared_to(pr)
					if d2 < best_d and move_clear(pe, pr, radius, step_height, 0.6, upper):
						best_d = d2
						best_r = idr
				if best_r >= 0:
					var cost := sqrt(best_d)
					(nodes[int(end_id)]["nbrs"] as Array).append({"to": best_r, "cost": cost})
					(nodes[best_r]["nbrs"] as Array).append({"to": int(end_id), "cost": cost})

	var graph := {"nodes": nodes, "r_cells": r_cells, "l_cells": l_cells}
	_graphs[gkey] = graph
	return graph


func _graph_anchors(graph: Dictionary, pos: Vector3, radius: float,
		step_height: float, upper: Dictionary) -> Array:
	var nodes: Array = graph["nodes"]
	var cands: Array = []
	for i in nodes.size():
		var p: Vector3 = nodes[i]["pos"]
		if absf(p.y - pos.y) > 1.35:
			continue
		var d2 := p.distance_squared_to(pos)
		if d2 <= 36.0:
			cands.append({"id": i, "d2": d2})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["d2"]) < float(b["d2"]))
	var out: Array = []
	for c in cands.slice(0, mini(8, cands.size())):
		var nid := int(c["id"])
		if move_clear(pos, nodes[nid]["pos"], radius, step_height, 0.6, upper):
			out.append(nid)
			if out.size() >= 3:
				break
	if out.is_empty() and not cands.is_empty():
		out.append(int(cands[0]["id"]))
	return out


func _graph_path(from: Vector3, goal: Vector3, radius: float,
		step_height: float, upper: Dictionary) -> Array:
	var graph := _get_graph(radius, step_height, upper)
	var nodes: Array = graph["nodes"]
	if nodes.is_empty():
		return []
	var start_pos := depenetrate(from, radius, step_height, upper)
	var goal_pos := depenetrate(goal, radius, step_height, upper)
	var starts := _graph_anchors(graph, start_pos, radius, step_height, upper)
	var goals := _graph_anchors(graph, goal_pos, radius, step_height, upper)
	if starts.is_empty() or goals.is_empty():
		return []
	var goal_set := {}
	for g in goals:
		goal_set[int(g)] = true
	var g_score := {}
	var parent := {}
	var open: Array = []
	for s in starts:
		var sid := int(s)
		var d := start_pos.distance_to(nodes[sid]["pos"])
		g_score[sid] = d
		parent[sid] = -1
		open.append({"id": sid, "f": d + (nodes[sid]["pos"] as Vector3).distance_to(goal_pos)})
	var closed := {}
	var hit_goal := -1
	while not open.is_empty():
		var bi := 0
		var bf := float(open[0]["f"])
		for i in range(1, open.size()):
			var f := float(open[i]["f"])
			if f < bf:
				bf = f
				bi = i
		var cur: Dictionary = open[bi]
		open.remove_at(bi)
		var cid := int(cur["id"])
		if closed.has(cid):
			continue
		closed[cid] = true
		if goal_set.has(cid):
			hit_goal = cid
			break
		var cg := float(g_score[cid])
		for e in nodes[cid]["nbrs"]:
			var nid := int(e["to"])
			if closed.has(nid):
				continue
			var ng := cg + float(e["cost"])
			if g_score.has(nid) and float(g_score[nid]) <= ng:
				continue
			g_score[nid] = ng
			parent[nid] = cid
			open.append({"id": nid, "f": ng + (nodes[nid]["pos"] as Vector3).distance_to(goal_pos)})
	if hit_goal < 0:
		return []
	var raw: Array = []
	var k := hit_goal
	while k >= 0:
		raw.push_front(nodes[k]["pos"])
		k = int(parent.get(k, -1))
	raw.append(goal_pos)
	return raw


func _path_uncached(from: Vector3, goal: Vector3, radius: float,
		step_height := DEFAULT_STEP_HEIGHT, upper: Dictionary = {}) -> Array:
	var start := depenetrate(from, radius, step_height, upper)
	var target := depenetrate(goal, radius, step_height, upper)
	if move_clear(start, target, radius, step_height, 0.6, upper):
		return [target]
	var route := _graph_path(start, target, radius, step_height, upper)
	if route.is_empty():
		route = _route(start, target, radius, step_height, upper)
	if route.is_empty():
		var landed := move_slide(start, target, radius, step_height, 0.6, upper)
		if (landed - start).slide(Vector3.UP).length() > 0.2:
			return [landed]
		return []
	var pts: Array = route.duplicate()
	# 贪心拉直：从最远处往回找第一个整段可走到的点。
	var out: Array = []
	var anchor := start
	var i := 0
	while i < pts.size():
		var pick := -1
		for j in range(mini(pts.size() - 1, i + 6), i - 1, -1):
			if move_clear(anchor, pts[j], radius, step_height, 0.6, upper):
				pick = j
				break
		if pick < 0:
			pick = i
		out.append(pts[pick])
		anchor = pts[pick]
		i = pick + 1
	return out


## 下一个可走到的路点：选路径上最远一个 move_supported 能直达的点。
func path(from: Vector3, goal: Vector3, radius: float,
		step_height := DEFAULT_STEP_HEIGHT, upper: Dictionary = {}) -> Array:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Array = _r_path(from, goal, radius, step_height, upper)
		_prof_add("path", _t0)
		return _r
	return _r_path(from, goal, radius, step_height, upper)


func _r_next_waypoint(from: Vector3, goal: Vector3, radius: float,
		step_height := DEFAULT_STEP_HEIGHT, pull := 0.0, upper: Dictionary = {}) -> Vector3:
	var heading := (goal - from).slide(Vector3.UP)
	if pull > 0.0 and absf(goal.y - from.y) <= step_height + 0.15 and heading.length() > pull:
		var probe := from + heading.limit_length(pull)
		var reach := move_supported(from, probe, radius, step_height, 0.6, upper)
		if (reach - probe).slide(Vector3.UP).length() < 0.06 and absf(reach.y - probe.y) <= step_height + 0.15:
			return probe
	var pts := path(from, goal, radius, step_height, upper)
	if pts.is_empty():
		return from
	for j in range(pts.size() - 1, -1, -1):
		var p: Vector3 = pts[j]
		if (p - from).slide(Vector3.UP).length_squared() < 0.09 and absf(p.y - from.y) <= step_height + 0.15:
			continue
		var reach := move_supported(from, p, radius, step_height, 0.6, upper)
		if (reach - p).slide(Vector3.UP).length() < 0.06 and absf(reach.y - p.y) <= step_height + 0.15:
			return p
	for p: Vector3 in pts:
		if (p - from).slide(Vector3.UP).length_squared() >= 0.09 or absf(p.y - from.y) > step_height + 0.15:
			return p
	return pts[-1]


## 把点投影到最近的可走面（对站在障碍顶/空中的目标做落点）。
func next_waypoint(from: Vector3, goal: Vector3, radius: float,
		step_height := DEFAULT_STEP_HEIGHT, pull := 0.0, upper: Dictionary = {}) -> Vector3:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Vector3 = _r_next_waypoint(from, goal, radius, step_height, pull, upper)
		_prof_add("next_waypoint", _t0)
		return _r
	return _r_next_waypoint(from, goal, radius, step_height, pull, upper)


func _r_near_point(pos: Vector3, search_radius := 6.0) -> Vector3:
	var p := Vector2(pos.x, pos.z)
	var best := pos
	var dist := INF
	var best_h := -INF
	for i in regions.size():
		var region: Dictionary = regions[i]
		var q := _nearest_on_poly(region["poly"], p)
		var cand := Vector3(q.x, float(region["y0"]), q.y)
		var d := (cand - pos).length()
		if d < dist:
			dist = d
			best = cand
			best_h = float(region["y0"])
	for line in lines:
		var info := _line_info(line, p, 6.0)
		if info.is_empty():
			continue
		var dir: Vector2 = line["dir"]
		var perp: Vector2 = line["perp"]
		var a: Vector2 = line["a"]
		var t := clampf((p - a).dot(dir), 0.0, float(line["len"]))
		var s := clampf((p - a).dot(perp), -float(line["width"]) * 0.5, float(line["width"]) * 0.5)
		var q := a + dir * t + perp * s
		var h := lerpf(float(line["y0"]), float(line["y1"]), t / float(line["len"]))
		var cand := Vector3(q.x, h, q.y)
		var d := (cand - pos).length()
		if d < dist:
			dist = d
			best = cand
			best_h = h
	# 范围检查：太远就放弃
	return best if dist <= search_radius else pos


# ---------------- 路由内部 ----------------
func near_point(pos: Vector3, search_radius := 6.0) -> Vector3:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Vector3 = _r_near_point(pos, search_radius)
		_prof_add("near_point", _t0)
		return _r
	return _r_near_point(pos, search_radius)


func _r_route(from: Vector3, goal: Vector3, radius: float, step_height: float,
		upper: Dictionary = {}) -> Array:
	var from_node := _node_for(from, radius)
	var goal_node := _node_for(goal, radius)
	if from_node.is_empty() or goal_node.is_empty():
		return []
	# 直接可走则不需要图搜索。
	if from_node["kind"] == "region" and goal_node["kind"] == "region" \
		and int(from_node["ref"]) == int(goal_node["ref"]):
		return _detour(from, goal, radius, step_height, upper, 0)
	var seq := _astar(from_node, goal_node)
	if seq.is_empty():
		return []
	var pts: Array = []
	var cursor := from
	for k in range(1, seq.size()):
		var a_node: Dictionary = seq[k - 1]
		var b_node: Dictionary = seq[k]
		var is_goal := _node_key(b_node) == _node_key(goal_node)
		if String(a_node["kind"]) == "line":
			# 已在 line 上：爬升段算走完，落点取 line 端或 goal 在线上的投影。
			if is_goal:
				var exit := _line_exit_for_goal(b_node, goal)
				if (exit - cursor).slide(Vector3.UP).length() > 0.05:
					pts.append(exit)
					cursor = exit
			else:
				var exit := _line_exit_for_region(a_node, b_node)
				if (exit - cursor).slide(Vector3.UP).length() > 0.05:
					pts.append(exit)
					cursor = exit
			continue
		var link: Dictionary = b_node.get("via", {})
		if String(link.get("link", "")) == "line":
			# region → line：从 via.tag 端进入，走到另一端（或 goal 的投影）。
			var line: Dictionary = lines[int(link["line"])]
			var entry := _line_point3(line, String(link.get("tag", "a")))
			if (entry - cursor).slide(Vector3.UP).length() > 0.05:
				pts.append_array(_detour(cursor, entry, radius, step_height, upper, 0))
				if not pts.is_empty():
					cursor = pts[-1]
			var exit := _line_exit_for_goal(b_node, goal) if is_goal else \
				_line_point3(line, "b" if String(link.get("tag", "a")) == "a" else "a")
			pts.append(exit)
			cursor = exit
		else:
			# 同层 portal：两侧质心中点投回两区域交集。
			var cross := _portal_point(a_node, b_node)
			var detour := _detour(cursor, cross, radius, step_height, upper, 0)
			pts.append_array(detour)
			cursor = pts[-1] if not pts.is_empty() else cross
	var tail := _detour(cursor, goal, radius, step_height, upper, 0)
	pts.append_array(tail)
	return pts


## line 落到某 region 的出口端：取高度与 region 匹配的那端。
func _route(from: Vector3, goal: Vector3, radius: float, step_height: float,
		upper: Dictionary = {}) -> Array:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Array = _r_route(from, goal, radius, step_height, upper)
		_prof_add("_route", _t0)
		return _r
	return _r_route(from, goal, radius, step_height, upper)


func _line_exit_for_region(line_node: Dictionary, region_node: Dictionary) -> Vector3:
	var line: Dictionary = lines[int(line_node["ref"])]
	var region: Dictionary = regions[int(region_node["ref"])]
	var ry := float(region["y0"])
	if absf(ry - float(line["y0"])) <= 0.55:
		return _line_point3(line, "a")
	if absf(ry - float(line["y1"])) <= 0.55:
		return _line_point3(line, "b")
	# 两端都匹配不上时选离区域中心近的一端。
	var c: Vector2 = region["center"]
	var pa := _line_point3(line, "a")
	var pb := _line_point3(line, "b")
	return pa if Vector2(pa.x - c.x, pa.z - c.y).length_squared() \
		< Vector2(pb.x - c.x, pb.z - c.y).length_squared() else pb


## goal 落在线上时的出口：把 goal 横向投到 line 上再取插值高度。
func _line_exit_for_goal(line_node: Dictionary, goal: Vector3) -> Vector3:
	var line: Dictionary = lines[int(line_node["ref"])]
	var p := Vector2(goal.x, goal.z)
	var a: Vector2 = line["a"]
	var t := clampf((p - a).dot(line["dir"]) / float(line["len"]), 0.0, 1.0)
	var q := a + (line["dir"] as Vector2) * (t * float(line["len"]))
	return Vector3(q.x, lerpf(float(line["y0"]), float(line["y1"]), t), q.y)


func _line_point3(line: Dictionary, tag: String) -> Vector3:
	var p: Vector2 = line[tag]
	return Vector3(p.x, float(line["y0" if tag == "a" else "y1"]), p.y)


func _r_node_for(pos: Vector3, radius: float) -> Dictionary:
	var p := Vector2(pos.x, pos.z)
	var li := stair_at(pos)
	if li >= 0 and absf(line_height(lines[li], p) - pos.y) < 1.0:
		return {"kind": "line", "ref": li, "pos": pos}
	var ri := region_at(pos)
	if ri >= 0:
		return {"kind": "region", "ref": ri, "pos": pos}
	# 无支撑点：投影到最近可走面（目标在高障碍顶/悬空）。
	var near := near_point(pos)
	if not near.is_equal_approx(pos):
		var ri2 := region_at(near)
		if ri2 >= 0:
			return {"kind": "region", "ref": ri2, "pos": near, "goal_off": true}
		var li2 := stair_at(near)
		if li2 >= 0:
			return {"kind": "line", "ref": li2, "pos": near, "goal_off": true}
	return {}


## A*：节点 = region 索引与 line 索引；边代价 = XZ 距离 + 高度差 ×2。
## 每个节点记录 {node, via}：via 是到达该节点所用的邻接项（line/edge）。
func _node_for(pos: Vector3, radius: float) -> Dictionary:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Dictionary = _r_node_for(pos, radius)
		_prof_add("_node_for", _t0)
		return _r
	return _r_node_for(pos, radius)


func _r_astar(from: Dictionary, goal: Dictionary) -> Array:
	var start_key := _node_key(from)
	var target_key := _node_key(goal)
	_pred.clear()
	var open: Array = [{"key": start_key, "node": from, "via": {}, "f": 0.0, "g": 0.0}]
	var best_g := {start_key: 0.0}
	var parent := {}
	var parent_via := {}
	var closed := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(open[i]["f"]) < float(open[bi]["f"]):
				bi = i
		var cur: Dictionary = open[bi]
		open.remove_at(bi)
		var key: String = cur["key"]
		if closed.has(key):
			continue
		closed[key] = true
		parent[key] = cur["node"]
		parent_via[key] = cur["via"]
		if key == target_key:
			var seq: Array = []
			var k := key
			while k != start_key:
				var node: Dictionary = parent[k]
				node = node.duplicate()
				node["via"] = parent_via[k]
				seq.push_front(node)
				k = _parent_key(k, parent, parent_via, start_key)
			seq.push_front(from)
			return seq
		for next in _neighbors(cur["node"]):
			var nkey := _node_key(next)
			if closed.has(nkey):
				continue
			var g := float(cur["g"]) + _edge_cost(cur["node"], next)
			if best_g.has(nkey) and float(best_g[nkey]) <= g:
				continue
			best_g[nkey] = g
			var node := {"kind": next["kind"], "ref": next["ref"]}
			_pred[nkey] = key
			open.append({"key": nkey, "node": node, "via": next.get("via", {}),
				"f": g + _heuristic(node, goal), "g": g})
	return []


## 回朔 parent 链：节点 → 其父 key。结构体 parent 存的是 node；key→父 key 靠
## 在展开时把父 key 记进 _pred。
var _pred := {}
func _astar(from: Dictionary, goal: Dictionary) -> Array:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Array = _r_astar(from, goal)
		_prof_add("_astar", _t0)
		return _r
	return _r_astar(from, goal)


func _parent_key(key: String, _parent: Dictionary, _via: Dictionary, _start: String) -> String:
	return String(_pred.get(key, _start))


func _node_key(node: Dictionary) -> String:
	if String(node["kind"]) == "region":
		return "r%d" % int(node["ref"])
	return "l%d" % int(node["ref"])


func _node_pos(node: Dictionary) -> Vector3:
	if String(node["kind"]) == "region":
		var c: Vector2 = regions[int(node["ref"])]["center"]
		return Vector3(c.x, float(regions[int(node["ref"])]["y0"]), c.y)
	var line: Dictionary = lines[int(node["ref"])]
	var p := ((line["a"] as Vector2) + (line["b"] as Vector2)) * 0.5
	return Vector3(p.x, (float(line["y0"]) + float(line["y1"])) * 0.5, p.y)


func _neighbors(node: Dictionary) -> Array:
	var out: Array = []
	if String(node["kind"]) == "region":
		var ri := int(node["ref"])
		for e in _adj.get(ri, []):
			if String(e["link"]) == "line":
				out.append({"kind": "line", "ref": int(e["line"]), "via": e})
			else:
				out.append({"kind": "region", "ref": int(e["to"]), "via": e})
	else:
		var line: Dictionary = lines[int(node["ref"])]
		for e in _line_links(int(node["ref"])):
			out.append({"kind": "region", "ref": int(e["to"]), "via": e})
	return out


func _line_links(li: int) -> Array:
	var out: Array = []
	var seen := {}
	for ri in regions.size():
		for e in _adj.get(ri, []):
			if String(e["link"]) == "line" and int(e["line"]) == li and not seen.has(ri):
				seen[ri] = true
				out.append({"to": ri, "link": "line", "line": li})
	return out


func _edge_cost(a: Dictionary, b: Dictionary) -> float:
	var pa := _node_pos(a)
	var pb := _node_pos(b)
	var d := (pa - pb).slide(Vector3.UP).length()
	return d + absf(pa.y - pb.y) * 2.0


func _heuristic(a: Dictionary, b: Dictionary) -> float:
	return (_node_pos(a) - _node_pos(b)).slide(Vector3.UP).length()


func _portal_point(a: Dictionary, b: Dictionary) -> Vector3:
	if String(a["kind"]) == "region" and String(b["kind"]) == "region":
		var ra: Dictionary = regions[int(a["ref"])]
		var rb: Dictionary = regions[int(b["ref"])]
		var mid := ((ra["center"] as Vector2) + (rb["center"] as Vector2)) * 0.5
		var q := _nearest_on_poly(rb["poly"], _nearest_on_poly(ra["poly"], mid))
		return Vector3(q.x, float(rb["y0"]), q.y)
	return _node_pos(b)


## 区域内障碍绕行：直线被障碍挡住时找阻挡体切点绕。
func _r_detour(from: Vector3, goal: Vector3, radius: float, step_height: float,
		upper: Dictionary, depth: int) -> Array:
	if (goal - from).slide(Vector3.UP).length_squared() < 0.01:
		return [goal]
	var landed := move_supported(from, goal, radius, step_height, 0.6, upper)
	if (landed - goal).slide(Vector3.UP).length() < 0.06:
		return [goal]
	if depth >= 6 or _detour_budget <= 0 \
			or Time.get_ticks_usec() > _detour_deadline:
		return []
	_detour_budget -= 1
	# 支撑失败（悬崖）：无法绕行。
	if not _blocked_along(from, goal, radius):
		return []
	var blocker := _first_blocker(from, landed, radius)
	if blocker.is_empty():
		return []
	var corners := _detour_corners(from, goal, blocker, radius)
	var best: Array = []
	var best_len := INF
	for c in corners:
		# 每验证一条绕行腿扣一次预算；两层检查防单帧爆炸。
		_detour_budget -= 1
		if _detour_budget < 0 or Time.get_ticks_usec() > _detour_deadline:
			break
		var leg1 := move_supported(from, c, radius, step_height, 0.6, upper)
		if (leg1 - c).slide(Vector3.UP).length() > 0.06:
			continue
		var rest := _detour(c, goal, radius, step_height, upper, depth + 1)
		if rest.is_empty():
			continue
		var length := from.distance_to(c) + _path_len(c, rest)
		if length < best_len:
			best_len = length
			best = [c]
			best.append_array(rest)
	return best


func _detour(from: Vector3, goal: Vector3, radius: float, step_height: float,
		upper: Dictionary, depth: int) -> Array:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Array = _r_detour(from, goal, radius, step_height, upper, depth)
		_prof_add("_detour", _t0)
		return _r
	return _r_detour(from, goal, radius, step_height, upper, depth)


func _path_len(from: Vector3, pts: Array) -> float:
	var total := 0.0
	var cursor := from
	for p in pts:
		total += cursor.distance_to(p)
		cursor = p
	return total


func _blocked_along(from: Vector3, goal: Vector3, radius: float) -> bool:
	var offset := (goal - from).slide(Vector3.UP)
	var steps := maxi(1, ceili(offset.length() / SAMPLE_STEP))
	var pos := from
	for i in range(1, steps + 1):
		var target := from + offset * (float(i) / steps)
		var support := support_at(target, pos.y + DEFAULT_STEP_HEIGHT)
		if support < -INF * 0.5:
			continue	# 支撑失败不算障碍
		target.y = support
		if _blocked_at(target, radius, DEFAULT_STEP_HEIGHT):
			return true
		pos = target
	return false


func _r_first_blocker(from: Vector3, landed: Vector3, radius: float) -> Dictionary:
	var dir := (landed - from).slide(Vector3.UP)
	var dist := dir.length()
	if dist < 0.05:
		dir = Vector3.FORWARD
	else:
		dir /= dist
	var probe := from + dir * (dist + radius + 0.05)
	var p := Vector2(probe.x, probe.z)
	# 必须和 _blocked_at 一样过垂直带：全图尺度的女儿墙/顶棚棱柱在 XZ 上
	# 罩住一切，没有高度过滤会被误判成挡路者。
	var best := {}
	var nd := INF
	for i in _obstacle_candidates(Rect2(p, Vector2.ZERO).grow(radius * 3.0)):
		var o: Dictionary = obstacles[i]
		if from.y >= float(o["y1"]) - DEFAULT_STEP_HEIGHT \
			or from.y + STANCE_HEIGHT <= float(o["y0"]) + 0.02:
			continue
		var pad := radius if String(o["pad"]) == "actor" else 0.0
		var margin := _poly_margin(o["poly"], p)
		if margin > -pad and margin < nd:
			nd = margin
			best = o
	if not best.is_empty():
		return best
	# 拿不到精确阻挡体时，返回落在 landed 附近且过垂直带的最近障碍。
	var nearest := {}
	for i in obstacles.size():
		var o: Dictionary = obstacles[i]
		if from.y >= float(o["y1"]) - DEFAULT_STEP_HEIGHT \
			or from.y + STANCE_HEIGHT <= float(o["y0"]) + 0.02:
			continue
		var margin := _poly_margin(o["poly"], Vector2(landed.x, landed.z))
		if margin < nd:
			nd = margin
			nearest = o
	return nearest


## 绕行角点：对「按半径膨胀后的障碍包围盒」取全部 4 角，各沿盒心→角方向
## 推出一点 —— 候选点保证落在膨胀区外；哪几个真能用交给 move_supported
## 腿验证 + 递归选最短（细长障碍的正确绕行端不一定是 side 极端角）。
func _first_blocker(from: Vector3, landed: Vector3, radius: float) -> Dictionary:
	if _prof_on or _prof_tick():
		var _t0 := Time.get_ticks_usec()
		var _r: Dictionary = _r_first_blocker(from, landed, radius)
		_prof_add("_first_blocker", _t0)
		return _r
	return _r_first_blocker(from, landed, radius)


func _detour_corners(from: Vector3, goal: Vector3, blocker: Dictionary, radius: float) -> Array:
	var pad := (radius + 0.10) if String(blocker["pad"]) == "actor" else 0.10
	var rect: Rect2 = (blocker["aabb"] as Rect2).grow(pad)
	var center := rect.get_center()
	var corners := [
		Vector2(rect.position.x, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
	]
	var scored: Array = []
	for v2 in corners:
		var v: Vector2 = v2
		var away: Vector2 = (v - center).normalized() * 0.45
		var q: Vector2 = v + away
		var c := Vector3(q.x, 0.0, q.y)
		c.y = support_at(c, from.y + 1.0)
		if c.y <= -INF * 0.5:
			continue
		var cost := (c - from).slide(Vector3.UP).length() \
			+ (goal - c).slide(Vector3.UP).length()
		scored.append({"c": c, "cost": cost})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["cost"]) < float(b["cost"]))
	var out: Array = []
	for s in scored:
		out.append(s["c"])
	return out


# ============================================================== 校验
func stats() -> Dictionary:
	return {"regions": regions.size(), "lines": lines.size(), "obstacles": obstacles.size()}


## 连通性：同层邻接 + line 相连的区域算作同一可达分量。
func connectivity() -> Dictionary:
	var parent: Array = []
	for i in regions.size():
		parent.append(i)
	for i in regions.size():
		for e in _adj.get(i, []):
			if String(e["link"]) == "edge":
				_union(parent, i, int(e["to"]))
	var line_regions := {}
	for i in regions.size():
		for e in _adj.get(i, []):
			if String(e["link"]) == "line":
				var li := int(e["line"])
				if line_regions.has(li):
					_union(parent, int(line_regions[li]), i)
				else:
					line_regions[li] = i
	var groups := {}
	for i in regions.size():
		var root := _find(parent, i)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(i)
	return {"components": groups.size(), "groups": groups}


static func _union(parent: Array, a: int, b: int) -> void:
	parent[_find(parent, a)] = _find(parent, b)


static func _find(parent: Array, i: int) -> int:
	while int(parent[i]) != i:
		parent[i] = parent[int(parent[i])]
		i = int(parent[i])
	return i

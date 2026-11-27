extends Node3D
## F6 导航元信息视图：把 level.nav（NavField）画成世界内叠加层。
##
##   区域 region  —— 青色半透明面 + 亮边；
##   线 line      —— 黄色走廊（楼梯/坡道中线，两端高度渐变）；
##   障碍 obstacle —— 红色棱柱（顶面 + 竖棱）；
##   敌人路径     —— 每 0.5s 重算一次各敌人到玩家的 nav.path（青色亮线）。
##
## mode="solids"（F7）改画实际碰撞数据：arena["solids"] 绿框 + walkables 蓝面。
##
## ImmediateMesh 上限 256 surfaces：所有元素按材质合批成 6 个 surface。
## 默认关闭；关闭时整个节点被释放，零开销。

const REGION_FILL := Color(0.15, 0.75, 0.85, 0.16)
const REGION_EDGE := Color(0.35, 0.95, 1.0, 0.9)
const LINE_FILL := Color(1.0, 0.82, 0.25, 0.28)
const LINE_EDGE := Color(1.0, 0.9, 0.35, 0.95)
const OBSTACLE_FILL := Color(1.0, 0.25, 0.22, 0.14)
const OBSTACLE_EDGE := Color(1.0, 0.35, 0.3, 0.85)
const PATH_LINE := Color(0.45, 1.0, 0.75, 0.95)
const PATH_DOT := Color(1.0, 1.0, 0.5, 0.95)
const LIFT := 0.07                 # 叠加层抬离支撑面的高度
const PATH_PERIOD := 0.5
const LABEL_LIMIT := 48

var mode := "nav"          # "nav" = F6 元信息；"solids" = F7 物理碰撞数据
var _level: Node
var _field_mesh: ImmediateMesh
var _path_mesh: ImmediateMesh
var _labels: Array = []
var _path_age := 0.0
## F7 刚体提供者：death 任务在此登记回调，返回
## [{"aabb": AABB, "xf": Transform3D(可选), "color": Color(可选)}] 的 Array。
var _body_providers: Array = []


## F7 扩展接口：物理刚体视图把登记进来的 body 描述画成线框。
## provider 每次刷新时被调用，返回 box dict 列表（xf 缺省 = 恒等）。
## 例：view.add_body_provider(func(): return debris.bodies())
func add_body_provider(provider: Callable) -> void:
	_body_providers.append(provider)


static func attach(level: Node, parent: Node, p_mode := "nav") -> Node3D:
	var view = new()
	view.name = "NavDebugView" if p_mode == "nav" else "SolidsDebugView"
	view.mode = p_mode
	view._level = level
	parent.add_child(view)
	return view


func _ready() -> void:
	_field_mesh = ImmediateMesh.new()
	_path_mesh = ImmediateMesh.new()
	var inst := MeshInstance3D.new()
	inst.mesh = _field_mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	var pinst := MeshInstance3D.new()
	pinst.mesh = _path_mesh
	pinst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pinst)
	if mode == "solids":
		_rebuild_solids()
	else:
		_rebuild_field()


func _process(dt: float) -> void:
	_path_age += dt
	var period := 0.10 if mode == "solids" else PATH_PERIOD
	if _path_age >= period:
		_path_age = 0.0
		if mode == "solids" and not _body_providers.is_empty():
			_rebuild_solids()
		elif mode == "nav":
			_rebuild_paths()


func _exit_tree() -> void:
	for label in _labels:
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _nav():
	if _level == null or not is_instance_valid(_level):
		return null
	return _level.get("nav")


func _rebuild_field() -> void:
	var nav = _nav()
	_field_mesh.clear_surfaces()
	if nav == null:
		return
	var fill := _material(REGION_FILL)
	var edge := _material(REGION_EDGE)
	var lfill := _material(LINE_FILL)
	var ledge := _material(LINE_EDGE)
	var ofill := _material(OBSTACLE_FILL)
	var oedge := _material(OBSTACLE_EDGE)

	# ---- 区域面（一次 surface 扇出全部多边形）----
	_field_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fill)
	for region in nav.regions:
		var poly: PackedVector2Array = region["poly"]
		var y := float(region["y0"]) + LIFT
		var center: Vector2 = region["center"]
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			_field_mesh.surface_add_vertex(Vector3(center.x, y, center.y))
			_field_mesh.surface_add_vertex(Vector3(a.x, y, a.y))
			_field_mesh.surface_add_vertex(Vector3(b.x, y, b.y))
	_field_mesh.surface_end()
	# ---- 区域边线 ----
	_field_mesh.surface_begin(Mesh.PRIMITIVE_LINES, edge)
	for region in nav.regions:
		var poly: PackedVector2Array = region["poly"]
		var y := float(region["y0"]) + LIFT + 0.01
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			_field_mesh.surface_add_vertex(Vector3(a.x, y, a.y))
			_field_mesh.surface_add_vertex(Vector3(b.x, y, b.y))
	_field_mesh.surface_end()

	# ---- 线走廊面（楼梯/坡道）----
	_field_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, lfill)
	for line in nav.lines:
		var corners := _line_corners(line)
		_field_mesh.surface_add_vertex(corners[0])
		_field_mesh.surface_add_vertex(corners[1])
		_field_mesh.surface_add_vertex(corners[2])
		_field_mesh.surface_add_vertex(corners[0])
		_field_mesh.surface_add_vertex(corners[2])
		_field_mesh.surface_add_vertex(corners[3])
	_field_mesh.surface_end()
	_field_mesh.surface_begin(Mesh.PRIMITIVE_LINES, ledge)
	for line in nav.lines:
		var corners := _line_corners(line)
		for i in 4:
			_field_mesh.surface_add_vertex(corners[i] + Vector3.UP * 0.02)
			_field_mesh.surface_add_vertex(corners[(i + 1) % 4] + Vector3.UP * 0.02)
		var a: Vector2 = line["a"]
		var b: Vector2 = line["b"]
		_field_mesh.surface_add_vertex(
			Vector3(a.x, float(line["y0"]) + LIFT + 0.03, a.y))
		_field_mesh.surface_add_vertex(
			Vector3(b.x, float(line["y1"]) + LIFT + 0.03, b.y))
	_field_mesh.surface_end()

	# ---- 障碍棱柱：顶面 ----
	_field_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, ofill)
	for o in nav.obstacles:
		var poly: PackedVector2Array = o["poly"]
		var y1 := float(o["y1"]) + LIFT
		var mid := Vector2.ZERO
		for v in poly:
			mid += v
		mid /= float(poly.size())
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			_field_mesh.surface_add_vertex(Vector3(mid.x, y1, mid.y))
			_field_mesh.surface_add_vertex(Vector3(a.x, y1, a.y))
			_field_mesh.surface_add_vertex(Vector3(b.x, y1, b.y))
	_field_mesh.surface_end()
	# ---- 障碍棱柱：顶边 + 竖棱 ----
	_field_mesh.surface_begin(Mesh.PRIMITIVE_LINES, oedge)
	for o in nav.obstacles:
		var poly: PackedVector2Array = o["poly"]
		var y0 := float(o["y0"]) + LIFT
		var y1 := float(o["y1"]) + LIFT
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			_field_mesh.surface_add_vertex(Vector3(a.x, y1, a.y))
			_field_mesh.surface_add_vertex(Vector3(b.x, y1, b.y))
			_field_mesh.surface_add_vertex(Vector3(a.x, y0, a.y))
			_field_mesh.surface_add_vertex(Vector3(a.x, y1, a.y))
	_field_mesh.surface_end()

	# ---- 区域 id ----
	for label in _labels:
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()
	if nav.regions.size() <= LABEL_LIMIT:
		for region in nav.regions:
			var label := Label3D.new()
			label.text = String(region["id"])
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.font_size = 48
			label.pixel_size = 0.015
			label.modulate = Color(0.7, 1.0, 1.0, 0.9)
			var c: Vector2 = region["center"]
			label.position = Vector3(c.x, float(region["y0"]) + 0.9, c.y)
			add_child(label)
			_labels.append(label)


func _line_corners(line: Dictionary) -> Array:
	var a: Vector2 = line["a"]
	var b: Vector2 = line["b"]
	var perp: Vector2 = line["perp"] * float(line["width"]) * 0.5
	var y0 := float(line["y0"]) + LIFT
	var y1 := float(line["y1"]) + LIFT
	return [
		Vector3(a.x + perp.x, y0, a.y + perp.y),
		Vector3(a.x - perp.x, y0, a.y - perp.y),
		Vector3(b.x - perp.x, y1, b.y - perp.y),
		Vector3(b.x + perp.x, y1, b.y + perp.y),
	]


## F7：画 arena 的实际碰撞数据（solids 绿框 + walkables 蓝面）+ 注册的物理刚体/胶囊/碎块。
func _rebuild_solids() -> void:
	_field_mesh.clear_surfaces()
	if _level == null or not is_instance_valid(_level):
		return
	var arena = _level.get("arena")
	if arena is Dictionary:
		var sfill := _material(Color(0.2, 1.0, 0.45, 0.10))
		var sedge := _material(Color(0.3, 1.0, 0.5, 0.85))
		var wfill := _material(Color(0.25, 0.55, 1.0, 0.18))
		var wedge := _material(Color(0.45, 0.7, 1.0, 0.9))
		var solids: Array = arena.get("solids", [])
		var walkables: Array = arena.get("walkables", [])
		if not walkables.is_empty():
			_field_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, wfill)
			for box in walkables:
				_box_top_fan(box, LIFT)
			_field_mesh.surface_end()
			_field_mesh.surface_begin(Mesh.PRIMITIVE_LINES, wedge)
			for box in walkables:
				_box_edges(box, LIFT + 0.01, false)
			_field_mesh.surface_end()
		if not solids.is_empty():
			_field_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, sfill)
			for box in solids:
				_box_top_fan(box, LIFT)
			_field_mesh.surface_end()
			_field_mesh.surface_begin(Mesh.PRIMITIVE_LINES, sedge)
			for box in solids:
				_box_edges(box, LIFT, true)
			_field_mesh.surface_end()
	# 登记的动态刚体（静态碰撞体 / 推挤胶囊 / 碎块等），按颜色分批绘制。
	if not _body_providers.is_empty():
		for i in range(_body_providers.size() - 1, -1, -1):
			var obj: Object = _body_providers[i].get_object()
			if obj == null or not is_instance_valid(obj):
				_body_providers.remove_at(i)
		var by_color := {}
		for provider in _body_providers:
			var bodies: Array = provider.call()
			for body in bodies:
				if not body is Dictionary or not body.has("aabb"):
					continue
				var col: Color = body.get("color", Color(1.0, 0.65, 0.2, 0.9))
				var key := col.to_html()
				if not by_color.has(key):
					by_color[key] = {"col": col, "list": []}
				(by_color[key]["list"] as Array).append(body)
		for key in by_color:
			var grp: Dictionary = by_color[key]
			var bmat := _material(grp["col"])
			_field_mesh.surface_begin(Mesh.PRIMITIVE_LINES, bmat)
			for body in grp["list"]:
				var xf: Transform3D = body.get("xf", Transform3D.IDENTITY)
				_xf_box_edges(body["aabb"], xf)
			_field_mesh.surface_end()


func _box_top_fan(box: AABB, lift: float) -> void:
	var c := box.get_center()
	var y := box.end.y + lift
	var x0 := box.position.x
	var x1 := box.end.x
	var z0 := box.position.z
	var z1 := box.end.z
	_field_mesh.surface_add_vertex(Vector3(c.x, y, c.z))
	_field_mesh.surface_add_vertex(Vector3(x0, y, z0))
	_field_mesh.surface_add_vertex(Vector3(x1, y, z0))
	_field_mesh.surface_add_vertex(Vector3(c.x, y, c.z))
	_field_mesh.surface_add_vertex(Vector3(x1, y, z0))
	_field_mesh.surface_add_vertex(Vector3(x1, y, z1))
	_field_mesh.surface_add_vertex(Vector3(c.x, y, c.z))
	_field_mesh.surface_add_vertex(Vector3(x1, y, z1))
	_field_mesh.surface_add_vertex(Vector3(x0, y, z1))
	_field_mesh.surface_add_vertex(Vector3(c.x, y, c.z))
	_field_mesh.surface_add_vertex(Vector3(x0, y, z1))
	_field_mesh.surface_add_vertex(Vector3(x0, y, z0))


func _box_edges(box: AABB, lift: float, verticals: bool) -> void:
	var x0 := box.position.x
	var x1 := box.end.x
	var z0 := box.position.z
	var z1 := box.end.z
	var yt := box.end.y + lift
	var yb := box.position.y + lift
	var top := [Vector3(x0, yt, z0), Vector3(x1, yt, z0),
		Vector3(x1, yt, z1), Vector3(x0, yt, z1)]
	for i in 4:
		_field_mesh.surface_add_vertex(top[i])
		_field_mesh.surface_add_vertex(top[(i + 1) % 4])
	if not verticals:
		return
	var bot := [Vector3(x0, yb, z0), Vector3(x1, yb, z0),
		Vector3(x1, yb, z1), Vector3(x0, yb, z1)]
	for i in 4:
		_field_mesh.surface_add_vertex(bot[i])
		_field_mesh.surface_add_vertex(bot[(i + 1) % 4])
		_field_mesh.surface_add_vertex(bot[i])
		_field_mesh.surface_add_vertex(top[i])


## 世界变换下的 AABB 12 棱（F7 刚体线框用）。
func _xf_box_edges(box: AABB, xf: Transform3D) -> void:
	var p := box.position
	var e := box.end
	var c := [
		xf * Vector3(p.x, p.y, p.z), xf * Vector3(e.x, p.y, p.z),
		xf * Vector3(e.x, e.y, p.z), xf * Vector3(p.x, e.y, p.z),
		xf * Vector3(p.x, p.y, e.z), xf * Vector3(e.x, p.y, e.z),
		xf * Vector3(e.x, e.y, e.z), xf * Vector3(p.x, e.y, e.z)]
	for pair in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
			[0, 4], [1, 5], [2, 6], [3, 7]]:
		_field_mesh.surface_add_vertex(c[pair[0]])
		_field_mesh.surface_add_vertex(c[pair[1]])


func _rebuild_paths() -> void:
	_path_mesh.clear_surfaces()
	var nav = _nav()
	if nav == null or _level == null or not is_instance_valid(_level):
		return
	var player = _level.get("player")
	var enemies = _level.get("enemies")
	if player == null or enemies == null:
		return
	var rig = player.get("rig")
	if rig == null:
		return
	var goal: Vector3 = rig.global_position
	var line := _material(PATH_LINE)
	var dot := _material(PATH_DOT)
	_path_mesh.surface_begin(Mesh.PRIMITIVE_LINES, line)
	for e in enemies:
		if not is_instance_valid(e) or not e.get("alive"):
			continue
		var from: Vector3 = e.global_position
		var pts: Array = nav.path(from, goal, 1.2)
		var cursor := from + Vector3.UP * 0.35
		for p in pts:
			var q: Vector3 = p + Vector3.UP * 0.35
			_path_mesh.surface_add_vertex(cursor)
			_path_mesh.surface_add_vertex(q)
			cursor = q
	_path_mesh.surface_end()
	_path_mesh.surface_begin(Mesh.PRIMITIVE_LINES, dot)
	for e in enemies:
		if not is_instance_valid(e) or not e.get("alive"):
			continue
		var pts: Array = nav.path(e.global_position, goal, 1.2)
		if pts.is_empty():
			continue
		var top: Vector3 = pts[-1] + Vector3.UP * 0.6
		_path_mesh.surface_add_vertex(top - Vector3.UP * 0.25)
		_path_mesh.surface_add_vertex(top + Vector3.UP * 0.25)
		_path_mesh.surface_add_vertex(top - Vector3.RIGHT * 0.25)
		_path_mesh.surface_add_vertex(top + Vector3.RIGHT * 0.25)
	_path_mesh.surface_end()

extends RefCounted
## 地面电源车（GPU）：圆角机组箱 + 百叶 + 控制面板 + 卷盘/插头 + 轮子 + 牵引杆。
##
## 全部按米建模，挂在 scale = U 的节点下；节点摆到甲板上的 (31, 0, 7)。

const Kit := preload("res://src/arena/kit.gd")

const HW := 0.75      # 半宽（z）
const HH := 0.65      # 半高（y）
const CY := 1.10      # 截面中心
const HX := 1.30      # 半长（x）


static func build(parent: Node3D, M: Dictionary) -> void:
	var s := Node3D.new()
	s.name = "GPU"
	s.scale = Vector3.ONE * (1.0 / 0.547)
	s.position = Vector3(31.0, 0.0, 7.0) * (1.0 / 0.547)
	parent.add_child(s)

	var body: Material = M["gpu"]
	var dark: Material = M["wall_dark"]
	var steel: Material = M["steel"]
	var hot: Material = M["steel_hot"]
	var paint: Material = M["paint"]
	var rubber: Material = M["rubber"]
	var red: Material = M["red"]
	var amber: Material = M["amber"]
	var display: Material = M["display"]
	var gauge: Material = M["gauge"]
	var green: Material = M["green"]

	_shell(s, body, dark)
	_wheels(s, steel, rubber)
	_louvres(s, dark, steel)
	_panel(s, dark, steel, display, gauge, _M_red_plastic(), green, amber)
	_worklight(s, steel, M["warm"])
	_top(s, steel, hot, dark, amber)
	_reel(s, steel, dark, rubber, hot)
	_towbar(s, steel, hot, dark)
	_trim(s, paint, steel, hot, dark)
	_ground_cable(s, green, steel)


# ================================================================== 圆角机组箱
static func _shell(s: Node3D, body: Material, dark: Material) -> void:
	var n := 40
	var ring: Array = []
	for i in n:
		var a := TAU * float(i) / float(n)
		var c := cos(a)
		var sn := sin(a)
		ring.append(Vector2(
			HW * signf(c) * pow(absf(c), 0.40),
			HH * signf(sn) * pow(absf(sn), 0.40)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		var p0 := Vector3(-HX, CY + ring[i].y, ring[i].x)
		var p1 := Vector3(-HX, CY + ring[j].y, ring[j].x)
		var p2 := Vector3(HX, CY + ring[j].y, ring[j].x)
		var p3 := Vector3(HX, CY + ring[i].y, ring[i].x)
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(j) / float(n)
		var n0 := Vector3(0.0, sin(a0), cos(a0)).normalized()
		var n1 := Vector3(0.0, sin(a1), cos(a1)).normalized()
		_quad(st, p0, p1, p2, p3, n0, n1)
	# 两端封板
	for x in [-HX, HX]:
		var nx := -1.0 if x < 0.0 else 1.0
		var center := Vector3(x, CY, 0.0)
		for i in n:
			var j := (i + 1) % n
			var p0 := Vector3(x, CY + ring[i].y, ring[i].x)
			var p1 := Vector3(x, CY + ring[j].y, ring[j].x)
			_tri(st, center, p0, p1, Vector3(nx, 0.0, 0.0))
			_tri(st, center, p1, p0, Vector3(nx, 0.0, 0.0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = body
	s.add_child(mi)

	# 底盘
	_b(s, Vector3(2.50, 0.14, 1.30), Vector3(0.0, 0.40, 0.0), dark)
	_b(s, Vector3(2.44, 0.05, 0.10), Vector3(0.0, 0.34, 0.55), _M_steel_dark())
	_b(s, Vector3(2.44, 0.05, 0.10), Vector3(0.0, 0.34, -0.55), _M_steel_dark())


# ================================================================== 轮子
static func _wheels(s: Node3D, steel: Material, rubber: Material) -> void:
	for sx in [-0.95, 0.95]:
		for sz in [-0.55, 0.55]:
			Kit.cylinder(s, 0.22, 0.14, Vector3(sx, 0.22, sz), rubber, Vector3(PI * 0.5, 0.0, 0.0))
			Kit.cylinder(s, 0.08, 0.16, Vector3(sx, 0.22, sz), steel, Vector3(PI * 0.5, 0.0, 0.0))
			# 叉架 + 转向座
			for dz in [-0.10, 0.10]:
				_b(s, Vector3(0.06, 0.30, 0.03), Vector3(sx, 0.40, sz + dz), steel)
			_b(s, Vector3(0.22, 0.06, 0.22), Vector3(sx, 0.55, sz), steel)
			_b(s, Vector3(0.10, 0.10, 0.10), Vector3(sx, 0.60, sz), _M_steel_dark())


# ================================================================== 百叶 / 进气
static func _louvres(s: Node3D, dark: Material, steel: Material) -> void:
	# 两侧散热格栅
	for side in [-1.0, 1.0]:
		var z: float = side * (HW + 0.012)
		_b(s, Vector3(1.25, 0.78, 0.03), Vector3(-0.30, 1.10, z), dark)
		for k in 7:
			_b(s, Vector3(1.15, 0.055, 0.05), Vector3(-0.30, 0.78 + float(k) * 0.095, z + side * 0.02),
				steel)
		for dx in [-0.66, 0.66]:
			_b(s, Vector3(0.05, 0.82, 0.05), Vector3(-0.30 + dx, 1.10, z + side * 0.03), steel)
		for dy in [0.72, 1.48]:
			_b(s, Vector3(1.36, 0.05, 0.05), Vector3(-0.30, dy, z + side * 0.03), steel)
	# 西端进气：竖百叶 + 风机
	_b(s, Vector3(0.03, 0.90, 1.34), Vector3(-HX - 0.012, 1.10, 0.0), dark)
	for k in 7:
		_b(s, Vector3(0.05, 0.84, 0.055), Vector3(-HX - 0.03, 1.10, -0.51 + float(k) * 0.17), steel)
	Kit.cylinder(s, 0.34, 0.04, Vector3(-HX + 0.04, 1.10, 0.0), _M_steel_dark(),
		Vector3(0.0, 0.0, PI * 0.5))
	for k in 5:
		var a := TAU * float(k) / 5.0
		_b(s, Vector3(0.02, 0.28, 0.05), Vector3(-HX + 0.06, 1.10 + sin(a) * 0.15,
			cos(a) * 0.15), steel, Vector3(0.0, -a, 0.0))


# ================================================================== 控制面板
static func _panel(s: Node3D, dark: Material, steel: Material, display: Material,
		gauge: Material, red: Material, green: Material, amber: Material) -> void:
	var x := HX + 0.012
	# 凹面板 + 内框
	_b(s, Vector3(0.03, 0.72, 0.98), Vector3(x, 1.26, 0.0), dark)
	_b(s, Vector3(0.05, 0.80, 1.06), Vector3(x - 0.01, 1.26, 0.0), steel)
	# 显示屏：深色边框 + 绿色面板 + 几行读数
	_b(s, Vector3(0.04, 0.30, 0.46), Vector3(x + 0.005, 1.44, -0.16), _M_steel_dark())
	_b(s, Vector3(0.02, 0.22, 0.36), Vector3(x + 0.03, 1.44, -0.16), display)
	for k in 3:
		_b(s, Vector3(0.01, 0.022, 0.12 + float(k) * 0.05), Vector3(x + 0.045,
			1.50 - float(k) * 0.055, -0.20), _M_steel_dark())
	# 面板螺丝
	for sy in [0.94, 1.56]:
		for sz2 in [-0.42, 0.42]:
			Kit.cylinder(s, 0.012, 0.012, Vector3(x + 0.03, sy, sz2), steel,
				Vector3(0.0, 0.0, PI * 0.5))
	# 两块压力表
	for gz in [-0.34, 0.02]:
		Kit.cylinder(s, 0.085, 0.03, Vector3(x + 0.025, 1.16, gz), gauge,
			Vector3(0.0, 0.0, PI * 0.5))
		Kit.torus(s, 0.085, 0.012, Vector3(x + 0.04, 1.16, gz), steel, 20).rotation = \
			Vector3(0.0, 0.0, PI * 0.5)
		for k in 4:
			var ta := TAU * float(k) / 4.0 + 0.5
			_b(s, Vector3(0.008, 0.018, 0.008), Vector3(x + 0.045,
				1.16 + sin(ta) * 0.065, gz + cos(ta) * 0.065), _M_steel_dark())
		_b(s, Vector3(0.01, 0.07, 0.012), Vector3(x + 0.045, 1.19, gz),
			_M_steel_dark(), Vector3(0.0, 0.0, 0.6))
	# 一排小按钮
	for k in 6:
		_b(s, Vector3(0.02, 0.035, 0.045), Vector3(x + 0.03, 0.90, -0.30 + float(k) * 0.075),
			steel if k % 2 == 0 else _M_steel_dark())
	# 急停 + 旋钮
	Kit.cylinder(s, 0.055, 0.04, Vector3(x + 0.03, 1.02, 0.30), steel,
		Vector3(0.0, 0.0, PI * 0.5))
	Kit.cylinder(s, 0.075, 0.05, Vector3(x + 0.06, 1.02, 0.30), red,
		Vector3(0.0, 0.0, PI * 0.5))
	Kit.cylinder(s, 0.035, 0.03, Vector3(x + 0.03, 1.02, 0.10), steel,
		Vector3(0.0, 0.0, PI * 0.5))
	_b(s, Vector3(0.02, 0.10, 0.025), Vector3(x + 0.05, 1.02, 0.10), _M_steel_dark())
	# 三颗状态灯
	for i in 3:
		var mat: Material = green if i == 0 else (amber if i == 1 else red)
		Kit.cylinder(s, 0.022, 0.02, Vector3(x + 0.025, 1.60, 0.18 + float(i) * 0.10), mat,
			Vector3(0.0, 0.0, PI * 0.5))
	# 断路器手柄
	_b(s, Vector3(0.03, 0.16, 0.10), Vector3(x + 0.03, 0.86, -0.30), steel)
	_b(s, Vector3(0.05, 0.05, 0.14), Vector3(x + 0.06, 0.86, -0.30), _M_red_plastic())


## 控制面板上方的小工作灯：一段弯管 + 灯头 + 暖光
static func _worklight(s: Node3D, steel: Material, hot: Material) -> void:
	Kit.tube(s, Vector3(1.00, 1.76, 0.55), Vector3(1.12, 2.20, 0.55), 0.022, steel)
	Kit.tube(s, Vector3(1.12, 2.20, 0.55), Vector3(1.34, 2.24, 0.46), 0.022, steel)
	Kit.cylinder(s, 0.085, 0.05, Vector3(1.38, 2.22, 0.42), _M_steel_dark(), Vector3.ZERO)
	Kit.cylinder(s, 0.070, 0.02, Vector3(1.38, 2.18, 0.42), hot, Vector3.ZERO)
	var l := OmniLight3D.new()
	l.position = Vector3(1.40, 2.12, 0.42)
	l.light_color = Color(1.0, 0.82, 0.55)
	l.light_energy = 1.2
	l.omni_range = 3.2 * (1.0 / 0.547)
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	s.add_child(l)


# ================================================================== 顶部
static func _top(s: Node3D, steel: Material, hot: Material, dark: Material, amber: Material) -> void:
	# 吊耳 + 横梁
	for sx in [-1.0, 1.0]:
		for sz in [-0.5, 0.5]:
			var ring := Kit.torus(s, 0.10, 0.025, Vector3(sx, 1.80, sz), steel, 16)
			ring.rotation = Vector3(0.0, 0.0, 0.0)
		_b(s, Vector3(0.06, 0.06, 1.10), Vector3(sx, 1.80, 0.0), steel)
	# 排气管 + 防雨帽 + 隔热罩
	Kit.cylinder(s, 0.09, 0.62, Vector3(-0.92, 2.06, 0.44), _M_steel_dark(), Vector3.ZERO)
	Kit.cylinder(s, 0.15, 0.26, Vector3(-0.92, 1.88, 0.44), hot, Vector3.ZERO)
	Kit.cylinder(s, 0.15, 0.02, Vector3(-0.92, 2.43, 0.44), dark, Vector3.ZERO)
	Kit.cylinder(s, 0.03, 0.10, Vector3(-0.92, 2.37, 0.44), dark, Vector3.ZERO)
	# 顶部加注口
	Kit.cylinder(s, 0.10, 0.03, Vector3(0.35, 1.77, 0.18), steel, Vector3.ZERO)
	_b(s, Vector3(0.14, 0.03, 0.03), Vector3(0.35, 1.80, 0.18), dark)
	# 警示灯
	Kit.cylinder(s, 0.06, 0.08, Vector3(1.02, 1.80, -0.46), dark, Vector3.ZERO)
	var dome := SphereMesh.new()
	dome.radius = 0.055
	dome.height = 0.11
	var mi := MeshInstance3D.new()
	mi.mesh = dome
	mi.material_override = amber
	mi.position = Vector3(1.02, 1.86, -0.46)
	s.add_child(mi)


# ================================================================== 电缆卷盘
static func _reel(s: Node3D, steel: Material, dark: Material, rubber: Material, hot: Material) -> void:
	var rx := 0.52
	var ry := 0.95
	var rz := 0.98
	# 支架
	_b(s, Vector3(0.10, 0.50, 0.10), Vector3(rx - 0.42, 0.80, rz), steel)
	_b(s, Vector3(0.10, 0.50, 0.10), Vector3(rx + 0.42, 0.80, rz), steel)
	# 卷筒 + 两侧轮缘
	Kit.cylinder(s, 0.34, 0.40, Vector3(rx, ry, rz), dark, Vector3(PI * 0.5, 0.0, 0.0))
	for dz in [-0.21, 0.21]:
		Kit.cylinder(s, 0.42, 0.035, Vector3(rx, ry, rz + dz), hot, Vector3(PI * 0.5, 0.0, 0.0))
	# 缠好的电缆
	for k in 4:
		var ring := Kit.torus(s, 0.345, 0.045, Vector3(rx, ry, rz - 0.15 + float(k) * 0.10),
			rubber, 24)
		ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	# 出线导轮
	Kit.cylinder(s, 0.05, 0.22, Vector3(rx + 0.15, 1.28, rz + 0.28), steel,
		Vector3(PI * 0.5, 0.0, 0.0))
	# 短电缆 + 插头 + 挂座
	Kit.cable(s, Vector3(rx + 0.10, 0.95, rz + 0.25), Vector3(rx + 0.55, 0.62, rz + 0.30),
		0.18, 0.045, rubber)
	_b(s, Vector3(0.20, 0.18, 0.16), Vector3(rx + 0.62, 0.58, rz + 0.30), dark)
	Kit.cylinder(s, 0.06, 0.12, Vector3(rx + 0.72, 0.58, rz + 0.30), steel,
		Vector3(0.0, 0.0, PI * 0.5))
	_b(s, Vector3(0.26, 0.10, 0.22), Vector3(rx + 0.62, 0.44, rz + 0.30), steel)


# ================================================================== 牵引杆
static func _towbar(s: Node3D, steel: Material, hot: Material, dark: Material) -> void:
	for sz in [-0.22, 0.22]:
		Kit.tube(s, Vector3(-1.25, 0.50, sz), Vector3(-1.62, 0.86, 0.0), 0.045, steel)
	var ring := Kit.torus(s, 0.13, 0.03, Vector3(-1.66, 0.90, 0.0), hot, 16)
	ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_b(s, Vector3(0.14, 0.10, 0.14), Vector3(-1.28, 0.52, 0.0), dark)
	_b(s, Vector3(0.20, 0.05, 0.05), Vector3(-1.40, 0.62, 0.0), steel)


# ================================================================== 细节
static func _trim(s: Node3D, paint: Material, steel: Material, hot: Material, dark: Material) -> void:
	# 两侧把手
	for side in [-1.0, 1.0]:
		Kit.tube(s, Vector3(-0.10, 1.58, side * 0.78), Vector3(0.52, 1.58, side * 0.78), 0.025, steel)
		for sx in [-0.10, 0.52]:
			Kit.tube(s, Vector3(sx, 1.58, side * 0.78), Vector3(sx, 1.50, side * 0.74), 0.02, steel)
	# 黄黑警示带（底盘两侧）
	for i in 6:
		var mat: Material = paint if i % 2 == 0 else dark
		for side in [-1.0, 1.0]:
			_b(s, Vector3(0.34, 0.10, 0.02), Vector3(-1.10 + float(i) * 0.38, 0.40, side * 0.66),
				mat)
	# 白色铭牌 / 黄色警示牌
	_b(s, Vector3(0.45, 0.26, 0.02), Vector3(0.20, 1.16, 0.765), _M_white())
	_b(s, Vector3(0.20, 0.20, 0.02), Vector3(-0.75, 1.16, 0.765), paint)
	# 顶部扶手
	Kit.tube(s, Vector3(-0.95, 1.82, -0.55), Vector3(0.95, 1.82, -0.55), 0.022, steel)


static func _ground_cable(s: Node3D, _green: Material, steel: Material) -> void:
	var green := _M_dark_green()
	# 接地线盘在挂钩上
	var ring := Kit.torus(s, 0.16, 0.022, Vector3(-1.18, 1.10, -0.80), green, 18)
	ring.rotation = Vector3(0.0, 0.0, 0.0)
	_b(s, Vector3(0.06, 0.06, 0.10), Vector3(-1.30, 1.10, -0.78), steel)
	Kit.tube(s, Vector3(-1.18, 0.94, -0.80), Vector3(-1.18, 0.80, -0.80), 0.02, green)
	_b(s, Vector3(0.10, 0.10, 0.04), Vector3(-1.18, 0.74, -0.80), steel)


# ================================================================== 网格
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n0: Vector3, n1: Vector3) -> void:
	st.set_normal(n0); st.add_vertex(a)
	st.set_normal(n1); st.add_vertex(b)
	st.set_normal(n1); st.add_vertex(c)
	st.set_normal(n0); st.add_vertex(a)
	st.set_normal(n1); st.add_vertex(c)
	st.set_normal(n0); st.add_vertex(d)
	st.set_normal(n0); st.add_vertex(a)
	st.set_normal(n1); st.add_vertex(c)
	st.set_normal(n1); st.add_vertex(b)
	st.set_normal(n0); st.add_vertex(a)
	st.set_normal(n0); st.add_vertex(d)
	st.set_normal(n1); st.add_vertex(c)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n); st.add_vertex(a)
	st.set_normal(n); st.add_vertex(b)
	st.set_normal(n); st.add_vertex(c)


static func _b(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	return Kit.box(parent, size, pos, mat, rot)


static func _M_steel_dark() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.11, 0.12)
	m.roughness = 0.62
	m.metallic = 0.35
	return m


static func _M_red_plastic() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.045, 0.035)
	m.roughness = 0.42
	m.metallic = 0.0
	return m


static func _M_dark_green() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.22, 0.12)
	m.roughness = 0.85
	return m


static func _M_white() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.46, 0.46, 0.43)
	m.roughness = 0.85
	return m

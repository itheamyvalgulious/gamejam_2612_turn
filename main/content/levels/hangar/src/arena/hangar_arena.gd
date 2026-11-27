extends RefCounted
## 三号船坞：空间样段（v2 功能平面）。
##
## 目的：验证「能不能走、用途读不读得懂、镜头看不看得清」，不是最终美术。
## 全部按真实米作图，交给 Kit 前乘 U 换成世界单位。
##
## 空间（见 docs/HANGAR_PLAN.md）：
##   主厅 76 × 68 × 27 m；系留甲板 r=25；转盘 r=15；
##   北侧维修舱 32 × 10（凹进）；南侧勤务舱 28 × 10（凹进，储罐隔间）；
##   西侧人员入口 5 × 8；东南人员气闸 6 × 7；东侧舰载机大门 30 × 16；
##   北墙悬挑控制台 y=8.5…12.5。
##
## 通关：本样段没有敌人，也不推进关卡状态；走到东南气闸即看完空间。

const Kit := preload("res://src/arena/kit.gd")
const U := 1.0 / 0.547
const BALL := 1.2

## 导航元信息：船坞 —— 地面矩形 + platforms 顶面（机翼/台架/轿厢等）；
## 障碍 = cover 圆棱柱（机身/柱/柜/井道围护）+ 边界与内墙棱柱。
## 活动电梯：nav 只登记其静止层平台，运动中不走 nav（本关无敌人）。
static func nav_spec(_arena: Dictionary) -> Dictionary:
	return {
		"floor_margin": 0.4 * U,
		"walls_obstacles": true,
		"walls_sight": true,
		"cover_obstacles": true,
		"cover_shrink": BALL,
		"platforms": true,
	}

# ---------------- 主厅 ----------------
const HX := 38.0
const HZ := 34.0
const H := 27.0
const DECK_R := 25.0
const TABLE_R := 15.0

# ---------------- 北侧维修舱 ----------------
const BX0 := -26.0
const BX1 := 6.0
const BZ0 := 34.0
const BZ1 := 44.0
const BH := 9.5
const BAY_OPEN0 := -24.0
const BAY_OPEN1 := 0.0

# ---------------- 南侧勤务舱 ----------------
const UX0 := -8.0
const UX1 := 20.0
const UZ0 := -44.0
const UZ1 := -34.0
const UH := 8.0
const U_OPEN0 := 2.0
const U_OPEN1 := 10.0

# ---------------- 西侧人员入口 ----------------
const EX0 := -50.0
const EX1 := -38.0
const EZ0 := 26.0
const EZ1 := 31.0
const EH := 6.2

# ---------------- 东南人员气闸 ----------------
const AX0 := 38.0
const AX1 := 45.0
const AZ0 := -26.0
const AZ1 := -20.0
const AH := 4.2
const A_DOOR0 := -25.0
const A_DOOR1 := -21.0

# ---------------- 悬挑控制台 ----------------
const QBX0 := 2.0
const QBX1 := 18.0
const QBZ0 := 26.0
const QBZ1 := 34.0
const QY0 := 8.5
const QY1 := 12.5

# ---------------- 舰载机大门 ----------------
const VD_Z := 15.0
const VD_H := 16.0

const SPAWN := Vector3(-42.5, 0.0, 28.5)

static var _M := {}


static func build(origin := Vector3.ZERO) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arena_hangar"
	root.position = origin

	_mats()
	var walls: Array = []
	var cover: Array = []
	var platforms: Array = []
	_environment(root)
	_floor(root)
	_deck(root)
	_markings(root)
	_shell(root)
	_entry(root)
	_bay(root, cover, platforms)
	_utility(root)
	_east(root)
	_booth(root, platforms)
	_lift(root, cover, platforms)
	_crane(root)
	_lights(root)
	_props(root)
	_boss_placeholder(root)
	if "--rings" in OS.get_cmdline_user_args():
		_debug_rings(root)

	_outline(walls, cover)
	_solids(cover, platforms)

	var over := 3.0 / U - 0.6
	var bounds := AABB(
		Vector3((EX0 - over) * U, 0.0, (UZ0 - over) * U),
		Vector3((45.0 - EX0 + 2.0 * over) * U, H * U, (BZ1 - UZ0 + 2.0 * over) * U))

	# 本关全封闭，不做「相机在墙外就隐藏墙面」：墙面始终渲染。

	# 面向 +X（船坞方向）：第三人称镜头落在走廊里，而不是穿墙
	var spawn := Transform3D(Basis(Vector3.UP, -PI * 0.5), SPAWN * U)

	return {
		"node": root,
		"kind": "hangar",
		"name_cn": "三号船坞",
		"hint": "沿地面黄色走道绕到东南气闸。甲板上是 Boss 的位置占位。",
		"floor_y": 0.0,
		"bounds": bounds,
		"walls": walls,
		"cover": cover,
		"platforms": platforms,
		"camera_open": false,
		"ceiling": H * U,
		"spawns": [],
		"wall_slots": [],
		"lamps": [],
		"player_spawn": spawn,
	}


# ================================================================== 材质
static func _mats() -> void:
	_M = {
		"apron": Kit.std(Color(0.105, 0.112, 0.124), 0.70, 0.28,
			{"noise": 2.4, "grime": 0.22, "bump": 0.20, "streak": 0.12,
			"dirt": Color(0.020, 0.022, 0.026)}),
		"deck": Kit.std(Color(0.155, 0.166, 0.180), 0.70, 0.30,
			{"noise": 3.2, "grime": 0.26, "bump": 0.16, "streak": 0.16,
			"dirt": Color(0.030, 0.032, 0.036)}),
		"table": Kit.std(Color(0.196, 0.208, 0.222), 0.62, 0.34,
			{"noise": 3.6, "grime": 0.18, "bump": 0.12}),
		"wall": Kit.std(Color(0.135, 0.148, 0.164), 0.74, 0.14,
			{"noise": 7.0, "grime": 0.16, "bump": 0.22, "streak": 0.34, "tint": 0.04,
			"dirt": Color(0.026, 0.030, 0.036)}),
		"wall_dark": Kit.std(Color(0.062, 0.070, 0.080), 0.62, 0.40),
		"steel": Kit.std(Color(0.255, 0.272, 0.292), 0.48, 0.52),
		"steel_hot": Kit.std(Color(0.330, 0.336, 0.324), 0.52, 0.46),
		"rust": Kit.std(Color(0.145, 0.098, 0.070), 0.72, 0.35,
			{"noise": 1.6, "grime": 0.85, "streak": 0.6}),
		"rubber": Kit.std(Color(0.028, 0.028, 0.032), 0.90, 0.0),
		"amber": Kit.emissive(Color(0.98, 0.62, 0.10), 1.1, 0.16),
		"white_line": Kit.emissive(Color(0.72, 0.80, 0.86), 0.30, 0.35),
		"red": Kit.emissive(Color(1.0, 0.12, 0.08), 1.5),
		"green": Kit.emissive(Color(0.24, 1.0, 0.52), 1.6),
		"cyan": Kit.emissive(Color(0.32, 0.86, 1.0), 1.9),
		"lamp": Kit.emissive(Color(0.80, 0.90, 1.0), 3.0, 0.10),
		"warm": Kit.emissive(Color(1.0, 0.78, 0.46), 2.2, 0.12),
		"glass": Kit.glass(Color(0.30, 0.52, 0.64), 0.24),
		"paint": Kit.std(Color(0.520, 0.380, 0.075), 0.72, 0.15,
			{"noise": 4.0, "grime": 0.38, "bump": 0.18, "streak": 0.30}),
		"cabinet_red": Kit.std(Color(0.400, 0.062, 0.050), 0.58, 0.22,
			{"noise": 3.0, "grime": 0.26, "bump": 0.16, "streak": 0.30}),
		"hose": Kit.std(Color(0.055, 0.058, 0.062), 0.82, 0.05,
			{"noise": 6.0, "grime": 0.20, "bump": 0.30}),
		"tank": Kit.std(Color(0.610, 0.622, 0.634), 0.38, 0.72,
			{"noise": 2.4, "grime": 0.07, "bump": 0.05, "streak": 0.20, "tint": 0.02,
			"dirt": Color(0.060, 0.062, 0.064)}),
		"paper": Kit.std(Color(0.760, 0.745, 0.700), 0.94, 0.0,
			{"noise": 9.0, "grime": 0.10, "bump": 0.04, "streak": 0.05}),
		"tank_band": Kit.std(Color(0.760, 0.770, 0.755), 0.60, 0.05),
		"bay_back": Kit.std(Color(0.052, 0.058, 0.066), 0.80, 0.10,
			{"noise": 5.0, "grime": 0.30, "bump": 0.20, "streak": 0.40}),
		"door": Kit.std(Color(0.165, 0.176, 0.190), 0.70, 0.22,
			{"noise": 3.4, "grime": 0.30, "bump": 0.22, "streak": 0.30}),
		"shuttle": Kit.std(Color(0.290, 0.300, 0.310), 0.56, 0.34,
			{"noise": 4.5, "grime": 0.24, "bump": 0.20, "streak": 0.22}),
		"hull": Kit.std(Color(0.180, 0.192, 0.208), 0.66, 0.26,
			{"noise": 5.5, "grime": 0.20, "bump": 0.26, "streak": 0.26}),
	}


static func _environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.007, 0.011)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.20, 0.26)
	env.ambient_light_energy = 0.40
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.02
	env.tonemap_white = 3.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 0.92
	env.adjustment_brightness = 1.02

	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.90
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.024, 0.048, 0.062)
	env.fog_light_energy = 0.38
	env.fog_depth_begin = 22.0 * U
	env.fog_depth_end = 150.0 * U
	env.fog_density = 0.62
	env.fog_sky_affect = 0.0

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0075
	env.volumetric_fog_albedo = Color(0.05, 0.09, 0.11)
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_anisotropy = 0.25

	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.6
	env.ssao_power = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 24
	env.ssr_fade_out = 2.4

	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.42, 0.56, 0.78)
	sun.light_energy = 0.10
	sun.rotation_degrees = Vector3(-54.0, 28.0, 0.0)
	root.add_child(sun)


# ================================================================== 地面
static func _floor(root: Node3D) -> void:
	_b(root, Vector3(2 * HX + 1.0, 0.6, 2 * HZ + 1.0), Vector3(0.0, -0.30, 0.0), _M["apron"])
	_b(root, Vector3(BX1 - BX0, 0.6, BZ1 - BZ0), Vector3((BX0 + BX1) * 0.5, -0.30, (BZ0 + BZ1) * 0.5), _M["apron"])
	_b(root, Vector3(UX1 - UX0, 0.6, UZ1 - UZ0), Vector3((UX0 + UX1) * 0.5, -0.30, (UZ0 + UZ1) * 0.5), _M["apron"])
	_b(root, Vector3(EX1 - EX0, 0.6, EZ1 - EZ0), Vector3((EX0 + EX1) * 0.5, -0.30, (EZ0 + EZ1) * 0.5), _M["apron"])
	_b(root, Vector3(AX1 - AX0, 0.6, AZ1 - AZ0), Vector3((AX0 + AX1) * 0.5, -0.30, (AZ0 + AZ1) * 0.5), _M["apron"])


static func _deck(root: Node3D) -> void:
	# 系留甲板：r=25 的圆盘，比周围地面高 4 cm
	Kit.cylinder(root, DECK_R * U, 0.02 * U, Vector3(0.0, 0.01 * U, 0.0), _M["deck"], Vector3.ZERO)
	# 转盘：r=15 的圆盘，高 9 cm，外缘一道亮钢圈
	Kit.annulus(root, 23.6 * U, DECK_R * U, 128, 0.081 * U, _M["wall_dark"])
	Kit.cylinder(root, TABLE_R * U, 0.05 * U, Vector3(0.0, 0.025 * U, 0.0), _M["table"], Vector3.ZERO)
	Kit.annulus(root, (TABLE_R - 0.30) * U, TABLE_R * U, 96, 0.055 * U, _M["steel_hot"])

	# 甲板板缝（裁在圆内）
	var sx := -24.0
	while sx <= 24.0:
		var half := sqrt(maxf(0.0, DECK_R * DECK_R - sx * sx)) - 0.4
		if half > 0.2:
			_b(root, Vector3(0.05, 0.012, half * 2.0), Vector3(sx, 0.086, 0.0), _M["wall_dark"])
		sx += 4.0
	var sz := -24.0
	while sz <= 24.0:
		var half2 := sqrt(maxf(0.0, DECK_R * DECK_R - sz * sz)) - 0.4
		if half2 > 0.2:
			_b(root, Vector3(half2 * 2.0, 0.012, 0.05), Vector3(0.0, 0.086, sz), _M["wall_dark"])
		sz += 4.0
	# 转盘板缝
	var tx := -13.0
	while tx <= 13.0:
		var th := sqrt(maxf(0.0, TABLE_R * TABLE_R - tx * tx)) - 0.3
		if th > 0.2:
			_b(root, Vector3(0.05, 0.012, th * 2.0), Vector3(tx, 0.188, 0.0), _M["wall_dark"])
		tx += 3.0

	# 转盘辐条槽 + 中心系留座
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector3(cos(a), 0.0, sin(a))
		var p0 := d * 3.4
		var p1 := d * (TABLE_R - 0.7)
		_b(root, Vector3(0.34, 0.03, (p1 - p0).length()), Vector3((p0 + p1) * 0.5 + Vector3(0.0, 0.055, 0.0)),
			_M["wall_dark"], Vector3(0.0, -atan2(d.z, d.x) + PI * 0.5, 0.0))
	Kit.cylinder(root, 3.2 * U, 0.06 * U, Vector3(0.0, 0.09 * U, 0.0), _M["wall_dark"], Vector3.ZERO)
	Kit.annulus(root, 3.1 * U, 3.3 * U, 48, 0.125 * U, _M["amber"])

	# 地面轨道：北舱 → 转盘，转盘 → 东门
	for o in [-1.7, 1.7]:
		_b(root, Vector3(0.16, 0.03, BZ0 - 14.0), Vector3(o, 0.055, (BZ0 + 14.0) * 0.5), _M["steel"])
		_b(root, Vector3(0.16, 0.02, 0.30), Vector3(o, 0.045, 0.0), _M["wall_dark"])
		_b(root, Vector3(HX - 14.5, 0.03, 0.16), Vector3((14.5 + HX) * 0.5, 0.055, o), _M["steel"])
	# 轨枕
	var z := 15.0
	while z < BZ0 - 0.5:
		_b(root, Vector3(4.2, 0.02, 0.20), Vector3(0.0, 0.045, z), _M["wall_dark"])
		z += 1.6

	# 甲板边缘的系留环
	for i in 24:
		var a := TAU * float(i) / 24.0
		var p := Vector3(cos(a) * (DECK_R - 1.4), 0.03, sin(a) * (DECK_R - 1.4))
		Kit.cylinder(root, 0.22 * U, 0.05 * U, p * U, _M["steel"])
		Kit.annulus(root, 0.13 * U, 0.19 * U, 12, 0.055 * U, _M["amber"]).position = p * U


static func _markings(root: Node3D) -> void:
	var y := 0.022
	# 甲板外圈（白）
	_dash_ring(root, DECK_R - 0.55, 0.16, 2.4, 1.6, 0.032, _M["white_line"])
	# 安全走道（黄）：西门 → 北侧 → 东侧 → 气闸
	var walk: Array = [
		Vector2(EX1, 28.5), Vector2(33.0, 28.5),
		Vector2(33.0, -22.5), Vector2(AX0, -22.5),
	]
	for i in walk.size() - 1:
		var a: Vector2 = walk[i]
		var b: Vector2 = walk[i + 1]
		_dash_line(root, a + Vector2(0.0, 0.9), b + Vector2(0.0, 0.9), 0.12, 1.2, 1.0, y, _M["amber"])
		_dash_line(root, a - Vector2(0.0, 0.9), b - Vector2(0.0, 0.9), 0.12, 1.2, 1.0, y, _M["amber"])
	# 甲板上的人行横线（通向气闸）
	_dash_line(root, Vector2(25.5, -22.5), Vector2(AX0, -22.5), 0.12, 1.2, 1.0, y, _M["amber"])
	# 门槛警示条

	# 地面字：DOCK 03
	_label(root, "DOCK 03", Vector3(-16.0, 0.04, 6.0), 1.5, Color(0.42, 0.46, 0.50), -90.0)
	_label(root, "BAY 03", Vector3(-13.0, 0.05, 33.0), 1.1, Color(0.50, 0.44, 0.28), -90.0)


# ================================================================== 外壳
static func _shell(root: Node3D) -> void:
	var shell := Node3D.new()
	shell.name = "Shell"
	root.add_child(shell)
	var gn := Node3D.new()
	gn.name = "North"
	var gs := Node3D.new()
	gs.name = "South"
	var ge := Node3D.new()
	ge.name = "East"
	var gw := Node3D.new()
	gw.name = "West"
	var gr := Node3D.new()
	gr.name = "Roof"
	for g in [gn, gs, ge, gw, gr]:
		shell.add_child(g)

	var wall: Material = _M["wall"]
	var dark: Material = _M["wall_dark"]
	var steel: Material = _M["steel"]
	var strip: Material = Kit.emissive(Color(0.34, 0.80, 1.0), 1.7, 0.14)

	# ---- 北墙：留 24 m 维修舱口（x -24…0，高 9.5）
	_slab(gn, -HX, BAY_OPEN0, 0.0, H, HZ, HZ + 0.4, wall)
	_slab(gn, BAY_OPEN1, HX, 0.0, H, HZ, HZ + 0.4, wall)
	_slab(gn, BAY_OPEN0, BAY_OPEN1, BH, H, HZ, HZ + 0.4, wall)
	# ---- 南墙：留 8 m 勤务舱口（x 2…10，高 8）
	_slab(gs, -HX, U_OPEN0, 0.0, H, -HZ - 0.4, -HZ, wall)
	_slab(gs, U_OPEN1, HX, 0.0, H, -HZ - 0.4, -HZ, wall)
	_slab(gs, U_OPEN0, U_OPEN1, UH, H, -HZ - 0.4, -HZ, wall)
	# ---- 东墙：留 30 × 16 舰载机门 + 6 m 气闸口
	_slab(ge, HX, HX + 0.4, 0.0, H, -HZ, AZ0, wall)
	_slab(ge, HX, HX + 0.4, 0.0, H, AZ1, -VD_Z, wall)
	_slab(ge, HX, HX + 0.4, 0.0, H, VD_Z, HZ, wall)
	_slab(ge, HX, HX + 0.4, VD_H, H, -VD_Z, VD_Z, wall)
	_slab(ge, HX, HX + 0.4, AH, H, AZ0, AZ1, wall)
	# ---- 西墙：留 5 × 4.6 人员入口
	_slab(gw, -HX - 0.4, -HX, 0.0, H, -HZ, EZ0, wall)
	_slab(gw, -HX - 0.4, -HX, 0.0, H, EZ1, HZ, wall)
	_slab(gw, -HX - 0.4, -HX, EH, H, EZ0, EZ1, wall)

	# ---- 顶棚：分块板 + 桁架（屋顶组，相机到屋外时自动隐藏）
	for x in range(-32, 33, 8):
		_slab(gr, float(x), float(x + 8), H, H + 0.5, -HZ, HZ, dark)
	# 屋面下的横梁
	for x in range(-36, 37, 8):
		_b(root, Vector3(0.7, 0.9, 2 * HZ), Vector3(float(x), H - 1.3, 0.0), _M["hull"])
		for zz2 in [-24.0, -12.0, 0.0, 12.0, 24.0]:
			_b(root, Vector3(0.36, 1.0, 0.36), Vector3(float(x), H - 0.75, zz2), steel)
	# 纵向桁架杆
	for zz3 in [-24.0, -12.0, 0.0, 12.0, 24.0]:
		_b(root, Vector3(2 * HX - 2.0, 0.34, 0.34), Vector3(0.0, H - 0.55, zz3), _M["hull"])

	# ---- 墙面：按实墙分段（洞口处不生成板缝和灯带）
	var north_r: Array = [[-HX, BAY_OPEN0], [BAY_OPEN1, HX]]
	var south_r: Array = [[-HX, U_OPEN0], [U_OPEN1, HX]]
	var east_r: Array = [[-HZ, AZ0], [AZ1, -VD_Z], [VD_Z, HZ]]
	var west_r: Array = [[-HZ, EZ0], [EZ1, HZ]]
	_wall_details(gn, north_r, HZ, -1.0, true, wall, steel, strip)
	_wall_details(gs, south_r, -HZ, 1.0, true, wall, steel, strip)
	_wall_details(ge, east_r, HX, -1.0, false, wall, steel, strip)
	_wall_details(gw, west_r, -HX, 1.0, false, wall, steel, strip)

	# ---- 结构门架：立柱贴墙，顶梁横跨
	for x in range(-32, 33, 8):
		var fx := float(x)
		_b(root, Vector3(0.55, H, 0.55), Vector3(fx, H * 0.5, -HZ + 0.35), steel)
		_b(root, Vector3(0.55, H, 0.55), Vector3(fx, H * 0.5, HZ - 0.35), steel)

	# ---- 墙面舱段标识
	_label(root, "03", Vector3(-HX + 0.06, 16.0, -6.0), 3.0, Color(0.52, 0.58, 0.64), 0.0, Vector3(0.0, 90.0, 0.0))
	_label(root, "DOCK", Vector3(18.0, 16.0, HZ - 0.06), 2.6, Color(0.52, 0.58, 0.64), 0.0)


static func _wall_details(g: Node3D, ranges: Array, fixed: float, inward: float,
		along_x: bool, wall: Material, steel: Material, strip: Material) -> void:
	for r in ranges:
		var a: float = r[0]
		var b: float = r[1]
		if b - a < 0.6:
			continue
		var zo := fixed + inward * 0.11
		var zs := fixed + inward * 0.05
		var zt := fixed + inward * 0.16
		if along_x:
			_slab(g, a, b, 0.0, 1.15, minf(zo, fixed), maxf(zo, fixed), _M["rust"])
			_slab(g, a, b, 3.55, 3.70, minf(zs, fixed), maxf(zs, fixed), strip)
			_slab(g, a, b, 12.2, 12.6, minf(zt, fixed), maxf(zt, fixed), steel)
		else:
			_slab(g, minf(zo, fixed), maxf(zo, fixed), 0.0, 1.15, a, b, _M["rust"])
			_slab(g, minf(zs, fixed), maxf(zs, fixed), 3.55, 3.70, a, b, strip)
			_slab(g, minf(zt, fixed), maxf(zt, fixed), 12.2, 12.6, a, b, steel)
		var t := a + 1.5
		while t < b - 1.0:
			if along_x:
				_b(g, Vector3(0.07, H - 1.4, 0.10), Vector3(t, H * 0.5, fixed + inward * 0.05), steel)
			else:
				_b(g, Vector3(0.10, H - 1.4, 0.07), Vector3(fixed + inward * 0.05, H * 0.5, t), steel)
			t += 3.0


static func _slab(parent: Node3D, x0: float, x1: float, y0: float, y1: float,
		z0: float, z1: float, mat: Material) -> void:
	if x1 - x0 < 0.01 or y1 - y0 < 0.01 or z1 - z0 < 0.01:
		return
	_b(parent, Vector3(x1 - x0, y1 - y0, z1 - z0),
		Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), mat)


# ================================================================== 西门
static func _entry(root: Node3D) -> void:
	# 走廊：外门锁死（红），内门通向甲板
	_b(root, Vector3(EX1 - EX0, EH, 0.3), Vector3((EX0 + EX1) * 0.5, EH * 0.5, EZ0 - 0.15), _M["wall"])
	_b(root, Vector3(EX1 - EX0, EH, 0.3), Vector3((EX0 + EX1) * 0.5, EH * 0.5, EZ1 + 0.15), _M["wall"])
	_b(root, Vector3(EX1 - EX0, 0.3, EZ1 - EZ0), Vector3((EX0 + EX1) * 0.5, EH, (EZ0 + EZ1) * 0.5), _M["wall_dark"])
	# 外门
	_b(root, Vector3(0.35, EH, EZ1 - EZ0), Vector3(EX0 + 0.18, EH * 0.5, (EZ0 + EZ1) * 0.5), _M["steel"])
	_b(root, Vector3(0.10, 0.28, 1.1), Vector3(EX0 + 0.42, 3.4, (EZ0 + EZ1) * 0.5), _M["red"])
	# 内门框 + 橡胶密封
	_b(root, Vector3(0.30, EH, 0.35), Vector3(EX1 - 0.15, EH * 0.5, EZ0 - 0.1), _M["steel"])
	_b(root, Vector3(0.30, EH, 0.35), Vector3(EX1 - 0.15, EH * 0.5, EZ1 + 0.1), _M["steel"])
	_b(root, Vector3(0.30, 0.35, EZ1 - EZ0), Vector3(EX1 - 0.15, EH - 0.2, (EZ0 + EZ1) * 0.5), _M["steel"])
	# 门顶指示灯：绿 = 可通行
	_b(root, Vector3(0.16, 0.16, 0.5), Vector3(EX1 - 0.35, EH - 0.55, (EZ0 + EZ1) * 0.5), _M["green"])
	# 走廊照明：贴顶中线，避免镜头贴着灯带
	for dz in [-3.2, 0.0, 3.2]:
		_b(root, Vector3(0.16, 0.06, 0.9), Vector3((EX0 + EX1) * 0.5 + dz, EH - 0.18, (EZ0 + EZ1) * 0.5),
			Kit.emissive(Color(0.80, 0.88, 1.0), 1.4, 0.12))
	# 地面引导
	_dash_line(root, Vector2(EX1 - 3.0, 28.5), Vector2(EX1, 28.5), 0.12, 0.8, 0.6, 0.022, _M["amber"])
	_label(root, "DOCK 03  →", Vector3(EX0 + 1.2, 2.2, EZ1 - 0.6), 0.8, Color(0.85, 0.70, 0.30), 0.0, Vector3(0.0, 90.0, 0.0))


# ================================================================== 维修舱
static func _bay(root: Node3D, cover: Array, platforms: Array) -> void:
	var wall: Material = _M["wall"]
	# 侧墙与后墙
	_b(root, Vector3(0.4, BH, BZ1 - BZ0 + 0.4), Vector3(BX0 + 0.2, BH * 0.5, (BZ0 + BZ1) * 0.5 - 0.2), wall)
	_b(root, Vector3(0.4, BH, BZ1 - BZ0 + 0.4), Vector3(BX1 - 0.2, BH * 0.5, (BZ0 + BZ1) * 0.5 - 0.2), wall)
	_b(root, Vector3(BX1 - BX0, BH, 0.4), Vector3((BX0 + BX1) * 0.5, BH * 0.5, BZ1 - 0.2), _M["bay_back"])
	_b(root, Vector3(BX1 - BX0, 0.4, BZ1 - BZ0), Vector3((BX0 + BX1) * 0.5, BH, (BZ0 + BZ1) * 0.5), _M["wall"])
	# 开口两侧的短墙（主厅北墙上 24 m 的洞）
	_b(root, Vector3(BAY_OPEN0 - (BX0 + 0.4), BH, 0.5), Vector3((BX0 + 0.4 + BAY_OPEN0) * 0.5, BH * 0.5, BZ0), wall)
	_b(root, Vector3(BX1 - 0.4 - BAY_OPEN1, BH, 0.5), Vector3((BAY_OPEN1 + BX1 - 0.4) * 0.5, BH * 0.5, BZ0), wall)
	# 门楣
	_b(root, Vector3(BAY_OPEN1 - BAY_OPEN0 + 0.8, H - BH, 0.7), Vector3((BAY_OPEN0 + BAY_OPEN1) * 0.5, (BH + H) * 0.5, BZ0), _M["hull"])

	# 三座门架
	for gx in [-22.0, -10.0, 2.0]:
		_b(root, Vector3(0.42, 8.2, 0.42), Vector3(gx, 4.1, BZ0 + 0.6), _M["steel"])
		_b(root, Vector3(0.42, 8.2, 0.42), Vector3(gx, 4.1, BZ1 - 0.6), _M["steel"])
		_b(root, Vector3(0.5, 0.45, BZ1 - BZ0 - 1.2), Vector3(gx, 8.2, (BZ0 + BZ1) * 0.5), _M["steel"])
		_b(root, Vector3(0.9, 0.16, 1.4), Vector3(gx, 7.9, BZ0 + 3.2), _M["warm"])

	# 穿梭机：圆截面机身 + 鼻锥 + 尾锥 + 座舱脊 + 后掠翼 + 发动机舱（沿 x 停放）
	var sh := Node3D.new()
	sh.name = "Shuttle"
	root.add_child(sh)
	var hullm: Material = _M["shuttle"]
	var dark: Material = _M["wall_dark"]

	# 机身（圆截面，沿 X）
	var fus := CylinderMesh.new()
	fus.top_radius = 1.32 * U
	fus.bottom_radius = 1.32 * U
	fus.height = 10.0 * U
	fus.radial_segments = 16
	var fmi := MeshInstance3D.new()
	fmi.mesh = fus
	fmi.material_override = hullm
	fmi.position = Vector3(-12.0, 3.05, 39.0) * U
	fmi.rotation = Vector3(0.0, 0.0, PI * 0.5)
	sh.add_child(fmi)

	# 鼻锥 + 尾锥
	var nose := Kit.cone(sh, 1.32 * U, 2.6 * U, Vector3(-5.7, 3.05, 39.0) * U, hullm)
	nose.rotation = Vector3(0.0, 0.0, -PI * 0.5)
	var tail_c := CylinderMesh.new()
	tail_c.top_radius = 0.86 * U
	tail_c.bottom_radius = 1.32 * U
	tail_c.height = 2.2 * U
	tail_c.radial_segments = 16
	var tmi := MeshInstance3D.new()
	tmi.mesh = tail_c
	tmi.material_override = hullm
	tmi.position = Vector3(-18.1, 3.05, 39.0) * U
	tmi.rotation = Vector3(0.0, 0.0, -PI * 0.5)
	sh.add_child(tmi)

	# 座舱脊（半埋的圆柱）
	var can := CylinderMesh.new()
	can.top_radius = 0.78 * U
	can.bottom_radius = 0.78 * U
	can.height = 3.0 * U
	can.radial_segments = 14
	var cmi := MeshInstance3D.new()
	cmi.mesh = can
	cmi.material_override = _M["glass"]
	cmi.position = Vector3(-9.2, 4.05, 39.0) * U
	cmi.rotation = Vector3(0.0, 0.0, PI * 0.5)
	sh.add_child(cmi)

	# 机翼：内段 + 外段（后掠、渐缩），比单块平板像机翼
	for side in [-1.0, 1.0]:
		_b(sh, Vector3(5.4, 0.24, 2.4), Vector3(-12.2, 2.85, 39.0 + side * 1.95), hullm)
		_b(sh, Vector3(2.8, 0.18, 1.6), Vector3(-13.2, 2.90, 39.0 + side * 3.18), hullm)
		# 翼尖小翼
		_b(sh, Vector3(1.2, 0.52, 0.12), Vector3(-14.3, 3.10, 39.0 + side * 3.62), hullm)
		# 发动机舱 + 喷口
		Kit.cylinder(sh, 0.52 * U, 2.6 * U, Vector3(-16.6, 2.35, 39.0 + side * 2.6) * U, hullm,
			Vector3(0.0, 0.0, PI * 0.5))
		Kit.cylinder(sh, 0.44 * U, 0.22 * U, Vector3(-17.9, 2.35, 39.0 + side * 2.6) * U, dark,
			Vector3(0.0, 0.0, PI * 0.5))
		# 机翼外侧黄色标记
		_b(sh, Vector3(2.2, 0.05, 0.40), Vector3(-13.2, 3.01, 39.0 + side * 3.05), _M["paint"])

	# 垂尾
	_b(sh, Vector3(2.4, 2.6, 0.18), Vector3(-18.55, 4.45, 39.0), hullm, Vector3(0.0, 0.0, 0.16))
	_b(sh, Vector3(1.1, 0.7, 0.24), Vector3(-19.0, 5.4, 39.0), _M["paint"])

	# 腹部整流罩（打破“香肠”感）+ 深色鼻锥雷达罩
	_b(sh, Vector3(8.2, 0.55, 1.9), Vector3(-13.0, 2.05, 39.0), _M["wall_dark"])
	_b(sh, Vector3(0.9, 0.55, 1.1), Vector3(-4.6, 3.05, 39.0), _M["wall_dark"])
	# 驾驶舱风挡
	for side in [-1.0, 1.0]:
		_b(sh, Vector3(1.5, 0.42, 0.05), Vector3(-7.3, 3.85, 39.0 + side * 0.62),
			_M["glass"], Vector3(0.0, side * 0.55, 0.0))
	# 发动机进气环
	for side in [-1.0, 1.0]:
		Kit.torus(sh, 0.52 * U, 0.05 * U, Vector3(-15.3, 2.35, 39.0 + side * 2.6) * U,
			_M["steel"], 20)

	# 机身环向板缝
	for px in [-16.0, -13.0, -10.0, -7.0]:
		Kit.torus(sh, 1.33 * U, 0.035 * U, Vector3(px, 3.05, 39.0) * U, dark, 24)
	# 侧舷窗带
	for side in [-1.0, 1.0]:
		_b(sh, Vector3(3.6, 0.30, 0.05), Vector3(-8.6, 3.65, 39.0 + side * 1.28), _M["glass"])

	# 起落架：支柱 + 撬板
	for dz in [-1.35, 1.35]:
		_b(sh, Vector3(0.16, 1.75, 0.16), Vector3(-15.5, 1.62, 39.0 + dz), _M["steel"])
		_b(sh, Vector3(0.16, 1.75, 0.16), Vector3(-9.0, 1.62, 39.0 + dz), _M["steel"])
		_b(sh, Vector3(7.0, 0.18, 0.30), Vector3(-12.2, 0.85, 39.0 + dz), _M["steel"])

	# 检修台架（黄漆，不发光）
	for dz in [-4.45, 4.45]:
		_b(sh, Vector3(8.0, 0.14, 0.8), Vector3(-15.0, 1.42, 39.0 + dz), _M["paint"])
		for k in 3:
			_b(sh, Vector3(0.14, 1.42, 0.14), Vector3(-18.5 + float(k) * 3.5, 0.71, 39.0 + dz), _M["steel"])

	# 上机翼的三级检修梯（机翼东南角）
	for k in 3:
		var sx2: float = -7.0 - float(k) * 0.9
		var stop: float = 0.65 * float(k + 1)
		_b(root, Vector3(0.9, 0.10, 0.9), Vector3(sx2, stop, 35.9), _M["paint"])
		_b(root, Vector3(0.08, stop, 0.08), Vector3(sx2 - 0.4, stop * 0.5, 35.9), _M["steel"])
		_b(root, Vector3(0.08, stop, 0.08), Vector3(sx2 + 0.4, stop * 0.5, 35.9), _M["steel"])
		platforms.append({"c": Vector3(sx2, 0.0, 35.9) * U,
			"hx": 0.45 * U, "hz": 0.45 * U, "h": stop * U})
		_cov(cover, Vector3(sx2, 0.0, 35.9), 0.42, stop - 0.34)

	# 舱内背光条（让开口里有层次，不是黑洞）
	_slab(root, BX0 + 0.5, BX1 - 0.5, 8.4, 8.55, BZ1 - 0.45, BZ1 - 0.32,
		Kit.emissive(Color(0.36, 0.58, 0.82), 0.9, 0.14))
	for lx in [-17.0, -5.0]:
		_b(root, Vector3(6.0, 0.10, 0.26), Vector3(lx, BH - 0.45, BZ0 + 1.2), _M["warm"])

	# 工具间：柜列 + 工作台 + 零件架
	_b(root, Vector3(0.8, 2.2, 7.0), Vector3(BX0 + 0.9, 1.1, 36.0), _M["steel_hot"])
	for k in 4:
		_b(root, Vector3(0.06, 1.9, 0.06), Vector3(BX0 + 1.32, 1.0, 33.4 + float(k) * 1.7), _M["wall_dark"])
	_b(root, Vector3(3.2, 0.12, 1.4), Vector3(BX0 + 2.6, 1.0, 42.0), _M["steel_hot"])
	_b(root, Vector3(0.12, 1.0, 0.12), Vector3(BX0 + 1.2, 0.5, 42.0), _M["steel"])
	_b(root, Vector3(3.0, 2.4, 0.5), Vector3(-4.0, 1.2, BZ1 - 0.7), _M["wall_dark"])
	for k in 3:
		_b(root, Vector3(2.8, 0.10, 0.6), Vector3(-4.0, 0.6 + float(k) * 0.7, BZ1 - 0.75), _M["rust"])

	# 舱内地面标线 + 编号
	_dash_line(root, Vector2(BX0 + 1.4, 35.0), Vector2(BX1 - 1.0, 35.0), 0.12, 1.4, 1.0, 0.022, _M["amber"])
	_label(root, "MAINT 03", Vector3(-20.0, 0.05, 41.5), 1.0, Color(0.50, 0.44, 0.28), -90.0)


# ================================================================== 勤务舱
static func _utility(root: Node3D) -> void:
	var wall: Material = _M["wall"]
	_b(root, Vector3(0.4, UH, UZ1 - UZ0 + 0.4), Vector3(UX0 + 0.2, UH * 0.5, (UZ0 + UZ1) * 0.5 + 0.2), wall)
	_b(root, Vector3(0.4, UH, UZ1 - UZ0 + 0.4), Vector3(UX1 - 0.2, UH * 0.5, (UZ0 + UZ1) * 0.5 + 0.2), wall)
	_b(root, Vector3(UX1 - UX0, UH, 0.4), Vector3((UX0 + UX1) * 0.5, UH * 0.5, UZ0 + 0.2), wall)
	_b(root, Vector3(UX1 - UX0, 0.4, UZ1 - UZ0), Vector3((UX0 + UX1) * 0.5, UH, (UZ0 + UZ1) * 0.5), _M["wall_dark"])
	# 主厅南墙上的开口（8 m）
	_b(root, Vector3(U_OPEN0 - UX0, UH, 0.5), Vector3((UX0 + U_OPEN0) * 0.5, UH * 0.5, -HZ), wall)
	_b(root, Vector3(UX1 - U_OPEN1, UH, 0.5), Vector3((U_OPEN1 + UX1) * 0.5, UH * 0.5, -HZ), wall)
	_b(root, Vector3(U_OPEN1 - U_OPEN0 + 0.8, H - UH, 0.7), Vector3((U_OPEN0 + U_OPEN1) * 0.5, (UH + H) * 0.5, -HZ), _M["hull"])
	# 卷帘门（半开）
	_b(root, Vector3(U_OPEN1 - U_OPEN0, 2.2, 0.16), Vector3((U_OPEN0 + U_OPEN1) * 0.5, UH - 1.1, -HZ + 0.35), _M["rust"])
	for k in 6:
		_b(root, Vector3(U_OPEN1 - U_OPEN0 - 0.2, 0.08, 0.22), Vector3((U_OPEN0 + U_OPEN1) * 0.5, UH - 2.0 + float(k) * 0.34, -HZ + 0.28), _M["steel"])

	# 灭火剂储罐组 + 围堰 + 阀组（不是燃料：紧邻作战甲板，用惰性灭火剂更合理）
	for tx in [-3.6, 0.8, 11.0, 15.6]:
		# 裙座 + 罐体 + 半球顶
		Kit.cylinder(root, 2.12 * U, 0.55 * U, Vector3(tx, 0.28, -39.5) * U, _M["rust"])
		var body := CylinderMesh.new()
		body.top_radius = 2.00 * U
		body.bottom_radius = 2.00 * U
		body.height = 5.40 * U
		body.radial_segments = 48
		body.rings = 1
		var bmi := MeshInstance3D.new()
		bmi.mesh = body
		bmi.material_override = _M["tank"]
		bmi.position = Vector3(tx, 3.25, -39.5) * U
		root.add_child(bmi)
		var dome := SphereMesh.new()
		dome.radius = 2.00 * U
		dome.height = 2.00 * U
		dome.radial_segments = 24
		dome.rings = 12
		var dm := MeshInstance3D.new()
		dm.mesh = dome
		dm.material_override = _M["tank"]
		dm.position = Vector3(tx, 5.95, -39.5) * U
		root.add_child(dm)
		# 白色标识带 + 铭牌
		Kit.cylinder(root, 2.03 * U, 0.38 * U, Vector3(tx, 4.35, -39.5) * U, _M["tank_band"])
		for k in 3:
			var off := float(k - 1) * 0.42
			var dz3 := sqrt(maxf(0.0, 4.0 - off * off))
			_b(root, Vector3(0.40, 0.34, 0.03),
				Vector3(tx + off, 4.35, -39.5 + dz3 + 0.02), _M["wall_dark"],
				Vector3(0.0, -asin(off / 2.0), 0.0))
		# 顶部接口
		Kit.cylinder(root, 0.26 * U, 0.75 * U, Vector3(tx, 7.30, -39.5) * U, _M["steel"])
		# 泄压管：从顶部沿罐体侧面向下接到阀组
		_b(root, Vector3(0.14, 1.6, 0.14), Vector3(tx + 1.55, 6.55, -38.0), _M["steel"])
		_b(root, Vector3(0.14, 0.14, 1.6), Vector3(tx + 1.55, 5.75, -38.6), _M["steel"])
		# 罐侧直梯（朝大厅一侧）
		for dx in [-0.34, 0.34]:
			_b(root, Vector3(0.07, 5.40, 0.07), Vector3(tx + dx, 3.25, -37.62), _M["steel"])
		for k in 13:
			_b(root, Vector3(0.74, 0.05, 0.05), Vector3(tx, 0.70 + float(k) * 0.40, -37.62), _M["steel"])
		# 阀组：落在围堰外侧的走道上（不在堰体里），跨过堰顶接进罐体
		_b(root, Vector3(0.36, 0.07, 0.36), Vector3(tx, 0.035, -36.55), _M["steel"])
		Kit.cylinder(root, 0.10 * U, 1.45 * U, Vector3(tx, 0.755, -36.55) * U, _M["steel_hot"])
		_b(root, Vector3(0.30, 0.30, 0.30), Vector3(tx, 1.30, -36.55), _M["steel_hot"])
		Kit.torus(root, 0.20 * U, 0.035 * U, Vector3(tx, 1.50, -36.55) * U, _M["paint"], 20)
		Kit.cylinder(root, 0.05 * U, 0.18 * U, Vector3(tx, 1.50, -36.55) * U, _M["steel"])
		_b(root, Vector3(0.10, 0.10, 1.00), Vector3(tx, 1.28, -37.05), _M["steel"])
		_b(root, Vector3(0.10, 0.30, 0.10), Vector3(tx, 1.13, -37.55), _M["steel"])
	# 罐壁上的几张便条（贴着圆柱面，暂时不写字）
	_tank_papers(root, -3.6, -39.5, 2.0)

	# 集合管：沿罐列把阀组串起来
	_b(root, Vector3(22.0, 0.16, 0.16), Vector3(6.0, 1.05, -36.55), _M["steel_hot"])
	_b(root, Vector3(0.42, 0.42, 0.12), Vector3(-5.02, 1.05, -36.55), _M["rust"])
	# 围堰
	_b(root, Vector3(24.0, 1.1, 0.35), Vector3(6.0, 0.55, -37.0), _M["wall_dark"])
	_b(root, Vector3(0.35, 1.1, 7.175), Vector3(-5.825, 0.55, -40.4125), _M["wall_dark"])
	_b(root, Vector3(0.35, 1.1, 7.175), Vector3(17.825, 0.55, -40.4125), _M["wall_dark"])
	# 顶部管束
	for dz in [-41.0, -40.2, -39.4]:
		_b(root, Vector3(26.0, 0.16, 0.16), Vector3(6.0, 7.2, dz), _M["steel"])
	_label(root, "FIRE SUPPRESSANT", Vector3(6.0, 9.6, -33.92), 0.9,
		Color(0.62, 0.70, 0.66), 0.0)

	# 消防柜 + 软管盘
	_fire_cabinet(root, 13.6, -33.78)


## 贴在储罐圆柱面上的几张便条：每张按所在角度旋转，贴合曲面。
static func _tank_papers(root: Node3D, tx: float, cz: float, r: float) -> void:
	var specs: Array = [
		[168.0, 1.52, 0.30, 0.42, -4.0],
		[176.5, 1.74, 0.26, 0.36, 3.5],
		[184.0, 1.46, 0.28, 0.40, -2.0],
		[193.0, 1.64, 0.24, 0.32, 5.5],
	]
	for sp in specs:
		var th: float = deg_to_rad(float(sp[0]))
		var pos := Vector3(tx + sin(th) * (r + 0.012), float(sp[1]), cz + cos(th) * (r + 0.012))
		_b(root, Vector3(float(sp[2]), float(sp[3]), 0.012), pos, _M["paper"],
			Vector3(0.0, th, deg_to_rad(float(sp[4]))))


# ================================================================== 消防器材
## 立式消防柜：柜体 + 内嵌门 + 观察窗 + 拉手 + 铰链 + 底座
static func _fire_cabinet(root: Node3D, x: float, z: float) -> void:
	var w := 1.10
	var h := 1.70
	var d := 0.42
	_b(root, Vector3(w + 0.10, 0.12, d + 0.10), Vector3(x, 0.06, z), _M["wall_dark"])
	_b(root, Vector3(w, h, d), Vector3(x, 0.12 + h * 0.5, z), _M["cabinet_red"])
	# 门板（略凹）
	_b(root, Vector3(w - 0.16, h - 0.18, 0.04), Vector3(x, 0.12 + h * 0.5, z + d * 0.5 + 0.02), _M["cabinet_red"])
	_b(root, Vector3(w - 0.10, h - 0.10, 0.02), Vector3(x, 0.12 + h * 0.5, z + d * 0.5 - 0.01), _M["wall_dark"])
	# 观察窗
	_b(root, Vector3(0.46, 0.52, 0.03), Vector3(x, 0.12 + h - 0.48, z + d * 0.5 + 0.05), _M["glass"])
	# 拉手 + 铰链
	_b(root, Vector3(0.06, 0.26, 0.05), Vector3(x + w * 0.5 - 0.16, 0.12 + h * 0.5, z + d * 0.5 + 0.06), _M["steel_hot"])
	for hy in [0.12 + h * 0.25, 0.12 + h * 0.75]:
		_b(root, Vector3(0.10, 0.14, 0.04), Vector3(x - w * 0.5 + 0.02, hy, z + d * 0.5 + 0.04), _M["steel"])
	# 顶部标签带
	_b(root, Vector3(w - 0.06, 0.14, 0.02), Vector3(x, 0.12 + h - 0.10, z + d * 0.5 + 0.03), _M["tank_band"])
	_label(root, "FIRE", Vector3(x, 1.62, z + d * 0.5 + 0.07), 0.30, Color(0.88, 0.88, 0.84), 0.0)


## 壁挂软管盘：支架 + 两侧轮缘 + 卷筒 + 缠好的软管 + 下垂喷头
static func _hose_reel(root: Node3D, x: float, y: float, z: float) -> void:
	# 挂板与支臂（朝 +Z 伸出，即朝大厅）
	_b(root, Vector3(0.55, 0.62, 0.06), Vector3(x, y, z - 0.42), _M["steel"])
	_b(root, Vector3(0.10, 0.10, 0.42), Vector3(x, y + 0.16, z - 0.21), _M["steel"])
	_b(root, Vector3(0.08, 0.30, 0.08), Vector3(x, y, z - 0.06), _M["steel"])
	# 轮缘（用圆环，不是实心圆盘；这样能看到中间缠的软管）
	for dz in [-0.14, 0.14]:
		var rim := Kit.torus(root, 0.55 * U, 0.045 * U, Vector3(x, y, z + dz) * U,
			_M["cabinet_red"], 32)
		rim.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	# 卷筒 + 缠好的软管
	Kit.cylinder(root, 0.40 * U, 0.26 * U, Vector3(x, y, z) * U, _M["steel_hot"],
		Vector3(PI * 0.5, 0.0, 0.0))
	for dz in [-0.08, -0.03, 0.02, 0.07]:
		Kit.cylinder(root, 0.49 * U, 0.045 * U, Vector3(x, y, z + dz) * U, _M["hose"],
			Vector3(PI * 0.5, 0.0, 0.0))
	# 轴头
	for dz in [-0.20, 0.20]:
		Kit.cylinder(root, 0.11 * U, 0.06 * U, Vector3(x, y, z + dz) * U, _M["steel"],
			Vector3(PI * 0.5, 0.0, 0.0))
	# 下垂的软管与喷头
	_b(root, Vector3(0.07, 0.55, 0.07), Vector3(x + 0.42, y - 0.42, z + 0.02), _M["hose"])
	Kit.cylinder(root, 0.055 * U, 0.26 * U, Vector3(x + 0.42, y - 0.78, z + 0.02) * U, _M["steel_hot"])
	_b(root, Vector3(0.14, 0.10, 0.10), Vector3(x + 0.42, y - 0.90, z + 0.02), _M["cabinet_red"])


# ================================================================== 东端
static func _east(root: Node3D) -> void:
	# 舰载机大门：30 × 16 m，双扇，中缝 + 警示条 + 撞痕
	var door_z := VD_Z * 2.0
	_b(root, Vector3(0.6, VD_H, 0.9), Vector3(HX - 0.3, VD_H * 0.5, -VD_Z - 0.45), _M["hull"])
	_b(root, Vector3(0.6, VD_H, 0.9), Vector3(HX - 0.3, VD_H * 0.5, VD_Z + 0.45), _M["hull"])
	_b(root, Vector3(0.6, 1.4, door_z + 1.8), Vector3(HX - 0.3, VD_H + 0.7, 0.0), _M["hull"])
	for s in [-1.0, 1.0]:
		_b(root, Vector3(0.5, VD_H - 0.2, VD_Z - 0.15), Vector3(HX - 0.05, (VD_H - 0.2) * 0.5, s * (VD_Z * 0.5)), _M["door"])
		# 门扇加强筋
		var yy := 1.6
		while yy < VD_H - 1.0:
			_b(root, Vector3(0.16, 0.22, VD_Z - 0.5), Vector3(HX - 0.36, yy, s * (VD_Z * 0.5)), _M["hull"])
			yy += 1.8
	_b(root, Vector3(0.10, VD_H - 0.2, 0.12), Vector3(HX - 0.42, (VD_H - 0.2) * 0.5, 0.0), _M["amber"])
	# 撞痕：一块内凹的暗板 + 弯折筋
	_b(root, Vector3(0.10, 3.2, 4.4), Vector3(HX - 0.46, 4.6, 4.2), _M["wall_dark"])
	for k in 3:
		_b(root, Vector3(0.12, 0.18, 3.6), Vector3(HX - 0.50, 3.3 + float(k) * 1.2, 4.4), _M["rust"])
	# 门槛 + 地面黄黑条
	_b(root, Vector3(1.6, 0.10, door_z + 1.0), Vector3(HX - 0.9, 0.05, 0.0), _M["steel"])
	_hazard_band(root, Vector3(HX - 0.9, 0.12, 0.0), 1.0, door_z, 0.0)

	# 人员气闸：内门（绿）→ 小室 → 外门
	_b(root, Vector3(0.35, AH, AZ1 - AZ0 + 0.6), Vector3(AX0 + 0.18, AH * 0.5, (AZ0 + AZ1) * 0.5), _M["hull"])
	# 内门洞
	_b(root, Vector3(0.35, AH, A_DOOR1 - A_DOOR0), Vector3(AX1 - 0.2, AH * 0.5, (A_DOOR0 + A_DOOR1) * 0.5), _M["wall_dark"])
	_b(root, Vector3(0.2, 2.4, A_DOOR1 - A_DOOR0 - 0.4), Vector3(AX0 + 0.05, 1.2, (A_DOOR0 + A_DOOR1) * 0.5), _M["steel"])
	_b(root, Vector3(0.14, 0.14, 0.5), Vector3(AX0 + 0.2, 2.9, (A_DOOR0 + A_DOOR1) * 0.5), _M["green"])
	# 小室内壁
	_b(root, Vector3(AX1 - AX0, AH, 0.3), Vector3((AX0 + AX1) * 0.5, AH * 0.5, AZ0 + 0.15), _M["wall"])
	_b(root, Vector3(AX1 - AX0, AH, 0.3), Vector3((AX0 + AX1) * 0.5, AH * 0.5, AZ1 - 0.15), _M["wall"])
	_b(root, Vector3(AX1 - AX0, 0.3, AZ1 - AZ0), Vector3((AX0 + AX1) * 0.5, AH, (AZ0 + AZ1) * 0.5), _M["wall_dark"])
	# 外门（半开，透出舰内冷光）
	_b(root, Vector3(0.25, AH - 0.4, 1.6), Vector3(AX1 - 0.15, (AH - 0.4) * 0.5 + 0.2, AZ0 + 0.9), _M["steel"])
	_b(root, Vector3(0.12, 2.8, AZ1 - AZ0 - 1.4), Vector3(AX1 - 0.08, 1.5, (AZ0 + AZ1) * 0.5), _M["cyan"])
	_b(root, Vector3(0.16, 0.16, 0.9), Vector3(AX0 - 0.10, 3.5, (AZ0 + AZ1) * 0.5), _M["green"])
	_b(root, Vector3(AX1 - AX0, 0.05, AZ1 - AZ0), Vector3((AX0 + AX1) * 0.5, 0.025, (AZ0 + AZ1) * 0.5), _M["deck"])
	_b(root, Vector3(AX1 - AX0 - 0.8, 0.10, 0.5), Vector3((AX0 + AX1) * 0.5, AH - 0.25, (AZ0 + AZ1) * 0.5), _M["lamp"])
	# 气闸标牌
	_label(root, "AIRLOCK", Vector3(AX0 + 0.05, 3.4, (AZ0 + AZ1) * 0.5), 0.55, Color(0.35, 0.85, 0.55), 0.0, Vector3(0.0, -90.0, 0.0))


# ================================================================== 控制台
static func _booth(root: Node3D, platforms: Array) -> void:
	var qy := QY0
	# 楼板 + 悬挑桁架
	_b(root, Vector3(QBX1 - QBX0, 0.20, QBZ1 - QBZ0), Vector3((QBX0 + QBX1) * 0.5, qy - 0.10, (QBZ0 + QBZ1) * 0.5), _M["hull"])
	for k in 4:
		var px := QBX0 + 1.4 + float(k) * 4.0
		_tube(root, Vector3(px, qy - 0.3, QBZ0 + 0.2), Vector3(px, 1.5, QBZ1 - 0.3), 0.10, _M["steel"])
		_tube(root, Vector3(px, qy - 0.3, QBZ0 + 0.2), Vector3(px, qy - 0.3, QBZ1 - 0.2), 0.08, _M["steel"])
	# 玻璃盒
	var gy := QY1 - QY0
	_b(root, Vector3(QBX1 - QBX0, gy, 0.14), Vector3((QBX0 + QBX1) * 0.5, qy + gy * 0.5, QBZ0 + 0.07), _M["glass"])
	_b(root, Vector3(0.14, gy, QBZ1 - QBZ0), Vector3(QBX0 + 0.07, qy + gy * 0.5, (QBZ0 + QBZ1) * 0.5), _M["glass"])
	# 东侧玻璃留出上人的门洞（z 30.0…33.4）
	_b(root, Vector3(0.14, gy, 4.0), Vector3(QBX1 - 0.07, qy + gy * 0.5, QBZ0 + 2.0), _M["glass"])
	_b(root, Vector3(0.14, gy, 0.6), Vector3(QBX1 - 0.07, qy + gy * 0.5, QBZ1 - 0.3), _M["glass"])
	_b(root, Vector3(0.18, 0.22, 3.4), Vector3(QBX1 - 0.07, qy + 3.5, 31.7), _M["steel"])
	_b(root, Vector3(0.18, 0.10, 0.7), Vector3(QBX1 - 0.07, qy + 0.05, 30.2), _M["green"])
	_b(root, Vector3(QBX1 - QBX0, 0.18, QBZ1 - QBZ0), Vector3((QBX0 + QBX1) * 0.5, QY1, (QBZ0 + QBZ1) * 0.5), _M["hull"])
	# 竖框
	for k in 5:
		var px2 := QBX0 + float(k) * (QBX1 - QBX0) / 4.0
		_b(root, Vector3(0.12, gy, 0.12), Vector3(px2, qy + gy * 0.5, QBZ0 + 0.08), _M["steel"])
	# 室内：控制台 + 座椅 + 暖光
	for k in 3:
		var cx := QBX0 + 3.0 + float(k) * 5.0
		_b(root, Vector3(2.4, 0.85, 1.2), Vector3(cx, qy + 0.42, QBZ0 + 2.2), _M["wall_dark"])
		platforms.append({"c": Vector3(cx, 0.0, QBZ0 + 2.2) * U,
			"hx": 1.2 * U, "hz": 0.6 * U, "h": (qy + 0.85) * U, "strict": true})
		_b(root, Vector3(2.2, 0.06, 0.9), Vector3(cx, qy + 0.90, QBZ0 + 2.2), _M["cyan"])
		_b(root, Vector3(0.7, 0.9, 0.7), Vector3(cx, qy + 0.45, QBZ0 + 3.6), _M["rubber"])
		platforms.append({"c": Vector3(cx, 0.0, QBZ0 + 3.6) * U,
			"hx": 0.35 * U, "hz": 0.35 * U, "h": (qy + 0.90) * U, "strict": true})
	_b(root, Vector3(QBX1 - QBX0 - 1.0, 0.10, 0.4), Vector3((QBX0 + QBX1) * 0.5, QY1 - 0.35, (QBZ0 + QBZ1) * 0.5), _M["warm"])
	# 铭牌
	_label(root, "DOCK CONTROL", Vector3((QBX0 + QBX1) * 0.5, qy + 0.30, QBZ0 - 0.02), 0.5, Color(0.55, 0.78, 0.90), 0.0, Vector3(0.0, 0.0, 0.0))


# ================================================================== 控制台升降台
## 轿厢内净高 2.5 m：站进去自动升到控制台（8.5 m），离开后回落。
## 顶棚有垂直夹紧（hangar_lift.gd），不会从顶上钻出去。
static func _lift(root: Node3D, cover: Array, platforms: Array) -> void:
	var x0 := 19.0
	var x1 := 22.0
	var z0 := 29.5
	var z1 := 33.0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var shaft_top := QY0 + 3.7

	# ---------------- 井道（静态）
	# 东墙 / 北墙
	_b(root, Vector3(0.20, shaft_top, z1 - z0), Vector3(x1 - 0.10, shaft_top * 0.5, cz), _M["hull"])
	_b(root, Vector3(x1 - x0, shaft_top, 0.20), Vector3(cx, shaft_top * 0.5, z1 - 0.10), _M["hull"])
	# 墙面板缝与警示条
	for gz in [z0 + 0.8, z0 + 1.8, z0 + 2.8]:
		_b(root, Vector3(0.06, shaft_top - 0.4, 0.16), Vector3(x1 - 0.22, shaft_top * 0.5, gz), _M["steel"])
	_b(root, Vector3(0.06, 0.18, z1 - z0 - 0.4), Vector3(x1 - 0.23, 1.15, cz), _M["paint"])
	# 四角立柱
	for px in [x0 + 0.10, x1 - 0.10]:
		for pz in [z0 + 0.10, z1 - 0.10]:
			_b(root, Vector3(0.16, shaft_top, 0.16), Vector3(px, shaft_top * 0.5, pz), _M["steel"])
	# 顶梁 + 曳引机座
	_b(root, Vector3(x1 - x0 + 0.24, 0.20, z1 - z0 + 0.24), Vector3(cx, shaft_top + 0.10, cz), _M["steel"])
	_b(root, Vector3(1.2, 0.45, 0.9), Vector3(cx, shaft_top + 0.42, cz - 0.4), _M["wall_dark"])
	_b(root, Vector3(0.30, 0.30, 0.30), Vector3(cx, shaft_top + 0.28, cz + 0.6), _M["paint"])
	# 导轨（东墙两根 + 北墙一根）
	for pz in [cz - 1.05, cz + 1.05]:
		_b(root, Vector3(0.08, shaft_top - 0.2, 0.16), Vector3(x1 - 0.16, (shaft_top - 0.2) * 0.5, pz), _M["steel_hot"])
	_b(root, Vector3(0.16, shaft_top - 0.2, 0.08), Vector3(cx + 0.9, (shaft_top - 0.2) * 0.5, z1 - 0.16), _M["steel_hot"])
	# 底层门槛 + 层号
	_b(root, Vector3(x1 - x0, 0.05, 0.30), Vector3(cx, 0.025, z0 - 0.05), _M["steel"])
	_label(root, "0 m", Vector3(x0 + 0.35, 0.12, z0 - 0.16), 0.5, Color(0.62, 0.66, 0.70), -90.0)
	_label(root, "8.5 m", Vector3(x0 + 0.35, QY0 + 0.12, z0 - 0.16), 0.5, Color(0.62, 0.66, 0.70), -90.0)
	# 呼叫面板
	_b(root, Vector3(0.34, 0.62, 0.10), Vector3(x0 + 0.55, 1.25, z0 - 0.05), _M["steel_hot"])
	_b(root, Vector3(0.16, 0.16, 0.05), Vector3(x0 + 0.55, 1.38, z0 - 0.11), _M["amber"])
	_b(root, Vector3(0.16, 0.16, 0.05), Vector3(x0 + 0.55, 1.14, z0 - 0.11), _M["green"])
	_label(root, "LIFT", Vector3(cx, 2.15, z0 - 0.06), 0.5, Color(0.85, 0.72, 0.34), 0.0,
		Vector3(0.0, 180.0, 0.0))
	# 顶部门槛板：只铺在玻璃门与井道之间（x 18.0…19.25），不进轿厢行程
	_b(root, Vector3(1.25, 0.10, 3.3), Vector3(18.62, QY0 - 0.05, cz), _M["steel"])
	_b(root, Vector3(0.09, 0.09, 3.3), Vector3(19.25, QY0 + 0.02, cz), _M["paint"])

	# ---------------- 轿厢（可动）
	var car := Node3D.new()
	car.name = "LiftRig"
	root.add_child(car)
	var iw := x1 - x0 - 0.62
	var id := z1 - z0 - 0.62
	var h := 3.40
	# 底板 + 踢脚
	_b(car, Vector3(iw, 0.10, id), Vector3(cx, 0.05, cz), _M["deck"])
	_b(car, Vector3(iw, 0.14, 0.08), Vector3(cx, 0.17, z0 + 0.31), _M["paint"])
	_b(car, Vector3(iw, 0.14, 0.08), Vector3(cx, 0.17, z1 - 0.31), _M["paint"])
	_b(car, Vector3(0.08, 0.14, id), Vector3(x0 + 0.31, 0.17, cz), _M["paint"])
	_b(car, Vector3(0.08, 0.14, id), Vector3(x1 - 0.31, 0.17, cz), _M["paint"])
	# 四角立柱 + 顶框
	for px in [x0 + 0.31, x1 - 0.31]:
		for pz in [z0 + 0.31, z1 - 0.31]:
			_b(car, Vector3(0.09, h, 0.09), Vector3(px, h * 0.5, pz), _M["steel"])
	_b(car, Vector3(iw, 0.10, 0.09), Vector3(cx, h - 0.05, z0 + 0.31), _M["steel"])
	_b(car, Vector3(iw, 0.10, 0.09), Vector3(cx, h - 0.05, z1 - 0.31), _M["steel"])
	_b(car, Vector3(0.09, 0.10, id), Vector3(x0 + 0.31, h - 0.05, cz), _M["steel"])
	_b(car, Vector3(0.09, 0.10, id), Vector3(x1 - 0.31, h - 0.05, cz), _M["steel"])
	# 顶棚 + 顶灯
	_b(car, Vector3(iw, 0.07, id), Vector3(cx, h + 0.04, cz), _M["wall_dark"])
	_b(car, Vector3(0.9, 0.04, 1.5), Vector3(cx, h - 0.02, cz), _M["lamp"])
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(cx, h - 0.25, cz) * U
	lamp.light_color = Color(0.86, 0.92, 1.0)
	lamp.light_energy = 2.6
	lamp.omni_range = 5.5 * U
	lamp.shadow_enabled = false
	car.add_child(lamp)
	# 北 / 东侧护笼（竖向栏杆 + 中横杆）
	for gz in [z0 + 0.42, z0 + 0.74, z1 - 0.74, z1 - 0.42]:
		pass
	var bx0 := x0 + 0.37
	while bx0 <= x1 - 0.37:
		_b(car, Vector3(0.045, h - 0.20, 0.045), Vector3(bx0, h * 0.5 - 0.05, z1 - 0.31), _M["steel_hot"])
		bx0 += 0.30
	var bz0 := z0 + 0.37
	while bz0 <= z1 - 0.37:
		_b(car, Vector3(0.045, h - 0.20, 0.045), Vector3(x1 - 0.31, h * 0.5 - 0.05, bz0), _M["steel_hot"])
		bz0 += 0.30
	_b(car, Vector3(iw, 0.05, 0.06), Vector3(cx, 1.05, z1 - 0.31), _M["steel_hot"])
	_b(car, Vector3(0.06, 0.05, id), Vector3(x1 - 0.31, 1.05, cz), _M["steel_hot"])
	# 南侧（进车口）细护栏：只在 0.55 m 以下，抬腿能进
	_b(car, Vector3(iw, 0.06, 0.05), Vector3(cx, 0.55, z0 + 0.31), _M["paint"])
	# 西侧（出车口）两侧黄链柱
	_b(car, Vector3(0.05, 0.30, 0.05), Vector3(x0 + 0.31, 0.95, z0 + 0.38), _M["amber"])
	_b(car, Vector3(0.05, 0.30, 0.05), Vector3(x0 + 0.31, 0.95, z1 - 0.38), _M["amber"])
	# 轿厢操作面板
	_b(car, Vector3(0.26, 0.44, 0.08), Vector3(x1 - 0.40, 1.35, z0 + 0.45), _M["steel_hot"])
	_b(car, Vector3(0.12, 0.12, 0.04), Vector3(x1 - 0.40, 1.48, z0 + 0.50), _M["green"])

	var car_idx := platforms.size()
	platforms.append({"c": Vector3(cx, 0.0, cz) * U,
		"hx": iw * 0.5 * U, "hz": id * 0.5 * U, "h": 0.10 * U})
	# 井道西沿到玻璃门之间的出梯平台（与轿厢地板、控制台地面同高）
	platforms.append({"c": Vector3(18.7, 0.0, cz) * U,
		"hx": 0.75 * U, "hz": 1.7 * U, "h": QY0 * U})

	var lift = preload("res://hangar/src/arena/hangar_lift.gd").new()
	lift.name = "Lift"
	lift.setup(car, platforms, car_idx, Vector3(cx, 0.0, cz), QY0 - 0.10, 0.95)
	root.add_child(lift)

	# 井道北墙 / 东墙挡人（南、西留空进出）
	for gx in [x0 + 0.5, cx, x1 - 0.5]:
		_cov(cover, Vector3(gx, 0.0, z1 - 0.10), 0.45, shaft_top)
	for gz in [z0 + 0.6, cz, z1 - 0.6]:
		_cov(cover, Vector3(x1 - 0.10, 0.0, gz), 0.45, shaft_top)


# ================================================================== 吊车# ================================================================== 吊车# ================================================================== 吊车
static func _crane(root: Node3D) -> void:
	var ry := 24.0
	for z in [-22.0, 22.0]:
		_b(root, Vector3(2 * HX - 1.0, 0.7, 0.8), Vector3(0.0, ry, z), _M["hull"])
		_b(root, Vector3(2 * HX - 1.0, 0.14, 0.30), Vector3(0.0, ry + 0.42, z), _M["steel"])
	# 桥架（沿 z 跨过主厅）+ 小车 + 吊钩
	_b(root, Vector3(2.4, 0.9, 44.0), Vector3(6.0, ry - 0.55, 0.0), _M["steel_hot"])
	_b(root, Vector3(2.6, 0.28, 44.4), Vector3(6.0, ry - 0.05, 0.0), _M["steel"])
	_b(root, Vector3(3.0, 1.5, 3.2), Vector3(6.0, ry - 1.75, 0.0), _M["steel"])
	for dz in [-1.2, 1.2]:
		_b(root, Vector3(0.10, 1.0, 0.10), Vector3(6.0, ry - 3.0, dz), _M["wall_dark"])
	_b(root, Vector3(1.0, 0.9, 1.0), Vector3(6.0, 22.7, 0.0), _M["steel"])
	_b(root, Vector3(0.18, 0.5, 0.18), Vector3(6.0, 22.2, 0.0), _M["amber"])
	# 司机室
	_b(root, Vector3(2.4, 2.0, 2.2), Vector3(6.0, ry - 1.0, 10.0), _M["hull"])
	_b(root, Vector3(2.2, 1.0, 0.14), Vector3(6.0, ry - 0.7, 8.85), _M["glass"])
	_b(root, Vector3(0.5, 0.4, 0.5), Vector3(6.0, ry + 0.6, 10.0), _M["red"])


# ================================================================== 灯光
static func _lights(root: Node3D) -> void:
	# 高棚灯：7 × 2 排，每盏都有实体灯具 + 光源
	for x in [-36.0, -24.0, -12.0, 0.0, 12.0, 24.0, 36.0]:
		for z in [-16.0, 16.0]:
			_b(root, Vector3(2.8, 0.26, 0.8), Vector3(x, H - 1.05, z), _M["wall_dark"])
			var lamp := _b(root, Vector3(2.5, 0.07, 0.46), Vector3(x, H - 1.20, z), _M["lamp"])
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_b(root, Vector3(0.06, 1.0, 0.06), Vector3(x - 1.1, H - 0.55, z), _M["steel"])
			_b(root, Vector3(0.06, 1.0, 0.06), Vector3(x + 1.1, H - 0.55, z), _M["steel"])
			_omni(root, Vector3(x, H - 1.9, z), Color(0.80, 0.90, 1.0), 11.0, 58.0, 0.55)

	# 墙面发光带在墙脚打亮地面（不再额外放灯，靠材质自发光 + 一盏低位补光）
	for p in [Vector3(-30.0, 1.6, -30.0), Vector3(30.0, 1.6, -30.0),
			Vector3(-30.0, 1.6, 30.0), Vector3(30.0, 1.6, 30.0)]:
		_omni(root, p, Color(0.60, 0.78, 0.96), 3.0, 24.0, 0.8)

	# 维修舱工作灯（暖）
	for p in [Vector3(-20.0, 7.4, 37.0), Vector3(-10.0, 7.4, 37.0), Vector3(0.0, 7.4, 37.0)]:
		_omni(root, p, Color(1.0, 0.80, 0.52), 7.0, 24.0, 0.7)
	_omni(root, Vector3(-12.0, 8.6, 39.0), Color(0.92, 0.90, 0.84), 3.0, 16.0, 0.4)
	# 勤务舱（冷绿）
	_omni(root, Vector3(6.0, 5.2, -39.0), Color(0.58, 0.94, 0.84), 5.5, 22.0, 0.7)
	_omni(root, Vector3(6.0, 5.2, -34.6), Color(0.70, 0.88, 1.0), 4.0, 14.0, 0.8)
	# 入口走廊
	_omni(root, Vector3(-44.0, 4.2, 28.5), Color(0.84, 0.90, 1.0), 1.5, 7.0, 0.35)
		# 东南气闸：绿光 + 白光，保证出口一眼能看到
	_omni(root, Vector3(AX0 - 1.0, 2.4, (AZ0 + AZ1) * 0.5), Color(0.42, 1.0, 0.64), 3.0, 9.0, 0.45)
	_omni(root, Vector3((AX0 + AX1) * 0.5, 3.4, (AZ0 + AZ1) * 0.5), Color(0.86, 0.96, 1.0), 6.5, 12.0, 0.5)
	# 东侧大门前的门槛光
	_omni(root, Vector3(HX - 3.0, 4.0, 0.0), Color(0.55, 0.72, 1.0), 5.0, 20.0, 0.7)
	# 控制台暖光
	_omni(root, Vector3((QBX0 + QBX1) * 0.5, QY0 + 1.7, (QBZ0 + QBZ1) * 0.5),
		Color(1.0, 0.82, 0.58), 5.0, 16.0, 0.7)

	# 两盏带阴影的顶灯：给 Boss 和地面长影子
	var s1 := SpotLight3D.new()
	s1.position = Vector3(-8.0, 25.0, 8.0) * U
	s1.light_color = Color(0.86, 0.92, 1.0)
	s1.light_energy = 6.0
	s1.spot_range = 42.0 * U
	s1.spot_angle = 46.0
	s1.rotation_degrees = Vector3(-90.0, 18.0, 0.0)
	s1.shadow_enabled = false   # 顶灯只做照明；阴影由主光提供（省 GPU）
	root.add_child(s1)


static func _omni(root: Node3D, p: Vector3, col: Color, energy: float, rng: float,
		fog := 0.5) -> void:
	var l := OmniLight3D.new()
	l.position = p * U
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng * U
	l.omni_attenuation = 0.7
	l.light_volumetric_fog_energy = fog
	l.shadow_enabled = false
	root.add_child(l)


# ================================================================== 地面设备
static func _props(root: Node3D) -> void:
	# 地面电源车：滑撬底座 + 机组箱 + 控制面板 + 散热格栅 + 电缆卷盘 + 吊耳
	_b(root, Vector3(2.30, 0.14, 1.60), Vector3(31.0, 0.07, 7.0), _M["wall_dark"])
	for sx in [29.95, 32.05]:
		for sz in [6.30, 7.70]:
			_b(root, Vector3(0.16, 0.16, 0.16), Vector3(sx, 0.20, sz), _M["steel"])
	# 机组箱体（上小下大，形成台阶感）
	_b(root, Vector3(1.90, 1.10, 1.30), Vector3(31.0, 0.69, 7.0), _M["shuttle"])
	_b(root, Vector3(1.55, 0.16, 1.10), Vector3(31.0, 1.30, 7.0), _M["steel_hot"])
	# 散热格栅（西侧面）
	for k in 7:
		_b(root, Vector3(0.05, 0.07, 1.05), Vector3(30.03, 0.35 + float(k) * 0.12, 7.0), _M["wall_dark"])
	# 控制面板（东侧，朝甲板）
	_b(root, Vector3(0.06, 0.55, 0.75), Vector3(31.97, 1.00, 7.0), _M["wall_dark"])
	for gz2 in [6.80, 7.20]:
		Kit.cylinder(root, 0.11 * U, 0.05 * U, Vector3(32.02, 1.12, gz2) * U, _M["tank_band"],
			Vector3(0.0, 0.0, PI * 0.5))
	_b(root, Vector3(0.05, 0.16, 0.16), Vector3(32.02, 0.88, 7.0), _M["paint"])
	_b(root, Vector3(0.05, 0.10, 0.10), Vector3(32.02, 0.88, 6.72), _M["green"])
	_b(root, Vector3(0.05, 0.10, 0.10), Vector3(32.02, 0.88, 7.28), _M["red"])
	# 顶部警示灯 + 吊耳 + 铭牌
	_b(root, Vector3(0.16, 0.12, 0.16), Vector3(30.6, 1.44, 7.0), _M["amber"])
	for sx2 in [30.2, 31.8]:
		for sz2 in [6.45, 7.55]:
			Kit.torus(root, 0.10 * U, 0.025 * U, Vector3(sx2, 1.42, sz2) * U, _M["steel"], 12)
	_b(root, Vector3(0.55, 0.20, 0.03), Vector3(31.0, 0.95, 7.66), _M["tank_band"])
	# 电缆卷盘（南侧）+ 拖出的电缆
	Kit.cylinder(root, 0.40 * U, 0.26 * U, Vector3(32.45, 0.70, 7.55) * U, _M["cabinet_red"],
		Vector3(0.0, 0.0, PI * 0.5))
	Kit.cylinder(root, 0.30 * U, 0.30 * U, Vector3(32.45, 0.70, 7.55) * U, _M["steel_hot"],
		Vector3(0.0, 0.0, PI * 0.5))
	Kit.cable(root, Vector3(32.55, 0.55, 7.30) * U, Vector3(29.2, 0.28, 4.6) * U,
		0.55 * U, 0.05 * U, _M["hose"])

	# 拖杆 + 壁挂支架（靠东墙）
	_b(root, Vector3(0.16, 0.16, 3.2), Vector3(33.2, 0.55, 3.6), _M["steel_hot"])
	_b(root, Vector3(0.7, 0.18, 0.24), Vector3(33.2, 0.55, 2.1), _M["steel"])
	for bz in [2.6, 4.6]:
		_b(root, Vector3(0.5, 0.10, 0.10), Vector3(33.4, 0.35, bz), _M["steel"])

	# 轮挡（大门内侧地面）
	for cz in [2.2, -2.2]:
		for cx in [34.6, 35.6]:
			_b(root, Vector3(0.55, 0.22, 0.30), Vector3(cx, 0.11, cz), _M["paint"])

	# 工具车（西侧墙）
	for dz in [5.0, -7.0]:
		_b(root, Vector3(1.0, 1.32, 1.5), Vector3(-34.2, 0.66, dz), _M["steel_hot"])
		for k in 3:
			_b(root, Vector3(0.06, 0.4, 1.3), Vector3(-33.66, 0.35 + float(k) * 0.42, dz), _M["wall_dark"])
		_b(root, Vector3(0.10, 0.10, 1.4), Vector3(-33.6, 1.62, dz), _M["steel"])

	# 气瓶架（西墙北段）
	for k in 3:
		for j in 2:
			Kit.cylinder(root, 0.22 * U, 1.45 * U,
				Vector3(-34.5 + float(j) * 0.55, 0.72, 19.0 + float(k) * 0.55) * U,
				_M["red"] if (k + j) % 2 == 0 else _M["steel"])
	_b(root, Vector3(1.4, 0.12, 2.0), Vector3(-34.2, 1.5, 19.55), _M["steel"])

	# 电缆盘
	Kit.cylinder(root, 0.95 * U, 0.85 * U, Vector3(26.0, 1.0, -30.0) * U, _M["rust"],
		Vector3(0.0, 0.0, PI * 0.5))
	_b(root, Vector3(0.2, 1.0, 1.0), Vector3(26.0, 0.5, -30.0), _M["steel"])

	# 防撞护栏（舰载机门前两翼）
	for dz in [12.5, -12.5]:
		for k in 4:
			_b(root, Vector3(0.16, 1.0, 0.16), Vector3(33.5 + float(k) * 1.2, 0.5, dz), _M["paint"])
		_b(root, Vector3(3.8, 0.12, 0.12), Vector3(35.3, 0.9, dz), _M["paint"])

	# 壁挂梯（贴北墙，带护笼）
	for k in 16:
		_b(root, Vector3(0.86, 0.05, 0.05), Vector3(28.0, 0.35 + float(k) * 0.42, 33.35), _M["steel"])
	for dx in [-0.43, 0.43]:
		_b(root, Vector3(0.07, 7.2, 0.07), Vector3(28.0 + dx, 3.6, 33.35), _M["steel"])
	for k in 6:
		var hy := 2.6 + float(k) * 0.85
		_b(root, Vector3(0.07, 0.07, 0.7), Vector3(27.57, hy, 33.0), _M["steel"])
		_b(root, Vector3(0.07, 0.07, 0.7), Vector3(28.43, hy, 33.0), _M["steel"])
	for k in 3:
		_b(root, Vector3(0.86, 0.05, 0.05), Vector3(28.0, 2.9 + float(k) * 1.7, 32.7), _M["steel"])

	# 托盘与货箱（南墙东段）
	_b(root, Vector3(2.4, 0.16, 2.0), Vector3(26.0, 0.08, -30.5), _M["rust"])
	_b(root, Vector3(1.9, 1.1, 1.5), Vector3(25.8, 0.7, -30.4), _M["wall_dark"])
	_b(root, Vector3(1.2, 0.8, 1.1), Vector3(26.6, 0.5, -30.9), _M["rust"])

	# 消防软管盘：贴墙安装，带支臂和挂板
	_hose_reel(root, 21.0, 1.62, -33.45)


# ================================================================== Boss 占位
static func _boss_placeholder(root: Node3D) -> void:
	var g := Node3D.new()
	g.name = "BossPlaceholder"
	root.add_child(g)
	# 球体：r=2，体心 y=6
	var sph := SphereMesh.new()
	sph.radius = 2.0 * U
	sph.height = 4.0 * U
	sph.radial_segments = 32
	sph.rings = 16
	var body := MeshInstance3D.new()
	body.mesh = sph
	body.material_override = _M["hull"]
	body.position = Vector3(0.0, 6.0, 0.0) * U
	g.add_child(body)
	# 前部红色镜头
	var eye := SphereMesh.new()
	eye.radius = 0.42 * U
	eye.height = 0.84 * U
	var eye_mi := MeshInstance3D.new()
	eye_mi.mesh = eye
	eye_mi.material_override = _M["red"]
	eye_mi.position = Vector3(0.0, 5.8, -2.0) * U
	g.add_child(eye_mi)
	# 8 条支撑腿：体 → 膝 → 落地
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.15
		var d := Vector3(cos(a), 0.0, sin(a))
		var hip := d * 1.7 + Vector3(0.0, 5.3, 0.0)
		var knee := d * 6.4 + Vector3(0.0, 4.3, 0.0)
		var foot := d * 9.6 + Vector3(0.0, 0.25, 0.0)
		_tube(g, hip, knee, 0.20, _M["steel_hot"])
		_tube(g, knee, foot, 0.16, _M["steel_hot"])
		for jp in [hip, knee]:
			var jm := SphereMesh.new()
			jm.radius = 0.30 * U
			jm.height = 0.60 * U
			var jmi := MeshInstance3D.new()
			jmi.mesh = jm
			jmi.material_override = _M["steel"]
			jmi.position = jp * U
			g.add_child(jmi)
		Kit.cylinder(g, 0.55 * U, 0.12 * U, foot * U, _M["steel"])
	# 包络参考：待机 15 m 与扫掠 21.4 m
	_dash_ring(g, 15.0, 0.12, 1.8, 1.5, 0.04, _M["amber"])
	_dash_ring(g, 21.4, 0.12, 1.8, 1.5, 0.04, _M["red"])
	_label(g, "BOSS 占位 · 体心 y=6 · 腿 9.6 m", Vector3(0.0, 0.06, 11.0), 1.0,
		Color(0.72, 0.46, 0.42), -90.0)


static func _debug_rings(root: Node3D) -> void:
	for r in [15.0, 21.4, 25.0]:
		Kit.annulus(root, (r - 0.08) * U, (r + 0.08) * U, 160, 0.06 * U,
			Kit.emissive(Color(0.2, 1.0, 1.0), 3.0))


# ================================================================== 实体碰撞
## 场景里每一件“看起来是实体”的东西都在这里登记，尺寸与建模型处一致。
static func _solids(cover: Array, platforms: Array) -> void:
	# 穿梭机（机身 + 起落架），沿 x 停放
	for x in [-18.0, -14.0, -10.0, -6.0, -2.6]:
		_cov(cover, Vector3(x, 0.0, 39.0), 2.0, 4.4)
	for dz in [-1.55, 1.55]:
		_cov(cover, Vector3(-16.0, 0.0, 39.0 + dz), 0.7, 2.8)
		_cov(cover, Vector3(-8.0, 0.0, 39.0 + dz), 0.7, 2.8)
	# 机翼：整片可站（顶面 3.04 m）
	platforms.append({"c": Vector3(-12.0, 0.0, 39.0) * U,
		"hx": 2.5 * U, "hz": 3.8 * U, "h": 3.04 * U})

	# 检修台架：可跳上去（平台）+ 侧面碰撞
	for dz in [-4.45, 4.45]:
		platforms.append({"c": Vector3(-15.0, 0.0, 39.0 + dz) * U,
			"hx": 4.0 * U, "hz": 0.4 * U, "h": 1.42 * U, "strict": true})
		for sx in [-18.0, -16.0, -14.0, -12.0]:
			_cov(cover, Vector3(sx, 0.0, 39.0 + dz), 0.45, 1.12)
	# 维修舱门架立柱
	for gx in [-22.0, -10.0, 2.0]:
		for gz in [BZ0 + 0.6, BZ1 - 0.6]:
			_cov(cover, Vector3(gx, 0.0, gz), 0.35, 8.2)
	# 工具柜 / 工作台 / 零件架
	for gz in [35.4, 41.6]:
		_cov(cover, Vector3(BX0 + 1.0, 0.0, gz), 0.9, 1.86)
		platforms.append({"c": Vector3(BX0 + 1.0, 0.0, gz) * U, "hx": 0.40 * U, "hz": 3.50 * U, "h": 2.20 * U})
	_block(cover, platforms, BX0 + 2.6, 42.0, 1.6, 0.7, 1.06)
	_block(cover, platforms, -4.0, BZ1 - 0.75, 1.5, 0.25, 2.4)

	# 储罐 + 围堰
	for tx in [-3.6, 0.8, 11.0, 15.6]:
		_cov(cover, Vector3(tx, 0.0, -39.5), 2.1, 7.0)
	_chain_h(cover, Vector2(-6.0, -37.0), Vector2(18.0, -37.0), 0.18, 0.78)
	_chain_h(cover, Vector2(-5.825, -36.9), Vector2(-5.825, -44.0), 0.18, 0.78)
	_chain_h(cover, Vector2(17.825, -36.9), Vector2(17.825, -44.0), 0.18, 0.78)
	platforms.append({"c": Vector3(6.0, 0.0, -37.0) * U, "hx": 12.0 * U, "hz": 0.18 * U, "h": 1.1 * U, "strict": true})
	platforms.append({"c": Vector3(-5.825, 0.0, -40.4) * U, "hx": 0.18 * U, "hz": 3.6 * U, "h": 1.1 * U})
	platforms.append({"c": Vector3(17.825, 0.0, -40.4) * U, "hx": 0.18 * U, "hz": 3.6 * U, "h": 1.1 * U})

	# 消防柜 / 软管盘
	_cov(cover, Vector3(13.3, 0.0, -33.78), 0.50, 1.48)
	_cov(cover, Vector3(13.9, 0.0, -33.78), 0.50, 1.48)
	platforms.append({"c": Vector3(13.6, 0.0, -33.78) * U, "hx": 0.55 * U, "hz": 0.21 * U, "h": 1.82 * U, "strict": true})



	# 地面电源车（可站）+ 拖杆
	_block(cover, platforms, 31.0, 7.0, 1.05, 0.70, 1.38)
	_cov(cover, Vector3(33.2, 0.0, 3.6), 0.35, 0.40)
	platforms.append({"c": Vector3(33.2, 0.0, 3.6) * U, "hx": 0.22 * U, "hz": 1.55 * U, "h": 0.70 * U, "strict": true})
	# 防撞护栏
	for dz in [12.5, -12.5]:
		for k in 4:
			_cov(cover, Vector3(33.5 + float(k) * 1.2, 0.0, dz), 0.45, 0.62)
		platforms.append({"c": Vector3(35.3, 0.0, dz) * U, "hx": 1.9 * U, "hz": 0.18 * U, "h": 0.95 * U, "strict": true})
	# 工具车 / 气瓶 / 电缆盘 / 梯子 / 托盘
	for dz in [5.0, -7.0]:
		_block(cover, platforms, -34.2, dz, 0.5, 0.75, 1.32)
	_cov(cover, Vector3(-34.2, 0.0, 19.55), 1.0, 1.26)
	platforms.append({"c": Vector3(-34.2, 0.0, 19.55) * U, "hx": 0.70 * U, "hz": 1.00 * U, "h": 1.60 * U})
	_cov(cover, Vector3(26.0, 0.0, -30.0), 1.1, 1.56)
	platforms.append({"c": Vector3(26.0, 0.0, -30.0) * U, "hx": 0.66 * U, "hz": 0.66 * U, "h": 1.90 * U, "strict": true})
	_cov(cover, Vector3(28.0, 0.0, 33.4), 0.6, 6.0)
	# 托盘 + 两个货箱：都能站
	_block(cover, platforms, 26.0, -30.5, 1.2, 1.0, 0.16)
	_block(cover, platforms, 25.8, -30.4, 0.95, 0.75, 1.25)
	_block(cover, platforms, 26.6, -30.9, 0.6, 0.55, 0.8)

	# 控制台里的操作台与座椅：从台面 8.5 m 起算，不挡下面的走道
	for k in 3:
		var dcx: float = QBX0 + 3.0 + float(k) * 5.0
		_cov_y(cover, Vector3(dcx - 0.6, QY0, QBZ0 + 2.2), 0.75, 0.60)
		_cov_y(cover, Vector3(dcx + 0.6, QY0, QBZ0 + 2.2), 0.75, 0.60)
		_cov_y(cover, Vector3(dcx, QY0, QBZ0 + 3.6), 0.45, 0.56)

	# 控制台地面（可走）+ 玻璃围挡（从 8.5 m 起，不挡下面走道）
	platforms.append({"c": Vector3(10.0, 0.0, 30.0) * U, "hx": 8.0 * U, "hz": 4.0 * U, "h": QY0 * U})
	for gx in [4.0, 7.0, 10.0, 13.0, 16.0]:
		_cov_y(cover, Vector3(gx, QY0, QBZ0 + 0.07), 0.6, 3.8)
	for gz in [27.0, 29.0, 33.7]:
		_cov_y(cover, Vector3(QBX0 + 0.07, QY0, gz), 0.6, 3.8)
	for gz in [27.0, 28.5, 29.5, 33.7]:
		_cov_y(cover, Vector3(QBX1 - 0.07, QY0, gz), 0.6, 3.8)

	# 控制台斜撑落地端（管子本身在头顶以上，只挡柱脚）
	for k in 4:
		_cov(cover, Vector3(QBX0 + 1.4 + float(k) * 4.0, 0.0, QBZ1 - 0.3), 0.3, 8.0)

	# 吊车轨道梁：在 24 m，不挡人

# ================================================================== 碰撞
static func _outline(walls: Array, cover: Array) -> void:
	var segs: Array = [
		# 西
		[-HX, -HZ, -HX, EZ0], [-HX, EZ1, -HX, HZ],
		# 入口走廊
		[EX0, EZ0, -HX, EZ0], [EX0, EZ1, -HX, EZ1], [EX0, EZ0, EX0, EZ1],
		# 北（含维修舱开口）
		[-HX, HZ, BAY_OPEN0, HZ], [BAY_OPEN1, HZ, HX, HZ],
		# 维修舱
		[BX0, HZ, BX0, BZ1], [BX0, BZ1, BX1, BZ1], [BX1, BZ1, BX1, HZ],
		# 东（大门 + 气闸开口）
		[HX, HZ, HX, VD_Z], [HX, -VD_Z, HX, AZ1], [HX, AZ0, HX, -HZ],
		# 气闸
		[HX, AZ1, AX1, AZ1], [AX1, AZ1, AX1, A_DOOR1], [AX1, A_DOOR0, AX1, AZ0],
		[AX1, AZ0, HX, AZ0],
		# 南（勤务舱开口）
		[-HX, -HZ, UX0, -HZ], [UX0, -HZ, U_OPEN0, -HZ],
		[U_OPEN1, -HZ, UX1, -HZ], [UX1, -HZ, HX, -HZ],
		# 勤务舱
		[UX0, -HZ, UX0, UZ0], [UX0, UZ0, UX1, UZ0], [UX1, UZ0, UX1, -HZ],
	]
	for s in segs:
		walls.append({"a": Vector2(s[0], s[1]) * U, "b": Vector2(s[2], s[3]) * U,
			"h": H * U, "n": Vector2.ZERO})
		_chain(cover, Vector2(s[0], s[1]), Vector2(s[2], s[3]))


static func _chain_h(cover: Array, a: Vector2, b: Vector2, phys: float, h: float) -> void:
	var d := b - a
	var total := d.length()
	if total < 0.05:
		return
	d /= total
	var step := 0.40
	var n := int(ceil(total / step))
	for i in range(n + 1):
		var p: Vector2 = a + d * minf(float(i) * step, total)
		cover.append({"c": Vector3(p.x, 0.0, p.y) * U, "r": phys * U + BALL,
			"h": h * U, "cam": false})


static func _chain(cover: Array, a: Vector2, b: Vector2) -> void:
	var d := b - a
	var total := d.length()
	if total < 0.05:
		return
	d /= total
	var step := 0.40
	var n := int(ceil(total / step))
	for i in range(n + 1):
		var p: Vector2 = a + d * minf(float(i) * step, total)
		cover.append({"c": Vector3(p.x, 0.0, p.y) * U, "r": 0.12 * U + BALL,
			"h": H * U, "cam": false})


## 可站的实体：侧面挡人（h 略低于顶面，站上去就不再推），顶面登记为平台。
static func _block(cover: Array, platforms: Array, cx: float, cz: float,
		hx: float, hz: float, top: float) -> void:
	_cov(cover, Vector3(cx, 0.0, cz), maxf(hx, hz) * 0.62, maxf(0.06, top - 0.34))
	platforms.append({"c": Vector3(cx, 0.0, cz) * U, "hx": hx * U, "hz": hz * U, "h": top * U})


static func _cov(cover: Array, c: Vector3, phys_r: float, h: float) -> void:
	cover.append({"c": c * U, "r": phys_r * U + BALL, "h": h * U, "cam": true})


static func _cov_y(cover: Array, c: Vector3, phys_r: float, h: float) -> void:
	cover.append({"c": c * U, "r": phys_r * U + BALL, "h": h * U, "cam": true})


# ================================================================== 小工具
static func _b(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	return Kit.box(parent, size * U, pos * U, mat, rot)


static func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	Kit.tube(parent, a * U, b * U, radius * U, mat)


static func _dash_line(parent: Node3D, a: Vector2, b: Vector2, width: float,
		dash: float, gap: float, y: float, mat: Material) -> void:
	var d := b - a
	var total := d.length()
	if total < 0.05:
		return
	d /= total
	var n := int(total / (dash + gap)) + 1
	for i in n:
		var s := float(i) * (dash + gap) + dash * 0.5
		if s > total:
			break
		var c := a + d * s
		Kit.box(parent, Vector3(dash, 0.02, width) * U, Vector3(c.x, y, c.y) * U, mat,
			Vector3(0.0, atan2(d.y, d.x), 0.0))


static func _dash_ring(parent: Node3D, r: float, width: float, dash: float, gap: float,
		y: float, mat: Material) -> void:
	var circ := TAU * r
	var n := int(circ / (dash + gap))
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var seg := circ / float(n) * 0.62
		var c := Vector3(cos(a0) * r, y, sin(a0) * r)
		Kit.box(parent, Vector3(seg, 0.02, width) * U, c * U, mat,
			Vector3(0.0, -a0 + PI * 0.5, 0.0))


static func _hazard_band(parent: Node3D, center: Vector3, sx: float, sz: float, _pad: float) -> void:
	# 45° 黄黑条：沿 x 或 z 的长边，用短方块拼
	var along_x := sx >= sz
	var length := maxf(sx, sz)
	var n := int(length / 0.9)
	for i in n:
		var t := -length * 0.5 + 0.45 + float(i) * 0.9
		var p := center + (Vector3(t, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, t))
		var size := Vector3(0.62, 0.02, minf(sx, sz)) if along_x else Vector3(minf(sx, sz), 0.02, 0.62)
		_b(parent, size, p, _M["amber"] if i % 2 == 0 else _M["rubber"])


static func _label(parent: Node3D, txt: String, pos: Vector3, size: float, col: Color,
		pitch := -90.0, rot := Vector3.ZERO) -> void:
	var lab := Label3D.new()
	lab.text = txt
	lab.font_size = 64
	lab.pixel_size = 0.0022 * size
	lab.modulate = col
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lab.no_depth_test = false
	lab.position = pos * U
	lab.rotation_degrees = Vector3(pitch, 0.0, 0.0) + rot
	parent.add_child(lab)

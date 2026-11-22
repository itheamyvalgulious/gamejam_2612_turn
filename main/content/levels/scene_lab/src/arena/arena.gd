extends RefCounted
## ArenaKit — procedural cyberpunk arenas (three levels).
##
## FROZEN CONTRACT — the game only ever calls ArenaKit.build(kind, origin).
##
##   kind: "alley" (L1 窄巷) | "plaza" (L2 广场) | "chamber" (L3 灯墙厅)
##
##   -> {
##        node:          Node3D   已建好的场景几何根节点（add_child 即可）
##        kind:          String
##        name_cn:       String   关卡中文名
##        hint:          String   关卡提示（显示在 HUD）
##        floor_y:       float    地面高度（通常 0.0）
##        bounds:        AABB     可玩区域（x/z 有效；y 忽略）
##        walls:         Array[{a: Vector2, b: Vector2, h: float, n: Vector2}]
##                                竖直墙段（俯视 x/z）：a→b，h 高度，n 指向场地内侧的法线
##        cover:         Array[{c: Vector3, r: float, h: float}]   柱/箱等掩体（相机避让用）
##        wall_slots:    Array[{plane: Plane, xform: Transform3D, size: Vector2}]
##                                可投影影子的墙面：xform 把墙面局部 XY（米，中心为原点）
##                                映射到世界，size 是墙面尺寸（宽高），plane 是世界平面
##        lamps:         Array[Transform3D]   灯具（位置；-Z 指向场地内）
##        spawns:        Array[Transform3D]   敌人出生点（-Z 面朝场地中心）
##        player_spawn:  Transform3D          玩家出生点（-Z 面朝战斗方向）
##      }
##
## 本实现（美术版）：几何全部由 MB + gfx/surface.gdshader 程序化生成，
## 大气/灯光/天气在 arena_env.gd，几何词汇表与调色板在 arena_art.gd。
## 所有返回数据都在根节点局部坐标系（root.position = origin），几何同样烘焙在同一空间。
##
## 数据补充说明：
##  * cover.c 是掩体的**底面中心**（y = 地面高度），h 是它的物理高度；
##    r 已经按「玩家/相机 = 半径 1.2 m 的球」做了膨胀（r = 物理半径 + 1.2）。
##  * wall_slots 的 plane 满足 normal·x = d，法线指向场内（场内点有正的距离）。
##  * lamps 与 wall_slots 一一对应：chamber 各 4 个，lamps[i] 就挂在 wall_slots[i] 上。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const Art := preload("res://src/arena/arena_art.gd")
const EnvKit := preload("res://src/arena/arena_env.gd")
const WarehouseArena := preload("res://src/warehouse/warehouse_arena.gd")
const PanopticonArena := preload("res://src/panopticon/panopticon_arena.gd")
const WardArena := preload("res://src/ward/ward_arena.gd")

const ALLEY := "alley"
const PLAZA := "plaza"
const CHAMBER := "chamber"

const BALL := 1.2   # 玩家/相机避让球半径


static func build(kind: String, origin := Vector3.ZERO) -> Dictionary:
	Mats.build()
	# 三关都是湿夜里；湿润度用同一值，避免共享材质在关卡间“串味”
	Mats.sun(1.0, 0.88)
	match kind:
		"warehouse":
			return WarehouseArena.build(origin)
		"panopticon":
			return PanopticonArena.build(origin)
		"ward":
			return WardArena.build(origin)
		PLAZA:
			return _plaza(origin)
		CHAMBER:
			return _chamber(origin)
		_:
			return _alley(origin)


# ------------------------------------------------------------------ 公共工具
static func _root(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Arena_" + kind
	return root


static func _wall(walls: Array, a: Vector2, b: Vector2, h: float, n: Vector2) -> void:
	walls.append({"a": a, "b": b, "h": h, "n": n.normalized()})


static func _cover(cover: Array, c: Vector3, phys_r: float, h: float) -> void:
	cover.append({"c": Vector3(c.x, 0.0, c.z), "r": phys_r + BALL, "h": h})


static func _spawn(pos: Vector3) -> Transform3D:
	return Art.facing(pos, Vector3.ZERO)


## 水洼材质（gfx/arena_puddle.gdshader）：深色水膜 + 雨点涟漪，反射靠 SSR。
static func _puddle_mat(deep: Color, sheen: Color, wet := 0.95) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://gfx/arena_puddle.gdshader")
	m.set_shader_parameter("deep_col", Vector3(deep.r, deep.g, deep.b))
	m.set_shader_parameter("sheen_col", Vector3(sheen.r, sheen.g, sheen.b))
	m.set_shader_parameter("wetness", wet)
	m.set_shader_parameter("ripple", 1.0)
	return m


# ================================================================== L1 窄巷
static func _alley(origin: Vector3) -> Dictionary:
	const HX := 20.0     # 半宽（x）
	const HZ := 34.0     # 半长（z）
	const WH := 26.0     # 墙高
	var pal := Art.PAL_ALLEY
	var rng := H.rng(20261201, 11)
	var root := _root(ALLEY)
	var mb := MB.new()
	var far := MB.new()        # 远景/背景体量（不投影）
	var walls: Array = []
	var cover: Array = []
	var slots: Array = []
	var lamps: Array = []

	# ---------------- 地面：湿沥青车行道 + 两侧人行道
	Art.ground_base(mb, Rect2(-6.6, -HZ, 13.2, HZ * 2.0), pal, M.ASPHALT, "asphalt", 0.12)
	Art.sidewalk(mb, Vector2(-HX, -HZ), Vector2(-HX, HZ), Vector2(1, 0), HX - 6.6, pal, 0.21, 0.15, M.ASPHALT)
	Art.sidewalk(mb, Vector2(HX, HZ), Vector2(HX, -HZ), Vector2(-1, 0), HX - 6.6, pal, 0.44, 0.15, M.ASPHALT)
	# 车道中线（虚线）+ 车辙
	var z := -HZ + 3.0
	while z < HZ - 3.0:
		Art.paint_line(mb, Vector2(0, z), Vector2(0, z + 2.6), 0.16, pal)
		z += 6.4
	Art.paint_line(mb, Vector2(-6.1, -HZ), Vector2(-6.1, HZ), 0.12, pal, 0.018)
	Art.paint_line(mb, Vector2(6.1, -HZ), Vector2(6.1, HZ), 0.12, pal, 0.018)
	# 排水篦子 + 井盖
	for gz in [-24.0, -8.0, 9.0, 25.0]:
		Art.grate(mb, Vector2(5.9, gz), Vector2(0.9, 1.6), pal, 0.014, 0.3)
		Art.grate(mb, Vector2(-5.9, gz + 3.0), Vector2(0.9, 1.6), pal, 0.014, 0.4)
	for mz in [-19.0, 2.0, 21.0]:
		mb.setm(M.METAL, Art.tint(pal, "metal_light") * 0.35, 0.5)
		mb.cyl_y(Vector3(2.4, 0.02, mz), 0.42, 0.045, 14, true)

	# ---------------- 西侧楼体（内立面 x = -20）
	var west := [
		{"z0": -HZ, "z1": -16.0, "h": 26.0, "col": 0, "sty": M.STY_PUNCHED, "d": 14.0},
		{"z0": -16.0, "z1": 2.0, "h": 22.0, "col": 1, "sty": M.STY_PANEL, "d": 12.0},
		{"z0": 2.0, "z1": 18.0, "h": 30.0, "col": 2, "sty": M.STY_CURTAIN, "d": 16.0},
		{"z0": 18.0, "z1": HZ, "h": 24.0, "col": 3, "sty": M.STY_INDUSTRIAL, "d": 13.0},
	]
	for b in west:
		Art.facade_block(mb, Vector2(-HX, b["z0"]), Vector2(-HX, b["z1"]), Vector2(1, 0),
			b["d"], b["h"], pal, H.rng(11, int(b["z0"] * 10.0), 5),
			b["sty"], Art.wall_col(pal, b["col"]), {"bands": 2, "ground": "service"})
	_wall(walls, Vector2(-HX, -HZ), Vector2(-HX, HZ), WH, Vector2(1, 0))
	slots.append(Art.wall_slot(Vector2(-HX, -HZ), Vector2(-HX, HZ), 0.0, WH, Vector2(1, 0)))

	# ---------------- 东侧楼体（内立面 x = +20），中段留 3 m 装卸凹龛
	var bay_z0 := -12.0
	var bay_z1 := 8.0
	var bay_x := 23.2
	var east := [
		{"z0": -HZ, "z1": bay_z0, "h": 28.0, "col": 0, "sty": M.STY_PUNCHED, "d": 15.0, "x": HX},
		{"z0": bay_z0, "z1": bay_z1, "h": 18.0, "col": 1, "sty": M.STY_INDUSTRIAL, "d": 12.0, "x": bay_x},
		{"z0": bay_z1, "z1": 22.0, "h": 24.0, "col": 2, "sty": M.STY_FINS, "d": 13.0, "x": HX},
		{"z0": 22.0, "z1": HZ, "h": 30.0, "col": 3, "sty": M.STY_CURTAIN, "d": 16.0, "x": HX},
	]
	for b in east:
		Art.facade_block(mb, Vector2(b["x"], b["z0"]), Vector2(b["x"], b["z1"]), Vector2(-1, 0),
			b["d"], b["h"], pal, H.rng(23, int(b["z0"] * 10.0), 7),
			b["sty"], Art.wall_col(pal, b["col"]), {"bands": 2, "ground": "service"})
	_wall(walls, Vector2(HX, -HZ), Vector2(HX, bay_z0), WH, Vector2(-1, 0))
	_wall(walls, Vector2(bay_x, bay_z0), Vector2(bay_x, bay_z1), WH, Vector2(-1, 0))
	_wall(walls, Vector2(HX, bay_z1), Vector2(HX, HZ), WH, Vector2(-1, 0))
	slots.append(Art.wall_slot(Vector2(HX, -HZ), Vector2(HX, bay_z0), 0.0, WH, Vector2(-1, 0)))
	slots.append(Art.wall_slot(Vector2(HX, bay_z1), Vector2(HX, HZ), 0.0, WH, Vector2(-1, 0)))

	# 凹龛：地面抬高 + 侧壁 + 装卸平台 + 卷帘 + 门灯
	mb.setm(M.CONCRETE, Art.tint(pal, "concrete") * 0.9, 0.31)
	Art.floor_rect(mb, Rect2(HX, bay_z0, bay_x - HX, bay_z1 - bay_z0), 0.16)
	for e in [[Vector2(HX, bay_z0), Vector2(bay_x, bay_z0), Vector2(0, 1)],
			[Vector2(bay_x, bay_z1), Vector2(HX, bay_z1), Vector2(0, -1)]]:
		mb.setm(M.CONCRETE, Art.tint(pal, "concrete_dark"), 0.33)
		Art.wall_quad(mb, e[0], e[1], 0.0, 18.0, e[2])
		Art.hazard_band(mb, e[0], e[1], e[2], 0.5, 1.0, pal, 0.34)
	_wall(walls, Vector2(HX, bay_z0), Vector2(bay_x, bay_z0), 18.0, Vector2(0, 1))
	_wall(walls, Vector2(bay_x, bay_z1), Vector2(HX, bay_z1), 18.0, Vector2(0, -1))
	# 平台 + 卷帘门 + 卸货灯
	mb.setm(M.CONCRETE, Art.tint(pal, "concrete"), 0.35)
	Art.box_rect(mb, Rect2(bay_x - 1.5, bay_z0 + 1.0, 1.5, bay_z1 - bay_z0 - 2.0), 0.16, 1.25)
	mb.setm(M.METAL, Art.tint(pal, "metal_light") * 0.5, 0.37)
	Art.wall_quad(mb, Vector2(bay_x, bay_z0 + 2.5), Vector2(bay_x, bay_z0 + 8.5), 1.25, 5.6, Vector2(-1, 0))
	mb.setm(M.METAL, Art.tint(pal, "metal"), 0.39)
	var bz := 1.5
	while bz < 5.5:
		Art.wall_quad(mb, Vector2(bay_x, bay_z0 + 2.5), Vector2(bay_x, bay_z0 + 8.5), bz, bz + 0.07, Vector2(-1, 0))
		bz += 0.36
	mb.setm(M.EMIT, Mats.c(pal["warm"]), 0.41, 2.0)
	Art.wall_quad(mb, Vector2(bay_x, bay_z0 + 3.4), Vector2(bay_x, bay_z0 + 7.6), 5.9, 6.35, Vector2(-1, 0))
	mb.setm(M.EMIT, Mats.c(pal["cool"]), 0.43, 2.4)
	Art.wall_quad(mb, Vector2(bay_x, bay_z0 + 0.6), Vector2(bay_x, bay_z0 + 3.0), 6.4, 6.6, Vector2(-1, 0))
	Art.wall_vent(mb, Vector3(bay_x, 2.2, bay_z0 + 3.0), Vector2(-1, 0), pal, 0.45)
	Art.drainpipe(mb, Vector3(bay_x, 0.16, bay_z0 + 9.0), Vector2(-1, 0), 17.0, 0.16,
		Art.tint(pal, "metal"), pal, 0.47)

	# ---------------- 巷子两端
	# 近端（玩家身后 z = +34）
	Art.facade_block(mb, Vector2(-HX, HZ), Vector2(HX, HZ), Vector2(0, -1), 14.0, 24.0, pal,
		H.rng(31, 91, 3), M.STY_PUNCHED, Art.wall_col(pal, 1), {"bands": 2, "ground": "service"})
	_wall(walls, Vector2(-HX, HZ), Vector2(HX, HZ), WH, Vector2(0, -1))
	slots.append(Art.wall_slot(Vector2(-HX, HZ), Vector2(HX, HZ), 0.0, WH, Vector2(0, -1)))
	# 远端（z = -34）：两栋楼夹出一个 8 m 宽的暗口，后墙 6 m 处收头 —— 敌人的背光位
	Art.facade_block(mb, Vector2(HX, -HZ), Vector2(4.0, -HZ), Vector2(0, 1), 16.0, 26.0, pal,
		H.rng(41, 13, 3), M.STY_PUNCHED, Art.wall_col(pal, 0), {"bands": 2, "ground": "service"})
	Art.facade_block(mb, Vector2(-4.0, -HZ), Vector2(-HX, -HZ), Vector2(0, 1), 16.0, 26.0, pal,
		H.rng(43, 17, 3), M.STY_PANEL, Art.wall_col(pal, 2), {"bands": 2, "ground": "service"})
	_wall(walls, Vector2(HX, -HZ), Vector2(4.0, -HZ), WH, Vector2(0, 1))
	_wall(walls, Vector2(-4.0, -HZ), Vector2(-HX, -HZ), WH, Vector2(0, 1))
	_wall(walls, Vector2(4.0, -HZ), Vector2(-4.0, -HZ), 20.0, Vector2(0, 1))
	slots.append(Art.wall_slot(Vector2(HX, -HZ), Vector2(4.0, -HZ), 0.0, WH, Vector2(0, 1)))
	slots.append(Art.wall_slot(Vector2(-4.0, -HZ), Vector2(-HX, -HZ), 0.0, WH, Vector2(0, 1)))
	# 暗口里的后墙 + 地面 + 招牌（远处最后一层）
	Art.ground_base(mb, Rect2(-4.0, -HZ - 6.0, 8.0, 6.0), pal, M.ASPHALT, "asphalt", 0.51)
	Art.facade_block(mb, Vector2(6.0, -HZ - 6.0), Vector2(-6.0, -HZ - 6.0), Vector2(0, 1), 12.0, 20.0, pal,
		H.rng(51, 19, 3), M.STY_INDUSTRIAL, Art.wall_col(pal, 3), {"bands": 1, "ground": "blank"})
	mb.setm(M.EMIT, Art.neon_of(pal, 1), 0.53, 2.6)
	Art.wall_quad(mb, Vector2(-3.6, -HZ - 6.0), Vector2(3.6, -HZ - 6.0), 3.4, 4.4, Vector2(0, 1))
	mb.setm(M.EMIT, Art.neon_of(pal, 2), 0.55, 1.5)
	Art.wall_quad(mb, Vector2(-1.2, -HZ - 6.0), Vector2(1.2, -HZ - 6.0), 0.2, 3.2, Vector2(0, 1))

	# ---------------- 墙面附件：管线、空调、爬梯、消防梯、通风口、招牌
	for i in 5:
		var wz := -HZ + 6.0 + 11.0 * float(i)
		Art.pipe_run(mb, Vector3(-HX + 0.3, 7.2 + 0.4 * float(i % 3), wz),
			Vector3(-HX + 0.3, 7.2 + 0.4 * float(i % 3), wz + 9.0), 0.09,
			Art.tint(pal, "metal_light") * 0.4, pal, 0.6 + 0.03 * float(i))
		Art.ac_unit(mb, Vector3(-HX, 5.6 + 1.9 * float(i % 3), wz + 3.0), Vector2(1, 0),
			pal, H.rng(i, 61, 9), 0.65 + 0.01 * float(i))
		Art.drainpipe(mb, Vector3(-HX, 0.0, wz + 6.5), Vector2(1, 0), 25.0, 0.14,
			Art.tint(pal, "metal"), pal, 0.7 + 0.01 * float(i))
	for i in 4:
		var ez := -HZ + 9.0 + 13.0 * float(i)
		if ez > bay_z0 - 2.0 and ez < bay_z1 + 2.0:
			continue
		Art.ac_unit(mb, Vector3(HX, 6.4 + 2.1 * float(i % 3), ez), Vector2(-1, 0),
			pal, H.rng(i, 71, 9), 0.8 + 0.01 * float(i))
		Art.ladder(mb, Vector3(HX, 2.4, ez + 4.0), Vector2(-1, 0), 16.0, pal, 0.85 + 0.01 * float(i))
	Art.fire_escape(mb, Vector2(-HX, 6.0), Vector2(-HX, 13.0), Vector2(1, 0), 13.4, pal,
		H.rng(81, 3, 1), 0.9)
	Art.fire_escape(mb, Vector2(HX, -26.0), Vector2(HX, -19.0), Vector2(-1, 0), 16.2, pal,
		H.rng(83, 5, 1), 0.92)
	Art.wall_vent(mb, Vector3(-HX, 1.5, -20.0), Vector2(1, 0), pal, 0.94)
	Art.wall_vent(mb, Vector3(HX, 1.2, 15.0), Vector2(-1, 0), pal, 0.96)

	# ---------------- 墙面灯管 + 发光海报（近场细节 / 灯光节奏）
	for i in 9:
		var tz := -HZ + 4.0 + 7.6 * float(i)
		var col := Art.neon_of(pal, i) * 0.9
		var wl := 1.4 + 0.5 * float(i % 3)
		if i % 2 == 0:
			Art.wall_tube(mb, Vector3(-HX, 4.5 + 0.6 * float(i % 3), tz), Vector2(1, 0), wl, pal, col, 0.9 + 0.01 * float(i))
			EnvKit.omni(root, Vector3(-HX + 1.1, 4.5 + 0.6 * float(i % 3), tz), col, 11.0, 1.5, 1.2)
		else:
			Art.wall_tube(mb, Vector3(HX, 5.1 + 0.5 * float(i % 3), tz + 2.0), Vector2(-1, 0), wl, pal, col, 0.92 + 0.01 * float(i))
			EnvKit.omni(root, Vector3(HX - 1.1, 5.1 + 0.5 * float(i % 3), tz + 2.0), col, 11.0, 1.5, 1.2)
	for i in 6:
		var pz2 := -HZ + 9.0 + 11.0 * float(i)
		var side := 1.0 if i % 2 == 0 else -1.0
		var px2 := HX * side
		Art.poster(mb, Vector3(px2 - side * 0.0, 2.5 + 0.35 * float(i % 3), pz2), Vector2(-side, 0),
			1.0, 1.5, Art.neon_of(pal, i + 1) * 0.45, pal, 0.94 + 0.01 * float(i))

	# ---------------- 霓虹：刀牌 / 招牌带 / 灯串
	var sign_spots := [
		{"p": Vector3(-HX, 6.4, -21.0), "n": Vector2(1, 0), "c": 0, "w": 0.9, "h": 3.4},
		{"p": Vector3(-HX, 4.6, 8.0), "n": Vector2(1, 0), "c": 2, "w": 0.7, "h": 2.6},
		{"p": Vector3(HX, 5.2, -16.0), "n": Vector2(-1, 0), "c": 1, "w": 1.0, "h": 3.8},
		{"p": Vector3(HX, 7.0, 13.0), "n": Vector2(-1, 0), "c": 3, "w": 0.75, "h": 3.0},
	]
	for s in sign_spots:
		Art.neon_blade(mb, s["p"], s["n"], s["w"], s["h"], Art.neon_of(pal, s["c"]), pal, rng.randf())
		lamps.append(Art.facing(s["p"] + Vector3(s["n"].x, 0.0, s["n"].y) * 1.4,
			s["p"] + Vector3(s["n"].x, 0.0, s["n"].y) * 8.0))
	# 净高招牌带（横贯立面）
	mb.setm(M.EMIT, Art.neon_of(pal, 0), 0.71, 1.7)
	Art.wall_quad(mb, Vector2(-HX + 0.16, -12.0), Vector2(-HX + 0.16, -4.0), 9.4, 10.3, Vector2(1, 0))
	mb.setm(M.EMIT, Art.neon_of(pal, 2), 0.73, 1.7)
	Art.wall_quad(mb, Vector2(HX - 0.16, 16.0), Vector2(HX - 0.16, 24.0), 11.0, 11.9, Vector2(-1, 0))
	mb.setm(M.SCREEN, Art.neon_of(pal, 4), 0.75, 1.9)
	Art.wall_quad(mb, Vector2(HX - 0.2, -30.0), Vector2(HX - 0.2, -22.0), 6.0, 11.0, Vector2(-1, 0))

	# ---------------- 跨巷钢桁架（打破隧道感 + 提供顶光）
	for g in [{"z": 4.0, "y": 10.6, "c": 2}, {"z": -18.0, "y": 13.2, "c": 0}]:
		_gantry(mb, g["z"], g["y"], pal, rng, Art.neon_of(pal, g["c"]))
		Art.bulb_string(mb, Vector3(-HX, g["y"] - 1.6, g["z"] + 5.0),
			Vector3(HX, g["y"] - 2.4, g["z"] - 5.0), 1.6, pal, 12, 0.8)
	# 空中电缆 + 灯串
	Art.cable(mb, Vector3(-HX, 9.0, -6.0), Vector3(HX, 8.2, -7.5), 1.9, pal)
	Art.cable(mb, Vector3(-HX, 12.0, 20.0), Vector3(HX, 12.6, 18.0), 2.4, pal)
	Art.bulb_string(mb, Vector3(-HX, 8.4, 24.0), Vector3(HX, 8.0, 22.5), 1.7, pal, 14, 1.4)

	# ---------------- 掩体（半径已含 1.2 m 避让球）
	Art.dumpster(mb, Vector3(15.6, 0.15, 3.2), Vector2(-1, 0), pal, rng, 0.22, 0.11)
	_cover(cover, Vector3(15.6, 0, 3.2), 1.35, 1.8)
	Art.crate(mb, Vector3(16.4, 0.15, -6.0), Vector3(1.5, 1.4, 1.4), 0.4, pal, rng, 0.13)
	Art.crate(mb, Vector3(16.4, 1.55, -6.0), Vector3(1.2, 1.1, 1.2), -0.2, pal, rng, 0.15, true)
	_cover(cover, Vector3(16.4, 0, -6.0), 1.05, 2.65)
	Art.transformer_box(mb, Vector3(-16.8, 0.15, 12.0), 0.15, pal, rng, 0.17)
	_cover(cover, Vector3(-16.8, 0, 12.0), 1.0, 1.7)
	Art.crate(mb, Vector3(-15.4, 0.15, 19.6), Vector3(1.7, 1.5, 1.5), -0.5, pal, rng, 0.19)
	_cover(cover, Vector3(-15.4, 0, 19.6), 1.2, 1.5)
	Art.dumpster(mb, Vector3(-17.4, 0.15, -4.0), Vector2(1, 0), pal, rng, -1.4, 0.23)
	_cover(cover, Vector3(-17.4, 0, -4.0), 1.35, 1.8)
	# 街道家具（小掩体）
	Art.bench(mb, Vector3(13.0, 0.15, 14.0), 0.0, pal, 0.25)
	Art.trash_bin(mb, Vector3(-13.2, 0.15, -14.0), pal, 0.27)
	Art.vending(mb, Vector3(-19.4, 0.15, 6.0), Vector2(1, 0), pal, rng, 0.29)
	_cover(cover, Vector3(-19.4, 0, 6.0), 0.7, 1.9)

	# ---------------- 水洼（镜像霓虹）
	var water := _puddle_mat(Color(0.006, 0.008, 0.014), Color(0.05, 0.02, 0.07), 0.95)
	var puddles := [
		Vector3(-3.2, 0, 18.0), Vector3(2.6, 0, 6.0), Vector3(-1.4, 0, -7.0),
		Vector3(4.4, 0, -21.0), Vector3(-4.6, 0, -28.0), Vector3(11.0, 0.15, 8.0),
		Vector3(-11.6, 0.15, -3.0), Vector3(14.2, 0.15, -17.0), Vector3(-9.4, 0.15, 24.0),
	]
	for i in puddles.size():
		Art.puddle(root, puddles[i], 2.2 + 1.1 * float(i % 3), 900 + i, water, 0.025)

	# ---------------- 灯光 & 大气
	EnvKit.lights(root, pal)
	# 路灯（两侧各两盏）
	for l in [{"p": Vector3(-14.6, 0.15, 11.0), "d": Vector2(1, 0)},
			{"p": Vector3(-14.6, 0.15, -19.0), "d": Vector2(1, 0)},
			{"p": Vector3(14.6, 0.15, 3.0), "d": Vector2(-1, 0)},
			{"p": Vector3(14.6, 0.15, -27.0), "d": Vector2(-1, 0)}]:
		var head := Art.street_lamp(mb, l["p"], l["d"], pal, H.rng(int(l["p"].z), 5, 2), 0.4, 8.6)
		var iv: Vector2 = l["d"]
		lamps.append(Art.facing(head, head + Vector3(iv.x, 0.0, iv.y) * 6.0))
		EnvKit.omni(root, head, Mats.c(pal["cool"]) * 0.8, 18.0, 2.6, 1.15)
		EnvKit.halo(root, head + Vector3(0, -0.12, 0), 2.6, Mats.c(pal["cool"]), 1.5, head.z, 0.05)
	# 霓虹补光
	EnvKit.omni(root, Vector3(-18.0, 6.4, -21.0), Art.neon_of(pal, 0), 17.0, 4.2, 1.0)
	EnvKit.omni(root, Vector3(18.0, 5.2, -16.0), Art.neon_of(pal, 1), 17.0, 4.0, 1.0)
	EnvKit.omni(root, Vector3(18.0, 7.0, 13.0), Art.neon_of(pal, 3), 15.0, 3.4, 1.0)
	EnvKit.omni(root, Vector3(-18.0, 4.6, 8.0), Art.neon_of(pal, 2), 13.0, 2.8, 1.0)
	EnvKit.omni(root, Vector3(22.0, 6.4, -2.0), Art.tint(pal, "warm") * 0.9, 15.0, 3.0, 1.1)
	EnvKit.omni(root, Vector3(-8.0, 10.4, 4.0), Art.tint(pal, "cool"), 14.0, 2.4, 1.1)
	EnvKit.omni(root, Vector3(0, 13.0, -18.0), Art.neon_of(pal, 0) * 0.9, 16.0, 2.6, 1.1)
	# 巷尾背光：让敌人在逆光里现身
	EnvKit.omni(root, Vector3(0, 3.0, -37.0), Art.neon_of(pal, 1), 26.0, 6.0, 1.0)
	EnvKit.spot(root, Art.aim(Vector3(0, 4.6, -36.5), Vector3(0, 1.4, -6.0)),
		Art.neon_of(pal, 1), 46.0, 7.0, 44.0)
	EnvKit.halo(root, Vector3(0, 3.9, -36.6), 5.0, Art.neon_of(pal, 1), 1.5, 3.0, 0.09, 0.18)

	# 雨 / 蒸汽
	EnvKit.rain(root, Vector3(0, 15.0, 0), Vector3(20.0, 15.0, 34.0), 3400,
		pal["rain_col"], pal["rain_alpha"], 30.0)
	EnvKit.steam(root, Vector3(22.4, 1.4, -9.0), 26, 1.1, Art.tint(pal, "cool"), 0.16, 2.0, 3.0, 6.0,
		Vector3(0.3, 0.05, 0.3))
	EnvKit.steam(root, Vector3(-5.6, 0.05, 9.0), 34, 1.4, Art.tint(pal, "concrete"), 0.13, 1.7, 3.4, 8.0,
		Vector3(0.5, 0.02, 0.5))
	EnvKit.steam(root, Vector3(5.4, 0.05, -24.5), 30, 1.3, Art.tint(pal, "concrete"), 0.12, 1.9, 3.2, 8.0,
		Vector3(0.5, 0.02, 0.5))
	# 空中的浮尘（雨丝之外的湿空气感）
	EnvKit.steam(root, Vector3(0, 12.0, 0), 220, 0.16, Art.tint(pal, "cool"), 0.5, 0.35, 9.0, 40.0,
		Vector3(18.0, 8.0, 30.0), 0.06)

	# ---------------- 装配
	root.position = origin
	root.add_child(mb.instance(Mats.surface, Mats.glass, true))
	var far_mi := far.instance(Mats.surface, Mats.glass, false)
	far_mi.name = "Far"
	root.add_child(far_mi)
	root.add_child(EnvKit.atmosphere(pal))
	return {
		"node": root, "kind": ALLEY, "name_cn": "第一关 · 霓虹窄巷",
		"hint": "别看着它挥刀 —— 画面里的怪物会格挡你的一切攻击", "floor_y": 0.0,
		"bounds": AABB(Vector3(-HX, -1.0, -HZ), Vector3(HX * 2.0, 14.0, HZ * 2.0)),
		"walls": walls, "cover": cover, "wall_slots": slots, "lamps": lamps,
		"spawns": [_spawn(Vector3(0, 0, -29.0))],
		"player_spawn": _spawn(Vector3(0, 0, 26.0)),
	}


## 跨巷钢桁架：上下弦 + 斜腹杆 + 走道板 + 底部霓虹
static func _gantry(mb: MB, z: float, y: float, pal: Dictionary,
		rng: RandomNumberGenerator, col: Color) -> void:
	var steel := Art.tint(pal, "metal")
	mb.setm(M.METAL, steel, 0.31)
	for sx in [-16.0, 16.0]:
		mb.box(Vector3(sx, y * 0.5, z), Vector3(0.55, y, 0.55))
	mb.box(Vector3(0, y, z), Vector3(36.0, 0.5, 0.5))
	mb.box(Vector3(0, y - 1.5, z), Vector3(36.0, 0.4, 0.4))
	mb.setm(M.METAL, steel * 1.25, 0.33)
	mb.box(Vector3(0, y - 0.72, z), Vector3(36.0, 0.09, 2.2))
	for i in 9:
		var x := -16.0 + 4.0 * float(i)
		mb.box_frame(Vector3(x, y - 1.5, z), Vector3(x + 2.0, y, z), 0.16)
		mb.box(Vector3(x + 2.0, y - 0.4, z), Vector3(0.12, 1.3, 0.12))
	mb.setm(M.EMIT, col, 0.35, 2.8)
	mb.box(Vector3(0, y - 1.66, z), Vector3(35.0, 0.12, 0.3))
	mb.setm(M.METAL, steel * 0.7, 0.37)
	for sx2 in [-11.0, 11.0]:
		mb.box(Vector3(sx2, y - 2.6, z + 0.1), Vector3(3.4, 1.9, 0.16))
		mb.setm(M.EMIT, Art.neon_of(pal, 2), 0.39, 2.2)
		mb.box(Vector3(sx2, y - 2.1, z + 0.2), Vector3(2.6, 0.7, 0.06))
		mb.setm(M.METAL, steel * 0.7, 0.41)


# ================================================================== L2 广场
static func _plaza(origin: Vector3) -> Dictionary:
	const HB := 42.0     # 半宽
	const WH := 30.0     # 墙高
	var pal := Art.PAL_PLAZA
	var rng := H.rng(20261202, 22)
	var root := _root(PLAZA)
	var mb := MB.new()
	var far := MB.new()
	var walls: Array = []
	var cover: Array = []
	var slots: Array = []
	var lamps: Array = []

	# ---------------- 地面：广场铺装 + 两条横穿的街道
	Art.ground_base(mb, Rect2(-HB, -HB, HB * 2.0, HB * 2.0), pal, M.CONCRETE, "concrete", 0.14)
	Art.ground_base(mb, Rect2(-HB, 12.0, HB * 2.0, 14.0), pal, M.ASPHALT, "asphalt", 0.16)
	Art.ground_base(mb, Rect2(-HB, -26.0, HB * 2.0, 14.0), pal, M.ASPHALT, "asphalt", 0.18)
	# 车道线 / 斑马线 / 广场环线
	var x := -HB + 2.0
	while x < HB - 2.0:
		Art.paint_line(mb, Vector2(x, 18.8), Vector2(x + 3.0, 18.8), 0.18, pal)
		Art.paint_line(mb, Vector2(x + 1.5, -12.2), Vector2(x + 4.5, -12.2), 0.18, pal)
		x += 6.4
	for i in 7:
		var px := -6.3 + 2.1 * float(i)
		Art.paint_line(mb, Vector2(px, 12.4), Vector2(px, 18.0), 1.1, pal, 0.022)
	Art.paint_ring(mb, Vector2.ZERO, 13.0, 0.45, pal, 64, 0.022)
	Art.paint_ring(mb, Vector2.ZERO, 8.0, 0.22, pal, 56, 0.022, pal["paint"])
	Art.paint_ring(mb, Vector2.ZERO, 20.0, 0.16, pal, 72, 0.022)
	for i in 4:
		var ang := TAU * float(i) / 4.0 + PI * 0.25
		var dirq := Vector2(cos(ang), sin(ang))
		Art.paint_line(mb, dirq * 4.0, dirq * 30.0, 0.2, pal, 0.021)
	# 排水篦子 + 通风口
	for g in [Vector2(-21.0, 15.5), Vector2(-7.0, 15.5), Vector2(7.0, 15.5), Vector2(21.0, 15.5),
			Vector2(0.0, -13.0), Vector2(-28.0, -13.0), Vector2(28.0, -13.0)]:
		Art.grate(mb, g, Vector2(1.6, 1.1), pal, 0.016, 0.3)

	# ---------------- 四面楼群（内立面正好压在 bounds 上）
	# 北（z = -42）
	var nz := [
		{"x0": -HB, "x1": -26.0, "h": 34.0, "c": 0, "s": M.STY_PUNCHED},
		{"x0": -26.0, "x1": -10.0, "h": 28.0, "c": 1, "s": M.STY_CURTAIN},
		{"x0": -10.0, "x1": 4.0, "h": 40.0, "c": 2, "s": M.STY_PUNCHED},
		{"x0": 4.0, "x1": 20.0, "h": 30.0, "c": 3, "s": M.STY_FINS},
		{"x0": 20.0, "x1": HB, "h": 33.0, "c": 0, "s": M.STY_PANEL},
	]
	for b in nz:
		Art.facade_block(mb, Vector2(b["x0"], -HB), Vector2(b["x1"], -HB), Vector2(0, 1),
			15.0, b["h"], pal, H.rng(101, int(b["x0"]), 5), b["s"],
			Art.wall_col(pal, b["c"]), {"bands": 3, "ground": "arcade"})
	_wall(walls, Vector2(-HB, -HB), Vector2(HB, -HB), WH, Vector2(0, 1))
	slots.append(Art.wall_slot(Vector2(-HB, -HB), Vector2(HB, -HB), 0.0, WH, Vector2(0, 1)))
	# 南（z = +42，玩家身后：整条商业街）
	var sz := [
		{"x0": -HB, "x1": -22.0, "h": 30.0, "c": 3, "s": M.STY_CURTAIN},
		{"x0": -22.0, "x1": -4.0, "h": 36.0, "c": 2, "s": M.STY_PUNCHED},
		{"x0": -4.0, "x1": 16.0, "h": 30.0, "c": 1, "s": M.STY_PANEL},
		{"x0": 16.0, "x1": HB, "h": 32.0, "c": 0, "s": M.STY_FINS},
	]
	for b in sz:
		Art.facade_block(mb, Vector2(b["x0"], HB), Vector2(b["x1"], HB), Vector2(0, -1),
			15.0, b["h"], pal, H.rng(103, int(b["x0"]), 5), b["s"],
			Art.wall_col(pal, b["c"]), {"bands": 3, "ground": "arcade"})
	_wall(walls, Vector2(-HB, HB), Vector2(HB, HB), WH, Vector2(0, -1))
	slots.append(Art.wall_slot(Vector2(-HB, HB), Vector2(HB, HB), 0.0, WH, Vector2(0, -1)))
	# 东西两侧各留一个 16 m 宽的街口（矮墙 h=6），街口外是延伸的街道与远景亮窗楼群
	for side_raw in [-1.0, 1.0]:
		var side: float = side_raw
		var sx := HB * side
		var ivx := Vector2(-side, 0)
		var zb := [
			{"z0": -HB, "z1": -8.0, "h": 32.0, "c": 0, "s": M.STY_CURTAIN},
			{"z0": 8.0, "z1": 20.0, "h": 29.0, "c": 2, "s": M.STY_PUNCHED},
			{"z0": 20.0, "z1": HB, "h": 35.0, "c": 1, "s": M.STY_PANEL},
		]
		for b in zb:
			Art.facade_block(mb, Vector2(sx, b["z0"]), Vector2(sx, b["z1"]), ivx,
				15.0, b["h"], pal, H.rng(107 + int(side), int(b["z0"]), 5), b["s"],
				Art.wall_col(pal, b["c"]), {"bands": 3, "ground": "arcade"})
		_wall(walls, Vector2(sx, -HB), Vector2(sx, -8.0), WH, ivx)
		_wall(walls, Vector2(sx, 8.0), Vector2(sx, HB), WH, ivx)
		slots.append(Art.wall_slot(Vector2(sx, -HB), Vector2(sx, -8.0), 0.0, WH, ivx))
		slots.append(Art.wall_slot(Vector2(sx, 8.0), Vector2(sx, HB), 0.0, WH, ivx))
		# 街口矮墙 + 防撞护栏 + 危险条纹
		var ga := Vector2(sx, -8.0)
		var gb := Vector2(sx, 8.0)
		mb.setm(M.CONCRETE, Art.tint(pal, "concrete") * 0.9, 0.5)
		Art.box_rect(mb, Rect2(sx - 0.35, -8.0, 0.7, 16.0), 0.0, 6.0, true)
		Art.hazard_band(mb, ga + ivx * 0.36, gb + ivx * 0.36, ivx, 0.5, 1.1, pal, 0.52)
		mb.setm(M.METAL, Art.tint(pal, "metal_light") * 0.6, 0.54)
		Art.wall_quad(mb, ga + ivx * 0.42, gb + ivx * 0.42, 5.2, 5.45, ivx)
		Art.wall_quad(mb, ga + ivx * 0.42, gb + ivx * 0.42, 4.3, 4.55, ivx)
		mb.box(Vector3(sx + ivx.x * 0.45, 4.85, 0.0), Vector3(0.12, 0.12, 15.6))
		for i in 4:
			mb.box(Vector3(sx + ivx.x * 0.45, 4.85, -6.0 + 4.0 * float(i)), Vector3(0.16, 0.16, 0.16))
		_wall(walls, ga, gb, 6.0, ivx)
		# 街口外的街道延伸 + 街灯 + 远处楼群
		_street_out(root, mb, far, sx, ivx, pal, H.rng(131 + int(side), 7, 3), side > 0.0)

	# ---------------- 拱廊前的自动售货机 / 箱体（近场可读的小体量）
	for i in 5:
		var vx := -34.0 + 17.0 * float(i)
		if i % 2 == 0:
			Art.vending(mb, Vector3(vx, 0, -40.2), Vector2(0, 1), pal, rng, 0.86 + 0.01 * float(i))
			_cover(cover, Vector3(vx, 0, -40.2), 0.7, 1.9)
		else:
			Art.vending(mb, Vector3(vx, 0, 40.2), Vector2(0, -1), pal, rng, 0.88 + 0.01 * float(i))
			_cover(cover, Vector3(vx, 0, 40.2), 0.7, 1.9)

	# ---------------- 边界霓虹刀牌（广场尺度的竖向地标）
	var blades := [
		{"p": Vector3(-24.0, 7.6, -HB), "n": Vector2(0, 1), "c": 0, "w": 1.2, "h": 5.4},
		{"p": Vector3(24.0, 8.2, -HB), "n": Vector2(0, 1), "c": 2, "w": 1.3, "h": 6.0},
		{"p": Vector3(-20.0, 7.4, HB), "n": Vector2(0, -1), "c": 1, "w": 1.1, "h": 5.0},
		{"p": Vector3(20.0, 8.0, HB), "n": Vector2(0, -1), "c": 3, "w": 1.2, "h": 5.6},
	]
	for b in blades:
		Art.neon_blade(mb, b["p"], b["n"], b["w"], b["h"], Art.neon_of(pal, b["c"]), pal, rng.randf())
		var iv2: Vector2 = b["n"]
		EnvKit.omni(root, b["p"] + Vector3(iv2.x, 0.0, iv2.y) * 2.2, Art.neon_of(pal, b["c"]),
			20.0, 3.4, 1.0)
		lamps.append(Art.facing(b["p"] + Vector3(iv2.x, 0.0, iv2.y) * 2.0,
			b["p"] + Vector3(iv2.x, 0.0, iv2.y) * 10.0))

	# ---------------- 中央掩体柱 + 街道家具
	var pillars := [Vector2(-16.0, -16.0), Vector2(16.0, -16.0), Vector2(-16.0, 16.0), Vector2(16.0, 16.0)]
	for i in pillars.size():
		var r := 1.9 + 0.35 * float(i % 2)
		Art.pillar(mb, pillars[i], r, 6.4, pal, H.rng(i, 201, 4), 0.6 + 0.05 * float(i))
		_cover(cover, Vector3(pillars[i].x, 0, pillars[i].y), r, 6.9)
	# 变电箱 / 报刊亭 / 长凳 / 垃圾桶
	Art.transformer_box(mb, Vector3(-30.0, 0, 6.0), 0.2, pal, rng, 0.7)
	_cover(cover, Vector3(-30.0, 0, 6.0), 1.0, 1.7)
	Art.transformer_box(mb, Vector3(30.0, 0, -6.0), -0.3, pal, rng, 0.72)
	_cover(cover, Vector3(30.0, 0, -6.0), 1.0, 1.7)
	for s in [Vector3(-33.0, 0, 21.0), Vector3(33.0, 0, -21.0)]:
		Art.bench(mb, s, 0.4, pal, 0.74)
		Art.trash_bin(mb, s + Vector3(1.6, 0, 0.4), pal, 0.76)
	Art.vending(mb, Vector3(-40.6, 0, -14.0), Vector2(1, 0), pal, rng, 0.78)
	for i in 4:
		var pvv: Vector2 = pillars[i]
		Art.crate(mb, Vector3(pvv.x + 3.4, 0, pvv.y + 1.2), Vector3(1.4, 1.3, 1.3), 0.3 * float(i),
			pal, rng, 0.8 + 0.01 * float(i))
		_cover(cover, Vector3(pvv.x + 3.4, 0, pvv.y + 1.2), 0.98, 1.3)

	# ---------------- 广场地面发光环 + 地埋上照灯
	mb.setm(M.EMIT, Art.neon_of(pal, 0) * 0.7, 0.6, 0.55)
	Art.paint_ring(mb, Vector2.ZERO, 13.0, 0.22, pal, 72, 0.026, "")
	mb.setm(M.EMIT, Art.neon_of(pal, 2) * 0.6, 0.62, 0.40)
	Art.paint_ring(mb, Vector2.ZERO, 8.0, 0.14, pal, 64, 0.026, "")
	for i in 4:
		var ang := TAU * float(i) / 4.0 + PI * 0.25
		var c2 := Vector2(cos(ang), sin(ang)) * 14.5
		# 灯具本体
		mb.setm(M.METAL, Art.tint(pal, "metal"), 0.64)
		mb.cyl_y(Vector3(c2.x, 0.16, c2.y), 0.36, 0.32, 10, true, 0.30)
		mb.setm(M.EMIT, Art.neon_of(pal, 1), 0.66, 2.6)
		mb.cyl_y(Vector3(c2.x, 0.34, c2.y), 0.28, 0.06, 10, true)
		EnvKit.omni(root, Vector3(c2.x, 0.7, c2.y), Art.neon_of(pal, 1), 15.0, 2.4, 1.3)
		EnvKit.halo(root, Vector3(c2.x, 0.55, c2.y), 1.5, Art.neon_of(pal, 1), 1.0, float(i), 0.06)
		_cover(cover, Vector3(c2.x, 0, c2.y), 0.36, 0.4)

	# ---------------- 水洼 + 积水长条
	var water := _puddle_mat(Color(0.005, 0.010, 0.011), Color(0.02, 0.07, 0.07), 0.95)
	var pud := [
		Vector3(-22.0, 0, 15.6), Vector3(-6.0, 0, 15.8), Vector3(9.0, 0, 15.4), Vector3(24.0, 0, 15.9),
		Vector3(-14.0, 0, -13.2), Vector3(6.0, 0, -13.4), Vector3(26.0, 0, -13.0), Vector3(-31.0, 0, -13.3),
		Vector3(-9.0, 0, 2.0), Vector3(11.0, 0, -2.0), Vector3(0.0, 0, 24.0), Vector3(-24.0, 0, -24.0),
	]
	for i in pud.size():
		Art.puddle(root, pud[i], 2.6 + 1.4 * float(i % 3), 1400 + i, water, 0.024)

	# ---------------- 灯光 & 大气
	EnvKit.lights(root, pal)
	# 广场灯塔（4 根 12 m 桅杆，双侧灯头）
	for i in 4:
		var c := Vector2(-24.0, 0.0) if i == 0 else (Vector2(24.0, 0.0) if i == 1 else
			(Vector2(0.0, -24.0) if i == 2 else Vector2(0.0, 24.0)))
		var head := _mast(mb, c, pal, H.rng(i, 301, 4), 0.9 + 0.03 * float(i))
		lamps.append(Art.facing(head, Vector3.ZERO))
		EnvKit.omni(root, head, Mats.c(pal["cool"]), 40.0, 8.0, 0.85)
		EnvKit.omni(root, head + Vector3(0, -1.2, 0), Mats.c(pal["warm"]) * 0.7, 22.0, 2.8, 1.15)
		EnvKit.halo(root, head, 3.6, Mats.c(pal["cool"]), 1.6, float(i) * 3.7, 0.05)
	_cover(cover, Vector3(-24.0, 0, 0.0), 0.5, 12.0)
	_cover(cover, Vector3(24.0, 0, 0.0), 0.5, 12.0)
	_cover(cover, Vector3(0.0, 0, -24.0), 0.5, 12.0)
	_cover(cover, Vector3(0.0, 0, 24.0), 0.5, 12.0)
	# 拱廊霓虹补光 + 广告屏亮度
	for i in 5:
		EnvKit.omni(root, Vector3(-34.0 + 17.0 * float(i), 5.0, -40.6), Art.neon_of(pal, i), 26.0, 4.2, 1.05)
		EnvKit.omni(root, Vector3(-31.0 + 15.5 * float(i), 5.0, 40.6), Art.neon_of(pal, i + 1), 26.0, 4.2, 1.05)
	# 东西两侧拱廊补光
	for side2_raw in [-1.0, 1.0]:
		var side2: float = side2_raw
		var sx2 := HB * side2
		var ivx2 := Vector2(-side2, 0)
		for i2 in 4:
			var zz := -32.0 + 19.0 * float(i2)
			if absf(zz) < 11.0:
				continue
			EnvKit.omni(root, Vector3(sx2 - ivx2.x * 1.4, 5.0, zz), Art.neon_of(pal, i2 + 1), 24.0, 3.8, 1.05)
	# 街口两侧的暖色橱窗光
	EnvKit.omni(root, Vector3(-41.0, 3.4, -12.0), Art.tint(pal, "warm"), 16.0, 2.6, 1.1)
	EnvKit.omni(root, Vector3(41.0, 3.4, 12.0), Art.tint(pal, "warm"), 16.0, 2.6, 1.1)

	# 雨 / 蒸汽
	EnvKit.rain(root, Vector3(0, 18.0, 0), Vector3(42.0, 18.0, 42.0), 7600,
		pal["rain_col"], 0.38, 32.0)
	for g2 in [Vector3(-21.0, 0.05, 15.5), Vector3(7.0, 0.05, 15.5), Vector3(0.0, 0.05, -13.0),
			Vector3(-28.0, 0.05, -13.0), Vector3(21.0, 0.05, 15.5)]:
		EnvKit.steam(root, g2, 34, 1.5, Art.tint(pal, "concrete"), 0.13, 1.6, 3.4, 9.0,
			Vector3(0.7, 0.02, 0.5))
	EnvKit.steam(root, Vector3(0, 20.0, 0), 320, 0.18, Art.tint(pal, "cool"), 0.45, 0.3, 10.0, 50.0,
		Vector3(36.0, 10.0, 36.0), 0.05)

	root.position = origin
	root.add_child(mb.instance(Mats.surface, Mats.glass, true))
	var far_mi := far.instance(Mats.surface, Mats.glass, false)
	far_mi.name = "Far"
	root.add_child(far_mi)
	root.add_child(EnvKit.atmosphere(pal))
	return {
		"node": root, "kind": PLAZA, "name_cn": "第二关 · 雨夜广场",
		"hint": "画面里的小怪打不动；弹反远程怪的箭，别正对着它", "floor_y": 0.0,
		"bounds": AABB(Vector3(-HB, -1.0, -HB), Vector3(HB * 2.0, 14.0, HB * 2.0)),
		"walls": walls, "cover": cover, "wall_slots": slots, "lamps": lamps,
		"spawns": [_spawn(Vector3(-30.0, 0, -26.0)), _spawn(Vector3(30.0, 0, -26.0)),
			_spawn(Vector3(0.0, 0, -34.0))],
		"player_spawn": _spawn(Vector3(0.0, 0, 30.0)),
	}


## 广场灯塔：12 m 桅杆 + 双侧灯头，返回灯头世界坐标
static func _mast(mb: MB, c: Vector2, pal: Dictionary, rng: RandomNumberGenerator,
		seed := 0.0) -> Vector3:
	mb.setm(M.CONCRETE, Art.tint(pal, "concrete") * 0.9, seed)
	mb.box(Vector3(c.x, 0.3, c.y), Vector3(1.7, 0.6, 1.7))
	mb.setm(M.METAL, Art.tint(pal, "metal_light") * 0.5, seed + 0.1)
	mb.cyl_y(Vector3(c.x, 6.4, c.y), 0.22, 12.8, 10, true, 0.13)
	mb.setm(M.METAL, Art.tint(pal, "metal"), seed + 0.15)
	mb.box(Vector3(c.x, 12.4, c.y), Vector3(1.3, 0.5, 1.3))
	mb.setm(M.EMIT, Mats.c(pal["cool"]), seed + 0.2, 3.4)
	for o in [[1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0]]:
		var d := Vector2(o[0], o[1])
		mb.setm(M.METAL, Art.tint(pal, "metal"), seed + 0.25)
		mb.box(Vector3(c.x + d.x * 0.9, 12.15, c.y + d.y * 0.9), Vector3(absf(d.x) * 1.1 + 0.4, 0.16, absf(d.y) * 1.1 + 0.4))
		mb.setm(M.EMIT, Mats.c(pal["cool"]), seed + 0.3, 3.1)
		mb.box(Vector3(c.x + d.x * 0.9, 11.95, c.y + d.y * 0.9), Vector3(absf(d.x) * 0.9 + 0.5, 0.14, absf(d.y) * 0.9 + 0.5))
	mb.setm(M.ROADPAINT, Art.tint(pal, "stripe"), seed + 0.35)
	mb.cyl_y(Vector3(c.x, 1.1, c.y), 0.26, 0.5, 10, true)
	return Vector3(c.x, 12.1, c.y)


## 街口外的街道延伸：人行道 / 街灯 / 电车轨道 / 远景楼群（放在 far 里，不投影）
static func _street_out(root: Node3D, mb: MB, far: MB, x_wall: float, iv: Vector2,
		pal: Dictionary, rng: RandomNumberGenerator, east: bool) -> void:
	var sgn := -signf(iv.x)          # 负号：街道必须朝场地外侧延伸
	var x_far := x_wall + 150.0 * sgn
	# 街道基面
	mb.setm(M.ASPHALT, Art.tint(pal, "asphalt"), 0.56)
	Art.floor_rect(mb, Rect2(minf(x_wall, x_far), -9.0, 150.0, 18.0), -0.02)
	mb.setm(M.CONCRETE, Art.tint(pal, "concrete") * 0.85, 0.58)
	Art.floor_rect(mb, Rect2(minf(x_wall, x_far), -14.0, 150.0, 5.0), 0.14)
	Art.floor_rect(mb, Rect2(minf(x_wall, x_far), 9.0, 150.0, 5.0), 0.14)
	# 车道线 + 电车轨道
	var t := x_wall + 4.0 * sgn
	while absf(t - x_wall) < 146.0:
		Art.paint_line(mb, Vector2(t, 0.0), Vector2(t + 3.0 * sgn, 0.0), 0.18, pal)
		t += 6.4 * sgn
	mb.setm(M.METAL, Art.tint(pal, "metal_light") * 0.35, 0.6)
	for r in [-3.3, -2.5]:
		Art.floor_rect(mb, Rect2(minf(x_wall, x_far), float(r), 150.0, 0.12), 0.03)
	# 街灯（只在靠街口一侧做 3 盏，远处用自发光代替）
	for i in 3:
		var px := x_wall + (14.0 + 26.0 * float(i)) * sgn
		var head := Art.street_lamp(mb, Vector3(px, 0.14, -11.6), Vector2(0, 1), pal,
			H.rng(i, 411, 2), 0.6 + 0.1 * float(i), 9.0)
		if i == 0:
			EnvKit.omni(root, head, Mats.c(pal["cool"]), 30.0, 5.0, 0.95)
		# 街两侧挂的霓虹招牌（正对街口，从广场能看见）
		mb.setm(M.EMIT, Art.neon_of(pal, i), 0.62 + 0.05 * float(i), 2.2)
		mb.box(Vector3(px + 6.0 * sgn, 6.0, -6.5), Vector3(2.0, 4.4, 0.16))
		mb.setm(M.EMIT, Art.neon_of(pal, i + 2), 0.68 + 0.05 * float(i), 1.8)
		mb.box(Vector3(px - 4.0 * sgn, 7.4, 6.5), Vector3(1.6, 3.6, 0.16))
	# 远处的城市体量：一排亮窗楼群（shader 立面，无投影）
	var cxs := x_wall + 62.0 * sgn
	var rr := H.rng(int(x_wall), 421, 5)
	for i in 10:
		var w := rr.randf_range(14.0, 30.0)
		var d := rr.randf_range(14.0, 26.0)
		var h := rr.randf_range(74.0, 210.0)
		var zz := -96.0 + 21.0 * float(i) + rr.randf_range(-5.0, 5.0)
		Art.skyline_tower(far, Vector2(cxs + rr.randf_range(-30.0, 40.0) * sgn, zz), w, d, h, pal,
			H.rng(i, 431, int(x_wall)), M.STY_CURTAIN if i % 3 == 0 else M.STY_PUNCHED,
			Art.wall_col(pal, i % 4) * 0.9)
	for i in 8:
		var zz2 := -76.0 + 22.0 * float(i)
		Art.skyline_tower(far, Vector2(cxs + rr.randf_range(26.0, 96.0) * sgn, zz2),
			rr.randf_range(18.0, 34.0), rr.randf_range(18.0, 30.0), rr.randf_range(110.0, 260.0), pal,
			H.rng(i, 441, int(x_wall)), M.STY_PUNCHED, Art.wall_col(pal, (i + 1) % 4) * 0.85)


# ================================================================== L3 灯墙厅
static func _chamber(origin: Vector3) -> Dictionary:
	const HB := 60.0     # 半宽（120 × 120，对战空间比初版大一倍）
	const CH := 19.0     # 天花高
	const LAMP_Y := 1.8   # 低位壁灯：灯体中心 1.8 m（影子才能完整落到对面墙上）
	const LAMP_OFF := 0.5  # 贴墙 0.5 m（0.3~0.8 区间）
	var pal := Art.PAL_CHAMBER
	var root := _root(CHAMBER)
	var mb := MB.new()
	var wmb := MB.new()      # 四面大墙单独一份网格 + 低湿度材质：干净平整、无雨痕反光
	var walls: Array = []
	var slots: Array = []
	var lamps: Array = []
	var cover: Array = []

	# ---------------- 地面：暗色抛光板 + 血红发光环 + 中心圆
	Art.ground_base(mb, Rect2(-HB, -HB, HB * 2.0, HB * 2.0), pal, M.CONCRETE, "concrete_dark", 0.14)
	mb.setm(M.METAL, Art.tint(pal, "metal") * 1.15, 0.16)
	Art.floor_rect(mb, Rect2(-HB, -HB, HB * 2.0, 4.0), 0.012)
	Art.floor_rect(mb, Rect2(-HB, HB - 4.0, HB * 2.0, 4.0), 0.012)
	Art.floor_rect(mb, Rect2(-HB, -HB, 4.0, HB * 2.0), 0.012)
	Art.floor_rect(mb, Rect2(HB - 4.0, -HB, 4.0, HB * 2.0), 0.012)
	Art.paint_ring(mb, Vector2.ZERO, 18.0, 0.42, pal, 72, 0.02, "5e1414")
	Art.paint_ring(mb, Vector2.ZERO, 40.0, 0.24, pal, 88, 0.02, "5e1414")
	Art.paint_ring(mb, Vector2.ZERO, 4.4, 0.35, pal, 40, 0.02)
	for i in 4:
		var ang := TAU * float(i) / 4.0
		Art.paint_line(mb, Vector2(cos(ang), sin(ang)) * 5.2, Vector2(cos(ang), sin(ang)) * 44.0,
			0.22, pal, 0.019)
	# 地面红色导光条（贴着四周金属带）
	mb.setm(M.EMIT, Mats.c("e02a1c"), 0.18, 0.85)
	for e in [Rect2(-HB + 4.15, -HB, 0.14, HB * 2.0), Rect2(HB - 4.29, -HB, 0.14, HB * 2.0),
			Rect2(-HB, -HB + 4.15, HB * 2.0, 0.14), Rect2(-HB, HB - 4.29, HB * 2.0, 0.14)]:
		Art.floor_rect(mb, e, 0.022)

	# ---------------- 四面干净大墙 + 壁灯
	var defs := [
		{"a": Vector2(-HB, -HB), "b": Vector2(HB, -HB), "n": Vector2(0, 1)},
		{"a": Vector2(HB, HB), "b": Vector2(-HB, HB), "n": Vector2(0, -1)},
		{"a": Vector2(-HB, HB), "b": Vector2(-HB, -HB), "n": Vector2(1, 0)},
		{"a": Vector2(HB, -HB), "b": Vector2(HB, HB), "n": Vector2(-1, 0)},
	]
	for d in defs:
		var a: Vector2 = d["a"]
		var b: Vector2 = d["b"]
		var n: Vector2 = d["n"]
		# 墙体（向内 6 m 厚），内立面 = 离场最近的平面
		# 墙面用「喷涂板」材质：没有 hgt/bump 项，掠射角下不会出现细密竖向条纹/摩尔纹
		wmb.setm(M.PLASTIC, Art.wall_col(pal, 0), 0.2)
		Art.wall_quad(wmb, a, b, 0.0, CH, n)
		var shell_a := a - n * 0.04          # 退后 4 cm，避免与墙面板共面 z-fighting
		var shell_b := b - n * 0.04
		var back := a - n * 6.0
		var back2 := b - n * 6.0
		mb.setm(M.WALL, Art.wall_col(pal, 1) * 0.8, 0.22, 0.0, 60.0)
		mb.prism(PackedVector2Array([shell_a, shell_b, back2, back]), 0.0, CH + 0.6, true, false)
		# 踢脚 + 檐口（仅两条水平线，保持墙面干净）
		var a_in := a + n * 0.02
		var b_in := b + n * 0.02
		wmb.setm(M.CONCRETE, Art.tint(pal, "concrete_dark"), 0.24)
		Art.wall_quad(wmb, a_in, b_in, 0.0, 0.34, n)
		wmb.setm(M.METAL, Art.tint(pal, "metal"), 0.26)
		Art.wall_quad(wmb, a_in, b_in, CH - 0.85, CH, n)
		# 危险条纹脚线：只往内 1.8 cm —— 必须留在影子网格（沿法向 +3 cm）后面，避免共面闪烁
		var a_in2 := a + n * 0.018
		var b_in2 := b + n * 0.018
		Art.hazard_band(wmb, a_in2, b_in2, n, 0.34, 0.62, pal, 0.28)
		_wall(walls, a, b, CH, n)
		# 墙面标架 + 低位壁灯（灯体中心 1.8 m、贴墙 0.5 m）
		var slot := Art.wall_slot(a, b, 0.0, CH, n)
		slots.append(slot)
		var c := (a + b) * 0.5
		var slot_xf: Transform3D = slot["xform"]
		var lamp_base := Transform3D(slot_xf.basis, Vector3(c.x, LAMP_Y, c.y))
		var bulb := Art.wall_sconce(mb, lamp_base, pal, 0.3, LAMP_OFF)
		lamps.append(Art.facing(bulb, bulb + Vector3(n.x, 0.0, n.y)))
		# 灯口只留一个很小的本地光池：灯体正上方那片墙不能过曝（影子会落在那上面）
		EnvKit.omni(root, bulb, Color(0.92, 0.96, 1.0), 9.0, 1.2, 1.45)
		# 向上 / 向内的窄光晕（灯体可读性，纵向拉长、压扁横向）
		EnvKit.halo(root, bulb + Vector3(0, 0.62, 0) + Vector3(n.x, 0.0, n.y) * 0.06,
			1.3, Color(0.94, 0.97, 1.0), 1.35, float(slots.size()) * 2.3, 0.06, 0.0, 1.0, 2.2)
		# 墙脚两侧上照灯：光池压在墙脚与两侧，让影子落在中等亮度的大墙面上
		var th3 := (Vector3(b.x, 0.0, b.y) - Vector3(a.x, 0.0, a.y)).normalized()
		for side_v in [-1.0, 1.0]:
			var sv: float = side_v
			var up_root := Vector3(c.x, 0.0, c.y) + th3 * (sv * 20.0) + Vector3(n.x, 0.0, n.y) * 0.52
			mb.setm(M.METAL, Art.tint(pal, "metal"), 0.5 + 0.02 * float(slots.size()))
			mb.cyl_y(up_root + Vector3(0, 0.15, 0), 0.25, 0.3, 10, true, 0.19)
			mb.setm(M.EMIT, Mats.c("fff0e6"), 0.52, 2.4)
			mb.cyl_y(up_root + Vector3(0, 0.33, 0), 0.19, 0.07, 10, true)
			var aim_pt := up_root + th3 * (sv * 10.0) + Vector3(0, 7.5, 0) - Vector3(n.x, 0.0, n.y) * 0.7
			EnvKit.spot(root, Art.aim(up_root + Vector3(0, 0.35, 0), aim_pt),
				Color(1.0, 0.92, 0.86), 22.0, 1.7, 62.0, 0.95)
			EnvKit.halo(root, up_root + Vector3(0, 0.4, 0), 1.15, Color(1.0, 0.95, 0.9), 0.8,
				float(slots.size()) * 3.1 + sv, 0.06)

	# ---------------- 天花板：钢桁架 + 暗色顶板 + 红色导光槽
	mb.setm(M.METAL, Art.tint(pal, "metal"), 0.4)
	for i in 5:
		var x := -48.0 + 24.0 * float(i)
		mb.box(Vector3(x, CH - 0.55, 0), Vector3(0.65, 0.85, HB * 2.0))
		mb.box(Vector3(0, CH - 0.55, x), Vector3(HB * 2.0, 0.85, 0.65))
	mb.setm(M.METAL, Art.tint(pal, "metal") * 1.3, 0.42)
	for i in 3:
		var y := CH - 1.3 - 0.5 * float(i)
		mb.box(Vector3(0, y, -HB + 0.4), Vector3(HB * 2.0, 0.1, 0.1))
		mb.box(Vector3(0, y, HB - 0.4), Vector3(HB * 2.0, 0.1, 0.1))
	mb.setm(M.PLASTIC, Art.tint(pal, "metal") * 1.5, 0.44)
	Art.ceil_rect(mb, Rect2(-HB, -HB, HB * 2.0, HB * 2.0), CH + 0.2)
	mb.setm(M.EMIT, Mats.c("e03420"), 0.46, 0.62)
	for e in [Rect2(-44.0, -2.0, 88.0, 0.2), Rect2(-2.0, -44.0, 0.2, 88.0)]:
		Art.ceil_rect(mb, e, CH - 0.16)

	# ---------------- 灯光 & 大气
	EnvKit.lights(root, pal)
	# 中央两盏极暗的红光，给地面与顶棚一点体积感（不投影）
	# 主匀光（暖白，压一档：机身在场地中央不再过曝，墙面仍是"中等亮度"）
	EnvKit.omni(root, Vector3(0, 13.0, 0), Color(1.0, 0.86, 0.80), 88.0, 3.15, 0.50)
	# 地面红光（只做低位氛围，能量减半）
	EnvKit.omni(root, Vector3(0, 1.5, 0), Color(1.0, 0.26, 0.18), 46.0, 1.0, 1.25)
	# 冷色顶光 + 四角冷补：把红墙与大怪暗剪影分开，也给机甲一点冷轮廓
	EnvKit.omni(root, Vector3(0, 15.5, 0), Color(0.42, 0.70, 1.0), 92.0, 0.9, 0.55)
	for cs in [Vector2(-40, -40), Vector2(40, -40), Vector2(-40, 40), Vector2(40, 40)]:
		EnvKit.omni(root, Vector3(cs.x, 6.5, cs.y), Color(0.38, 0.66, 1.0), 36.0, 0.55, 0.9)
	# 极淡的细雨/落尘（室内滴落的水汽），与浮尘叠加
	EnvKit.rain(root, Vector3(0, 11.0, 0), Vector3(52.0, 8.0, 52.0), 2600,
		pal["rain_col"], 0.10, 9.0)
	# 浮尘（慢速微尘）
	EnvKit.steam(root, Vector3(0, 11.0, 0), 1400, 0.05, Color(1.0, 0.92, 0.86), 0.30, 0.22, 16.0, 30.0,
		Vector3(48.0, 7.0, 48.0), 0.05)

	root.position = origin
	root.add_child(mb.instance(Mats.surface, Mats.glass, true))
	var wmat: ShaderMaterial = Mats.shader_mat.duplicate()
	wmat.set_shader_parameter("wetness", 0.0)   # 干墙：去掉 wetness 驱动的竖向雨痕（远处会摩尔纹）
	wmat.set_shader_parameter("dirt", 0.35)
	var wmi := wmb.instance(wmat, Mats.glass, true)
	wmi.name = "Walls"
	root.add_child(wmi)
	root.add_child(EnvKit.atmosphere(pal))
	return {
		"node": root, "kind": CHAMBER, "name_cn": "第三关 · 灯墙之厅",
		"hint": "直视大怪即死 —— 看墙上的影子找它", "floor_y": 0.0,
		"bounds": AABB(Vector3(-HB, -1.0, -HB), Vector3(HB * 2.0, 21.0, HB * 2.0)),
		"walls": walls, "cover": cover, "wall_slots": slots, "lamps": lamps,
		"spawns": [Art.facing(Vector3.ZERO, Vector3(0.0, 0, HB))],
		# 背向进入：出生时背对大怪（-Z 指向南墙），先看见墙上的影子，转身才是对决
		"player_spawn": Art.facing(Vector3(0.0, 0, HB - 20.0), Vector3(0.0, 0, HB * 2.0)),
	}

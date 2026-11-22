extends RefCounted
## 仓库关卡：56 × 36 × 10 m，按 ArenaKit 契约交付。
## 几何直接用 actdemo 的世界单位（1 u = 0.547 m）建，避免再出现“4.57 u 当成米”的错误。

const Kit := preload("res://src/warehouse/kit.gd")

const U := 1.0 / 0.547
const BALL := 1.2
const HALF_X := 28.0
const HALF_Z := 18.0
const H := 13.5
const WALL_PAD := 0.60
# 地面层玻璃办公室
const OFF_X0 := -27.5
const OFF_X1 := -20.5
const OFF_Z0 := -17.5
const OFF_Z1 := -10.5
const OFF_H := 4.20      # 玩家中心与墙面的距离（米）

# 二层环廊（只沿四边一圈）
const RING_TOP := 6.40
const RING_W := 3.60
const RING_T := 0.18
const RING_X := HALF_X - RING_W * 0.5
const RING_Z := HALF_Z - RING_W * 0.5
const GATE_A := -7.40      # 环廊东侧跑酷落脚开口
const GATE_B := -3.00

# 跑酷货柜：x/z 米，top 为可站立顶面
const PARKOUR := [
	{"c": Vector3(21.5, 0.0, 10.0), "top": 1.10, "hx": 1.20, "hz": 0.90},
	{"c": Vector3(21.5, 0.0, 6.2), "top": 2.20, "hx": 1.20, "hz": 0.90},
	{"c": Vector3(21.5, 0.0, 2.4), "top": 3.30, "hx": 1.20, "hz": 0.90},
	{"c": Vector3(21.5, 0.0, -1.4), "top": 4.40, "hx": 1.20, "hz": 0.90},
	{"c": Vector3(21.5, 0.0, -5.2), "top": 5.50, "hx": 1.20, "hz": 0.90},
]


static func build(origin := Vector3.ZERO) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arena_warehouse"
	root.position = origin

	_environment(root)
	_shell(root)
	_racks(root)
	_dock(root)
	_office(root)
	_ring(root)
	_parkour(root)
	_props(root)
	_details(root)
	_lights(root)

	var walls: Array = []
	_wall(walls, Vector2(-HALF_X, -HALF_Z), Vector2(HALF_X, -HALF_Z), H, Vector2(0, 1))
	_wall(walls, Vector2(HALF_X, -HALF_Z), Vector2(HALF_X, HALF_Z), H, Vector2(-1, 0))
	_wall(walls, Vector2(HALF_X, HALF_Z), Vector2(-HALF_X, HALF_Z), H, Vector2(0, -1))
	_wall(walls, Vector2(-HALF_X, HALF_Z), Vector2(-HALF_X, -HALF_Z), H, Vector2(1, 0))
	# 地面层玻璃办公室隔断（前墙 + 东墙）
	_wall(walls, Vector2(-27.5, -10.5), Vector2(-20.5, -10.5), 3.2, Vector2(0, 1))
	_wall(walls, Vector2(-20.5, -17.5), Vector2(-20.5, -10.5), 3.2, Vector2(1, 0))

	var platforms: Array = []
	var cover: Array = []
	# 货架：每排沿 x 用密排小圆，半径=半深，不额外放大
	for z in [-12.0, -8.0, 8.0, 12.0]:
		var x := -19.2
		while x <= 19.2:
			_cover(cover, Vector3(x, 0.0, z), 0.78, 7.40)
			x += 1.6
	# 柱
	for x in [-24.0, 24.0]:
		for z in [-14.0, -6.0, 6.0, 14.0]:
			_cover(cover, Vector3(x, 0.0, z), 0.36, 10.0)
	# 可站立的小平台（视觉物件 + 平台高度 + 低位碰撞）
	for spec in [[Vector3(5.0, 0.0, 2.0), 1.30, 1.00, 0.46],
			[Vector3(-9.0, 0.0, 4.0), 1.50, 0.90, 1.35],
			[Vector3(6.0, 0.0, -14.0), 1.20, 0.90, 0.95]]:
		var c: Vector3 = spec[0]
		var rx: float = float(spec[1])
		var rz: float = float(spec[2])
		var top: float = float(spec[3])
		platforms.append({"c": Vector3(c.x * U, 0.0, c.z * U), "hx": rx * U, "hz": rz * U, "h": top * U})
		_cover(cover, c, maxf(rx, rz) * 0.9, top - 0.30)

	# 叉车：侧面只挡到 1.05（站上去不被推），后座 / 配重肩 / 顶棚都能站
	_cover(cover, Vector3(12.4, 0.0, 14.1), 1.05, 1.05)
	for spec in [[Vector3(10.98, 0.0, 14.1), 1.37, 0.30, 0.62],   # 配重圆肩
			[Vector3(12.06, 0.0, 14.1), 1.32, 0.27, 0.27],        # 座椅
			[Vector3(12.40, 0.0, 14.1), 2.41, 0.52, 0.60]]:       # 护顶棚
		var fp: Vector3 = spec[0]
		platforms.append({"c": Vector3(fp.x * U, 0.0, fp.z * U),
			"hx": float(spec[2]) * U, "hz": float(spec[3]) * U, "h": float(spec[1]) * U})

	# 通道地面备货：托盘货 / 空托盘摞 / 周转箱（顶面可以跳上去）
	var floor_tops := [0.59, 0.52, 0.90]
	var floor_hx := [0.62, 0.62, 0.34]
	var floor_hz := [0.52, 0.50, 0.30]
	var fi := 0
	for c in floor_cargo_spots():
		var ft: float = floor_tops[fi]
		platforms.append({"c": Vector3(c.x * U, 0.0, c.z * U),
			"hx": float(floor_hx[fi]) * U, "hz": float(floor_hz[fi]) * U, "h": ft * U})
		_cover(cover, c, maxf(float(floor_hx[fi]), float(floor_hz[fi])) * 1.1, ft - 0.30)
		fi += 1

	# 地面上的可踩道具：位置 / 顶面 / 半宽 / 半深
	for spec in [[Vector3(2.0, 0.0, 6.25), 0.55, 0.70, 0.35],    # 托盘千斤顶
			[Vector3(-2.0, 0.0, -6.0), 0.94, 0.50, 0.30],        # 工具车
			[Vector3(19.0, 0.0, 2.0), 1.00, 0.80, 0.50],         # 纸板捆
			[Vector3(-7.0, 0.0, 14.0), 0.63, 0.62, 0.52],        # 装卸托盘 A
			[Vector3(20.0, 0.0, 13.6), 1.05, 0.55, 0.45]]:       # 装卸托盘 B（缠绕膜）
		var pp: Vector3 = spec[0]
		var pt: float = float(spec[1])
		platforms.append({"c": Vector3(pp.x * U, 0.0, pp.z * U),
			"hx": float(spec[2]) * U, "hz": float(spec[3]) * U, "h": pt * U})
		_cover(cover, pp, maxf(float(spec[2]), float(spec[3])) * 1.1, pt - 0.30)

	# 预压纸板捆（三摞）
	for i in 3:
		var bx := 18.0 - float(i) * 1.2
		platforms.append({"c": Vector3(bx * U, 0.0, -14.0 * U),
			"hx": 0.52 * U, "hz": 0.45 * U, "h": 0.95 * U})
		_cover(cover, Vector3(bx, 0.0, -14.0), 0.58, 0.65)

	# 油桶：六个各自可以站
	for i in 6:
		var bxx := -9.0 + float(i) * 0.8
		platforms.append({"c": Vector3(bxx * U, 0.0, -15.5 * U),
			"hx": 0.28 * U, "hz": 0.28 * U, "h": 0.90 * U})
		_cover(cover, Vector3(bxx, 0.0, -15.5), 0.34, 0.60)

	# 办公室屋顶也当平台：从环廊掉到屋顶站得住
	platforms.append({
		"c": Vector3((OFF_X0 + OFF_X1) * 0.5 * U, 0.0, (OFF_Z0 + OFF_Z1) * 0.5 * U),
		"hx": ((OFF_X1 - OFF_X0) * 0.5 + 0.15) * U,
		"hz": ((OFF_Z1 - OFF_Z0) * 0.5 + 0.15) * U,
		"h": (OFF_H + 0.14) * U,
	})

	# 办公室玻璃隔断 / 东墙
	var ox := OFF_X0
	while ox <= OFF_X1:
		if ox < -25.9 or ox > -23.7:
			_cover(cover, Vector3(ox, 0.0, OFF_Z1), 0.45, 2.90)
		ox += 0.95
	var oz := OFF_Z0
	while oz <= OFF_Z1:
		_cover(cover, Vector3(OFF_X1, 0.0, oz), 0.45, 2.90)
		oz += 0.95
	for dx in [-26.3, -23.6]:
		platforms.append({"c": Vector3(dx * U, 0.0, -14.2 * U),
			"hx": 0.90 * U, "hz": 0.38 * U, "h": 0.80 * U})
		_cover(cover, Vector3(dx, 0.0, -14.2), 0.80, 0.50)

	# 二层环廊：只沿四边，中间是空的
	for spec in [[Vector3(0.0, 0.0, -HALF_Z + RING_W * 0.5), HALF_X, RING_W * 0.5],
			[Vector3(0.0, 0.0, HALF_Z - RING_W * 0.5), HALF_X, RING_W * 0.5],
			[Vector3(HALF_X - RING_W * 0.5, 0.0, 0.0), RING_W * 0.5, HALF_Z - RING_W],
			[Vector3(-HALF_X + RING_W * 0.5, 0.0, 0.0), RING_W * 0.5, HALF_Z - RING_W]]:
		var rc: Vector3 = spec[0]
		platforms.append({"c": Vector3(rc.x * U, 0.0, rc.z * U),
			"hx": float(spec[1]) * U, "hz": float(spec[2]) * U, "h": RING_TOP * U})

	# 二层环廊护栏：挡住行走，但 1.15 m 高、跳跃（1.5 m）可以翻过去
	var inz2 := HALF_Z - RING_W
	var inx2 := HALF_X - RING_W
	var rail_h := 0.80          # 顶面 7.20；栏杆顶平台在 7.54，站上去时不会被推开
	# 间距必须 < 2×(0.35+1.1)/U ≈ 1.58 m，否则两个圆中间能钻过去
	var rail_step := 1.10
	# 按等分取点，保证两端正好落在内角点上（不留角上的口子）
	var nx := maxi(2, int(ceil(inx2 * 2.0 / rail_step)))
	for i in nx + 1:
		var px := -inx2 + inx2 * 2.0 * float(i) / float(nx)
		_cover(cover, Vector3(px, 0.0, -inz2), 0.10, rail_h, RING_TOP)
		_cover(cover, Vector3(px, 0.0, inz2), 0.10, rail_h, RING_TOP)
	var nz := maxi(2, int(ceil(inz2 * 2.0 / rail_step)))
	for i in nz + 1:
		var pz := -inz2 + inz2 * 2.0 * float(i) / float(nz)
		_cover(cover, Vector3(-inx2, 0.0, pz), 0.10, rail_h, RING_TOP)
		if pz <= GATE_A or pz >= GATE_B:
			_cover(cover, Vector3(inx2, 0.0, pz), 0.10, rail_h, RING_TOP)
	# 开口两端封死
	for gz2 in [GATE_A, GATE_B]:
		_cover(cover, Vector3(inx2, 0.0, gz2), 0.10, rail_h, RING_TOP)

	# 货架顶板：跳上去可以在整排上跑
	for z in [-12.0, -8.0, 8.0, 12.0]:
		platforms.append({"c": Vector3(0.0, 0.0, z * U), "hx": 20.1 * U, "hz": 0.71 * U,
			"h": 8.00 * U})

	# 栏杆顶面：可以跳上去站着。strict = 用机体中心判定，而不是四足凸包，
	# 否则隔 0.9 m 也能“站”在空气上
	var rz2 := HALF_Z - RING_W - 0.10
	var rx2 := HALF_X - RING_W - 0.10
	var rail_y := RING_TOP + 1.14
	for rspec in [[Vector3(0.0, 0.0, -rz2), HALF_X - RING_W, 0.30],
			[Vector3(0.0, 0.0, rz2), HALF_X - RING_W, 0.30],
			[Vector3(-rx2, 0.0, 0.0), 0.30, HALF_Z - RING_W],
			[Vector3(rx2, 0.0, -10.90), 0.30, 3.50],
			[Vector3(rx2, 0.0, 5.70), 0.30, 8.70]]:
		var rp: Vector3 = rspec[0]
		platforms.append({"c": Vector3(rp.x * U, 0.0, rp.z * U),
			"hx": float(rspec[1]) * U, "hz": float(rspec[2]) * U,
			"h": rail_y * U, "strict": true})

	# 跑酷货柜
	for spec in PARKOUR:
		var pc: Vector3 = spec["c"]
		var ptop: float = float(spec["top"])
		var phx: float = float(spec["hx"])
		var phz: float = float(spec["hz"])
		platforms.append({"c": Vector3(pc.x * U, 0.0, pc.z * U), "hx": phx * U, "hz": phz * U,
			"h": ptop * U})
		_cover(cover, pc, maxf(phx, phz) * 0.95, ptop - 0.60)

	# _clamp_to_arena 固定内缩 3 u；这里把 bounds 外扩，使实际限制落在 WALL_PAD 米处
	var over := 3.0 / U - WALL_PAD
	var bounds := AABB(Vector3((-HALF_X - over) * U, 0.0, (-HALF_Z - over) * U),
		Vector3((HALF_X + over) * 2.0 * U, H * U, (HALF_Z + over) * 2.0 * U))
	var occ = preload("res://src/warehouse/occlusion.gd").new()
	occ.name = "Occlusion"
	occ.setup(root.get_node("Shell"), HALF_X * U, HALF_Z * U, H * U)
	root.add_child(occ)

	var spawn := Transform3D(Basis(), Vector3(0.0, 0.0, 2.0 * U))

	return {
		"node": root,
		"kind": "warehouse",
		"name_cn": "仓库 · 装卸区",
		"hint": "东侧货柜可跑酷上二层环廊；沿通道绕行",
		"floor_y": 0.0,
		"bounds": bounds,
		"walls": walls,
		"cover": cover,
		"platforms": platforms,
		"camera_open": true,
		"ceiling": H * U,
		"spawns": [
			_ring_spawn(Vector3(RING_X, RING_TOP, -9.5)),
			_ring_spawn(Vector3(RING_X, RING_TOP, 9.5)),
			_ring_spawn(Vector3(-RING_X, RING_TOP, -9.5)),
			_ring_spawn(Vector3(-RING_X, RING_TOP, 9.5)),
		],
		"wall_slots": [],
		"lamps": [],
		"player_spawn": spawn,
	}


static func P(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * U


static func S(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * U


static func _wall(walls: Array, a: Vector2, b: Vector2, h: float, n: Vector2) -> void:
	walls.append({"a": a * U, "b": b * U, "h": h * U, "n": n.normalized()})


static func _ring_spawn(p: Vector3) -> Transform3D:
	var d := Vector3(-p.x, 0.0, -p.z)
	if d.length() < 0.01:
		d = Vector3.FORWARD
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), p * U)


static func _cover(cover: Array, c: Vector3, phys_r: float, h: float, base_y := 0.0) -> void:
	# cam=false：悬空掩体（二层护栏）只挡角色，不参与相机避让，
	# 否则相机在楼下也会被这圈“看不见的柱子”顶开
	cover.append({"c": Vector3(c.x * U, base_y * U, c.z * U), "r": phys_r * U + BALL,
		"h": h * U, "cam": base_y <= 0.01})


# ------------------------------------------------------------------ 环境
static func _environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.008, 0.013)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.09, 0.14, 0.19)
	env.ambient_light_energy = 0.36
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.94
	env.tonemap_white = 2.8
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.22
	env.adjustment_saturation = 1.20
	env.adjustment_brightness = 1.02

	env.glow_enabled = true
	env.glow_intensity = 0.95
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.020, 0.070, 0.090)
	env.fog_light_energy = 0.42
	env.fog_depth_begin = 14.0 * U
	env.fog_depth_end = 120.0 * U
	env.fog_density = 0.70
	env.fog_sky_affect = 0.0

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.010
	env.volumetric_fog_albedo = Color(0.05, 0.11, 0.14)
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_anisotropy = 0.25

	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.6
	env.ssao_power = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_out = 1.6

	env.ssil_enabled = false
	env.sdfgi_enabled = false

	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.48, 0.62, 0.95)
	sun.light_energy = 0.12
	sun.rotation_degrees = Vector3(-62.0, 28.0, 0.0)
	sun.shadow_enabled = false
	root.add_child(sun)


# ------------------------------------------------------------------ 外壳
static func _shell(root: Node3D) -> void:
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://gfx/warehouse/floor.gdshader")
	floor_mat.set_shader_parameter("base_col", Vector3(0.040, 0.047, 0.058))
	floor_mat.set_shader_parameter("grout_col", Vector3(0.016, 0.021, 0.028))
	floor_mat.set_shader_parameter("tile", 2.0)
	floor_mat.set_shader_parameter("grout", 0.02)
	floor_mat.set_shader_parameter("stain", 0.72)
	floor_mat.set_shader_parameter("wet", 0.56)
	var wall_mat := Kit.std(Color(0.072, 0.082, 0.096), 0.55, 0.55, {"noise": 1.2, "grime": 0.42, "bump": 0.65, "streak": 0.45, "dirt": Color(0.018, 0.022, 0.028)})
	var dark := Kit.std(Color(0.024, 0.028, 0.036), 0.55, 0.4)
	var steel := Kit.std(Color(0.13, 0.15, 0.18), 0.35, 0.85)
	var neon_c := Kit.emissive(Color(0.22, 0.82, 1.0), 2.0)
	var neon_m := Kit.emissive(Color(1.0, 0.18, 0.58), 1.8)

	Kit.box(root, S(56.0, 0.4, 36.0), P(0.0, -0.2, 0.0), floor_mat)

	# 外壳分组：相机在墙外/屋顶上方时，只隐藏靠近相机的那一面，实现“单向透视”
	var shell := Node3D.new()
	shell.name = "Shell"
	root.add_child(shell)
	var g_n := Node3D.new()
	g_n.name = "North"
	var g_s := Node3D.new()
	g_s.name = "South"
	var g_e := Node3D.new()
	g_e.name = "East"
	var g_w := Node3D.new()
	g_w.name = "West"
	var g_r := Node3D.new()
	g_r.name = "Roof"
	for g in [g_n, g_s, g_e, g_w, g_r]:
		shell.add_child(g)

	Kit.box(g_n, S(56.4, H, 0.3), P(0.0, H * 0.5, -HALF_Z - 0.15), wall_mat)
	Kit.box(g_s, S(56.4, H, 0.3), P(0.0, H * 0.5, HALF_Z + 0.15), wall_mat)
	Kit.box(g_w, S(0.3, H, 36.4), P(-HALF_X - 0.15, H * 0.5, 0.0), wall_mat)
	Kit.box(g_e, S(0.3, H, 36.4), P(HALF_X + 0.15, H * 0.5, 0.0), wall_mat)
	Kit.box(g_r, S(56.0, 0.2, 36.0), P(0.0, H + 0.1, 0.0), dark)

	for i in 28:
		var x := -27.0 + float(i) * 2.0
		Kit.box(g_n, S(0.08, 9.6, 0.06), P(x, 4.8, -HALF_Z + 0.03), steel)
		Kit.box(g_s, S(0.08, 9.6, 0.06), P(x, 4.8, HALF_Z - 0.03), steel)
	for i in 18:
		var z := -17.0 + float(i) * 2.0
		Kit.box(g_w, S(0.06, 9.6, 0.08), P(-HALF_X + 0.03, 4.8, z), steel)
		Kit.box(g_e, S(0.06, 9.6, 0.08), P(HALF_X - 0.03, 4.8, z), steel)

	# 墙身霓虹横线（属于外壳，随对应墙一起隐藏）
	Kit.box(g_n, S(56.0, 0.07, 0.05), P(0.0, 3.60, -HALF_Z + 0.06), neon_c)
	Kit.box(g_s, S(56.0, 0.07, 0.05), P(0.0, 3.60, HALF_Z - 0.06), neon_c)
	Kit.box(g_w, S(0.05, 0.07, 36.0), P(-HALF_X + 0.06, 3.60, 0.0), neon_m)
	Kit.box(g_e, S(0.05, 0.07, 36.0), P(HALF_X - 0.06, 3.60, 0.0), neon_m)

	# 屋面桁架（始终可见）+ 天窗（随屋顶隐藏）
	for z in [-15.0, -9.0, -3.0, 3.0, 9.0, 15.0]:
		Kit.box(root, S(56.0, 0.28, 0.28), P(0.0, H - 0.60, z), steel)
		for x in [-20.0, -10.0, 0.0, 10.0, 20.0]:
			Kit.box(root, S(0.18, 1.2, 0.18), P(x, H - 1.00, z), steel)
	for x in [-14.0, 0.0, 14.0]:
		for z in [-8.0, 8.0]:
			var sky := Kit.box(g_r, S(6.0, 0.08, 4.0), P(x, H - 0.30, z),
				Kit.emissive(Color(0.34, 0.66, 1.0), 1.6))
			sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 柱
	for x in [-24.0, 24.0]:
		for z in [-14.0, -6.0, 6.0, 14.0]:
			Kit.box(root, S(0.5, H, 0.5), P(x, H * 0.5, z), wall_mat)
			Kit.box(root, S(1.1, 0.2, 1.1), P(x, 0.1, z), dark)
			Kit.box(root, S(0.56, 0.18, 0.56), P(x, 1.4, z), neon_m if x > 0.0 else neon_c)
			Kit.box(root, S(0.05, 7.4, 0.05), P(x - (0.28 if x > 0.0 else -0.28), 4.2, z), neon_c)

	# 地面标线
	var paint := Kit.emissive(Color(0.25, 0.86, 1.0), 0.85)
	for z in [-7.1, -8.9, 7.1, 8.9]:
		Kit.box(root, S(40.0, 0.012, 0.10), P(0.0, 0.012, z), paint)
	for x in [-2.0, 2.0]:
		Kit.box(root, S(0.10, 0.012, 34.0), P(x, 0.012, 0.0), paint)


# ------------------------------------------------------------------ 货架
## 统一按“米”作图，交给 Kit 时再换成世界单位
static func _mb3(root: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3,
		shadow := true) -> MeshInstance3D:
	var mi := Kit.box(root, size * U, pos * U, mat, rot)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _mb(root: Node3D, size: Vector3, pos: Vector3, mat: Material, yaw := 0.0,
		shadow := true) -> MeshInstance3D:
	return _mb3(root, size, pos, mat, Vector3(0.0, yaw, 0.0), shadow)


static func _hash(a: int, b: int, c: int) -> int:
	return absi((a * 73856093) ^ (b * 19349663) ^ (c * 83492791)) % 997


static var _ink_mat: Material = null


static func _ink() -> Material:
	if _ink_mat == null:
		_ink_mat = Kit.std(Color(0.07, 0.065, 0.06), 0.85, 0.0)
	return _ink_mat


## 木托盘：承重块 + 面板（远看有厚度差）
static func _pallet(root: Node3D, base: Vector3, yaw: float, top: Material, bottom: Material) -> void:
	_mb(root, Vector3(1.16, 0.10, 0.96), base + Vector3(0.0, 0.05, 0.0), bottom, yaw)
	_mb(root, Vector3(1.24, 0.028, 1.00), base + Vector3(0.0, 0.112, 0.0), top, yaw, false)


## 纸箱：箱体 + 顶部胶带 + 正面竖胶带 +（可选）面单
static func _carton(root: Node3D, base: Vector3, yaw: float, w: float, h: float, d: float,
		mat: Material, tape: Material, lab: Material, tilt := 0.0) -> void:
	var rot := Vector3(tilt, yaw, 0.0)
	_mb3(root, Vector3(w, h, d), base + Vector3(0.0, h * 0.5, 0.0), mat, rot)
	_mb3(root, Vector3(w * 0.15, 0.010, d * 0.97), base + Vector3(0.0, h + 0.005, 0.0), tape, rot, false)
	_mb3(root, Vector3(w * 0.15, h * 0.94, 0.010), base + Vector3(0.0, h * 0.5, d * 0.5 + 0.005),
		tape, rot, false)
	if lab != null:
		_mb3(root, Vector3(w * 0.32, h * 0.24, 0.008),
			base + Vector3(w * 0.17, h * 0.66, d * 0.5 + 0.009), lab, rot, false)
		_mb3(root, Vector3(w * 0.21, h * 0.035, 0.006),
			base + Vector3(w * 0.17, h * 0.60, d * 0.5 + 0.013), _ink(), rot, false)


## 企业货箱：深色箱体 + 冷光边条（赛博朋克味）
static func _corp_crate(root: Node3D, base: Vector3, yaw: float, w: float, h: float, d: float,
		seed: int) -> void:
	var shell := Kit.std(Color(0.050, 0.060, 0.075), 0.40, 0.50)
	var glow := Kit.emissive(Color(0.20, 0.80, 1.0) if seed % 2 == 0 else Color(1.0, 0.20, 0.62), 1.6)
	_mb(root, Vector3(w, h, d), base + Vector3(0.0, h * 0.5, 0.0), shell, yaw)
	_mb(root, Vector3(w * 1.01, 0.035, d * 1.01), base + Vector3(0.0, h * 0.80, 0.0), glow, yaw, false)
	_mb(root, Vector3(w * 1.01, 0.022, d * 1.01), base + Vector3(0.0, h * 0.18, 0.0), glow, yaw, false)
	for s in [-1.0, 1.0]:
		_mb(root, Vector3(0.025, h * 0.55, 0.02), base + Vector3(s * w * 0.42, h * 0.48, d * 0.5),
			glow, yaw, false)


## 塑料周转箱：箱体 + 开口
static func _crate(root: Node3D, base: Vector3, yaw: float, w: float, h: float, d: float,
		mat: Material, dark: Material) -> void:
	_mb(root, Vector3(w, h, d), base + Vector3(0.0, h * 0.5, 0.0), mat, yaw)
	_mb(root, Vector3(w - 0.11, 0.025, d - 0.11), base + Vector3(0.0, h - 0.012, 0.0), dark, yaw, false)


static func floor_cargo_spots() -> Array:
	return [Vector3(-10.6, 0.0, -10.0), Vector3(9.4, 0.0, 10.4), Vector3(-14.4, 0.0, 10.1)]


static func _racks(root: Node3D) -> void:
	var frame := Kit.std(Color(0.075, 0.085, 0.105), 0.42, 0.75)
	var frame_lt := Kit.std(Color(0.15, 0.17, 0.21), 0.40, 0.70)
	var beam := Kit.std(Color(0.11, 0.12, 0.15), 0.50, 0.50)
	var deck := Kit.std(Color(0.10, 0.11, 0.135), 0.55, 0.45)
	var clip := Kit.emissive(Color(1.0, 0.60, 0.10), 1.0)
	var plate := Kit.std(Color(0.045, 0.050, 0.060), 0.5, 0.5)
	var steel := Kit.std(Color(0.16, 0.18, 0.22), 0.35, 0.85)
	var led := Kit.emissive(Color(0.22, 0.82, 1.0), 1.9)
	var led_m := Kit.emissive(Color(1.0, 0.18, 0.58), 1.25)

	var wood := Kit.std(Color(0.37, 0.28, 0.17), 0.88, 0.0, {"noise": 2.2, "grime": 0.30, "bump": 0.8, "tint": 0.14, "streak": 0.12, "dirt": Color(0.08, 0.06, 0.04)})
	var wood_dk := Kit.std(Color(0.25, 0.18, 0.10), 0.92, 0.0, {"noise": 2.2, "grime": 0.30, "bump": 0.8, "tint": 0.14, "streak": 0.12, "dirt": Color(0.08, 0.06, 0.04)})
	var kraft := Kit.std(Color(0.39, 0.30, 0.19), 0.92, 0.0, {"noise": 3.4, "grime": 0.16, "bump": 1.0, "tint": 0.18, "dirt": Color(0.14, 0.10, 0.07)})
	var kraft_lt := Kit.std(Color(0.50, 0.41, 0.28), 0.90, 0.0, {"noise": 3.4, "grime": 0.16, "bump": 1.0, "tint": 0.18, "dirt": Color(0.14, 0.10, 0.07)})
	var white := Kit.std(Color(0.58, 0.57, 0.53), 0.85, 0.0, {"noise": 3.4, "grime": 0.16, "bump": 1.0, "tint": 0.18, "dirt": Color(0.14, 0.10, 0.07)})
	var tape := Kit.std(Color(0.74, 0.68, 0.50), 0.70, 0.0)
	var lab := Kit.std(Color(0.88, 0.86, 0.78), 0.70, 0.0)
	var blue := Kit.std(Color(0.10, 0.23, 0.40), 0.60, 0.0)
	var grey_c := Kit.std(Color(0.27, 0.28, 0.30), 0.60, 0.0)
	var wrap := Kit.glass(Color(0.58, 0.62, 0.64, 0.24), 0.5)

	var rows: Array = [-12.0, -8.0, 8.0, 12.0]
	var levels: Array = [2.2, 4.4, 6.6]
	var bay := 2.5
	var n_bays := 16

	for zi in rows.size():
		var z: float = rows[zi]
		# 立柱（主柱 + 朝通道的亮面）
		for i in n_bays + 1:
			var x := -20.0 + float(i) * bay
			for s in [-0.68, 0.68]:
				_mb(root, Vector3(0.16, 8.0, 0.16), Vector3(x, 4.0, z + s), frame)
				_mb(root, Vector3(0.035, 7.86, 0.10), Vector3(x - 0.098, 4.0, z + s), frame_lt)
				# 柱脚底板 + 地脚螺栓
				_mb(root, Vector3(0.34, 0.025, 0.34), Vector3(x, 0.015, z + s), steel, 0.0, false)
				_mb(root, Vector3(0.10, 0.06, 0.10), Vector3(x, 0.03, z + s), _ink(), 0.0, false)
			# 两端 X 形斜撑（只做端榀，不挡视线）
			if i == 0 or i == n_bays:
				var sx := 1.0 if i == 0 else -1.0
				for lv in 3:
					var y0: float = 0.25 + float(lv) * 2.2
					Kit.tube(root, Vector3(x, y0, z + 0.68) * U,
						Vector3(x + sx * 2.3, y0 + 2.0, z + 0.68) * U, 0.05 * U, frame_lt)
					Kit.tube(root, Vector3(x + sx * 2.3, y0, z + 0.68) * U,
						Vector3(x, y0 + 2.0, z + 0.68) * U, 0.05 * U, frame_lt)

		# 横梁 + 层板 + 梁端安全销
		for y in [2.2, 4.4, 6.6, 7.9]:
			for s in [-0.68, 0.68]:
				_mb(root, Vector3(40.3, 0.14, 0.13), Vector3(0.0, y, z + s), beam)
			if y < 7.0:
				_mb(root, Vector3(40.0, 0.05, 1.50), Vector3(0.0, y + 0.02, z), deck)
				# 层板前挡边（两侧通道各一条）
				for s2 in [-1.0, 1.0]:
					_mb(root, Vector3(40.0, 0.12, 0.035), Vector3(0.0, y + 0.03, z + s2 * 0.755),
						frame_lt, 0.0, false)
					# 挡边上沿的冷光灯带（湿地面会反出长条）
					_mb(root, Vector3(39.9, 0.020, 0.014), Vector3(0.0, y + 0.078, z + s2 * 0.777),
						led_m if zi == 3 else led, 0.0, false)
				for zz in [-0.42, 0.0, 0.42]:
					_mb(root, Vector3(39.8, 0.006, 0.03), Vector3(0.0, y + 0.048, z + zz),
						frame, 0.0, false)
			for ex in [-20.0, 20.0]:
				for s in [-0.68, 0.68]:
					_mb(root, Vector3(0.20, 0.26, 0.19), Vector3(ex, y, z + s), clip, 0.0, false)

		# 每层货物：托盘 / 纸箱 / 周转箱 / 缠绕膜 / 空位
		for i in n_bays:
			var cx := -20.0 + bay * (float(i) + 0.5)
			for li in levels.size():
				var y: float = float(levels[li]) + 0.05
				var hv := _hash(zi, i, li)
				# 不完美对齐：角度、左右、前后都留随机量（仓库里没人拿尺子摆货）
				var yaw := float(hv % 13 - 6) * 0.017
				var jx := float((hv / 13) % 7 - 3) * 0.055
				var jz := float((hv / 91) % 5 - 2) * 0.045
				var tilt := float((hv / 7) % 3 - 1) * 0.012
				var b := Vector3(cx + jx, y, z + jz)
				var kind := hv % 12
				if kind < 4:
					# 双箱托盘
					_pallet(root, b, yaw, wood, wood_dk)
					_carton(root, b + Vector3(-0.30, 0.126, 0.0), yaw + 0.02, 0.58, 0.52, 0.86,
						kraft, tape, lab)
					_carton(root, b + Vector3(0.30, 0.126, 0.02), yaw - 0.03, 0.58, 0.46, 0.80,
						kraft_lt, tape, null, tilt)
				elif kind < 6:
					# 大箱 + 两小箱
					_pallet(root, b, yaw, wood_dk, wood_dk)
					_carton(root, b + Vector3(0.0, 0.126, 0.0), yaw, 1.02, 0.50, 0.86, kraft, tape, lab)
					_carton(root, b + Vector3(-0.26, 0.626, 0.0), yaw + 0.05, 0.48, 0.40, 0.62,
						white, tape, null, tilt)
					_carton(root, b + Vector3(0.26, 0.626, 0.0), yaw - 0.04, 0.48, 0.36, 0.58,
						kraft_lt, tape, null, -tilt)
				elif kind < 8:
					# 直接码放在层板上
					var hh := 0.0
					for k in 2:
						var h := 0.42 + 0.06 * float(k)
						_carton(root, b + Vector3(float(k) * 0.05 - 0.02, hh, 0.0),
							yaw + 0.10 * float(k), 0.80, h, 0.74,
							kraft if k == 0 else kraft_lt, tape, lab if k == 0 else null)
						hh += h
				elif kind < 10:
					# 塑料周转箱
					for k in 3:
						_crate(root, b + Vector3(0.0, float(k) * 0.30, 0.0), yaw,
							0.64, 0.30, 0.54, blue if k % 2 == 0 else grey_c, frame)
				elif kind < 11:
					# 缠绕膜托盘
					_pallet(root, b, yaw, wood_dk, wood_dk)
					_mb(root, Vector3(1.02, 0.92, 0.86), b + Vector3(0.0, 0.56, 0.0), kraft, yaw, false)
					_mb(root, Vector3(1.07, 0.96, 0.91), b + Vector3(0.0, 0.56, 0.0), wrap, yaw, false)
				elif hv % 2 == 0:
					# 企业货箱：深色箱体 + 冷光边条
					_corp_crate(root, b, yaw, 1.10, 0.68, 0.88, hv)
				else:
					# 空位：只留一张托盘
					if hv % 3 == 0:
						_pallet(root, b, yaw, wood_dk, wood_dk)

		# 封顶：顶板铺在立柱上（顶面 8.0 m），可以在上面跑
		_mb(root, Vector3(40.2, 0.08, 1.42), Vector3(0.0, 7.96, z), deck, 0.0, false)
		for zz2 in [-0.62, 0.0, 0.62]:
			_mb(root, Vector3(40.0, 0.012, 0.05), Vector3(0.0, 8.012, z + zz2), frame, 0.0, false)

		# 排端标牌（两面）
		for sx in [-1.0, 1.0]:
			var ex: float = float(sx) * 20.16
			_mb(root, Vector3(0.045, 0.66, 1.28), Vector3(ex - float(sx) * 0.02, 7.15, z), plate)
			_mb(root, Vector3(0.05, 0.58, 1.20), Vector3(ex, 7.15, z),
				Kit.emissive(Color(0.06, 0.34, 0.46), 0.7))
			_mb(root, Vector3(0.045, 6.60, 0.045), Vector3(ex - float(sx) * 0.22, 3.70, z),
				led_m, 0.0, false)
			var tl := Label3D.new()
			tl.text = "A-%02d" % (zi + 1)
			tl.font_size = 96
			tl.pixel_size = 0.0042
			tl.modulate = Color(0.92, 0.99, 1.0)
			tl.position = Vector3(ex + sx * 0.04, 7.15, z) * U
			tl.rotation_degrees = Vector3(0.0, 90.0 * sx, 0.0)
			tl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			root.add_child(tl)

	# 通道吊牌
	for z2 in [-10.0, 10.0]:
		for x2 in [-11.0, 11.0]:
			_mb(root, Vector3(0.04, 0.60, 2.10), Vector3(x2, 8.55, z2),
				Kit.emissive(Color(0.06, 0.36, 0.48), 0.7))
			for dz in [-0.80, 0.80]:
				_mb(root, Vector3(0.04, 0.80, 0.04), Vector3(x2, 9.25, z2 + dz), steel, 0.0, false)
			var sl := Label3D.new()
			sl.text = "AISLE %s" % ("A" if z2 < 0.0 else "B")
			sl.font_size = 96
			sl.pixel_size = 0.0040
			sl.modulate = Color(0.92, 0.99, 1.0)
			sl.position = Vector3(x2, 8.55, z2) * U
			sl.rotation_degrees = Vector3(0.0, 90.0 * (1.0 if x2 > 0.0 else -1.0), 0.0)
			sl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			root.add_child(sl)

	# 通道地面的备货：托盘货 / 空托盘摞 / 周转箱
	var s0: Vector3 = floor_cargo_spots()[0]
	_pallet(root, s0, 0.04, wood, wood_dk)
	_carton(root, s0 + Vector3(-0.28, 0.126, 0.0), 0.06, 0.56, 0.46, 0.82, kraft, tape, lab)
	_carton(root, s0 + Vector3(0.29, 0.126, -0.02), -0.02, 0.56, 0.42, 0.78, kraft_lt, tape, null)

	var s1: Vector3 = floor_cargo_spots()[1]
	for i in 4:
		_pallet(root, s1 + Vector3(0.0, 0.128 * float(i), 0.0), 0.0, wood_dk, wood_dk)

	var s2: Vector3 = floor_cargo_spots()[2]
	for k in 3:
		_crate(root, s2 + Vector3(0.0, float(k) * 0.30, 0.0), 0.0,
			0.64, 0.30, 0.54, blue if k % 2 == 0 else grey_c, frame)

	# 叉车
	var orange := Kit.std(Color(0.62, 0.30, 0.05), 0.55, 0.22)
	var dark := Kit.std(Color(0.11, 0.12, 0.13), 0.5, 0.4)
	var rubber := Kit.std(Color(0.04, 0.04, 0.045), 0.9, 0.0)
	var fk := Vector3(12.4, 0.0, 14.1)

	# 车身：主箱 + 后部斜罩（绕 Z 轴倾角，去掉纯直角）
	_mb(root, Vector3(1.80, 0.50, 1.32), fk + Vector3(-0.05, 0.56, 0.0), orange)
	Kit.box(root, Vector3(0.62, 0.46, 1.30) * U, (fk + Vector3(-1.02, 0.74, 0.0)) * U, orange,
		Vector3(0.0, 0.0, -0.36))
	# 配重（后部圆肩）
	_mb(root, Vector3(0.42, 0.72, 1.26), fk + Vector3(-1.36, 0.50, 0.0), dark)
	Kit.cylinder(root, 0.45 * U, 1.24 * U, (fk + Vector3(-1.42, 0.92, 0.0)) * U, dark,
		Vector3(PI * 0.5, 0.0, 0.0))
	# 挡泥板
	for sx in [-0.80, 0.80]:
		for sz in [-0.60, 0.60]:
			Kit.box(root, Vector3(0.86, 0.07, 0.30) * U,
				(fk + Vector3(sx, 0.73, sz)) * U, dark,
				Vector3(0.0, 0.0, 0.0 if sx < 0.0 else 0.0))
	# 座椅 / 靠背 / 方向盘 / 踏板
	_mb(root, Vector3(0.52, 0.12, 0.52), fk + Vector3(-0.34, 1.26, 0.0), dark)
	Kit.box(root, Vector3(0.50, 0.52, 0.10) * U, (fk + Vector3(-0.62, 1.50, 0.0)) * U, dark,
		Vector3(0.0, 0.0, -0.22))
	Kit.torus(root, 0.15 * U, 0.022 * U, (fk + Vector3(-0.06, 1.52, 0.0)) * U, steel)
	Kit.tube(root, (fk + Vector3(-0.06, 1.28, 0.0)) * U, (fk + Vector3(-0.06, 1.52, 0.0)) * U,
		0.035 * U, steel)
	# 护顶架：四根斜柱 + 顶棚（前檐上翘）
	for sx in [-0.44, 0.44]:
		for sz in [-0.54, 0.54]:
			Kit.tube(root, (fk + Vector3(sx, 1.30, sz)) * U, (fk + Vector3(sx * 0.86, 2.34, sz * 0.9)) * U,
				0.045 * U, dark)
	Kit.box(root, Vector3(1.02, 0.06, 1.20) * U, (fk + Vector3(0.0, 2.38, 0.0)) * U, dark,
		Vector3(0.0, 0.0, -0.06))
	# 顶部警示灯
	Kit.cylinder(root, 0.06 * U, 0.12 * U, (fk + Vector3(-0.30, 2.48, 0.0)) * U,
		Kit.emissive(Color(1.0, 0.55, 0.10), 1.6))
	# 门架 / 货叉 / 液压缸 / 链条
	for sz in [-0.42, 0.42]:
		_mb(root, Vector3(0.13, 3.05, 0.11), fk + Vector3(0.95, 1.58, sz), steel)
		_mb(root, Vector3(0.24, 0.09, 0.09), fk + Vector3(0.95, 3.12, sz), steel)
		Kit.tube(root, (fk + Vector3(0.95, 0.30, sz)) * U, (fk + Vector3(0.95, 3.05, sz)) * U,
			0.018 * U, steel)
	_mb(root, Vector3(0.09, 0.50, 1.02), fk + Vector3(1.04, 0.72, 0.0), steel)
	for sz in [-0.34, 0.34]:
		# 货叉：竖直叉跟 + 水平叉身 + 上翘叉尖
		_mb(root, Vector3(0.10, 0.34, 0.13), fk + Vector3(1.14, 0.34, sz), steel)
		_mb(root, Vector3(1.16, 0.055, 0.13), fk + Vector3(1.70, 0.26, sz), steel)
		Kit.box(root, Vector3(0.26, 0.055, 0.13) * U, (fk + Vector3(2.36, 0.28, sz)) * U, steel,
			Vector3(0.0, 0.0, 0.14))
		Kit.cylinder(root, 0.055 * U, 1.24 * U, (fk + Vector3(0.82, 1.16, sz * 0.55)) * U, steel)
	for sx in [-0.80, 0.80]:
		for sz in [-0.60, 0.60]:
			var wheel := Kit.cylinder(root, 0.34 * U, 0.26 * U, (fk + Vector3(sx, 0.34, sz)) * U, rubber)
			wheel.basis = Basis(Vector3.RIGHT, PI * 0.5)


# ------------------------------------------------------------------ 装卸门
static func _dock(root: Node3D) -> void:
	var door := Kit.std(Color(0.17, 0.18, 0.19), 0.55, 0.45)
	var dark := Kit.std(Color(0.06, 0.065, 0.07), 0.6, 0.3)
	var yellow := Kit.emissive(Color(0.95, 0.62, 0.08), 0.5)

	var neon_c := Kit.emissive(Color(0.22, 0.82, 1.0), 2.0)
	var neon_m := Kit.emissive(Color(1.0, 0.18, 0.58), 1.8)
	var lamp_steel := Kit.std(Color(0.10, 0.11, 0.13), 0.45, 0.7)
	for xi in 3:
		var x: float = [-16.0, 0.0, 16.0][xi]
		# 卷帘门（关着，可见实体）
		Kit.box(root, S(5.0, 5.0, 0.18), P(x, 2.5, HALF_Z - 0.22), door)
		for k in 12:
			Kit.box(root, S(4.9, 0.06, 0.04), P(x, 0.3 + float(k) * 0.4, HALF_Z - 0.33), dark)
		# 门框 + 防撞胶
		for s in [-2.6, 2.6]:
			Kit.box(root, S(0.22, 5.2, 0.30), P(x + s, 2.6, HALF_Z - 0.10), dark)
		Kit.box(root, S(5.4, 0.22, 0.30), P(x, 5.15, HALF_Z - 0.10), dark)
		for s in [-2.2, 2.2]:
			Kit.box(root, S(0.5, 0.8, 0.4), P(x + s, 0.55, HALF_Z - 0.45), Kit.std(Color(0.08, 0.08, 0.09), 0.8))
		Kit.box(root, S(5.2, 0.012, 0.9), P(x, 0.012, HALF_Z - 1.2), yellow)
		# 门楣霓虹 + DOCK 灯箱
		Kit.box(root, S(4.9, 0.09, 0.10), P(x, 5.34, HALF_Z - 0.22), neon_c if xi != 1 else neon_m)
		Kit.box(root, S(3.2, 0.34, 0.12), P(x, 5.80, HALF_Z - 0.24), lamp_steel)
		Kit.box(root, S(3.05, 0.24, 0.04), P(x, 5.80, HALF_Z - 0.30),
			Kit.emissive(Color(0.08, 0.40, 0.55), 0.9))
		var dl := Label3D.new()
		dl.text = "DOCK 0%d" % (xi + 1)
		dl.font_size = 96
		dl.pixel_size = 0.0052
		dl.modulate = Color(0.90, 0.99, 1.0)
		dl.position = P(x, 5.80, HALF_Z - 0.33)
		dl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		dl.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		root.add_child(dl)

	# 装卸平台边沿与警示
	Kit.box(root, S(56.0, 0.10, 2.2), P(0.0, 0.05, HALF_Z - 1.6), Kit.std(Color(0.12, 0.13, 0.14), 0.7))
	for x in [-20.0, -8.0, 4.0, 16.0]:
		Kit.box(root, S(0.9, 0.012, 1.4), P(x, 0.02, 14.6), yellow)
	# 待发运托盘货
	var wood := Kit.std(Color(0.37, 0.28, 0.17), 0.88, 0.0, {"noise": 2.2, "grime": 0.30, "bump": 0.8, "tint": 0.14, "streak": 0.12, "dirt": Color(0.08, 0.06, 0.04)})
	var wood_dk := Kit.std(Color(0.25, 0.18, 0.10), 0.92, 0.0, {"noise": 2.2, "grime": 0.30, "bump": 0.8, "tint": 0.14, "streak": 0.12, "dirt": Color(0.08, 0.06, 0.04)})
	var kraft := Kit.std(Color(0.39, 0.30, 0.19), 0.92, 0.0, {"noise": 3.4, "grime": 0.16, "bump": 1.0, "tint": 0.18, "dirt": Color(0.14, 0.10, 0.07)})
	var kraft_lt := Kit.std(Color(0.50, 0.41, 0.28), 0.90, 0.0, {"noise": 3.4, "grime": 0.16, "bump": 1.0, "tint": 0.18, "dirt": Color(0.14, 0.10, 0.07)})
	var tape := Kit.std(Color(0.74, 0.68, 0.50), 0.70, 0.0)
	var lab := Kit.std(Color(0.88, 0.86, 0.78), 0.70, 0.0)
	var wrap := Kit.glass(Color(0.58, 0.62, 0.64, 0.24), 0.5)
	for spec in [[-7.0, 14.0, 0.0], [-6.2, 12.8, 0.06], [20.0, 13.6, -0.04]]:
		var bx: float = spec[0]
		var bz: float = spec[1]
		var yw: float = spec[2]
		_pallet(root, Vector3(bx, 0.0, bz), yw, wood, wood_dk)
		if spec[0] > 10.0:
			_mb(root, Vector3(1.02, 0.92, 0.86), Vector3(bx, 0.58, bz), kraft, yw, false)
			_mb(root, Vector3(1.07, 0.96, 0.91), Vector3(bx, 0.58, bz), wrap, yw, false)
		else:
			_carton(root, Vector3(bx - 0.28, 0.126, bz), yw, 0.56, 0.50, 0.84, kraft, tape, lab)
			_carton(root, Vector3(bx + 0.29, 0.126, bz + 0.02), yw, 0.56, 0.44, 0.80, kraft_lt, tape, null)


# ------------------------------------------------------------------ 办公室
static func _office(root: Node3D) -> void:
	var glass := Kit.glass(Color(0.12, 0.20, 0.22), 0.20)
	var frame := Kit.std(Color(0.09, 0.10, 0.12), 0.45, 0.70)
	var panel := Kit.std(Color(0.16, 0.17, 0.20), 0.55, 0.30)
	var desk := Kit.std(Color(0.13, 0.14, 0.16), 0.60, 0.30)
	var lamp := Kit.emissive(Color(0.78, 0.93, 1.0), 2.0)
	var red := Kit.emissive(Color(1.0, 0.15, 0.10), 2.0)

	# 地面层玻璃办公室（原来架在 4.5 m，会顶到二层环廊，降到地面）
	var x0 := OFF_X0
	var x1 := OFF_X1
	var z0 := OFF_Z0
	var z1 := OFF_Z1
	var oh := OFF_H
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5

	# 前墙玻璃 + 2.2 m 门洞（-25.9 ~ -23.7），滑门收到左侧
	for spec in [[-26.7, 1.6], [-22.1, 3.2]]:
		var g := Kit.box(root, S(float(spec[1]), oh - 0.20, 0.06),
			P(float(spec[0]), (oh - 0.20) * 0.5, z1), glass)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.box(root, S(1.10, oh - 0.60, 0.06), P(-26.35, (oh - 0.60) * 0.5, z1 + 0.13), panel)
	Kit.box(root, S(0.10, 0.28, 0.04), P(-23.45, 1.35, z1 + 0.08),
		Kit.emissive(Color(0.25, 1.0, 0.55), 1.6))
	for x in [x0, -25.9, -23.7, x1]:
		Kit.box(root, S(0.14, oh, 0.14), P(x, oh * 0.5, z1), frame)
	Kit.box(root, S(x1 - x0 + 0.3, 0.12, 0.16), P(cx, oh - 0.06, z1), frame)

	# 东侧实墙 + 屋顶（半安全屋：屋顶挡住上方的远程怪）
	Kit.box(root, S(0.12, oh, z1 - z0), P(x1, oh * 0.5, cz), panel)
	Kit.box(root, S(x1 - x0 + 0.3, 0.14, z1 - z0 + 0.3), P(cx, oh + 0.07, cz), frame)
	for i in 2:
		Kit.box(root, S(3.2, 0.04, 0.44), P(x0 + 2.1 + float(i) * 3.4, oh - 0.05, cz), lamp)

	# 地台 / 工位 / 屏幕 / 椅子
	Kit.box(root, S(x1 - x0, 0.02, z1 - z0), P(cx, 0.012, cz), Kit.std(Color(0.06, 0.07, 0.08), 0.7))
	for i in 2:
		var dx := -26.3 + float(i) * 2.7
		Kit.box(root, S(1.80, 0.08, 0.75), P(dx, 0.76, -14.2), desk)
		for s in [-0.80, 0.80]:
			Kit.box(root, S(0.06, 0.76, 0.06), P(dx + s, 0.38, -14.2), desk)
		Kit.box(root, S(0.64, 0.40, 0.05), P(dx, 1.04, -14.60), frame)
		Kit.box(root, S(0.56, 0.33, 0.02), P(dx, 1.04, -14.64),
			Kit.emissive(Color(0.14, 0.44, 0.60), 0.7))
		Kit.box(root, S(0.52, 0.07, 0.50), P(dx, 0.46, -13.30), desk)
		Kit.box(root, S(0.52, 0.42, 0.07), P(dx, 0.68, -13.05), desk)


# ------------------------------------------------------------------ 二层环廊
## 只沿四边一圈的夹层（内圈空着）。唯一的上法是从东侧的货柜跑酷上去。
static func _ring(root: Node3D) -> void:
	var deck := Kit.std(Color(0.125, 0.135, 0.155), 0.55, 0.50)
	var frame := Kit.std(Color(0.09, 0.10, 0.12), 0.45, 0.70)
	var rail := Kit.std(Color(0.13, 0.15, 0.18), 0.40, 0.80)
	var led := Kit.emissive(Color(0.22, 0.82, 1.0), 1.7)
	var hazard := Kit.emissive(Color(1.0, 0.62, 0.10), 0.8)
	var cy := RING_TOP - RING_T * 0.5

	# 甲板：南北整条，东西夹在中间（避免角上重叠）
	for spec in [[Vector3(0.0, cy, -HALF_Z + RING_W * 0.5), Vector3(HALF_X * 2.0, RING_T, RING_W)],
			[Vector3(0.0, cy, HALF_Z - RING_W * 0.5), Vector3(HALF_X * 2.0, RING_T, RING_W)],
			[Vector3(HALF_X - RING_W * 0.5, cy, 0.0),
				Vector3(RING_W, RING_T, HALF_Z * 2.0 - RING_W * 2.0)],
			[Vector3(-HALF_X + RING_W * 0.5, cy, 0.0),
				Vector3(RING_W, RING_T, HALF_Z * 2.0 - RING_W * 2.0)]]:
		_mb(root, spec[1], spec[0], deck)

	# 内沿封边 + 灯带
	var inz := HALF_Z - RING_W
	var inx := HALF_X - RING_W
	_mb(root, Vector3(inx * 2.0, 0.30, 0.06), Vector3(0.0, RING_TOP - 0.16, -inz), frame)
	_mb(root, Vector3(inx * 2.0, 0.30, 0.06), Vector3(0.0, RING_TOP - 0.16, inz), frame)
	_mb(root, Vector3(0.06, 0.30, inz * 2.0), Vector3(inx, RING_TOP - 0.16, 0.0), frame)
	_mb(root, Vector3(0.06, 0.30, inz * 2.0), Vector3(-inx, RING_TOP - 0.16, 0.0), frame)
	_mb(root, Vector3(inx * 2.0 - 0.1, 0.05, 0.03), Vector3(0.0, RING_TOP - 0.24, -inz - 0.04),
		led, 0.0, false)
	_mb(root, Vector3(inx * 2.0 - 0.1, 0.05, 0.03), Vector3(0.0, RING_TOP - 0.24, inz + 0.04),
		led, 0.0, false)
	_mb(root, Vector3(0.03, 0.05, inz * 2.0 - 0.1), Vector3(inx + 0.04, RING_TOP - 0.24, 0.0),
		led, 0.0, false)
	_mb(root, Vector3(0.03, 0.05, inz * 2.0 - 0.1), Vector3(-inx - 0.04, RING_TOP - 0.24, 0.0),
		led, 0.0, false)

	# 护栏：东侧在跑酷落脚处留一个开口（GATE_A~GATE_B）
	var rail_off := 0.10
	_rail(root, Vector3(-inx, 0.0, -inz + rail_off), Vector3(inx, 0.0, -inz + rail_off), rail, led)
	_rail(root, Vector3(-inx, 0.0, inz - rail_off), Vector3(inx, 0.0, inz - rail_off), rail, led)
	_rail(root, Vector3(-inx + rail_off, 0.0, -inz), Vector3(-inx + rail_off, 0.0, inz), rail, led)
	_rail(root, Vector3(inx - rail_off, 0.0, -inz), Vector3(inx - rail_off, 0.0, GATE_A), rail, led)
	_rail(root, Vector3(inx - rail_off, 0.0, GATE_B), Vector3(inx - rail_off, 0.0, inz), rail, led)
	# 开口两侧的加粗立柱 + 地面警示条
	for gz in [GATE_A, GATE_B]:
		_mb(root, Vector3(0.14, 1.30, 0.14), Vector3(inx - rail_off, RING_TOP + 0.65, gz), frame)
	_mb(root, Vector3(1.6, 0.012, 0.30), Vector3(inx + 0.55, RING_TOP + 0.012, (GATE_A + GATE_B) * 0.5),
		hazard, 0.0, false)

	# 贴墙斜撑（不再落地，避免在通道里立柱子）
	for x in [-24.5, -17.5, -10.5, -3.5, 3.5, 10.5, 17.5, 24.5]:
		_bracket(root, Vector3(x, 4.40, -HALF_Z + 0.12), Vector3(x, RING_TOP - 0.12, -inz + 0.10), frame)
		_bracket(root, Vector3(x, 4.40, HALF_Z - 0.12), Vector3(x, RING_TOP - 0.12, inz - 0.10), frame)
	for z in [-13.0, -6.5, 0.0, 6.5, 13.0]:
		_bracket(root, Vector3(-HALF_X + 0.12, 4.40, z), Vector3(-inx + 0.10, RING_TOP - 0.12, z), frame)
		_bracket(root, Vector3(HALF_X - 0.12, 4.40, z), Vector3(inx - 0.10, RING_TOP - 0.12, z), frame)


static func _rail(root: Node3D, a: Vector3, b: Vector3, mat: Material, led: Material) -> void:
	var d := b - a
	var n := maxi(1, int(d.length() / 2.6))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		_mb(root, Vector3(0.07, 1.12, 0.07), p + Vector3(0.0, RING_TOP + 0.56, 0.0), mat, 0.0, false)
	var mid := (a + b) * 0.5
	var horiz := absf(d.x) > absf(d.z)
	var top := Vector3(absf(d.x), 0.045, 0.045) if horiz else Vector3(0.045, 0.045, absf(d.z))
	var bar := Vector3(absf(d.x), 0.035, 0.035) if horiz else Vector3(0.035, 0.035, absf(d.z))
	_mb(root, top, mid + Vector3(0.0, RING_TOP + 1.12, 0.0), led, 0.0, false)
	_mb(root, bar, mid + Vector3(0.0, RING_TOP + 0.70, 0.0), mat, 0.0, false)


static func _bracket(root: Node3D, a: Vector3, b: Vector3, mat: Material) -> void:
	# a 贴墙，b 是甲板内沿下方；斜撑 + 贴墙竖杆 + 底托
	Kit.tube(root, a * U, b * U, 0.06 * U, mat)
	Kit.tube(root, Vector3(a.x, 3.30, a.z) * U, Vector3(a.x, b.y, a.z) * U, 0.07 * U, mat)
	Kit.tube(root, Vector3(a.x, b.y, a.z) * U, b * U, 0.05 * U, mat)


# ------------------------------------------------------------------ 跑酷货柜
## 东侧一列货柜，每级 +1.1 m、间隙 2.0 m；最后一级 5.5 m 直接跳上 6.4 m 环廊。
static func _parkour(root: Node3D) -> void:
	var hazard := Kit.emissive(Color(1.0, 0.62, 0.10), 0.75)

	for idx in PARKOUR.size():
		var spec: Dictionary = PARKOUR[idx]
		var c: Vector3 = spec["c"]
		var top: float = float(spec["top"])
		var hx: float = float(spec["hx"])
		var hz: float = float(spec["hz"])

		# 五个登高台阶，五种完全不同的箱子
		match idx:
			1: _crate_wood(root, c, top, hx, hz)
			2: _crate_wrapped(root, c, top, hx, hz)
			3: _crate_rust(root, c, top, hx, hz)
			4: _crate_plastic(root, c, top, hx, hz)
			_: _crate_steel(root, c, top, hx, hz, idx)

		# 顶面两侧警示条（站在上面能看清边界）
		for sz2 in [-1.0, 1.0]:
			_mb(root, Vector3(hx * 2.0 - 0.24, 0.012, 0.10),
				Vector3(c.x, top + 0.006, c.z + sz2 * (hz - 0.09)), hazard, 0.0, false)
		if idx == 0:
			_mb(root, Vector3(hx * 2.0, 0.012, 0.22), Vector3(c.x, 0.014, c.z - hz - 0.35),
				hazard, 0.0, false)


static func _crate_steel(root: Node3D, c: Vector3, top: float, hx: float, hz: float, idx: int) -> void:
	var body := Kit.std(Color(0.24, 0.25, 0.28), 0.60, 0.35)
	var rib := Kit.std(Color(0.095, 0.105, 0.125), 0.62, 0.50)
	var trim := Kit.std(Color(0.20, 0.21, 0.24), 0.45, 0.65)
	_mb(root, Vector3(hx * 2.0, top, hz * 2.0), c + Vector3(0.0, top * 0.5, 0.0), body)
	# 横向压筋 + 色带
	for s in [-1.0, 1.0]:
		for k in 3:
			var yy: float = top * (0.26 + 0.235 * float(k))
			_mb(root, Vector3(hx * 2.0 - 0.14, 0.10, 0.03),
				Vector3(c.x, yy, c.z + s * (hz + 0.016)), rib, 0.0, false)
		_mb(root, Vector3(hx * 2.0 - 0.30, 0.16, 0.02),
			Vector3(c.x, top * 0.70, c.z + s * (hz + 0.026)),
			Kit.emissive(Color(0.18, 0.62, 0.82), 0.55), 0.0, false)
	# 四角倒角
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mb(root, Vector3(0.13, top - 0.04, 0.13),
				c + Vector3(sx * (hx - 0.02), top * 0.5, sz * (hz - 0.02)), rib, PI * 0.25, false)
	# 门端
	var fx: float = c.x - hx - 0.012
	for yy2 in [top * 0.22, top * 0.78]:
		_mb(root, Vector3(0.03, 0.10, hz * 2.0 - 0.22), Vector3(fx, yy2, c.z), trim, 0.0, false)
	Kit.tube(root, Vector3(fx - 0.02, top * 0.24, c.z - 0.55) * U,
		Vector3(fx - 0.02, top * 0.76, c.z + 0.55) * U, 0.028 * U, trim)
	_mb(root, Vector3(0.04, 0.08, 0.44), Vector3(fx - 0.04, top * 0.50, c.z), trim, 0.0, false)
	_mb(root, Vector3(0.05, 0.06, hz * 2.0 - 0.30),
		Vector3(c.x - hx - 0.03, top - 0.17, c.z),
		Kit.emissive(Color(0.22, 0.82, 1.0), 1.5), 0.0, false)
	_parkour_cap(root, c, top, hx, hz, trim)
	_parkour_label(root, c, top, hx, hz, "TR-%02d" % (idx + 11), Color(0.60, 0.64, 0.68))


static func _crate_wood(root: Node3D, c: Vector3, top: float, hx: float, hz: float) -> void:
	var wood := Kit.std(Color(0.34, 0.24, 0.14), 0.92, 0.0,
		{"noise": 2.4, "grime": 0.30, "bump": 0.85, "streak": 0.10, "dirt": Color(0.09, 0.06, 0.04)})
	var dark := Kit.std(Color(0.20, 0.14, 0.08), 0.92, 0.0)
	_mb(root, Vector3(hx * 2.0, top, hz * 2.0), c + Vector3(0.0, top * 0.5, 0.0), wood)
	# 横向木板缝
	var boards := maxi(2, int(top / 0.55))
	for k in boards - 1:
		var yy: float = float(k + 1) * top / float(boards)
		_mb(root, Vector3(hx * 2.0 + 0.012, 0.022, hz * 2.0 + 0.012),
			Vector3(c.x, yy, c.z), dark, 0.0, false)
	# 四角立柱 + 上下包边
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mb(root, Vector3(0.12, top, 0.12),
				c + Vector3(sx * (hx - 0.05), top * 0.5, sz * (hz - 0.05)), dark, 0.0, false)
	_parkour_cap(root, c, top, hx, hz, dark)
	_parkour_label(root, c, top, hx, hz, "CARGO", Color(0.82, 0.78, 0.66))


static func _crate_wrapped(root: Node3D, c: Vector3, top: float, hx: float, hz: float) -> void:
	var card := Kit.std(Color(0.40, 0.33, 0.22), 0.92, 0.0,
		{"noise": 3.2, "grime": 0.16, "bump": 1.0, "tint": 0.18, "dirt": Color(0.14, 0.10, 0.07)})
	var wrap := Kit.glass(Color(0.66, 0.70, 0.72, 0.10), 0.45)
	wrap.roughness = 0.55
	wrap.metallic = 0.05
	var dark := Kit.std(Color(0.15, 0.14, 0.13), 0.8, 0.0)
	# 托盘底座
	_mb(root, Vector3(hx * 2.0, 0.12, hz * 2.0), c + Vector3(0.0, 0.06, 0.0), dark, 0.0, false)
	# 纸箱堆
	_mb(root, Vector3(hx * 2.0 - 0.10, top - 0.26, hz * 2.0 - 0.10),
		c + Vector3(0.0, 0.12 + (top - 0.26) * 0.5, 0.0), card)
	# 缠绕膜
	_mb(root, Vector3(hx * 2.0 - 0.03, top - 0.24, hz * 2.0 - 0.03),
		c + Vector3(0.0, 0.12 + (top - 0.24) * 0.5, 0.0), wrap, 0.0, false)
	# 打包带
	for sx in [-1.0, 1.0]:
		_mb(root, Vector3(0.07, top - 0.24, hz * 2.0 - 0.06),
			c + Vector3(sx * hx * 0.5, 0.12 + (top - 0.24) * 0.5, 0.0), dark, 0.0, false)
	_parkour_cap(root, c, top, hx, hz, dark)


static func _crate_rust(root: Node3D, c: Vector3, top: float, hx: float, hz: float) -> void:
	var body := Kit.std(Color(0.30, 0.15, 0.10), 0.85, 0.25,
		{"noise": 1.8, "grime": 0.55, "bump": 0.35, "tint": 0.26, "streak": 0.40,
		"dirt": Color(0.10, 0.05, 0.03)})
	var dark := Kit.std(Color(0.14, 0.10, 0.08), 0.9, 0.15)
	_mb(root, Vector3(hx * 2.0, top, hz * 2.0), c + Vector3(0.0, top * 0.5, 0.0), body)
	# 侧面检修口 + 爬梯（竖杆属于附件，不是“满面条纹”）
	_mb(root, Vector3(0.04, top * 0.22, hz * 0.5), Vector3(c.x - hx - 0.02, top * 0.34, c.z + hz * 0.3),
		dark, 0.0, false)
	var lx: float = c.x + hx + 0.03
	for sz in [-0.30, 0.30]:
		_mb(root, Vector3(0.05, top * 0.72, 0.05), Vector3(lx, top * 0.42, c.z + sz), dark, 0.0, false)
	for k in 5:
		var yy: float = top * (0.16 + 0.13 * float(k))
		_mb(root, Vector3(0.05, 0.05, 0.66), Vector3(lx, yy, c.z), dark, 0.0, false)
	# 锈迹斑块（深色不规则块）
	for k in 4:
		var px: float = c.x - hx + 0.35 + float(k) * (hx * 2.0 - 0.7) / 3.0
		_mb(root, Vector3(0.34, top * 0.16, 0.02),
			Vector3(px, top * (0.30 + 0.14 * float(k % 2)), c.z - hz - 0.012), dark, 0.0, false)
	_parkour_cap(root, c, top, hx, hz, dark)
	_parkour_label(root, c, top, hx, hz, "07", Color(0.70, 0.52, 0.36))


static func _crate_plastic(root: Node3D, c: Vector3, top: float, hx: float, hz: float) -> void:
	var shell := Kit.std(Color(0.52, 0.54, 0.55), 0.75, 0.05,
		{"noise": 1.4, "grime": 0.20, "bump": 0.25, "tint": 0.10})
	var dark := Kit.std(Color(0.16, 0.17, 0.18), 0.7, 0.1)
	_mb(root, Vector3(hx * 2.0, top, hz * 2.0), c + Vector3(0.0, top * 0.5, 0.0), shell)
	# 三段箱体（周转箱叠放）+ 每段上沿
	var rows := maxi(2, int(top / 0.62))
	for k in rows:
		var yy: float = float(k + 1) * top / float(rows)
		_mb(root, Vector3(hx * 2.0 + 0.03, 0.06, hz * 2.0 + 0.03),
			Vector3(c.x, yy - 0.03, c.z), dark, 0.0, false)
		# 通风槽
		for v in 4:
			var vx: float = c.x - hx + 0.28 + float(v) * (hx * 2.0 - 0.56) / 3.0
			_mb(root, Vector3(0.24, 0.05, 0.015),
				Vector3(vx, yy - top / float(rows) * 0.5, c.z - hz - 0.008), dark, 0.0, false)
	_parkour_cap(root, c, top, hx, hz, dark)
	_parkour_label(root, c, top, hx, hz, "PLASTIC", Color(0.20, 0.22, 0.24))


static func _parkour_cap(root: Node3D, c: Vector3, top: float, hx: float, hz: float, mat: Material) -> void:
	_mb(root, Vector3(hx * 2.0 + 0.05, 0.06, hz * 2.0 + 0.05),
		Vector3(c.x, top - 0.02, c.z), mat, 0.0, false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mb(root, Vector3(0.16, 0.22, 0.16),
				Vector3(c.x + sx * (hx - 0.10), top - 0.11, c.z + sz * (hz - 0.10)),
				mat, 0.0, false)


static func _parkour_label(root: Node3D, c: Vector3, top: float, hx: float, hz: float,
		text: String, col: Color) -> void:
	var cl := Label3D.new()
	cl.text = text
	cl.font_size = 96
	cl.pixel_size = 0.0055
	cl.modulate = col
	cl.position = (c + Vector3(-hx - 0.05, top * 0.62, 0.0)) * U
	cl.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	cl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	root.add_child(cl)


# ------------------------------------------------------------------ 道具
static func _props(root: Node3D) -> void:
	var barrel := Kit.std(Color(0.20, 0.11, 0.06), 0.55, 0.3)
	var barrel_blue := Kit.std(Color(0.08, 0.18, 0.30), 0.55, 0.3)
	var steel := Kit.std(Color(0.30, 0.31, 0.33), 0.4, 0.8)
	var grey := Kit.std(Color(0.19, 0.20, 0.21), 0.5, 0.45)
	var card := Kit.std(Color(0.36, 0.29, 0.19), 0.92, 0.0, {"noise": 3.4, "grime": 0.16, "bump": 1.0, "tint": 0.18, "dirt": Color(0.14, 0.10, 0.07)})
	var card_dk := Kit.std(Color(0.26, 0.20, 0.12), 0.92, 0.0, {"noise": 3.4, "grime": 0.16, "bump": 1.0, "tint": 0.18, "dirt": Color(0.14, 0.10, 0.07)})
	var wood := Kit.std(Color(0.37, 0.28, 0.17), 0.88, 0.0, {"noise": 2.2, "grime": 0.30, "bump": 0.8, "tint": 0.14, "streak": 0.12, "dirt": Color(0.08, 0.06, 0.04)})
	var wood_dk := Kit.std(Color(0.25, 0.18, 0.10), 0.92, 0.0, {"noise": 2.2, "grime": 0.30, "bump": 0.8, "tint": 0.14, "streak": 0.12, "dirt": Color(0.08, 0.06, 0.04)})
	var orange := Kit.std(Color(0.58, 0.31, 0.06), 0.55, 0.2)
	var red := Kit.std(Color(0.52, 0.08, 0.06), 0.45, 0.1)

	# 油桶：桶身 + 两道箍 + 顶盖 + 桶塞
	for i in 6:
		var bx := -9.0 + float(i) * 0.8
		var m: Material = barrel_blue if i % 2 == 0 else barrel
		Kit.cylinder(root, 0.32 * U, 0.88 * U, P(bx, 0.44, -15.5), m)
		for ry in [0.26, 0.62]:
			Kit.cylinder(root, 0.335 * U, 0.045 * U, P(bx, ry, -15.5), grey)
		Kit.cylinder(root, 0.30 * U, 0.03 * U, P(bx, 0.885, -15.5), steel)
		Kit.cylinder(root, 0.05 * U, 0.045 * U, P(bx + 0.14, 0.895, -15.5), steel)

	# 纸板捆（压扁的瓦楞纸 + 打包带）
	for i in 3:
		var bx2 := 18.0 - float(i) * 1.2
		var yw := 0.05 * float(i)
		_mb(root, Vector3(1.05, 0.95, 0.90), Vector3(bx2, 0.475, -14.0), card, yw)
		for k in 6:
			_mb(root, Vector3(1.08, 0.028, 0.93), Vector3(bx2, 0.09 + float(k) * 0.152, -14.0),
				card_dk, yw, false)
		for sx2 in [-0.34, 0.34]:
			_mb(root, Vector3(0.045, 0.99, 0.95), Vector3(bx2 + sx2, 0.48, -14.0), steel, yw, false)

	# 剪叉升降台（顶面 1.35，可站立）
	var sl := Vector3(-9.0, 0.0, 4.0)
	_mb(root, Vector3(3.0, 0.26, 1.8), sl + Vector3(0.0, 0.15, 0.0), orange)
	for sx in [-1.30, 1.30]:
		for sz in [-0.78, 0.78]:
			_mb(root, Vector3(0.16, 0.22, 0.16), sl + Vector3(sx, 0.03, sz), grey)
	for sz in [-0.72, 0.72]:
		Kit.tube(root, (sl + Vector3(-1.12, 0.30, sz)) * U, (sl + Vector3(1.12, 1.14, sz)) * U,
			0.055 * U, steel)
		Kit.tube(root, (sl + Vector3(1.12, 0.30, sz)) * U, (sl + Vector3(-1.12, 1.14, sz)) * U,
			0.055 * U, steel)
	_mb(root, Vector3(2.90, 0.20, 1.70), sl + Vector3(0.0, 1.25, 0.0), steel)
	_mb(root, Vector3(2.86, 0.03, 1.66), sl + Vector3(0.0, 1.345, 0.0), grey, 0.0, false)
	# 液压缸 + 控制盒
	Kit.cylinder(root, 0.09 * U, 0.85 * U, (sl + Vector3(-0.55, 0.72, 0.0)) * U,
		Kit.std(Color(0.55, 0.52, 0.42), 0.4, 0.7))
	_mb(root, Vector3(0.30, 0.30, 0.18), sl + Vector3(1.35, 0.62, 0.0), grey, 0.0, false)

	# 大货箱（顶面 0.945，可站立）
	var bc := Vector3(6.0, 0.0, -14.0)
	_mb(root, Vector3(2.40, 0.90, 1.80), bc + Vector3(0.0, 0.45, 0.0), wood)
	for sx3 in [-1.19, 1.19]:
		_mb(root, Vector3(0.055, 0.86, 1.82), bc + Vector3(sx3, 0.44, 0.0), wood_dk, 0.0, false)
	for sz3 in [-0.89, 0.89]:
		_mb(root, Vector3(2.42, 0.86, 0.055), bc + Vector3(0.0, 0.44, sz3), wood_dk, 0.0, false)
	_mb(root, Vector3(2.46, 0.05, 1.86), bc + Vector3(0.0, 0.925, 0.0),
		Kit.std(Color(0.42, 0.32, 0.20), 0.8))
	# 正面喷字
	_mb(root, Vector3(0.95, 0.20, 0.02), bc + Vector3(0.0, 0.58, 0.915), _ink(), 0.0, false)
	_mb(root, Vector3(0.35, 0.12, 0.02), bc + Vector3(0.0, 0.36, 0.915), _ink(), 0.0, false)

	# 大件木箱（顶面 0.46，可站立）
	var pc := Vector3(5.0, 0.0, 2.0)
	_mb(root, Vector3(2.60, 0.40, 2.00), pc + Vector3(0.0, 0.22, 0.0), wood)
	for i in 6:
		var px := -1.0 + float(i) * 0.4
		_mb(root, Vector3(0.035, 0.40, 2.02), pc + Vector3(px, 0.22, 0.0), wood_dk, 0.0, false)
	for sx5 in [-1.26, 1.26]:
		for sz5 in [-0.96, 0.96]:
			_mb(root, Vector3(0.10, 0.46, 0.10), pc + Vector3(sx5, 0.23, sz5), wood_dk, 0.0, false)
			_mb(root, Vector3(0.14, 0.44, 0.14), pc + Vector3(sx5, 0.22, sz5), wood_dk, PI * 0.25, false)
	for sz6 in [-0.96, 0.96]:
		_mb(root, Vector3(2.62, 0.06, 0.07), pc + Vector3(0.0, 0.035, sz6), wood_dk, 0.0, false)
		_mb(root, Vector3(2.62, 0.06, 0.07), pc + Vector3(0.0, 0.40, sz6), wood_dk, 0.0, false)
	for sx6 in [-1.26, 1.26]:
		_mb(root, Vector3(0.07, 0.06, 2.02), pc + Vector3(sx6, 0.40, 0.0), wood_dk, 0.0, false)
	_mb(root, Vector3(2.66, 0.04, 2.06), pc + Vector3(0.0, 0.44, 0.0), wood, 0.0, false)
	# 侧面喷字
	_mb(root, Vector3(0.90, 0.18, 0.02), pc + Vector3(-0.35, 0.26, 1.015), _ink(), 0.0, false)
	_mb(root, Vector3(0.30, 0.10, 0.02), pc + Vector3(0.75, 0.26, 1.015), _ink(), 0.0, false)

	# 工具车：柜体 + 抽屉 + 脚轮 + 把手
	var tc := Vector3(-2.0, 0.0, -6.0)
	_mb(root, Vector3(1.00, 0.86, 0.60), tc + Vector3(0.0, 0.50, 0.0), grey)
	_mb(root, Vector3(1.02, 0.04, 0.62), tc + Vector3(0.0, 0.94, 0.0), steel, 0.0, false)
	for k in 3:
		var dy := 0.24 + float(k) * 0.24
		_mb(root, Vector3(0.90, 0.19, 0.03), tc + Vector3(0.0, dy, 0.315), steel, 0.0, false)
		_mb(root, Vector3(0.40, 0.03, 0.04), tc + Vector3(0.0, dy + 0.02, 0.34), _ink(), 0.0, false)
	for sx4 in [-0.38, 0.38]:
		for sz4 in [-0.20, 0.20]:
			Kit.cylinder(root, 0.07 * U, 0.05 * U, (tc + Vector3(sx4, 0.04, sz4)) * U, _ink())
	_mb(root, Vector3(0.05, 0.05, 0.55), tc + Vector3(-0.55, 0.98, 0.0), steel, 0.0, false)

	# 灭火器 + 托架
	Kit.cylinder(root, 0.15 * U, 0.60 * U, P(9.0, 0.32, 7.0), red)
	Kit.cylinder(root, 0.05 * U, 0.16 * U, P(9.0, 0.70, 7.0), grey)
	_mb(root, Vector3(0.36, 0.06, 0.36), Vector3(9.0, 0.03, 7.0), grey, 0.0, false)
	_mb(root, Vector3(0.30, 0.16, 0.02), Vector3(9.0, 0.46, 7.19), Kit.std(Color(0.72, 0.70, 0.64), 0.7), 0.0, false)

	# A 字告示牌
	var sg := Vector3(-2.0, 0.0, 7.0)
	_mb(root, Vector3(0.80, 0.60, 0.04), sg + Vector3(0.0, 0.62, 0.10), orange, 0.0)
	_mb(root, Vector3(0.80, 0.60, 0.04), sg + Vector3(0.0, 0.62, -0.10), orange, 0.0)
	_mb(root, Vector3(0.62, 0.42, 0.02), sg + Vector3(0.0, 0.63, 0.13), _ink(), 0.0, false)


# ------------------------------------------------------------------ 细节
static func _details(root: Node3D) -> void:
	var yellow := Kit.emissive(Color(0.95, 0.62, 0.08), 0.6)
	var black := Kit.std(Color(0.035, 0.035, 0.04), 0.8, 0.0)
	var rubber := Kit.std(Color(0.04, 0.04, 0.045), 0.85, 0.0)
	var steel := Kit.std(Color(0.25, 0.26, 0.28), 0.35, 0.85)
	var red := Kit.emissive(Color(1.0, 0.12, 0.08), 1.2)
	var white := Kit.std(Color(0.75, 0.75, 0.72), 0.5, 0.1)

	# 货架端部防撞护角 + 地面排号
	for zi in 4:
		var z: float = [-12.0, -8.0, 8.0, 12.0][zi]
		for x in [-20.1, 20.1]:
			for s2 in [-0.55, 0.55]:
				Kit.box(root, S(0.18, 1.3, 0.18), P(x, 0.65, z + s2), yellow)
			Kit.box(root, S(0.20, 0.12, 1.35), P(x, 1.25, z), yellow)
		var lab := Label3D.new()
		lab.text = "A-%02d" % (zi + 1)
		lab.font_size = 96
		lab.pixel_size = 0.006
		lab.modulate = Color(0.95, 0.72, 0.25)
		lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lab.position = P(-19.0, 0.03, z - 0.2)
		lab.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		root.add_child(lab)

	# 装卸门：门封、防撞胶、调平台、控制箱、门号
	for idx in 3:
		var x: float = [-16.0, 0.0, 16.0][idx]
		for s2 in [-1.0, 1.0]:
			Kit.box(root, S(0.18, 5.0, 0.20), P(x + s2 * 2.55, 2.5, HALF_Z - 0.36), rubber)
			Kit.box(root, S(0.55, 0.55, 0.55), P(x + s2 * 2.15, 0.55, HALF_Z - 0.55), rubber)
		Kit.box(root, S(5.1, 0.18, 0.20), P(x, 5.05, HALF_Z - 0.36), rubber)
		# 调平台钢板
		Kit.box(root, S(4.8, 0.06, 1.3), P(x, 0.06, HALF_Z - 1.9), steel)
		for k in 4:
			Kit.box(root, S(4.6, 0.015, 0.04), P(x, 0.10, HALF_Z - 2.4 + float(k) * 0.32), black)
		# 控制箱
		Kit.box(root, S(0.38, 0.55, 0.14), P(x + 3.15, 1.55, HALF_Z - 0.40), Kit.std(Color(0.16, 0.17, 0.18), 0.45, 0.5))
		Kit.box(root, S(0.06, 0.12, 0.02), P(x + 3.15, 1.68, HALF_Z - 0.48), red)
		Kit.box(root, S(0.06, 0.12, 0.02), P(x + 3.15, 1.50, HALF_Z - 0.48), Kit.emissive(Color(0.30, 1.0, 0.45), 1.4))
		# 门号
		var dn := Label3D.new()
		dn.text = "0%d" % (idx + 1)
		dn.font_size = 96
		dn.pixel_size = 0.012
		dn.modulate = Color(0.70, 0.76, 0.80)
		dn.position = P(x, 3.1, HALF_Z - 0.34)
		dn.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		dn.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		root.add_child(dn)
		# 底部锈迹 / 水痕
		for s3 in [-2.2, 2.2]:
			Kit.box(root, S(0.55, 0.9, 0.02), P(x + s3, 0.45, HALF_Z - 0.33),
				Kit.std(Color(0.20, 0.10, 0.05), 0.95, 0.1))

		# 门号地贴
		var lab2 := Label3D.new()
		lab2.text = "DOCK %d" % (idx + 1)
		lab2.font_size = 96
		lab2.pixel_size = 0.007
		lab2.modulate = Color(0.95, 0.70, 0.20)
		lab2.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lab2.position = P(x, 0.03, HALF_Z - 1.0)
		lab2.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		root.add_child(lab2)

	# 办公室内部灯（否则玻璃盒子里看不到工位）
	var ol := OmniLight3D.new()
	ol.position = P(-24.0, 2.55, -14.0)
	ol.light_color = Color(0.82, 0.90, 1.0)
	ol.light_energy = 5.2
	ol.omni_range = 11.0 * U
	ol.omni_attenuation = 1.1
	root.add_child(ol)

	# 消防管 / 喷淋 / 桥架横档 / 通风口
	Kit.cylinder(root, 0.09 * U, 50.0 * U, P(0.0, H - 0.70, -4.0),
		Kit.std(Color(0.45, 0.10, 0.07), 0.45), Vector3(0.0, 0.0, PI * 0.5))
	for x in [-18.0, -9.0, 0.0, 9.0, 18.0]:
		Kit.cylinder(root, 0.04 * U, 0.45 * U, P(x, H - 0.95, -4.0), red)
	Kit.cylinder(root, 0.09 * U, 50.0 * U, P(0.0, H - 0.70, 4.0),
		Kit.std(Color(0.45, 0.10, 0.07), 0.45), Vector3(0.0, 0.0, PI * 0.5))
	for x in [-18.0, -9.0, 0.0, 9.0, 18.0]:
		Kit.cylinder(root, 0.04 * U, 0.45 * U, P(x, H - 0.95, 4.0), red)
	for z2 in [-6.0, 6.0]:
		for i in 18:
			Kit.box(root, S(0.05, 0.03, 0.45), P(-17.0 + float(i) * 2.0, H - 1.00, z2), steel)
	for x in [-10.0, 10.0]:
		Kit.box(root, S(1.4, 0.05, 0.9), P(x, H - 0.20, -14.0), Kit.std(Color(0.08, 0.08, 0.09), 0.6))
		for k in 5:
			Kit.box(root, S(1.2, 0.01, 0.03), P(x, H - 0.22, -14.3 + float(k) * 0.14), black)

	# 托盘千斤顶 / 锥桶 / 纸板捆
	Kit.box(root, S(1.4, 0.08, 0.18), P(2.0, 0.10, 6.0), steel)
	Kit.box(root, S(1.4, 0.08, 0.18), P(2.0, 0.10, 6.5), steel)
	Kit.box(root, S(0.12, 0.9, 0.12), P(2.6, 0.55, 6.25), steel, Vector3(0.0, 0.0, -0.5))
	for i in 4:
		Kit.cone(root, 0.11 * U, 0.55 * U, P(-12.0 + float(i) * 3.0, 0.28, 15.2),
			Kit.emissive(Color(1.0, 0.35, 0.05), 0.5))
	Kit.box(root, S(1.6, 1.0, 1.0), P(19.0, 0.5, 2.0), Kit.std(Color(0.30, 0.25, 0.18), 0.9))
	for i in 3:
		Kit.box(root, S(1.5, 0.02, 0.8), P(19.0, 0.06 + float(i) * 0.32, 2.0), black)

	# 北墙：人行门 + 出口牌（挂在外壳组里，随北墙一起隐藏）
	var north: Node3D = root.get_node("Shell/North")
	Kit.box(north, S(2.0, 2.5, 0.18), P(8.0, 1.25, -HALF_Z + 0.20), Kit.std(Color(0.10, 0.11, 0.13), 0.5, 0.5))
	Kit.box(north, S(2.2, 0.16, 0.22), P(8.0, 2.55, -HALF_Z + 0.20), steel)
	Kit.box(north, S(0.06, 0.35, 0.05), P(8.8, 1.2, -HALF_Z + 0.32), Kit.emissive(Color(0.25, 1.0, 0.55), 1.2))
	Kit.box(north, S(0.8, 0.25, 0.06), P(8.0, 2.9, -HALF_Z + 0.15), Kit.std(Color(0.03, 0.03, 0.035), 0.5))
	Kit.box(north, S(0.60, 0.08, 0.03), P(8.0, 2.9, -HALF_Z + 0.20), Kit.emissive(Color(0.25, 1.0, 0.45), 1.8))

	# 墙面灯箱广告：放在货架顶上方的空白墙带（8 m 以上才看得到）
	var cyan_box := Kit.emissive(Color(0.10, 0.46, 0.62), 0.55)
	var mag_box := Kit.emissive(Color(0.55, 0.08, 0.30), 0.55)
	for sx in [-1.0, 1.0]:
		var px: float = float(sx) * 9.0
		Kit.box(north, S(8.0, 1.5, 0.10), P(px, 9.70, -HALF_Z + 0.22),
			Kit.std(Color(0.03, 0.035, 0.04), 0.5, 0.6))
		Kit.box(north, S(7.6, 1.2, 0.05), P(px, 9.70, -HALF_Z + 0.29),
			mag_box if sx > 0.0 else cyan_box)
		var wl := Label3D.new()
		wl.text = "SECTOR 07" if sx < 0.0 else "WAREHOUSE 07"
		wl.font_size = 96
		wl.pixel_size = 0.0055
		wl.modulate = Color(0.95, 0.99, 1.0)
		wl.position = P(px, 9.70, -HALF_Z + 0.33)
		wl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		north.add_child(wl)

	# 东西墙各挂一块竖招牌
	for spec in [[-1.0, "DOCKING"], [1.0, "CARGO"]]:
		var sgn: float = float(spec[0])
		var grp: Node3D = root.get_node("Shell/West" if sgn < 0.0 else "Shell/East")
		var wx: float = -HALF_X + 0.22 if sgn < 0.0 else HALF_X - 0.22
		Kit.box(grp, S(0.10, 3.6, 2.4), P(wx, 7.4, 0.0), Kit.std(Color(0.03, 0.035, 0.04), 0.5, 0.6))
		Kit.box(grp, S(0.05, 3.2, 2.0), P(wx + sgn * 0.07, 7.4, 0.0), cyan_box if sgn < 0.0 else mag_box)
		var sl2 := Label3D.new()
		sl2.text = str(spec[1])
		sl2.font_size = 96
		sl2.pixel_size = 0.0055
		sl2.modulate = Color(0.95, 0.99, 1.0)
		sl2.position = P(wx + sgn * 0.11, 7.4, 0.0)
		sl2.rotation_degrees = Vector3(0.0, 90.0 * sgn * -1.0, 0.0)
		sl2.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		grp.add_child(sl2)

	# 监控摄像头（柱子上）
	for x in [-24.0, 24.0]:
		for z in [-6.0, 6.0]:
			var cdir := 1.0 if x < 0.0 else -1.0
			Kit.box(root, S(0.16, 0.16, 0.16), P(x + cdir * 0.34, 5.6, z), Kit.std(Color(0.05, 0.055, 0.065), 0.45, 0.6))
			Kit.box(root, S(0.30, 0.10, 0.13), P(x + cdir * 0.55, 5.5, z), Kit.std(Color(0.06, 0.065, 0.075), 0.4, 0.6),
				Vector3(0.0, 0.0, cdir * 0.35))
			Kit.box(root, S(0.03, 0.03, 0.03), P(x + cdir * 0.70, 5.46, z), Kit.emissive(Color(1.0, 0.15, 0.10), 2.0))

	# 屋面下垂电缆
	for i in 3:
		var cx := -18.0 + float(i) * 18.0
		Kit.cable(root, P(cx, H - 0.50, -16.0), P(cx, H - 0.50, 16.0), 0.55 * U, 0.03 * U, _ink(), 18)

	# 地面全息警示箭头
	for spec in [[-14.0, 0.0], [14.0, 0.0], [0.0, 12.0]]:
		var gx: float = spec[0]
		var gz: float = spec[1]
		for k in 3:
			Kit.box(root, S(1.2, 0.012, 0.20), P(gx, 0.014, gz + float(k) * 0.55 - 0.55),
				Kit.emissive(Color(1.0, 0.55, 0.10), 0.7), Vector3(0.0, 0.0, 0.0))


# ------------------------------------------------------------------ 灯光
static func _lights(root: Node3D) -> void:
	var steel := Kit.std(Color(0.13, 0.15, 0.18), 0.35, 0.85)
	var cyan := Color(0.66, 0.88, 1.0)

	# 高棚灯：冷白灯管 + 灯壳 + 吊杆
	for x in [-18.0, 0.0, 18.0]:
		for z in [-10.0, 10.0]:
			Kit.box(root, S(2.0, 0.14, 0.44), P(x, H - 0.95, z), Kit.std(Color(0.06, 0.07, 0.08), 0.5, 0.6))
			var lamp := Kit.box(root, S(1.78, 0.03, 0.30), P(x, H - 1.04, z), Kit.emissive(cyan, 2.4))
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for dz in [-0.52, 0.52]:
				Kit.box(root, S(0.035, 0.60, 0.035), P(x, H - 0.50, z + dz), steel)
			var l := OmniLight3D.new()
			l.position = P(x, H - 1.70, z)
			l.light_color = Color(0.72, 0.87, 1.0)
			l.light_energy = 7.2
			l.omni_range = 60.0 * U
			l.omni_attenuation = 0.7
			l.light_volumetric_fog_energy = 0.5
			l.shadow_enabled = false
			root.add_child(l)

	# 货架通道里的低位灯：高棚灯照不到 8 m 货架的下层
	for z in [-10.0, 10.0, -6.0, 6.0]:
		for x in [-12.0, 0.0, 12.0]:
			var w := OmniLight3D.new()
			w.position = P(x, 4.4, z)
			w.light_color = Color(0.86, 0.90, 1.0)
			w.light_energy = 2.4
			w.omni_range = 13.0 * U
			w.omni_attenuation = 1.0
			root.add_child(w)

	# 二层环廊照明：贴墙小灯，照亮甲板
	# 环廊灯挂在墙上、甲板上方 2.8 m（机体 2.5 m），不再横在走道正中
	for spec in [[Vector2(-14.0, -HALF_Z + 0.18), Vector2(0.0, 1.0)],
			[Vector2(14.0, -HALF_Z + 0.18), Vector2(0.0, 1.0)],
			[Vector2(-14.0, HALF_Z - 0.18), Vector2(0.0, -1.0)],
			[Vector2(14.0, HALF_Z - 0.18), Vector2(0.0, -1.0)],
			[Vector2(HALF_X - 0.18, -7.0), Vector2(-1.0, 0.0)],
			[Vector2(HALF_X - 0.18, 7.0), Vector2(-1.0, 0.0)],
			[Vector2(-HALF_X + 0.18, -7.0), Vector2(1.0, 0.0)],
			[Vector2(-HALF_X + 0.18, 7.0), Vector2(1.0, 0.0)]]:
		var lpos: Vector2 = spec[0]
		var ln: Vector2 = spec[1]
		var ly: float = RING_TOP + 2.80
		var along_x: bool = absf(ln.y) > 0.5
		var bx: float = 0.90 if along_x else 0.24
		var bz: float = 0.24 if along_x else 0.90
		Kit.box(root, S(bx, 0.08, bz), P(lpos.x, ly, lpos.y),
			Kit.std(Color(0.07, 0.08, 0.09), 0.5, 0.6))
		var lampf := Kit.box(root, S(bx - 0.16, 0.02, bz - 0.10),
			P(lpos.x, ly - 0.05, lpos.y), Kit.emissive(cyan, 2.2))
		lampf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lr := OmniLight3D.new()
		lr.position = P(lpos.x + ln.x * 0.40, ly - 0.60, lpos.y + ln.y * 0.40)
		lr.light_color = Color(0.80, 0.90, 1.0)
		lr.light_energy = 2.8
		lr.omni_range = 10.0 * U
		lr.omni_attenuation = 1.1
		root.add_child(lr)

	# 跑酷货柜：从屋面桁架吊两盏灯（不能悬在半空：站在 5.5 m 货柜上头顶到 9.5 m）
	for spec in [[21.5, 5.2], [21.5, -4.2]]:
		var px2: float = float(spec[0])
		var pz2: float = float(spec[1])
		var hang: float = 11.20
		Kit.tube(root, P(px2, H - 0.66, pz2), P(px2, hang + 0.10, pz2), 0.022 * U,
			Kit.std(Color(0.12, 0.13, 0.15), 0.5, 0.6))
		Kit.box(root, S(1.10, 0.12, 0.24), P(px2, hang, pz2),
			Kit.std(Color(0.07, 0.08, 0.09), 0.5, 0.6))
		var pf := Kit.box(root, S(0.94, 0.02, 0.16), P(px2, hang - 0.07, pz2),
			Kit.emissive(Color(0.74, 0.86, 1.0), 2.0))
		pf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pk := OmniLight3D.new()
		pk.position = P(px2, hang - 0.35, pz2)
		pk.light_color = Color(0.74, 0.86, 1.0)
		pk.light_energy = 4.2
		pk.omni_range = 15.0 * U
		pk.omni_attenuation = 1.0
		root.add_child(pk)

	# 货架通道端头：品红补光
	for z in [-10.0, 10.0]:
		for x in [-22.0, 22.0]:
			var m := OmniLight3D.new()
			m.position = P(x, 4.6, z)
			m.light_color = Color(1.0, 0.20, 0.62)
			m.light_energy = 3.2
			m.omni_range = 22.0 * U
			m.light_volumetric_fog_energy = 0.8
			root.add_child(m)

	# 装卸区：钠黄，和青色形成冷暖对比
	for x in [-16.0, 0.0, 16.0]:
		var l := OmniLight3D.new()
		l.position = P(x, 3.4, 15.0)
		l.light_color = Color(1.0, 0.62, 0.26)
		l.light_energy = 3.4
		l.omni_range = 26.0 * U
		l.omni_attenuation = 1.35
		l.light_volumetric_fog_energy = 0.9
		root.add_child(l)

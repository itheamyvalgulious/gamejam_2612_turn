extends RefCounted
## 暮色楼顶：楼顶跑酷空间样段。
##
## 目的：用第一视角验证「屋顶读不读得懂、跳得过去、落得下来」，不是最终美术，
## 也不含敌人 / Boss / 音效。
##
## 空间（全部真实米，交给 Kit 前乘 U）：
##   下层大屋面（起点，也是跌落回收面）y=18.0，102 × 60 m；
##   三座屋顶设备房 R1 y=21.6、R2 y=22.8、R3 y=21.6；
##   终点信标塔 F y=22.8，与 R3 隔 4 m。
##
## 路线：大屋面 → 货箱 / 集装箱 / 机组三段攀爬 → R1 → 跨 5 m → R2
##       → 跨 5 m → R3 → 跨 4 m → F。
## 屋面之间是 5 m 空隙，掉下去落在 y=18 的大屋面上，可以走回攀爬点重来。
##
## 碰撞约定（和船坞一致）：引擎不用网格碰撞，只认
##   cover   —— 竖直圆柱（侧面挡人，h 是柱高）
##   platforms —— 轴对齐矩形台面（只能站，不挡侧面）
## 所以每个可站实体都登记「一圈侧墙 + 一块台面」，且侧墙高度比台面低 0.3 m：
## 站在台面上时侧墙不再推人，走上台面边缘会自然掉下去（跑酷要能掉）。

const Kit := preload("res://src/arena/kit.gd")
const U := 1.0 / 0.547
const BALL := 1.2

# ---------------- 高度（米） ----------------
const DECK_Y := 18.0
const R1_Y := 21.6
const R2_Y := 22.4
const R3_Y := 21.4
const F_Y := 22.2
const PARAPET_H := 1.55   # 比跳跃高度 1.5 m 高，翻不过去

# ---------------- 大屋面 ----------------
const DX0 := -46.0
const DX1 := 56.0
const DZ0 := -30.0
const DZ1 := 30.0

# ---------------- 设备房（中心 + 半宽） ----------------
const R1X := -17.0
const R1Z := -2.0
const R1HX := 10.0
const R1HZ := 10.0

const R2X := 8.0
const R2Z := -3.0
const R2HX := 11.2
const R2HZ := 10.0

const R3X := 33.0
const R3Z := 3.0
const R3HX := 10.0
const R3HZ := 10.0

const FX := 50.0
const FZ := 4.0
const FHX := 3.0
const FHZ := 3.0

const C1_Y := 19.0   # 攀爬：垃圾箱
const C2_Y := 20.0   # 攀爬：集装箱
const C3_Y := 21.0   # 攀爬：机组
const SPAWN := Vector3(-43.0, DECK_Y, 15.0)

static var _M := {}


static func build(origin := Vector3.ZERO) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arena_rooftop"
	root.position = origin

	_mats()
	var walls: Array = []
	var cover: Array = []
	var platforms: Array = []
	_environment(root)
	_city(root)
	_deck(root, cover, platforms)
	_climb(root, cover, platforms)
	_plant(root, cover, platforms)
	_headhouse(root, cover, platforms)
	_workshop(root, cover, platforms)
	_beacon(root, cover, platforms)
	_lights(root)
	_roof_clutter(root, cover)

	# room_shared 的 player.reset() 最后会把 position.y 拉回 ground_height=0，
	# 所以整张图整体下移 DECK_Y：大屋面落在 y=0，街面落到 y=-18。
	var shift := Vector3(0.0, -DECK_Y, 0.0) * U
	root.position = origin + shift
	for pl in platforms:
		pl["c"] = Vector3(pl["c"].x, pl["c"].y + shift.y, pl["c"].z)
		pl["h"] = float(pl["h"]) + shift.y
	for cv in cover:
		cv["c"] = Vector3(cv["c"].x, cv["c"].y + shift.y, cv["c"].z)

	var over := 2.0
	var bounds := AABB(
		Vector3((DX0 - over) * U, 0.0, (DZ0 - over) * U),
		Vector3((DX1 - DX0 + 2.0 * over) * U, 60.0 * U, (DZ1 - DZ0 + 2.0 * over) * U))

	# 面向东偏北：一进场就能同时看到攀爬点、R1 和大屋面纵深
	var spawn := Transform3D(Basis(Vector3.UP, deg_to_rad(-62.0)), SPAWN * U + shift)

	return {
		"node": root,
		"kind": "rooftop",
		"name_cn": "暮色楼顶",
		"hint": "踩着货箱和机组爬上设备房，跨过三处屋面空隙，抵达信标塔。",
		"floor_y": 0.0,
		"bounds": bounds,
		"walls": walls,
		"cover": cover,
		"platforms": platforms,
		"camera_open": true,
		"ceiling": 0.0,
		"spawns": [],
		"wall_slots": [],
		"lamps": [],
		"player_spawn": spawn,
	}


# ================================================================== 材质
static func _mats() -> void:
	_M = {
		# 屋面：老化沥青卷材 + 补丁
		"deck": Kit.std(Color(0.268, 0.256, 0.236), 0.90, 0.0,
			{"noise": 9.0, "grime": 0.34, "bump": 0.26, "streak": 0.10,
			"dirt": Color(0.055, 0.050, 0.044)}),
		"tar": Kit.std(Color(0.048, 0.047, 0.046), 0.96, 0.0,
			{"noise": 12.0, "grime": 0.20, "bump": 0.14}),
		"seam": Kit.std(Color(0.075, 0.072, 0.068), 1.0, 0.0,
			{"noise": 18.0, "grime": 0.30, "bump": 0.10}),
		"conc": Kit.std(Color(0.310, 0.302, 0.285), 0.86, 0.0,
			{"noise": 6.0, "grime": 0.30, "bump": 0.22, "streak": 0.22,
			"dirt": Color(0.062, 0.058, 0.052)}),
		"conc_dark": Kit.std(Color(0.165, 0.164, 0.158), 0.84, 0.0,
			{"noise": 7.0, "grime": 0.40, "bump": 0.24, "streak": 0.34}),
		"facade": Kit.std(Color(0.150, 0.152, 0.160), 0.82, 0.0,
			{"noise": 4.0, "grime": 0.34, "bump": 0.18, "streak": 0.42,
			"dirt": Color(0.035, 0.034, 0.036)}),
		"metal": Kit.std(Color(0.330, 0.342, 0.352), 0.48, 0.55,
			{"noise": 3.4, "grime": 0.18, "bump": 0.10, "streak": 0.16}),
		"metal_dark": Kit.std(Color(0.120, 0.126, 0.134), 0.56, 0.46,
			{"noise": 4.0, "grime": 0.24, "bump": 0.12}),
		"steel_matte": Kit.std(Color(0.215, 0.222, 0.226), 0.86, 0.16,
			{"noise": 6.0, "grime": 0.40, "bump": 0.18, "streak": 0.30}),
		"rust": Kit.std(Color(0.180, 0.108, 0.062), 0.78, 0.26,
			{"noise": 3.0, "grime": 0.80, "bump": 0.20, "streak": 0.52}),
		"rubber": Kit.std(Color(0.032, 0.032, 0.034), 0.94, 0.0,
			{"noise": 10.0, "grime": 0.12, "bump": 0.18}),
		"paint": Kit.std(Color(0.560, 0.400, 0.075), 0.76, 0.0,
			{"noise": 6.0, "grime": 0.42, "bump": 0.14, "streak": 0.34}),
		"white": Kit.std(Color(0.470, 0.470, 0.450), 0.78, 0.0,
			{"noise": 7.0, "grime": 0.46, "bump": 0.12, "streak": 0.40}),
		"louvre": Kit.std(Color(0.090, 0.096, 0.104), 0.62, 0.34,
			{"noise": 5.0, "grime": 0.26, "bump": 0.16}),
		"hvac": Kit.std(Color(0.360, 0.356, 0.330), 0.66, 0.18,
			{"noise": 4.2, "grime": 0.34, "bump": 0.16, "streak": 0.30}),
		"door": Kit.std(Color(0.145, 0.150, 0.152), 0.62, 0.30,
			{"noise": 5.0, "grime": 0.30, "bump": 0.14}),
		"glass": Kit.glass(Color(0.20, 0.34, 0.40), 0.30),
		"asphalt": Kit.std(Color(0.050, 0.050, 0.055), 0.92, 0.0,
			{"noise": 14.0, "grime": 0.22, "bump": 0.18}),
		"win_warm": Kit.emissive(Color(1.0, 0.72, 0.40), 0.9, 0.22),
		"win_dim": Kit.emissive(Color(1.0, 0.74, 0.44), 0.30, 0.34),
		"win_cool": Kit.emissive(Color(0.48, 0.72, 0.92), 1.2, 0.18),
		"lamp": Kit.emissive(Color(1.0, 0.70, 0.36), 3.0, 0.14),
		"beacon": Kit.emissive(Color(1.0, 0.10, 0.06), 4.0, 0.18),
		"strip": Kit.emissive(Color(0.30, 0.86, 0.98), 2.2, 0.14),
		"green": Kit.emissive(Color(0.30, 1.0, 0.45), 1.6, 0.16),
		"red": Kit.emissive(Color(1.0, 0.16, 0.10), 1.8, 0.16),
	}


# ================================================================== 环境
static func _environment(root: Node3D) -> void:
	var env := Environment.new()

	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://rooftop/src/arena/rooftop_sky.gdshader")
	sm.set_shader_parameter("top_color", Color(0.150, 0.320, 0.700))
	sm.set_shader_parameter("horizon_color", Color(0.980, 0.545, 0.250))
	sm.set_shader_parameter("ground_color", Color(0.070, 0.062, 0.066))
	sm.set_shader_parameter("sun_color", Color(1.0, 0.72, 0.44))
	sm.set_shader_parameter("sun_dir", Vector3(-0.86, 0.32, -0.18).normalized())
	sky.sky_material = sm

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.27, 0.44)
	env.ambient_light_energy = 0.58
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.06
	env.tonemap_white = 3.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.02

	env.glow_enabled = true
	env.glow_intensity = 0.72
	env.glow_strength = 0.90
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.255, 0.235, 0.270)
	env.fog_light_energy = 0.55
	env.fog_depth_begin = 85.0 * U
	env.fog_depth_end = 380.0 * U
	env.fog_density = 0.34
	env.fog_sky_affect = 0.0

	env.ssao_enabled = true
	env.ssao_radius = 1.8
	env.ssao_intensity = 2.0
	env.ssao_power = 1.8
	env.ssr_enabled = true
	env.ssr_max_steps = 20
	env.ssr_fade_out = 2.4

	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.74, 0.50)
	sun.light_energy = 2.55
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 200.0 * U
	root.add_child(sun)
	# 太阳在西偏北，低角度：光往东走，正好照亮玩家前进方向看到的立面
	sun.look_at_from_position(Vector3.ZERO, Vector3(0.86, -0.32, 0.18).normalized(), Vector3.UP)

	# 东侧补一点冷光，别让背光面全黑（不投影）
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.36, 0.52, 0.86)
	fill.light_energy = 0.55
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.shadow_enabled = false
	root.add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(-0.62, -0.52, -0.58).normalized(), Vector3.UP)


# ================================================================== 城市背景
static func _city(root: Node3D) -> void:
	# 街面
	_b(root, Vector3(760.0, 0.5, 760.0), Vector3(0.0, -0.26, 0.0), _M["asphalt"])
	# 楼下道路标线（从屋面只露出一点点，主要是让俯视不空）
	for k in 7:
		_dash_m(root, Vector2(-60.0 + float(k) * 22.0, -44.0), Vector2(-52.0 + float(k) * 22.0, -44.0),
			0.5, 4.0, 4.0, 0.02, _M["white"])
	_b(root, Vector3(520.0, 0.05, 1.2), Vector3(0.0, 0.01, -44.0), _M["tar"])
	_b(root, Vector3(520.0, 0.05, 1.2), Vector3(0.0, 0.01, 44.0), _M["tar"])

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261125

	# 近景邻楼：只做剪影，别把屋面围死
	for i in 14:
		var a := TAU * float(i) / 14.0 + rng.randf_range(-0.08, 0.08)
		var r := rng.randf_range(78.0, 120.0)
		var sx := rng.randf_range(10.0, 24.0)
		var sz := rng.randf_range(10.0, 24.0)
		var h := rng.randf_range(14.0, 34.0)
		_tower(root, cos(a) * r, sin(a) * r, sx, sz, h, rng, false)

	# 远景天际线
	for i in 34:
		var a := TAU * float(i) / 34.0 + rng.randf_range(-0.05, 0.05)
		var r := rng.randf_range(150.0, 300.0)
		var sx := rng.randf_range(14.0, 38.0)
		var sz := rng.randf_range(14.0, 38.0)
		var h := rng.randf_range(26.0, 82.0)
		_tower(root, cos(a) * r, sin(a) * r, sx, sz, h, rng, true)

	# 街灯：几盏钠灯，给楼下一点暖色
	for k in 8:
		var lx := -220.0 + float(k) * 62.0
		_b(root, Vector3(0.35, 9.0, 0.35), Vector3(lx, 4.5, -44.0), _M["metal_dark"])
		_b(root, Vector3(1.6, 0.22, 0.6), Vector3(lx + 0.6, 9.0, -44.0), _M["lamp"])
		_omni(root, Vector3(lx + 0.6, 8.7, -44.0), Color(1.0, 0.62, 0.30), 1.1, 26.0, 0.25)


static func _tower(root: Node3D, cx: float, cz: float, sx: float, sz: float, h: float,
		rng: RandomNumberGenerator, far: bool) -> void:
	var mat: Material = _M["facade"] if not far else _M["conc_dark"]
	_b(root, Vector3(sx, h, sz), Vector3(cx, h * 0.5, cz), mat)
	# 楼顶帽檐
	_b(root, Vector3(sx + 0.6, 0.5, sz + 0.6), Vector3(cx, h + 0.25, cz), _M["conc_dark"])

	var dir := Vector2(-cx, -cz).normalized()
	var tx := (sx * 0.5) / maxf(absf(dir.x), 0.001)
	var tz := (sz * 0.5) / maxf(absf(dir.y), 0.001)
	var face_dist := minf(tx, tz)
	var face := Vector2(cx, cz) + dir * (face_dist + 0.06)
	var tangent := Vector2(-dir.y, dir.x)
	var half := minf(sx, sz) * 0.5
	var n := 2 if far else 4
	for j in n:
		var w := rng.randf_range(1.0, 2.2)
		var hh := rng.randf_range(0.5, 1.0)
		var t := rng.randf_range(0.25, 0.78)
		var slide := tangent * rng.randf_range(-half * 0.55, half * 0.55)
		var p := face + slide
		var mat2: Material = _M["win_warm"] if rng.randf() > 0.42 else _M["win_cool"]
		# 窗带沿楼体切向排布
		_b(root, Vector3(w, hh, 0.10), Vector3(p.x, h * t, p.y), mat2,
			Vector3(0.0, atan2(dir.x, dir.y), 0.0))


# ================================================================== 大屋面
static func _deck(root: Node3D, cover: Array, platforms: Array) -> void:
	var cx := (DX0 + DX1) * 0.5
	var cz := (DZ0 + DZ1) * 0.5
	var w := DX1 - DX0
	var d := DZ1 - DZ0

	# 楼下体量（只在女儿墙外看得到）
	_b(root, Vector3(w - 1.0, DECK_Y - 0.5, d - 1.0),
		Vector3(cx, (DECK_Y - 0.5) * 0.5, cz), _M["facade"])
	# 屋面板
	_b(root, Vector3(w, 0.5, d), Vector3(cx, DECK_Y - 0.25, cz), _M["deck"])
	platforms.append({"c": Vector3(cx, 0.0, cz) * U,
		"hx": w * 0.5 * U, "hz": d * 0.5 * U, "h": DECK_Y * U})

	# 女儿墙：1.55 m，高于跳跃高度，翻不出去
	var py := DECK_Y + PARAPET_H * 0.5
	_b(root, Vector3(w, PARAPET_H, 0.35), Vector3(cx, py, DZ0), _M["conc"])
	_b(root, Vector3(w, PARAPET_H, 0.35), Vector3(cx, py, DZ1), _M["conc"])
	_b(root, Vector3(0.35, PARAPET_H, d), Vector3(DX0, py, cz), _M["conc"])
	_b(root, Vector3(0.35, PARAPET_H, d), Vector3(DX1, py, cz), _M["conc"])
	# 压顶
	_b(root, Vector3(w + 0.1, 0.12, 0.5), Vector3(cx, DECK_Y + PARAPET_H, DZ0), _M["metal"])
	_b(root, Vector3(w + 0.1, 0.12, 0.5), Vector3(cx, DECK_Y + PARAPET_H, DZ1), _M["metal"])
	_b(root, Vector3(0.5, 0.12, d + 0.1), Vector3(DX0, DECK_Y + PARAPET_H, cz), _M["metal"])
	_b(root, Vector3(0.5, 0.12, d + 0.1), Vector3(DX1, DECK_Y + PARAPET_H, cz), _M["metal"])

	_chain_y(cover, Vector2(DX0, DZ0), Vector2(DX1, DZ0), 0.18, DECK_Y, DECK_Y + PARAPET_H)
	_chain_y(cover, Vector2(DX0, DZ1), Vector2(DX1, DZ1), 0.18, DECK_Y, DECK_Y + PARAPET_H)
	_chain_y(cover, Vector2(DX0, DZ0), Vector2(DX0, DZ1), 0.18, DECK_Y, DECK_Y + PARAPET_H)
	_chain_y(cover, Vector2(DX1, DZ0), Vector2(DX1, DZ1), 0.18, DECK_Y, DECK_Y + PARAPET_H)

	# 伸缩缝：只沿长向留几道，做窄做暗，不要读成瓷砖
	for k in 4:
		var x := DX0 + 18.0 + float(k) * 18.0
		_b(root, Vector3(0.06, 0.01, d - 2.0), Vector3(x, DECK_Y + 0.006, cz), _M["seam"])

	# 起点到攀爬点的黄色虚线
	_dash_m(root, Vector2(-41.0, 10.0), Vector2(-38.2, 10.0), 0.28, 1.1, 0.9, DECK_Y + 0.02, _M["paint"])
	_dash_m(root, Vector2(-36.0, 2.0), Vector2(-28.0, 2.0), 0.28, 1.1, 0.9, DECK_Y + 0.02, _M["paint"])

	# 屋面补丁 / 积水
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711
	for i in 10:
		var px := rng.randf_range(DX0 + 8.0, DX1 - 8.0)
		var pz := rng.randf_range(DZ0 + 5.0, DZ1 - 5.0)
		var ps := rng.randf_range(1.2, 3.2)
		_b(root, Vector3(ps, 0.015, ps * rng.randf_range(0.6, 1.4)),
			Vector3(px, DECK_Y + 0.008, pz), _M["tar"])
	for i in 4:
		var px2 := rng.randf_range(-10.0, 30.0)
		var pz2 := rng.randf_range(-20.0, 20.0)
		var ps2 := rng.randf_range(1.0, 2.4)
		_b(root, Vector3(ps2, 0.012, ps2 * 0.7), Vector3(px2, DECK_Y + 0.01, pz2), _M["glass"])

	# 屋顶排水口
	for p in [Vector2(DX0 + 3.0, DZ0 + 3.0), Vector2(DX1 - 3.0, DZ0 + 3.0),
			Vector2(DX0 + 3.0, DZ1 - 3.0), Vector2(DX1 - 3.0, DZ1 - 3.0)]:
		Kit.cylinder(root, 0.42 * U, 0.06 * U, Vector3(p.x, DECK_Y + 0.03, p.y) * U,
			_M["metal_dark"], Vector3.ZERO)
		Kit.cylinder(root, 0.30 * U, 0.09 * U, Vector3(p.x, DECK_Y + 0.05, p.y) * U,
			_M["tar"], Vector3.ZERO)

	# 起点到攀爬点的浅色走道（实线，比虚线好读）
	_b(root, Vector3(7.0, 0.02, 1.30), Vector3(-39.5, DECK_Y + 0.012, 10.0), _M["paint"])
	_b(root, Vector3(1.9, 0.02, 1.30), Vector3(-35.2, DECK_Y + 0.012, 9.5), _M["paint"])
	# 走道两侧的白色边线
	for dz in [-0.72, 0.72]:
		_b(root, Vector3(7.0, 0.02, 0.10), Vector3(-39.5, DECK_Y + 0.014, 10.0 + dz), _M["white"])
	# 起点附近的托盘堆 / 油桶 / 卷材（都在走道南侧，不挡路）
	_solid_box(root, cover, platforms, -41.0, 2.5, 0.75, 0.60, 18.85, _M["rust"])
	for k in 3:
		_b(root, Vector3(1.5, 0.10, 1.2), Vector3(-41.0, 18.30 + float(k) * 0.18, 2.5), _M["metal"])
	_b(root, Vector3(1.4, 0.05, 1.1), Vector3(-41.0, 18.88, 2.5), _M["tar"])
	_solid_box(root, cover, platforms, -38.6, 3.2, 0.65, 0.55, 18.92, _M["door"])
	for k in 3:
		_b(root, Vector3(1.32, 0.06, 0.06), Vector3(-38.6, 18.30 + float(k) * 0.22, 3.76), _M["metal_dark"])
	_b(root, Vector3(0.90, 0.22, 0.03), Vector3(-38.6, 18.62, 3.22), _M["white"])
	# 三卷防水卷材
	for k in 3:
		Kit.cylinder(root, 0.22 * U, 1.8 * U, Vector3(-43.5, 18.22, 4.0 + float(k) * 0.55) * U,
			_M["rubber"], Vector3(0.0, 0.0, PI * 0.5))

	# 西南角的楼梯间出屋面（起点背景）
	_stair_hut(root, cover, platforms, -42.0, -23.0)


static func _stair_hut(root: Node3D, cover: Array, platforms: Array, cx: float, cz: float) -> void:
	var hx := 3.4
	var hz := 3.0
	var top := DECK_Y + 3.4
	_solid_box(root, cover, platforms, cx, cz, hx, hz, top, _M["conc"])
	# 门
	_b(root, Vector3(1.5, 2.2, 0.12), Vector3(cx + 1.2, DECK_Y + 1.1, cz + hz + 0.02), _M["door"])
	_b(root, Vector3(0.10, 0.10, 0.10), Vector3(cx + 1.85, DECK_Y + 1.2, cz + hz + 0.10), _M["metal"])
	# 门头灯 + 雨檐
	_b(root, Vector3(2.0, 0.10, 0.6), Vector3(cx + 1.2, DECK_Y + 2.5, cz + hz + 0.25), _M["metal_dark"])
	_b(root, Vector3(0.34, 0.10, 0.16), Vector3(cx + 1.2, DECK_Y + 2.36, cz + hz + 0.30), _M["lamp"])
	_omni(root, Vector3(cx + 1.2, DECK_Y + 2.30, cz + hz + 0.55), Color(1.0, 0.68, 0.36), 1.6, 9.0, 0.35)
	# 通风格栅
	for k in 4:
		_b(root, Vector3(0.9, 0.08, 0.06), Vector3(cx - 1.6, DECK_Y + 1.0 + float(k) * 0.22, cz + hz + 0.02),
			_M["louvre"])
	# 屋顶小风机
	_b(root, Vector3(1.1, 0.55, 1.1), Vector3(cx - 1.2, top + 0.27, cz - 0.6), _M["hvac"])
	Kit.cylinder(root, 0.42 * U, 0.10 * U, Vector3(cx - 1.2, top + 0.58, cz - 0.6) * U,
		_M["metal_dark"], Vector3.ZERO)
	# 铭牌（不写文字，只做一块反光板）
	_b(root, Vector3(1.2, 0.34, 0.04), Vector3(cx - 1.4, DECK_Y + 2.1, cz + hz + 0.03), _M["white"])


# ================================================================== 攀爬段
static func _climb(root: Node3D, cover: Array, platforms: Array) -> void:
	# 大屋面 18.0 → 垃圾箱 19.0 → 集装箱 20.0 → 机组 21.0 → R1 屋面 21.6
	# 每级 1.0 m，跳起来有余量；机组与 R1 西墙咬合，最后一步只差 0.6 m。

	# ---------------- 垃圾箱 ----------------
	var c1x := -36.0
	var c1z := 9.5
	_solid_box(root, cover, platforms, c1x, c1z, 1.6, 1.0, C1_Y, _M["metal_dark"])
	# 箱盖：四周一圈翻边 + 中间略凹
	_b(root, Vector3(3.34, 0.10, 2.14), Vector3(c1x, C1_Y - 0.04, c1z), _M["steel_matte"])
	_b(root, Vector3(3.02, 0.04, 1.84), Vector3(c1x, C1_Y + 0.01, c1z), _M["steel_matte"])
	# 侧面加强筋
	for k in 5:
		_b(root, Vector3(0.07, 0.86, 2.02), Vector3(c1x - 1.35 + float(k) * 0.68, 18.46, c1z), _M["metal"])
	# 前后两个投料口
	for sz2 in [-1.0, 1.0]:
		_b(root, Vector3(1.5, 0.62, 0.06), Vector3(c1x + 0.4, DECK_Y + 0.52, c1z + sz2 * 1.03), _M["rubber"])
		_b(root, Vector3(1.7, 0.08, 0.10), Vector3(c1x + 0.4, DECK_Y + 0.90, c1z + sz2 * 1.04), _M["steel_matte"])
		_b(root, Vector3(0.08, 0.70, 0.08), Vector3(c1x - 1.30, DECK_Y + 0.45, c1z + sz2 * 1.04), _M["steel_matte"])
	# 轮子
	for sx in [-37.0, -35.0]:
		for sz in [8.7, 10.3]:
			Kit.cylinder(root, 0.16 * U, 0.12 * U, Vector3(sx, 18.13, sz) * U, _M["rubber"],
				Vector3(0.0, 0.0, PI * 0.5))
	# 锈迹：一条竖向脏带
	_b(root, Vector3(0.22, 0.95, 0.03), Vector3(c1x - 0.9, 18.5, c1z - 1.02), _M["rust"])

	# ---------------- 集装箱 ----------------
	var c2x := -31.8
	var c2z := 10.0
	var c2hx := 2.3
	var c2hz := 1.2
	var box_mat := Kit.std(Color(0.078, 0.125, 0.100), 0.84, 0.10,
		{"noise": 4.0, "grime": 0.58, "bump": 0.18, "streak": 0.60})
	_solid_box(root, cover, platforms, c2x, c2z, c2hx, c2hz, C2_Y, box_mat)
	# 长边波纹（南北两面）
	var rib_y := (DECK_Y + C2_Y) * 0.5
	for k in 12:
		var bx := c2x - c2hx + 0.22 + float(k) * 0.36
		for sz in [-1.0, 1.0]:
			_b(root, Vector3(0.10, C2_Y - DECK_Y - 0.24, 0.05),
				Vector3(bx, rib_y, c2z + sz * (c2hz + 0.01)), _M["metal_dark"])
	# 短边波纹（东西两面）
	for k in 6:
		var bz := c2z - c2hz + 0.20 + float(k) * 0.38
		for sx in [-1.0, 1.0]:
			_b(root, Vector3(0.05, C2_Y - DECK_Y - 0.24, 0.10),
				Vector3(c2x + sx * (c2hx + 0.01), rib_y, bz), _M["metal_dark"])
	# 顶框 + 角件
	_b(root, Vector3(c2hx * 2.0 + 0.10, 0.10, c2hz * 2.0 + 0.10), Vector3(c2x, C2_Y - 0.03, c2z),
		_M["steel_matte"])
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_b(root, Vector3(0.22, 0.22, 0.22), Vector3(c2x + sx * c2hx, C2_Y - 0.12,
				c2z + sz * c2hz), _M["metal_dark"])
	# 西面箱门：两扇 + 四根锁杆 + 把手
	for k in 2:
		var dz2 := -0.56 + float(k) * 1.12
		_b(root, Vector3(0.06, 1.62, 1.00), Vector3(c2x - c2hx - 0.04, rib_y, c2z + dz2), _M["door"])
	for dz3 in [-0.92, -0.30, 0.30, 0.92]:
		_b(root, Vector3(0.07, 1.70, 0.07), Vector3(c2x - c2hx - 0.10, rib_y, c2z + dz3), _M["metal"])
	_b(root, Vector3(0.10, 0.10, 0.40), Vector3(c2x - c2hx - 0.14, 18.95, c2z + 0.30), _M["metal"])
	# 顶面检修口 + 铭牌
	_b(root, Vector3(1.0, 0.08, 0.7), Vector3(c2x + 0.9, C2_Y + 0.04, c2z - 0.3), _M["rust"])
	_b(root, Vector3(0.9, 0.26, 0.03), Vector3(c2x - 1.2, 19.30, c2z - c2hz - 0.04), _M["white"])

	# ---------------- 屋顶机组 ----------------
	var c3x := -28.0
	var c3z := 10.0
	_solid_box(root, cover, platforms, c3x, c3z, 1.4, 1.1, C3_Y, _M["hvac"])
	_b(root, Vector3(2.84, 0.10, 2.24), Vector3(c3x, C3_Y - 0.04, c3z), _M["steel_matte"])
	# 顶面风扇
	Kit.cylinder(root, 0.58 * U, 0.10 * U, Vector3(c3x, C3_Y + 0.02, c3z) * U, _M["metal_dark"], Vector3.ZERO)
	Kit.torus(root, 0.56 * U, 0.035 * U, Vector3(c3x, C3_Y + 0.02, c3z) * U, _M["metal"], 20)
	for k in 4:
		var a := TAU * float(k) / 4.0
		_b(root, Vector3(0.10, 0.03, 0.50), Vector3(c3x + cos(a) * 0.26, C3_Y + 0.07,
			c3z + sin(a) * 0.26), _M["metal_dark"], Vector3(0.0, -a, 0.0))
	# 侧面百叶
	for k in 7:
		_b(root, Vector3(2.50, 0.06, 0.06), Vector3(c3x, 18.42 + float(k) * 0.17, c3z + 1.12),
			_M["louvre"])
	# 检修门 + 控制盒
	_b(root, Vector3(0.06, 0.80, 0.70), Vector3(c3x - 1.42, 18.62, c3z - 0.20), _M["door"])
	_b(root, Vector3(0.10, 0.34, 0.36), Vector3(c3x - 1.44, 19.10, c3z + 0.60), _M["metal_dark"])
	_b(root, Vector3(0.04, 0.10, 0.10), Vector3(c3x - 1.50, 19.12, c3z + 0.52), _M["green"])
	# 机组北面到墙角之间没有可贴的墙面（机组在 R1 西南角外侧），
	# 不做冷媒管，避免又一次出现“悬空斜管”；改成一个落地接线箱。
	_b(root, Vector3(0.60, 0.90, 0.50), Vector3(c3x - 1.15, DECK_Y + 0.45, c3z - 1.55), _M["metal_dark"])
	_b(root, Vector3(0.46, 0.10, 0.36), Vector3(c3x - 1.15, DECK_Y + 0.96, c3z - 1.55), _M["metal"])
	_cov_y(cover, Vector3(c3x - 1.15, 0.0, c3z - 1.55), 0.34, DECK_Y, DECK_Y + 1.0)


# ================================================================== R1 设备房
static func _plant(root: Node3D, cover: Array, platforms: Array) -> void:
	var top := R1_Y
	_slab(root, cover, platforms, R1X, R1Z, R1HX, R1HZ, top, _M["conc"], _M["conc_dark"])
	# 南墙百叶
	for k in 9:
		_b(root, Vector3(12.0, 0.12, 0.10), Vector3(R1X - 2.0, DECK_Y + 0.9 + float(k) * 0.22, R1Z + R1HZ + 0.02),
			_M["louvre"])
	_b(root, Vector3(12.4, 0.10, 0.26), Vector3(R1X - 2.0, DECK_Y + 2.95, R1Z + R1HZ + 0.06), _M["metal"])
	_b(root, Vector3(12.4, 0.10, 0.26), Vector3(R1X - 2.0, DECK_Y + 0.78, R1Z + R1HZ + 0.06), _M["metal"])
	# 西墙门（两扇）
	for k in 2:
		_b(root, Vector3(0.12, 2.1, 1.4), Vector3(R1X - R1HX - 0.02, DECK_Y + 1.05, R1Z + 1.0 + float(k) * 1.7),
			_M["door"])
	_b(root, Vector3(0.22, 0.10, 3.6), Vector3(R1X - R1HX - 0.06, DECK_Y + 2.22, R1Z + 1.85), _M["metal"])
	# 西墙：竖向压型板分缝 + 桥架 + 排风机 + 门头雨棚
	for k in 7:
		_b(root, Vector3(0.06, top - DECK_Y - 0.55, 0.10), Vector3(R1X - R1HX - 0.04,
			(DECK_Y + top) * 0.5 - 0.2, R1Z - 10.0 + float(k) * 2.9), _M["metal_dark"])
	_b(root, Vector3(0.16, 0.12, 19.0), Vector3(R1X - R1HX - 0.12, DECK_Y + 2.75, R1Z - 0.5), _M["metal"])
	for k in 8:
		_b(root, Vector3(0.22, 0.10, 0.10), Vector3(R1X - R1HX - 0.14, DECK_Y + 2.70,
			R1Z - 9.0 + float(k) * 2.4), _M["metal_dark"])
	for k in 6:
		_b(root, Vector3(0.10, 0.08, 1.10), Vector3(R1X - R1HX - 0.06, DECK_Y + 1.15 + float(k) * 0.12,
			R1Z + 5.2), _M["louvre"])
	_b(root, Vector3(0.14, 0.86, 1.34), Vector3(R1X - R1HX - 0.10, DECK_Y + 1.50, R1Z + 5.2), _M["metal_dark"])
	_b(root, Vector3(1.5, 0.22, 4.6), Vector3(R1X - R1HX - 0.55, DECK_Y + 2.45, R1Z + 0.85), _M["metal_dark"])
	_b(root, Vector3(1.54, 0.08, 4.64), Vector3(R1X - R1HX - 0.55, DECK_Y + 2.59, R1Z + 0.85), _M["metal"])
	for dz2 in [-1.9, 1.9]:
		_tube(root, Vector3(R1X - R1HX - 1.02, DECK_Y + 2.35, R1Z + 0.85 + dz2),
			Vector3(R1X - R1HX - 0.60, DECK_Y + 1.90, R1Z + 0.85 + dz2), 0.04, _M["metal"])
	# 西南角落点的黄黑警示带：贴在屋面挑檐外侧，告诉玩家“从这里上来”
	for k in 3:
		_b(root, Vector3(0.72, 0.40, 0.10), Vector3(R1X - 0.2 + float(k) * 0.80, top - 0.28,
			R1Z + R1HZ + 0.27), _M["paint"] if k % 2 == 0 else _M["rubber"])
	# 东墙落水管
	_tube(root, Vector3(R1X + R1HX + 0.12, DECK_Y, R1Z - 6.0), Vector3(R1X + R1HX + 0.12, top, R1Z - 6.0),
		0.11, _M["rust"])
	for k in 3:
		_b(root, Vector3(0.30, 0.08, 0.30), Vector3(R1X + R1HX + 0.12, DECK_Y + 1.0 + float(k) * 1.4, R1Z - 6.0),
			_M["metal_dark"])
	# 屋面：冷水机组（1.6 m，高于跳跃高度，只做侧面碰撞，不登记台面）
	_cov_box(cover, -20.0, 2.0, 1.3, 1.1, top, top + 1.85)
	_b(root, Vector3(2.6, 1.85, 2.2), Vector3(-20.0, top + 0.925, 2.0), _M["hvac"])
	_b(root, Vector3(2.8, 0.14, 2.4), Vector3(-20.0, top + 1.87, 2.0), _M["metal"])
	for dx in [-0.62, 0.62]:
		for dz in [-0.55, 0.55]:
			Kit.cylinder(root, 0.34 * U, 0.06 * U, Vector3(-20.0 + dx, top + 1.93, 2.0 + dz) * U,
				_M["metal_dark"], Vector3.ZERO)
	# 屋面风管（1.2 m，可站）
	_solid_box(root, cover, platforms, -17.0, -8.2, 4.2, 0.8, top + 1.2, _M["metal"], top)
	_b(root, Vector3(8.6, 0.10, 1.7), Vector3(-17.0, top + 1.21, -8.2), _M["metal_dark"])
	for k in 6:
		_b(root, Vector3(0.10, 1.1, 1.7), Vector3(-21.0 + float(k) * 1.6, top + 0.55, -8.2), _M["metal_dark"])
	# 排风立管：2.2 m 高，明显超出跳跃高度（不做可站台面）
	for p in [Vector2(-11.0, 4.0), Vector2(-24.0, -6.0)]:
		Kit.cylinder(root, 0.28 * U, 2.10 * U, Vector3(p.x, top + 1.05, p.y) * U, _M["metal"], Vector3.ZERO)
		Kit.cylinder(root, 0.40 * U, 0.14 * U, Vector3(p.x, top + 2.17, p.y) * U, _M["metal_dark"], Vector3.ZERO)
		for k in 3:
			Kit.torus(root, 0.30 * U, 0.03 * U, Vector3(p.x, top + 0.45 + float(k) * 0.55, p.y) * U,
				_M["metal_dark"], 12)
		_cov_y(cover, Vector3(p.x, 0.0, p.y), 0.32, top, top + 2.24)
	# 东侧起跳边缘：黄黑警示带（跑酷读数）
	_edge_band(root, R1X + R1HX, true, R1Z - 9.0, R1Z + 9.0, top)


# ================================================================== R2 楼梯间
static func _headhouse(root: Node3D, cover: Array, platforms: Array) -> void:
	var top := R2_Y
	_slab(root, cover, platforms, R2X, R2Z, R2HX, R2HZ, top, _M["conc"], _M["conc_dark"])
	# 上部：一排独立窗格（暖光），读作“有人的楼梯间”
	var wz := R2Z + R2HZ + 0.02
	_b(root, Vector3(12.4, 1.04, 0.08), Vector3(R2X - 2.0, top - 0.90, wz), _M["metal_dark"])
	for k in 6:
		var wx := R2X - 7.1 + float(k) * 2.35
		_b(root, Vector3(1.55, 0.80, 0.10), Vector3(wx, top - 0.90, wz + 0.06), _M["win_dim"])
		_b(root, Vector3(0.12, 0.92, 0.14), Vector3(wx + 0.83, top - 0.90, wz + 0.10), _M["metal_dark"])
		_b(root, Vector3(1.70, 0.10, 0.14), Vector3(wx, top - 0.44, wz + 0.10), _M["metal_dark"])
		_b(root, Vector3(1.70, 0.10, 0.14), Vector3(wx, top - 1.36, wz + 0.10), _M["metal_dark"])
	# 西面也开三格窗
	var wx2 := R2X - R2HX - 0.02
	_b(root, Vector3(0.08, 1.04, 8.2), Vector3(wx2, top - 0.90, R2Z - 3.0), _M["metal_dark"])
	for k in 3:
		var wzz := R2Z - 5.6 + float(k) * 2.5
		_b(root, Vector3(0.10, 0.80, 1.65), Vector3(wx2 - 0.06, top - 0.90, wzz), _M["win_dim"])
		_b(root, Vector3(0.14, 0.92, 0.12), Vector3(wx2 - 0.10, top - 0.90, wzz + 0.88), _M["metal_dark"])
	# 东墙门（大屋面层）
	_b(root, Vector3(0.12, 2.2, 1.6), Vector3(R2X + R2HX + 0.02, DECK_Y + 1.1, R2Z + 2.0), _M["door"])
	_b(root, Vector3(0.20, 0.10, 2.0), Vector3(R2X + R2HX + 0.06, DECK_Y + 2.32, R2Z + 2.0), _M["metal"])
	_edge_band(root, R2X + R2HX, true, R2Z - 9.0, R2Z + 9.0, top)
	_land_stripe(root, R2X - R2HX + 0.9, R2Z - 9.0, R2Z + 9.0, top)
	# 屋面：天窗（与屋面齐平，可走）
	_b(root, Vector3(4.2, 0.08, 3.2), Vector3(R2X, top + 0.02, R2Z + 2.0), _M["glass"])
	for k in 3:
		_b(root, Vector3(4.2, 0.06, 0.08), Vector3(R2X, top + 0.06, R2Z + 0.6 + float(k) * 1.4), _M["metal_dark"])
	# 排风立管：2.2 m 高
	Kit.cylinder(root, 0.40 * U, 2.10 * U, Vector3(R2X - 6.0, top + 1.05, R2Z - 6.0) * U,
		_M["metal"], Vector3.ZERO)
	Kit.cylinder(root, 0.52 * U, 0.14 * U, Vector3(R2X - 6.0, top + 2.17, R2Z - 6.0) * U,
		_M["metal_dark"], Vector3.ZERO)
	_cov_y(cover, Vector3(R2X - 6.0, 0.0, R2Z - 6.0), 0.44, top, top + 2.24)
	# 卫星天线（视觉，杆只做碰撞）
	_tube(root, Vector3(R2X + 6.0, top, R2Z - 5.0), Vector3(R2X + 6.0, top + 2.4, R2Z - 5.0), 0.07, _M["metal"])
	var dish := Kit.cone(root, 1.15 * U, 0.45 * U, Vector3(R2X + 6.0, top + 2.55, R2Z - 5.0) * U,
		_M["white"])
	dish.rotation = Vector3(-0.75, 0.4, 0.0)
	_cov_y(cover, Vector3(R2X + 6.0, 0.0, R2Z - 5.0), 0.25, top, top + 2.2)


# ================================================================== R3 检修房
static func _workshop(root: Node3D, cover: Array, platforms: Array) -> void:
	var top := R3_Y
	_slab(root, cover, platforms, R3X, R3Z, R3HX, R3HZ, top, _M["conc"], _M["conc_dark"])
	# 北墙两扇卷帘门（大屋面层）
	for k in 2:
		_b(root, Vector3(3.6, 3.0, 0.12), Vector3(R3X - 4.0 + float(k) * 6.0, DECK_Y + 1.5, R3Z - R3HZ - 0.02),
			_M["door"])
		for j in 8:
			_b(root, Vector3(3.5, 0.06, 0.10), Vector3(R3X - 4.0 + float(k) * 6.0, DECK_Y + 0.45 + float(j) * 0.32,
				R3Z - R3HZ - 0.08), _M["metal_dark"])
	# 屋面：大断面风管（1.4 m，可站）
	_solid_box(root, cover, platforms, R3X - 1.0, R3Z + 3.5, 5.0, 1.0, top + 1.2, _M["metal"], top)
	_b(root, Vector3(10.2, 0.10, 2.1), Vector3(R3X - 1.0, top + 1.21, R3Z + 3.5), _M["metal_dark"])
	for k in 7:
		_b(root, Vector3(0.10, 1.1, 2.1), Vector3(R3X - 5.4 + float(k) * 1.5, top + 0.55, R3Z + 3.5),
			_M["metal_dark"])
	# 天窗
	_b(root, Vector3(3.2, 0.08, 2.4), Vector3(R3X + 4.0, top + 0.02, R3Z - 4.0), _M["glass"])
	# 水塔：四腿 + 罐体，底面离屋面 2.2 m（明显站不上去）
	for dx in [-1.5, 1.5]:
		for dz in [-1.5, 1.5]:
			_tube(root, Vector3(40.0 + dx, top, 9.5 + dz),
				Vector3(40.0 + dx, top + 2.2, 9.5 + dz), 0.11, _M["rust"])
			_cov_y(cover, Vector3(40.0 + dx, 0.0, 9.5 + dz), 0.16, top, top + 2.2)
	Kit.cylinder(root, 1.9 * U, 2.6 * U, Vector3(40.0, top + 3.5, 9.5) * U, _M["rust"], Vector3.ZERO)
	Kit.cylinder(root, 2.0 * U, 0.14 * U, Vector3(40.0, top + 4.84, 9.5) * U, _M["metal_dark"],
		Vector3.ZERO)
	_cov_y(cover, Vector3(40.0, 0.0, 9.5), 1.95, top, top + 4.9)


# ================================================================== 终点信标塔
static func _beacon(root: Node3D, cover: Array, platforms: Array) -> void:
	var top := F_Y
	_slab(root, cover, platforms, FX, FZ, FHX, FHZ, top, _M["conc"], _M["conc_dark"])
	_land_stripe(root, FX - FHX + 0.7, FZ - 2.4, FZ + 2.4, top)
	# 塔身：一圈竖缝 + 底部检修门
	for k in 6:
		_b(root, Vector3(0.10, top - DECK_Y - 0.6, 0.10), Vector3(FX - 2.4 + float(k) * 0.96,
			(DECK_Y + top) * 0.5 - 0.15, FZ - FHZ - 0.03), _M["metal_dark"])
	_b(root, Vector3(1.2, 2.0, 0.12), Vector3(FX - 1.0, DECK_Y + 1.0, FZ + FHZ + 0.02), _M["door"])
	# 西面（落点这一侧）：检修门 + 百叶 + 壁灯 + 竖向分缝
	_b(root, Vector3(0.12, 2.0, 1.4), Vector3(FX - FHX - 0.02, DECK_Y + 1.0, FZ), _M["door"])
	_b(root, Vector3(0.16, 0.10, 1.8), Vector3(FX - FHX - 0.06, DECK_Y + 2.10, FZ), _M["metal_dark"])
	_b(root, Vector3(0.08, 0.10, 0.10), Vector3(FX - FHX - 0.12, DECK_Y + 1.0, FZ - 0.55), _M["metal"])
	for k in 4:
		_b(root, Vector3(0.10, 0.08, 1.1), Vector3(FX - FHX - 0.05, DECK_Y + 2.50 + float(k) * 0.18,
			FZ - 1.6), _M["louvre"])
	for k in 3:
		_b(root, Vector3(0.10, top - DECK_Y - 0.7, 0.10), Vector3(FX - FHX - 0.03,
			(DECK_Y + top) * 0.5 - 0.1, FZ - 2.1 + float(k) * 2.1), _M["metal_dark"])
	_b(root, Vector3(0.34, 0.12, 0.22), Vector3(FX - FHX - 0.14, DECK_Y + 2.95, FZ + 1.8), _M["lamp"])
	_omni(root, Vector3(FX - FHX - 0.50, DECK_Y + 2.86, FZ + 1.8), Color(1.0, 0.70, 0.38), 1.2, 8.0, 0.3)
	# 顶部平台：护栏（1.55 m，翻不过去）
	var rail_y := top + 0.775
	# 顶栏加宽到 0.30 m，并登记可站台面：从设备箱（5.2）跳 0.55 m 就能上来
	_b(root, Vector3(6.0, 0.10, 0.30), Vector3(FX, top + 1.55, FZ - FHZ), _M["metal"])
	_b(root, Vector3(6.0, 0.10, 0.30), Vector3(FX, top + 1.55, FZ + FHZ), _M["metal"])
	_b(root, Vector3(0.30, 0.10, 6.0), Vector3(FX + FHX, top + 1.55, FZ), _M["metal"])
	for k in 5:
		var t := -3.0 + float(k) * 1.5
		_b(root, Vector3(0.08, 1.55, 0.08), Vector3(FX + t, rail_y, FZ - FHZ), _M["metal"])
		_b(root, Vector3(0.08, 1.55, 0.08), Vector3(FX + t, rail_y, FZ + FHZ), _M["metal"])
	_b(root, Vector3(0.08, 1.55, 0.08), Vector3(FX + FHX, rail_y, FZ + 1.5), _M["metal"])
	_b(root, Vector3(0.08, 1.55, 0.08), Vector3(FX + FHX, rail_y, FZ - 1.5), _M["metal"])
	_ring_y(cover, FX, FZ, FHX, FHZ, top, top + 1.15, 0.10, "w")
	# 顶栏台面（北/南/东三面，西侧开口）
	platforms.append({"c": Vector3(FX, 0.0, FZ - FHZ) * U,
		"hx": 3.0 * U, "hz": 0.15 * U, "h": (top + 1.55) * U})
	platforms.append({"c": Vector3(FX, 0.0, FZ + FHZ) * U,
		"hx": 3.0 * U, "hz": 0.15 * U, "h": (top + 1.55) * U})
	platforms.append({"c": Vector3(FX + FHX, 0.0, FZ) * U,
		"hx": 0.15 * U, "hz": 3.0 * U, "h": (top + 1.55) * U})
	# 设备箱（1.0 m，可站）
	_solid_box(root, cover, platforms, FX - 1.6, FZ + 1.4, 0.7, 0.6, top + 1.0, _M["hvac"], top)
	# 桅杆 + 航空障碍灯
	_tube(root, Vector3(FX + 1.4, top, FZ - 1.4), Vector3(FX + 1.4, top + 5.6, FZ - 1.4), 0.09, _M["metal"])
	for k in 3:
		var ty := top + 1.2 + float(k) * 1.6
		Kit.torus(root, 0.16 * U, 0.03 * U, Vector3(FX + 1.4, ty, FZ - 1.4) * U, _M["metal_dark"], 10)
	var lamp := Kit.cylinder(root, 0.20 * U, 0.34 * U, Vector3(FX + 1.4, top + 5.85, FZ - 1.4) * U,
		_M["beacon"], Vector3.ZERO)
	lamp.name = "BeaconLamp"
	_omni(root, Vector3(FX + 1.4, top + 5.9, FZ - 1.4), Color(1.0, 0.12, 0.06), 1.4, 14.0, 0.6)
	# 三条拉索
	for ang in [0.4, 2.4, 4.4]:
		Kit.cable(root, Vector3(FX + 1.4, top + 4.6, FZ - 1.4) * U,
			Vector3(FX + 1.4 + cos(ang) * 1.45, top, FZ - 1.4 + sin(ang) * 1.45) * U, 0.15 * U, 0.02 * U,
			_M["metal_dark"])
	# 屋面黄圈
	Kit.annulus(root, 1.15 * U, 1.35 * U, 48, (top + 0.02) * U, _M["paint"])


# ================================================================== 灯光
static func _lights(root: Node3D) -> void:
	# R1 南墙两盏钠灯（暖，照亮大屋面）
	for lx in [-22.0, -12.0]:
		_b(root, Vector3(0.62, 0.14, 0.30), Vector3(lx, DECK_Y + 3.5, R1Z + R1HZ + 0.18), _M["lamp"])
		_omni(root, Vector3(lx, DECK_Y + 3.35, R1Z + R1HZ + 0.75), Color(1.0, 0.66, 0.32), 2.6, 20.0, 0.45)
	# R3 北墙一盏冷白
	_b(root, Vector3(0.62, 0.14, 0.30), Vector3(R3X, DECK_Y + 3.6, R3Z - R3HZ - 0.18), _M["strip"])
	_omni(root, Vector3(R3X, DECK_Y + 3.45, R3Z - R3HZ - 0.75), Color(0.62, 0.82, 1.0), 2.2, 20.0, 0.45)
	# R2 门头一盏
	_b(root, Vector3(0.40, 0.12, 0.26), Vector3(R2X + R2HX + 0.20, DECK_Y + 2.5, R2Z + 2.0), _M["lamp"])
	_omni(root, Vector3(R2X + R2HX + 0.55, DECK_Y + 2.4, R2Z + 2.0), Color(1.0, 0.70, 0.38), 1.4, 10.0, 0.35)


# ================================================================== 屋面杂物
static func _roof_clutter(root: Node3D, cover: Array) -> void:
	# 沿女儿墙的桥架
	_tube(root, Vector3(DX0 + 1.2, DECK_Y + 0.35, DZ0 + 1.0), Vector3(DX1 - 1.2, DECK_Y + 0.35, DZ0 + 1.0),
		0.10, _M["metal"])
	for k in 26:
		_b(root, Vector3(0.08, 0.35, 0.30), Vector3(DX0 + 3.0 + float(k) * 4.0, DECK_Y + 0.17, DZ0 + 1.0),
			_M["metal_dark"])
	# 几根落地立管 + 弯头
	for k in 3:
		var px := 12.0 + float(k) * 9.0
		_tube(root, Vector3(px, DECK_Y, DZ1 - 1.4), Vector3(px, DECK_Y + 1.7, DZ1 - 1.4), 0.09, _M["rust"])
		Kit.cylinder(root, 0.14 * U, 0.22 * U, Vector3(px, DECK_Y + 1.78, DZ1 - 1.4) * U, _M["metal_dark"],
			Vector3.ZERO)
		_cov_y(cover, Vector3(px, 0.0, DZ1 - 1.4), 0.18, DECK_Y, DECK_Y + 1.8)
	# 检修竖梯（贴 R3 西墙）：两根立杆 + 沿 z 的横档
	for k in 9:
		_b(root, Vector3(0.06, 0.05, 0.56), Vector3(R3X - R3HX - 0.12, DECK_Y + 0.45 + float(k) * 0.34,
			R3Z + 6.0), _M["metal"])
	for dz in [-0.28, 0.28]:
		_b(root, Vector3(0.06, 3.5, 0.06), Vector3(R3X - R3HX - 0.12, DECK_Y + 1.75, R3Z + 6.0 + dz),
			_M["metal"])


# ================================================================== 碰撞工具
## 实心盒：四边侧墙（只到 top-0.3）+ 台面。base 是盒底（大屋面 18.0 或所在屋面）。
static func _solid_box(root: Node3D, cover: Array, platforms: Array, cx: float, cz: float,
		hx: float, hz: float, top: float, mat: Material, base := DECK_Y) -> void:
	_b(root, Vector3(hx * 2.0, top - base, hz * 2.0),
		Vector3(cx, (base + top) * 0.5, cz), mat)
	_ring_y(cover, cx, cz, hx, hz, base, top - 0.3)
	platforms.append({"c": Vector3(cx, 0.0, cz) * U,
		"hx": hx * U, "hz": hz * U, "h": top * U})


## 楼体 + 屋面板 + 一圈侧墙 + 台面
static func _slab(root: Node3D, cover: Array, platforms: Array, cx: float, cz: float,
		hx: float, hz: float, top: float, roof_mat: Material, body_mat: Material) -> void:
	_b(root, Vector3(hx * 2.0, top - 0.5 - DECK_Y, hz * 2.0),
		Vector3(cx, (DECK_Y + top - 0.5) * 0.5, cz), body_mat)
	_b(root, Vector3(hx * 2.0 + 0.5, 0.5, hz * 2.0 + 0.5),
		Vector3(cx, top - 0.25, cz), roof_mat)
	_ring_y(cover, cx, cz, hx, hz, DECK_Y, top - 0.3)
	platforms.append({"c": Vector3(cx, 0.0, cz) * U,
		"hx": hx * U, "hz": hz * U, "h": top * U})


## 不可站的高体块：只做侧墙（顶面高于跳跃高度时用）
static func _cov_box(cover: Array, cx: float, cz: float, hx: float, hz: float,
		base: float, top: float) -> void:
	_ring_y(cover, cx, cz, hx, hz, base, top - 0.3)


## 一圈侧墙：base…top，skip 可省掉某一边（"n"/"e"/"s"/"w"）
static func _ring_y(cover: Array, cx: float, cz: float, hx: float, hz: float,
		base: float, top: float, phys := 0.12, skip := "") -> void:
	if skip != "n":
		_chain_y(cover, Vector2(cx - hx, cz - hz), Vector2(cx + hx, cz - hz), phys, base, top)
	if skip != "e":
		_chain_y(cover, Vector2(cx + hx, cz - hz), Vector2(cx + hx, cz + hz), phys, base, top)
	if skip != "s":
		_chain_y(cover, Vector2(cx + hx, cz + hz), Vector2(cx - hx, cz + hz), phys, base, top)
	if skip != "w":
		_chain_y(cover, Vector2(cx - hx, cz + hz), Vector2(cx - hx, cz - hz), phys, base, top)


static func _chain_y(cover: Array, a: Vector2, b: Vector2, phys: float,
		base: float, top: float) -> void:
	var d := b - a
	var total := d.length()
	if total < 0.05:
		return
	d /= total
	var step := 0.40
	var n := int(ceil(total / step))
	for i in range(n + 1):
		var p: Vector2 = a + d * minf(float(i) * step, total)
		cover.append({"c": Vector3(p.x, base, p.y) * U, "r": phys * U + BALL,
			"h": maxf(0.05, top - base) * U, "cam": false})


static func _cov(cover: Array, c: Vector3, phys_r: float, h: float) -> void:
	cover.append({"c": c * U, "r": phys_r * U + BALL, "h": h * U, "cam": true})


static func _cov_y(cover: Array, c: Vector3, phys_r: float, base: float, top: float) -> void:
	cover.append({"c": Vector3(c.x, base, c.z) * U, "r": phys_r * U + BALL,
		"h": maxf(0.05, top - base) * U, "cam": true})


# ================================================================== 小工具
static func _b(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	return Kit.box(parent, size * U, pos * U, mat, rot)


static func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	Kit.tube(parent, a * U, b * U, radius * U, mat)


## 起跳边缘：黄黑相间的短块（沿 z 或 x）
static func _edge_band(root: Node3D, fixed: float, along_z: bool, a: float, b: float, top: float) -> void:
	var total := b - a
	var n := int(total / 0.9)
	for i in n:
		var t := a + 0.45 + float(i) * 0.9
		var pos := Vector3(fixed - 0.35, top + 0.015, t) if along_z else Vector3(t, top + 0.015, fixed - 0.35)
		var size := Vector3(0.70, 0.02, 0.44) if along_z else Vector3(0.44, 0.02, 0.70)
		_b(root, size, pos, _M["paint"] if i % 2 == 0 else _M["rubber"])


## 落点白线：提醒“这块能站”
static func _land_stripe(root: Node3D, x: float, z0: float, z1: float, top: float) -> void:
	_b(root, Vector3(0.34, 0.02, z1 - z0), Vector3(x, top + 0.015, (z0 + z1) * 0.5), _M["paint"])


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


## 米制虚线（Kit.dashed_line 收世界单位，这里统一乘 U）
static func _dash_m(parent: Node3D, a: Vector2, b: Vector2, width: float, dash: float,
		gap: float, y: float, mat: Material) -> void:
	var dir := b - a
	var total := dir.length()
	if total < 0.01:
		return
	dir /= total
	var n := int(total / (dash + gap))
	for i in n:
		var s := float(i) * (dash + gap) + dash * 0.5
		var c := a + dir * s
		Kit.box(parent, Vector3(dash, 0.02, width) * U, Vector3(c.x, y, c.y) * U, mat,
			Vector3(0.0, atan2(dir.y, dir.x), 0.0))

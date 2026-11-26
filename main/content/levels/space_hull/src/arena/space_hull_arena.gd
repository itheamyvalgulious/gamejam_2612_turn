extends RefCounted
## 轨道船背：飞船外壳第一稿（只做场景，不含敌人 / Boss / 音效）。
##
## 设计（2026-11-25 修订）：
##   一艘整体静止的大型飞船，路线在**抬高的背脊甲板**上，船壳在脚下 4 m。
##   不再用大转盘 / 空间站环，路线笔直，方便读距离和安排三段战斗。
##   实验室在船尾，船坞大门在船头；主角从炸开的实验室落到背脊甲板，
##   沿 190 m 的背脊打到船坞门口。
##
## 空间（真实米，交给 Kit 前乘 U）：
##   船壳：长 260 m、宽 44 m、高 36 m；壳顶 y=0。
##   背脊甲板：y=4.0，路线从 x=-8（实验室平台）到 x=190（船坞门）。
##   战斗 A x=0…30；桁架 1 x=30…80；战斗 B x=80…110；
##   桁架 2 x=110…160；战斗 C x=160…190。
##   桁架段是 6.8 / 8.0 m 宽的高架栈桥，中间有三处 3 m 断口，
##   掉下去会落到壳顶 y=0，由 main.gd 送回检查点。
##
## 防空门禁：
##   每段战斗区尽头有一对防空炮 + 一道红色光闸，炮的供电来自区内的供能节点。
##   初稿没有敌人，F8 直接切“全部断电”，用来预览清完怪、拆完节点后的通行状态。
##   实际流程（清完一波 → 按住 3 s 拆除）由主程序接，场景只留接口和模型。
##
## 碰撞约定（和船坞/楼顶一致）：
##   cover    = 竖直圆柱，侧面挡人；platforms = 轴对齐矩形台面，只能站。
##   甲板 / 栈桥台面在 y=4.0；所有可跳上的箱体都登记台面。
##   矮护栏（1.25 m）是可站的实体墙；漏斗墙 1.85 m，只挡不站。

const Kit := preload("res://src/arena/kit.gd")
const AAState := preload("res://space_hull/src/arena/space_aa.gd")
const U := 1.0 / 0.547
const BALL := 1.2

# ---------------- 主尺度 ----------------
const DECK_Y := 4.0
const HULL_CY := -18.0
const HULL_RY := 18.0
const HULL_RZ := 22.0
const HULL_X0 := -30.0
const HULL_X1 := 230.0
const SPAWN := Vector3(-3.0, DECK_Y, 0.0)
const SUN_DIR := Vector3(-0.55, 0.52, -0.65)

# ---------------- 路线 ----------------
const X_START0 := -8.0
const X_START1 := 0.0
const X_A1 := 30.0
const X_B0 := 80.0
const X_B1 := 110.0
const X_C0 := 160.0
const X_DOOR := 190.0

const G1 := 30.5
const G2 := 110.5
const G3 := 186.5

const GAPS1 := [[42.0, 45.0], [56.0, 59.0], [70.0, 73.0]]
const GAPS2 := [[122.0, 125.0], [136.0, 139.0], [150.0, 153.0]]

const W_START := 8.0
const W_A := 9.0
const W_T1 := 3.4
const W_B := 10.0
const W_T2 := 4.0
const W_C := 18.0

static var _M := {}


static func build(origin := Vector3.ZERO) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arena_space_hull"
	root.position = origin

	_mats()
	var walls: Array = []
	var cover: Array = []
	var platforms: Array = []
	var gates: Array = []
	# 三段各自一套防空/供能状态：拆 A 段节点只关 A 段光闸
	var aa1 := AAState.new()
	aa1.name = "AA1"
	root.add_child(aa1)
	var aa2 := AAState.new()
	aa2.name = "AA2"
	root.add_child(aa2)
	var aa3 := AAState.new()
	aa3.name = "AA3"
	root.add_child(aa3)

	_environment(root)
	_hull(root)
	_hull_details(root)
	_deck(root, platforms)
	_bulwarks(root, cover, platforms)
	_lab(root, cover)
	_arena_a(root, cover, platforms)
	_arena_b(root, cover, platforms)
	_arena_c(root, cover, platforms)

	# 三道防空门禁 + 三个供能节点，各自独立
	_aa_turret(aa1, cover, platforms, 28.0, -6.0, Vector3(38.0, DECK_Y, -6.0))
	_aa_turret(aa1, cover, platforms, 28.0, 6.0, Vector3(38.0, DECK_Y, 6.0))
	_gate(root, aa1, cover, platforms, gates, G1, -4.4, 4.4)
	_power_node(aa1, cover, platforms, 24.0, -6.0, 1.0, Vector3(28.0, DECK_Y, -6.0), Vector3(28.0, DECK_Y, 6.0))

	_aa_turret(aa2, cover, platforms, 107.5, -6.5, Vector3(117.5, DECK_Y, -6.5))
	_aa_turret(aa2, cover, platforms, 107.5, 6.5, Vector3(117.5, DECK_Y, 6.5))
	_gate(root, aa2, cover, platforms, gates, G2, -5.0, 5.0)
	_power_node(aa2, cover, platforms, 104.0, 6.0, -1.0, Vector3(107.5, DECK_Y, 6.5), Vector3(107.5, DECK_Y, -6.5))

	_aa_turret(aa3, cover, platforms, 184.0, -16.0, Vector3(192.0, DECK_Y, -22.0))
	_aa_turret(aa3, cover, platforms, 184.0, 16.0, Vector3(192.0, DECK_Y, 22.0))
	_gate(root, aa3, cover, platforms, gates, G3, -17.2, 17.2)
	_power_node(aa3, cover, platforms, 184.0, -13.0, 1.0, Vector3(184.0, DECK_Y, -16.0), Vector3(184.0, DECK_Y, 16.0))

	_hangar_block(root, cover)
	_lights(root, cover)

	var bounds := AABB(
		Vector3(-60.0, 0.0, -60.0) * U,
		Vector3(340.0, 90.0, 120.0) * U)

	var spawn := Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), SPAWN * U)

	return {
		"node": root,
		"kind": "space_hull",
		"name_cn": "轨道船背",
		"hint": "从炸开的实验室沿船背推进；清完每段，拆掉供能节点，再穿过防空光闸。",
		"floor_y": DECK_Y,
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
		"aa_states": [aa1, aa2, aa3],
		"gates": gates,
		"nodes": [
			{"x": 24.0, "z": -6.0, "state": aa1},
			{"x": 104.0, "z": 6.0, "state": aa2},
			{"x": 184.0, "z": -13.0, "state": aa3},
		],
		"checkpoints": [
			{"x": -3.0, "z": 0.0},
			{"x": 35.0, "z": 0.0},
			{"x": 80.0, "z": 0.0},
			{"x": 115.0, "z": 0.0},
			{"x": 160.0, "z": 0.0},
		],
	}


# ================================================================== 材质
static func _mats() -> void:
	_M = {
		# 甲板：冷灰防滑涂层，不反光，避免一整片“停车场”
		"deck": Kit.std(Color(0.175, 0.185, 0.198), 0.88, 0.14,
			{"noise": 5.0, "grime": 0.42, "bump": 0.24, "streak": 0.14,
			"dirt": Color(0.028, 0.032, 0.038)}),
		"deck_panel": Kit.std(Color(0.215, 0.225, 0.238), 0.82, 0.18,
			{"noise": 6.0, "grime": 0.38, "bump": 0.20, "streak": 0.16}),
		"deck_panel2": Kit.std(Color(0.145, 0.155, 0.168), 0.86, 0.16,
			{"noise": 7.0, "grime": 0.44, "bump": 0.22, "streak": 0.20}),
		"deck_dark": Kit.std(Color(0.075, 0.082, 0.092), 0.90, 0.18,
			{"noise": 9.0, "grime": 0.36, "bump": 0.18, "streak": 0.24}),
		"seam": Kit.std(Color(0.038, 0.043, 0.050), 0.92, 0.12,
			{"noise": 12.0, "grime": 0.30, "bump": 0.10}),
		"armor": Kit.std(Color(0.245, 0.260, 0.278), 0.66, 0.22,
			{"noise": 4.0, "grime": 0.34, "bump": 0.18, "streak": 0.22}),
		"armor_light": Kit.std(Color(0.405, 0.420, 0.432), 0.68, 0.18,
			{"noise": 3.4, "grime": 0.30, "bump": 0.14, "streak": 0.18}),
		"hull": Kit.std(Color(0.285, 0.300, 0.318), 0.58, 0.30,
			{"noise": 4.0, "grime": 0.32, "bump": 0.14, "streak": 0.18}),
		"hull_light": Kit.std(Color(0.440, 0.455, 0.465), 0.62, 0.22,
			{"noise": 3.2, "grime": 0.28, "bump": 0.12}),
		"hull_dark": Kit.std(Color(0.098, 0.106, 0.118), 0.66, 0.26,
			{"noise": 6.0, "grime": 0.34, "bump": 0.16}),
		"under": Kit.std(Color(0.108, 0.118, 0.130), 0.80, 0.20,
			{"noise": 6.0, "grime": 0.44, "bump": 0.18, "streak": 0.28}),
		"truss": Kit.std(Color(0.205, 0.216, 0.228), 0.56, 0.42,
			{"noise": 3.0, "grime": 0.28, "bump": 0.10}),
		"steel": Kit.std(Color(0.330, 0.342, 0.354), 0.50, 0.44,
			{"noise": 3.0, "grime": 0.22, "bump": 0.10}),
		"steel_dark": Kit.std(Color(0.125, 0.134, 0.145), 0.62, 0.34,
			{"noise": 4.0, "grime": 0.30, "bump": 0.12}),
		"cable": Kit.std(Color(0.038, 0.041, 0.045), 0.86, 0.10,
			{"noise": 10.0, "grime": 0.18, "bump": 0.14}),
		"rubber": Kit.std(Color(0.028, 0.030, 0.033), 0.94, 0.0,
			{"noise": 8.0, "grime": 0.12, "bump": 0.18}),
		"paint": Kit.std(Color(0.680, 0.480, 0.070), 0.78, 0.0,
			{"noise": 5.0, "grime": 0.40, "bump": 0.14, "streak": 0.30}),
		"hazard_y": Kit.std(Color(0.720, 0.530, 0.055), 0.74, 0.08,
			{"noise": 6.0, "grime": 0.32, "bump": 0.12}),
		"hazard_k": Kit.std(Color(0.040, 0.042, 0.045), 0.88, 0.08,
			{"noise": 8.0, "grime": 0.18, "bump": 0.10}),
		"gold": Kit.std(Color(0.360, 0.250, 0.080), 0.58, 0.35,
			{"noise": 4.0, "grime": 0.48, "bump": 0.16, "streak": 0.30}),
		"radiator": Kit.std(Color(0.470, 0.480, 0.478), 0.70, 0.12,
			{"noise": 5.0, "grime": 0.40, "bump": 0.14, "streak": 0.22}),
		"radiator_dark": Kit.std(Color(0.090, 0.098, 0.108), 0.76, 0.16,
			{"noise": 7.0, "grime": 0.32, "bump": 0.14}),
		"vent": Kit.std(Color(0.050, 0.055, 0.062), 0.82, 0.20,
			{"noise": 14.0, "grime": 0.24, "bump": 0.18}),
		"label": Kit.std(Color(0.620, 0.620, 0.580), 0.80, 0.0,
			{"noise": 3.0, "grime": 0.46, "bump": 0.08, "streak": 0.34}),
		"glass": Kit.glass(Color(0.10, 0.19, 0.25), 0.30),
		"node_glass": Kit.glass(Color(0.30, 0.50, 0.65), 0.12),
		"window_cool": Kit.emissive(Color(0.55, 0.78, 1.0), 1.2, 0.18),
		"window_warm": Kit.emissive(Color(1.0, 0.78, 0.48), 0.9, 0.18),
		"strip": Kit.emissive(Color(0.30, 0.84, 0.98), 1.25, 0.16),
		"strip_warm": Kit.emissive(Color(1.0, 0.66, 0.28), 1.35, 0.16),
		"amber": Kit.emissive(Color(1.0, 0.56, 0.10), 1.8, 0.14),
		"red": Kit.emissive(Color(1.0, 0.10, 0.06), 2.1, 0.14),
		"green": Kit.emissive(Color(0.22, 1.0, 0.38), 1.6, 0.14),
		"white": Kit.emissive(Color(0.92, 0.96, 1.0), 1.8, 0.14),
		"engine": Kit.emissive(Color(0.28, 0.60, 1.0), 3.8, 0.10),
		"core_on": Kit.emissive(Color(1.0, 0.44, 0.08), 2.6, 0.14),
		"lamp_dim": Kit.emissive(Color(0.34, 0.55, 0.72), 0.45, 0.30),
		"off": Kit.std(Color(0.062, 0.068, 0.076), 0.86, 0.18,
			{"noise": 7.0, "grime": 0.30, "bump": 0.12}),
		"off_green": Kit.emissive(Color(0.16, 0.82, 0.32), 0.8, 0.16),
		"screen": Kit.emissive(Color(1.0, 0.55, 0.12), 1.2, 0.12),
		"screen_ok": Kit.emissive(Color(0.18, 1.0, 0.42), 1.0, 0.12),
		"soot": Kit.std(Color(0.020, 0.019, 0.018), 0.98, 0.0,
			{"noise": 12.0, "grime": 0.08, "bump": 0.16}),
	}
	# 节点玻璃：Kit.glass 默认带金属反射，近看会变成黑筒；这里改成无金属、低不透明度
	var ng: StandardMaterial3D = _M["node_glass"]
	ng.metallic = 0.0
	ng.roughness = 0.20


# ================================================================== 环境
static func _environment(root: Node3D) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://space_hull/src/arena/space_sky.gdshader")
	sm.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	sm.set_shader_parameter("sun_color", Color(1.0, 0.96, 0.86))
	sky.sky_material = sm

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.105, 0.150, 0.230)
	env.ambient_light_energy = 0.78
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.tonemap_white = 3.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.02

	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.7
	env.ssao_power = 1.7
	env.fog_enabled = false

	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 2.70
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 230.0 * U
	root.add_child(sun)
	# 太阳在玩家背后偏左上：正面看船头，受光面朝向玩家
	sun.look_at_from_position(Vector3.ZERO, -SUN_DIR.normalized(), Vector3.UP)

	# 地球反照：从下方补冷光，不投影
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.34, 0.54, 0.92)
	fill.light_energy = 0.42
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.shadow_enabled = false
	root.add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.38, 1.0, -0.22).normalized(), Vector3.FORWARD)

	# 正面冷补光：把实验室 +X 面、舱体外侧和背光面从纯黑里拉出来
	var front := DirectionalLight3D.new()
	front.light_color = Color(0.38, 0.52, 0.78)
	front.light_energy = 0.32
	front.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	front.shadow_enabled = false
	root.add_child(front)
	front.look_at_from_position(Vector3.ZERO, Vector3(-1.0, -0.10, 0.16).normalized(), Vector3.UP)

	_earth(root)


static func _earth(root: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://space_hull/src/arena/earth.gdshader")
	mat.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	mat.set_shader_parameter("ocean_color", Color(0.018, 0.060, 0.155))
	mat.set_shader_parameter("land_color", Color(0.075, 0.125, 0.070))
	mat.set_shader_parameter("desert_color", Color(0.285, 0.225, 0.135))
	mat.set_shader_parameter("cloud_color", Color(0.820, 0.855, 0.870))
	mat.set_shader_parameter("atmo_color", Color(0.180, 0.400, 0.860))

	var sphere := SphereMesh.new()
	sphere.radius = 450.0 * U
	sphere.height = 900.0 * U
	sphere.radial_segments = 96
	sphere.rings = 48
	var mi := MeshInstance3D.new()
	mi.name = "Earth"
	mi.mesh = sphere
	mi.material_override = mat
	mi.position = Vector3(850.0, -450.0, -300.0) * U
	# 把极轴转到侧面：玩家从船背看到的是中纬度海陆，而不是一整个白色极冠
	mi.rotation = Vector3(0.28, 0.0, 1.12)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ================================================================== 船壳
static func _hull(root: Node3D) -> void:
	# 主船体：一根 260 m 长的扁椭圆柱，壳顶正好在 y=0
	var cm := CylinderMesh.new()
	cm.top_radius = HULL_RZ * U
	cm.bottom_radius = HULL_RZ * U
	cm.height = (HULL_X1 - HULL_X0) * U
	cm.radial_segments = 32
	cm.rings = 1
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = cm
	hull.material_override = _M["hull"]
	hull.position = Vector3((HULL_X0 + HULL_X1) * 0.5, HULL_CY, 0.0) * U
	hull.rotation = Vector3(0.0, 0.0, PI * 0.5)
	hull.scale = Vector3(HULL_RY / HULL_RZ, 1.0, 1.0)
	root.add_child(hull)

	# 船头：锥形艏段
	var bow_mesh := CylinderMesh.new()
	bow_mesh.top_radius = 0.6 * U
	bow_mesh.bottom_radius = HULL_RZ * U
	bow_mesh.height = 52.0 * U
	bow_mesh.radial_segments = 32
	bow_mesh.rings = 1
	var bow := MeshInstance3D.new()
	bow.name = "Bow"
	bow.mesh = bow_mesh
	bow.material_override = _M["hull"]
	bow.position = Vector3(246.0, HULL_CY, 0.0) * U
	bow.rotation = Vector3(0.0, 0.0, -PI * 0.5)
	bow.scale = Vector3(HULL_RY / HULL_RZ, 1.0, 1.0)
	root.add_child(bow)

	# 船尾端面
	var stern_mesh := CylinderMesh.new()
	stern_mesh.top_radius = HULL_RZ * U
	stern_mesh.bottom_radius = HULL_RZ * U
	stern_mesh.height = 1.6 * U
	stern_mesh.radial_segments = 32
	var stern := MeshInstance3D.new()
	stern.name = "Stern"
	stern.mesh = stern_mesh
	stern.material_override = _M["hull_dark"]
	stern.position = Vector3(HULL_X0 - 0.8, HULL_CY, 0.0) * U
	stern.rotation = Vector3(0.0, 0.0, PI * 0.5)
	stern.scale = Vector3(HULL_RY / HULL_RZ, 1.0, 1.0)
	root.add_child(stern)

	# 四个主推进器
	for zz in [-14.0, -6.0, 6.0, 14.0]:
		_engine_bell(root, Vector3(HULL_X0 - 1.0, -9.0, zz))

	# 背脊甲板的承力龙骨：两条贯穿全船的箱梁
	for zz in [-5.2, 5.2]:
		_b(root, Vector3(250.0, 0.7, 0.7), Vector3(90.0, 0.2, zz), _M["truss"])
	# 壳顶两条主管线
	for zz in [-2.4, 2.4]:
		_tube(root, Vector3(-24.0, 0.28, zz), Vector3(224.0, 0.28, zz), 0.18, _M["steel_dark"])


static func _hull_y(z: float) -> float:
	var k := clampf(absf(z) / HULL_RZ, 0.0, 1.0)
	return HULL_CY + HULL_RY * sqrt(maxf(0.0, 1.0 - k * k))


static func _engine_bell(root: Node3D, p: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.3 * U
	mesh.bottom_radius = 1.25 * U
	mesh.height = 6.0 * U
	mesh.radial_segments = 20
	var bell := MeshInstance3D.new()
	bell.mesh = mesh
	bell.material_override = _M["steel_dark"]
	bell.position = p * U
	bell.rotation = Vector3(0.0, 0.0, PI * 0.5)
	root.add_child(bell)
	# 喷口内的蓝光
	var glow := SphereMesh.new()
	glow.radius = 1.05 * U
	glow.height = 2.1 * U
	glow.radial_segments = 16
	glow.rings = 8
	var gm := MeshInstance3D.new()
	gm.mesh = glow
	gm.material_override = _M["engine"]
	gm.position = (p + Vector3(-2.6, 0.0, 0.0)) * U
	root.add_child(gm)


static func _hull_details(root: Node3D) -> void:
	# 横向加强筋：贴着椭圆壳面
	for zz in [-12.4, -15.0, -19.5, -21.4, 12.4, 15.0, 19.5, 21.4]:
		var yy := _hull_y(zz) + 0.04
		_b(root, Vector3(258.0, 0.20, 0.20), Vector3(100.0, yy, zz), _M["steel_dark"])
	# 竖向板缝：每条带三段
	for xx in range(-24, 231, 8):
		for zz in [-15.0, -19.5, -21.4, 15.0, 19.5, 21.4]:
			var yy := _hull_y(zz) + 0.04
			_b(root, Vector3(0.13, 2.4, 0.13), Vector3(float(xx), yy + 1.1, zz), _M["seam"])
	# 上侧装甲板
	for xx in range(-12, 221, 24):
		for zz in [-17.2, 17.2]:
			var yy := _hull_y(zz) + 0.05
			_b(root, Vector3(10.0, 3.0, 0.16), Vector3(float(xx), yy + 1.2, zz), _M["armor"])
			_b(root, Vector3(9.6, 0.06, 0.18), Vector3(float(xx), yy + 2.7, zz), _M["seam"])
	# 侧舷窗
	for xx in [-6.0, 18.0, 44.0, 68.0, 96.0, 124.0, 152.0, 178.0, 202.0]:
		for zz in [-18.85, 18.85]:
			var yy := _hull_y(zz) + 0.35
			_b(root, Vector3(1.5, 0.46, 0.12), Vector3(xx, yy, zz), _M["window_cool"])
			_b(root, Vector3(1.9, 0.16, 0.16), Vector3(xx, yy + 0.34, zz), _M["hull_dark"])
	# 壳顶检修走道：低一层，给背脊甲板提供“下面还有东西”的层次
	for zz in [-8.0, 8.0]:
		var yy := _hull_y(zz) + 0.12
		_b(root, Vector3(244.0, 0.16, 1.4), Vector3(100.0, yy, zz), _M["under"])
		for xx in range(-18, 219, 12):
			_b(root, Vector3(0.10, 0.85, 0.10), Vector3(float(xx), yy + 0.5, zz), _M["steel_dark"])
		_b(root, Vector3(244.0, 0.06, 0.06), Vector3(100.0, yy + 0.92, zz), _M["steel_dark"])
	# 壳顶大舱盖
	for xx in [-4.0, 26.0, 58.0, 88.0, 118.0, 148.0, 178.0, 208.0]:
		_cyl(root, 2.0, 0.18, Vector3(xx, _hull_y(0.0) + 0.10, 0.0), _M["hull_dark"])
		_torus(root, 2.0, 0.10, Vector3(xx, _hull_y(0.0) + 0.20, 0.0), _M["steel_dark"], Vector3.ZERO, 32)
	# 散热翼：两侧各三片
	for side in [-1.0, 1.0]:
		for k in 3:
			var px := 48.0 + float(k) * 8.0
			var pz: float = side * (28.0 + float(k) * 2.6)
			_b(root, Vector3(14.0, 11.0, 0.22), Vector3(px, -12.0, pz), _M["radiator"])
			# 面板格栅
			for gy in range(-7, 6, 2):
				_b(root, Vector3(13.4, 0.08, 0.26), Vector3(px, float(gy) - 12.0, pz - side * 0.02), _M["radiator_dark"])
			for gx in [-4.0, 0.0, 4.0]:
				_b(root, Vector3(0.08, 10.4, 0.26), Vector3(px + gx, -12.0, pz), _M["radiator_dark"])
			# 与船体的连接臂
			_tube(root, Vector3(px, -8.0, side * 19.0), Vector3(px, -8.0, pz - side * 0.2), 0.24, _M["truss"])
			_tube(root, Vector3(px, -16.0, side * 20.0), Vector3(px, -16.0, pz - side * 0.2), 0.20, _M["truss"])
	# 侧面挂载舱
	_module_cyl(root, Vector3(34.0, -25.0, -30.0), 6.0, 20.0, _M["hull"])
	_module_cyl(root, Vector3(122.0, -24.0, 33.0), 5.0, 18.0, _M["hull"])
	_module_cyl(root, Vector3(158.0, -43.0, -8.0), 7.0, 16.0, _M["hull_dark"])
	# 船头两侧的天线阵
	for side in [-1.0, 1.0]:
		_antenna(root, Vector3(214.0, 0.0, side * 16.0), 13.0)
	# 船尾的系缆/拖曳环
	for zz in [-10.0, 10.0]:
		_torus(root, 1.6, 0.22, Vector3(-33.0, -12.0, zz), _M["steel_dark"], Vector3(0.0, 0.0, PI * 0.5), 24)


static func _module_cyl(root: Node3D, p: Vector3, radius: float, length: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * U
	mesh.bottom_radius = radius * U
	mesh.height = length * U
	mesh.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = p * U
	mi.rotation = Vector3(0.0, 0.0, PI * 0.5)
	root.add_child(mi)
	# 端环 + 侧窗
	for xx in [-0.42, 0.0, 0.42]:
		_torus(root, radius * 0.98, 0.18, p + Vector3(length * xx, 0.0, 0.0), _M["steel_dark"], Vector3(0.0, 0.0, PI * 0.5), 28)
	for xx in [-0.24, 0.0, 0.24]:
		_b(root, Vector3(1.6, 0.46, 0.12), p + Vector3(length * xx, 0.0, radius * 0.98), _M["window_warm"])
		_b(root, Vector3(1.6, 0.46, 0.12), p + Vector3(length * xx, 0.0, -radius * 0.98), _M["window_warm"])
	# 连接臂
	_tube(root, p + Vector3(-length * 0.3, 0.0, 0.0), Vector3(p.x - length * 0.3, -4.0, p.z * 0.45), 0.30, _M["truss"])
	_tube(root, p + Vector3(length * 0.3, 0.0, 0.0), Vector3(p.x + length * 0.3, -4.0, p.z * 0.45), 0.30, _M["truss"])


static func _antenna(root: Node3D, base: Vector3, h: float) -> void:
	_tube(root, base, base + Vector3(0.0, h, 0.0), 0.16, _M["steel_dark"])
	for k in 3:
		var yy := h * (0.45 + float(k) * 0.18)
		_b(root, Vector3(2.6, 0.08, 0.08), base + Vector3(0.0, yy, 0.0), _M["steel_dark"])
	# 小碟
	var dish := CylinderMesh.new()
	dish.top_radius = 1.4 * U
	dish.bottom_radius = 1.4 * U
	dish.height = 0.18 * U
	dish.radial_segments = 20
	var dm := MeshInstance3D.new()
	dm.mesh = dish
	dm.material_override = _M["steel"]
	dm.position = (base + Vector3(0.0, h + 0.2, 0.0)) * U
	dm.rotation = Vector3(0.22, 0.0, 0.0)
	root.add_child(dm)
	_b(root, Vector3(0.10, 0.10, 0.10), base + Vector3(0.0, h + 0.55, 0.55), _M["red"])


# ================================================================== 甲板
static func _deck(root: Node3D, platforms: Array) -> void:
	_deck_seg(root, platforms, X_START0, X_START1, -W_START, W_START, -2.0, "start")
	_deck_seg(root, platforms, X_START1, X_A1, -W_A, W_A, -2.0, "A")
	_deck_gaps(root, platforms, X_A1, X_B0, -W_T1, W_T1, GAPS1)
	_deck_seg(root, platforms, X_B0, X_B1, -W_B, W_B, -2.6, "B")
	_deck_gaps(root, platforms, X_B1, X_C0, -W_T2, W_T2, GAPS2)
	_deck_seg(root, platforms, X_C0, X_DOOR, -W_C, W_C, -9.0, "C")


static func _deck_seg(root: Node3D, platforms: Array, x0: float, x1: float,
		z0: float, z1: float, side_bottom: float, tag: String) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var dx := x1 - x0
	var dz := z1 - z0
	# 甲板面
	_b(root, Vector3(dx, 0.40, dz), Vector3(cx, DECK_Y - 0.20, cz), _M["deck"])
	platforms.append({"c": Vector3(cx, 0.0, cz) * U,
		"hx": dx * 0.5 * U, "hz": dz * 0.5 * U, "h": DECK_Y * U})
	# 甲板下的承力箱体
	_b(root, Vector3(dx, DECK_Y - 0.40, dz), Vector3(cx, (DECK_Y - 0.40) * 0.5, cz), _M["under"])
	# 两侧侧壁（宽甲板向下包到船壳）
	var wall_h := (DECK_Y - 0.40) - side_bottom
	for zz in [z0, z1]:
		_b(root, Vector3(dx, wall_h, 0.50), Vector3(cx, side_bottom + wall_h * 0.5, zz), _M["under"])
		for xx in range(int(x0) + 2, int(x1), 6):
			_b(root, Vector3(0.36, wall_h - 0.2, 0.62), Vector3(float(xx), side_bottom + wall_h * 0.5, zz), _M["steel_dark"])
	# 甲板面板 + 板缝 + 边灯
	_deck_panels(root, x0, x1, z0, z1, 4.0)
	_deck_trim(root, x0, x1, z0, z1)
	# 底部斜撑：甲板边缘 → 船壳
	for xx in range(int(x0) + 4, int(x1), 10):
		for side in [-1.0, 1.0]:
			_tube(root, Vector3(float(xx), DECK_Y - 0.7, side * (absf(z0) - 0.4)),
				Vector3(float(xx) + 3.0, 0.2, side * (absf(z0) - 4.0)), 0.20, _M["truss"])
	# 支撑立柱
	for xx in range(int(x0) + 4, int(x1), 8):
		for side in [-1.0, 1.0]:
			var zz: float = side * (absf(z0) - 1.2)
			_b(root, Vector3(0.42, DECK_Y - 0.5, 0.42), Vector3(float(xx), (DECK_Y - 0.5) * 0.5, zz), _M["truss"])
	if tag != "":
		root.set_meta("deck_" + tag, true)


static func _deck_gaps(root: Node3D, platforms: Array, x0: float, x1: float,
		z0: float, z1: float, gaps: Array) -> void:
	var cursor := x0
	for g in gaps:
		var ga: float = g[0]
		var gb: float = g[1]
		if ga > cursor:
			_catwalk_seg(root, platforms, cursor, ga, z0, z1)
			_gap_edge(root, ga, z0, z1, -1.0)
		_gap_edge(root, gb, z0, z1, 1.0)
		cursor = gb
	if cursor < x1:
		_catwalk_seg(root, platforms, cursor, x1, z0, z1)


static func _catwalk_seg(root: Node3D, platforms: Array, x0: float, x1: float,
		z0: float, z1: float) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var dx := x1 - x0
	var dz := z1 - z0
	_b(root, Vector3(dx, 0.36, dz), Vector3(cx, DECK_Y - 0.18, cz), _M["deck"])
	platforms.append({"c": Vector3(cx, 0.0, cz) * U,
		"hx": dx * 0.5 * U, "hz": dz * 0.5 * U, "h": DECK_Y * U})
	_deck_panels(root, x0, x1, z0, z1, 2.4)
	# 中央格栅
	var gz := 1.6
	_b(root, Vector3(dx - 0.2, 0.006, gz), Vector3(cx, DECK_Y + 0.010, cz), _M["deck_dark"])
	for xx in range(int(x0) + 1, int(x1), 1):
		_b(root, Vector3(0.06, 0.006, gz), Vector3(float(xx) + 0.5, DECK_Y + 0.017, cz), _M["steel_dark"])
	_deck_trim(root, x0, x1, z0, z1)
	# 栈桥的深桁架：4 m 高，下面能直接看到船壳
	for zz in [z0 + 0.35, z1 - 0.35]:
		_b(root, Vector3(dx, 1.05, 0.42), Vector3(cx, 2.4, zz), _M["truss"])
		_b(root, Vector3(dx, 0.30, 0.30), Vector3(cx, 0.36, zz * 0.62), _M["truss"])
	for xx in range(int(x0) + 2, int(x1), 4):
		_b(root, Vector3(0.32, 0.32, dz - 0.4), Vector3(float(xx), 2.4, cz), _M["truss"])
		_tube(root, Vector3(float(xx), 3.55, z0 + 0.35), Vector3(float(xx) + 2.0, 0.36, 0.0), 0.13, _M["truss"])
		_tube(root, Vector3(float(xx) + 2.0, 3.55, z1 - 0.35), Vector3(float(xx), 0.36, 0.0), 0.13, _M["truss"])
	for xx in range(int(x0) + 2, int(x1), 8):
		_b(root, Vector3(0.34, 3.6, 0.34), Vector3(float(xx), 2.0, cz), _M["truss"])
	# 门架：每 10 m 一道，给栈桥尺度
	for xx in range(int(x0) + 5, int(x1), 10):
		var h := 6.2
		for side in [-1.0, 1.0]:
			_b(root, Vector3(0.44, h, 0.44), Vector3(float(xx), DECK_Y + h * 0.5, side * (absf(z0) - 0.15)), _M["steel_dark"])
		_b(root, Vector3(0.34, 0.34, dz + 0.3), Vector3(float(xx), DECK_Y + h, cz), _M["steel_dark"])
		_b(root, Vector3(0.10, 0.10, dz - 0.5), Vector3(float(xx), DECK_Y + h - 0.25, cz), _M["strip"])


static func _deck_panels(root: Node3D, x0: float, x1: float, z0: float, z1: float,
		cell: float) -> void:
	var x := x0 + 0.08
	var ix := 0
	while x < x1 - 0.10:
		var xe := minf(x + cell - 0.16, x1 - 0.08)
		var z := z0 + 0.08
		var iz := 0
		while z < z1 - 0.10:
			var ze := minf(z + cell - 0.16, z1 - 0.08)
			var mat: Material = _M["deck_panel"] if (ix + iz) % 2 == 0 else _M["deck_panel2"]
			_b(root, Vector3(xe - x, 0.006, ze - z), Vector3((x + xe) * 0.5, DECK_Y + 0.004, (z + ze) * 0.5), mat)
			z = ze + 0.16
			iz += 1
		x = xe + 0.16
		ix += 1


static func _deck_trim(root: Node3D, x0: float, x1: float, z0: float, z1: float) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var dx := x1 - x0
	var dz := z1 - z0
	for xx in range(int(x0) + 2, int(x1), 4):
		_b(root, Vector3(0.07, 0.004, dz - 0.2), Vector3(float(xx), DECK_Y + 0.002, cz), _M["seam"])
	# 两条边灯
	for zz in [z0 + 0.42, z1 - 0.42]:
		for xx in range(int(x0) + 1, int(x1), 4):
			_b(root, Vector3(0.12, 0.05, 0.85), Vector3(float(xx) + 1.5, DECK_Y + 0.03, zz), _M["strip"])
	# 中线黄色虚线（仅宽甲板）
	if dz > 10.0:
		_dash_m(root, Vector2(x0 + 1.0, 0.0), Vector2(x1 - 1.0, 0.0), 0.20, 1.6, 2.6, DECK_Y + 0.015, _M["paint"])


static func _gap_edge(root: Node3D, x: float, z0: float, z1: float, facing: float) -> void:
	# 断口两侧的黄黑条 + 红色警示灯
	var cz := (z0 + z1) * 0.5
	var dz := z1 - z0
	var bx := x + facing * 0.45
	_b(root, Vector3(0.90, 0.06, dz), Vector3(bx, DECK_Y + 0.03, cz), _M["hazard_k"])
	for i in int(dz / 0.9):
		var zz := z0 + 0.45 + float(i) * 0.9
		_b(root, Vector3(0.86, 0.07, 0.44), Vector3(bx, DECK_Y + 0.035, zz), _M["hazard_y"])
	for side in [-1.0, 1.0]:
		_b(root, Vector3(0.18, 0.18, 0.18), Vector3(x + facing * 0.55, DECK_Y + 0.20, side * (absf(z0) - 0.55)), _M["red"])
	# 断口下的横梁，给“下面是船壳”一点层次
	_b(root, Vector3(0.34, 0.34, dz), Vector3(x, 1.4, cz), _M["truss"])


# ================================================================== 护栏 / 漏斗
static func _bulwarks(root: Node3D, cover: Array, platforms: Array) -> void:
	# 起始平台两侧
	_bulwark(root, cover, platforms, X_START0, X_START1, -W_START + 0.25, -1.0, 1.25)
	_bulwark(root, cover, platforms, X_START0, X_START1, W_START - 0.25, 1.0, 1.25)
	# 战斗 A：护墙延长到 29.5，漏斗墙只收最后 0.5 m；x=28 的炮塔整体在墙前
	_bulwark(root, cover, platforms, 0.0, 29.5, -W_A + 0.25, -1.0, 1.25)
	_bulwark(root, cover, platforms, 0.0, 29.5, W_A - 0.25, 1.0, 1.25)
	_funnel_wall(root, cover, platforms, Vector2(29.5, -W_A + 0.25), Vector2(30.0, -W_T1 - 0.15), 0.95)
	_funnel_wall(root, cover, platforms, Vector2(29.5, W_A - 0.25), Vector2(30.0, W_T1 + 0.15), 0.95)
	# 桁架 1：按断口分段
	_bulwark_runs(root, cover, platforms, 30.0, 80.0, W_T1, GAPS1)
	# 战斗 B：护墙延长到 108.5，漏斗墙后移，避开 x=107.5 的炮塔
	_bulwark(root, cover, platforms, 80.0, 108.5, -W_B + 0.25, -1.0, 1.25)
	_bulwark(root, cover, platforms, 80.0, 108.5, W_B - 0.25, 1.0, 1.25)
	_funnel_wall(root, cover, platforms, Vector2(108.5, -W_B + 0.25), Vector2(110.0, -W_T2 - 0.15), 0.95)
	_funnel_wall(root, cover, platforms, Vector2(108.5, W_B - 0.25), Vector2(110.0, W_T2 + 0.15), 0.95)
	# 桁架 2
	_bulwark_runs(root, cover, platforms, 110.0, 160.0, W_T2, GAPS2)
	# 战斗 C + 大门前
	_bulwark(root, cover, platforms, 160.0, 190.0, -W_C + 0.25, -1.0, 1.25)
	_bulwark(root, cover, platforms, 160.0, 190.0, W_C - 0.25, 1.0, 1.25)


static func _bulwark_runs(root: Node3D, cover: Array, platforms: Array,
		x0: float, x1: float, hz: float, gaps: Array) -> void:
	var cursor := x0
	for g in gaps:
		var ga: float = g[0]
		var gb: float = g[1]
		if ga > cursor:
			_bulwark(root, cover, platforms, cursor, ga, -hz + 0.25, -1.0, 1.25)
			_bulwark(root, cover, platforms, cursor, ga, hz - 0.25, 1.0, 1.25)
		cursor = gb
	if cursor < x1:
		_bulwark(root, cover, platforms, cursor, x1, -hz + 0.25, -1.0, 1.25)
		_bulwark(root, cover, platforms, cursor, x1, hz - 0.25, 1.0, 1.25)


static func _bulwark(root: Node3D, cover: Array, platforms: Array,
		x0: float, x1: float, z: float, side: float, h: float) -> void:
	var dx := x1 - x0
	if dx < 0.4:
		return
	var cx := (x0 + x1) * 0.5
	var top := DECK_Y + h
	var inner := z - side * 0.27
	_b(root, Vector3(dx, h, 0.50), Vector3(cx, DECK_Y + h * 0.5, z), _M["armor"])
	# 下沿深色带 + 上沿压条
	_b(root, Vector3(dx - 0.06, 0.24, 0.56), Vector3(cx, DECK_Y + 0.12, z), _M["hull_dark"])
	_b(root, Vector3(dx, 0.06, 0.58), Vector3(cx, top + 0.03, z), _M["armor_light"])
	_b(root, Vector3(dx - 0.2, 0.04, 0.06), Vector3(cx, top - 0.12, inner), _M["seam"])
	# 内侧灯带
	_b(root, Vector3(dx - 0.3, 0.06, 0.05), Vector3(cx, top - 0.30, inner), _M["strip"])
	# 竖向板缝
	for xx in range(int(x0) + 2, int(x1), 3):
		_b(root, Vector3(0.05, h - 0.28, 0.035), Vector3(float(xx), DECK_Y + h * 0.5, inner), _M["seam"])
	# 通风格栅
	for xx in range(int(x0) + 4, int(x1), 8):
		_b(root, Vector3(1.5, 0.42, 0.10), Vector3(float(xx), DECK_Y + 0.72, inner), _M["vent"])
		for k in 4:
			_b(root, Vector3(1.3, 0.04, 0.13), Vector3(float(xx), DECK_Y + 0.56 + float(k) * 0.10, inner), _M["steel_dark"])
	# 底部黄黑警示块
	for xx in range(int(x0) + 5, int(x1), 10):
		_b(root, Vector3(1.1, 0.28, 0.06), Vector3(float(xx), DECK_Y + 0.32, inner), _M["hazard_y"])
	# 侧碰撞停在台面下 0.30 m；台面登记为可站
	_chain_y(cover, Vector2(x0, z), Vector2(x1, z), 0.12, DECK_Y, top - 0.30)
	platforms.append({"c": Vector3(cx, 0.0, z) * U,
		"hx": dx * 0.5 * U, "hz": 0.32 * U, "h": (top + 0.06) * U})


static func _funnel_wall(root: Node3D, cover: Array, platforms: Array,
		a: Vector2, b: Vector2, h: float) -> void:
	var d := b - a
	var total := d.length()
	if total < 0.1:
		return
	var ang := atan2(-d.y, d.x)
	var cx := (a.x + b.x) * 0.5
	var cz := (a.y + b.y) * 0.5
	_b(root, Vector3(total, h, 0.45), Vector3(cx, DECK_Y + h * 0.5, cz), _M["armor"], Vector3(0.0, ang, 0.0))
	_b(root, Vector3(total, 0.30, 0.50), Vector3(cx, DECK_Y + 0.15, cz), _M["hull_dark"], Vector3(0.0, ang, 0.0))
	_b(root, Vector3(total, 0.06, 0.55), Vector3(cx, DECK_Y + h + 0.03, cz), _M["armor_light"], Vector3(0.0, ang, 0.0))
	# 沿墙的竖缝
	var n := int(total / 2.2)
	for i in n:
		var t := (float(i) + 0.5) / float(maxi(n, 1))
		var p := a.lerp(b, t)
		_b(root, Vector3(0.05, h - 0.30, 0.05), Vector3(p.x, DECK_Y + h * 0.5, p.y), _M["seam"], Vector3(0.0, ang, 0.0))
	# 入口黄黑条 + 警示灯
	_b(root, Vector3(1.0, 0.26, 0.06), Vector3(a.x, DECK_Y + 0.34, a.y), _M["hazard_y"], Vector3(0.0, ang, 0.0))
	_b(root, Vector3(0.22, 0.22, 0.22), Vector3(a.x, DECK_Y + h + 0.18, a.y), _M["amber"])
	# 侧面挡人；顶面登记成一串小台面，沿斜墙可站
	_chain_y(cover, a, b, 0.14, DECK_Y, DECK_Y + h - 0.30)
	var top := DECK_Y + h + 0.06
	var segs := maxi(2, int(ceil(total / 0.45)))
	for i in range(segs + 1):
		var p := a.lerp(b, float(i) / float(segs))
		platforms.append({"c": Vector3(p.x, 0.0, p.y) * U,
			"hx": 0.27 * U, "hz": 0.27 * U, "h": top * U})


# ================================================================== 实验室
static func _lab(root: Node3D, cover: Array) -> void:
	var x0 := -22.0
	var x1 := -6.0
	var cy := DECK_Y
	# 承力台架
	_b(root, Vector3(x1 - x0, DECK_Y, 12.0), Vector3((x0 + x1) * 0.5, DECK_Y * 0.5, 0.0), _M["under"])
	for xx in [-20.0, -14.0, -8.0]:
		_tube(root, Vector3(xx, DECK_Y - 0.2, -5.6), Vector3(xx + 3.0, 0.2, -2.0), 0.26, _M["truss"])
		_tube(root, Vector3(xx, DECK_Y - 0.2, 5.6), Vector3(xx + 3.0, 0.2, 2.0), 0.26, _M["truss"])
	# 舱体：下/上/左/右/后五面，+X 面留 6 × 5 m 破口
	_b(root, Vector3(x1 - x0, 2.5, 12.0), Vector3((x0 + x1) * 0.5, cy + 1.25, 0.0), _M["hull_dark"])
	_b(root, Vector3(x1 - x0, 2.5, 12.0), Vector3((x0 + x1) * 0.5, cy + 8.75, 0.0), _M["hull"])
	_b(root, Vector3(x1 - x0, 5.0, 3.0), Vector3((x0 + x1) * 0.5, cy + 5.0, -4.5), _M["hull"])
	_b(root, Vector3(x1 - x0, 5.0, 3.0), Vector3((x0 + x1) * 0.5, cy + 5.0, 4.5), _M["hull"])
	_b(root, Vector3(1.8, 10.0, 12.0), Vector3(x0 + 0.9, cy + 5.0, 0.0), _M["hull_dark"])

	# 前脸：破口下方 / 上方 / 两侧，外面是浅灰装甲，洞边压一圈烧黑
	_b(root, Vector3(0.55, 2.5, 12.0), Vector3(x1 - 0.28, cy + 1.25, 0.0), _M["hull"])
	_b(root, Vector3(0.55, 2.5, 12.0), Vector3(x1 - 0.28, cy + 8.75, 0.0), _M["hull_light"])
	_b(root, Vector3(0.55, 5.0, 3.0), Vector3(x1 - 0.28, cy + 5.0, -4.5), _M["hull"])
	_b(root, Vector3(0.55, 5.0, 3.0), Vector3(x1 - 0.28, cy + 5.0, 4.5), _M["hull"])
	# 破口四周的烧灼/变形区
	_b(root, Vector3(0.10, 5.6, 6.6), Vector3(x1 + 0.02, cy + 5.0, 0.0), _M["soot"])
	_b(root, Vector3(0.10, 1.1, 8.2), Vector3(x1 + 0.02, cy + 1.55, 0.0), _M["soot"])
	_b(root, Vector3(0.10, 1.1, 8.2), Vector3(x1 + 0.02, cy + 8.6, 0.0), _M["soot"])
	# 破口边框：橙色应急灯带
	_b(root, Vector3(0.08, 0.14, 6.2), Vector3(x1 + 0.10, cy + 2.45, 0.0), _M["amber"])
	_b(root, Vector3(0.08, 0.14, 6.2), Vector3(x1 + 0.10, cy + 7.55, 0.0), _M["amber"])
	for zz in [-3.08, 3.08]:
		_b(root, Vector3(0.08, 5.1, 0.14), Vector3(x1 + 0.10, cy + 5.0, zz), _M["amber"])

	# 内部：地板 / 天花 / 后墙 / 实验台 / 应急灯（透过破口能看到）
	_b(root, Vector3(12.0, 0.20, 6.0), Vector3(-13.0, cy + 2.55, 0.0), _M["steel_dark"])
	_b(root, Vector3(12.0, 0.20, 6.0), Vector3(-13.0, cy + 7.45, 0.0), _M["soot"])
	_b(root, Vector3(0.30, 5.0, 6.0), Vector3(-19.2, cy + 5.0, 0.0), _M["hull_dark"])
	# 后墙的冷光灯板
	_b(root, Vector3(0.06, 2.2, 4.0), Vector3(-18.95, cy + 5.0, 0.0), _M["lamp_dim"])
	for zz in [-2.8, 2.8]:
		_b(root, Vector3(12.0, 5.0, 0.18), Vector3(-13.0, cy + 5.0, zz), _M["soot"])
	# 两排实验台
	for zz in [-2.0, 2.0]:
		_b(root, Vector3(10.0, 0.72, 1.2), Vector3(-13.0, cy + 3.0, zz), _M["steel_dark"])
		_b(root, Vector3(10.0, 0.06, 1.3), Vector3(-13.0, cy + 3.38, zz), _M["label"])
		for k in 3:
			_b(root, Vector3(1.2, 0.5, 0.8), Vector3(-17.0 + float(k) * 3.2, cy + 3.66, zz), _M["hull_dark"])
	# 破损的中央培养罐
	_cyl(root, 1.1, 2.4, Vector3(-13.0, cy + 3.70, 0.0), _M["glass"])
	_torus(root, 1.12, 0.08, Vector3(-13.0, cy + 2.62, 0.0), _M["steel_dark"], Vector3.ZERO, 24)
	_torus(root, 1.12, 0.08, Vector3(-13.0, cy + 4.78, 0.0), _M["steel_dark"], Vector3.ZERO, 24)
	# 顶部冷光条与应急红灯
	_b(root, Vector3(10.0, 0.10, 0.10), Vector3(-13.0, cy + 7.15, 0.0), _M["strip"])
	_b(root, Vector3(0.45, 0.45, 0.45), Vector3(-9.0, cy + 6.85, 0.0), _M["red"])
	_omni(root, Vector3(-12.0, cy + 4.6, 0.0), Color(0.72, 0.86, 1.0), 2.2, 12.0, 0.40)
	_omni(root, Vector3(-9.0, cy + 6.4, 0.0), Color(1.0, 0.18, 0.10), 1.4, 8.0, 0.35)

	# 撕裂外翻的板片：沿洞边一圈
	for k in 12:
		var a := TAU * float(k) / 12.0
		var py := cy + 5.0 + sin(a) * 2.6
		var pz := cos(a) * 3.15
		_b(root, Vector3(1.2, 0.16, 0.75), Vector3(x1 + 0.28, py, pz), _M["hull"],
			Vector3(0.35 * sin(a), 0.85 * cos(a), 0.55 * sin(a)))
		_b(root, Vector3(0.7, 0.10, 0.5), Vector3(x1 + 0.45, py, pz), _M["soot"],
			Vector3(0.35 * sin(a), 0.85 * cos(a), 0.55 * sin(a)))

	# 前脸板缝 + 警示条
	for zz in [-5.6, -3.9, 3.9, 5.6]:
		_b(root, Vector3(0.06, 2.2, 0.08), Vector3(x1 + 0.03, cy + 4.2, zz), _M["seam"])
	for yy in [cy + 6.0, cy + 12.0]:
		_b(root, Vector3(0.06, 0.08, 11.6), Vector3(x1 + 0.03, yy, 0.0), _M["seam"])
	for zz in [-4.4, 4.4]:
		_b(root, Vector3(0.06, 0.35, 1.6), Vector3(x1 + 0.04, cy + 0.5, zz), _M["hazard_y"])

	# 地面烧灼痕 + 散落碎片（全部让开中央出生点）
	_b(root, Vector3(4.0, 0.02, 7.0), Vector3(-4.0, DECK_Y + 0.012, 0.0), _M["soot"])
	for k in 12:
		var dx := -7.4 + float(k % 4) * 0.85
		var dz := 4.0 + float(k % 3) * 1.15
		if k % 2 == 0:
			dz = -dz
		_b(root, Vector3(0.9, 0.14, 0.6), Vector3(dx, DECK_Y + 0.30 + float(k % 3) * 0.35, dz),
			_M["hull"], Vector3(0.3 * float(k), 0.7 * float(k), 0.2 * float(k)))
	# 垂下来的断缆：挂在洞的两侧
	for k in 4:
		var zz := (3.3 + float(k)) * (1.0 if k % 2 == 0 else -1.0)
		Kit.cable(root, Vector3(-5.6, cy + 6.3, zz) * U, Vector3(-4.5, cy + 0.3, zz + 0.3) * U, 0.55 * U, 0.035 * U, _M["cable"])
	# 破口外的应急投光灯
	_b(root, Vector3(0.55, 0.45, 0.45), Vector3(-5.55, cy + 8.0, 4.4), _M["hull_dark"])
	_b(root, Vector3(0.42, 0.12, 0.42), Vector3(-5.55, cy + 7.75, 4.4), _M["strip_warm"])
	_omni(root, Vector3(-2.6, cy + 4.8, 0.0), Color(1.0, 0.42, 0.18), 2.3, 14.0, 0.50)

	# 舱顶设备
	_module_cyl(root, Vector3(-14.0, cy + 11.4, 0.0), 2.2, 10.0, _M["steel_dark"])
	_antenna(root, Vector3(-19.0, cy + 10.0, 4.0), 6.0)
	# 舱体碰撞：只挡外圈，破口在 2.5 m 高处，玩家进不去
	_chain_y(cover, Vector2(x0, -6.0), Vector2(x0, 6.0), 0.5, DECK_Y, DECK_Y + 10.0)
	_chain_y(cover, Vector2(x1, -6.0), Vector2(x1, -3.0), 0.5, DECK_Y, DECK_Y + 10.0)
	_chain_y(cover, Vector2(x1, 3.0), Vector2(x1, 6.0), 0.5, DECK_Y, DECK_Y + 10.0)
	# 破口下方的实体墙：洞在 2.5 m 高处，玩家不能从下面走进实验室
	_chain_y(cover, Vector2(x1, -3.0), Vector2(x1, 3.0), 0.5, DECK_Y, DECK_Y + 2.5)
	# 两侧舱壁
	_chain_y(cover, Vector2(x0, -6.0), Vector2(x1, -6.0), 0.5, DECK_Y, DECK_Y + 10.0)
	_chain_y(cover, Vector2(x0, 6.0), Vector2(x1, 6.0), 0.5, DECK_Y, DECK_Y + 10.0)


# ================================================================== 战斗 A
static func _arena_a(root: Node3D, cover: Array, platforms: Array) -> void:
	# 货舱/设备箱：高，不可站
	_cargo_pod(root, cover, platforms, 8.0, -6.0, 3.2, 2.4, 3.2, "A1")
	# 两组可跳箱
	_crate(root, cover, platforms, 13.0, 5.2, 1.8, 1.2, 1.8)
	_crate(root, cover, platforms, 14.9, 4.2, 1.4, 0.9, 1.4)
	# 低矮管组：可站
	_pipe_housing(root, cover, platforms, 4.2, 3.2, 3.0, 1.8)
	# 散热立板：高墙
	_b(root, Vector3(0.45, 3.2, 6.2), Vector3(22.0, DECK_Y + 1.6, -3.0), _M["radiator"])
	for gy in range(0, 6, 1):
		_b(root, Vector3(0.50, 0.07, 6.0), Vector3(22.0, DECK_Y + 0.4 + float(gy) * 0.5, -3.0), _M["radiator_dark"])
	_ring_y(cover, 22.0, -3.0, 0.35, 3.1, DECK_Y, DECK_Y + 2.9)
	# 甲板系留环 / 舱盖
	for zz in [-7.0, 7.0]:
		for xx in [6.0, 18.0, 26.0]:
			_torus(root, 0.42, 0.09, Vector3(xx, DECK_Y + 0.05, zz), _M["steel_dark"], Vector3.ZERO, 20)
	# 电缆槽
	_b(root, Vector3(26.0, 0.16, 0.5), Vector3(13.0, DECK_Y + 0.08, 8.0), _M["steel_dark"])
	_b(root, Vector3(26.0, 0.16, 0.5), Vector3(13.0, DECK_Y + 0.08, -8.2), _M["steel_dark"])


# ================================================================== 战斗 B
static func _arena_b(root: Node3D, cover: Array, platforms: Array) -> void:
	# 中央变压器组
	_b(root, Vector3(4.2, 2.8, 4.2), Vector3(94.0, DECK_Y + 1.4, -3.6), _M["hull_dark"])
	for gy in range(0, 5, 1):
		_b(root, Vector3(4.4, 0.10, 0.60), Vector3(94.0, DECK_Y + 0.4 + float(gy) * 0.55, -1.42), _M["steel_dark"])
	_ring_y(cover, 94.0, -3.6, 2.1, 2.1, DECK_Y, DECK_Y + 2.5)
	platforms.append({"c": Vector3(94.0, 0.0, -3.6) * U,
		"hx": 2.1 * U, "hz": 2.1 * U, "h": (DECK_Y + 2.8) * U})
	# 两侧矮箱，可站
	_crate(root, cover, platforms, 86.0, 5.6, 2.0, 1.4, 2.0)
	_crate(root, cover, platforms, 102.0, 5.6, 2.0, 1.4, 2.0)
	# 低管组
	_pipe_housing(root, cover, platforms, 90.0, 8.2, 5.0, 1.4)
	# 地面舱盖 + 警示圈
	_cyl(root, 1.6, 0.12, Vector3(100.0, DECK_Y + 0.06, -7.0), _M["hull_dark"])
	_torus(root, 1.6, 0.10, Vector3(100.0, DECK_Y + 0.12, -7.0), _M["paint"], Vector3.ZERO, 28)
	# 断掉的天线杆横在甲板上（纯视觉，不挡路）
	_tube(root, Vector3(84.0, DECK_Y + 0.35, -8.2), Vector3(96.0, DECK_Y + 0.35, 9.0), 0.18, _M["steel_dark"])


# ================================================================== 战斗 C
static func _arena_c(root: Node3D, cover: Array, platforms: Array) -> void:
	# 两个燃料罐
	for xx in [168.0, 174.0]:
		_fuel_tank(root, cover, xx, -12.0)
	# 货箱堆，可站
	_crate(root, cover, platforms, 171.0, 10.0, 2.4, 1.6, 2.4)
	_crate(root, cover, platforms, 174.4, 9.2, 1.8, 1.0, 1.8)
	# 龙门吊：柱 + 顶梁 + 吊钩
	for side in [-1.0, 1.0]:
		_b(root, Vector3(0.55, 10.0, 0.55), Vector3(180.0, DECK_Y + 5.0, side * 14.0), _M["steel_dark"])
		_ring_y(cover, 180.0, side * 14.0, 0.35, 0.35, DECK_Y, DECK_Y + 9.7)
	_b(root, Vector3(0.55, 0.55, 28.5), Vector3(180.0, DECK_Y + 10.0, 0.0), _M["steel_dark"])
	_b(root, Vector3(0.20, 0.20, 0.20), Vector3(180.0, DECK_Y + 10.0, 0.0), _M["amber"])
	_tube(root, Vector3(180.0, DECK_Y + 9.8, 0.0), Vector3(180.0, DECK_Y + 6.2, 0.0), 0.05, _M["cable"])
	_b(root, Vector3(0.8, 0.5, 0.5), Vector3(180.0, DECK_Y + 5.9, 0.0), _M["steel_dark"])
	# 大门前的黄色引导线
	for zz in [-10.0, -5.0, 5.0, 10.0]:
		_dash_m(root, Vector2(178.0, zz), Vector2(188.0, zz), 0.28, 1.6, 1.4, DECK_Y + 0.015, _M["paint"])
	# 门槛前黄黑条
	_hazard_band(root, 187.4, 188.6, -15.0, 15.0)
	# 地面加油软管
	Kit.cable(root, Vector3(170.0, DECK_Y + 0.5, -10.0) * U, Vector3(176.0, DECK_Y + 0.5, -2.0) * U, 0.18 * U, 0.07 * U, _M["cable"])
	Kit.cable(root, Vector3(172.0, DECK_Y + 0.5, -10.0) * U, Vector3(178.0, DECK_Y + 0.5, 1.0) * U, 0.22 * U, 0.07 * U, _M["cable"])


# ================================================================== 通用实体
static func _cargo_pod(root: Node3D, cover: Array, platforms: Array, cx: float, cz: float,
		hx: float, h: float, hz: float, tag: String) -> void:
	var y0 := DECK_Y
	_b(root, Vector3(hx * 2.0, h, hz * 2.0), Vector3(cx, y0 + h * 0.5, cz), _M["armor"])
	_b(root, Vector3(hx * 2.0 + 0.2, 0.14, hz * 2.0 + 0.2), Vector3(cx, y0 + h, cz), _M["armor_light"])
	_b(root, Vector3(hx * 2.0, 0.24, hz * 2.0), Vector3(cx, y0 + 0.12, cz), _M["hazard_k"])
	# 正面舱门：凹板 + 中缝 + 拉手
	var face := cz + hz + 0.02
	_b(root, Vector3(2.2, h - 0.8, 0.05), Vector3(cx, y0 + h * 0.52, face), _M["hull_dark"])
	_b(root, Vector3(0.06, h - 1.0, 0.07), Vector3(cx, y0 + h * 0.52, face + 0.03), _M["seam"])
	_b(root, Vector3(0.18, 0.55, 0.10), Vector3(cx + 1.02, y0 + h * 0.52, face + 0.05), _M["steel_dark"])
	_b(root, Vector3(0.9, 0.42, 0.04), Vector3(cx - 0.6, y0 + h * 0.72, face + 0.04), _M["label"])
	# 竖向加强筋
	for k in int(hx * 2.0 / 1.1):
		var xx := cx - hx + 0.7 + float(k) * 1.1
		for zz in [cz - hz - 0.02, cz + hz + 0.02]:
			_b(root, Vector3(0.10, h - 0.45, 0.06), Vector3(xx, y0 + h * 0.5, zz), _M["seam"])
	# 顶部通风格栅
	for k in 3:
		_b(root, Vector3(hx * 1.3, 0.06, 0.35), Vector3(cx, y0 + h + 0.02, cz - hz * 0.55 + float(k) * hz * 0.55), _M["vent"])
	# 底部黄黑带
	for k in int(hx * 2.0 / 0.85):
		var xx := cx - hx + 0.42 + float(k) * 0.85
		_b(root, Vector3(0.42, 0.22, 0.04), Vector3(xx, y0 + 0.12, face + 0.01),
			_M["hazard_y"] if k % 2 == 0 else _M["hazard_k"])
	_ring_y(cover, cx, cz, hx, hz, y0, y0 + h - 0.30)
	platforms.append({"c": Vector3(cx, 0.0, cz) * U,
		"hx": hx * U, "hz": hz * U, "h": (y0 + h + 0.07) * U})
	root.set_meta("pod_" + tag, true)


static func _crate(root: Node3D, cover: Array, platforms: Array,
		cx: float, cz: float, hx: float, h: float, hz: float) -> void:
	var y0 := DECK_Y
	_b(root, Vector3(hx * 2.0, h, hz * 2.0), Vector3(cx, y0 + h * 0.5, cz), _M["armor"])
	_b(root, Vector3(hx * 2.0 + 0.10, 0.10, hz * 2.0 + 0.10), Vector3(cx, y0 + h, cz), _M["armor_light"])
	# 正面凹板 + 标签
	var face := cz + hz + 0.01
	_b(root, Vector3(hx * 1.5, h * 0.55, 0.04), Vector3(cx, y0 + h * 0.52, face), _M["deck_dark"])
	_b(root, Vector3(hx * 0.9, h * 0.20, 0.035), Vector3(cx - hx * 0.2, y0 + h * 0.68, face + 0.02), _M["label"])
	_b(root, Vector3(0.28, 0.08, 0.06), Vector3(cx + hx * 0.55, y0 + h * 0.55, face + 0.02), _M["steel_dark"])
	# 角部护条
	for sx in [-1.0, 1.0]:
		_b(root, Vector3(0.12, h, 0.12), Vector3(cx + sx * (hx - 0.08), y0 + h * 0.5, cz + hz - 0.08), _M["steel_dark"])
		_b(root, Vector3(0.12, h, 0.12), Vector3(cx + sx * (hx - 0.08), y0 + h * 0.5, cz - hz + 0.08), _M["steel_dark"])
	# 底部警示
	for k in int(hx * 2.0 / 0.8):
		var xx := cx - hx + 0.4 + float(k) * 0.8
		_b(root, Vector3(0.4, 0.16, 0.035), Vector3(xx, y0 + 0.08, face + 0.005),
			_M["hazard_y"] if k % 2 == 0 else _M["hazard_k"])
	_ring_y(cover, cx, cz, hx, hz, y0, y0 + h - 0.30)
	platforms.append({"c": Vector3(cx, 0.0, cz) * U,
		"hx": hx * U, "hz": hz * U, "h": (y0 + h + 0.05) * U})


static func _pipe_housing(root: Node3D, cover: Array, platforms: Array,
		cx: float, cz: float, hx: float, hz: float) -> void:
	var h := 0.9
	var y0 := DECK_Y
	_b(root, Vector3(hx * 2.0, h, hz * 2.0), Vector3(cx, y0 + h * 0.5, cz), _M["hull_dark"])
	_b(root, Vector3(hx * 2.0 - 0.2, 0.06, hz * 2.0 - 0.2), Vector3(cx, y0 + h + 0.01, cz), _M["deck_panel"])
	# 侧面三根管
	for k in 3:
		var py := y0 + 0.26 + float(k) * 0.20
		_tube(root, Vector3(cx - hx + 0.25, py, cz + hz + 0.16),
			Vector3(cx + hx - 0.25, py, cz + hz + 0.16), 0.10, _M["steel_dark"])
	# 端部面板 + 警示
	for sx in [-1.0, 1.0]:
		_b(root, Vector3(0.05, 0.55, hz * 1.4), Vector3(cx + sx * (hx + 0.01), y0 + 0.42, cz), _M["vent"])
	_b(root, Vector3(hx * 2.0, 0.16, 0.04), Vector3(cx, y0 + 0.08, cz + hz + 0.01), _M["hazard_y"])
	_ring_y(cover, cx, cz, hx, hz, y0, y0 + h - 0.30)
	platforms.append({"c": Vector3(cx, 0.0, cz) * U,
		"hx": hx * U, "hz": hz * U, "h": (y0 + h + 0.04) * U})


static func _fuel_tank(root: Node3D, cover: Array, cx: float, cz: float) -> void:
	_cyl(root, 2.0, 6.0, Vector3(cx, DECK_Y + 3.0, cz), _M["armor_light"])
	for yy in [DECK_Y + 1.0, DECK_Y + 3.0, DECK_Y + 5.0]:
		_torus(root, 2.05, 0.10, Vector3(cx, yy, cz), _M["steel_dark"], Vector3.ZERO, 28)
	_b(root, Vector3(4.4, 0.30, 4.4), Vector3(cx, DECK_Y + 0.15, cz), _M["hazard_k"])
	_hazard_band_ring(root, cx, cz, 2.3, DECK_Y + 0.15)
	_tube(root, Vector3(cx, DECK_Y + 5.8, cz), Vector3(cx + 1.6, DECK_Y + 7.2, cz), 0.16, _M["steel_dark"])
	_cov(cover, Vector3(cx, DECK_Y, cz), 2.15, 6.0)


static func _hazard_band(root: Node3D, x0: float, x1: float, z0: float, z1: float) -> void:
	var n := int((z1 - z0) / 0.9)
	for i in n:
		var zz := z0 + 0.45 + float(i) * 0.9
		_b(root, Vector3(x1 - x0, 0.025, 0.44), Vector3((x0 + x1) * 0.5, DECK_Y + 0.02, zz),
			_M["hazard_y"] if i % 2 == 0 else _M["hazard_k"])


static func _hazard_band_face(root: Node3D, cx: float, cz: float, width: float, h: float, y: float) -> void:
	var n := int(width / 0.8)
	for i in n:
		var xx := cx - width * 0.5 + 0.4 + float(i) * 0.8
		_b(root, Vector3(0.4, h, 0.03), Vector3(xx, y, cz), _M["hazard_y"] if i % 2 == 0 else _M["hazard_k"])


static func _hazard_band_ring(root: Node3D, cx: float, cz: float, r: float, y: float) -> void:
	var n := 12
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p0 := Vector3(cx + cos(a0) * r, y, cz + sin(a0) * r)
		var p1 := Vector3(cx + cos(a1) * r, y, cz + sin(a1) * r)
		var mid := (p0 + p1) * 0.5
		var d := p1 - p0
		_b(root, Vector3(d.length(), 0.03, 0.26), mid, _M["hazard_y"] if i % 2 == 0 else _M["hazard_k"],
			Vector3(0.0, atan2(-d.z, d.x), 0.0))


# ================================================================== 防空炮 / 光闸 / 供能节点
static func _aa_turret(aa: Node3D, cover: Array, platforms: Array, x: float, z: float, aim: Vector3) -> void:
	var t := Node3D.new()
	t.position = Vector3(x, DECK_Y, z) * U
	var dir := aim - Vector3(x, DECK_Y, z)
	t.rotation.y = atan2(-dir.z, dir.x)
	aa.add_child(t)

	# 底座平台 + 炮座
	_b(t, Vector3(3.6, 0.30, 3.6), Vector3(0.0, 0.15, 0.0), _M["steel_dark"])
	for k in 4:
		var xx := -1.5 + float(k) * 1.0
		_b(t, Vector3(0.45, 0.16, 0.05), Vector3(xx, 0.15, 1.82), _M["hazard_y"] if k % 2 == 0 else _M["hazard_k"])
	_cyl(t, 1.75, 0.85, Vector3(0.0, 0.425, 0.0), _M["hull_dark"])
	_torus(t, 1.75, 0.10, Vector3(0.0, 0.80, 0.0), _M["steel_dark"], Vector3.ZERO, 28)
	# 炮塔壳
	_b(t, Vector3(3.0, 1.5, 2.5), Vector3(0.1, 1.65, 0.0), _M["armor"])
	_b(t, Vector3(2.7, 0.22, 2.9), Vector3(0.1, 2.42, 0.0), _M["armor_light"])
	_b(t, Vector3(0.9, 0.75, 1.2), Vector3(-1.75, 1.45, 0.0), _M["steel_dark"])
	# 双联装炮管 + 炮口环
	for zz in [-0.62, 0.62]:
		_tube(t, Vector3(1.2, 1.75, zz), Vector3(4.4, 1.92, zz), 0.13, _M["steel_dark"])
		_b(t, Vector3(0.55, 0.30, 0.34), Vector3(4.55, 1.94, zz), _M["hull_dark"])
		var ring := _torus(t, 0.20, 0.045, Vector3(4.88, 1.94, zz), _M["amber"], Vector3(0.0, 0.0, PI * 0.5), 16)
		aa.part(ring, _M["amber"], _M["off"])
	# 后部散热格栅
	for k in 4:
		_b(t, Vector3(0.10, 0.95, 2.2), Vector3(-1.45, 1.55, 0.0), _M["vent"])
	# 顶部雷达：桅杆加高，把碟抬到炮塔顶 1.9 m 以上，避免看起来像可踩的平台
	_b(t, Vector3(0.18, 3.00, 0.18), Vector3(-0.55, 4.03, 0.0), _M["steel_dark"])
	var dish := CylinderMesh.new()
	dish.top_radius = 0.85 * U
	dish.bottom_radius = 0.85 * U
	dish.height = 0.12 * U
	dish.radial_segments = 18
	var dm := MeshInstance3D.new()
	dm.mesh = dish
	dm.material_override = _M["steel"]
	dm.position = Vector3(-0.55, 5.58, 0.0) * U
	dm.rotation = Vector3(0.35, 0.0, 0.0)
	t.add_child(dm)
	# 通电警示条：琥珀色，和红色光闸区分开
	for zz in [-1.32, 1.32]:
		var strip := _b(t, Vector3(2.3, 0.12, 0.06), Vector3(0.1, 1.95, zz), _M["amber"])
		aa.part(strip, _M["amber"], _M["off"])
	var rear := _b(t, Vector3(0.06, 0.12, 2.0), Vector3(-1.55, 1.95, 0.0), _M["amber"])
	aa.part(rear, _M["amber"], _M["off"])
	var lamp := _omni_node(t, Vector3(-0.4, 2.9, 0.0), Color(1.0, 0.34, 0.08), 1.0, 11.0, 0.35)
	aa.light(lamp, 1.0)
	# 顶面维护格栅：把炮塔盖四周加宽 0.25 m，落点更好找
	_b(t, Vector3(0.30, 0.06, 3.40), Vector3(-1.45, 2.565, 0.0), _M["steel_dark"])
	_b(t, Vector3(0.30, 0.06, 3.40), Vector3(1.65, 2.565, 0.0), _M["steel_dark"])
	_b(t, Vector3(3.40, 0.06, 0.30), Vector3(0.10, 2.565, -1.70), _M["steel_dark"])
	_b(t, Vector3(3.40, 0.06, 0.30), Vector3(0.10, 2.565, 1.70), _M["steel_dark"])
	# 雷达桅杆根部也挡一下，避免站在顶面时相机穿进桅杆
	var mast_pos: Vector3 = t.position + t.basis.x * (-0.55 * U)
	cover.append({"c": Vector3(mast_pos.x, (DECK_Y + 2.53) * U, mast_pos.z),
		"r": 0.22 * U + BALL, "h": 3.5 * U, "cam": true})
	# 碰撞：炮座挡人，顶面格栅可站；侧碰撞停在台面下 0.30
	_cov(cover, Vector3(x, DECK_Y, z), 1.9, 2.23)
	platforms.append({"c": Vector3(x, 0.0, z) * U,
		"hx": 1.70 * U, "hz": 1.80 * U, "h": (DECK_Y + 2.59) * U})


static func _gate(root: Node3D, aa: Node3D, cover: Array, platforms: Array, gates: Array,
		x: float, z0: float, z1: float) -> void:
	var cz := (z0 + z1) * 0.5
	var dz := z1 - z0
	var wide := dz > 20.0
	var pylon_out := 1.2 if wide else 0.5
	var spon := 1.9 if wide else 1.2
	var top := DECK_Y + 7.0
	# 上/下发射轨：让红色光条像一道门，而不是一根栏杆
	_b(aa, Vector3(0.34, 0.20, dz + 0.6), Vector3(x, DECK_Y + 0.12, cz), _M["steel_dark"])
	_b(aa, Vector3(0.34, 0.20, dz + 0.6), Vector3(x, DECK_Y + 5.40, cz), _M["steel_dark"])
	for k in int((dz + 0.6) / 0.9):
		var hz := cz - (dz + 0.6) * 0.5 + 0.45 + float(k) * 0.9
		_b(aa, Vector3(0.38, 0.22, 0.42), Vector3(x, DECK_Y + 0.12, hz),
			_M["hazard_y"] if k % 2 == 0 else _M["hazard_k"])
	var top_rail := _b(aa, Vector3(0.36, 0.10, dz), Vector3(x, DECK_Y + 5.50, cz), _M["red"])
	aa.part(top_rail, _M["red"], _M["off"])
	platforms.append({"c": Vector3(x, 0.0, cz) * U,
		"hx": 0.18 * U, "hz": dz * 0.5 * U, "h": (DECK_Y + 5.55) * U})
	# 两根门柱；宽门的柱子退到矮护墙外面，避免和墙/光条穿在一起
	for zz in [cz - dz * 0.5 - pylon_out, cz + dz * 0.5 + pylon_out]:
		# 门柱落在小外伸台上，不从栈桥边上悬空
		_b(root, Vector3(spon, 0.34, spon), Vector3(x, DECK_Y - 0.17, zz), _M["deck"])
		_b(root, Vector3(spon, 1.0, 0.30), Vector3(x, DECK_Y - 0.85, zz + (1.0 if zz > cz else -1.0) * 0.55), _M["under"])
		_tube(root, Vector3(x, DECK_Y - 0.35, zz), Vector3(x, 0.2, zz + (1.0 if zz > cz else -1.0) * 2.2), 0.16, _M["truss"])
		platforms.append({"c": Vector3(x, 0.0, zz) * U,
			"hx": spon * 0.5 * U, "hz": spon * 0.5 * U, "h": DECK_Y * U})
		_b(aa, Vector3(0.72, 7.2, 0.72), Vector3(x, DECK_Y + 3.6, zz), _M["armor"])
		_b(aa, Vector3(0.86, 0.14, 0.86), Vector3(x, top + 0.07, zz), _M["armor_light"])
		var pstrip := _b(aa, Vector3(0.10, 0.55, 0.10), Vector3(x - 0.38, DECK_Y + 5.9, zz), _M["red"])
		aa.part(pstrip, _M["red"], _M["off"])
		_cov(cover, Vector3(x, DECK_Y, zz), 0.55, 7.2)
	# 顶梁：宽门（终点）不横一根大梁挡住大门
	if not wide:
		_b(aa, Vector3(0.72, 0.72, dz + 2.4), Vector3(x, top + 0.36, cz), _M["armor"])
		var rail := _b(aa, Vector3(0.10, 0.06, dz + 1.4), Vector3(x - 0.38, top - 0.15, cz), _M["red"])
		aa.part(rail, _M["red"], _M["off"])
	# 宽门不横顶梁，也不在中间加横杆；只保留 8.5 m 的顶轨
	# 红色光条（9 / 13 / 18 条，视门宽）；门面抬到 4.4 m，炮塔顶也翻不过去
	var n := int(maxf(7.0, floor(dz / 0.95)))
	for i in n:
		var zz := z0 + (dz * (float(i) + 0.5) / float(n))
		var bar := _b(aa, Vector3(0.05, 5.40, 0.06), Vector3(x, DECK_Y + 2.75, zz), _M["red"])
		aa.part(bar, _M["red"], _M["off"])
	# 通电时门面本身是实体；断电时把碰撞高度归零
	var blocker_start := cover.size()
	_chain_y(cover, Vector2(x, z0), Vector2(x, z1), 0.08, DECK_Y, DECK_Y + 5.4)
	for i in range(blocker_start, cover.size()):
		aa.blocker(cover[i])
	# 门口地面警示
	_b(root, Vector3(1.4, 0.025, dz), Vector3(x, DECK_Y + 0.015, cz), _M["hazard_k"])
	# 红色扫描灯
	var lamp := _omni_node(aa, Vector3(x - 0.2, DECK_Y + 3.2, cz), Color(1.0, 0.10, 0.06), 1.3, 16.0, 0.55)
	aa.light(lamp, 1.3)
	gates.append({"x0": x - 0.35, "x1": x + 0.35, "z0": z0, "z1": z1, "state": aa})


static func _power_node(aa: Node3D, cover: Array, platforms: Array, x: float, z: float, face: float,
		t1 := Vector3.ZERO, t2 := Vector3.ZERO) -> void:
	# face = +1 朝 +Z，-1 朝 -Z
	var n := Node3D.new()
	n.position = Vector3(x, DECK_Y, z) * U
	aa.add_child(n)
	# 地面黄黑警示环
	for i in 16:
		var a := TAU * float(i) / 16.0
		_b(n, Vector3(0.95, 0.022, 0.34), Vector3(cos(a) * 3.15, 0.011, sin(a) * 3.15),
			_M["hazard_y"] if i % 2 == 0 else _M["hazard_k"], Vector3(0.0, -a, 0.0))
	# 底座 + 机柜
	_b(n, Vector3(4.2, 0.30, 3.6), Vector3(0.0, 0.15, 0.0), _M["hazard_k"])
	_b(n, Vector3(3.4, 2.8, 2.6), Vector3(0.0, 1.55, 0.0), _M["hull_dark"])
	_b(n, Vector3(3.5, 0.18, 2.7), Vector3(0.0, 2.93, 0.0), _M["armor_light"])
	# 侧面散热鳍
	for k in 9:
		_b(n, Vector3(0.10, 2.2, 2.2), Vector3(-1.72, 1.5, 0.0), _M["vent"])
	# 核心：玻璃管 + 内芯 + 环
	_cyl(n, 0.48, 2.1, Vector3(0.0, 1.65, face * 1.32), _M["node_glass"])
	var core := _cyl(n, 0.28, 1.8, Vector3(0.0, 1.65, face * 1.36), _M["core_on"])
	aa.part(core, _M["core_on"], _M["off"])
	for yy in [0.8, 1.65, 2.5]:
		_torus(n, 0.52, 0.07, Vector3(0.0, yy, face * 1.34), _M["steel_dark"], Vector3.ZERO, 20)
	# 控制台：前面留出玻璃管，下面补一段支撑臂，避免看起来悬空
	_b(n, Vector3(0.92, 0.22, 0.85), Vector3(0.0, 0.50, face * 1.55), _M["steel_dark"])
	_b(n, Vector3(1.7, 0.75, 0.55), Vector3(0.0, 0.85, face * 2.16), _M["steel_dark"])
	var screen := _b(n, Vector3(0.90, 0.42, 0.04), Vector3(0.0, 1.10, face * 2.46), _M["screen"])
	aa.part(screen, _M["screen"], _M["off"])
	# 五格进度灯：清完怪后按住 3 s，逐格转绿
	for k in 5:
		var pip := _b(n, Vector3(0.22, 0.14, 0.05), Vector3(-0.62 + float(k) * 0.31, 1.52, face * 2.47), _M["amber"])
		aa.part(pip, _M["amber"], _M["off_green"])
	# 侧面断电手柄
	_tube(n, Vector3(-1.05, 1.0, face * 1.55), Vector3(-1.25, 1.55, face * 1.82), 0.07, _M["red"])
	_b(n, Vector3(0.18, 0.18, 0.18), Vector3(-1.28, 1.62, face * 1.86), _M["rubber"])
	# 顶部警示灯 + 高桅杆（远处也能看到节点在哪）
	var beacon := _b(n, Vector3(0.22, 0.22, 0.22), Vector3(0.0, 3.18, 0.0), _M["amber"])
	aa.part(beacon, _M["amber"], _M["off"])
	_tube(n, Vector3(0.0, 3.1, 0.0), Vector3(0.0, 6.2, 0.0), 0.10, _M["steel_dark"])
	var top_beacon := _b(n, Vector3(0.50, 0.50, 0.50), Vector3(0.0, 6.35, 0.0), _M["amber"])
	aa.part(top_beacon, _M["amber"], _M["off"])
	var beam := _b(n, Vector3(0.07, 3.2, 0.07), Vector3(0.0, 8.2, 0.0), _M["amber"])
	aa.part(beam, _M["amber"], _M["off"])
	var ring := _torus(n, 0.95, 0.055, Vector3(0.0, 9.75, 0.0), _M["amber"], Vector3.ZERO, 24)
	aa.part(ring, _M["amber"], _M["off"])
	var lamp := _omni_node(n, Vector3(0.0, 2.4, face * 1.5), Color(1.0, 0.42, 0.10), 1.2, 11.0, 0.35)
	aa.light(lamp, 1.2)
	var lamp2 := _omni_node(n, Vector3(0.0, 6.3, 0.0), Color(1.0, 0.46, 0.12), 1.4, 22.0, 0.30)
	aa.light(lamp2, 1.4)
	# 碰撞：机身挡人；顶盖（3.5 x 2.7）可站，侧碰撞停在台面下 0.30
	_cov(cover, Vector3(x, DECK_Y, z), 2.60, 2.72)
	platforms.append({"c": Vector3(x, 0.0, z) * U,
		"hx": 1.75 * U, "hz": 1.35 * U, "h": (DECK_Y + 3.02) * U})
	# 从节点到两座炮塔的电缆
	if t1 != Vector3.ZERO:
		_cable_to(aa, Vector3(x, DECK_Y + 0.42, z), t1)
	if t2 != Vector3.ZERO:
		_cable_to(aa, Vector3(x, DECK_Y + 0.42, z), t2)


static func _cable_to(parent: Node3D, a: Vector3, b: Vector3) -> void:
	for k in 2:
		var off := Vector3(0.0, 0.0, (float(k) - 0.5) * 0.26)
		var aa := a + Vector3(0.0, 0.42, 0.0)
		var bb := b + Vector3(0.0, 0.42, 0.0)
		Kit.cable(parent, (aa + off) * U, (bb + off) * U, 0.16 * U, 0.105 * U, _M["cable"])


# ================================================================== 船坞大门
static func _hangar_block(root: Node3D, cover: Array) -> void:
	var x := X_DOOR
	# 主体 + 底部裙墙（落到船壳）
	_b(root, Vector3(36.0, 22.0, 40.0), Vector3(x + 18.0, DECK_Y + 11.0, 0.0), _M["hull"])
	_b(root, Vector3(36.0, DECK_Y, 40.0), Vector3(x + 18.0, DECK_Y * 0.5, 0.0), _M["under"])
	# 正立面：门洞上方 + 两侧
	_b(root, Vector3(0.6, 6.0, 40.0), Vector3(x + 0.3, DECK_Y + 19.0, 0.0), _M["armor"])
	_b(root, Vector3(0.6, 16.0, 5.0), Vector3(x + 0.3, DECK_Y + 8.0, -17.5), _M["armor"])
	_b(root, Vector3(0.6, 16.0, 5.0), Vector3(x + 0.3, DECK_Y + 8.0, 17.5), _M["armor"])
	# 门框
	_b(root, Vector3(1.0, 17.6, 1.4), Vector3(x - 0.1, DECK_Y + 8.8, -16.0), _M["hull_dark"])
	_b(root, Vector3(1.0, 17.6, 1.4), Vector3(x - 0.1, DECK_Y + 8.8, 16.0), _M["hull_dark"])
	_b(root, Vector3(1.0, 1.4, 33.4), Vector3(x - 0.1, DECK_Y + 16.7, 0.0), _M["hull_dark"])
	# 两扇门：30 m 宽 × 16 m 高，中缝 + 加强筋 + 撞痕
	for side in [-1.0, 1.0]:
		_b(root, Vector3(0.50, 15.8, 14.85), Vector3(x + 0.15, DECK_Y + 7.9, side * 7.425), _M["deck_dark"])
		for k in 8:
			_b(root, Vector3(0.18, 0.22, 14.4), Vector3(x - 0.12, DECK_Y + 1.3 + float(k) * 1.85, side * 7.425), _M["hull"])
	_b(root, Vector3(0.14, 15.6, 0.14), Vector3(x - 0.18, DECK_Y + 7.9, 0.0), _M["amber"])
	# 撞痕
	_b(root, Vector3(0.10, 3.2, 4.4), Vector3(x - 0.30, DECK_Y + 4.8, 4.2), _M["soot"])
	for k in 3:
		_b(root, Vector3(0.12, 0.18, 3.6), Vector3(x - 0.34, DECK_Y + 3.5 + float(k) * 1.2, 4.4), _M["gold"])
	# 门槛 + 黄黑条
	_b(root, Vector3(1.6, 0.12, 31.0), Vector3(x - 0.8, DECK_Y + 0.06, 0.0), _M["steel"])
	_hazard_band(root, x - 1.1, x - 0.2, -15.0, 15.0)
	# 门楣灯带 + 两侧信标
	_b(root, Vector3(0.25, 0.34, 18.0), Vector3(x - 0.25, DECK_Y + 17.4, 0.0), _M["white"])
	for zz in [-17.0, 17.0]:
		_b(root, Vector3(0.30, 0.30, 0.30), Vector3(x - 0.30, DECK_Y + 18.1, zz), _M["red"])
		_b(root, Vector3(0.26, 0.26, 0.26), Vector3(x - 0.30, DECK_Y + 1.2, zz), _M["green"])
	# 门侧控制箱
	_b(root, Vector3(0.45, 1.5, 1.0), Vector3(x - 0.55, DECK_Y + 1.9, 16.6), _M["hull_dark"])
	_b(root, Vector3(0.05, 0.45, 0.55), Vector3(x - 0.79, DECK_Y + 2.1, 16.6), _M["screen_ok"])
	_tube(root, Vector3(x - 0.55, DECK_Y + 1.2, 16.6), Vector3(x - 0.55, DECK_Y + 0.1, 17.4), 0.06, _M["cable"])
	# 立面细节：板缝 / 通风格栅 / 管线
	for zz in [-19.0, -16.0, 16.0, 19.0]:
		_b(root, Vector3(0.10, 21.0, 0.10), Vector3(x - 0.32, DECK_Y + 10.5, zz), _M["seam"])
	for gy in range(0, 4, 1):
		_b(root, Vector3(0.12, 0.14, 3.4), Vector3(x - 0.34, DECK_Y + 18.2 + float(gy) * 0.7, -18.0), _M["steel_dark"])
		_b(root, Vector3(0.12, 0.14, 3.4), Vector3(x - 0.34, DECK_Y + 18.2 + float(gy) * 0.7, 18.0), _M["steel_dark"])
	# 侧面管线
	for zz in [-20.0, 20.0]:
		_tube(root, Vector3(x + 2.0, DECK_Y + 14.0, zz), Vector3(x + 32.0, DECK_Y + 14.0, zz), 0.18, _M["steel_dark"])
	# 门洞碰撞：整面墙
	_chain_y(cover, Vector2(x + 0.4, -20.0), Vector2(x + 0.4, 20.0), 0.45, DECK_Y, DECK_Y + 22.0)
	# 桥塔
	_b(root, Vector3(14.0, 14.0, 14.0), Vector3(x + 16.0, DECK_Y + 29.0, 0.0), _M["hull"])
	_b(root, Vector3(12.0, 2.2, 12.0), Vector3(x + 16.0, DECK_Y + 37.1, 0.0), _M["armor_light"])
	for yy in [DECK_Y + 31.4, DECK_Y + 32.8, DECK_Y + 34.2]:
		_b(root, Vector3(12.4, 0.30, 0.12), Vector3(x + 16.0, yy, -7.05), _M["window_cool"])
		_b(root, Vector3(12.4, 0.30, 0.12), Vector3(x + 16.0, yy, 7.05), _M["window_cool"])
		_b(root, Vector3(0.12, 0.30, 10.0), Vector3(x + 9.05, yy, 0.0), _M["window_cool"])
	# 桅杆
	_tube(root, Vector3(x + 16.0, DECK_Y + 38.2, 0.0), Vector3(x + 16.0, DECK_Y + 47.0, 0.0), 0.20, _M["steel_dark"])
	for k in 3:
		_b(root, Vector3(3.6, 0.08, 0.08), Vector3(x + 16.0, DECK_Y + 40.5 + float(k) * 1.6, 0.0), _M["steel_dark"])
	_b(root, Vector3(0.22, 0.22, 0.22), Vector3(x + 16.0, DECK_Y + 47.3, 0.0), _M["red"])
	# 门内透出的冷光
	_omni(root, Vector3(x - 1.8, DECK_Y + 8.0, 0.0), Color(0.42, 0.72, 1.0), 1.5, 18.0, 0.45)
	_omni(root, Vector3(x - 1.8, DECK_Y + 17.0, 0.0), Color(0.95, 0.98, 1.0), 1.0, 12.0, 0.30)


# ================================================================== 灯光
static func _lights(root: Node3D, cover: Array) -> void:
	for p in [Vector3(7.0, 8.4, 5.0), Vector3(22.0, 8.4, -5.0),
			Vector3(88.0, 8.4, 5.0), Vector3(104.0, 8.4, -5.0),
			Vector3(168.0, 8.4, 8.0), Vector3(181.0, 8.4, -8.0)]:
		_tube(root, Vector3(p.x, DECK_Y, p.z), p, 0.13, _M["steel_dark"])
		_cov(cover, Vector3(p.x, DECK_Y, p.z), 0.20, 4.4)
		_b(root, Vector3(0.6, 0.18, 0.6), p, _M["white"])
		_omni(root, p - Vector3(0.0, 0.2, 0.0), Color(1.0, 0.82, 0.58), 1.2, 16.0, 0.40)


# ================================================================== 小工具
static func _b(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	return Kit.box(parent, size * U, pos * U, mat, rot)


static func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	return Kit.cylinder(parent, radius * U, height * U, pos * U, mat)


static func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	Kit.tube(parent, a * U, b * U, radius * U, mat)


static func _torus(parent: Node3D, radius: float, tube: float, pos: Vector3,
		mat: Material, rot := Vector3.ZERO, rings := 32) -> MeshInstance3D:
	var mi := Kit.torus(parent, radius * U, tube * U, pos * U, mat, rings)
	mi.rotation = rot
	return mi


static func _cov(cover: Array, c: Vector3, phys_r: float, h: float) -> void:
	cover.append({"c": c * U, "r": phys_r * U + BALL, "h": h * U, "cam": true})


static func _ring_y(cover: Array, cx: float, cz: float, hx: float, hz: float,
		base: float, top: float, phys := 0.12) -> void:
	_chain_y(cover, Vector2(cx - hx, cz - hz), Vector2(cx + hx, cz - hz), phys, base, top)
	_chain_y(cover, Vector2(cx + hx, cz - hz), Vector2(cx + hx, cz + hz), phys, base, top)
	_chain_y(cover, Vector2(cx + hx, cz + hz), Vector2(cx - hx, cz + hz), phys, base, top)
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


static func _omni(root: Node3D, p: Vector3, col: Color, energy: float, rng: float,
		fog := 0.5) -> OmniLight3D:
	return _omni_node(root, p, col, energy, rng, fog)


static func _omni_node(parent: Node3D, p: Vector3, col: Color, energy: float, rng: float,
		fog := 0.5) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = p * U
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng * U
	l.omni_attenuation = 0.7
	l.light_volumetric_fog_energy = fog
	l.shadow_enabled = false
	parent.add_child(l)
	return l


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
		Kit.box(parent, Vector3(dash, 0.008, width) * U, Vector3(c.x, y, c.y) * U, mat,
			Vector3(0.0, atan2(dir.y, dir.x), 0.0))

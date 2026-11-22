extends RefCounted
## 病房（Ward）：40 × 22 × 6.5 m。
##
## 南北两排靠墙病床 + 中央一组“床头对床头、床身朝外”的岛式病床，
## 两组岛式床之间是一道 1.30 m 的实体隔墙（不是帘子），墙顶可以站上去。
## 病床 0.59 / 床头柜 0.75 / 护士站 1.05 / 处置柜 1.30 / 隔墙 1.30 m，全部可跳上。

const Kit := preload("res://src/warehouse/kit.gd")

const U := 1.0 / 0.547
const BALL := 1.2
const HALF_X := 20.0
const HALF_Z := 11.0
const H := 6.5

const BED_TOP := 0.59
const TABLE_TOP := 0.75
const CAB_TOP := 1.30
const DIV_TOP := 1.30
const BED_LEN := 2.05
const BED_HALF_W := 0.475


## 每张床：[x, 床头 z, 朝向]（dir=+1 表示床身朝 +z）
static func bed_spots() -> Array:
	var out: Array = []
	for i in 8:
		var x := -12.25 + 3.5 * float(i)
		out.append([x, -9.90, 1.0])
		out.append([x, 9.90, -1.0])
	for i in 7:
		var x := -10.5 + 3.5 * float(i)
		out.append([x, -0.45, -1.0])
		out.append([x, 0.45, 1.0])
	return out


static func build(origin := Vector3.ZERO) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arena_ward"
	root.position = origin

	_env(root)
	_shell(root)
	_beds(root)
	_curtains(root)
	_props(root)
	_mirror(root)
	_lights(root)

	var walls: Array = []
	_wall(walls, Vector2(-HALF_X, -HALF_Z), Vector2(HALF_X, -HALF_Z), H, Vector2(0, 1))
	_wall(walls, Vector2(HALF_X, -HALF_Z), Vector2(HALF_X, HALF_Z), H, Vector2(-1, 0))
	_wall(walls, Vector2(HALF_X, HALF_Z), Vector2(-HALF_X, HALF_Z), H, Vector2(0, -1))
	_wall(walls, Vector2(-HALF_X, HALF_Z), Vector2(-HALF_X, -HALF_Z), H, Vector2(1, 0))

	var platforms: Array = []
	var cover: Array = []

	for spec in bed_spots():
		var x: float = float(spec[0])
		var z_head: float = float(spec[1])
		var dir: float = float(spec[2])
		var zc: float = z_head + dir * BED_LEN * 0.5
		platforms.append({"c": Vector3(x * U, 0.0, zc * U),
			"hx": BED_HALF_W * U, "hz": BED_LEN * 0.5 * U, "h": BED_TOP * U})
		for dz in [-0.70, 0.0, 0.70]:
			_cover(cover, Vector3(x, 0.0, zc + dz), 0.42, BED_TOP - 0.42)
		# 床头柜：两床之间、靠近床头
		_platform(platforms, cover, Vector3(x + 1.75, 0.0, z_head + dir * 0.36), 0.22, 0.22, TABLE_TOP)

	# 中央岛两排之间的实体隔墙（1.30 m，可以跳上去走）
	platforms.append({"c": Vector3.ZERO, "hx": 11.10 * U, "hz": 0.09 * U, "h": DIV_TOP * U})
	# 圆柱掩体太粗会把人推得跳不上墙，这里沿墙布一排细圆柱
	var wstep := 0.9
	var wn := int(22.2 / wstep)
	for i in wn + 1:
		_cover(cover, Vector3(-11.10 + wstep * float(i), 0.0, 0.0), 0.12, DIV_TOP - 0.42)

	# 处置柜（西端）
	for spec in [[Vector3(-18.4, 0.0, -4.0), 0.55, 0.40], [Vector3(-18.4, 0.0, 4.0), 0.55, 0.40]]:
		var p: Vector3 = spec[0]
		_platform(platforms, cover, p, float(spec[1]), float(spec[2]), CAB_TOP)

	# 护士站（西端）
	platforms.append({"c": Vector3(-16.6 * U, 0.0, 0.0), "hx": 0.45 * U, "hz": 1.50 * U, "h": 1.05 * U})
	for k in 5:
		_cover(cover, Vector3(-16.6, 0.0, -1.5 + 0.75 * float(k)), 0.38, 1.05 - 0.42)

	var bounds := AABB(Vector3(-HALF_X * U, 0.0, -HALF_Z * U),
		Vector3(HALF_X * 2.0 * U, H * U, HALF_Z * 2.0 * U))

	var spawn := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(10.0, 0.0, 4.9) * U)

	return {
		"node": root,
		"kind": "ward",
		"name_cn": "病房 · 夜班",
		"hint": "床、床头柜、隔墙都能跳上去",
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


static func P(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * U


static func S(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * U


static func _wall(walls: Array, a: Vector2, b: Vector2, h: float, n: Vector2) -> void:
	walls.append({"a": a * U, "b": b * U, "h": h * U, "n": n.normalized()})


static func _cover(cover: Array, c: Vector3, phys_r: float, h: float, base_y := 0.0) -> void:
	cover.append({"c": Vector3(c.x * U, base_y * U, c.z * U), "r": phys_r * U + BALL,
		"h": h * U, "cam": base_y <= 0.01})


static func _platform(platforms: Array, cover: Array, c: Vector3, hx: float, hz: float, top: float) -> void:
	platforms.append({"c": Vector3(c.x * U, 0.0, c.z * U), "hx": hx * U, "hz": hz * U, "h": top * U})
	_cover(cover, c, maxf(hx, hz) * 0.92, top - 0.42)


static func _mb(root: Node3D, size: Vector3, pos: Vector3, mat: Material, yaw := 0.0,
		shadow := true) -> MeshInstance3D:
	var mi := Kit.box(root, size * U, pos * U, mat, Vector3(0.0, yaw, 0.0))
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------ 环境
static func _env(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.010, 0.018, 0.020)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# 环境光偏冷偏灰：暖光才有地方“跳出来”，否则整间都是橘子色
	env.ambient_light_color = Color(0.225, 0.235, 0.240)
	env.ambient_light_energy = 3.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.18
	env.tonemap_white = 2.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.24
	env.adjustment_saturation = 1.02
	env.adjustment_brightness = 0.98

	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 0.95
	env.glow_hdr_threshold = 0.90
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.048, 0.050, 0.045)
	env.fog_light_energy = 1.0
	env.fog_depth_begin = 8.0 * U
	env.fog_depth_end = 46.0 * U
	env.fog_density = 0.14

	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.15
	env.ssao_power = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 36
	env.ssr_fade_out = 1.4

	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.34, 0.46, 0.58)
	sun.light_energy = 0.07
	sun.rotation_degrees = Vector3(-70.0, 15.0, 0.0)
	sun.shadow_enabled = false
	root.add_child(sun)


# ------------------------------------------------------------------ 外壳
static func _shell(root: Node3D) -> void:
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://gfx/panopticon/floor.gdshader")
	floor_mat.set_shader_parameter("base_col", Vector3(0.152, 0.158, 0.146))
	floor_mat.set_shader_parameter("grout_col", Vector3(0.050, 0.052, 0.045))
	floor_mat.set_shader_parameter("stain_col", Vector3(0.080, 0.086, 0.042))
	floor_mat.set_shader_parameter("tile", 0.9)
	floor_mat.set_shader_parameter("grout", 0.014)
	floor_mat.set_shader_parameter("stain", 0.48)
	floor_mat.set_shader_parameter("wet", 0.34)
	floor_mat.set_shader_parameter("rough", 0.34)

	# 脏瓷砖墙裙 + 近黑上墙：赛博朋克病房的“用了几十年”感
	var low := Kit.std(Color(0.215, 0.228, 0.205), 0.62, 0.05,
		{"noise": 2.4, "grime": 0.55, "bump": 0.28, "tint": 0.18, "streak": 0.45})
	var upper := Kit.std(Color(0.150, 0.160, 0.155), 0.80, 0.02,
		{"noise": 1.8, "grime": 0.34, "bump": 0.10, "streak": 0.30})
	# 天花板/压边：高金属度在没有环境贴图时会变成纯黑，这里必须用漫反射
	var trim := Kit.std(Color(0.260, 0.265, 0.250), 0.88, 0.02,
		{"noise": 1.4, "grime": 0.30, "bump": 0.16, "streak": 0.18})
	var steel := Kit.std(Color(0.115, 0.128, 0.128), 0.35, 0.8)
	# 唯一保留的冷光：设备青
	var neon := Kit.emissive(Color(0.16, 0.80, 0.78), 1.0)
	# 应急/警示红
	var neon_m := Kit.emissive(Color(0.95, 0.16, 0.14), 1.1)

	Kit.box(root, S(HALF_X * 2.0, 0.4, HALF_Z * 2.0), P(0.0, -0.2, 0.0), floor_mat)
	Kit.box(root, S(HALF_X * 2.0, 0.3, HALF_Z * 2.0), P(0.0, H + 0.15, 0.0), trim)

	# 西墙（挂镜子的那面）整组标到 layer 3，镜像相机看不到它们
	var wall_specs := [[S(HALF_X * 2.4, H, 0.3), P(0.0, H * 0.5, -HALF_Z - 0.15)],
			[S(HALF_X * 2.4, H, 0.3), P(0.0, H * 0.5, HALF_Z + 0.15)],
			[S(0.3, H, HALF_Z * 2.4), P(-HALF_X - 0.15, H * 0.5, 0.0)],
			[S(0.3, H, HALF_Z * 2.4), P(HALF_X + 0.15, H * 0.5, 0.0)]]
	_tint_layers(root, wall_specs, upper, 2)

	var low_specs := [[S(HALF_X * 2.2, 1.6, 0.12), P(0.0, 0.8, -HALF_Z + 0.06)],
			[S(HALF_X * 2.2, 1.6, 0.12), P(0.0, 0.8, HALF_Z - 0.06)],
			[S(0.12, 1.6, HALF_Z * 2.2), P(-HALF_X + 0.06, 0.8, 0.0)],
			[S(0.12, 1.6, HALF_Z * 2.2), P(HALF_X - 0.06, 0.8, 0.0)]]
	_tint_layers(root, low_specs, low, 2)

	var neon_specs := [[S(HALF_X * 2.0, 0.06, 0.04), P(0.0, 1.62, -HALF_Z + 0.10)],
			[S(HALF_X * 2.0, 0.06, 0.04), P(0.0, 1.62, HALF_Z - 0.10)],
			[S(0.04, 0.06, HALF_Z * 2.0), P(-HALF_X + 0.10, 1.62, 0.0)],
			[S(0.04, 0.06, HALF_Z * 2.0), P(HALF_X - 0.10, 1.62, 0.0)]]
	_tint_layers(root, neon_specs, neon, 2)

	var neon_m_specs := [[S(HALF_X * 2.0, 0.05, 0.05), P(0.0, 0.10, -HALF_Z + 0.10)],
			[S(HALF_X * 2.0, 0.05, 0.05), P(0.0, 0.10, HALF_Z - 0.10)],
			[S(0.05, 0.05, HALF_Z * 2.0), P(-HALF_X + 0.10, 0.10, 0.0)],
			[S(0.05, 0.05, HALF_Z * 2.0), P(HALF_X - 0.10, 0.10, 0.0)]]
	_tint_layers(root, neon_m_specs, neon_m, 2)

	# 吊顶灯带：两排琥珀应急光，一排是坏的（只留暗灯槽）
	var warm_tube := Kit.emissive(Color(1.0, 0.90, 0.74), 1.55)
	var dead_tube := Kit.std(Color(0.055, 0.060, 0.058), 0.9, 0.0)
	for zz in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		Kit.box(root, S(HALF_X * 1.8, 0.08, 0.34), P(0.0, H - 0.10, zz), warm_tube)
	# 北侧灯带坏了一段：暗色罩子盖住中段
	Kit.box(root, S(11.0, 0.10, 0.42), P(-6.0, H - 0.115, -8.0), dead_tube)

	# 东墙双开滑门：按机体尺寸放大（洞口 3.9 × 4.0 m，人形机甲能直着走出去）
	var door_mat := Kit.std(Color(0.270, 0.285, 0.275), 0.55, 0.30,
		{"noise": 1.6, "grime": 0.35, "bump": 0.20, "streak": 0.35})
	var door_dark := Kit.std(Color(0.055, 0.060, 0.058), 0.70, 0.20)
	var warn := Kit.std(Color(0.62, 0.50, 0.10), 0.65, 0.10,
		{"noise": 1.4, "grime": 0.55, "bump": 0.18})
	for sz in [2.93, 6.87]:
		Kit.box(root, S(0.34, 4.10, 0.30), P(HALF_X - 0.05, 2.05, sz), trim)
	Kit.box(root, S(0.34, 0.30, 4.24), P(HALF_X - 0.05, 4.10, 4.90), trim)
	# 两扇门（各 1.92 m 宽），中缝留一道暗线
	for sz in [3.96, 5.84]:
		Kit.box(root, S(0.10, 3.90, 1.88), P(HALF_X - 0.13, 1.95, sz), door_mat)
		Kit.box(root, S(0.12, 0.26, 1.88), P(HALF_X - 0.14, 0.16, sz), warn)
		Kit.box(root, S(0.12, 0.06, 1.88), P(HALF_X - 0.14, 0.30, sz), door_dark)
		Kit.box(root, S(0.12, 1.60, 0.10), P(HALF_X - 0.14, 2.55, sz), door_dark)
	Kit.box(root, S(0.14, 3.90, 0.05), P(HALF_X - 0.15, 1.95, 4.90), door_dark)
	# 门槛踏板 + 认证灯
	Kit.box(root, S(0.70, 0.05, 3.90), P(HALF_X - 0.40, 0.025, 4.90), door_dark)
	Kit.box(root, S(0.10, 0.26, 0.42), P(HALF_X - 0.20, 2.30, 6.60),
		Kit.emissive(Color(0.18, 0.85, 0.78), 1.1))
	Kit.box(root, S(0.08, 0.22, 0.72), P(HALF_X - 0.20, 4.30, 4.90),
		Kit.emissive(Color(1.0, 0.18, 0.12), 1.3))
	# 门顶横向导轨（滑门看得出来是滑的）
	Kit.box(root, S(0.16, 0.12, 4.60), P(HALF_X - 0.24, 4.00, 4.90), door_dark)

	# 南墙窗
	for i in 4:
		var wx := -12.0 + float(i) * 8.0
		_mb(root, Vector3(5.0, 2.4, 0.10), Vector3(wx, 4.0, HALF_Z - 0.10), trim, 0.0, false)
		var pane := Kit.box(root, S(4.6, 2.1, 0.04), P(wx, 4.0, HALF_Z - 0.16),
			Kit.glass(Color(0.20, 0.38, 0.45, 0.22), 0.3))
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Kit.box(root, S(0.09, 2.1, 0.05), P(wx, 4.0, HALF_Z - 0.14), steel)


## 建一排盒子，其中第 skip_idx 个标到「不参与镜像」的 layer。
static func _tint_layers(root: Node3D, specs: Array, mat: Material, skip_idx: int) -> void:
	for i in specs.size():
		var spec: Array = specs[i]
		var mi := Kit.box(root, spec[0], spec[1], mat)
		if i == skip_idx:
			mi.layers = 1 << 3


# ------------------------------------------------------------------ 镜子
## 东门对面（西墙）整面镜子。
static func _mirror(root: Node3D) -> void:
	var m = load("res://src/ward/mirror.gd").new()
	m.name = "WestMirror"
	m.position = P(-19.78, 2.86, 0.0)
	m.basis = Basis(Vector3.UP, PI * 0.5)
	root.add_child(m)
	m.setup(12.0 * U, 4.56 * U)

	# 镜框：暗金属压条（也不进镜子）
	var frame := Kit.std(Color(0.115, 0.125, 0.122), 0.45, 0.55,
		{"noise": 1.4, "grime": 0.35, "bump": 0.16})
	for spec in [[Vector3(0.14, 0.16, 12.40), Vector3(-19.74, 2.86 + 2.36, 0.0)],
			[Vector3(0.14, 0.16, 12.40), Vector3(-19.74, 2.86 - 2.36, 0.0)],
			[Vector3(0.14, 4.88, 0.16), Vector3(-19.74, 2.86, 6.12)],
			[Vector3(0.14, 4.88, 0.16), Vector3(-19.74, 2.86, -6.12)]]:
		var mi := _mb(root, spec[0], spec[1], frame, 0.0, false)
		mi.layers = 1 << 3

	# 镜面内侧一圈很淡的青色导边：远处也能看出这是块镜子而不是门
	var rim := Kit.emissive(Color(0.16, 0.72, 0.70), 0.7)
	for spec in [[Vector3(0.05, 0.05, 12.10), Vector3(-19.70, 2.86 + 2.30, 0.0)],
			[Vector3(0.05, 0.05, 12.10), Vector3(-19.70, 2.86 - 2.30, 0.0)],
			[Vector3(0.05, 4.62, 0.05), Vector3(-19.70, 2.86, 6.04)],
			[Vector3(0.05, 4.62, 0.05), Vector3(-19.70, 2.86, -6.04)]]:
		var ri := _mb(root, spec[0], spec[1], rim, 0.0, false)
		ri.layers = 1 << 3


# ------------------------------------------------------------------ 病床
static func _beds(root: Node3D) -> void:
	var frame := Kit.std(Color(0.235, 0.255, 0.250), 0.42, 0.60,
		{"noise": 1.8, "grime": 0.45, "bump": 0.32})
	# 骨白床品：偏黄、有洗不掉的旧渍
	var sheet := Kit.std(Color(0.585, 0.570, 0.500), 0.88, 0.0,
		{"noise": 2.0, "grime": 0.38, "bump": 0.35, "tint": 0.22})
	var pillow := Kit.std(Color(0.660, 0.645, 0.575), 0.90, 0.0,
		{"noise": 2.2, "grime": 0.30, "tint": 0.10})
	var dark := Kit.std(Color(0.045, 0.048, 0.046), 0.6, 0.4)
	var rail := Kit.std(Color(0.170, 0.185, 0.182), 0.35, 0.8)

	for spec in bed_spots():
		var x: float = float(spec[0])
		var z_head: float = float(spec[1])
		var dir: float = float(spec[2])
		var zc: float = z_head + dir * BED_LEN * 0.5
		# 床架 / 床垫 / 枕头
		_mb(root, Vector3(0.95, 0.42, BED_LEN), Vector3(x, 0.21, zc), frame)
		_mb(root, Vector3(0.89, 0.16, BED_LEN - 0.08), Vector3(x, 0.50, zc), sheet)
		_mb(root, Vector3(0.62, 0.10, 0.46), Vector3(x, 0.63, z_head + dir * 0.52), pillow)
		# 床头 / 床尾
		_mb(root, Vector3(0.96, 0.60, 0.07), Vector3(x, 0.86, z_head), rail)
		_mb(root, Vector3(0.96, 0.34, 0.06), Vector3(x, 0.62, z_head + dir * (BED_LEN - 0.06)), rail)
		# 侧栏
		for sx in [-0.44, 0.44]:
			for dz in [0.62, -0.62]:
				_mb(root, Vector3(0.05, 0.30, 0.05), Vector3(x + sx, 0.60, zc + dz), rail, 0.0, false)
		# 脚轮
		for sx in [-0.34, 0.34]:
			for dz in [-0.82, 0.82]:
				Kit.cylinder(root, 0.09 * U, 0.05 * U, (Vector3(x + sx, 0.09, zc + dz)) * U, dark,
					Vector3(PI * 0.5, 0.0, 0.0))
		# 床头柜（两床之间、靠近床头）
		var tx := x + 1.75
		var tz: float = z_head + dir * 0.36
		_mb(root, Vector3(0.44, 0.72, 0.44), Vector3(tx, 0.36, tz), frame)
		_mb(root, Vector3(0.48, 0.04, 0.48), Vector3(tx, 0.74, tz), rail, 0.0, false)
		# 输液架
		var ix := x - 0.72
		Kit.cylinder(root, 0.022 * U, 1.85 * U, P(ix, 0.93, tz), rail)
		Kit.cylinder(root, 0.20 * U, 0.03 * U, P(ix, 0.02, tz), dark)
		_mb(root, Vector3(0.26, 0.09, 0.05), Vector3(ix + 0.10, 1.80, tz), rail, 0.0, false)
		_mb(root, Vector3(0.15, 0.24, 0.07), Vector3(ix + 0.20, 1.62, tz), sheet, 0.0, false)


# ------------------------------------------------------------------ 隔帘
## 每张床一组吊顶轨道（两侧 + 床尾）；床间全拉，床尾按固定哈希决定拉不拉。
static func _curtains(root: Node3D) -> void:
	var steel := Kit.std(Color(0.235, 0.250, 0.245), 0.40, 0.55)
	# 帘布用布料（不是玻璃）：略透、粗糙、双面
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.775, 0.760, 0.680, 0.94)
	cloth.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloth.roughness = 0.95
	cloth.metallic = 0.0
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rail_y := 3.90

	for bi in bed_spots().size():
		var spec: Array = bed_spots()[bi]
		var x: float = float(spec[0])
		var z_head: float = float(spec[1])
		var dir: float = float(spec[2])
		var z_foot: float = z_head + dir * (BED_LEN + 0.22)
		var z_start: float = z_head + dir * 0.06
		# 轨道
		for sx in [-1.75, 1.75]:
			Kit.tube(root, P(x + sx, rail_y, z_head), P(x + sx, rail_y, z_foot), 0.012 * U, steel)
			Kit.tube(root, P(x + sx, rail_y, z_foot), P(x + sx, rail_y, H), 0.008 * U, steel)
		Kit.tube(root, P(x - 1.75, rail_y, z_foot), P(x + 1.75, rail_y, z_foot), 0.012 * U, steel)

		# 床与床之间：全部拉满（7 片，左右交替偏置出褶皱）
		for k in 7:
			var t: float = (float(k) + 0.5) / 7.0
			var zz: float = z_start + (z_foot - z_start) * t
			var off: float = 0.05 if k % 2 == 0 else -0.05
			var yaw: float = 0.10 if k % 2 == 0 else -0.10
			var cur := _mb(root, Vector3(0.06, 3.60, 0.40), Vector3(x + 1.75 + off, 2.05, zz),
				cloth, yaw, false)
			cur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# 床与过道之间：固定哈希决定这张床拉不拉；拉就整幅
		var r := _hash_i(bi, 0) % 100
		if r < 55:
			for k in 9:
				var t2: float = (float(k) + 0.5) / 9.0
				var xx: float = x - 1.75 + 3.50 * t2
				var off2: float = 0.05 if k % 2 == 0 else -0.05
				var yaw2: float = 0.10 if k % 2 == 0 else -0.10
				var cur2 := _mb(root, Vector3(0.40, 3.60, 0.06), Vector3(xx, 2.05, z_foot + off2),
					cloth, yaw2, false)
				cur2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			for k in 2:
				var xx2: float = x + 1.60 - 0.13 * float(k)
				var bun := _mb(root, Vector3(0.22, 3.60, 0.14), Vector3(xx2, 2.05, z_foot),
					cloth, 0.0, false)
				bun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _hash_i(a: int, b: int) -> int:
	return absi((a * 73856093) ^ (b * 19349663) ^ 0x2f1)


# ------------------------------------------------------------------ 道具
static func _props(root: Node3D) -> void:
	var steel := Kit.std(Color(0.125, 0.138, 0.135), 0.35, 0.8)
	var dark := Kit.std(Color(0.042, 0.045, 0.043), 0.6, 0.4)
	# 旧漆金属柜：氧化铜绿，不是干净塑料
	var teal := Kit.std(Color(0.098, 0.150, 0.130), 0.62, 0.10,
		{"noise": 2.0, "grime": 0.55, "bump": 0.32, "tint": 0.20})
	var green := Kit.emissive(Color(0.30, 1.0, 0.62), 1.7)

	# 处置柜（西端）
	for pz in [-4.0, 4.0]:
		_mb(root, Vector3(1.10, 1.28, 0.80), Vector3(-18.4, 0.64, pz), teal)
		_mb(root, Vector3(1.14, 0.06, 0.84), Vector3(-18.4, 1.29, pz), steel, 0.0, false)
		for k in 3:
			_mb(root, Vector3(0.94, 0.03, 0.80), Vector3(-18.4, 0.28 + 0.36 * float(k), pz),
				dark, 0.0, false)

	# 中央岛隔墙
	var wall_mat := Kit.std(Color(0.24, 0.40, 0.40), 0.6, 0.15,
		{"noise": 1.6, "grime": 0.3, "bump": 0.3})
	_mb(root, Vector3(25.2, 1.30, 0.16), Vector3(0.0, 0.65, 0.0), wall_mat)
	_mb(root, Vector3(25.4, 0.06, 0.22), Vector3(0.0, 1.32, 0.0), steel, 0.0, false)

	# 墙上监护仪（北墙每两床一台）
	for i in 4:
		var x := -12.25 + 7.0 * float(i) + 1.75
		_mb(root, Vector3(0.90, 0.60, 0.14), Vector3(x, 2.45, -HALF_Z + 0.16), dark, 0.0, false)
		_mb(root, Vector3(0.72, 0.42, 0.02), Vector3(x, 2.45, -HALF_Z + 0.24),
			Kit.emissive(Color(0.06, 0.42, 0.40), 1.05), 0.0, false)
		_mb(root, Vector3(0.44, 0.02, 0.01), Vector3(x, 2.46, -HALF_Z + 0.26), green, 0.0, false)

	# 护士站（西端）
	var ns := Vector3(-16.6, 0.0, 0.0)
	_mb(root, Vector3(0.90, 1.05, 3.0), ns + Vector3(0.0, 0.52, 0.0), teal)
	_mb(root, Vector3(1.00, 0.06, 3.1), ns + Vector3(0.0, 1.07, 0.0), steel, 0.0, false)
	_mb(root, Vector3(0.06, 0.50, 0.90), ns + Vector3(0.30, 1.35, -0.7), dark, 0.0, false)
	_mb(root, Vector3(0.02, 0.34, 0.74), ns + Vector3(0.34, 1.35, -0.7),
		Kit.emissive(Color(0.06, 0.40, 0.40), 1.0), 0.0, false)

	# 地面血迹 / 拖痕
	for spec in [[-8.0, 4.9, 1.6, 0.9, 0.6], [3.0, -4.9, 2.2, 1.1, 0.4], [10.5, 4.9, 1.2, 0.8, 0.9]]:
		_mb(root, Vector3(float(spec[2]), 0.006, float(spec[3])),
			Vector3(float(spec[0]), 0.008, float(spec[1])),
			Kit.std(Color(0.070, 0.022, 0.018), 0.75), float(spec[4]))


# ------------------------------------------------------------------ 灯光
static func _lights(root: Node3D) -> void:
	# 琥珀应急灯：只留 5 盏，中间大块留给阴影
	for spec in [[-15.0, -8.0, 2.6], [-15.0, 8.0, 2.2], [5.0, -8.0, 2.5],
			[15.0, 0.0, 2.4], [-5.0, 6.0, 2.2], [5.0, 8.0, 2.3],
			[-5.0, -8.0, 2.1], [15.0, 8.0, 2.0]]:
		var l := OmniLight3D.new()
		l.position = P(float(spec[0]), H - 0.9, float(spec[1]))
		l.light_color = Color(1.0, 0.88, 0.70)
		l.light_energy = float(spec[2]) * 2.3
		l.omni_range = 12.0 * U
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		root.add_child(l)

	# 备用电的冷光：让房间还有一半是蓝的
	for spec in [[-5.0, -6.0, 1.7], [10.0, 6.0, 1.5], [0.0, 0.0, 1.4]]:
		var k := OmniLight3D.new()
		k.position = P(float(spec[0]), H - 1.1, float(spec[1]))
		k.light_color = Color(0.58, 0.78, 0.88)
		k.light_energy = float(spec[2]) * 2.0
		k.omni_range = 11.0 * U
		k.omni_attenuation = 1.25
		root.add_child(k)

	# 监护仪附近的冷光：只够照亮墙上一小块
	for spec in [[-10.5, -HALF_Z + 0.9], [3.5, -HALF_Z + 0.9], [10.5, -HALF_Z + 0.9]]:
		var c := OmniLight3D.new()
		c.position = P(float(spec[0]), 2.45, float(spec[1]))
		c.light_color = Color(0.20, 0.88, 0.85)
		c.light_energy = 1.3
		c.omni_range = 6.0 * U
		c.omni_attenuation = 1.4
		root.add_child(c)

	# 天花灯带：每根下面挂 4 个光源，房间才是“亮着”的
	for zz in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for xx in [-13.5, -4.5, 4.5, 13.5]:
			if zz == -8.0 and (xx == -13.5 or xx == -4.5):
				continue
			var tl := OmniLight3D.new()
			tl.position = P(xx, H - 0.25, zz)
			tl.light_color = Color(1.0, 0.93, 0.84)
			tl.light_energy = 4.0
			tl.omni_range = 16.0 * U
			tl.omni_attenuation = 1.0
			root.add_child(tl)

	# 门口顶灯：不然门是一团黑
	var dl := OmniLight3D.new()
	dl.position = P(HALF_X - 2.2, 4.4, 4.9)
	dl.light_color = Color(1.0, 0.90, 0.76)
	dl.light_energy = 4.2
	dl.omni_range = 10.0 * U
	root.add_child(dl)

	# 两条过道各补一盏，别让中段发黑
	for spec in [[-9.0, 4.9, 3.0], [6.0, -4.9, 3.0], [-9.0, -4.9, 2.4]]:
		var al := OmniLight3D.new()
		al.position = P(float(spec[0]), H - 1.0, float(spec[1]))
		al.light_color = Color(1.0, 0.90, 0.78)
		al.light_energy = float(spec[2])
		al.omni_range = 11.0 * U
		root.add_child(al)

	# 东门应急红灯
	var r := OmniLight3D.new()
	r.position = P(HALF_X - 0.8, 2.9, 4.9)
	r.light_color = Color(1.0, 0.18, 0.14)
	r.light_energy = 2.6
	r.omni_range = 8.0 * U
	root.add_child(r)

	# 护士站一盏台灯
	var n := OmniLight3D.new()
	n.position = P(-16.6, 2.2, 0.0)
	n.light_color = Color(1.0, 0.80, 0.58)
	n.light_energy = 1.8
	n.omni_range = 6.5 * U
	root.add_child(n)

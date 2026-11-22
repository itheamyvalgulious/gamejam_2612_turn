extends RefCounted
## 回廊实验舱（Panopticon）：圆形大厅 + 中央玻璃实验罐 + 环形长廊。
##
## 中间是 R=13 m 的玻璃罐，实验体泡在液体里；玩家只能沿罐体外圈跑（回字长廊）。
## 纯场景，不放敌人（近战会打破玻璃）。

const Kit := preload("res://src/warehouse/kit.gd")

const U := 1.0 / 0.547
const BALL := 1.2
const RADIUS := 30.0        # 圆形大厅半径
const SEGMENTS := 32        # 墙体分面数
const H := 14.0             # 层高
const TANK_R := 13.0        # 玻璃罐半径
const TANK_TOP := 12.6      # 罐顶
const LIQ_TOP := 10.4       # 液面
const FLOOR_STYLE := "epoxy"   # "wet" | "epoxy" | "grating"


static func build(origin := Vector3.ZERO) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arena_panopticon"
	root.position = origin

	_env(root)
	_shell(root)
	_tank(root)
	_exit_door(root)
	_block(root)
	_details(root)
	_lab_details(root)
	_lights(root)

	var walls: Array = []
	for i in SEGMENTS:
		var a0 := TAU * float(i) / float(SEGMENTS)
		var a1 := TAU * float(i + 1) / float(SEGMENTS)
		var p0 := Vector2(cos(a0) * RADIUS, sin(a0) * RADIUS)
		var p1 := Vector2(cos(a1) * RADIUS, sin(a1) * RADIUS)
		var n := (p0 + p1) * 0.5
		n = -n.normalized()
		_wall(walls, p0, p1, H, n)

	var platforms: Array = []
	var cover: Array = []

	# 外墙：密排圆（间隔 1.9 m，远小于推开直径 2.1 m）
	# cam=false：墙的相机遮挡交给 walls 段，否则相机在贴墙时会被人为撑开的圆顶到角色脸上
	var i := 0
	while i < 96:
		var a := TAU * float(i) / 96.0
		_cover(cover, Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS), 0.45, H, 0.0, false)
		i += 1
	# 罐体：一圈密排圆
	i = 0
	while i < 80:
		var a2 := TAU * float(i) / 80.0
		_cover(cover, Vector3(cos(a2) * TANK_R, 0.0, sin(a2) * TANK_R), 0.55, TANK_TOP)
		i += 1

	# 罐边的可跳方块
	platforms.append({"c": Vector3(0.0, 0.0, 15.2 * U), "hx": 1.60 * U, "hz": 1.20 * U,
		"h": 1.10 * U})
	_cover(cover, Vector3(0.0, 0.0, 15.2), 1.45, 0.80)
	# 控制台
	_cover(cover, Vector3(4.4, 0.0, 16.4), 0.90, 1.10)

	# 四根监控臂（立杆 + 横臂 + 红灯）都要挡人
	for ai in 4:
		var a := TAU * float(ai) / 4.0 + PI * 0.25
		var dir := Vector3(cos(a), 0.0, sin(a))
		var p0 := dir * (TANK_R + 2.6)
		_cover(cover, p0, 0.20, 2.20)                       # 立杆
		_cover(cover, p0 - dir * 0.35, 0.45, 0.32, 1.94)    # 横臂
		_cover(cover, p0 - dir * 0.70, 0.16, 0.34, 1.88)    # 红灯

	var bounds := AABB(Vector3(-RADIUS * U, 0.0, -RADIUS * U),
		Vector3(RADIUS * 2.0 * U, H * U, RADIUS * 2.0 * U))

	var spawn := Transform3D(Basis(), Vector3(0.0, 0.0, 24.0 * U))

	return {
		"node": root,
		"kind": "panopticon",
		"name_cn": "回廊实验舱",
		"hint": "绕中央实验罐跑；玻璃罐别碰",
		"floor_y": 0.0,
		"bounds": bounds,
		"bounds_circle": (RADIUS - 1.0) * U,
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


static func _cover(cover: Array, c: Vector3, phys_r: float, h: float, base_y := 0.0,
		cam := true) -> void:
	cover.append({"c": Vector3(c.x * U, base_y * U, c.z * U), "r": phys_r * U + BALL,
		"h": h * U, "cam": cam and base_y <= 0.01})


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
	env.background_color = Color(0.004, 0.010, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.07, 0.13, 0.14)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.98
	env.tonemap_white = 2.6
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.20
	env.adjustment_saturation = 1.18

	env.glow_enabled = true
	env.glow_intensity = 0.95
	env.glow_strength = 1.0
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.015, 0.055, 0.055)
	env.fog_light_energy = 0.45
	env.fog_depth_begin = 12.0 * U
	env.fog_depth_end = 100.0 * U
	env.fog_density = 0.55
	env.fog_sky_affect = 0.0

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.010
	env.volumetric_fog_albedo = Color(0.05, 0.12, 0.12)
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_anisotropy = 0.25

	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.4
	env.ssao_power = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 40
	env.ssr_fade_out = 1.5

	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.45, 0.62, 0.68)
	sun.light_energy = 0.10
	sun.rotation_degrees = Vector3(-70.0, 20.0, 0.0)
	sun.shadow_enabled = false
	root.add_child(sun)


# ------------------------------------------------------------------ 圆形外壳
static func _shell(root: Node3D) -> void:
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://gfx/panopticon/floor.gdshader")
	match FLOOR_STYLE:
		"wet":
			floor_mat.set_shader_parameter("base_col", Vector3(0.042, 0.056, 0.058))
			floor_mat.set_shader_parameter("grout_col", Vector3(0.015, 0.024, 0.026))
			floor_mat.set_shader_parameter("stain_col", Vector3(0.020, 0.030, 0.030))
			floor_mat.set_shader_parameter("tile", 2.0)
			floor_mat.set_shader_parameter("grout", 0.02)
			floor_mat.set_shader_parameter("stain", 0.60)
			floor_mat.set_shader_parameter("wet", 0.55)
			floor_mat.set_shader_parameter("rough", 0.55)
		"grating":
			floor_mat.set_shader_parameter("base_col", Vector3(0.10, 0.11, 0.12))
			floor_mat.set_shader_parameter("grout_col", Vector3(0.04, 0.045, 0.05))
			floor_mat.set_shader_parameter("stain_col", Vector3(0.08, 0.07, 0.05))
			floor_mat.set_shader_parameter("tile", 1.0)
			floor_mat.set_shader_parameter("grout", 0.0)
			floor_mat.set_shader_parameter("stain", 0.20)
			floor_mat.set_shader_parameter("wet", 0.15)
			floor_mat.set_shader_parameter("grating", 1.0)
			floor_mat.set_shader_parameter("rough", 0.45)
			floor_mat.set_shader_parameter("metal", 0.55)
		_:
			# 环氧自流平：浅一点的冷灰绿，小块分隔，化学污渍
			floor_mat.set_shader_parameter("base_col", Vector3(0.105, 0.125, 0.125))
			floor_mat.set_shader_parameter("grout_col", Vector3(0.045, 0.055, 0.058))
			floor_mat.set_shader_parameter("stain_col", Vector3(0.055, 0.105, 0.085))
			floor_mat.set_shader_parameter("tile", 1.6)
			floor_mat.set_shader_parameter("grout", 0.012)
			floor_mat.set_shader_parameter("stain", 0.40)
			floor_mat.set_shader_parameter("wet", 0.10)
			floor_mat.set_shader_parameter("rough", 0.30)
	var wall := Kit.std(Color(0.095, 0.115, 0.118), 0.60, 0.45,
		{"noise": 1.2, "grime": 0.40, "bump": 0.60, "streak": 0.45,
		"dirt": Color(0.015, 0.024, 0.024)})
	var dark := Kit.std(Color(0.026, 0.034, 0.038), 0.55, 0.4)
	var steel := Kit.std(Color(0.14, 0.17, 0.18), 0.35, 0.8)
	var neon := Kit.emissive(Color(0.20, 0.85, 0.80), 1.8)
	var neon_m := Kit.emissive(Color(1.0, 0.20, 0.55), 1.5)

	# 圆盘地面 / 屋顶
	Kit.cylinder(root, (RADIUS + 0.4) * U, 0.6 * U, P(0.0, -0.30, 0.0), floor_mat)
	Kit.cylinder(root, (RADIUS + 0.4) * U, 0.5 * U, P(0.0, H, 0.0), dark)

	# 圆柱墙：32 个面
	var seg_len := TAU * RADIUS / float(SEGMENTS) * 1.04
	for i in SEGMENTS:
		var a := TAU * float(i) / float(SEGMENTS)
		var px := cos(a) * (RADIUS + 0.15)
		var pz := sin(a) * (RADIUS + 0.15)
		_mb(root, Vector3(seg_len, H, 0.30), Vector3(px, H * 0.5, pz), wall, -a - PI * 0.5)
		# 每面两道竖缝
		for k in 2:
			var off := (float(k) - 0.5) * seg_len * 0.34
			var sx := px - sin(a) * off * 0.0 + cos(a + PI * 0.5) * off
			var sz := pz + sin(a + PI * 0.5) * off
			_mb(root, Vector3(0.10, H - 0.6, 0.10), Vector3(sx, H * 0.5, sz), steel, -a - PI * 0.5)

	# 墙腰线（两圈）
	Kit.torus(root, (RADIUS - 0.05) * U, 0.05 * U, P(0.0, 4.4, 0.0), neon)
	Kit.torus(root, (RADIUS - 0.05) * U, 0.03 * U, P(0.0, 6.95, 0.0), neon_m)

	# 地面：两道环线 + 24 条放射线
	Kit.annulus(root, (TANK_R + 0.9) * U, (TANK_R + 1.3) * U, 96, 0.012 * U, neon)
	Kit.annulus(root, (RADIUS - 2.2) * U, (RADIUS - 1.8) * U, 96, 0.012 * U, neon)
	for i in 24:
		var a2 := TAU * float(i) / 24.0
		var mid_r := (TANK_R + RADIUS - 2.0) * 0.5
		var len := RADIUS - 2.0 - TANK_R
		_mb(root, Vector3(0.14, 0.012, len), Vector3(cos(a2) * mid_r, 0.012, sin(a2) * mid_r),
			neon, -a2 + PI * 0.5)

	# 天花：同心发光环 + 中心盘
	Kit.torus(root, 6.0 * U, 0.35 * U, P(0.0, H - 0.55, 0.0), neon)
	Kit.torus(root, 12.0 * U, 0.22 * U, P(0.0, H - 0.55, 0.0), neon)
	Kit.torus(root, 20.0 * U, 0.16 * U, P(0.0, H - 0.55, 0.0), neon_m)
	Kit.cylinder(root, 4.6 * U, 0.30 * U, P(0.0, H - 0.20, 0.0), dark)


# ------------------------------------------------------------------ 中央实验罐
static func _tank(root: Node3D) -> void:
	var steel := Kit.std(Color(0.13, 0.16, 0.17), 0.4, 0.75)
	var dark := Kit.std(Color(0.03, 0.04, 0.045), 0.6, 0.3)
	var glass := Kit.glass(Color(0.42, 0.80, 0.74, 0.16), 0.22)
	var glow := Kit.emissive(Color(0.25, 0.95, 0.80), 1.6)

	# 基座
	Kit.cylinder(root, (TANK_R + 0.6) * U, 0.70 * U, P(0.0, 0.35, 0.0), steel)
	Kit.torus(root, (TANK_R + 0.15) * U, 0.10 * U, P(0.0, 0.80, 0.0), glow)
	# 玻璃筒
	Kit.cylinder(root, TANK_R * U, (TANK_TOP - 0.70) * U, P(0.0, (TANK_TOP + 0.70) * 0.5, 0.0), glass)
	# 罐口箍
	Kit.torus(root, TANK_R * U, 0.24 * U, P(0.0, TANK_TOP, 0.0), steel)
	Kit.torus(root, TANK_R * U, 0.10 * U, P(0.0, TANK_TOP - 0.06, 0.0), glow)

	# 液体
	var liq := ShaderMaterial.new()
	liq.shader = load("res://gfx/panopticon/liquid.gdshader")
	liq.set_shader_parameter("top_col", Color(0.10, 0.42, 0.38))
	liq.set_shader_parameter("deep_col", Color(0.02, 0.12, 0.13))
	liq.set_shader_parameter("alpha", 0.46)
	liq.set_shader_parameter("base_y", 0.78)
	liq.set_shader_parameter("span", LIQ_TOP - 0.78)
	var liq_mesh := Kit.cylinder(root, (TANK_R - 0.22) * U, (LIQ_TOP - 0.78) * U,
		P(0.0, (LIQ_TOP + 0.78) * 0.5, 0.0), liq)
	liq_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var liq_cyl := liq_mesh.mesh as CylinderMesh
	if liq_cyl != null:
		liq_cyl.cap_bottom = false          # 底面不要那个发亮的大圆盘

	# 实验体：很小的标本，沉在液体深处
	var flesh := Kit.std(Color(0.10, 0.13, 0.13), 0.75, 0.05,
		{"noise": 2.0, "grime": 0.5, "bump": 0.6, "dirt": Color(0.02, 0.03, 0.03)})
	var eye := Kit.emissive(Color(1.0, 0.55, 0.35), 2.2)
	var core_y := 3.0
	var body := SphereMesh.new()
	body.radius = 0.46 * U
	body.height = 1.00 * U
	var bi := MeshInstance3D.new()
	bi.mesh = body
	bi.material_override = flesh
	bi.position = P(0.0, core_y, 0.0)
	root.add_child(bi)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var base := P(cos(a) * 0.34, core_y - 0.20, sin(a) * 0.34)
		var tip := P(cos(a) * 0.78, core_y - 0.78 + 0.12 * float(i % 2), sin(a) * 0.78)
		Kit.tube(root, base * U, tip * U, 0.055 * U, flesh)
	# 支撑杆：从罐底托住标本
	Kit.cylinder(root, 0.035 * U, core_y * U, P(0.0, core_y * 0.5, 0.0), steel)
	for i in 4:
		var a2 := TAU * float(i) / 4.0 + 0.4
		var s := SphereMesh.new()
		s.radius = 0.035 * U
		s.height = 0.07 * U
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = eye
		mi.position = P(cos(a2) * 0.26, core_y + 0.26, sin(a2) * 0.26)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

	# 罐内灯
	for spec in [[0.0, 3.0, 0.0, Color(0.20, 0.95, 0.75)], [0.0, 9.8, 0.0, Color(0.16, 0.75, 0.95)]]:
		var l := OmniLight3D.new()
		l.position = P(float(spec[0]), float(spec[1]), float(spec[2]))
		l.light_color = spec[3]
		l.light_energy = 5.0
		l.omni_range = 16.0 * U
		l.omni_attenuation = 1.0
		root.add_child(l)


# ------------------------------------------------------------------ 单侧出口
static func _exit_door(root: Node3D) -> void:
	var dark := Kit.std(Color(0.07, 0.08, 0.09), 0.55, 0.4)
	var steel := Kit.std(Color(0.24, 0.27, 0.28), 0.4, 0.8)
	var hazard := Kit.emissive(Color(1.0, 0.62, 0.10), 0.8)
	var green := Kit.emissive(Color(0.25, 1.0, 0.55), 1.6)
	var dz := RADIUS - 0.35

	# 门内凹槽（深色背板）
	_mb(root, Vector3(6.4, 5.2, 0.10), Vector3(0.0, 2.6, dz - 0.08), dark, 0.0, false)
	# 门框：两侧立柱 + 门楣（不是一整块，否则把门挡住）
	for sx in [-1.0, 1.0]:
		_mb(root, Vector3(0.55, 5.8, 0.55), Vector3(sx * 3.45, 2.9, dz), steel, 0.0, false)
	_mb(root, Vector3(7.6, 0.55, 0.55), Vector3(0.0, 5.45, dz), steel, 0.0, false)
	# 双开滑门（关闭状态）
	for sx in [-1.0, 1.0]:
		_mb(root, Vector3(3.05, 4.95, 0.16), Vector3(sx * 1.55, 2.48, dz - 0.26), steel, 0.0, false)
		# 门缝
		_mb(root, Vector3(0.06, 4.95, 0.20), Vector3(sx * 0.03, 2.48, dz - 0.34), dark, 0.0, false)
		# 竖向加强肋
		for k in 3:
			_mb(root, Vector3(0.10, 4.5, 0.06), Vector3(sx * (0.7 + float(k) * 0.9), 2.48, dz - 0.36),
				steel, 0.0, false)
	# 门楣 + 警示条 + 出口灯
	_mb(root, Vector3(7.2, 0.5, 0.5), Vector3(0.0, 5.35, dz), dark, 0.0, false)
	for k in 7:
		_mb(root, Vector3(0.52, 0.22, 0.06), Vector3(-2.7 + float(k) * 0.9, 5.35, dz - 0.28),
			hazard if k % 2 == 0 else dark, 0.0, false)
	_mb(root, Vector3(2.2, 0.36, 0.10), Vector3(0.0, 5.75, dz - 0.26), green, 0.0, false)
	# 门侧读卡器
	_mb(root, Vector3(0.22, 0.34, 0.10), Vector3(3.9, 1.45, dz - 0.30), dark, 0.0, false)
	_mb(root, Vector3(0.08, 0.10, 0.04), Vector3(3.9, 1.52, dz - 0.36), green, 0.0, false)
	# 地面黄线
	_mb(root, Vector3(7.4, 0.012, 0.22), Vector3(0.0, 0.014, dz - 1.3), hazard, 0.0, false)
	# 门两侧照明
	for sx in [-3.6, 3.6]:
		var l := OmniLight3D.new()
		l.position = P(sx, 4.6, dz - 1.4)
		l.light_color = Color(0.85, 0.95, 1.0)
		l.light_energy = 4.0
		l.omni_range = 9.0 * U
		l.omni_attenuation = 1.0
		root.add_child(l)


# ------------------------------------------------------------------ 控制台
static func _boxb(root: Node3D, size: Vector3, pos: Vector3, mat: Material, basis: Basis) -> MeshInstance3D:
	var mi := Kit.box(root, size * U, pos * U, mat)
	mi.basis = basis
	return mi


static func _knob(root: Node3D, pos: Vector3, normal: Vector3, radius: float, mat: Material) -> void:
	var mi := Kit.cylinder(root, radius * U, 0.022 * U, pos * U, mat)
	mi.basis = Basis(Quaternion(Vector3.UP, normal))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ 罐边方块
static func _block(root: Node3D) -> void:
	# 一个长方体台子，台面上就是控制台（不是旁边再摆一个独立的）
	var body := Kit.std(Color(0.16, 0.18, 0.19), 0.60, 0.35,
		{"noise": 2.0, "grime": 0.30, "bump": 0.6, "dirt": Color(0.05, 0.06, 0.06)})
	var trim := Kit.std(Color(0.22, 0.24, 0.25), 0.45, 0.60)
	var panel := Kit.std(Color(0.15, 0.165, 0.175), 0.60, 0.35)
	var frame := Kit.std(Color(0.06, 0.07, 0.08), 0.50, 0.60)
	var hazard := Kit.emissive(Color(1.0, 0.62, 0.10), 0.75)
	var cols := [Color(0.95, 0.25, 0.20), Color(1.0, 0.66, 0.16), Color(0.30, 1.0, 0.55),
		Color(0.30, 0.75, 1.0), Color(0.88, 0.88, 0.82)]
	var c := Vector3(0.0, 0.0, 15.2)

	# 箱体：顶面 1.10（站立面在靠外的一侧）
	_mb(root, Vector3(3.20, 1.10, 2.40), c + Vector3(0.0, 0.55, 0.0), body)
	_mb(root, Vector3(3.26, 0.06, 2.46), c + Vector3(0.0, 1.07, 0.0), trim, 0.0, false)
	for k in 4:
		_mb(root, Vector3(0.03, 1.04, 2.42), c + Vector3(-1.2 + float(k) * 0.8, 0.55, 0.0),
			trim, 0.0, false)
	for sz in [-1.0, 1.0]:
		_mb(root, Vector3(2.9, 0.012, 0.10), c + Vector3(0.0, 1.104, sz * 1.05), hazard, 0.0, false)

	# ---- 台面上的控制台：两层斜面（靠罐体一侧），后侧留 1 m 站立面
	var low_b := Basis(Vector3.RIGHT, 0.29)
	var low_c := c + Vector3(0.0, 1.19, 0.0)
	var low_n := low_b * Vector3.UP
	_boxb(root, Vector3(2.86, 0.07, 0.62), low_c, panel, low_b)
	# 三排按键，每排七个
	for row in 3:
		for k in 7:
			var p := low_c + low_b * Vector3(-1.14 + 0.38 * float(k), 0.0, -0.18 + 0.18 * float(row))
			_knob(root, p + low_n * 0.050, low_n, 0.040,
				Kit.emissive(cols[(k + row) % cols.size()], 0.95))

	var up_b := Basis(Vector3.RIGHT, 0.40)
	var up_c := c + Vector3(0.0, 1.40, -0.60)
	var up_n := up_b * Vector3.UP
	_boxb(root, Vector3(2.86, 0.07, 0.62), up_c, panel, up_b)
	# 两块小显示器 + 中间一个表盘
	for k in 2:
		var p3 := up_c + up_b * Vector3(-0.80 + 1.60 * float(k), 0.0, 0.0)
		_boxb(root, Vector3(0.66, 0.03, 0.34), p3 + up_n * 0.045, frame, up_b)
		var scr := _boxb(root, Vector3(0.58, 0.02, 0.27), p3 + up_n * 0.064,
			Kit.emissive(Color(0.16, 0.60, 0.68), 2.2), up_b)
		scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pg := up_c + up_b * Vector3(0.0, 0.0, 0.0)
	var ring := Kit.torus(root, 0.085 * U, 0.012 * U, (pg + up_n * 0.050) * U,
		Kit.std(Color(0.30, 0.32, 0.34), 0.4, 0.7))
	ring.basis = up_b
	var needle := _boxb(root, Vector3(0.072, 0.008, 0.010), pg + up_n * 0.064,
		Kit.emissive(Color(1.0, 0.45, 0.15), 1.5), up_b)
	needle.basis = up_b * Basis(Vector3.UP, 0.9)

	# 后排立板 + 指示灯
	_mb(root, Vector3(2.86, 0.34, 0.10), Vector3(c.x, 1.36, c.z - 1.02), panel)
	for k in 6:
		_mb(root, Vector3(0.14, 0.05, 0.02),
			Vector3(c.x - 0.90 + 0.36 * float(k), 1.38, c.z - 1.08),
			Kit.emissive(cols[k % cols.size()], 1.6), 0.0, false)

	# 台面上一盏小工作灯（照亮按键）
	var bar := Kit.box(root, Vector3(2.2, 0.04, 0.08) * U,
		(Vector3(c.x, 1.86, c.z - 0.75)) * U, Kit.emissive(Color(0.85, 0.95, 1.0), 1.8))
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-0.9, 0.9]:
		Kit.box(root, Vector3(0.04, 0.68, 0.04) * U,
			(Vector3(c.x + sx, 1.52, c.z - 0.75)) * U, frame)
	var tl := OmniLight3D.new()
	tl.position = P(0.0, 1.70, 14.4)
	tl.light_color = Color(0.85, 0.95, 1.0)
	tl.light_energy = 3.4
	tl.omni_range = 5.0 * U
	tl.omni_attenuation = 1.3
	root.add_child(tl)


# ------------------------------------------------------------------ 细节
static func _details(root: Node3D) -> void:
	var steel := Kit.std(Color(0.15, 0.18, 0.19), 0.4, 0.8)
	var dark := Kit.std(Color(0.04, 0.05, 0.055), 0.6, 0.3)
	var neon := Kit.emissive(Color(0.20, 0.85, 0.80), 1.6)

	# 墙上的观察窗 / 舱门（圆形监狱的“牢房”）
	for i in 16:
		var a := TAU * float(i) / 16.0 + 0.09
		var px := cos(a) * (RADIUS - 0.12)
		var pz := sin(a) * (RADIUS - 0.12)
		var yaw := -a - PI * 0.5
		_mb(root, Vector3(2.6, 3.0, 0.10), Vector3(px, 1.9, pz), dark, yaw, false)
		_mb(root, Vector3(2.2, 2.6, 0.04), Vector3(px - cos(a) * 0.06, 1.9, pz - sin(a) * 0.06),
			Kit.std(Color(0.08, 0.10, 0.11), 0.6, 0.3), yaw, false)
		# 观察窗
		_mb(root, Vector3(1.5, 0.8, 0.05), Vector3(px - cos(a) * 0.10, 2.6, pz - sin(a) * 0.10),
			Kit.emissive(Color(0.10, 0.40, 0.42), 0.7), yaw, false)
		_mb(root, Vector3(0.10, 0.36, 0.05), Vector3(px - cos(a) * 0.10, 1.1, pz - sin(a) * 0.10),
			neon, yaw, false)

	# 罐体四周的监控臂
	for i in 4:
		var a2 := TAU * float(i) / 4.0 + PI * 0.25
		var p0 := Vector3(cos(a2) * (TANK_R + 2.6), 0.0, sin(a2) * (TANK_R + 2.6))
		Kit.box(root, S(0.18, 2.2, 0.18), P(p0.x, 1.1, p0.z), dark)
		Kit.box(root, S(0.7, 0.18, 0.18), P(p0.x - cos(a2) * 0.35, 2.1, p0.z - sin(a2) * 0.35), dark,
			Vector3(0.0, -a2, 0.0))
		Kit.box(root, S(0.10, 0.10, 0.10) * U,
			Vector3(p0.x - cos(a2) * 0.7, 2.05, p0.z - sin(a2) * 0.7) * U,
			Kit.emissive(Color(1.0, 0.2, 0.2), 2.0))

	# 罐体周围的检修平台（矮台阶，不挡路）
	for i in 6:
		var a3 := TAU * float(i) / 6.0 + 0.2
		var r0 := TANK_R + 2.0
		_mb(root, Vector3(1.6, 0.35, 0.9),
			Vector3(cos(a3) * r0, 0.175, sin(a3) * r0), steel, -a3 - PI * 0.5)

	# 地面油污 / 水渍由 floor shader 处理；这里补几段贴地管线
	for i in 3:
		var a4 := TAU * float(i) / 3.0 + 0.6
		var r1 := TANK_R + 3.0
		_mb(root, Vector3(4.0, 0.10, 0.16),
			Vector3(cos(a4) * r1, 0.10, sin(a4) * r1), steel, -a4 + PI * 0.5)


# ------------------------------------------------------------------ 实验室痕迹
static func _lab_details(root: Node3D) -> void:
	var panel := Kit.std(Color(0.045, 0.058, 0.062), 0.75, 0.15)
	var steel := Kit.std(Color(0.18, 0.21, 0.22), 0.4, 0.8)
	var dark := Kit.std(Color(0.03, 0.04, 0.045), 0.6, 0.3)
	var yellow := Kit.emissive(Color(1.0, 0.68, 0.12), 0.7)

	# 1) 墙上贴的便签（手写涂鸦，不是印刷公式）
	_notes(root)

	# 2) 警示喷字（4 处）
	var stencils := ["CONTAINMENT 02", "BIOHAZARD", "SPECIMEN 07", "NO ENTRY"]
	for i in 4:
		var a2 := TAU * (float(i) + 0.5) / 4.0
		var px2 := cos(a2) * (RADIUS - 0.14)
		var pz2 := sin(a2) * (RADIUS - 0.14)
		var yawp2 := -a2 - PI * 0.5
		var yawt2 := atan2(-cos(a2), -sin(a2))
		_mb(root, Vector3(4.0, 0.72, 0.05), Vector3(px2, 4.02, pz2), panel, yawp2, false)
		_mb(root, Vector3(4.0, 0.07, 0.06), Vector3(px2, 3.70, pz2), yellow, yawp2, false)
		_label3d(root, Vector3(px2 - cos(a2) * 0.07, 4.06, pz2 - sin(a2) * 0.07),
			yawt2, String(stencils[i]), 0.0080, Color(0.95, 0.74, 0.28), 64)

	# 4) 沿墙管线 + 卡箍
	Kit.torus(root, (RADIUS - 0.45) * U, 0.07 * U, P(0.0, 7.45, 0.0), steel)
	Kit.torus(root, (RADIUS - 0.55) * U, 0.05 * U, P(0.0, 8.05, 0.0), steel)
	for i in 24:
		var a3 := TAU * float(i) / 24.0
		_mb(root, Vector3(0.10, 0.30, 0.62), Vector3(cos(a3) * (RADIUS - 0.45), 7.75, sin(a3) * (RADIUS - 0.45)),
			dark, -a3 - PI * 0.5, false)
	# 5) 通风口
	for i in 8:
		var a4 := TAU * (float(i) + 0.5) / 8.0
		var px4 := cos(a4) * (RADIUS - 0.10)
		var pz4 := sin(a4) * (RADIUS - 0.10)
		var yaw4 := -a4 - PI * 0.5
		_mb(root, Vector3(1.6, 0.7, 0.12), Vector3(px4, 8.75, pz4), dark, yaw4, false)
		for k in 4:
			_mb(root, Vector3(1.4, 0.05, 0.03),
				Vector3(px4 - cos(a4) * 0.05, 8.55 + 0.14 * float(k), pz4 - sin(a4) * 0.05),
				steel, yaw4, false)

	# 6) 罐体基座上的铭牌
	_label3d(root, Vector3(0.0, 0.55, TANK_R + 0.72), 0.0,
		"SPEC-07  ·  BIO-CONTAINMENT", 0.0055, Color(0.75, 0.86, 0.85), 64)


static func _notes(root: Node3D) -> void:
	var papers := [Color(0.76, 0.75, 0.69), Color(0.82, 0.78, 0.64), Color(0.68, 0.74, 0.73),
		Color(0.74, 0.70, 0.62)]
	var inks := [Color(0.13, 0.14, 0.15), Color(0.16, 0.12, 0.10), Color(0.10, 0.16, 0.18)]
	var tape := Kit.glass(Color(0.86, 0.86, 0.80, 0.35), 0.5)
	var notes := [
		"it is still alive.",
		"do not open this door.",
		"who moved the ladder?",
		"the seal broke on 11/03.",
		"it hums at 3 a.m. every night.",
		"burn this note after reading.",
		"the readout is lying.",
		"sample 3 went to fridge B.",
		"mass +2.3 kg. no intake.",
		"turn off the lights if it looks at you.",
		"ask K. about the teeth.",
		"we are not alone in here.",
	]
	# 四簇，每簇三四张，像随手贴上去的
	var clusters := [0.35, 1.95, 3.35, 5.05]
	for i in notes.size():
		var ci := i / 4
		var kk := i % 4
		var a: float = float(clusters[ci]) + (float(kk) - 1.5) * 0.030
		var hsh := float((i * 37) % 100) / 100.0
		var hsh2 := float((i * 53) % 100) / 100.0
		var y := 2.20 + 0.26 * float(kk) + 0.22 * hsh
		var w := 0.62 + 0.10 * hsh2
		var h := 0.82 + 0.10 * hsh
		var roll := (hsh2 - 0.5) * 0.26
		var yaw := atan2(-cos(a), -sin(a))
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3(0.0, 0.0, 1.0), roll)
		var n := b * Vector3(0.0, 0.0, 1.0)
		var pos := Vector3(cos(a) * (RADIUS - 0.16), y, sin(a) * (RADIUS - 0.16))

		var q := Kit.quad(root, Vector2(w, h) * U, pos * U,
			Kit.emissive(papers[i % papers.size()], 0.55))
		q.basis = b
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 胶带
		for sx in [-1.0, 1.0]:
			var tp := Kit.quad(root, Vector2(0.12, 0.045) * U,
				(pos + b * Vector3(sx * w * 0.36, h * 0.46, 0.006)) * U, tape,
				Vector3(0.0, yaw, roll))
			tp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 手写内容（字体只有一种，靠字号/角度/换行做出潦草感）
		var l := Label3D.new()
		l.text = String(notes[i])
		l.font = load("res://assets/fonts/DejaVuSans.ttf")
		l.font_size = 44
		l.pixel_size = 0.0024
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = int(w / 0.0024 * 0.86)
		l.modulate = inks[i % inks.size()]
		l.outline_size = 0
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.position = (pos + n * 0.012) * U
		l.basis = b
		root.add_child(l)


static func _label3d(root: Node3D, pos: Vector3, yaw: float, text: String, pix: float,
		col: Color, fs := 64) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/DejaVuSans.ttf")
	l.font_size = fs
	l.pixel_size = pix
	l.modulate = col
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.position = pos * U
	l.rotation = Vector3(0.0, yaw, 0.0)
	root.add_child(l)


# ------------------------------------------------------------------ 灯光
static func _lights(root: Node3D) -> void:
	for i in 16:
		var a := TAU * float(i) / 16.0
		var l := OmniLight3D.new()
		l.position = P(cos(a) * 21.0, 12.2, sin(a) * 21.0)
		l.light_color = Color(0.70, 0.88, 0.92)
		l.light_energy = 3.6
		l.omni_range = 16.0 * U
		l.omni_attenuation = 1.0
		l.light_volumetric_fog_energy = 0.5
		root.add_child(l)
	for i in 8:
		var a2 := TAU * float(i) / 8.0
		var l2 := OmniLight3D.new()
		l2.position = P(cos(a2) * (TANK_R + 3.5), 1.6, sin(a2) * (TANK_R + 3.5))
		l2.light_color = Color(0.18, 0.90, 0.78)
		l2.light_energy = 3.0
		l2.omni_range = 11.0 * U
		l2.omni_attenuation = 1.2
		root.add_child(l2)
	# 低位洗墙灯（照墙上的纸和舱门）
	for i in 8:
		var a5 := TAU * (float(i) + 0.5) / 8.0
		var l5 := OmniLight3D.new()
		l5.position = P(cos(a5) * 27.0, 3.4, sin(a5) * 27.0)
		l5.light_color = Color(0.72, 0.86, 0.88)
		l5.light_energy = 2.2
		l5.omni_range = 7.0 * U
		l5.omni_attenuation = 1.2
		root.add_child(l5)

	# 墙面洗光
	for i in 8:
		var a3 := TAU * float(i) / 8.0 + 0.2
		var l3 := OmniLight3D.new()
		l3.position = P(cos(a3) * 26.5, 6.5, sin(a3) * 26.5)
		l3.light_color = Color(0.55, 0.72, 0.76)
		l3.light_energy = 3.2
		l3.omni_range = 13.0 * U
		l3.omni_attenuation = 1.2
		root.add_child(l3)

	var top := OmniLight3D.new()
	top.position = P(0.0, 13.0, 0.0)
	top.light_color = Color(0.60, 0.85, 0.95)
	top.light_energy = 6.0
	top.omni_range = 30.0 * U
	root.add_child(top)

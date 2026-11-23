extends RefCounted
## ArenaEnv — 每个关卡自带的大气 / 灯光 / 天气（全部程序化，无外部资源）。
##
## 采用 Forward+ 特性组合：glow 泛光 + SSAO + SSR + 距离雾 + 程序化天空 + 雨幕/蒸汽。
## 刻意 **不使用** Environment.volumetric_fog：froxel 网格在本项目会产生全屏规则网纹。
##
## 调色板字典由 arena_art.gd 顶部的 PAL_* 提供，字段含义见那里的注释。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const SKY_SHADER := preload("res://gfx/sky.gdshader")
const RAIN_SHADER := preload("res://gfx/rain.gdshader")
const STEAM_SHADER := preload("res://gfx/arena_steam.gdshader")
const GLOW_SHADER := preload("res://gfx/arena_glow.gdshader")


# ------------------------------------------------------------------ atmosphere

static func atmosphere(pal: Dictionary) -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = sky_material(pal)
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = pal["amb_col"]
	env.ambient_light_sky_contribution = pal["sky_contrib"]
	env.ambient_light_energy = pal["amb_energy"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# 色调映射 / 调色：偏冷对比，用 filmic 压住霓虹高光
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = pal["exposure"]
	env.tonemap_white = 2.4
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = pal["contrast"]
	env.adjustment_saturation = pal["sat"]

	# 泛光：霓虹与灯具的主要“空气感”来源
	env.glow_enabled = true
	env.glow_intensity = pal["glow_intensity"]
	env.glow_strength = pal["glow_strength"]
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = pal["glow_hdr"]
	env.glow_hdr_scale = 1.5
	env.glow_normalized = false
	var levels := [0.0, 0.35, 0.7, 0.95, 0.6, 0.35, 0.18]
	for i in 7:
		env.set_glow_level(i, levels[i])

	# 距离雾：按深度雾，近处干净、远处被霓虹霾吃掉
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = pal["fog_col"]
	env.fog_light_energy = pal["fog_energy"]
	env.fog_depth_begin = pal["fog_begin"]
	env.fog_depth_end = pal["fog_end"]
	env.fog_depth_curve = pal["fog_curve"]
	env.fog_density = pal["fog_density"]
	env.fog_sky_affect = pal["fog_sky"]
	env.fog_height = pal["fog_height"]
	env.fog_height_density = pal["fog_height_density"]
	env.fog_aerial_perspective = 0.28

	# SSAO：沟槽暗部、街角接地
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = pal["ssao"]
	env.ssao_power = 2.2
	env.ssao_detail = 0.85
	env.ssao_horizon = 0.03
	env.ssao_sharpness = 0.92
	env.ssao_light_affect = 0.4

	# SSR：湿沥青 / 水洼镜像霓虹
	env.ssr_enabled = true
	env.ssr_max_steps = 40
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.8
	env.ssr_depth_tolerance = 0.32

	# SSIL / SDFGI 关闭（性能）
	env.ssil_enabled = false
	env.sdfgi_enabled = false

	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	return we


static func sky_material(pal: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SKY_SHADER
	m.set_shader_parameter("night", pal["sky_night"])
	m.set_shader_parameter("sky_gain", pal["sky_gain"])
	m.set_shader_parameter("zenith_col", pal["sky_zenith"])
	m.set_shader_parameter("mid_col", pal["sky_mid"])
	m.set_shader_parameter("horizon_col", pal["sky_horizon"])
	m.set_shader_parameter("city_glow", pal["sky_glow"])
	m.set_shader_parameter("smog", pal["sky_smog"])
	m.set_shader_parameter("cloud_cover", pal["sky_cloud"])
	m.set_shader_parameter("stars", pal["sky_stars"])
	m.set_shader_parameter("moon_dir", pal["moon_dir"])
	return m


# ------------------------------------------------------------------ lights

## 主平行光（月光/城市辉光方向）+ 补光；阴影只开主光，且只覆盖场地本身。
static func lights(parent: Node3D, pal: Dictionary) -> void:
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_color = pal["key_col"]
	key.light_energy = pal["key_energy"]
	key.light_angular_distance = 1.2
	key.rotation_degrees = pal["key_rot"]
	key.shadow_enabled = pal["key_shadow"]
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key.directional_shadow_max_distance = pal["shadow_dist"]
	key.shadow_bias = 0.05
	key.shadow_normal_bias = 1.6
	parent.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = pal["fill_col"]
	fill.light_energy = pal["fill_energy"]
	fill.rotation_degrees = Vector3(-26, -58, 0)
	fill.shadow_enabled = false
	parent.add_child(fill)


static func omni(parent: Node3D, pos: Vector3, col: Color, range_m: float,
		energy: float, att := 1.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.omni_range = range_m
	l.omni_attenuation = att
	l.light_energy = energy
	l.shadow_enabled = false
	l.light_bake_mode = Light3D.BAKE_DISABLED
	parent.add_child(l)
	return l


static func spot(parent: Node3D, xf: Transform3D, col: Color, range_m: float,
		energy: float, angle_deg: float, att := 1.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.transform = xf
	l.light_color = col
	l.spot_range = range_m
	l.spot_angle = angle_deg
	l.spot_angle_attenuation = 0.6
	l.spot_attenuation = att
	l.light_energy = energy
	l.shadow_enabled = false
	l.light_bake_mode = Light3D.BAKE_DISABLED
	parent.add_child(l)
	return l


## 加性光晕（朝向相机的圆盘）：灯具的“强光晕”。size 为直径（米）。
static func halo(parent: Node3D, pos: Vector3, size: float, col: Color,
		strength: float, seed := 0.0, core := 0.10, flicker := 0.0,
		halo_amt := 1.0, height_scale := 1.0) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("core", core)
	mat.set_shader_parameter("halo", halo_amt)
	mat.set_shader_parameter("seed", seed)
	mat.set_shader_parameter("flicker", flicker)
	var q := QuadMesh.new()
	q.size = Vector2(size, size * height_scale)   # height_scale < 1 压扁、> 1 拉成"向上"的窄光晕
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Halo"
	mi.mesh = q
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ weather

## GPU 雨幕：盒状发射器，覆盖整个竞技场（跟随相机由游戏侧决定，这里铺满场地）。
static func rain(parent: Node3D, center: Vector3, extents: Vector3, amount: int,
		col: Color, alpha: float, fall := 30.0) -> GPUParticles3D:
	var mat := ShaderMaterial.new()
	mat.shader = RAIN_SHADER
	mat.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
	mat.set_shader_parameter("alpha", alpha)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.028, 0.9)
	quad.material = mat

	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = amount
	p.lifetime = 1.3
	p.preprocess = 1.2
	p.local_coords = false
	p.explosiveness = 0.0
	p.randomness = 0.6
	p.fixed_fps = 30
	p.visibility_aabb = AABB(center - extents - Vector3(4, 20, 4),
		extents * 2.0 + Vector3(8, 60, 8))
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = center

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.10, -1.0, 0.06)
	pm.spread = 2.5
	pm.initial_velocity_min = fall * 0.82
	pm.initial_velocity_max = fall * 1.15
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.65
	pm.scale_max = 1.5
	pm.color = Color(1, 1, 1, 1)
	p.process_material = pm
	parent.add_child(p)
	return p


## 蒸汽 / 浮尘：竖直上升的软片。lift 给一点自发光，让它在霓虹下可见。
static func steam(parent: Node3D, pos: Vector3, amount: int, size: float,
		col: Color, alpha: float, rise := 1.6, life := 2.6, spread := 5.0,
		extents := Vector3(0.35, 0.05, 0.35), lit := 0.0) -> GPUParticles3D:
	var mat := ShaderMaterial.new()
	mat.shader = STEAM_SHADER
	mat.set_shader_parameter("alpha", alpha)
	mat.set_shader_parameter("lift", lit)
	mat.set_shader_parameter("softness", 0.55)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat

	var p := GPUParticles3D.new()
	p.name = "Steam"
	p.amount = amount
	p.lifetime = life
	p.preprocess = life * 0.9
	p.local_coords = false
	p.randomness = 0.9
	p.visibility_aabb = AABB(pos - Vector3(6, 2, 6), Vector3(12, 14, 12))
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos

	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 0.0))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	grad.add_point(0.18, Color(col.r, col.g, col.b, 0.85))
	grad.add_point(0.55, Color(col.r * 0.9, col.g * 0.9, col.b * 0.95, 0.45))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = rise * 0.6
	pm.initial_velocity_max = rise * 1.35
	pm.gravity = Vector3(0, 0.25, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.7
	pm.damping_min = 0.05
	pm.damping_max = 0.4
	pm.color_ramp = ramp
	p.process_material = pm
	parent.add_child(p)
	return p

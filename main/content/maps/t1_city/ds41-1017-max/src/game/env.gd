## Atmosphere: procedural sky, wet-neon lighting, fog, bloom, SSAO/SSR.
class_name Env
extends Node3D

var world_env: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var fill: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial

var night := 1.0
var rain := 0.85
var current := "night"
var _t := 0.0

const PRESETS := {
	"dusk": {"sun_rot": Vector3(-9, 168, 0), "sun_col": Color(1.0, 0.44, 0.22), "sun_energy": 1.3,
		"amb": 0.20, "night": 0.8, "fog": 0.0005, "glow": 0.55},
	"night": {"sun_rot": Vector3(-19, 205, 0), "sun_col": Color(0.45, 0.55, 1.0), "sun_energy": 0.22,
		"amb": 0.14, "night": 1.0, "fog": 0.00072, "glow": 0.62},
	"day": {"sun_rot": Vector3(-30, 124, 0), "sun_col": Color(1.0, 0.88, 0.72), "sun_energy": 2.4,
		"amb": 0.32, "night": 0.05, "fog": 0.0001, "glow": 0.16},
	"storm": {"sun_rot": Vector3(-24, 190, 0), "sun_col": Color(0.55, 0.6, 0.78), "sun_energy": 0.45,
		"amb": 0.34, "night": 0.9, "fog": 0.0016, "glow": 0.65},
}

func setup(preset := "night") -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ShaderMaterial.new()
	sky_mat = sky.sky_material
	sky_mat.shader = load("res://gfx/sky.gdshader")
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.13, 0.16, 0.26)
	env.ambient_light_sky_contribution = 0.30
	env.ambient_light_energy = 0.46
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# tonemap / exposure
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.78
	env.tonemap_white = 2.2
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.20
	env.adjustment_saturation = 1.04
	env.adjustment_brightness = 0.98

	# glow / bloom
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_strength = 0.95
	env.glow_bloom = 0.10
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.05
	env.glow_hdr_scale = 1.4
	env.glow_normalized = false
	for i in 7:
		env.set_glow_level(i, [0.0, 0.4, 0.7, 0.9, 0.6, 0.35, 0.2][i])

	# fog
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.075, 0.085, 0.14)
	env.fog_light_energy = 0.32
	env.fog_density = 0.0008
	env.fog_sky_affect = 0.32
	env.fog_height = 18.0
	env.fog_height_density = 0.03
	env.fog_aerial_perspective = 0.3

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_albedo = Color(0.75, 0.68, 0.8)
	env.volumetric_fog_emission = Color(0.16, 0.07, 0.14)
	env.volumetric_fog_emission_energy = 0.35
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 190.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_ambient_inject = 0.55
	env.volumetric_fog_gi_inject = 0.1

	# SSAO
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 3.4
	env.ssao_power = 2.1
	env.ssao_detail = 0.8
	env.ssao_horizon = 0.02
	env.ssao_sharpness = 0.95
	env.ssao_light_affect = 0.42

	# SSR
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3

	# SSIL off (perf), SDFGI off (perf)
	env.ssil_enabled = false
	env.sdfgi_enabled = false

	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 240.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_volumetric_fog_energy = 1.2
	add_child(sun)

	fill = DirectionalLight3D.new()
	fill.light_color = Color(0.42, 0.56, 0.92)
	fill.light_energy = 0.0
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-22, -52, 0)
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.45, 0.55, 0.95)
	moon.light_energy = 0.35
	moon.rotation_degrees = Vector3(-38, 32, 0)
	moon.shadow_enabled = false
	add_child(moon)

	apply(preset)
	Mats.build()
	Mats.sun(night, rain)

func apply(preset: String) -> void:
	if not PRESETS.has(preset):
		return
	current = preset
	var p: Dictionary = PRESETS[preset]
	sun.rotation_degrees = p["sun_rot"]
	sun.light_color = p["sun_col"]
	sun.light_energy = p["sun_energy"]
	env.ambient_light_energy = p["amb"]
	fill.light_energy = 0.0
	night = p["night"]
	env.fog_density = p["fog"]
	env.glow_intensity = p["glow"]
	var day := 1.0 - night
	env.volumetric_fog_emission_energy = 0.4 * night
	env.volumetric_fog_density = 0.0035 * (0.35 + 0.65 * night)
	env.fog_light_color = Color(0.075, 0.085, 0.14).lerp(Color(0.55, 0.58, 0.66), day)
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("sky_gain", 0.44 + 0.40 * day)
	sky_mat.set_shader_parameter("zenith_col", Vector3(0.006, 0.010, 0.032).lerp(Vector3(0.065, 0.135, 0.265), day))
	sky_mat.set_shader_parameter("mid_col", Vector3(0.042, 0.035, 0.10).lerp(Vector3(0.245, 0.345, 0.47), day))
	sky_mat.set_shader_parameter("horizon_col", Vector3(0.26, 0.10, 0.17).lerp(Vector3(0.58, 0.60, 0.62), day))
	sky_mat.set_shader_parameter("smog", 0.62 - day * 0.4)
	sky_mat.set_shader_parameter("stars", 1.0 - day)
	sky_mat.set_shader_parameter("cloud_cover", 0.62)
	sky_mat.set_shader_parameter("city_glow", Vector3(0.20, 0.07, 0.15).lerp(Vector3(0.14, 0.14, 0.14), day * 0.6))
	fill.light_energy = 0.95 * day
	moon.light_energy = 0.35 * night
	Mats.sun(night, rain)

func _process(delta: float) -> void:
	_t += delta
	# subtle flicker of the whole sky glow
	if sky_mat:
		sky_mat.set_shader_parameter("city_glow", Vector3(0.34, 0.10, 0.24) * (0.94 + 0.06 * sin(_t * 0.7)))
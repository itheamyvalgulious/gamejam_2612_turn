extends RefCounted
## LEVIATHAN materials. All procedural, no textures.
##
## Black machined metal / bare steel trims / deep red armour / orange-red
## energy. Per-tentacle materials are unique instances so each limb can carry
## its own role glow, charge and length uniforms.

const METAL := preload("res://shaders/boss_metal.gdshader")
const LENS := preload("res://shaders/boss_lens.gdshader")
const ORB := preload("res://shaders/boss_orb.gdshader")
const CORE := preload("res://shaders/boss_core.gdshader")
const GLASS := preload("res://shaders/boss_glass.gdshader")
const LASER := preload("res://shaders/boss_laser.gdshader")
const IMPACT := preload("res://shaders/boss_impact.gdshader")
const FLOOR := preload("res://shaders/boss_floor.gdshader")
const OVERLAY := preload("res://shaders/screen_overlay.gdshader")
const TENTACLE := preload("res://shaders/boss_tentacle.gdshader")

const ORANGE := Color(1.0, 0.24, 0.035)
const ORANGE_HOT := Color(1.0, 0.60, 0.22)
const RED := Color(1.0, 0.075, 0.012)
const RED_DEEP := Color(0.34, 0.012, 0.004)
const BLACK := Color(0.020, 0.020, 0.024)
const WHITE_HOT := Color(1.0, 0.90, 0.78)

static var _c: Dictionary = {}


static func _keep(k: String, m: Material) -> Material:
	_c[k] = m
	return m


static func _metal(k: String, albedo: Color, rough: float, edge: Color,
		wear: float, brush: float, scratch: float, panel_var: float,
		oxide: float, metallic := 1.0) -> ShaderMaterial:
	if _c.has(k):
		return _c[k]
	var m := ShaderMaterial.new()
	m.shader = METAL
	m.set_shader_parameter("albedo_color", albedo)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("roughness_base", rough)
	m.set_shader_parameter("roughness_variation", 0.11)
	m.set_shader_parameter("brush_strength", brush)
	m.set_shader_parameter("brush_dir", Vector3(0.0, 0.0, 1.0))
	m.set_shader_parameter("grain_scale", 16.0)
	m.set_shader_parameter("scratch_density", scratch)
	m.set_shader_parameter("scratch_scale", 0.8)
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("edge_wear", wear)
	m.set_shader_parameter("edge_power", 3.0)
	m.set_shader_parameter("oxide_amount", oxide)
	m.set_shader_parameter("oxide_color", Color(0.10, 0.026, 0.010))
	m.set_shader_parameter("panel_scale", 2.6)
	m.set_shader_parameter("panel_variation", panel_var)
	m.resource_name = k
	return _keep(k, m)


static func hull() -> ShaderMaterial:
	return _metal("hull", Color(0.014, 0.014, 0.018), 0.50,
		Color(0.20, 0.21, 0.24), 0.26, 0.16, 0.30, 0.035, 0.025)


static func hull_soft() -> ShaderMaterial:
	return _metal("hull_soft", Color(0.023, 0.023, 0.028), 0.52,
		Color(0.24, 0.25, 0.29), 0.22, 0.12, 0.22, 0.025, 0.02)


static func steel() -> ShaderMaterial:
	return _metal("steel", Color(0.075, 0.076, 0.086), 0.30,
		Color(0.38, 0.40, 0.44), 0.30, 0.30, 0.20, 0.014, 0.012)


static func steel_dark() -> ShaderMaterial:
	return _metal("steel_dark", Color(0.046, 0.046, 0.053), 0.36,
		Color(0.34, 0.35, 0.39), 0.44, 0.34, 0.34, 0.03, 0.03)


static func red_plate() -> ShaderMaterial:
	return _metal("red_plate", Color(0.240, 0.020, 0.008), 0.33,
		Color(0.95, 0.28, 0.06), 0.50, 0.30, 0.30, 0.05, 0.04)


static func red_deep() -> ShaderMaterial:
	return _metal("red_deep", Color(0.120, 0.010, 0.004), 0.40,
		Color(0.55, 0.10, 0.02), 0.40, 0.22, 0.26, 0.04, 0.035)


static func rod_metal() -> ShaderMaterial:
	return _metal("rod", Color(0.028, 0.029, 0.035), 0.42,
		Color(0.30, 0.31, 0.35), 0.35, 0.32, 0.30, 0.03, 0.02)


static func ball_metal() -> ShaderMaterial:
	return _metal("ball", Color(0.085, 0.087, 0.098), 0.32,
		Color(0.52, 0.54, 0.60), 0.45, 0.40, 0.20, 0.015, 0.012)


static func trim() -> ShaderMaterial:
	return _metal("trim", Color(0.30, 0.29, 0.31), 0.25,
		Color(0.62, 0.63, 0.68), 0.36, 0.45, 0.18, 0.012, 0.01)


static func seal_black() -> StandardMaterial3D:
	if _c.has("seal"):
		return _c["seal"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.010, 0.009, 0.011)
	m.metallic = 0.15
	m.roughness = 0.82
	m.resource_name = "seal"
	return _keep("seal", m)


static func joint() -> StandardMaterial3D:
	if _c.has("joint"):
		return _c["joint"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.010, 0.010, 0.013)
	m.metallic = 0.30
	m.roughness = 0.74
	m.resource_name = "joint"
	return _keep("joint", m)


static func rubber() -> StandardMaterial3D:
	if _c.has("rubber"):
		return _c["rubber"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.024, 0.023, 0.026)
	m.metallic = 0.10
	m.roughness = 0.86
	m.resource_name = "rubber"
	return _keep("rubber", m)


static func tentacle(seed_value: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TENTACLE
	m.set_shader_parameter("albedo_color", Color(0.028, 0.029, 0.035))
	m.set_shader_parameter("accent_color", Color(0.34, 0.030, 0.006))
	m.set_shader_parameter("trim_color", Color(0.46, 0.47, 0.52))
	m.set_shader_parameter("glow_color", ORANGE)
	m.set_shader_parameter("glow_energy", 1.6)
	m.set_shader_parameter("role", 0.0)
	m.set_shader_parameter("charge", 0.0)
	m.set_shader_parameter("length_m", 6.0)
	m.set_shader_parameter("metallic", 1.0)
	m.set_shader_parameter("roughness_base", 0.40)
	m.set_shader_parameter("seed", seed_value)
	m.set_shader_parameter("wave_energy", 1.0)
	m.resource_name = "tentacle_%d" % int(seed_value * 100.0)
	return m


static func emissive(col: Color, energy := 4.0) -> StandardMaterial3D:
	var k := "emit_%s_%s" % [col.to_html(), energy]
	if _c.has(k):
		return _c[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.6)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.metallic = 0.12
	m.roughness = 0.38
	m.disable_receive_shadows = true
	m.resource_name = k
	return _keep(k, m)


static func signal_red() -> StandardMaterial3D:
	return emissive(RED, 7.0)


static func lens() -> ShaderMaterial:
	if _c.has("lens"):
		return _c["lens"]
	var m := ShaderMaterial.new()
	m.shader = LENS
	m.set_shader_parameter("glass_color", Color(0.006, 0.006, 0.009))
	m.set_shader_parameter("iris_color", RED)
	m.set_shader_parameter("core_color", Color(1.0, 0.30, 0.08))
	m.set_shader_parameter("intensity", 4.2)
	m.set_shader_parameter("pupil_radius", 0.31)
	m.set_shader_parameter("blade_count", 9.0)
	m.set_shader_parameter("ring_frequency", 62.0)
	m.set_shader_parameter("scan_speed", 0.55)
	m.set_shader_parameter("seed", 0.3)
	m.set_shader_parameter("aperture", 0.55)
	m.set_shader_parameter("alert", 0.35)
	m.resource_name = "boss_lens"
	return _keep("lens", m)


static func lens_small() -> ShaderMaterial:
	if _c.has("lens_small"):
		return _c["lens_small"]
	var m := lens().duplicate() as ShaderMaterial
	m.set_shader_parameter("intensity", 3.2)
	m.set_shader_parameter("pupil_radius", 0.26)
	m.resource_name = "boss_lens_small"
	return _keep("lens_small", m)


static func orb() -> ShaderMaterial:
	if _c.has("orb"):
		return _c["orb"]
	var m := ShaderMaterial.new()
	m.shader = ORB
	m.set_shader_parameter("color", Color(1.0, 0.045, 0.006))
	m.set_shader_parameter("hot_color", Color(1.0, 0.18, 0.035))
	m.set_shader_parameter("energy", 0.25)
	m.set_shader_parameter("opacity", 0.0)
	m.set_shader_parameter("seed", 0.7)
	m.set_shader_parameter("charge", 0.0)
	m.resource_name = "boss_orb"
	return _keep("orb", m)


static func core() -> ShaderMaterial:
	if _c.has("core"):
		return _c["core"]
	var m := ShaderMaterial.new()
	m.shader = CORE
	m.set_shader_parameter("color", Color(1.0, 0.030, 0.004))
	m.set_shader_parameter("hot_color", Color(1.0, 0.22, 0.045))
	m.set_shader_parameter("energy", 1.0)
	m.set_shader_parameter("seed", 0.3)
	m.set_shader_parameter("charge", 0.0)
	m.resource_name = "boss_core"
	return _keep("core", m)


static func glass() -> ShaderMaterial:
	if _c.has("glass"):
		return _c["glass"]
	var m := ShaderMaterial.new()
	m.shader = GLASS
	m.set_shader_parameter("tint", Color(1.0, 0.22, 0.06))
	m.set_shader_parameter("rim_color", Color(1.0, 0.66, 0.45))
	m.set_shader_parameter("opacity", 0.0)
	m.set_shader_parameter("pattern", 1.0)
	m.set_shader_parameter("energy", 1.0)
	m.set_shader_parameter("seed", 0.4)
	m.resource_name = "boss_glass"
	return _keep("glass", m)


static func laser(core_col: Color, edge_col: Color, intensity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LASER
	m.set_shader_parameter("core_color", core_col)
	m.set_shader_parameter("edge_color", edge_col)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("seed", randf() * 10.0)
	m.set_shader_parameter("flow_speed", 20.0)
	m.set_shader_parameter("core_power", 1.0)
	m.resource_name = "laser"
	return m


static func impact() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = IMPACT
	m.set_shader_parameter("tint", Color(1.0, 0.32, 0.06))
	m.set_shader_parameter("intensity", 1.0)
	m.set_shader_parameter("progress", 0.0)
	m.set_shader_parameter("seed", randf() * 10.0)
	return m


static func floor_mat() -> ShaderMaterial:
	if _c.has("floor"):
		return _c["floor"]
	var m := ShaderMaterial.new()
	m.shader = FLOOR
	m.set_shader_parameter("base_color", Color(0.018, 0.019, 0.026))
	m.set_shader_parameter("grid_color", Color(0.26, 0.34, 0.55))
	m.set_shader_parameter("accent_color", Color(1.0, 0.30, 0.06))
	m.set_shader_parameter("cold_color", Color(0.22, 0.38, 0.72))
	m.set_shader_parameter("ring_radius", 8.5)
	m.set_shader_parameter("ring_glow", 1.4)
	m.resource_name = "boss_floor"
	return _keep("floor", m)


static func overlay() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OVERLAY
	m.set_shader_parameter("vignette", 0.62)
	m.set_shader_parameter("vignette_width", 1.30)
	m.set_shader_parameter("scan_amount", 0.018)
	m.set_shader_parameter("grain", 0.014)
	m.set_shader_parameter("aberration", 0.55)
	return m


static func contact_shadow() -> StandardMaterial3D:
	if _c.has("shadow"):
		return _c["shadow"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.75))
	g.add_point(0.72, Color(1, 1, 1, 0.12))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.albedo_color = Color(0, 0, 0, 0.72)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return _keep("shadow", m)


static func dust(color: Color) -> StandardMaterial3D:
	var k := "dust_%s" % color.to_html()
	if _c.has(k):
		return _c[k]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = tex
	m.albedo_color = color
	m.disable_receive_shadows = true
	return _keep(k, m)

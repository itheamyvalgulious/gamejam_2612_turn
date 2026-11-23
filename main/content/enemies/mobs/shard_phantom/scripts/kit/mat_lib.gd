extends RefCounted
## MatLib — shared palette + shader materials.
##
## Art direction: matte machined metal, near-black with deep red plates,
## restrained rim light, high-purity surfaces (no grunge maps, no seams).
## Energy is the only saturated thing on screen: yellow arcs, pale violet shield.

const KATANA_SHADER := preload("res://shaders/energy_katana.gdshader")
const LIGHTNING_SHADER := preload("res://shaders/lightning.gdshader")
const SHIELD_SHADER := preload("res://shaders/shield.gdshader")
const THRUSTER_SHADER := preload("res://shaders/thruster.gdshader")
const GLOW_SHADER := preload("res://shaders/glow_dot.gdshader")
const FLOOR_SHADER := preload("res://shaders/floor.gdshader")
const LENS_SHADER := preload("res://shaders/lens.gdshader")
const RING_SHADER := preload("res://shaders/fx_ring.gdshader")

const ARC_YELLOW := Color(1.0, 0.74, 0.09)
const ARC_CORE := Color(1.0, 0.97, 0.78)
const SHIELD_LILAC := Color(0.66, 0.56, 1.0)
const SHIELD_RIM := Color(0.90, 0.84, 1.0)
const THRUSTER_ORANGE := Color(1.0, 0.31, 0.06)
const SIGNAL_RED := Color(1.0, 0.13, 0.06)

static var _cache: Dictionary = {}
static var _radial_tex: GradientTexture2D


static func _cached(key: String):
	if _cache.has(key):
		return _cache[key]
	return null


static func _keep(key: String, value):
	_cache[key] = value
	return value


static func pbr(albedo: Color, metallic: float, roughness: float,
		rim := 0.0, rim_tint := 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = rim_tint
	m.resource_name = "matte_metal"
	return m


# ------------------------------------------------------------------- metals

static func armor_black() -> StandardMaterial3D:
	var m = _cached("armor_black")
	if m != null:
		return m
	return _keep("armor_black", pbr(Color(0.030, 0.031, 0.037), 0.94, 0.47, 0.16, 0.35))


static func armor_black_soft() -> StandardMaterial3D:
	var m = _cached("armor_black_soft")
	if m != null:
		return m
	return _keep("armor_black_soft", pbr(Color(0.052, 0.051, 0.058), 0.88, 0.55, 0.12, 0.3))


static func armor_red() -> StandardMaterial3D:
	var m = _cached("armor_red")
	if m != null:
		return m
	return _keep("armor_red", pbr(Color(0.170, 0.014, 0.016), 0.86, 0.40, 0.30, 0.6))


static func armor_red_dark() -> StandardMaterial3D:
	var m = _cached("armor_red_dark")
	if m != null:
		return m
	return _keep("armor_red_dark", pbr(Color(0.085, 0.009, 0.011), 0.90, 0.46, 0.22, 0.5))


static func trim() -> StandardMaterial3D:
	var m = _cached("trim")
	if m != null:
		return m
	return _keep("trim", pbr(Color(0.46, 0.455, 0.47), 1.0, 0.29, 0.35, 0.5))


static func trim_dark() -> StandardMaterial3D:
	var m = _cached("trim_dark")
	if m != null:
		return m
	return _keep("trim_dark", pbr(Color(0.16, 0.16, 0.175), 1.0, 0.35))


static func joint() -> StandardMaterial3D:
	var m = _cached("joint")
	if m != null:
		return m
	return _keep("joint", pbr(Color(0.013, 0.013, 0.016), 0.55, 0.68))


static func glass_black() -> StandardMaterial3D:
	var m = _cached("glass_black")
	if m != null:
		return m
	return _keep("glass_black", pbr(Color(0.008, 0.010, 0.014), 0.92, 0.055, 0.6, 0.7))


static func shield_metal() -> StandardMaterial3D:
	var m = _cached("shield_metal")
	if m != null:
		return m
	return _keep("shield_metal", pbr(Color(0.30, 0.27, 0.40), 1.0, 0.34, 0.30, 0.7))


static func cloth() -> StandardMaterial3D:
	var m = _cached("cloth")
	if m != null:
		return m
	return _keep("cloth", pbr(Color(0.028, 0.027, 0.034), 0.10, 0.86))


# ----------------------------------------------------------------- emitters

static func emissive(color: Color, energy := 5.0) -> StandardMaterial3D:
	var k := "emit_%s_%s" % [color.to_html(), energy]
	var m = _cached(k)
	if m != null:
		return m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.6)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.metallic = 0.15
	mat.roughness = 0.38
	mat.disable_receive_shadows = true
	mat.resource_name = "emissive"
	return _keep(k, mat)


static func signal_red() -> StandardMaterial3D:
	var m = _cached("signal_red")
	if m != null:
		return m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.03, 0.02)
	mat.emission_enabled = true
	mat.emission = SIGNAL_RED
	mat.emission_energy_multiplier = 7.5
	mat.metallic = 0.3
	mat.roughness = 0.20
	mat.disable_receive_shadows = true
	return _keep("signal_red", mat)


# ------------------------------------------------------------------ shaders

static func katana_arc() -> ShaderMaterial:
	var m = _cached("katana")
	if m != null:
		return m
	var mat := ShaderMaterial.new()
	mat.shader = KATANA_SHADER
	mat.set_shader_parameter("core_color", ARC_CORE)
	mat.set_shader_parameter("arc_color", ARC_YELLOW)
	mat.set_shader_parameter("intensity", 2.7)
	mat.set_shader_parameter("arc_density", 7.0)
	mat.set_shader_parameter("arc_speed", 1.8)
	mat.set_shader_parameter("charge", 0.0)
	return _keep("katana", mat)


static func lightning(color := ARC_YELLOW, energy := 4.6) -> ShaderMaterial:
	var k := "lightning_%s_%s" % [color.to_html(), energy]
	var m = _cached(k)
	if m != null:
		return m
	var mat := ShaderMaterial.new()
	mat.shader = LIGHTNING_SHADER
	mat.set_shader_parameter("arc_color", color)
	mat.set_shader_parameter("core_color", ARC_CORE)
	mat.set_shader_parameter("intensity", energy)
	mat.set_shader_parameter("seed", randf() * 100.0)
	return _keep(k, mat)


static func shield_skin() -> ShaderMaterial:
	var m = _cached("shield_skin")
	if m != null:
		return m
	var mat := ShaderMaterial.new()
	mat.shader = SHIELD_SHADER
	mat.set_shader_parameter("tint", SHIELD_LILAC)
	mat.set_shader_parameter("rim_color", SHIELD_RIM)
	mat.set_shader_parameter("ring_count", 7.0)
	mat.set_shader_parameter("impact", 0.0)
	return _keep("shield_skin", mat)


static func thruster(tint := THRUSTER_ORANGE, energy := 3.1) -> ShaderMaterial:
	var k := "thruster_%s_%s" % [tint.to_html(), energy]
	var m = _cached(k)
	if m != null:
		return m
	var mat := ShaderMaterial.new()
	mat.shader = THRUSTER_SHADER
	mat.set_shader_parameter("flame_color", tint)
	mat.set_shader_parameter("hot_color", Color(1.0, 0.86, 0.62))
	mat.set_shader_parameter("intensity", energy)
	return _keep(k, mat)


static func glow(tint := SIGNAL_RED, energy := 2.0) -> ShaderMaterial:
	var k := "glow_%s_%s" % [tint.to_html(), energy]
	var m = _cached(k)
	if m != null:
		return m
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("intensity", energy)
	return _keep(k, mat)


static func floor() -> ShaderMaterial:
	var m = _cached("floor")
	if m != null:
		return m
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SHADER
	mat.set_shader_parameter("base_color", Color(0.024, 0.026, 0.034))
	mat.set_shader_parameter("grid_color", Color(0.30, 0.38, 0.60))
	mat.set_shader_parameter("accent_color", Color(1.0, 0.36, 0.09))
	return _keep("floor", mat)


static func lens() -> ShaderMaterial:
	var m = _cached("lens")
	if m != null:
		return m
	var mat := ShaderMaterial.new()
	mat.shader = LENS_SHADER
	mat.set_shader_parameter("iris_color", Color(1.0, 0.13, 0.055))
	mat.set_shader_parameter("intensity", 3.2)
	return _keep("lens", mat)


static func ring() -> ShaderMaterial:
	var m = _cached("fx_ring")
	if m != null:
		return m
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	return _keep("fx_ring", mat)


# -------------------------------------------------------------------- misc

static func radial_texture() -> GradientTexture2D:
	if _radial_tex != null:
		return _radial_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.32, Color(1, 1, 1, 0.80))
	g.add_point(0.70, Color(1, 1, 1, 0.16))
	_radial_tex = GradientTexture2D.new()
	_radial_tex.gradient = g
	_radial_tex.fill = GradientTexture2D.FILL_RADIAL
	_radial_tex.fill_from = Vector2(0.5, 0.5)
	_radial_tex.fill_to = Vector2(1.0, 0.5)
	_radial_tex.width = 128
	_radial_tex.height = 128
	return _radial_tex


static func contact_shadow(alpha := 0.62) -> StandardMaterial3D:
	var k := "shadow_%s" % alpha
	var m = _cached(k)
	if m != null:
		return m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = radial_texture()
	mat.albedo_color = Color(0.0, 0.0, 0.0, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return _keep(k, mat)


static func dust(color := Color(1.0, 0.42, 0.11, 0.22)) -> StandardMaterial3D:
	var k := "dust_%s" % color.to_html()
	var m = _cached(k)
	if m != null:
		return m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = radial_texture()
	mat.albedo_color = color
	mat.disable_receive_shadows = true
	return _keep(k, mat)


static func tint_instance(mi: GeometryInstance3D, color: Color, seed_value := -1.0) -> void:
	if seed_value < 0.0:
		seed_value = randf() * 100.0
	mi.set_instance_shader_parameter("fx_tint", color)
	mi.set_instance_shader_parameter("fx_seed", seed_value)
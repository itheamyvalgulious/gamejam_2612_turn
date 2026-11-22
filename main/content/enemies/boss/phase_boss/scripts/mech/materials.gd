extends RefCounted
## MechMaterials — the entire palette, generated at runtime.
## Standard PBR for hard surfaces, hand-written shaders for energy and VFX.

const BLADE_CORE_SHADER := preload("res://shaders/blade.gdshader")
const BLADE_GLOW_SHADER := preload("res://shaders/blade_glow.gdshader")
const TRAIL_SHADER := preload("res://shaders/blade_trail.gdshader")
const FLOOR_SHADER := preload("res://shaders/arena_floor.gdshader")
const RING_SHADER := preload("res://shaders/ring_fx.gdshader")

static var _cache: Dictionary = {}
static var _radial_tex: GradientTexture2D


static func _cached(key: String) -> Material:
	return _cache.get(key)


static func _standard(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	m.resource_name = "mech_surface"
	return m


static func armor() -> StandardMaterial3D:
	var k := "armor"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.64, 0.615, 0.555), 0.28, 0.40)
	m.rim_enabled = true
	m.rim = 0.18
	m.rim_tint = 0.35
	_cache[k] = m
	return m


static func armor_shadow() -> StandardMaterial3D:
	var k := "armor_shadow"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.245, 0.24, 0.235), 0.60, 0.38)
	_cache[k] = m
	return m


static func armor_edge() -> StandardMaterial3D:
	var k := "armor_edge"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.82, 0.80, 0.745), 0.45, 0.27)
	m.rim_enabled = true
	m.rim = 0.25
	_cache[k] = m
	return m


static func frame() -> StandardMaterial3D:
	var k := "frame"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.062, 0.068, 0.082), 0.84, 0.34)
	_cache[k] = m
	return m


static func frame_light() -> StandardMaterial3D:
	var k := "frame_light"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.135, 0.140, 0.158), 0.80, 0.31)
	_cache[k] = m
	return m


static func rubber() -> StandardMaterial3D:
	var k := "rubber"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.018, 0.019, 0.022), 0.10, 0.72)
	_cache[k] = m
	return m


static func copper() -> StandardMaterial3D:
	var k := "copper"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.52, 0.24, 0.10), 1.0, 0.28)
	_cache[k] = m
	return m


static func paint() -> StandardMaterial3D:
	var k := "paint"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.46, 0.040, 0.018), 0.22, 0.42)
	m.rim_enabled = true
	m.rim = 0.22
	m.rim_tint = 0.7
	_cache[k] = m
	return m


static func glass() -> StandardMaterial3D:
	var k := "glass"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.012, 0.020, 0.032), 0.92, 0.08)
	m.rim_enabled = true
	m.rim = 0.6
	_cache[k] = m
	return m


static func emissive(color := Color(1.0, 0.30, 0.06), energy := 5.0) -> StandardMaterial3D:
	var k := "emit_%s_%s" % [color.to_html(), energy]
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.55)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	m.metallic = 0.2
	m.resource_name = "emissive"
	_cache[k] = m
	return m


static func visor_orange() -> StandardMaterial3D:
	var k := "visor"
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.18, 0.02)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.32, 0.055)
	m.emission_energy_multiplier = 8.0
	m.metallic = 0.5
	m.roughness = 0.12
	_cache[k] = m
	return m


static func blade_core() -> ShaderMaterial:
	var k := "blade_core"
	if _cache.has(k):
		return _cache[k]
	var m := ShaderMaterial.new()
	m.shader = BLADE_CORE_SHADER
	m.set_shader_parameter("energy", 4.2)
	_cache[k] = m
	return m


static func blade_glow() -> ShaderMaterial:
	var k := "blade_glow"
	if _cache.has(k):
		return _cache[k]
	var m := ShaderMaterial.new()
	m.shader = BLADE_GLOW_SHADER
	m.set_shader_parameter("strength", 1.35)
	m.set_shader_parameter("color", Color(1.0, 0.30, 0.055))
	_cache[k] = m
	return m


static func trail() -> ShaderMaterial:
	var k := "trail"
	if _cache.has(k):
		return _cache[k]
	var m := ShaderMaterial.new()
	m.shader = TRAIL_SHADER
	m.set_shader_parameter("energy", 2.1)
	_cache[k] = m
	return m


static func floor() -> ShaderMaterial:
	var k := "floor"
	if _cache.has(k):
		return _cache[k]
	var m := ShaderMaterial.new()
	m.shader = FLOOR_SHADER
	_cache[k] = m
	return m


static func ring_fx() -> ShaderMaterial:
	var k := "ring_fx"
	if _cache.has(k):
		return _cache[k]
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	_cache[k] = m
	return m


static func radial_texture() -> GradientTexture2D:
	if _radial_tex != null:
		return _radial_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.38, Color(1, 1, 1, 0.72))
	g.add_point(0.72, Color(1, 1, 1, 0.18))
	_radial_tex = GradientTexture2D.new()
	_radial_tex.gradient = g
	_radial_tex.fill = GradientTexture2D.FILL_RADIAL
	_radial_tex.fill_from = Vector2(0.5, 0.5)
	_radial_tex.fill_to = Vector2(1.0, 0.5)
	_radial_tex.width = 128
	_radial_tex.height = 128
	return _radial_tex


static func dust() -> StandardMaterial3D:
	var k := "dust"
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(1.0, 0.42, 0.11, 0.24)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.38, 0.09)
	m.emission_energy_multiplier = 0.55
	m.disable_receive_shadows = true
	m.no_depth_test = false
	_cache[k] = m
	return m


static func contact_shadow() -> StandardMaterial3D:
	var k := "contact_shadow"
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.0, 0.0, 0.0, 0.62)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	_cache[k] = m
	return m


static func pylon() -> StandardMaterial3D:
	var k := "pylon"
	if _cache.has(k):
		return _cache[k]
	var m := _standard(Color(0.028, 0.032, 0.042), 0.18, 0.82)
	_cache[k] = m
	return m


static func mote() -> StandardMaterial3D:
	var k := "mote"
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.45, 0.60, 1.0, 0.20)
	m.emission_enabled = false
	m.disable_receive_shadows = true
	_cache[k] = m
	return m


static func hit_flash() -> StandardMaterial3D:
	var k := "hit_flash"
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(1.0, 0.66, 0.30, 0.90)
	m.emission_enabled = false
	m.disable_receive_shadows = true
	_cache[k] = m
	return m


static func spark() -> StandardMaterial3D:
	var k := "spark"
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(1.0, 0.58, 0.20, 0.95)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.35, 0.07)
	m.emission_energy_multiplier = 0.7
	m.disable_receive_shadows = true
	_cache[k] = m
	return m


static func smoke() -> StandardMaterial3D:
	var k := "smoke"
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.48, 0.42, 0.37, 0.42)
	m.disable_receive_shadows = true
	_cache[k] = m
	return m


static func speed_streak() -> StandardMaterial3D:
	var k := "streak"
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.42, 0.12, 0.25)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	_cache[k] = m
	return m
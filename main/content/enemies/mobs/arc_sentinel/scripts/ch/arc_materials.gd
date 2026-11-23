extends RefCounted
## ARC // SENTINEL v2 — palette and materials.
##
## Black/graphite machined metal, orange-red accents, electric-orange blade,
## orange hard-light shield. Every metal surface uses the procedural
## `arc_metal_v2` shader (brushed streaks, pitting, scratches, roughness
## breakup, edge wear). If the shader is missing (e.g. during first import) the
## helpers fall back to StandardMaterial3D so the project still boots.

const LENS := preload("res://shaders/arc_lens.gdshader")
const SHIELD := preload("res://shaders/arc_shield.gdshader")
const TRAIL := preload("res://shaders/arc_trail.gdshader")
const BLADE_CORE := preload("res://shaders/arc_blade_core.gdshader")
const EYE_BALL := preload("res://shaders/arc_eye_ball.gdshader")
const OPTIC_GLASS := preload("res://shaders/arc_optic_glass.gdshader")

static var _metal_probed := false
static var _metal_shader: Shader = null

const ORANGE := Color(1.0, 0.22, 0.035)
const ORANGE_HOT := Color(1.0, 0.55, 0.16)
const ORANGE_DEEP := Color(0.30, 0.025, 0.006)
const BLACK := Color(0.028, 0.028, 0.032)

static var _c: Dictionary = {}


static func _keep(k: String, m: Material) -> Material:
	_c[k] = m
	return m


static func _metal_res() -> Shader:
	if not _metal_probed:
		_metal_probed = true
		if ResourceLoader.exists("res://shaders/arc_metal_v2.gdshader"):
			_metal_shader = load("res://shaders/arc_metal_v2.gdshader")
	return _metal_shader


static func _metal_mat(k: String, albedo: Color, metallic: float, rough: float,
		edge: Color, wear: float, brush: float, scratch: float,
		panel_var: float, oxide: float) -> Material:
	if _c.has(k):
		return _c[k]
	var sh := _metal_res()
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("albedo_color", albedo)
		m.set_shader_parameter("metallic", metallic)
		m.set_shader_parameter("roughness_base", rough)
		m.set_shader_parameter("roughness_variation", 0.10)
		m.set_shader_parameter("brush_strength", brush)
		m.set_shader_parameter("brush_dir", Vector3(0.0, 0.0, 1.0))
		m.set_shader_parameter("grain_scale", 30.0)
		m.set_shader_parameter("scratch_density", scratch)
		m.set_shader_parameter("scratch_scale", 1.0)
		m.set_shader_parameter("edge_color", edge)
		m.set_shader_parameter("edge_wear", wear)
		m.set_shader_parameter("edge_power", 3.0)
		m.set_shader_parameter("oxide_amount", oxide)
		m.set_shader_parameter("oxide_color", Color(0.10, 0.028, 0.010))
		m.set_shader_parameter("panel_scale", 4.0)
		m.set_shader_parameter("panel_variation", panel_var)
		m.resource_name = k
		return _keep(k, m)
	var s := StandardMaterial3D.new()
	s.albedo_color = albedo
	s.metallic = metallic
	s.roughness = rough
	s.metallic_specular = 0.55
	s.resource_name = k + "_std"
	return _keep(k, s)


static func hull() -> Material:
	return _metal_mat("hull", Color(0.014, 0.014, 0.017), 1.0, 0.46,
		Color(0.16, 0.17, 0.19), 0.22, 0.12, 0.22, 0.025, 0.030)


static func hull_soft() -> Material:
	return _metal_mat("hull_soft", Color(0.018, 0.018, 0.022), 1.0, 0.48,
		Color(0.10, 0.11, 0.12), 0.16, 0.10, 0.18, 0.02, 0.02)


static func steel() -> Material:
	return _metal_mat("steel", Color(0.060, 0.060, 0.067), 1.0, 0.36,
		Color(0.26, 0.27, 0.30), 0.35, 0.20, 0.14, 0.012, 0.012)


static func steel_dark() -> Material:
	return _metal_mat("steel_dark", Color(0.055, 0.055, 0.062), 1.0, 0.36,
		Color(0.30, 0.31, 0.34), 0.45, 0.42, 0.36, 0.04, 0.03)


static func tread() -> Material:
	# belt shoes: black anodised steel.  A *broad* specular wash on these large
	# flat up-facing pads reads as light concrete, so the roughness is kept low
	# (sharp glints instead of a wash).
	return _metal_mat("tread", Color(0.040, 0.040, 0.044), 1.0, 0.30,
		Color(0.34, 0.35, 0.38), 0.55, 0.45, 0.45, 0.03, 0.03)


static func belt() -> StandardMaterial3D:
	if _c.has("belt"):
		return _c["belt"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.012, 0.012, 0.014)
	m.metallic = 0.20
	m.metallic_specular = 0.10
	m.roughness = 0.90
	m.resource_name = "belt"
	return _keep("belt", m)


static func mat_black() -> StandardMaterial3D:
	# large flat up-facing deck plates: coated black, no grazing metal wash
	if _c.has("mat_black"):
		return _c["mat_black"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.010, 0.010, 0.011)
	m.metallic = 0.10
	m.metallic_specular = 0.0
	m.roughness = 0.88
	m.resource_name = "mat_black"
	return _keep("mat_black", m)


static func orange_panel() -> Material:
	return _metal_mat("orange_panel", Color(0.330, 0.026, 0.006), 0.88, 0.34,
		Color(0.95, 0.24, 0.045), 0.55, 0.25, 0.35, 0.07, 0.05)


static func orange_deep() -> Material:
	return _metal_mat("orange_deep", Color(0.160, 0.014, 0.004), 0.90, 0.40,
		Color(0.55, 0.10, 0.02), 0.45, 0.22, 0.30, 0.05, 0.04)


static func orange_metal() -> Material:
	return _metal_mat("orange_metal", Color(0.400, 0.060, 0.010), 0.92, 0.28,
		Color(1.0, 0.40, 0.08), 0.4, 0.5, 0.2, 0.04, 0.02)


static func tire() -> StandardMaterial3D:
	if _c.has("tire"):
		return _c["tire"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.026, 0.025, 0.028)
	m.metallic = 0.22
	m.roughness = 0.80
	m.resource_name = "tire"
	return _keep("tire", m)


static func joint() -> StandardMaterial3D:
	if _c.has("joint"):
		return _c["joint"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.010, 0.010, 0.012)
	m.metallic = 0.35
	m.roughness = 0.72
	m.resource_name = "joint"
	return _keep("joint", m)


static func signal_orange() -> StandardMaterial3D:
	return emissive(ORANGE, 5.2)


static func emissive(col: Color, energy: float) -> StandardMaterial3D:
	var k := "emit_%s_%s" % [col.to_html(), energy]
	if _c.has(k):
		return _c[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.55)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.metallic = 0.1
	m.roughness = 0.35
	m.disable_receive_shadows = true
	m.resource_name = k
	return _keep(k, m)


static func lens() -> ShaderMaterial:
	if _c.has("lens"):
		return _c["lens"]
	var m := ShaderMaterial.new()
	m.shader = LENS
	m.set_shader_parameter("glass_color", Color(0.006, 0.007, 0.010))
	m.set_shader_parameter("iris_color", ORANGE)
	m.set_shader_parameter("core_color", Color(1.0, 0.72, 0.42))
	m.set_shader_parameter("intensity", 4.2)
	m.set_shader_parameter("pupil_radius", 0.30)
	m.set_shader_parameter("blade_count", 7.0)
	m.set_shader_parameter("ring_frequency", 52.0)
	m.set_shader_parameter("scan_speed", 0.7)
	m.set_shader_parameter("seed", 0.3)
	m.set_shader_parameter("aperture", 0.55)
	m.resource_name = "lens"
	return _keep("lens", m)


## Rotating red optic ball (latitude bands + seams so its rotation is legible).
static func eye_ball() -> ShaderMaterial:
	if _c.has("eye_ball"):
		return _c["eye_ball"]
	var m := ShaderMaterial.new()
	m.shader = EYE_BALL
	m.set_shader_parameter("base_color", Color(0.045, 0.006, 0.008))
	m.set_shader_parameter("glow_color", Color(1.0, 0.10, 0.03))
	m.set_shader_parameter("intensity", 0.55)
	m.set_shader_parameter("band_count", 7.0)
	m.set_shader_parameter("seed", 0.3)
	m.resource_name = "eye_ball"
	return _keep("eye_ball", m)


## Thin fixed glass shell over the socket aperture.
static func optic_glass() -> ShaderMaterial:
	if _c.has("optic_glass"):
		return _c["optic_glass"]
	var m := ShaderMaterial.new()
	m.shader = OPTIC_GLASS
	m.set_shader_parameter("tint", Color(1.0, 0.22, 0.05))
	m.set_shader_parameter("alpha", 0.14)
	m.set_shader_parameter("intensity", 0.28)
	m.set_shader_parameter("scan", 0.6)
	m.resource_name = "optic_glass"
	return _keep("optic_glass", m)


static func shield() -> ShaderMaterial:
	if _c.has("shield"):
		return _c["shield"]
	var m := ShaderMaterial.new()
	m.shader = SHIELD
	m.set_shader_parameter("tint", Color(1.0, 0.24, 0.045))
	m.set_shader_parameter("rim_color", Color(1.0, 0.80, 0.52))
	m.set_shader_parameter("intensity", 1.0)
	m.set_shader_parameter("opacity", 0.52)
	m.set_shader_parameter("ring_count", 6.0)
	m.set_shader_parameter("ring_bright", 0.55)
	m.set_shader_parameter("travel_speed", 0.20)
	m.set_shader_parameter("fresnel_power", 2.2)
	m.set_shader_parameter("impact", 0.0)
	m.set_shader_parameter("seed", 0.0)
	m.resource_name = "shield"
	return _keep("shield", m)


static func blade_core_solid() -> StandardMaterial3D:
	if _c.has("blade_core_solid"):
		return _c["blade_core_solid"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.22, 0.035)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.24, 0.03)
	m.emission_energy_multiplier = 3.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = "blade_core_solid"
	return _keep("blade_core_solid", m)


static func blade_core() -> ShaderMaterial:
	if _c.has("blade_core"):
		return _c["blade_core"]
	var m := ShaderMaterial.new()
	m.shader = BLADE_CORE
	m.set_shader_parameter("tint", Color(1.0, 0.30, 0.05))
	m.set_shader_parameter("intensity", 1.0)
	m.resource_name = "blade_core"
	return _keep("blade_core", m)


static func trail() -> ShaderMaterial:
	if _c.has("trail"):
		return _c["trail"]
	var m := ShaderMaterial.new()
	m.shader = TRAIL
	m.set_shader_parameter("tint", Color(1.0, 0.38, 0.08))
	m.set_shader_parameter("energy", 2.4)
	m.resource_name = "trail"
	return _keep("trail", m)


static func glow_quad(col: Color, energy := 1.0, billboard := true) -> StandardMaterial3D:
	var k := "glow_%s_%s" % [col.to_html(), energy]
	if _c.has(k):
		return _c[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	m.albedo_color = col * energy
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.resource_name = k
	return _keep(k, m)
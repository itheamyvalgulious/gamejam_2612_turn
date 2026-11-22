extends RefCounted
## MechMaterials — VESPER palette, generated at runtime.
## Cold white / navy / black-blue hard surfaces use a procedural brushed-metal
## shader; energy, optics and VFX use hand-written shaders.  All procedural:
## no textures, no imported assets.
##
## Legacy function names (armor, paint, copper, visor_orange, ...) are kept so
## arena.gd / fx.gd / hud.gd / older rig code keep working; they simply carry
## the new blue-white theme.

const METAL_SHADER := preload("res://shaders/vesper_metal.gdshader")
const BLADE_CORE_SHADER := preload("res://shaders/vesper_blade_core.gdshader")
const BLADE_GLOW_SHADER := preload("res://shaders/vesper_blade_glow.gdshader")
const LENS_SHADER := preload("res://shaders/vesper_lens.gdshader")
const VISOR_SHADER := preload("res://shaders/vesper_visor.gdshader")
const HAIR_SHADER := preload("res://shaders/vesper_hair.gdshader")
const THRUSTER_SHADER := preload("res://shaders/vesper_thruster.gdshader")
const PETAL_SHADER := preload("res://shaders/vesper_engine_petal.gdshader")
const TRAIL_SHADER := preload("res://shaders/blade_trail.gdshader")
const FLOOR_SHADER := preload("res://shaders/arena_floor.gdshader")
const RING_SHADER := preload("res://shaders/ring_fx.gdshader")

## Theme colours — white-leaning silver metallic + crisp sapphire/electric blue.
const ENERGY_BLUE := Color(0.16, 0.48, 1.0)
const ENERGY_WHITE := Color(0.90, 0.97, 1.0)
const SIGNAL_GREEN := Color(0.20, 1.0, 0.45)

const ARMOR_WHITE := Color(0.80, 0.84, 0.89)
const ARMOR_SILVER := Color(0.72, 0.76, 0.82)
const ARMOR_NAVY := Color(0.055, 0.155, 0.420)
const ARMOR_DARK := Color(0.125, 0.155, 0.215)
const STEEL := Color(0.86, 0.90, 0.96)
const BRIGHT_STEEL := Color(0.95, 0.97, 1.0)

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


## Shared constructor for the procedural brushed-metal shader.
static func _metal(key: String, albedo: Color, metallic: float, roughness: float,
		edge_wear := 0.55, panel_variation := 0.10, brush := 0.55,
		grain := 26.0, scratch := 0.30, edge := STEEL) -> Material:
	var cached: Material = _cache.get(key)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = METAL_SHADER
	m.resource_name = key
	m.set_shader_parameter("albedo_color", albedo)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("roughness_base", roughness)
	m.set_shader_parameter("roughness_variation", 0.10)
	m.set_shader_parameter("brush_strength", brush)
	m.set_shader_parameter("grain_scale", grain)
	m.set_shader_parameter("scratch_density", scratch)
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("edge_wear", edge_wear)
	m.set_shader_parameter("edge_power", 2.6)
	m.set_shader_parameter("panel_scale", 2.6)
	m.set_shader_parameter("panel_variation", panel_variation)
	m.set_shader_parameter("tint_blue", Color(0.82, 0.89, 1.0))
	m.set_shader_parameter("env_sheen", 0.13)
	_cache[key] = m
	return m


# --------------------------------------------------------------- main armour
static func armor_white() -> Material:
	var cached: Material = _cache.get("armor_white")
	if cached != null:
		return cached
	return _metal("armor_white", ARMOR_WHITE, 0.76, 0.30,
		0.42, 0.06, 0.28, 28.0, 0.09, BRIGHT_STEEL)


static func armor_silver() -> Material:
	var cached: Material = _cache.get("armor_silver")
	if cached != null:
		return cached
	return _metal("armor_silver", ARMOR_SILVER, 0.88, 0.24,
		0.40, 0.05, 0.25, 32.0, 0.08, BRIGHT_STEEL)


static func armor() -> Material:
	return armor_white()


static func armor_blue() -> Material:
	var cached: Material = _cache.get("armor_blue")
	if cached != null:
		return cached
	return _metal("armor_blue", ARMOR_NAVY, 0.90, 0.22,
		0.45, 0.10, 0.34, 30.0, 0.10, Color(0.58, 0.78, 1.0))


static func joint_blue() -> Material:
	var cached: Material = _cache.get("joint_blue")
	if cached != null:
		return cached
	var m := _metal("joint_blue", Color(0.035, 0.115, 0.360), 0.88, 0.32,
		0.12, 0.04, 0.24, 30.0, 0.05, Color(0.28, 0.50, 0.92)) as ShaderMaterial
	m.set_shader_parameter("env_sheen", 0.03)
	m.set_shader_parameter("tint_blue", Color(0.20, 0.44, 0.88))
	return m


static func armor_shadow() -> Material:
	var cached: Material = _cache.get("armor_shadow")
	if cached != null:
		return cached
	return _metal("armor_shadow", Color(0.06, 0.08, 0.13), 0.90, 0.30,
		0.40, 0.08, 0.36, 28.0, 0.12, Color(0.62, 0.72, 0.88))


static func armor_dark() -> Material:
	var cached: Material = _cache.get("armor_dark")
	if cached != null:
		return cached
	return _metal("armor_dark", ARMOR_DARK, 0.92, 0.28,
		0.36, 0.08, 0.34, 32.0, 0.10, Color(0.65, 0.74, 0.88))


static func armor_edge() -> Material:
	var cached: Material = _cache.get("armor_edge")
	if cached != null:
		return cached
	return _metal("armor_edge", Color(0.84, 0.88, 0.94), 0.98, 0.18,
		0.62, 0.05, 0.28, 34.0, 0.12, BRIGHT_STEEL)


static func trim() -> Material:
	var cached: Material = _cache.get("trim")
	if cached != null:
		return cached
	return _metal("trim", Color(0.91, 0.93, 0.97), 0.98, 0.13,
		0.38, 0.03, 0.18, 40.0, 0.06, BRIGHT_STEEL)


# ------------------------------------------------------------- frame / joints
static func frame() -> Material:
	var cached: Material = _cache.get("frame")
	if cached != null:
		return cached
	return _metal("frame", Color(0.14, 0.21, 0.38), 0.90, 0.24,
		0.45, 0.07, 0.34, 30.0, 0.10, Color(0.62, 0.74, 0.94))


static func frame_light() -> Material:
	var cached: Material = _cache.get("frame_light")
	if cached != null:
		return cached
	return _metal("frame_light", Color(0.68, 0.73, 0.81), 0.94, 0.20,
		0.48, 0.06, 0.30, 30.0, 0.08, BRIGHT_STEEL)


static func rubber() -> Material:
	var k := "rubber"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := _standard(Color(0.014, 0.017, 0.023), 0.05, 0.80)
	_cache[k] = m
	return m


## Legacy name: hydraulic fittings are now polished cool gunmetal, no copper.
static func copper() -> Material:
	var k := "copper"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	return _metal(k, Color(0.20, 0.24, 0.32), 0.98, 0.22,
		0.40, 0.04, 0.32, 36.0, 0.26, Color(0.78, 0.84, 0.94))


## Accent panels: saturated electric-blue metal.
static func paint() -> Material:
	var k := "paint"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	return _metal(k, Color(0.035, 0.120, 0.500), 0.90, 0.22,
		0.45, 0.08, 0.30, 30.0, 0.28, Color(0.42, 0.62, 1.0))


static func glass() -> Material:
	var k := "glass"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := _standard(Color(0.006, 0.012, 0.024), 0.90, 0.05)
	m.rim_enabled = true
	m.rim = 0.6
	m.resource_name = "glass"
	_cache[k] = m
	return m


# ------------------------------------------------------------------- energy
static func emissive(color := ENERGY_BLUE, energy := 5.0) -> Material:
	var k := "emit_%s_%s" % [color.to_html(), energy]
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.60)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.35
	m.metallic = 0.25
	m.resource_name = "emissive"
	_cache[k] = m
	return m


# --------------------------------------------------------------- optics / fx
static func _visor() -> Material:
	var k := "visor_blue"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.010, 0.030, 0.080)
	m.emission_enabled = true
	m.emission = Color(0.30, 0.60, 1.0)
	m.emission_energy_multiplier = 3.2
	m.metallic = 0.35
	m.roughness = 0.10
	m.rim_enabled = true
	m.rim = 0.5
	m.resource_name = "visor_blue"
	_cache[k] = m
	return m


## Legacy name kept for old call sites; the visor is electric blue now.
static func visor_orange() -> Material:
	return _visor()


static func visor_blue() -> Material:
	return _visor()


static func visor_black() -> StandardMaterial3D:
	var k := "visor_black"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.005, 0.007, 0.012)
	m.metallic = 0.55
	m.roughness = 0.10
	m.clearcoat_enabled = true
	m.clearcoat = 0.9
	m.clearcoat_roughness = 0.06
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.6
	m.resource_name = k
	_cache[k] = m
	return m


## Smoked, semi-transparent faceplate.  Kept in its own shader so the optics
## inside the mask stay readable through the glass.
static func visor_glass() -> ShaderMaterial:
	var k := "visor_glass"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = VISOR_SHADER
	m.resource_name = k
	m.set_shader_parameter("tint", Color(0.010, 0.016, 0.035))
	m.set_shader_parameter("rim_color", Color(0.22, 0.44, 0.95))
	m.set_shader_parameter("base_alpha", 0.30)
	m.set_shader_parameter("rim_alpha", 0.88)
	m.render_priority = 2
	_cache[k] = m
	return m


## Dense scalp hair underlayer: uses the hair shader with vertex colors so the
## scalp cap and the long hair locks blend seamlessly with no visible root gap.
static func hair_cap() -> Material:
	var k := "hair_cap"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = HAIR_SHADER
	m.set_shader_parameter("is_scalp", true)
	m.set_shader_parameter("energy", 0.015)
	m.resource_name = k
	_cache[k] = m
	return m


## Jet-black matte cavity wall behind the visor (no sheen, no reflections).
static func cavity_black() -> StandardMaterial3D:
	var k := "cavity_black"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.004, 0.004, 0.006)
	m.metallic = 0.0
	m.roughness = 0.98
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = k
	_cache[k] = m
	return m


static func visor_cavity() -> StandardMaterial3D:
	var k := "visor_cavity"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	# 腔体内壁是可辨认的深蓝金属，而不是纯黑虚空：透过玻璃能看到“里面”
	m.albedo_color = Color(0.018, 0.032, 0.060)
	m.metallic = 0.45
	m.roughness = 0.38
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = k
	_cache[k] = m
	return m


static func indicator_green() -> Material:
	var k := "indicator_green"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = SIGNAL_GREEN.darkened(0.65)
	m.emission_enabled = true
	m.emission = SIGNAL_GREEN
	m.emission_energy_multiplier = 1.1
	m.roughness = 0.30
	m.metallic = 0.20
	m.resource_name = "indicator_green"
	_cache[k] = m
	return m


static func lens_blue() -> ShaderMaterial:
	var k := "lens_blue"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = LENS_SHADER
	m.resource_name = k
	m.set_shader_parameter("glass_color", Color(0.004, 0.008, 0.018))
	m.set_shader_parameter("iris_color", Color(0.08, 0.32, 1.0))
	m.set_shader_parameter("core_color", Color(0.48, 0.76, 1.0))
	m.set_shader_parameter("hot_color", Color(0.85, 0.96, 1.0))
	m.set_shader_parameter("rim_color", Color(0.02, 0.08, 0.30))
	m.set_shader_parameter("intensity", 3.2)
	m.set_shader_parameter("lens_radius", 0.062)
	m.set_shader_parameter("pupil_radius", 0.30)
	m.set_shader_parameter("iris_radius", 0.58)
	m.set_shader_parameter("blade_count", 7.0)
	m.set_shader_parameter("iris_speed", 0.55)
	m.set_shader_parameter("pulse_speed", 1.7)
	m.set_shader_parameter("scan_speed", 0.85)
	m.set_shader_parameter("aperture", 0.62)
	m.set_shader_parameter("alert", 0.0)
	m.set_shader_parameter("phase", 0.0)
	m.set_shader_parameter("seed", 0.0)
	_cache[k] = m
	return m


# ------------------------------------------------------------------- weapon
static func crossguard() -> Material:
	var k := "crossguard"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = BLADE_CORE_SHADER
	m.set_shader_parameter("hot_color", Color(0.82, 0.95, 1.0))
	m.set_shader_parameter("mid_color", Color(0.08, 0.40, 1.0))
	m.set_shader_parameter("tip_color", Color(0.45, 0.86, 1.0))
	m.set_shader_parameter("energy", 1.65)
	m.set_shader_parameter("core_boost", 0.45)
	m.set_shader_parameter("scan_scale", 22.0)
	m.set_shader_parameter("flow_speed", 16.0)
	m.set_shader_parameter("scan_strength", 0.18)
	m.resource_name = "crossguard"
	_cache[k] = m
	return m


static func blade_core() -> ShaderMaterial:
	var k := "blade_core"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = BLADE_CORE_SHADER
	m.set_shader_parameter("hot_color", Color(0.88, 0.96, 1.0))
	m.set_shader_parameter("mid_color", Color(0.08, 0.42, 1.0))
	m.set_shader_parameter("tip_color", Color(0.45, 0.86, 1.0))
	m.set_shader_parameter("energy", 1.50)
	m.set_shader_parameter("core_boost", 0.45)
	m.set_shader_parameter("scan_scale", 28.0)
	m.set_shader_parameter("flow_speed", 14.0)
	m.set_shader_parameter("scan_strength", 0.18)
	_cache[k] = m
	return m


static func blade_glow() -> ShaderMaterial:
	var k := "blade_glow"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = BLADE_GLOW_SHADER
	m.set_shader_parameter("color", Color(0.10, 0.44, 1.0))
	m.set_shader_parameter("edge_color", Color(0.55, 0.88, 1.0))
	m.set_shader_parameter("strength", 0.65)
	_cache[k] = m
	return m


static func engine_petal() -> ShaderMaterial:
	var k := "engine_petal"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = PETAL_SHADER
	m.set_shader_parameter("edge_color", Color(0.30, 0.62, 1.0))
	m.set_shader_parameter("intensity", 1.0)
	m.set_shader_parameter("open_glow", 0.0)
	_cache[k] = m
	return m


static func thruster() -> ShaderMaterial:
	var k := "thruster"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = THRUSTER_SHADER
	m.set_shader_parameter("color", Color(0.08, 0.28, 1.0))
	m.set_shader_parameter("rim_color", Color(0.20, 0.55, 1.0))
	m.set_shader_parameter("hot_color", Color(0.85, 0.95, 1.0))
	m.set_shader_parameter("boost", 0.0)
	m.set_shader_parameter("energy", 3.2)
	m.set_shader_parameter("intensity", 1.0)
	m.set_shader_parameter("flicker_speed", 17.0)
	m.set_shader_parameter("seed", 0.0)
	_cache[k] = m
	return m


static func trail() -> ShaderMaterial:
	var k := "trail"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = TRAIL_SHADER
	m.set_shader_parameter("energy", 2.1)
	m.set_shader_parameter("color", Color(0.10, 0.34, 1.0))
	m.set_shader_parameter("tint_mix", 1.0)
	_cache[k] = m
	return m


# ---------------------------------------------------------------- arena / fx
static func floor() -> ShaderMaterial:
	var k := "floor"
	var cached := _cache.get(k) as ShaderMaterial
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = FLOOR_SHADER
	m.set_shader_parameter("base_color", Color(0.010, 0.014, 0.022))
	m.set_shader_parameter("line_color", Color(0.28, 0.55, 1.0))
	m.set_shader_parameter("cool_color", Color(0.14, 0.36, 1.0))
	m.set_shader_parameter("grid_glow", 0.20)
	_cache[k] = m
	return m


static func ring_fx() -> ShaderMaterial:
	var k := "ring_fx"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter("color", Color(0.10, 0.34, 1.0))
	m.set_shader_parameter("energy", 1.8)
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


static func dust() -> Material:
	var k := "dust"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.55, 0.72, 1.0, 0.22)
	m.emission_enabled = true
	m.emission = Color(0.30, 0.55, 1.0)
	m.emission_energy_multiplier = 0.5
	m.disable_receive_shadows = true
	m.no_depth_test = false
	m.resource_name = "dust"
	_cache[k] = m
	return m


static func contact_shadow() -> Material:
	var k := "contact_shadow"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.0, 0.0, 0.0, 0.62)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.resource_name = "contact_shadow"
	_cache[k] = m
	return m


static func pylon() -> Material:
	var k := "pylon"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := _standard(Color(0.016, 0.022, 0.034), 0.55, 0.62)
	m.resource_name = "pylon"
	_cache[k] = m
	return m


static func mote() -> Material:
	var k := "mote"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.55, 0.72, 1.0, 0.22)
	m.emission_enabled = false
	m.disable_receive_shadows = true
	m.resource_name = "mote"
	_cache[k] = m
	return m


static func hit_flash() -> Material:
	var k := "hit_flash"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.80, 0.92, 1.0, 0.90)
	m.emission_enabled = false
	m.disable_receive_shadows = true
	m.resource_name = "hit_flash"
	_cache[k] = m
	return m


static func spark() -> Material:
	var k := "spark"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.70, 0.85, 1.0, 0.95)
	m.emission_enabled = true
	m.emission = Color(0.28, 0.60, 1.0)
	m.emission_energy_multiplier = 0.8
	m.disable_receive_shadows = true
	m.resource_name = "spark"
	_cache[k] = m
	return m


static func smoke() -> Material:
	var k := "smoke"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = radial_texture()
	m.albedo_color = Color(0.32, 0.38, 0.48, 0.38)
	m.disable_receive_shadows = true
	m.resource_name = "smoke"
	_cache[k] = m
	return m


static func speed_streak() -> Material:
	var k := "streak"
	var cached: Material = _cache.get(k)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.55, 0.75, 1.0, 0.25)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.resource_name = "speed_streak"
	_cache[k] = m
	return m
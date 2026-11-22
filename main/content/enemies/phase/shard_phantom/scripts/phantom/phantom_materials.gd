extends RefCounted
## PhantomMaterials — palette + shader instances for the shard phantom.
##
## Palette: matte near-black machined metal, deep oxblood panels, a handful of
## orange-red signal edges.  Energy is always orange-red -> white-hot core.

const MODULE_SHADER := preload("res://shaders/module_shell.gdshader")
const SHURIKEN_SHADER := preload("res://shaders/shuriken.gdshader")
const TRAIL_SHADER := preload("res://shaders/energy_trail.gdshader")
const PLUME_SHADER := preload("res://shaders/micro_thruster.gdshader")
const RING_SHADER := preload("res://shaders/assembly_ring.gdshader")
const GROUND_SHADER := preload("res://shaders/ground_glow.gdshader")
const SHADOW_SHADER := preload("res://shaders/soft_shadow.gdshader")
const LENS_SHADER := preload("res://shaders/lens.gdshader")
const EMITTER_SHADER := preload("res://shaders/palm_emitter.gdshader")
const VENT_SHADER := preload("res://shaders/vent_plume.gdshader")
const MK := preload("res://scripts/kit/mesh_kit.gd")

const ENERGY := Color(1.0, 0.22, 0.045)
const ENERGY_HOT := Color(1.0, 0.66, 0.34)
const SIGNAL := Color(1.0, 0.13, 0.035)

const TINTS := [
	Color(0.018, 0.018, 0.022),   # near-black matte shell
	Color(0.015, 0.015, 0.019),   # near-black matte shell
	Color(0.011, 0.011, 0.014),   # darker graphite
	Color(0.055, 0.004, 0.005),   # oxblood panel
	Color(0.085, 0.011, 0.011),   # deep red
	Color(0.105, 0.082, 0.076),   # warm graphite
]

static var _cache: Dictionary = {}


static func _keep(k: String, v):
	_cache[k] = v
	return v


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
	return m


static func module() -> ShaderMaterial:
	var m: ShaderMaterial = _cache.get("module")
	if m != null:
		return m
	m = ShaderMaterial.new()
	m.shader = MODULE_SHADER
	m.set_shader_parameter("base_color", Color(0.010, 0.010, 0.012))
	m.set_shader_parameter("edge_color", ENERGY)
	m.set_shader_parameter("metallic_value", 0.88)
	m.set_shader_parameter("roughness_value", 0.54)
	return _keep("module", m)


static func inner_shell() -> ShaderMaterial:
	return _metal_frame("inner_shell", Color(0.014, 0.014, 0.017), 0.9, 0.58)


static func seam() -> StandardMaterial3D:
	var m = _cache.get("seam")
	if m != null:
		return m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.030, 0.010, 0.010)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.10, 0.025)
	mat.emission_energy_multiplier = 0.32
	mat.metallic = 0.5
	mat.roughness = 0.45
	return _keep("seam", mat)


static func _metal_frame(key: String, albedo: Color, metallic: float, rough: float) -> ShaderMaterial:
	var m: ShaderMaterial = _cache.get(key)
	if m != null:
		return m
	m = ShaderMaterial.new()
	m.shader = MODULE_SHADER
	m.set_shader_parameter("style", 1.0)
	m.set_shader_parameter("base_color", albedo)
	m.set_shader_parameter("fx_tint", albedo)
	m.set_shader_parameter("metallic_value", metallic)
	m.set_shader_parameter("roughness_value", rough)
	m.set_shader_parameter("edge_gain", 0.0)
	return _keep(key, m)


static func frame() -> ShaderMaterial:
	return _metal_frame("frame", Color(0.016, 0.016, 0.019), 0.9, 0.56)


static func frame_light() -> ShaderMaterial:
	return _metal_frame("frame_light", Color(0.022, 0.022, 0.026), 0.9, 0.52)


static func trim() -> ShaderMaterial:
	return _metal_frame("trim", Color(0.085, 0.084, 0.090), 0.92, 0.48)


static func dark_glass() -> StandardMaterial3D:
	var m = _cache.get("dark_glass")
	if m != null:
		return m
	return _keep("dark_glass", pbr(Color(0.005, 0.006, 0.009), 0.95, 0.08, 0.5, 0.6))


static func emissive(color: Color, energy := 4.0) -> StandardMaterial3D:
	var k := "emit_%s_%s" % [color.to_html(), energy]
	var m = _cache.get(k)
	if m != null:
		return m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.65)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.metallic = 0.2
	mat.roughness = 0.32
	mat.disable_receive_shadows = true
	return _keep(k, mat)


static func head_optic() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LENS_SHADER
	m.set_shader_parameter("glass_color", Color(0.006, 0.006, 0.009))
	m.set_shader_parameter("iris_color", Color(1.0, 0.15, 0.03))
	m.set_shader_parameter("intensity", 3.2)
	m.set_shader_parameter("pupil_radius", 0.24)
	m.set_shader_parameter("iris_radius", 0.72)
	m.set_shader_parameter("ring_frequency", 46.0)
	m.set_shader_parameter("scan_speed", 0.72)
	m.set_shader_parameter("seed", 0.37)
	m.set_shader_parameter("alert", 0.0)
	return m


static func emitter() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = EMITTER_SHADER
	m.set_shader_parameter("housing", Color(0.012, 0.012, 0.014))
	m.set_shader_parameter("rim_color", Color(1.0, 0.20, 0.04))
	m.set_shader_parameter("core_color", Color(1.0, 0.60, 0.24))
	m.set_shader_parameter("intensity", 2.3)
	m.set_shader_parameter("charge", 0.0)
	m.set_shader_parameter("seed", 0.71)
	return m


static func shuriken() -> ShaderMaterial:
	var m: ShaderMaterial = _cache.get("shuriken")
	if m != null:
		return m
	m = ShaderMaterial.new()
	m.shader = SHURIKEN_SHADER
	m.set_shader_parameter("hot_color", Color(1.0, 0.96, 0.88))
	m.set_shader_parameter("energy_color", Color(1.0, 0.22, 0.03))
	m.set_shader_parameter("intensity", 2.7)
	m.set_shader_parameter("spin", 6.0)
	m.set_shader_parameter("blades", 4.0)
	return _keep("shuriken", m)


static func trail() -> ShaderMaterial:
	var m: ShaderMaterial = _cache.get("trail")
	if m != null:
		return m
	m = ShaderMaterial.new()
	m.shader = TRAIL_SHADER
	m.set_shader_parameter("hot_color", Color(1.0, 0.90, 0.72))
	m.set_shader_parameter("energy_color", ENERGY)
	m.set_shader_parameter("intensity", 2.1)
	return _keep("trail", m)


static func vent() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = VENT_SHADER
	m.set_shader_parameter("hot_color", Color(1.0, 0.88, 0.66))
	m.set_shader_parameter("flame_color", Color(1.0, 0.18, 0.025))
	m.set_shader_parameter("intensity", 3.4)
	return m


static func plume() -> ShaderMaterial:
	var m: ShaderMaterial = _cache.get("plume")
	if m != null:
		return m
	m = ShaderMaterial.new()
	m.shader = PLUME_SHADER
	m.set_shader_parameter("hot_color", Color(1.0, 0.90, 0.72))
	m.set_shader_parameter("flame_color", Color(1.0, 0.20, 0.03))
	m.set_shader_parameter("intensity", 1.35)
	return _keep("plume", m)


static func assembly_ring() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter("tint", ENERGY)
	m.set_shader_parameter("intensity", 0.50)
	return m


static func ground_glow() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("tint", Color(1.0, 0.115, 0.015))
	m.set_shader_parameter("intensity", 0.45)
	return m


static func charge_glow() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = MAT_RADIAL()
	mat.albedo_color = Color(1.0, 0.34, 0.07, 1.0)
	mat.disable_receive_shadows = true
	return mat


static func soft_shadow(strength := 0.75) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_SHADER
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("softness", 2.6)
	mat.set_shader_parameter("tint", Color(0.0, 0.0, 0.0))
	mat.render_priority = 3
	return mat


static func contact_shadow(alpha := 0.72) -> StandardMaterial3D:
	var k := "shadow_%s" % alpha
	var m = _cache.get(k)
	if m != null:
		return m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = MAT_RADIAL()
	mat.albedo_color = Color(0.0, 0.0, 0.0, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return _keep(k, mat)


static func MAT_RADIAL() -> GradientTexture2D:
	if _cache.has("radial"):
		return _cache["radial"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.30, Color(1, 1, 1, 0.82))
	g.add_point(0.64, Color(1, 1, 1, 0.24))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_keep("radial", t)
	return t
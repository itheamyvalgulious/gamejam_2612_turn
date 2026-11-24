## Shared materials. One uber surface material + one glass material for the whole city.
class_name Mats
extends RefCounted

static var surface: Material
static var shader_mat: ShaderMaterial
static var glass: ShaderMaterial
static var _built := false

static func build() -> void:
	if _built:
		return
	_built = true
	var s: Shader = load("res://gfx/surface.gdshader")
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = s
	surface = shader_mat
	var g: Shader = load("res://gfx/glass.gdshader")
	glass = ShaderMaterial.new()
	glass.shader = g
	glass.render_priority = 1

static func sun(night: float, wet: float) -> void:
	if shader_mat == null:
		return
	shader_mat.set_shader_parameter("night", night)
	shader_mat.set_shader_parameter("wetness", wet)
	glass.set_shader_parameter("night", night)
	glass.set_shader_parameter("wetness", wet)

# sRGB hex -> linear Color for vertex tints
static func c(hex: String, a := 1.0) -> Color:
	var col := Color(hex)
	col.a = a
	return col.srgb_to_linear()

static func cr(r: float, g: float, b: float) -> Color:
	return Color(r, g, b).srgb_to_linear()

static func jitter(rng: RandomNumberGenerator, base: Color, amt := 0.08) -> Color:
	var f := 1.0 + rng.randf_range(-amt, amt)
	return Color(base.r * f, base.g * f, base.b * f, base.a)
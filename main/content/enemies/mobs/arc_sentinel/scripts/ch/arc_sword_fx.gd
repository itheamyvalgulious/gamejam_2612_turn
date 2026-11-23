class_name ArcSwordFX2
extends MeshInstance3D
## Every sword selects from the same library of prebuilt, single-surface ribbons.

const VARIANTS: MeshLibrary = preload("res://assets/vfx/arc_ribbon_variants.res")
const RIBBON_SHADER: Shader = preload("res://shaders/arc_ribbon.gdshader")
const SHAPE_INTERVAL_MIN := 0.044
const SHAPE_INTERVAL_MAX := 0.067
const REFERENCE_BLADE_LENGTH := 2.24

static var _variant_ids := VARIANTS.get_item_list()
static var _ribbon_material: ShaderMaterial

@export_range(0.05, 2.0, 0.01) var blade_scale := 0.46

@export var external_intensity := 1.0:
	set(value):
		if is_equal_approx(external_intensity, value):
			return
		external_intensity = value
		if is_node_ready():
			set_instance_shader_parameter("arc_intensity", external_intensity)

var _rng := RandomNumberGenerator.new()
var _shape := -1
var _shape_left := 0.0


func _ready() -> void:
	if _ribbon_material == null:
		_ribbon_material = ShaderMaterial.new()
		_ribbon_material.shader = RIBBON_SHADER
	material_override = _ribbon_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 0.15
	_apply_scale()
	set_instance_shader_parameter("arc_intensity", external_intensity)
	_rng.randomize()
	set_instance_shader_parameter("arc_phase", _rng.randf_range(0.0, TAU))
	_select_shape()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or external_intensity <= 0.001:
		return
	_shape_left -= delta
	if _shape_left <= 0.0:
		_select_shape()


func _select_shape() -> void:
	var index := _rng.randi_range(0, _variant_ids.size() - 1)
	if index == _shape:
		index = (index + 1) % _variant_ids.size()
	_shape = index
	mesh = VARIANTS.get_item_mesh(_variant_ids[index])
	_shape_left = _rng.randf_range(SHAPE_INTERVAL_MIN, SHAPE_INTERVAL_MAX)


func set_blade_scale(value: float) -> void:
	var clamped := clampf(value, 0.05, 2.0)
	if is_equal_approx(blade_scale, clamped):
		return
	blade_scale = clamped
	_apply_scale()


func _apply_scale() -> void:
	scale = Vector3.ONE * blade_scale
	set_instance_shader_parameter("arc_mesh_scale", blade_scale)


func blade_tip_y() -> float:
	return REFERENCE_BLADE_LENGTH * blade_scale

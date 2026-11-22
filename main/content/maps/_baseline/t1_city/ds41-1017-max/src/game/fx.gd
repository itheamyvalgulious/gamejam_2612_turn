## Weather FX: GPU rain veil around the camera.
class_name Fx
extends Node3D

var rain: GPUParticles3D
var mat: ShaderMaterial

func setup() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://gfx/rain.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.85)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.amount = 5200
	p.lifetime = 1.1
	p.preprocess = 0.6
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-45, -30, -45), Vector3(90, 60, 90))
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(42, 26, 42)
	pm.direction = Vector3(0.08, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 34.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.6
	p.process_material = pm
	add_child(p)
	rain = p
	p.emitting = true

func set_intensity(v: float) -> void:
	if rain:
		rain.emitting = v > 0.2
		rain.amount_ratio = clampf(v, 0.0, 1.0)

func follow(pos: Vector3) -> void:
	rain.global_position = pos + Vector3(0, 16, 0)
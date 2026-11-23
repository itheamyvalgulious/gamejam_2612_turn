extends Node3D
## The warning, beam and contact test all use the same snapshots of the firing lane.

const BeamShader = preload("res://gfx/wheel_sentry_beam.gdshader")
const LaneShader = preload("res://gfx/wheel_sentry_lane.gdshader")
const ArenaKit = preload("res://src/arena/arena.gd")

var start := Vector3.ZERO
var end := Vector3.ZERO
var radius := 0.55

var _glow: MeshInstance3D
var _sheath: MeshInstance3D
var _core: MeshInstance3D
var _aim_line: MeshInstance3D
var _lane: MeshInstance3D
var _muzzle: MeshInstance3D
var _muzzle_light: OmniLight3D
var _rings: Array[MeshInstance3D] = []
var _core_material: ShaderMaterial
var _sheath_material: ShaderMaterial
var _glow_material: ShaderMaterial
var _lane_material: ShaderMaterial
var _ring_material: StandardMaterial3D


func configure(origin: Vector3, limit: Vector3, width: float) -> void:
	start = origin
	end = limit
	radius = width
	var distance := maxf(start.distance_to(end), 0.01)
	global_position = start
	if start.distance_squared_to(end) > 0.0001:
		look_at(end)

	_core_material = _tube_material(Color("fff5cb"), 0.0)
	_sheath_material = _tube_material(Color("ffae3e"), 0.58)
	_glow_material = _tube_material(Color("ff611e"), 1.0)
	_aim_line = _tube(radius * 0.09, distance, _tube_material(Color("ff6931"), 0.0))
	_core = _tube(radius * 0.43, distance, _core_material)
	_sheath = _tube(radius * 0.69, distance, _sheath_material)
	_glow = _tube(radius, distance, _glow_material)

	var flat := Vector3(end.x - start.x, 0, end.z - start.z)
	var floor_strip := PlaneMesh.new()
	floor_strip.size = Vector2(radius * 2.0, maxf(flat.length(), 0.01))
	_lane_material = ShaderMaterial.new()
	_lane_material.shader = LaneShader
	_lane_material.set_shader_parameter("length_world", flat.length())
	_lane = _mesh(floor_strip, _lane_material)
	_lane.top_level = true
	_lane.global_position = Vector3((start.x + end.x) * 0.5, 0.056, (start.z + end.z) * 0.5)
	_lane.global_rotation.y = atan2(-flat.x, -flat.z)

	var core_ball := SphereMesh.new()
	core_ball.radius = 0.22
	core_ball.height = 0.44
	_muzzle = _mesh(core_ball, _emission(Color("ff922b"), 4.2))
	_muzzle.position.z = -0.13
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color("ff6432")
	_muzzle_light.omni_range = 10.0
	add_child(_muzzle_light)
	_muzzle_light.position.z = -0.30

	var ring := TorusMesh.new()
	ring.inner_radius = radius * 0.84
	ring.outer_radius = radius * 0.90
	ring.rings = 32
	ring.ring_segments = 6
	_ring_material = _emission(Color("ff973d"), 2.8)
	for i in 5:
		var rim := _mesh(ring, _ring_material)
		rim.rotation.x = PI * 0.5
		_rings.append(rim)
	show_warning(0.0)


func show_warning(progress: float) -> void:
	_core.hide()
	_sheath.hide()
	_glow.hide()
	_aim_line.show()
	_lane.show()
	_lane_material.set_shader_parameter("phase", progress)
	_lane_material.set_shader_parameter("strength", lerpf(0.66, 1.5, progress))
	_muzzle.scale = Vector3.ONE * lerpf(0.22, 1.12, progress)
	_muzzle_light.light_energy = 0.2 + progress * progress * 3.2
	for i in _rings.size():
		var ring := _rings[i]
		var turn := fposmod(progress * 1.35 + float(i) / _rings.size(), 1.0)
		ring.position.z = -0.24 - turn * 0.60
		ring.scale = Vector3.ONE * lerpf(1.15, 0.30, turn) * lerpf(0.56, 0.98, progress)


func show_fire(age: float, duration: float) -> void:
	_aim_line.hide()
	_core.show()
	_sheath.show()
	_glow.show()
	var active := 1.0 - smoothstep(duration * 0.58, duration, age)
	var initial_pulse := 1.0 - smoothstep(0.0, 0.14, age)
	_core_material.set_shader_parameter("strength", lerpf(0.50, 1.18, active))
	_sheath_material.set_shader_parameter("strength", (0.26 + 0.48 * active) * (1.0 + initial_pulse * 0.75))
	_glow_material.set_shader_parameter("strength", lerpf(0.25, 0.78, active) + 0.26 * initial_pulse)
	_lane_material.set_shader_parameter("strength", 0.52 * active)
	_muzzle.scale = Vector3.ONE * (lerpf(0.85, 2.15, active) + 0.68 * initial_pulse)
	_muzzle_light.light_energy = lerpf(2.0, 10.0, active) + 4.3 * initial_pulse
	_ring_material.albedo_color = Color("ff973d") * lerpf(0.6, 3.6, active)
	var length := start.distance_to(end)
	var travel_speed := maxf(28.0, length / maxf(0.1, duration * 0.62))
	var spacing := maxf(1.25, length * 0.09)
	for i in _rings.size():
		var ring := _rings[i]
		var travel := age * travel_speed - i * spacing
		ring.visible = travel >= 0.0 and travel < length and active > 0.06
		ring.position.z = -clampf(travel, 0.0, length)
		ring.scale = Vector3.ONE * lerpf(0.93, 1.10, clampf(travel / maxf(length, 0.01), 0.0, 1.0))


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _tube(width: float, length: float, mat: Material) -> MeshInstance3D:
	var tube := CylinderMesh.new()
	tube.top_radius = width
	tube.bottom_radius = width
	tube.height = length
	tube.radial_segments = 24
	tube.rings = 1
	tube.cap_top = false
	tube.cap_bottom = false
	var body := _mesh(tube, mat)
	body.rotation.x = -PI * 0.5
	body.position.z = -length * 0.5
	return body


func _emission(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color * energy
	return mat


func _tube_material(color: Color, detail: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = BeamShader
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("detail", detail)
	mat.set_shader_parameter("strength", 0.9)
	return mat


static func clip_end(origin: Vector3, target: Vector3, arena: Dictionary) -> Vector3:
	var from := Vector2(origin.x, origin.z)
	var to := Vector2(target.x, target.z)
	var delta := to - from
	var closest := 1.0
	var distance := origin.distance_to(target)
	for solid: AABB in arena.get("solids", []):
		var entry: Variant = solid.intersects_segment(origin, target)
		if entry != null and distance > 0.0001:
			closest = minf(closest, origin.distance_to(entry) / distance)
	if delta.length_squared() < 0.0001:
		return origin.lerp(target, closest)
	for wall: Dictionary in arena.get("walls", []):
		var cross = Geometry2D.segment_intersects_segment(from, to, wall["a"], wall["b"])
		if cross == null:
			continue
		var portion: float = (cross - from).dot(delta) / delta.length_squared()
		var height := lerpf(origin.y, target.y, portion)
		if height >= 0.0 and height <= float(wall["h"]):
			closest = minf(closest, portion)
	for object: Dictionary in arena.get("cover", []):
		var bottom: Vector3 = object["c"]
		var circle := Vector2(bottom.x, bottom.z)
		var size := maxf(0.01, float(object["r"]) - ArenaKit.BALL)
		var entry := Geometry2D.segment_intersects_circle(from, to, circle, size)
		if from.distance_squared_to(circle) <= size * size:
			entry = 0.0
		if entry < 0.0:
			continue
		var reverse_entry := Geometry2D.segment_intersects_circle(to, from, circle, size)
		var exit := 1.0 - maxf(0.0, reverse_entry)
		if to.distance_squared_to(circle) <= size * size:
			exit = 1.0
		var height := lerpf(origin.y, target.y, entry)
		var top: float = bottom.y + float(object["h"])
		if height > top and target.y < top:
			entry = inverse_lerp(origin.y, target.y, top)
			height = top
		elif height < bottom.y and target.y > bottom.y:
			entry = inverse_lerp(origin.y, target.y, bottom.y)
			height = bottom.y
		if entry <= exit and height >= bottom.y and height <= top:
			closest = minf(closest, entry)
	# Keep the terminal glow out of the wall instead of extending behind it.
	return origin.lerp(target, maxf(0.0, closest - (0.025 / origin.distance_to(target) if closest < 1.0 else 0.0)))

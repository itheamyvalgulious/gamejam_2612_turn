extends Node3D
## The warning, beam and contact test all use the same snapshots of the firing lane.

const BeamShader = preload("res://gfx/wheel_sentry_beam.gdshader")
const LaneShader = preload("res://gfx/wheel_sentry_lane.gdshader")
const ArenaKit = preload("res://src/arena/arena.gd")

var start := Vector3.ZERO
var end := Vector3.ZERO
var direction := Vector3.FORWARD
var obstruction_distance := INF
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


func configure(origin: Vector3, forward: Vector3, width: float, arena: Dictionary) -> void:
	start = origin
	direction = forward.normalized()
	radius = width
	obstruction_distance = trace_obstruction(start, direction, arena)
	var camera := get_viewport().get_camera_3d()
	var camera_far := camera.far if camera != null else 500.0
	var bounds: AABB = arena.get("bounds", AABB())
	# With an open ray, draw past the camera's far plane from anywhere in the arena.
	var visible_distance := camera_far * 2.0 + bounds.size.length()
	end = start + direction * (obstruction_distance if is_finite(obstruction_distance) else visible_distance)
	var distance := maxf(start.distance_to(end), 0.01)
	global_position = start
	var up := Vector3.FORWARD if absf(direction.y) > 0.999 else Vector3.UP
	look_at(start + direction, up)

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
	_lane.global_position = Vector3((start.x + end.x) * 0.5, float(arena.get("floor_y", 0.0)) + 0.056, (start.z + end.z) * 0.5)
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


## Distance to the first arena surface along a normalized ray. An open ray returns INF.
static func trace_obstruction(origin: Vector3, forward: Vector3, arena: Dictionary) -> float:
	var closest := INF
	for solid: AABB in arena.get("solids", []):
		if solid.has_point(origin):
			return 0.0
		var point: Variant = solid.intersects_ray(origin, forward)
		if point != null:
			var distance := ((point as Vector3) - origin).dot(forward)
			if distance >= 0.0:
				closest = minf(closest, distance)

	var floor_y := float(arena.get("floor_y", 0.0))
	if arena.has("floor_y") and forward.y < 0.0 and origin.y >= floor_y:
		var distance := (floor_y - origin.y) / forward.y
		var landing := origin + forward * distance
		var bounds: AABB = arena.get("bounds", AABB())
		if not bounds.has_surface() or (landing.x >= bounds.position.x and landing.x <= bounds.end.x
			and landing.z >= bounds.position.z and landing.z <= bounds.end.z):
			closest = minf(closest, distance)

	var origin_xz := Vector2(origin.x, origin.z)
	var forward_xz := Vector2(forward.x, forward.z)
	for wall: Dictionary in arena.get("walls", []):
		var edge: Vector2 = wall["b"] - wall["a"]
		var determinant := forward_xz.cross(edge)
		if determinant == 0.0:
			continue
		var offset: Vector2 = wall["a"] - origin_xz
		var distance := offset.cross(edge) / determinant
		var along_wall := offset.cross(forward_xz) / determinant
		var height := origin.y + forward.y * distance
		if distance >= 0.0 and along_wall >= 0.0 and along_wall <= 1.0 \
				and height >= floor_y and height <= floor_y + float(wall["h"]):
			closest = minf(closest, distance)

	for object: Dictionary in arena.get("cover", []):
		var bottom: Vector3 = object["c"]
		var size := maxf(0.01, float(object["r"]) - ArenaKit.BALL)
		var distance := _cylinder_entry(origin - bottom, forward, size, float(object["h"]))
		closest = minf(closest, distance)
	return closest


static func _cylinder_entry(offset: Vector3, forward: Vector3, width: float, height: float) -> float:
	# Intersect the horizontal disk and the vertical interval, including the caps.
	var radial := Vector2(offset.x, offset.z)
	var horizontal := Vector2(forward.x, forward.z)
	var speed_squared := horizontal.length_squared()
	var outside := radial.length_squared() - width * width
	var entry := 0.0
	var leave := INF
	if speed_squared > 0.0:
		var approach := radial.dot(horizontal)
		var discriminant := approach * approach - speed_squared * outside
		if discriminant < 0.0:
			return INF
		var half_span := sqrt(discriminant)
		entry = maxf(entry, (-approach - half_span) / speed_squared)
		leave = (-approach + half_span) / speed_squared
	elif outside > 0.0:
		return INF

	if forward.y != 0.0:
		var lower := -offset.y / forward.y
		var upper := (height - offset.y) / forward.y
		entry = maxf(entry, minf(lower, upper))
		leave = minf(leave, maxf(lower, upper))
	elif offset.y < 0.0 or offset.y > height:
		return INF
	return entry if entry <= leave else INF

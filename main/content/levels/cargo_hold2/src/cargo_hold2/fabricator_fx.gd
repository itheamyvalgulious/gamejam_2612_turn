extends Node3D

# Each pass is projected onto the posed model. Sampling happens once, before the film.
const SEAM_LIMITS := [
	[Vector2(-0.92, -0.04), Vector2(-0.39, 0.14)],
	[Vector2(0.88, 0.00), Vector2(0.39, 0.18)],
	[Vector2(-0.32, -0.27), Vector2(0.31, -0.27)],
]
const VERTEX_SAMPLES := 24
const MAX_SPARKS := 105

var _streaks := ImmediateMesh.new()
var _sparks := MeshInstance3D.new()
var _spark_material := StandardMaterial3D.new()
var _heat_light := OmniLight3D.new()
var _arc := MeshInstance3D.new()
var _arc_material := StandardMaterial3D.new()
var _metal: Array[MeshInstance3D] = []
var _tracks: Array[PackedVector3Array] = []
var _rng := RandomNumberGenerator.new()
var _particles: Array[Dictionary] = []
var _spark_count := 0.0
var _was_cutting := false
var _hot_point := Vector3.ZERO
var _heat := 0.0


func _ready() -> void:
	_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spark_material.vertex_color_use_as_albedo = true
	_sparks.mesh = _streaks
	_sparks.material_override = _spark_material
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)

	var plasma := CylinderMesh.new()
	plasma.top_radius = 0.009
	plasma.bottom_radius = 0.019
	plasma.height = 1.0
	plasma.radial_segments = 9
	_arc.mesh = plasma
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.albedo_color = Color("ffd3a2")
	_arc_material.emission_enabled = true
	_arc_material.emission = Color("ffb66b")
	_arc.material_override = _arc_material
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc)
	_heat_light.light_color = Color("ffb478")
	_heat_light.omni_range = 2.20
	_heat_light.light_specular = 1.10
	add_child(_heat_light)


func begin(rig: Node3D) -> void:
	_rng.seed = 61514
	var body: Node3D = rig.body
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var mat := mesh.get_active_material(0) as ShaderMaterial
		if mat != null and mat.shader != null and mat.shader.resource_path.get_file() == "vesper_metal.gdshader":
			_metal.append(mesh)
	if _tracks.is_empty():
		_bake_tracks(rig.global_position)


func _bake_tracks(origin: Vector3) -> void:
	var surfaces: Array[Dictionary] = []
	for metal in _metal:
		var bounds := metal.global_transform * metal.get_aabb()
		if bounds.end.y < 1.85 or bounds.position.y > 3.16:
			continue
		if bounds.position.z > origin.z + 0.48 or bounds.end.z < origin.z - 0.54:
			continue
		surfaces.append({"bounds": bounds, "local": metal.global_transform.affine_inverse(), "faces": metal.mesh.get_faces()})

	for limits in SEAM_LIMITS:
		var best := PackedVector3Array()
		for z_offset in [0.0, -0.10, 0.10, -0.19, 0.19, 0.28]:
			var run := PackedVector3Array()
			for i in VERTEX_SAMPLES:
				var offset: Vector2 = limits[0].lerp(limits[1], i / float(VERTEX_SAMPLES - 1))
				var hit := _surface_hit(origin.x + offset.x, origin.z + offset.y + z_offset, surfaces)
				if not hit.is_finite():
					run.clear()
					continue
				if not run.is_empty() and absf(run[-1].y - hit.y) > 0.10:
					run.clear()
				run.append(hit)
				if run.size() > best.size():
					best = run.duplicate()
		_tracks.append(best)


func _surface_hit(x: float, z: float, surfaces: Array[Dictionary]) -> Vector3:
	var ray := Vector3(x, 3.17, z)
	var highest := -INF
	for surface in surfaces:
		var aabb: AABB = surface["bounds"]
		if x < aabb.position.x or x > aabb.end.x or z < aabb.position.z or z > aabb.end.z:
			continue
		var inverse: Transform3D = surface["local"]
		var local_ray := inverse * ray
		var local_dir := inverse.basis * Vector3.DOWN
		var faces: PackedVector3Array = surface["faces"]
		for v in range(0, faces.size(), 3):
			var point = Geometry3D.ray_intersects_triangle(local_ray, local_dir, faces[v], faces[v + 1], faces[v + 2])
			if point != null:
				var distance: float = (point - local_ray).dot(local_dir) / local_dir.length_squared()
				var y := ray.y - distance
				if y >= 1.85:
					highest = maxf(highest, y)
	return Vector3(x, highest, z)


func sample_seam(index: int, t: float) -> Vector3:
	var track := _tracks[index]
	if track.size() < 2:
		return Vector3.INF
	var cursor := clampf(t, 0.0, 1.0) * float(track.size() - 1)
	var lo := mini(floori(cursor), track.size() - 2)
	return track[lo].lerp(track[lo + 1], cursor - float(lo))


func machine(dt: float, nozzle: Vector3, contact: Vector3, power: float) -> void:
	var cutting := power > 0.04 and contact.is_finite()
	if cutting:
		_hot_point = contact
		_heat = clampf(power, 0.0, 1.0)
		_spark_count += dt * (40.0 + 98.0 * power)
		if not _was_cutting:
			_spark_count += 13.0
		while _spark_count >= 1.0 and _particles.size() < MAX_SPARKS:
			_spark_count -= 1.0
			_scatter(contact, power)
	else:
		_heat = move_toward(_heat, 0.0, dt * 3.4)
		_spark_count = 0.0
	_was_cutting = cutting
	for metal in _metal:
		metal.set_instance_shader_parameter(&"cargo_fabrication", Vector4(_hot_point.x, _hot_point.y, _hot_point.z, _heat))

	_arc.visible = cutting
	if cutting:
		var delta := nozzle - contact
		var axis := delta.normalized()
		var side := Vector3.FORWARD.cross(axis).normalized()
		_arc.global_transform = Transform3D(Basis(side, delta, side.cross(axis)), contact + delta * 0.5)
		_arc_material.emission_energy_multiplier = 0.65 + power * 2.35
	_heat_light.global_position = _hot_point + Vector3.UP * 0.12
	_heat_light.light_energy = _heat * (0.56 + 0.84 * pow(_rng.randf(), 3.0))
	_draw_sparks(dt)


func _scatter(contact: Vector3, power: float) -> void:
	var phi := _rng.randf_range(0.0, TAU)
	var speed := _rng.randf_range(1.75, 4.4) * (0.72 + power * 0.28)
	var velocity := Vector3(cos(phi) * speed - 0.35,
		_rng.randf_range(0.38, 1.62), sin(phi) * speed - 0.48)
	var duration := _rng.randf_range(0.13, 0.38)
	_particles.append({"p": to_local(contact) + Vector3.UP * 0.03, "v": velocity, "age": 0.0, "life": duration})


func _draw_sparks(dt: float) -> void:
	_streaks.clear_surfaces()
	var drew := false
	for i in range(_particles.size() - 1, -1, -1):
		var spark := _particles[i]
		var age: float = spark["age"] + dt
		var life: float = spark["life"]
		if age >= life:
			_particles.remove_at(i)
			continue
		var velocity: Vector3 = spark["v"]
		var at: Vector3 = spark["p"]
		spark["age"] = age
		velocity.y -= 7.2 * dt
		at += velocity * dt
		spark["p"] = at
		spark["v"] = velocity
		if not drew:
			_streaks.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			drew = true
		var width := Vector3(-velocity.z, 0, velocity.x).normalized() * 0.018
		var color := Color(2.5, 1.14, 0.41, 0.97 * (1.0 - age / life))
		_streaks.surface_set_color(color)
		_streaks.surface_add_vertex(at - width)
		_streaks.surface_add_vertex(at + width)
		_streaks.surface_set_color(Color(1.0, 0.32, 0.10, 0.0))
		_streaks.surface_add_vertex(at - velocity * 0.063)
	if drew:
		_streaks.surface_end()
	_sparks.visible = drew


func finish_print() -> void:
	_arc.hide()
	_sparks.hide()
	_heat_light.light_energy = 0.0
	_heat = 0.0
	_spark_count = 0.0
	_was_cutting = false
	_particles.clear()
	for metal in _metal:
		metal.set_instance_shader_parameter(&"cargo_fabrication", Vector4.ZERO)
	_metal.clear()

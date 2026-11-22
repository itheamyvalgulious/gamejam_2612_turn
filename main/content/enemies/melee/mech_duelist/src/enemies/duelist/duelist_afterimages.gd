extends Node3D
## Samples ghost poses along the dash. The armor meshes are shared and built at scene load.

const Lunge = preload("res://src/enemies/duelist/duelist_lunge.gd")
const GhostShader = preload("res://gfx/duelist_afterimage.gdshader")
const SAMPLES := [0.10, 0.255, 0.41, 0.565, 0.72, 0.875]
const FADE_TIME := 0.17

var _anchors: Array[Node3D] = []
var _ghosts: Array[Node3D] = []
var _materials: Array[ShaderMaterial] = []
var _captured: Array[bool] = []
var _last_position := Vector3.ZERO


func setup(actor: Node3D) -> void:
	var armor := {}
	for part in actor.find_children("*", "MeshInstance3D", true, false):
		var piece := part as MeshInstance3D
		if piece.mesh == null or not piece.is_visible_in_tree() or piece.get_aabb().size.length_squared() < 0.15:
			continue
		var anchor := piece.get_parent_node_3d()
		if not armor.has(anchor):
			armor[anchor] = SurfaceTool.new()
			armor[anchor].begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in piece.mesh.get_surface_count():
			armor[anchor].append_from(piece.mesh, index, piece.transform)

	var meshes: Array[ArrayMesh] = []
	for anchor: Node3D in armor:
		_anchors.append(anchor)
		meshes.append(armor[anchor].commit())

	for i in SAMPLES.size():
		var ghost := Node3D.new()
		ghost.hide()
		add_child(ghost)
		ghost.top_level = true
		ghost.global_transform = Transform3D.IDENTITY
		var material := ShaderMaterial.new()
		material.shader = GhostShader
		for mesh in meshes:
			var layer := MeshInstance3D.new()
			layer.mesh = mesh
			layer.material_override = material
			layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ghost.add_child(layer)
		_ghosts.append(ghost)
		_materials.append(material)
		_captured.append(false)


func capture(actor: Node3D, before: float, time: float, previous: Vector3, current: Vector3, pose: Callable) -> void:
	if time <= Lunge.BURST_START or before >= Lunge.BURST_END:
		return
	if previous.is_equal_approx(current):
		return
	var skeleton := actor.get_node("DuelistSkeleton") as Skeleton3D
	var progress_before := Lunge.burst_at(before)
	var progress_now := Lunge.burst_at(time)
	var changed := false
	for i in SAMPLES.size():
		var sample := _sample_time(i)
		if _captured[i] or sample <= before or sample > time:
			continue
		# Capture the actual path, so steering leaves the old ghosts in place.
		var fraction := inverse_lerp(progress_before, progress_now, Lunge.burst_at(sample))
		var path_position := previous.lerp(current, fraction)
		if path_position.distance_squared_to(_last_position) < 0.012:
			continue
		_last_position = path_position
		_captured[i] = true
		changed = true
		pose.call(sample, path_position)
		skeleton.force_update_all_bone_transforms()
		for j in _anchors.size():
			var piece := _ghosts[i].get_child(j) as Node3D
			piece.transform = _anchors[j].global_transform
	if changed:
		pose.call(time, current)
		skeleton.force_update_all_bone_transforms()


func apply(time: float) -> void:
	for i in _ghosts.size():
		var age := time - _sample_time(i)
		_ghosts[i].visible = _captured[i] and age >= 0.0 and age < FADE_TIME
		if _ghosts[i].visible:
			var opacity := lerpf(0.41, 0.87, float(i) / (SAMPLES.size() - 1))
			opacity *= 1.0 - smoothstep(0.0, FADE_TIME, age)
			_materials[i].set_shader_parameter("opacity", opacity)


func clear() -> void:
	_captured.fill(false)
	_last_position = Vector3.INF
	for ghost in _ghosts:
		ghost.hide()


func _sample_time(index: int) -> float:
	return lerpf(Lunge.BURST_START, Lunge.BURST_END, SAMPLES[index])

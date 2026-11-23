extends "res://src/enemies/duelist/duelist_model.gd"
## Adapts the humanoid sword and articulated model to the shared combat and parry code.

const Lunge = preload("res://src/enemies/duelist/duelist_lunge.gd")
const Sequence = preload("res://src/enemies/duelist/duelist_sequence.gd")
const ReturnCut = preload("res://src/enemies/duelist/duelist_return_cut.gd")
const HIT_START := 0.188
const HIT_END := Lunge.CUT_END
const PREDICTION_STEPS := 20
const SWEEP_SAMPLES := 9

var attack_hit_from := Sequence.attack_seconds(HIT_START)
var attack_hit_to := Sequence.attack_seconds(HIT_END)
var attack_elapsed := 0.0
var is_attacking := false
var last_dt := 1.0 / 60.0
var weapon_scale := 1.0
var weapon_prev_xf := Transform3D.IDENTITY
var weapon_xf := Transform3D.IDENTITY
var _hit_window := false
var _strike_start := 0.0
var _hit_start := HIT_START
var _hit_end := HIT_END
var _prediction: Array[Transform3D] = []
var _opening_clock := true
var _normal_rate := 1.0
var _normal_windup_end := 0.0
var _normal_windup_extension := Sequence.NORMAL_WINDUP_EXTENSION
var _opening_discs: Array = []
var _metal_discs: Array = []
var _body_geometry: Array[Dictionary] = []


func _ready() -> void:
	super()
	_cache_body_geometry()
	_metal_discs = blade_discs.duplicate()
	# Both damage and guard prediction use the visible sweep beyond the metal blade.
	var metal_end := BLADE_START + BLADE_LENGTH
	for i in range(1, SWEEP_SAMPLES + 1):
		var progress := float(i) / SWEEP_SAMPLES
		var radius := lerpf(Blade.TIP_OFFSET, 0.045, progress)
		blade_discs.append({"y": lerpf(metal_end, SWEEP_END, progress), "r": radius})
	_opening_discs = blade_discs


func _cache_body_geometry() -> void:
	for attachment: BoneAttachment3D in _skeleton.get_children():
		if attachment.bone_name == &"Blade":
			continue
		var from_world := attachment.global_transform.affine_inverse()
		var bounds := AABB()
		var faces := PackedVector3Array()
		for mesh: MeshInstance3D in attachment.find_children("*", "MeshInstance3D", true, false):
			var local := from_world * mesh.global_transform
			var mesh_bounds := local * mesh.get_aabb()
			bounds = mesh_bounds if faces.is_empty() else bounds.merge(mesh_bounds)
			faces.append_array(local * mesh.mesh.get_faces())
		if not faces.is_empty():
			_body_geometry.append({
				"target": _skeleton.pose_target(attachment.bone_idx), "bounds": bounds, "faces": faces,
			})


func body_in_view(camera: Camera3D) -> bool:
	if camera == null or not is_visible_in_tree():
		return false
	var frustum := camera.get_frustum()
	for piece in _body_geometry:
		var target := piece["target"] as Node3D
		var from_world := target.global_transform.affine_inverse()
		var local_planes: Array[Plane] = []
		for plane in frustum:
			local_planes.append(from_world * plane)
		if Vision.faces_in_frustum(piece["bounds"], piece["faces"], local_planes):
			return true
	return false


func start_strike(dash: Dictionary, time: float) -> void:
	var live_position := position
	_prepare_strike(0.0, HIT_START, HIT_END,
		func(sample: float) -> void: Lunge.apply(self, dash, sample))
	Lunge.apply(self, dash, time, live_position)


func start_return(pose: Dictionary, time: float) -> void:
	_prepare_strike(Lunge.DURATION, ReturnCut.HIT_START, ReturnCut.HIT_END,
		func(sample: float) -> void: ReturnCut.apply(self, pose, sample))
	ReturnCut.apply(self, pose, time - Lunge.DURATION)


func start_normal(move: GDScript, pose: Dictionary, time: float, rate: float, index := 0, extension := Sequence.NORMAL_WINDUP_EXTENSION) -> void:
	var strike: Vector4 = move.STRIKES[index]
	_normal_rate = rate
	_normal_windup_extension = extension
	_normal_windup_end = move.WINDUP_END
	_prepare_strike(0.0, strike.z, strike.w,
		func(sample: float) -> void: move.apply(self, pose, sample), false)
	move.apply(self, pose, time)


func cancel_strike() -> void:
	is_attacking = false
	_hit_window = false
	_prediction.clear()


func _prepare_strike(start: float, from: float, to: float, sample_pose: Callable, opening := true) -> void:
	_opening_clock = opening
	blade_discs = _opening_discs if opening else _metal_discs
	_strike_start = start
	_hit_start = start + from
	_hit_end = start + to
	attack_hit_from = _strike_seconds(_hit_start)
	attack_hit_to = _strike_seconds(_hit_end)
	_prediction.clear()
	weapon_scale = global_basis.get_scale().x
	for i in range(PREDICTION_STEPS + 1):
		sample_pose.call(lerpf(from, to, float(i) / PREDICTION_STEPS))
		_prediction.append(weapon_spin.global_transform)



func _strike_seconds(time: float) -> float:
	if _opening_clock:
		return Sequence.attack_seconds(time)
	return Sequence.normal_seconds(time, _normal_windup_end, _normal_rate, _normal_windup_extension)


func update_strike(t0: float, t1: float, dt: float) -> void:
	last_dt = dt
	attack_elapsed = _strike_seconds(t1)
	is_attacking = t1 >= _strike_start and t0 < _hit_end and not _prediction.is_empty()
	_hit_window = is_attacking and t1 >= _hit_start and t0 < t1
	if _hit_window:
		weapon_prev_xf = predict_weapon_xf(_strike_seconds(t0))
		weapon_xf = predict_weapon_xf(attack_elapsed)


func in_hit_window() -> bool:
	return _hit_window


func blade_span() -> Vector2:
	return Vector2(BLADE_START, SWEEP_END if _opening_clock else BLADE_START + BLADE_LENGTH)


func predict_weapon_xf(elapsed: float) -> Transform3D:
	if _prediction.is_empty():
		return weapon_spin.global_transform
	var sample := clampf(inverse_lerp(attack_hit_from, attack_hit_to, elapsed), 0.0, 1.0) * PREDICTION_STEPS
	var index := mini(floori(sample), PREDICTION_STEPS - 1)
	return _prediction[index].interpolate_with(_prediction[index + 1], sample - index)


func hit_parts() -> Array:
	var factor := global_basis.get_scale().x
	var parts := [
		_part(body.global_position, torso.to_global(Vector3(0, 0.31, 0)), 0.38 * factor, "pelvis"),
		_part(torso.to_global(Vector3(0, 0.31, 0)), torso.to_global(Vector3(0, 0.78, 0)), 0.52 * factor, "chest"),
		_part(head.to_global(Vector3(0, 0.13, 0)), head.to_global(Vector3(0, 0.40, 0)), 0.235 * factor, "head"),
	]
	for leg in legs:
		var hip: Vector3 = leg["hip"].global_position
		var knee: Vector3 = leg["knee"].global_position
		var ankle: Vector3 = leg["ankle"].global_position
		parts.append(_part(hip, knee, 0.20 * factor, "thigh"))
		parts.append(_part(knee, ankle, 0.18 * factor, "shin"))
		parts.append(_part(ankle, leg["ankle"].to_global(Vector3(0, -0.08, -0.36)), 0.13 * factor, "foot"))
	for arm in arms:
		var shoulder: Vector3 = arm["shoulder"].global_position
		var elbow: Vector3 = arm["elbow"].global_position
		var hand: Vector3 = arm["wrist"].global_position
		parts.append(_part(shoulder, elbow, 0.17 * factor, "upper_arm"))
		parts.append(_part(elbow, hand, 0.13 * factor, "forearm"))
	return parts


func _part(from: Vector3, to: Vector3, radius: float, label: String) -> Dictionary:
	return {"a": from, "b": to, "r": radius, "label": label}


func sync_replay_pose() -> void:
	_skeleton.sync()

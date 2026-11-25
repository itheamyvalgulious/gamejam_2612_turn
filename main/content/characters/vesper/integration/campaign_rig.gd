extends "res://scripts/mech/mech_rig.gd"
## Applies the campaign's timings and collision rules to the shared VESPER rig.

const BladePath = preload("res://integration/blade_path.gd")
const CLIPS := {
	"slash_fwd": "FRONT_R",
	"slash_left": "SIDE_THRUST_L",
	"slash_right": "SIDE_THRUST_R",
	"slash_back": "BACK_THRUST",
	"heavy": "HEAVY",
	"spin": "SPIN",
	"plunge": "HEAVY",
}

var arena_bounds := Vector2.ZERO
var follow_platform_height := false
var guard := 0.0
var attack_elapsed := 0.0
var attack_hit_from := 0.0
var attack_hit_to := 0.0
var weapon_xf := Transform3D.IDENTITY
var last_intercept_miss := 0.0
var weapon_prev_xf := Transform3D.IDENTITY
var weapon_scale := 1.0
var blade_discs: Array = []

var _timings: Dictionary = {}
var _attack_total := 0.0
var _lunge_distance := 0.0
var _authored_lunge := 0.0
var _authored_strike := Vector2.ZERO
var _blade_path := BladePath.new()
var _first_person := false


func _ready() -> void:
	super._ready()
	blade_discs = _measure_blade()
	_record_blade()
	weapon_prev_xf = weapon_xf


func advance(dt: float) -> void:
	super.advance(dt)
	_record_blade()


func _record_blade() -> void:
	weapon_prev_xf = weapon_xf
	weapon_xf = weapon_spin.global_transform
	weapon_scale = weapon_xf.basis.get_scale().x


func _constrain_horizontal() -> void:
	if arena_bounds.x > 0.1 and arena_bounds.y > 0.1:
		position.x = clampf(position.x, -arena_bounds.x, arena_bounds.x)
		position.z = clampf(position.z, -arena_bounds.y, arena_bounds.y)


func _advance_jump(dt: float) -> void:
	# Lab rooms support falling off a platform. Galleria and City resolve stairs in the level.
	if follow_platform_height and jump_state == "GROUND":
		if position.y > ground_height + 0.02:
			jump_state = "AIR"
			vertical_velocity = 0.0
			air_time = 0.0
		elif position.y < ground_height:
			position.y = ground_height
	super._advance_jump(dt)


func set_timings(timings: Dictionary) -> void:
	_timings = timings


func play_action(action: String, lunge: float) -> void:
	clear_blade_path()
	_attack_queue.clear()
	var clip := _clip(CLIPS[action])
	var timing: Dictionary = _timings.get("heavy" if action == "plunge" else action, {})
	var trail: Array = clip["trail"]
	var duration: float = clip["duration"]
	_authored_strike = Vector2(float(trail[0]), float(trail[1]))
	attack_hit_from = float(timing.get("windup", _authored_strike.x / ATTACK_RATE))
	attack_hit_to = attack_hit_from + maxf(0.02, float(timing.get("active", (_authored_strike.y - _authored_strike.x) / ATTACK_RATE)))
	_attack_total = maxf(attack_hit_to + 0.01, float(timing.get("duration", duration / ATTACK_RATE)))
	attack_elapsed = 0.0
	_lunge_distance = lunge
	_authored_lunge = _eval_curve(clip.get("lunge", []), duration)
	_begin_attack(clip, action in ["heavy", "spin", "plunge"])


func _advance_attack(dt: float) -> void:
	if not is_attacking:
		return
	attack_elapsed = minf(attack_elapsed + dt, _attack_total)
	attack_time = _clip_time(attack_elapsed)
	if attack_elapsed >= _attack_total:
		# Apply the last increment so a completion frame cannot drop root motion.
		position += -global_basis.z.normalized() * (_lunge_at(attack_time) - _lunge_prev)
		_finish_attack()


func _clip_time(elapsed: float) -> float:
	if elapsed < attack_hit_from:
		return lerpf(0.0, _authored_strike.x, elapsed / maxf(attack_hit_from, 0.001))
	if elapsed < attack_hit_to:
		var progress := inverse_lerp(attack_hit_from, attack_hit_to, elapsed)
		return lerpf(_authored_strike.x, _authored_strike.y, progress)
	var recovery := clampf(inverse_lerp(attack_hit_to, _attack_total, elapsed), 0.0, 1.0)
	return lerpf(_authored_strike.y, float(_attack["duration"]), recovery)


func _lunge_at(t: float) -> float:
	if absf(_authored_lunge) > 0.001:
		return super._lunge_at(t) * _lunge_distance / absf(_authored_lunge)
	if t <= _authored_strike.x:
		return 0.0
	return smoothstep(_authored_strike.x, _authored_strike.y, t) * _lunge_distance


func in_hit_window() -> bool:
	return is_attacking and attack_elapsed >= attack_hit_from and attack_elapsed <= attack_hit_to


func blade_span() -> Vector2:
	return Vector2(BLADE_Y0, BLADE_Y0 + BLADE_LEN)


func combat_capsule() -> Dictionary:
	# These dimensions are in level units. The model's metre conversion must not rescale them.
	return {
		"a": global_position + Vector3.UP,
		"b": global_position + Vector3.UP * 4.4,
		"r": 1.1,
		"scale": 1.0,
	}


func plan_blade_intercept(point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float, deadline: float, speed := 26.0) -> Dictionary:
	var res := _solve_intercept(point, axis, face, torso_turn)
	if res.is_empty():
		return {}
	var hilt: Vector3 = res["hilt"]
	var yaw: float = res["yaw"]
	var travel: float = weapon_root.position.distance_to(hilt) * float(res["torso_scale"])
	var duration := clampf(travel / maxf(speed, 1.0), 0.03, maxf(deadline, 0.03))
	last_intercept_miss = res["miss"]
	_blade_path.plan(weapon_root.position, weapon_root.basis, hilt, res["basis"], duration,
		torso.rotation.y, yaw)
	return {"hilt": hilt, "yaw": yaw, "t": res["t"], "dur": duration, "travel": travel,
		"miss": res["miss"]}


## 落点可达性探针：返回「按这套落点+刀轴规划后，刀身到落点的剩余距离」。
## > 0 说明点在机械臂可达域外，调用方应把落点往身体里收再重试。
func blade_reach_miss(point: Vector3, axis: Vector3, face: Vector3, torso_turn: float) -> float:
	var res := _solve_intercept(point, axis, face, torso_turn)
	if res.is_empty():
		return 1e9
	return float(res["miss"])


## 纯几何求解：挑刀轴正/反两种握法里「刀身最贴近落点」的一种。
## 返回 hilt(躯干局部) / basis(weapon_root 局部基) / yaw / t / miss / torso_scale。
func _solve_intercept(point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float) -> Dictionary:
	if axis.length_squared() < 0.000001:
		return {}
	var from_body := body.to_local(point)
	var yaw := clampf(atan2(-from_body.x, -from_body.z) * clampf(torso_turn, 0.0, 1.0), -2.8, 2.8)
	var target_torso := _torso_transform(Vector3(torso.rotation.x, yaw, torso.rotation.z))
	var to_torso := target_torso.affine_inverse()
	var point_local := to_torso * point
	var up := (to_torso.basis * axis).normalized()
	var rest := Vector3(BASE_POSE["wpx"], BASE_POSE["wpy"], BASE_POSE["wpz"])
	var hilt_scale := weapon_root.scale.y
	var span := blade_span() * hilt_scale
	var best_score := INF
	var hilt := rest
	var root_basis := weapon_root.basis.orthonormalized()
	var blade_point := 0.0
	var best_miss := 1e9
	for side in [1.0, -1.0]:
		var blade_axis: Vector3 = up * side
		var normal := (to_torso.basis * face).slide(blade_axis)
		if normal.length_squared() < 0.0001:
			normal = Vector3.UP.cross(blade_axis)
		if normal.length_squared() < 0.0001:
			normal = Vector3.RIGHT
		normal = normal.normalized()
		var blade_basis := Basis(blade_axis.cross(normal).normalized(), blade_axis, normal)
		var basis := blade_basis * weapon_spin.basis.inverse()
		var along := clampf((point_local - rest).dot(blade_axis), span.x, span.y)
		var candidate := _reachable_hilt(point_local - blade_axis * along, blade_axis)
		var miss := (candidate + blade_axis * along).distance_to(point_local)
		var score := miss * 3.0 + candidate.distance_to(rest) + 0.45 * candidate.distance_to(weapon_root.position)
		if score < best_score:
			best_score = score
			hilt = candidate
			root_basis = basis
			blade_point = along / hilt_scale
	var travel := weapon_root.position.distance_to(hilt) * target_torso.basis.get_scale().x
	var duration := clampf(travel / maxf(speed, 1.0), 0.03, maxf(deadline, 0.03))
	_blade_path.plan(weapon_root.position, weapon_root.basis, hilt, root_basis, duration,
		torso.rotation.y, yaw)
	return {"hilt": hilt, "yaw": yaw, "t": blade_point, "dur": duration, "travel": travel}


func _reachable_hilt(hilt: Vector3, axis: Vector3) -> Vector3:
	hilt.z = minf(hilt.z, -0.30)
	for pass_index in 3:
		for index in arms.size():
			var arm: Dictionary = arms[index]
			var shoulder: Vector3 = arm["shoulder"].position
			var grip := axis * GRIP * (1.0 if index == 1 else -1.0)
			var limit: float = float(arm["upper"]) + float(arm["fore"]) - 0.026
			hilt = shoulder + (hilt + grip - shoulder).limit_length(limit) - grip
	return hilt


func _torso_transform(angles: Vector3) -> Transform3D:
	var basis := Basis.from_euler(angles).scaled(torso.scale)
	return body.global_transform * Transform3D(basis, torso.position)


func plan_blade_return(duration: float) -> void:
	var rest := Vector3(BASE_POSE["wpx"], BASE_POSE["wpy"], BASE_POSE["wpz"])
	var basis := Basis.from_euler(Vector3(BASE_POSE["wrx"], BASE_POSE["wry"], BASE_POSE["wrz"]))
	_blade_path.plan(weapon_root.position, weapon_root.basis, rest, basis, duration, torso.rotation.y, 0.0)


func clear_blade_path() -> void:
	_blade_path.cancel()


func blade_path_active() -> bool:
	return _blade_path.active


func _current_pose(dt: float) -> Dictionary:
	var pose := super._current_pose(dt)
	if is_attacking or not (_blade_path.active or guard > 0.0):
		return pose
	pose = pose.duplicate()
	if _blade_path.active:
		var step := _blade_path.sample(dt)
		var hilt: Vector3 = step["pos"]
		var basis: Basis = step["basis"]
		var angles := basis.get_euler()
		pose.merge({
			"wpx": hilt.x, "wpy": hilt.y, "wpz": hilt.z, "ty": float(step["yaw"]),
			"wrx": angles.x, "wry": angles.y, "wrz": angles.z,
		}, true)
	else:
		pose["wpy"] = lerpf(float(pose["wpy"]), 0.36, guard)
		pose["wrx"] = lerpf(float(pose["wrx"]), -0.37, guard)
	return pose


func set_first_person_view(on: bool) -> void:
	if _first_person == on:
		return
	_first_person = on
	set_body_hidden(on)


func reset_demo(pos: Vector3, new_heading: float) -> void:
	clear_blade_path()
	guard = 0.0
	attack_elapsed = 0.0
	super.reset_demo(pos, new_heading)
	if _first_person:
		set_body_hidden(true)
	_record_blade()
	weapon_prev_xf = weapon_xf


func foot_points_xz() -> Array:
	var points: Array = []
	for leg in legs:
		var ankle: Vector3 = leg["ankle"].global_position
		points.append(Vector2(ankle.x, ankle.z))
	return points


func replay_nodes() -> Array:
	var nodes: Array = [self, body, torso, head, weapon_root, weapon_spin]
	for leg in legs:
		nodes.append_array([leg["hip"], leg["knee"], leg["ankle"]])
	for arm in arms:
		nodes.append_array([arm["shoulder"], arm["elbow"], arm["wrist"]])
	return nodes


func _measure_blade(buckets := 30) -> Array:
	var points := PackedVector3Array()
	var lo := INF
	var hi := -INF
	for child in weapon_spin.get_children():
		if child is not MeshInstance3D or child.name in [&"BladeGlow1", &"BladeAura"]:
			continue
		var part := child as MeshInstance3D
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = part.transform * vertex
				points.append(point)
				lo = minf(lo, point.y)
				hi = maxf(hi, point.y)
	if points.is_empty() or is_equal_approx(lo, hi):
		return []
	var radii := PackedFloat32Array()
	radii.resize(buckets)
	var width := (hi - lo) / float(buckets)
	for point in points:
		var index := clampi(int((point.y - lo) / width), 0, buckets - 1)
		radii[index] = maxf(radii[index], Vector2(point.x, point.z).length())
	var discs: Array = []
	for index in buckets:
		if radii[index] > 0.002:
			discs.append({"y": lo + (float(index) + 0.5) * width, "r": radii[index]})
	return discs

extends RefCounted
## The first strike. Times are measured from the first frame of the red flash.

const Rig = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const Brace = preload("res://src/enemies/duelist/duelist_ground_brace.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const SkeletonLayout = preload("res://src/enemies/duelist/duelist_rig.gd")

const PALM_RELEASE := 0.054
const BURST_START := 0.064
const BURST_END := 0.168
const THRUST_END := BURST_START + 0.030
const BRAKE_START := BURST_START + 0.080
const THRUST_SPEED := 11.8
const BRAKE_SPEED := 6.0
const HIP_TURN_START := 0.091
const CHEST_TURN_START := 0.118
const SWEEP_START := 0.147
const FRONT_LAND := 0.170
const TRAIL_START := 0.186
const CUT_END := 0.398
const DURATION := 0.448
const MAX_TRAVEL := 40.80
const TARGET_CLEARANCE := 4.80  # Room for the torso and sweep in first person.
const REAR_LAND := 0.307
const TRACK_TURN_SPEED := 8.0   # Radians per clip second.
const TRACK_LEAD_TIME := 0.09
const MAX_TRACK_LEAD := 2.75


static func begin(model, target: Vector3, cover: Array = []) -> Dictionary:
	var feet: Array[Transform3D] = []
	var knees: Array[Vector3] = []
	for leg: Dictionary in model.legs:
		var foot := leg["ankle"] as Node3D
		feet.append(model.global_transform * foot.transform)
		knees.append(_pole(leg["hip"], leg["knee"], foot))

	var support: Dictionary = model.arms[0]
	var sword_angles: Vector2 = model.sword_arm_angles(7.0)
	return begin_path(model.position, model.rotation.y, model.scale.x, target, cover).merged({
		"hip": model.body.transform, "chest": model.torso.basis, "feet": feet, "knees": knees,
		"push_contact": feet[1] * _toe_contact(0.0),
		"support": model.global_transform * support["wrist"].transform,
		"support_pole": _pole(support["shoulder"], support["elbow"], support["wrist"]),
		"blade": (model.body.basis * model.torso.basis).inverse() * model.weapon_root.basis,
		"sword_angles": sword_angles,
	})


static func begin_path(origin: Vector3, yaw: float, scale: float, target: Vector3, cover: Array) -> Dictionary:
	var direction := (target - origin).slide(Vector3.UP)
	var distance := direction.length()
	direction = direction / distance if distance > 0.001 else -Basis(Vector3.UP, yaw).z
	var aim := atan2(-direction.x, -direction.z)
	var reach := clampf(distance - TARGET_CLEARANCE, 0.0, MAX_TRAVEL)
	var body_radius := 1.1 * scale
	var travel := _clear_distance(origin, direction, reach, cover, body_radius)
	return {
		"origin": origin, "end": origin + direction * travel, "direction": direction,
		"cover": cover, "body_radius": body_radius,
		"yaw": yaw, "aim": aim, "watch": target,
	}


static func _clear_distance(origin: Vector3, direction: Vector3, travel: float, cover: Array, body_radius: float) -> float:
	for obstacle: Dictionary in cover:
		var center: Vector3 = obstacle["c"]
		var offset := (center - origin).slide(Vector3.UP)
		var radius := float(obstacle["r"]) + body_radius
		var along := offset.dot(direction)
		var intercept := radius * radius - offset.slide(direction).length_squared()
		if along > 0.0 and intercept > 0.0 and offset.length_squared() >= radius * radius:
			travel = minf(travel, maxf(0.0, along - sqrt(intercept)))
	return travel


static func track_target(state: Dictionary, target: Vector3, velocity: Vector3,
		position_now: Vector3, before: float, time: float) -> Vector3:
	var origin: Vector3 = state["origin"]
	var to_target := (target - origin).slide(Vector3.UP)
	var aim: float = state["aim"]
	if to_target.length_squared() > 0.001:
		var wanted := atan2(-to_target.x, -to_target.z)
		var turn := TRACK_TURN_SPEED * maxf(0.0, time - maxf(before, 0.0))
		aim = rotate_toward(aim, wanted, turn)
	var direction := Vector3(-sin(aim), 0.0, -cos(aim))
	state["direction"] = direction
	state["aim"] = aim
	state["watch"] = target

	var lead := clampf(velocity.dot(direction) * TRACK_LEAD_TIME, 0.0, MAX_TRACK_LEAD)
	var reach := clampf(to_target.dot(direction) + lead - TARGET_CLEARANCE, 0.0, MAX_TRAVEL)
	var cover: Array = state["cover"]
	var body_radius: float = state["body_radius"]
	var travel := _clear_distance(origin, direction, reach, cover, body_radius)
	var landing := origin + direction * travel
	state["end"] = landing

	# Apply the remaining fraction of the burst from the actual position.
	# This preserves the easing on a straight path without moving past positions.
	var old_progress := burst_at(before)
	var progress := burst_at(time)
	var ratio := clampf(inverse_lerp(old_progress, 1.0, progress), 0.0, 1.0)
	var motion := (landing - position_now) * ratio
	var next := position_now
	if motion.dot(direction) > 0.0:
		var step_direction := motion.normalized()
		var safe := maxf(0.0, (target - position_now).dot(step_direction) - TARGET_CLEARANCE)
		var step := _clear_distance(position_now, step_direction, minf(motion.length(), safe), cover, body_radius)
		next += step_direction * step

	if time >= BURST_END:
		state["end"] = next
	return next


static func burst_at(time: float) -> float:
	if time < THRUST_END:
		return _burst_segment(time, BURST_START, THRUST_END, 0.0, 0.50, 0.0, THRUST_SPEED)
	if time < BRAKE_START:
		return _burst_segment(time, THRUST_END, BRAKE_START, 0.50, 0.90, THRUST_SPEED, BRAKE_SPEED)
	return _burst_segment(time, BRAKE_START, BURST_END, 0.90, 1.0, BRAKE_SPEED, 0.0)


static func _burst_segment(time: float, start: float, end: float, from: float, to: float,
		speed_in: float, speed_out: float) -> float:
	# Matching tangents keeps the change in speed continuous at both joins.
	var third := (end - start) / 3.0
	var progress := clampf(inverse_lerp(start, end, time), 0.0, 1.0)
	return bezier_interpolate(from, from + speed_in * third, to - speed_out * third, to, progress)


static func apply(model, state: Dictionary, time: float, path_position := Vector3.INF) -> void:
	var aim: float = state["aim"]
	var advance := burst_at(time)
	var hip_turn := smoothstep(HIP_TURN_START, 0.336, time)
	var yaw := aim - 0.11 + 0.33 * hip_turn
	model.position = path_position if path_position.is_finite() else (state["origin"] as Vector3).lerp(state["end"], advance)
	model.rotation.y = lerp_angle(state["yaw"], yaw, smoothstep(0.020, 0.142, time))
	var transfer := smoothstep(FRONT_LAND - 0.012, 0.340, time)
	var drive := smoothstep(0.022, 0.163, time)
	var hip_start: Transform3D = state["hip"]
	var body := model.body as Node3D
	var chest := model.torso as Node3D
	body.position = hip_start.origin.lerp(Vector3(0.038, 1.71, 0.14), drive)
	var load_right := smoothstep(0.005, 0.047, time) * (1.0 - smoothstep(BURST_START, BURST_END, time))
	body.position += Vector3(0.22, -0.035, -0.19) * load_right
	body.position += Vector3(-0.14, -0.12, -0.22) * transfer
	body.position.y -= 0.12 * sin(PI * advance)
	body.basis = hip_start.basis.slerp(_angles(-18, -8, -7).slerp(_angles(-13, 15, 8), hip_turn), drive)
	var shoulder_turn := smoothstep(CHEST_TURN_START, 0.377, time)
	chest.basis = (state["chest"] as Basis).slerp(_angles(-8, -13, 7).slerp(_angles(-11, 20, 6), shoulder_turn), drive)
	var toes := _pose_feet(model, state, time)
	Pace.aim_head(model, state["watch"])
	_pose_support(model, state, time)
	_pose_sword(model, state, time)
	var palm_release := smoothstep(PALM_RELEASE, 0.219, time)
	model.finish_pose(lerpf(0.45, 0.24, palm_release), 1.0, toes, lerpf(46.0, 0.0, palm_release))


static func _pose_feet(model, state: Dictionary, time: float) -> Vector2:
	var scale: float = model.scale.x
	var origin: Vector3 = state["origin"]
	var stance := Transform3D(Basis(Vector3.UP, state["aim"]).scaled(Vector3.ONE * scale), origin)
	var displacement: Vector3 = model.position - origin
	var to_local: Transform3D = model.global_transform.affine_inverse()
	var targets: Array[Transform3D] = []
	var toe_angles := Vector2.ZERO
	var ceiling := INF
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var start: Transform3D = state["feet"][i]
		var front := side < 0.0
		# Both feet travel with the burst, then finish their respective landing poses.
		var burst := burst_at(time)
		var progress := 0.07 * smoothstep(PALM_RELEASE, 0.084, time) + 0.69 * burst
		progress += 0.24 * smoothstep(0.102, FRONT_LAND, time)
		if not front:
			progress = 0.78 * burst + 0.22 * smoothstep(BURST_END, REAR_LAND, time)

		var step := Transform3D(_angles(0, 12, 0), Vector3(-0.53, Pace.SOLE_HEIGHT, -1.06))
		var lift := sin(PI * progress) * (0.22 if front else 0.19)
		if front:
			toe_angles[i] = lerpf(Brace.BACK_TOE_ANGLE, 0.0, progress)
		else:
			# Keep the ball of the right foot in place as the heel rises for the push.
			var push := smoothstep(0.026, BURST_START, time)
			var toe := lerpf(0.0, 27.0, push)
			var pivot := start * _toe_contact(0.0)
			start.basis *= Basis(Vector3.RIGHT, deg_to_rad(-35.0 * push))
			start.origin = pivot - start.basis * _toe_contact(toe)
			toe_angles[i] = lerpf(toe, 19.0, progress)
			var pitched := _angles(-27, -17, 0)
			step = Transform3D(pitched, Vector3(0.47, 0, 1.13) - pitched * _toe_contact(19.0))
		var flight := start.interpolate_with(stance * step, progress)
		flight.origin += displacement
		var target := to_local * flight
		target.origin.y += lift
		target = to_local * (model.keep_sole_above_floor(model.global_transform * target) as Transform3D)
		targets.append(target)
		var offset: Vector3 = model.body.basis * Vector3(side * 0.319, -0.028, 0)
		var horizontal: Vector3 = (target.origin - model.body.position - offset).slide(Vector3.UP)
		var reach: float = model.THIGH + model.SHIN - 0.012
		ceiling = minf(ceiling, target.origin.y - offset.y + sqrt(maxf(0.0, reach * reach - horizontal.length_squared())))

	model.body.position.y = minf(model.body.position.y, ceiling)
	var bend := smoothstep(0.027, FRONT_LAND, time)
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var hip: Vector3 = model.body.transform * Vector3(side * 0.319, -0.028, 0)
		var goal := Vector3(side * 0.19, 0.03, -1.0)
		if side > 0.0:
			var planted := smoothstep(0.025, BURST_START, time) * (1.0 - burst_at(time))
			goal.x -= 0.53 * planted
		var pole: Vector3 = (state["knees"][i] as Vector3).lerp(goal, bend)
		Rig.solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, targets[i].origin, pole, model.THIGH, model.SHIN)
		leg["ankle"].basis = targets[i].basis
	return toe_angles


static func _pose_support(model, state: Dictionary, time: float) -> void:
	var arm: Dictionary = model.arms[0]
	var elbow := arm["elbow"] as Node3D
	var wrist := arm["wrist"] as Node3D
	var planted: Transform3D = model.global_transform.affine_inverse() * state["support"]
	var lift := smoothstep(PALM_RELEASE, 0.223, time)
	var draw := smoothstep(0.144, 0.393, time)
	var hand := planted.origin.lerp(Vector3(-1.25, 1.74, -0.61).lerp(Vector3(-1.18, 1.43, 0.40), draw), lift)
	var shoulder: Vector3 = model.shoulder_anchor(arm, hand)
	var pole: Vector3 = (state["support_pole"] as Vector3).lerp(Vector3(-0.82, -0.05, 0.53), lift)
	Rig.solve_chain(arm["shoulder"], elbow, wrist, shoulder, hand, pole, model.UPPER_ARM, model.FOREARM)
	var open_hand := elbow.basis * _angles(-7, -22, 5)
	wrist.basis = planted.basis.slerp(open_hand, lift)


static func _pose_sword(model, state: Dictionary, time: float) -> void:
	# Carry the guard with the chest until the hips and shoulder have led the turn.
	var chest: Basis = model.body.basis * model.torso.basis
	var start: Basis = chest * state["blade"]
	var sweep := smoothstep(SWEEP_START, CUT_END, time)
	var start_yaw := atan2(-start.y.z, start.y.x)
	var local_aim := angle_difference(model.rotation.y, float(state["aim"]))
	var theta := lerp_angle(start_yaw, local_aim + 2.25, sweep)
	var pitch := lerpf(asin(start.y.y), deg_to_rad(8.0), sweep)
	var follow_arc := smoothstep(SWEEP_START, 0.224, time) * (1.0 - smoothstep(0.278, 0.392, time))
	pitch -= deg_to_rad(10.0) * follow_arc
	var shaft := Vector3(cos(theta) * cos(pitch), sin(pitch), -sin(theta) * cos(pitch))
	var start_edge := Vector3.UP.cross(start.y).normalized()
	var start_roll := start_edge.signed_angle_to(-start.x, start.y)
	# Roll the edge toward the rising sweep along the same curve as the blade.
	var edge_turn := 1.0 - pow(1.0 - sweep, 7.2)
	var edge := Vector3.UP.cross(shaft).normalized().rotated(shaft, lerpf(start_roll, deg_to_rad(7.0), edge_turn))
	var weapon := Basis(-edge, shaft, shaft.cross(edge))
	var deviation := lerpf(7.0, 11.0, edge_turn) - 8.0 * sweep
	var angles: Vector2 = state["sword_angles"]
	var flex := lerpf(angles.x, deg_to_rad(96.0), sweep)
	var roll := lerpf(angles.y, deg_to_rad(-71.0), sweep)
	model.pose_sword_arm(weapon, flex, roll, deviation)


static func _toe_contact(angle: float) -> Vector3:
	var hinge := SkeletonLayout.TOE_HINGE
	return hinge + Basis(Vector3.RIGHT, deg_to_rad(angle)) * (Pace.TOE - hinge)


static func _pole(upper: Node3D, joint: Node3D, end: Node3D) -> Vector3:
	return (joint.position - upper.position).slide((end.position - upper.position).normalized()).normalized()


static func _angles(pitch: float, yaw: float, roll: float) -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, roll) * (PI / 180.0))

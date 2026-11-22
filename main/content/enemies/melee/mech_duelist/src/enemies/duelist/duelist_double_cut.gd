extends RefCounted
## The first cut falls across the body. The return rises to the outside and finishes behind the shoulder.

const NormalCut = preload("res://src/enemies/duelist/duelist_normal_cut.gd")
const Alert = preload("res://src/enemies/duelist/duelist_alert_pose.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")

const DISPLAY_NAME := "二连斩"
const WINDUP_END := 0.49
const LEAD_STEP_START := 0.27
const LEAD_LAND := 0.53
const TRAIL_START := 0.62
const HIT_START := 0.65
const HIT_END := 0.87
const SECOND_WINDUP := 0.93
const SECOND_TRAIL_START := 1.035
const SECOND_HIT_START := 1.065
const SECOND_HIT_END := 1.35
const SECOND_FINISH := 1.44
const HOLD_START := 1.59
const HOLD_END := 2.09
const GUARD_BLEND_START := 2.48
const DURATION := 2.64
const STRIKES := [
	Vector4(0.0, TRAIL_START, HIT_START, HIT_END),
	Vector4(SECOND_WINDUP, SECOND_TRAIL_START, SECOND_HIT_START, SECOND_HIT_END),
]
const FOOTFALLS := [Vector3(LEAD_LAND, 1, 0.53)]

# Time, blade yaw/pitch/bank, then elbow bend/forearm roll/wrist deviation/wrist flexion.
# Yaw is continuous through the overhead circle, even when it passes -360 degrees.
const BLADE_KEYS := [
	[0.07, Vector3(-23, 36, -170), Vector4(120, 46, 18, 6)],
	[0.12, Vector3(-15, 24, -179), Vector4(114, 68, 18, 17)],
	[0.24, Vector3(-38, -32, -222), Vector4(98, 68, 18, 22)],
	[0.34, Vector3(-35, -53, -256), Vector4(104, 52, 6, 16)],
	[0.41, Vector3(-52, -44, -252), Vector4(97, 33, 5, 7)],
	[0.49, Vector3(-94, -11, -241), Vector4(104, 1, 16, -3)],
	[0.55, Vector3(-145, 11, -242), Vector4(119, -25, 18, -10)],
	[0.61, Vector3(-201, 5, -252), Vector4(127, -53, 18, -21)],
	[0.68, Vector3(-275, 14, -330), Vector4(125, -68, 18, -22)],
	[0.72, Vector3(-340, 19, -376), Vector4(121, -68, 18, -22)],
	[0.77, Vector3(-402, 12, -421), Vector4(92, -68, 18, -22)],
	[0.83, Vector3(-448, 2, -450), Vector4(55, -67, 18, -18)],
	# Unwind around the forearm through the low turnaround. The wrist stays near neutral.
	[0.89, Vector3(-478, 4, -470), Vector4(39, -44, 18, -13)],
	[0.95, Vector3(-487, 9, -491), Vector4(33, -12, 18, -7)],
	[1.00, Vector3(-475, 8, -498), Vector4(48, 18, 17, -2)],
	[1.04, Vector3(-461, 20, -502), Vector4(55, 42, 18, 3)],
	[1.12, Vector3(-381, 32, -516), Vector4(103, 68, 18, 16)],
	[1.20, Vector3(-313, 21, -588), Vector4(119, 68, 18, 22)],
	[1.30, Vector3(-262, 47, -523), Vector4(29, 68, 18, 10)],
	[SECOND_FINISH, Vector3(-248, 41, -521), Vector4(12, 68, 18, 4)],
	[HOLD_START, Vector3(-244, 45, -513), Vector4(12, 68, 18, 5)],
	[HOLD_END, Vector3(-244, 45, -513), Vector4(12, 68, 18, 5)],
	[2.20, Vector3(-284, 36, -585), Vector4(86, 68, 18, 22)],
	[2.32, Vector3(-349, -16, -630), Vector4(121, 68, 18, 22)],
	[GUARD_BLEND_START, Vector3(-382, 12, -572), Vector4(125, 44, 18, 10)],
]


static func can_start(model: Node3D, focus: Vector3) -> bool:
	return NormalCut.can_start(model, focus)


static func begin(model, focus: Vector3, cover: Array, bounds: AABB) -> Dictionary:
	var state := NormalCut.begin(model, focus)
	place_steps(model, state, focus, cover, bounds)
	return state


static func place_steps(model, state: Dictionary, focus: Vector3, cover: Array, bounds: AABB,
		step_forward := true) -> void:
	var start: Transform3D = model.global_transform
	var size := start.basis.get_scale().x
	var gap := (focus - start.origin).slide(Vector3.UP).length()
	var distance := clampf(gap - 2.55, 0.0, 0.94 * size) if step_forward else 0.0
	var end := start.origin - start.basis.z.normalized() * distance
	for obstacle: Dictionary in cover:
		var radius := maxf(0.35, float(obstacle["r"]) - 1.2) + 1.1 * size
		end = Hit.slide_around_body(start.origin, end, obstacle["c"], radius)
	var shift := start.affine_inverse() * _inside(end, bounds)
	var right := Vector3(shift.x + 0.59, 0.0, shift.z - 0.60)
	var rear := Vector3(shift.x - 0.60, 0.0, shift.z + 0.10)
	state["root"] = start
	state["focus"] = focus
	state["shift"] = shift
	state["lead"] = _foot_at(model, start, right, -8.0, cover, bounds)
	state["rear_finish"] = _foot_at(model, start, rear, 12.0, cover, bounds)


static func apply(model, state: Dictionary, time: float) -> void:
	var root: Transform3D = state["root"]
	var shift: Vector3 = state["shift"]
	var wind := smoothstep(0.02, 0.46, time)
	var cut := smoothstep(0.50, 0.81, time)
	var return_cut := smoothstep(0.96, 1.34, time)
	var settle := smoothstep(1.20, 1.57, time)
	var guard := smoothstep(HOLD_END, DURATION, time)
	var follow := 1.0 - guard
	var drift := shift * (0.69 * smoothstep(LEAD_STEP_START, LEAD_LAND, time) + 0.31 * smoothstep(LEAD_LAND, 0.82, time))
	model.global_position = root * drift

	var hip: Transform3D = state["hip"]
	var body := model.body as Node3D
	var chest := model.torso as Node3D
	var guard_height: float = model.HIP_HEIGHT - Alert.HIP_DROP
	body.position = hip.origin.lerp(Vector3(0.07, guard_height, -0.04), maxf(wind, guard))
	body.position += Vector3(0.12, -0.10, -0.14) * cut * follow
	body.position += Vector3(0.02, -0.17, -0.18) * settle * follow
	var hip_cut := smoothstep(0.47, 0.77, time)
	var hip_return := smoothstep(0.93, 1.30, time)
	var pelvis := Vector3(-7.0 - 5.0 * cut, -7.0 * wind + 26.0 * hip_cut - 30.0 * hip_return, -4.0 * return_cut)
	var torso := Vector3(-5.0 - 12.0 * settle, -12.0 * wind + 37.0 * cut - 45.0 * return_cut, 9.0 * settle)
	var hips_to := Basis.from_euler(pelvis * (PI / 180.0))
	var chest_to := Basis.from_euler(torso * (PI / 180.0))
	body.basis = hip.basis.slerp(hips_to, wind).slerp(Basis(Vector3.RIGHT, Alert.HIP_PITCH), guard)
	chest.basis = (state["chest"] as Basis).slerp(chest_to, wind).slerp(Basis(Vector3.RIGHT, Alert.CHEST_PITCH), guard)

	_pose_legs(model, state, time, drift)
	Pace.aim_head(model, state["focus"])
	_pose_support(model, state, time, guard)
	_pose_sword(model, state, time)
	var toes: Vector2 = state["toes"]
	model.finish_pose(0.29, 1.0, toes * (1.0 - wind), 0.0, 0.075 * wind * follow)


static func _pose_support(model, state: Dictionary, time: float, guard: float) -> void:
	var start: Vector3 = state["support_hand"]
	# Extend the open hand with the lift, then fold it back above the low blade.
	var extend := smoothstep(0.18, 0.49, time)
	var tuck := smoothstep(0.57, 0.79, time)
	var reach := Vector3(-0.72, 0.30, -1.28)
	var chest := Vector3(-0.56, 0.86, -0.75)
	var hand := start.lerp(reach, extend).lerp(chest, tuck)
	hand += Vector3(-0.06, -0.11, -0.25) * smoothstep(1.04, SECOND_FINISH, time)
	NormalCut.pose_support(model, state, hand.lerp(Alert.SUPPORT_HAND, guard) - start)


static func _pose_legs(model, state: Dictionary, time: float, drift: Vector3) -> void:
	var feet: Array[Transform3D] = state["feet"].duplicate()
	var lead: Transform3D = state["lead"]
	var rear_finish: Transform3D = state["rear_finish"]
	var step := clampf(inverse_lerp(LEAD_STEP_START, LEAD_LAND, time), 0.0, 1.0)
	var right := feet[1].interpolate_with(lead, smoothstep(0.0, 1.0, step))
	right.origin.y += 0.24 * sin(PI * step)
	var left := feet[0]
	var heel := smoothstep(0.32, 0.78, time)
	# Raise the rear heel around the planted toe, until the recovery step.
	var toe_contact := left * Pace.TOE
	left.basis = Basis(Vector3.UP, deg_to_rad(16.0) * heel) * left.basis \
		* Basis(Vector3.RIGHT, deg_to_rad(-14.0) * heel)
	left.origin = toe_contact - left.basis * Pace.TOE
	var collect := clampf(inverse_lerp(2.16, 2.59, time), 0.0, 1.0)
	left = left.interpolate_with(rear_finish, smoothstep(0.0, 1.0, collect))
	left.origin.y += 0.16 * sin(PI * collect)
	feet[0] = left.translated(-drift)
	feet[1] = right.translated(-drift)
	var knees: Array[Vector3] = state["knees"].duplicate()
	for i in feet.size():
		var side: float = model.legs[i]["side"]
		var facing := -feet[i].basis.z.slide(Vector3.UP).normalized()
		knees[i] = knees[i].lerp(facing + Vector3(side * 0.19, 0, 0), smoothstep(0.0, 0.25, time))
	NormalCut.pose_legs(model, feet, knees)


static func _pose_sword(model, state: Dictionary, time: float) -> void:
	var pose := _sample_sword(time)
	var blade: Vector3 = pose[0]
	var angles: Vector4 = pose[1]
	var entry := smoothstep(0.0, BLADE_KEYS[0][0], time)
	var start_blade: Basis = state["blade"]
	var start_angles: Vector2 = state["angles"]
	var weapon := start_blade.slerp(_blade_basis(blade), entry)
	var flex := lerpf(start_angles.x, deg_to_rad(angles.x), entry)
	var roll := lerp_angle(start_angles.y, deg_to_rad(angles.y), entry)
	var deviation := lerpf(state["deviation"], angles.z, entry)
	var flexion := lerpf(state["wrist_flexion"], angles.w, entry)
	if time > GUARD_BLEND_START:
		var guard := smoothstep(GUARD_BLEND_START, DURATION, time)
		Alert.pose_weapon(model)
		if guard >= 1.0:
			return
		var wrist: Basis = model.arms[1]["wrist"].basis
		var target: Vector2 = model.sword_arm_angles(Alert.WRIST_DEVIATION)
		weapon = weapon.slerp(wrist * model.Hand.sword_socket().basis, guard)
		flex = lerpf(flex, target.x, guard)
		roll = lerp_angle(roll, target.y, guard)
		deviation = lerpf(deviation, Alert.WRIST_DEVIATION, guard)
		flexion = lerpf(flexion, -14.0, guard)
	model.pose_sword_arm(weapon, flex, roll, deviation, flexion)


static func _sample_sword(time: float, keys := BLADE_KEYS, ease_from := HOLD_START) -> Array:
	for i in range(1, keys.size()):
		var end: Array = keys[i]
		if time <= float(end[0]):
			var start: Array = keys[i - 1]
			var next: Array = keys[mini(i + 1, keys.size() - 1)]
			var previous: Array = keys[maxi(i - 2, 0)]
			var span: float = float(end[0]) - float(start[0])
			var u := clampf((time - float(start[0])) / span, 0.0, 1.0)
			var first: Vector3 = start[1]
			var last: Vector3 = end[1]
			var ease := smoothstep(0.0, 1.0, u)
			var first_joints: Vector4 = start[2]
			var last_joints: Vector4 = end[2]
			if float(start[0]) >= ease_from:
				return [first.lerp(last, ease), first_joints.lerp(last_joints, ease)]
			var before: float = float(previous[0]) - float(start[0])
			var after: float = float(next[0]) - float(start[0])
			var blade := first.cubic_interpolate_in_time(last, previous[1], next[1], u,
				span, before, after)
			# Sustain the roll through adjacent keys without overshooting the wrist limits.
			var joints := first_joints.cubic_interpolate_in_time(last_joints, previous[2], next[2], u,
				span, before, after).clamp(first_joints.min(last_joints), first_joints.max(last_joints))
			return [blade, joints]
	return [keys.back()[1], keys.back()[2]]


static func _blade_basis(angles: Vector3) -> Basis:
	var yaw := deg_to_rad(angles.x)
	var pitch := deg_to_rad(angles.y)
	var shaft := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var edge := Vector3.UP.cross(shaft).normalized().rotated(shaft, deg_to_rad(angles.z))
	return Basis(-edge, shaft, shaft.cross(edge))


static func _foot_at(model, root: Transform3D, local: Vector3, yaw: float, cover: Array, bounds: AABB) -> Transform3D:
	var point := root * local
	var scale := root.basis.get_scale().x
	point = _inside(Hit.resolve_circles(point, 0.23 * scale, cover, point.y), bounds)
	point.y = model.floor_height(point) + Pace.SOLE_HEIGHT * scale
	var basis := root.basis * Basis(Vector3.UP, deg_to_rad(yaw))
	var foot: Transform3D = model.keep_sole_above_floor(Transform3D(basis, point))
	return root.affine_inverse() * foot


static func _inside(point: Vector3, bounds: AABB) -> Vector3:
	if bounds.size.length_squared() <= 0.1:
		return point
	return Vector3(clampf(point.x, bounds.position.x + 3.0, bounds.end.x - 3.0), point.y,
		clampf(point.z, bounds.position.z + 3.0, bounds.end.z - 3.0))

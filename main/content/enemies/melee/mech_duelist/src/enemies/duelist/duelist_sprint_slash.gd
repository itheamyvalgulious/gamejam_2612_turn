extends RefCounted
## Continue the double cut into two forward steps and a descending third cut.

const DoubleCut = preload("res://src/enemies/duelist/duelist_double_cut.gd")
const NormalCut = preload("res://src/enemies/duelist/duelist_normal_cut.gd")
const Alert = preload("res://src/enemies/duelist/duelist_alert_pose.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Units = preload("res://src/core/units.gd")

const DISPLAY_NAME := "冲刺斩"
const WINDUP_END := DoubleCut.WINDUP_END
const RUN_START := DoubleCut.HOLD_START
const LEFT_STEP := 1.64
const LEFT_LAND := 2.04
const RIGHT_LAND := 2.50
const THIRD_TRAIL_START := 2.42
const THIRD_HIT_START := 2.47
const THIRD_HIT_END := 2.69
const GUARD_BLEND_START := 2.99
const DURATION := 3.34
const PRESS_START_RANGE := 5.5 / Units.M_PER_UNIT
const FIRST_CUT_RANGE := 3.55 / Units.M_PER_UNIT
const RETREAT_PREP_RANGE := 4.5 / Units.M_PER_UNIT
const WINDUP_APPROACH_RANGE := 1.75 / Units.M_PER_UNIT
const READY_CLIP := DoubleCut.LEAD_STEP_START
const FLASH_READY_CLIP := 0.52
const MIN_FLASH_DISTANCE := 0.25 / Units.M_PER_UNIT
const MIN_FACING := 0.88
const STANDOFF := 3.30
const RUN_REACH := 3.15

# Strike preparation, blade ribbon, first and last hit samples.
const STRIKES := [
	DoubleCut.STRIKES[0], DoubleCut.STRIKES[1],
	Vector4(RUN_START, THIRD_TRAIL_START, THIRD_HIT_START, THIRD_HIT_END),
]
const FOOTFALLS := [
	DoubleCut.FOOTFALLS[0], Vector3(LEFT_LAND, 0, 0.62), Vector3(RIGHT_LAND, 1, 0.69),
]

# Blade yaw/pitch/bank, then elbow bend/forearm roll/wrist deviation/wrist flexion.
const BLADE_KEYS := [
	[1.76, Vector3(92, 20, -192), Vector4(53, 70, 15, 24)],
	[1.88, Vector3(19, -25, -262), Vector4(122, 68, -7, 24)],
	[2.02, Vector3(-22, -48, -281), Vector4(111, 49, -9, 4)],
	[2.17, Vector3(-37, -45, -290), Vector4(104, 43, -16, 1)],
	[2.30, Vector3(-70, -26, -263), Vector4(108, 16, 1, 2)],
	[2.39, Vector3(-141, 5, -259), Vector4(124, -20, 19, -4)],
	[2.48, Vector3(-230, 19, -324), Vector4(118, -68, 19, -18)],
	[2.55, Vector3(-342, 2, -412), Vector4(103, -68, 19, -18)],
	[2.62, Vector3(-390, -13, -396), Vector4(89, -68, 19, -22)],
	[2.71, Vector3(-406, -19, -401), Vector4(70, -68, 19, -22)],
	[2.87, Vector3(-405, -15, -399), Vector4(75, -68, 19, -22)],
	[GUARD_BLEND_START, Vector3(-387, 22, -414), Vector4(128, -68, 19, -3)],
]


static func can_start(model: Node3D, focus: Vector3, reach: float) -> bool:
	var offset := (focus - model.global_position).slide(Vector3.UP)
	return offset.length_squared() <= reach * reach \
		and -model.global_basis.z.normalized().dot(offset.normalized()) >= MIN_FACING


static func begin_ready(model, focus: Vector3, cover: Array, bounds: AABB) -> Dictionary:
	var state := DoubleCut.begin(model, focus, cover, bounds)
	var feet: Array[Transform3D] = state["feet"]
	var right := feet[1]
	state["ready_from"] = right
	state["ready_to"] = DoubleCut._foot_at(model, state["root"], right.origin,
		rad_to_deg(right.basis.get_euler().y), cover, bounds)
	return state


static func apply_ready(model, state: Dictionary, progress: float) -> void:
	var feet: Array[Transform3D] = state["feet"]
	var from: Transform3D = state["ready_from"]
	feet[1] = from.interpolate_with(state["ready_to"], smoothstep(0.0, 0.55, progress))
	DoubleCut.apply(model, state, READY_CLIP * smoothstep(0.0, 1.0, progress))


static func prepare_run(model, state: Dictionary, focus: Vector3, cover: Array, bounds: AABB) -> void:
	DoubleCut.apply(model, state, RUN_START)
	var run := NormalCut.begin(model, focus)
	var root: Transform3D = model.global_transform
	var size := root.basis.get_scale().x
	var forward := -root.basis.z.normalized()
	var gap := (focus - root.origin).dot(forward)
	var dest := root.origin + forward * clampf(gap - STANDOFF, 0.0, RUN_REACH * size)
	for obstacle: Dictionary in cover:
		var radius := maxf(0.35, float(obstacle["r"]) - 1.2) + 1.1 * size
		dest = Hit.slide_around_body(root.origin, dest, obstacle["c"], radius)
	var shift := root.affine_inverse() * DoubleCut._inside(dest, bounds)
	run["root"] = root
	run["shift"] = shift
	run["left_step"] = DoubleCut._foot_at(model, root, shift * 0.51 + Vector3(-0.51, 0.0, -0.88), 9.0, cover, bounds)
	run["right_step"] = DoubleCut._foot_at(model, root, shift + Vector3(0.58, 0.0, -0.65), -10.0, cover, bounds)
	run["left_guard"] = DoubleCut._foot_at(model, root, shift + Vector3(-0.57, 0.0, 0.21), 12.0, cover, bounds)
	state["run"] = run


static func apply(model, state: Dictionary, time: float) -> void:
	if time < RUN_START:
		DoubleCut.apply(model, state, time)
		return
	var run: Dictionary = state["run"]
	var root: Transform3D = run["root"]
	var shift: Vector3 = run["shift"]
	var drive := smoothstep(LEFT_STEP, RIGHT_LAND + 0.03, time)
	var drift := shift * drive
	model.global_position = root * drift

	var hip: Transform3D = run["hip"]
	var body := model.body as Node3D
	var chest := model.torso as Node3D
	var lift := smoothstep(RUN_START, 1.98, time)
	var cut := smoothstep(2.39, 2.66, time)
	var guard := smoothstep(2.82, DURATION, time)
	var stance := Vector3(0.05, model.HIP_HEIGHT - 0.17, -0.27)
	var guarded := Vector3(0.07, model.HIP_HEIGHT - Alert.HIP_DROP, -0.04)
	body.position = (hip.origin.lerp(stance, lift) + Vector3(0.06, -0.29, -0.12) * cut).lerp(guarded, guard)
	var hip_angles := Vector3(-13.0, -10.0 + 27.0 * cut, -4.0 * cut)
	var chest_angles := Vector3(-11.0, -13.0 + 44.0 * cut, 8.0 * cut)
	body.basis = hip.basis.slerp(Basis.from_euler(hip_angles * (PI / 180.0)), lift)
	body.basis = body.basis.slerp(Basis(Vector3.RIGHT, Alert.HIP_PITCH), guard)
	chest.basis = (run["chest"] as Basis).slerp(Basis.from_euler(chest_angles * (PI / 180.0)), lift)
	chest.basis = chest.basis.slerp(Basis(Vector3.RIGHT, Alert.CHEST_PITCH), guard)

	_pose_legs(model, run, time, drift)
	Pace.aim_head(model, (state["focus"] as Vector3).lerp(run["focus"], lift))
	var hand: Vector3 = run["support_hand"]
	var up := smoothstep(1.63, 2.03, time)
	var close := smoothstep(2.40, 2.65, time)
	var support := hand.lerp(Vector3(-0.96, 1.11, -0.52), up)
	support = support.lerp(Vector3(-0.56, 1.06, -0.68), close).lerp(Alert.SUPPORT_HAND, guard)
	NormalCut.pose_support(model, run, support - hand)
	_pose_sword(model, run, time)
	model.finish_pose(0.18, 1.0, Vector2.ZERO, 0.0, 0.075 * (1.0 - guard))


static func _pose_legs(model, run: Dictionary, time: float, drift: Vector3) -> void:
	var planted: Array[Transform3D] = run["feet"]
	var left := _step(planted[0], run["left_step"], LEFT_STEP, LEFT_LAND, time, 0.31)
	var right := _step(planted[1], run["right_step"], LEFT_LAND, RIGHT_LAND, time, 0.43)
	var heel := smoothstep(2.13, RIGHT_LAND, time)
	var contact := left * Pace.TOE
	left.basis *= Basis(Vector3.RIGHT, deg_to_rad(-13.0) * heel)
	left.origin = contact - left.basis * Pace.TOE
	left = _step(left, run["left_guard"], 2.91, 3.24, time, 0.19)
	var feet: Array[Transform3D] = [left.translated(-drift), right.translated(-drift)]
	var knees: Array[Vector3] = run["knees"].duplicate()
	var blend := smoothstep(RUN_START, LEFT_LAND, time)
	for i in feet.size():
		var direction := -feet[i].basis.z.slide(Vector3.UP).normalized()
		var side: float = model.legs[i]["side"]
		knees[i] = knees[i].lerp(direction + Vector3(side * 0.19, 0, 0), blend)
	NormalCut.pose_legs(model, feet, knees)


static func _step(from: Transform3D, to: Transform3D, start: float, end: float, time: float, lift: float) -> Transform3D:
	var phase := clampf(inverse_lerp(start, end, time), 0.0, 1.0)
	var foot := from.interpolate_with(to, smoothstep(0.0, 1.0, phase))
	foot.origin.y += lift * sin(PI * phase)
	return foot


static func _pose_sword(model, run: Dictionary, time: float) -> void:
	var sample := DoubleCut._sample_sword(time, BLADE_KEYS, 2.71)
	var angles: Vector4 = sample[1]
	var entry := smoothstep(RUN_START, BLADE_KEYS[0][0], time)
	var start_blade: Basis = run["blade"]
	var start_angles: Vector2 = run["angles"]
	var weapon := start_blade.slerp(DoubleCut._blade_basis(sample[0]), entry)
	var flex := lerpf(start_angles.x, deg_to_rad(angles.x), entry)
	var roll := lerp_angle(start_angles.y, deg_to_rad(angles.y), entry)
	var deviation := lerpf(run["deviation"], angles.z, entry)
	var flexion := lerpf(run["wrist_flexion"], angles.w, entry)
	if time >= GUARD_BLEND_START:
		var guard := smoothstep(GUARD_BLEND_START, DURATION, time)
		Alert.pose_weapon(model)
		if guard >= 1.0:
			return
		var wrist: Basis = model.arms[1]["wrist"].basis
		var guard_angles: Vector2 = model.sword_arm_angles(Alert.WRIST_DEVIATION)
		weapon = weapon.slerp(wrist * model.Hand.sword_socket().basis, guard)
		flex = lerpf(flex, guard_angles.x, guard)
		roll = lerp_angle(roll, guard_angles.y, guard)
		deviation = lerpf(deviation, Alert.WRIST_DEVIATION, guard)
		flexion = lerpf(flexion, -14.0, guard)
	model.pose_sword_arm(weapon, flex, roll, deviation, flexion)

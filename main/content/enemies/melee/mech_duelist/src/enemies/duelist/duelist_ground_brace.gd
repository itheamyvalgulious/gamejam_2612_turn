extends RefCounted
## 低位撑地：落脚换重心，髋部下沉，右手把刀在身侧展开，左掌最后承重。

const IK = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const SkeletonLayout = preload("res://src/enemies/duelist/duelist_rig.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Charge = preload("res://src/enemies/duelist/duelist_charge.gd")
const TOE_CONTACT := Vector3(0, -0.174, -0.386)
const BACK_TOE_ANGLE := 36.0
const BACK_FOOT := Vector3(-0.54, 0, 2.02)
const BACK_FOOT_FINAL := Vector3(deg_to_rad(-49.0), deg_to_rad(16.0), 0)
const SUPPORT_HAND := Vector3(-0.93, 0.038, -1.11)
const CONTACT_TIME := 1.54
const RISE_TIME := CONTACT_TIME + Charge.DURATION + Charge.FLASH_DURATION + 0.08
const STAND_TIME := RISE_TIME + 1.47
const DURATION := STAND_TIME + 0.25
const HOLD_TIME := CONTACT_TIME + Charge.DURATION * 0.85


static func depth_at(elapsed: float) -> float:
	var time := fposmod(elapsed, DURATION)
	return smoothstep(0.28, CONTACT_TIME, time) * (1.0 - smoothstep(RISE_TIME, STAND_TIME, time))


static func apply(model, depth: float, from_pace := false, watch := Vector3.INF, load_amount := 0.0) -> void:
	if not from_pace:
		# The gallery uses the same entry pose on its stationary pedestal.
		var stage: Transform3D = model.transform
		Pace.apply(model, Pace.DURATION)
		model.transform = stage
	var t := clampf(depth, 0.0, 1.0)
	if t == 0.0:
		return

	var compression := smoothstep(0.14, 1.0, t)
	var blend := smoothstep(0.02, 0.54, t)
	var transfer := smoothstep(0.21, 0.48, t) * (1.0 - smoothstep(0.62, 1.0, t))
	var body := model.body as Node3D
	var torso := model.torso as Node3D
	body.position = body.position.lerp(Vector3(0.04, 2.47, -0.025).lerp(Vector3(0.08, 1.045, 0.11), compression), blend)
	body.position.x += 0.14 * transfer
	body.position.y -= 0.062 * load_amount * compression
	_rotate_toward(body, Vector3(2, 8, 0).lerp(Vector3(-13, -18, -9), compression), blend)
	_rotate_toward(torso, Vector3(0, -3, 0).lerp(Vector3(-49, 12, 38), compression), blend)
	if watch.is_finite():
		Pace.aim_head(model, watch)
	else:
		var gaze := Basis.from_euler(Vector3(-0.22, 0.35, -0.22))
		var neck := (body.basis * torso.basis).inverse() * gaze
		var head := model.head as Node3D
		head.quaternion = head.quaternion.slerp(neck.get_rotation_quaternion(), compression)

	_pose_feet(model, body, t, compression, blend)
	var palm_turn := smoothstep(0.44, 0.96, t)
	for arm: Dictionary in model.arms:
		if arm["side"] > 0.0:
			_pose_sword_arm(model, t)
		else:
			_pose_support_arm(model, arm, t, palm_turn)
	model.finish_pose(lerpf(0.29, 0.45, palm_turn), 1.0,
		Vector2(BACK_TOE_ANGLE * compression, 0.0), 46.0 * palm_turn)


static func _pose_feet(model, body: Node3D, t: float, compression: float, blend: float) -> void:
	var targets: Array[Transform3D] = []
	var bends: Array[Vector3] = []
	var max_height := INF
	for leg: Dictionary in model.legs:
		var side: float = leg["side"]
		var foot := leg["ankle"] as Node3D
		var bend_start := _joint_pole(leg["hip"], leg["knee"], foot)
		var target := foot.transform
		var bend: Vector3
		if side > 0.0:
			var step := smoothstep(0.02, 0.31, t)
			target.origin = foot.position.lerp(Vector3(0.44, 0.175, -1.09), step)
			target.origin.y += sin(PI * step) * 0.11
			target.basis = Basis(Vector3.UP, lerp_angle(foot.rotation.y, deg_to_rad(-27.0), step))
			bend = Vector3(0.16, 0, -1).lerp(Vector3(0.27, 0.44, -0.91), compression)
		else:
			var step := smoothstep(0.32, 0.66, t)
			var pitched := Basis.from_euler(Vector3(deg_to_rad(-49.0 * compression), deg_to_rad(lerpf(7, 16, step)), 0))
			target.basis = foot.basis.slerp(pitched, blend)
			var planted := BACK_FOOT + Basis.from_euler(BACK_FOOT_FINAL) * _toe_offset(1.0)
			planted.y = 0.0
			target.origin = (foot.transform * TOE_CONTACT).lerp(planted, step) - target.basis * _toe_offset(compression)
			target.origin.y += sin(PI * step) * 0.115
			bend = Vector3(-0.14, 0, -1).lerp(Vector3(-0.23, -1, -0.02), compression)
		targets.append(target)
		bends.append(bend_start.lerp(bend, blend))

		# Keep the hip within reach of both prescribed foot contacts.
		var offset := body.basis * Vector3(side * 0.319, -0.028, 0)
		var delta := target.origin - body.position - offset
		var reach: float = model.THIGH + model.SHIN - 0.004
		var ceiling := target.origin.y - offset.y + sqrt(maxf(0.0, reach * reach - delta.x * delta.x - delta.z * delta.z))
		max_height = minf(max_height, ceiling)

	var margin := maxf(0.0, 0.02 - absf(body.position.y - max_height)) / 0.02
	body.position.y = minf(body.position.y, max_height) - 0.005 * margin * margin
	for i in model.legs.size():
		var leg: Dictionary = model.legs[i]
		var side: float = leg["side"]
		var hip := body.transform * Vector3(side * 0.319, -0.028, 0)
		IK.solve_chain(leg["hip"], leg["knee"], leg["ankle"], hip, targets[i].origin,
			bends[i], model.THIGH, model.SHIN)
		leg["ankle"].basis = targets[i].basis


static func _pose_sword_arm(model, t: float) -> void:
	var settle := smoothstep(0.22, 0.94, t)
	var start: Vector2 = model.sword_arm_angles(Pace.SWORD_DEVIATION)
	# Hold the blade near horizontal beside the crouch, with the edge angled
	# down. Rotate it into the cut only after the launch starts.
	var shaft := Vector3(0.60, 0.025, -0.80).normalized()
	var edge := Vector3.UP.cross(shaft).normalized().rotated(shaft, deg_to_rad(-108.0))
	var guard := Basis(-edge, shaft, shaft.cross(edge))
	var blade := (model.weapon_root.basis as Basis).slerp(guard, settle)
	var flex := lerpf(start.x, deg_to_rad(82.0), settle)
	var roll := lerpf(start.y, deg_to_rad(-72.0), settle)
	model.pose_sword_arm(blade, flex, roll, lerpf(Pace.SWORD_DEVIATION, 7.0, settle))


static func _pose_support_arm(model, arm: Dictionary, t: float, palm_turn: float) -> void:
	var wrist := arm["wrist"] as Node3D
	var wrist_start := wrist.basis
	var reach := smoothstep(0.23, 0.96, t)
	var hand := wrist.position.lerp(SUPPORT_HAND, reach)
	var pole := _joint_pole(arm["shoulder"], arm["elbow"], wrist).lerp(Vector3(-0.78, 0.30, 0.35), reach)
	var shoulder: Vector3 = model.shoulder_anchor(arm, hand)
	IK.solve_chain(arm["shoulder"], arm["elbow"], wrist, shoulder, hand, pole, model.UPPER_ARM, model.FOREARM)
	wrist.basis = wrist_start
	_rotate_toward(wrist, Vector3(90, 9, 0), palm_turn)


static func _rotate_toward(node: Node3D, degrees: Vector3, weight: float) -> void:
	node.basis = node.basis.slerp(Basis.from_euler(degrees * (PI / 180.0)), weight)


static func _toe_offset(compression: float) -> Vector3:
	var hinge := SkeletonLayout.TOE_HINGE
	return hinge + Basis(Vector3.RIGHT, deg_to_rad(BACK_TOE_ANGLE * compression)) * (TOE_CONTACT - hinge)


static func _joint_pole(upper: Node3D, joint: Node3D, end: Node3D) -> Vector3:
	return (joint.position - upper.position).slide((end.position - upper.position).normalized()).normalized()

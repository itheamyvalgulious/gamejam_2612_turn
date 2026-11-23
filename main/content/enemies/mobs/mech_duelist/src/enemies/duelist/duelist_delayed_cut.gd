extends RefCounted
## An outside lift, a planted lead step, then a diagonal cut from the chest turn.

const NormalCut = preload("res://src/enemies/duelist/duelist_normal_cut.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const DISPLAY_NAME := "延迟斜劈"
const LEAD_LAND := 0.384
const TRAIL_START := 0.455
const HIT_START := 0.47
const HIT_END := 0.635
const DURATION := 1.03

const RAISED := Vector3(0.44, 0.85, 0.29)
const CUT_THROUGH := Vector3(-0.38, -0.23, -0.90)


static func begin(model, focus: Vector3, cover: Array, bounds: AABB) -> Dictionary:
	var state := NormalCut.begin(model, focus)
	var foot: Transform3D = state["feet"][0]
	var planted: Vector3 = model.to_global(foot.origin + Vector3(-0.07, 0, -0.65))
	planted = Hit.resolve_circles(planted, 0.23 * model.scale.x, cover, planted.y)
	if bounds.size.length_squared() > 0.1:
		planted.x = clampf(planted.x, bounds.position.x + 3.0, bounds.end.x - 3.0)
		planted.z = clampf(planted.z, bounds.position.z + 3.0, bounds.end.z - 3.0)
	state["lead_foot"] = model.to_local(planted)
	return state


static func apply(model, state: Dictionary, time: float) -> void:
	var sink := smoothstep(0.035, 0.23, time)
	var drive := smoothstep(LEAD_LAND - 0.023, 0.57, time)
	var chest_turn := smoothstep(0.423, 0.625, time)
	var recover := smoothstep(0.663, DURATION, time)
	var weight := 1.0 - recover
	var body := model.body as Node3D
	var chest := model.torso as Node3D
	var hip: Transform3D = state["hip"]
	body.position = hip.origin + Vector3(0.13, -0.115, 0.14) * (sink * (1.0 - drive))
	body.position += Vector3(-0.15, -0.12, -0.43) * drive * lerpf(1.0, 0.28, recover)
	body.basis = Basis.from_euler(Vector3(-0.085 * drive, deg_to_rad(-11.0 * sink + 29.0 * drive), 0.045 * sink) * weight) * hip.basis
	chest.basis = Basis.from_euler(Vector3(-0.12 * chest_turn, deg_to_rad(-17.0 * sink + 33.0 * chest_turn),
		-0.055 * chest_turn) * weight) * (state["chest"] as Basis)

	var lift := smoothstep(0.125, 0.270, time)
	var foot_phase := clampf(inverse_lerp(0.218, LEAD_LAND, time), 0.0, 1.0)
	var foot_place := smoothstep(0.0, 1.0, foot_phase)
	var feet: Array[Transform3D] = state["feet"].duplicate()
	var lead := feet[0]
	lead.origin = lead.origin.lerp(state["lead_foot"], foot_place)
	lead.origin.y += 0.155 * sin(PI * foot_phase)
	lead.basis = lead.basis.slerp(Basis(Vector3.UP, deg_to_rad(-9.0)), foot_place)
	feet[0] = lead
	NormalCut.pose_legs(model, feet, state["knees"])
	Pace.aim_head(model, state["focus"])
	NormalCut.pose_support(model, state, (Vector3(-0.24, 0.07, 0.16) * lift
		+ Vector3(-0.15, -0.10, 0.19) * chest_turn) * weight)
	_pose_sword(model, state, time, lift, recover)
	var toes: Vector2 = state["toes"]
	toes.x *= 1.0 - foot_place
	model.finish_pose(0.29, 1.0, toes)


static func _pose_sword(model, state: Dictionary, time: float, lift: float, recover: float) -> void:
	var high := RAISED.normalized()
	var low := CUT_THROUGH.normalized()
	var axis := high.cross(low).normalized()
	var cut := smoothstep(0.441, 0.646, time)
	var shaft := high.rotated(axis, high.angle_to(low) * cut)
	var from: Basis = state["blade"]
	var trunk: Transform3D = model.body.transform * model.torso.transform
	var ready: Vector3 = state["sword_hand"]
	# Carry the grip outside the right shoulder, then bring it across in front of the armor.
	var outside := Vector3(1.13, 1.47, -0.59)
	var follow := Vector3(0.26, 0.08, -1.19)
	var stroke := outside.lerp(follow, cut)
	stroke.y = lerpf(outside.y, follow.y, 1.0 - pow(1.0 - cut, 1.6))
	stroke.z -= 0.42 * sin(PI * cut)
	var hand := ready.lerp(stroke, lift).lerp(ready, recover)
	# Make room as the blade changes direction on the lift and the return.
	hand.x += 0.22 * (sin(PI * lift) + sin(PI * recover))
	hand.z -= 0.24 * sin(PI * recover)
	var active := lift * (1.0 - recover)
	var elbow := (state["sword_pole"] as Vector3).lerp(Vector3(0.87, -0.55, 0.30), active)
	var aim := from.y.slerp(shaft, lift).slerp(from.y, recover)
	var deviation := lerpf(13.0, -9.0, smoothstep(0.10, 0.72, cut))
	NormalCut.pose_sword_grip(model, trunk * hand, trunk.basis * elbow, aim,
		lerpf(state["deviation"], deviation, active))
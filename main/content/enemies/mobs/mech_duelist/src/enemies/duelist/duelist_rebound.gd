extends RefCounted
## The blade loses momentum first. Shoulder, elbow and chest absorb the reaction.

const NormalCut = preload("res://src/enemies/duelist/duelist_normal_cut.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const DURATION := 0.48


static func begin(model, focus: Vector3, contact_normal: Vector3, ready: Dictionary) -> Dictionary:
	var state := NormalCut.begin(model, focus)
	var blade: Basis = state["blade"]
	# The contact normal points toward the player's blade.
	var away: Vector3 = model.global_basis.inverse() * -contact_normal
	var deflection := (away.normalized() + Vector3.UP * 0.58).slide(blade.y).normalized()
	if deflection.is_zero_approx():
		deflection = blade.x
	state["axis"] = blade.y.cross(deflection).normalized()
	state["ready_blade"] = ready["blade"]
	state["ready_angles"] = ready["angles"]
	state["ready_deviation"] = ready["deviation"]
	state["ready_flexion"] = ready["wrist_flexion"]
	state["ready_grip_cant"] = ready["grip_cant"]
	return state


static func apply(model, state: Dictionary, time: float) -> void:
	var bounce := smoothstep(0.0, 0.076, time)
	var absorb := smoothstep(0.025, 0.155, time)
	var recover := smoothstep(0.155, DURATION, time)
	var tension := absorb * (1.0 - recover)
	var body := model.body as Node3D
	var chest := model.torso as Node3D
	var hip: Transform3D = state["hip"]
	body.position = hip.origin + Vector3(0.075, -0.075, 0.155) * tension
	body.basis = Basis.from_euler(Vector3(0.045, -0.050, 0.020) * tension) * hip.basis
	chest.basis = Basis.from_euler(Vector3(0.115, -0.102, -0.035) * tension) * (state["chest"] as Basis)
	NormalCut.pose_legs(model, state["feet"], state["knees"])
	Pace.aim_head(model, state["focus"])
	NormalCut.pose_support(model, state, Vector3(-0.06, 0.06, 0.14) * tension)

	var incoming: Basis = state["blade"]
	var deflected := Basis(state["axis"], deg_to_rad(23.0) * bounce) * incoming
	var ready: Basis = state["ready_blade"]
	var blocked_angles: Vector2 = state["angles"]
	var ready_angles: Vector2 = state["ready_angles"]
	var bent := minf(blocked_angles.x + deg_to_rad(32.0) * absorb, deg_to_rad(121.0))
	var grip_cant := lerpf(state["grip_cant"], state["ready_grip_cant"], recover)
	model.pose_sword_arm(deflected.slerp(ready, recover), lerpf(bent, ready_angles.x, recover),
		lerp_angle(blocked_angles.y, ready_angles.y, recover),
		lerpf(state["deviation"], state["ready_deviation"], recover),
		lerpf(state["wrist_flexion"], state["ready_flexion"], recover), grip_cant)
	model.finish_pose(0.29, 1.0, state["toes"], 0.0, 0.0, grip_cant)

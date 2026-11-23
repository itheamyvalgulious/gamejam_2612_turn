extends RefCounted

const Rig = preload("res://src/enemies/duelist/duelist_display_pose.gd")

const HIP_DROP := 0.32
const HIP_PITCH := -0.115
const CHEST_PITCH := -0.085
const SUPPORT_HAND := Vector3(-0.60, 0.76, -0.72)
const SUPPORT_POLE := Vector3(-0.64, -0.69, 0.33)
const WEAPON_HAND := Vector3(0.85, 0.58, -0.67)
const WEAPON_POLE := Vector3(0.43, -0.89, 0.11)
# In front view the hilt stays outside the right chest, with the blade leaning inward.
const WRIST_ROLL := 8.0
const WRIST_DEVIATION := 16.0


static func pose_weapon(model) -> void:
	var trunk: Transform3D = model.body.transform * model.torso.transform
	var arm: Dictionary = model.arms[1]
	var wrist := arm["wrist"] as Node3D
	var hand := trunk * WEAPON_HAND
	var shoulder: Vector3 = model.shoulder_anchor(arm, hand)
	Rig.solve_chain(arm["shoulder"], arm["elbow"], wrist, shoulder, hand,
		trunk.basis * WEAPON_POLE, model.UPPER_ARM, model.FOREARM)
	wrist.basis = model.sword_wrist_basis(arm, WRIST_ROLL, WRIST_DEVIATION)

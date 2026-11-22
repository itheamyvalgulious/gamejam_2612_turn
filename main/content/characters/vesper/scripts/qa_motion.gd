extends Node3D
## Motion continuity / acceleration audit.
##
## The rule: every clip's joints must move continuously, with no teleport and
## with joint accelerations no larger than the existing FRONT_R diagonal cleave.
##
## We sample the WORLD position of every visible end-effector (both wrists,
## both elbows, the hilt, the blade tip, the head) at 120 Hz and take second
## differences.  FRONT_R is measured first and becomes the ceiling for all
## other clips (and for itself, trivially).
##
## Run: godot --headless --path . res://scenes/qa_motion.tscn

const Rig = preload("res://scripts/mech/mech_rig.gd")
const DT := 1.0 / 120.0

var rig
var fails: Array[String] = []
var rows: Array[String] = []
var ref_accel := 0.0
var ref_step := 0.0

func _ready() -> void:
	rig = Rig.new()
	rig.auto_step = false
	rig.set_process(false)
	add_child(rig)
	await get_tree().process_frame
	var clips := [
		["FRONT_R", 1], ["FRONT_L", 2], ["RISE_R", 3], ["RISE_L", 4],
		["SIDE_R", 5], ["SIDE_L", 6], ["BACK", 7], ["HEAVY", 8], ["SPIN", 9],
	]
	for c in clips:
		await _audit(String(c[0]), int(c[1]))
	print("\n==== MOTION AUDIT ====")
	for r in rows:
		print(r)
	print("reference FRONT_R: max accel %.0f m/s^2, max step %.3f m" % [ref_accel, ref_step])
	print("failures: ", fails.size())
	for f in fails:
		print("FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


func _start(idx: int) -> void:
	rig.reset_demo(Vector3.ZERO, 0.0)
	await get_tree().process_frame
	match idx:
		1, 2, 3, 4: rig.request_front_attack(idx)
		5: rig.request_side_attack(1.0)
		6: rig.request_side_attack(-1.0)
		7: rig.request_back_attack()
		8: rig.request_heavy_attack()
		9: rig.request_spin_attack()


func _joints() -> Array:
	var wl: Vector3 = rig.arms[0]["wrist"].global_position
	var wr: Vector3 = rig.arms[1]["wrist"].global_position
	var el: Vector3 = rig.arms[0]["elbow"].global_position
	var er: Vector3 = rig.arms[1]["elbow"].global_position
	var hilt: Vector3 = rig.weapon_root.global_position
	var tip: Vector3 = rig.blade_tip.global_position
	var head: Vector3 = rig.head.global_position
	return [wl, wr, el, er, hilt, tip, head]


func _audit(label: String, idx: int) -> void:
	await _start(idx)
	var names := ["wristR", "wristL", "elbowR", "elbowL", "hilt", "bladeTip", "head"]
	var prev2: Array = []
	var prev1: Array = []
	var max_a := 0.0
	var max_step := 0.0
	var worst_a := ""
	var worst_step := ""
	var frames := 0
	while frames < 420:
		rig.advance(DT)
		frames += 1
		var p := _joints()
		if prev1.size() == p.size():
			for i in p.size():
				var step: float = (p[i] as Vector3).distance_to(prev1[i])
				if step > max_step:
					max_step = step
					worst_step = names[i]
				if prev2.size() == p.size():
					var acc: float = ((p[i] as Vector3) - 2.0 * (prev1[i] as Vector3) + (prev2[i] as Vector3)).length() / (DT * DT)
					if acc > max_a:
						max_a = acc
						worst_a = names[i]
		prev2 = prev1
		prev1 = p
		if not rig.is_attacking and frames > 20:
			break
	if label == "FRONT_R":
		ref_accel = max_a
		ref_step = max_step
	var acc_ok := max_a <= ref_accel * 1.02 + 1.0
	var step_ok := max_step <= ref_step * 1.05 + 0.005
	rows.append("%-7s accel=%.0f (%s)  step=%.3f (%s)  %s" % [
		label, max_a, worst_a, max_step, worst_step,
		"PASS" if acc_ok and step_ok else "FAIL"])
	if not acc_ok:
		fails.append("%s joint acceleration %.0f exceeds FRONT_R %.0f (%s)" % [label, max_a, ref_accel, worst_a])
	if not step_ok:
		fails.append("%s joint step %.3f exceeds FRONT_R %.3f (%s)" % [label, max_step, ref_step, worst_step])
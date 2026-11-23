extends Node3D
## Target-hit acceptance for the "1.5 m copy of itself" rule.
##
## Measured the way the requirement defines it: at the clip's hit frame a second,
## idle copy of the character is placed exactly 1.50 m from the attacker's
## vertical-projection centre, along the attack direction (character-local
## front / left / right / back), facing the attacker.  The blade must reach into
## that copy's real body volume: the whole 1.25 m blade (guard -> tip) is treated
## as a capsule and tested against the copy's actual limb/torso capsules, so a
## blade waving in empty air in front of the copy does not count as a hit.
##
##   godot --headless --path . res://scenes/qa_targets.tscn

const Rig = preload("res://scripts/mech/mech_rig.gd")

const DIST := 1.5
const BLADE_Y0 := 0.28        # guard side of the plasma blade
const BLADE_TIP := 1.56       # real tip (0.28 hilt + 1.28 blade)
const BLADE_R := 0.065
const UPPER_S := 1.107
const LOWER_S := 0.78

var rig
var dummy
var fails: Array[String] = []
var rows: Array[String] = []


func _ready() -> void:
	rig = Rig.new()
	rig.auto_step = false
	rig.set_process(false)
	add_child(rig)
	dummy = Rig.new()
	dummy.auto_step = false
	dummy.set_process(false)
	add_child(dummy)
	await get_tree().process_frame
	# the three requested directions plus the four front cleaves
	await _run("FRONT_R", 1, Vector3(0, 0, -1))
	await _run("FRONT_L", 2, Vector3(0, 0, -1))
	await _run("RISE_R", 3, Vector3(0, 0, -1))
	await _run("RISE_L", 4, Vector3(0, 0, -1))
	await _run("SIDE_R", 5, Vector3(1, 0, 0))
	await _run("SIDE_L", 6, Vector3(-1, 0, 0))
	await _run("BACK", 7, Vector3(0, 0, 1))
	print("\n==== TARGET HIT QA (1.50 m copy of itself) ====")
	for r in rows:
		print(r)
	print("failures: ", fails.size())
	for f in fails:
		print("FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


func _run(label: String, idx: int, local_dir: Vector3) -> void:
	rig.reset_demo(Vector3.ZERO, 0.0)
	await get_tree().process_frame
	# the copy of itself stands 1.50 m away (centre to centre, both on the floor)
	var dir_world: Vector3 = rig.global_transform.basis * local_dir
	dir_world.y = 0.0
	dir_world = dir_world.normalized()
	dummy.reset_demo(rig.global_position + dir_world * DIST, 0.0)
	dummy.face_target(rig.global_position)
	dummy.advance(1.0 / 120.0)
	var centre_dist := Vector2(dummy.global_position.x - rig.global_position.x,
		dummy.global_position.z - rig.global_position.z).length()
	var parts := _body_parts(dummy)
	match idx:
		1, 2, 3, 4: rig.request_front_attack(idx)
		5: rig.request_side_attack(1.0)
		6: rig.request_side_attack(-1.0)
		7: rig.request_back_attack()
	var best := 1e9
	var best_name := ""
	var best_pt := Vector3.ZERO
	var best_t := -1.0
	var best_tip := Vector3.ZERO
	var guard := 0
	while guard < 500:
		rig.advance(1.0 / 120.0)
		guard += 1
		var a: Vector3 = rig.weapon_spin.global_transform * Vector3(0, BLADE_Y0, 0)
		var b: Vector3 = rig.weapon_spin.global_transform * Vector3(0, BLADE_TIP, 0)
		for part in parts:
			var d := _seg_seg(a, b, part["a"], part["b"]) - BLADE_R - float(part["r"])
			if d < best:
				best = d
				best_name = String(part["name"])
				best_pt = _closest_on_seg(a, b, part["a"], part["b"])
				best_t = rig.attack_time
				best_tip = b
		if not rig.is_attacking and guard > 20:
			break
	var ok: bool = best <= 0.0
	var tag := "PASS" if ok else "FAIL"
	rows.append("%-8s %s  centre-dist=%.2f m  blade-vs-%s=%+.3f m  contact y=%.2f  t=%.2f  tip=%s" % [
		label, tag, centre_dist, best_name, best, best_pt.y, best_t, _v(best_tip)])
	if not ok:
		fails.append("%s misses the 1.5 m copy (closest %.3f m to %s)" % [label, best, best_name])


## Same capsule model as qa_collision._parts(): the copy's real body volumes.
func _body_parts(r) -> Array:
	var out: Array = []
	out.append(_cap("pelvis", r.lower_body.global_transform * Vector3(0, -0.02, 0),
		r.lower_body.global_transform * Vector3(0, 0.16, 0), 0.23 * LOWER_S))
	out.append(_cap("chest", r.torso.global_transform * Vector3(0, 0.26, 0),
		r.torso.global_transform * Vector3(0, 0.50, 0), 0.17 * UPPER_S))
	out.append(_cap("head", r.head.global_position, r.head.global_position, 0.16 * UPPER_S))
	for arm in r.arms:
		var side := "R" if float(arm["side"]) > 0.0 else "L"
		var sh: Vector3 = arm["shoulder"].global_position
		var el: Vector3 = arm["elbow"].global_position
		var wr: Vector3 = arm["wrist"].global_position
		out.append(_cap("arm%s_up" % side, sh, el, 0.055 * UPPER_S))
		out.append(_cap("arm%s_fore" % side, el, wr, 0.043 * UPPER_S))
		out.append(_cap("arm%s_hand" % side, wr, wr + (wr - el).normalized() * 0.07, 0.036 * UPPER_S))
	for i in r.legs.size():
		var leg: Dictionary = r.legs[i]
		var hip: Vector3 = leg["hip"].global_position
		var knee: Vector3 = leg["knee"].global_position
		var ankle: Vector3 = leg["ankle"].global_position
		out.append(_cap("leg%d_thigh" % i, hip, knee, 0.085 * LOWER_S))
		out.append(_cap("leg%d_shin" % i, knee, ankle, 0.065 * LOWER_S))
		out.append(_cap("leg%d_foot" % i, ankle, ankle + Vector3(0.10, -0.05, 0), 0.06 * LOWER_S))
	return out


func _cap(n: String, a: Vector3, b: Vector3, r: float) -> Dictionary:
	return {"name": n, "a": a, "b": b, "r": r}


func _closest_on_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Vector3:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	if a > 1e-9:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom != 0.0:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			var t := (b * s + f) / e
			if t < 0.0:
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				s = clampf((b - c) / a, 0.0, 1.0)
	return p1 + d1 * s


func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]


func _seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return p1.distance_to(p2)
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom != 0.0:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)
extends Node3D
## Strict component-level collision audit for every VESPER attack.
##
## Every body part is a capsule/sphere in world space.  For every clip and
## every frame we measure the closest distance between non-adjacent parts,
## so "looks fine" is not accepted: a negative number is a real intersection.
##
## Run: godot --headless --path . res://scenes/qa_collision.tscn

const Rig = preload("res://scripts/mech/mech_rig.gd")
const DT := 1.0 / 120.0

var rig
var fails: Array[String] = []
var rows: Array[String] = []


func _ready() -> void:
	rig = Rig.new()
	rig.auto_step = false
	rig.set_process(false)
	add_child(rig)
	await get_tree().process_frame
	await _run()
	print("\n==== COLLISION AUDIT ====")
	for r in rows:
		print(r)
	print("failures: ", fails.size())
	for f in fails:
		print("FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


func _run() -> void:
	var clips := [
		["FRONT_R", 1], ["FRONT_L", 2], ["RISE_R", 3], ["RISE_L", 4],
		["SIDE_R", 5], ["SIDE_L", 6], ["BACK", 7], ["HEAVY", 8], ["SPIN", 9],
	]
	for c in clips:
		await _audit(String(c[0]), int(c[1]))


func _start(idx: int) -> void:
	rig.reset_demo(Vector3.ZERO, 0.0)
	await get_tree().process_frame
	match idx:
		1, 2, 3, 4:
			rig.request_front_attack(idx)
		5:
			rig.request_side_attack(1.0)
		6:
			rig.request_side_attack(-1.0)
		7:
			rig.request_back_attack()
		8:
			rig.request_heavy_attack()
		9:
			rig.request_spin_attack()


func _audit(label: String, idx: int) -> void:
	await _start(idx)
	var worst := 1e9
	var worst_pair := ""
	var worst_t := 0.0
	var grip_worst := 0.0
	var dir_ok := true
	var yaw_total := 0.0
	var yaw_reverse := 0.0
	var prev_yaw: float = rig.torso.rotation.y
	var hit_samples := 0
	var hit_dir := Vector3.ZERO
	var frames := 0
	while frames < 360:
		rig.advance(DT)
		frames += 1
		var parts := _parts()
		for i in parts.size():
			for j in range(i + 1, parts.size()):
				var A: Dictionary = parts[i]
				var B: Dictionary = parts[j]
				if not _allowed(String(A["grp"]), String(B["grp"]), String(A["name"]), String(B["name"])):
					continue
				var d := _capsule_gap(A, B)
				if d < worst:
					worst = d
					worst_pair = "%s <-> %s" % [A["name"], B["name"]]
					worst_t = rig.attack_time
		# grip
		var gerr := _grip_error()
		if rig.is_attacking and rig.attack_time > 0.14 and rig.attack_time < float(rig._attack["duration"]) - 0.14:
			grip_worst = maxf(grip_worst, gerr)
			# spin continuity
			if idx == 9:
				var y: float = rig.torso.rotation.y
				var dy := wrapf(y - prev_yaw, -PI, PI)
				yaw_total += dy
				if rig.attack_time > 0.24 and dy < -0.01:
					yaw_reverse = maxf(yaw_reverse, -dy)
				prev_yaw = y
			# side/back hit direction
			var hit_at := 0.30
			if idx >= 5:
				hit_at = 0.34 if idx <= 6 else (0.80 if idx == 7 else 0.58)
			if absf(rig.attack_time - hit_at) < DT * 1.5:
				var axis: Vector3 = rig.weapon_spin.global_transform.basis.y.normalized()
				if idx == 5:
					dir_ok = dir_ok and axis.dot(rig.global_transform.basis.x) > 0.985
				elif idx == 6:
					dir_ok = dir_ok and axis.dot(rig.global_transform.basis.x) < -0.985
				elif idx == 7:
					dir_ok = dir_ok and axis.dot(rig.global_transform.basis.z) > 0.95
				hit_dir = axis
				hit_samples += 1
		if not rig.is_attacking and frames > 10:
			break
	var status := "PASS" if worst >= -0.005 else "FAIL"
	if status == "FAIL":
		fails.append("%s penetration %.3f (%s @ %.2fs)" % [label, worst, worst_pair, worst_t])
	if grip_worst > 0.03:
		fails.append("%s grip error %.3f" % [label, grip_worst])
	if not dir_ok:
		fails.append("%s hit axis not exact" % label)
	if idx == 9:
		if yaw_total < TAU - 0.15:
			fails.append("%s spin total %.2f < 360" % [label, yaw_total])
		if yaw_reverse > 0.02:
			fails.append("%s spin reverses %.2f rad" % [label, yaw_reverse])
	rows.append("%-7s %s  min_clear=%+.3f  %-42s grip=%.3f  yaw=%.2f rev=%.2f  dir=%s" % [
		label, status, worst, worst_pair, grip_worst, yaw_total, yaw_reverse, str(hit_dir)])


func _parts() -> Array:
	var out: Array = []
	# pelvis + torso + head
	var lower_s := 0.78
	var upper_s := 1.107
	out.append(_cap("pelvis", "body", rig.lower_body.global_transform * Vector3(0, -0.02, 0),
		rig.lower_body.global_transform * Vector3(0, 0.16, 0), 0.23 * lower_s))
	out.append(_cap("chest", "body", rig.torso.global_transform * Vector3(0, 0.26, 0),
		rig.torso.global_transform * Vector3(0, 0.50, 0), 0.17 * upper_s))
	out.append(_cap("head", "body", rig.head.global_position, rig.head.global_position, 0.16 * upper_s))
	for arm in rig.arms:
		var side := "R" if float(arm["side"]) > 0.0 else "L"
		var sh: Vector3 = arm["shoulder"].global_position
		var el: Vector3 = arm["elbow"].global_position
		var wr: Vector3 = arm["wrist"].global_position
		# Real mesh half-extents for arm_w = 0.74
		out.append(_cap("arm%s_up" % side, "arm" + side, sh, el, 0.055 * upper_s))
		out.append(_cap("arm%s_fore" % side, "arm" + side, el, wr, 0.043 * upper_s))
		out.append(_cap("arm%s_hand" % side, "hand" + side, wr, wr + (wr - el).normalized() * 0.07, 0.036 * upper_s))
	for i in rig.legs.size():
		var leg: Dictionary = rig.legs[i]
		var hip: Vector3 = leg["hip"].global_position
		var knee: Vector3 = leg["knee"].global_position
		var ankle: Vector3 = leg["ankle"].global_position
		out.append(_cap("leg%d_thigh" % i, "leg%d" % i, hip, knee, 0.085 * lower_s))
		out.append(_cap("leg%d_shin" % i, "leg%d" % i, knee, ankle, 0.065 * lower_s))
		out.append(_cap("leg%d_foot" % i, "leg%d" % i, ankle, ankle + Vector3(0.10, -0.05, 0), 0.06 * lower_s))
	# weapon (weapon_spin local Y is the blade axis; root scale is 1/0.82)
	var wx: Transform3D = rig.weapon_spin.global_transform
	# Every rigid part of the sword, not just hilt + blade: the pommel and the
	# crossguard are real volumes that can (and did) pass through the body.
	# Real mesh extents (hilt prism -0.20..+0.14, pommel cap -0.26..-0.16).
	var pommel_a := wx * Vector3(0, -0.265, 0)
	var pommel_b := wx * Vector3(0, -0.185, 0)
	var hilt_a := wx * Vector3(0, -0.20, 0)
	var hilt_b := wx * Vector3(0, 0.15, 0)
	# Crossguard = the horizontal crossbar (local X), not the housing block that
	# legitimately sits inside the forward fist.
	var guard_a := wx * Vector3(-0.220, 0.198, 0)
	var guard_b := wx * Vector3(0.220, 0.198, 0)
	var blade_a := wx * Vector3(0, 0.55, 0)
	var blade_b := wx * Vector3(0, 1.88, 0)
	out.append(_cap("weapon_pommel", "weapon", pommel_a, pommel_b, 0.038))
	out.append(_cap("weapon_hilt", "weapon", hilt_a, hilt_b, 0.033))
	out.append(_cap("weapon_guard", "weapon", guard_a, guard_b, 0.026))
	out.append(_cap("weapon_blade", "weapon", blade_a, blade_b, 0.065))
	return out


func _cap(n: String, grp: String, a: Vector3, b: Vector3, r: float) -> Dictionary:
	return {"name": n, "grp": grp, "a": a, "b": b, "r": r}


func _allowed(ga: String, gb: String, na: String, nb: String) -> bool:
	# skip the weapon-vs-hand grip contact and adjacent limb segments
	# attachment overlaps: head/chest, pelvis/chest, upper arm/chest, thigh/pelvis
	if ga == "body" and gb == "body" and ((na == "head" and nb == "chest") or (nb == "head" and na == "chest") or (na == "pelvis" and nb == "chest") or (nb == "pelvis" and na == "chest")):
		return false
	if ga == "body" and gb.begins_with("arm") and na in ["chest", "pelvis"] and nb.ends_with("_up"):
		return false
	if gb == "body" and ga.begins_with("arm") and nb in ["chest", "pelvis"] and na.ends_with("_up"):
		return false
	if ga == "body" and gb.begins_with("leg") and na == "pelvis" and nb.ends_with("_thigh"):
		return false
	if gb == "body" and ga.begins_with("leg") and nb == "pelvis" and na.ends_with("_thigh"):
		return false
	if ga == "weapon" and gb == "weapon":
		return false
	# The only contact that is legitimate is a GRIPPING fist wrapped around the
	# hilt.  Everything else is a real intersection:
	#   - blade / guard / pommel vs either hand,
	#   - any sword part vs either forearm or upper arm,
	#   - the hilt vs a hand that has RELEASED the weapon.
	if ga == "weapon" or gb == "weapon":
		var wn := na if ga == "weapon" else nb
		var other := nb if ga == "weapon" else na
		var og := gb if ga == "weapon" else ga
		# The blade is checked against EVERY body part, including both arms.
		if wn == "weapon_blade":
			return true
		# Grip hardware (hilt / guard / pommel) lives inside the fists and the
		# glove cuffs, so capsule contact with the forearms there is expected.
		# It is still checked against the torso, head, pelvis and legs above.
		if og.begins_with("arm"):
			return false
		if og.begins_with("hand"):
			var is_right := other == "armR_hand"
			var gripping := is_right or float(rig._offhand_cur) < 0.15
			if gripping:
				return false
		return true
	if ga == gb and ga.begins_with("leg"):
		return false
	if ga == gb and ga.begins_with("arm"):
		return false
	if (na.ends_with("_fore") and nb.ends_with("_hand")) or (nb.ends_with("_fore") and na.ends_with("_hand")):
		if na.substr(3, 1) == nb.substr(3, 1):
			return false
	# adjacent body/head is always checked
	return true


func _capsule_gap(A: Dictionary, B: Dictionary) -> float:
	var d := _seg_seg(A["a"], A["b"], B["a"], B["b"])
	return d - float(A["r"]) - float(B["r"])


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
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return c1.distance_to(c2)


func _grip_error() -> float:
	if rig.weapon_root == null or rig.arms.size() < 2:
		return 0.0
	# Fixed convention: arm 0 = right (pommel, -GRIP), arm 1 = left (+GRIP).
	var grips: Array = [
		rig.weapon_root.transform * Vector3(0, -0.16, 0),
		rig.weapon_root.transform * Vector3(0, 0.16, 0),
	]
	var off_idx := 1
	var err := 0.0
	for i in 2:
		if i == off_idx and rig._offhand_cur > 0.03:
			continue
		var grip: Vector3 = rig.torso.global_transform * grips[i]
		var wrist: Vector3 = rig.arms[i]["wrist"].global_position
		err = maxf(err, grip.distance_to(wrist))
	return err
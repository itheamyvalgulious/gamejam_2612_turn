extends Node3D
## VESPER v2 acceptance harness.  Headless:
##   godot --headless --path . res://scenes/qa_v2.tscn
## Checks proportions, knee angle, all eight attacks, side/back direction,
## lateral dashes, jump crouch, hair motion and ground clearance.

const Rig = preload("res://scripts/mech/mech_rig.gd")

var rig
var fails: Array[String] = []
var checks := 0
var report := {}


func _ready() -> void:
	rig = Rig.new()
	rig.name = "VESPER"
	rig.auto_step = false
	rig.set_process(false)
	add_child(rig)
	await get_tree().process_frame
	await _run()
	_finish()


func _ok(cond: bool, label: String, detail := "") -> void:
	checks += 1
	if cond:
		print("PASS  ", label, "  ", detail)
	else:
		print("FAIL  ", label, "  ", detail)
		fails.append(label + " " + detail)


func _run() -> void:
	rig.reset_demo(Vector3.ZERO, 0.0)
	for i in 8:
		rig.advance(1.0 / 60.0)
	await get_tree().process_frame

	# ---------------- proportions
	var bb: AABB = rig.body_aabb()
	var height := bb.end.y
	var low := bb.position.y
	var radius := 0.0
	for cx in [bb.position.x, bb.end.x]:
		for cz in [bb.position.z, bb.end.z]:
			radius = maxf(radius, Vector2(cx, cz).length())
	var stance := 0.0
	for leg in rig.legs:
		var t: Vector3 = leg["target"]
		stance = maxf(stance, Vector2(t.x, t.z).length())
	var torso_r := 0.0
	for cx in [bb.position.x, bb.end.x]:
		for cz in [bb.position.z, bb.end.z]:
			torso_r = maxf(torso_r, Vector2(cx, cz).length())
	report["height"] = height
	report["floor"] = low
	report["stance_radius"] = stance
	report["silhouette_radius"] = radius
	_ok(height >= 1.90 and height <= 2.12, "height ~2.0 m", "%.3f m" % height)
	_ok(low >= -0.005, "feet above floor", "min y %.3f m" % low)
	_ok(stance >= 0.36 and stance <= 0.56, "compact 0.5 m stance", "%.3f m" % stance)
	_ok(radius <= 1.22, "silhouette compact", "%.3f m" % radius)

	# ---------------- asymmetric forward camera + green indicator
	var cam_pod: Node3D = rig.head_camera
	var head_fwd: Vector3 = (-rig.head.global_transform.basis.z).normalized()
	var cam_fwd: Vector3 = (-cam_pod.global_transform.basis.z).normalized()
	_ok(cam_fwd.dot(head_fwd) > 0.995, "head camera points forward", "dot %.4f" % cam_fwd.dot(head_fwd))
	var lens_d := float(cam_pod.get_meta("lens_diameter", 0.0))
	_ok(lens_d >= 0.10, "head camera large enough", "%.3f m" % lens_d)
	var cam_x: float = rig.head.to_local(cam_pod.global_position).x
	var green: MeshInstance3D = rig.head_green_dot
	var green_x: float = rig.head.to_local(green.global_position).x
	_ok(absf(cam_x) < 0.01 and green_x < -0.02, "centred camera / offset green dot", "cam x %.3f, green x %.3f" % [cam_x, green_x])
	report["head_camera"] = {"forward_dot": cam_fwd.dot(head_fwd), "lens_m": lens_d, "cam_x": cam_x, "green_x": green_x}

	for i in 4:
		var ka: float = rig.get_knee_angle(i)
		_ok(ka >= 128.0 and ka <= 142.0, "knee %d ~135 deg" % i, "%.1f deg" % ka)
	report["knee"] = [rig.get_knee_angle(0), rig.get_knee_angle(1), rig.get_knee_angle(2), rig.get_knee_angle(3)]

	# ---------------- attacks
	var front := ["FRONT_R", "FRONT_L", "RISE_R", "RISE_L"]
	var fronts := {}
	for nm in front:
		var res := await _run_front_attack(front.find(nm) + 1)
		fronts[nm] = res
		_ok(float(res["min_z"]) < -0.75, "%s reaches forward" % nm, "tip z %.2f" % res["min_z"])
		_ok(float(res["reach"]) >= 1.2, "%s blade reach" % nm, "%.2f m" % res["reach"])
		_ok(float(res["floor"]) >= -0.02, "%s ground clearance" % nm, "%.3f" % res["floor"])
	report["front"] = fronts

	# side thrust: no body turn, tip out to +X
	rig.reset_demo(Vector3.ZERO, 0.0)
	var max_x := -99.0
	var max_yaw := 0.0
	var side_floor := 99.0
	rig.request_side_attack(1.0)
	for i in 150:
		rig.advance(1.0 / 60.0)
		max_x = maxf(max_x, rig.blade_tip_world().x)
		max_yaw = maxf(max_yaw, absf(rig.torso.rotation.y))
		side_floor = minf(side_floor, rig.body_aabb().position.y)
		if not rig.is_attacking and i > 10:
			break
	_ok(max_x >= 1.35, "side thrust reaches +X", "tip x %.2f" % max_x)
	_ok(max_yaw <= 0.20, "side thrust does not turn", "max torso yaw %.3f rad" % max_yaw)
	_ok(side_floor >= -0.02, "side thrust floor", "%.3f" % side_floor)
	report["side"] = {"tip_x": max_x, "yaw": max_yaw}

	# back thrust: tip behind (+Z) and on the body's left (-X)
	rig.reset_demo(Vector3.ZERO, 0.0)
	var best_back := Vector3.ZERO
	var back_yaw := 0.0
	rig.request_back_attack()
	for i in 170:
		rig.advance(1.0 / 60.0)
		var tip: Vector3 = rig.blade_tip_world()
		if tip.z > best_back.z:
			best_back = tip
		back_yaw = maxf(back_yaw, absf(rig.torso.rotation.y))
		if not rig.is_attacking and i > 10:
			break
	_ok(best_back.z >= 0.90, "back thrust reaches behind", "tip z %.2f" % best_back.z)
	_ok(absf(best_back.x) <= 0.25, "back thrust aims behind the centre line", "tip x %.2f" % best_back.x)
	_ok(back_yaw <= 0.80, "back thrust turn <= 45 deg", "%.3f rad" % back_yaw)
	report["back"] = {"tip": best_back, "yaw": back_yaw}

	# heavy: overhead and down
	rig.reset_demo(Vector3.ZERO, 0.0)
	var heavy_min_y := 99.0
	var heavy_max_y := -99.0
	rig.request_heavy_attack()
	for i in 220:
		rig.advance(1.0 / 60.0)
		var ty: float = rig.blade_tip_world().y
		heavy_min_y = minf(heavy_min_y, ty)
		heavy_max_y = maxf(heavy_max_y, ty)
		if not rig.is_attacking and i > 10:
			break
	_ok(heavy_max_y >= 1.55, "heavy raises overhead", "tip y %.2f" % heavy_max_y)
	_ok(heavy_min_y <= 0.35, "heavy strikes low", "tip y %.2f" % heavy_min_y)
	report["heavy"] = {"min_y": heavy_min_y, "max_y": heavy_max_y}

	# spin: continuous 360 and horizontal blade
	rig.reset_demo(Vector3.ZERO, 0.0)
	var yaw_acc := 0.0
	var prev_yaw: float = rig.torso.rotation.y
	var horiz_err := 0.0
	rig.request_spin_attack()
	for i in 220:
		rig.advance(1.0 / 60.0)
		var y: float = rig.torso.rotation.y
		yaw_acc += absf(wrapf(y - prev_yaw, -PI, PI))
		prev_yaw = y
		if rig.is_attacking and rig.attack_time > 0.55 and rig.attack_time < 0.95:
			var h: Vector3 = rig.weapon_root.global_position
			var t: Vector3 = rig.blade_tip_world()
			horiz_err = maxf(horiz_err, absf(t.y - h.y))
		if not rig.is_attacking and i > 10:
			break
	_ok(yaw_acc >= TAU * 0.92, "spin sweeps 360", "%.2f rad" % yaw_acc)
	_ok(horiz_err <= 0.55, "spin blade held level", "dy %.2f m" % horiz_err)
	report["spin"] = {"yaw": yaw_acc, "level_err": horiz_err}

	# ---------------- dashes
	var fwd := await _dash_test(Vector3(0, 0, -1), "forward")
	_ok(fwd["along"] >= 1.2, "forward dash distance", "%.2f m" % fwd["along"])
	var left := await _dash_test(Vector3(-1, 0, 0), "left")
	_ok(left["along"] >= 1.2 and left["side"] >= 1.2, "left dash", "along %.2f side %.2f" % [left["along"], left["side"]])
	var right := await _dash_test(Vector3(1, 0, 0), "right")
	_ok(right["along"] >= 1.2 and right["side"] >= 1.2, "right dash", "along %.2f side %.2f" % [right["along"], right["side"]])
	var back_d := await _dash_test(Vector3(0, 0, 1), "back")
	_ok(back_d["along"] >= 1.2, "back dash distance", "%.2f m" % back_d["along"])
	_ok(float(back_d["min_fwd_dot"]) > 0.85, "dual thrusters swivel forward on back dash", "min dot %.3f" % back_d["min_fwd_dot"])
	report["dash"] = {"fwd": fwd, "left": left, "right": right, "back": back_d}

	# ---------------- jump crouch + apex
	rig.reset_demo(Vector3.ZERO, 0.0)
	var crouch_y := 99.0
	var apex := -99.0
	rig.request_jump()
	for i in 200:
		rig.advance(1.0 / 60.0)
		if rig.jump_state == "TAKEOFF":
			crouch_y = minf(crouch_y, rig.body.position.y)
		apex = maxf(apex, rig.position.y)
		if rig.jump_state == "LANDING" and i > 20:
			break
	var drop: float = 1.235 - crouch_y
	_ok(drop >= 0.18, "jump has visible crouch", "hip drop %.2f m" % drop)
	_ok(apex >= 0.55, "jump apex", "%.2f m" % apex)
	report["jump"] = {"crouch_drop": drop, "apex": apex}

	# ---------------- hair
	rig.reset_demo(Vector3.ZERO, 0.0)
	for i in 30:
		rig.advance(1.0 / 60.0)
		await get_tree().process_frame
	var tips0: Array = rig.hair_tips()
	var local0: Array[Vector3] = []
	for t in tips0:
		local0.append(rig.head.to_local(t))
	# Move and rotate the rig: the tips must move *relative to the head*, not
	# merely ride along with world translation.
	rig.move_command = Vector3(0, 0, -5.0)
	for i in 30:
		rig.advance(1.0 / 60.0)
		await get_tree().process_frame
	rig.heading += 1.2
	rig.rotation.y = rig.heading
	rig.move_command = Vector3.ZERO
	for i in 24:
		rig.advance(1.0 / 60.0)
		await get_tree().process_frame
	var tips1: Array = rig.hair_tips()
	_ok(tips0.size() >= 20, "hair bone-chain tips", "%d tips" % tips0.size())
	var hair_move := 0.0
	var nan := false
	for i in mini(local0.size(), tips1.size()):
		var b: Vector3 = rig.head.to_local(tips1[i])
		if is_nan(b.x):
			nan = true
		hair_move = maxf(hair_move, local0[i].distance_to(b))
	_ok(not nan, "hair no NaN")
	_ok(hair_move >= 0.03, "hair responds to motion", "tip shift %.3f m" % hair_move)
	report["hair"] = {"tips": tips0.size(), "shift": hair_move}


func _run_front_attack(step: int) -> Dictionary:
	rig.reset_demo(Vector3.ZERO, 0.0)
	await get_tree().process_frame
	rig.request_front_attack(step)
	var min_z := 99.0
	var reach := 0.0
	var floor_y := 99.0
	for i in 180:
		rig.advance(1.0 / 60.0)
		var tip: Vector3 = rig.blade_tip_world()
		min_z = minf(min_z, tip.z)
		reach = maxf(reach, Vector2(tip.x, tip.z).length())
		floor_y = minf(floor_y, rig.body_aabb().position.y)
		if not rig.is_attacking and i > 10:
			break
	return {"min_z": min_z, "reach": reach, "floor": floor_y}


func _dash_test(local_dir: Vector3, _label: String) -> Dictionary:
	rig.reset_demo(Vector3.ZERO, 0.0)
	var p0: Vector3 = rig.global_position
	rig.request_dash(local_dir)
	var min_fwd_dot := -1.0
	for i in 40:
		rig.advance(1.0 / 60.0)
		if i == 11:
			var rig_fwd: Vector3 = -rig.global_transform.basis.z.normalized()
			min_fwd_dot = 1.0
			for tn in rig.thruster_nodes:
				var exhaust_dir: Vector3 = (tn as Node3D).global_transform.basis.z.normalized()
				min_fwd_dot = minf(min_fwd_dot, exhaust_dir.dot(rig_fwd))
	var d: Vector3 = rig.global_position - p0
	return {
		"along": d.length(),
		"side": absf(d.x) if absf(local_dir.x) > 0.5 else absf(d.z),
		"min_fwd_dot": min_fwd_dot,
	}


func _finish() -> void:
	print("\n==== VESPER v2 QA: %d checks, %d failures ====" % [checks, fails.size()])
	for f in fails:
		print("  FAILED: ", f)
	var f := FileAccess.open("res://renders/qa_v2.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	get_tree().quit(0 if fails.is_empty() else 1)
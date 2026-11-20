extends Node3D
## ARC // SENTINEL v2 — acceptance QA.
##
## Headless: godot --headless --path . res://scenes/qa.tscn
## Checks: every clip frame for self-collision, all direct animation blends,
## authored attack paths, both mandated blocks, solver timings.

const CH_SCENE := "res://scenes/character.tscn"

var ch: Node3D
var kin
var anim
var fails: Array = []
var rows: Array = []


func _ready() -> void:
	ch = load(CH_SCENE).instantiate()
	add_child(ch)
	await get_tree().process_frame
	kin = ch.kin
	anim = ch.anim
	print("=== ARC SENTINEL v2 QA ===")
	print("anims: ", ch.anim_names())
	print("build_ms: ", anim.build_ms, "  attack: ", anim.attack_ms,
		"  attack_up: ", anim.attack_up_ms, "  defend: ", anim.defend_ms)
	_test_clip_clearance()
	_test_transitions()
	_test_attack_poses()
	_test_blocks()
	_test_timing()
	_write_report()
	print("\n=== RESULT: %s (%d failures) ===" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	for f in fails:
		print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


func _fail(msg: String) -> void:
	fails.append(msg)


func _test_clip_clearance() -> void:
	print("\n-- clip clearance --")
	for name in ch.anim_names():
		var dur: float = anim.duration(name)
		var n := 96
		var worst := 9.0
		var wp := ["", ""]
		var wt := 0.0
		var floor_worst := 9.0
		for i in n + 1:
			var t := dur * float(i) / float(n)
			var pose: Dictionary = anim.sample(name, t)
			var a: Dictionary = kin.audit(pose)
			if float(a["min"]) < worst:
				worst = float(a["min"])
				wp = a["pair"]
				wt = t
			floor_worst = minf(floor_worst, float(a["floor"]))
		var ok := worst > 0.0 and floor_worst > -0.002
		print("  %-9s dur %.2f  min %+.4f m at %.2fs %s  floor %+.4f  %s" % [
			name, dur, worst, wt, str(wp), floor_worst, "OK" if ok else "FAIL"])
		rows.append({"clip": name, "dur": dur, "min": worst, "pair": wp,
			"t": wt, "floor": floor_worst})
		if not ok:
			_fail("%s collision %.4f m %s at %.2fs (floor %.4f)" % [name, worst, str(wp), wt, floor_worst])


func _test_transitions() -> void:
	print("\n-- animation blends (state-machine reachable) --")
	var loops := ["idle", "walk"]
	var drawn := ["idle", "walk", "attack", "attack_up", "defend"]
	var worst := 9.0
	var wdesc := ""
	for a in loops:
		for b in drawn:
			if a == b:
				continue
			var ta: float = anim.duration(a) * 0.55
			var pa: Dictionary = anim.sample(a, ta)
			var pb: Dictionary = anim.sample(b, 0.0)
			var mn := 9.0
			var mp := ["", ""]
			for k in 13:
				var u := float(k) / 12.0
				var p: Dictionary = ArcKin2.blend_pose(pa, pb, u)
				var au: Dictionary = kin.audit(p)
				if float(au["min"]) < mn:
					mn = float(au["min"])
					mp = au["pair"]
			if mn < worst:
				worst = mn
				wdesc = "%s@%.2f -> %s : %.4f %s" % [a, ta, b, mn, str(mp)]
			rows.append({"blend": "%s->%s" % [a, b], "min": mn, "pair": mp})
	# one-shots are never cancelled: their end pose is the idle base
	for a in ["attack", "attack_up", "defend"]:
		var pa2: Dictionary = anim.sample(a, anim.duration(a))
		for b in drawn:
			var pb2: Dictionary = anim.sample(b, 0.0)
			var mn2 := 9.0
			var mp2 := ["", ""]
			for k in 13:
				var p2: Dictionary = ArcKin2.blend_pose(pa2, pb2, float(k) / 12.0)
				var au2: Dictionary = kin.audit(p2)
				if float(au2["min"]) < mn2:
					mn2 = float(au2["min"])
					mp2 = au2["pair"]
			if mn2 < worst:
				worst = mn2
				wdesc = "%s(end) -> %s : %.4f %s" % [a, b, mn2, str(mp2)]
			rows.append({"blend": "%s(end)->%s" % [a, b], "min": mn2, "pair": mp2})
	print("  worst reachable blend: %s" % wdesc)
	if worst <= 0.0:
		_fail("animation blend collision: %s" % wdesc)
	# rest <-> idle must go through draw / sheathe
	for pair in [["rest", "idle"], ["idle", "rest"]]:
		var pa3: Dictionary = anim.sample(pair[0], 0.0)
		var pb3: Dictionary = anim.sample(pair[1], 0.0)
		var mn3 := 9.0
		for k in 13:
			var p3: Dictionary = ArcKin2.blend_pose(pa3, pb3, float(k) / 12.0)
			mn3 = minf(mn3, float(kin.audit(p3)["min"]))
		print("  direct %s->%s min %+.4f (routed via draw/sheathe)" % [pair[0], pair[1], mn3])


func _elbow_bend(arm: Dictionary) -> float:
	var upper: Vector3 = arm["e"] - arm["s"]
	var fore: Vector3 = arm["w"] - arm["e"]
	return rad_to_deg(upper.angle_to(fore))


func _test_attack_poses() -> void:
	print("\n-- authored strike paths --")
	var down_start := kin.arm_fk(-1, anim.action_key("attack", "windup")) as Dictionary
	var down_middle := kin.arm_fk(-1, anim.action_key("attack", "front")) as Dictionary
	var down_end := kin.arm_fk(-1, anim.action_key("attack", "end")) as Dictionary
	var up_start := kin.arm_fk(-1, anim.action_key("attack_up", "windup")) as Dictionary
	var up_middle := kin.arm_fk(-1, anim.action_key("attack_up", "front")) as Dictionary
	var up_finish: Dictionary = anim.action_key("attack_up", "end")
	var up_end := kin.arm_fk(-1, up_finish) as Dictionary
	var up_optic: Transform3D = kin.camera_xf(up_finish)
	print("  downward windup wrist x %.3f m, rising finish wrist x %.3f m" % [
		down_start["w"].x, up_end["w"].x])
	if float(down_start["w"].x) < 0.10:
		_fail("Downward windup hand does not reach the left side")
	if float(up_end["w"].x) < 0.20 or float(up_end["tool"].x) < up_optic.origin.x + 0.065:
		_fail("Rising finish does not carry the hand left of the forward optic")
	for arm in [down_middle, up_middle]:
		var tool: Vector3 = arm["tool"]
		if absf(tool.x) > 0.14 or tool.z < 0.70:
			_fail("Strike does not carry the hand through the zone in front of the chassis")
	if down_start["tool"].y < 1.40 or down_start["dir"].x < 0.25:
		_fail("Downward cut does not load high to the left")
	if down_middle["dir"].z < 0.85 or _elbow_bend(down_start) < 65.0:
		_fail("Downward cut does not extend out of a bent-elbow windup")
	if down_end["dir"].x >= 0.0 or down_end["dir"].y >= 0.0 or down_end["dir"].z < 0.55:
		_fail("Downward cut does not finish right-front-down")
	if up_start["tool"].x > -0.50 or up_start["tool"].y > 0.80 or up_start["dir"].z >= 0.0:
		_fail("Rising cut does not load low to the right")
	if up_end["dir"].x <= 0.0 or up_end["dir"].y < 0.60 or up_end["tool"].y <= up_end["s"].y:
		_fail("Rising cut does not finish left-front-up")
	for name in ["attack", "attack_up"]:
		var worst_eye := 0.0
		var nearest_elbow := -INF
		var smallest_bend := 180.0
		for i in 121:
			var pose: Dictionary = anim.sample(name, anim.duration(name) * i / 120.0)
			var optic: Transform3D = kin.camera_xf(pose)
			worst_eye = maxf(worst_eye, rad_to_deg(optic.basis.z.angle_to(Vector3.BACK)))
			var arm: Dictionary = kin.arm_fk(-1, pose)
			nearest_elbow = maxf(nearest_elbow, (arm["e"] as Vector3).x)
			smallest_bend = minf(smallest_bend, _elbow_bend(arm))
		print("  %s: optic deviation %.2f deg, elbow closest to centre x %.3f m, min bend %.1f deg" % [
			name, worst_eye, nearest_elbow, smallest_bend])
		if worst_eye > 1.5:
			_fail("%s optic lost level forward aim" % name)
		if smallest_bend < 12.0:
			_fail("%s locked out the right elbow" % name)


func _test_blocks() -> void:
	print("\n-- mandated blocks --")
	ch.set_block_threat(0)
	var a: Dictionary = ch.block_plan_stats()
	ch.set_block_threat(1)
	var b: Dictionary = ch.block_plan_stats()
	for r in [a, b]:
		print("  threat %d %s: effector %s blocked %s miss %.4f clear %.4f plan %.1f ms" % [
			int(r["threat"]), str(r["threat_name"]), str(r["effector"]),
			str(r["blocked"]), float(r["miss"]), float(r["min_clear"]), float(r["plan_ms"])])
		if not bool(r["blocked"]):
			_fail("block %s not intercepted" % str(r["threat_name"]))
		if str(r["effector"]) != ("shield" if int(r["threat"]) == 0 else "sword"):
			_fail("block %s wrong effector %s" % [str(r["threat_name"]), str(r["effector"])])
		if float(r["min_clear"]) <= 0.0:
			_fail("block %s collision %.4f" % [str(r["threat_name"]), float(r["min_clear"])])
	if str(a["effector"]) == "guard" or str(b["effector"]) == "guard":
		_fail("guard fallback used")


func _test_timing() -> void:
	print("\n-- solver timing --")
	var atk: Dictionary = ch.attack_plan_stats("attack")
	var up: Dictionary = ch.attack_plan_stats("attack_up")
	ch.set_block_threat(0)
	var bl: Dictionary = ch.block_plan_stats()
	print("  attack plan %.1f ms (min clear %.4f, qdot %.1f)" % [
		float(atk["plan_ms"]), float(atk["min_clear"]), float(atk["qdot_max"])])
	print("  attack_up plan %.1f ms (min clear %.4f, qdot %.1f)" % [
		float(up["plan_ms"]), float(up["min_clear"]), float(up["qdot_max"])])
	print("  block plan %.1f ms" % float(bl["plan_ms"]))
	if float(atk["plan_ms"]) > 50.0:
		_fail("attack plan %.1f ms > 50" % float(atk["plan_ms"]))
	if float(up["plan_ms"]) > 50.0:
		_fail("attack_up plan %.1f ms > 50" % float(up["plan_ms"]))
	if float(bl["plan_ms"]) > 50.0:
		_fail("block plan %.1f ms > 50" % float(bl["plan_ms"]))
	if float(atk["min_clear"]) <= 0.0:
		_fail("attack table collision %.4f %s" % [float(atk["min_clear"]), str(atk["min_pair"])])
	if float(atk["qdot_max"]) > 30.0:
		_fail("attack qdot %.1f > 30 rad/s" % float(atk["qdot_max"]))
	if float(up["min_clear"]) <= 0.0:
		_fail("attack_up table collision %.4f %s" % [float(up["min_clear"]), str(up["min_pair"])])
	if float(up["qdot_max"]) > 25.5:
		_fail("attack_up qdot %.1f > 25.5 rad/s" % float(up["qdot_max"]))


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	var f := FileAccess.open("res://renders/v2/qa_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"pass": fails.is_empty(), "fails": fails, "rows": rows,
			"timing": {"attack_ms": anim.attack_ms, "attack_up_ms": anim.attack_up_ms,
				"defend_ms": anim.defend_ms, "build_ms": anim.build_ms},
		}, "  "))
		f.close()
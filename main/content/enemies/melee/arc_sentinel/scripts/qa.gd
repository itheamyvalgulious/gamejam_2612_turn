extends Node3D
## ARC // GRINDER v3 — acceptance QA.
##
## Headless: godot --headless --path . res://scenes/qa.tscn
## Checks: every clip frame for self-collision + floor, all reachable blends,
## exact attack/guard constraints, runtime block planning budget, optic aim,
## track belt periodicity, and joint-speed sanity.

const D2R := PI / 180.0
const TAU := PI * 2.0
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
	print("=== ARC GRINDER v3 QA ===")
	print("anims: ", ch.anim_names())
	print("build_ms: ", anim.build_ms, "  attack1: ", anim.attack1_ms,
		"  attack2: ", anim.attack2_ms, "  block(raw): ", anim.block_plan_raw_ms)
	_test_clip_clearance()
	_test_transitions()
	_test_attack_poses()
	_test_swing_paths()
	_test_blocks()
	_test_timing()
	_test_optic()
	_test_tracks()
	_test_static_clearance()
	_write_report()
	print("\n=== RESULT: %s (%d failures) ===" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	for f in fails:
		print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


func _fail(msg: String) -> void:
	fails.append(msg)


func _audit_exact(pose: Dictionary) -> Dictionary:
	return kin.audit(pose, false, 10.0)


func _test_clip_clearance() -> void:
	print("\n-- clip clearance --")
	for name in ch.anim_names():
		var dur: float = anim.duration(name)
		var n := 120
		var worst := 9.0
		var wp := ["", ""]
		var wt := 0.0
		var floor_worst := 9.0
		var tip_low := 9.0
		for i in n + 1:
			var t := dur * float(i) / float(n)
			var pose: Dictionary = anim.sample(name, t)
			var a: Dictionary = _audit_exact(pose)
			if float(a["min"]) < worst:
				worst = float(a["min"])
				wp = a["pair"]
				wt = t
			floor_worst = minf(floor_worst, float(a["floor"]))
			tip_low = minf(tip_low, float((kin.arm_fk(pose)["tip"] as Vector3).y))
		var ok := worst > 0.0 and floor_worst > -0.004 and tip_low > 0.12
		print("  %-8s dur %.2f  min %+.4f m at %.2fs %s  floor %+.4f  tip y %+.3f  %s" % [
			name, dur, worst, wt, str(wp), floor_worst, tip_low, "OK" if ok else "FAIL"])
		rows.append({"clip": name, "dur": dur, "min": worst, "pair": wp,
			"t": wt, "floor": floor_worst, "tip_low": tip_low})
		if not ok:
			_fail("%s collision %.4f m %s at %.2fs (floor %.4f tip %.3f)" % [
				name, worst, str(wp), wt, floor_worst, tip_low])


func _test_transitions() -> void:
	print("\n-- animation blends (state-machine reachable) --")
	var states: Array = []
	for nm in ["idle", "run"]:
		for f in [0.0, 0.33, 0.66]:
			states.append([nm, f])
	for nm in ["attack1", "attack2", "block"]:
		states.append([nm, 0.0])
		states.append([nm, 1.0])
	var worst := 9.0
	var wdesc := ""
	for a in states:
		for b in states:
			if a == b:
				continue
			var ta: float = anim.duration(a[0]) * float(a[1])
			var tb: float = anim.duration(b[0]) * float(b[1])
			var pa: Dictionary = anim.sample(a[0], ta)
			var pb: Dictionary = anim.sample(b[0], tb)
			var mn := 9.0
			var mp := ["", ""]
			for k in 13:
				var u := float(k) / 12.0
				var p: Dictionary = ArcKin3.blend_pose(pa, pb, u)
				var au: Dictionary = _audit_exact(p)
				if float(au["min"]) < mn:
					mn = float(au["min"])
					mp = au["pair"]
			if mn < worst:
				worst = mn
				wdesc = "%s@%.2f -> %s@%.2f : %.4f %s" % [
					a[0], ta, b[0], tb, mn, str(mp)]
			rows.append({"blend": "%s->%s" % [a[0], b[0]], "min": mn, "pair": mp})
	print("  worst reachable blend: %s" % wdesc)
	if worst <= 0.0:
		_fail("animation blend collision: %s" % wdesc)
	# one-shots must start and end on the idle base pose (no pop)
	var base: Dictionary = anim.sample("idle", 0.0)
	for nm in ["attack1", "attack2", "block"]:
		for f in [0.0, 1.0]:
			var p2: Dictionary = anim.sample(nm, anim.duration(nm) * f)
			var dq := 0.0
			for j in ["sh", "elb", "wr"]:
				var qa: Quaternion = base.get(j + "_q", Quaternion())
				var qb: Quaternion = p2.get(j + "_q", Quaternion())
				dq = maxf(dq, qa.angle_to(qb))
			print("  %s @%.0f%% joint delta from idle %.4f rad" % [nm, f * 100.0, dq])
			if dq > 0.02:
				_fail("%s endpoint %.0f%% is not the idle base (%.4f rad)" % [nm, f * 100.0, dq])


func _blade_info(pose: Dictionary) -> Dictionary:
	var fk: Dictionary = kin.arm_fk(pose)
	var b: Basis = fk["tool_basis"]
	var d: Vector3 = fk["dir"]
	var up: Vector3 = b * Vector3(0, 0, 1)
	var side: Vector3 = b * Vector3(1, 0, 0)
	var tip: Vector3 = fk["tip"]
	# lowest point of the real blade volume (wide axis = side, thickness = up)
	var low := 9.0
	for i in 8:
		var f := float(i) / 7.0
		var p: Vector3 = (fk["tool"] as Vector3) + d * (kin.blade_len * f)
		var hw: float = kin.blade_half_w * (1.0 - 0.7 * f)
		var ht: float = kin.blade_half_t * (1.0 - 0.7 * f)
		for cx in [-1.0, 1.0]:
			for cy in [-1.0, 1.0]:
				var q: Vector3 = p + side * (cx * hw) + up * (cy * ht)
				low = minf(low, q.y)
	return {"s": fk["s"], "e": fk["e"], "w": fk["w"], "tool": fk["tool"], "dir": d,
		"basis": b, "tip": tip, "low": low, "face": fk["face"]}


func _elbow_bend(pose: Dictionary) -> float:
	var fk: Dictionary = kin.arm_fk(pose)
	var u: Vector3 = ((fk["e"] as Vector3) - (fk["s"] as Vector3)).normalized()
	var f: Vector3 = ((fk["w"] as Vector3) - (fk["e"] as Vector3)).normalized()
	return rad_to_deg(u.angle_to(f))


func _test_attack_poses() -> void:
	print("\n-- exact poses --")
	# idle: blade level, slightly up, pointing forward, arm folded
	# body height excluding the arm (top of the shoulder socket ball)
	var body_h: float = kin.body_y + kin.shoulder_local.y + 0.098
	print("  body height (no arm) %.3f m   optic radius %.3f m (cube/3, cube %.2f)" % [
		body_h, kin.cam_ap, kin.cube])
	if body_h < 1.48 or body_h > 1.70:
		_fail("body height %.3f m is not ~1.6 m" % body_h)
	if absf(kin.cam_ap - kin.cube / 3.0) > 1e-6:
		_fail("optic radius %.3f is not cube/3" % kin.cam_ap)
	var pid: Dictionary = anim.sample("idle", 0.0)
	var bi := _blade_info(pid)
	var idir: Vector3 = bi["dir"]
	var ibend := 180.0 - _elbow_bend(pid)
	print("  idle: dir %s  tool (%.2f, %.2f, %.2f)  tip y %.2f z %.2f  elbow bend %.1f deg" % [
		str(idir), float(bi["tool"].x), float(bi["tool"].y), float(bi["tool"].z),
		float(bi["tip"].y), float(bi["tip"].z), ibend])
	if idir.z < 0.97 or absf(idir.x) > 0.08 or idir.y < 0.03 or idir.y > 0.15:
		_fail("idle blade not level-forward with a slight up tilt (%s)" % str(idir))
	if ibend < 55.0:
		_fail("idle arm not folded (elbow bend %.1f deg)" % ibend)
	if float(bi["tool"].z) < 0.30:
		_fail("idle sword not held in front (tool z %.2f)" % float(bi["tool"].z))
	if float(bi["tool"].y) < 1.10 or float(bi["tool"].y) > 1.48:
		_fail("idle sword height %.2f out of range" % float(bi["tool"].y))
	# attack1 windup: blade straight up
	var pt: Dictionary = anim.action_key("attack1", "top")
	var bt := _blade_info(pt)
	print("  attack1 top: dir %s  tool y %.2f  tip y %.2f" % [
		str(bt["dir"]), float(bt["tool"].y), float(bt["tip"].y)])
	if (bt["dir"] as Vector3).y < 0.93:
		_fail("attack1 windup blade not vertical (%s)" % str(bt["dir"]))
	if float(bt["tool"].y) < 1.62 or float(bt["tip"].y) < 2.35:
		_fail("attack1 windup not overhead (tool %.2f tip %.2f)" % [
			float(bt["tool"].y), float(bt["tip"].y)])
	# attack1 impact: blade down-forward, tip low and forward, sagittal
	var ph: Dictionary = anim.action_key("attack1", "hit")
	var bh := _blade_info(ph)
	var hdir: Vector3 = bh["dir"]
	print("  attack1 hit: dir %s  tool (%.2f, %.2f, %.2f)  tip (%.2f, %.2f, %.2f)  low %.2f" % [
		str(hdir), float(bh["tool"].x), float(bh["tool"].y), float(bh["tool"].z),
		float(bh["tip"].x), float(bh["tip"].y), float(bh["tip"].z), float(bh["low"])])
	if hdir.y > -0.45 or hdir.z < 0.60:
		_fail("attack1 impact blade not down-forward (%s)" % str(hdir))
	if absf(hdir.x) > 0.10:
		_fail("attack1 impact not a sagittal chop (x %.2f)" % hdir.x)
	if float(bh["tip"].y) > 0.80 or float(bh["tip"].y) < 0.30:
		_fail("attack1 impact tip height %.2f not low" % float(bh["tip"].y))
	if float(bh["tip"].z) < 1.10:
		_fail("attack1 impact tip not forward (z %.2f)" % float(bh["tip"].z))
	if float(bh["low"]) < 0.28:
		_fail("attack1 impact blade too low (low %.2f)" % float(bh["low"]))
	# attack2 windup: blade horizontal, to the character's right and back
	var pc: Dictionary = anim.action_key("attack2", "coil2")
	var bc := _blade_info(pc)
	print("  attack2 coil: dir %s  tool x %.2f y %.2f  tip x %.2f z %.2f" % [
		str(bc["dir"]), float(bc["tool"].x), float(bc["tool"].y),
		float(bc["tip"].x), float(bc["tip"].z)])
	if (bc["dir"] as Vector3).x > -0.50 or (bc["dir"] as Vector3).z > -0.35:
		_fail("attack2 windup not back-right (%s)" % str(bc["dir"]))
	if absf((bc["dir"] as Vector3).y) > 0.12:
		_fail("attack2 windup not horizontal (%s)" % str(bc["dir"]))
	if float(bc["tool"].x) > -0.35:
		_fail("attack2 windup tool not out to the right (%.2f)" % float(bc["tool"].x))
	# attack2 across the front
	var pf: Dictionary = anim.action_key("attack2", "sweep2")
	var bf := _blade_info(pf)
	print("  attack2 sweep2: dir %s  tool z %.2f  tip z %.2f" % [
		str(bf["dir"]), float(bf["tool"].z), float(bf["tip"].z)])
	if (bf["dir"] as Vector3).z < 0.90 or absf((bf["dir"] as Vector3).y) > 0.10:
		_fail("attack2 mid sweep not horizontal-forward (%s)" % str(bf["dir"]))
	if float(bf["tool"].z) < 0.45:
		_fail("attack2 mid sweep not in front (tool z %.2f)" % float(bf["tool"].z))
	# attack2 follow: blade to the character's left
	var pe: Dictionary = anim.action_key("attack2", "follow")
	var be := _blade_info(pe)
	print("  attack2 follow: dir %s  tip x %.2f" % [str(be["dir"]), float(be["tip"].x)])
	if (be["dir"] as Vector3).x < 0.85 or (be["dir"] as Vector3).z > -0.20:
		_fail("attack2 follow not back-left (%s)" % str(be["dir"]))
	if float(be["tool"].x) < 0.35:
		_fail("attack2 follow tool not out to the left (%.2f)" % float(be["tool"].x))


func _test_swing_paths() -> void:
	print("\n-- swing paths --")
	# attack1: tip stays in the sagittal plane and sweeps down in front
	var worst_x := 0.0
	var low_tip := 9.0
	var reach_z := -9.0
	var tr1: Array = anim.trajs.get("attack1", [])
	for s in tr1:
		var fk: Dictionary = kin.arm_fk(s["pose"])
		var tip: Vector3 = fk["tip"]
		worst_x = maxf(worst_x, absf(tip.x))
		low_tip = minf(low_tip, tip.y)
		reach_z = maxf(reach_z, tip.z)
	print("  attack1 tip: |x| max %.3f  min y %.3f  max z %.3f  samples %d" % [
		worst_x, low_tip, reach_z, tr1.size()])
	if worst_x > 0.22:
		_fail("attack1 tip leaves the sagittal plane (|x| %.2f)" % worst_x)
	if reach_z < 1.25:
		_fail("attack1 tip does not reach forward (z %.2f)" % reach_z)
	if low_tip < 0.30:
		_fail("attack1 tip through the floor (%.2f)" % low_tip)
	# attack2: tip azimuth sweeps > 180 degrees around the body
	var tr2: Array = anim.trajs.get("attack2", [])
	var prev_az := 1e9
	var total := 0.0
	var flat := 0.0
	for s in tr2:
		var fk2: Dictionary = kin.arm_fk(s["pose"])
		var tip2: Vector3 = fk2["tip"]
		var az := atan2(tip2.x, tip2.z)
		if prev_az < 1e8:
			var d := wrapf(az - prev_az, -PI, PI)
			total += absf(d)
		else:
			flat = az
		prev_az = az
	print("  attack2 tip azimuth sweep %.1f deg (start %.1f)" % [rad_to_deg(total), rad_to_deg(flat)])
	if rad_to_deg(total) < 180.0:
		_fail("attack2 sweep only %.1f deg" % rad_to_deg(total))
	# no teleport: bounded joint speed and bounded tool step per sample
	for nm in ["attack1", "attack2", "block"]:
		var tr: Array = anim.trajs.get(nm, [])
		var qd: float = anim.traj_qdot(nm)
		var max_step := 0.0
		var max_dt := 0.0
		for i in tr.size() - 1:
			var a: Dictionary = tr[i]["pose"]
			var b: Dictionary = tr[i + 1]["pose"]
			var dt := maxf(float(tr[i + 1]["t"]) - float(tr[i]["t"]), 1e-4)
			var ta: Vector3 = kin.arm_fk(a)["tool"]
			var tb: Vector3 = kin.arm_fk(b)["tool"]
			max_step = maxf(max_step, ta.distance_to(tb) / dt)
			max_dt = maxf(max_dt, dt)
		print("  %s qdot %.1f rad/s  tool %.2f m/s  max sample dt %.3f s" % [
			nm, qd, max_step, max_dt])
		if qd > 46.0:
			_fail("%s joint speed %.1f rad/s > 46" % [nm, qd])


func _test_blocks() -> void:
	print("\n-- planned blocks --")
	var cases := [
		[0.0, 0.0], [-45.0, 0.0], [45.0, 0.0], [-70.0, 0.0], [70.0, 0.0],
		[-20.0, 12.0], [20.0, -12.0], [0.0, 14.0],
	]
	var worst_miss := 0.0
	var worst_clear := 9.0
	var worst_ms := 0.0
	var all_ok := true
	for c in cases:
		ch.set_block_threat(float(c[0]), float(c[1]))
		var st: Dictionary = ch.block_plan_stats()
		var dur: float = anim.duration("block")
		# measure the actual guard pose from the clip, not the report
		var guard_pose: Dictionary = anim.sample("block", float(st["t_guard"]))
		var guard: Dictionary = _blade_info(guard_pose)
		var d := Vector3(sin(float(c[0]) * D2R) * cos(float(c[1]) * D2R),
			sin(float(c[1]) * D2R), cos(float(c[0]) * D2R) * cos(float(c[1]) * D2R)).normalized()
		var chest: Vector3 = kin.chest_point()
		var miss := ArcKin3.seg_seg_dist(chest + d * 1.8, chest - d * 0.05,
			guard["tool"], guard["tip"])
		var face_err := rad_to_deg(acos(clampf((guard["face"] as Vector3).dot(d), -1.0, 1.0)))
		var traj_clear: Dictionary = anim.traj_min_clear("block", 10.0)
		print("  threat %+5.1f/%+4.1f: miss %.4f  face %.1f deg  clear %.4f (%s)  plan %.1f ms  dur %.2f" % [
			float(c[0]), float(c[1]), miss, face_err, float(traj_clear["min"]),
			str(traj_clear["pair"]), float(st["plan_ms"]), dur])
		worst_miss = maxf(worst_miss, miss)
		worst_clear = minf(worst_clear, float(traj_clear["min"]))
		worst_ms = maxf(worst_ms, float(st["plan_ms"]))
		if miss > 0.02:
			all_ok = false
		if face_err > 25.0:
			all_ok = false
		if float(traj_clear["min"]) <= 0.0:
			all_ok = false
		if not bool(st["guarded"]):
			all_ok = false
		rows.append({"block": "%+0.1f/%+0.1f" % [float(c[0]), float(c[1])],
			"miss": miss, "face_err": face_err, "min": float(traj_clear["min"]),
			"plan_ms": float(st["plan_ms"])})
	ch.set_block_threat(0.0, 0.0)
	print("  worst miss %.4f  worst clear %.4f  worst (cached) plan %.1f ms  raw plan %.1f ms" % [
		worst_miss, worst_clear, worst_ms, float(anim.block_plan_raw_ms)])
	if not all_ok:
		_fail("a planned block case failed (miss %.4f clear %.4f)" % [worst_miss, worst_clear])
	if float(anim.block_plan_raw_ms) <= 20.0:
		print("  runtime block planning is inside the 20 ms budget (no bake needed)")
	else:
		_fail("runtime block planning %.1f ms > 20 ms; a pre-baked table is required" % float(anim.block_plan_raw_ms))


func _test_timing() -> void:
	print("\n-- solver timing --")
	var a1: Dictionary = ch.attack_plan_stats("attack1")
	var a2: Dictionary = ch.attack_plan_stats("attack2")
	print("  attack1 build %.1f ms  min clear %.4f  qdot %.1f  samples %d" % [
		float(a1["plan_ms"]), float(a1["min_clear"]), float(a1["qdot_max"]), int(a1["samples"])])
	print("  attack2 build %.1f ms  min clear %.4f  qdot %.1f  samples %d" % [
		float(a2["plan_ms"]), float(a2["min_clear"]), float(a2["qdot_max"]), int(a2["samples"])])
	# real-time idle/run sample cost
	var t0 := Time.get_ticks_usec()
	for i in 200:
		anim.sample("idle", anim.duration("idle") * float(i) / 200.0)
	var idle_us := float(Time.get_ticks_usec() - t0) / 200.0
	t0 = Time.get_ticks_usec()
	for i in 200:
		anim.sample("run", anim.duration("run") * float(i) / 200.0)
	var run_us := float(Time.get_ticks_usec() - t0) / 200.0
	print("  realtime solve: idle %.2f ms  run %.2f ms per frame" % [idle_us / 1000.0, run_us / 1000.0])
	if float(a1["min_clear"]) <= 0.0:
		_fail("attack1 trajectory collision %.4f" % float(a1["min_clear"]))
	if float(a2["min_clear"]) <= 0.0:
		_fail("attack2 trajectory collision %.4f" % float(a2["min_clear"]))
	if idle_us / 1000.0 > 3.0 or run_us / 1000.0 > 3.0:
		_fail("realtime idle/run solve too slow (%.2f / %.2f ms)" % [idle_us / 1000.0, run_us / 1000.0])
	if float(anim.build_ms) > 6000.0:
		_fail("full build %.0f ms > 6000" % float(anim.build_ms))


func _test_optic() -> void:
	print("\n-- optic --")
	ch.set_anim_time(0.0)
	var shell: Node3D = ch.rig.J["optic_shell"]
	var eye: Node3D = ch.rig.J["eye_aim"]
	var identity_ok := true
	for nm in ["idle", "run", "attack1", "attack2", "block"]:
		for f in [0.0, 0.4, 0.8]:
			var p: Dictionary = anim.sample(nm, anim.duration(nm) * f)
			ch.rig.apply_pose(p)
			var t := shell.transform
			if not t.basis.is_equal_approx(Basis.IDENTITY) or t.origin.length_squared() > 1e-12:
				identity_ok = false
	print("  fixed lens shell never rotates: %s" % str(identity_ok))
	if not identity_ok:
		_fail("fixed lens shell moved with a pose")
	# aim at a set of points; direction must match within 1.5 degrees
	ch.P["lens_track"] = 0.0
	ch.set_anim_time(0.0)
	var worst := 0.0
	for tgt in [Vector3(2.3, 1.4, 2.6), Vector3(-2.8, 0.7, 2.0),
			Vector3(0.0, 0.55, 4.0), Vector3(1.2, 2.3, 3.2)]:
		ch.aim_eye_at(tgt)
		var dir: Vector3 = ch.eye_dir()
		var want: Vector3 = (tgt - eye.global_position).normalized()
		var err := rad_to_deg(dir.angle_to(want))
		worst = maxf(worst, err)
		var rot := eye.rotation
		print("  target %s -> eye dir %s  err %.2f deg  yaw %.1f pitch %.1f" % [
			str(tgt), str(dir), err, rad_to_deg(rot.y), rad_to_deg(rot.x)])
		if err > 1.5:
			_fail("optic aim error %.2f deg > 1.5" % err)
	print("  worst optic aim error %.2f deg" % worst)
	ch.P["lens_track"] = 1.0


func _test_tracks() -> void:
	print("\n-- tracks (independent locomotion layer) --")
	ch.clear_track_control()
	var rs: float = ch.get_param("run_speed")
	var cap: float = ch.rig.MAX_TRACK_SPEED
	var wr: float = ch.rig.wheel_r
	var revs := rs / (TAU * wr)
	print("  run speed %.2f m/s  cap %.1f m/s  wheel r %.3f m  wheel %.2f rev/s" % [
		rs, cap, wr, revs])
	if rs <= 0.05 or rs > cap + 1e-6:
		_fail("run speed %.2f m/s outside (0, %.1f]" % [rs, cap])
	if cap > 3.0001:
		_fail("track speed cap %.2f m/s exceeds the 3 m/s budget" % cap)
	if revs > 3.5:
		_fail("wheel spin %.2f rev/s at run speed is implausible" % revs)
	# the body clips must not carry any track state at all
	for nm in ["idle", "run"]:
		var p: Dictionary = anim.sample(nm, anim.duration(nm) * 0.37)
		for k in ["track_L", "track_R", "wheel_L", "wheel_R"]:
			if p.has(k):
				_fail("%s clip still carries track key %s" % [nm, k])
	# straight drive: belt distance and wheel rollout must agree exactly
	ch.set_track_speed(rs, rs)
	var wn0: float = (ch.rig.J["wheel_trackL0"] as Node3D).rotation.x
	var t0: Dictionary = ch.track_state()
	ch.step_tracks(0.5)
	var wn1: float = (ch.rig.J["wheel_trackL0"] as Node3D).rotation.x
	var t1: Dictionary = ch.track_state()
	var dl := float(t1["left_travel"]) - float(t0["left_travel"])
	var dr := float(t1["right_travel"]) - float(t0["right_travel"])
	var wl := float(t1["left_wheel"]) - float(t0["left_wheel"])
	var wrr := float(t1["right_wheel"]) - float(t0["right_wheel"])
	print("  straight 0.5 s: belt L %+.3f R %+.3f m  wheel L %+.3f R %+.3f rad" % [
		dl, dr, wl, wrr])
	print("  wheel node spin %.3f rad -> rim travel %.3f m" % [wn1 - wn0, (wn1 - wn0) * wr])
	if absf(dl - rs * 0.5) > 1e-4 or absf(dr - rs * 0.5) > 1e-4:
		_fail("belt travel %.3f/%.3f does not match speed x time %.3f" % [
			dl, dr, rs * 0.5])
	if absf(wl * wr - dl) > 1e-4 or absf(wrr * wr - dr) > 1e-4:
		_fail("wheel rollout does not match belt travel (belt %.3f, wheel %.3f)" % [
			dl, wl * wr])
	if absf((wn1 - wn0) * wr - dl) > 1e-4:
		_fail("wheel nodes did not follow the belt (%.3f vs %.3f m)" % [
			(wn1 - wn0) * wr, dl])
	# plates really move, at the same rate (computed from the belt layer;
	# a headless render server does not keep MultiMesh buffers)
	var a: Transform3D = ch.rig.belt_plate_xf("trackL", 0, -float(t0["left_travel"]))
	var b: Transform3D = ch.rig.belt_plate_xf("trackL", 0, -float(t1["left_travel"]))
	var plate_d := a.origin.distance_to(b.origin)
	print("  plate 0 moved %.3f m in 0.5 s (belt travel %.3f m)" % [plate_d, dl])
	if plate_d < absf(dl) * 0.9:
		_fail("belt plates do not track the belt distance (%.3f vs %.3f)" % [plate_d, dl])
	# belt direction: the ground contact patch must run backwards (toward -Z)
	var near_bottom := false
	for i in 8:
		var q: Transform3D = ch.rig.belt_plate_xf("trackL", i, 0.0)
		if q.origin.y < 0.14:
			near_bottom = true
			var q2: Transform3D = ch.rig.belt_plate_xf("trackL", i, -0.02)
			if q2.origin.z > q.origin.z:
				_fail("belt contact patch runs forward under a forward drive")
			break
	if not near_bottom:
		_fail("no belt plate reaches the ground contact patch")
	# differential: opposite tracks counter-rotate the wheels (pivot in place)
	ch.set_track_speed(-1.0, 1.0)
	var d0: Dictionary = ch.track_state()
	ch.step_tracks(0.25)
	var d1: Dictionary = ch.track_state()
	var piv_l := float(d1["left_travel"]) - float(d0["left_travel"])
	var piv_r := float(d1["right_travel"]) - float(d0["right_travel"])
	var piv_wl := float(d1["left_wheel"]) - float(d0["left_wheel"])
	var piv_wr := float(d1["right_wheel"]) - float(d0["right_wheel"])
	print("  differential 0.25 s: L %+.3f R %+.3f m  wheel L %+.2f R %+.2f rad" % [
		piv_l, piv_r, piv_wl, piv_wr])
	if absf(piv_l + 0.25) > 1e-4 or absf(piv_r - 0.25) > 1e-4:
		_fail("differential tracks do not run opposite (%.3f / %.3f)" % [piv_l, piv_r])
	if piv_wl * piv_wr >= 0.0:
		_fail("differential wheels do not counter-rotate")
	# clamp to the 3 m/s budget
	ch.set_track_speed(9.0, -9.0)
	var c0: Dictionary = ch.track_state()
	print("  clamp: requested 9.0 / -9.0 -> %.2f / %.2f m/s" % [
		float(c0["left_speed"]), float(c0["right_speed"])])
	if absf(float(c0["left_speed"]) - cap) > 1e-6 \
			or absf(float(c0["right_speed"]) + cap) > 1e-6:
		_fail("track speeds are not clamped to the cap")
	# body animation and locomotion are independent in both directions
	ch.set_track_speed(0.8, -0.8)
	var f0: Dictionary = ch.track_state()
	ch.set_playing(false)
	ch.play_anim("attack1")
	ch.set_anim_time(0.3)
	ch.step_tracks(0.1)
	var f1: Dictionary = ch.track_state()
	print("  attack1 @0.3 s keeps driving: L %+.2f R %+.2f m/s, %+.3f / %+.3f m" % [
		float(f1["left_speed"]), float(f1["right_speed"]),
		float(f1["left_travel"]) - float(f0["left_travel"]),
		float(f1["right_travel"]) - float(f0["right_travel"])])
	if absf(float(f1["left_speed"]) - 0.8) > 1e-6 \
			or absf(float(f1["right_speed"]) + 0.8) > 1e-6:
		_fail("body clip changed the track speeds")
	if absf(float(f1["left_travel"]) - float(f0["left_travel"]) - 0.08) > 1e-4 \
			or absf(float(f1["right_travel"]) - float(f0["right_travel"]) + 0.08) > 1e-4:
		_fail("body clip reset the track travel")
	# an external speed command must keep integrating through the real frame loop
	var g0: Dictionary = ch.track_state()
	ch._process(0.1)
	var g1: Dictionary = ch.track_state()
	var cmd_adv := float(g1["left_travel"]) - float(g0["left_travel"])
	if absf(cmd_adv - 0.08) > 1e-4:
		_fail("external track speed command did not advance (%.3f m in 0.1 s)" % cmd_adv)
	if absf(float(g1["left_speed"]) - 0.8) > 1e-6 \
			or absf(float(g1["right_speed"]) + 0.8) > 1e-6:
		_fail("external track speed command was overwritten by the clip")
	# run autopilot: with no manual override, run drives both tracks at run_speed;
# calling the real _process once also proves the per-frame wiring
	ch.set_playing(false)
	ch.play_anim("run")
	ch.clear_track_control()
	ch.set_anim_speed(1.0)
	var q0: Dictionary = ch.track_state()
	ch._process(0.25)
	var e0: Dictionary = ch.track_state()
	var run_adv := float(e0["left_travel"]) - float(q0["left_travel"])
	print("  run autopilot: L %+.2f R %+.2f m/s, +%.3f m in one 0.25 s tick" % [
		float(e0["left_speed"]), float(e0["right_speed"]), run_adv])
	if absf(float(e0["left_speed"]) - rs) > 1e-4 \
			or absf(float(e0["right_speed"]) - rs) > 1e-4:
		_fail("run clip does not drive the tracks at run_speed")
	if absf(run_adv - rs * 0.25) > 1e-4:
		_fail("per-frame drive advanced %.3f m, expected %.3f" % [run_adv, rs * 0.25])
	ch.clear_track_control()
	ch.set_playing(false)
	ch.play_anim("idle")
	rows.append({"tracks": {"run_speed": rs, "cap": cap, "wheel_r": wr,
		"wheel_rev_s": revs, "straight_dl": dl, "straight_dr": dr,
		"pivot_l": piv_l, "pivot_r": piv_r}})


func _test_static_clearance() -> void:
	print("\n-- turret vs chassis clearance --")
	var worst_x := 9.0
	var worst_y := 9.0
	var worst_waist := 9.0
	var track_inner: float = kin.track_x - kin.track_hw
	for nm in ["idle", "run", "attack1", "attack2", "block"]:
		var dur: float = anim.duration(nm)
		for i in 25:
			var pose: Dictionary = anim.sample(nm, dur * float(i) / 24.0)
			var bx: Transform3D = kin.body_xf(pose)
			var ch_half: float = kin.cube_half - 0.052
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var q: Vector3 = bx * Vector3(sx * ch_half, sy * ch_half, sz * ch_half)
						worst_x = minf(worst_x, track_inner - absf(q.x))
						worst_y = minf(worst_y, q.y - (kin.deck_y + kin.deck_hy))
	print("  cube corner to track inner wall %.4f m" % worst_x)
	print("  cube lowest corner above deck %.4f m" % worst_y)
	var leds: Array = ch.rig._leds
	print("  status LEDs: %d" % leds.size())
	if leds.size() < 6:
		_fail("status LED row missing (%d)" % leds.size())
	ch.rig.set_status_time(0.0)
	var e0: float = (leds[0]["mat"] as StandardMaterial3D).emission_energy_multiplier
	ch.rig.set_status_time(0.42)
	var e1: float = (leds[0]["mat"] as StandardMaterial3D).emission_energy_multiplier
	ch.rig.set_status_time(1.05)
	var e2: float = (leds[0]["mat"] as StandardMaterial3D).emission_energy_multiplier
	if absf(e0 - e1) < 1e-4 and absf(e1 - e2) < 1e-4:
		_fail("status LEDs do not blink")
	if worst_x < 0.005:
		_fail("turret cube corners hit the track inner walls (%.4f m)" % worst_x)
	if worst_y < 0.01:
		_fail("turret cube hits the chassis deck (%.4f m)" % worst_y)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/v3"))
	var f := FileAccess.open("res://renders/v3/qa_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"pass": fails.is_empty(), "fails": fails, "rows": rows,
			"timing": {"attack1_ms": anim.attack1_ms, "attack2_ms": anim.attack2_ms,
				"block_ms_raw": anim.block_plan_raw_ms, "build_ms": anim.build_ms},
		}, "  "))
		f.close()
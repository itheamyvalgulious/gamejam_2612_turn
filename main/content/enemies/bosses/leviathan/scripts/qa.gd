extends Node3D
## LEVIATHAN headless acceptance suite.
##
## Runs deterministic fixed-dt scenarios against scenes/character.tscn and
## measures the contract the design is judged on:
##   * 8 idle limbs: large waving, mutual + self clearance, smoothness
##   * 5 support limbs under a 1.2 m circular body motion: planted feet,
##     constant limb length, mutual clearance, non-straight (bent) shape
##   * attack 1 / 2 on randomly placed targets: exact line / over-then-down
##   * attack 3: large horizontal sweep
##   * scheduler: <=2 attacks, <=5 support, 2 re-tasks every 2 s
##   * phase 2 at 3 limbs: shell open, core, glass, laser hits the target
## Writes renders/qa_report.json. Exit code 0 = PASS.

const BOSS := preload("res://scenes/character.tscn")
const TENT := preload("res://scripts/boss/tentacle.gd")
const D2R := PI / 180.0
const TAU := PI * 2.0
const N := 40

var boss
var checks: Array = []
var metrics: Dictionary = {}
var _out := ""


func _ready() -> void:
	boss = BOSS.instantiate()
	add_child(boss)
	await _frames(3)
	boss.manual = true
	boss.set_auto(false)
	boss.set_process(false)
	_out = ProjectSettings.globalize_path("res://renders")
	DirAccess.make_dir_recursive_absolute(_out)

	var t0 := Time.get_ticks_msec()
	_test_idle()
	_test_support_circle()
	_test_attacks()
	_test_scheduler()
	_test_phase_laser()
	_test_support_floor()
	_test_cut_explosion()
	_test_perf()
	var total := (Time.get_ticks_msec() - t0) / 1000.0
	metrics["elapsed_s"] = total

	var passed := true
	var fails := 0
	for c in checks:
		if not c["ok"]:
			fails += 1
			passed = false
	var report := {
		"pass": passed, "failures": fails, "checks": checks, "metrics": metrics,
		"generated": Time.get_datetime_string_from_system(),
	}
	var f := FileAccess.open(_out.path_join("qa_report.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("\n================ LEVIATHAN QA ================")
	for c in checks:
		print("%s  %-34s  %s" % ["PASS" if c["ok"] else "FAIL", c["name"], c["detail"]])
	print("-----------------------------------------------")
	print("%d checks, %d failures, %.1f s" % [checks.size(), fails, total])
	print("VERDICT: %s" % ("PASS" if passed else "FAIL"))
	print("===============================================\n")
	get_tree().quit(0 if passed else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ------------------------------------------------------------------ helpers

func _ck(name: String, ok: bool, detail: String) -> void:
	checks.append({"name": name, "ok": ok, "detail": detail})
	if not ok:
		print("[qa] FAIL ", name, " :: ", detail)


func _reset(roles: Array, motion := "free") -> void:
	boss.reset_boss()
	boss.manual = true
	boss.set_auto(false)
	boss.set_process(false)
	boss.set_motion_mode(motion, 1.2, 10.0)
	# reset_boss leaves even limbs supporting; force the requested set
	for i in 8:
		boss.force_role(i, "idle")
	for i in roles.size():
		if roles[i] != "idle":
			boss.force_role(i, roles[i])


func _step(n: int) -> void:
	for i in n:
		boss.sim_step(1.0 / 60.0)


func _tips() -> Array:
	var out: Array = []
	for i in 8:
		var tn = boss.tents[i]
		out.append(tn.pts[tn.pts.size() - 1] if tn.pts.size() > 0 else Vector3.ZERO)
	return out


func _seg_dist(p1: Vector3, p2: Vector3, q1: Vector3, q2: Vector3) -> float:
	var d1 := p2 - p1
	var d2 := q2 - q1
	var r := p1 - q1
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return p1.distance_to(q1)
	if a <= 1e-9:
		s = 0.0
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var denom := a * e - bb * bb
			if absf(denom) > 1e-9:
				s = clampf((bb * f - c * e) / denom, 0.0, 1.0)
			else:
				s = 0.0
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / a, 0.0, 1.0)
	var c1 := p1 + d1 * s
	var c2 := q1 + d2 * t
	return c1.distance_to(c2)


func _pair_clearance(A, B, stride := 2) -> float:
	var best := 1e9
	var pa: PackedVector3Array = A.pts
	var pb: PackedVector3Array = B.pts
	if pa.size() < 3 or pb.size() < 3:
		return best
	var i := 0
	while i < N - 1:
		var j := 0
		while j < N - 1:
			var d := _seg_dist(pa[i], pa[i + 1], pb[j], pb[j + 1])
			d -= (A.radii[i] + A.radii[i + 1] + B.radii[j] + B.radii[j + 1]) * 0.25
			if d < best:
				best = d
			j += stride
		i += stride
	return best


func _self_clearance(A) -> float:
	var best := 1e9
	var p: PackedVector3Array = A.pts
	for i in range(0, N - 2):
		for j in range(i + 6, N - 1):
			var d := _seg_dist(p[i], p[i + 1], p[j], p[j + 1])
			d -= (A.radii[i] + A.radii[i + 1] + A.radii[j] + A.radii[j + 1]) * 0.25
			if d < best:
				best = d
	return best


func _all_clearances(stride := 2) -> Dictionary:
	var pair := 1e9
	var selfc := 1e9
	var body := 1e9
	var ground := 1e9
	var pair_names := ["", ""]
	var c: Vector3 = boss.body_center
	var alive: Array = []
	for i in 8:
		if boss.tents[i].alive:
			alive.append(i)
	for ai in range(alive.size()):
		var A = boss.tents[alive[ai]]
		var sc := _self_clearance(A)
		if sc < selfc:
			selfc = sc
		for bi in range(ai + 1, alive.size()):
			var B = boss.tents[alive[bi]]
			var d := _pair_clearance(A, B, stride)
			if d < pair:
				pair = d
				pair_names = ["T%d" % (alive[ai] + 1), "T%d" % (alive[bi] + 1)]
		for k in range(3, N):
			var bd: float = (A.pts[k] - c).length() - 2.0 - A.radii[k]
			if bd < body:
				body = bd
			var gd: float = A.pts[k].y - A.radii[k] - 0.02
			if gd < ground:
				ground = gd
	return {"pair": pair, "self": selfc, "body": body, "ground": ground,
		"pair_names": pair_names}


func _tip_motion_stats(tn) -> Dictionary:
	return {"tip": tn.pts[N - 1]}


func _bend(tn) -> float:
	var p: PackedVector3Array = tn.pts
	var a := p[0]
	var b := p[N - 1]
	var chord := b - a
	var cl := chord.length()
	if cl < 0.1:
		return 0.0
	var best := 0.0
	for i in range(1, N - 1):
		var rel := p[i] - a
		var perp := rel - chord * (rel.dot(chord) / (cl * cl))
		best = maxf(best, perp.length())
	return best


# --------------------------------------------------------------- idle test

func _test_idle() -> void:
	_reset(["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle"])
	_step(120)
	var min_pair := 1e9
	var min_pair_names := ["", ""]
	var min_self := 1e9
	var min_body := 1e9
	var min_ground := 1e9
	var tip_min: Array[Vector3] = []
	var tip_max: Array[Vector3] = []
	var tip_prev: Array[Vector3] = []
	var max_jump := 0.0
	var max_speed := 0.0
	for i in 8:
		var p: Vector3 = boss.tents[i].pts[N - 1]
		tip_min.append(p)
		tip_max.append(p)
		tip_prev.append(p)
	var samples := 0
	for s in 240:  # 12 s at 20 Hz
		_step(3)
		samples += 1
		var cl := _all_clearances(2)
		if cl["pair"] < min_pair:
			min_pair = cl["pair"]
			min_pair_names = cl["pair_names"]
		min_self = minf(min_self, cl["self"])
		min_body = minf(min_body, cl["body"])
		min_ground = minf(min_ground, cl["ground"])
		for i in 8:
			var p2: Vector3 = boss.tents[i].pts[N - 1]
			tip_min[i] = Vector3(minf(tip_min[i].x, p2.x), minf(tip_min[i].y, p2.y), minf(tip_min[i].z, p2.z))
			tip_max[i] = Vector3(maxf(tip_max[i].x, p2.x), maxf(tip_max[i].y, p2.y), maxf(tip_max[i].z, p2.z))
			var jump := p2.distance_to(tip_prev[i])
			max_jump = maxf(max_jump, jump)
			max_speed = maxf(max_speed, jump * 20.0)  # samples at 20 Hz
			tip_prev[i] = p2
	var min_range := 1e9
	var min_y_range := 1e9
	for i in 8:
		var dxz := Vector2(tip_max[i].x - tip_min[i].x, tip_max[i].z - tip_min[i].z).length()
		var dy: float = tip_max[i].y - tip_min[i].y
		var r3: float = (tip_max[i] - tip_min[i]).length()
		print("[qa] idle T%d range3d=%.2f xz=%.2f y=%.2f role=%s" % [i + 1, r3, dxz, dy,
			boss.tents[i].role])
		min_range = minf(min_range, r3)
		min_y_range = minf(min_y_range, dy)
	var worst_exit := 0.0
	for i in 8:
		var tn = boss.tents[i]
		var rel: Vector3 = tn.pts[1] - tn.base
		var ang := rad_to_deg(acos(clampf(rel.normalized().dot(tn.base_dir_w), -1.0, 1.0)))
		worst_exit = maxf(worst_exit, ang)
	_ck("idle: leaves through the socket hole", worst_exit < 8.0,
		"worst first-segment angle %.1f deg" % worst_exit)
	metrics["idle"] = {"socket_exit_deg": worst_exit, "min_pair_clear": min_pair, "min_self_clear": min_self,
		"min_body_clear": min_body, "min_ground_clear": min_ground,
		"min_tip_xz_range": min_range, "min_tip_y_range": min_y_range,
		"max_tip_speed_20hz": max_speed}
	_ck("idle: mutual clearance", min_pair > 0.0,
		"min %.3f m between capsules (%s/%s)" % [min_pair, min_pair_names[0], min_pair_names[1]])
	_ck("idle: self clearance", min_self > 0.0, "min %.3f m" % min_self)
	_ck("idle: body clearance", min_body > 0.0, "min %.3f m" % min_body)
	_ck("idle: ground clearance", min_ground > -0.02, "min %.3f m" % min_ground)
	_ck("idle: large waving", min_range > 2.2,
		"min tip 3D range %.2f m (min y range %.2f)" % [min_range, min_y_range])
	_ck("idle: continuous speed", max_speed < 30.0,
		"max tip speed %.1f m/s at 20 Hz" % max_speed)


# ------------------------------------------------------------ support test

func _test_support_circle() -> void:
	_reset(["support", "support", "support", "support", "support", "idle", "idle", "idle"], "circle")
	_step(240)  # plant + settle at full height
	var min_pair := 1e9
	var min_pair_names := ["", ""]
	var min_self := 1e9
	var min_ground := 1e9
	var max_pin := 0.0
	var min_len := 1e9
	var max_len := 0.0
	var mean_len := 0.0
	var n_len := 0
	var min_bend := 1e9
	var per_min: Array = []
	var per_max: Array = []
	for i in 8:
		per_min.append(1e9)
		per_max.append(0.0)
	var cx0: float = boss.body_center.x
	var cz0: float = boss.body_center.z
	var max_r := 0.0
	var max_jump := 0.0
	var prev_tips: Array = _tips()
	var samples := 0
	for s in 220:  # 22 s at 10 Hz (two circles)
		_step(6)
		samples += 1
		var cl := _all_clearances(2)
		if cl["pair"] < min_pair:
			min_pair = cl["pair"]
			min_pair_names = cl["pair_names"]
		min_self = minf(min_self, cl["self"])
		min_ground = minf(min_ground, cl["ground"])
		max_r = maxf(max_r, Vector2(boss.body_center.x, boss.body_center.z).length())
		for i in 8:
			var tn = boss.tents[i]
			if tn.role == "support" and tn.foot_valid:
				var pin: float = tn.pts[N - 1].distance_to(tn.foot)
				max_pin = maxf(max_pin, pin)
				var ln: float = tn.spine_length()
				min_len = minf(min_len, ln)
				max_len = maxf(max_len, ln)
				mean_len += ln
				n_len += 1
				per_min[i] = minf(per_min[i], ln)
				per_max[i] = maxf(per_max[i], ln)
				min_bend = minf(min_bend, _bend(tn))
			var j: float = tn.pts[N - 1].distance_to(prev_tips[i])
			max_jump = maxf(max_jump, j)
			prev_tips[i] = tn.pts[N - 1]
	mean_len /= float(maxi(n_len, 1))
	var var_pct := 0.0
	var var_worst := -1
	for i in 8:
		if per_max[i] <= 0.0:
			continue
		var mid: float = (per_max[i] + per_min[i]) * 0.5
		var pct: float = (per_max[i] - per_min[i]) / maxf(mid, 0.001) * 100.0
		if pct > var_pct:
			var_pct = pct
			var_worst = i
	metrics["support_circle"] = {"min_pair_clear": min_pair, "min_self_clear": min_self,
		"min_ground_clear": min_ground, "max_foot_pin_error": max_pin,
		"len_min": min_len, "len_max": max_len, "len_mean": mean_len,
		"len_variation_pct": var_pct, "min_bend": min_bend,
		"body_circle_radius": max_r, "max_tip_jump_10hz": max_jump}
	_ck("support: mutual clearance", min_pair > 0.0,
		"min %.3f m (%s/%s)" % [min_pair, min_pair_names[0], min_pair_names[1]])
	_ck("support: self clearance", min_self > 0.0, "min %.3f m" % min_self)
	_ck("support: ground clearance", min_ground > -0.02, "min %.3f m" % min_ground)
	_ck("support: feet pinned", max_pin < 0.02, "max slip %.4f m" % max_pin)
	_ck("support: constant length", var_pct < 3.0,
		"worst T%d %.2f%% (all %.3f..%.3f m)" % [var_worst + 1, var_pct, min_len, max_len])
	_ck("support: bent, not a strut", min_bend > 0.35, "min bend %.2f m" % min_bend)
	_ck("support: body circular motion", max_r > 0.8,
		"circle radius %.2f m" % max_r)


# ------------------------------------------------------------- attack tests

func _test_attacks() -> void:
	# start from a stable idle stance
	_reset(["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle"])
	_step(90)
	for trial in 3:
		var g := Vector3(-6.0 + 6.0 * float(trial), 0.0, 12.0 + 2.0 * float(trial))
		boss.set_target(g + Vector3(0, 1.15, 0), g)
		# --- attack 1
		_reset(["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle"])
		boss.set_target(g + Vector3(0, 1.15, 0), g)
		_step(30)
		boss.force_role(2, "attack1")
		var tn = boss.tents[2]
		var line_o: Vector3 = tn.attack_start_tip
		var line_t: Vector3 = tn.attack_target
		var dir: Vector3 = tn.attack_dir
		var max_perp := 0.0
		var min_hit := 1e9
		var reached := false
		var orient1 := 0.0
		for s in 110:
			boss.sim_step(1.0 / 60.0)
			if tn.role == "attack" and tn.attack_kind == 1:
				if tn.attack_t > 0.30 and tn.attack_t < 0.70:
					var rel: Vector3 = tn.pts[N - 1] - line_o
					var perp := (rel - dir * rel.dot(dir)).length()
					max_perp = maxf(max_perp, perp)
				if tn.attack_t > 0.50 and tn.attack_t < 0.62:
					var seg: Vector3 = (tn.pts[N - 1] - tn.pts[N - 2]).normalized()
					orient1 = maxf(orient1, seg.dot(dir))
				var d: float = tn.pts[N - 1].distance_to(line_t)
				min_hit = minf(min_hit, d)
				if d < 0.4:
					reached = true
		_ck("attack1 #%d: line thrust" % trial, max_perp < 0.20,
			"max line deviation %.3f m" % max_perp)
		_ck("attack1 #%d: tip pre-aimed" % trial, orient1 > 0.90,
			"last-segment dot %.3f" % orient1)
		_ck("attack1 #%d: reaches target" % trial, reached and min_hit < 0.30,
			"closest tip %.3f m" % min_hit)
		_ck("attack1 #%d: attack cap" % trial, _count_attacks() <= 2,
			"%d attacks" % _count_attacks())

		# --- attack 2
		_reset(["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle"])
		boss.set_target(g + Vector3(0, 1.15, 0), g)
		_step(30)
		boss.force_role(2, "attack2")
		var tn2 = boss.tents[2]
		var over: Vector3 = tn2.attack_over
		var max_above := -1e9
		var min_d := 1e9
		var went_over := false
		var plunged := false
		var orient2 := 0.0
		for s in 150:
			boss.sim_step(1.0 / 60.0)
			if tn2.role == "attack" and tn2.attack_kind == 2:
				var tip: Vector3 = tn2.pts[N - 1]
				max_above = maxf(max_above, tip.y - boss.target_chest.y)
				if tip.distance_to(over) < 1.0:
					went_over = true
				if went_over and tip.y < boss.target_chest.y + 0.5:
					plunged = true
				if tn2.attack_t > 1.02 and tn2.attack_t < 1.18:
					var seg2: Vector3 = (tn2.pts[N - 1] - tn2.pts[N - 2]).normalized()
					orient2 = maxf(orient2, -seg2.y)
				min_d = minf(min_d, tip.distance_to(boss.target_chest))
		_ck("attack2 #%d: reaches overhead" % trial, went_over and max_above > 3.0,
			"max above target %.2f m" % max_above)
		_ck("attack2 #%d: tip points down" % trial, orient2 > 0.90,
			"down dot %.3f" % orient2)
		_ck("attack2 #%d: plunges down" % trial, plunged and min_d < 0.35,
			"closest tip %.3f m" % min_d)

		# --- attack 3
		_reset(["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle"])
		_step(30)
		boss.force_role(2, "attack3")
		var tn3 = boss.tents[2]
		var az0 := 999.0
		var az_lo := 999.0
		var az_hi := -999.0
		var az_last := 999.0
		var unwrapped := 0.0
		var max_rad := 0.0
		var max_h := 0.0
		var band_dev := 0.0
		var band_min_r := 999.0
		var band_wi := -1
		var band_wt := 0.0
		for s in 430:
			boss.sim_step(1.0 / 60.0)
			if tn3.role == "attack" and tn3.attack_kind == 3:
				var tip3: Vector3 = tn3.pts[N - 1]
				var c: Vector3 = boss.body_center
				if tn3.attack_t >= 1.90 and tn3.attack_t < 5.50:
					var az := atan2(tip3.x - c.x, tip3.z - c.z)
					if az0 > 998.0:
						az0 = az
					else:
						var d := wrapf(az - az_last, -PI, PI)
						unwrapped += d
					az_last = az
					az_lo = minf(az_lo, az0 + unwrapped)
					az_hi = maxf(az_hi, az0 + unwrapped)
					var rr3 := Vector2(tip3.x - c.x, tip3.z - c.z).length()
					max_rad = maxf(max_rad, rr3)
					max_h = maxf(max_h, tip3.y)
					for pi in N:
						var pp: Vector3 = tn3.pts[pi]
						var pr := Vector2(pp.x - c.x, pp.z - c.z).length()
						if pr > 4.2:
							var dv := absf(pp.y - boss.P["attack3_height"])
							if dv > band_dev:
								band_dev = dv
								band_wi = pi
								band_wt = tn3.attack_t
							band_min_r = minf(band_min_r, pr)
		var sweep_deg := (az_hi - az_lo) / D2R
		_ck("attack3 #%d: full 360 sweep" % trial, sweep_deg > 300.0 and max_rad > 12.5,
			"%.0f deg at r %.1f m, h %.1f m" % [sweep_deg, max_rad, max_h])
		_ck("attack3 #%d: whole distal limb at 1 m" % trial,
			band_dev < 0.15 and band_min_r < 5.2,
			"max height dev %.3f m at i=%d t=%.2f, flat from r %.1f m" % [band_dev, band_wi, band_wt, band_min_r])
		metrics["attack%d" % trial] = {"sweep_deg": sweep_deg, "sweep_radius": max_rad,
			"a1_hit": min_hit, "a2_above": max_above, "a2_hit": min_d, "a3_deg": sweep_deg}


func _count_attacks() -> int:
	var n := 0
	for i in 8:
		if boss.tents[i].alive and boss.tents[i].role == "attack":
			n += 1
	return n


# ------------------------------------------------------------ scheduler test

func _test_scheduler() -> void:
	boss.reset_boss()
	boss.manual = true
	boss.set_process(false)
	boss.set_auto(true)
	boss.set_param("role_period", 2.0)
	var max_atk := 0
	var max_sup := 0
	var min_sup := 99
	var violations := 0
	var changes := 0
	var cycles := 0
	var prev_roles: Array = []
	for i in 8:
		prev_roles.append(boss.tents[i].role)
	var prev_cycle := 0
	for s in 1800:  # 30 s
		boss.sim_step(1.0 / 60.0)
		var a := _count_attacks()
		var sp := 0
		for i in 8:
			if boss.tents[i].alive and boss.tents[i].role == "support":
				sp += 1
		max_atk = maxi(max_atk, a)
		max_sup = maxi(max_sup, sp)
		min_sup = mini(min_sup, sp)
		if a > int(boss.get_param("attack_max")) or sp > int(boss.get_param("support_max")):
			violations += 1
		var cyc := int(boss.t / 2.0)
		if cyc != prev_cycle:
			var changed := 0
			for i in 8:
				if boss.tents[i].role != prev_roles[i]:
					changed += 1
				prev_roles[i] = boss.tents[i].role
			if changed >= 1:
				changes += 1
			cycles += 1
			prev_cycle = cyc
	metrics["scheduler"] = {"max_attacks": max_atk, "max_support": max_sup,
		"min_support": min_sup, "cap_violations": violations,
		"cycles": cycles, "cycles_with_change": changes}
	_ck("scheduler: <= 2 attacks", max_atk <= 2, "max %d" % max_atk)
	_ck("scheduler: <= 5 support", max_sup <= 5, "max %d" % max_sup)
	_ck("scheduler: cap violations", violations == 0, "%d frames" % violations)
	_ck("scheduler: roles rotate", changes >= maxi(1, cycles - 3),
		"%d/%d cycles changed" % [changes, cycles])


# --------------------------------------------------------- phase + laser

func _test_phase_laser() -> void:
	boss.reset_boss()
	boss.manual = true
	boss.set_process(false)
	boss.set_auto(false)
	boss.set_target(Vector3(2.0, 1.15, 13.0), Vector3(2.0, 0, 13.0))
	boss.set_phase_force(1)
	_step(30)
	var shell1: float = boss.shell_t
	var ap1: float = boss.rig.aperture_half_angle()
	var covered1: bool = boss.phase == 1
	boss.set_phase_force(0)
	# cut down to three limbs, automatic phase 2
	for i in 5:
		boss.cut_tentacle(i)
	_step(300)  # 5 s: cut, shell open, core ignites
	var shell2: float = boss.shell_t
	var ap2: float = boss.rig.aperture_half_angle()
	var core2: float = boss.phase2_t
	var live2: int = boss.live
	_ck("phase: starts sealed", covered1 and shell1 < 0.45 and ap1 < 45.0,
		"captured phase-1 shell %.2f aperture %.1f deg" % [shell1, ap1])
	_ck("phase: 3 limbs -> phase 2", live2 == 3 and boss.phase == 2,
		"live %d phase %d" % [live2, boss.phase])
	_ck("phase: shell fully opens", shell2 > 0.90 and ap2 > 85.0,
		"shell %.2f aperture %.1f deg" % [shell2, ap2])
	_ck("phase: core exposed", core2 > 0.75, "core %.2f" % core2)
	_ck("phase: glass wall visible", boss.rig.glass_mi.visible,
		"glass opacity on")
	# laser
	boss.set_target(boss.tents[0].foot + Vector3(2.0, 1.3, 8.0),
		boss.tents[0].foot + Vector3(2.0, 0.0, 8.0))
	boss.fire_laser()
	var firing := false
	var max_beam := 0.0
	var tip_ok := false
	for s in 180:
		boss.sim_step(1.0 / 60.0)
		if boss.laser_state == "fire" or boss.beam_dist > 0.1:
			firing = true
			max_beam = maxf(max_beam, boss.beam_dist)
			var dir: Vector3 = (boss.target_chest - boss.body_center).normalized()
			var origin: Vector3 = boss.body_center + dir * (1.05 + 0.45 * boss.phase2_t)
			var hitp: Vector3 = origin + dir * boss.beam_dist
			if hitp.distance_to(boss.target_chest) < 0.35:
				tip_ok = true
	_ck("laser: fires when fully open", firing and max_beam > 4.0,
		"beam length %.1f m" % max_beam)
	_ck("laser: terminates on target", tip_ok, "end point within 0.35 m")
	metrics["phase_laser"] = {"shell1": shell1, "aperture1": ap1,
		"shell2": shell2, "aperture2": ap2, "core2": core2,
		"live_after_cuts": live2, "beam_len": max_beam, "beam_on_target": tip_ok}


# ----------------------------------------------- support floor + fallen body

func _test_support_floor() -> void:
	boss.reset_boss()
	boss.manual = true
	boss.set_process(false)
	boss.set_auto(true)
	boss.set_phase_force(1)
	for i in 8:
		boss.force_role(i, "idle")
	for i in 3:
		boss.force_role(i, "support")
	_step(60)
	# cut two of the three supports
	boss.cut_tentacle(0)
	boss.cut_tentacle(1)
	_step(60)
	var sup: int = boss._count_role("support")
	var idle: int = boss._count_role("idle")
	_ck("support floor: idle limbs fill in", sup >= 3 and idle >= 1,
		"%d support / %d idle after cutting two supports" % [sup, idle])
	var h_stand: float = boss.body_center.y
	# cut down below three limbs
	var guard := 0
	while boss.live > 2 and guard < 12:
		var cut_one := false
		for i in 8:
			if boss.live > 2 and boss.tents[i].alive and boss.tents[i].role != "explode":
				cut_one = boss.cut_tentacle(i)
				if cut_one:
					break
		guard += 1
		if not cut_one:
			_step(30)
	_step(240)
	var attacks := 0
	var alive := 0
	for i in 8:
		if boss.tents[i].alive:
			alive += 1
			if boss.tents[i].role == "attack":
				attacks += 1
	var h_fall: float = boss.body_center.y
	_ck("fallen: below three limbs", boss.live < 3 and alive < 3,
		"live %d" % boss.live)
	_ck("fallen: sphere drops to the ground", h_fall < 2.35 and h_stand > 5.0,
		"body %.2f m -> %.2f m" % [h_stand, h_fall])
	_ck("fallen: all remaining limbs attack", attacks == alive and alive >= 1,
		"%d/%d attacking" % [attacks, alive])
	metrics["support_floor"] = {"support_after_cuts": sup, "idle_after_cuts": idle,
		"stand_h": h_stand, "fallen_h": h_fall, "live": boss.live,
		"attacks": attacks}


# ------------------------------------------------------- cut explosion order

func _test_cut_explosion() -> void:
	boss.reset_boss()
	boss.manual = true
	boss.set_process(false)
	boss.set_auto(false)
	for i in 8:
		boss.force_role(i, "idle")
	_step(90)
	var tn = boss.tents[0]
	var total: float = tn.spine_length()
	var ok: bool = boss.cut_tentacle(0)
	_step(1)
	var cut0: float = tn.explode_cut
	var mono := true
	var prev := cut0
	var samples := 0
	for s in 160:
		_step(1)
		if tn.role == "explode" or tn.alive:
			if tn.explode_cut > prev + 0.001:
				mono = false
			prev = tn.explode_cut
			samples += 1
	_ck("cut: explosion starts at the tip", ok and cut0 > total - 1.4,
		"cut %.1f of %.1f m" % [cut0, total])
	_step(240)
	var active_fx := 0
	for b in boss._bursts:
		if b["active"]:
			active_fx += 1
	for e in boss._cut_fx:
		if e["sparks"].emitting or e["frags"].emitting:
			active_fx += 1
	_ck("cut: burns from tip to root", mono and tn.explode_cut < 0.25,
		"cut %.2f m, %d samples" % [tn.explode_cut, samples])
	_ck("cut: no residue after the burst", active_fx == 0,
		"%d active burst(s)" % active_fx)
	_ck("cut: limb disappears", not tn.alive and not tn.root.visible,
		"alive=%s visible=%s" % [str(tn.alive), str(tn.root.visible)])
	metrics["cut"] = {"total_len": total, "first_cut": cut0, "final_cut": tn.explode_cut}


# -------------------------------------------------------------- performance

func _test_perf() -> void:
	boss.reset_boss()
	boss.set_auto(true)
	boss.set_phase_force(2)
	_step(240)
	var t0 := Time.get_ticks_usec()
	var n := 600
	for i in n:
		boss.sim_step(1.0 / 60.0)
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	metrics["sim_ms_per_step"] = us / 1000.0
	_ck("perf: sim step budget", us / 1000.0 < 12.0,
		"%.2f ms per 60 Hz step (CPU, no render)" % (us / 1000.0))
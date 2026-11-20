extends RefCounted
class_name ArcAnim2
## ARC // SENTINEL v2 — pose library, solver-driven clips and trajectories.
##
## Authoring model:
##   * attacks lead with authored elbow and wrist guides;
##   * other action keys store body joint values plus
##     Cartesian tool targets (right sword, left shield);
##   * `_build_traj()` samples the Cartesian targets (Catmull-Rom position,
##     basis slerp), solves both arms at every sample with the previous sample
##     as the IK seed (swivel continuity) and the body as an obstacle set;
##   * the resulting joint-space trajectory is cached and sampled by time.
##
## This avoids the classic failure mode of pure joint-space key interpolation:
## two individually valid keys can have different elbow swivels, and the blend
## between them sweeps the shield or blade through the hull. Solving the
## Cartesian path keeps the end effectors on the intended arc and the audit
## verifies the whole path.

const D2R := PI / 180.0
const TAU := PI * 2.0

var kin: ArcKin2
var P: Dictionary = {}

var idle_key: Dictionary = {}
var rest_key: Dictionary = {}
var idle_body: Dictionary = {}
var rest_body: Dictionary = {}
var idle_rt: Dictionary = {}
var idle_lt: Dictionary = {}
var rest_rt: Dictionary = {}
var rest_lt: Dictionary = {}

var attack_keys: Array = []
var attack_up_keys: Array = []
var draw_keys: Array = []
var sheathe_keys: Array = []
var defend_keys: Array = []
var defend_effector := "shield"

var trajs: Dictionary = {}       # clip -> [{t, pose}]
var clip_dur: Dictionary = {}
var traj_ms: Dictionary = {}
var baked_defend: Dictionary = {}
var baked_keys: Dictionary = {}
var bake_ms := 0
var bake_loaded := false
var build_ms := 0
var attack_ms := 0
var attack_up_ms := 0
var defend_ms := 0
var draw_ms := 0
var key_stats: Array = []

const SWIVELS := [-75.0, -48.0, -24.0, 0.0, 24.0, 48.0, 75.0]
const TRAJ_HZ := 56.0

const ATTACK_TOTAL := 1.45
const ATTACK_UP_TOTAL := 1.50
const DEFEND_TOTAL := 1.25
const DRAW_TOTAL := 0.90
const SHEATHE_TOTAL := 0.85
const REST_TOTAL := 4.00
const IDLE_TOTAL := 3.20
const WALK_TOTAL := 0.90


func _init(k: ArcKin2, p: Dictionary) -> void:
	kin = k
	P = p.duplicate()


func build() -> void:
	var t0 := Time.get_ticks_usec()
	key_stats.clear()
	trajs.clear()
	traj_ms.clear()
	idle_key = _build_idle_key()
	rest_key = _build_rest_key()
	bake_loaded = _load_bake()
	var ta := Time.get_ticks_usec()
	_build_attack()
	if not bake_loaded:
		_build_strike_traj("attack", attack_keys)
	attack_ms = int((Time.get_ticks_usec() - ta) / 1000)
	ta = Time.get_ticks_usec()
	_build_attack_up()
	if not bake_loaded:
		_build_strike_traj("attack_up", attack_up_keys)
	attack_up_ms = int((Time.get_ticks_usec() - ta) / 1000)
	ta = Time.get_ticks_usec()
	_build_draw_sheathe()
	draw_ms = int((Time.get_ticks_usec() - ta) / 1000)
	ta = Time.get_ticks_usec()
	_build_defend()
	defend_ms = int((Time.get_ticks_usec() - ta) / 1000)
	_build_trajs()
	attack_ms += int(traj_ms.get("attack", 0))
	attack_up_ms += int(traj_ms.get("attack_up", 0))
	draw_ms += int(traj_ms.get("draw", 0)) + int(traj_ms.get("sheathe", 0))
	build_ms = int((Time.get_ticks_usec() - t0) / 1000)


# ------------------------------------------------------------------ body base

func _body(over := {}) -> Dictionary:
	var b := {
		"root_lift": 0.0, "root_sway": 0.0, "root_shift": 0.0,
		"body_pitch": 0.0, "body_yaw": 0.0, "body_roll": 0.0,
		"torso_pitch": 0.0, "torso_yaw": 0.0, "torso_roll": 0.0,
		"lens_yaw": 0.0, "lens_pitch": 0.0,
		"wheel_spin_L": 0.0, "wheel_spin_R": 0.0,
		"shield_yaw": 0.0, "shield_pitch": 0.0,
	}
	for k in over:
		b[k] = over[k]
	if not b.has("cam_yaw"):
		# the front camera is a stabilized turret: the torso can twist for a
		# cross-body swing while the optic keeps facing forward
		b["cam_yaw"] = -0.70 * (float(b["torso_yaw"]) + float(b["body_yaw"]))
	return b


func _base(over := {}) -> Dictionary:
	var p := _body(over)
	for nm in ["L", "R"]:
		for j in ["sh", "elb", "wr"]:
			for ax in ["pitch", "yaw", "roll"]:
				p["%s%s_%s" % [j, nm, ax]] = 0.0
	p["_blade_on"] = 1.0
	p["_docked_shield"] = 0.0
	p["_docked_sword"] = 0.0
	if not p.has("cam_slide"):
		p["cam_slide"] = 0.0
	if not p.has("cam_drop"):
		p["cam_drop"] = 0.0
	return p


# ------------------------------------------------------------------ targets

func _sword_target(pos: Vector3, dir: Vector3, face := Vector3(1, 0, 0),
		use_wrist := false) -> Dictionary:
	var d := dir.normalized()
	var b := kin.sword_basis(d, face)
	if use_wrist:
		pos = pos + d * kin.L3
	return {"tool": pos, "basis": b, "dir": d}


func _shield_target(c: Vector3, n: Vector3, up := Vector3.UP) -> Dictionary:
	var nn := n.normalized()
	var b := kin.shield_basis(nn, up)
	var tool := c - nn * kin.shield_off
	return {"tool": tool, "basis": b, "c": c, "n": nn}


func _shoulder(pose: Dictionary, side: int) -> Vector3:
	return kin.torso_xf(pose) * kin.shoulder_local(side)


# ------------------------------------------------------------------ solve

func _solve_pair(body: Dictionary, rt: Dictionary, lt: Dictionary,
		blade_on: float, docked_shield: float, label := "",
		docked_sword := 0.0, seed: Dictionary = {}, swivels: Array = [], swivels_l: Array = [],
		continuity := false) -> Dictionary:
	var base := _base(body)
	if continuity:
		base["_traj"] = 1.0
	base["_blade_on"] = blade_on
	base["_docked_shield"] = docked_shield
	base["_docked_sword"] = docked_sword
	base["_seed"] = idle_key if seed.is_empty() else seed
	var body_obs := _body_obstacles(base)
	var lbest := _solve_arm(1, lt, base, swivels_l if not swivels_l.is_empty() else (swivels if not swivels.is_empty() else SWIVELS), body_obs)
	var lpose := base.duplicate()
	_merge_arm(lpose, lbest, "L")
	var left_obs := _arm_obstacles(lpose, "L")
	var rbest := _solve_arm(-1, rt, base, swivels if not swivels.is_empty() else SWIVELS, body_obs + left_obs)
	var pose := base.duplicate()
	_merge_arm(pose, rbest, "R")
	_merge_arm(pose, lbest, "L")
	# A single warm-start swivel may have drifted into a collision; retry the
	# full swivel set before giving up.
	var au := kin.audit(pose)
	if float(au["min"]) >= 0.006 or swivels.is_empty():
		pose["_audit"] = au
		pose["_audit_label"] = label
		return pose
	var lb2 := _solve_arm(1, lt, base, SWIVELS, body_obs)
	var lpose2 := base.duplicate()
	_merge_arm(lpose2, lb2, "L")
	var lobs2 := _arm_obstacles(lpose2, "L")
	var rb2 := _solve_arm(-1, rt, base, SWIVELS, body_obs + lobs2)
	var p2 := base.duplicate()
	_merge_arm(p2, rb2, "R")
	_merge_arm(p2, lb2, "L")
	var a2 := kin.audit(p2)
	if float(a2["min"]) < 0.006:
		# exhaustive fallback, still bounded and build-time only
		var rlist := _solve_arm_list(-1, rt, base, SWIVELS, body_obs + lobs2)
		var llist := _solve_arm_list(1, lt, base, SWIVELS, body_obs)
		var best := p2
		var best_score := float(a2["min"]) - 1.0
		for l in llist:
			for r in rlist:
				var p3 := base.duplicate()
				_merge_arm(p3, r, "R")
				_merge_arm(p3, l, "L")
				var a3 := kin.audit(p3)
				var sc := float(a3["min"]) - 0.002 * (float(r["cost"]) + float(l["cost"]))
				if sc > best_score:
					best_score = sc
					best = p3
					best["_audit"] = a3
		p2 = best
		a2 = p2.get("_audit", a2)
	p2["_audit_label"] = label
	if float(a2["min"]) < 0.006:
		key_stats.append({"label": label, "clear": float(a2["min"]),
			"pair": a2["pair"], "reachR": float(rb2.get("reach", 0.0)),
			"reachL": float(lb2.get("reach", 0.0))})
	return p2


func _body_obstacles(base: Dictionary) -> Array:
	var out: Array = []
	for p in kin.proxies(base):
		var n: String = p["name"]
		if (ArcKin2.BODY_PARTS as Array).has(n) or n == "wheelL" or n == "wheelR":
			out.append(p)
	return out


func _arm_obstacles(pose: Dictionary, side: String) -> Array:
	var out: Array = []
	var pfx := ["sh" + side, "upper" + side, "elb" + side, "fore" + side,
		"wr" + side, "tool" + side]
	if side == "L":
		pfx.append("shield")
	else:
		pfx.append("blade")
	for p in kin.proxies(pose):
		if (pfx as Array).has(p["name"]):
			out.append(p)
	return out


func _solve_arm(side: int, target: Dictionary, base: Dictionary, swivels: Array,
		obstacles: Array = []) -> Dictionary:
	return kin.arm_solve(side, target["tool"], target["basis"], base,
		{"swivels": swivels}, obstacles)


func _solve_arm_list(side: int, target: Dictionary, base: Dictionary, swivels: Array,
		obstacles: Array = []) -> Array:
	var out: Array = []
	for sv in swivels:
		var r := kin.arm_solve(side, target["tool"], target["basis"], base,
			{"swivels": [sv]}, obstacles)
		if not r.is_empty() and bool(r.get("ok", false)):
			out.append(r)
	out.sort_custom(func(a, b): return float(a["cost"]) < float(b["cost"]))
	return out


func _merge_arm(pose: Dictionary, arm: Dictionary, nm: String) -> void:
	for k in arm:
		if k.begins_with("sh" + nm) or k.begins_with("elb" + nm) or k.begins_with("wr" + nm):
			pose[k] = arm[k]


func _swivel_of(side: int, pose: Dictionary) -> float:
	var tx := kin.torso_xf(pose)
	var inv := tx.affine_inverse()
	var fk := kin.arm_fk(side, pose)
	var s: Vector3 = inv * (fk["s"] as Vector3)
	var w: Vector3 = inv * (fk["w"] as Vector3)
	var e: Vector3 = inv * (fk["e"] as Vector3)
	var d := w - s
	var r := d.length()
	if r < 0.03:
		return 0.0
	var u := d / r
	var side_f := float(side)
	var pole := Vector3(side_f, -0.55, -0.25)
	var perp := pole - u * pole.dot(u)
	if perp.length_squared() < 1e-8:
		perp = Vector3.UP - u * u.y
	perp = perp.normalized()
	var side_axis := u.cross(perp).normalized()
	var a := (kin.L1 * kin.L1 - kin.L2 * kin.L2 + r * r) / (2.0 * r)
	var mid := s + u * a
	var q := e - mid
	return rad_to_deg(atan2(q.dot(side_axis), q.dot(perp)))


# ------------------------------------------------------------------ keys

func _k(t: float, body: Dictionary, rt: Dictionary, lt: Dictionary,
		blade_on: float, ds: float, dw: float, label: String,
		seed: Dictionary = {}) -> Dictionary:
	var pose: Dictionary
	if bake_loaded and baked_keys.has(label):
		pose = (baked_keys[label] as Dictionary).duplicate()
	else:
		pose = _solve_pair(body, rt, lt, blade_on, ds, label, dw, seed)
	return {"t": t, "body": body, "rt": rt, "lt": lt, "blade": blade_on,
		"ds": ds, "dw": dw, "label": label, "pose": pose}


func _idle_targets(phase: float) -> Array:
	var sway := sin(phase)
	var sway2 := sin(phase * 2.0 + 0.4)
	var rpos := Vector3(-0.52 + 0.012 * sway, 0.84 + 0.010 * sway2, 0.36 + 0.008 * cos(phase))
	# The idle arm is bent, so the blade points up (mirror of the old low
	# blade about the horizontal); a downward blade read as a stowed pose.
	var rdir := Vector3(-0.18 + 0.02 * sway, 0.65, 0.74).normalized()
	var r := _sword_target(rpos, rdir, Vector3(1, 0, 0))
	var bn := Vector3(0.45, 0.05 + 0.015 * sway2, 0.89).normalized()
	var l := _shield_target(Vector3(0.52 + 0.008 * sway, 1.00 + 0.008 * sway2, 0.48), bn, Vector3.UP)
	return [r, l]


func _build_idle_key() -> Dictionary:
	idle_body = _body({"body_pitch": 1.0 * D2R, "body_roll": 1.0 * D2R})
	var tg := _idle_targets(0.0)
	idle_rt = tg[0]
	idle_lt = tg[1]
	return _solve_pair(idle_body, idle_rt, idle_lt, 1.0, 0.0, "idle")


func _rest_targets(body: Dictionary) -> Array:
	var bx := kin.body_xf(body)
	var tx := kin.torso_xf(body)
	var mouth := bx * kin.sheath_a
	var sdir := (bx.basis * (kin.sheath_b - kin.sheath_a)).normalized()
	var r := _sword_target(mouth, sdir, bx.basis * Vector3(1, 0, 0))
	var c := tx * Vector3(0.0, kin.back_y, -0.505)
	var n := (tx.basis * Vector3(0, 0, -1)).normalized()
	var l := _shield_target(c, n, (tx.basis * Vector3(0, 1, 0)).normalized())
	return [r, l]


func _build_rest_key() -> Dictionary:
	rest_body = _body({"body_pitch": -1.0 * D2R, "torso_yaw": 35.0 * D2R,
		"body_yaw": 6.0 * D2R})
	var tg := _rest_targets(rest_body)
	rest_rt = tg[0]
	rest_lt = tg[1]
	return _solve_pair(rest_body, rest_rt, rest_lt, 0.0, 1.0, "rest", 1.0)


# ------------------------------------------------------------------ idle/walk

func idle(t: float) -> Dictionary:
	var ph := TAU * t / IDLE_TOTAL
	var body := _body({
		"body_pitch": (1.2 * sin(ph) + 0.4) * D2R,
		"body_roll": 1.4 * sin(ph + 0.8) * D2R,
		"body_yaw": 0.6 * sin(ph * 0.5) * D2R,
		"root_lift": 0.006 * sin(ph * 2.0),
		"root_sway": 0.008 * sin(ph + 1.2),
		"torso_yaw": 1.6 * sin(ph + 0.35) * D2R,
		"torso_pitch": 0.7 * sin(ph * 2.0 + 0.2) * D2R,
		"wheel_spin_L": 0.025 * sin(ph),
		"wheel_spin_R": 0.025 * sin(ph),
	})
	var tg := _idle_targets(ph)
	var seed := idle_key if t < 0.001 else {}
	return _solve_pair(body, tg[0], tg[1], 1.0, 0.0, "idle", 0.0, seed)


func walk(t: float) -> Dictionary:
	var ph := TAU * t / WALK_TOTAL
	var lean := (7.0 + 1.4 * sin(ph * 2.0)) * D2R
	var body := _body({
		"body_pitch": lean,
		"body_roll": 2.6 * sin(ph) * D2R,
		"body_yaw": 1.6 * sin(ph + 0.6) * D2R,
		"root_lift": -0.012 + 0.012 * sin(ph * 2.0 + 0.3),
		"root_sway": 0.012 * sin(ph + 0.4),
		"root_shift": 0.010 * sin(ph * 2.0),
		"torso_yaw": -2.2 * sin(ph + 0.2) * D2R,
		"torso_pitch": -2.0 * D2R,
		"wheel_spin_L": -TAU * t / WALK_TOTAL,
		"wheel_spin_R": -TAU * t / WALK_TOTAL,
	})
	var rpos := Vector3(-0.52 + 0.020 * sin(ph), 0.84 + 0.016 * sin(ph * 2.0 + 0.7),
		0.36 + 0.016 * cos(ph))
	var rdir := Vector3(-0.18 + 0.03 * sin(ph + 0.4), 0.65, 0.74).normalized()
	var r := _sword_target(rpos, rdir, Vector3(1, 0, 0))
	var l := _shield_target(Vector3(0.52 + 0.010 * sin(ph), 1.00 + 0.012 * sin(ph * 2.0),
		0.48 + 0.008 * cos(ph)), Vector3(0.45, 0.05, 0.89).normalized(), Vector3.UP)
	var seed := idle_key if t < 0.001 else {}
	return _solve_pair(body, r, l, 1.0, 0.0, "walk", 0.0, seed)


func rest(t: float) -> Dictionary:
	var ph := TAU * t / REST_TOTAL
	var body := _body({
		"body_pitch": (0.6 * sin(ph) - 1.0) * D2R,
		"body_roll": 0.8 * sin(ph + 0.6) * D2R,
		"root_lift": 0.004 * sin(ph * 2.0),
		"body_yaw": 6.0 * D2R,
		"torso_yaw": (35.0 + 1.2 * sin(ph + 0.2)) * D2R,
		"torso_pitch": 0.6 * sin(ph * 2.0) * D2R,
	})
	var tg := _rest_targets(body)
	var seed := rest_key if t < 0.001 else {}
	return _solve_pair(body, tg[0], tg[1], 0.0, 1.0, "rest", 1.0, seed)


# ------------------------------------------------------------------ attack

func _build_attack() -> void:
	attack_keys = [
		_strike_idle("attack/start", 0.0),
		_strike_key("attack/lift", 0.16, _strike_body(0.005, 0.012, 1, 10, 2),
			Vector3(-0.69, 1.18, 0.04), Vector3(-0.49, 1.46, 0.16),
			Vector3(-0.14, 0.80, 0.58), Vector3(0.59, 1.00, 0.43)),
		_strike_key("attack/windup", 0.34, _strike_body(-0.015, 0.031, -3, 42, -4),
			Vector3(-0.24, 1.45, 0.37), Vector3(0.20, 1.60, 0.51),
			Vector3(0.59, 0.77, -0.24), Vector3(0.67, 0.94, 0.27)),
		_strike_key("attack/release", 0.46, _strike_body(-0.010, 0.020, 1, 25, -2),
			Vector3(-0.25, 1.34, 0.48), Vector3(0.16, 1.43, 0.68),
			Vector3(0.52, 0.65, 0.56), Vector3(0.66, 0.97, 0.30)),
		_strike_key("attack/front", 0.58, _strike_body(-0.020, -0.015, 5, 5, 4),
			Vector3(-0.40, 1.16, 0.47), Vector3(-0.05, 1.16, 0.75),
			Vector3(-0.08, 0.08, 0.99), Vector3(0.62, 1.02, 0.36)),
		_strike_key("attack/end", 0.70, _strike_body(-0.029, -0.032, 6, -16, 5),
			Vector3(-0.65, 0.94, 0.35), Vector3(-0.82, 0.78, 0.67),
			Vector3(-0.53, -0.44, 0.73), Vector3(0.53, 1.10, 0.43)),
		_strike_key("attack/follow", 0.83, _strike_body(-0.037, -0.026, 4, -20, 5),
			Vector3(-0.67, 0.91, 0.32), Vector3(-0.86, 0.73, 0.63),
			Vector3(-0.63, -0.45, 0.65), Vector3(0.55, 1.07, 0.43)),
		_strike_key("attack/recover", 1.02, _strike_body(0.013, -0.020, 0, -12, -2),
			Vector3(-0.70, 0.87, 0.12), Vector3(-0.66, 0.77, 0.50),
			Vector3(-0.40, -0.08, 0.91), Vector3(0.56, 1.02, 0.45)),
		_strike_key("attack/settle", 1.23, _strike_body(-0.004, 0, 2, -3, 2),
			Vector3(-0.69, 0.85, -0.04), Vector3(-0.53, 0.76, 0.31),
			Vector3(-0.23, 0.55, 0.80), Vector3(0.53, 1.00, 0.47)),
		_strike_idle("attack/idle", ATTACK_TOTAL),
	]


func _build_attack_up() -> void:
	attack_up_keys = [
		_strike_idle("attack_up/start", 0.0),
		_strike_key("attack_up/lower", 0.17, _strike_body(-0.025, -0.025, 3, -9, 5),
			Vector3(-0.72, 0.87, -0.02), Vector3(-0.68, 0.65, 0.31),
			Vector3(-0.61, 0.28, 0.74), Vector3(0.59, 1.02, 0.40)),
		_strike_key("attack_up/windup", 0.36, _strike_body(-0.038, -0.027, 4, -19, 5),
			Vector3(-0.67, 0.79, -0.03), Vector3(-0.80, 0.57, 0.28),
			Vector3(-0.82, -0.24, -0.51), Vector3(0.62, 1.03, 0.34)),
		_strike_key("attack_up/drive", 0.46, _strike_body(-0.022, -0.020, 1, -11, 4),
			Vector3(-0.68, 0.80, 0.01), Vector3(-0.80, 0.61, 0.34),
			Vector3(-0.88, -0.19, -0.44), Vector3(0.62, 1.05, 0.35)),
		_strike_key("attack_up/release", 0.57, _strike_body(0.023, 0.006, -4, 2, -2),
			Vector3(-0.67, 0.96, 0.28), Vector3(-0.72, 0.83, 0.65),
			Vector3(-0.54, -0.04, 0.84), Vector3(0.64, 1.03, 0.37)),
		_strike_key("attack_up/front", 0.67, _strike_body(0.027, 0.028, -3, 19, -4),
			Vector3(-0.38, 1.17, 0.485), Vector3(-0.025, 1.20, 0.77),
			Vector3(0.10, 0.40, 0.91), Vector3(0.69, 0.94, 0.27)),
		_strike_key("attack_up/end", 0.78, _strike_body(0.005, 0.040, -1, 37, -6),
			Vector3(-0.085, 1.30, 0.52), Vector3(0.345, 1.51, 0.72),
			Vector3(0.65, 0.70, 0.29), Vector3(0.71, 0.89, 0.25)),
		_strike_key("attack_up/follow", 0.89, _strike_body(-0.028, 0.031, 1, 40, -5),
			Vector3(-0.075, 1.36, 0.49), Vector3(0.35, 1.61, 0.61),
			Vector3(0.62, 0.76, 0.20), Vector3(0.70, 0.92, 0.26)),
		_strike_key("attack_up/recover", 1.11, _strike_body(0.010, 0.015, 1, 18, 2),
			Vector3(-0.55, 1.14, 0.12), Vector3(-0.28, 1.24, 0.46),
			Vector3(0.16, 0.83, 0.54), Vector3(0.57, 0.98, 0.43)),
		_strike_key("attack_up/settle", 1.32, _strike_body(-0.004, 0, 2, 2, 1),
			Vector3(-0.70, 0.87, -0.04), Vector3(-0.52, 0.77, 0.31),
			Vector3(-0.18, 0.66, 0.73), Vector3(0.53, 1.00, 0.47)),
		_strike_idle("attack_up/idle", ATTACK_UP_TOTAL),
	]


func _strike_body(lift: float, sway: float, pitch: float, yaw: float, roll: float) -> Dictionary:
	return _body({
		"root_lift": lift, "root_sway": sway, "root_shift": pitch * 0.006,
		"body_pitch": pitch * D2R, "body_yaw": yaw * 0.22 * D2R, "body_roll": roll * D2R,
		"torso_pitch": pitch * 0.28 * D2R, "torso_yaw": yaw * 0.78 * D2R,
	})


func _strike_key(label: String, time: float, body: Dictionary, elbow: Vector3,
		wrist: Vector3, blade_dir: Vector3, shield_center: Vector3) -> Dictionary:
	return {"label": label, "t": time, "body": body, "elbow": elbow,
		"wrist": wrist, "blade_dir": blade_dir.normalized(), "shield_center": shield_center,
		"pose": baked_keys.get(label, {})}


func _strike_idle(label: String, time: float) -> Dictionary:
	var arm := kin.arm_fk(-1, idle_key)
	var key := _strike_key(label, time, idle_body, arm["e"], arm["w"], arm["dir"], idle_lt["c"])
	key["pose"] = idle_key
	return key


func _build_strike_traj(name: String, keys: Array) -> void:
	var started := Time.get_ticks_usec()
	var frames: Array = [{"t": 0.0, "pose": idle_key}]
	var previous := idle_key
	for segment in keys.size() - 1:
		var start: float = keys[segment]["t"]
		var end: float = keys[segment + 1]["t"]
		var steps := ceili((end - start) * TRAJ_HZ)
		for i in range(1, steps + 1):
			var time := lerpf(start, end, float(i) / steps)
			var pose := idle_key if segment == keys.size() - 2 and i == steps else (
				_strike_pose(keys, segment, time, previous))
			frames.append({"t": time, "pose": pose})
			previous = pose
		keys[segment + 1]["pose"] = previous
	trajs[name] = frames
	clip_dur[name] = float(keys.back()["t"])
	traj_ms[name] = int((Time.get_ticks_usec() - started) / 1000)


func _strike_pose(keys: Array, segment: int, time: float, previous: Dictionary) -> Dictionary:
	var a: Dictionary = keys[segment]
	var b: Dictionary = keys[segment + 1]
	var weight := inverse_lerp(float(a["t"]), float(b["t"]), time)
	var body := _body()
	for part in body:
		body[part] = _strike_curve(keys, segment, part, weight, true)
	var pose := _base(body)
	# The turret compensates chassis motion to keep the optic level with the target.
	var eye_forward := kin.torso_xf(pose).basis.inverse() * Vector3.BACK
	pose["cam_yaw"] = atan2(eye_forward.x, eye_forward.z)
	pose["lens_pitch"] = -asin(clampf(eye_forward.y, -1.0, 1.0))
	pose["_seed"] = previous
	pose["_traj"] = 1.0
	var elbow: Vector3 = _strike_curve(keys, segment, "elbow", weight)
	var wrist: Vector3 = _strike_curve(keys, segment, "wrist", weight)
	var direction: Vector3 = _strike_curve(keys, segment, "blade_dir", weight)
	var shield_center: Vector3 = _strike_curve(keys, segment, "shield_center", weight)
	var prior_arm := kin.arm_fk(-1, previous)
	var old_direction: Vector3 = prior_arm["dir"]
	var new_direction := direction.normalized()
	var blade_basis := Basis(Quaternion(old_direction.normalized(), new_direction)) * (prior_arm["tool_basis"] as Basis)
	# Transport the blade face with its direction. Restore the idle roll gradually
	# once the blade is back in front and both orientations share the same axis.
	if time >= 0.94:
		var idle_facing := kin.sword_basis(new_direction, Vector3.RIGHT)
		blade_basis = blade_basis.slerp(idle_facing, smoothstep(0.94, 1.25, time) * 0.22)
	var right := kin.arm_from_guides(-1, elbow, wrist, blade_basis, pose)
	_merge_arm(pose, right, "R")
	var shield := _shield_target(shield_center, Vector3(0.45, 0.056, 0.89))
	var left := _solve_arm(1, shield, pose, SWIVELS, _body_obstacles(pose) + _arm_obstacles(pose, "R"))
	_merge_arm(pose, left, "L")
	pose.erase("_seed")
	pose.erase("_traj")
	return _unwrap_pose(previous, pose)


func _strike_curve(keys: Array, segment: int, field: String, weight: float, is_body := false) -> Variant:
	var first: Dictionary = keys[maxi(segment - 1, 0)]
	var a: Dictionary = keys[segment]
	var b: Dictionary = keys[segment + 1]
	var last: Dictionary = keys[mini(segment + 2, keys.size() - 1)]
	var t0: float = a["t"]
	var to: float = float(b["t"]) - t0
	var pre: float = float(first["t"]) - t0
	var post: float = float(last["t"]) - t0
	if is_body:
		return cubic_interpolate_in_time(a["body"][field], b["body"][field],
			first["body"][field], last["body"][field], weight, to, pre, post)
	var v: Vector3 = a[field]
	return v.cubic_interpolate_in_time(b[field], first[field], last[field], weight, to, pre, post)


func _draw_back_targets() -> Array:
	# lift the shield straight back off the hook before swinging it around
	var r := _sword_target(Vector3(0.225, 0.72, 0.19),
		Vector3(0.04, -0.20, -0.98), Vector3(1, 0, 0))
	var l := _shield_target(Vector3(0.16, 1.08, -0.64), Vector3(0, 0, -1), Vector3.UP)
	return [r, l]


func _draw_mid_targets() -> Array:
	var r := _sword_target(Vector3(0.259, 0.778, 0.443),
		Vector3(0.058, -0.232, -0.971), Vector3(1, 0, 0))
	var l := _shield_target(Vector3(0.66, 1.16, 0.02), Vector3(1, 0, 0), Vector3.UP)
	return [r, l]


func _draw_front_targets() -> Array:
	var r := _sword_target(Vector3(-0.10, 0.80, 0.64),
		Vector3(-0.40, -0.20, 0.90), Vector3(1, 0, 0))
	var l := _shield_target(Vector3(0.60, 1.05, 0.42),
		Vector3(0.50, 0.02, 0.87), Vector3.UP)
	return [r, l]


func _build_draw_sheathe() -> void:
	draw_keys.clear()
	sheathe_keys.clear()
	var dsc := DRAW_TOTAL / 1.10
	var ssc := SHEATHE_TOTAL / 1.05
	var b0 := rest_body
	var b1 := _body({"torso_yaw": 35.0 * D2R, "body_yaw": 6.0 * D2R,
		"root_lift": -0.006})
	var back := _draw_back_targets()
	var rear_left_r := _sword_target(Vector3(0.225, 0.72, 0.19),
		Vector3(0.04, -0.20, -0.98), Vector3(1, 0, 0))
	var rear_left_l := _shield_target(Vector3(0.60, 1.12, -0.55),
		Vector3(0, 0, -1), Vector3.UP)
	var b2 := _body({"torso_yaw": 25.0 * D2R, "body_yaw": 6.0 * D2R,
		"root_lift": -0.008})
	var mid := _draw_mid_targets()
	var b3 := _body({"torso_yaw": 0.0, "root_lift": 0.0})
	var front := _draw_front_targets()
	draw_keys.append({"t": 0.0, "body": b0, "rt": rest_rt, "lt": rest_lt,
		"blade": 0.0, "ds": 1.0, "dw": 1.0, "label": "draw/rest", "pose": rest_key})
	var d1 := _k(0.14 * dsc, b1, back[0], back[1], 0.0, 0.0, 1.0, "draw/back", rest_key)
	draw_keys.append(d1)
	var d2 := _k(0.24 * dsc, b1, rear_left_r, rear_left_l, 0.0, 0.0, 1.0, "draw/rear", d1["pose"])
	draw_keys.append(d2)
	var d3 := _k(0.36 * dsc, b2, mid[0], mid[1], 0.0, 0.0, 0.0, "draw/clear", d2["pose"])
	draw_keys.append(d3)
	var bvia := _body({"torso_yaw": 10.0 * D2R, "body_yaw": 2.0 * D2R,
		"root_lift": 0.0})
	var rvia := _sword_target(Vector3(0.20, 0.92, 0.70),
		Vector3(0.0, 0.30, 0.95), Vector3(1, 0, 0), true)
	var lvia := _shield_target(Vector3(0.64, 1.10, 0.18),
		Vector3(0.60, 0.02, 0.80), Vector3.UP)
	var dv := _k(0.48 * dsc, bvia, rvia, lvia, 0.0, 0.0, 0.0, "draw/via", d3["pose"])
	draw_keys.append(dv)
	var d4 := _k(0.62 * dsc, b3, front[0], front[1], 1.0, 0.0, 0.0, "draw/front", dv["pose"])
	draw_keys.append(d4)
	draw_keys.append({"t": DRAW_TOTAL, "body": idle_body, "rt": idle_rt, "lt": idle_lt,
		"blade": 1.0, "ds": 0.0, "dw": 0.0, "label": "draw/idle", "pose": idle_key})
	sheathe_keys.append({"t": 0.0, "body": idle_body, "rt": idle_rt, "lt": idle_lt,
		"blade": 1.0, "ds": 0.0, "dw": 0.0, "label": "sheathe/idle", "pose": idle_key})
	var s1 := _k(0.35 * ssc, b3, front[0], front[1], 1.0, 0.0, 0.0,
		"sheathe/front", idle_key)
	sheathe_keys.append(s1)
	var sv := _k(0.48 * ssc, bvia, rvia, lvia, 0.0, 0.0, 0.0,
		"sheathe/via", s1["pose"])
	sheathe_keys.append(sv)
	var s2 := _k(0.60 * ssc, b2, mid[0], mid[1], 0.0, 0.0, 0.0,
		"sheathe/clear", sv["pose"])
	sheathe_keys.append(s2)
	var s3 := _k(0.78 * ssc, b1, rear_left_r, rear_left_l, 0.0, 0.0, 1.0,
		"sheathe/rear", s2["pose"])
	sheathe_keys.append(s3)
	var s4 := _k(0.88 * ssc, b1, back[0], back[1], 0.0, 0.0, 1.0,
		"sheathe/back", s3["pose"])
	sheathe_keys.append(s4)
	sheathe_keys.append({"t": SHEATHE_TOTAL, "body": rest_body, "rt": rest_rt,
		"lt": rest_lt, "blade": 0.0, "ds": 1.0, "dw": 1.0,
		"label": "sheathe/rest", "pose": rest_key})


# ------------------------------------------------------------------ defend

func _defend_shield_pose() -> Dictionary:
	var b := _body({
		"root_lift": -0.040, "root_sway": 0.030, "body_yaw": 5.0 * D2R,
		"body_roll": 2.0 * D2R, "torso_yaw": 12.0 * D2R,
		"torso_pitch": 5.0 * D2R, "torso_roll": 1.0 * D2R,
	})
	var c := Vector3(0.438, 1.06, 0.488)
	var n := Vector3(0.707, 0.0, 0.707)
	var l := _shield_target(c, n, Vector3.UP)
	var r := _sword_target(Vector3(-0.60, 0.86, 0.30),
		Vector3(-0.15, -0.55, 0.82), Vector3(0, 0, 1))
	return {"body": b, "rt": r, "lt": l}


func _defend_sword_pose() -> Dictionary:
	var b := _body({
		"root_lift": -0.030, "root_sway": -0.030, "body_yaw": -5.0 * D2R,
		"body_roll": -2.0 * D2R, "torso_yaw": -13.0 * D2R,
		"torso_pitch": 6.0 * D2R, "torso_roll": -1.0 * D2R,
	})
	var l := _shield_target(Vector3(0.60, 1.02, 0.42),
		Vector3(0.55, 0.0, 0.84), Vector3.UP)
	var c := Vector3(-0.424, 1.060, 0.474)
	var d := Vector3(0.10, 0.98, 0.10).normalized()
	var tool := c - d * 0.30
	var r := _sword_target(tool, d, Vector3(-0.715, 0.05, 0.697))
	return {"body": b, "rt": r, "lt": l}


func _build_defend() -> void:
	var threat := int(P.get("_threat", 0))
	var spec: Dictionary
	if threat == 0:
		defend_effector = "shield"
		spec = _defend_shield_pose()
	else:
		defend_effector = "sword"
		spec = _defend_sword_pose()
	var block := _k(0.20, spec["body"], spec["rt"], spec["lt"], 1.0, 0.0, 0.0,
		"defend/block", idle_key)
	defend_keys = [
		{"t": 0.0, "body": idle_body, "rt": idle_rt, "lt": idle_lt,
			"blade": 1.0, "ds": 0.0, "dw": 0.0, "label": "defend/idle", "pose": idle_key},
		block,
		{"t": 0.94, "body": spec["body"], "rt": spec["rt"], "lt": spec["lt"],
			"blade": 1.0, "ds": 0.0, "dw": 0.0, "label": "defend/hold",
			"pose": block["pose"]},
		{"t": DEFEND_TOTAL, "body": idle_body, "rt": idle_rt, "lt": idle_lt,
			"blade": 1.0, "ds": 0.0, "dw": 0.0, "label": "defend/idle2",
			"pose": idle_key},
	]
	trajs.erase("defend")
	traj_ms.erase("defend")
	var bd = baked_defend.get(defend_effector, {})
	if not bd.is_empty():
		trajs["defend"] = bd["samples"]
		clip_dur["defend"] = float(bd["dur"])
		traj_ms["defend"] = 1
	else:
		_build_traj("defend", defend_keys)


# ------------------------------------------------------------------ trajectories

func _build_trajs() -> void:
	for spec in [["draw", draw_keys], ["sheathe", sheathe_keys]]:
		if not trajs.has(spec[0]):
			_build_traj(spec[0], spec[1])


func _build_traj(name: String, keys: Array) -> void:
	if keys.size() < 2:
		return
	var t0 := Time.get_ticks_usec()
	var out := _build_traj_raw(name, keys)
	_smooth_traj(out, keys)
	_smooth_traj(out, keys)
	if name == "draw" or name == "sheathe":
		_retime_clip_by_tool_arc(out)
	else:
		_limit_qdot(out, 25.0)
	trajs[name] = out
	clip_dur[name] = float(out[out.size() - 1]["t"])
	traj_ms[name] = int((Time.get_ticks_usec() - t0) / 1000)


func _build_traj_raw(name: String, keys: Array) -> Array:
	var dur := float(keys[keys.size() - 1]["t"])
	var steps := maxi(2, int(ceil(dur * TRAJ_HZ)))
	var out: Array = []
	var prev: Dictionary = keys[0]["pose"]
	out.append({"t": 0.0, "pose": prev})
	for i in range(1, steps + 1):
		var t := dur * float(i) / float(steps)
		var seg := _segment_index(keys, t)
		var u := clampf((t - float(keys[seg]["t"])) /
			maxf(float(keys[seg + 1]["t"]) - float(keys[seg]["t"]), 1e-6), 0.0, 1.0)
		var lin := bool(keys[seg].get("lin", false)) or bool(keys[seg + 1].get("lin", false))
		var ee := u if lin else smoothstep(0.0, 1.0, u)
		var body := _interp_body(keys[seg]["body"], keys[seg + 1]["body"], ee)
		var rt := _interp_target(keys, seg, u, true)
		var lt := _interp_target(keys, seg, u, false)
		var blade := lerpf(float(keys[seg]["blade"]), float(keys[seg + 1]["blade"]), ee)
		if blade > 0.45:
			_guard_blade(rt)
		_guard_shield(lt)
		var ds := lerpf(float(keys[seg]["ds"]), float(keys[seg + 1]["ds"]), ee)
		var dw := lerpf(float(keys[seg]["dw"]), float(keys[seg + 1]["dw"]), ee)
		var svr := _swivel_of(-1, prev)
		var svl := _swivel_of(1, prev)
		var pose := _solve_pair(body, rt, lt, blade, ds, name, dw, prev, [svr], [svl], true)
		if float(kin.audit(pose)["min"]) < 0.004:
			pose = _solve_pair(body, rt, lt, blade, ds, name, dw, prev,
				[svr, svr - 18.0, svr + 18.0, svr - 36.0, svr + 36.0],
				[svl, svl - 18.0, svl + 18.0, svl - 36.0, svl + 36.0], true)
		var au := kin.audit(pose)
		if float(au["min"]) < 0.002:
			var lt2 := _nudge_shield(lt, body)
			var p2 := _solve_pair(body, rt, lt2, blade, ds, name, dw, prev, [], [], true)
			if float(kin.audit(p2)["min"]) > float(au["min"]):
				pose = p2
		pose = _unwrap_pose(prev, pose)
		out.append({"t": t, "pose": pose})
		prev = pose
	return out


func _retime(keys: Array, out: Array) -> bool:
	# If a segment asks the wrist for more than ~14 rad/s, give that segment
	# more time (a local time reparameterization). The Cartesian path is
	# unchanged; only its speed profile is stretched.
	for i in keys.size() - 1:
		var t0 := float(keys[i]["t"])
		var t1 := float(keys[i + 1]["t"])
		if t1 - t0 < 1e-4:
			continue
		var peak := 0.0
		for j in range(1, out.size()):
			var a: Dictionary = out[j - 1]["pose"]
			var b: Dictionary = out[j]["pose"]
			var tt: float = out[j]["t"]
			if tt < t0 - 1e-6 or tt > t1 + 1e-6:
				continue
			var dt := maxf(float(out[j]["t"]) - float(out[j - 1]["t"]), 1e-3)
			for k in a:
				if k.begins_with("_") or not b.has(k):
					continue
				if a[k] is Quaternion and b[k] is Quaternion:
					peak = maxf(peak, (a[k] as Quaternion).angle_to(b[k] as Quaternion) / dt)
				elif a[k] is float:
					peak = maxf(peak, absf(wrapf(float(b[k]) - float(a[k]), -PI, PI)) / dt)
		if peak > 15.0:
			var extra := (peak / 12.0 - 1.0) * (t1 - t0)
			for j in range(i + 1, keys.size()):
				keys[j]["t"] = float(keys[j]["t"]) + extra
			return true
	return false


## Re-time a whole short clip by the sword-tool arc length with one smooth
## bell.  Used for draw/sheathe, where every key used to be an ease-in/out stop.
func _retime_clip_by_tool_arc(out: Array) -> void:
	if out.size() < 4:
		return
	var total_t := float(out[out.size() - 1]["t"])
	if total_t <= 0.0:
		return
	var ss: Array[float] = [0.0]
	var prev := _tool_of(out[0]["pose"])
	for i in range(1, out.size()):
		var p := _tool_of(out[i]["pose"])
		ss.append(ss[ss.size() - 1] + p.distance_to(prev))
		prev = p
	var total: float = ss[ss.size() - 1]
	if total < 1e-5:
		return
	for j in ss.size():
		var u := ss[j] / total
		out[j]["t"] = total_t * _inv_smoothstep(u)


func _tool_of(pose: Dictionary) -> Vector3:
	var fk: Dictionary = kin.arm_fk(-1, pose)
	return fk["tool"]


## Re-time one continuous swing by the sword-tip arc length.  Times of the
## samples between the windup and follow keys are solved from s(t) with a
## single smoothstep, so tip speed is zero at the ends and has one broad peak
## in the middle - no sawtooth from stitching key segments.
func _inv_smoothstep(u: float) -> float:
	if u <= 0.0:
		return 0.0
	if u >= 1.0:
		return 1.0
	var v := u
	for i in 10:
		var f := 3.0 * v * v - 2.0 * v * v * v - u
		var fp := 6.0 * v - 6.0 * v * v
		if absf(fp) < 1e-6:
			break
		v = clampf(v - f / fp, 0.0, 1.0)
	return v


## The arm joints carry both a quaternion and redundant Euler fields for the
## UI.  The Euler yaw can wrap ±180° while the actual quaternion is continuous;
## feeding it to the speed limiter used to stretch whole clips for a fake jump.
func _is_redundant_euler(a: Dictionary, b: Dictionary, k: String) -> bool:
	if k.ends_with("_pitch") or k.ends_with("_yaw") or k.ends_with("_roll"):
		var base := k.left(k.rfind("_"))
		return a.has(base + "_q") and b.has(base + "_q")
	return false


func _global_qdot_scale(out: Array, max_qdot: float) -> void:
	if out.size() < 2:
		return
	var peak := 0.0
	for i in range(1, out.size()):
		var a: Dictionary = out[i - 1]["pose"]
		var b: Dictionary = out[i]["pose"]
		var dt := maxf(float(out[i]["t"]) - float(out[i - 1]["t"]), 1e-3)
		for k in a:
			if k.begins_with("_") or not b.has(k) or _is_redundant_euler(a, b, k):
				continue
			if a[k] is Quaternion and b[k] is Quaternion:
				peak = maxf(peak, (a[k] as Quaternion).angle_to(b[k]) / dt)
			elif a[k] is float:
				peak = maxf(peak, absf(wrapf(float(b[k]) - float(a[k]), -PI, PI)) / dt)
	if peak > max_qdot:
		var f := peak / max_qdot
		for i in out.size():
			out[i]["t"] = float(out[i]["t"]) * f


func _limit_qdot(out: Array, max_qdot: float) -> void:
	# Local time reparameterization: fast joint samples get more time, slow
	# samples keep theirs. This bounds the physical joint speed without
	# changing the Cartesian sword path or the exact key poses.
	if out.size() < 2:
		return
	var t := 0.0
	out[0]["t"] = 0.0
	for i in range(1, out.size()):
		var a: Dictionary = out[i - 1]["pose"]
		var b: Dictionary = out[i]["pose"]
		var peak := 0.0
		for k in a:
			if k.begins_with("_") or not b.has(k):
				continue
			if a[k] is Quaternion and b[k] is Quaternion:
				peak = maxf(peak, (a[k] as Quaternion).angle_to(b[k] as Quaternion))
			elif a[k] is float:
				peak = maxf(peak, absf(wrapf(float(b[k]) - float(a[k]), -PI, PI)))
		var dt_req := peak / max_qdot if peak > 0.0001 else 0.0
		var dt_orig := 1.0 / TRAJ_HZ
		t += maxf(dt_orig, dt_req)
		out[i]["t"] = t


func _smooth_traj(out: Array, keys: Array) -> void:
	if out.size() < 9:
		return
	var key_ts: Array = []
	for k in keys:
		key_ts.append(float(k["t"]))
	for i in range(1, out.size() - 1):
		var t: float = out[i]["t"]
		var near_key := false
		for kt in key_ts:
			if absf(t - float(kt)) < 0.008:
				near_key = true
				break
		if near_key:
			continue
		var p: Dictionary = out[i]["pose"]
		var orig := p.duplicate()
		var lo := maxi(i - 4, 0)
		var hi := mini(i + 4, out.size() - 1)
		for k in p:
			if k.begins_with("_"):
				continue
			if p[k] is Quaternion:
				var acc := Vector4.ZERO
				var ref: Quaternion = p[k]
				for j in range(lo, hi + 1):
					var q: Quaternion = out[j]["pose"][k]
					if q.dot(ref) < 0.0:
						q = Quaternion(-q.x, -q.y, -q.z, -q.w)
					acc += Vector4(q.x, q.y, q.z, q.w)
				var v := acc.normalized()
				p[k] = Quaternion(v.x, v.y, v.z, v.w)
			elif p[k] is float:
				var sum := 0.0
				var cnt := 0
				for j in range(lo, hi + 1):
					sum += float(out[j]["pose"][k])
					cnt += 1
				p[k] = sum / float(cnt)
		if float(kin.audit(p)["min"]) < 0.012:
			for k in orig:
				p[k] = orig[k]


func _unwrap_pose(prev: Dictionary, pose: Dictionary) -> Dictionary:
	for k in pose:
		if k.begins_with("_") or not (pose[k] is float) or not prev.has(k):
			continue
		pose[k] = float(prev[k]) + wrapf(float(pose[k]) - float(prev[k]), -PI, PI)
	return pose


func _segment_index(keys: Array, t: float) -> int:
	for i in keys.size() - 1:
		if t <= float(keys[i + 1]["t"]) + 1e-9:
			return i
	return keys.size() - 2


func _interp_body(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		if a.has(k) and (a[k] is float):
			out[k] = lerpf(float(a[k]), float(b[k]), u)
	return out


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


func _interp_target(keys: Array, seg: int, u: float, right: bool) -> Dictionary:
	var key_a: String = "rt" if right else "lt"
	var i0 := maxi(seg - 1, 0)
	var i1 := seg
	var i2 := seg + 1
	var i3 := mini(seg + 2, keys.size() - 1)
	var a: Dictionary = keys[i1][key_a]
	var b: Dictionary = keys[i2][key_a]
	var p0: Vector3 = keys[i0][key_a]["tool"]
	var p1: Vector3 = a["tool"]
	var p2: Vector3 = b["tool"]
	var p3: Vector3 = keys[i3][key_a]["tool"]
	var pos := p1.lerp(p2, u)
	var ba: Basis = a["basis"]
	var bb: Basis = b["basis"]
	var basis := ba.slerp(bb, u).orthonormalized()
	return {"tool": pos, "basis": basis}


func _guard_blade(rt: Dictionary) -> void:
	var b: Basis = rt["basis"]
	var d := b * Vector3(0, -1, 0)
	var tip: Vector3 = (rt["tool"] as Vector3) + d * kin.blade_len
	if tip.y < 0.14:
		rt["tool"] = (rt["tool"] as Vector3) + Vector3(0, 0.14 - tip.y, 0)


func _guard_shield(lt: Dictionary) -> void:
	var b: Basis = lt["basis"]
	var c: Vector3 = (lt["tool"] as Vector3) + b * Vector3(0, 0, kin.shield_off)
	if c.y < kin.shield_r + 0.04:
		lt["tool"] = (lt["tool"] as Vector3) + Vector3(0, kin.shield_r + 0.04 - c.y, 0)


func _nudge_shield(lt: Dictionary, body: Dictionary) -> Dictionary:
	# push the field outward from the torso axis, keeping its normal
	var c: Vector3 = lt["tool"] + (lt["basis"] as Basis) * Vector3(0, 0, kin.shield_off)
	var tx := kin.torso_xf(body)
	var origin: Vector3 = tx.origin + (tx.basis * Vector3(0, kin.hull_y, 0))
	var out := c - origin
	out.y = 0.0
	if out.length_squared() < 1e-5:
		out = Vector3(1, 0, 0)
	out = out.normalized() * 0.10
	var n: Vector3 = (lt["basis"] as Basis) * Vector3(0, 0, 1)
	var up: Vector3 = (lt["basis"] as Basis) * Vector3(0, 1, 0)
	return _shield_target(c + out, n, up)


# ------------------------------------------------------------------ sampling

func duration(name: String) -> float:
	if clip_dur.has(name):
		return float(clip_dur[name])
	match name:
		"rest": return REST_TOTAL
		"idle": return IDLE_TOTAL
		"walk": return WALK_TOTAL
		"attack": return ATTACK_TOTAL
		"attack_up": return ATTACK_UP_TOTAL
		"defend": return DEFEND_TOTAL
		"draw": return DRAW_TOTAL
		"sheathe": return SHEATHE_TOTAL
	return 1.0


func sample(name: String, t: float) -> Dictionary:
	match name:
		"rest": return rest(t)
		"idle": return idle(t)
		"walk": return walk(t)
		"attack", "attack_up":
			if not trajs.has(name):
				_build_strike_traj(name, _keys_for(name))
			return _sample_traj(name, t)
		"defend", "draw", "sheathe":
			if not trajs.has(name):
				_build_traj(name, _keys_for(name))
			return _sample_traj(name, t)
	return idle(t)


func _keys_for(name: String) -> Array:
	match name:
		"attack": return attack_keys
		"attack_up": return attack_up_keys
		"draw": return draw_keys
		"sheathe": return sheathe_keys
		"defend": return defend_keys
	return []


func _sample_traj(name: String, t: float) -> Dictionary:
	var tr: Array = trajs[name]
	if tr.is_empty():
		return idle(t)
	if t <= float(tr[0]["t"]):
		return (tr[0]["pose"] as Dictionary).duplicate()
	for i in tr.size() - 1:
		var a: Dictionary = tr[i]
		var b: Dictionary = tr[i + 1]
		if t <= float(b["t"]) + 1e-9:
			var u := clampf((t - float(a["t"])) /
				maxf(float(b["t"]) - float(a["t"]), 1e-6), 0.0, 1.0)
			return _blend_linear(a["pose"], b["pose"], u)
	return (tr[tr.size() - 1]["pose"] as Dictionary).duplicate()


func _blend_linear(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out: Dictionary = b.duplicate()
	for key in b:
		if key.begins_with("_"):
			if key == "_blade_on" or key == "_docked_shield" or key == "_docked_sword":
				out[key] = lerpf(float(a.get(key, b[key])), float(b[key]), k)
			continue
		if b[key] is Quaternion:
			if a.has(key) and a[key] is Quaternion:
				out[key] = (a[key] as Quaternion).slerp(b[key] as Quaternion, k)
			continue
		if a.has(key) and b[key] is float:
			out[key] = lerpf(float(a[key]), float(b[key]), k)
	return out


func _blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out: Dictionary = b.duplicate()
	for key in b:
		if key.begins_with("_"):
			if key == "_blade_on" or key == "_docked_shield" or key == "_docked_sword":
				out[key] = lerpf(float(a.get(key, b[key])), float(b[key]), k)
			continue
		if b[key] is Quaternion:
			if a.has(key) and a[key] is Quaternion:
				out[key] = (a[key] as Quaternion).slerp(b[key] as Quaternion, k)
			continue
		if a.has(key) and b[key] is float:
			var av := float(a[key])
			var bv := float(b[key])
			var dv := wrapf(bv - av, -PI, PI)
			out[key] = av + dv * k
	return out


func action_key(name: String, which: String) -> Dictionary:
	var keys: Array = _keys_for(name)
	var want := name + "/" + which
	for k in keys:
		if str(k.get("label", "")) == want:
			return k["pose"]
	return {}


func traj_qdot(name: String) -> float:
	if not trajs.has(name):
		return 0.0
	var tr: Array = trajs[name]
	var best := 0.0
	for i in tr.size() - 1:
		var a: Dictionary = tr[i]["pose"]
		var b: Dictionary = tr[i + 1]["pose"]
		var dt := maxf(float(tr[i + 1]["t"]) - float(tr[i]["t"]), 1e-3)
		for k in a:
			if k.begins_with("_") or not b.has(k) or _is_redundant_euler(a, b, k):
				continue
			if a[k] is Quaternion and b[k] is Quaternion:
				var qa: Quaternion = a[k]
				var qb: Quaternion = b[k]
				best = maxf(best, qa.angle_to(qb) / dt)
			elif a[k] is float:
				var dv := absf(wrapf(float(b[k]) - float(a[k]), -PI, PI))
				best = maxf(best, dv / dt)
	return best


# ------------------------------------------------------------------ joint trajectories

func _build_joint_traj(name: String, keys: Array) -> void:
	var t0 := Time.get_ticks_usec()
	var out: Array = _joint_traj_raw(keys)
	for pass_i in 3:
		if not _retime(keys, out):
			break
		out = _joint_traj_raw(keys)
	_smooth_traj(out, keys)
	trajs[name] = out
	clip_dur[name] = float(keys[keys.size() - 1]["t"])
	traj_ms[name] = int((Time.get_ticks_usec() - t0) / 1000)


func _joint_traj_raw(keys: Array) -> Array:
	var dur := float(keys[keys.size() - 1]["t"])
	var steps := maxi(2, int(ceil(dur * TRAJ_HZ)))
	var out: Array = []
	for i in range(steps + 1):
		var t := dur * float(i) / float(steps)
		if i == 0:
			out.append({"t": 0.0, "pose": (keys[0]["pose"] as Dictionary).duplicate()})
			continue
		if i == steps:
			out.append({"t": dur, "pose": (keys[keys.size() - 1]["pose"] as Dictionary).duplicate()})
			continue
		var seg := _segment_index(keys, t)
		var u := clampf((t - float(keys[seg]["t"])) /
			maxf(float(keys[seg + 1]["t"]) - float(keys[seg]["t"]), 1e-6), 0.0, 1.0)
		var lin := bool(keys[seg].get("lin", false)) or bool(keys[seg + 1].get("lin", false))
		var ee := u if lin else smoothstep(0.0, 1.0, u)
		var pose := _blend(keys[seg]["pose"], keys[seg + 1]["pose"], ee)
		out.append({"t": t, "pose": pose})
	return out


# ------------------------------------------------------------------ bake

func _sig() -> String:
	var keys := ["body_scale", "hull_radius", "wheel_radius", "shield_radius", "blade_length", "blade_width"]
	var parts: Array = ["strikes=3"]
	for k in keys:
		parts.append("%s=%.6f" % [k, float(P.get(k, 0.0))])
	return "|".join(parts)


func _pose_to_data(pose: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in pose:
		if k.begins_with("_") and k != "_blade_on" and k != "_docked_shield" and k != "_docked_sword":
			continue
		var v = pose[k]
		if v is Quaternion:
			var q: Quaternion = v
			out[k] = [q.x, q.y, q.z, q.w]
		elif v is float:
			out[k] = v
	return out


func _pose_from_data(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		var v = d[k]
		if v is Array and (v as Array).size() == 4:
			out[k] = Quaternion(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
		elif v is float or v is int:
			out[k] = float(v)
	return out


func _load_bake() -> bool:
	if float(P.get("_no_bake", 0.0)) > 0.5:
		return false
	var path := "res://data/arc_traj_v2.json"
	if not FileAccess.file_exists(path):
		return false
	var t0 := Time.get_ticks_usec()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary) or str(data.get("sig", "")) != _sig():
		return false
	var clips: Dictionary = data.get("clips", {})
	for name in ["attack", "attack_up", "draw", "sheathe"]:
		if not clips.has(name):
			return false
		var arr: Array = []
		for s in clips[name]["samples"]:
			arr.append({"t": float(s["t"]), "pose": _pose_from_data(s["pose"])})
		trajs[name] = arr
		clip_dur[name] = float(clips[name]["dur"])
		traj_ms[name] = 1
	baked_keys.clear()
	var kd: Dictionary = data.get("keys", {})
	for label in kd:
		baked_keys[label] = _pose_from_data(kd[label])
	for nm in ["shield", "sword"]:
		if clips.has("defend_" + nm):
			var arr2: Array = []
			for s2 in clips["defend_" + nm]["samples"]:
				arr2.append({"t": float(s2["t"]), "pose": _pose_from_data(s2["pose"])})
			baked_defend[nm] = {"samples": arr2,
				"dur": float(clips["defend_" + nm]["dur"])}
	bake_ms = int((Time.get_ticks_usec() - t0) / 1000)
	return true


func write_bake(path := "res://data/arc_traj_v2.json") -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data"))
	var clips: Dictionary = {}
	for name in ["attack", "attack_up", "draw", "sheathe"]:
		var tr: Array = trajs.get(name, [])
		var samples: Array = []
		for s in tr:
			samples.append({"t": float(s["t"]), "pose": _pose_to_data(s["pose"])})
		clips[name] = {"dur": float(clip_dur.get(name, 0.0)), "samples": samples}
	for nm in ["shield", "sword"]:
		var bd: Dictionary = baked_defend.get(nm, {})
		if bd.is_empty():
			continue
		var samples2: Array = []
		for s2 in bd["samples"]:
			samples2.append({"t": float(s2["t"]), "pose": _pose_to_data(s2["pose"])})
		clips["defend_" + nm] = {"dur": float(bd["dur"]), "samples": samples2}
	var kd: Dictionary = {}
	for label in baked_keys:
		kd[label] = _pose_to_data(baked_keys[label])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"sig": _sig(), "clips": clips, "keys": kd}))
		f.close()


# ------------------------------------------------------------------ lens

static func lens_aim(torso: Transform3D, lens_pos: Vector3, target: Vector3) -> Vector2:
	var local := torso.affine_inverse() * target
	local -= lens_pos
	var yaw := atan2(local.x, local.z)
	var flat := sqrt(local.x * local.x + local.z * local.z)
	var pitch := -atan2(local.y, maxf(flat, 1e-5))
	return Vector2(clampf(yaw, -35.0 * D2R, 35.0 * D2R),
		clampf(pitch, -25.0 * D2R, 25.0 * D2R))
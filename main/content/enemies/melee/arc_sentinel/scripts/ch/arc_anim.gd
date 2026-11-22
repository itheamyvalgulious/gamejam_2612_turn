extends RefCounted
class_name ArcAnim3
## ARC // GRINDER v3 — pose library, planner and clips.
##
## Authoring model
##   * a clip is a list of keys: body values + a Cartesian sword target;
##   * trajectories sample the Cartesian target (lerp + basis slerp), solve the
##     single arm with one fixed swivel branch per clip (chosen by probing the
##     whole path), and audit every sample against the body;
##   * attacks are re-timed by blade-tip arc length with a hard acceleration
##     into the impact and a deceleration out of it;
##   * `block` is planned at runtime from a threat azimuth/elevation: a small
##     search places the blade mid-line on the threat ray with the flat facing
##     the attacker, ranks candidates by clearance, then samples the guard.
##
## No sheathed stance: the sword is always live, so every clip starts and ends
## on the same idle base pose and any transition is a short joint fade.

const D2R := PI / 180.0
const TAU := PI * 2.0

const SWIVELS := [-80.0, -60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0, 80.0]
const TRAJ_HZ := 64.0

const IDLE_TOTAL := 3.200
const RUN_TOTAL := 0.720
const IDLE_TOOL := Vector3(0.160, 1.060, 0.500)
const IDLE_DIR := Vector3(0.0, 0.075, 0.997)

var kin: ArcKin3
var P: Dictionary = {}
var arm_shift := 0.0

var idle_key: Dictionary = {}
var idle_body: Dictionary = {}
var idle_swivel := 0.0
var trajs: Dictionary = {}
var clip_dur: Dictionary = {}
var clip_swivel: Dictionary = {}
var plan_ms: Dictionary = {}
var build_ms := 0
var last_worst := 9.0
var last_worst_pair: Array = ["", ""]
var attack1_ms := 0
var attack2_ms := 0
var block_ms := 0
var block_plan_raw_ms := 0
var block_threat_deg := 0.0
var block_elev_deg := 0.0
var block_stats: Dictionary = {}
var block_keys: Array = []
var attack1_keys: Array = []
var attack2_keys: Array = []
var key_stats: Array = []
var _block_cache: Dictionary = {}


func _init(k: ArcKin3, p: Dictionary) -> void:
	kin = k
	P = p.duplicate()
	# authored sword targets are written around the old shoulder height; keep
	# them at the same offset from the (taller) current shoulder
	arm_shift = (kin.body_y + kin.shoulder_local.y) - 1.235


func build() -> void:
	var t0 := Time.get_ticks_usec()
	key_stats.clear()
	trajs.clear()
	clip_dur.clear()
	plan_ms.clear()
	clip_swivel.clear()
	_block_cache.clear()
	idle_key = _build_idle_key()
	var ta := Time.get_ticks_usec()
	_build_attack1()
	attack1_ms = int((Time.get_ticks_usec() - ta) / 1000)
	ta = Time.get_ticks_usec()
	_build_attack2()
	attack2_ms = int((Time.get_ticks_usec() - ta) / 1000)
	ta = Time.get_ticks_usec()
	plan_block(float(P.get("block_threat", 0.0)), float(P.get("block_elev", 0.0)))
	block_ms = int((Time.get_ticks_usec() - ta) / 1000)
	build_ms = int((Time.get_ticks_usec() - t0) / 1000)


# ------------------------------------------------------------------ base pose

func _body(over := {}) -> Dictionary:
	var b := {
		"root_yaw": 0.0,
		"body_lift": 0.0, "body_sway": 0.0, "body_shift": 0.0,
		"body_pitch": 0.0, "body_yaw": 0.0, "body_roll": 0.0,
		"cam_yaw": 0.0, "cam_pitch": 0.0,
	}
	for k in over:
		b[k] = over[k]
	return b


func _base(over := {}) -> Dictionary:
	var p := _body(over)
	for j in ["sh", "elb", "wr"]:
		for ax in ["pitch", "yaw", "roll"]:
			p["%s_%s" % [j, ax]] = 0.0
	p["_blade_on"] = 1.0
	p["_block_hit"] = 0.0
	return p


func _sword(pos: Vector3, dir: Vector3, face: Vector3) -> Dictionary:
	var d := dir.normalized()
	return {"tool": pos + Vector3(0, arm_shift, 0), "basis": kin.sword_basis(d, face), "dir": d}


## Ship-space sword target for the runtime planner (no authoring offset).
func _sword_world(pos: Vector3, dir: Vector3, face: Vector3) -> Dictionary:
	var d := dir.normalized()
	return {"tool": pos, "basis": kin.sword_basis(d, face), "dir": d}


# ------------------------------------------------------------------ solver

func _body_obstacles(base: Dictionary) -> Array:
	var out: Array = []
	for p in kin.proxies(base):
		var n: String = p["name"]
		if n == "sh" or n == "upper" or n == "elb" or n == "fore" or n == "wr" or n == "tool" or n == "blade":
			continue
		out.append(p)
	return out


func _solve(body: Dictionary, target: Dictionary, seed := {}, swivels: Array = [],
		blade_on := 1.0, audit_pose := true) -> Dictionary:
	var base := _base(body)
	base["_blade_on"] = blade_on
	base["_seed"] = seed if not seed.is_empty() else idle_key
	var obs := _body_obstacles(base)
	var sv := swivels if not swivels.is_empty() else SWIVELS
	var best := kin.arm_solve(target["tool"], target["basis"], base, {"swivels": sv}, obs)
	var pose := base.duplicate()
	if best.is_empty() or not bool(best.get("ok", false)):
		return pose
	_merge(pose, best)
	pose["_cost"] = float(best.get("cost", 0.0))
	if audit_pose:
		pose["_audit"] = kin.audit(pose)
	return pose


func _merge(pose: Dictionary, arm: Dictionary) -> void:
	for k in arm:
		if k.begins_with("sh") or k.begins_with("elb") or k.begins_with("wr"):
			pose[k] = arm[k]


# ------------------------------------------------------------------ idle / run

func _idle_target(ph: float) -> Dictionary:
	var sway := sin(ph)
	var sway2 := sin(ph * 2.0 + 0.4)
	var pos := IDLE_TOOL + Vector3(0.008 * sway, 0.010 * sway2, 0.006 * cos(ph))
	var d := (IDLE_DIR + Vector3(0.010 * sway, 0.012 * sway2, -0.004 * cos(ph))).normalized()
	return _sword(pos, d, Vector3(1, 0, 0))


func _build_idle_key() -> Dictionary:
	idle_body = _body({"body_pitch": 0.9 * D2R, "body_roll": 0.7 * D2R})
	var tgt := _idle_target(0.0)
	var best := 0.0
	var best_score := -1e9
	var best_pose: Dictionary = {}
	for sv in SWIVELS:
		var p := _solve(idle_body, tgt, {}, [sv], 1.0)
		var au := kin.audit(p)
		var score := float(au["min"]) - 0.01 * float(p.get("_cost", 0.0))
		if score > best_score:
			best_score = score
			best = float(sv)
			best_pose = p
	idle_swivel = best
	return best_pose


func idle(t: float) -> Dictionary:
	var ph := TAU * t / IDLE_TOTAL
	var body := _body({
		"body_pitch": (0.9 + 0.8 * sin(ph)) * D2R,
		"body_roll": 0.9 * sin(ph + 0.8) * D2R,
		"body_yaw": 0.5 * sin(ph * 0.5) * D2R,
		"body_lift": 0.004 * sin(ph * 2.0),
		"body_sway": 0.004 * sin(ph + 1.1),
		"cam_yaw": 0.02 * sin(ph + 0.3),
		"cam_pitch": 0.01 * sin(ph * 2.0),
	})
	var seed := idle_key if t < 0.001 else {}
	return _solve(body, _idle_target(ph), seed, [idle_swivel], 1.0, false)


func run(t: float) -> Dictionary:
	var ph := TAU * t / RUN_TOTAL
	var body := _body({
		"body_pitch": (7.5 + 1.3 * sin(ph * 2.0)) * D2R,
		"body_roll": 2.0 * sin(ph) * D2R,
		"body_yaw": 1.6 * sin(ph + 0.5) * D2R,
		"root_yaw": 2.2 * sin(ph) * D2R,
		"body_lift": -0.006 + 0.010 * sin(ph * 2.0 + 0.6),
		"body_sway": 0.010 * sin(ph + 0.3),
		"body_shift": 0.008 * sin(ph * 2.0 + 0.2),
		"cam_yaw": -2.0 * D2R,
	})
	var pos := Vector3(0.260 + 0.020 * sin(ph), 1.160 + 0.020 * sin(ph * 2.0 + 0.9),
		0.460 + 0.014 * cos(ph))
	var d := Vector3(0.06 + 0.03 * sin(ph + 0.4), 0.30 + 0.03 * sin(ph * 2.0 + 1.1),
		0.95).normalized()
	var seed := idle_key if t < 0.001 else {}
	return _solve(body, _sword(pos, d, Vector3(1, 0, 0)), seed, [idle_swivel], 1.0, false)


# ------------------------------------------------------------------ attack 1

func _build_attack1() -> void:
	var lead := clampf(float(P.get("attack1_lead", 1.0)), 0.55, 1.8)
	var follow := clampf(float(P.get("attack1_follow", 1.0)), 0.45, 2.2)
	var over := clampf(float(P.get("attack1_overshoot", 1.0)), 0.0, 2.0)
	var t_lift := 0.11 * lead
	var t_raise := 0.23 * lead
	var t_top := 0.32 * lead
	var t_strike := 0.395 * lead
	var t_hit := 0.455 * lead
	var t_hold := t_hit + 0.022
	var t_fol := t_hit + 0.095 * follow
	var t_rec := t_hit + 0.30 * follow
	var t_end := t_hit + 0.62 * follow
	attack1_keys.clear()
	attack1_keys.append({"t": 0.0, "body": idle_body, "target": _idle_target(0.0),
		"blade": 1.0, "label": "idle", "pose": idle_key})
	var b1 := _body({"body_pitch": -1.5 * D2R, "body_roll": 0.5 * D2R,
		"body_lift": 0.004, "body_shift": -0.004})
	var k1 := _key(t_lift, b1, _sword(Vector3(0.10, 1.260, 0.460),
		Vector3(0.02, 0.60, 0.795), Vector3(1, 0, 0)), "a1/lift1", idle_key)
	attack1_keys.append(k1)
	var b2 := _body({"body_pitch": -3.0 * D2R, "body_roll": 1.0 * D2R,
		"body_lift": 0.008, "body_shift": -0.008})
	var k2 := _key(t_raise, b2, _sword(Vector3(0.035, 1.420, 0.140),
		Vector3(0.0, 0.925, -0.380), Vector3(1, 0, 0)), "a1/raise", k1["pose"])
	attack1_keys.append(k2)
	var b3 := _body({"body_pitch": -4.8 * D2R, "body_roll": 0.6 * D2R,
		"body_lift": 0.010, "body_shift": -0.010, "cam_pitch": 0.10})
	var k3 := _key(t_top, b3, _sword(Vector3(0.0, 1.570, 0.050),
		Vector3(0.0, 0.990, -0.140), Vector3(1, 0, 0)), "a1/top", k2["pose"])
	attack1_keys.append(k3)
	var b4 := _body({"body_pitch": 2.0 * D2R, "body_roll": -0.4 * D2R,
		"body_lift": 0.002, "body_shift": 0.004, "cam_pitch": -0.04})
	var k4 := _key(t_strike, b4, _sword(Vector3(0.0, 1.270, 0.500),
		Vector3(0.0, 0.170, 0.985), Vector3(1, 0, 0)), "a1/strike", k3["pose"])
	attack1_keys.append(k4)
	var b5 := _body({"body_pitch": 6.0 * D2R, "body_roll": -1.2 * D2R,
		"body_lift": -0.014, "body_shift": 0.012, "cam_pitch": -0.10})
	var k5 := _key(t_hit, b5, _sword(Vector3(0.02, 0.980, 0.630),
		Vector3(0.0, -0.620, 0.785), Vector3(1, 0, 0)), "a1/hit", k4["pose"])
	attack1_keys.append(k5)
	var k5h := _key(t_hold, b5, _sword(Vector3(0.02, 0.978, 0.634),
		Vector3(0.0, -0.625, 0.780), Vector3(1, 0, 0)), "a1/hold", k5["pose"])
	attack1_keys.append(k5h)
	var b6 := _body({"body_pitch": (6.0 + 2.0 * over) * D2R, "body_roll": -1.6 * D2R,
		"body_lift": -0.018, "body_shift": 0.015, "cam_pitch": -0.12})
	var k6 := _key(t_fol, b6, _sword(Vector3(0.03, 0.918, 0.664),
		Vector3(0.0, -0.700, 0.714), Vector3(1, 0, 0)), "a1/follow", k5h["pose"])
	attack1_keys.append(k6)
	var b7 := _body({"body_pitch": 2.4 * D2R, "body_roll": -0.4 * D2R,
		"body_lift": -0.004, "body_shift": 0.004})
	var k7 := _key(t_rec, b7, _sword(Vector3(0.120, 1.000, 0.552),
		Vector3(0.0, -0.060, 0.998), Vector3(1, 0, 0)), "a1/recover", k6["pose"])
	attack1_keys.append(k7)
	attack1_keys.append({"t": t_end, "body": idle_body, "target": _idle_target(0.0),
		"blade": 1.0, "label": "idle2", "pose": idle_key})
	for k in attack1_keys:
		var lb := str(k["label"])
		k["lin"] = lb in ["a1/top", "a1/strike", "a1/hit", "a1/hold", "a1/follow"]
	var sw := kin.swivel_of(idle_key)
	var out := _build_traj_raw("attack1", attack1_keys, sw)
	_smooth_traj(out, attack1_keys)
	if not out.is_empty():
		var t0 := _label_time(attack1_keys, "a1/top")
		var t1 := _label_time(attack1_keys, "a1/hit")
		var t2 := _label_time(attack1_keys, "a1/follow")
		_retime_by_tip(out, t0, t1, t2)
		_land_idle(out, 0.16)
	trajs["attack1"] = out
	clip_dur["attack1"] = float(out[out.size() - 1]["t"]) if not out.is_empty() else 1.0
	clip_swivel["attack1"] = sw


# ------------------------------------------------------------------ attack 2

func _build_attack2() -> void:
	var lead := clampf(float(P.get("attack2_lead", 1.0)), 0.55, 1.8)
	var follow := clampf(float(P.get("attack2_follow", 1.0)), 0.45, 2.2)
	var over := clampf(float(P.get("attack2_overshoot", 1.0)), 0.0, 2.0)
	var t_raise := 0.095 * lead
	var t_coil := 0.20 * lead
	var t_hold := 0.30 * lead
	var t_s1 := 0.38 * lead
	var t_s2 := 0.46 * lead
	var t_s3 := 0.545 * lead
	var t_fol := 0.635 * lead
	var t_over := t_fol + 0.055 * follow
	var t_rec := t_fol + 0.22 * follow
	var t_end := t_fol + 0.52 * follow
	attack2_keys.clear()
	attack2_keys.append({"t": 0.0, "body": idle_body, "target": _idle_target(0.0),
		"blade": 1.0, "label": "idle", "pose": idle_key})
	var b0 := _body({"root_yaw": -2.0 * D2R, "body_yaw": -1.0 * D2R,
		"body_pitch": 0.5 * D2R, "body_lift": 0.004})
	var k0 := _key(t_raise, b0, _sword(Vector3(-0.100, 1.300, 0.440),
		Vector3(-0.350, 0.250, 0.902), Vector3.UP), "a2/raise", idle_key)
	attack2_keys.append(k0)
	var b1 := _body({"root_yaw": -9.0 * D2R, "body_yaw": -4.5 * D2R,
		"body_pitch": 1.0 * D2R, "body_roll": -1.0 * D2R,
		"body_lift": -0.004, "body_sway": -0.008, "body_shift": -0.006})
	var k1 := _key(t_coil, b1, _sword(Vector3(-0.440, 1.210, 0.100),
		Vector3(-0.660, 0.0, -0.751), Vector3.UP), "a2/coil", k0["pose"])
	attack2_keys.append(k1)
	var b2 := _body({"root_yaw": -12.0 * D2R, "body_yaw": -6.0 * D2R,
		"body_pitch": 1.0 * D2R, "body_roll": -1.8 * D2R,
		"body_lift": -0.008, "body_sway": -0.012, "body_shift": -0.008})
	var k2 := _key(t_hold, b2, _sword(Vector3(-0.468, 1.222, -0.024),
		Vector3(-0.800, 0.0, -0.600), Vector3.UP), "a2/coil2", k1["pose"])
	attack2_keys.append(k2)
	var b3 := _body({"root_yaw": -5.0 * D2R, "body_yaw": -3.0 * D2R,
		"body_pitch": 2.0 * D2R, "body_roll": -1.0 * D2R,
		"body_lift": -0.004, "body_sway": -0.006, "body_shift": 0.002})
	var k3 := _key(t_s1, b3, _sword(Vector3(-0.360, 1.232, 0.560),
		Vector3(-0.300, 0.0, 0.954), Vector3.UP), "a2/sweep1", k2["pose"])
	attack2_keys.append(k3)
	var b4 := _body({"root_yaw": 0.0, "body_yaw": 0.0,
		"body_pitch": 2.5 * D2R, "body_roll": 0.0,
		"body_lift": -0.002, "body_shift": 0.006})
	var k4 := _key(t_s2, b4, _sword(Vector3(-0.040, 1.240, 0.660),
		Vector3(0.200, 0.0, 0.980), Vector3.UP), "a2/sweep2", k3["pose"])
	attack2_keys.append(k4)
	var b5 := _body({"root_yaw": 6.0 * D2R, "body_yaw": 3.0 * D2R,
		"body_pitch": 2.0 * D2R, "body_roll": 1.0 * D2R,
		"body_lift": -0.004, "body_sway": 0.006, "body_shift": 0.006})
	var k5 := _key(t_s3, b5, _sword(Vector3(0.300, 1.230, 0.520),
		Vector3(0.720, 0.0, 0.694), Vector3.UP), "a2/sweep3", k4["pose"])
	attack2_keys.append(k5)
	var b6 := _body({"root_yaw": 12.0 * D2R, "body_yaw": 5.0 * D2R,
		"body_pitch": 1.0 * D2R, "body_roll": 1.6 * D2R,
		"body_lift": -0.008, "body_sway": 0.012, "body_shift": 0.008})
	var k6 := _key(t_fol, b6, _sword(Vector3(0.456, 1.210, 0.140),
		Vector3(0.920, 0.0, -0.392), Vector3.UP), "a2/follow", k5["pose"])
	attack2_keys.append(k6)
	var b7 := _body({"root_yaw": (12.0 + 2.0 * over) * D2R, "body_yaw": (5.0 + 1.5 * over) * D2R,
		"body_pitch": 0.5 * D2R, "body_roll": 2.0 * D2R,
		"body_lift": -0.010, "body_sway": 0.014, "body_shift": 0.010})
	var k7 := _key(t_over, b7, _sword(Vector3(0.464, 1.196, 0.090),
		Vector3(0.940, 0.0, -0.342), Vector3.UP), "a2/overshoot", k6["pose"])
	attack2_keys.append(k7)
	var b8 := _body({"root_yaw": 4.0 * D2R, "body_yaw": 1.5 * D2R,
		"body_pitch": 1.5 * D2R, "body_roll": 0.6 * D2R,
		"body_lift": -0.002, "body_sway": 0.004})
	var k8 := _key(t_rec, b8, _sword(Vector3(0.400, 1.100, 0.460),
		Vector3(0.500, 0.030, 0.866), Vector3(1, 0, 0)), "a2/recover", k7["pose"])
	attack2_keys.append(k8)
	attack2_keys.append({"t": t_end, "body": idle_body, "target": _idle_target(0.0),
		"blade": 1.0, "label": "idle2", "pose": idle_key})
	for k in attack2_keys:
		var lb2 := str(k["label"])
		k["lin"] = lb2 in ["a2/coil2", "a2/sweep1", "a2/sweep2", "a2/sweep3",
			"a2/follow", "a2/overshoot"]
	var sw := kin.swivel_of(idle_key)
	var out := _build_traj_raw("attack2", attack2_keys, sw)
	_smooth_traj(out, attack2_keys)
	if not out.is_empty():
		var t0 := _label_time(attack2_keys, "a2/coil2")
		var t1 := _label_time(attack2_keys, "a2/sweep2")
		var t2 := _label_time(attack2_keys, "a2/follow")
		_retime_by_tip(out, t0, t1, t2)
		_land_idle(out, 0.16)
	trajs["attack2"] = out
	clip_dur["attack2"] = float(out[out.size() - 1]["t"]) if not out.is_empty() else 1.0
	clip_swivel["attack2"] = sw


# ------------------------------------------------------------------ block plan

## Plan a sword parry against a threat arriving from `az_deg` (0 = straight
## ahead, + = character's left) and `elev_deg`.  Returns stats; the clip is
## stored in trajs["block"].
func plan_block(az_deg: float, elev_deg: float) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	block_threat_deg = az_deg
	block_elev_deg = elev_deg
	var key := "%.1f/%.1f" % [az_deg, elev_deg]
	if _block_cache.has(key):
		var cached: Dictionary = _block_cache[key]
		trajs["block"] = cached["samples"]
		clip_dur["block"] = float(cached["dur"])
		block_stats = (cached["stats"] as Dictionary).duplicate()
		block_stats["plan_ms"] = int((Time.get_ticks_usec() - t0) / 1000)
		block_stats["cached"] = true
		block_ms = int(block_stats["plan_ms"])
		return block_stats
	var az := az_deg * D2R
	var el := clampf(elev_deg, -20.0, 20.0) * D2R
	var d := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
	var chest := kin.chest_point()
	var body := _body({
		"body_pitch": 2.2 * D2R,
		"body_yaw": clampf(-az_deg * 0.10, -6.0, 6.0) * D2R,
		"body_roll": clampf(-az_deg * 0.03, -2.0, 2.0) * D2R,
		"body_lift": -0.012,
		"body_sway": clampf(az_deg * 0.0003, -0.01, 0.01),
		"cam_yaw": clampf(-az_deg * 0.5, -12.0, 12.0) * D2R,
	})
	var horiz := d.cross(Vector3.UP)
	if horiz.length_squared() < 1e-6:
		horiz = Vector3.RIGHT
	horiz = horiz.normalized()
	var best: Dictionary = {}
	var best_score := -1e9
	var base := _base(body)
	var shoulder := kin.shoulder_world(body)
	var reach_max: float = kin.L1 + kin.L2 - 0.010
	# The tool sits `u` back along the blade from the intercept point, which
	# lies `depth` in front of the chest on the threat line.  The blade is
	# perpendicular to the threat and always tilted UP (a down-tilted parry
	# would put the tip into the track deck).
	for depth in [0.44, 0.56]:
		for u in [0.36, 0.54]:
			for tilt in [-26.0, -6.0]:
				for hsgn in [-1.0, 1.0]:
					var bd: Vector3 = horiz * (float(hsgn) * cos(float(tilt) * D2R)) \
						+ Vector3.UP * sin(float(tilt) * D2R)
					bd = (bd - d * bd.dot(d)).normalized()
					var tool: Vector3 = chest + d * float(depth) - bd * float(u)
					if (tool - shoulder).length() > reach_max:
						continue
					var tgt := _sword_world(tool, bd, d)
					var sol := kin.arm_solve(tool, tgt["basis"], base,
						{"swivels": [0.0, -48.0, 48.0]}, [])
					if sol.is_empty() or not bool(sol.get("ok", false)):
						continue
					if bool(sol.get("clamped", false)):
						continue
					var pose := base.duplicate()
					_merge(pose, sol)
					var au := kin.audit(pose, false, 0.040)
					var clr := float(au["min"])
					var score := minf(clr, 0.030) * 4.0 - 0.010 * float(sol.get("cost", 0.0))
					if clr < -0.002:
						score -= 1.0
					if score > best_score:
						best_score = score
						best = {"pose": pose, "tilt": float(tilt) * float(hsgn),
							"range": float(depth), "tool": tool, "dir": bd,
							"clear": clr, "target": tgt}
	var t_cand := Time.get_ticks_usec()
	var guard_pose: Dictionary = best["pose"]
	var lead := clampf(float(P.get("block_lead", 1.0)), 0.5, 1.8)
	var hold := clampf(float(P.get("block_hold", 1.0)), 0.35, 2.4)
	var follow := clampf(float(P.get("block_follow", 1.0)), 0.5, 2.0)
	var t_guard := 0.20 * lead
	var t_hold := t_guard + 0.34 * hold
	var t_end := t_hold + 0.34 * follow
	var mid_tool := (IDLE_TOOL as Vector3).lerp(best["tool"] as Vector3, 0.55)
	# the transition lifts the blade over the deck before dropping into the
	# guard, so the tip never sweeps down through the tracks
	mid_tool.y = maxf(mid_tool.y + 0.060, 1.230)
	mid_tool.z = maxf(mid_tool.z, 0.500)
	var mid_dir := (IDLE_DIR as Vector3).lerp(best["dir"] as Vector3, 0.45).normalized()
	var mid := _sword(mid_tool, mid_dir, (IDLE_DIR as Vector3).lerp(d, 0.55).normalized())
	var guard: Dictionary = best["target"]
	block_keys = [
		{"t": 0.0, "body": idle_body, "target": _idle_target(0.0), "blade": 1.0,
			"label": "idle", "pose": idle_key},
		_key(t_guard * 0.55, _body({
			"body_yaw": float(body["body_yaw"]) * 0.55,
			"body_pitch": float(body["body_pitch"]) * 0.6,
			"body_lift": float(body["body_lift"]) * 0.5,
			"cam_yaw": float(body["cam_yaw"]) * 0.6,
		}), mid, "block/mid", idle_key, {"swivels": [0.0, -48.0, 48.0]}),
		_key(t_guard, body, guard, "block/guard", idle_key, {}, guard_pose),
	]
	block_keys.append(_key(t_hold, body, guard, "block/hold", guard_pose, {}, guard_pose))
	# return along the same lifted arc so the long blade cannot sweep through
	# the upper arm on the way back
	var mid_pose: Dictionary = block_keys[1]["pose"]
	block_keys.append(_key(t_hold + 0.14 * follow, _body({
		"body_yaw": float(body["body_yaw"]) * 0.45,
		"body_pitch": float(body["body_pitch"]) * 0.5,
		"body_lift": float(body["body_lift"]) * 0.4,
		"cam_yaw": float(body["cam_yaw"]) * 0.5,
	}), mid, "block/release", mid_pose, {}, mid_pose))
	block_keys.append({"t": t_end, "body": idle_body, "target": _idle_target(0.0),
		"blade": 1.0, "label": "idle2", "pose": idle_key})
	var t_keys := Time.get_ticks_usec()
	var out := _build_traj_raw("block", block_keys, kin.swivel_of(idle_key), false, 32.0, 1)
	var t_traj := Time.get_ticks_usec()
	_land_idle(out, 0.14)
	# snap the guard window to real samples so the sampled guard pose is the
	# solved guard exactly
	var idx_guard := 0
	var idx_hold := 0
	var best_d := 1e9
	var best_dh := 1e9
	for i in out.size():
		var dt := absf(float(out[i]["t"]) - t_guard)
		var dth := absf(float(out[i]["t"]) - t_hold)
		if dt < best_d:
			best_d = dt
			idx_guard = i
		if dth < best_dh:
			best_dh = dth
			idx_hold = i
	t_guard = float(out[idx_guard]["t"])
	t_hold = float(out[idx_hold]["t"])
	var worst: float = last_worst
	var wp: Array = last_worst_pair
	var guard_sample: Dictionary = out[idx_guard]["pose"]
	var miss := _block_miss(guard_sample, d)
	var face_err := rad_to_deg(acos(clampf((kin.arm_fk(guard_sample)["face"] as Vector3).dot(d), -1.0, 1.0)))
	var dur := float(out[out.size() - 1]["t"]) if not out.is_empty() else 1.0
	trajs["block"] = out
	clip_dur["block"] = dur
	if OS.get_environment("BLOCK_PROF") != "":
		print("    [block prof] cand %.1f  keys %.1f  traj %.1f ms" % [
			(t_cand - t0) / 1000.0, (t_keys - t_cand) / 1000.0, (t_traj - t_keys) / 1000.0])
	block_stats = {
		"effector": "blade",
		"threat": az_deg, "elev": elev_deg,
		"plan_ms": int((Time.get_ticks_usec() - t0) / 1000),
		"dur": dur, "t_guard": t_guard, "t_hold": t_hold,
		"tilt": float(best["tilt"]), "range": float(best["range"]),
		"min_clear": worst, "min_pair": wp,
		"miss": miss, "face_err": face_err,
		"guarded": miss <= 0.02 and face_err <= 25.0 and worst > 0.004,
		"cached": false,
	}
	block_plan_raw_ms = int(block_stats["plan_ms"])
	_block_cache[key] = {"samples": out, "dur": dur, "stats": block_stats.duplicate()}
	block_ms = int(block_stats["plan_ms"])
	return block_stats


## Joint-space sampling for the block: the planner has already chosen the
## guard, so a joint fade cannot change the chosen blade line.  Every sample is
## audited; a colliding sample is repaired with the Cartesian solver.
func _build_block_traj(keys: Array) -> Dictionary:
	var dur := float(keys[keys.size() - 1]["t"])
	var steps := maxi(4, int(ceil(dur * 56.0)))
	var out: Array = []
	var worst := 9.0
	var wp := ["", ""]
	for i in steps + 1:
		var t := dur * float(i) / float(steps)
		var seg := _segment_index(keys, t)
		var ka: Dictionary = keys[seg]
		var kb: Dictionary = keys[seg + 1]
		var u := clampf((t - float(ka["t"])) /
			maxf(float(kb["t"]) - float(ka["t"]), 1e-6), 0.0, 1.0)
		var ee := smoothstep(0.0, 1.0, u)
		var pose := ArcKin3.blend_pose(ka["pose"], kb["pose"], ee)
		var clear := 9.0
		if i % 4 == 0 or i == steps:
			var au := kin.audit(pose)
			clear = float(au["min"])
			if clear < worst:
				worst = clear
				wp = au["pair"]
		else:
			clear = kin.blade_clear(pose)
			if clear < worst:
				worst = clear
				wp = ["blade", "body"]
		if clear < 0.004:
			var body := _interp_body(ka["body"], kb["body"], ee)
			var target := _interp_target(ka["target"], kb["target"], u)
			_guard_blade(target)
			pose = _repair_sample(body, target, ka["pose"], idle_swivel, pose)
		out.append({"t": t, "pose": pose})
	return {"samples": out, "min": worst, "pair": wp}


func _block_miss(pose: Dictionary, d: Vector3) -> float:
	var fk := kin.arm_fk(pose)
	var a: Vector3 = fk["tool"]
	var b: Vector3 = fk["tip"]
	var chest := kin.chest_point()
	var origin := chest + d * 1.8
	var end := chest - d * 0.05
	return kin.seg_seg_dist(origin, end, a, b)


# ------------------------------------------------------------------ keys

func _key(t: float, body: Dictionary, target: Dictionary, label: String,
		seed := {}, opts := {}, pose_override := {}) -> Dictionary:
	var pose: Dictionary
	if not pose_override.is_empty():
		pose = pose_override.duplicate()
	else:
		var sv: Array = opts.get("swivels", [])
		pose = _solve(body, target, seed, sv, 1.0)
	return {"t": t, "body": body, "target": target, "blade": 1.0,
		"label": label, "pose": pose}


func _label_time(keys: Array, label: String) -> float:
	for k in keys:
		if str(k.get("label", "")) == label:
			return float(k["t"])
	return -1.0


# ------------------------------------------------------------------ trajectories

func _choose_swivel(name: String, keys: Array) -> float:
	var best := 0.0
	var best_score := -1e9
	for sv in SWIVELS:
		var out := _build_traj_raw(name, keys, float(sv), true)
		var score := 9.0
		for i in range(0, out.size(), 3):
			score = minf(score, float(kin.audit(out[i]["pose"])["min"]))
		var ep := 0.0
		for i in range(1, out.size(), 3):
			var q1: Quaternion = out[i]["pose"].get("elb_q", Quaternion())
			var q0: Quaternion = out[i - 1]["pose"].get("elb_q", Quaternion())
			ep = maxf(ep, q0.angle_to(q1))
		score -= ep * 0.15
		if score > best_score:
			best_score = score
			best = float(sv)
	return best


func _build_traj_raw(name: String, keys: Array, swivel: float, probe := false,
		hz := TRAJ_HZ, n_swivel := 5) -> Array:
	var dur := float(keys[keys.size() - 1]["t"])
	var steps := maxi(2, int(ceil(dur * hz)))
	var out: Array = []
	last_worst = 9.0
	last_worst_pair = ["", ""]
	var prev: Dictionary = keys[0]["pose"]
	out.append({"t": 0.0, "pose": prev})
	for i in range(1, steps + 1):
		var t := dur * float(i) / float(steps)
		var seg := _segment_index(keys, t)
		var ka: Dictionary = keys[seg]
		var kb: Dictionary = keys[seg + 1]
		var u := clampf((t - float(ka["t"])) /
			maxf(float(kb["t"]) - float(ka["t"]), 1e-6), 0.0, 1.0)
		var lin := bool(ka.get("lin", false)) or bool(kb.get("lin", false))
		var ee := u if lin else smoothstep(0.0, 1.0, u)
		var body := _interp_body(ka["body"], kb["body"], ee)
		var target := _interp_target(ka["target"], kb["target"], u)
		_guard_blade(target)
		if probe:
			var pp := _solve_traj_sample(body, target, prev, kin.swivel_of(prev))
			pp = _unwrap_pose(prev, pp)
			out.append({"t": t, "pose": pp})
			prev = pp
			continue
		var pose := _solve_traj_sample(body, target, prev, kin.swivel_of(prev), n_swivel)
		pose = _unwrap_pose(prev, pose)
		var au := kin.audit(pose)
		if float(au["min"]) < 0.0015:
			if OS.get_environment("BLOCK_PROF") != "" and name == "block":
				print("      repair t %.3f clr %+.4f %s" % [t, float(au["min"]), str(au["pair"])])
			pose = _repair_sample(body, target, prev, kin.swivel_of(prev), pose, 5)
			pose = _unwrap_pose(prev, pose)
			au = kin.audit(pose)
		if float(au["min"]) < last_worst:
			last_worst = float(au["min"])
			last_worst_pair = au["pair"]
		if float(au["min"]) < 0.0:
			key_stats.append({"label": name, "t": t, "clear": float(au["min"]),
				"pair": au["pair"]})
		out.append({"t": t, "pose": pose})
		prev = pose
	return out


func _solve_traj_sample(body: Dictionary, target: Dictionary, prev: Dictionary,
		center: float, n_swivel := 5) -> Dictionary:
	var base := _base(body)
	base["_seed"] = prev
	base["_traj"] = 1.0
	# with a single swivel the obstacle ranking is pointless; the per-sample
	# audit below is the actual collision check
	var obs: Array = _body_obstacles(base) if n_swivel > 1 else []
	var sv: Array = [center]
	if n_swivel >= 3:
		sv.append(center + 18.0)
		sv.append(center - 18.0)
	if n_swivel >= 5:
		sv.append(center + 34.0)
		sv.append(center - 34.0)
	var sol := kin.arm_solve(target["tool"], target["basis"], base,
		{"swivels": sv}, obs)
	var pose := base.duplicate()
	if not sol.is_empty() and bool(sol.get("ok", false)):
		_merge(pose, sol)
	return pose


func _repair_sample(body: Dictionary, target: Dictionary, prev: Dictionary,
		swivel: float, fallback: Dictionary, n: int = 5) -> Dictionary:
	var best := fallback
	var best_clear := float(kin.audit(fallback)["min"])
	# 1) nudge the tool outward / upward (cheap, keeps the authored blade line
	#    direction and only shifts the whole line a few centimetres)
	var tool: Vector3 = target["tool"]
	var outward := Vector3(tool.x, 0.0, tool.z)
	if outward.length_squared() < 1e-6:
		outward = Vector3.FORWARD
	outward = outward.normalized()
	for off in [outward * 0.05, Vector3(0, 0.05, 0), outward * 0.05 + Vector3(0, 0.04, 0),
			outward * 0.09, Vector3(0, 0.09, 0)]:
		var t2 := {"tool": tool + off, "basis": target["basis"]}
		var p2 := _solve_traj_sample(body, t2, prev, swivel, 1)
		var c2 := float(kin.audit(p2)["min"])
		if c2 > best_clear:
			best_clear = c2
			best = p2
		if best_clear > 0.006:
			return best
	# 2) swivel variations around the current branch
	var sys: Array = []
	for k in n:
		var step := float(k) * 20.0
		sys.append(swivel + step)
		sys.append(swivel - step)
	for sv in sys:
		var p := _solve_traj_sample(body, target, prev, float(sv), 1)
		var c := float(kin.audit(p)["min"])
		if c > best_clear:
			best_clear = c
			best = p
		if best_clear > 0.010:
			break
	return best


func _interp_body(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		if a.has(k) and (a[k] is float):
			out[k] = lerpf(float(a[k]), float(b[k]), u)
	return out


func _interp_target(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var pos: Vector3 = (a["tool"] as Vector3).lerp(b["tool"] as Vector3, u)
	var basis: Basis = (a["basis"] as Basis).slerp(b["basis"] as Basis, u).orthonormalized()
	return {"tool": pos, "basis": basis}


func _guard_blade(t: Dictionary) -> void:
	var b: Basis = t["basis"]
	var d := b * Vector3(0, -1, 0)
	var tip: Vector3 = (t["tool"] as Vector3) + d * kin.blade_len
	if tip.y < 0.16:
		t["tool"] = (t["tool"] as Vector3) + Vector3(0, 0.16 - tip.y, 0)


func _segment_index(keys: Array, t: float) -> int:
	for i in keys.size() - 1:
		if t <= float(keys[i + 1]["t"]) + 1e-9:
			return i
	return keys.size() - 2


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
		var lo := maxi(i - 3, 0)
		var hi := mini(i + 3, out.size() - 1)
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
		if float(kin.audit(p)["min"]) < 0.010:
			for k in orig:
				p[k] = orig[k]


## Re-time [t0,t1,t2] by tip arc length: accelerate into t1 (the impact), then
## decelerate out of it.  Times after t2 are untouched.
func _retime_by_tip(out: Array, t0: float, t1: float, t2: float) -> void:
	if t0 < 0.0 or t1 <= t0 or t2 <= t1:
		return
	var i0 := -1
	var i1 := -1
	var i2 := -1
	for i in out.size():
		var t := float(out[i]["t"])
		if i0 < 0 and t >= t0 - 1e-6:
			i0 = i
		if i1 < 0 and t >= t1 - 1e-6:
			i1 = i
		if i2 < 0 and t >= t2 - 1e-6:
			i2 = i
	if i0 < 0 or i1 <= i0 + 1 or i2 <= i1 + 1:
		return
	var s1 := _tip_arc(out, i0, i1)
	var s2 := _tip_arc(out, i1, i2)
	if s1 < 1e-5 or s2 < 1e-5:
		return
	var acc := 0.0
	for i in range(i0 + 1, i1 + 1):
		acc += _tip_step(out, i - 1)
		var u := clampf(acc / s1, 0.0, 1.0)
		out[i]["t"] = t0 + (t1 - t0) * sqrt(u)
	acc = 0.0
	for i in range(i1 + 1, i2 + 1):
		acc += _tip_step(out, i - 1)
		var u := clampf(acc / s2, 0.0, 1.0)
		out[i]["t"] = t1 + (t2 - t1) * (1.0 - sqrt(maxf(0.0, 1.0 - u)))


func _tip_step(out: Array, i: int) -> float:
	var a: Vector3 = _tip_of(out[i]["pose"])
	var b: Vector3 = _tip_of(out[i + 1]["pose"])
	return a.distance_to(b)


func _tip_arc(out: Array, i0: int, i1: int) -> float:
	var total := 0.0
	for i in range(i0, i1):
		total += _tip_step(out, i)
	return total


func _tip_of(pose: Dictionary) -> Vector3:
	return kin.arm_fk(pose)["tip"]


## Blend the tail of a clip into the exact idle base so the clip ends on the
## same pose the live idle loop uses (no transition pop).
func _land_idle(out: Array, span: float) -> void:
	if out.size() < 2:
		return
	var t_end := float(out[out.size() - 1]["t"])
	var t0 := maxf(0.0, t_end - span)
	for s in out:
		var t := float(s["t"])
		if t <= t0:
			continue
		var w := smoothstep(0.0, 1.0, (t - t0) / maxf(t_end - t0, 1e-6))
		s["pose"] = ArcKin3.blend_pose(s["pose"], idle_key, w)
	out[out.size() - 1]["pose"] = idle_key.duplicate()


func _limit_qdot(out: Array, max_qdot: float) -> void:
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
		var dt_req := peak / max_qdot if peak > 0.0001 else 0.0
		t += maxf(1.0 / TRAJ_HZ, dt_req)
		out[i]["t"] = t


func _unwrap_pose(prev: Dictionary, pose: Dictionary) -> Dictionary:
	for k in pose:
		if k.begins_with("_") or not (pose[k] is float) or not prev.has(k):
			continue
		pose[k] = float(prev[k]) + wrapf(float(pose[k]) - float(prev[k]), -PI, PI)
	return pose


# ------------------------------------------------------------------ sampling

func duration(name: String) -> float:
	if clip_dur.has(name):
		return float(clip_dur[name])
	if name == "idle":
		return IDLE_TOTAL
	if name == "run":
		return RUN_TOTAL
	return 1.0


func sample(name: String, t: float) -> Dictionary:
	if name == "idle":
		return idle(t)
	if name == "run":
		return run(t)
	if not trajs.has(name):
		return idle(t)
	return _sample_traj(name, t)


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
			return ArcKin3.blend_pose(a["pose"], b["pose"], u)
	return (tr[tr.size() - 1]["pose"] as Dictionary).duplicate()


func action_key(name: String, which: String) -> Dictionary:
	var keys: Array = attack1_keys if name == "attack1" else (attack2_keys if name == "attack2" else block_keys)
	var want := ""
	if name == "attack1":
		want = "a1/" + which
	elif name == "attack2":
		want = "a2/" + which
	else:
		want = "block/" + which
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
			if k.begins_with("_") or not b.has(k):
				continue
			if a[k] is Quaternion and b[k] is Quaternion:
				best = maxf(best, (a[k] as Quaternion).angle_to(b[k] as Quaternion) / dt)
	return best


func traj_min_clear(name: String, margin := 0.06) -> Dictionary:
	if not trajs.has(name):
		return {"min": 0.0, "pair": ["", ""]}
	var worst := 9.0
	var wp := ["", ""]
	for s in trajs[name]:
		var a := kin.audit(s["pose"], false, margin)
		if float(a["min"]) < worst:
			worst = float(a["min"])
			wp = a["pair"]
	return {"min": worst, "pair": wp}


# ------------------------------------------------------------------ optic aim

## Aim direction for the rotating inner optic ball, in body space.
static func eye_aim(body_basis: Basis, eye_world: Vector3, target: Vector3) -> Vector2:
	var local := body_basis.inverse() * (target - eye_world)
	if local.length_squared() < 1e-8:
		return Vector2.ZERO
	local = local.normalized()
	var yaw := atan2(local.x, local.z)
	var pitch := -asin(clampf(local.y, -1.0, 1.0))
	return Vector2(clampf(yaw, -62.0 * D2R, 62.0 * D2R),
		clampf(pitch, -42.0 * D2R, 42.0 * D2R))
extends RefCounted
class_name ArcKin2
## ARC // SENTINEL v2 — analytic arm kinematics + collision audit.
##
## Arms are 3 ball joints (shoulder / elbow / wrist). The solver treats the
## shoulder+elbow as a 2-bone chain with one free swivel angle around the
## shoulder→wrist axis, and the wrist as a 3-DOF tool aligner. This is the
## classical analytic "swivel" IK (Korein & Badler 1982; Tolani et al. 2000)
## instead of an iterative full-arm solve: exact, deterministic, microsecond
## cost. A small set of swivel candidates is ranked by joint-limit cost and
## self-collision, which replaces the usual null-space projection.
##
## Collision proxies are capsules / discs. Every pair that is not a neighbour
## in the same kinematic chain is checked; `audit()` is used by the runtime
## planner, the QA harness and the acceptance scenes.

const D2R := PI / 180.0
const TAU := PI * 2.0
const EPS := 1e-6

# ---------------------------------------------------------------- dimensions
var P: Dictionary = {}

var body_y := 0.620
var torso_y := 0.160
var hull_y := 0.280
var hull_r := 0.225
var hull_half := 0.260
var cam_y := 0.280
var cam_z := 0.330
var cam_r := 0.120
var shoulder_x := 0.270
var shoulder_y := 0.320
var shoulder_z := 0.020
var L1 := 0.340
var L2 := 0.330
var L3 := 0.130
var shield_r := 0.310
var shield_off := 0.110
var blade_len := 1.030
var blade_half_w := 0.088
var blade_half_t := 0.050
var sheath_a := Vector3(0.280, 0.040, 0.180)
var sheath_b := Vector3(0.330, -0.120, -0.330)
var back_y := 0.280
var back_z := -0.300
var wheel_x := 0.450
var wheel_y := 0.300
var wheel_r := 0.300


func _init(p: Dictionary) -> void:
	P = p.duplicate()
	_apply_dims()


func _apply_dims() -> void:
	hull_r = float(P.get("hull_radius", 0.225))
	var body_scale: float = float(P.get("body_scale", 1.0))
	body_y = 0.620 * body_scale
	torso_y = 0.160 * body_scale
	hull_y = 0.280 * body_scale
	hull_half = 0.260 * body_scale
	cam_y = 0.280 * body_scale
	cam_z = 0.330 * body_scale
	cam_r = 0.120 * body_scale
	shoulder_x = 0.270 * body_scale
	shoulder_y = 0.320 * body_scale
	shoulder_z = 0.020 * body_scale
	L1 = 0.480 * body_scale
	L2 = 0.400 * body_scale
	L3 = 0.130 * body_scale
	shield_r = float(P.get("shield_radius", 0.310))
	shield_off = 0.110
	blade_len = float(P.get("blade_length", 1.030))
	blade_half_w = float(P.get("blade_width", 0.176)) * 0.5
	blade_half_t = 0.050
	sheath_a = Vector3(0.225, 0.090, 0.180) * body_scale
	sheath_b = Vector3(0.235, -0.020, -0.330) * body_scale
	back_y = 0.280 * body_scale
	back_z = -0.300 * body_scale
	wheel_x = 0.450 * body_scale
	wheel_r = float(P.get("wheel_radius", 0.325))
	wheel_y = wheel_r


func shoulder_local(side: int) -> Vector3:
	# side: +1 = left (+X), -1 = right (-X)
	return Vector3(float(side) * shoulder_x, shoulder_y, shoulder_z)


func body_xf(pose: Dictionary) -> Transform3D:
	var lift := float(pose.get("root_lift", 0.0))
	var sway := float(pose.get("root_sway", 0.0))
	var shift := float(pose.get("root_shift", 0.0))
	var basis := Basis.from_euler(Vector3(
		float(pose.get("body_pitch", 0.0)),
		float(pose.get("body_yaw", 0.0)),
		float(pose.get("body_roll", 0.0))))
	return Transform3D(basis, Vector3(sway, body_y + lift, shift))


func torso_xf(pose: Dictionary) -> Transform3D:
	var b := body_xf(pose)
	var local := Transform3D(
		Basis.from_euler(Vector3(
			float(pose.get("torso_pitch", 0.0)),
			float(pose.get("torso_yaw", 0.0)),
			float(pose.get("torso_roll", 0.0)))),
		Vector3(0.0, torso_y, 0.0))
	return b * local


func camera_xf(pose: Dictionary) -> Transform3D:
	var t := torso_xf(pose)
	var slide := clampf(float(pose.get("cam_slide", 0.0)), 0.0, 0.08)
	var drop := clampf(float(pose.get("cam_drop", 0.0)), 0.0, 0.36)
	var eye := Basis.from_euler(Vector3(
		float(pose.get("lens_pitch", 0.0)),
		float(pose.get("cam_yaw", 0.0)), 0.0))
	return t * Transform3D(eye, Vector3(0.0, cam_y - drop, cam_z - 0.020 - slide))


func lens_xf(pose: Dictionary) -> Transform3D:
	var t := torso_xf(pose)
	var yaw := Transform3D(Basis(Vector3.UP, float(pose.get("lens_yaw", 0.0))),
		Vector3(0.0, cam_y, cam_z))
	var pitch := Transform3D(Basis(Vector3.RIGHT, float(pose.get("lens_pitch", 0.0))), Vector3.ZERO)
	return t * yaw * pitch


# ---------------------------------------------------------------- basis utils

static func basis_from_y_z(y_axis: Vector3, z_hint: Vector3) -> Basis:
	var y := y_axis.normalized()
	var z := z_hint - y * z_hint.dot(y)
	if z.length_squared() < 1e-8:
		var alt := Vector3.FORWARD
		if absf(y.dot(alt)) > 0.95:
			alt = Vector3.RIGHT
		z = alt - y * alt.dot(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## Tool basis for a sword: local -Y is the blade axis, local Z is the face
## normal (the wide axis is local X).
static func sword_basis(blade_dir: Vector3, face_hint: Vector3) -> Basis:
	return basis_from_y_z(-blade_dir, face_hint)


## Tool basis for the shield: local Z is the shield normal, local Y is the
## shield "up".
static func shield_basis(normal: Vector3, up_hint := Vector3.UP) -> Basis:
	var z := normal.normalized()
	var y := up_hint - z * up_hint.dot(z)
	if y.length_squared() < 1e-8:
		y = Vector3.FORWARD - z * Vector3.FORWARD.dot(z)
	y = y.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


static func rot_x(a: float) -> Basis:
	return Basis(Vector3.RIGHT, a)


static func euler_of(b: Basis) -> Vector3:
	return b.get_euler()


# ---------------------------------------------------------------- arm FK

func _jbasis(pose: Dictionary, nm: String, j: String) -> Basis:
	var qk := "%s%s_q" % [j, nm]
	if pose.has(qk) and pose[qk] is Quaternion:
		return Basis(pose[qk] as Quaternion)
	return Basis.from_euler(Vector3(
		float(pose.get("%s%s_pitch" % [j, nm], 0.0)),
		float(pose.get("%s%s_yaw" % [j, nm], 0.0)),
		float(pose.get("%s%s_roll" % [j, nm], 0.0))))


func arm_fk(side: int, pose: Dictionary) -> Dictionary:
	var nm := "L" if side > 0 else "R"
	var sh := _jbasis(pose, nm, "sh")
	var el := _jbasis(pose, nm, "elb")
	var wr := _jbasis(pose, nm, "wr")
	var tx := torso_xf(pose)
	var s_local := shoulder_local(side)
	var s := tx * s_local
	var tb := tx.basis
	var e := s + tb * (sh * Vector3(0.0, -L1, 0.0))
	var w := e + tb * (sh * el * Vector3(0.0, -L2, 0.0))
	var bt := tb * sh * el * wr
	var t := w + bt * Vector3(0.0, -L3, 0.0)
	return {
		"s": s, "e": e, "w": w, "tool": t, "tool_basis": bt,
		"dir": bt * Vector3(0.0, -1.0, 0.0),
		"local_s": s_local,
	}


# ---------------------------------------------------------------- arm solve

## Solve one arm. `tool_pos` / `tool_basis` are root-space. Returns a dictionary
## with joint euler components, FK points, reach error and a validity flag.
func arm_solve(side: int, tool_pos: Vector3, tool_basis: Basis,
		pose: Dictionary, opts := {}, obstacles: Array = []) -> Dictionary:
	var tx := torso_xf(pose)
	var inv := tx.affine_inverse()
	var b_local := inv.basis * tool_basis
	# orthonormalise (torso basis is orthonormal; guard against caller error)
	b_local = b_local.orthonormalized()
	var t_local := inv * tool_pos
	var s := shoulder_local(side)
	var tool_off := b_local * Vector3(0.0, -L3, 0.0)
	var w := t_local - tool_off
	var d := w - s
	var r := d.length()
	var reach := r
	var r_max := L1 + L2 - 0.002
	var r_min := absf(L1 - L2) + 0.002
	var clamped := false
	if r > r_max:
		r = r_max
		clamped = true
	if r < r_min:
		r = r_min
		clamped = true
	if clamped:
		var u := d.normalized()
		w = s + u * r
		d = w - s
	var u := d.normalized()
	# pole: elbow points outward and slightly down/back
	var side_f := float(side)
	var pole := Vector3(side_f * 1.0, -0.55, -0.25)
	var perp := pole - u * pole.dot(u)
	if perp.length_squared() < 1e-8:
		perp = Vector3.UP - u * u.y
		if perp.length_squared() < 1e-8:
			perp = Vector3.FORWARD - u * u.z
	perp = perp.normalized()
	var side_axis := u.cross(perp).normalized()
	var a := (L1 * L1 - L2 * L2 + r * r) / (2.0 * r)
	var h2 := L1 * L1 - a * a
	var h := sqrt(maxf(h2, 0.0))
	var swivels: Array = opts.get("swivels", [-75.0, -55.0, -35.0, -18.0, 0.0, 18.0, 35.0, 55.0, 75.0])
	var best: Dictionary = {}
	var best_cost := 1e30
	for sv in swivels:
		var phi := float(sv) * D2R
		var e := s + u * a + (perp * cos(phi) + side_axis * sin(phi)) * h
		var cand := _solve_elbow(side, s, e, w, b_local, pose)
		if cand.is_empty():
			continue
		var cost := _joint_cost(cand, side, pose)
		if not obstacles.is_empty():
			var clr := _candidate_clearance(side, cand, pose, obstacles, b_local)
			cand["_clear_est"] = clr
			if clr < 0.030:
				cost += (0.030 - clr) * 180.0 + 1.5
		if cost < best_cost:
			best_cost = cost
			best = cand
	if best.is_empty():
		return {"ok": false, "reach": reach, "clamped": clamped}
	best["ok"] = true
	best["reach"] = reach
	best["clamped"] = clamped
	best["cost"] = best_cost
	return best


## Author the elbow and forearm directly while preserving both link lengths.
func arm_from_guides(side: int, elbow_guide: Vector3, wrist_guide: Vector3,
		tool_basis: Basis, pose: Dictionary) -> Dictionary:
	var inv := torso_xf(pose).affine_inverse()
	var s := shoulder_local(side)
	var e := s + (inv * elbow_guide - s).normalized() * L1
	var w := e + (inv * wrist_guide - e).normalized() * L2
	return _solve_elbow(side, s, e, w, (inv.basis * tool_basis).orthonormalized(), pose)


func _solve_elbow(side: int, s: Vector3, e: Vector3, w: Vector3,
		b_local: Basis, pose: Dictionary) -> Dictionary:
	var u := (e - s)
	var f := (w - e)
	if u.length_squared() < 1e-10 or f.length_squared() < 1e-10:
		return {}
	u = u.normalized()
	f = f.normalized()
	var bend := u.cross(f)
	var y := -u
	var x: Vector3
	if bend.length_squared() < 1e-10:
		# straight arm: choose a stable bend axis from the pole
		x = y.cross(Vector3.UP)
		if x.length_squared() < 1e-8:
			x = y.cross(Vector3.FORWARD)
	else:
		x = bend.normalized()
	x = x.normalized()
	var z := x.cross(y).normalized()
	var rsh := Basis(x, y, z)
	var f_local := rsh.transposed() * f
	var beta := atan2(-f_local.z, -f_local.y)
	var relb0 := rot_x(beta)
	# Share the tool twist between the elbow (ball joint) and wrist. The roll
	# is chosen to stay close to the previous sample's elbow/wrist orientation,
	# which removes the wrist gimbal flips without introducing branch jumps.
	var seed: Dictionary = pose.get("_seed", {})
	var sw = seed.get("wr%s_q" % ("L" if side > 0 else "R"))
	var se = seed.get("elb%s_q" % ("L" if side > 0 else "R"))
	var relb := relb0
	var rwr := (rsh * relb).transposed() * b_local
	var best_cost := 1e30
	for gdeg in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]:
		var cand := relb0 * Basis(Vector3.UP, float(gdeg) * D2R)
		var wr_c := (rsh * cand).transposed() * b_local
		var c := (wr_c.get_rotation_quaternion()).angle_to(Quaternion()) * 0.02
		if sw is Quaternion:
			c += (wr_c.get_rotation_quaternion()).angle_to(sw) * 1.2
		if se is Quaternion:
			c += (cand.get_rotation_quaternion()).angle_to(se) * 1.0
		var we := wr_c.get_euler()
		if absf(we.x) > 2.4:
			c += (absf(we.x) - 2.4) * 2.0
		if absf(we.y) > 2.4:
			c += (absf(we.y) - 2.4) * 2.0
		if absf(we.z) > 2.4:
			c += (absf(we.z) - 2.4) * 2.0
		if c < best_cost:
			best_cost = c
			relb = cand
			rwr = wr_c
	var sh_e := euler_of(rsh)
	var el_e := euler_of(relb)
	var wr_e := euler_of(rwr)
	var nm := "L" if side > 0 else "R"
	var out := {
		"sh%s_pitch" % nm: sh_e.x, "sh%s_yaw" % nm: sh_e.y, "sh%s_roll" % nm: sh_e.z,
		"elb%s_pitch" % nm: el_e.x, "elb%s_yaw" % nm: el_e.y, "elb%s_roll" % nm: el_e.z,
		"wr%s_pitch" % nm: wr_e.x, "wr%s_yaw" % nm: wr_e.y, "wr%s_roll" % nm: wr_e.z,
		"sh%s_q" % nm: rsh.get_rotation_quaternion(),
		"elb%s_q" % nm: relb.get_rotation_quaternion(),
		"wr%s_q" % nm: rwr.get_rotation_quaternion(),
	}
	var bt := rsh * relb * rwr
	var t := w + bt * Vector3(0.0, -L3, 0.0)
	out["_s"] = s
	out["_e"] = e
	out["_w"] = w
	out["_t"] = t
	out["_bt"] = bt
	out["_err"] = (t - (w + b_local * Vector3(0.0, -L3, 0.0))).length()
	return out


func _joint_cost(cand: Dictionary, side: int, pose: Dictionary) -> float:
	var nm := "L" if side > 0 else "R"
	var cost := 0.0
	# elbow must bend the right way (positive pitch)
	var ep := float(cand["elb%s_pitch" % nm])
	if ep < -0.02:
		cost += (-ep) * 8.0
	if ep > 2.80:
		cost += (ep - 2.80) * 8.0
	# shoulder euler limits
	for ax in ["pitch", "yaw", "roll"]:
		var v := absf(float(cand["sh%s_%s" % [nm, ax]]))
		if v > 2.30:
			cost += (v - 2.30) * 4.0
	# wrist limits / preference for a neutral-ish wrist
	for ax in ["pitch", "yaw", "roll"]:
		var v2 := absf(float(cand["wr%s_%s" % [nm, ax]]))
		if v2 > 2.50:
			cost += (v2 - 2.50) * 3.0
	# prefer the pose close to the seed (continuity between samples)
	var seed: Dictionary = pose.get("_seed", {})
	var max_jump := 0.0
	for j in ["sh", "elb", "wr"]:
		var qk := "%s%s_q" % [j, nm]
		if cand.has(qk) and seed.has(qk):
			var q: Quaternion = cand[qk]
			var sq: Quaternion = seed[qk]
			var qd := q.angle_to(sq)
			cost += qd * 3.5
			max_jump = maxf(max_jump, qd)
	if float(pose.get("_traj", 0.0)) > 0.5 and max_jump > 0.30:
		cost += (max_jump - 0.30) * 220.0
	for k in cand:
		if k.begins_with("_") or not seed.has(k) or not (cand[k] is float):
			continue
		var dv := absf(float(cand[k]) - float(seed[k]))
		cost += minf(dv, 0.8) * 0.02
	return cost


## Fast approximate clearance of one solved arm (and its weapon) against a
## list of body proxies. Used to rank swivel candidates before the full audit.
func _candidate_clearance(side: int, cand: Dictionary, pose: Dictionary,
		obstacles: Array, _b_local: Basis) -> float:
	var tx := torso_xf(pose)
	var s := tx * shoulder_local(side)
	var e := tx * (cand["_e"] as Vector3)
	var w := tx * (cand["_w"] as Vector3)
	var t := tx * (cand["_t"] as Vector3)
	var bt := tx.basis * (cand["_bt"] as Basis)
	var u := (e - s).normalized()
	var f := (w - e).normalized()
	var tv := (t - w).normalized()
	var links: Array = [
		{"kind": "cap", "a": s + u * 0.115, "b": e - u * 0.115, "r": 0.055},
		{"kind": "cap", "a": e, "b": e, "r": 0.076},
		{"kind": "cap", "a": e + f * 0.130, "b": w - f * 0.130, "r": 0.046},
		{"kind": "cap", "a": w, "b": w, "r": 0.066},
	]
	if float(pose.get("_docked_sword", 0.0)) < 0.5 or side > 0:
		links.append({"kind": "cap", "a": w + tv * 0.080, "b": t, "r": 0.048})
	if side < 0 and float(pose.get("_blade_on", 1.0)) > 0.45:
		var d := bt * Vector3(0, -1, 0)
		links.append({"kind": "cap", "a": t, "b": t + d * blade_len, "r": 0.062})
	if side > 0 and float(pose.get("_docked_shield", 0.0)) < 0.5:
		var n := bt * Vector3(0, 0, 1)
		links.append({"kind": "disc", "c": t + n * shield_off, "n": n,
			"r": shield_r, "t": 0.040})
	var worst := 9.9
	for link in links:
		for o in obstacles:
			var d2 := proxy_distance(link, o)
			if d2 < worst:
				worst = d2
	return worst


# ---------------------------------------------------------------- collision

const BODY_PARTS := ["torso", "camera", "camera_barrel", "back", "waist",
	"chassis", "bodylow", "hook", "sheath", "suspL", "suspR"]

const ADJ := {
	"shL": ["upperL", "torso", "waist"],
	"upperL": ["shL", "elbL", "foreL", "torso"],
	"elbL": ["upperL", "foreL"],
	"foreL": ["elbL", "wrL", "upperL", "toolL", "shield", "waist"],
	"wrL": ["foreL", "toolL", "shield"],
	"toolL": ["wrL", "foreL", "shield"],
	"shield": ["toolL", "wrL", "foreL", "upperL", "elbL", "shL", "hook", "back"],
	"shR": ["upperR", "torso", "waist"],
	"upperR": ["shR", "elbR", "foreR", "torso"],
	"elbR": ["upperR", "foreR"],
	"foreR": ["elbR", "wrR", "upperR", "toolR", "blade", "waist"],
	"wrR": ["foreR", "toolR", "blade"],
	"toolR": ["wrR", "foreR", "blade"],
	"blade": ["toolR", "wrR", "foreR"],
	"wheelL": ["suspL", "chassis"],
	"wheelR": ["suspR", "chassis"],
	"suspL": ["wheelL", "chassis", "bodylow"],
	"suspR": ["wheelR", "chassis", "bodylow"],
}


func _adj(a: String, b: String) -> bool:
	if BODY_PARTS.has(a) and BODY_PARTS.has(b):
		return true
	if ADJ.has(a) and (ADJ[a] as Array).has(b):
		return true
	if ADJ.has(b) and (ADJ[b] as Array).has(a):
		return true
	return false


## Build world-space collision proxies for a pose.
func proxies(pose: Dictionary) -> Array:
	var tx := torso_xf(pose)
	var bx := body_xf(pose)
	var out: Array = []
	# hull capsule along local Z
	var hc := tx * Vector3(0.0, hull_y, 0.0)
	var ha := tx * Vector3(0.0, hull_y, -0.180)
	var hb := tx * Vector3(0.0, hull_y, 0.180)
	out.append({"name": "torso", "kind": "cap", "a": ha, "b": hb, "r": hull_r})
	# camera ball (always outside the hull) + barrel when it is extended
	var cxf := camera_xf(pose)
	var cball := cxf * Vector3(0.0, 0.0, 0.0)
	out.append({"name": "camera", "kind": "cap", "a": cball, "b": cball, "r": cam_r})
	out.append({"name": "camera_barrel", "kind": "cap",
		"a": cxf * Vector3(0.0, 0.0, 0.040),
		"b": cxf * Vector3(0.0, 0.0, 0.155), "r": 0.092})
	out.append({"name": "back", "kind": "cap",
		"a": tx * Vector3(0.0, back_y, -0.330),
		"b": tx * Vector3(0.0, back_y, -0.350), "r": 0.110})
	# waist column + chassis
	out.append({"name": "waist", "kind": "cap",
		"a": bx * Vector3(0.0, 0.000, 0.0), "b": bx * Vector3(0.0, torso_y + 0.075, 0.0),
		"r": 0.105})
	# The lower chassis is a short, wide machined block; a disc proxy matches
	# its real vertical extent instead of a fat capsule that blocks the arms.
	var upb := (bx.basis * Vector3.UP).normalized()
	out.append({"name": "chassis", "kind": "disc",
		"c": bx * Vector3(0.0, 0.055, 0.0), "n": upb, "r": 0.175, "t": 0.145})
	out.append({"name": "bodylow", "kind": "disc",
		"c": bx * Vector3(0.0, 0.070, 0.0), "n": upb, "r": 0.195, "t": 0.160})
	# sheath (chassis)
	out.append({"name": "sheath", "kind": "cap",
		"a": bx * sheath_a, "b": bx * sheath_b, "r": 0.060})
	# rear hook
	out.append({"name": "hook", "kind": "cap",
		"a": tx * Vector3(-0.10, back_y, back_z - 0.10),
		"b": tx * Vector3(0.10, back_y, back_z - 0.10), "r": 0.055})
	# suspension links + wheels (axles fixed in root space)
	for s in [1, -1]:
		var nm := "L" if s > 0 else "R"
		var mount := bx * Vector3(float(s) * 0.300, 0.020, -0.020)
		var axle := Vector3(float(s) * wheel_x, wheel_y, 0.0)
		out.append({"name": "susp" + nm, "kind": "cap", "a": mount,
			"b": Vector3(float(s) * (wheel_x - 0.115), wheel_y, 0.0), "r": 0.060})
		out.append({"name": "wheel" + nm, "kind": "disc", "c": axle,
			"n": Vector3.RIGHT, "r": wheel_r, "t": 0.160})
	# arms
	for s in [1, -1]:
		var nm2 := "L" if s > 0 else "R"
		var fk := arm_fk(s, pose)
		out.append({"name": "sh" + nm2, "kind": "cap", "a": fk["s"], "b": fk["s"], "r": 0.090})
		var uvec: Vector3 = ((fk["e"] as Vector3) - (fk["s"] as Vector3)).normalized()
		var fvec: Vector3 = ((fk["w"] as Vector3) - (fk["e"] as Vector3)).normalized()
		var tvec: Vector3 = ((fk["tool"] as Vector3) - (fk["w"] as Vector3)).normalized()
		out.append({"name": "upper" + nm2, "kind": "cap",
			"a": (fk["s"] as Vector3) + uvec * 0.115,
			"b": (fk["e"] as Vector3) - uvec * 0.115, "r": 0.055})
		out.append({"name": "elb" + nm2, "kind": "cap", "a": fk["e"], "b": fk["e"], "r": 0.076})
		out.append({"name": "fore" + nm2, "kind": "cap",
			"a": (fk["e"] as Vector3) + fvec * 0.130,
			"b": (fk["w"] as Vector3) - fvec * 0.130, "r": 0.046})
		out.append({"name": "wr" + nm2, "kind": "cap", "a": fk["w"], "b": fk["w"], "r": 0.066})
		out.append({"name": "tool" + nm2, "kind": "cap",
			"a": (fk["w"] as Vector3) + tvec * 0.080, "b": fk["tool"], "r": 0.048})
		if s > 0:
			var n := (fk["tool_basis"] as Basis) * Vector3(0.0, 0.0, 1.0)
			var c := (fk["tool"] as Vector3) + n * shield_off
			# shield gimbal
			var gy := Basis(Vector3.UP, float(pose.get("shield_yaw", 0.0)))
			var gp := Basis(Vector3.RIGHT, float(pose.get("shield_pitch", 0.0)))
			var gb: Basis = fk["tool_basis"] * gy * gp
			n = gb * Vector3(0.0, 0.0, 1.0)
			c = (fk["tool"] as Vector3) + gb * Vector3(0.0, 0.0, shield_off)
			out.append({"name": "shield", "kind": "disc", "c": c, "n": n,
				"r": shield_r, "t": 0.040})
		else:
			if float(pose.get("_blade_on", 1.0)) > 0.45:
				var d := (fk["tool_basis"] as Basis) * Vector3(0.0, -1.0, 0.0)
				out.append({"name": "blade", "kind": "cap",
					"a": fk["tool"], "b": (fk["tool"] as Vector3) + d * blade_len,
					"r": 0.062})
	return out


## Minimum clearance over all non-adjacent proxy pairs. `detail` returns the
## worst pairs. Negative = interpenetration.
func audit(pose: Dictionary, detail := false) -> Dictionary:
	var ps := proxies(pose)
	var worst := 1e9
	var worst_pair := ["", ""]
	var worst_by: Dictionary = {}
	for i in ps.size():
		var a: Dictionary = ps[i]
		for j in range(i + 1, ps.size()):
			var b: Dictionary = ps[j]
			var an: String = a["name"]
			var bn: String = b["name"]
			if _adj(an, bn):
				continue
			if _docked(an, bn, pose):
				continue
			var d := proxy_distance(a, b)
			if d < worst:
				worst = d
				worst_pair = [an, bn]
			var key := an + "/" + bn
			if not worst_by.has(key) or d < float(worst_by[key]):
				worst_by[key] = d
	# floor clearance for the blade and shield rim
	var floor := _floor_clear(ps)
	if detail:
		return {"min": worst, "pair": worst_pair, "floor": floor, "pairs": worst_by}
	return {"min": worst, "pair": worst_pair, "floor": floor}


func _docked(a: String, b: String, pose: Dictionary) -> bool:
	# the generator sits in the sheath mouth while the blade is off; the shield
	# rests on the rear hook. Only exempt while actually docked.
	if float(pose.get("_docked_sword", 0.0)) > 0.5:
		if (a == "toolR" or a == "wrR" or b == "toolR" or b == "wrR"):
			if a == "sheath" or b == "sheath" or a == "bodylow" or b == "bodylow" or a == "chassis" or b == "chassis":
				return true
	if (a == "blade" or b == "blade") and (a == "sheath" or b == "sheath"):
		return float(pose.get("_blade_on", 1.0)) < 0.45
	if float(pose.get("_docked_shield", 0.0)) > 0.5:
		var shield_side := ["toolL", "shield", "wrL", "foreL"]
		var hook_side := ["hook", "back", "torso", "sheath"]
		if (shield_side.has(a) and hook_side.has(b)) or (shield_side.has(b) and hook_side.has(a)):
			return true
	return false


func _floor_clear(ps: Array) -> float:
	var low := 1e9
	for p in ps:
		if p["kind"] == "cap":
			low = minf(low, minf((p["a"] as Vector3).y, (p["b"] as Vector3).y) - float(p["r"]))
		else:
			var c: Vector3 = p["c"]
			var nn: Vector3 = p["n"]
			low = minf(low, c.y - float(p["r"]))
	return low


# ---------------------------------------------------------------- distance

static func seg_seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= EPS and e <= EPS:
		return r.length()
	if a <= EPS:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= EPS:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom != 0.0:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			else:
				s = 0.0
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


static func point_seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > EPS:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func proxy_distance(a: Dictionary, b: Dictionary) -> float:
	var ka: String = a["kind"]
	var kb: String = b["kind"]
	if ka == "cap" and kb == "cap":
		return seg_seg_dist(a["a"], a["b"], b["a"], b["b"]) - float(a["r"]) - float(b["r"])
	if ka == "disc" and kb == "disc":
		# shield-shield unlikely; use centers
		return (a["c"] as Vector3).distance_to(b["c"]) - float(a["r"]) - float(b["r"])
	if ka == "disc":
		return _cap_disc(b, a)
	if kb == "disc":
		return _cap_disc(a, b)
	return 1e9


static func _cap_disc(cap: Dictionary, disc: Dictionary) -> float:
	var a: Vector3 = cap["a"]
	var b: Vector3 = cap["b"]
	var c: Vector3 = disc["c"]
	var n: Vector3 = (disc["n"] as Vector3).normalized()
	var rr := float(disc["r"])
	var half_t := float(disc["t"]) * 0.5
	var best := 1e9
	for i in 5:
		var p := a.lerp(b, float(i) / 4.0)
		var q := p - c
		var pd := q.dot(n)
		var planar := q - n * pd
		var rad := planar.length()
		var radial := maxf(rad - rr, 0.0)
		var normal := maxf(absf(pd) - half_t, 0.0)
		var d := sqrt(radial * radial + normal * normal) - float(cap["r"])
		best = minf(best, d)
	return best


# ---------------------------------------------------------------- pose helpers

static func blend_pose(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out: Dictionary = b.duplicate()
	for key in b:
		if key.begins_with("_"):
			if key == "_blade_on" or key == "_docked_shield":
				out[key] = lerpf(float(a.get(key, b[key])), float(b[key]), k)
			continue
		if b[key] is Quaternion:
			if a.has(key) and a[key] is Quaternion:
				out[key] = (a[key] as Quaternion).slerp(b[key] as Quaternion, k)
			continue
		if a.has(key) and b[key] is float:
			out[key] = lerpf(float(a[key]), float(b[key]), k)
	return out


static func copy_arm(dst: Dictionary, src: Dictionary, nm: String) -> void:
	for k in src:
		if k.begins_with("sh" + nm) or k.begins_with("elb" + nm) or k.begins_with("wr" + nm):
			dst[k] = src[k]
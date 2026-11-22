extends RefCounted
class_name ArcKin3
## ARC // GRINDER v3 — chassis kinematics + single top-mounted 3-ball-joint arm.
##
## The character is a tracked turret: two triangular track units flank a
## chamfered cube body; the cube carries a shallow socketed optic on its front
## face and a 3-ball-joint arm rising from its top deck.  The arm chain is
## base ball (shoulder) -> link 1 -> elbow ball -> link 2 -> wrist ball ->
## emitter -> arc blade.
##
## Analytic swivel IK (Korein & Badler 1982; Tolani et al. 2000): the
## shoulder+elbow solve is closed form for one free swivel angle around the
## shoulder->wrist axis; wrist is a 3-DOF aligner.  A small swivel set is ranked
## by joint cost + continuity + self-collision.  Collision proxies are capsules
## and oriented boxes; the audit is shared by the runtime planner and QA.

const D2R := PI / 180.0
const TAU := PI * 2.0
const EPS := 1e-6

## Preferred elbow direction in body space.  The elbow sits out to the
## character's left and slightly up/back, which keeps it clear of the cube and
## reads as a folded hydraulic arm at rest.
const POLE := Vector3(0.86, 0.42, -0.22)

## Parts that never move relative to the rig root (chassis).
const CHASSIS := ["deck", "trackL", "trackR"]

var P: Dictionary = {}

# ---------------------------------------------------------------- dimensions
var cube := 0.52
var cube_half := 0.26
var body_y := 0.96
var shoulder_local := Vector3(0.0, 0.50, 0.0)
var L1 := 0.46
var L2 := 0.40
var L3 := 0.115
var blade_len := 1.03
var blade_half_w := 0.088
var blade_half_t := 0.025
var blade_r := 0.085
var cam_z := 0.230
var cam_r := 0.150
var cam_ap := 0.1733
var cam_shell_r := 0.192
var cam_shell_z := 0.310
var cam_face := 0.260
var deck_y := 0.475
var deck_hx := 0.300
var deck_hy := 0.058
var deck_hz := 0.310
var track_x := 0.460
var track_hw := 0.110
var track_poly: Array[Vector2] = [Vector2(0.50, 0.206), Vector2(0.0, 0.600), Vector2(-0.50, 0.206)]
var track_r := 0.190
var track_belt_out := 0.171
var track_belt_in := 0.139
var wheel_r := 0.140
var track_belt_r := 0.155
var waist_r := 0.170
var waist_lo := 0.460
var waist_hi := 0.780


func _init(p: Dictionary) -> void:
	P = p.duplicate()
	_apply_dims()


func _apply_dims() -> void:
	cube = clampf(float(P.get("cube_size", 0.52)), 0.44, 0.64)
	cube_half = cube * 0.5
	body_y = 0.70 + cube_half
	shoulder_local = Vector3(0.0, cube_half + 0.240, 0.0)
	var arm_scale := clampf(float(P.get("arm_scale", 1.0)), 0.82, 1.18)
	L1 = 0.46 * arm_scale
	L2 = 0.40 * arm_scale
	L3 = 0.115
	blade_len = clampf(float(P.get("blade_length", 1.03)), 0.80, 1.30)
	blade_half_w = clampf(float(P.get("blade_width", 0.176)), 0.12, 0.24) * 0.5
	blade_half_t = 0.025
	blade_r = maxf(0.070, blade_half_w * 0.86)
	cam_face = cube_half
	cam_ap = cube / 3.0
	cam_r = cam_ap * 0.84
	cam_z = cube_half - 0.015
	cam_shell_r = cam_ap * 1.11
	cam_shell_z = cam_face + 0.050


# ---------------------------------------------------------------- transforms

func body_xf(pose: Dictionary) -> Transform3D:
	var basis := Basis.from_euler(Vector3(
		float(pose.get("body_pitch", 0.0)),
		float(pose.get("body_yaw", 0.0)),
		float(pose.get("body_roll", 0.0))))
	var pos := Vector3(
		float(pose.get("body_sway", 0.0)),
		body_y + float(pose.get("body_lift", 0.0)),
		float(pose.get("body_shift", 0.0)))
	return Transform3D(basis, pos)


func shoulder_world(pose: Dictionary) -> Vector3:
	return body_xf(pose) * shoulder_local


## Threat target point (upper chest / optic line) in root space.
func chest_point() -> Vector3:
	return Vector3(0.0, body_y + 0.10, 0.12)


## Perimeter of the rounded-triangle belt centreline (one belt loop).
func track_loop_len() -> float:
	var per := 0.0
	for i in track_poly.size():
		per += track_poly[i].distance_to(track_poly[(i + 1) % track_poly.size()])
	return per + TAU * track_belt_r


## Rig-root rotation (skid pivot of the whole chassis).  Arm targets are
## authored in the pre-root frame, so the solver ignores this; the rig applies
## it to its root node.
func root_basis(pose: Dictionary) -> Basis:
	return Basis(Vector3.UP, float(pose.get("root_yaw", 0.0)))


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


## Tool basis for the sword: local -Y is the blade axis, local Z is the face
## normal, local X is the wide axis (edge <-> spine).
static func sword_basis(blade_dir: Vector3, face_hint: Vector3) -> Basis:
	return basis_from_y_z(-blade_dir, face_hint)


static func rot_x(a: float) -> Basis:
	return Basis(Vector3.RIGHT, a)


# ---------------------------------------------------------------- arm FK

func _jbasis(pose: Dictionary, j: String) -> Basis:
	var qk := j + "_q"
	if pose.has(qk) and pose[qk] is Quaternion:
		return Basis(pose[qk] as Quaternion)
	return Basis.from_euler(Vector3(
		float(pose.get(j + "_pitch", 0.0)),
		float(pose.get(j + "_yaw", 0.0)),
		float(pose.get(j + "_roll", 0.0))))


func arm_fk(pose: Dictionary) -> Dictionary:
	var sh := _jbasis(pose, "sh")
	var el := _jbasis(pose, "elb")
	var wr := _jbasis(pose, "wr")
	var bx := body_xf(pose)
	var s := bx * shoulder_local
	var e := s + (bx.basis * sh) * Vector3(0.0, -L1, 0.0)
	var w := e + (bx.basis * sh * el) * Vector3(0.0, -L2, 0.0)
	var bt := (bx.basis * sh * el * wr).orthonormalized()
	var t := w + bt * Vector3(0.0, -L3, 0.0)
	return {
		"s": s, "e": e, "w": w, "tool": t, "tool_basis": bt,
		"dir": bt * Vector3(0.0, -1.0, 0.0),
		"face": bt * Vector3(0.0, 0.0, 1.0),
		"tip": t + (bt * Vector3(0.0, -1.0, 0.0)) * blade_len,
	}


## Blade midpoint (the point the block planner puts on the threat line).
func blade_mid(pose: Dictionary) -> Vector3:
	var fk := arm_fk(pose)
	return (fk["tool"] as Vector3) + (fk["dir"] as Vector3) * (blade_len * 0.36)


# ---------------------------------------------------------------- arm solve

func arm_solve(tool_pos: Vector3, tool_basis: Basis, pose: Dictionary,
		opts := {}, obstacles: Array = []) -> Dictionary:
	var bx := body_xf(pose)
	var inv := bx.affine_inverse()
	var b_local := (inv.basis * tool_basis).orthonormalized()
	var t_local := inv * tool_pos
	var s := shoulder_local
	var w := t_local - b_local * Vector3(0.0, -L3, 0.0)
	var d := w - s
	var reach := d.length()
	var r := clampf(reach, absf(L1 - L2) + 0.002, L1 + L2 - 0.002)
	var clamped := absf(r - reach) > 1e-5
	if clamped:
		if reach < 1e-6:
			d = Vector3(0.0, -1.0, 0.0)
		else:
			d = d / reach
		w = s + d * r
		d = w - s
	var u := d / r
	var pole: Vector3 = opts.get("pole", POLE)
	var perp := pole - u * pole.dot(u)
	if perp.length_squared() < 1e-8:
		perp = Vector3.UP - u * u.y
		if perp.length_squared() < 1e-8:
			perp = Vector3.FORWARD - u * u.z
	perp = perp.normalized()
	var side_axis := u.cross(perp).normalized()
	var a := (L1 * L1 - L2 * L2 + r * r) / (2.0 * r)
	var h := sqrt(maxf(L1 * L1 - a * a, 0.0))
	var swivels: Array = opts.get("swivels",
		[-80.0, -60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0, 80.0])
	var best: Dictionary = {}
	var best_cost := 1e30
	for sv in swivels:
		var phi := float(sv) * D2R
		var e := s + u * a + (perp * cos(phi) + side_axis * sin(phi)) * h
		var cand := _solve_elbow(s, e, w, b_local, pose)
		if cand.is_empty():
			continue
		var cost := _joint_cost(cand, pose)
		# hard-ish penalty for the arm volume inside the turret cube; this is
		# the dominant self-collision and it is a handful of point-to-box
		# queries, far cheaper than a full proxy audit per swivel
		var hh := Vector3(cube_half - 0.006, cube_half - 0.006, cube_half - 0.006)
		var ce := point_box(e, Vector3.ZERO, Basis.IDENTITY, hh)
		if ce < 0.092:
			cost += (0.092 - ce) * 420.0
		var cw := point_box(w, Vector3.ZERO, Basis.IDENTITY, hh)
		if cw < 0.074:
			cost += (0.074 - cw) * 420.0
		for t in [0.18, 0.42, 0.66, 0.86]:
			var um := s + (e - s) * float(t)
			var cu := point_box(um, Vector3.ZERO, Basis.IDENTITY, hh) - 0.050
			if cu < 0.0:
				cost += (-cu) * 460.0
		for t2 in [0.22, 0.50, 0.78]:
			var fm := e + (w - e) * float(t2)
			var cf := point_box(fm, Vector3.ZERO, Basis.IDENTITY, hh) - 0.044
			if cf < 0.0:
				cost += (-cf) * 460.0
		if not obstacles.is_empty():
			var clr := _candidate_clearance(cand, pose, obstacles, b_local)
			cand["_clear_est"] = clr
			if clr < 0.030:
				cost += (0.030 - clr) * 200.0 + 2.0
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


func _solve_elbow(s: Vector3, e: Vector3, w: Vector3, b_local: Basis,
		pose: Dictionary) -> Dictionary:
	var u := e - s
	var f := w - e
	if u.length_squared() < 1e-10 or f.length_squared() < 1e-10:
		return {}
	u = u.normalized()
	f = f.normalized()
	var bend := u.cross(f)
	var y := -u
	var x: Vector3
	if bend.length_squared() < 1e-10:
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
	var seed: Dictionary = pose.get("_seed", {})
	var sw = seed.get("wr_q")
	var se = seed.get("elb_q")
	var relb := relb0
	var best_cost := 1e30
	for gdeg in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]:
		var cand := relb0 * Basis(Vector3.UP, float(gdeg) * D2R)
		var wr_c := (rsh * cand).transposed() * b_local
		var c := wr_c.get_rotation_quaternion().angle_to(Quaternion()) * 0.02
		if sw is Quaternion:
			c += wr_c.get_rotation_quaternion().angle_to(sw) * 1.2
		if se is Quaternion:
			c += cand.get_rotation_quaternion().angle_to(se) * 1.0
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
	var rwr := (rsh * relb).transposed() * b_local
	var sh_e := rsh.get_euler()
	var el_e := relb.get_euler()
	var wr_e := rwr.get_euler()
	var out := {
		"sh_pitch": sh_e.x, "sh_yaw": sh_e.y, "sh_roll": sh_e.z,
		"elb_pitch": el_e.x, "elb_yaw": el_e.y, "elb_roll": el_e.z,
		"wr_pitch": wr_e.x, "wr_yaw": wr_e.y, "wr_roll": wr_e.z,
		"sh_q": rsh.get_rotation_quaternion(),
		"elb_q": relb.get_rotation_quaternion(),
		"wr_q": rwr.get_rotation_quaternion(),
	}
	out["_s"] = s
	out["_e"] = e
	out["_w"] = w
	out["_t"] = w + (rsh * relb * rwr) * Vector3(0.0, -L3, 0.0)
	out["_bt"] = rsh * relb * rwr
	return out


## Swivel angle of a solved pose around the shoulder->wrist axis (same
## parameterisation as `arm_solve`, so trajectories can stay on one branch).
func swivel_of(pose: Dictionary) -> float:
	var bx := body_xf(pose)
	var fk := arm_fk(pose)
	var inv := bx.affine_inverse()
	var s: Vector3 = inv * (fk["s"] as Vector3)
	var w: Vector3 = inv * (fk["w"] as Vector3)
	var e: Vector3 = inv * (fk["e"] as Vector3)
	var d := w - s
	var r := d.length()
	if r < 0.03:
		return 0.0
	var u := d / r
	var perp := POLE - u * POLE.dot(u)
	if perp.length_squared() < 1e-8:
		perp = Vector3.UP - u * u.y
	if perp.length_squared() < 1e-8:
		return 0.0
	perp = perp.normalized()
	var side_axis := u.cross(perp).normalized()
	var a := (L1 * L1 - L2 * L2 + r * r) / (2.0 * r)
	var mid := s + u * a
	var q := e - mid
	return rad_to_deg(atan2(q.dot(side_axis), q.dot(perp)))


func _joint_cost(cand: Dictionary, pose: Dictionary) -> float:
	var cost := 0.0
	var ep := float(cand["elb_pitch"])
	if ep < -0.02:
		cost += (-ep) * 10.0
	if ep > 2.80:
		cost += (ep - 2.80) * 8.0
	for ax in ["pitch", "yaw", "roll"]:
		var v := absf(float(cand["sh_" + ax]))
		if v > 2.30:
			cost += (v - 2.30) * 4.0
	for ax in ["pitch", "yaw", "roll"]:
		var v2 := absf(float(cand["wr_" + ax]))
		if v2 > 2.50:
			cost += (v2 - 2.50) * 3.0
	var seed: Dictionary = pose.get("_seed", {})
	var max_jump := 0.0
	for j in ["sh", "elb", "wr"]:
		var qk: String = j + "_q"
		if cand.has(qk) and seed.has(qk):
			var q: Quaternion = cand[qk]
			var sq: Quaternion = seed[qk]
			var qd := q.angle_to(sq)
			cost += qd * 3.5
			max_jump = maxf(max_jump, qd)
	if float(pose.get("_traj", 0.0)) > 0.5 and max_jump > 0.30:
		cost += (max_jump - 0.30) * 240.0
	for k in cand:
		if k.begins_with("_") or not seed.has(k) or not (cand[k] is float):
			continue
		var dv := absf(float(cand[k]) - float(seed[k]))
		cost += minf(dv, 0.8) * 0.02
	return cost


func _candidate_clearance(cand: Dictionary, pose: Dictionary, obstacles: Array,
		_b_local: Basis) -> float:
	var bx := body_xf(pose)
	var s := bx * (cand["_s"] as Vector3)
	var e := bx * (cand["_e"] as Vector3)
	var w := bx * (cand["_w"] as Vector3)
	var t := bx * (cand["_t"] as Vector3)
	var bt := (bx.basis * (cand["_bt"] as Basis)).orthonormalized()
	var u := (e - s).normalized()
	var f := (w - e).normalized()
	var tv := (t - w).normalized()
	var links: Array = [
		{"kind": "cap", "a": s + u * 0.155, "b": e - u * 0.115, "r": 0.052},
		{"kind": "cap", "a": e, "b": e, "r": 0.076},
		{"kind": "cap", "a": e + f * 0.130, "b": w - f * 0.130, "r": 0.046},
		{"kind": "cap", "a": w, "b": w, "r": 0.066},
		{"kind": "cap", "a": w + tv * 0.070, "b": t, "r": 0.050},
	]
	if float(pose.get("_blade_on", 1.0)) > 0.45:
		var d := bt * Vector3(0, -1, 0)
		links.append({"kind": "cap", "a": t, "b": t + d * blade_len, "r": blade_r})
	var worst := 9.9
	for link in links:
		var lc: Vector3 = ((link["a"] as Vector3) + (link["b"] as Vector3)) * 0.5
		var lr: float = ((link["a"] as Vector3).distance_to(link["b"] as Vector3)) * 0.5 \
			+ float(link["r"])
		for o in obstacles:
			var lb: float = lc.distance_to(o["cr"] as Vector3) - lr - float(o["rr"])
			if lb > 0.10:
				worst = minf(worst, lb)
				continue
			worst = minf(worst, proxy_distance(link, o))
	return worst


# ---------------------------------------------------------------- collision

const ADJ := {
	"sh": ["mount", "hull", "upper", "elb"],
	"upper": ["sh", "elb", "fore"],
	"elb": ["sh", "upper", "fore", "wr"],
	"fore": ["elb", "wr", "upper", "tool"],
	"wr": ["elb", "fore", "tool"],
	"tool": ["wr", "fore", "blade"],
	"blade": ["tool", "wr", "fore"],
	"hull": ["mount", "waist", "optic", "hood", "deck"],
	"mount": ["hull", "sh"],
	"optic": ["hull", "hood"],
	"hood": ["hull", "optic"],
	"waist": ["hull", "deck"],
	"deck": ["waist", "hull", "trackL", "trackR"],
	"trackL": ["deck", "trackR"],
	"trackR": ["deck", "trackL"],
}


func _adj(a: String, b: String) -> bool:
	if a == b:
		return true   # several proxies can describe one part (optic ball/bezel)
	if (CHASSIS as Array).has(a) and (CHASSIS as Array).has(b):
		return true
	if ADJ.has(a) and (ADJ[a] as Array).has(b):
		return true
	if ADJ.has(b) and (ADJ[b] as Array).has(a):
		return true
	return false


func proxies(pose: Dictionary) -> Array:
	var bx := body_xf(pose)
	var out: Array = []
	# turret cube (chamfered in the mesh, box proxy is a hair smaller)
	out.append({"name": "hull", "kind": "box",
		"c": bx * Vector3.ZERO, "basis": bx.basis,
		"h": Vector3(cube_half - 0.006, cube_half - 0.006, cube_half - 0.006)})
	# optic: flat bezel plate + protruding ball, then the brow
	out.append({"name": "optic", "kind": "box",
		"c": bx * Vector3(0.0, 0.0, cam_face + 0.030), "basis": bx.basis,
		"h": Vector3(cam_ap * 1.13, cam_ap * 1.13, 0.040)})
	out.append({"name": "optic", "kind": "cap",
		"a": bx * Vector3(0.0, 0.0, cam_face + 0.030),
		"b": bx * Vector3(0.0, 0.0, cam_z + cam_r), "r": cam_r})
	out.append({"name": "hood", "kind": "cap",
		"a": bx * Vector3(-0.165, cam_ap + 0.030, cam_face + 0.020),
		"b": bx * Vector3(0.165, cam_ap + 0.030, cam_face + 0.020), "r": 0.020})
	# shoulder pedestal on the cube top
	out.append({"name": "mount", "kind": "cap",
		"a": bx * Vector3(0.0, cube_half - 0.020, 0.0),
		"b": bx * Vector3(0.0, cube_half + 0.045, 0.0), "r": 0.095})
	# fixed chassis
	out.append({"name": "waist", "kind": "cap",
		"a": Vector3(0.0, waist_lo, 0.0), "b": Vector3(0.0, waist_hi - 0.06, 0.0), "r": waist_r})
	out.append({"name": "deck", "kind": "box",
		"c": Vector3(0.0, deck_y, 0.0), "basis": Basis.IDENTITY,
		"h": Vector3(deck_hx, deck_hy, deck_hz)})
	# track units: three stacked boxes approximate the triangular belt volume
	for s in [1, -1]:
		var nm := "trackL" if s > 0 else "trackR"
		var x := float(s) * track_x
		var hw := track_hw - 0.007
		for band in [[0.210, 0.210, 0.560], [0.500, 0.100, 0.440], [0.700, 0.105, 0.270]]:
			out.append({"name": nm, "kind": "box",
				"c": Vector3(x, float(band[0]), -0.010), "basis": Basis.IDENTITY,
				"h": Vector3(hw, float(band[1]), float(band[2]))})
	# arm
	var fk := arm_fk(pose)
	var s2: Vector3 = fk["s"]
	var e2: Vector3 = fk["e"]
	var w2: Vector3 = fk["w"]
	var t2: Vector3 = fk["tool"]
	var uvec := (e2 - s2).normalized()
	var fvec := (w2 - e2).normalized()
	var tvec := (t2 - w2).normalized()
	out.append({"name": "sh", "kind": "cap", "a": s2, "b": s2, "r": 0.098})
	# the proximal 15 cm of the upper link is inside the socket ball, so the
	# collision proxy starts where the link becomes visible
	out.append({"name": "upper", "kind": "cap",
		"a": s2 + uvec * 0.155, "b": e2 - uvec * 0.115, "r": 0.052})
	out.append({"name": "elb", "kind": "cap", "a": e2, "b": e2, "r": 0.080})
	out.append({"name": "fore", "kind": "cap",
		"a": e2 + fvec * 0.130, "b": w2 - fvec * 0.130, "r": 0.048})
	out.append({"name": "wr", "kind": "cap", "a": w2, "b": w2, "r": 0.066})
	out.append({"name": "tool", "kind": "cap",
		"a": w2 + tvec * 0.070, "b": t2, "r": 0.050})
	if float(pose.get("_blade_on", 1.0)) > 0.45:
		var d := fk["dir"] as Vector3
		out.append({"name": "blade", "kind": "cap",
			"a": t2, "b": t2 + d * blade_len, "r": blade_r})
	# bounding data for cheap pair rejection
	for p in out:
		if p["kind"] == "cap":
			var pa: Vector3 = p["a"]
			var pb: Vector3 = p["b"]
			var e := Vector3(absf(pa.x - pb.x), absf(pa.y - pb.y), absf(pa.z - pb.z))
			p["cr"] = (pa + pb) * 0.5
			p["rr"] = pa.distance_to(pb) * 0.5 + float(p["r"])
			p["lo"] = pa.lerp(pb, 0.5) - (e * 0.5 + Vector3.ONE * float(p["r"])) - Vector3.ZERO
			var lo: Vector3 = Vector3(minf(pa.x, pb.x), minf(pa.y, pb.y), minf(pa.z, pb.z)) - Vector3.ONE * float(p["r"])
			var hi: Vector3 = Vector3(maxf(pa.x, pb.x), maxf(pa.y, pb.y), maxf(pa.z, pb.z)) + Vector3.ONE * float(p["r"])
			p["lo"] = lo
			p["hi"] = hi
		else:
			var h: Vector3 = p["h"]
			var basis: Basis = p["basis"]
			var c: Vector3 = p["c"]
			var ext := Vector3(
				absf(basis.x.x) * h.x + absf(basis.y.x) * h.y + absf(basis.z.x) * h.z,
				absf(basis.x.y) * h.x + absf(basis.y.y) * h.y + absf(basis.z.y) * h.z,
				absf(basis.x.z) * h.x + absf(basis.y.z) * h.y + absf(basis.z.z) * h.z)
			p["cr"] = c
			p["rr"] = h.length()
			p["lo"] = c - ext
			p["hi"] = c + ext
	return out


static var _pair_cache: Dictionary = {}


func audit(pose: Dictionary, detail := false, margin := 0.06) -> Dictionary:
	var ps := proxies(pose)
	var worst := 1e9
	var worst_pair := ["", ""]
	var worst_by: Dictionary = {}
	var pairs: Array = _pair_cache.get(ps.size(), [])
	if pairs.is_empty():
		for i in ps.size():
			for j in range(i + 1, ps.size()):
				if not _adj(str(ps[i]["name"]), str(ps[j]["name"])):
					pairs.append([i, j])
		_pair_cache[ps.size()] = pairs
	var los: Array = []
	var his: Array = []
	for p in ps:
		los.append(p["lo"])
		his.append(p["hi"])
	for pair in pairs:
		var i: int = pair[0]
		var j: int = pair[1]
		var la: Vector3 = los[i]
		var ha: Vector3 = his[i]
		var lbv: Vector3 = los[j]
		var hb: Vector3 = his[j]
		var gx: float = maxf(maxf(lbv.x - ha.x, la.x - hb.x), 0.0)
		var gy: float = maxf(maxf(lbv.y - ha.y, la.y - hb.y), 0.0)
		var gz: float = maxf(maxf(lbv.z - ha.z, la.z - hb.z), 0.0)
		var lb: float = sqrt(gx * gx + gy * gy + gz * gz)
		if lb > margin:
			worst = minf(worst, lb)
			continue
		var a: Dictionary = ps[i]
		var b: Dictionary = ps[j]
		var d := proxy_distance(a, b)
		if d < worst:
			worst = d
			worst_pair = [a["name"], b["name"]]
		if detail:
			var key := str(a["name"]) + "/" + str(b["name"])
			worst_by[key] = d
	var floor := _floor_clear(ps)
	if detail:
		return {"min": worst, "pair": worst_pair, "floor": floor, "pairs": worst_by}
	return {"min": worst, "pair": worst_pair, "floor": floor}


## Fast blade-vs-body clearance, used by the block planner's fade check.
func blade_clear(pose: Dictionary) -> float:
	var ps := proxies(pose)
	if ps.is_empty():
		return 9.0
	var b: Dictionary = ps[ps.size() - 1]
	if str(b["name"]) != "blade":
		return 9.0
	var arm := ["sh", "upper", "elb", "fore", "wr", "tool", "blade"]
	var worst := 9.0
	for i in ps.size() - 1:
		var a: Dictionary = ps[i]
		if (arm as Array).has(str(a["name"])):
			continue
		worst = minf(worst, proxy_distance(b, a))
	return worst


func _floor_clear(ps: Array) -> float:
	var low := 1e9
	for p in ps:
		if p["kind"] == "cap":
			low = minf(low, minf((p["a"] as Vector3).y, (p["b"] as Vector3).y) - float(p["r"]))
		else:
			var b: Basis = p["basis"]
			var h: Vector3 = p["h"]
			var c: Vector3 = p["c"]
			var drop := absf(b.y.x) * h.x + absf(b.y.y) * h.y + absf(b.y.z) * h.z
			low = minf(low, c.y - drop)
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
			if absf(denom) > 1e-12:
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
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


static func point_seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > EPS:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Signed distance from a point to an oriented box (negative = inside).
static func point_box(p: Vector3, c: Vector3, b: Basis, h: Vector3) -> float:
	var q := b.transposed() * (p - c)
	var l := Vector3(absf(q.x) - h.x, absf(q.y) - h.y, absf(q.z) - h.z)
	var outside := Vector3(maxf(l.x, 0.0), maxf(l.y, 0.0), maxf(l.z, 0.0)).length()
	var inside := minf(maxf(l.x, maxf(l.y, l.z)), 0.0)
	return outside + inside


const BOX_SAMPLES := 9


static func proxy_distance(a: Dictionary, b: Dictionary) -> float:
	var ka: String = a["kind"]
	var kb: String = b["kind"]
	if ka == "cap" and kb == "cap":
		return seg_seg_dist(a["a"], a["b"], b["a"], b["b"]) - float(a["r"]) - float(b["r"])
	if ka == "box" and kb == "cap":
		return _cap_box(b, a)
	if ka == "cap" and kb == "box":
		return _cap_box(a, b)
	return minf(_box_points(b, a), _box_points(a, b))


## Sample one box's corners / face centres / edge midpoints against another.
static func _box_points(from_box: Dictionary, to_box: Dictionary) -> float:
	var c: Vector3 = from_box["c"]
	var basis: Basis = from_box["basis"]
	var h: Vector3 = from_box["h"]
	var best := 1e9
	for sx in [-1.0, 0.0, 1.0]:
		for sy in [-1.0, 0.0, 1.0]:
			for sz in [-1.0, 0.0, 1.0]:
				if sx == 0.0 and sy == 0.0 and sz == 0.0:
					continue
				var p: Vector3 = c + basis * Vector3(sx * h.x, sy * h.y, sz * h.z)
				best = minf(best, point_box(p, to_box["c"], to_box["basis"], to_box["h"]))
	return best


static func _cap_box(cap: Dictionary, box: Dictionary) -> float:
	var a: Vector3 = cap["a"]
	var b: Vector3 = cap["b"]
	var c: Vector3 = box["c"]
	var basis: Basis = box["basis"]
	var h: Vector3 = box["h"]
	var rr := float(cap["r"])
	var best := 1e9
	for i in BOX_SAMPLES:
		var p := a.lerp(b, float(i) / float(BOX_SAMPLES - 1))
		best = minf(best, point_box(p, c, basis, h))
	return best - rr


# ---------------------------------------------------------------- pose helpers

static func blend_pose(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out: Dictionary = b.duplicate()
	for key in b:
		if key.begins_with("_"):
			if key == "_blade_on" or key == "_block_hit":
				out[key] = lerpf(float(a.get(key, b[key])), float(b[key]), k)
			continue
		if b[key] is Quaternion:
			if a.has(key) and a[key] is Quaternion:
				out[key] = (a[key] as Quaternion).slerp(b[key] as Quaternion, k)
			continue
		if a.has(key) and b[key] is float:
			out[key] = lerpf(float(a[key]), float(b[key]), k)
	return out


static func copy_arm(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if k.begins_with("sh") or k.begins_with("elb") or k.begins_with("wr"):
			dst[k] = src[k]
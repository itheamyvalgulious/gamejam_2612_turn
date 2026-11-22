extends RefCounted
## VESPER // attack choreography data (2 m frame, 1.25 m plasma greatsword).
##
## All weapon poses live in TORSO space:
##   +X = character right, +Y = up, -Z = forward.
## Poses are patch dictionaries over BASE_POSE; every key only has to spell out
## the channels it changes.  Positions are authored for the small 2 m frame
## (the old 4.2 m prototype numbers were scaled to roughly 45 %).
##
## Clip schema
##   name      : String  -- the id used by get_clip()
##   duration  : float   -- seconds
##   trail     : [t0, t1] -- blade ribbon window
##   keys      : [{t, p}] -- p is a torso-space pose patch
##   lunge     : [[t, metres]] -- forward travel of the body
##   hit_at    : float   -- contact time
##   hit_kind  : "air" | "ground"
##   style     : "twohand" | "side_r" | "back_r" | "spin"
##
## Conventions
##   sword local +Y = blade axis (hilt -> tip)
##   sword local +X = blade width, local +Z = flat-face normal
##   Node3D Euler order is YXZ
##
## Mirroring note: the ready stance is a vertical guard (blade nearly upright
## and leaned slightly forward).  mirrored() flips only the channels a key
## actually authored, so empty t=0 / t=duration keys stay empty and both sides
## share the same neutral stance instead of teleporting the hilt to the other
## side.  Every authored action key mirrors exactly.

const BLADE_LEN := 1.25
const TAU := PI * 2.0

const BASE_POSE := {
	"ty": 0.0, "tx": 0.0, "tz": 0.0, "hy": 0.04, "hx": -0.02,
	"crouch": 0.0, "lean": 0.0,
	"offhand": 0.0, "left_raise": 0.0,
	"wpx": 0.18, "wpy": 0.17, "wpz": -0.37,
	"wrx": -0.26, "wry": 0.0, "wrz": 0.08,
}

const CLIP_NAMES := [
	"FRONT_R", "FRONT_L", "RISE_R", "RISE_L",
	"SIDE_THRUST_R", "SIDE_THRUST_L", "BACK_THRUST", "HEAVY", "SPIN",
]

# Channels that flip sign under a left/right mirror.  wrx (blade pitch), hx
# (head pitch), crouch and lean are sagittal and stay untouched.
const MIRROR_CHANNELS := ["wpx", "ty", "hy", "wry", "wrz", "tx", "tz"]

# ---------------------------------------------------------------- 1. FRONT_R
# Front diagonal cleave: high right -> low left.  The blade starts over the
# right shoulder, sweeps in front of the chest and finishes across the left hip.
static var FRONT_R: Dictionary = {
	"name": "FRONT_R",
	"duration": 0.84,
	"trail": [0.18, 0.46],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.18, "p": {
			"ty": -0.34, "tz": 0.06, "tx": 0.03, "hy": 0.30, "hx": -0.04,
			"crouch": 0.05, "lean": -0.03,
			"wpx": 0.30, "wpy": 0.42, "wpz": -0.34,
			"wrx": -0.15, "wry": 0.0, "wrz": -0.32,
		}},
		{"t": 0.24, "p": {
			"ty": 0.02, "tz": -0.03, "tx": -0.02, "hy": 0.03, "hx": 0.0,
			"crouch": 0.07, "lean": 0.03,
			"wpx": 0.18, "wpy": 0.38, "wpz": -0.36,
			"wrx": -0.08, "wry": -0.60, "wrz": 0.72,
		}},
		{"t": 0.30, "p": {
			"ty": 0.28, "tz": -0.08, "tx": -0.05, "hy": -0.22, "hx": 0.04,
			"crouch": 0.09, "lean": 0.07,
			"wpx": 0.04, "wpy": 0.32, "wpz": -0.48,
			"wrx": 0.0, "wry": -1.775423, "wrz": 1.846555,
		}},
		{"t": 0.44, "p": {
			"ty": 0.44, "tz": -0.10, "tx": -0.07, "hy": -0.30, "hx": 0.05,
			"crouch": 0.11, "lean": 0.09,
			"wpx": 0.06, "wpy": 0.30, "wpz": -0.50,
			"wrx": 0.0, "wry": -0.5328, "wrz": 1.30,
		}},
		{"t": 0.60, "p": {
			"ty": 0.14, "tz": -0.03, "tx": -0.02, "hy": -0.06, "hx": 0.02,
			"crouch": 0.04, "lean": 0.03,
			"wpx": 0.02, "wpy": 0.28, "wpz": -0.46,
			"wrx": 0.0, "wry": -0.30, "wrz": 0.55,
		}},
		{"t": 0.84, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.14, 0.0], [0.30, 0.08], [0.52, 0.20], [0.84, 0.20]],
	"hit_at": 0.30, "hit_kind": "air", "style": "twohand",
}

# ---------------------------------------------------------------- 2. FRONT_L
# Exact mirror of FRONT_R: high left -> low right.
static var FRONT_L: Dictionary = mirrored(FRONT_R)

# ---------------------------------------------------------------- 3. RISE_R
# Rising fang: low right -> high left, blade dragged up through the front.
static var RISE_R: Dictionary = {
	"name": "RISE_R",
	"duration": 0.78,
	"trail": [0.18, 0.44],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.16, "p": {
			"ty": -0.32, "tz": 0.05, "tx": 0.02, "hy": 0.26, "hx": 0.06,
			"crouch": 0.18, "lean": -0.05,
			"wpx": 0.22, "wpy": 0.16, "wpz": -0.45,
			"wrx": 0.0, "wry": -2.3731, "wrz": 2.1535,
		}},
		{"t": 0.30, "p": {
			"ty": 0.08, "tz": -0.05, "tx": -0.04, "hy": -0.18, "hx": -0.03,
			"crouch": 0.04, "lean": 0.05,
			"wpx": 0.02, "wpy": 0.36, "wpz": -0.44,
			"wrx": 0.0, "wry": -1.0175, "wrz": 0.9268,
		}},
		{"t": 0.44, "p": {
			"ty": 0.34, "tz": -0.02, "tx": -0.06, "hy": -0.22, "hx": -0.04,
			"crouch": -0.03, "lean": 0.03,
			"wpx": -0.08, "wpy": 0.46, "wpz": -0.34,
			"wrx": 0.0, "wry": -1.0214, "wrz": 0.6112,
		}},
		{"t": 0.60, "p": {
			"ty": 0.12, "tx": -0.01, "hy": 0.04, "crouch": 0.02, "lean": 0.01,
			"wpx": 0.02, "wpy": 0.30, "wpz": -0.38,
			"wrx": 0.0, "wry": -0.60, "wrz": 0.42,
		}},
		{"t": 0.78, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.12, 0.0], [0.30, 0.30], [0.48, 0.42], [0.78, 0.42]],
	"hit_at": 0.30, "hit_kind": "air", "style": "twohand",
}

# ---------------------------------------------------------------- 4. RISE_L
# Exact mirror of RISE_R: low left -> high right.
static var RISE_L: Dictionary = mirrored(RISE_R)

# ------------------------------------------------------------ 5. SIDE_THRUST_R
# Right-hand side thrust without turning the waist.  The hilt travels straight
# out along +X at shoulder height, blade axis exactly +X, blade face vertical.
# The left hand is released and the rig raises it out of the guard.
static var SIDE_THRUST_R: Dictionary = {
	"name": "SIDE_THRUST_R",
	"duration": 0.82,
	"trail": [0.24, 0.48],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.07, "p": {
			"ty": 0.0, "tz": 0.02, "tx": 0.01, "hy": 0.08, "crouch": 0.03,
			"lean": -0.01, "offhand": 0.7, "left_raise": 0.0,
			"wpx": 0.20, "wpy": 0.26, "wpz": -0.44,
			"wrx": -0.12, "wry": 0.60, "wrz": -1.42,
		}},
		{"t": 0.14, "p": {
			"ty": 0.0, "tz": 0.03, "tx": 0.02, "hy": 0.14, "crouch": 0.06,
			"lean": -0.02,
			"wpx": 0.22, "wpy": 0.30, "wpz": -0.44,
			"wrx": 0.0, "wry": 1.15, "wrz": -1.5708,
			"offhand": 1.0, "left_raise": 0.0,
		}},
		{"t": 0.28, "p": {
			"ty": 0.0, "tz": -0.02, "tx": -0.01, "hy": 0.02, "crouch": 0.04,
			"lean": 0.02,
			"wpx": 0.32, "wpy": 0.40, "wpz": -0.30,
			"wrx": 0.0, "wry": 0.35, "wrz": -1.5708,
			"offhand": 1.0, "left_raise": 0.0,
		}},
		{"t": 0.34, "p": {
			"ty": 0.0, "tz": -0.03, "tx": -0.02, "hy": -0.06, "crouch": 0.04,
			"lean": 0.03,
			"wpx": 0.32, "wpy": 0.44, "wpz": -0.20,
			"wrx": 0.0, "wry": 0.0, "wrz": -1.5708,
			"offhand": 1.0, "left_raise": 0.0,
		}},
		{"t": 0.46, "p": {
			"ty": 0.0, "tz": -0.03, "tx": -0.02, "hy": -0.06, "crouch": 0.05,
			"lean": 0.04,
			"wpx": 0.32, "wpy": 0.44, "wpz": -0.20,
			"wrx": 0.0, "wry": 0.0, "wrz": -1.5708,
			"offhand": 1.0, "left_raise": 0.0,
		}},
		{"t": 0.58, "p": {
			"ty": 0.0, "tx": 0.0, "hy": 0.02, "crouch": 0.03, "lean": 0.01,
			"wpx": 0.28, "wpy": 0.34, "wpz": -0.36,
			"wrx": 0.0, "wry": 0.55, "wrz": -1.5708,
			"offhand": 1.0, "left_raise": 0.0,
		}},
		{"t": 0.82, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.14, 0.0], [0.30, 0.0], [0.50, 0.0], [0.82, 0.0]],
	"hit_at": 0.34, "hit_kind": "air", "style": "twohand",
}

# ---------------------------------------------------------------- 5b. SIDE_L
# Exact mirror of the right side thrust; still two-handed.
static var SIDE_THRUST_L: Dictionary = mirrored(SIDE_THRUST_R)

# ------------------------------------------------------------ 6. BACK_THRUST
# Reverse thrust, authored as a CONTINUOUS path (dense keys generated from a
# Catmull-Rom spline) instead of a handful of hand-typed poses, so no channel
# can ever snap:
#
#   A. 0.00-0.30  the blade - pointing up-forward in the guard - rolls about the
#                fore-aft axis to the left until it lies flat, tip to the left.
#   B. 0.10-0.30  the LEFT hand leaves the hilt and rises up-left (no teleport:
#                offhand/left_raise ramp).
#   C. 0.30-0.66  the right arm + sword rotate horizontally about the body's
#                vertical axis; the right fist travels around the front of the
#                belly to the centre line.  The right forearm is solved
#                perpendicular to the blade by the rig.
#   D. 0.66-0.80  the fist keeps pushing forward (upper arm to the left, torso
#                turns 41 deg) while the blade stays aimed straight back, and the
#                body throws itself backwards (-Z lunge) into the thrust.
#   E. 0.80-1.16  reverse the same swept path back to the guard.
#
# The blade direction is parameterised as
#     b = (-sin(psi) * cos(eps), sin(eps), cos(psi) * cos(eps))
# with psi measured from +Z (back) toward -X (left): forward = PI, left = PI/2.
# The orientation is the BASE guard orientation rotated along the shortest arc
# from b0 to b, so the blade's flat face never spins unexpectedly.
const BACK_DURATION := 1.34
const BACK_HIT := 0.80
const BACK_HIT_HAND := Vector3(0.02, 0.28, -0.38)
const BACK_HIT_PSI := 0.72
const BACK_HIT_YAW := 0.72

const BACK_WAYPOINTS := [
	{"t": 0.00, "h": Vector3(0.1928, 0.016, -0.329), "psi": 2.84, "eps": 1.30,
		"yaw": 0.00, "crouch": 0.00, "lean": 0.00, "tx": 0.00, "hy": 0.04, "off": 0.00, "raise": 0.00, "roll": 0.00},
	{"t": 0.12, "h": Vector3(0.165, 0.10, -0.340), "psi": 2.66, "eps": 1.06,
		"yaw": 0.02, "crouch": 0.02, "lean": 0.00, "tx": 0.01, "hy": 0.02, "off": 0.18, "raise": 0.30, "roll": 0.00},
	{"t": 0.22, "h": Vector3(0.070, 0.22, -0.350), "psi": 2.26, "eps": 0.62,
		"yaw": 0.05, "crouch": 0.04, "lean": 0.00, "tx": 0.02, "hy": -0.06, "off": 0.62, "raise": 0.80, "roll": 0.00},
	{"t": 0.32, "h": Vector3(-0.080, 0.300, -0.350), "psi": 1.82, "eps": 0.13,
		"yaw": 0.09, "crouch": 0.05, "lean": 0.01, "tx": 0.03, "hy": -0.14, "off": 1.00, "raise": 1.00, "roll": 0.15},
	{"t": 0.46, "h": Vector3(-0.130, 0.305, -0.400), "psi": 1.52, "eps": 0.03,
		"yaw": 0.20, "crouch": 0.06, "lean": 0.01, "tx": 0.03, "hy": -0.16, "off": 1.00, "raise": 1.00, "roll": 0.55},
	{"t": 0.58, "h": Vector3(-0.100, 0.300, -0.420), "psi": 1.12, "eps": 0.00,
		"yaw": 0.29, "crouch": 0.07, "lean": 0.02, "tx": 0.02, "hy": -0.14, "off": 1.00, "raise": 1.00, "roll": 0.85},
	{"t": 0.68, "h": Vector3(-0.070, 0.260, -0.500), "psi": 0.60, "eps": 0.00,
		"yaw": 0.36, "crouch": 0.075, "lean": 0.03, "tx": 0.01, "hy": -0.10, "off": 1.00, "raise": 1.00, "roll": 1.00},
	{"t": 0.80, "h": Vector3(-0.060, 0.220, -0.520), "psi": 0.26, "eps": 0.00,
		"yaw": 0.40, "crouch": 0.08, "lean": 0.04, "tx": 0.00, "hy": -0.06, "off": 1.00, "raise": 1.00, "roll": 1.00},
	{"t": 0.88, "h": Vector3(-0.060, 0.220, -0.520), "psi": 0.26, "eps": 0.00,
		"yaw": 0.40, "crouch": 0.08, "lean": 0.04, "tx": 0.00, "hy": -0.04, "off": 1.00, "raise": 1.00, "roll": 1.00},
	{"t": 0.98, "h": Vector3(0.010, 0.240, -0.530), "psi": 0.66, "eps": 0.04,
		"yaw": 0.34, "crouch": 0.06, "lean": 0.03, "tx": 0.01, "hy": -0.02, "off": 1.00, "raise": 1.00, "roll": 0.85},
	{"t": 1.07, "h": Vector3(0.070, 0.220, -0.400), "psi": 1.75, "eps": 0.22,
		"yaw": 0.22, "crouch": 0.04, "lean": 0.01, "tx": 0.02, "hy": 0.02, "off": 1.00, "raise": 1.00, "roll": 0.20},
	{"t": 1.18, "h": Vector3(0.160, 0.090, -0.360), "psi": 2.55, "eps": 0.85,
		"yaw": 0.07, "crouch": 0.02, "lean": 0.00, "tx": 0.01, "hy": 0.03, "off": 1.00, "raise": 1.00, "roll": 0.00},
	{"t": 1.27, "h": Vector3(0.188, 0.030, -0.342), "psi": 2.78, "eps": 1.20,
		"yaw": 0.02, "crouch": 0.00, "lean": 0.00, "tx": 0.00, "hy": 0.04, "off": 1.00, "raise": 1.00, "roll": 0.00},
	{"t": 1.34, "h": Vector3(0.1928, 0.016, -0.329), "psi": 2.84, "eps": 1.30,
		"yaw": 0.00, "crouch": 0.00, "lean": 0.00, "tx": 0.00, "hy": 0.04, "off": 1.00, "raise": 1.00, "roll": 0.00},
]


static func _back_base_basis() -> Basis:
	return Basis.from_euler(Vector3(
		float(BASE_POSE["wrx"]), float(BASE_POSE["wry"]), float(BASE_POSE["wrz"])),
		EULER_ORDER_YXZ)


static func _back_waypoint_scalar(arr: Array, t: float, key: String) -> float:
	var ts: Array = []
	for w in arr:
		ts.append(float(w["t"]))
	if t <= float(ts[0]):
		return float(arr[0][key])
	if t >= float(ts[ts.size() - 1]):
		return float(arr[ts.size() - 1][key])
	var i := 0
	for k in ts.size() - 1:
		if t >= float(ts[k]) and t <= float(ts[k + 1]):
			i = k
			break
	var t0: float = float(ts[maxi(i - 1, 0)])
	var t1: float = float(ts[i])
	var t2: float = float(ts[i + 1])
	var t3: float = float(ts[mini(i + 2, ts.size() - 1)])
	var v0: float = float(arr[maxi(i - 1, 0)][key])
	var v1: float = float(arr[i][key])
	var v2: float = float(arr[i + 1][key])
	var v3: float = float(arr[mini(i + 2, ts.size() - 1)][key])
	var m1 := (v2 - v0) / maxf(t2 - t0, 1e-4) * (t2 - t1)
	var m2 := (v3 - v1) / maxf(t3 - t1, 1e-4) * (t2 - t1)
	var u := (t - t1) / maxf(t2 - t1, 1e-5)
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * v1 + (u3 - 2.0 * u2 + u) * m1 \
		+ (-2.0 * u3 + 3.0 * u2) * v2 + (u3 - u2) * m2


static func _back_waypoint_vec(arr: Array, t: float, key: String) -> Vector3:
	var ts: Array = []
	for w in arr:
		ts.append(float(w["t"]))
	if t <= float(ts[0]):
		return arr[0][key]
	if t >= float(ts[ts.size() - 1]):
		return arr[ts.size() - 1][key]
	var i := 0
	for k in ts.size() - 1:
		if t >= float(ts[k]) and t <= float(ts[k + 1]):
			i = k
			break
	var t0: float = float(ts[maxi(i - 1, 0)])
	var t1: float = float(ts[i])
	var t2: float = float(ts[i + 1])
	var t3: float = float(ts[mini(i + 2, ts.size() - 1)])
	var v0: Vector3 = arr[maxi(i - 1, 0)][key]
	var v1: Vector3 = arr[i][key]
	var v2: Vector3 = arr[i + 1][key]
	var v3: Vector3 = arr[mini(i + 2, ts.size() - 1)][key]
	var m1 := (v2 - v0) / maxf(t2 - t0, 1e-4) * (t2 - t1)
	var m2 := (v3 - v1) / maxf(t3 - t1, 1e-4) * (t2 - t1)
	var u := (t - t1) / maxf(t2 - t1, 1e-5)
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * v1 + (u3 - 2.0 * u2 + u) * m1 \
		+ (-2.0 * u3 + 3.0 * u2) * v2 + (u3 - u2) * m2


static func _unwrap_euler(prev: Vector3, e: Vector3, first: bool) -> Vector3:
	if first:
		return e
	# YXZ triples are two-to-one: (rx,ry,rz) == (PI-rx, ry+PI, rz+PI).  Choose
	# the branch nearest the previous sample so get_euler()'s branch cut can
	# never snap the interpolated blade through 180 degrees.
	var best := Vector3.ZERO
	var best_d := 1.0e20
	for c in [e, Vector3(PI - e.x, e.y + PI, e.z + PI)]:
		var v: Vector3 = c
		for i in 3:
			while v[i] - prev[i] > PI:
				v[i] -= TAU
			while v[i] - prev[i] < -PI:
				v[i] += TAU
		var d := (v - prev).length_squared()
		if d < best_d:
			best_d = d
			best = v
	return best


static func back_pose_at(t: float) -> Dictionary:
	var h: Vector3 = _back_waypoint_vec(BACK_WAYPOINTS, t, "h")
	var psi: float = _back_waypoint_scalar(BACK_WAYPOINTS, t, "psi")
	var eps: float = _back_waypoint_scalar(BACK_WAYPOINTS, t, "eps")
	var b := Vector3(-sin(psi) * cos(eps), sin(eps), cos(psi) * cos(eps)).normalized()
	var base: Basis = _back_base_basis()
	var rot := Basis(Quaternion(base.y.normalized(), b))
	var bas := rot * base
	# Guard-bar roll: the 0.47 m crossguard must never sweep flat through the
	# chest.  As the blade flattens we roll it so the crossbar stands VERTICAL
	# (blade edge up), then roll back on the recovery.
	var roll_w: float = _back_waypoint_scalar(BACK_WAYPOINTS, t, "roll")
	if roll_w > 0.001:
		# Guard-bar roll: the 0.47 m crossguard must never sweep flat through the
		# chest.  Slerp the whole basis toward the orientation whose GUARD BAR
		# (the BladeRoll child's X) is vertical.
		var x_up := Vector3.UP - b * Vector3.UP.dot(b)
		if x_up.length_squared() > 1e-4:
			var x_target := (Basis(b, -2.35) * x_up.normalized()).normalized()
			var bas_v := Basis(x_target, b, x_target.cross(b).normalized())
			var q0 := bas.get_rotation_quaternion()
			var q1 := bas_v.get_rotation_quaternion()
			# explicit hemisphere fix: no long-way-around quaternion lerp
			if q0.dot(q1) < 0.0:
				q1 = Quaternion(-q1.x, -q1.y, -q1.z, -q1.w)
			bas = Basis(q0.slerp(q1, clampf(roll_w, 0.0, 1.0)))
	var e := bas.get_euler(EULER_ORDER_YXZ)
	var root := h + b * float(BASE_POSE.get("grip", 0.16))
	return {
		"wpx": root.x, "wpy": root.y, "wpz": root.z,
		"wrx": e.x, "wry": e.y, "wrz": e.z,
		"ty": _back_waypoint_scalar(BACK_WAYPOINTS, t, "yaw"),
		"crouch": _back_waypoint_scalar(BACK_WAYPOINTS, t, "crouch"),
		"lean": _back_waypoint_scalar(BACK_WAYPOINTS, t, "lean"),
		"tx": _back_waypoint_scalar(BACK_WAYPOINTS, t, "tx"),
		"hy": _back_waypoint_scalar(BACK_WAYPOINTS, t, "hy"),
		"offhand": _back_waypoint_scalar(BACK_WAYPOINTS, t, "off"),
		"left_raise": _back_waypoint_scalar(BACK_WAYPOINTS, t, "raise"),
	}


static func _branch_near(target: Vector3, e: Vector3) -> Vector3:
	var best := e
	var best_d := 1.0e20
	for c in [e, Vector3(PI - e.x, e.y + PI, e.z + PI)]:
		var v: Vector3 = c
		for i in 3:
			while v[i] - target[i] > PI:
				v[i] -= TAU
			while v[i] - target[i] < -PI:
				v[i] += TAU
		var d := (v - target).length_squared()
		if d < best_d:
			best_d = d
			best = v
	return best


static func make_back_thrust() -> Dictionary:
	var n := 202
	var keys: Array = []
	for i in n:
		var t: float = BACK_DURATION * float(i) / float(n - 1)
		var p: Dictionary = back_pose_at(t)
		keys.append({"t": t, "p": p})
	# Pick a CONSISTENT Euler branch from the END of the clip backwards.  The
	# final key must be the exact guard Euler (so the blend back to idle cannot
	# spin), and every earlier key takes the equivalent branch nearest the next
	# one.  This is what keeps the Euler path continuous through the recovery.
	var guard := Vector3(float(BASE_POSE["wrx"]), float(BASE_POSE["wry"]), float(BASE_POSE["wrz"]))
	var next := guard
	for i in range(n - 1, -1, -1):
		var p: Dictionary = keys[i]["p"]
		var e := Vector3(float(p["wrx"]), float(p["wry"]), float(p["wrz"]))
		if i == 0 or i == n - 1:
			e = guard
		else:
			e = _branch_near(next, e)
		p["wrx"] = e.x
		p["wry"] = e.y
		p["wrz"] = e.z
		next = e
	return {
		"name": "BACK_THRUST",
		"duration": BACK_DURATION,
		"trail": [0.52, 0.84],
		"keys": keys,
		"lunge": [[0.0, 0.0], [0.52, 0.0], [0.80, -0.58], [1.34, -0.58]],
		"hit_at": BACK_HIT, "hit_kind": "air", "style": "back_r",
	}


static var BACK_THRUST: Dictionary = make_back_thrust()


# ----------------------------------------------------------------- 7. HEAVY
# Guillotine: raise overhead, arch back, then crouch and slam the tip into the
# ground in front.  wrx drives the whole sagittal arc (up -> forward -> down).
static var HEAVY: Dictionary = {
	"name": "HEAVY",
	"duration": 1.48,
	"trail": [0.56, 0.80],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.34, "p": {
			"ty": 0.02, "tx": 0.12, "hy": 0.0, "hx": -0.15,
			"crouch": -0.06, "lean": -0.08,
			"wpx": 0.24, "wpy": 0.54, "wpz": -0.34,
			"wrx": 0.42, "wry": 0.0, "wrz": 0.03,
		}},
		{"t": 0.48, "p": {
			"ty": 0.0, "tx": 0.18, "hy": 0.0, "hx": -0.22,
			"crouch": -0.10, "lean": -0.12,
			"wpx": 0.24, "wpy": 0.64, "wpz": -0.34,
			"wrx": 0.72, "wry": 0.0, "wrz": 0.0,
		}},
		{"t": 0.55, "p": {
			"ty": 0.0, "tx": 0.10, "hy": 0.0, "hx": 0.0,
			"crouch": 0.14, "lean": -0.06,
			"wpx": 0.20, "wpy": 0.70, "wpz": -0.34,
			"wrx": -0.65, "wry": 0.0, "wrz": 0.01,
		}},
		{"t": 0.62, "p": {
			"ty": 0.0, "tx": 0.04, "hy": 0.0, "hx": 0.14,
			"crouch": 0.28, "lean": -0.02,
			"wpx": 0.20, "wpy": 0.73, "wpz": -0.34,
			"wrx": -1.85, "wry": 0.0, "wrz": 0.02,
		}},
		{"t": 0.70, "p": {
			"ty": 0.0, "tx": 0.0, "tz": 0.0, "hy": 0.0, "hx": 0.26,
			"crouch": 0.38, "lean": 0.0,
			"wpx": 0.20, "wpy": 0.74, "wpz": -0.34,
			"wrx": -2.95, "wry": 0.0, "wrz": 0.02,
		}},
		{"t": 0.84, "p": {
			"ty": 0.0, "tx": -0.24, "hy": 0.10, "hx": 0.20,
			"crouch": 0.24, "lean": 0.16,
			"wpx": 0.16, "wpy": 0.56, "wpz": -0.34,
			"wrx": -2.25, "wry": 0.0, "wrz": 0.04,
		}},
		{"t": 1.12, "p": {
			"ty": 0.0, "tx": -0.08, "hy": 0.03, "hx": 0.06,
			"crouch": 0.08, "lean": 0.04,
			"wpx": 0.20, "wpy": 0.30, "wpz": -0.38,
			"wrx": -1.35, "wry": 0.0, "wrz": 0.06,
		}},
		{"t": 1.48, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.48, 0.0], [0.60, 0.16], [0.84, 0.52], [1.48, 0.52]],
	"hit_at": 0.70, "hit_kind": "ground", "style": "twohand",
}

# ------------------------------------------------------------------ 8. SPIN
# Helix storm: waist ty runs 0 -> 2*PI, blade held out horizontally at chest
# height.  Keys 0.30 -> 1.16 are evenly spaced in ty so the mid-spin angular
# velocity is constant (the rig may replace ty with its own trapezoid).
static var SPIN: Dictionary = {
	"name": "SPIN",
	"duration": 1.42,
	"trail": [0.30, 1.20],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.20, "p": {
			"ty": -0.52, "tz": 0.06, "tx": 0.03, "hy": 0.28,
			"crouch": 0.10, "lean": 0.04,
			"wpx": 0.30, "wpy": 0.34, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.5061, "wrz": 1.4705,
		}},
		{"t": 0.30, "p": {
			"ty": 0.0, "crouch": 0.14, "lean": 0.06,
			"wpx": 0.20, "wpy": 0.36, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.7945, "wrz": 1.5708,
		}},
		{"t": 0.60, "p": {
			"ty": 2.10, "crouch": 0.14, "lean": 0.07,
			"wpx": 0.20, "wpy": 0.36, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.7945, "wrz": 1.5708,
		}},
		{"t": 0.90, "p": {
			"ty": 4.20, "crouch": 0.13, "lean": 0.07,
			"wpx": 0.20, "wpy": 0.36, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.7945, "wrz": 1.5708,
		}},
		{"t": 1.16, "p": {
			"ty": 6.02, "crouch": 0.10, "lean": 0.05,
			"wpx": 0.20, "wpy": 0.36, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.7945, "wrz": 1.5708,
		}},
		{"t": 1.30, "p": {
			"ty": TAU, "tz": -0.02, "crouch": 0.05, "lean": 0.02,
			"wpx": 0.28, "wpy": 0.32, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.2487, "wrz": 1.4202,
		}},
		{"t": 1.42, "p": {"ty": TAU}},
	],
	"lunge": [[0.0, 0.0], [0.20, 0.03], [0.50, 0.30], [0.80, 0.55], [1.10, 0.62], [1.42, 0.62]],
	"hit_at": 0.72, "hit_kind": "air", "style": "spin",
}

# --------------------------------------------------------------------- index
static var CLIPS: Dictionary = {}


static func _static_init() -> void:
	CLIPS = {
		"FRONT_R": FRONT_R,
		"FRONT_L": FRONT_L,
		"RISE_R": RISE_R,
		"RISE_L": RISE_L,
		"SIDE_THRUST_R": SIDE_THRUST_R,
		"SIDE_THRUST_L": SIDE_THRUST_L,
		"BACK_THRUST": BACK_THRUST,
		"HEAVY": HEAVY,
		"SPIN": SPIN,
	}


static func get_clip(name: String) -> Dictionary:
	return CLIPS.get(name, FRONT_R)


## Mix weight for the left hand: 0 = both hands on the hilt, 1 = left hand
## released and raised clear of the weapon.
static func offhand_for(clip_name: String) -> float:
	# Every shipped clip is two-handed on the hilt; the dedicated "side_r"
	# style exists for future one-hand choreography only.
	return 0.0


# ------------------------------------------------------------ mirror utility
## Reflect a clip left/right.  Only the channels present in each key are
## flipped; empty keys stay empty, so the mirrored clip enters and leaves
## through the same (asymmetric) ready stance as the original.
static func mirrored(clip: Dictionary) -> Dictionary:
	var out := clip.duplicate(true)
	var src_name := String(out.get("name", ""))
	if src_name.ends_with("_R"):
		out["name"] = src_name.substr(0, src_name.length() - 2) + "_L"
	elif src_name.ends_with("_L"):
		out["name"] = src_name.substr(0, src_name.length() - 2) + "_R"
	var new_keys: Array = []
	for key in out["keys"]:
		var pose: Dictionary = {}
		for ch in key.get("p", {}).keys():
			var v := float(key["p"][ch])
			if ch in MIRROR_CHANNELS:
				v = -v
			pose[ch] = v
		new_keys.append({"t": float(key["t"]), "p": pose})
	out["keys"] = new_keys
	return out


# ---------------------------------------------------------- special helpers
## Core of the right/left side thrust.  u = 0 is the start of the extension,
## u = 1 is full reach.  Hilt stays at shoulder height, blade axis is exactly
## +X * side, blade face vertical.  The lateral travel is what two 1.06 m arms
## can still hold with both fists on the hilt (the old 0.46 m reach needed
## 1.33 m arms); the blade is 1.53 m long, so the tip still clears a target
## standing 1.5 m away.
static func side_thrust_pose(u: float, side: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var s := signf(side)
	if s == 0.0:
		s = 1.0
	return {
		"wpx": s * lerpf(0.24, 0.32, u),
		"wpy": lerpf(0.38, 0.44, u),
		"wpz": lerpf(-0.34, -0.20, u),
		"wrx": 0.0,
		"wry": 0.0,
		"wrz": -s * PI * 0.5,
	}


## Core of the back thrust.  u = 0 is the low left-side carry just before the
## stab (blade swept under the torso), u = 1 is the contact pose: hilt at the
## centre-line (0.0, 0.16, 0.40), blade axis (-0.02, 0.05, 0.998) pointing almost
## straight behind so the tip reaches a 1.8 m target.
static func back_thrust_pose(u: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var sp := back_pose_at(lerpf(0.32, BACK_HIT, u))
	return {
		"wpx": float(sp["wpx"]), "wpy": float(sp["wpy"]), "wpz": float(sp["wpz"]),
		"wrx": float(sp["wrx"]), "wry": float(sp["wry"]), "wrz": float(sp["wrz"]),
		"ty": float(sp["ty"]),
	}


## Euler (YXZ) that aims sword local +Y along `axis` with the blade width as
## close to world up as possible (vertical blade plane).
static func _aim_euler(axis: Vector3) -> Vector3:
	var y := axis.normalized()
	var x := Vector3.UP - y * Vector3.UP.dot(y)
	if x.length_squared() < 0.0001:
		x = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z).get_euler(EULER_ORDER_YXZ)
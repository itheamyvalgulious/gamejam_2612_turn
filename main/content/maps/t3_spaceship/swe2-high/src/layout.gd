extends RefCounted

## Ship envelope + route + zone table. Everything downstream reads this, so a
## room can be resized by editing one Rect2 entry and the walls/corridors stay
## consistent (rooms are carved out of zones, separated by service corridors).

# ---------------- envelope -----------------
# +Z is stern (engine), -Z is bow (bridge). Ship-space metres.
const LEN := 300.0            # bow z=-150 .. stern plate z=+150
const W_MAX := 31.0           # half-beam at midbody
const H_BOT := -16.0
const H_TOP := 13.5
const WID_MID := [ -80.0, 120.0 ]     # z range of full beam
const DECK_ENG := -9.0        # engine deck floor (route start)
const DECK_MAIN := -1.0       # main deck floor
const DECK_CMD := 7.0         # command deck floor

# hull half-beam w(z) and superellipse exponent e(z)
static func hull_w(z: float) -> float:
	var w := W_MAX
	if z < WID_MID[0]:
		var t := clampf((z - (-150.0)) / (WID_MID[0] - (-150.0)), 0.0, 1.0)
		w *= pow(sin(t * PI * 0.5), 0.85)         # rounded taper to a soft nose
	elif z > WID_MID[1]:
		var t := clampf((z - WID_MID[1]) / (150.0 - WID_MID[1]), 0.0, 1.0)
		w *= 1.0 - 0.18 * t * t                    # slight flare-in at stern
	return w


static func hull_e(z: float) -> float:
	# squarer amidships, rounder at bow
	if z < WID_MID[0]:
		return lerpf(2.0, 2.7, clampf((z + 150.0) / 70.0, 0.0, 1.0))
	return 2.7


static func hull_pt(z: float, ang: float, grow := 0.0) -> Vector3:
	# superellipse section: x = w*sgn(cos)|cos|^a , y = cy + h*sgn(sin)|sin|^a
	var w := hull_w(z) + grow
	var e := hull_e(z)
	var a := 2.0 / e
	var c := cos(ang)
	var s := sin(ang)
	var x := w * signf(c) * pow(absf(c), a)
	var h_bot := H_BOT - grow
	var h_top := H_TOP + grow
	var yh := h_top if s >= 0.0 else h_bot
	var y := cy(z) + yh * signf(s) * pow(absf(s), a)
	return Vector3(x, y, z)


static func cy(_z: float) -> float:
	return -0.75   # vertical centre of section


# ---------------- route --------------------
## Main quest path, stern engine pit -> bridge. Roughly Z-descending.
var route: Array = []


func _init() -> void:
	route = [
		Vector3(0, DECK_ENG, 144),      # engine pit floor
		Vector3(0, DECK_ENG, 132),      # engine hall centre
		Vector3(0, DECK_ENG, 118),      # through thrust frame
		Vector3(0, DECK_ENG, 108),      # reactor chamber (through torus hole)
		Vector3(0, DECK_ENG, 98),       # fuel gallery
		Vector3(0, DECK_ENG, 86),       # machine corridor A
		Vector3(0, DECK_ENG, 74),       # machine corridor B
		Vector3(0, DECK_ENG, 64),       # cargo hold floor
		Vector3(6, DECK_ENG, 52),       # cargo ramp base
		Vector3(6, DECK_MAIN, 36),      # cargo ramp top
		Vector3(0, DECK_MAIN, 30),      # atrium entry
		Vector3(0, DECK_MAIN, 18),      # atrium centre
		Vector3(0, DECK_MAIN, 6),       # habitat spine
		Vector3(0, DECK_MAIN, -8),      # habitat spine
		Vector3(0, DECK_MAIN, -22),     # habitat spine
		Vector3(0, DECK_MAIN, -34),     # lobby
		Vector3(0, DECK_MAIN, -48),     # stair base
		Vector3(0, DECK_CMD, -70),      # stair top
		Vector3(0, DECK_CMD, -80),      # command corridor
		Vector3(0, DECK_CMD, -92),
		Vector3(0, DECK_CMD, -104),     # anteroom
		Vector3(0, DECK_CMD, -118),     # bridge
		Vector3(0, DECK_CMD, -128),     # viewport
	]


func route_len() -> float:
	var d := 0.0
	for i in range(route.size() - 1):
		d += (route[i] as Vector3).distance_to(route[i + 1])
	return d


# ---------------- zones --------------------
# Each zone: rect in ship XZ (full width x0..x1, z0..z1), floor/ceiling,
# wall/floor/ceiling material keys, light tint, detail level.
# Rooms inside a zone are generated on a corridor grid: the zone is carved
# into a spine corridor + room cells; between adjacent rooms a service gap.
func zones() -> Array:
	return [
		{"id": "engine", "x0": -20.0, "x1": 20.0, "z0": 116.0, "z1": 148.0,
			"y0": -13.0, "y1": -1.0, "floor": "floor_a", "wall": "metal_a",
			"ceil": "ceil", "light": Color(1.0, 0.62, 0.30), "detail": 3},
		{"id": "reactor", "x0": -16.0, "x1": 16.0, "z0": 100.0, "z1": 116.0,
			"y0": -13.0, "y1": -1.0, "floor": "floor_a", "wall": "metal_a",
			"ceil": "ceil", "light": Color(0.45, 0.7, 1.0), "detail": 3},
		{"id": "fuel", "x0": -14.0, "x1": 14.0, "z0": 88.0, "z1": 100.0,
			"y0": DECK_ENG, "y1": -1.5, "floor": "floor_a", "wall": "metal_a",
			"ceil": "ceil", "light": Color(1.0, 0.7, 0.35), "detail": 2},
		{"id": "machine", "x0": -14.0, "x1": 14.0, "z0": 66.0, "z1": 88.0,
			"y0": DECK_ENG, "y1": -2.0, "floor": "floor_a", "wall": "wall_a",
			"ceil": "ceil", "light": Color(1.0, 0.78, 0.5), "detail": 2},
		{"id": "cargo", "x0": -15.0, "x1": 15.0, "z0": 34.0, "z1": 66.0,
			"y0": DECK_ENG, "y1": 4.5, "floor": "floor_b", "wall": "metal_a",
			"ceil": "ceil", "light": Color(1.0, 0.85, 0.6), "detail": 3},
		{"id": "atrium", "x0": -15.0, "x1": 15.0, "z0": 8.0, "z1": 34.0,
			"y0": DECK_MAIN, "y1": 11.0, "floor": "floor_b", "wall": "wall_b",
			"ceil": "ceil", "light": Color(0.9, 0.95, 1.0), "detail": 3},
		{"id": "habitat", "x0": -14.0, "x1": 14.0, "z0": -38.0, "z1": 8.0,
			"y0": DECK_MAIN, "y1": 5.5, "floor": "floor_b", "wall": "wall_b",
			"ceil": "ceil", "light": Color(1.0, 0.9, 0.75), "detail": 2},
		{"id": "lobby", "x0": -12.0, "x1": 12.0, "z0": -48.0, "z1": -38.0,
			"y0": DECK_MAIN, "y1": 5.5, "floor": "floor_c", "wall": "wall_c",
			"ceil": "ceil", "light": Color(0.7, 0.85, 1.0), "detail": 2},
		{"id": "stair", "x0": -9.0, "x1": 9.0, "z0": -70.0, "z1": -48.0,
			"y0": DECK_MAIN, "y1": 13.0, "floor": "floor_c", "wall": "wall_c",
			"ceil": "ceil", "light": Color(0.7, 0.85, 1.0), "detail": 3},
		{"id": "command", "x0": -11.0, "x1": 11.0, "z0": -104.0, "z1": -70.0,
			"y0": DECK_CMD, "y1": 13.0, "floor": "floor_c", "wall": "wall_c",
			"ceil": "ceil", "light": Color(0.6, 0.8, 1.0), "detail": 2},
		{"id": "bridge", "x0": -10.0, "x1": 10.0, "z0": -136.0, "z1": -104.0,
			"y0": DECK_CMD, "y1": 13.5, "floor": "floor_c", "wall": "wall_c",
			"ceil": "ceil", "light": Color(0.5, 0.75, 1.0), "detail": 3},
	]

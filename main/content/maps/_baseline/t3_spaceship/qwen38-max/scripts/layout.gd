class_name Layout
extends RefCounted
## Ship layout data: decks, rooms, doors, window bands, main route.
## Units: meters. x: 0 = stern transom -> 280 = bow. z: -port / +starboard.
## Decks: 0 engineering y=0, 1 main y=7.5, 2 command y=15. Pitch 7.5, clear height 6.
## Door `pos` is an ABSOLUTE coordinate along the wall (x for N/S walls, z for W/E walls).
## Wall sides: N = z0 wall, S = z1 wall, W = x0 wall, E = x1 wall.

const DECK_Y := [0.0, 7.5, 15.0]
const DECK_CEIL := [6.0, 13.5, 21.0]
const SHIP_L := 280.0
const HULL_TOP := 24.0
const HULL_KEEL := -3.5
const WALL_T := 0.3

var rng := RandomNumberGenerator.new()
var rooms: Array = []
var route: Array = []  # main route polyline (floor level +0.02)

const STYLE_TINT := {
	"engine": Color(1.0, 0.62, 0.25),
	"control": Color(1.0, 0.7, 0.35),
	"airlock": Color(1.0, 0.45, 0.15),
	"junction": Color(0.55, 0.8, 1.0),
	"ramp": Color(0.9, 0.78, 0.35),
	"shaft": Color(0.7, 0.82, 0.95),
	"corridor": Color(0.5, 0.78, 1.0),
	"cargo": Color(0.85, 0.72, 0.3),
	"utility": Color(0.6, 0.72, 0.8),
	"life": Color(0.35, 0.9, 0.55),
	"mess": Color(1.0, 0.8, 0.5),
	"medical": Color(0.55, 0.88, 1.0),
	"hydro": Color(0.85, 0.45, 1.0),
	"lab": Color(0.6, 0.92, 0.92),
	"quarters": Color(1.0, 0.75, 0.55),
	"gym": Color(0.95, 0.7, 0.4),
	"hangar": Color(0.92, 0.85, 0.4),
	"catwalk": Color(0.9, 0.8, 0.4),
	"server": Color(0.3, 0.72, 1.0),
	"lounge": Color(0.62, 0.8, 1.0),
	"bridge": Color(0.55, 0.78, 1.0),
	"office": Color(0.7, 0.75, 0.85),
	"storage": Color(0.72, 0.7, 0.6),
	"eva": Color(1.0, 0.55, 0.25),
	"pods": Color(1.0, 0.6, 0.3),
	"tanks": Color(0.4, 0.75, 0.8),
}

func _init(p_seed: int = 7) -> void:
	rng.seed = p_seed
	_build()
	_jitter()
	_build_route()

# --------------------------------------------------------------- hull shape

static func hull_half_width(x: float) -> float:
	if x <= 8.0:
		return 44.0
	if x <= 40.0:
		return 44.0 + 6.0 * _ss((x - 8.0) / 32.0)
	if x <= 200.0:
		return 50.0
	var t := clampf((x - 200.0) / 80.0, 0.0, 1.0)
	return 3.0 + 47.0 * pow(maxf(1.0 - t * t, 0.0), 0.9)

static func hull_half_height(x: float) -> float:
	if x <= 250.0:
		return 13.75
	var t := clampf((x - 250.0) / 30.0, 0.0, 1.0)
	return 3.5 + 10.25 * pow(maxf(1.0 - t * t, 0.0), 0.6)

static func hull_center_y() -> float:
	return (HULL_TOP + HULL_KEEL) * 0.5

static func _ss(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

# --------------------------------------------------------------- helpers

func R(name: String, deck: int, x0: float, x1: float, z0: float, z1: float, style: String, detail: int) -> Dictionary:
	var r := {
		"name": name, "deck": deck, "x0": x0, "x1": x1, "z0": z0, "z1": z1,
		"style": style, "detail": detail,
		"y0": DECK_Y[deck], "y1": DECK_CEIL[deck],
		"doors": [], "floor_holes": [], "ceil_holes": [], "win": [],
		"open_sides": [],      # sides with railing instead of wall: "N","S","E","W"
		"seed": rng.randf(),
		"no_floor": false, "no_ceil": false, "no_walls": false,
		"custom": "",
		"jx": [], "jz": [],    # jitter-allowed edges
	}
	rooms.append(r)
	return r

func D(r: Dictionary, side: String, pos: float, w: float, h: float = 3.0, kind: String = "std", open: bool = true) -> void:
	r["doors"].append({"side": side, "pos": pos, "w": w, "h": h, "kind": kind, "open": open})

func WIN(r: Dictionary, side: String, a0: float, a1: float, y0: float, y1: float) -> void:
	r["win"].append({"side": side, "a0": a0, "a1": a1, "y0": y0, "y1": y1})

# --------------------------------------------------------------- the ship

func _build() -> void:
	# ================= DECK 0 — engineering =================
	var eng := R("ENGINE BAY", 0, 4, 56, -40, 40, "engine", 2)
	eng["no_walls"] = true

	var ctrl := R("REACTOR CONTROL", 0, 56, 66, -24, 24, "control", 2)
	D(ctrl, "W", -18.75, 2.5, 3.0, "std", true)
	D(ctrl, "W", 18.75, 2.5, 3.0, "std", true)
	D(ctrl, "E", 0.0, 3.2, 3.2, "airlock", true)
	D(ctrl, "N", 61.0, 2.4, 2.8, "std", true)
	D(ctrl, "S", 61.0, 2.4, 2.8, "std", true)
	WIN(ctrl, "W", -10.0, 10.0, 1.0, 4.2)

	var airlock := R("AIRLOCK A-1", 0, 66, 74, -6, 6, "airlock", 2)
	D(airlock, "W", 0.0, 3.2, 3.2, "airlock", true)
	D(airlock, "E", 0.0, 3.2, 3.2, "airlock", true)
	D(airlock, "N", 70.0, 2.0, 2.6, "std", false)
	D(airlock, "S", 70.0, 2.0, 2.6, "std", false)

	var jct := R("JUNCTION J-1", 0, 74, 86, -10, 10, "junction", 2)
	D(jct, "W", 0.0, 3.2, 3.2, "airlock", true)
	D(jct, "N", 81.0, 6.0, 4.0, "wide", true)
	D(jct, "E", 0.0, 6.0, 4.0, "wide", true)
	D(jct, "S", 79.0, 3.0, 3.0, "std", true)

	var shaftA0 := R("STAIR SHAFT A - D0", 0, 74, 86, 10, 22, "shaft", 1)
	shaftA0["ceil_holes"].append(Rect2(78.3, 12.0, 2.6, 8.8))
	D(shaftA0, "N", 79.0, 3.0, 3.0, "std", true)

	var cool := R("COOLANT PLANT", 0, 56, 66, 24, 40, "utility", 1)
	var cpump := R("COOLANT PUMPS", 0, 66, 74, 24, 40, "utility", 0)
	D(cpump, "W", 32.0, 2.0, 2.6, "std", false)
	var taux := R("TURBINE AUX", 0, 56, 74, -40, -24, "utility", 0)
	D(taux, "S", 61.0, 2.4, 2.6, "std", false)
	D(taux, "S", 70.0, 2.0, 2.6, "std", false)
	var pump2 := R("PUMP ROOM", 0, 66, 74, -24, -6, "utility", 0)
	D(pump2, "S", 70.0, 2.0, 2.6, "std", false)
	R("CABLE CELLAR", 0, 74, 78, -34, -16, "utility", 0)

	var ramp := R("CARGO RAMP R-1", 0, 74, 114, -16, -10, "ramp", 2)
	ramp["custom"] = "ramp"
	D(ramp, "S", 81.0, 6.0, 4.0, "wide", true)
	var hvac := R("HVAC BAY", 0, 78, 114, -34, -16, "utility", 0)
	D(hvac, "S", 96.0, 2.4, 2.6, "std", false)
	var pump3 := R("HYDRAULICS", 0, 86, 114, -10, -3, "utility", 0)
	D(pump3, "S", 100.0, 2.4, 2.6, "std", true)

	R("SPINE C-0 DECK 0", 0, 86, 226, -3, 3, "corridor", 2)
	var cargoA := R("CARGO HOLD A", 0, 88, 126, 3, 40, "cargo", 1)
	cargoA["jx"] = ["x1"]
	D(cargoA, "N", 100.0, 4.0, 3.4, "wide", true)
	var cargoB := R("CARGO HOLD B", 0, 128, 166, 3, 40, "cargo", 0)
	cargoB["jx"] = ["x0", "x1"]
	D(cargoB, "N", 140.0, 4.0, 3.4, "wide", false)
	var life := R("LIFE SUPPORT", 0, 168, 200, 3, 36, "life", 1)
	life["jx"] = ["x0", "x1"]
	D(life, "N", 180.0, 3.0, 3.0, "std", true)
	var fstore := R("FORWARD STORE", 0, 202, 226, 3, 30, "storage", 0)
	D(fstore, "N", 210.0, 2.4, 2.8, "std", false)

	var work := R("MACHINE WORKSHOP", 0, 116, 146, -34, -3, "utility", 1)
	work["jx"] = ["x1"]
	D(work, "S", 130.0, 3.0, 3.0, "std", true)
	var ordn := R("ORDNANCE STORE", 0, 148, 176, -32, -3, "storage", 0)
	D(ordn, "S", 160.0, 2.4, 2.8, "std", false)
	var waste := R("WASTE RECYCLING", 0, 178, 202, -30, -3, "utility", 0)
	D(waste, "S", 190.0, 2.4, 2.8, "std", false)
	var pods0 := R("POD BAY LOWER", 0, 204, 226, -28, -3, "pods", 1)
	D(pods0, "S", 214.0, 3.0, 3.0, "std", true)

	R("SPINE C-0E", 0, 238, 246, -3, 3, "corridor", 0)
	var shaftB0 := R("STAIR SHAFT B - D0", 0, 226, 238, -8, 8, "shaft", 0)
	shaftB0["ceil_holes"].append(Rect2(234.0, -5.9, 3.6, 11.9))
	D(shaftB0, "W", 0.0, 3.0, 3.0, "std", true)
	D(shaftB0, "E", 0.0, 3.0, 3.0, "std", true)
	var sensor := R("SENSOR BAY", 0, 238, 246, 3, 22, "utility", 0)
	D(sensor, "N", 242.0, 2.0, 2.6, "std", false)
	var tanks0 := R("WATER TANKS", 0, 238, 246, -22, -8, "tanks", 0)
	var ballast0 := R("TRIM TANKS", 0, 226, 238, -22, -8, "tanks", 0)

	# ================= DECK 1 — main =================
	var driveup := R("DRIVE MACHINERY UPPER", 1, 4, 56, -40, 40, "utility", 0)
	D(driveup, "E", 20.0, 3.0, 3.0, "std", false)
	var gal1 := R("TURBINE GALLERY", 1, 56, 74, 6, 40, "utility", 1)
	D(gal1, "N", 63.0, 2.4, 2.8, "std", true)
	var wc1 := R("WEST PASSAGE D1", 1, 56, 74, -8, 6, "corridor", 1)
	D(wc1, "E", 0.0, 2.4, 2.8, "std", true)
	D(wc1, "N", 63.5, 2.4, 2.8, "std", true)
	D(wc1, "S", 63.0, 2.4, 2.8, "std", true)
	var eva := R("EVA AIRLOCK", 1, 56, 74, -24, -8, "eva", 1)
	var evac := R("EVA TUBE", 1, 62, 66, -48, -24, "eva", 1)
	evac["custom"] = "tube"
	D(evac, "N", 64.0, 1.8, 2.4, "airlock", false)
	D(evac, "S", 64.0, 2.2, 2.6, "std", true)
	var pstore := R("PORT CHASE STORE", 1, 56, 74, -40, -24, "storage", 0)
	D(pstore, "S", 60.0, 2.0, 2.6, "std", false)

	var shaftA1 := R("STAIR SHAFT A - D1", 1, 74, 86, 10, 22, "shaft", 1)
	shaftA1["floor_holes"].append(Rect2(78.3, 15.3, 2.6, 5.2))
	shaftA1["ceil_holes"].append(Rect2(78.3, 12.0, 2.6, 8.6))
	D(shaftA1, "N", 82.5, 2.4, 2.6, "std", true)
	D(shaftA1, "W", 16.0, 2.4, 2.6, "std", true)
	var vest1 := R("VESTIBULE D1", 1, 74, 86, 3, 10, "corridor", 1)
	D(vest1, "N", 80.0, 2.4, 2.6, "std", true)
	D(vest1, "S", 82.5, 2.4, 2.6, "std", true)
	var s1store := R("STORE S-1", 1, 74, 86, -10, -3, "storage", 0)
	D(s1store, "S", 80.0, 2.0, 2.6, "std", false)
	var cold := R("COLD STORAGE", 1, 86, 114, -10, -3, "storage", 0)
	D(cold, "S", 100.0, 2.4, 2.6, "std", false)
	var duct := R("DUCT FARM", 1, 74, 114, -38, -16, "utility", 0)
	var lobby1 := R("RAMP LOBBY D1", 1, 114, 124, -16, -3, "junction", 1)
	D(lobby1, "S", 118.0, 4.0, 3.4, "wide", true)
	D(lobby1, "W", -6.5, 2.4, 2.6, "std", true)
	WIN(lobby1, "W", -15.2, -11.0, 8.6, 10.6)

	R("SPINE C-1 DECK 1", 1, 74, 226, -3, 3, "corridor", 2)
	var sp1e := R("SPINE C-1E", 1, 238, 250, -3, 3, "corridor", 1)
	D(sp1e, "W", 0.0, 4.0, 3.2, "std", true)
	var mess := R("MESS HALL", 1, 86, 126, 3, 32, "mess", 2)
	mess["jx"] = ["x1"]
	D(mess, "N", 100.0, 4.0, 3.2, "wide", true)
	var med := R("MEDICAL BAY", 1, 128, 160, 3, 30, "medical", 2)
	med["jx"] = ["x0", "x1"]
	D(med, "N", 140.0, 3.0, 3.0, "std", true)
	var hydro := R("HYDROPONICS", 1, 162, 200, 3, 36, "hydro", 2)
	hydro["jx"] = ["x0", "x1"]
	D(hydro, "N", 176.0, 3.0, 3.2, "std", true)
	var lab := R("SCIENCE LAB", 1, 202, 224, 3, 26, "lab", 1)
	D(lab, "N", 210.0, 2.4, 2.8, "std", false)
	var pods1 := R("POD BAY UPPER", 1, 238, 250, 3, 20, "pods", 1)
	D(pods1, "N", 244.0, 3.0, 3.0, "std", true)
	var ballast := R("FWD BALLAST", 1, 238, 250, -20, -3, "tanks", 0)
	D(ballast, "S", 244.0, 2.0, 2.6, "std", false)

	var hangar := R("HANGAR BAY", 1, 124, 196, -44, -3, "hangar", 2)
	hangar["y1"] = 21.0
	hangar["no_ceil"] = true
	D(hangar, "S", 136.0, 12.0, 5.5, "hangar", true)
	var q1 := R("CAPTAIN'S QUARTERS", 1, 196, 210, -32, -3, "quarters", 2)
	D(q1, "S", 203.0, 2.4, 2.8, "std", true)
	D(q1, "N", 203.0, 2.4, 2.8, "std", true)
	var gym := R("GYM", 1, 196, 210, -42, -32, "gym", 1)
	D(gym, "S", 203.0, 2.4, 2.8, "std", true)
	var q2 := R("CREW QUARTERS Q-2", 1, 212, 224, -30, -3, "quarters", 1)
	D(q2, "S", 218.0, 2.4, 2.8, "std", true)
	D(q2, "N", 218.0, 2.0, 2.6, "std", true)
	var rec := R("RECREATION", 1, 212, 224, -40, -30, "gym", 0)
	D(rec, "S", 218.0, 2.0, 2.6, "std", false)

	var shaftB1 := R("STAIR SHAFT B - D1", 1, 226, 238, -8, 8, "shaft", 1)
	shaftB1["floor_holes"].append(Rect2(234.0, -1.0, 3.6, 7.0))
	shaftB1["ceil_holes"].append(Rect2(234.0, -5.9, 3.6, 11.9))
	D(shaftB1, "W", 0.0, 4.0, 3.2, "wide", true)
	D(shaftB1, "E", 0.0, 4.0, 3.2, "wide", true)

	# ================= DECK 2 — command =================
	var arch2 := R("ARCHIVE", 2, 74, 88, -30, -3, "office", 0)
	D(arch2, "S", 80.0, 2.4, 2.8, "std", false)
	var chart := R("CHART ROOM", 2, 88, 122, -30, -3, "office", 0)
	D(chart, "S", 104.0, 2.4, 2.8, "std", false)
	var shaftA2 := R("STAIR SHAFT A - D2", 2, 74, 86, 10, 22, "shaft", 1)
	shaftA2["floor_holes"].append(Rect2(78.3, 15.3, 2.6, 5.2))
	D(shaftA2, "N", 82.5, 2.4, 2.6, "std", true)
	var vest2 := R("VESTIBULE D2", 2, 74, 86, 3, 10, "corridor", 1)
	D(vest2, "N", 80.0, 2.4, 2.6, "std", true)
	D(vest2, "S", 82.5, 2.4, 2.6, "std", true)

	R("SPINE C-2 DECK 2", 2, 74, 226, -3, 3, "corridor", 1)
	var admin := R("ADMINISTRATION", 2, 88, 118, 3, 26, "office", 0)
	D(admin, "N", 100.0, 2.4, 2.8, "std", false)
	var ward := R("WARDROOM", 2, 120, 150, 3, 24, "mess", 1)
	D(ward, "N", 132.0, 3.0, 3.0, "std", true)
	var server := R("SERVER CORE", 2, 152, 192, 3, 32, "server", 2)
	server["jx"] = ["x1"]
	D(server, "N", 168.0, 3.0, 3.2, "std", true)
	var brief := R("BRIEFING ROOM", 2, 194, 224, 3, 26, "lab", 1)
	D(brief, "N", 206.0, 3.0, 3.0, "std", false)

	var catwalk := R("HANGAR CATWALK D2", 2, 124, 196, -8, -3, "catwalk", 2)
	catwalk["open_sides"] = ["N"]
	catwalk["no_ceil"] = true
	D(catwalk, "S", 130.0, 4.0, 3.2, "wide", true)
	D(catwalk, "E", -5.5, 2.4, 2.8, "std", true)
	var catwalkX := R("HANGAR CATWALK X", 2, 188, 196, -40, -8, "catwalk", 1)
	catwalkX["open_sides"] = ["W", "E", "S"]
	catwalkX["no_ceil"] = true
	var lounge := R("OBSERVATION LOUNGE", 2, 196, 226, -44, -3, "lounge", 2)
	D(lounge, "S", 210.0, 3.0, 3.2, "std", true)
	D(lounge, "W", -5.5, 2.4, 2.8, "std", true)
	WIN(lounge, "N", 200.0, 222.0, 16.2, 19.8)

	var shaftB2 := R("STAIR SHAFT B - D2", 2, 226, 238, -8, 8, "shaft", 2)
	shaftB2["floor_holes"].append(Rect2(234.0, -1.0, 3.6, 7.0))
	D(shaftB2, "W", 0.0, 4.0, 3.2, "wide", true)
	D(shaftB2, "E", 0.0, 4.0, 3.2, "wide", true)
	var navcom := R("NAV / COMMS", 2, 238, 248, 3, 18, "office", 1)
	D(navcom, "N", 244.0, 2.4, 2.8, "std", true)
	var cmd := R("COMMAND PASSAGE", 2, 238, 248, -3, 3, "corridor", 2)
	D(cmd, "W", 0.0, 4.0, 3.2, "wide", true)
	D(cmd, "E", 0.0, 5.0, 3.6, "wide", true)

	var bridge := R("BRIDGE", 2, 248, 262, -22, 22, "bridge", 2)
	bridge["no_walls"] = true
	bridge["custom"] = "bridge"
	D(bridge, "W", 0.0, 5.0, 3.6, "wide", true)
	var bridge2 := R("BRIDGE FWD", 2, 262, 268, -16, 16, "bridge", 2)
	bridge2["no_walls"] = true
	bridge2["custom"] = "bridge2"
	var ready := R("READY ROOM", 2, 248, 256, 10, 22, "quarters", 1)
	ready["custom"] = "ready"
	ready["no_walls"] = true
	D(ready, "S", 252.0, 2.2, 2.6, "std", true)

func _jitter() -> void:
	# Room-size adjustability: interior partition edges and outer depths jitter
	# within a bounded range. Corridor-adjacent walls never move, so corridors
	# keep constant width and rooms never collide (requirement: sizes adjustable,
	# corridors separate rooms).
	for r in rooms:
		for e in r["jx"]:
			r[e] += rng.randf_range(-0.9, 0.9)
		for e in r["jz"]:
			r[e] += rng.randf_range(-2.0, 2.0)
		var bmax: float = hull_half_width((r["x0"] + r["x1"]) * 0.5) - 5.0
		r["z1"] = minf(r["z1"], bmax)
		r["z0"] = maxf(r["z0"], -bmax)

func _build_route() -> void:
	route = [
		# engine bay
		Vector3(16, 0.02, 16), Vector3(24, 0.02, 10), Vector3(29, 0.02, 2), Vector3(40, 0.02, 0), Vector3(50, 0.02, 8),
		# into reactor control through south door (z=+18.75)
		Vector3(54, 0.02, 16), Vector3(56.2, 0.02, 18.7), Vector3(58.5, 0.02, 18.7), Vector3(60, 0.02, 14), Vector3(61, 0.02, 4),
		# airlock
		Vector3(64, 0.02, 0), Vector3(67, 0.02, 0), Vector3(71, 0.02, 0), Vector3(75, 0.02, 0),
		# junction -> ramp
		Vector3(80, 0.02, -2), Vector3(81, 0.02, -7), Vector3(81, 0.15, -11), Vector3(86, 1.7, -13),
		Vector3(96, 3.77, -13), Vector3(106, 5.85, -13), Vector3(113, 7.3, -13),
		# deck1 lobby -> spine
		Vector3(117, 7.52, -12), Vector3(118, 7.52, -8), Vector3(118, 7.52, -3.5), Vector3(121, 7.52, 0),
		Vector3(140, 7.52, 0), Vector3(160, 7.52, 0), Vector3(180, 7.52, 0), Vector3(200, 7.52, 0), Vector3(220, 7.52, 0),
		# shaft B: flight A up (z +6 -> -6), landing, flight B up (z -6 -> +6)
		Vector3(225.5, 7.52, 0), Vector3(227.5, 7.52, 2.5), Vector3(228.5, 7.6, 5.2),
		Vector3(228.5, 8.59, 2.5), Vector3(228.5, 9.84, -1.5), Vector3(228.5, 10.87, -4.8),
		Vector3(229.5, 11.27, -7), Vector3(233, 11.27, -7), Vector3(235.5, 11.5, -5.2),
		Vector3(235.5, 12.5, -2), Vector3(235.5, 13.75, 2), Vector3(235.5, 14.75, 5.2),
		# deck2: step-off north, west along strip, south lane, east to command
		Vector3(235.5, 15.02, 7), Vector3(231, 15.02, 7), Vector3(228.5, 15.02, 5.5), Vector3(228.5, 15.02, 1),
		Vector3(230, 15.02, -2.5), Vector3(234, 15.02, -3), Vector3(237.5, 15.02, -2),
		Vector3(240, 15.02, 0), Vector3(244, 15.02, 0), Vector3(248.5, 15.02, 0),
		# bridge
		Vector3(252, 15.02, 0), Vector3(257, 15.02, 0), Vector3(262, 15.02, 0), Vector3(265, 15.02, 0),
	]

func get_room(rname: String) -> Dictionary:
	for r in rooms:
		if r["name"] == rname:
			return r
	return {}

func rooms_at(deck: int) -> Array:
	var out := []
	for r in rooms:
		if r["deck"] == deck:
			out.append(r)
	return out

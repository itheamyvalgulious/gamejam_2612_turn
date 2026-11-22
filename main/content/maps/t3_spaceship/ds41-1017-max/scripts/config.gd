class_name ShipConfig
extends RefCounted

## Single source of truth for the ship's dimensions, decks and zone layout.
## The hull is fixed; rooms are inset from their module envelopes by
## `room_scale` and `side_room_w`, so interior volumes can be re-tuned
## within their min/max bounds without touching the exterior.

const BOW := -152.0
const STERN := 150.0
const DECK_ENG := -20.0
const DECK_LOW := -12.0
const DECK_MAIN := -4.0
const DECK_UPPER := 4.0
const DECK_TOP := 12.0
const DECK_H := 6.4

# --- adjustable knobs (documented in README) --------------------------------
var room_scale := 1.0        # 0.94 .. 1.06 : pulls room walls in/out
var side_room_w := 15.0      # 13 .. 18      : quarters / medbay depth
var shop_depth := 4.0        # 3.2 .. 5.0    : atrium storefront depth
var gallery_depth := 5.0     # 4.2 .. 6.0    : atrium balcony depth
var atrium_open_w := 9.0     # 8 .. 10       : half width of atrium void
var corridor_w := 6.2        # 5.2 .. 7.4    : main spine corridor width

# --- module envelopes (fixed) ------------------------------------------------
var zones := {
	"engine":   {"x0": -19.0, "x1": 19.0, "z0": 92.0, "z1": 148.0, "y": DECK_ENG, "h": 16.6},
	"cargo":    {"x0": -28.0, "x1": 28.0, "z0": 42.0, "z1": 82.0, "y": DECK_LOW, "h": 7.4},
	"corr_aft": {"x0": -corridor_w * 0.5, "x1": corridor_w * 0.5, "z0": 16.0, "z1": 42.0, "y": DECK_LOW, "h": 4.4},
	"spine":    {"x0": -corridor_w * 0.5, "x1": corridor_w * 0.5, "z0": -24.0, "z1": 10.0, "y": DECK_MAIN, "h": 4.6},
	"reactor":  {"x0": -20.0, "x1": 20.0, "z0": -54.0, "z1": -24.0, "y": DECK_MAIN, "h": 13.2},
	"atrium":   {"x0": -18.0, "x1": 18.0, "z0": -92.0, "z1": -58.0, "y": DECK_MAIN, "h": 18.0},
	"hydro":    {"x0": -11.0, "x1": 11.0, "z0": -116.0, "z1": -92.0, "y": DECK_UPPER, "h": 8.2},
	"bridge_approach": {"x0": -3.0, "x1": 3.0, "z0": -124.0, "z1": -116.0, "y": DECK_UPPER, "h": 4.6},
	"bridge":   {"x0": -7.4, "x1": 7.4, "z0": -147.0, "z1": -124.0, "y": 12.6, "h": 4.6},
	"quarters": {"x0": 14.0, "x1": 14.0 + side_room_w, "z0": -48.0, "z1": -30.0, "y": DECK_UPPER, "h": 4.2},
	"medbay":   {"x0": -14.0 - side_room_w, "x1": -14.0, "z0": -48.0, "z1": -30.0, "y": DECK_UPPER, "h": 4.2},
	"hangar":   {"x0": -13.0, "x1": 13.0, "z0": -88.0, "z1": -58.0, "y": DECK_LOW, "h": 7.6},
	"machine":  {"x0": -13.0, "x1": 13.0, "z0": -56.0, "z1": -30.0, "y": DECK_LOW, "h": 7.0},
	"tanks":    {"x0": -18.0, "x1": 18.0, "z0": -28.0, "z1": 0.0, "y": DECK_LOW, "h": 7.0},
	"observation": {"x0": -11.0, "x1": 11.0, "z0": -54.0, "z1": -30.0, "y": DECK_TOP, "h": 4.9},
	"officers": {"x0": -11.0, "x1": 11.0, "z0": -28.0, "z1": -8.0, "y": DECK_TOP, "h": 4.9},
	"galley":   {"x0": 14.0, "x1": 14.0 + side_room_w, "z0": -92.0, "z1": -76.0, "y": DECK_UPPER, "h": 4.2},
	"shops":    {"x0": -18.0, "x1": 18.0, "z0": -92.0, "z1": -58.0, "y": DECK_MAIN},
}

# Zone labels for signage / HUD.
var zone_names := {
	"engine": "ENGINEERING · AFT DRIVE",
	"cargo": "CARGO HOLD 2",
	"corr_aft": "SERVICE SPINE · AFT",
	"spine": "MAIN SPINE · DECK B",
	"reactor": "REACTOR HALL",
	"atrium": "CENTRAL GALLERIA",
	"hydro": "HYDROPONICS / BIO DOME",
	"bridge_approach": "COMMAND ACCESS",
	"bridge": "COMMAND BRIDGE",
	"quarters": "CREW QUARTERS",
	"medbay": "MEDICAL BAY",
	"hangar": "SHUTTLE HANGAR",
	"machine": "MACHINE SHOP",
	"tanks": "PROCESSING & TANKS",
	"observation": "OBSERVATION LOUNGE",
	"officers": "OFFICER COUNTRY",
	"galley": "GALLEY & MESS",
}

# The playable route, stern engine sub-deck -> bridge.
var route: Array = [
	Vector3(8.5, DECK_ENG + 0.1, 144.0),
	Vector3(8.5, DECK_ENG + 0.1, 124.0),
	Vector3(8.5, DECK_ENG + 0.1, 106.0),
	Vector3(8.5, DECK_ENG + 0.1, 96.0),
	Vector3(15.9, DECK_ENG + 0.1, 92.0),
	Vector3(15.9, DECK_ENG + 0.6, 91.0),
	Vector3(15.9, DECK_LOW + 0.1, 84.0),
	Vector3(12.0, DECK_LOW + 0.1, 80.0),
	Vector3(0.0, DECK_LOW + 0.1, 74.0),
	Vector3(0.0, DECK_LOW + 0.1, 30.0),
	Vector3(0.0, DECK_LOW + 0.1, 18.0),
	Vector3(0.0, DECK_LOW + 0.1, 15.0),
	Vector3(3.4, DECK_LOW + 0.1, 14.0),
	Vector3(3.4, DECK_MAIN + 0.1, 9.0),
	Vector3(2.0, DECK_MAIN + 0.1, 5.0),
	Vector3(0.0, DECK_MAIN + 0.1, 2.0),
	Vector3(0.0, DECK_MAIN + 0.1, -26.0),
	Vector3(-7.0, DECK_MAIN + 0.1, -42.0),
	Vector3(0.0, DECK_MAIN + 0.1, -56.0),
	Vector3(-6.0, DECK_MAIN + 0.1, -70.0),
	Vector3(0.0, DECK_MAIN + 0.1, -76.0),
	Vector3(0.0, DECK_MAIN + 0.1, -84.0),
	Vector3(0.0, DECK_MAIN + 2.0, -86.0),
	Vector3(0.0, DECK_UPPER + 0.1, -90.0),
	Vector3(0.0, DECK_UPPER + 0.1, -96.0),
	Vector3(0.0, DECK_UPPER + 0.1, -114.0),
	Vector3(0.0, DECK_UPPER + 0.1, -120.0),
	Vector3(0.0, 12.7, -126.0),
	Vector3(0.0, 12.7, -140.0),
	Vector3(0.0, 12.7, -145.0),
]


# Cinematic look targets for the guided tour (same count as `route`).
var route_look: Array = [
	Vector3(0.0, -6.0, 132.0),
	Vector3(0.0, -6.0, 132.0),
	Vector3(-2.0, -5.0, 132.0),
	Vector3(14.0, -13.0, 92.0),
	Vector3(16.0, -12.0, 86.0),
	Vector3(14.0, -9.0, 78.0),
	Vector3(0.0, -9.0, 60.0),
	Vector3(0.0, -9.0, 40.0),
	Vector3(0.0, -10.0, 30.0),
	Vector3(0.0, -10.5, 18.0),
	Vector3(3.0, -7.0, 10.0),
	Vector3(2.0, -5.0, 2.0),
	Vector3(0.0, -4.0, -20.0),
	Vector3(0.0, 0.0, -39.0),
	Vector3(0.0, 0.0, -44.0),
	Vector3(0.0, 2.0, -62.0),
	Vector3(0.0, 2.0, -78.0),
	Vector3(0.0, 4.0, -88.0),
	Vector3(0.0, 6.0, -96.0),
	Vector3(0.0, 6.0, -104.0),
	Vector3(0.0, 7.0, -112.0),
	Vector3(0.0, 8.0, -118.0),
	Vector3(0.0, 11.0, -124.0),
	Vector3(0.0, 13.0, -136.0),
	Vector3(0.0, 13.0, -146.0),
]


func zone(key: String) -> Dictionary:
	return zones[key]


func inset() -> float:
	# how far room walls are pulled inside the module envelope
	return (room_scale - 1.0) * 4.0


func floor_y(key: String) -> float:
	return float(zones[key]["y"])


func ceil_y(key: String) -> float:
	return float(zones[key]["y"]) + float(zones[key]["h"])


func center(key: String) -> Vector3:
	var z: Dictionary = zones[key]
	return Vector3((float(z["x0"]) + float(z["x1"])) * 0.5,
		float(z["y"]) + 1.7, (float(z["z0"]) + float(z["z1"])) * 0.5)


func route_length() -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += route[i].distance_to(route[i - 1])
	return total
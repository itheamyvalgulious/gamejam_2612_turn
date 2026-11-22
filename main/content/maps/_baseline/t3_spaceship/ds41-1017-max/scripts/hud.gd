extends CanvasLayer

## In-world HUD: zone readout, route progress, deck schematic overlay.

var main: Node
var cfg: ShipConfig
var painter: Control
var font: Font
var panel_on := true
var map_on := false
var tour_active := false
var tour_progress := 0.0

const COL_TEXT := Color(0.76, 0.90, 1.0)
const COL_DIM := Color(0.42, 0.56, 0.66)
const COL_ACCENT := Color(1.0, 0.62, 0.22)
const COL_GREEN := Color(0.35, 1.0, 0.55)
const COL_BG := Color(0.015, 0.03, 0.045, 0.78)

const DECKS := [
	{"y": -20.0, "label": "DECK 04", "use": "ENGINEERING"},
	{"y": -12.0, "label": "DECK 03", "use": "CARGO / PLANT"},
	{"y": -4.0, "label": "DECK 02", "use": "MAIN SPINE"},
	{"y": 4.0, "label": "DECK 01", "use": "HABITAT"},
	{"y": 12.0, "label": "DECK 00", "use": "COMMAND"},
]

var hull_profile := [
	Vector2(-152, 4.2), Vector2(-138, 8.8), Vector2(-112, 15.2),
	Vector2(-76, 24.4), Vector2(-30, 32.0), Vector2(0, 35.0),
	Vector2(40, 35.0), Vector2(100, 29.0), Vector2(148, 21.6),
]


func _ready() -> void:
	layer = 10
	font = ThemeDB.fallback_font
	painter = Control.new()
	painter.name = "HUDPainter"
	painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(painter)
	painter.draw.connect(_paint)
	set_process(true)


func _process(_dt: float) -> void:
	painter.queue_redraw()


func toggle_panel() -> void:
	panel_on = not panel_on


func toggle_map() -> void:
	map_on = not map_on


func current_zone() -> Dictionary:
	if main == null or main.cam == null:
		return {}
	var p: Vector3 = main.cam.global_position
	var best := {}
	var best_score := 1e9
	for key in cfg.zones:
		var z: Dictionary = cfg.zones[key]
		var y: float = z["y"]
		if p.x >= float(z["x0"]) - 0.6 and p.x <= float(z["x1"]) + 0.6 \
				and p.z >= float(z["z0"]) - 0.6 and p.z <= float(z["z1"]) + 0.6:
			var score: float = absf(p.y - y - 1.6)
			if p.y > y - 1.2 and p.y < y + float(z.get("h", 6.0)) + 1.2 and score < best_score:
				best_score = score
				best = z.duplicate()
				best["key"] = key
				best["name"] = cfg.zone_names.get(key, key.to_upper())
	return best


func current_deck_index() -> int:
	if main == null or main.cam == null:
		return 2
	var p: Vector3 = main.cam.global_position
	var best := 0
	var bd := 1e9
	for i in DECKS.size():
		var d := absf(p.y - float(DECKS[i]["y"]))
		if d < bd:
			bd = d
			best = i
	return best


func _paint() -> void:
	var vp := painter.get_viewport_rect().size
	var w := vp.x
	var h := vp.y
	if map_on:
		_draw_map(w, h)
		return
	if panel_on:
		_draw_hud(w, h)
	if tour_active:
		_draw_tour(w, h)


# ------------------------------------------------------------------- pieces --
func _text(pos: Vector2, s: String, size: int, col: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, box_w: float = -1.0) -> void:
	painter.draw_string(font, pos, s, align, box_w, size, col)


func _panel(rect: Rect2, col: Color = COL_BG, line: Color = Color(0.25, 0.55, 0.75, 0.5)) -> void:
	painter.draw_rect(rect, col)
	painter.draw_rect(rect, line, false, 1.0)


func _bracket(rect: Rect2, col: Color, size: float = 10.0) -> void:
	var tl := rect.position
	var br := rect.position + rect.size
	painter.draw_line(tl, tl + Vector2(size, 0), col, 2.0)
	painter.draw_line(tl, tl + Vector2(0, size), col, 2.0)
	painter.draw_line(Vector2(br.x, tl.y), Vector2(br.x - size, tl.y), col, 2.0)
	painter.draw_line(Vector2(br.x, tl.y), Vector2(br.x, tl.y + size), col, 2.0)
	painter.draw_line(Vector2(tl.x, br.y), Vector2(tl.x + size, br.y), col, 2.0)
	painter.draw_line(Vector2(tl.x, br.y), Vector2(tl.x, br.y - size), col, 2.0)
	painter.draw_line(br, Vector2(br.x - size, br.y), col, 2.0)
	painter.draw_line(br, Vector2(br.x, br.y - size), col, 2.0)


func _draw_hud(w: float, h: float) -> void:
	var zone := current_zone()
	var deck_i := current_deck_index()
	var deck: Dictionary = DECKS[deck_i]
	if tour_active and not map_on:
		return
	var zname: String = zone.get("name", "SERVICE SPACE")
	var zkey: String = zone.get("key", "")

	# top-left identity block
	_panel(Rect2(28, 24, 360, 104), COL_BG, Color(0.25, 0.55, 0.75, 0.35))
	_bracket(Rect2(28, 24, 360, 104), Color(0.4, 0.75, 1.0, 0.55), 12.0)
	_text(Vector2(44, 50), "SSV  ORION   ·   DSV-04", 17, COL_ACCENT)
	_text(Vector2(44, 72), "DEEP SURVEY VESSEL  /  INTERIOR NAV", 12, COL_DIM)
	_text(Vector2(44, 102), zname, 20, COL_TEXT)
	_text(Vector2(44, 120), "%s  ·  %s" % [deck["label"], deck["use"]], 12, COL_DIM)
	if main.tour == null or not main.tour.is_running():
		_text(Vector2(300, 50), "%4.0f m" % Vector2(main.cam.global_position.x, main.cam.global_position.z).length(), 12, COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 74)

	# top-right route progress
	var prog := 0.0
	if main.has_method("route_progress"):
		prog = clampf(main.route_progress(), 0.0, 1.0)
	if main.tour and main.tour.is_running():
		prog = clampf(main.tour.dist / maxf(main.tour.total, 1.0), 0.0, 1.0)
	_panel(Rect2(w - 330, 24, 302, 52), COL_BG, Color(0.25, 0.55, 0.75, 0.35))
	_text(Vector2(w - 316, 44), "MAIN ROUTE   ·   STERN → BRIDGE", 11, COL_DIM)
	var bar := Rect2(w - 316, 52, 272, 8)
	painter.draw_rect(bar, Color(0.15, 0.25, 0.32))
	painter.draw_rect(Rect2(bar.position, Vector2(bar.size.x * prog, bar.size.y)), COL_GREEN)
	for k in 5:
		var x := bar.position.x + bar.size.x * (float(k) / 4.0)
		painter.draw_line(Vector2(x, bar.position.y - 2), Vector2(x, bar.position.y + 10), COL_DIM, 1.0)
	_text(Vector2(w - 316, 70), "%s" % ("AUTOPILOT" if tour_active else "MANUAL"), 10,
		COL_GREEN if tour_active else COL_DIM)

	# crosshair
	if not map_on and not tour_active:
		var c := Vector2(w * 0.5, h * 0.5)
		painter.draw_circle(c, 1.6, Color(0.7, 0.95, 1.0, 0.9))
		painter.draw_arc(c, 9.0, 0.0, TAU, 24, Color(0.6, 0.85, 1.0, 0.28), 1.0)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			painter.draw_line(c + d * 13, c + d * 18, Color(0.6, 0.85, 1.0, 0.35), 1.0)

	# bottom-left controls
	_panel(Rect2(28, h - 132, 402, 104), COL_BG, Color(0.25, 0.55, 0.75, 0.25))
	_text(Vector2(44, h - 108), "W A S D  move      SHIFT  boost      Q / E  down / up", 11, COL_DIM)
	_text(Vector2(44, h - 88), "MOUSE  look      F  guided tour      TAB  deck plan", 11, COL_DIM)
	_text(Vector2(44, h - 68), "1 – 9  jump to zone      V  hull cutaway      H  HUD", 11, COL_DIM)
	_text(Vector2(44, h - 46), "ESC  release mouse", 11, COL_DIM)

	# bottom-right zone list / teleport hints
	_panel(Rect2(w - 300, h - 208, 272, 180), COL_BG, Color(0.25, 0.55, 0.75, 0.25))
	_text(Vector2(w - 286, h - 184), "FAST TRAVEL", 11, COL_ACCENT)
	var jumps := [
		["1", "ENGINEERING", "engine"], ["2", "CARGO HOLD", "cargo"],
		["3", "REACTOR HALL", "reactor"], ["4", "GALLERIA", "atrium"],
		["5", "BIO DOME", "hydro"], ["6", "BRIDGE", "bridge"],
	]
	for i in jumps.size():
		var j: Array = jumps[i]
		var yy := h - 160 + i * 22
		var hot: bool = zkey == j[2]
		_text(Vector2(w - 286, yy), "[%s]" % j[0], 12, COL_ACCENT if hot else COL_DIM)
		_text(Vector2(w - 256, yy), j[1], 12, COL_TEXT if hot else COL_DIM)
		if hot:
			painter.draw_line(Vector2(w - 286, yy + 5), Vector2(w - 296, yy + 5), COL_GREEN, 2.0)

	if not Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_text(Vector2(w * 0.5, h - 30), "CLICK TO CAPTURE MOUSE", 12, COL_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 300)


func _draw_tour(w: float, h: float) -> void:
	painter.draw_rect(Rect2(0, 0, w, 54), Color(0, 0, 0, 0.85))
	painter.draw_rect(Rect2(0, h - 54, w, 54), Color(0, 0, 0, 0.85))
	var zone := current_zone()
	_text(Vector2(44, 34), "AUTOPILOT  ·  MAIN ROUTE", 14, COL_GREEN)
	_text(Vector2(w - 44, 34), zone.get("name", ""), 14, COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 600)
	var bar := Rect2(44, h - 34, w - 88, 4)
	painter.draw_rect(bar, Color(0.2, 0.3, 0.35))
	painter.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(tour_progress, 0, 1), bar.size.y)), COL_GREEN)
	_text(Vector2(44, h - 42), "F  RELEASE", 10, COL_DIM)


# ---------------------------------------------------------------------- map --
func _map_point(z: float, x: float, rect: Rect2) -> Vector2:
	var tz := (z - (-160.0)) / 320.0
	var tx := (x - (-40.0)) / 80.0
	return Vector2(rect.position.x + tz * rect.size.x, rect.position.y + tx * rect.size.y)


func _draw_map(w: float, h: float) -> void:
	painter.draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.01, 0.02, 0.82))
	painter.draw_rect(Rect2(0, 0, w, 34), Color(0.01, 0.03, 0.05, 0.95))
	painter.draw_line(Vector2(0, 34), Vector2(w, 34), Color(0.25, 0.6, 0.8, 0.5), 1.0)
	_text(Vector2(28, 24), "SSV ORION   ·   DECK PLAN", 15, COL_ACCENT)
	_text(Vector2(w - 28, 24), "TAB  CLOSE", 12, COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	var rect := Rect2(80, 170, w - 160, h - 330)
	_panel(rect.grow(26), Color(0.01, 0.02, 0.035, 0.9), Color(0.3, 0.6, 0.8, 0.5))
	_text(Vector2(rect.position.x, rect.position.y - 48), "DORSAL SECTION  ·  HABITABLE VOLUMES", 13, COL_TEXT)
	_text(Vector2(rect.position.x, rect.position.y - 26), "BOW ←   → STERN        ACTIVE DECK HIGHLIGHTED", 11, COL_DIM)

	# hull outline
	var top: Array = []
	var bot: Array = []
	for p in hull_profile:
		var zz: float = p.x
		var halfw: float = p.y
		top.append(_map_point(zz, -halfw * 0.98, rect))
		bot.append(_map_point(zz, halfw * 0.98, rect))
	var outline: Array = top.duplicate()
	bot.reverse()
	outline.append_array(bot)
	painter.draw_colored_polygon(outline, Color(0.05, 0.12, 0.16, 0.85))
	var closed := outline.duplicate()
	closed.append(outline[0])
	painter.draw_polyline(closed, Color(0.35, 0.7, 0.95, 0.7), 1.5)

	# zones on the current deck
	var deck_i := current_deck_index()
	var deck_y: float = DECKS[deck_i]["y"]
	var zone := current_zone()
	for key in cfg.zones:
		var z: Dictionary = cfg.zones[key]
		var zy: float = z["y"]
		var p0 := _map_point(float(z["z0"]), float(z["x0"]), rect)
		var p1 := _map_point(float(z["z1"]), float(z["x1"]), rect)
		var rr := Rect2(p0, p1 - p0)
		var active: bool = key == zone.get("key", "")
		var on_deck := absf(zy - deck_y) <= 2.0
		if not on_deck and not active:
			painter.draw_rect(rr, Color(0.12, 0.28, 0.36, 0.16))
			painter.draw_rect(rr, Color(0.3, 0.5, 0.6, 0.28), false, 1.0)
			if ("atrium" in key) or ("hydro" in key) or ("bridge" == key):
				var nm2: String = cfg.zone_names.get(key, key.to_upper())
				_text(Vector2(rr.position.x + 4, rr.position.y + 13), nm2.substr(0, 12), 9,
					Color(0.45, 0.6, 0.68))
			continue
		var fill := Color(0.2, 0.55, 0.7, 0.34) if not active else Color(0.25, 0.85, 0.5, 0.36)
		var line := Color(0.35, 0.65, 0.8, 0.6) if not active else Color(0.4, 1.0, 0.6, 1.0)
		painter.draw_rect(rr, fill)
		painter.draw_rect(rr, line, false, 1.4 if active else 1.0)
		if rr.size.x > 58:
			var nm: String = cfg.zone_names.get(key, key.to_upper())
			var maxc := maxi(4, int(rr.size.x / 6.4))
			if nm.length() > maxc:
				nm = nm.substr(0, maxc)
			_text(Vector2(rr.position.x + 4, rr.position.y + 14), nm, 9,
				Color(0.85, 1.0, 0.9) if active else Color(0.55, 0.72, 0.8))

	# route: whole line dim, current deck bright
	var all_pts: Array = []
	var route_pts: Array = []
	for p in cfg.route:
		all_pts.append(_map_point(p.z, p.x, rect))
		if absf(p.y - deck_y) < 6.0:
			route_pts.append(_map_point(p.z, p.x, rect))
	if all_pts.size() > 1:
		painter.draw_polyline(all_pts, Color(0.25, 0.7, 0.4, 0.35), 1.2)
	if route_pts.size() > 1:
		painter.draw_polyline(route_pts, COL_GREEN, 2.2)

	# player
	if main and main.cam:
		var pp: Vector3 = main.cam.global_position
		var map_p := _map_point(pp.z, pp.x, rect)
		painter.draw_circle(map_p, 5.0, Color(1.0, 0.65, 0.2))
		painter.draw_arc(map_p, 11.0, 0.0, TAU, 20, Color(1.0, 0.65, 0.2, 0.5), 1.0)
		var fwd: Vector3 = -main.cam.global_transform.basis.z
		var tip := _map_point(pp.z + fwd.z * 10.0, pp.x + fwd.x * 10.0, rect)
		painter.draw_line(map_p, tip, Color(1.0, 0.8, 0.4), 2.0)

	# deck tabs
	for i in DECKS.size():
		var label: String = DECKS[i]["label"]
		var x := rect.position.x + 20 + i * 112
		var y := rect.end.y + 34
		var active: bool = i == deck_i
		_panel(Rect2(x, y, 92, 28), Color(0.06, 0.12, 0.16, 0.9) if not active else Color(0.15, 0.4, 0.25, 0.9),
			Color(0.3, 0.7, 0.9, 0.5) if not active else COL_GREEN)
		_text(Vector2(x + 12, y + 19), label, 11, COL_DIM if not active else COL_GREEN)

	_text(Vector2(rect.position.x, rect.end.y + 86), "GREEN LINE = MAIN ROUTE      ·      ORANGE MARKER = PLAYER", 11, COL_DIM)
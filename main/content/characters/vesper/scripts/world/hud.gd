extends Control
## Minimal diegetic combat HUD drawn entirely in code.

const ORANGE := Color(0.22, 0.55, 1.0)
const AMBER := Color(0.55, 0.78, 1.0)
const IVORY := Color(0.84, 0.85, 0.86)
const DIM := Color(0.42, 0.47, 0.53)
const FAINT := Color(0.23, 0.27, 0.32)
const CYAN := Color(0.33, 0.64, 1.0)

var rig
var auto_mode := true
var phase_text := "CALIBRATION"
var overlay: ColorRect

var _intro := 0.0
var _flash := 0.0
var _hud_redraw_acc := 0.0
var _pulse := 0.0
var _font: Font
var _vignette: ColorRect
var _hud_visible := true
var text_outline := true
var fade := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	var sh := ShaderMaterial.new()
	sh.shader = preload("res://shaders/screen_overlay.gdshader")
	sh.set_shader_parameter("vignette", 0.52)
	sh.set_shader_parameter("scanline", 0.012)
	sh.set_shader_parameter("grain", 0.008)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.material = sh
	_vignette.show_behind_parent = true
	add_child(_vignette)
	set_process(true)


func set_rig(r) -> void:
	rig = r


func show_intro(seconds: float) -> void:
	_intro = seconds


func flash(strength: float) -> void:
	_flash = maxf(_flash, strength)


func set_hud_visible(v: bool) -> void:
	_hud_visible = v
	queue_redraw()


func _process(delta: float) -> void:
	step(delta)
	# HUD is mostly static text; redrawing its outlined glyphs every frame cost
	# ~6 ms/frame on a 1650.  20 Hz is visually indistinguishable here.
	_hud_redraw_acc += delta
	if _hud_redraw_acc >= 0.08:
		_hud_redraw_acc = 0.0
		queue_redraw()


func step(delta: float) -> void:
	_pulse += delta
	_intro = maxf(0.0, _intro - delta)
	_flash = maxf(0.0, _flash - delta * 3.5)


func set_fade(v: float) -> void:
	fade = clampf(v, 0.0, 1.0)


func _draw() -> void:
	if not _hud_visible:
		return
	var w := size.x
	var h := size.y
	var s := h / 900.0
	var mx := 66.0 * s
	var my := 64.0 * s

	# corner brackets
	var bc := Color(0.55, 0.58, 0.62, 0.45)
	_line(Vector2(mx - 22 * s, my - 20 * s), Vector2(mx - 22 * s + 26 * s, my - 20 * s), bc, 1.0 * s)
	_line(Vector2(mx - 22 * s, my - 20 * s), Vector2(mx - 22 * s, my - 20 * s + 26 * s), bc, 1.0 * s)
	_line(Vector2(w - mx + 22 * s, h - my + 18 * s), Vector2(w - mx + 22 * s - 26 * s, h - my + 18 * s), bc, 1.0 * s)
	_line(Vector2(w - mx + 22 * s, h - my + 18 * s), Vector2(w - mx + 22 * s, h - my + 18 * s - 26 * s), bc, 1.0 * s)

	# title lockup
	_line(Vector2(mx, my - 20 * s), Vector2(mx + 44 * s, my - 20 * s), ORANGE, 2.0 * s)
	_tracked("VX-02  //  VESPER", Vector2(mx, my + 6 * s), 27 * s, IVORY, 2.2 * s)
	_tracked("BIO-MECHANICAL ASSAULT FRAME", Vector2(mx, my + 26 * s), 9.5 * s, DIM, 2.0 * s)
	_tracked("UNIT 04   /   LIVE FIRE EXERCISE", Vector2(mx, my + 44 * s), 8.0 * s, FAINT * 1.4, 1.4 * s)
	# hex emblem
	var hx := Vector2(mx + 306 * s, my + 2 * s)
	var hp := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + TAU * i / 6.0
		hp.append(hx + Vector2(cos(a), sin(a)) * 15.0 * s)
	draw_polyline(_closed(hp), Color(0.7, 0.72, 0.75, 0.55), 1.0 * s, true)
	draw_circle(hx, 2.2 * s, ORANGE)

	# top right telemetry
	var trx := w - mx
	_right("COMBAT SIMULATION", trx, my - 3 * s, 8.0 * s, DIM)
	_right("SECTOR 09  //  ALT 0412", trx, my + 12 * s, 8.0 * s, FAINT * 1.6)
	var dot_col := ORANGE if fmod(_pulse, 1.6) < 1.1 else Color(0.3, 0.18, 0.1)
	draw_circle(Vector2(trx - 154 * s, my + 28 * s), 2.6 * s, dot_col)
	_right("LIVE FEED", trx, my + 32 * s, 8.5 * s, IVORY)

	# phase center top
	var phase := "PHASE // " + phase_text
	var pw := _text_width(phase, 9.0 * s, 2.0 * s)
	_tracked(phase, Vector2((w - pw) * 0.5, my + 2 * s), 9.5 * s, Color(0.72, 0.76, 0.80, 0.85), 2.0 * s)
	_line(Vector2((w - pw) * 0.5, my + 9 * s), Vector2((w - pw) * 0.5 + pw, my + 9 * s), Color(0.5, 0.52, 0.56, 0.25), 1.0 * s)

	# bottom left: motion telemetry
	var by := h - 215 * s
	_line(Vector2(mx, by), Vector2(mx + 366 * s, by), Color(0.5, 0.52, 0.56, 0.28), 1.0 * s)
	_tracked("MOTION TELEMETRY", Vector2(mx, by + 14 * s), 8.0 * s, DIM, 1.8 * s)
	if rig != null:
		var state: String = rig.locomotion_state
		var spd: float = rig.display_speed
		_tracked(state, Vector2(mx, by + 42 * s), 22 * s, IVORY, 2.0 * s)
		var speed_text := "%04.1f" % spd
		if text_outline:
			draw_string_outline(_font, Vector2(mx, by + 84 * s), speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(33 * s), maxi(1, int(2.0 * s)), Color(0, 0, 0, 0.55))
		draw_string(_font, Vector2(mx, by + 84 * s), speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 33 * s, ORANGE)
		var sw := _text_width(speed_text, 33 * s, 0.0)
		_tracked("M/S", Vector2(mx + sw + 8 * s, by + 84 * s), 9.0 * s, DIM, 1.2 * s)
		# segmented velocity ladder
		var segs := 24
		var gap := 3.0 * s
		var segw := (366.0 * s - gap * (segs - 1)) / segs
		for i in segs:
			var x := mx + i * (segw + gap)
			var threshold := 9.0 * float(i + 1) / segs
			var on := spd >= threshold * 0.88 and spd > 0.25
			var col := ORANGE if i > 15 else CYAN
			if not on:
				col = Color(0.17, 0.19, 0.22)
			elif i > 15:
				col = AMBER
			draw_rect(Rect2(x, by + 98 * s, segw, 4.0 * s), col)
		# state line
		var status := ""
		if rig.is_attacking:
			status = "BLADE // " + rig.attack_name
			_tracked(status, Vector2(mx, by + 124 * s), 10.5 * s, ORANGE, 1.8 * s)
		else:
			status = "AUTO DEMO // MOVE TO TAKE CONTROL" if auto_mode else "MANUAL CONTROL // READY"
			_tracked(status, Vector2(mx, by + 124 * s), 9.0 * s, DIM, 1.4 * s)

	# bottom right controls
	var cx := w - mx
	var cy := h - 246 * s
	var lines := [
		["MOUSE", "ORBIT / WHEEL ZOOM"],
		["WASD", "MOVE / STRAFE"],
		["Q / E", "TURN"],
		["CTRL", "SPRINT"],
		["SHIFT", "DASH (INPUT DIR)"],
		["SPACE", "JUMP"],
		["J", "FRONT COMBO x4"],
		["U / Y", "SIDE THRUST R / L"],
		["I", "BACK THRUST"],
		["K", "GUILLOTINE"],
		["L", "HELIX STORM"],
		["TAB", "AUTO DEMO"],
		["H", "HUD"],
	]
	for i in lines.size():
		var yy := cy + i * 14.0 * s
		var key: String = lines[i][0]
		var label: String = lines[i][1]
		_tracked(key, Vector2(cx - 218 * s, yy), 9.0 * s, Color(0.62, 0.82, 1.0), 1.0 * s)
		_tracked(label, Vector2(cx - 138 * s, yy), 9.0 * s, Color(0.58, 0.62, 0.67), 1.0 * s)

	# subtle vignette inside the HUD corners (keeps text readable over bright floor)

	# impact flash
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.55, 1.0, _flash * 0.16))
	if fade > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, fade))


const TAU := PI * 2.0


func _line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	draw_line(a, b, col, width)


func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q


func _text_width(text: String, fsize: float, tracking: float) -> float:
	if text == "":
		return 0.0
	var w := 0.0
	for ch in text:
		w += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fsize)).x + tracking
	return w - tracking


func _tracked(text: String, pos: Vector2, fsize: float, col: Color, tracking: float) -> void:
	var x := pos.x
	var outline := maxi(1, int(1.6 * (size.y / 900.0)))
	for ch in text:
		if text_outline:
			draw_string_outline(_font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fsize), outline, Color(0, 0, 0, 0.55))
		draw_string(_font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fsize), col)
		x += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fsize)).x + tracking


func _right(text: String, right_x: float, y: float, fsize: float, col: Color) -> void:
	var w := _text_width(text, fsize, 0.0)
	var outline := maxi(1, int(1.5 * (size.y / 900.0)))
	if text_outline:
		draw_string_outline(_font, Vector2(right_x - w, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fsize), outline, Color(0, 0, 0, 0.5))
	draw_string(_font, Vector2(right_x - w, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fsize), col)
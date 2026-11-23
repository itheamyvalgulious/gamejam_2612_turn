extends CanvasLayer

const Style = preload("res://ui/turn_style.gd")
const Catalog = preload("res://core/level_catalog.gd")
const RETICLE_COLOR := Color(0.91, 0.97, 0.98, 0.68)
const TRACK := Color("#192630")

var _canvas: Control
var _font: Font
var _state := ""
var _hint := ""
var _room_key := ""
var _level_name := ""
var _level_idx := 0
var _level_left := 0.0
var _alive := 0
var _total := 0
var _first_person := false
var _mask := false
var _toast := ""
var _toast_color := Style.TEXT
var _toast_left := 0.0
var _tutorial := ""
var _tutorial_left := 0.0
var _guard_taught := false
var _shot_taught := false
var _boss := ""
var _boss_hp := 0.0
var _boss_max := 0.0
var _phase := ""
var _phase_fill := 0.0
var _phase_active := false
var _death: Control
var _threats := PackedVector2Array()

func _ready() -> void:
	layer = 40
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_font = Style.theme().default_font

func _process(delta: float) -> void:
	_level_left = maxf(0.0, _level_left - delta)
	_toast_left = maxf(0.0, _toast_left - delta)
	_tutorial_left = maxf(0.0, _tutorial_left - delta)
	_canvas.queue_redraw()

func set_level(index: int) -> void:
	_level_idx = index
	_level_name = Catalog.get_entry(index)[0]
	_level_left = 2.0
	_toast_left = 0.0
	_tutorial_left = 0.0
	_threats.clear()

func set_enemy_count(alive: int, total: int) -> void:
	_alive = alive
	_total = total

func set_state(value: String) -> void:
	_state = value

func set_hint(value: String) -> void:
	_hint = value

func set_room_key(value: String) -> void:
	_room_key = value

func set_first_person(enabled: bool) -> void:
	_first_person = enabled

func set_fp_mask(enabled: bool) -> void:
	_mask = enabled

func set_hud_visible(enabled: bool) -> void:
	visible = enabled

func set_boss_health(title: String, amount: float, maximum: float) -> void:
	_boss = title
	_boss_hp = amount
	_boss_max = maximum

func set_boss_phase(title: String, value: String, progress: float, active: bool) -> void:
	_phase = "虚化中" if active and title != "转入虚化" else title
	if title == "虚化持续":
		_phase += "   " + value
	_phase_fill = progress
	_phase_active = active

func show_banner(title: String, subtitle: String, seconds: float) -> void:
	_toast = title if not title.is_empty() else subtitle
	_toast_color = Style.TEXT
	_toast_left = seconds if not _toast.is_empty() else 0.0

func flash_block() -> void:
	_feedback("被格挡", Style.BLOCKED)
	if not _guard_taught:
		_guard_taught = true
		_tutorial = "移开视线，再出刀"
		_tutorial_left = 2.3

func flash_parry() -> void:
	_feedback("架住", Style.FOCUS)

func flash_reflect() -> void:
	_feedback("弹反", Style.FOCUS)

func flash_immune() -> void:
	_feedback("虚化免伤", Style.PHASE)

func _feedback(title: String, color: Color) -> void:
	_toast = title
	_toast_color = color
	_toast_left = 0.72

func flash_death(cause: String) -> void:
	if is_instance_valid(_death):
		return
	get_parent().call("_release_mouse")
	_death = Control.new()
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_STOP
	_death.theme = Style.theme()
	add_child(_death)
	var tint := ColorRect.new()
	tint.color = Color(0.032, 0.020, 0.035, 0.72)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.add_child(tint)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_death.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 325
	column.add_theme_constant_override("separation", 13)
	center.add_child(column)
	column.add_child(Style.label("行动中断", 50))
	if cause not in ["你死了", "你被击中", ""]:
		column.add_child(Style.label(cause, 19, Style.MUTED))
	var retry := Style.button("重试", _restart)
	column.add_child(retry)
	column.add_child(Style.button("返回关卡选择", TurnSession.return_to_menu))
	retry.grab_focus()

func _restart() -> void:
	get_parent().call_deferred("restart_level")

func clear_death() -> void:
	if is_instance_valid(_death):
		_death.hide()
		_death.queue_free()
		_death = null

func update_threats(enemies: Array, shots: Array, camera: Camera3D, player: Node) -> void:
	_threats.clear()
	if not player.alive or camera == null:
		return
	var capsule: Dictionary = player.capsule()
	var a: Vector3 = capsule["a"]
	var b: Vector3 = capsule["b"]
	for shot: Dictionary in shots:
		if not shot["alive"] or shot["spent"] or shot["owner"] != "enemy":
			continue
		var source: Vector3 = shot["pos"]
		var travel: Vector3 = shot["vel"] * 0.42
		if travel.dot((a + b) * 0.5 - source) <= 0.0 or travel.length_squared() < 0.0001:
			continue
		var nearest := Geometry3D.get_closest_points_between_segments(source, source + travel, a, b)
		if nearest[0].distance_squared_to(nearest[1]) > pow(float(capsule["r"]) + float(shot["radius"]), 2):
			continue
		_add_edge_threat(camera, source)
		if not _shot_taught and shot["kind"] == "arrow":
			_shot_taught = true
			var key := TurnSession.binding_label("parry")
			if key != "—":
				_tutorial = "%s  ·  弹反" % key
				_tutorial_left = 2.0
	for enemy: Node in enemies:
		if not is_instance_valid(enemy) or not enemy.alive or not enemy.has_method("hud_alert"):
			continue
		var at: Vector3 = enemy.center()
		if not _outside(camera, at) or not enemy.hud_alert(player):
			continue
		_add_edge_threat(camera, at)

func _outside(camera: Camera3D, at: Vector3) -> bool:
	return camera.is_position_behind(at) or not get_viewport().get_visible_rect().has_point(camera.unproject_position(at))

func _add_edge_threat(camera: Camera3D, at: Vector3) -> void:
	if not _outside(camera, at):
		return
	var direction: Vector2
	if camera.is_position_behind(at):
		var local := camera.to_local(at)
		direction = Vector2(signf(local.x), 0.0) if absf(local.x) > 0.1 else Vector2.DOWN
	else:
		direction = get_viewport().get_visible_rect().get_center().direction_to(camera.unproject_position(at))
	for other in _threats:
		if direction.dot(other) > 0.968:
			return
	_threats.append(direction)

func _draw_hud() -> void:
	if is_instance_valid(_death):
		return
	var size := _canvas.size
	if size.x < 10.0:
		return
	if _level_left > 0.0:
		var fade := clampf(_level_left / 0.52, 0.0, 1.0)
		var origin := Vector2(38, 53)
		var label_width := _font.get_string_size(_level_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
		_canvas.draw_rect(Rect2(origin + Vector2(-20, -26), Vector2(label_width + 36, 36)), Color(Style.INK, 0.78 * fade))
		_canvas.draw_rect(Rect2(origin + Vector2(-17, -18), Vector2(2, 20)), Color(Style.FOCUS, fade))
		_text(_level_name, origin, 25, Color(Style.TEXT, fade))
	elif _total > 0 and _boss_max <= 0.0 and _alive > 0:
		_canvas.draw_rect(Rect2(26, 25, 78, 29), Color(Style.INK, 0.78))
		_text("剩余 %d" % _alive, Vector2(36, 45), 15, Style.MUTED)
	if _boss_max > 0.0 and _boss != "":
		_draw_boss(size)
	if _first_person:
		_canvas.draw_circle(size * 0.5, 1.6, RETICLE_COLOR)
		_canvas.draw_arc(size * 0.5, 5.0, -0.4, 0.4, 6, RETICLE_COLOR, 1.0, true)
		_canvas.draw_arc(size * 0.5, 5.0, PI - 0.4, PI + 0.4, 6, RETICLE_COLOR, 1.0, true)
	if _mask:
		var key := TurnSession.binding_label("fp_mask")
		var caption := "视野遮罩" if key == "—" else "视野遮罩  ·  " + key
		var width := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_text(caption, Vector2(size.x - 32 - width, 45), 14, Style.MUTED)
	for direction in _threats:
		_draw_edge(size, direction)
	if _toast_left > 0.0:
		var y := size.y * 0.5 + 39.0
		_chip(_toast, Vector2(size.x * 0.5, y), 18, Color(_toast_color, minf(_toast_left * 5.0, 1.0)))
	var prompt := _hint
	if prompt.is_empty() and _tutorial_left > 0.0:
		prompt = _tutorial
	if prompt.is_empty() and _total == 0 and _room_key not in ["", "—"]:
		var next_action := "返回关卡选择" if _level_idx == Catalog.level_count() - 1 else "下一关"
		prompt = "%s  ·  %s" % [_room_key, next_action]
	if not prompt.is_empty():
		_chip(prompt, Vector2(size.x * 0.5, size.y - 44.0), 16, Style.TEXT)
	if not _state.is_empty():
		_text(_state, Vector2(32, size.y - 24), 13, Style.MUTED)

func _draw_boss(size: Vector2) -> void:
	var width := minf(size.x * 0.51, 620.0)
	var center := size.x * 0.5
	_chip(_boss, Vector2(center, 39), 22, Style.TEXT)
	var edge := center - width * 0.5
	_meter(Rect2(edge, 62, width, 7), _boss_hp / _boss_max, Style.DANGER)
	if not _phase.is_empty():
		var tint := Style.PHASE if _phase_active else Style.FOCUS
		_meter(Rect2(edge, 76, width, 3), _phase_fill, tint)
		_chip(_phase, Vector2(center, 99), 13, tint)

func _meter(track: Rect2, fraction: float, color: Color) -> void:
	_canvas.draw_rect(track.grow(1.0), Color(Style.INK, 0.85))
	_canvas.draw_rect(track, TRACK)
	var fill := Rect2(track.position, Vector2(track.size.x * clampf(fraction, 0.0, 1.0), track.size.y))
	_canvas.draw_rect(fill, color)

func _draw_edge(size: Vector2, direction: Vector2) -> void:
	var bounds := size * 0.5 - Vector2(32, 112)
	var distance := minf(bounds.x / maxf(absf(direction.x), 0.001), bounds.y / maxf(absf(direction.y), 0.001))
	var pos := size * 0.5 + direction * distance
	var wing := direction.orthogonal() * 7.0
	var tail := pos - direction * 9.0
	var path := PackedVector2Array([tail - wing, pos, tail + wing])
	_canvas.draw_polyline(path, Color(Style.INK, 0.9), 5.0, true)
	_canvas.draw_polyline(path, Style.DANGER, 2.0, true)

func _chip(value: String, center: Vector2, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(center.x - width * 0.5, center.y)
	_canvas.draw_rect(Rect2(origin + Vector2(-9, -font_size), Vector2(width + 18, font_size + 9)), Color(Style.INK, 0.79 * color.a))
	_text(value, origin, font_size, color)

func _text(value: String, origin: Vector2, font_size: int, color: Color) -> void:
	_canvas.draw_string(_font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

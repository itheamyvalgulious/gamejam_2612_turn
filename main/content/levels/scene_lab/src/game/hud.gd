extends CanvasLayer
## GameHud — 战斗 HUD：关卡横幅 / 敌人计数 / 准星 / 屏幕外指示器 / 死亡卡 / 操作提示。
##
## 接口冻结（签名不可改，由 level.gd / main.gd 调用）：
##   set_level(idx, name_cn, hint)  set_enemy_count(alive, total)  set_state(text)
##   show_banner(title, sub, seconds)  flash_block()  flash_death(text)  clear_death()
##   set_markers([{screen:Vector2, off:bool, kind:String, dist:float, seen:bool}])
##   set_first_person(v)  set_hud_visible(v)  set_hint(text)  set_fp_mask(v)
##
## 风格：赛博朋克暗底 · 青 + 橙霓虹描边 · 全中文。

const C_BG := Color(0.02, 0.03, 0.045, 0.62)
const C_CYAN := Color(0.34, 0.94, 1.0)
const C_ORANGE := Color(1.0, 0.58, 0.22)
const C_RED := Color(1.0, 0.34, 0.30)
const C_TEXT := Color(0.86, 0.91, 0.97)
const C_DIM := Color(0.48, 0.55, 0.66)
const C_GREEN := Color(0.4, 1.0, 0.7)

const CONTROLS := [
	["鼠标左键", "攻击"],
	["WASD + 左键", "方向斩"],
	["鼠标右键", "弹反 / 举刀"],
	["空格", "跳跃"],
	["Shift", "冲刺"],
	["V", "切换视角"],
	["Tab", "第一人称视野"],
	["~", "手感参数"],
	["Esc", "暂停"],
]

var _font: Font
var _canvas: Control
var _level_name := ""
var _level_idx := 0
var _hint := ""
var _alive := 0
var _total := 0
var _state := ""
var _banner_title := ""
var _banner_sub := ""
var _banner_t := 0.0
var _banner_max := 0.01
var _block_t := 0.0
var _parry_t := 0.0
var _death := ""
var _death_anim := 0.0
var _first_person := false
var _fp_mask := false
var _visible_hud := true
var _markers: Array = []


func _ready() -> void:
	layer = 40
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)


func _process(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t = maxf(0.0, _banner_t - delta)
	if _block_t > 0.0:
		_block_t = maxf(0.0, _block_t - delta)
	if _parry_t > 0.0:
		_parry_t = maxf(0.0, _parry_t - delta)
	if _death != "":
		_death_anim = minf(1.0, _death_anim + delta * 3.5)
	_canvas.queue_redraw()


# ------------------------------------------------------------------ API
func set_level(idx: int, name_cn: String, hint: String) -> void:
	_level_idx = idx
	_level_name = name_cn
	_hint = hint
	_canvas.queue_redraw()


func set_enemy_count(alive: int, total: int) -> void:
	_alive = alive
	_total = total
	_canvas.queue_redraw()


func set_state(text: String) -> void:
	_state = text
	_canvas.queue_redraw()


func show_banner(title: String, sub: String, seconds: float) -> void:
	_banner_title = title
	_banner_sub = sub
	_banner_t = seconds
	_banner_max = maxf(0.01, seconds)
	_canvas.queue_redraw()


func flash_block() -> void:
	_block_t = 0.75
	_canvas.queue_redraw()


## 自己架住一刀（免伤 + 被击退）
func flash_parry() -> void:
	_parry_t = 0.7
	_canvas.queue_redraw()


func flash_death(text: String) -> void:
	_death = text
	_death_anim = 0.0
	_canvas.queue_redraw()


func clear_death() -> void:
	_death = ""
	_death_anim = 0.0
	_canvas.queue_redraw()


func set_markers(list: Array) -> void:
	_markers = list
	_canvas.queue_redraw()


func set_first_person(v: bool) -> void:
	_first_person = v
	_canvas.queue_redraw()


func set_hud_visible(v: bool) -> void:
	_visible_hud = v
	_canvas.queue_redraw()


## 第三人称「第一人称视野黑幕」是否开着（Tab）
func set_fp_mask(v: bool) -> void:
	if _fp_mask == v:
		return
	_fp_mask = v
	_canvas.queue_redraw()


func set_hint(text: String) -> void:
	_hint = text
	_canvas.queue_redraw()


## 测试用：HUD 内部状态是否健康
func debug_ok() -> bool:
	return _font != null and _canvas != null and is_inside_tree() and _canvas.size.x > 10.0


func marker_count() -> int:
	return _markers.size()


# ------------------------------------------------------------------ drawing
func _draw_hud() -> void:
	var vp := _canvas.size
	if not _visible_hud or vp.x < 10.0:
		return
	_draw_stats(vp)
	_draw_markers(vp)
	if _death == "":
		if _first_person:
			_draw_crosshair(vp)
		_draw_parry(vp)
		_draw_block(vp)
		_draw_banner(vp)
		_draw_controls(vp)
		_draw_hint(vp)
	_draw_fp_mask(vp)
	_draw_death(vp)


func _glow(pos: Vector2, text: String, align: int, width: float, size: int, col: Color, r := 2.0) -> void:
	var g := Color(col.r, col.g, col.b, col.a * 0.35)
	for o in [Vector2(-r, 0), Vector2(r, 0), Vector2(0, -r), Vector2(0, r)]:
		_canvas.draw_string(_font, pos + o, text, align, width, size, g)
	_canvas.draw_string(_font, pos, text, align, width, size, col)


func _panel(rect: Rect2, accent: Color) -> void:
	_canvas.draw_rect(rect, C_BG)
	_canvas.draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.55), false, 1.0)
	_canvas.draw_rect(Rect2(rect.position.x, rect.position.y, 3.0, rect.size.y), accent)


func _draw_stats(vp: Vector2) -> void:
	var p := Vector2(22, 20)
	var w := 330.0
	var h := 112.0
	_panel(Rect2(p, Vector2(w, h)), C_ORANGE)
	_canvas.draw_string(_font, Vector2(p.x + 16, p.y + 24), "关卡 %d" % (_level_idx + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
	_glow(Vector2(p.x + 16, p.y + 54), _level_name, HORIZONTAL_ALIGNMENT_LEFT, w - 30.0, 22, C_ORANGE, 1.5)
	# 敌人计数
	var alive_col := C_RED if _alive > 0 else C_GREEN
	_canvas.draw_string(_font, Vector2(p.x + 16, p.y + 84), "敌人",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_DIM)
	_canvas.draw_string(_font, Vector2(p.x + 60, p.y + 84), "%d / %d" % [_alive, _total],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, alive_col)
	# 击杀进度条
	var bar := Rect2(p.x + w - 128.0, p.y + 74.0, 112.0, 6.0)
	_canvas.draw_rect(bar, Color(0.1, 0.13, 0.18, 0.9))
	var killed := maxi(0, _total - _alive)
	var fr := float(killed) / float(maxi(1, _total))
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fr, 6.0)), C_GREEN)
	_canvas.draw_rect(bar, Color(0.3, 0.6, 0.75, 0.4), false, 1.0)
	if _state != "":
		_canvas.draw_string(_font, Vector2(p.x + 16, p.y + 103), _state,
			HORIZONTAL_ALIGNMENT_LEFT, w - 30.0, 13, C_CYAN)


## 黑幕模式提示：右上角一块小牌子（黑幕是纯视觉的，不能让人忘了自己在哪个模式里）
func _draw_fp_mask(vp: Vector2) -> void:
	if not _fp_mask:
		return
	var w := 246.0
	var box := Rect2(vp.x - w - 22.0, 20.0, w, 30.0)
	_canvas.draw_rect(box, Color(0.01, 0.02, 0.03, 0.72))
	_canvas.draw_rect(box, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.5), false, 1.0)
	_canvas.draw_rect(Rect2(box.position.x, box.position.y, 3.0, box.size.y), C_CYAN)
	_canvas.draw_string(_font, Vector2(box.position.x, box.position.y + 20.0), "第一人称视野 · Tab 关闭",
		HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.95))


func _draw_crosshair(vp: Vector2) -> void:
	var c := vp * 0.5
	var col := Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.85)
	_canvas.draw_circle(c, 1.6, col)
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_canvas.draw_line(c + d * 7.0, c + d * 16.0, col, 1.6)
	_canvas.draw_arc(c, 22.0, 0, TAU, 32, Color(col.r, col.g, col.b, 0.28), 1.0)


func _draw_parry(vp: Vector2) -> void:
	if _parry_t <= 0.0:
		return
	var a := clampf(_parry_t / 0.7, 0.0, 1.0)
	# 青色边缘：这是「你架住了」的反馈，和红色的「你被挡了」相反
	var edge := 22.0
	_canvas.draw_rect(Rect2(0, 0, vp.x, edge), Color(0.30, 0.85, 1.0, 0.22 * a))
	_canvas.draw_rect(Rect2(0, vp.y - edge, vp.x, edge), Color(0.30, 0.85, 1.0, 0.22 * a))
	var pos := Vector2(vp.x * 0.5, vp.y * 0.5 + 92.0)
	_canvas.draw_rect(Rect2(pos.x - 250.0, pos.y - 44.0, 500.0, 80.0), Color(0.0, 0.03, 0.05, 0.45 * a))
	_glow(pos, "格挡", HORIZONTAL_ALIGNMENT_CENTER, 0.0, 34, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, a), 3.0)
	_canvas.draw_string(_font, Vector2(pos.x, pos.y + 27), "刀架住了它的刀 · 免伤，但会被推开",
		HORIZONTAL_ALIGNMENT_CENTER, 0.0, 14, Color(0.75, 0.95, 1.0, a * 0.95))


func _draw_block(vp: Vector2) -> void:
	if _block_t <= 0.0:
		return
	var a := clampf(_block_t / 0.75, 0.0, 1.0)
	# 红色边缘警示
	var edge := 26.0
	_canvas.draw_rect(Rect2(0, 0, vp.x, edge), Color(1.0, 0.15, 0.12, 0.28 * a))
	_canvas.draw_rect(Rect2(0, vp.y - edge, vp.x, edge), Color(1.0, 0.15, 0.12, 0.28 * a))
	_canvas.draw_rect(Rect2(0, 0, edge, vp.y), Color(1.0, 0.15, 0.12, 0.28 * a))
	_canvas.draw_rect(Rect2(vp.x - edge, 0, edge, vp.y), Color(1.0, 0.15, 0.12, 0.28 * a))
	var pos := Vector2(vp.x * 0.5, vp.y * 0.5 + 92.0)
	_canvas.draw_rect(Rect2(pos.x - 310.0, pos.y - 46.0, 620.0, 86.0), Color(0.05, 0.0, 0.0, 0.5 * a))
	_glow(Vector2(pos.x, pos.y), "被格挡", HORIZONTAL_ALIGNMENT_CENTER, 0.0, 36, Color(C_RED.r, C_RED.g, C_RED.b, a), 3.0)
	_canvas.draw_string(_font, Vector2(pos.x, pos.y + 28), "视线内的目标无法被击中 · 请绕到它看不见的方向",
		HORIZONTAL_ALIGNMENT_CENTER, 0.0, 15, Color(1.0, 0.8, 0.75, a * 0.95))


func _draw_banner(vp: Vector2) -> void:
	if _banner_t <= 0.0:
		return
	var t_in := 0.4
	var t_out := 0.6
	var age := _banner_max - _banner_t
	var a := clampf(age / t_in, 0.0, 1.0) * clampf(_banner_t / t_out, 0.0, 1.0)
	if a <= 0.001:
		return
	var cy := vp.y * 0.34
	var y := cy - (1.0 - a) * 16.0
	_canvas.draw_rect(Rect2(vp.x * 0.5 - 340.0, y - 66.0, 680.0, 120.0), Color(0.008, 0.015, 0.025, 0.6 * a))
	_canvas.draw_line(Vector2(vp.x * 0.5 - 340.0, y - 46), Vector2(vp.x * 0.5 + 340.0, y - 46),
		Color(C_ORANGE.r, C_ORANGE.g, C_ORANGE.b, 0.6 * a), 1.5)
	_canvas.draw_line(Vector2(vp.x * 0.5 - 260.0, y + 42), Vector2(vp.x * 0.5 + 260.0, y + 42),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.6 * a), 1.5)
	_glow(Vector2(vp.x * 0.5, y), _banner_title, HORIZONTAL_ALIGNMENT_CENTER, 0.0, 54,
		Color(C_ORANGE.r, C_ORANGE.g, C_ORANGE.b, a), 3.0)
	_canvas.draw_string(_font, Vector2(vp.x * 0.5, y + 30), _banner_sub,
		HORIZONTAL_ALIGNMENT_CENTER, 0.0, 20, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, a))


func _draw_controls(vp: Vector2) -> void:
	var n := CONTROLS.size()
	var line_h := 19.0
	var box_h := n * line_h + 18.0
	var box := Rect2(18, vp.y - 20.0 - box_h, 268.0, box_h)
	_canvas.draw_rect(box, Color(0.01, 0.02, 0.03, 0.5))
	_canvas.draw_rect(Rect2(box.position.x, box.position.y, 3.0, box.size.y), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.7))
	var y := box.position.y + 12.0
	for row in CONTROLS:
		_canvas.draw_string(_font, Vector2(box.position.x + 14, y + 5), String(row[0]),
			HORIZONTAL_ALIGNMENT_LEFT, 96.0, 13, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.9))
		_canvas.draw_string(_font, Vector2(box.position.x + 112, y + 5), String(row[1]),
			HORIZONTAL_ALIGNMENT_LEFT, 150.0, 13, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.95))
		y += line_h


func _draw_hint(vp: Vector2) -> void:
	if _hint == "":
		return
	_canvas.draw_string(_font, Vector2(vp.x * 0.5 + 40.0, vp.y - 26.0), _hint,
		HORIZONTAL_ALIGNMENT_CENTER, vp.x - 400.0, 15, Color(0.62, 0.72, 0.85, 0.92))


func _draw_death(vp: Vector2) -> void:
	if _death == "":
		return
	var a := clampf(_death_anim, 0.0, 1.0)
	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.28, 0.01, 0.01, 0.44 * a))
	var pulse := 0.75 + 0.25 * absf(sin(_death_anim * 4.0))
	_canvas.draw_rect(Rect2(0, vp.y * 0.5 - 82.0, vp.x, 164.0), Color(0.03, 0.0, 0.0, 0.55 * a))
	_canvas.draw_rect(Rect2(0, vp.y * 0.5 - 82.0, vp.x, 2), Color(1.0, 0.25, 0.2, 0.8 * a))
	_canvas.draw_rect(Rect2(0, vp.y * 0.5 + 82.0, vp.x, 2), Color(1.0, 0.25, 0.2, 0.8 * a))
	_glow(Vector2(vp.x * 0.5, vp.y * 0.5), _death, HORIZONTAL_ALIGNMENT_CENTER, 0.0, 56,
		Color(1.0, 0.42, 0.36, a * pulse), 4.0)
	_canvas.draw_string(_font, Vector2(vp.x * 0.5, vp.y * 0.5 + 56), "按 R 立刻重开本关",
		HORIZONTAL_ALIGNMENT_CENTER, 0.0, 20, Color(1.0, 0.96, 0.94, a))


func _draw_markers(vp: Vector2) -> void:
	var center := vp * 0.5
	var inset := 66.0
	for m in _markers:
		var seen := bool(m.get("seen", false))
		var kind := String(m.get("kind", "mob"))
		var dist := float(m.get("dist", 0.0))
		var col := (C_CYAN if seen else C_RED)
		var sc: Vector2 = m.get("screen", center)
		var dvec := sc - center
		if dvec.length() < 1.0:
			dvec = Vector2.DOWN
		var dir := dvec.normalized()
		if bool(m.get("off", false)):
			var half := center - Vector2(inset, inset)
			var tx := half.x / maxf(absf(dir.x), 0.0001)
			var ty := half.y / maxf(absf(dir.y), 0.0001)
			var pos := center + dir * minf(tx, ty)
			_draw_arrow(pos, dir, col)
			_canvas.draw_string(_font, Vector2(pos.x - dir.x * 34.0, pos.y - dir.y * 34.0 + 4.0),
				"%s %dm" % [_kind_tag(kind), int(dist)],
				HORIZONTAL_ALIGNMENT_CENTER, 96.0, 11, Color(col.r, col.g, col.b, 0.8))
		else:
			var p := sc
			var pts := PackedVector2Array([
				p + Vector2(0, -9), p + Vector2(9, 0), p + Vector2(0, 9), p + Vector2(-9, 0)])
			_canvas.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.28))
			_canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(col.r, col.g, col.b, 0.9), 1.4)
			_canvas.draw_string(_font, Vector2(p.x - 48.0, p.y + 24.0), "%s %dm" % [_kind_tag(kind), int(dist)],
				HORIZONTAL_ALIGNMENT_CENTER, 96.0, 11, Color(col.r, col.g, col.b, 0.8))


func _draw_arrow(pos: Vector2, dir: Vector2, col: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var tip := pos + dir * 12.0
	var b1 := pos - dir * 6.0 + perp * 8.0
	var b2 := pos - dir * 6.0 - perp * 8.0
	var pts := PackedVector2Array([tip, b1, b2])
	_canvas.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.85))
	_canvas.draw_circle(pos, 3.0, Color(1, 1, 1, 0.7))


func _kind_tag(kind: String) -> String:
	match kind:
		"boss":
			return "首领"
		"archer":
			return "弓手"
		_:
			return "敌人"

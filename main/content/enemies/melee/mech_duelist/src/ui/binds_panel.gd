extends CanvasLayer
## BindsPanel — Esc 暂停 / 全键位重绑面板（CanvasLayer）。
##
## 接口冻结（不可改签名）：open() / close() / toggle() / is_open() / handle_input(event) -> bool
##
## 上半「按键绑定」列出 B.actions() 的全部动作（按组分区），点击或回车进入
## 「按下新键」捕获态，下一个键盘 / 鼠标输入完成绑定，Esc 取消。下半「系统」
## 放继续 / 重开 / 恢复默认 / 退出。冲突时明示「已与「XX」冲突，对方被解绑」。

const HEADER_H := 96.0
const ROW_H := 27.0
const HEAD_H := 30.0
const PAD := 22.0
const SYS_ROW_H := 34.0
const SYS_HEAD_H := 30.0
const SYS_PAD := 16.0

const C_BG := Color(0.016, 0.013, 0.02, 0.95)
const C_HEAD := Color(0.045, 0.03, 0.05, 0.98)
const C_LINE := Color(0.85, 0.42, 0.18, 0.38)
const C_ORANGE := Color(1.0, 0.56, 0.20)
const C_CYAN := Color(0.30, 0.95, 1.0)
const C_TEXT := Color(0.86, 0.88, 0.94)
const C_DIM := Color(0.44, 0.46, 0.55)
const C_KEY := Color(0.55, 1.0, 0.78)
const C_CAP := Color(1.0, 0.78, 0.30)
const C_SEL := Color(0.9, 0.42, 0.14, 0.22)
const C_GREEN := Color(0.35, 1.0, 0.66)

const KEY_PRETTY := {
	"Space": "空格", "Escape": "Esc", "Backspace": "退格", "Enter": "回车",
	"Tab": "Tab", "QuoteLeft": "~", "Shift": "Shift", "Ctrl": "Ctrl", "Alt": "Alt",
	"Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
}

var _open := false
var _rows: Array = []          # 导航用：绑定行 + 系统行
var _bind_rows: Array = []     # head / action
var _sys_rows: Array = []      # button
var _sel := 0
var _scroll := 0.0
var _capture := ""             # 正在重绑的 action id
var _panel: PanelContainer
var _list: Control
var _font: Font
var _msg := ""
var _msg_t := 0.0
var _msg_col := Color(1, 0.85, 0.4)
var _id_label: Dictionary = {}
var _capture_t := 0.0


func _ready() -> void:
	layer = 52
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_font = ThemeDB.fallback_font

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	_list = Control.new()
	_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.draw.connect(_draw_list)
	_panel.add_child(_list)
	_build()


func _build() -> void:
	_rows.clear()
	_bind_rows.clear()
	_sys_rows.clear()
	_id_label.clear()
	for a in B.actions():
		_id_label[String(a["id"])] = String(a["label"])
	for g in B.groups():
		_bind_rows.append({"kind": "head", "group": g})
		for a in B.actions():
			if String(a["group"]) == g:
				_bind_rows.append({"kind": "action", "id": a["id"], "label": a["label"]})
	_sys_rows.append({"kind": "head", "group": "系统菜单"})
	_sys_rows.append({"kind": "button", "id": "resume", "label": "继续游戏"})
	_sys_rows.append({"kind": "button", "id": "restart", "label": "重开本关"})
	_sys_rows.append({"kind": "button", "id": "reset_binds", "label": "恢复默认按键"})
	_sys_rows.append({"kind": "button", "id": "quit", "label": "退出游戏"})
	_rows = _bind_rows + _sys_rows
	_sel = clampi(_sel, 0, maxi(0, _rows.size() - 1))


# ------------------------------------------------------------------ api
func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	visible = true
	_capture = ""
	_clamp_scroll()
	_list.queue_redraw()


func close() -> void:
	_open = false
	visible = false
	_capture = ""
	_scroll = 0.0


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## 测试用：绑定（action）行数 / 系统按钮数
func action_row_count() -> int:
	var n := 0
	for r in _bind_rows:
		if String(r["kind"]) == "action":
			n += 1
	return n


func system_row_count() -> int:
	return _sys_rows.size() - 1


func is_capturing() -> bool:
	return _capture != ""


# ------------------------------------------------------------------ geometry
func _sys_top() -> float:
	var h := SYS_HEAD_H + system_row_count() * SYS_ROW_H + SYS_PAD
	return _list.size.y - h


func _bind_content_h() -> float:
	var h := 0.0
	for r in _bind_rows:
		h += HEAD_H if String(r["kind"]) == "head" else ROW_H
	return h


func _visible_h() -> float:
	return maxf(1.0, _sys_top() - HEADER_H - 8.0)


func _clamp_scroll() -> void:
	_scroll = clampf(_scroll, 0.0, maxf(0.0, _bind_content_h() - _visible_h()))


func _bind_row_y(i: int) -> float:
	var y := HEADER_H - _scroll
	for k in i:
		y += HEAD_H if String(_bind_rows[k]["kind"]) == "head" else ROW_H
	return y


func _sys_row_y(j: int) -> float:
	return _sys_top() + SYS_HEAD_H + j * SYS_ROW_H


func _row_index_at(y: float) -> int:
	if y < _sys_top():
		var yy := HEADER_H - _scroll
		for i in _bind_rows.size():
			var h := HEAD_H if String(_bind_rows[i]["kind"]) == "head" else ROW_H
			if y >= yy and y < yy + h:
				return i
			yy += h
		return -1
	for j in system_row_count():
		var sy := _sys_row_y(j)
		if y >= sy and y < sy + SYS_ROW_H:
			return _bind_rows.size() + 1 + j
	return -1


# ------------------------------------------------------------------ input
func handle_input(ev: InputEvent) -> bool:
	if not _open:
		return false

	if _capture != "":
		if ev is InputEventKey and ev.keycode == KEY_ESCAPE and ev.pressed and not ev.echo:
			_capture = ""
			_msg = "已取消"
			_msg_col = C_DIM
			_msg_t = 1.6
			_list.queue_redraw()
			return true
		if ev is InputEventKey and not ev.pressed:
			return true
		if ev is InputEventMouseButton and not ev.pressed:
			return true
		if ev is InputEventMouseMotion:
			return true
		_do_rebind(ev)
		return true

	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_ESCAPE:
				close()
			KEY_UP:
				_move_sel(-1)
			KEY_DOWN:
				_move_sel(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate()
			KEY_F7:
				B.reset_all()
				_set_msg("已恢复默认按键", C_GREEN)
			_:
				return false
		return true

	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll += 3.0 * ROW_H
			_clamp_scroll()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll -= 3.0 * ROW_H
			_clamp_scroll()
		elif ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			var i := _row_index_at(ev.position.y)
			if i >= 0:
				_sel = i
				_activate()
		_list.queue_redraw()
		return true
	if ev is InputEventMouseMotion:
		return true
	return true


func _move_sel(dir: int) -> void:
	if _rows.is_empty():
		return
	_sel = clampi(_sel + dir, 0, _rows.size() - 1)
	# 跳过组标题
	for _n in _rows.size():
		if String(_rows[_sel]["kind"]) != "head":
			break
		var n := _sel + dir
		if n < 0 or n >= _rows.size():
			break
		_sel = n
	_ensure_visible()
	_list.queue_redraw()


func _ensure_visible() -> void:
	if _sel >= _bind_rows.size():
		return
	var y := _bind_row_y(_sel)
	if y < HEADER_H + 4.0:
		_scroll = maxf(0.0, _scroll - (HEADER_H + 4.0 - y))
	elif y + ROW_H > _sys_top() - 4.0:
		_scroll += (y + ROW_H) - (_sys_top() - 4.0)
	_clamp_scroll()


func _activate() -> void:
	if _rows.is_empty():
		return
	var r: Dictionary = _rows[_sel]
	match String(r["kind"]):
		"action":
			_capture = String(r["id"])
			_capture_t = 0.0
			_set_msg("请按下新按键（Esc 取消）", C_CAP)
		"button":
			match String(r["id"]):
				"resume":
					close()
				"restart":
					var main := get_parent()
					if main and main.has_method("restart_level"):
						main.restart_level()
					close()
				"reset_binds":
					B.reset_all()
					_set_msg("已恢复默认按键", C_GREEN)
				"quit":
					get_tree().quit()
	_list.queue_redraw()


func _do_rebind(ev: InputEvent) -> void:
	var displaced := B.rebind(_capture, ev)
	var key_txt := _pretty(B.event_text(_capture))
	if displaced != "":
		var lb := String(_id_label.get(displaced, displaced))
		_set_msg("已绑定「%s」→ %s　·　已与「%s」冲突，对方被解绑" % [_id_label.get(_capture, _capture), key_txt, lb], C_CAP)
	else:
		_set_msg("已绑定「%s」→ %s" % [_id_label.get(_capture, _capture), key_txt], C_GREEN)
	_capture = ""
	_list.queue_redraw()


func _set_msg(text: String, col: Color) -> void:
	_msg = text
	_msg_col = col
	_msg_t = 3.0


func _pretty(t: String) -> String:
	return String(KEY_PRETTY.get(t, t))


# ------------------------------------------------------------------ paint
func _draw_list() -> void:
	var vp := _list.size
	if vp.x < 10.0:
		return
	_clamp_scroll()
	var sys_top := _sys_top()

	_list.draw_rect(Rect2(Vector2.ZERO, vp), C_BG)

	# 绑定区
	var y := HEADER_H - _scroll
	for i in _bind_rows.size():
		var r: Dictionary = _bind_rows[i]
		var h := HEAD_H if String(r["kind"]) == "head" else ROW_H
		if y + h > HEADER_H and y < sys_top:
			_draw_bind_row(i, r, y, vp.x)
		y += h

	# 系统区
	var sy := sys_top
	for r in _sys_rows:
		if String(r["kind"]) == "head":
			_list.draw_rect(Rect2(0, sy, vp.x, SYS_HEAD_H), C_HEAD)
			_list.draw_line(Vector2(0, sy + 0.5), Vector2(vp.x, sy + 0.5), C_LINE, 1.0)
			_list.draw_rect(Rect2(0, sy + 1, 3, SYS_HEAD_H - 2), C_CYAN)
			_list.draw_string(_font, Vector2(PAD, sy + 21), String(r["group"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_CYAN)
			sy += SYS_HEAD_H
		else:
			_draw_button(_rows.find(r), r, sy, vp.x)
			sy += SYS_ROW_H

	_draw_header(vp)
	_list.draw_string(_font, Vector2(vp.x - PAD - 320.0, vp.y - 14.0), "按键写入 user://actdemo_binds.json",
		HORIZONTAL_ALIGNMENT_RIGHT, 320.0, 12, Color(0.4, 0.44, 0.52))


func _draw_header(vp: Vector2) -> void:
	_list.draw_rect(Rect2(0, 0, vp.x, HEADER_H), C_HEAD)
	_list.draw_line(Vector2(0, HEADER_H - 1.0), Vector2(vp.x, HEADER_H - 1.0), C_LINE, 1.0)
	_list.draw_rect(Rect2(0, 0, 4, HEADER_H), C_ORANGE)
	_list.draw_string(_font, Vector2(PAD + 6, 32), "暂 停",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, C_ORANGE)
	_list.draw_string(_font, Vector2(PAD + 6, 58), "按键绑定",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_CYAN)
	_list.draw_string(_font, Vector2(PAD + 6, 80),
		"↑↓ 选择　Enter / 左键 绑定　F7 恢复默认按键　Esc 继续",
		HORIZONTAL_ALIGNMENT_LEFT, vp.x * 0.5 - PAD, 13, C_DIM)
	if _msg_t > 0.0:
		var a := clampf(_msg_t / 0.5, 0.0, 1.0)
		_canvas_msg(vp, a)


func _draw_bind_row(i: int, r: Dictionary, y: float, vp_x: float) -> void:
	if String(r["kind"]) == "head":
		_list.draw_rect(Rect2(0, y, vp_x, HEAD_H), Color(0.05, 0.055, 0.075, 0.85))
		_list.draw_rect(Rect2(0, y + 1, 3, HEAD_H - 2), C_ORANGE)
		_list.draw_string(_font, Vector2(PAD, y + 21), String(r["group"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_ORANGE)
		return
	var id := String(r["id"])
	var sel := i == _sel
	var capturing := id == _capture
	var cy := y + ROW_H * 0.5
	if sel or capturing:
		_list.draw_rect(Rect2(PAD, y + 2, vp_x - PAD * 2.0, ROW_H - 4), C_SEL)
		_list.draw_rect(Rect2(PAD, y + 2, 3, ROW_H - 4), C_ORANGE)
	_list.draw_string(_font, Vector2(PAD + 14, cy + 5), String(r["label"]),
		HORIZONTAL_ALIGNMENT_LEFT, vp_x * 0.55, 15, C_TEXT if sel else Color(0.74, 0.77, 0.84))
	# 当前按键
	var kx := vp_x - PAD - 300.0
	if capturing:
		var pulse := 0.6 + 0.4 * absf(sin(_capture_t * 5.0))
		_list.draw_string(_font, Vector2(kx, cy + 5), "▶ 按下新键…",
			HORIZONTAL_ALIGNMENT_RIGHT, 290, 15, Color(C_CAP.r, C_CAP.g, C_CAP.b, pulse))
	else:
		var txt := _pretty(B.event_text(id))
		var is_mouse := txt.begins_with("鼠标")
		_list.draw_rect(Rect2(kx + 290.0 - 132.0, cy - 11.0, 132.0, 22.0),
			Color(0.12, 0.16, 0.22, 0.9))
		_list.draw_rect(Rect2(kx + 290.0 - 132.0, cy - 11.0, 132.0, 22.0),
			C_CYAN if is_mouse else C_KEY, false, 1.0)
		_list.draw_string(_font, Vector2(kx + 290.0 - 132.0, cy + 5), txt,
			HORIZONTAL_ALIGNMENT_CENTER, 132.0, 14, C_CYAN if is_mouse else C_KEY)


func _draw_button(idx: int, r: Dictionary, y: float, vp_x: float) -> void:
	var sel := idx == _sel
	var w := minf(420.0, vp_x - PAD * 2.0)
	var box := Rect2(PAD, y + 3, w, SYS_ROW_H - 8)
	if sel:
		_list.draw_rect(box, Color(0.10, 0.5, 0.75, 0.32))
		_list.draw_rect(box, C_CYAN, false, 1.0)
		_list.draw_rect(Rect2(box.position.x, box.position.y, 3, box.size.y), C_CYAN)
	else:
		_list.draw_rect(box, Color(0.05, 0.06, 0.08, 0.7))
		_list.draw_rect(box, C_LINE, false, 1.0)
	_list.draw_string(_font, Vector2(box.position.x + 16, box.position.y + box.size.y * 0.5 + 6),
		String(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT if sel else Color(0.72, 0.76, 0.84))


func _canvas_msg(vp: Vector2, a: float) -> void:
	var box := Rect2(vp.x * 0.5, 12.0, vp.x * 0.5 - PAD, 62.0)
	_list.draw_rect(box, Color(0.03, 0.03, 0.05, 0.9))
	_list.draw_rect(box, _msg_col, false, 1.0)
	_list.draw_string(_font, Vector2(box.position.x + 14.0, box.position.y + 38.0), _msg,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24.0, 14, Color(_msg_col.r, _msg_col.g, _msg_col.b, a))


func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t = maxf(0.0, _msg_t - delta)
		_list.queue_redraw()
	if _capture != "":
		_capture_t += delta
		_list.queue_redraw()

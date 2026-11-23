extends CanvasLayer
## Tuning — 「~」手感参数面板（CanvasLayer）。
##
## 接口冻结（不可改签名）：open() / close() / toggle() / is_open() / handle_input(event) -> bool
##
## 全部行由 P.defs() 自动生成，所以 P 里新增参数这里立刻出现。参数按组分区，
## 左侧是可点击的分组导航条，组标题吸顶。键盘 / 鼠标都能改值：
##   ↑↓ 选择 · ←→ 调整(Shift ×10 · Ctrl ×0.1) · Enter 输入数值 · Backspace 恢复默认
##   Tab 跳下一组 · F5 存盘 · F6 重置当前组 · ~ / Esc 关闭
##   鼠标：滚轮滚动、点击选中、拖动滑块改值、点组名跳组
##
## handle_input 返回 true 表示事件被 UI 吃掉，游戏不再处理。

const HEADER_H := 54.0
const FOOTER_H := 30.0
const LEFT_W := 180.0
const ROW_H := 26.0
const HEAD_H := 30.0
const NAV_H := 27.0
const PAD := 16.0

const C_BG := Color(0.012, 0.017, 0.026, 0.978)
const C_HEAD := Color(0.028, 0.05, 0.075, 0.98)
const C_HEADBAR := Color(0.05, 0.11, 0.16, 0.98)
const C_NAV := Color(0.02, 0.035, 0.055, 0.98)
const C_LINE := Color(0.10, 0.55, 0.70, 0.35)
const C_CYAN := Color(0.30, 0.95, 1.0)
const C_ORANGE := Color(1.0, 0.58, 0.22)
const C_TEXT := Color(0.84, 0.90, 0.96)
const C_DIM := Color(0.42, 0.50, 0.60)
const C_SEL := Color(0.13, 0.55, 0.82, 0.30)
const C_GREEN := Color(0.35, 1.0, 0.66)
const C_TRACK := Color(0.10, 0.13, 0.18, 0.95)

var _rows: Array = []          # {kind:"head"|"param", group, path, def}
var _groups: Array = []
var _sel := 0
var _scroll := 0.0
var _open := false
var _edit: LineEdit
var _panel: PanelContainer
var _list: Control
var _font: Font
var _drag_row := -1
var _save_flash := 0.0


func _ready() -> void:
	layer = 50
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

	_edit = LineEdit.new()
	_edit.visible = false
	_edit.custom_minimum_size = Vector2(170, 26)
	_edit.size = Vector2(170, 26)
	_edit.add_theme_font_size_override("font_size", 15)
	add_child(_edit)
	_edit.text_submitted.connect(_on_edit_submit)

	_build_rows()
	P.bulk_changed.connect(_build_rows)


# ------------------------------------------------------------------ rows
func _build_rows() -> void:
	_rows.clear()
	_groups = P.groups()
	for g in _groups:
		_rows.append({"kind": "head", "group": g})
		for d in P.defs(g):
			_rows.append({"kind": "param", "path": d["path"], "group": g, "def": d})
	_sel = clampi(_sel, 0, maxi(0, _rows.size() - 1))
	_clamp_scroll()
	_list.queue_redraw()


func _row_h(r: Dictionary) -> float:
	return HEAD_H if String(r["kind"]) == "head" else ROW_H


func _content_h() -> float:
	var h := 0.0
	for r in _rows:
		h += _row_h(r)
	return h


func _visible_h() -> float:
	return maxf(1.0, _list.size.y - HEADER_H - FOOTER_H)


func _clamp_scroll() -> void:
	_scroll = clampf(_scroll, 0.0, maxf(0.0, _content_h() - _visible_h()))


func _row_y(i: int) -> float:
	var y := HEADER_H - _scroll
	for k in i:
		y += _row_h(_rows[k])
	return y


func _row_at(y: float) -> int:
	var yy := HEADER_H - _scroll
	for i in _rows.size():
		var h := _row_h(_rows[i])
		if y >= yy and y < yy + h:
			return i
		yy += h
	return -1


func _current_group() -> String:
	if _sel < 0 or _sel >= _rows.size():
		return ""
	return String(_rows[_sel].get("group", ""))


# ------------------------------------------------------------------ api
func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	visible = true
	_clamp_scroll()
	_list.queue_redraw()


func close() -> void:
	_open = false
	visible = false
	_drag_row = -1
	_edit.visible = false
	P.save()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## 测试用：参数行总数 / 分组数
func param_row_count() -> int:
	var n := 0
	for r in _rows:
		if String(r["kind"]) == "param":
			n += 1
	return n


func group_count() -> int:
	return _groups.size()


# ------------------------------------------------------------------ input
## 返回 true 表示事件已被面板吃下。
func handle_input(ev: InputEvent) -> bool:
	if not _open:
		return false

	if _edit.visible:
		if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
			_edit.visible = false
			_list.queue_redraw()
			return true
		# 文本输入交给 LineEdit 自己处理；游戏此时已暂停。
		if ev is InputEventKey:
			return false
		return true

	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_ESCAPE, KEY_QUOTELEFT:
				close()
			KEY_UP:
				_move_sel(-1)
			KEY_DOWN:
				_move_sel(1)
			KEY_LEFT:
				_nudge(-1.0 * _mul(ev))
			KEY_RIGHT:
				_nudge(1.0 * _mul(ev))
			KEY_PAGEUP:
				_nudge(10.0 * _mul(ev))
			KEY_PAGEDOWN:
				_nudge(-10.0 * _mul(ev))
			KEY_TAB:
				_next_group()
			KEY_ENTER, KEY_KP_ENTER:
				_activate()
			KEY_BACKSPACE:
				_reset_row()
			KEY_F5:
				P.save()
				_save_flash = 2.2
				_list.queue_redraw()
			KEY_F6:
				P.reset_group(_current_group())
				_save_flash = 0.0
			KEY_HOME:
				_sel = 0
				_scroll = 0.0
				_list.queue_redraw()
			KEY_END:
				_sel = _rows.size() - 1
				_ensure_visible()
				_list.queue_redraw()
			_:
				return false
		return true

	if ev is InputEventMouseButton:
		_mouse_button(ev)
		return true
	if ev is InputEventMouseMotion:
		if _drag_row >= 0:
			_drag_to(ev.position.x)
		return true
	return true


func _mouse_button(ev: InputEventMouseButton) -> void:
	var p: Vector2 = ev.position
	if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll += 3.0 * ROW_H
		_clamp_scroll()
		_list.queue_redraw()
		return
	if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll -= 3.0 * ROW_H
		_clamp_scroll()
		_list.queue_redraw()
		return
	if ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if not ev.pressed:
		_drag_row = -1
		return
	# 左侧分组导航
	if p.x < LEFT_W:
		var gi := int((p.y - HEADER_H - 30.0) / NAV_H)
		if gi >= 0 and gi < _groups.size():
			_jump_group(gi)
		return
	var i := _row_at(p.y)
	if i < 0 or String(_rows[i]["kind"]) != "param":
		return
	_sel = i
	var d: Dictionary = _rows[i]["def"]
	var t := String(d["type"])
	match t:
		"bool":
			P.set_value(d["path"], not P.getb(d["path"]))
		"enum":
			P.add_value(d["path"], 1.0)
		_:
			var br := _bar_rect(i)
			if p.x >= br.position.x - 10.0 and p.x <= br.end.x + 10.0:
				_drag_row = i
				_drag_to(p.x)
	_list.queue_redraw()


func _mul(ev: InputEventKey) -> float:
	if ev.shift_pressed:
		return 10.0
	if ev.ctrl_pressed:
		return 0.1
	return 1.0


func _move_sel(dir: int) -> void:
	if _rows.is_empty():
		return
	var i := _sel
	for _n in _rows.size():
		i = clampi(i + dir, 0, _rows.size() - 1)
		if String(_rows[i]["kind"]) == "param":
			break
		if i == 0 or i == _rows.size() - 1:
			break
	_sel = i
	_ensure_visible()
	_list.queue_redraw()


func _ensure_visible() -> void:
	var y := _row_y(_sel)
	var top := HEADER_H
	var bottom := _list.size.y - FOOTER_H
	if y < top + 4.0:
		_scroll = maxf(0.0, _scroll - (top + 4.0 - y))
	elif y + ROW_H > bottom - 4.0:
		_scroll += (y + ROW_H) - (bottom - 4.0)
	_clamp_scroll()


func _next_group() -> void:
	if _groups.is_empty():
		return
	var cur := _groups.find(_current_group())
	var gi := wrapi(cur + 1, 0, _groups.size())
	_jump_group(gi)


func _jump_group(gi: int) -> void:
	if gi < 0 or gi >= _groups.size():
		return
	var g := String(_groups[gi])
	for i in _rows.size():
		if String(_rows[i]["kind"]) == "param" and String(_rows[i]["group"]) == g:
			_sel = i
			var head_y := _row_y(i) - ROW_H  # 组标题所在行
			_scroll = maxf(0.0, head_y - HEADER_H)
			_clamp_scroll()
			_list.queue_redraw()
			return


func _nudge(dir: float) -> void:
	if _sel >= _rows.size() or String(_rows[_sel]["kind"]) != "param":
		return
	P.add_value(String(_rows[_sel]["path"]), dir)
	_list.queue_redraw()


func _reset_row() -> void:
	if _sel >= _rows.size() or String(_rows[_sel]["kind"]) != "param":
		return
	var path := String(_rows[_sel]["path"])
	P.set_value(path, P.spec(path)["default"])
	_list.queue_redraw()


func _activate() -> void:
	if _sel >= _rows.size() or String(_rows[_sel]["kind"]) != "param":
		return
	var d: Dictionary = _rows[_sel]["def"]
	var t := String(d["type"])
	if t == "bool":
		P.set_value(d["path"], not P.getb(d["path"]))
	elif t == "enum":
		P.add_value(d["path"], 1.0)
	else:
		_start_edit()


func _start_edit() -> void:
	if _sel >= _rows.size():
		return
	var d: Dictionary = _rows[_sel]["def"]
	var y := _row_y(_sel)
	_edit.position = Vector2(_list.size.x - PAD - 470.0, y + (ROW_H - 26.0) * 0.5)
	_edit.text = str(P.value(d["path"]))
	_edit.visible = true
	_edit.grab_focus()
	_edit.select_all()


func _on_edit_submit(text: String) -> void:
	_edit.visible = false
	if _sel < _rows.size() and String(_rows[_sel]["kind"]) == "param":
		var d: Dictionary = _rows[_sel]["def"]
		var v: float = text.to_float() if String(d["type"]) == "float" else text.to_int()
		P.set_value(d["path"], v)
	_list.queue_redraw()


# ------------------------------------------------------------------ drag
func _bar_rect(i: int) -> Rect2:
	var vp_x := _list.size.x
	var w := 250.0
	var x := vp_x - PAD - w
	var y := _row_y(i) + ROW_H * 0.5 - 3.0
	return Rect2(Vector2(x, y), Vector2(w, 6.0))


func _drag_to(x: float) -> void:
	if _drag_row < 0 or _drag_row >= _rows.size():
		return
	var d: Dictionary = _rows[_drag_row]["def"]
	var br := _bar_rect(_drag_row)
	var u := clampf((x - br.position.x) / maxf(1.0, br.size.x), 0.0, 1.0)
	var mn := float(d["min"])
	var mx := float(d["max"])
	var raw := mn + u * (mx - mn)
	var st := float(d.get("step", 0.0))
	if st > 0.0:
		raw = mn + roundf((raw - mn) / st) * st
	P.set_value(String(d["path"]), raw)
	_list.queue_redraw()


# ------------------------------------------------------------------ paint
func _fade_color(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


func _draw_list() -> void:
	var vp := _list.size
	if vp.x < 10.0:
		return
	_clamp_scroll()
	var top := HEADER_H
	var bottom := vp.y - FOOTER_H

	# 背景 + 淡淡的网格
	_list.draw_rect(Rect2(Vector2.ZERO, vp), C_BG)
	for gx in range(int(LEFT_W), int(vp.x), 64):
		_list.draw_line(Vector2(gx, top), Vector2(gx, bottom), Color(0.15, 0.5, 0.65, 0.045), 1.0)
	for gy in range(int(top), int(bottom), 64):
		_list.draw_line(Vector2(LEFT_W, gy), Vector2(vp.x, gy), Color(0.15, 0.5, 0.65, 0.045), 1.0)

	# 行
	var sticky := -1
	var y := HEADER_H - _scroll
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var h := _row_h(r)
		if String(r["kind"]) == "head":
			if y < top - 1.0:
				sticky = i
			if y + h > top and y < bottom:
				_draw_head(r, y, vp.x, false)
		else:
			if y + h > top and y < bottom:
				_draw_param(i, r, y, vp.x)
		y += h

	# 左侧分组导航
	_draw_nav(vp, top, bottom)
	# 顶栏 / 底栏 / 吸顶标题（后画，盖住滚出边界的行）
	_draw_header(vp)
	_draw_footer(vp, bottom)
	if sticky >= 0:
		_draw_head(_rows[sticky], top, vp.x, true)


func _draw_head(r: Dictionary, y: float, vp_x: float, sticky: bool) -> void:
	var band := C_HEADBAR if sticky else C_HEAD
	_list.draw_rect(Rect2(LEFT_W, y, vp_x - LEFT_W, HEAD_H), band)
	_list.draw_rect(Rect2(LEFT_W, y + 1.5, 3.0, HEAD_H - 3.0), C_ORANGE)
	_list.draw_line(Vector2(LEFT_W, y + HEAD_H - 1.0), Vector2(vp_x, y + HEAD_H - 1.0),
		C_LINE if not sticky else Color(0.4, 0.8, 0.95, 0.55), 1.0)
	if sticky:
		_list.draw_line(Vector2(LEFT_W, y + HEAD_H + 0.5), Vector2(vp_x, y + HEAD_H + 0.5),
			Color(0, 0, 0, 0.5), 1.0)
	var cnt := P.defs(String(r["group"])).size()
	_list.draw_string(_font, Vector2(LEFT_W + 16, y + HEAD_H * 0.5 + 6), String(r["group"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_ORANGE)
	_list.draw_string(_font, Vector2(vp_x - 90, y + HEAD_H * 0.5 + 5), "%d 项" % cnt,
		HORIZONTAL_ALIGNMENT_RIGHT, 74, 12, C_DIM)


func _draw_param(i: int, r: Dictionary, y: float, vp_x: float) -> void:
	var d: Dictionary = r["def"]
	var path := String(d["path"])
	var sel := i == _sel
	var row := Rect2(LEFT_W + 6, y + 1, vp_x - LEFT_W - 12, ROW_H - 2)
	if sel:
		_list.draw_rect(row, C_SEL)
		_list.draw_rect(Rect2(LEFT_W + 6, y + 1, 3.0, ROW_H - 2), C_CYAN)
	elif i % 2 == 1:
		_list.draw_rect(row, Color(1, 1, 1, 0.018))

	var bar := _bar_rect(i)
	var val_end := bar.position.x - 14.0
	var val_x := val_end - 150.0
	var label_x := LEFT_W + 20.0
	var label_w := maxf(40.0, val_x - label_x - 12.0)

	var col := C_TEXT if sel else Color(0.70, 0.75, 0.82)
	_list.draw_string(_font, Vector2(label_x, y + ROW_H * 0.5 + 5), String(d["label"]),
		HORIZONTAL_ALIGNMENT_LEFT, label_w, 14, col)

	var t := String(d["type"])
	match t:
		"bool":
			_draw_bool(d, path, val_x, val_end, y, sel)
		"enum":
			_draw_enum(d, path, val_x, val_end, y, sel)
		_:
			_list.draw_string(_font, Vector2(val_x, y + ROW_H * 0.5 + 5), _value_text(d),
				HORIZONTAL_ALIGNMENT_RIGHT, 150, 14, C_GREEN if sel else Color(0.6, 0.86, 0.72))
			_draw_bar(d, path, bar, y, sel)


func _draw_bool(d: Dictionary, path: String, vx: float, vend: float, y: float, sel: bool) -> void:
	var on := P.getb(path)
	var cy := y + ROW_H * 0.5
	var w := 54.0
	var box := Rect2(Vector2(vend - w, cy - 9.0), Vector2(w, 18.0))
	_list.draw_rect(box, Color(0.35, 1.0, 0.66, 0.20) if on else Color(0.5, 0.5, 0.55, 0.15))
	_list.draw_rect(box, C_GREEN if on else C_DIM, false, 1.0)
	_list.draw_circle(Vector2(box.position.x + (w - 13.0) if on else box.position.x + 13.0, cy), 5.0,
		C_GREEN if on else C_DIM)
	_list.draw_string(_font, Vector2(vx, cy + 5), "开" if on else "关",
		HORIZONTAL_ALIGNMENT_RIGHT, 150, 14, C_GREEN if on else C_DIM)


func _draw_enum(d: Dictionary, _path: String, vx: float, _vend: float, y: float, sel: bool) -> void:
	var cy := y + ROW_H * 0.5
	var txt := "◀ %s ▶" % _value_text(d)
	_list.draw_string(_font, Vector2(vx, cy + 5), txt,
		HORIZONTAL_ALIGNMENT_RIGHT, 150, 14, C_CYAN if sel else Color(0.55, 0.85, 0.95))


func _draw_bar(d: Dictionary, path: String, bar: Rect2, y: float, sel: bool) -> void:
	var mn := float(d["min"])
	var mx := float(d["max"])
	if mx <= mn:
		return
	var v := P.getm(path)          # 面板一律显示真实米（存档值），不显示世界单位
	var fr := clampf((v - mn) / (mx - mn), 0.0, 1.0)
	var dfl: float = clampf((float(d["default"]) - mn) / (mx - mn), 0.0, 1.0)
	_list.draw_rect(bar, C_TRACK)
	_list.draw_rect(bar, Color(0.2, 0.5, 0.7, 0.30), false, 1.0)
	_list.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fr, bar.size.y)),
		C_CYAN if sel else Color(0.3, 0.7, 0.85, 0.7))
	# 默认值刻度
	var dx := bar.position.x + bar.size.x * dfl
	_list.draw_line(Vector2(dx, bar.position.y - 3.0), Vector2(dx, bar.end.y + 3.0),
		C_ORANGE, 1.0)
	# 当前值滑块
	var kx := bar.position.x + bar.size.x * fr
	_list.draw_circle(Vector2(kx, bar.position.y + bar.size.y * 0.5), 6.0, Color(0.02, 0.05, 0.08, 1.0))
	_list.draw_circle(Vector2(kx, bar.position.y + bar.size.y * 0.5), 5.0, C_CYAN if sel else Color(0.5, 0.85, 1.0))


func _draw_nav(vp: Vector2, top: float, bottom: float) -> void:
	_list.draw_rect(Rect2(0, top, LEFT_W, bottom - top), C_NAV)
	_list.draw_line(Vector2(LEFT_W, top), Vector2(LEFT_W, bottom), C_LINE, 1.0)
	_list.draw_string(_font, Vector2(PAD, top + 22), "分组导航", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_CYAN)
	var cur := _current_group()
	var y := top + 30.0
	for gi in _groups.size():
		var g := String(_groups[gi])
		var cy := y + NAV_H * 0.5
		var active := g == cur
		var rect := Rect2(8, y + 2, LEFT_W - 16, NAV_H - 4)
		if active:
			_list.draw_rect(rect, Color(0.10, 0.45, 0.7, 0.35))
			_list.draw_rect(Rect2(8, y + 2, 3.0, NAV_H - 4), C_CYAN)
		_list.draw_string(_font, Vector2(PAD + 6, cy + 5), g,
			HORIZONTAL_ALIGNMENT_LEFT, LEFT_W - 70, 13, C_TEXT if active else C_DIM)
		_list.draw_string(_font, Vector2(LEFT_W - 14, cy + 5), str(P.defs(g).size()),
			HORIZONTAL_ALIGNMENT_RIGHT, 24, 12, C_DIM)
		y += NAV_H


func _draw_header(vp: Vector2) -> void:
	_list.draw_rect(Rect2(0, 0, vp.x, HEADER_H), C_HEAD)
	_list.draw_line(Vector2(0, HEADER_H - 1.0), Vector2(vp.x, HEADER_H - 1.0), C_LINE, 1.0)
	_list.draw_rect(Rect2(0, 0, 4, HEADER_H), C_CYAN)
	_list.draw_string(_font, Vector2(PAD + 6, 24), "手感参数面板",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, C_CYAN)
	_list.draw_string(_font, Vector2(PAD + 6, 43),
		"↑↓ 选择   ←→ 调整(Shift ×10 · Ctrl ×0.1)   Enter 输入   Backspace 还原   Tab 跳组   F5 存盘   F6 重置组   ~ / Esc 关闭",
		HORIZONTAL_ALIGNMENT_LEFT, vp.x - 220.0, 12, C_DIM)
	if _save_flash > 0.0:
		_list.draw_string(_font, Vector2(vp.x - PAD - 150.0, 40), "● 已保存",
			HORIZONTAL_ALIGNMENT_RIGHT, 150, 14, _fade_color(C_GREEN, clampf(_save_flash / 0.5, 0.0, 1.0)))


func _draw_footer(vp: Vector2, y: float) -> void:
	_list.draw_rect(Rect2(0, y, vp.x, FOOTER_H), C_HEAD)
	_list.draw_line(Vector2(0, y + 0.5), Vector2(vp.x, y + 0.5), C_LINE, 1.0)
	var r: Dictionary = _rows[_sel] if _sel < _rows.size() else {}
	var info := ""
	if String(r.get("kind", "")) == "param":
		var d: Dictionary = r["def"]
		info = "%s" % d["path"]
		var note := String(d.get("note", ""))
		if note != "":
			info += "   —   " + note
	_list.draw_string(_font, Vector2(PAD, y + 20), info,
		HORIZONTAL_ALIGNMENT_LEFT, vp.x - 320.0, 13, C_DIM)
	_list.draw_string(_font, Vector2(vp.x - PAD - 200.0, y + 20), "共 %d 项 · %d 组" % [param_row_count(), _groups.size()],
		HORIZONTAL_ALIGNMENT_RIGHT, 200, 13, C_DIM)


# ------------------------------------------------------------------ helpers
func _value_text(d: Dictionary) -> String:
	var path := String(d["path"])
	match String(d["type"]):
		"bool":
			return "开" if P.getb(path) else "关"
		"enum":
			for o in d["options"]:
				if String(o["v"]) == P.gets(path):
					return String(o["label"])
			return P.gets(path)
		"int":
			return "%d%s" % [P.geti(path), d["unit"]]
		_:
			var f := P.getm(path)          # 同上：显示真实米
			var st: float = float(d["step"])
			var dec := 3
			if st >= 1.0:
				dec = 0
			elif st >= 0.1:
				dec = 1
			elif st >= 0.01:
				dec = 2
			return ("%%.%df%s" % [dec, d["unit"]]) % f


func _process(delta: float) -> void:
	if _save_flash > 0.0:
		_save_flash = maxf(0.0, _save_flash - delta)
		_list.queue_redraw()

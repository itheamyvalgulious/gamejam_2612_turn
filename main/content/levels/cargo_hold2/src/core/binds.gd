extends Node
## B — all rebindable input.
##
## Actions are created in the InputMap at runtime from this table, so the Esc
## menu can rebind everything (including itself) and persist to
## user://actdemo_binds.json.  Events are serialised as plain dicts.

const SAVE_PATH := "user://actdemo_binds.json"
const INTERACTION_SAVE_PATH := "user://turn_cargo_interaction.json"

## {id, label, group, ev:[{t:"key", k:KEY}, {t:"mouse", b:MOUSE_BUTTON_LEFT}]}
const DEFS := [
	{"id": "move_forward", "label": "前进", "group": "移动", "ev": [{"t": "key", "k": KEY_W}]},
	{"id": "move_back", "label": "后退", "group": "移动", "ev": [{"t": "key", "k": KEY_S}]},
	{"id": "move_left", "label": "左移", "group": "移动", "ev": [{"t": "key", "k": KEY_A}]},
	{"id": "move_right", "label": "右移", "group": "移动", "ev": [{"t": "key", "k": KEY_D}]},
	{"id": "jump", "label": "跳跃", "group": "动作", "ev": [{"t": "key", "k": KEY_SPACE}]},
	{"id": "dash", "label": "冲刺", "group": "动作", "ev": [{"t": "key", "k": KEY_SHIFT}]},
	{"id": "attack_light", "label": "攻击（配合 WASD 出方向斩）", "group": "动作",
		"ev": [{"t": "mouse", "b": MOUSE_BUTTON_LEFT}]},
	{"id": "parry", "label": "弹反 / 举刀", "group": "动作", "ev": [{"t": "mouse", "b": MOUSE_BUTTON_RIGHT}]},
	{"id": "attack_heavy", "label": "重斩", "group": "动作", "ev": [{"t": "key", "k": KEY_Q}]},
	{"id": "attack_spin", "label": "回旋斩", "group": "动作", "ev": [{"t": "key", "k": KEY_E}]},
	{"id": "interact", "label": "交互", "group": "动作", "ev": [{"t": "key", "k": KEY_F}]},
	{"id": "cam_mode", "label": "切换第一/第三人称", "group": "视角", "ev": [{"t": "key", "k": KEY_V}]},
	{"id": "fp_mask", "label": "第一人称视野黑幕（第三人称）", "group": "视角",
		"ev": [{"t": "key", "k": KEY_TAB}]},
	{"id": "cam_left", "label": "镜头左转", "group": "视角", "ev": [{"t": "key", "k": KEY_LEFT}]},
	{"id": "cam_right", "label": "镜头右转", "group": "视角", "ev": [{"t": "key", "k": KEY_RIGHT}]},
	{"id": "tuning", "label": "手感参数面板", "group": "系统", "ev": [{"t": "key", "k": KEY_QUOTELEFT}]},
	{"id": "pause", "label": "暂停 / 按键绑定", "group": "系统", "ev": [{"t": "key", "k": KEY_ESCAPE}]},
	{"id": "restart", "label": "重开本关", "group": "系统", "ev": [{"t": "key", "k": KEY_R}]},
	{"id": "next_level", "label": "下一关（调试）", "group": "系统", "ev": [{"t": "key", "k": KEY_N}]},
	{"id": "hud_toggle", "label": "隐藏 / 显示 HUD", "group": "系统", "ev": [{"t": "key", "k": KEY_F1}]},
	{"id": "audio_test", "label": "听声辨位测试（8 方位）", "group": "系统",
		"ev": [{"t": "key", "k": KEY_F2}]},
	{"id": "replay_toggle", "label": "回放最后 20 秒（第三人称）", "group": "系统",
		"ev": [{"t": "key", "k": KEY_DELETE}]},
]

var _events: Dictionary = {}     # id -> Array[Dictionary]
var _labels: Dictionary = {}     # id -> label
var _groups: Array = []


func _ready() -> void:
	for d in DEFS:
		_labels[d["id"]] = d["label"]
		if not _groups.has(d["group"]):
			_groups.append(d["group"])
		_events[d["id"]] = d["ev"].duplicate(true)
	load_from_disk()
	apply_all()


# ------------------------------------------------------------------ input map
func apply_all() -> void:
	for id in _events.keys():
		if not InputMap.has_action(id):
			InputMap.add_action(id, 0.2)
		InputMap.action_erase_events(id)
		for desc in _events[id]:
			var ev := make_event(desc)
			if ev != null:
				InputMap.action_add_event(id, ev)


func make_event(desc: Dictionary) -> InputEvent:
	match String(desc.get("t", "key")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(desc.get("k", 0))
			k.keycode = int(desc.get("k", 0))
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(desc.get("b", MOUSE_BUTTON_LEFT))
			return m
	return null


func desc_from_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"t": "key", "k": int(ev.physical_keycode) if ev.physical_keycode != 0 else int(ev.keycode)}
	if ev is InputEventMouseButton:
		return {"t": "mouse", "b": int(ev.button_index)}
	return {}


## Returns the id that used to own this event (displaced), or "" if none.
func rebind(id: String, ev: InputEvent) -> String:
	var desc := desc_from_event(ev)
	if desc.is_empty() or not _events.has(id):
		return ""
	var displaced := ""
	for other in _events.keys():
		if other == id:
			continue
		var kept: Array = []
		for d in _events[other]:
			if not _same_desc(d, desc):
				kept.append(d)
			else:
				displaced = String(other)
		_events[other] = kept
	_events[id] = [desc]
	apply_all()
	save()
	return displaced


func _same_desc(a: Dictionary, b: Dictionary) -> bool:
	if String(a.get("t", "")) != String(b.get("t", "")):
		return false
	if String(a.get("t", "")) == "key":
		return int(a.get("k", 0)) == int(b.get("k", 0))
	return int(a.get("b", 0)) == int(b.get("b", 0))


func event_text(id: String) -> String:
	if not _events.has(id) or _events[id].is_empty():
		return "—"
	return describe(_events[id][0])


func describe(desc: Dictionary) -> String:
	match String(desc.get("t", "")):
		"key":
			var k := int(desc.get("k", 0))
			match k:
				KEY_QUOTELEFT: return "~"
				KEY_LEFT: return "←"
				KEY_RIGHT: return "→"
				KEY_UP: return "↑"
				KEY_DOWN: return "↓"
				KEY_SPACE: return "空格"
				KEY_DELETE: return "Del"
				KEY_ESCAPE: return "Esc"
				KEY_SHIFT: return "Shift"
			var s := OS.get_keycode_string(k)
			return s if s != "" else "KEY%d" % k
		"mouse":
			match int(desc.get("b", 0)):
				MOUSE_BUTTON_LEFT: return "鼠标左键"
				MOUSE_BUTTON_RIGHT: return "鼠标右键"
				MOUSE_BUTTON_MIDDLE: return "鼠标中键"
				_: return "鼠标键%d" % int(desc.get("b", 0))
	return "—"


func actions() -> Array:
	var out: Array = []
	for d in DEFS:
		out.append({"id": d["id"], "label": d["label"], "group": d["group"]})
	return out


func groups() -> Array:
	return _groups


func reset_all() -> void:
	_events.clear()
	for d in DEFS:
		_events[d["id"]] = d["ev"].duplicate(true)
	apply_all()
	save()


# ------------------------------------------------------------------ queries
func pressed(id: String) -> bool:
	return InputMap.has_action(id) and Input.is_action_pressed(id)


func just(id: String) -> bool:
	return InputMap.has_action(id) and Input.is_action_just_pressed(id)


func move_vector() -> Vector2:
	if not (InputMap.has_action("move_left") and InputMap.has_action("move_right")):
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func mouse_attack() -> bool:
	return InputMap.has_action("attack_light") and Input.is_action_just_pressed("attack_light")


# ------------------------------------------------------------------ persist
func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		var shared := _events.duplicate()
		shared.erase("interact")
		f.store_string(JSON.stringify(shared, "  "))
		f.close()
	# Other levels save the shared controls independently of this action.
	var interaction := FileAccess.open(INTERACTION_SAVE_PATH, FileAccess.WRITE)
	if interaction != null:
		interaction.store_string(JSON.stringify(_events["interact"]))
		interaction.close()


func load_from_disk() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if parsed is Dictionary:
			for id in parsed:
				if _events.has(id):
					var events := _saved_events(parsed[id])
					if not events.is_empty():
						_events[id] = events
	if FileAccess.file_exists(INTERACTION_SAVE_PATH):
		var value = JSON.parse_string(FileAccess.get_file_as_string(INTERACTION_SAVE_PATH))
		if value is Array:
			var saved := _saved_events(value)
			if saved.is_empty() or not _interaction_key_used(saved[0]):
				_events["interact"] = saved
				return
	_default_interact_key()


func _saved_events(value: Variant) -> Array:
	var events: Array = []
	if value is Array:
		for d in value:
			if d is Dictionary:
				events.append({"t": String(d.get("t", "key")), "k": int(d.get("k", 0)), "b": int(d.get("b", 0))})
	return events


func _interaction_key_used(candidate: Dictionary) -> bool:
	for action in _events:
		if action == "interact":
			continue
		for existing in _events[action]:
			if _same_desc(candidate, existing):
				return true
	return false


func _default_interact_key() -> void:
	for key in [KEY_F, KEY_G, KEY_T]:
		var candidate := {"t": "key", "k": key}
		if not _interaction_key_used(candidate):
			_events["interact"] = [candidate]
			return
	_events["interact"] = []

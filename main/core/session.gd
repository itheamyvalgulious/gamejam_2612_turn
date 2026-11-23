extends Node

const MENU := "res://ui/menu/menu.tscn"
const Catalog = preload("res://core/level_catalog.gd")

enum MenuPage { HOME, LEVELS }

var menu_page := MenuPage.HOME
var _active := -1
var _changing := false
var _services: Script
var _arguments := PackedStringArray()


func open_level(index: int) -> void:
	if _changing or index < 0 or index >= Catalog.level_count():
		return
	_changing = true
	_switch.call_deferred(index)


func return_to_menu() -> void:
	if _changing or _active < 0:
		return
	_changing = true
	_switch.call_deferred(-1)


func level_arguments() -> PackedStringArray:
	var result := OS.get_cmdline_user_args()
	result.append_array(_arguments)
	return result


func active_level_index() -> int:
	return _active


func advance_level() -> void:
	if _active < 0:
		return
	if _active == Catalog.level_count() - 1:
		return_to_menu()
	else:
		open_level(_active + 1)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif key.keycode == KEY_F1 and _active >= 0:
		get_viewport().set_input_as_handled()
		return_to_menu()


func _process(_delta: float) -> void:
	if _changing or _active < 0:
		return
	var current := get_tree().current_scene
	if is_instance_valid(current):
		var level: Node = current.get("level")
		if level != null and level.get("state") == "finished":
			advance_level()


func _switch(index: int) -> void:
	var scene_path := MENU
	var next_services: Script
	if index >= 0:
		var entry := Catalog.get_entry(index)
		var episode := String(entry[2])
		var entry_scene := String(entry[3])
		scene_path = "res://runtime/levels/%s/%s" % [episode, "main.tscn" if entry_scene.is_empty() else entry_scene]
		next_services = load("res://runtime/systems/%s/services.gd" % Catalog.services_for(index)) as Script
		if next_services == null:
			_switch_failed(scene_path)
			return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_switch_failed(scene_path)
		return

	var tree := get_tree()
	var old := tree.current_scene
	tree.current_scene = null
	if is_instance_valid(old):
		old.free()
	if _services != null:
		_services.call("stop")
	_active = index
	_arguments.clear()
	InputMap.load_from_project_settings()

	_services = next_services
	if index >= 0:
		menu_page = MenuPage.LEVELS
		_arguments = PackedStringArray(Catalog.get_entry(index)[4])
		if DisplayServer.get_name() == "headless":
			_arguments.append("--no-mouse-capture")
		_services.call("start", tree.root)
	var current := packed.instantiate()
	tree.root.add_child(current)
	tree.current_scene = current
	if index < 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.root.title = "TURN" if index < 0 else "TURN · " + String(Catalog.get_entry(index)[0])
	_changing = false


func _switch_failed(path: String) -> void:
	_changing = false
	push_error("Unable to load " + path)
	var current := get_tree().current_scene
	if current != null and current.has_method("show_load_error"):
		current.call("show_load_error")

extends Node
## Mouse-look belongs to an explicit click in the focused game window.

signal capture_changed(captured: bool)

var _owns_capture := false
var _capture_frame := -1
var _no_mouse_capture := "--no-mouse-capture" in OS.get_cmdline_user_args()


func _ready() -> void:
	get_window().focus_exited.connect(release)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release()


func _exit_tree() -> void:
	if _owns_capture:
		_owns_capture = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func capture() -> void:
	if _no_mouse_capture or _owns_capture or DisplayServer.get_name() == "headless" or not get_window().has_focus():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_owns_capture = true
	_capture_frame = Engine.get_process_frames() + 1
	capture_changed.emit(true)


func release() -> void:
	if not _owns_capture:
		return
	_owns_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	capture_changed.emit(false)


func is_captured() -> bool:
	return _owns_capture and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and get_window().has_focus()


func can_move() -> bool:
	# The click that takes control also matches the attack binding.
	return _no_mouse_capture or (is_captured() and Engine.get_process_frames() > _capture_frame)


func toggle_fullscreen() -> void:
	release()
	var window := get_window()
	var fullscreen := window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	window.mode = Window.MODE_WINDOWED if fullscreen else Window.MODE_FULLSCREEN

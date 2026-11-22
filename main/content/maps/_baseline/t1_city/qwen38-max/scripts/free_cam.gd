class_name FreeCam
extends Camera3D
## Fly camera: click to capture mouse, WASD move, Q/E down/up, Shift boost,
## wheel changes speed, Esc releases mouse, Esc twice quits.

var yaw := 0.0
var pitch := -0.25
var speed := 40.0
var captured := false

func _ready() -> void:
	current = true
	fov = 62.0
	far = 16000.0
	near = 0.2

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			captured = true
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = clampf(speed * 1.25, 2.0, 2000.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = clampf(speed / 1.25, 2.0, 2000.0)
	elif ev is InputEventMouseMotion and captured:
		yaw -= ev.relative.x * 0.0022
		pitch = clampf(pitch - ev.relative.y * 0.0022, -1.55, 1.55)
		rotation = Vector3(pitch, yaw, 0)
	elif ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_ESCAPE:
			if captured:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				captured = false
			else:
				get_tree().quit()

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += transform.basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir += Vector3.DOWN
	if dir.length_squared() > 0.0:
		var boost := 4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		position += dir.normalized() * speed * boost * delta

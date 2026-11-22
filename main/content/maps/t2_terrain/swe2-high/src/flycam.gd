extends Node

## flycam.gd — WASD/QE + mouse fly camera for ground inspection.

var cam: Camera3D
var speed := 60.0
var boost := 4.0
var yaw := 0.0
var pitch := -0.2


func _ready() -> void:
	if cam:
		var e := cam.global_rotation
		yaw = e.y
		pitch = e.x


func teleport(p: Vector3, t: Vector3) -> void:
	cam.look_at_from_position(p, t, Vector3.UP)
	var e := cam.global_rotation
	yaw = e.y
	pitch = e.x


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= ev.relative.x * 0.0025
		pitch = clampf(pitch - ev.relative.y * 0.0025, -1.45, 1.45)
		cam.rotation = Vector3(pitch, yaw, 0)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.25, 600.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed * 0.8, 2.0)


func _process(dt: float) -> void:
	var dir := Vector3.ZERO
	var b := cam.global_transform.basis
	if Input.is_key_pressed(KEY_W): dir -= b.z
	if Input.is_key_pressed(KEY_S): dir += b.z
	if Input.is_key_pressed(KEY_A): dir -= b.x
	if Input.is_key_pressed(KEY_D): dir += b.x
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL): dir -= Vector3.UP
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): dir += Vector3.UP
	var v := speed * (boost if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	cam.global_position += dir.normalized() * v * dt

extends Node

## Free-fly camera with mouse look. WASD + QE vertical, Shift fast, [ ] speed.

var cam: Camera3D
var main: Node3D
var speed := 6.0
var yaw := 0.0
var pitch := 0.0


func _ready() -> void:
	set_process_input(true)
	var t := cam.global_transform
	yaw = atan2(-t.basis.z.x, -t.basis.z.z)
	pitch = asin(clampf(t.basis.z.y, -1.0, 1.0))


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= ev.relative.x * 0.0022
		pitch = clampf(pitch - ev.relative.y * 0.0022, -1.45, 1.45)
		_apply()
	elif ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_BRACKETLEFT: speed = maxf(1.0, speed * 0.7)
			KEY_BRACKETRIGHT: speed = minf(60.0, speed * 1.4)


func _apply() -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	cam.global_transform = Transform3D(b, cam.global_position)


func _process(dt: float) -> void:
	var d := Vector3.ZERO
	var b := cam.global_transform.basis
	if Input.is_key_pressed(KEY_W): d -= b.z
	if Input.is_key_pressed(KEY_S): d += b.z
	if Input.is_key_pressed(KEY_A): d -= b.x
	if Input.is_key_pressed(KEY_D): d += b.x
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): d += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL): d -= Vector3.UP
	var sp := speed * (3.2 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	cam.global_position += d.normalized() * sp * dt if d.length() > 0.0 else Vector3.ZERO


func teleport(p: Vector3, look: Vector3) -> void:
	cam.global_position = p
	cam.look_at(look, Vector3.UP)
	var t := cam.global_transform
	yaw = atan2(-t.basis.z.x, -t.basis.z.z)
	pitch = asin(clampf(t.basis.z.y, -1.0, 1.0))

## Free-fly camera controller (mouse look + WASD), screenshot friendly.
extends Node3D

var cam: Camera3D
var world
var frozen := false
var yaw := 0.0
var pitch := 0.0
var speed := 26.0
var pos := Vector3.ZERO
var fast := false
var mouse_look := true

func _ready() -> void:
	if cam:
		pos = cam.global_position
		var e := cam.global_rotation
		pitch = e.x
		yaw = e.y
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0022
		pitch = clampf(pitch - event.relative.y * 0.0022, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_T:
				if world:
					world.toggle_time()
			KEY_R:
				if world:
					world.toggle_rain()
			KEY_X:
				if world:
					world.toggle_xray()
			KEY_G:
				if world:
					world.toggle_cutaway()
			KEY_F:
				if world:
					world.toggle_hud()
			KEY_1:
				_teleport(Vector3(-96, 2.1, 260), Vector3(-40, 9, 40))
			KEY_2:
				_teleport(Vector3(-220, 260, 900), Vector3(-40, 30, -60))
			KEY_3:
				_teleport(Vector3(760, 6, -140), Vector3(980, 5, 60))
			KEY_4:
				_teleport(Vector3(300, 150, 470), Vector3(-60, 90, 20))
			KEY_5:
				if world:
					world.enter_interior()

func _teleport(p: Vector3, look: Vector3) -> void:
	pos = p
	var d := (look - p).normalized()
	yaw = atan2(-d.x, -d.z)
	pitch = asin(d.y)

func _process(delta: float) -> void:
	if frozen or cam == null:
		return
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		dir.y += 1.0
	fast = Input.is_key_pressed(KEY_SHIFT)
	var sp := speed * (7.0 if fast else 1.0)
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0))
	pos += (basis * dir.normalized() * sp * delta) if dir.length() > 0.01 else Vector3.ZERO
	cam.global_position = pos
	cam.global_rotation = Vector3(pitch, yaw, 0)
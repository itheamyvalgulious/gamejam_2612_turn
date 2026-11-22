extends Node

## Free-fly camera rig for the ship walkthrough.
## WASD / QE, Shift boost, mouse look, 1-9 jump to zones, F tour, Tab map, V hull.

var camera: Camera3D
var main: Node
var yaw := 0.0
var pitch := 0.0
var base_speed := 9.0
var sensitivity := 0.0022
var captured := true
var active := true


func _ready() -> void:
	captured = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


func set_look(y: float, p: float) -> void:
	yaw = y
	pitch = p
	camera.rotation = Vector3(pitch, yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and captured:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * sensitivity
		pitch = clampf(pitch - mm.relative.y * sensitivity, -1.5, 1.5)
		camera.rotation = Vector3(pitch, yaw, 0.0)
	elif event is InputEventMouseButton and event.pressed:
		if not captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			captured = true
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		match k:
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				captured = false
			KEY_H:
				if main.hud:
					main.hud.toggle_panel()
			KEY_TAB:
				if main.hud:
					main.hud.toggle_map()
			KEY_V:
				main.toggle_hull()
			KEY_G:
				main.cycle_quality()
			KEY_F:
				if main.tour:
					main.tour.toggle()
			KEY_R:
				main.jump_home()
			KEY_BRACKETLEFT:
				base_speed = maxf(2.0, base_speed - 2.0)
			KEY_BRACKETRIGHT:
				base_speed = minf(60.0, base_speed + 2.0)
			_:
				if k >= KEY_1 and k <= KEY_9:
					var idx := k - KEY_1
					if main.has_method("jump_to"):
						main.jump_to(idx)


func _process(dt: float) -> void:
	if not active or camera == null:
		return
	if main.tour and main.tour.is_running():
		return
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_CTRL):
		dir.y -= 1.0
	var speed := base_speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 3.2
	var move := Basis(Vector3.UP, yaw) * Vector3(dir.x, 0.0, dir.z)
	move.y = dir.y
	if move.length() > 0.0:
		camera.global_position += move.normalized() * speed * dt
	if not captured:
		camera.rotation = Vector3(pitch, yaw, 0.0)


func teleport(pos: Vector3, look: Vector3) -> void:
	camera.global_position = pos
	var d := look - pos
	yaw = atan2(-d.x, -d.z)
	pitch = atan2(d.y, Vector2(d.x, d.z).length())
	camera.rotation = Vector3(pitch, yaw, 0.0)
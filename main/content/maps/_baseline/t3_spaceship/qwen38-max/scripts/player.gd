class_name PlayerCam
extends Node3D
## Fly-through exploration camera: WASD + mouse, Q/E down/up, F speed cycle,
## [ / ] jump along the main route, R reset to engine bay, ESC free mouse.

var cam: Camera3D
var yaw := 0.0
var pitch := 0.0
var speed := 5.0
var route: Array = []
var ridx := 0

func _init(lay: Layout) -> void:
	if lay:
		route = lay.route

func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.04
	cam.far = 14000.0
	add_child(cam)
	if route.size() > 4:
		_jump_to(0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("PLAYER READY: WASD move, mouse look, F speed, [ ] route jump, R reset, ESC cursor")

func _jump_to(i: int) -> void:
	ridx = clampi(i, 0, route.size() - 2)
	var p0: Vector3 = route[ridx]
	position = p0 + Vector3(0, 1.65, 0)
	var p1: Vector3 = route[mini(ridx + 3, route.size() - 1)]
	var d := p1 - p0
	if d.length() > 0.01:
		yaw = atan2(-d.x, -d.z)
	pitch = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0022
		pitch = clampf(pitch - event.relative.y * 0.0022, -1.55, 1.55)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			KEY_F:
				speed = [5.0, 14.0, 40.0][( [5.0, 14.0, 40.0].find(speed) + 1) % 3]
				print("speed: ", speed)
			KEY_BRACKETRIGHT:
				_jump_to(ridx + 4)
			KEY_BRACKETLEFT:
				_jump_to(ridx - 4)
			KEY_R:
				_jump_to(0)
			KEY_M:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var f: Vector3 = b * Vector3(0, 0, -1)
	var right: Vector3 = Basis(Vector3.UP, yaw) * Vector3(1, 0, 0)
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): v += f
	if Input.is_key_pressed(KEY_S): v -= f
	if Input.is_key_pressed(KEY_D): v += right
	if Input.is_key_pressed(KEY_A): v -= right
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): v += Vector3.UP
	if Input.is_key_pressed(KEY_Q): v -= Vector3.UP
	if v.length() > 0.01:
		position += v.normalized() * speed * delta
	cam.transform = Transform3D(b, Vector3.ZERO)

extends Node3D
## Third-person combat camera with cinematic shot support, spring damping,
## FOV kick and deterministic shake.

var camera: Camera3D
var target: Node3D

# shot parameters (distance/height/focus are in metres)
var yaw := 2.60
var distance := 6.4
var height := 1.65
var focus_height := 1.25
var fov := 40.0
var world_yaw := 0.0
var use_world_yaw := false
var follow_rate := 5.5

var shake_energy := 0.0
var speed_kick := 0.0

var _sm_pos := Vector3.ZERO
var _sm_focus := Vector3.ZERO
var _initialized := false
var _shake_t := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.08
	camera.far = 180.0
	add_child(camera)


func snap() -> void:
	_initialized = false


func set_shot(p_yaw: float, p_distance: float, p_height: float, p_focus: float, p_fov: float,
		p_world := false, p_world_yaw := 0.0) -> void:
	yaw = p_yaw
	distance = p_distance
	height = p_height
	focus_height = p_focus
	fov = p_fov
	use_world_yaw = p_world
	world_yaw = p_world_yaw


func add_shake(amount: float) -> void:
	shake_energy = minf(1.4, shake_energy + amount)


func update_camera(dt: float, speed: float) -> void:
	if target == null:
		return
	_shake_t += dt
	var base_yaw: float = world_yaw if use_world_yaw else target.rotation.y + yaw
	var focus: Vector3 = target.global_position + Vector3(0, focus_height, 0)
	var des: Vector3 = target.global_position + Vector3(0, height, 0) \
		+ Basis(Vector3.UP, base_yaw) * Vector3(0, 0, distance)
	# keep the lens off the floor
	des.y = maxf(des.y, 0.55)
	if not _initialized:
		_sm_pos = des
		_sm_focus = focus
		_initialized = true
	else:
		var k := 1.0 - exp(-follow_rate * dt)
		_sm_pos = _sm_pos.lerp(des, k)
		_sm_focus = _sm_focus.lerp(focus, 1.0 - exp(-8.0 * dt))
	speed_kick = lerpf(speed_kick, clampf((speed - 2.0) * 0.25, 0.0, 3.2), 1.0 - exp(-4.0 * dt))
	shake_energy = maxf(0.0, shake_energy - dt * 2.4)
	var sh := shake_energy * shake_energy
	var shake_off := Vector3(
		sin(_shake_t * 87.0) * sh * 0.12,
		cos(_shake_t * 71.0) * sh * 0.09,
		sin(_shake_t * 53.0 + 1.0) * sh * 0.07)
	camera.global_position = _sm_pos + shake_off
	var look := _sm_focus + Vector3(sin(_shake_t * 93.0), cos(_shake_t * 67.0), 0.0) * sh * 0.045
	camera.look_at(look, Vector3.UP)
	camera.fov = lerpf(camera.fov, fov + speed_kick, 1.0 - exp(-6.0 * dt))
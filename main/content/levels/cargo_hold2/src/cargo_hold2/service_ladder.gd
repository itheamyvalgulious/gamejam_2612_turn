extends RefCounted

const CargoArena = preload("res://src/cargo_hold2/arena.gd")
const LADDER := CargoArena.SERVICE_LADDER
const DECK_Y := CargoArena.SERVICE_DECK_Y
const BASE_Z := LADDER.z + 1.74
const CLIMB_Z := LADDER.z + 1.03
const DECK_Z := LADDER.z - 1.65
const DOCK_RISE := 0.58
const TOP_LIFT_START := DECK_Y - 0.55
const TOP_CROSS_START := TOP_LIFT_START + 1.10
const TOP_END := TOP_CROSS_START + 2.17
const CLIMB_SPEED := 2.36
const ALIGN_TIME := 0.40

var active := false
var progress := 0.0
var weight := 0.0
var at := Vector3.ZERO
var yaw := 0.0
var _initial_at := Vector3.ZERO
var _initial_yaw := 0.0
var _align_elapsed := 0.0
var _speed := 0.0


func available(origin: Vector3, view: Vector3) -> bool:
	var offset := origin - LADDER
	if absf(offset.x) > 0.78:
		return false
	if absf(origin.y) < 0.08:
		return offset.z >= 0.93 and offset.z <= 2.85 and view.z < -0.45
	return absf(origin.y - DECK_Y) < 0.08 and offset.z <= -1.00 and offset.z >= -2.90 and view.z > 0.45


func begin(origin: Vector3, heading: float) -> void:
	active = true
	progress = TOP_END if origin.y > DECK_Y * 0.5 else 0.0
	at = origin
	yaw = heading
	_initial_at = origin
	_initial_yaw = heading
	_align_elapsed = 0.0
	_speed = 0.0
	weight = 0.0


func step(dt: float, direction: float) -> void:
	if _align_elapsed < ALIGN_TIME:
		_align_elapsed = minf(_align_elapsed + dt, ALIGN_TIME)
		var blend := smoothstep(0.0, ALIGN_TIME, _align_elapsed)
		at = _initial_at.lerp(_route_at(progress), blend)
		yaw = lerp_angle(_initial_yaw, 0.0, blend)
		return

	_speed = move_toward(_speed, direction * CLIMB_SPEED, (16.0 if is_zero_approx(direction) else 11.0) * dt)
	var previous := progress
	progress = clampf(progress + _speed * dt, 0.0, TOP_END)
	at = _route_at(progress)
	weight = smoothstep(0.03, 0.67, progress) * (1.0 - smoothstep(TOP_CROSS_START, TOP_END, progress))
	if (progress <= 0.0 and previous > 0.0) or (progress >= TOP_END and previous < TOP_END):
		active = false


func _route_at(distance: float) -> Vector3:
	var height := distance
	var depth := lerpf(BASE_Z, CLIMB_Z, smoothstep(0.0, DOCK_RISE, distance))
	if distance > TOP_LIFT_START:
		var lift := clampf((distance - TOP_LIFT_START) / (TOP_CROSS_START - TOP_LIFT_START), 0.0, 1.0)
		height = lerpf(TOP_LIFT_START, DECK_Y, lift * (2.0 - lift))
		depth = lerpf(CLIMB_Z, DECK_Z, smoothstep(TOP_CROSS_START, TOP_END, distance))
	return Vector3(LADDER.x, height, depth)

extends "res://team/vesper/integration/campaign_rig.gd"

const CargoArena = preload("res://src/cargo_hold2/arena.gd")
const WALK_START := 10.76
const WALK_LENGTH := 5.62
const STEP_PERIOD := 1.04
const SWING := 0.24
# Front left leads, then the opposite rear foot, front right and rear left.
const FIRST_SWING := [0.43, 0.95, 0.17, 0.69]
const WALK_SPEED_UNITS := 2.48
const ACCEL_WINDOW := 0.77
const BRAKE_WINDOW := 0.68

var opening_pose := false
var opening_time := 0.0
var suspension_rest := 0.0
var boot_light := 1.0
var blade_power := 1.0
var wake_shift := 0.0
var wake_gaze := 0.0
var _ladder_weight := 0.0
var _energy_blade: Array[MeshInstance3D] = []


func _ready() -> void:
	super._ready()
	for child in weapon_spin.get_children():
		if child is MeshInstance3D and child.get_aabb().size.y > 0.8:
			_energy_blade.append(child)


static func travel(age: float) -> float:
	var t := clampf(age, 0.0, WALK_LENGTH)
	var brake_start := WALK_LENGTH - BRAKE_WINDOW
	if t <= ACCEL_WINDOW:
		var u := t / ACCEL_WINDOW
		return WALK_SPEED_UNITS * ACCEL_WINDOW * (u * u * u - 0.5 * pow(u, 4.0))
	if t < brake_start:
		return WALK_SPEED_UNITS * (t - ACCEL_WINDOW * 0.5)
	var u := (t - brake_start) / BRAKE_WINDOW
	return WALK_SPEED_UNITS * (brake_start - ACCEL_WINDOW * 0.5 + BRAKE_WINDOW * (u - u * u * u + 0.5 * pow(u, 4.0)))


func _current_pose(dt: float) -> Dictionary:
	var pose := super._current_pose(dt)
	if _ladder_weight > 0.0:
		var climbing := pose.duplicate()
		climbing["crouch"] = float(pose["crouch"]) + 0.22 * _ladder_weight
		climbing["lean"] = float(pose["lean"]) + 0.23 * _ladder_weight
		climbing["tx"] = float(pose["tx"]) + 0.12 * _ladder_weight
		return climbing
	if not opening_pose:
		return pose
	# The base rig returns its shared smoothing state. Keep the film pose layer separate.
	pose = pose.duplicate()
	var age := opening_time - WALK_START
	var carry := smoothstep(0.02, 0.68, age) * (1.0 - smoothstep(WALK_LENGTH - 0.65, WALK_LENGTH + 0.43, age))
	var sway := sin(age * TAU / STEP_PERIOD)
	pose["crouch"] = float(pose["crouch"]) + 0.52 * suspension_rest + carry * (0.24 + sway * 0.019)
	pose["lean"] = float(pose["lean"]) + 0.11 * suspension_rest + 0.14 * carry
	pose["tx"] = float(pose["tx"]) - 0.18 * suspension_rest + 0.13 * carry
	pose["hx"] = float(pose["hx"]) - 0.48 * suspension_rest + 0.49 * wake_gaze + 0.085 * carry
	pose["hy"] = float(pose["hy"]) - 0.29 * wake_gaze + sway * carry * 0.031
	pose["lean"] = float(pose["lean"]) + 0.12 * wake_shift
	pose["tz"] = float(pose["tz"]) + 0.12 * wake_shift + 0.042 * carry * sway
	pose["ty"] = float(pose["ty"]) - 0.09 * wake_shift - 0.038 * carry * sway
	pose["wpy"] = float(pose["wpy"]) - 0.13 * suspension_rest - 0.11 * carry
	pose["wrx"] = lerpf(float(pose["wrx"]), -1.68, maxf(suspension_rest, carry))
	return pose


func _update_legs(dt: float, run_amt: float) -> void:
	if not opening_pose:
		super._update_legs(dt, run_amt)
		if _ladder_weight > 0.0:
			_pose_ladder_feet(dt)
		return
	var age := opening_time - WALK_START
	var carry := smoothstep(0.0, 0.80, age) * (1.0 - smoothstep(WALK_LENGTH - 0.55, WALK_LENGTH + 0.31, age))
	body.position.x = 0.061 * wake_shift + 0.044 * carry * sin(age * TAU / STEP_PERIOD)
	body.position.z = 0.092 * wake_shift
	var inverse_lower := lower_body.global_transform.affine_inverse()
	var start := CargoArena.PLAYER_SPAWN
	var extent := FOOT_R * LOWER_SCALE * scale.x
	var ankle_height := ANKLE_H * LOWER_SCALE * scale.y
	for i in legs.size():
		var leg: Dictionary = legs[i]
		var phase: float = FIRST_SWING[i]
		var cycle := floorf((age - phase) / STEP_PERIOD)
		var lift_off := phase + maxf(cycle, 0.0) * STEP_PERIOD
		var u := smoothstep(lift_off, lift_off + SWING, age)
		var lead := SWING + (STEP_PERIOD - SWING) * 0.46
		var from_distance := travel(lift_off - STEP_PERIOD + lead) if cycle >= 1.0 else 0.0
		var to_distance := travel(lift_off + lead)
		var az: float = leg["az"]
		var from_z := start.z + sin(az) * extent - from_distance
		var to_z := start.z + sin(az) * extent - to_distance
		var from_floor := _support(from_z)
		var to_floor := _support(to_z)
		var lift := sin(PI * u) * (0.21 + absf(from_floor - to_floor) * 0.53)
		var floor_at := lerpf(from_floor, to_floor, u)
		var world_foot := Vector3(start.x + cos(az) * extent, floor_at + ankle_height + lift, lerpf(from_z, to_z, u))
		var target := inverse_lower * world_foot
		var hip: Node3D = leg["root"]
		var v := target - hip.position
		var yaw_joint: Node3D = leg["yaw"]
		yaw_joint.rotation.y = atan2(-v.z, v.x) + az
		super._solve_leg_ik(leg, target, dt, sin(PI * u) * 0.17)
		var planted := u <= 0.0 or u >= 1.0
		if planted and not leg["down"] and to_distance - from_distance > 0.10:
			footstep.emit(world_foot - Vector3.UP * ankle_height, 0.34 + 0.20 * (from_floor - to_floor))
		leg["down"] = planted


func begin_ladder_pose() -> void:
	stop_terrain_swing()
	clear_blade_path()
	_vel_h = Vector3.ZERO
	move_command = Vector3.ZERO
	dash_time = 0.0
	vertical_velocity = 0.0


func step_ladder_pose(dt: float, at: Vector3, facing: float, weight: float, attached: bool) -> void:
	_ladder_weight = weight
	global_position = at
	ground_height = at.y
	jump_state = "GROUND"
	heading = facing
	lock_heading = true
	weapon_root.visible = not attached
	advance(dt)
	lock_heading = false


func reset_ladder_pose() -> void:
	_ladder_weight = 0.0
	weapon_root.show()


func _update_arms(pose: Dictionary) -> void:
	super._update_arms(pose)
	if _ladder_weight <= 0.0:
		return
	var to_torso := torso.global_transform.affine_inverse()
	var ladder := CargoArena.SERVICE_LADDER
	var top_grip := smoothstep(7.0, 8.65, global_position.y)
	for i in arms.size():
		var arm: Dictionary = arms[i]
		var side: float = arm["side"]
		var wrist: Node3D = arm["wrist"]
		var reach := _ladder_contact(global_position.y + 3.50, i, ladder.z + 0.015)
		var hand := Vector3(ladder.x + side * 0.49, reach.y, reach.z)
		var handle := Vector3(ladder.x + side * CargoArena.LADDER_HALF_WIDTH, 11.84, ladder.z - 0.38)
		hand = hand.lerp(handle, top_grip)
		var target := to_torso * wrist.global_position.lerp(hand, _ladder_weight)
		_solve_arm(arm, target, Vector3.RIGHT, Vector3.FORWARD)


func _pose_ladder_feet(dt: float) -> void:
	var to_lower := lower_body.global_transform.affine_inverse()
	var ladder := CargoArena.SERVICE_LADDER
	var stepping_onto_deck := global_position.y >= CargoArena.SERVICE_DECK_Y - 0.01
	for leg in legs:
		var az: float = leg["az"]
		var front := sin(az) < 0.0
		var side := signf(cos(az))
		var phase := 0 if (front == (side < 0.0)) else 1
		var expected_y := global_position.y + (0.62 if front else 0.13)
		var rung := _ladder_contact(expected_y, phase, ladder.z + 0.17)
		var foot := Vector3(ladder.x + side * (0.44 if front else 0.69),
			rung.y + ANKLE_H * LOWER_SCALE * scale.y + 0.025, rung.z)
		var ankle: Node3D = leg["ankle"]
		var blend := _ladder_weight
		if stepping_onto_deck and front:
			blend *= smoothstep(ladder.z - 0.82, ladder.z + 0.69, global_position.z)
		var target := to_lower * ankle.global_position.lerp(foot, blend)
		var hip: Node3D = leg["root"]
		var aim := target - hip.position
		var yaw_joint: Node3D = leg["yaw"]
		yaw_joint.rotation.y = atan2(-aim.z, aim.x) + az
		_solve_leg_ik(leg, target, dt, -0.08 * blend)


func _ladder_contact(y: float, phase: int, depth: float) -> Vector3:
	var pitch := CargoArena.LADDER_RUNG_PITCH
	var index := (y - CargoArena.LADDER_FIRST_RUNG) / pitch
	var rung := floorf((index - float(phase)) * 0.5) * 2.0 + float(phase)
	var u := smoothstep(0.50, 0.93, (index - rung) * 0.5)
	var height := CargoArena.LADDER_FIRST_RUNG + clampf(rung + u * 2.0, 0.0,
		float(CargoArena.LADDER_RUNG_COUNT - 1)) * pitch
	return Vector3(0, height, depth + sin(PI * u) * 0.15)


func _support(z: float) -> float:
	return CargoArena.PRINT_BED_HEIGHT if z > CargoArena.PRINT_BED_FRONT else 0.0


func advance(dt: float) -> void:
	super.advance(dt)
	if not opening_pose:
		return
	lens_material.set_shader_parameter("intensity", 0.045 + 1.70 * boot_light)
	lens_light.light_energy *= boot_light
	for mesh in _energy_blade:
		mesh.visible = blade_power > 0.001
		mesh.scale.y = maxf(0.001, blade_power)
	weapon_light.light_energy *= blade_power

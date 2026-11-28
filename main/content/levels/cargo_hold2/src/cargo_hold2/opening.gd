extends RefCounted

const CargoArena = preload("res://src/cargo_hold2/arena.gd")
const OpeningRig = preload("res://src/cargo_hold2/opening_rig.gd")
const PRINT_DONE := 5.35
const TRANSFER_START := 5.98
const TRANSFER_CUT := 8.43
const WAKE_SHOT := 8.90
const PASSES := [Vector2(0.47, 1.62), Vector2(2.20, 3.28), Vector2(3.91, 5.19)]
const WALK_START := OpeningRig.WALK_START
const EYE_SHOT := 16.21
const DURATION := 17.62

var active := false
var time := 0.0
var _player: PlayerUnit
var _cam: GameCam
var _printer: Dictionary
var _fx: Node3D
var _sound_cue := 0
var _printer_voice := -1
var _voice := -1
var _printing := false
var _machining_at := Vector3.ZERO
var _last_pass := -1


func begin(player: PlayerUnit, cam: GameCam, arena: Dictionary) -> void:
	_player = player
	_cam = cam
	_printer = arena["printer"]
	_fx = _printer["effects"]
	if _printer_voice >= 0:
		Snd.stop(_printer_voice)
	_printer_voice = -1
	if _voice >= 0:
		Snd.stop(_voice)
	_voice = -1
	_fx.finish_print()
	active = true
	time = 0.0
	_sound_cue = 0
	_printing = true
	_last_pass = -1
	_cam.set_first_person(false)
	_player.rig.opening_pose = true
	_player.rig.ground_height = CargoArena.PRINT_BED_HEIGHT
	_player.rig.global_position = CargoArena.PLAYER_SPAWN + Vector3.UP * CargoArena.PRINT_BED_HEIGHT
	_pose_actor(0.001)
	_fx.begin(_player.rig)
	_apply_frame(0.0)


func step(dt: float) -> void:
	time = minf(time + dt, DURATION)
	_apply_frame(dt)
	active = time < DURATION
	if not active:
		_player.rig.opening_pose = false


func _apply_frame(dt: float) -> void:
	_pose_actor(dt)
	_pose_printer(dt)
	_sound()
	_shot()


func _pose_actor(dt: float) -> void:
	var rig = _player.rig
	rig.opening_time = time
	var weight := smoothstep(WAKE_SHOT + 0.24, WAKE_SHOT + 0.83, time)
	# Head wakes first, weight shifts onto the rear pair, then the suspension pushes up.
	var rise := smoothstep(WAKE_SHOT + 0.65, WALK_START + 0.27, time)
	rig.suspension_rest = 1.0 - rise
	var receiving := smoothstep(TRANSFER_START + 0.18, TRANSFER_START + 0.68, time) * (1.0 - smoothstep(TRANSFER_CUT - 0.01, TRANSFER_CUT + 0.09, time))
	var diagnostic := receiving * (0.065 + 0.042 * pow(absf(sin(time * 8.4)), 9.0))
	rig.boot_light = smoothstep(WAKE_SHOT + 0.09, WAKE_SHOT + 1.04, time) + diagnostic
	rig.wake_shift = weight * (1.0 - smoothstep(WALK_START - 0.43, WALK_START + 0.52, time))
	rig.wake_gaze = smoothstep(WAKE_SHOT + 0.13, WAKE_SHOT + 0.87, time) * (1.0 - rise)
	rig.blade_power = smoothstep(EYE_SHOT - 0.31, EYE_SHOT + 0.67, time)
	rig.move_command = Vector3.ZERO
	rig.facing_heading = 0.0
	var at := CargoArena.PLAYER_SPAWN
	at.z -= OpeningRig.travel(time - WALK_START)
	var support := smoothstep(CargoArena.PRINT_BED_FRONT - 1.00, CargoArena.PRINT_BED_FRONT + 1.00, at.z)
	at.y = support * CargoArena.PRINT_BED_HEIGHT
	rig.ground_height = at.y
	rig.global_position = at
	rig.advance(dt)


func _pose_printer(dt: float) -> void:
	if _printing and time <= TRANSFER_START + 0.34:
		_machine_passes(dt)
	elif _printing:
		_fx.finish_print()
		_printing = false

	var phase := time - TRANSFER_START
	var loss := smoothstep(TRANSFER_CUT - 0.06, TRANSFER_CUT + 0.11, time)
	var carrier := smoothstep(0.0, 0.31, phase) * (1.0 - loss)
	var interference := loss * (1.0 - smoothstep(TRANSFER_CUT + 0.22, TRANSFER_CUT + 0.51, time))
	_update_readout(phase, carrier, interference)


func _machine_passes(dt: float) -> void:
	var pass_index := PASSES.size() - 1
	for i in PASSES.size():
		if time <= PASSES[i].y:
			pass_index = i
			break
	var window: Vector2 = PASSES[pass_index]
	var u := smoothstep(window.x, window.y, time)
	var location: Vector3 = _fx.sample_seam(pass_index, u)
	var valid := location.is_finite()
	if not valid:
		location = CargoArena.PLAYER_SPAWN + Vector3(0.0, 2.6, 0.0)
	var tool_clearance := 0.12
	var load := smoothstep(window.x, window.x + 0.15, time) * (1.0 - smoothstep(window.y - 0.13, window.y, time))
	if time < window.x:
		var previous_end := 0.0
		var previous := location
		if pass_index > 0:
			previous_end = PASSES[pass_index - 1].y
			var end: Vector3 = _fx.sample_seam(pass_index - 1, 1.0)
			if end.is_finite():
				previous = end
		var cross := smoothstep(previous_end, window.x, time)
		location = previous.lerp(location, cross)
		tool_clearance += 0.62 * (sin(PI * cross) if pass_index > 0 else 1.0 - cross)
	var nozzle := location + Vector3.UP * tool_clearance
	if time >= PASSES[-1].y:
		# Lift clear before moving the gantry down the rails.
		var lift := smoothstep(PASSES[-1].y, PRINT_DONE + 0.17, time)
		var retreat := smoothstep(PRINT_DONE + 0.10, TRANSFER_START + 0.22, time)
		var park := Vector3(CargoArena.PLAYER_SPAWN.x + 2.30, 3.44, 41.64)
		nozzle += Vector3.UP * lift * 0.72
		nozzle = nozzle.lerp(park, retreat)

	var bridge: Node3D = _printer["bridge"]
	var head: Node3D = _printer["head"]
	var optic: Node3D = _printer["optic"]
	var ram: Node3D = _printer["spindle"]
	var lamp: OmniLight3D = _printer["lamp"]
	bridge.position.z = nozzle.z
	head.position.x = nozzle.x - bridge.global_position.x
	optic.position.y = nozzle.y - head.global_position.y + 0.47
	optic.rotation.y = minf(time, PRINT_DONE) * 1.6
	ram.position.y = -0.58
	ram.scale.y = maxf(0.13, ram.position.y - optic.position.y - 0.09)
	var power := load * (0.80 + 0.20 * pow(absf(sin(time * 44.0)), 7.0)) if valid else 0.0
	lamp.light_energy = 0.11 + power * 0.45
	_fx.machine(dt, nozzle, location, power)
	_machining_at = location
	if power > 0.28 and _last_pass != pass_index:
		_last_pass = pass_index
		Snd.play_at("fabricator_contact", location, {"gain": 0.64, "prio": 3})


func _update_readout(phase: float, carrier: float, interference: float) -> void:
	var fabrication: Label3D = _printer["fabrication"]
	var transfer: Label3D = _printer["transfer"]
	var display: ShaderMaterial = _printer["display"]
	var printed := time >= PRINT_DONE
	var dropped := time >= TRANSFER_CUT
	fabrication.text = "完成" if printed else "处理中"
	fabrication.modulate = Color("e0ffff") if printed else Color("acf0f0")
	transfer.text = "中断" if dropped else "接收中"
	transfer.modulate = Color("ffd0c4") if dropped else Color("e7d7ff")
	var finished_segments := 10 + int(time >= PASSES[1].y) + int(printed)
	var held_segments := floorf(minf(maxf(phase, 0.0) * 4.15, 7.0))
	var waiting := smoothstep(1.68, 1.84, phase) * (1.0 - smoothstep(TRANSFER_CUT - 0.03, TRANSFER_CUT + 0.02, time))
	display.set_shader_parameter("printed", float(finished_segments) / 12.0)
	display.set_shader_parameter("received", held_segments / 12.0)
	display.set_shader_parameter("pending", waiting)
	display.set_shader_parameter("carrier", carrier)
	display.set_shader_parameter("fault", interference)
	display.set_shader_parameter("interrupted", 1.0 if dropped else 0.0)


func _shot() -> void:
	var camera := _cam.camera
	var x := CargoArena.PLAYER_SPAWN.x
	var at: Vector3 = _player.rig.global_position
	if time < TRANSFER_START:
		var glide := smoothstep(0.15, TRANSFER_START, time)
		var camera_at := Vector3(x - lerpf(2.92, 2.43, glide),
			lerpf(2.04, 2.94, glide), lerpf(35.30, 36.07, glide))
		camera.fov = lerpf(58.0, 55.0, glide)
		var center := Vector3(x + 0.07, 2.69, 39.1)
		camera.look_at_from_position(camera_at, center.lerp(_machining_at, 0.35))
	elif time < WAKE_SHOT:
		# Hold the instrument long enough to read the failed transfer.
		var screen: Vector3 = _printer["screen"]
		var push := smoothstep(TRANSFER_START, TRANSFER_CUT - 0.15, time)
		var recoil := smoothstep(TRANSFER_CUT, TRANSFER_CUT + 0.26, time)
		var camera_at := screen + Vector3(-3.53 + 0.28 * push - 0.78 * recoil,
			0.18 - 0.12 * recoil, -1.04 + 0.15 * push - 0.36 * recoil)
		camera.fov = 40.0 + 5.0 * recoil
		camera.look_at_from_position(camera_at, screen + Vector3(0, -0.06, 0.0))
	elif time < EYE_SHOT:
		var outside := smoothstep(WALK_START + 0.65, EYE_SHOT - 0.14, time)
		var start := smoothstep(WAKE_SHOT, WALK_START + 0.75, time)
		var camera_at := Vector3(x - lerpf(2.45, 4.31, outside), lerpf(1.92, 2.10, start),
			clampf(at.z - lerpf(3.65, 5.1, outside), 23.52, 35.32))
		camera.fov = lerpf(55.0, 64.0, outside)
		camera.look_at_from_position(camera_at, at + Vector3(0.21, lerpf(2.45, 1.91, start), -0.19))
	else:
		if not _cam.first_person:
			_cam.set_first_person(true)
		var settle := smoothstep(EYE_SHOT, EYE_SHOT + 1.0, time)
		_cam.pitch = lerpf(-0.22, -0.16, settle)
		var eye := _cam.fp_transform()
		eye.origin.y -= 0.18 * (1.0 - settle)
		camera.global_transform = eye
		camera.fov = lerpf(74.0, P.getf("cam.first_fov"), settle)


func _sound() -> void:
	var at: Vector3 = _player.rig.global_position
	if _sound_cue == 0 and time >= 0.14:
		_printer_voice = Snd.play_at("fabricator_servo", at + Vector3.UP * 3.5, {"gain": 0.78, "prio": 3})
		_sound_cue = 1
	elif _sound_cue == 1 and time >= TRANSFER_START:
		_voice = Snd.play_at("fabricator_transfer", _printer["feed_at"], {"gain": 0.70, "prio": 3})
		_sound_cue = 2
	elif _sound_cue == 2 and time >= TRANSFER_CUT:
		Snd.stop(_voice)
		_voice = Snd.play_at("cargo_radio", _printer["screen"], {"gain": 0.68, "prio": 3})
		_sound_cue = 3
	elif _sound_cue == 3 and time >= WAKE_SHOT + 0.52:
		_voice = Snd.play_at("step", at, {"gain": 0.46, "prio": 2})
		_sound_cue = 4

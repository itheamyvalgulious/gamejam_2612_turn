extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TurnSession.open_level(9)
	while TurnSession.active_level_index() != 9 or get_tree().current_scene == null:
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	var player = get_tree().current_scene.get("player")
	var level = get_tree().current_scene.get("level")
	var rig = player.rig
	print("[move] move_speed=%.2f" % rig.move_speed)
	# accelerate from rest toward +X (drive the rig directly; B.move_vector is 0 headless)
	Input.action_press("move_right")
	var speeds := []
	for i in 60:
		player.step(1.0 / 60.0, level.arena, level.enemies)
		await get_tree().physics_frame
		speeds.append(rig._vel_h.length())
	Input.action_release("move_right")
	print("[move] accel profile: ", _fmt(speeds))
	# turn 180 instantly
	Input.action_press("move_left")
	player.step(1.0/60.0, level.arena, level.enemies)
	await get_tree().physics_frame
	print("[move] after 1 frame of 180-turn: speed=%.2f heading=%.2f" % [rig._vel_h.length(), rig.heading])
	var turn_speeds := []
	for i in 12:
		player.step(1.0/60.0, level.arena, level.enemies)
		await get_tree().physics_frame
		turn_speeds.append(rig._vel_h.length())
	print("[move] 180-turn speed profile:", _fmt(turn_speeds))
	Input.action_release("move_left")
	# coast to stop
	for i in 40:
		player.step(1.0/60.0, level.arena, level.enemies)
		await get_tree().physics_frame
	print("[move] after brake: speed=%.2f" % rig._vel_h.length())
	# dash
	rig.request_dash(Vector3(0,0,-1))
	var dspeeds := []
	for i in 30:
		player.step(1.0 / 60.0, level.arena, level.enemies)
		await get_tree().physics_frame
		dspeeds.append(rig._vel_h.length())
		if rig.dash_time <= 0.0 and dspeeds.size() > 8:
			break
	print("[move] dash profile: ", _fmt(dspeeds))
	get_tree().quit()

func _fmt(a: Array) -> String:
	var out := ""
	for i in a.size():
		out += "%.1f " % a[i]
	return out

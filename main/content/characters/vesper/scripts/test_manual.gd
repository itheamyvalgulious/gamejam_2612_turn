extends Node3D
func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var rig = main.rig
	var cam = main.cam_rig
	print("before auto=", main.auto_mode, " pos=", rig.position, " heading=", rig.heading)
	Input.action_press("move_forward")
	await get_tree().create_timer(0.6).timeout
	print("t0.6 auto=", main.auto_mode, " pos=", rig.position, " heading=", rig.heading, " camw=", cam.world_yaw, " camuse=", cam.use_world_yaw)
	await get_tree().create_timer(1.0).timeout
	print("t1.6 pos=", rig.position, " heading=", rig.heading, " camw=", cam.world_yaw)
	await get_tree().create_timer(1.0).timeout
	print("t2.6 pos=", rig.position, " heading=", rig.heading, " camw=", cam.world_yaw)
	Input.action_release("move_forward")
	await get_tree().create_timer(0.5).timeout
	rig.request_jump()
	await get_tree().create_timer(0.5).timeout
	print("jump mid state=", rig.jump_state, " y=", rig.position.y, " loco=", rig.locomotion_state)
	await get_tree().create_timer(1.2).timeout
	print("jump end state=", rig.jump_state, " y=", rig.position.y, " loco=", rig.locomotion_state)
	get_tree().quit()

extends SceneTree

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/character.tscn")
	var ch = ps.instantiate()
	root.add_child(ch)
	await process_frame
	await process_frame
	var ok := true
	print("anims=", ch.anim_names())
	for a in ch.anim_names():
		ch.play_anim(a)
		var d = ch.anim_duration()
		ch.set_playing(false)
		var t = d * 0.5
		ch.set_anim_time(t)
		print("  ", a, " dur=", d, " scrub=", ch.anim_time())
	print("params=", ch.param_specs().size(), " joints=", ch.joint_specs().size())
	ch.set_joint("shoulder_R_pitch", -20.0)
	print("joint shoulder_R_pitch=", ch.get_joint("shoulder_R_pitch"))
	ch.set_param("height", 1.70)
	ch.set_param("module_count", 60)
	ch.set_param("module_size", 0.14)
	print("height=", ch.get_param("height"), " count=", ch.get_param("module_count"), " modules=", ch.field.mods.size())
	ch.play_anim("disperse")
	ch.set_playing(false)
	ch.set_anim_time(ch.anim_duration())
	print("after disperse assembled=", ch.is_assembled(), " state=", ch.field.state_name())
	ch.reform()
	ch.set_playing(false)
	ch.set_anim_time(ch.anim_duration())
	await process_frame
	print("after reform assembled=", ch.is_assembled(), " state=", ch.field.state_name())
	ch.play_anim("attack")
	ch.set_playing(false)
	ch.set_anim_time(0.555)
	await process_frame
	print("attack t=", ch.anim_time(), " shuriken active=", ch.shurikens[0].active, " pos=", ch.shurikens[0].blade.global_position)
	ch.play_anim("idle")
	print("loop idle=", ch.is_looping())
	ch.play_anim("walk")
	print("loop walk=", ch.is_looping())
	ch.play_anim("attack")
	print("loop attack=", ch.is_looping())
	ch.set_playing(true)
	var mid := false
	for i in 600:
		ch._process(1.0 / 60.0)
		if i == 80:
			mid = ch.shurikens[0].active
	var vis := 0
	for s in ch.shurikens:
		if s.active or s.visible:
			vis += 1
	print("attack soak mid_active=", mid, " final_visible=", vis, " shot_age=", ch._shot_age, " t=", ch.anim_time())
	print("debug=", ch.rig_debug())
	print("CONTRACT_TEST_DONE")
	quit(0)

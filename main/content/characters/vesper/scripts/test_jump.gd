extends Node3D
const Rig = preload("res://scripts/mech/mech_rig.gd")
func _ready() -> void:
	var rig = Rig.new()
	add_child(rig)
	rig.auto_step = false
	rig.set_process(false)
	for i in 10:
		rig.advance(1.0 / 60.0)
	rig.request_jump()
	var t := 0.0
	var seen := {}
	var apex := 0.0
	while t < 2.0:
		rig.advance(1.0 / 60.0)
		t += 1.0 / 60.0
		apex = maxf(apex, rig.position.y)
		if not seen.has(rig.jump_state):
			seen[rig.jump_state] = true
			print("STATE ", rig.jump_state, " at ", t, " y=", rig.position.y)
	print("DONE apex=", apex, " final_state=", rig.jump_state, " y=", rig.position.y, " seen=", seen.keys())
	get_tree().quit()

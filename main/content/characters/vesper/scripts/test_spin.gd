extends Node3D
const Rig = preload("res://scripts/mech/mech_rig.gd")
func _ready() -> void:
	var rig = Rig.new()
	add_child(rig)
	rig.auto_step = false
	rig.set_process(false)
	for i in 8:
		rig.advance(1.0 / 60.0)
	rig.request_spin_attack()
	var last := 0.0
	var report := 0.0
	var acc := 0.0
	var t := 0.0
	var min_step := 999.0
	var max_step := 0.0
	print("spin start")
	while t < 1.35:
		rig.advance(1.0 / 60.0)
		t += 1.0 / 60.0
		var y: float = rig.torso.rotation.y
		var d: float = wrapf(y - last, -PI, PI)
		last = y
		if rig.is_attacking:
			acc += d
			min_step = minf(min_step, absf(d))
			max_step = maxf(max_step, absf(d))
		report += 1.0 / 60.0
		if report >= 0.07:
			report = 0.0
			print("t=%.3f atk=%.3f y=%.3f d=%.4f state=%s" % [t, rig.attack_time, y, d, rig.attack_name])
	print("total rotated=%.3f min_step=%.4f max_step=%.4f final=%s" % [acc, min_step, max_step, rig.jump_state])
	get_tree().quit()

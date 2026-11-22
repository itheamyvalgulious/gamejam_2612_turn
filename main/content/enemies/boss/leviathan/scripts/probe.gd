extends Node3D
## Fast visual probe for iteration. Not part of the deliverable UI.
## Env: PROBE_VIEW, PROBE_SNAP, PROBE_STEPS, PROBE_PHASE, PROBE_ROLES,
##      PROBE_ATTACK, PROBE_FRAME, PROBE_TARGET, PROBE_CAM

const STUDIO := preload("res://scenes/studio.tscn")
var studio


func _ready() -> void:
	studio = STUDIO.instantiate()
	add_child(studio)
	await _frames(5)
	studio.ui_root.visible = false
	studio._shot_mode = true
	if studio._overlay:
		studio._overlay.visible = false
	var b = studio.boss
	b.manual = true
	b.set_auto(false)
	b.set_target(studio.dummy.chest_world(), studio.dummy.ground_world())
	var roles := OS.get_environment("PROBE_ROLES")
	if roles == "idle_all":
		for i in 8:
			b.force_role(i, "idle")
	elif roles == "support5":
		for i in 8:
			b.force_role(i, "support" if i < 5 else "idle")
	elif roles == "support5b":
		for i in 8:
			b.force_role(i, "idle")
		for i in 5:
			b.force_role(i, "support")
	elif roles == "mix":
		for i in 8:
			var r := "support" if i in [0, 2, 4] else "idle"
			b.force_role(i, r)
	elif roles == "attack1":
		for i in 8:
			b.force_role(i, "idle")
		b.force_role(2, "attack1")
	elif roles == "attack2":
		for i in 8:
			b.force_role(i, "idle")
		b.force_role(2, "attack2")
	elif roles == "attack3":
		for i in 8:
			b.force_role(i, "idle")
		b.force_role(2, "attack3")
	elif roles == "cut":
		for i in 8:
			b.force_role(i, "idle")
		b.cut_tentacle(0)
	elif roles == "fallen":
		for i in 8:
			b.force_role(i, "idle")
		for i in 6:
			for j in 8:
				if b.cut_tentacle(j):
					break
			for j in 22:
				b.sim_step(1.0 / 60.0)
	var tg := OS.get_environment("PROBE_TARGET")
	if tg != "":
		var p := tg.split(",")
		if p.size() == 3:
			studio.dummy.set_target_pos(Vector3(float(p[0]), float(p[1]), float(p[2])))
			b.set_target(studio.dummy.chest_world(), studio.dummy.ground_world())
	var ph := OS.get_environment("PROBE_PHASE")
	if ph != "":
		b.set_phase_force(int(ph))
		if int(ph) == 2:
			b.fire_laser()
	var steps := int(OS.get_environment("PROBE_STEPS"))
	if steps <= 0:
		steps = 60
	for i in steps:
		b.sim_step(1.0 / 60.0)
	if OS.get_environment("PROBE_LASER") == "1":
		b.fire_laser()
		for i in 68:
			b.sim_step(1.0 / 60.0)
	var hide := OS.get_environment("PROBE_HIDE")
	if hide == "tent":
		for tn in b.tents:
			tn.root.visible = false
	elif hide == "blades":
		for bl in b.rig.blade_nodes:
			bl.visible = false
	elif hide == "eye":
		b.rig.eye_yaw.visible = false
	elif hide == "core":
		b.rig.orb_mi.visible = false
		b.rig.core_mi.visible = false
		b.rig.glass_mi.visible = false
	elif hide == "orb":
		b.rig.orb_mi.visible = false
		b.rig.orb_outer_mi.visible = false
	elif hide == "coreonly":
		b.rig.core_mi.visible = false
	elif hide == "glass":
		b.rig.glass_mi.visible = false

	var cam := OS.get_environment("PROBE_VIEW")
	match cam:
		"front":
			studio.set_view(0, 5, 24, Vector3(0, 5.6, 1.0))
		"side":
			studio.set_view(90, 6, 26, Vector3(0, 5.4, 1.0))
		"back":
			studio.set_view(180, 8, 26, Vector3(0, 5.4, 0.0))
		"eye":
			studio.set_view(8, 8, 10.0, Vector3(0, 6.0, 2.2))
		"low":
			studio.set_view(22, -4, 30, Vector3(0, 3.6, 1.0))
		"top":
			studio.set_view(18, 58, 28, Vector3(0, 3.0, 1.0))
		"attack":
			studio.set_view(88, 9, 30, Vector3(0, 3.4, 5.5))
		"hero":
			studio.set_view(30, 11, 32, Vector3(0, 5.0, 2.0))
		"wide":
			studio.set_view(24, 12, 38, Vector3(0, 5.0, 3.0))
		"wide2":
			studio.set_view(26, 12, 40, Vector3(0, 5.0, 0.5))
		"sweep":
			studio.set_view(30, 30, 40, Vector3(0, 3.0, 0.5))
		"socket":
			studio.set_view(14, 2, 10.5, Vector3(0, 4.4, 1.8))
		"socket2":
			studio.set_view(58, 6, 9.0, Vector3(0, 4.4, 1.4))
		"fx":
			studio.set_view(30, 4, 16.0, Vector3(5.5, 3.2, 5.5))
		_:
			studio.set_view(30, 11, 32, Vector3(0, 5.0, 2.0))
	await _frames(4)
	var snap_path := OS.get_environment("PROBE_SNAP")
	if snap_path == "":
		snap_path = "/tmp/opencode/boss_shots/probe.png"
	DirAccess.make_dir_recursive_absolute(snap_path.get_base_dir())
	await studio.snap(snap_path)
	print("[probe] phase=%d shell=%.2f live=%d roles=%s" % [b.phase, b.shell_t, b.live,
		str(b.role_counts())])
	print("[probe] p2=%.2f orb vis=%s scale=%s core vis=%s scale=%s energy=%.1f light=%.1f glass=%s opacity=%.2f" % [
		b.phase2_t, str(b.rig.orb_mi.visible), str(b.rig.orb_mi.scale),
		str(b.rig.core_mi.visible), str(b.rig.core_mi.scale),
		float(b.rig.core_mat.get_shader_parameter("energy")),
		b.rig.core_light.light_energy, str(b.rig.glass_mi.visible),
		float(b.rig.glass_mat.get_shader_parameter("opacity"))])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
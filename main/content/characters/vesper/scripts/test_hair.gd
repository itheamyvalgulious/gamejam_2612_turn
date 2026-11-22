extends Node3D
## Hair self-test — proxy head, 240 fixed steps with an 8 m/s translation and a
## full 360 degree turn.  Prints three tips every 60 frames and verifies that
## the spring chains actually lag behind the head (local displacement > 0.08 m)
## with no NaNs.
##
## Run: godot --headless --path . res://scenes/test_hair.tscn
## Optional still: HAIR_SHOT=/tmp/opencode/hair.png xvfb-run -a godot --path . res://scenes/test_hair.tscn

const Hair = preload("res://scripts/mech/hair.gd")
const DT := 1.0 / 60.0
const FRAMES := 240

class TestRig extends Node3D:
	var speed := 0.0
	var is_attacking := false
	var dash_time := 0.0
	var attack_time := 0.0

var rig: TestRig
var head: Node3D
var hair
var cam: Camera3D
var rest_local: Array[Vector3] = []
var max_disp: Array[float] = [0.0, 0.0, 0.0]
var all_disp: Array[float] = []
var sampled := [0, 60, 120, 180, 240]
var nans := 0


func _ready() -> void:
	Engine.max_fps = 60
	get_window().size = Vector2i(960, 720)
	_build_stage()
	_build_head()
	hair = Hair.new()
	hair.name = "Hair"
	head.add_child(hair)
	hair.setup(head, {})
	hair.set_wind(Vector3(0.12, 0.0, -0.08))
	hair.update(0.0, rig)
	rest_local = _local_tips()

	var n_strands: int = hair._strands.size()
	all_disp.resize(n_strands)
	for i in n_strands:
		all_disp[i] = 0.0
	print("HAIR strands=%d bones=%d settings=%d joints=%d tips=%d" % [
		n_strands, hair._skeleton.get_bone_count(),
		hair._sim.get_setting_count(), hair._sim.get_joint_count(0),
		hair.get_tip_positions().size()])
	print("REST local tips: %s %s %s" % [_fmt(rest_local[0]), _fmt(rest_local[1]), _fmt(rest_local[2])])
	var roots := []
	var tips_x := []
	for i in hair._strands.size():
		var pts: PackedVector3Array = hair._strands[i]["points"]
		roots.append(pts[0].x)
		tips_x.append(pts[8].x)
	roots.sort()
	tips_x.sort()
	print("ROOTS x %.3f..%.3f  TIPS x %.3f..%.3f  n=%d" % [roots[0], roots[-1], tips_x[0], tips_x[-1], roots.size()])

	# one clean frame so the modifier pass has run before the stress loop
	hair.update(DT, rig)
	await get_tree().process_frame

	var t := 0.0
	var last_report := 0
	for f in FRAMES:
		t += DT
		# 8 m/s forward, one full turn over the four seconds
		rig.position = Vector3(0.0, 0.0, -8.0 * t)
		rig.rotation.y = TAU * (t / (DT * float(FRAMES)))
		rig.speed = 8.0
		hair.update(DT, rig)
		await get_tree().process_frame

		var tips: Array = hair.get_tip_positions()
		if tips.size() != hair._strands.size():
			print("FAIL tip count ", tips.size())
			get_tree().quit(1)
			return
		for i in tips.size():
			if not _finite(tips[i]):
				nans += 1
				print("NAN at frame %d tip %d: %s" % [f, i, tips[i]])
		for i in tips.size():
			var local := _to_head_local(tips[i])
			all_disp[i] = maxf(all_disp[i], local.distance_to(rest_local[i]))
		for k in 3:
			var p: Vector3 = tips[k * 13]
			var local := _to_head_local(p)
			max_disp[k] = maxf(max_disp[k], local.distance_to(rest_local[k * 13]))

		if f + 1 in sampled:
			var all_tips: Array = hair.get_tip_positions()
			var tips3 := [all_tips[0], all_tips[21], all_tips[43]]
			var lines := ""
			for k in 3:
				lines += " tip%d=%s rel=%.3f" % [k, _fmt(tips3[k]), _to_head_local(tips3[k]).distance_to(rest_local[k * 2])]
			print("FRAME %3d world=%s%s" % [f + 1, _fmt(tips3[0]), lines])

	var shifted := 0
	for d in all_disp:
		if d > 0.03:
			shifted += 1
	print("MAX relative tip displacement: %.3f / %.3f / %.3f m" % max_disp)
	print("TIPS shifted > 0.03 m: %d / %d" % [shifted, all_disp.size()])
	var ok := nans == 0 and all_disp.size() >= 44 and shifted >= 44
	for d in max_disp:
		if d <= 0.08:
			ok = false
	print("BONE CHECK strand0 joints:")
	for i in 8:
		var gp: Transform3D = hair._skeleton.get_bone_global_pose(hair._strands[0]["bones"][i])
		print("  j%d local=%s" % [i, _fmt(gp.origin)])
	print("HAIR TEST ", "PASS" if ok else "FAIL")

	var shot := OS.get_environment("HAIR_SHOT")
	if shot != "":
		await _capture(shot)
	get_tree().quit(0 if ok else 1)


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.018, 0.032)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.30, 0.48)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.15
	we.environment = env
	add_child(we)

	var key := OmniLight3D.new()
	key.light_color = Color(0.70, 0.85, 1.0)
	key.light_energy = 2.2
	key.omni_range = 4.0
	key.position = Vector3(1.2, 2.5, 1.3)
	add_child(key)

	var rim := OmniLight3D.new()
	rim.light_color = Color(0.25, 0.45, 1.0)
	rim.light_energy = 2.5
	rim.omni_range = 3.0
	rim.position = Vector3(-1.4, 2.2, 1.6)
	add_child(rim)

	rig = TestRig.new()
	rig.name = "Rig"
	add_child(rig)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 1.872, -0.004)
	rig.add_child(head)

	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 34.0
	cam.near = 0.04
	cam.far = 60.0
	cam.position = Vector3(1.45, 0.62, 1.55)
	rig.add_child(cam)
	cam.look_at_from_position(cam.position, head.position + Vector3(0.0, 0.06, 0.0), Vector3.UP)


func _build_head() -> void:
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.092
	sm.height = 0.185
	sm.radial_segments = 24
	sm.rings = 12
	shell.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.045, 0.055, 0.075)
	mat.metallic = 0.7
	mat.roughness = 0.35
	shell.material_override = mat
	shell.position = Vector3(0.0, 0.040, 0.006)
	shell.scale = Vector3(1.0, 1.08, 1.02)
	head.add_child(shell)

	var face := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.145, 0.095, 0.035)
	face.mesh = bm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.075, 0.10, 0.17)
	fmat.metallic = 0.6
	fmat.roughness = 0.25
	face.material_override = fmat
	face.position = Vector3(0.0, 0.030, -0.088)
	head.add_child(face)

	var visor := MeshInstance3D.new()
	var vbm := BoxMesh.new()
	vbm.size = Vector3(0.112, 0.013, 0.012)
	visor.mesh = vbm
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.25, 0.72, 1.0)
	vmat.emission_enabled = true
	vmat.emission = Color(0.25, 0.70, 1.0)
	vmat.emission_energy_multiplier = 4.0
	visor.material_override = vmat
	visor.position = Vector3(0.0, 0.062, -0.108)
	head.add_child(visor)

	# asymmetric camera pod on +X, matching the real helmet
	var pod := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.030
	pm.bottom_radius = 0.030
	pm.height = 0.05
	pod.mesh = pm
	pod.material_override = mat
	pod.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	pod.position = Vector3(0.098, 0.052, -0.030)
	head.add_child(pod)

	# crown shell at the hair anchor
	var crown := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.115, 0.035, 0.10)
	crown.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.09, 0.12, 0.19)
	cmat.metallic = 0.65
	cmat.roughness = 0.3
	crown.material_override = cmat
	crown.position = Vector3(0.0, 0.165, 0.018)
	crown.rotation_degrees = Vector3(10.0, 0.0, 0.0)
	head.add_child(crown)


func _to_head_local(p: Vector3) -> Vector3:
	return head.global_transform.affine_inverse() * p


func _local_tips() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in hair.get_tip_positions():
		out.append(_to_head_local(p))
	return out


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _fmt(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _capture(path: String) -> void:
	# settle at a calm pose, then save three stills for eyeballing
	rig.position = Vector3.ZERO
	rig.rotation.y = 0.0
	rig.speed = 0.0
	hair.reset_sim()
	for i in 110:
		hair.update(DT, rig)
		await get_tree().process_frame

	var view_target := head.position + Vector3(0.0, 0.02, 0.0)
	var views := [
		["front", Vector3(0.92, 0.42, -1.02)],
		["side", Vector3(1.25, 0.42, 0.18)],
		["back", Vector3(0.12, 0.42, 1.35)],
	]
	var out := path.get_basename()
	for view in views:
		cam.position = view[1]
		cam.look_at_from_position(cam.position, view_target, Vector3.UP)
		hair.update(DT, rig)
		await get_tree().process_frame
		hair.update(DT, rig)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := "%s_%s.png" % [out, view[0]]
		img.save_png(p)
		print("SHOT ", p, " ", img.get_width(), "x", img.get_height())
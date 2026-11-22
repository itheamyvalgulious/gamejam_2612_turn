extends Node3D

const RenderPath = preload("res://scripts/render_path.gd")

const Rig = preload("res://scripts/mech/mech_rig.gd")
const Arena = preload("res://scripts/world/arena.gd")
var rig
var cam

func _ready() -> void:
	add_child(Arena.new())
	rig = Rig.new()
	add_child(rig)
	rig.auto_step = false
	rig.set_process(false)
	for i in 10:
		rig.advance(1.0 / 60.0)
	cam = Camera3D.new()
	cam.fov = 36.0
	add_child(cam)
	var shots := [
		["cine_hero", Vector3(5.8, 2.9, -9.6), Vector3(0, 3.0, 0), 39.0],
		["cine_close", Vector3(2.2, 1.7, -3.8), Vector3(0, 1.25, 0), 32.0],
		["cine_low", Vector3(5.2, 1.35, -8.2), Vector3(0, 2.8, 0), 42.0],
		["cine_back", Vector3(-4.2, 2.3, 5.9), Vector3(0, 1.25, 0), 40.0],
	]
	for shot in shots:
		cam.position = shot[1]
		cam.fov = shot[3]
		cam.look_at(shot[2])
		for i in 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(RenderPath.file("%s.png" % shot[0]))
	print("CINE DONE")
	get_tree().quit()
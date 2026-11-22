extends Node3D

## Deterministic still renderer: drives the showcase at a fixed 60 Hz, then
## saves specific beats at full resolution.  No realtime dependence.

const RenderPath = preload("res://scripts/render_path.gd")
const Arena = preload("res://scripts/world/arena.gd")
const Rig = preload("res://scripts/mech/mech_rig.gd")
const CameraRig = preload("res://scripts/world/camera_rig.gd")
const HUD = preload("res://scripts/world/hud.gd")
const Showcase = preload("res://scripts/world/showcase.gd")

var arena
var rig
var cam
var hud
var director
var sim_t := 0.0

const SHOTS := [
	["intro", 1.50],
	["walk", 3.40],
	["sprint", 6.00],
	["front_r", 8.02],
	["front_l", 8.76],
	["rise_r", 9.49],
	["rise_l", 10.22],
	["side", 11.36],
	["back", 12.78],
	["heavy_raise", 14.26],
	["heavy_apex", 14.40],
	["heavy_hit", 14.51],
	["spin", 16.50],
	["spin_late", 16.90],
	["dash_lateral", 18.46],
	["dash", 19.26],
	["takeoff", 20.06],
	["jump", 20.30],
	["land", 20.90],
	["hero", 22.00],
	["hero_late", 23.40],
]


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	arena = Arena.new()
	add_child(arena)
	rig = Rig.new()
	rig.auto_step = false
	add_child(rig)
	rig.set_process(false)
	cam = CameraRig.new()
	cam.target = rig
	add_child(cam)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = HUD.new()
	layer.add_child(hud)
	hud.set_rig(rig)
	hud.set_process(false)
	director = Showcase.new()
	director.setup(rig, cam, hud)
	director.reset()
	rig.footstep.connect(_on_footstep)
	rig.impact.connect(_on_impact)
	await get_tree().process_frame
	await get_tree().process_frame
	# warm up one frame so the HUD has a valid size
	for i in 2:
		_step(1.0 / 60.0)

	for shot in SHOTS:
		await _advance_to(shot[1])
		hud.queue_redraw()
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(RenderPath.file("still_%s.png" % shot[0]))
		print("STILL ", shot[0], " t=", sim_t)
	# extra gallery views while the mech is idle at the stage centre
	cam.set_shot(-0.55, 6.0, 2.05, 1.25, 39.0, false)
	cam.snap()
	for i in 8:
		cam.update_camera(1.0 / 60.0, 0.0)
	await _capture("back")
	cam.set_shot(-2.55, 5.2, 6.9, 1.2, 44.0, false)
	cam.snap()
	for i in 8:
		cam.update_camera(1.0 / 60.0, 0.0)
	await _capture("top")
	get_tree().quit()


func _capture(name: String) -> void:
	hud.queue_redraw()
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(RenderPath.file("still_%s.png" % name))
	print("EXTRA ", name)


func _step(dt: float) -> void:
	director.update(dt)
	rig.advance(dt)
	cam.update_camera(dt, rig.speed)
	hud.step(dt)
	sim_t += dt


func _advance_to(target: float) -> void:
	while sim_t < target - 0.0001:
		_step(1.0 / 60.0)
		if int(sim_t * 60.0) % 2 == 0:
			await get_tree().process_frame


func _on_footstep(_pos: Vector3, strength: float) -> void:
	cam.add_shake(0.02 * strength)


func _on_impact(_pos: Vector3, strength: float) -> void:
	cam.add_shake(0.45 * strength)
	hud.flash(0.55 * strength)
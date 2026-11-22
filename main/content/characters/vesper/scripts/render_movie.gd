extends Node3D
## Deterministic 30 fps showreel renderer.  Steps the whole game at 1/30 s,
## captures the viewport, and writes numbered JPEG frames for ffmpeg.

const Arena = preload("res://scripts/world/arena.gd")
const Rig = preload("res://scripts/mech/mech_rig.gd")
const CameraRig = preload("res://scripts/world/camera_rig.gd")
const HUD = preload("res://scripts/world/hud.gd")
const Showcase = preload("res://scripts/world/showcase.gd")
const RenderPath = preload("res://scripts/render_path.gd")

const FPS := 60
const SECONDS := 24.0
const OUT := "movie"

var rig
var cam
var hud
var director
var frames := 0
var start_t := 0.0
var seconds := 24.0
var out_dir := RenderPath.dir().path_join(OUT)

func _ready() -> void:
	if OS.get_environment("MOVIE_START") != "":
		start_t = float(OS.get_environment("MOVIE_START"))
	if OS.get_environment("MOVIE_SECONDS") != "":
		seconds = float(OS.get_environment("MOVIE_SECONDS"))
	if OS.get_environment("MOVIE_OUT") != "":
		out_dir = RenderPath.resolve(OS.get_environment("MOVIE_OUT"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	add_child(Arena.new())
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
	hud.text_outline = false
	hud.set_process(false)
	director = Showcase.new()
	director.setup(rig, cam, hud)
	director.reset()
	rig.footstep.connect(_on_footstep)
	rig.impact.connect(_on_impact)
	await get_tree().process_frame
	await get_tree().process_frame

	var total := int(FPS * seconds)
	var dt := 1.0 / float(FPS)
	for i in int(start_t * FPS):
		director.update(dt)
		rig.advance(dt)
		cam.update_camera(dt, rig.speed)
		hud.step(dt)
	var last_report := 0
	for i in total:
		director.update(dt)
		rig.advance(dt)
		cam.update_camera(dt, rig.speed)
		hud.step(dt)
		hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_jpg("%s/frame_%04d.jpg" % [out_dir, i], 0.92)
		frames += 1
		if i - last_report >= 30:
			last_report = i
			print("FRAME ", i, " / ", total)
	print("MOVIE DONE ", frames)
	get_tree().quit()

func _on_footstep(_pos: Vector3, strength: float) -> void:
	cam.add_shake(0.018 * strength)

func _on_impact(_pos: Vector3, strength: float) -> void:
	cam.add_shake(0.42 * strength)
	hud.flash(0.5 * strength)

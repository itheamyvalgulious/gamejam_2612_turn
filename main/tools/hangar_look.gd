extends Node3D
const Arena = preload("res://runtime/levels/hangar/arena/hangar_arena.gd")
const StaticBatch = preload("res://core/static_batch.gd")
const U := 1.0 / 0.547

var cam: Camera3D


func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 760)
	get_window().always_on_top = true
	var arena: Dictionary = Arena.build(Vector3.ZERO)
	add_child(arena["node"])
	StaticBatch.apply(arena["node"])
	cam = Camera3D.new()
	cam.fov = 66.0
	cam.near = 0.05
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute("res://build/hangar_shots")

	await _shot(Vector3(2.92, 10.44, 27.94), Vector3(2.92, 10.20, 25.0), "h_booth_wall")
	await _shot(Vector3(3.40, 10.40, 27.40), Vector3(2.00, 10.40, 26.0), "h_booth_corner")
	await _shot(Vector3(10.0, 14.0, 18.0), Vector3(4.0, 10.0, 28.0), "h_booth_ctx")
	get_tree().quit()


func _shot(p: Vector3, t: Vector3, name: String) -> void:
	cam.global_position = p * U
	cam.look_at(t * U, Vector3.UP)
	for i in 6:
		await get_tree().process_frame
	RenderingServer.force_draw(true)
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/hangar_shots/%s.png" % name)
	print("shot ", name)

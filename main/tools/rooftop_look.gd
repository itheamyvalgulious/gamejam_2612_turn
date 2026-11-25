extends Node3D
## 临时取景：楼顶样段的三张自检图（不会进仓库）

const Arena = preload("res://runtime/levels/rooftop/arena/rooftop_arena.gd")
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
	print("cover=%d platforms=%d" % [arena["cover"].size(), arena["platforms"].size()])
	cam = Camera3D.new()
	cam.fov = 66.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute("res://build/hangar_shots")

	await _shot(Vector3(40.0, 5.10, 4.0), Vector3(50.0, 5.10, 4.0), "h_tower_app")
	await _shot(Vector3(44.0, 3.60, 4.0), Vector3(50.0, 3.90, 4.0), "h_tower_gap")
	await _shot(Vector3(50.0, 6.60, 4.0), Vector3(50.0, 4.20, 4.0), "h_tower_top")
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

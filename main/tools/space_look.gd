extends Node3D
## 临时取景：轨道船背的自检图（不会进游戏）。

const Arena = preload("res://runtime/levels/space_hull/arena/space_hull_arena.gd")
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
	print("cover=%d platforms=%d gates=%d" % [arena["cover"].size(), arena["platforms"].size(), arena["gates"].size()])
	cam = Camera3D.new()
	cam.fov = 66.0
	cam.near = 0.05
	cam.far = 6000.0
	add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute("res://build/space_shots")

	await _shot(Vector3(70.0, 55.0, -340.0), Vector3(100.0, -6.0, 0.0), "s_overview")
	await _shot(Vector3(300.0, 55.0, -230.0), Vector3(150.0, -5.0, 0.0), "s_overview_bow")
	await _shot(Vector3(-3.0, 5.94, 0.0), Vector3(30.0, 5.4, 0.0), "s_start")
	await _shot(Vector3(2.0, 6.0, 7.0), Vector3(-7.0, 8.2, 0.0), "s_breach")
	await _shot(Vector3(11.0, 6.4, 11.0), Vector3(29.0, 5.4, 0.0), "s_arena_a")
	await _shot(Vector3(33.0, 5.94, 0.0), Vector3(80.0, 5.0, 0.0), "s_transit_1")
	await _shot(Vector3(84.0, 6.4, 9.0), Vector3(110.0, 5.4, 0.0), "s_arena_b")
	await _shot(Vector3(114.0, 5.94, 0.0), Vector3(160.0, 5.0, 0.0), "s_transit_2")
	await _shot(Vector3(164.0, 6.4, 14.0), Vector3(190.0, 9.0, 0.0), "s_arena_c")
	await _shot(Vector3(181.0, 6.0, 2.0), Vector3(190.0, 8.0, 0.0), "s_door")
	await _shot(Vector3(24.0, 7.0, -1.0), Vector3(28.0, 6.0, 6.0), "s_turret")
	await _shot(Vector3(25.0, 6.6, 2.0), Vector3(31.0, 5.2, 0.0), "s_gate")
	await _shot(Vector3(100.0, 6.0, -7.5), Vector3(850.0, -150.0, -300.0), "s_earth")
	await _shot(Vector3(100.0, 20.0, -70.0), Vector3(700.0, -250.0, -300.0), "s_earth_wide")
	get_tree().quit()


func _shot(p: Vector3, t: Vector3, name: String) -> void:
	cam.global_position = p * U
	cam.look_at(t * U, Vector3.UP)
	for i in 6:
		await get_tree().process_frame
	RenderingServer.force_draw(true)
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://build/space_shots/%s.png" % name)
	print("shot ", name)

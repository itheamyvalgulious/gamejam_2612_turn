extends Node3D

const RenderPath = preload("res://scripts/render_path.gd")


func _ready() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(RenderPath.file("main_3s.png"))
	print("SHOT1")
	await get_tree().create_timer(6.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(RenderPath.file("main_9s.png"))
	print("SHOT2")
	get_tree().quit()

extends Node3D

var world: World
var xray := false
var cutaway := false
var hud_on := true

func _ready() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_H:
				hud_on = not hud_on
				if world.hud:
					world.hud.visible = hud_on
			KEY_P:
				var img := get_viewport().get_texture().get_image()
				var path := "user://screenshot_%d.png" % Time.get_unix_time_from_system()
				img.save_png(path)
				print("saved ", path)
extends SceneTree
## Offline arc mesh bake. Combat only reads the resulting resource.

const Field = preload("res://scripts/ch/arc_field.gd")
const Ribbon = preload("res://scripts/ch/arc_bolt.gd")
const OUTPUT := "res://assets/vfx/arc_ribbon_variants.res"
const VARIANT_COUNT := 100
const BLADE_LAYERS := 3


func _initialize() -> void:
	var field := Field.new()
	field.blade_scale = 1.0
	var ribbon := Ribbon.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x41524332
	var library := MeshLibrary.new()
	var vertex_total := 0
	for index in VARIANT_COUNT:
		var edges: Array = []
		for layer in BLADE_LAYERS:
			_append_arcs(edges, field.grow(rng, 0.80), rng.randf_range(0.74, 0.92))
		for spark in rng.randi_range(11, 16):
			_append_arcs(edges, field.grow_escape_one(rng), rng.randf_range(0.42, 0.62))
		var mesh := ribbon.build(edges, rng)
		library.create_item(index)
		library.set_item_mesh(index, mesh)
		vertex_total += mesh.surface_get_array_len(0)
	var directory := ProjectSettings.globalize_path(OUTPUT.get_base_dir())
	var status := DirAccess.make_dir_recursive_absolute(directory)
	if status == OK:
		status = ResourceSaver.save(library, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	if status != OK:
		printerr("Failed to save arc variants: ", error_string(status))
		quit(1)
		return
	print("Baked ", library.get_item_list().size(), " arc variants, ", vertex_total, " vertices.")
	quit()


func _append_arcs(destination: Array, edges: Array, intensity: float) -> void:
	for edge: Dictionary in edges:
		edge["energy"] *= intensity
	destination.append_array(edges)

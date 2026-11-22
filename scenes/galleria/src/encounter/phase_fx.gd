extends Node3D
## Simulated by the level clock, so pause/hitstop also pause the phase animation.
const Art = preload("res://src/encounter/arena.gd")
var age := 0.0
var rings: Array[MeshInstance3D] = []
var beams: Array[MeshInstance3D] = []
var material: StandardMaterial3D

func setup(from: Vector3, to: Vector3) -> void:
	material = Art.glow(Color("70e9ff"), 5.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for pos in [from, to]:
		for i in 3:
			var ring := MeshInstance3D.new()
			var mesh := TorusMesh.new()
			mesh.inner_radius = 1.55
			mesh.outer_radius = 1.62
			mesh.rings = 40
			mesh.ring_segments = 8
			ring.mesh = mesh
			ring.material_override = material
			ring.position = pos + Vector3(0, 0.2 + i*1.4, 0)
			add_child(ring)
			rings.append(ring)
		for i in 8:
			var angle := TAU * i / 8.0
			var base: Vector3 = pos + Vector3(cos(angle)*1.6, 0.1, sin(angle)*1.6)
			beam(base, base + Vector3(0, 4.6, 0), 0.025)
	# Raised transit arc clears the 6 m containers and stays below the ceiling.
	var a := from + Vector3(0, 7.5, 0)
	var b := to + Vector3(0, 7.5, 0)
	beam(from + Vector3(0, 2.5, 0), a, 0.04)
	beam(a, b, 0.055)
	beam(b, to + Vector3(0, 2.5, 0), 0.04)

func beam(a: Vector3, b: Vector3, radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 8
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	var direction := (b-a).normalized()
	var right := direction.cross(Vector3.FORWARD).normalized()
	if right.length_squared() < 0.01:
		right = direction.cross(Vector3.UP).normalized()
	instance.transform = Transform3D(Basis(right, direction, right.cross(direction)), (a+b)*0.5)
	add_child(instance)
	beams.append(instance)

func advance(dt: float) -> void:
	age += dt
	var fade := clampf(1.0-age/0.46, 0, 1)
	material.albedo_color.a = fade
	material.emission_energy_multiplier = 5.0 * fade
	for i in rings.size():
		rings[i].position.y = 0.15 + fmod(age*12.0 + (i%3)*1.4, 4.8)
		rings[i].scale = Vector3.ONE * (1.0+age*0.55)
	if age >= 0.46:
		queue_free()

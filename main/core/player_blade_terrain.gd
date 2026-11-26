extends "res://core/blade_terrain.gd"
## Connects the shared terrain sweep to the player's rig and combat effects.

const BLADE_WALL_LAYER := 1 << 15
const PLAYER_MASK := TERRAIN_MASK | BLADE_WALL_LAYER
const WALL_DEPTH := 0.24


func _init() -> void:
	super._init()
	_query.collision_mask = PLAYER_MASK


func begin_player_step(rig) -> void:
	if recovering and rig.is_attacking:
		rig.stop_terrain_swing()


func advance_player(rig, dt: float, serial: int, sound: Node, fx: Node) -> void:
	var authored: Transform3D = rig.weapon_spin.global_transform
	var shoulder: Vector3 = rig.arms[0]["shoulder"].global_position
	var strike := serial if rig.is_attacking else -1
	var pose := advance(rig.get_world_3d().direct_space_state, authored, rig.blade_span(), shoulder, dt, strike)
	rig.weapon_xf = authored
	if recovering or not pose.is_equal_approx(authored):
		rig.apply_terrain_blade(pose, shoulder_recoil())
	rig.update_terrain_trail(dt, recovering)
	if impact.is_empty():
		return
	var point: Vector3 = impact["point"]
	var strength: float = impact["strength"]
	sound.play_at("clang", point, {"gain": lerpf(0.46, 0.96, strength)})
	fx.spark(point, impact["normal"], lerpf(0.38, 0.95, strength))
	fx.shake(0.22 * strength)


func allows_hit(rig, contact: Dictionary) -> bool:
	var at: float = contact.get("t", 1.0)
	var hilt: Vector3 = rig.weapon_prev_xf.origin.lerp(rig.weapon_xf.origin, at)
	var space: PhysicsDirectSpaceState3D = rig.get_world_3d().direct_space_state
	var point: Vector3 = contact["point"]
	return _segment_clear(space, hilt, contact.get("blade_point", point)) and _segment_clear(space, hilt, point)


static func _segment_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	if from.is_equal_approx(to):
		return true
	var ray := PhysicsRayQueryParameters3D.create(from, to, PLAYER_MASK)
	ray.hit_from_inside = true
	return space.intersect_ray(ray).is_empty()


static func install_arena_walls(arena: Dictionary) -> void:
	var root: Node3D = arena["node"]
	var body := StaticBody3D.new()
	body.name = "PlayerBladeWalls"
	# These arenas resolve movement using wall segments. Use the same geometry
	# for the blade without adding walls to the other physics systems.
	body.collision_layer = BLADE_WALL_LAYER
	body.collision_mask = 0
	for wall: Dictionary in arena["walls"]:
		var a: Vector2 = wall["a"]
		var b: Vector2 = wall["b"]
		var edge := b - a
		var base: float = wall.get("base_y", arena.get("floor_y", 0.0))
		var height: float = wall["h"] - base
		if edge.length_squared() < 0.0001 or height <= 0.0:
			continue
		var inward: Vector2 = wall["n"]
		var center := (a + b) * 0.5 - inward * (WALL_DEPTH * 0.5)
		_add_box(body, Vector3(center.x, base + height * 0.5, center.y),
			Vector3(edge.length(), height, WALL_DEPTH), -edge.angle())
	for box: AABB in arena.get("blade_boxes", []):
		_add_box(body, box.get_center(), box.size)
	var dimensions: Vector2 = arena.get("blade_center_cylinder", Vector2.ZERO)
	if dimensions.x > 0.0:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = dimensions.x
		cylinder.height = dimensions.y
		var volume := CollisionShape3D.new()
		volume.shape = cylinder
		volume.position.y = dimensions.y * 0.5
		body.add_child(volume)
	root.add_child(body)


static func _add_box(body: StaticBody3D, center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var volume := CollisionShape3D.new()
	volume.shape = box
	volume.position = center
	volume.rotation.y = yaw
	body.add_child(volume)

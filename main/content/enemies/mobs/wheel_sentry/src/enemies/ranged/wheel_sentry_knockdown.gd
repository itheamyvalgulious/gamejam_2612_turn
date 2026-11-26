extends RefCounted
## A brief attempt to stay upright precedes the rim catch and chassis impact.

const WreckBody = preload("res://src/enemies/ranged/wheel_sentry_wreck_body.gd")
const BROKEN_AT := 0.060
const RIM_CATCH_AT := 0.35
const RIM_CATCH_ANGLE := 0.23
const TURRET_CENTER := Vector3(0, 0.29, 0.01)
const MUZZLE_CENTER := Vector3(0, 0.17, -1.24)
const ARENA_MASK := 1 | (1 << 12)
const WRECK_LAYER := 1 << 13

var age := 0.0
var body: WreckBody
var fragments: Array[WreckBody] = []
var part := ""
var force := Vector3.ZERO
var _heading := Basis.IDENTITY
var _aim := Basis.IDENTITY
var _tilt_axis := Vector3.RIGHT
var _travel := Vector3.ZERO
var _wheel_speed := 0.0
var _brace := 0.0
var _load_side := 0.0
var _plates: Array[Node3D] = []
var _mounts: Array[Dictionary] = []
var _contacts: Array[Dictionary] = []
var _scraped := false
var _crashed := false
var _falling := false
var _wall_pivot_until := 0.0
var _wall_pivot_axis := Vector3.ZERO
var _scrape_until := 0.0
var _next_spark := 0.0
var _turret_shape: CollisionShape3D
var _muzzle_shape: CollisionShape3D
var _support_shapes: Array[Dictionary] = []


func begin(model, arena: Dictionary, point: Vector3, direction: Vector3, region: String,
		speed: float, brace: float) -> void:
	part = region
	force = direction.normalized() if not direction.is_zero_approx() else -model.turret.global_basis.z
	_heading = model.wheel_frame.global_basis.orthonormalized()
	_wheel_speed = speed
	_brace = brace
	_plates = model.armor_to_release(part, point)
	for plate in _plates:
		_mounts.append({"part": plate, "parent": plate.get_parent(), "transform": plate.transform})
	_prepare_arena_colliders(arena)

	var moving := -_heading.z * clampf(speed, -9.5, 9.5)
	var push := force.slide(Vector3.UP)
	var balance := push + moving * (0.12 if part == "wheel" else 0.077)
	if balance.length_squared() < 0.035:
		balance = -_heading.z + _heading.x * 0.18
	# A longitudinal blow pitches first. A small imbalance lets a stalled wheel fall to one side.
	var cross_wheel := balance.dot(_heading.x)
	_load_side = signf(cross_wheel) if absf(cross_wheel) > 0.07 else (1.0 if model.wheel_frame.to_local(point).x < 0.0 else -1.0)
	if part == "shoe_left" or part == "shoe_right":
		_load_side = -1.0 if part == "shoe_left" else 1.0
		balance += _heading.x * (_load_side * 0.24)
	balance += _heading.x * _load_side * 0.13
	_tilt_axis = Vector3.UP.cross(balance.normalized()).normalized()
	_travel = push * lerpf(3.05, 1.95, _brace) + moving * (0.10 if part == "wheel" else 0.19)
	if not push.is_zero_approx():
		var along := push.normalized()
		_travel += along * maxf(0.0, 1.15 - _travel.dot(along))


func advance(model, owner: Node3D, dt: float, rate: float) -> void:
	if dt <= 0.0 or age >= 3.0:
		return
	var previous := age
	age += dt
	if body == null:
		_start_wreck(model, owner, rate)
	body.simulation_rate = rate
	for fragment in fragments:
		fragment.simulation_rate = rate
	if previous < 0.25:
		_recoil_turret(model)
		_fold_supports(model)
	if previous < BROKEN_AT and age >= BROKEN_AT:
		_release_armor(model, owner, rate)
	var axle := body.global_basis.x.normalized()
	var motion_rate := maxf(0.01, rate)
	var rolling := body.linear_velocity.dot(-body.global_basis.z) / motion_rate
	var drive_sign := -1.0 if _wheel_speed < 0.0 else 1.0
	var attempt := smoothstep(0.035, 0.15, age) * (1.0 - smoothstep(0.24, 0.43, age))
	var coast := _wheel_speed * exp(-age * 4.8) + drive_sign * 2.0 * attempt
	model.wheel.rotate_x((-(rolling + coast) / model.WHEEL_RADIUS - body.angular_velocity.dot(axle) / motion_rate) * dt)
	model.set_defeat_power(age)


func _recoil_turret(model) -> void:
	var compression := smoothstep(0.0, 0.046, age) * (1.0 - smoothstep(0.080, 0.25, age))
	var axis: Vector3 = (model.global_basis.inverse() * _tilt_axis).normalized()
	var amount := 5.0 if part == "wheel" else 14.0
	var turn := Basis(axis, deg_to_rad(amount) * compression) * _aim
	var pose: Transform3D = model.global_transform * Transform3D(turn, model.turret.position)
	var world := body.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = ARENA_MASK
	query.shape = _turret_shape.shape
	query.transform = pose.translated_local(TURRET_CENTER)
	if not world.intersect_shape(query, 1).is_empty():
		return
	query.shape = _muzzle_shape.shape
	query.transform = pose.translated_local(MUZZLE_CENTER)
	if not world.intersect_shape(query, 1).is_empty():
		return
	model.turret.basis = turn
	_turret_shape.global_transform = pose.translated_local(TURRET_CENTER)
	_muzzle_shape.global_transform = query.transform


func _fold_supports(model) -> void:
	if _brace <= 0.22:
		return
	for support: Dictionary in model._supports:
		var side: float = support["side"]
		var delay := 0.02 if side == _load_side else 0.048
		var amount := _brace * (1.0 - smoothstep(delay, delay + 0.13, age))
		model.fold_failed_support(side, amount)
	for joint in _support_shapes:
		var link: Node3D = joint["link"]
		var shape: CollisionShape3D = joint["shape"]
		shape.global_transform = link.global_transform.translated_local(joint["center"])


func restore(model: Node3D, owner: Node3D) -> void:
	for mount in _mounts:
		var plate: Node3D = mount["part"]
		var parent: Node3D = mount["parent"]
		if plate.get_parent() != parent:
			plate.reparent(parent, false)
		plate.transform = mount["transform"]
	if is_instance_valid(body):
		model.reparent(owner, true)
		body.on_integrated = Callable()
		body.queue_free()
	for fragment in fragments:
		fragment.queue_free()
	fragments.clear()


func take_contacts() -> Array[Dictionary]:
	var events := _contacts
	_contacts = []
	return events


func _start_wreck(model, owner: Node3D, rate: float) -> void:
	var tilt: Basis = model.wheel_frame.global_basis.orthonormalized()
	_aim = model.turret.basis
	body = _rigid(owner, "SentryWreck", Transform3D(tilt, model.wheel.global_position), 48.0, 0.63, 0.05)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.UP * 0.81
	body.linear_damp = 0.42
	body.angular_damp = 0.78
	body.contact_monitor = true
	body.max_contacts_reported = 16
	var wheel := CylinderShape3D.new()
	wheel.radius = 1.321
	wheel.height = 0.91
	_add_shape(body, wheel, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), "Wheel")
	var inverse := body.global_transform.affine_inverse()
	var turret_pose: Transform3D = inverse * model.turret.global_transform
	_turret_shape = _add_shape(body, _box(Vector3(1.84, 1.00, 2.54)), turret_pose.translated_local(TURRET_CENTER), "Turret")
	_muzzle_shape = _add_shape(body, _box(Vector3(0.78, 0.96, 0.56)), turret_pose.translated_local(MUZZLE_CENTER), "Muzzle")
	_add_shape(body, _box(Vector3(1.48, 1.07, 0.81)), Transform3D(Basis.IDENTITY, Vector3(0, 0.66, 0.10)), "Suspension")
	for support: Dictionary in model._supports:
		for joint: String in ["arm", "rail", "shoe"]:
			_add_support_shape(support[joint], inverse)
	model.reparent(body, true)
	body.on_integrated = _balance_and_contacts
	body.launch(_travel, _tilt_axis * 0.65, rate)


func _add_support_shape(link: Node3D, body_inverse: Transform3D) -> void:
	var inverse := link.global_transform.affine_inverse()
	var bounds := AABB()
	for mesh: MeshInstance3D in link.find_children("*", "MeshInstance3D", true, false):
		var extent := (inverse * mesh.global_transform) * mesh.get_aabb()
		bounds = extent if not bounds.has_volume() else bounds.merge(extent)
	var center := bounds.get_center()
	var pose := (body_inverse * link.global_transform).translated_local(center)
	var shape := _add_shape(body, _box(bounds.size + Vector3.ONE * 0.055), pose, "Brace")
	shape.set_meta(&"support_link", true)
	_support_shapes.append({"link": link, "shape": shape, "center": center})


func _balance_and_contacts(state: PhysicsDirectBodyState3D, dt: float, rate: float) -> void:
	var rim_point := Vector3.INF
	var rim_normal := Vector3.UP
	var shell_point := Vector3.INF
	var wall_normal := Vector3.ZERO
	for index in state.get_contact_count():
		var owner_id := body.shape_find_owner(state.get_contact_local_shape(index))
		var shape := body.shape_owner_get_owner(owner_id) as CollisionShape3D
		var point := state.get_contact_collider_position(index)
		var normal := state.get_contact_local_normal(index)
		if absf(normal.y) < 0.30 and normal.dot(_travel) < -0.25:
			wall_normal += normal.slide(Vector3.UP)
		if shape.name == &"Wheel":
			if normal.y > 0.18 and (not rim_point.is_finite() or point.y < rim_point.y):
				rim_point = point
				rim_normal = normal
		elif normal.y > 0.20:
			var chassis_contact := shape.name in [&"Turret", &"Muzzle", &"Suspension"]
			var folded_side_contact := shape.has_meta(&"support_link") and state.transform.basis.y.y < 0.63
			if chassis_contact or folded_side_contact:
				shell_point = point

	var lean := Vector3.UP.signed_angle_to(state.transform.basis.y, _tilt_axis)
	if not _falling:
		# Load the struck side, briefly countersteer, then let the rim bite.
		var target := deg_to_rad(13.0 * smoothstep(0.0, 0.11, age) \
			- 10.0 * smoothstep(0.11, 0.235, age) + 32.0 * smoothstep(0.24, 0.49, age))
		var desired := clampf((target - lean) * 18.0, -1.85, 3.35) * rate
		var current := state.angular_velocity.dot(_tilt_axis)
		state.angular_velocity += _tilt_axis * ((desired - current) * (1.0 - exp(-dt * 24.0)))
		var braced_against_wall := not wall_normal.is_zero_approx() and age >= 0.42
		if rim_point.is_finite() and age >= RIM_CATCH_AT and (lean >= RIM_CATCH_ANGLE or braced_against_wall):
			_bite_rim(state, rim_point, rim_normal, rate)
		elif age >= 0.68:
			# An airborne wreck cannot create a scrape before it touches down.
			_falling = true

	if _falling and rim_point.is_finite() and not _scraped and state.transform.basis.y.y < 0.96 and not _crashed:
		_bite_rim(state, rim_point, rim_normal, rate)
	if _falling and is_zero_approx(_wall_pivot_until) and not wall_normal.is_zero_approx() and state.transform.basis.y.y > 0.69:
		_begin_wall_pivot(wall_normal.normalized())
	if age < _wall_pivot_until and state.transform.basis.y.y > 0.66:
		var turn := _wall_pivot_axis * (3.6 * rate)
		state.angular_velocity = state.angular_velocity.lerp(turn, 1.0 - exp(-dt * 22.0))
	if rim_point.is_finite() and age < _scrape_until and age >= _next_spark:
		_next_spark = age + 0.048
		_contacts.append({"kind": "rim_spark", "point": rim_point, "normal": rim_normal})
	if not _crashed and shell_point.is_finite() and (_falling or absf(lean) > 0.58):
		_crashed = true
		_contacts.append({"kind": "shell", "point": shell_point})


func _begin_wall_pivot(away: Vector3) -> void:
	# Keep the shove from the hit. Only the fall's rotation redirects off the wall.
	var along := _travel.slide(away).normalized().limit_length(0.38)
	_wall_pivot_axis = Vector3.UP.cross((along + away).normalized())
	_wall_pivot_until = age + 0.35


func _bite_rim(state: PhysicsDirectBodyState3D, point: Vector3, normal: Vector3, rate: float) -> void:
	if _scraped:
		return
	_scraped = true
	_falling = true
	_scrape_until = age + 0.23
	_next_spark = age + 0.04
	var tangent := state.linear_velocity.slide(normal)
	state.linear_velocity -= tangent * 0.42
	state.angular_velocity += _tilt_axis * clampf(1.7 + tangent.length() / rate * 0.35, 1.7, 3.4) * rate
	_contacts.append({"kind": "rim", "point": point, "normal": normal})


func _release_armor(model, owner: Node3D, rate: float) -> void:
	for i in _plates.size():
		var plate := _plates[i]
		var rotation := plate.global_basis.orthonormalized()
		var inverse := Transform3D(rotation, plate.global_position).affine_inverse()
		var points := PackedVector3Array()
		for mesh: MeshInstance3D in plate.find_children("*", "MeshInstance3D", true, false):
			points.append_array((inverse * mesh.global_transform) * mesh.mesh.get_faces())
		if points.size() < 4:
			continue
		var low := points[0]
		var high := low
		for vertex in points:
			low = low.min(vertex)
			high = high.max(vertex)
		var middle := (low + high) * 0.5
		for index in points.size():
			var from_center := points[index] - middle
			points[index] = from_center + from_center.normalized() * 0.065
		var pose := Transform3D(rotation, plate.global_position + rotation * middle)
		var piece := _rigid(owner, String(plate.name) + "Fragment", pose, 0.6, 0.69, 0.26)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		_add_shape(piece, shape, Transform3D.IDENTITY)
		var outward: Vector3 = (pose.origin - model.global_position).slide(Vector3.UP).normalized()
		var scatter := Vector3.UP.cross(force) * ((float(i) - 0.5) * 1.6)
		var velocity := force * 4.4 + Vector3.UP * 2.1 + outward * 1.15 + scatter
		if part == "wheel":
			var arm: Vector3 = pose.origin - model.wheel.global_position
			velocity += (_heading.x * (-_wheel_speed / model.WHEEL_RADIUS)).cross(arm).limit_length(3.1)
		piece.linear_damp = 0.18
		piece.angular_damp = 1.12
		piece.launch(velocity, (rotation.x + Vector3.UP * 0.5).normalized() * (5.5 + 1.3 * i), rate)
		plate.reparent(piece, true)
		fragments.append(piece)
	if not fragments.is_empty():
		_contacts.append({"kind": "break", "point": fragments[0].global_position})


func _rigid(owner: Node3D, label: String, pose: Transform3D, mass: float, friction: float, bounce: float) -> WreckBody:
	var item := WreckBody.new()
	item.name = label
	item.top_level = true
	item.mass = mass
	item.collision_layer = WRECK_LAYER
	item.collision_mask = ARENA_MASK
	item.continuous_cd = true
	item.custom_integrator = true
	item.physics_material_override = PhysicsMaterial.new()
	item.physics_material_override.friction = friction
	item.physics_material_override.bounce = bounce
	owner.add_child(item)
	item.global_transform = pose
	return item


static func _add_shape(owner: CollisionObject3D, shape: Shape3D, pose: Transform3D, label := "Collision") -> CollisionShape3D:
	var collider := CollisionShape3D.new()
	collider.name = label
	collider.shape = shape
	collider.transform = pose
	owner.add_child(collider)
	return collider


static func _box(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape


static func _prepare_arena_colliders(arena: Dictionary) -> void:
	# The original plaza exposes logical wall segments; newer maps already have solid geometry.
	if not arena.get("solids", []).is_empty():
		return
	var root := arena.get("node") as Node3D
	if root == null or root.has_node("SentryWreckSurfaces"):
		return
	var terrain := StaticBody3D.new()
	terrain.name = "SentryWreckSurfaces"
	terrain.top_level = true
	terrain.collision_layer = 1 << 12
	terrain.collision_mask = 0
	root.add_child(terrain)
	terrain.global_transform = Transform3D.IDENTITY
	var floor_y := float(arena.get("floor_y", 0.0))
	_add_shape(terrain, WorldBoundaryShape3D.new(), Transform3D(Basis.IDENTITY, Vector3.UP * floor_y))
	for wall: Dictionary in arena.get("walls", []):
		var a: Vector2 = wall["a"]
		var b: Vector2 = wall["b"]
		var across := b - a
		var height := float(wall["h"]) - floor_y
		if across.length_squared() < 0.01 or height <= 0.03:
			continue
		var center := (a + b) * 0.5
		var face := Basis(Vector3.UP, -atan2(across.y, across.x))
		var pose := Transform3D(face, Vector3(center.x, floor_y + height * 0.5, center.y))
		_add_shape(terrain, _box(Vector3(across.length(), height, 0.16)), pose)
	for cover: Dictionary in arena.get("cover", []):
		var post := CylinderShape3D.new()
		post.radius = maxf(0.1, float(cover["r"]) - 1.2)
		post.height = maxf(0.1, float(cover["h"]))
		var point: Vector3 = cover["c"]
		point.y = floor_y + post.height * 0.5
		_add_shape(terrain, post, Transform3D(Basis.IDENTITY, point))

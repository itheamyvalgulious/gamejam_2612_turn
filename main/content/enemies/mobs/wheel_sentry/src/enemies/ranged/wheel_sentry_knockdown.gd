extends RefCounted
## Keep the rolling joints and armor pose through the hit, then let the world catch the wreck.

const BROKEN_AT := 0.060
const FALL_AT := 0.124
const ARENA_MASK := 1 | (1 << 12)
const WRECK_LAYER := 1 << 13

var age := 0.0
var body: RigidBody3D
var fragments: Array[RigidBody3D] = []
var part := ""
var force := Vector3.ZERO
var _heading := Basis.IDENTITY
var _upright := Basis.IDENTITY
var _base := Vector3.ZERO
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


func begin(model, arena: Dictionary, point: Vector3, direction: Vector3, region: String,
		speed: float, brace: float) -> void:
	part = region
	force = direction.normalized() if not direction.is_zero_approx() else -model.turret.global_basis.z
	_heading = model.wheel_frame.global_basis.orthonormalized()
	_upright = model.global_basis
	_base = model.global_position
	_aim = model.turret.basis
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
	_tilt_axis = Vector3.UP.cross(balance.normalized())
	_travel = push * (1.45 if _brace > 0.65 else 2.55) + moving * (0.13 if part == "wheel" else 0.31)


func advance(model, owner: Node3D, dt: float) -> void:
	if dt <= 0.0 or age >= 3.0:
		return
	var previous := age
	age += dt
	if body == null:
		var lean := deg_to_rad(7.0) * pow(smoothstep(0.024, FALL_AT, age), 1.2)
		model.global_basis = Basis(_tilt_axis, lean) * _upright
		# Keep the outer edge of the narrowing contact patch off the floor as the wheel tilts.
		model.global_position = _base + Vector3.UP * (0.42 * absf(_tilt_axis.dot(_heading.z)) * sin(lean))
		var compression := smoothstep(0.0, 0.036, age) * (1.0 - smoothstep(0.074, 0.20, age))
		var axis: Vector3 = (model.global_basis.inverse() * _tilt_axis).normalized()
		var amount := 5.0 if part == "wheel" else 12.0
		model.turret.basis = Basis(axis, deg_to_rad(amount) * compression) * _aim
		if _brace > 0.22:
			model.fold_failed_support(_load_side, _brace * (1.0 - 0.62 * smoothstep(0.044, FALL_AT, age)))
		var rolling := 1.0 - smoothstep(0.008, 0.068, age) * (0.77 if part == "wheel" else 0.21)
		model.wheel.rotate_x(-_wheel_speed * rolling * dt / model.WHEEL_RADIUS)
	if previous < BROKEN_AT and age >= BROKEN_AT:
		_release_armor(model, owner)
	if previous < FALL_AT and age >= FALL_AT:
		_start_fall(model, owner)
	if body != null:
		var after := age - FALL_AT
		var axle := body.global_basis.x.normalized()
		var coast := lerpf(_wheel_speed * exp(-after * 5.4), body.linear_velocity.dot(-body.global_basis.z),
			smoothstep(0.0, 0.33, after))
		# The shell already rotates with the chassis. The visible tire supplies the remaining roll.
		model.wheel.rotate_x((-coast / model.WHEEL_RADIUS - body.angular_velocity.dot(axle)) * dt)
		if not _scraped and body.get_contact_count() > 0 and body.global_basis.y.dot(Vector3.UP) < 0.91:
			_scraped = true
			var across := body.global_basis.x.normalized() * _load_side
			var down := Vector3.DOWN.slide(across).normalized()
			_contacts.append({"kind": "rim", "point": body.global_position + down * model.WHEEL_RADIUS + across * 0.30})
	model.set_defeat_power(age)


func restore(model: Node3D, owner: Node3D) -> void:
	for mount in _mounts:
		var plate: Node3D = mount["part"]
		var parent: Node3D = mount["parent"]
		if plate.get_parent() != parent:
			plate.reparent(parent, false)
		plate.transform = mount["transform"]
	if is_instance_valid(body):
		model.reparent(owner, false)
		body.queue_free()
	for fragment in fragments:
		fragment.queue_free()
	fragments.clear()


func take_contacts() -> Array[Dictionary]:
	var events := _contacts
	_contacts = []
	return events


func _start_fall(model, owner: Node3D) -> void:
	var tilt: Basis = model.wheel_frame.global_basis.orthonormalized()
	body = _rigid(owner, "SentryWreck", Transform3D(tilt, model.wheel.global_position), 48.0, 0.79, 0.06)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.UP * 0.81
	body.linear_damp = 0.72
	body.angular_damp = 1.05
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.body_shape_entered.connect(_on_body_contact)
	var wheel := CylinderShape3D.new()
	wheel.radius = 1.321
	wheel.height = 0.84
	_add_shape(body, wheel, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), "Wheel")
	var inverse := body.global_transform.affine_inverse()
	var turret_pose: Transform3D = inverse * model.turret.global_transform
	_add_shape(body, _box(Vector3(1.43, 0.73, 2.31)), turret_pose.translated_local(Vector3(0, 0.30, -0.075)), "Turret")
	_add_shape(body, _box(Vector3(0.70, 0.58, 0.32)), turret_pose.translated_local(Vector3(0, 0.27, -1.22)), "Muzzle")
	_add_shape(body, _box(Vector3(1.48, 1.07, 0.81)), Transform3D(Basis.IDENTITY, Vector3(0, 0.66, 0.10)), "Suspension")
	if _brace > 0.22:
		for support: Dictionary in model._supports:
			var shoe: Node3D = support["shoe"]
			var pose := inverse * shoe.global_transform
			_add_shape(body, _box(Vector3(0.36, 0.19, 0.52)), pose.translated_local(Vector3(0, -0.075, -0.08)), "Brace")
	model.reparent(body, true)
	body.linear_velocity = _travel
	body.angular_velocity = _tilt_axis * lerpf(4.1, 3.95, _brace)


func _on_body_contact(_rid: RID, _surface: Node, _shape: int, own_shape: int) -> void:
	if _crashed:
		return
	var collider := body.shape_owner_get_owner(body.shape_find_owner(own_shape)) as CollisionShape3D
	if collider == null or collider.name not in [&"Turret", &"Muzzle", &"Suspension"]:
		return
	_crashed = true
	_contacts.append({"kind": "shell", "point": collider.global_position})


func _release_armor(model, owner: Node3D) -> void:
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
			points[index] -= middle
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
		piece.linear_velocity = velocity
		piece.angular_velocity = (rotation.x + Vector3.UP * 0.5).normalized() * (7.0 + 1.8 * i)
		plate.reparent(piece, true)
		fragments.append(piece)
	if not fragments.is_empty():
		_contacts.append({"kind": "break", "point": fragments[0].global_position})


func _rigid(owner: Node3D, label: String, pose: Transform3D, mass: float, friction: float, bounce: float) -> RigidBody3D:
	var item := RigidBody3D.new()
	item.name = label
	item.top_level = true
	item.mass = mass
	item.collision_layer = WRECK_LAYER
	item.collision_mask = ARENA_MASK
	item.continuous_cd = true
	item.physics_material_override = PhysicsMaterial.new()
	item.physics_material_override.friction = friction
	item.physics_material_override.bounce = bounce
	owner.add_child(item)
	item.global_transform = pose
	return item


static func _add_shape(owner: CollisionObject3D, shape: Shape3D, pose: Transform3D, label := "Collision") -> void:
	var collider := CollisionShape3D.new()
	collider.name = label
	collider.shape = shape
	collider.transform = pose
	owner.add_child(collider)


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

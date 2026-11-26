extends RigidBody3D
## Follow a grip pose with bounded forces. The solver owns the blade's actual pose.

signal contact(point: Vector3, other: Object)

const BLADE_LAYER := 2
const WORLD_LAYER := 4
const THICKNESS := 0.12
const WIDTH := 0.19
const WRIST_BEND := 17.0

class Grip extends RigidBody3D:
	var target := Transform3D.IDENTITY
	var target_velocity := Vector3.ZERO
	var target_spin := Vector3.ZERO
	var angular_strength := 1.0
	var blocked_axis := Vector3.ZERO

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		var pose := state.transform
		var acceleration := (target.origin - pose.origin) * 520.0 \
			+ (target_velocity - state.linear_velocity) * 39.0
		state.apply_central_force((acceleration * mass).limit_length(430.0))
		var error := rotation_error(pose.basis, target.basis)
		var desired := error * (190.0 * angular_strength) \
			+ (target_spin - state.angular_velocity) * (27.0 * sqrt(angular_strength))
		if desired.dot(blocked_axis) < 0.0:
			desired = desired.slide(blocked_axis)
		state.apply_torque((desired * 8.0).limit_length(810.0 * angular_strength))

	static func rotation_error(current: Basis, ideal: Basis) -> Vector3:
		var rotation := (ideal.get_rotation_quaternion() * current.get_rotation_quaternion().inverse()).normalized()
		if rotation.w < 0.0:
			rotation = -rotation
		var vector := Vector3(rotation.x, rotation.y, rotation.z)
		if vector.length_squared() < 0.000001:
			return vector * 2.0
		return vector.normalized() * rotation.get_angle()

var target := Transform3D.IDENTITY
var angular_strength := 1.0
var blade_start := 0.0
var grip_error := 0.0
var grip_gap := 0.0
var direction_error := 0.0
var wrist_bend := 0.0
var wrist_twist := 0.0

var _contact_ids: Array[int] = []
var _blade_center := Vector3.ZERO
var _moment_at_grip := Vector3.ONE
var _grip: Grip
var _world_query := PhysicsShapeQueryParameters3D.new()


func configure(length: float, blade_mass: float, start: float, pose: Transform3D) -> void:
	mass = blade_mass
	blade_start = start
	gravity_scale = 0.0
	can_sleep = false
	continuous_cd = true
	collision_layer = BLADE_LAYER
	collision_mask = BLADE_LAYER | WORLD_LAYER
	max_contacts_reported = 8
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.14
	physics_material_override.bounce = 0.24
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, length, THICKNESS)
	_world_query.shape = box
	_world_query.collision_mask = WORLD_LAYER
	var collider := CollisionShape3D.new()
	collider.shape = box
	_blade_center = Vector3.UP * (blade_start + length * 0.5)
	collider.position = _blade_center
	add_child(collider)
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = _blade_center
	inertia = blade_mass / 12.0 * Vector3(length * length + THICKNESS * THICKNESS,
		WIDTH * WIDTH + THICKNESS * THICKNESS, length * length + WIDTH * WIDTH)
	inertia.y += 0.12
	_moment_at_grip = inertia + Vector3(1, 0, 1) * (blade_mass * _blade_center.length_squared())
	transform = pose
	target = pose


func attach_grip() -> Node3D:
	var stage := get_parent() as Node3D
	_grip = Grip.new()
	_grip.mass = 6.0
	_grip.inertia = Vector3(3, 3, 3)
	_grip.gravity_scale = 0.0
	_grip.can_sleep = false
	_grip.angular_strength = angular_strength
	_grip.collision_layer = 0
	_grip.collision_mask = 0
	_grip.transform = transform
	stage.add_child(_grip)
	_grip.target = global_transform
	var joint := ConeTwistJoint3D.new()
	# The joint twists about X. Align that axis with the length of the sword.
	joint.transform = Transform3D(basis * Basis(Vector3.BACK, PI * 0.5), position)
	joint.swing_span = deg_to_rad(WRIST_BEND)
	joint.twist_span = 0.0
	stage.add_child(joint)
	joint.node_a = joint.get_path_to(_grip)
	joint.node_b = joint.get_path_to(self)
	return _grip


func follow(pose: Transform3D, delta: float) -> void:
	_grip.target_velocity = (pose.origin - target.origin) / delta
	_grip.target = pose
	_grip.target_spin = Grip.rotation_error(target.basis, pose.basis) / delta
	target = pose


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var current := state.transform
	var forearm := _grip.global_basis
	var wrist := Grip.rotation_error(current.basis, forearm)
	var rotation := (forearm.transposed() * current.basis).get_rotation_quaternion()
	var twist := wrapf(2.0 * atan2(rotation.y, rotation.w), -PI, PI)
	var grip_axis := forearm.y.normalized()
	var axial_speed := (state.angular_velocity - _grip.angular_velocity).dot(grip_axis)
	# A closed grip transmits twist into the forearm even between joint solver steps.
	state.angular_velocity -= grip_axis * (axial_speed + twist * 45.0)
	var angular_acceleration := wrist * 84.0 + (_grip.angular_velocity - state.angular_velocity) * 13.0
	# Yield only along blocked directions. Tangential motion can continue under the same drive.
	_grip.blocked_axis = Vector3.ZERO
	for index in state.get_contact_count():
		var normal := state.get_contact_local_normal(index)
		var arm := state.get_contact_local_position(index) - current.origin
		var blocked_axis := arm.cross(normal).normalized()
		if angular_acceleration.dot(blocked_axis) < 0.0:
			angular_acceleration = angular_acceleration.slide(blocked_axis)
		_grip.blocked_axis += blocked_axis
	var terrain := _swept_terrain_contact(state, angular_acceleration)
	if not terrain.is_empty():
		var normal: Vector3 = terrain["normal"]
		var point: Vector3 = terrain["point"]
		var blocked_axis := (point - current.origin).cross(normal).normalized()
		var inward := state.angular_velocity.dot(blocked_axis)
		if inward < 0.0:
			state.angular_velocity -= blocked_axis * (inward * 1.14)
		if angular_acceleration.dot(blocked_axis) < 0.0:
			angular_acceleration = angular_acceleration.slide(blocked_axis)
		_grip.blocked_axis += blocked_axis
	_grip.blocked_axis = _grip.blocked_axis.normalized()
	var torque := current.basis * (_moment_at_grip * (current.basis.transposed() * angular_acceleration))
	state.apply_torque(torque.limit_length(108.0))
	grip_error = current.origin.distance_to(target.origin)
	grip_gap = current.origin.distance_to(_grip.global_position)
	direction_error = current.basis.y.angle_to(target.basis.y)
	wrist_bend = rad_to_deg(forearm.y.angle_to(current.basis.y))
	wrist_twist = absf(rad_to_deg(twist))
	_read_contacts(state, terrain)


func _swept_terrain_contact(state: PhysicsDirectBodyState3D, requested: Vector3) -> Dictionary:
	# The engine's linear sweep needs help when only the far end of a blade moves.
	var spin := state.angular_velocity + requested * state.step * 0.5
	var speed := spin.length()
	var pose := state.transform
	var wrist_velocity := state.linear_velocity - state.angular_velocity.cross(pose.basis * _blade_center)
	var space := state.get_space_state()
	for fraction in [0.0, 0.5, 1.0]:
		var time: float = state.step * fraction
		var basis := pose.basis
		if speed > 0.001:
			basis = Basis(spin / speed, speed * time) * basis
		_world_query.transform = Transform3D(basis, pose.origin + wrist_velocity * time + basis * _blade_center)
		var terrain := space.get_rest_info(_world_query)
		if not terrain.is_empty():
			return terrain
	return {}


func _read_contacts(state: PhysicsDirectBodyState3D, terrain: Dictionary) -> void:
	var touching: Array[int] = []
	for index in state.get_contact_count():
		var other: Object = state.get_contact_collider_object(index)
		if not is_instance_valid(other):
			continue
		var id := other.get_instance_id()
		if not touching.has(id) and not _contact_ids.has(id):
			contact.emit(state.get_contact_collider_position(index), other)
		touching.append(id)
	if not terrain.is_empty():
		var id: int = terrain["collider_id"]
		if not touching.has(id) and not _contact_ids.has(id):
			contact.emit(terrain["point"], instance_from_id(id))
		touching.append(id)
	_contact_ids = touching

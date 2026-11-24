extends RigidBody3D
## Keep the solver in charge of contacts while advancing this piece at the shot's pace.

const WORLD_LAYER := 1
const FRAGMENT_LAYER := 1 << 7

var simulation_rate := 1.0
var _previous_rate := 1.0
var _gravity := 0.0


func launch(pose: Transform3D, shape: Shape3D, velocity: Vector3, spin: Vector3, rate: float) -> void:
	top_level = true
	collision_layer = FRAGMENT_LAYER
	collision_mask = WORLD_LAYER
	continuous_cd = true
	custom_integrator = true
	linear_damp_mode = DAMP_MODE_REPLACE
	angular_damp_mode = DAMP_MODE_REPLACE
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.68
	physics_material_override.bounce = 0.22
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	global_transform = pose
	simulation_rate = rate
	_previous_rate = maxf(rate, 0.01)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	linear_velocity = velocity * _previous_rate
	angular_velocity = spin * _previous_rate


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var rate := maxf(simulation_rate, 0.01)
	var ratio := rate / _previous_rate
	_previous_rate = rate
	var dt := state.step * rate
	state.linear_velocity = state.linear_velocity * (ratio * exp(-0.18 * dt)) +		+ Vector3.DOWN * (_gravity * dt * rate)
	state.angular_velocity *= ratio * exp(-0.95 * dt)

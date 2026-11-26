extends RigidBody3D
## Let the solver handle contacts while motion follows the execution clock.

var simulation_rate := 1.0
var on_integrated: Callable
var _previous_rate := 1.0


func launch(velocity: Vector3, spin: Vector3, rate: float) -> void:
	simulation_rate = rate
	_previous_rate = maxf(0.01, rate)
	linear_velocity = velocity * _previous_rate
	angular_velocity = spin * _previous_rate


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var rate := maxf(0.01, simulation_rate)
	var dt := state.step * rate
	var ratio := rate / _previous_rate
	_previous_rate = rate
	state.linear_velocity = state.linear_velocity * (ratio * exp(-linear_damp * dt)) \
		+ state.total_gravity * (dt * rate)
	state.angular_velocity *= ratio * exp(-angular_damp * dt)
	if on_integrated.is_valid():
		on_integrated.call(state, dt, rate)

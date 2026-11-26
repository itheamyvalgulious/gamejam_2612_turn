extends RefCounted
## Sweep a held blade against level geometry, then yield at the grip.
## Pose and collision always use the same hilt and blade axis.

const TERRAIN_MASK := 1
const RECOVERY_TIME := 0.50
const SKIN := 0.025
const SWEEP_STEP := 0.12

var impact: Dictionary = {}
var recovering: bool:
	get:
		return _age < RECOVERY_TIME

var _query := PhysicsShapeQueryParameters3D.new()
var _shape := CapsuleShape3D.new()
var _span := Vector2.ZERO
var _previous := Transform3D.IDENTITY
var _initialized := false
var _age := RECOVERY_TIME
var _contact_pose := Transform3D.IDENTITY
var _normal := Vector3.ZERO
var _slide := Vector3.ZERO
var _fold := Vector3.ZERO
var _last_strike := -1


func _init() -> void:
	_query.shape = _shape
	_query.collision_mask = TERRAIN_MASK
	_query.margin = 0.012


func reset() -> void:
	_initialized = false
	_age = RECOVERY_TIME
	_last_strike = -1
	impact.clear()


func advance(space: PhysicsDirectSpaceState3D, authored: Transform3D, span: Vector2,
		shoulder: Vector3, dt: float, strike := -1) -> Transform3D:
	impact.clear()
	var scale := authored.basis.get_scale()
	_span = span * scale.y
	_shape.radius = 0.085 * scale.x
	_shape.height = _span.y - _span.x + 2.0 * _shape.radius
	var desired := authored.orthonormalized()
	if not _initialized:
		_previous = desired
		_initialized = true
	_age = minf(_age + dt, RECOVERY_TIME)
	var target := _recovery(desired) if recovering else desired
	var incoming := _sweep(space, _previous, target)
	var pose: Transform3D = incoming["pose"]
	if incoming.has("point") and not recovering and strike >= 0 and strike != _last_strike:
		_last_strike = strike
		_normal = incoming["normal"]
		var point: Vector3 = incoming["point"]
		var blade_point := pose.affine_inverse() * point
		var travel := (desired * blade_point - _previous * blade_point) / maxf(dt, 0.001)
		var incidence := clampf(-travel.normalized().dot(_normal), 0.0, 1.0)
		var tangent := travel.slide(_normal)
		_slide = tangent.limit_length(6.0) * lerpf(0.075, 0.012, smoothstep(0.24, 0.76, incidence))
		_fold = (shoulder - pose.origin).normalized()
		# The elbow may fold toward the shoulder, but never feed pressure back into the wall.
		if _fold.dot(_normal) < 0.0:
			_fold = _fold.slide(_normal)
		_contact_pose = pose
		_age = 0.0
		impact = {"point": point, "normal": _normal, "incidence": incidence,
			"strength": clampf(maxf(-travel.dot(_normal), tangent.length() * 0.2) / 6.0, 0.2, 1.0)}
	elif incoming.has("point"):
		if not _contact(space, pose).is_empty():
			# A reset or a moving support can start inside a collider.
			pose = _clear_overlap(space, pose, shoulder)
		elif not recovering and not _contact(space, target).is_empty():
			# If idle carry is obstructed, tuck the hilt while the actor keeps moving.
			var tucked := _clear_overlap(space, target, shoulder)
			pose = _sweep(space, pose, tucked)["pose"]
	_previous = pose
	pose.basis = pose.basis.scaled_local(scale)
	return pose


func shoulder_recoil() -> Vector3:
	var envelope := smoothstep(0.0, 0.105, _age) * (1.0 - smoothstep(0.14, 0.43, _age))
	return (_normal - _slide * 0.45) * envelope


func _recovery(desired: Transform3D) -> Transform3D:
	var early := smoothstep(0.0, 0.14, _age)
	var release := smoothstep(0.02, 0.23, _age)
	var settle := smoothstep(0.15, RECOVERY_TIME, _age)
	var pose := _contact_pose.interpolate_with(desired, settle)
	var withdraw := _slide * early + _normal * (0.18 * early + 0.18 * release) + _fold * (0.23 * release)
	pose.origin += withdraw * (1.0 - settle)
	return pose


func _sweep(space: PhysicsDirectSpaceState3D, from: Transform3D, to: Transform3D) -> Dictionary:
	# Subdivide both rotation and translation so a sword rotating around a stationary
	# hand can still hit a thin railing, even on a low frame rate.
	var rotation := from.basis.get_rotation_quaternion().angle_to(to.basis.get_rotation_quaternion())
	var travel := from.origin.distance_to(to.origin) + rotation * _span.y
	var steps := clampi(ceili(travel / SWEEP_STEP), 1, 80)
	var clear := from
	for i in range(1, steps + 1):
		var next := from.interpolate_with(to, float(i) / steps)
		var hit := _contact(space, next)
		if hit.is_empty():
			clear = next
			continue
		for _refinement in 5:
			var middle := clear.interpolate_with(next, 0.5)
			if _contact(space, middle).is_empty():
				clear = middle
			else:
				next = middle
		return {"pose": clear, "normal": hit["normal"], "point": hit["point"]}
	return {"pose": to}


func _contact(space: PhysicsDirectSpaceState3D, pose: Transform3D) -> Dictionary:
	_query.transform = Transform3D(pose.basis, pose * (Vector3.UP * (_span.x + _span.y) * 0.5))
	return space.get_rest_info(_query)


func _clear_overlap(space: PhysicsDirectSpaceState3D, pose: Transform3D, shoulder: Vector3) -> Transform3D:
	var tuck := pose
	tuck.origin = pose.origin.lerp(shoulder, 0.48)
	var up := pose.basis.y.cross(Vector3.UP).normalized()
	for turn: float in [0.0, 0.32, 0.64, 1.05, 1.57]:
		tuck.basis = Basis(up, turn) * pose.basis if not up.is_zero_approx() else pose.basis
		var hit := _contact(space, tuck)
		if hit.is_empty():
			return tuck
		var normal: Vector3 = hit["normal"]
		var clear := tuck
		clear.origin += normal * (0.20 + SKIN)
		if _contact(space, clear).is_empty():
			return clear
	return pose

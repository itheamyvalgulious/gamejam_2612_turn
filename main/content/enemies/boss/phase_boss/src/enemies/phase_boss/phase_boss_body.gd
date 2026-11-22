extends RefCounted
## The player rig moves kinematically. Sweep its capsule against the posed mechanical body.

const SWEEP_STEP := 0.38
const SKIN := 0.025
const BODY_REACH := 13.0

class Capsule:
	var a: Vector3
	var b: Vector3
	var radius: float

	func _init(start: Vector3, end: Vector3, width: float) -> void:
		a = start
		b = end
		radius = width


static func resolve(model, from: Vector3, to: Vector3, shape: Dictionary, arena: Dictionary) -> Vector3:
	var floor_center: Vector3 = model.global_position.slide(Vector3.UP)
	var closest := Geometry3D.get_closest_point_to_segment(floor_center, from.slide(Vector3.UP), to.slide(Vector3.UP))
	if closest.distance_squared_to(floor_center) > BODY_REACH * BODY_REACH:
		return to
	var parts := posed_capsules(model)

	var capsule_bottom: Vector3 = shape["a"] - to
	var capsule_top: Vector3 = shape["b"] - to
	var radius := float(shape["r"])
	var bounds: AABB = arena["bounds"].grow(-3.0)
	var move := to - from
	var count := maxi(1, ceili(move.length() / SWEEP_STEP))
	var advance := move / float(count)
	var pos := from
	for i in count:
		var next := pos + advance
		var direction := (pos - floor_center).slide(Vector3.UP).normalized()
		if direction.is_zero_approx():
			direction = model.global_basis.x.normalized()
		var safe := _separate(next, capsule_bottom, capsule_top, radius, parts, direction, bounds)
		if _is_clear(safe, capsule_bottom, capsule_top, radius, parts):
			pos = safe
		elif not _is_clear(pos, capsule_bottom, capsule_top, radius, parts):
			# A moving boss can trap the player against a wall. Find nearby open floor.
			return _escape(safe, capsule_bottom, capsule_top, radius, parts, bounds)
	return pos


static func posed_capsules(model) -> Array[Capsule]:
	var scale: float = model.global_basis.get_scale().x
	var parts: Array[Capsule] = [
		Capsule.new(model.chest.to_global(Vector3(0, 0.0, -1.81)),
			model.chest.to_global(Vector3(0, 0.17, 1.35)), 2.04 * scale),
		Capsule.new(model.chest.to_global(Vector3(0, 0.12, 1.30)),
			model.pelvis.to_global(Vector3(0, 0.16, 1.30)), 1.64 * scale),
		Capsule.new(model.neck.global_position, model.head.global_position, 1.24 * scale),
		Capsule.new(model.head.global_position, model.head.to_global(Vector3(0, -0.32, -1.53)), 1.09 * scale),
		Capsule.new(model.jaw.global_position, model.jaw.to_global(Vector3(0, -0.10, -1.78)), 0.80 * scale),
	]
	for leg: Dictionary in model.legs:
		parts.append(Capsule.new(leg["root"].global_position, leg["joint"].global_position, 0.86 * scale))
		parts.append(Capsule.new(leg["joint"].global_position, leg["distal"].global_position, 0.64 * scale))
		parts.append(Capsule.new(leg["distal"].global_position, leg["paw"].to_global(Vector3(0, 0, -0.64)), 0.58 * scale))
	return parts


static func _separate(pos: Vector3, bottom: Vector3, top: Vector3, radius: float,
		parts: Array[Capsule], fallback: Vector3, bounds: AABB) -> Vector3:
	pos = _bound(pos, bounds)
	for pass_index in 5:
		var moved := false
		for part in parts:
			var contact := Geometry3D.get_closest_points_between_segments(pos + bottom, pos + top, part.a, part.b)
			var offset := contact[0] - contact[1]
			var margin := radius + part.radius + SKIN
			if offset.length_squared() >= margin * margin:
				continue
			var planar := offset.slide(Vector3.UP)
			var distance := planar.length()
			var push := sqrt(maxf(0.0, margin * margin - offset.y * offset.y)) - distance
			var normal := planar / distance if distance > 0.0001 else fallback
			pos = _bound(pos + normal * push, bounds)
			moved = true
		if not moved:
			break
	return pos


static func _is_clear(pos: Vector3, bottom: Vector3, top: Vector3, radius: float,
		parts: Array[Capsule]) -> bool:
	for part in parts:
		var contact := Geometry3D.get_closest_points_between_segments(pos + bottom, pos + top, part.a, part.b)
		var width := radius + part.radius - 0.006
		if contact[0].distance_squared_to(contact[1]) < width * width:
			return false
	return true


static func _escape(origin: Vector3, bottom: Vector3, top: Vector3, radius: float,
		parts: Array[Capsule], bounds: AABB) -> Vector3:
	for ring in range(1, 15):
		for i in 16:
			var angle := TAU * float(i) / 16.0
			var candidate := _bound(origin + Vector3(cos(angle), 0, sin(angle)) * (0.5 * ring), bounds)
			if _is_clear(candidate, bottom, top, radius, parts):
				return candidate
	return origin


static func _bound(pos: Vector3, bounds: AABB) -> Vector3:
	return Vector3(clampf(pos.x, bounds.position.x, bounds.end.x), pos.y,
		clampf(pos.z, bounds.position.z, bounds.end.z))

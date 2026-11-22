extends RefCounted
## 曲刃沿 +Y，-X 是外弧刃口，+X 是有厚度的刀背。

const SLICES := 24
const DEPTH := 0.035
const TIP_OFFSET := 0.26


static func _profile(u: float, width: float) -> Vector2:
	var half_width := width * 0.50 * (1.0 - 0.36 * u)
	return Vector2(TIP_OFFSET * u * u, half_width * (1.0 - smoothstep(0.83, 1.001, u)))


static func _point(u: float, edge: float, face: float, length: float, width: float) -> Vector3:
	var shape := _profile(u, width)
	var depth := DEPTH * (1.0 - smoothstep(0.84, 1.03, u))
	return Vector3(shape.x + edge * shape.y, u * length, face * depth)


static func body(length: float, width: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge := SurfaceTool.new()
	edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	var section := [Vector2(-1, 0), Vector2(-0.44, 1), Vector2(0.82, 1),
		Vector2(1, 0.55), Vector2(1, -0.55), Vector2(0.82, -1), Vector2(-0.44, -1)]
	for i in range(SLICES):
		var u := float(i) / SLICES
		var v := float(i + 1) / SLICES
		for j in range(section.size()):
			var s: Vector2 = section[j]
			var n: Vector2 = section[(j + 1) % section.size()]
			var material_surface := edge if j == 0 or j == section.size() - 1 else surface
			_quad(material_surface, _point(u, s.x, s.y, length, width), _point(u, n.x, n.y, length, width),
				_point(v, n.x, n.y, length, width), _point(v, s.x, s.y, length, width),
				Vector3(s.x + n.x, 0, s.y + n.y))
	var base := Vector3.ZERO
	var tip := Vector3(_profile(1.0, width).x, length, 0.0)
	for j in range(section.size()):
		var s: Vector2 = section[j]
		var n: Vector2 = section[(j + 1) % section.size()]
		_triangle(surface, base, _point(0.0, s.x, s.y, length, width), _point(0.0, n.x, n.y, length, width), Vector3.DOWN)
		_triangle(surface, tip, _point(1.0, s.x, s.y, length, width), _point(1.0, n.x, n.y, length, width), Vector3.UP)
	return edge.commit(surface.commit())


static func channels(length: float, width: float) -> ArrayMesh:
	return _face_strips(length, width, Vector2(0.24, 0.53), [Vector2(0.11, 0.15), Vector2(0.175, 0.80)])


static func inlays(length: float, width: float) -> ArrayMesh:
	return _face_strips(length, width, Vector2(-0.35, -0.11), [Vector2(0.23, 0.27), Vector2(0.295, 0.91)])


static func charge_edge(length: float, width: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SLICES:
		var u := lerpf(0.27, 0.965, float(i) / SLICES)
		var v := lerpf(0.27, 0.965, float(i + 1) / SLICES)
		var a := _point(u, -1.0, 0.0, length, width)
		var b := _point(v, -1.0, 0.0, length, width)
		var radius_a := 0.011 * (1.0 - smoothstep(0.88, 0.98, u))
		var radius_b := 0.011 * (1.0 - smoothstep(0.88, 0.98, v))
		for j in 6:
			var p := Vector3.RIGHT.rotated(Vector3.UP, TAU * j / 6.0)
			var q := Vector3.RIGHT.rotated(Vector3.UP, TAU * (j + 1) / 6.0)
			_quad(surface, a + p * radius_a, a + q * radius_a,
				b + q * radius_b, b + p * radius_b, p + q)
	return surface.commit()


static func _face_strips(length: float, width: float, across: Vector2, intervals: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for interval: Vector2 in intervals:
			for i in range(12):
				var u := lerpf(interval.x, interval.y, float(i) / 12.0)
				var v := lerpf(interval.x, interval.y, float(i + 1) / 12.0)
				_quad(surface, _point(u, across.x, side * 1.045, length, width), _point(u, across.y, side * 1.045, length, width),
					_point(v, across.y, side * 1.045, length, width), _point(v, across.x, side * 1.045, length, width),
					Vector3(0, 0, side))
	return surface.commit()


static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3) -> void:
	_triangle(surface, a, b, c, facing)
	_triangle(surface, a, c, d, facing)


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, facing: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	var points := [a, b, c] if normal.dot(facing) >= 0.0 else [a, c, b]
	if normal.dot(facing) < 0.0:
		normal = -normal
	for point in points:
		surface.set_normal(normal)
		surface.add_vertex(point)

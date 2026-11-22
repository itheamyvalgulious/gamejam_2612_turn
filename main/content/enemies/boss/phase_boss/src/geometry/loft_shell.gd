extends RefCounted
## 沿 Y 轴放样装甲。每层定义高度、横向和前后半径，以及截面中心的偏移。

const SIDES := 24


static func loft(sections: Array, opening_levels := Vector2i.ZERO) -> ArrayMesh:
	var rings: Array[PackedVector3Array] = []
	for section: Array in sections:
		var ring := PackedVector3Array()
		for i in SIDES:
			var angle := TAU * float(i) / SIDES
			ring.append(Vector3(section[3] + cos(angle) * section[1], section[0],
				section[4] + sin(angle) * section[2]))
		rings.append(ring)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level in range(rings.size() - 1):
		for i in SIDES:
			# The dorsal cassette opens the top strip of the chest only.
			if level >= opening_levels.x and level < opening_levels.y and i >= 16 and i < 20:
				continue
			var next := (i + 1) % SIDES
			var a := rings[level][i]
			var b := rings[level][next]
			var c := rings[level + 1][next]
			var d := rings[level + 1][i]
			var na := _normal(rings, level, i)
			var nb := _normal(rings, level, next)
			var nc := _normal(rings, level + 1, next)
			var nd := _normal(rings, level + 1, i)
			soft_tri(surface, a, b, c, na, nb, nc)
			soft_tri(surface, a, c, d, na, nc, nd)
	for level: int in [0, rings.size() - 1]:
		var normal := Vector3.DOWN if level == 0 else Vector3.UP
		var section: Array = sections[level]
		var center := Vector3(section[3], section[0], section[4])
		for i in SIDES:
			tri(surface, center, rings[level][i], rings[level][(i + 1) % SIDES], normal)
	return surface.commit()


static func _normal(rings: Array[PackedVector3Array], level: int, i: int) -> Vector3:
	var around := rings[level][(i + 1) % SIDES] - rings[level][(i + SIDES - 1) % SIDES]
	var along := rings[mini(level + 1, rings.size() - 1)][i] - rings[maxi(0, level - 1)][i]
	return along.cross(around).normalized()


static func soft_tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3) -> void:
	_vertex(surface, a, na)
	if (c - a).cross(b - a).dot(na + nb + nc) >= 0.0:
		_vertex(surface, b, nb)
		_vertex(surface, c, nc)
	else:
		_vertex(surface, c, nc)
		_vertex(surface, b, nb)


static func _vertex(surface: SurfaceTool, point: Vector3, normal: Vector3) -> void:
	surface.set_normal(normal)
	surface.add_vertex(point)


static func tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, facing: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	var points := [a, b, c]
	if normal.dot(facing) < 0.0:
		points = [a, c, b]
		normal = -normal
	for point in points:
		_vertex(surface, point, normal)

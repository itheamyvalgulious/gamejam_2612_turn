class_name InteriorsGen
extends RefCounted
## Real interior geometry behind curtain-wall glass: floor slabs, ceiling
## light strips, core, partitions and furniture near the glass.

func generate(gen: CityGen) -> void:
	var rng := gen.rng
	for it in gen.interior_targets:
		var poly: PackedVector2Array = it.poly
		var fp: PackedVector2Array = it.fp
		var h: float = it.h
		var fh: float = it.fh
		var sd: float = it.seed
		var ck := gen.chunk_of(Vector3(poly[0].x, 0, poly[0].y))
		var b := gen.buf(ck, "interior")
		var c := _cent2(poly)
		var floors := int(h / fh)
		for f in floors:
			var y := float(f) * fh + 0.15
			if y > h - 1.0:
				break
			# slab
			_poly_quad(b, poly, y, Color(0.25, 0.24, 0.22), 0.0)
			# ceiling light strip
			_poly_quad(b, _scale2(poly, c, 0.75), y + fh - 0.35, Color(1.0, 0.85, 0.65), 1.0)
			# partitions: two crossing quads
			if f < 14:
				var ax := rng.randf() * PI
				var dirv := Vector2(cos(ax), sin(ax))
				var ln := _extent(poly, dirv) * 0.7
				var p0 := c - dirv * ln * 0.5
				var p1 := c + dirv * ln * 0.5
				_wall_quad(b, p0, p1, y, y + fh - 0.4, Color(0.3, 0.29, 0.27), 0.0)
			# furniture near facade (first floors only, street life)
			if f < 7:
				var n := fp.size()
				for k in rng.randi_range(2, 4):
					var i := rng.randi_range(0, n - 1)
					var a: Vector2 = fp[i]
					var bq: Vector2 = fp[(i + 1) % n]
					var t := rng.randf()
					var pos2 := a.lerp(bq, t)
					var toward := (c - pos2).normalized()
					var pos2b := pos2 + toward * rng.randf_range(2.0, 5.0)
					var pw := Vector3(pos2b.x, 0, pos2b.y)
					var kind := rng.randf()
					if kind < 0.4:
						b.box(pw + Vector3(0, y + 0.4, 0), Vector3(1.8, 0.8, 0.9), Vector2.ZERO,
							Color(0.2, 0.18, 0.16), 0.5, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pw + Vector3(0, y + 0.4, 0)))
					elif kind < 0.7:
						b.box(pw + Vector3(0, y + 0.35, 0), Vector3(2.4, 0.7, 1.0), Vector2.ZERO,
							Color(0.25, 0.22, 0.2), 0.5, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pw + Vector3(0, y + 0.35, 0)))
					else:
						# desk with glowing monitor
						b.box(pw + Vector3(0, y + 0.37, 0), Vector3(1.6, 0.74, 0.8), Vector2.ZERO,
							Color(0.18, 0.17, 0.16), 0.5, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pw + Vector3(0, y + 0.37, 0)))
						b.box(pw + Vector3(0, y + 1.0, 0), Vector3(0.7, 0.45, 0.08), Vector2(1.0, 0.0),
							Color(0.6, 0.8, 1.0), 0.5, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pw + Vector3(0, y + 1.0, 0)))
		# core
		b.box(Vector3(c.x, h * 0.5, c.y), Vector3(9.0, h, 7.0), Vector2.ZERO, Color(0.2, 0.2, 0.2), 0.3)

func _cent2(poly: PackedVector2Array) -> Vector2:
	var g := Vector2.ZERO
	for p in poly:
		g += p
	return g / float(poly.size())

func _scale2(poly: PackedVector2Array, c: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(c + (p - c) * s)
	return out

func _extent(poly: PackedVector2Array, dirv: Vector2) -> float:
	var mn := 1e9
	var mx := -1e9
	for p in poly:
		var d := p.dot(dirv)
		mn = minf(mn, d)
		mx = maxf(mx, d)
	return mx - mn

func _poly_quad(b: MeshBuf, poly: PackedVector2Array, y: float, col: Color, emis: float) -> void:
	var c := _cent2(poly)
	var n := poly.size()
	for i in range(1, n - 1):
		b.tri_o(Vector3(poly[0].x, y, poly[0].y), Vector3(poly[i].x, y, poly[i].y),
			Vector3(poly[i + 1].x, y, poly[i + 1].y), Vector3.UP,
			PackedVector2Array([poly[0] * 0.2, poly[i] * 0.2, poly[i + 1] * 0.2]),
			Vector2(emis, 0), col)

func _wall_quad(b: MeshBuf, p0: Vector2, p1: Vector2, y0: float, y1: float,
		col: Color, emis: float) -> void:
	var a := Vector3(p0.x, y0, p0.y)
	var bq := Vector3(p1.x, y0, p1.y)
	var c := Vector3(p1.x, y1, p1.y)
	var d := Vector3(p0.x, y1, p0.y)
	var nn := Vector3((p1 - p0).y, 0, -(p1 - p0).x).normalized()
	b.quad_o(a, bq, c, d, nn, PackedVector2Array([
		Vector2(0, y0), Vector2(p0.distance_to(p1), y0), Vector2(p0.distance_to(p1), y1), Vector2(0, y1)]),
		Vector2(emis, 0), col)

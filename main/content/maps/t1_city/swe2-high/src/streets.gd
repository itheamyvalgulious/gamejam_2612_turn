extends Node3D

## Street network: extruded ribbons for major avenues + minor block
## streets, plus the canal water strip. All flat decals laid on h().

const CityLayout = preload("res://src/city.gd")
const GroundPlan = preload("res://src/ground.gd")

var _hf: RefCounted
var _city: RefCounted


func build(c: CityLayout, hf: GroundPlan) -> void:
	_city = c
	_hf = hf
	_ground_sheet()
	_road_ribbons()
	_canal()


func _ground_sheet() -> void:
	# one big terrain sheet at coarse res — city lots cover most of it
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 32.0
	# apron reaches 1.5 km past the build area so the skyline's ground
	# never ends in a hard cliff — fog swallows the far edge
	var ex0 := CityLayout.X0 - 1500.0
	var ex1 := CityLayout.X1 + 1500.0
	var ez0 := CityLayout.Z0 - 1500.0
	var ez1 := CityLayout.Z1 + 1500.0
	var nx := int((ex1 - ex0) / step) + 1
	var nz := int((ez1 - ez0) / step) + 1
	for iz in nz:
		for ix in nx:
			var x0 := ex0 + ix * step
			var z0 := ez0 + iz * step
			var x1 := minf(x0 + step, ex1)
			var z1 := minf(z0 + step, ez1)
			var y00: float = _hf.h(x0, z0)
			var y10: float = _hf.h(x1, z0)
			var y01: float = _hf.h(x0, z1)
			var y11: float = _hf.h(x1, z1)
			var rd: float = _hf.river_dist(Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5))
			# pavement: slight per-cell tint so bare ground reads as
			# concrete, not void
			# darker than the asphalt and low-contrast — bright checker
			# quads were reading as a board, not as urban ground
			var v := 0.92 + _h(ix * 7, iz * 13) * 0.16
			var col := Color(0.105 * v, 0.105 * v, 0.12 * v)
			# fade only in the outer extension zone — the city apron
			# keeps full brightness, the far skirt dims into the fog
			var edge := minf(
				minf(x0 - CityLayout.X0, CityLayout.X1 - x1),
				minf(z0 - CityLayout.Z0, CityLayout.Z1 - z1))
			var fade := clampf(1.0 + edge / 400.0, 0.15, 1.0)
			col = col * fade
			if rd < 60.0:
				col = Color(0.30 * v, 0.28 * v, 0.24 * v)   # quay stone
			elif _city.zone_at(Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)) == CityLayout.Zone.PARK:
				col = Color(0.13 * v, 0.20 * v, 0.11 * v)
			st.set_color(col)
			_add_quad(st,
				Vector3(x0, y00, z0), Vector3(x1, y10, z0),
				Vector3(x1, y11, z1), Vector3(x0, y01, z1))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	mi.material_override = m
	add_child(mi)


func _h(x: int, z: int) -> float:
	var s := sin(float(x) * 127.1 + float(z) * 311.7) * 43758.5453
	return s - floor(s)


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


func _road_ribbons() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in _city.roads_major:
		# carriageway + sidewalk strips up to the building faces
		_ribbon(st, r, 22.0, 0.12, Color(0.115, 0.115, 0.135))
		# a faint warm traffic wash down the spine — from the air it
		# reads as the city's lit arteries, not a bare canyon
		_ribbon(st, r, 0.6, 0.17, Color(0.9, 0.62, 0.28), 8.0, 8.6,
			Color(0.9, 0.62, 0.28))
		_ribbon(st, r, 2.0, 0.11, Color(0.0, 0.0, 0.0), 11.0, 14.0,
			Color(0.155, 0.155, 0.175))     # pavements
		# solid edge lines + centreline + two lane lines each direction
		_ribbon(st, r, 0.02, 0.16, Color(0.0, 0.0, 0.0), 10.4, 10.6,
			Color(0.8, 0.8, 0.75))
		_ribbon(st, r, 0.35, 0.16, Color(0.9, 0.74, 0.3))
		_lane_dash(st, r, 5.5, Color(0.85, 0.85, 0.8))
		_lane_dash(st, r, -5.5, Color(0.85, 0.85, 0.8))
	for r in _city.roads_minor:
		_ribbon(st, r, 9.0, 0.14, Color(0.12, 0.12, 0.14))
		_ribbon(st, r, 0.15, 0.16, Color(0.6, 0.6, 0.55))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Roads"
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	mi.material_override = m
	add_child(mi)


func _lane_dash(st: SurfaceTool, pts: PackedVector2Array, off: float, col: Color) -> void:
	# broken lane line: 3 m dash / 6 m gap, offset `off` metres from the
	# centreline — reads as lane separation at street level
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var seg := p1 - p0
		var len := seg.length()
		if len < 9.0:
			continue
		var dir := seg / len
		var n := Vector2(-dir.y, dir.x)
		var s := 0.0
		while s + 3.0 < len:
			var a0 := p0 + dir * s + n * off
			var a1 := p0 + dir * (s + 3.0) + n * off
			var y0: float = _hf.h(a0.x, a0.y) + 0.16
			var y1: float = _hf.h(a1.x, a1.y) + 0.16
			if y0 < -2.0 or y1 < -2.0:
				break
			var hw := 0.09
			st.set_color(col)
			_add_quad(st,
				Vector3(a0.x + n.x * hw, y0, a0.y + n.y * hw),
				Vector3(a1.x + n.x * hw, y1, a1.y + n.y * hw),
				Vector3(a1.x - n.x * hw, y1, a1.y - n.y * hw),
				Vector3(a0.x - n.x * hw, y0, a0.y - n.y * hw))
			s += 9.0


func _ribbon(st: SurfaceTool, pts: PackedVector2Array, w: float, lift: float, col: Color,
		edge_lo := -1.0, edge_hi := -1.0, edge_col := Color(0, 0, 0, 0)) -> void:
	var hw := w * 0.5
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var t: Vector2 = (p1 - p0).normalized()
		var n := Vector2(-t.y, t.x)
		var y0: float = _hf.h(p0.x, p0.y) + lift
		var y1: float = _hf.h(p1.x, p1.y) + lift
		# a street never dives into the canal — the bridge carries
		# the crossing, the grid just stops at the quay
		if y0 < -2.0 or y1 < -2.0:
			continue
		var v00 := Vector3(p0.x + n.x * hw, y0, p0.y + n.y * hw)
		var v01 := Vector3(p0.x - n.x * hw, y0, p0.y - n.y * hw)
		var v10 := Vector3(p1.x + n.x * hw, y1, p1.y + n.y * hw)
		var v11 := Vector3(p1.x - n.x * hw, y1, p1.y - n.y * hw)
		st.set_color(col)
		_add_quad(st, v00, v10, v11, v01)
		if edge_lo >= 0.0:
			# kerb glow strip just outside the carriageway edge
			var e00 := Vector3(p0.x + n.x * edge_lo, y0 - 0.02, p0.y + n.y * edge_lo)
			var e01 := Vector3(p0.x + n.x * edge_hi, y0 - 0.02, p0.y + n.y * edge_hi)
			var e10 := Vector3(p1.x + n.x * edge_lo, y1 - 0.02, p1.y + n.y * edge_lo)
			var e11 := Vector3(p1.x + n.x * edge_hi, y1 - 0.02, p1.y + n.y * edge_hi)
			st.set_color(edge_col)
			_add_quad(st, e00, e10, e11, e01)
			var f00 := Vector3(p0.x - n.x * edge_lo, y0 - 0.02, p0.y - n.y * edge_lo)
			var f01 := Vector3(p0.x - n.x * edge_hi, y0 - 0.02, p0.y - n.y * edge_hi)
			var f10 := Vector3(p1.x - n.x * edge_lo, y1 - 0.02, p1.y - n.y * edge_lo)
			var f11 := Vector3(p1.x - n.x * edge_hi, y1 - 0.02, p1.y - n.y * edge_hi)
			st.set_color(edge_col)
			_add_quad(st, f01, f11, f10, f00)


func _canal() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: PackedVector2Array = _city.river_pts
	var hw := 42.0
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var t: Vector2 = (p1 - p0).normalized()
		var n := Vector2(-t.y, t.x)
		var a := Vector3(p0.x + n.x * hw, -6.0, p0.y + n.y * hw)
		var b := Vector3(p1.x + n.x * hw, -6.0, p1.y + n.y * hw)
		var c := Vector3(p1.x - n.x * hw, -6.0, p1.y - n.y * hw)
		var d := Vector3(p0.x - n.x * hw, -6.0, p0.y - n.y * hw)
		st.set_color(Color(0.05, 0.14, 0.18))
		_add_quad(st, a, b, c, d)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Canal"
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = load("res://gfx/canal.gdshader")
	mi.material_override = m
	add_child(mi)

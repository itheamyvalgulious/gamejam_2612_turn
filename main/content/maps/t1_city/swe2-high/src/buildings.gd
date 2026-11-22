extends Node3D

## Building generator: each lot -> a mesh with footprint extrusion,
## stepped massing, window-grid UV data baked into vertex COLOR,
## and a per-instance seed for the facade shader.

const CityLayout = preload("res://src/city.gd")

var city: RefCounted
var terrain_h: Callable         # returns ground y at (x,z)
var mm_wall: MultiMesh
var mm_glass: MultiMesh
var mm_roof: MultiMesh
var _wall_mi: MultiMeshInstance3D
var _glass_mi: MultiMeshInstance3D
var _roof_mi: MultiMeshInstance3D


func _hash(seed: int, i: int) -> float:
	var s := sin(float(seed) * 91.7 + float(i) * 37.3) * 43758.5453
	return s - floor(s)


func build(c: CityLayout, hf: Callable) -> void:
	city = c
	terrain_h = hf
	mm_wall = MultiMesh.new()
	mm_wall.transform_format = MultiMesh.TRANSFORM_3D
	mm_wall.use_colors = true
	mm_wall.use_custom_data = true
	mm_glass = MultiMesh.new()
	mm_glass.transform_format = MultiMesh.TRANSFORM_3D
	mm_glass.use_colors = true
	mm_glass.use_custom_data = true
	mm_roof = MultiMesh.new()
	mm_roof.transform_format = MultiMesh.TRANSFORM_3D
	mm_roof.use_colors = true

	var wall_mesh := _unit_box()
	var glass_mesh := _unit_glass()
	var roof_mesh := _unit_roof()

	var wall_t: Array = []
	var wall_c: Array = []
	var wall_d: Array = []
	var glass_t: Array = []
	var glass_c: Array = []
	var glass_d: Array = []
	var roof_t: Array = []
	var roof_c: Array = []

	var dbg_cbd := false
	for lot in city.lots:
		_emit_lot(lot, wall_t, wall_c, wall_d,
			glass_t, glass_c, glass_d, roof_t, roof_c)
		if not dbg_cbd and lot["zone"] == CityLayout.Zone.CBD:
			var pp: PackedVector2Array = lot["poly"]
			print("CBDLOT ", pp[0], " ", pp[2])
			dbg_cbd = true

	mm_wall.instance_count = wall_t.size()
	mm_wall.mesh = wall_mesh
	# glass instances disabled: two window-grid skins (wall + glass) over
	# the same slab double-draw every aperture and their parallax/hash
	# mismatches read as speckle noise at every distance. The facade
	# shader renders lit panes itself; revisit only for real reflections.
	mm_glass.instance_count = 0
	mm_glass.mesh = glass_mesh
	mm_roof.instance_count = roof_t.size()
	mm_roof.mesh = roof_mesh
	for i in wall_t.size():
		mm_wall.set_instance_transform(i, wall_t[i])
		mm_wall.set_instance_color(i, wall_c[i])
		mm_wall.set_instance_custom_data(i, wall_d[i])
	for i in glass_t.size():
		mm_glass.set_instance_transform(i, glass_t[i])
		mm_glass.set_instance_color(i, glass_c[i])
		mm_glass.set_instance_custom_data(i, glass_d[i])
	for i in roof_t.size():
		mm_roof.set_instance_transform(i, roof_t[i])
		mm_roof.set_instance_color(i, roof_c[i])

	_wall_mi = MultiMeshInstance3D.new()
	_wall_mi.name = "Walls"
	_wall_mi.multimesh = mm_wall
	var wm := ShaderMaterial.new()
	wm.shader = load("res://gfx/facade.gdshader")
	_wall_mi.material_override = wm
	add_child(_wall_mi)

	_glass_mi = MultiMeshInstance3D.new()
	_glass_mi.name = "Glass"
	_glass_mi.multimesh = mm_glass
	var gm := ShaderMaterial.new()
	gm.shader = load("res://gfx/glass.gdshader")
	_glass_mi.material_override = gm
	add_child(_glass_mi)

	_roof_mi = MultiMeshInstance3D.new()
	_roof_mi.name = "Roofs"
	_roof_mi.multimesh = mm_roof
	var rm := ShaderMaterial.new()
	rm.shader = load("res://gfx/roof.gdshader")
	_roof_mi.material_override = rm
	add_child(_roof_mi)


# ------------------------------------------------------------- meshes -----
func _unit_box() -> ArrayMesh:
	# unit box 1×1×1 centred at origin, walls only (no floor) —
	# scaled per-instance; UV.y is the vertical fraction for window rows
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [
		[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 1, -0.5), Vector3(-0.5, 1, -0.5)],
		[Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 1, 0.5), Vector3(0.5, 1, -0.5)],
		[Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5), Vector3(-0.5, 1, 0.5), Vector3(0.5, 1, 0.5)],
		[Vector3(-0.5, 0, 0.5), Vector3(-0.5, 0, -0.5), Vector3(-0.5, 1, -0.5), Vector3(-0.5, 1, 0.5)],
	]
	for q in quads:
		var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
		st.set_normal(n)
		st.set_uv(Vector2(0, 0)); st.add_vertex(q[0])
		st.set_uv(Vector2(1, 0)); st.add_vertex(q[1])
		st.set_uv(Vector2(1, 1)); st.add_vertex(q[2])
		st.set_uv(Vector2(0, 0)); st.add_vertex(q[0])
		st.set_uv(Vector2(1, 1)); st.add_vertex(q[2])
		st.set_uv(Vector2(0, 1)); st.add_vertex(q[3])
	return st.commit()


func _unit_glass() -> ArrayMesh:
	# facade plane slightly proud of the wall — the shader cuts window
	# apertures and lights interiors
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [
		[Vector3(-0.52, 0.02, -0.5), Vector3(0.52, 0.02, -0.5), Vector3(0.52, 0.98, -0.5), Vector3(-0.52, 0.98, -0.5)],
		[Vector3(0.5, 0.02, -0.52), Vector3(0.5, 0.02, 0.52), Vector3(0.5, 0.98, 0.52), Vector3(0.5, 0.98, -0.52)],
		[Vector3(0.52, 0.02, 0.5), Vector3(-0.52, 0.02, 0.5), Vector3(-0.52, 0.98, 0.5), Vector3(0.52, 0.98, 0.5)],
		[Vector3(-0.5, 0.02, 0.52), Vector3(-0.5, 0.02, -0.52), Vector3(-0.5, 0.98, -0.52), Vector3(-0.5, 0.98, 0.52)],
	]
	for q in quads:
		var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
		st.set_normal(n)
		st.set_uv(Vector2(0, 0)); st.add_vertex(q[0])
		st.set_uv(Vector2(1, 0)); st.add_vertex(q[1])
		st.set_uv(Vector2(1, 1)); st.add_vertex(q[2])
		st.set_uv(Vector2(0, 0)); st.add_vertex(q[0])
		st.set_uv(Vector2(1, 1)); st.add_vertex(q[2])
		st.set_uv(Vector2(0, 1)); st.add_vertex(q[3])
	return st.commit()


func _unit_roof() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := [Vector3(-0.5, 1.0, -0.5), Vector3(0.5, 1.0, -0.5),
		Vector3(0.5, 1.0, 0.5), Vector3(-0.5, 1.0, 0.5)]
	var n := Vector3.UP
	st.set_normal(n)
	st.set_uv(Vector2(0, 0)); st.add_vertex(q[0])
	st.set_uv(Vector2(1, 0)); st.add_vertex(q[1])
	st.set_uv(Vector2(1, 1)); st.add_vertex(q[2])
	st.set_uv(Vector2(0, 0)); st.add_vertex(q[0])
	st.set_uv(Vector2(1, 1)); st.add_vertex(q[2])
	st.set_uv(Vector2(0, 1)); st.add_vertex(q[3])
	return st.commit()


# -------------------------------------------------------------- emit -----
func _emit_lot(lot: Dictionary,
		wall_t: Array, wall_c: Array, wall_d: Array,
		glass_t: Array, glass_c: Array, glass_d: Array,
		roof_t: Array, roof_c: Array) -> void:
	var poly: PackedVector2Array = lot["poly"]
	var zone: int = lot["zone"]
	var seed: int = lot["seed"]
	# footprint = polygon's AABB (fine — sub-lots are already tight)
	var mn := poly[0]
	var mx := poly[0]
	for v in poly:
		mn.x = minf(mn.x, v.x); mn.y = minf(mn.y, v.y)
		mx.x = maxf(mx.x, v.x); mx.y = maxf(mx.y, v.y)
	var cx := (mn.x + mx.x) * 0.5
	var cz := (mn.y + mx.y) * 0.5
	var w := mx.x - mn.x
	var d := mx.y - mn.y
	if w < 8.0 or d < 8.0:
		return
	# ground the base on the lot's LOWEST corner — terrain relief
	# between centre and corner was leaving podiums hovering
	var gy: float = terrain_h.call(cx, cz)
	for v in poly:
		gy = minf(gy, terrain_h.call(v.x, v.y))
	gy -= 0.4

	# massing per zone — CBD towers run tall and slim so the skyline has
	# needles, not slabs; residential stays low
	var floors: int
	var hgt: float
	match zone:
		CityLayout.Zone.CBD:
			floors = 18 + int(_hash(seed, 0) * 40.0)
			hgt = floors * 3.3
		CityLayout.Zone.IND:
			floors = 1 + int(_hash(seed, 1) * 3.0)
			hgt = floors * 7.0 + 6.0
		CityLayout.Zone.SCH:
			floors = 3 + int(_hash(seed, 2) * 4.0)
			hgt = floors * 3.6
		_:  # RES
			floors = 2 + int(_hash(seed, 3) * 6.0)
			hgt = floors * 3.1

	# podium: 3–4 storeys of streetwall — shopfronts below offices,
	# the tower shaft rises from inside
	var pod_f := mini(4, maxi(2, floors / 5))
	var pod_h := pod_f * 3.4
	# slim tower footprints — CBD needles, everything else keeps a
	# chunkier mass
	var slim := 0.42 if zone == CityLayout.Zone.CBD else 0.6
	var tw := w * (slim + _hash(seed, 4) * 0.22)
	var td := d * (slim + _hash(seed, 5) * 0.22)
	var rot := _hash(seed, 6) * TAU

	# facade albedo: real materials — CBD glass-concrete mix, school
	# warm brick, res mid-tones. Night dim comes from light, not from
	# painting the walls black
	var tint := Color(0.9, 0.9, 0.9)
	match zone:
		CityLayout.Zone.CBD:  tint = Color(0.30, 0.32, 0.40)
		CityLayout.Zone.IND:  tint = Color(0.30, 0.27, 0.24)
		CityLayout.Zone.SCH:  tint = Color(0.50, 0.42, 0.32)
		_:                    tint = Color(0.36, 0.33, 0.28)
	# per-lot variance so the skyline isn't one paint — small range,
	# never enough to black out a whole face
	tint = tint.darkened(_hash(seed, 15) * 0.12)

	# schools read differently: a classroom bar + taller gymnasium box —
	# a campus mass, not a slab
	if zone == CityLayout.Zone.SCH:
		var gym_w := w * 0.45
		var gym_d := d * 0.5
		var bar_w := w * 0.8
		var bar_d := d * 0.28
		var gym_h := 10.0 + _hash(seed, 30) * 4.0
		var bar_h := floors * 3.6
		var gym_basis := Basis.from_euler(Vector3(0, rot, 0)).scaled(
			Vector3(gym_w, gym_h, gym_d))
		wall_t.append(Transform3D(gym_basis,
			Vector3(cx - w * 0.12, gy, cz - d * 0.08)))
		wall_c.append(Color(0.45, 0.32, 0.22))
		wall_d.append(Color(_hash(seed, 31), int(gym_h / 3.6), zone, 0.0))
		var bar_basis := Basis.from_euler(Vector3(0, rot, 0)).scaled(
			Vector3(bar_w, bar_h, bar_d))
		wall_t.append(Transform3D(bar_basis,
			Vector3(cx + w * 0.02, gy, cz + d * 0.25)))
		wall_c.append(tint)
		wall_d.append(Color(_hash(seed, 32), floors, zone, 0.0))
		glass_t.append(Transform3D(gym_basis,
			Vector3(cx - w * 0.12, gy, cz - d * 0.08)))
		glass_c.append(Color(0.5, 0.4, 0.3))
		glass_d.append(Color(_hash(seed, 33), int(gym_h / 3.6), zone, 0.0))
		glass_t.append(Transform3D(bar_basis,
			Vector3(cx + w * 0.02, gy, cz + d * 0.25)))
		glass_c.append(tint)
		glass_d.append(Color(_hash(seed, 34), floors, zone, 0.0))
		roof_t.append(Transform3D(gym_basis,
			Vector3(cx - w * 0.12, gy, cz - d * 0.08)))
		roof_c.append(Color(0.30, 0.22, 0.16))
		roof_t.append(Transform3D(bar_basis,
			Vector3(cx + w * 0.02, gy, cz + d * 0.25)))
		roof_c.append(tint.darkened(0.5))
		return

	# NOTE: Transform3D.scaled() scales the origin too — scale the BASIS
	# only so the box lands at (cx, gy, cz), not at scale×position
	# podium glass box shrinks 6% inside the wall so its panes sit IN
	# the apertures, not pasted over the concrete — two skins at the
	# same size z-fight into the giant pane noise seen in the street
	# shot
	var pod_basis := Basis.from_euler(Vector3(0, rot, 0)).scaled(
		Vector3(w, pod_h, d))
	var pod_glass_basis := Basis.from_euler(Vector3(0, rot, 0)).scaled(
		Vector3(w * 0.94, pod_h * 0.96, d * 0.94))
	# wall + glass share ONE seed — misaligned window grids over the
	# same slab moiré into white-noise speckle; podiums sink 0.5 m so
	# bases bite the pavement, never hover
	var pod_seed := _hash(seed, 7)
	# sink 1.4 m — the podium base must bite through pavement into
	# the ground apron, or relief between lot corners leaves the
	# building floating over a black seam
	wall_t.append(Transform3D(pod_basis, Vector3(cx, gy - 1.4, cz)))
	wall_c.append(tint.darkened(0.15))
	wall_d.append(Color(pod_seed, pod_f, zone, 0.0))
	glass_t.append(Transform3D(pod_glass_basis, Vector3(cx, gy - 1.4, cz)))
	glass_c.append(tint)
	glass_d.append(Color(pod_seed, pod_f, zone, 0.0))
	# tower shaft above podium
	var th := hgt - pod_h
	if th > 0.5:
		var tow_basis := Basis.from_euler(Vector3(0, rot, 0)).scaled(
			Vector3(tw, th, td))
		var tow_glass_basis := Basis.from_euler(Vector3(0, rot, 0)).scaled(
			Vector3(tw * 0.94, th * 0.98, td * 0.94))
		var tow_org := Vector3(cx, gy + pod_h - 1.4, cz)
		var tow_seed := _hash(seed, 9)
		wall_t.append(Transform3D(tow_basis, tow_org))
		wall_c.append(tint)
		wall_d.append(Color(tow_seed, floors - pod_f, zone, 0.0))
		glass_t.append(Transform3D(tow_glass_basis, tow_org))
		glass_c.append(tint)
		glass_d.append(Color(tow_seed, floors - pod_f, zone, 0.0))
		# roof cap
		# roof quad is a unit cell at local y=1 — cap at the tower's
		# actual top, not pod_h+1 (a bug that hid it inside the shaft)
		roof_t.append(Transform3D(
			Basis.from_euler(Vector3(0, rot, 0)).scaled(Vector3(tw, 1.0, td)),
			Vector3(cx, gy + pod_h + th - 2.0, cz)))
		roof_c.append(tint.darkened(0.4))
	# podium roof — cap at podium top (was buried inside the slab)
	roof_t.append(Transform3D(
		Basis.from_euler(Vector3(0, rot, 0)).scaled(Vector3(w, 1.0, d)),
		Vector3(cx, gy + pod_h - 1.8, cz)))
	roof_c.append(tint.darkened(0.5))

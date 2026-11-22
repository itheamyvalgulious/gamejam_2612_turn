extends Node3D

# Physical "arc generator" hilt. It replaces the old arc-formed grip:
# a dark machined body with gold energy rings, a heavy pommel cell,
# a swept crossguard and a clawed emitter collar at the blade root.

var energy := 1.0

var _dark: StandardMaterial3D
var _dark_edge: StandardMaterial3D
var _bronze: StandardMaterial3D
var _gold: StandardMaterial3D
var _gold_hot: StandardMaterial3D
var _core: StandardMaterial3D
var _emissive: Array[StandardMaterial3D] = []
var _emissive_base: Array[float] = []
var _lights: Array[OmniLight3D] = []
var _light_base: Array[float] = []
var _time := 0.0

func _ready() -> void:
	_build_materials()
	_build_grip()
	_build_guard()
	_build_emitter()
	_build_pommel()
	_build_lights()
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	var e := clampf(energy, 0.6, 1.9)
	var flicker := 0.975 + 0.018 * sin(_time * 2.1) + 0.007 * sin(_time * 5.3)
	for i in range(_emissive.size()):
		_emissive[i].emission_energy_multiplier = _emissive_base[i] * (0.90 + 0.10 * e) * flicker
	for i in range(_lights.size()):
		_lights[i].light_energy = _light_base[i] * (0.90 + 0.10 * e)

func _build_materials() -> void:
	_dark = _material(Color(0.055, 0.062, 0.080), 0.68, 0.36)
	_dark.rim_enabled = true
	_dark.rim = 0.35
	_dark.rim_tint = 0.45

	_dark_edge = _material(Color(0.075, 0.085, 0.105), 0.95, 0.20)
	_dark_edge.rim_enabled = true
	_dark_edge.rim = 0.45
	_dark_edge.rim_tint = 0.35

	_bronze = _material(Color(0.30, 0.19, 0.09), 0.86, 0.28, Color(0.45, 0.20, 0.03), 0.22)
	_bronze.rim_enabled = true
	_bronze.rim = 0.4
	_bronze.rim_tint = 0.5

	_gold = _material(Color(0.80, 0.50, 0.12), 0.92, 0.24, Color(1.0, 0.46, 0.07), 0.45)
	_gold_hot = _material(Color(1.0, 0.68, 0.24), 0.35, 0.18, Color(1.0, 0.48, 0.09), 0.95)
	_core = _material(Color(1.0, 0.82, 0.45), 0.0, 0.10, Color(1.0, 0.52, 0.10), 1.0)

func _material(
	albedo: Color,
	metallic: float,
	roughness: float,
	emission := Color(0.0, 0.0, 0.0),
	emission_energy := 0.0
) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	m.metallic_specular = 0.55
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
		_emissive.append(m)
		_emissive_base.append(emission_energy)
	return m

func _add_mesh(
	mesh: Mesh,
	material: Material,
	position: Vector3,
	rotation := Vector3.ZERO,
	scale := Vector3.ONE
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = position
	mi.rotation = rotation
	mi.scale = scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _cylinder(
	top_radius: float,
	bottom_radius: float,
	height: float,
	segments: int,
	material: Material,
	position: Vector3,
	rotation := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 2
	return _add_mesh(mesh, material, position, rotation)

func _torus(
	inner_radius: float,
	outer_radius: float,
	material: Material,
	position: Vector3,
	rotation := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 20
	mesh.ring_segments = 6
	return _add_mesh(mesh, material, position, rotation)

func _sphere(radius: float, material: Material, position: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _add_mesh(mesh, material, position)

func _box(size: Vector3, material: Material, position: Vector3, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(mesh, material, position, rotation)

func _build_grip() -> void:
	# Machined main body.
	_cylinder(0.048, 0.055, 0.44, 12, _dark, Vector3(0.0, -0.345, 0.0))
	# Collars.
	_cylinder(0.060, 0.055, 0.055, 12, _dark_edge, Vector3(0.0, -0.098, 0.0))
	_cylinder(0.061, 0.071, 0.055, 12, _dark_edge, Vector3(0.0, -0.575, 0.0))

	# Gold energy bands and dark knurled ribs.
	for i in range(7):
		var y := -0.155 - float(i) * 0.0575
		var is_gold := i == 1 or i == 3 or i == 5
		var material: Material = _gold if is_gold else _dark_edge
		var inner := 0.0505 if is_gold else 0.0515
		var outer := 0.0595 if is_gold else 0.0605
		_torus(inner, outer, material, Vector3(0.0, y, 0.0))

	# Front control window and energy channel.
	_box(Vector3(0.044, 0.235, 0.018), _dark, Vector3(0.0, -0.315, 0.048))
	_box(Vector3(0.012, 0.176, 0.007), _gold_hot, Vector3(0.0, -0.315, 0.059))
	for i in range(3):
		_sphere(0.0045, _gold_hot, Vector3(0.0, -0.205 - float(i) * 0.016, 0.060))
	# A small thumb switch.
	_box(Vector3(0.022, 0.030, 0.014), _dark_edge, Vector3(0.026, -0.155, 0.050), Vector3(0.0, 0.0, -0.15))
	_box(Vector3(0.010, 0.016, 0.006), _gold, Vector3(0.026, -0.155, 0.059), Vector3(0.0, 0.0, -0.15))

	# Thin gold ring just under the emitter shoulder.
	_torus(0.061, 0.068, _gold, Vector3(0.0, -0.085, 0.0))
	_build_helix()

func _build_guard() -> void:
	# Central guard block, mostly covered by the emitter collar.
	_cylinder(0.095, 0.090, 0.105, 8, _dark_edge, Vector3(0.0, -0.025, 0.0))

	# Two short swept quillons: faceted tapering cones with gold inlays.
	# They are deliberately narrow relative to the old wing-like guard: the
	# blade must own the silhouette.
	for side: float in [-1.0, 1.0]:
		var tilt := 0.30
		var rot := Vector3(0.0, 0.0, -side * (PI * 0.5 - tilt))
		var wing := CylinderMesh.new()
		wing.top_radius = 0.011
		wing.bottom_radius = 0.050
		wing.height = 0.34
		wing.radial_segments = 8
		wing.rings = 3
		_add_mesh(wing, _bronze, Vector3(side * 0.185, -0.014, 0.0), rot, Vector3(1.20, 1.0, 0.80))

		# Base collar around each quillon.
		_torus(0.038, 0.049, _gold, Vector3(side * 0.095, 0.004, 0.0), Vector3(0.0, 0.0, PI * 0.5))
		# A thinner ring midway.
		_torus(0.028, 0.035, _gold, Vector3(side * 0.235, 0.030, 0.0), Vector3(0.0, 0.0, PI * 0.5))
		# Hot tip.
		_sphere(0.014, _gold_hot, Vector3(side * 0.353, 0.056, 0.0))
		# Emissive line running along the front face of the quillon.
		var line := CylinderMesh.new()
		line.top_radius = 0.0035
		line.bottom_radius = 0.0055
		line.height = 0.20
		line.radial_segments = 6
		line.rings = 1
		_add_mesh(line, _gold_hot, Vector3(side * 0.225, 0.038, 0.041), rot)

func _build_emitter() -> void:
	# Outer collar at the blade root.
	_cylinder(0.088, 0.108, 0.125, 12, _dark, Vector3(0.0, 0.005, 0.0))
	_torus(0.087, 0.101, _gold, Vector3(0.0, 0.058, 0.0))
	_torus(0.066, 0.075, _gold_hot, Vector3(0.0, 0.032, 0.0))
	_torus(0.094, 0.103, _dark_edge, Vector3(0.0, -0.048, 0.0))

	# Glowing throat / energy core.
	_sphere(0.034, _core, Vector3(0.0, 0.052, 0.0))
	_cylinder(0.035, 0.050, 0.018, 12, _gold_hot, Vector3(0.0, 0.077, 0.0))

	# Four emitter claws.
	for i in range(4):
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, 0.015, 0.0)
		pivot.rotation.y = float(i) * PI * 0.5 + PI * 0.25
		add_child(pivot)
		var claw := CylinderMesh.new()
		claw.top_radius = 0.0045
		claw.bottom_radius = 0.020
		claw.height = 0.185
		claw.radial_segments = 6
		claw.rings = 2
		var mi := MeshInstance3D.new()
		mi.mesh = claw
		mi.material_override = _bronze
		mi.position = Vector3(0.095, 0.085, 0.0)
		mi.rotation.z = -0.34
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)

func _build_pommel() -> void:
	# Power-cell pommel.
	_cylinder(0.060, 0.086, 0.13, 8, _bronze, Vector3(0.0, -0.635, 0.0))
	_torus(0.068, 0.083, _gold, Vector3(0.0, -0.635, 0.0))
	_cylinder(0.082, 0.055, 0.034, 8, _dark_edge, Vector3(0.0, -0.713, 0.0))
	_cylinder(0.052, 0.052, 0.010, 12, _gold_hot, Vector3(0.0, -0.733, 0.0))
	_torus(0.042, 0.050, _gold, Vector3(0.0, -0.656, 0.0))
	# Front-facing power cell on the pommel.
	_cylinder(0.026, 0.026, 0.010, 12, _gold_hot, Vector3(0.0, -0.638, 0.079), Vector3(PI * 0.5, 0.0, 0.0))
	_torus(0.028, 0.035, _gold, Vector3(0.0, -0.638, 0.078), Vector3(PI * 0.5, 0.0, 0.0))
	for i in range(4):
		var a := float(i) * PI * 0.5 + PI * 0.25
		_sphere(0.008, _gold, Vector3(cos(a) * 0.080, -0.690, sin(a) * 0.080))

func _build_helix() -> void:
	var points: Array[Vector3] = []
	var turns := 3.2
	var count := 86
	for i in range(count + 1):
		var t := float(i) / float(count)
		var y := lerpf(-0.545, -0.145, t)
		var angle := t * turns * TAU
		points.append(Vector3(cos(angle) * 0.0585, y, sin(angle) * 0.0585))
	var tube := _tube_mesh(points, 0.0055, 5)
	var mi := _add_mesh(tube, _gold, Vector3.ZERO)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _tube_mesh(points: Array[Vector3], radius: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in range(points.size()):
		var tangent: Vector3
		if i == 0:
			tangent = points[1] - points[0]
		elif i == points.size() - 1:
			tangent = points[i] - points[i - 1]
		else:
			tangent = points[i + 1] - points[i - 1]
		tangent = tangent.normalized()
		var ref := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var normal := tangent.cross(ref).normalized()
		var binormal := tangent.cross(normal).normalized()
		var ring: Array[Vector3] = []
		for j in range(sides):
			var a := TAU * float(j) / float(sides)
			ring.append(points[i] + normal * cos(a) * radius + binormal * sin(a) * radius)
		rings.append(ring)
	for i in range(rings.size() - 1):
		for j in range(sides):
			var v0: Vector3 = rings[i][j]
			var v1: Vector3 = rings[i][(j + 1) % sides]
			var v2: Vector3 = rings[i + 1][(j + 1) % sides]
			var v3: Vector3 = rings[i + 1][j]
			st.add_vertex(v0)
			st.add_vertex(v1)
			st.add_vertex(v2)
			st.add_vertex(v0)
			st.add_vertex(v2)
			st.add_vertex(v3)
	st.generate_normals()
	return st.commit()

func _build_lights() -> void:
	_add_light(Vector3(0.65, 0.52, 1.30), Color(1.0, 0.78, 0.55), 7.0, 3.6)
	_add_light(Vector3(-0.65, 0.35, -0.70), Color(0.30, 0.46, 1.0), 6.5, 2.8)
	_add_light(Vector3(-1.10, -0.15, 0.30), Color(0.25, 0.38, 0.85), 2.4, 2.4)
	_add_light(Vector3(0.0, -0.52, 0.85), Color(1.0, 0.62, 0.30), 2.2, 2.4)
	_add_light(Vector3(0.0, 0.07, 0.30), Color(1.0, 0.52, 0.16), 0.45, 0.9)
	_add_light(Vector3(0.45, -0.20, -1.05), Color(0.58, 0.70, 1.0), 2.4, 2.8)

func _add_light(position: Vector3, color: Color, light_energy: float, range_value: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = light_energy
	light.omni_range = range_value
	light.shadow_enabled = false
	add_child(light)
	_lights.append(light)
	_light_base.append(light_energy)
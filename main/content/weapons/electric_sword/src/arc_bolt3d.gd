class_name ArcBolt3D
extends MeshInstance3D

const ARC_SHADER: Shader = preload("res://shaders/arc_ribbon.gdshader")

var life := 0.1
var age := 0.0
var strength := 1.0
var instant := false
var _fade := 1.0
var _material: ShaderMaterial

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 3.0
	_material = ShaderMaterial.new()
	_material.shader = ARC_SHADER
	material_override = _material
	set_process(true)

func setup(edges: Array, rng: RandomNumberGenerator, lifetime: float, bolt_strength: float, energy: float, instant_mode := false) -> void:
	life = lifetime
	strength = bolt_strength
	instant = instant_mode
	age = 0.0
	mesh = _build_mesh(edges, rng)
	if _material != null:
		# Blade bolts start invisible so a newly added bolt is not rendered at
		# full brightness for one frame before its first fade-in tick.
		# Escape bolts are intentionally instant: they appear at full strength
		# and vanish abruptly, like real restriking arcs.
		_material.set_shader_parameter("fade", strength if instant else 0.0)
		_material.set_shader_parameter("intensity", energy)
		_material.set_shader_parameter("screen_size", get_viewport().get_visible_rect().size)
	else:
		push_warning("ArcBolt3D.setup called before _ready()")

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	if instant:
		_fade = strength
		if _material != null:
			_material.set_shader_parameter("fade", strength)
		return
	var t := age / life
	var fade_in := smoothstep(0.0, 0.20, t)
	var fade_out := 1.0 - smoothstep(0.64, 1.0, t)
	_fade = fade_in * fade_out * strength
	if _material != null:
		_material.set_shader_parameter("fade", _fade)

func _build_mesh(edges: Array, rng: RandomNumberGenerator) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var indices := PackedInt32Array()

	for edge in edges:
		var a: Vector3 = edge["a"]
		var b: Vector3 = edge["b"]
		var width: float = edge["width"]
		var energy: float = edge["energy"]
		var hue: float = edge["hue"]
		var phase: float = edge["phase"]
		var leader: bool = edge.get("leader", false)
		var leader_flag := 1.0 if leader else 0.0

		var pts := _jagged(a, b, width, energy, rng)
		for i in range(pts.size() - 1):
			_add_segment(pts[i], pts[i + 1], width, energy, hue, phase, leader_flag, verts, uvs, custom0, custom1, indices)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_INDEX] = indices

	var flags := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_INDEX
	flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh

func _jagged(a: Vector3, b: Vector3, width: float, energy: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var d := b - a
	var length := d.length()
	var pts := PackedVector3Array()
	pts.append(a)
	if length < 0.0001:
		pts.append(b)
		return pts

	var dir := d / length
	var perp_a := dir.cross(Vector3.UP)
	if perp_a.length_squared() < 0.0001:
		perp_a = dir.cross(Vector3.RIGHT)
	perp_a = perp_a.normalized()
	var perp_b := dir.cross(perp_a).normalized()

	# Amplitudes stay small relative to the step, so branch endpoints still
	# join cleanly while the body of each channel visibly snakes in 3D.
	var amp := clampf(length * 0.065, 0.0018, 0.0075)
	amp *= lerpf(1.15, 0.8, clampf(width / 0.052, 0.0, 1.0))
	var bow_a := rng.randf_range(-1.0, 1.0) * amp * 1.15
	var bow_b := rng.randf_range(-1.0, 1.0) * amp * 1.15

	var steps := clampi(roundi(length / 0.068), 2, 4)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var env := sin(t * PI)
		var off := perp_a * (bow_a * env + rng.randf_range(-amp, amp) * env)
		off += perp_b * (bow_b * env + rng.randf_range(-amp, amp) * env)
		pts.append(a.lerp(b, t) + off)
	pts.append(b)
	return pts

func _add_segment(
	p0: Vector3,
	p1: Vector3,
	width: float,
	energy: float,
	hue: float,
	phase: float,
	leader_flag: float,
	verts: PackedVector3Array,
	uvs: PackedVector2Array,
	custom0: PackedFloat32Array,
	custom1: PackedFloat32Array,
	indices: PackedInt32Array
) -> void:
	var base := verts.size()

	verts.append(p0)
	uvs.append(Vector2(0.0, -1.0))
	custom0.append_array([p1.x, p1.y, p1.z, width])
	custom1.append_array([energy, hue, phase, leader_flag])

	verts.append(p0)
	uvs.append(Vector2(0.0, 1.0))
	custom0.append_array([p1.x, p1.y, p1.z, width])
	custom1.append_array([energy, hue, phase, leader_flag])

	verts.append(p1)
	uvs.append(Vector2(1.0, 1.0))
	custom0.append_array([p0.x, p0.y, p0.z, width])
	custom1.append_array([energy, hue, phase, leader_flag])

	verts.append(p1)
	uvs.append(Vector2(1.0, -1.0))
	custom0.append_array([p0.x, p0.y, p0.z, width])
	custom1.append_array([energy, hue, phase, leader_flag])

	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
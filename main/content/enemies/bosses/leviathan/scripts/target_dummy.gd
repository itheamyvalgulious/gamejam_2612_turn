extends Node3D
## The "player" target: a small 1.95 m scout drone standing on the arena
## floor. Deliberately cyan/white so it reads against the boss's red-orange.
## Used by attack 1/2 and by the laser.

const MK := preload("res://scripts/kit/mesh_kit.gd")
const SK := preload("res://scripts/kit/shape_kit.gd")
const BM := preload("res://scripts/boss/boss_materials.gd")
const GLASS := preload("res://shaders/boss_glass.gdshader")

const CYAN := Color(0.22, 0.78, 1.0)
const CYAN_HOT := Color(0.75, 0.97, 1.0)

var body: Node3D
var marker: Node3D
var shield: MeshInstance3D
var shield_mat: ShaderMaterial
var flash := 0.0
var t := 0.0
var _visor_mat: StandardMaterial3D
var _marker_mat: StandardMaterial3D
var _ring_mat: ShaderMaterial
var _ring: MeshInstance3D
var _hit_light: OmniLight3D
var _base_y := 0.02


func _ready() -> void:
	_build()
	set_process(true)


func _mat(albedo: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = rough
	m.resource_name = "dummy_metal"
	return m


func _emissive(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.55)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.metallic = 0.1
	m.roughness = 0.35
	m.disable_receive_shadows = true
	return m


func _build() -> void:
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var dark := _mat(Color(0.035, 0.038, 0.048), 0.88, 0.42)
	var mid := _mat(Color(0.085, 0.09, 0.105), 0.92, 0.36)
	var steel := _mat(Color(0.30, 0.31, 0.35), 1.0, 0.28)
	var white := _mat(Color(0.62, 0.66, 0.72), 0.35, 0.42)
	var cyan := _emissive(CYAN, 5.0)
	_visor_mat = _emissive(CYAN_HOT, 7.0)

	var parts: Array = []
	# legs
	for s in [-1.0, 1.0]:
		var hip := Vector3(0.16 * s, 0.92, 0.0)
		_p(parts, MK.sphere(0.09, 10, 14), steel, hip)
		_p(parts, SK.beam(hip, Vector3(0.18 * s, 0.52, 0.02), 0.13, 0.15, 0.10, 0.12, 0.3),
			dark, Vector3.ZERO)
		_p(parts, MK.sphere(0.085, 10, 12), steel, Vector3(0.18 * s, 0.52, 0.02))
		_p(parts, SK.beam(Vector3(0.18 * s, 0.52, 0.02), Vector3(0.20 * s, 0.10, 0.0),
			0.11, 0.13, 0.08, 0.10, 0.3), mid, Vector3.ZERO)
		# boot
		_p(parts, MK.plate(0.20, 0.10, 0.36, 0.02), dark, Vector3(0.20 * s, 0.07, 0.05))
	# pelvis / waist
	_p(parts, MK.plate(0.40, 0.16, 0.26, 0.03), dark, Vector3(0, 1.00, 0))
	_p(parts, SK.beam(Vector3(0, 1.05, 0), Vector3(0, 1.20, 0), 0.16, 0.16, 0.20, 0.17, 0.3),
		mid, Vector3.ZERO)
	# torso
	_p(parts, MK.plate(0.56, 0.44, 0.30, 0.04), dark, Vector3(0, 1.34, 0))
	_p(parts, MK.plate(0.46, 0.34, 0.08, 0.02), mid, Vector3(0, 1.38, 0.16))
	_p(parts, MK.plate(0.30, 0.12, 0.04, 0.01), cyan, Vector3(0, 1.44, 0.205))
	_p(parts, MK.plate(0.52, 0.10, 0.20, 0.02), steel, Vector3(0, 1.12, 0))
	# back pack + antennae
	_p(parts, MK.plate(0.36, 0.34, 0.18, 0.03), mid, Vector3(0, 1.36, -0.19))
	_p(parts, MK.prism(8, 0.045, 0.02, 0.62), steel, Vector3(-0.12, 1.78, -0.22))
	_p(parts, MK.prism(8, 0.045, 0.02, 0.48), steel, Vector3(0.12, 1.70, -0.22))
	_p(parts, MK.sphere(0.035, 8, 10), cyan, Vector3(-0.12, 2.10, -0.22))
	# shoulders / arms
	for s2 in [-1.0, 1.0]:
		_p(parts, MK.sphere(0.12, 12, 16), mid, Vector3(0.34 * s2, 1.48, 0.0))
		_p(parts, SK.beam(Vector3(0.34 * s2, 1.48, 0), Vector3(0.40 * s2, 1.14, 0.04),
			0.12, 0.14, 0.09, 0.11, 0.3), dark, Vector3.ZERO)
		_p(parts, SK.beam(Vector3(0.40 * s2, 1.14, 0.04), Vector3(0.42 * s2, 0.82, 0.12),
			0.09, 0.11, 0.06, 0.08, 0.3), mid, Vector3.ZERO)
		_p(parts, MK.sphere(0.06, 8, 10), steel, Vector3(0.42 * s2, 0.82, 0.12))
		_p(parts, MK.plate(0.10, 0.20, 0.10, 0.02), white, Vector3(0.35 * s2, 1.54, 0.12),
			Basis(Vector3.FORWARD, 0.2 * s2))
	# neck / head
	_p(parts, MK.prism(12, 0.10, 0.08, 0.12), steel, Vector3(0, 1.60, 0))
	_p(parts, MK.sphere(0.17, 16, 22), mid, Vector3(0, 1.76, 0.01))
	_p(parts, MK.plate(0.28, 0.10, 0.06, 0.015), dark, Vector3(0, 1.78, 0.15))
	# visor
	var visor := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.24, 0.055)
	visor.mesh = q
	visor.material_override = _visor_mat
	visor.position = Vector3(0, 1.78, 0.185)
	body.add_child(visor)
	# small chin lamp
	_p(parts, MK.sphere(0.03, 8, 8), cyan, Vector3(0, 1.68, 0.16))
	for e in SK.bake(parts):
		var mi := MeshInstance3D.new()
		mi.mesh = e["mesh"]
		mi.material_override = e["mat"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		body.add_child(mi)

	# ground reticle
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = preload("res://shaders/fx_ring.gdshader")
	_ring_mat.set_shader_parameter("tint", CYAN)
	_ring_mat.set_shader_parameter("intensity", 1.5)
	_ring_mat.set_shader_parameter("progress", 0.35)
	_ring = MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(1, 1)
	_ring.mesh = rq
	_ring.material_override = _ring_mat
	_ring.rotation_degrees = Vector3(-90, 0, 0)
	_ring.position = Vector3(0, 0.045, 0)
	_ring.scale = Vector3.ONE * 4.2
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# floating marker ring + beam
	marker = Node3D.new()
	marker.position = Vector3(0, 2.55, 0)
	add_child(marker)
	_marker_mat = _emissive(CYAN, 3.2)
	var mr := MeshInstance3D.new()
	mr.mesh = MK.ring(0.32, 0.40, 0.035, 40, 0.008)
	mr.material_override = _marker_mat
	mr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(mr)
	var beam := MeshInstance3D.new()
	beam.mesh = MK.prism(12, 0.035, 0.012, 1.1)
	beam.material_override = _emissive(CYAN, 1.2)
	beam.position = Vector3(0, -0.55, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(beam)

	# hit shield bubble
	shield_mat = ShaderMaterial.new()
	shield_mat.shader = GLASS
	shield_mat.set_shader_parameter("tint", CYAN)
	shield_mat.set_shader_parameter("rim_color", CYAN_HOT)
	shield_mat.set_shader_parameter("opacity", 0.0)
	shield_mat.set_shader_parameter("pattern", 1.6)
	shield_mat.set_shader_parameter("energy", 1.4)
	shield_mat.set_shader_parameter("seed", 1.7)
	shield = MeshInstance3D.new()
	shield.mesh = MK.sphere(1.25, 24, 36, true)
	shield.material_override = shield_mat
	shield.position = Vector3(0, 1.0, 0)
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.visible = false
	add_child(shield)

	_hit_light = OmniLight3D.new()
	_hit_light.position = Vector3(0, 1.4, 0.6)
	_hit_light.light_color = CYAN
	_hit_light.light_energy = 0.0
	_hit_light.omni_range = 5.0
	_hit_light.shadow_enabled = false
	add_child(_hit_light)


func _p(parts: Array, mesh: Mesh, mat: Material, pos: Vector3, basis := Basis.IDENTITY) -> void:
	parts.append({"mesh": mesh, "mat": mat, "xf": Transform3D(basis, pos)})


func _process(dt: float) -> void:
	t += dt
	if marker:
		marker.rotation.y = t * 1.1
		marker.position.y = 2.55 + 0.07 * sin(t * 1.7)
	if flash > 0.0:
		flash = maxf(0.0, flash - dt * 2.6)
		shield.visible = true
		shield_mat.set_shader_parameter("opacity", 0.55 * flash)
		shield.scale = Vector3.ONE * (1.0 + (1.0 - flash) * 0.35)
		_hit_light.light_energy = 8.0 * flash
	else:
		shield.visible = false
		_hit_light.light_energy = 0.0
	if _visor_mat:
		_visor_mat.emission_energy_multiplier = 7.0 + 2.5 * flash + 0.6 * sin(t * 3.1)
	if _ring_mat:
		_ring_mat.set_shader_parameter("progress", 0.30 + 0.05 * sin(t * 1.2))


func set_target_pos(ground_pos: Vector3) -> void:
	position = Vector3(ground_pos.x, ground_pos.y + _base_y, ground_pos.z)


func chest_world() -> Vector3:
	return global_transform * Vector3(0, 1.28, 0)


func ground_world() -> Vector3:
	return Vector3(global_position.x, 0.0, global_position.z)


func hit() -> void:
	flash = 1.0
	if _marker_mat:
		_marker_mat.emission_energy_multiplier = 8.0
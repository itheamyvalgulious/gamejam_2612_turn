extends Node3D
## Arena / factory.  All architecture is procedural, like the character.

const MK = preload("res://scripts/mech/mesh_kit.gd")
const MAT = preload("res://scripts/mech/materials.gd")
const TAU := PI * 2.0

var dust: CPUParticles3D
var embers: CPUParticles3D
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var rim_light: DirectionalLight3D
var spot: SpotLight3D
var ground_glow: OmniLight3D


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_stage()
	_build_pylons()
	_build_lights()
	_build_particles()


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.008, 0.012, 0.024)
	sky_mat.sky_horizon_color = Color(0.10, 0.125, 0.17)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.065, 0.075, 0.095)
	sky_mat.ground_bottom_color = Color(0.004, 0.005, 0.008)
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.05
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.26, 0.30, 0.40)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.18
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.34
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 2.10
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_strength = 0.90
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.13, 0.18)
	env.fog_light_energy = 0.7
	env.fog_density = 0.013
	env.fog_sky_affect = 0.55
	env.fog_height = 2.0
	env.fog_height_density = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_floor() -> void:
	var mat: ShaderMaterial = MAT.floor()
	mat.set_shader_parameter("base_color", Color(0.011, 0.014, 0.020))
	mat.set_shader_parameter("line_color", Color(0.30, 0.58, 1.0))
	mat.set_shader_parameter("cool_color", Color(0.15, 0.38, 1.0))
	mat.set_shader_parameter("grid_glow", 0.18)
	mat.set_shader_parameter("arena_radius", 18.0)

	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = -0.12
	add_child(mi)



func _build_stage() -> void:
	var m := MAT
	# main hexagonal duelling dais
	MK.add(self, MK.prism(6, 9.4, 9.4, 0.18, PI / 6.0), m.frame(), Vector3(0, -0.09, 0))
	MK.add(self, MK.prism(6, 9.2, 9.2, 0.03, PI / 6.0), m.frame_light(), Vector3(0, 0.005, 0))
	# hex edge glow + orange markers at each vertex
	for i in 6:
		var a0 := PI / 6.0 + TAU * i / 6.0
		var a1 := PI / 6.0 + TAU * (i + 1) / 6.0
		var p0 := Vector3(cos(a0) * 9.25, 0.03, sin(a0) * 9.25)
		var p1 := Vector3(cos(a1) * 9.25, 0.03, sin(a1) * 9.25)
		var mid := (p0 + p1) * 0.5
		var edge := p1 - p0
		var beam := MeshInstance3D.new()
		beam.mesh = MK.beam_x(edge.length(), 0.022, 0.055, 0.022, 0.055)
		beam.material_override = m.emissive(Color(0.25, 0.55, 1.0), 1.0)
		beam.position = p0
		beam.rotation.y = -atan2(edge.z, edge.x)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		MK.add(self, MK.slab(0.25, 0.25, 0.025, 0.005), m.emissive(Color(0.22, 0.55, 1.0), 1.5), Vector3(cos(a0) * 8.7, 0.03, sin(a0) * 8.7))
	# inner ring around the fighter
	var inner := TorusMesh.new()
	inner.inner_radius = 3.1
	inner.outer_radius = 3.16
	inner.rings = 72
	inner.ring_segments = 4
	var im := MeshInstance3D.new()
	im.mesh = inner
	im.material_override = m.emissive(Color(0.22, 0.55, 1.0), 0.6)
	im.position.y = 0.035
	im.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(im)
	# radial tick marks
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector3(cos(a), 0, sin(a))
		MK.add(self, MK.slab(0.30, 0.045, 0.012, 0.003), m.emissive(Color(0.35, 0.60, 1.0), 0.9),
			d * 10.4 + Vector3(0, 0.03, 0), Vector3(0, -rad_to_deg(a), 0))
	# rim ring
	var rim := TorusMesh.new()
	rim.inner_radius = 11.8
	rim.outer_radius = 11.9
	rim.rings = 96
	rim.ring_segments = 4
	var rm := MeshInstance3D.new()
	rm.mesh = rim
	rm.material_override = m.emissive(Color(0.22, 0.50, 1.0), 0.9)
	rm.position.y = 0.02
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rm)
	# occasional dark deck plates around the dais
	for i in 6:
		var a := PI / 6.0 + TAU * i / 6.0
		var d := Vector3(cos(a), 0, sin(a))
		MK.add(self, MK.slab(2.0, 0.8, 0.12, 0.02), m.frame(), d * 13.4 + Vector3(0, 0.0, 0), Vector3(0, -rad_to_deg(a), 0))


func _build_pylons() -> void:
	var m := MAT
	for i in 8:
		var a := TAU * i / 8.0 + 0.18
		var d := Vector3(cos(a), 0, sin(a))
		var h := 8.0 + 4.0 * (0.5 + 0.5 * sin(i * 2.1 + 1.0))
		var base := d * 27.0
		var lean := Vector3(cos(a), 0, sin(a)) * 0.8
		MK.add(self, MK.prism(6, 0.55, 0.33, h, PI / 6.0), m.pylon(), base + Vector3(0, h * 0.5, 0), Vector3(2.5 * sin(a), 0, -2.5 * cos(a)))
		# emissive spine facing the arena
		var strip := MK.beam_x(h * 0.74, 0.10, 0.16, 0.07, 0.11)
		var sm := MeshInstance3D.new()
		sm.mesh = strip
		sm.material_override = m.emissive(Color(0.18, 0.45, 0.95), 0.45)
		sm.position = base - d * 0.34 + Vector3(0, h * 0.46, 0)
		sm.rotation_degrees = Vector3(0, 0, 90 + 2.5 * sin(a))
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sm)
		# cap
		MK.add(self, MK.prism(6, 0.38, 0.18, 0.5, PI / 6.0), m.armor_shadow(), base + Vector3(0, h + 0.2, 0))
		MK.add(self, MK.prism(6, 0.14, 0.10, 0.12, PI / 6.0), m.emissive(Color(0.3, 0.55, 1.0), 2.0), base + Vector3(0, h + 0.48, 0))


func _build_lights() -> void:
	var front_fill := DirectionalLight3D.new()
	front_fill.light_color = Color(0.68, 0.76, 1.0)
	front_fill.light_energy = 0.35
	add_child(front_fill)
	front_fill.look_at_from_position(Vector3(3, 3.2, -10), Vector3(0, 1.8, 0), Vector3.UP)

	key_light = DirectionalLight3D.new()
	key_light.light_color = Color(0.86, 0.92, 1.0)
	key_light.light_energy = 2.4
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 16.0
	key_light.shadow_bias = 0.035
	key_light.shadow_blur = 2.0
	add_child(key_light)
	key_light.look_at_from_position(Vector3(-7, 10, -9), Vector3(0, 2.0, 0), Vector3.UP)

	fill_light = DirectionalLight3D.new()
	fill_light.light_color = Color(0.30, 0.52, 1.0)
	fill_light.light_energy = 0.45
	add_child(fill_light)
	fill_light.look_at_from_position(Vector3(9, 5, -3), Vector3(0, 1.8, 0), Vector3.UP)

	rim_light = DirectionalLight3D.new()
	rim_light.light_color = Color(0.42, 0.68, 1.0)
	rim_light.light_energy = 1.1
	add_child(rim_light)
	rim_light.look_at_from_position(Vector3(2, 6, 10), Vector3(0, 2.2, 0), Vector3.UP)

	spot = SpotLight3D.new()
	spot.light_color = Color(0.72, 0.86, 1.0)
	spot.light_energy = 2.4
	spot.spot_range = 22.0
	spot.spot_angle = 26.0
	spot.spot_angle_attenuation = 0.65
	spot.shadow_enabled = false
	spot.position = Vector3(0.0, 13.0, -5.0)
	add_child(spot)
	spot.look_at(Vector3(0, 1.8, 0))

	# no ground bounce: the floor grid and blade lights provide the warm underlight


func _build_particles() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	dust = CPUParticles3D.new()
	dust.amount = 1
	dust.emitting = false
	dust.lifetime = 9.0
	dust.preprocess = 6.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 7.0
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 30.0
	dust.gravity = Vector3(0, 0.02, 0)
	dust.initial_velocity_min = 0.08
	dust.initial_velocity_max = 0.35
	dust.scale_amount_min = 0.006
	dust.scale_amount_max = 0.020
	dust.color = Color(0.55, 0.68, 1.0, 0.45)
	dust.mesh = quad
	dust.material_override = MAT.mote()
	dust.position = Vector3(0, 2.8, 0)
	dust.emitting = false
	add_child(dust)

	embers = CPUParticles3D.new()
	embers.amount = 8
	embers.lifetime = 5.5
	embers.preprocess = 4.0
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 1.6
	embers.direction = Vector3(0, 1, 0)
	embers.spread = 55.0
	embers.gravity = Vector3(0, 0.18, 0)
	embers.initial_velocity_min = 0.2
	embers.initial_velocity_max = 0.9
	embers.scale_amount_min = 0.006
	embers.scale_amount_max = 0.018
	embers.color = Color(0.45, 0.70, 1.0, 0.45)
	embers.mesh = quad
	embers.material_override = MAT.mote()
	embers.position = Vector3(0, 0.8, 0)
	embers.emitting = false
	add_child(embers)
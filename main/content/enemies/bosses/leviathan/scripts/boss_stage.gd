extends Node3D
## LEVIATHAN arena: dark industrial basin, containment ring, neon pylons,
## haze, volumetric night air and a controlled studio light rig.
## Everything is code-generated.

const MK := preload("res://scripts/kit/mesh_kit.gd")
const SK := preload("res://scripts/kit/shape_kit.gd")
const BM := preload("res://scripts/boss/boss_materials.gd")
const TAU := PI * 2.0

var world_env: Environment
var camera_key: SpotLight3D


func build() -> void:
	_build_environment()
	_build_ground()
	_build_arena()
	_build_pylons()
	_build_horizon()
	_build_haze()
	_build_probe()
	_build_lights()


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.008, 0.010, 0.018)
	sky_mat.sky_horizon_color = Color(0.030, 0.034, 0.050)
	sky_mat.sky_curve = 0.13
	sky_mat.ground_bottom_color = Color(0.004, 0.004, 0.006)
	sky_mat.ground_horizon_color = Color(0.016, 0.016, 0.026)
	sky_mat.ground_curve = 0.08
	sky_mat.sun_angle_max = 5.0
	sky_mat.sun_curve = 0.08
	sky_mat.sky_energy_multiplier = 0.95
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.96
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.52
	env.glow_strength = 1.0
	env.glow_bloom = 0.045
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.25
	env.glow_hdr_scale = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.10
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.7
	env.ssao_power = 1.5
	env.ssao_light_affect = 0.16
	env.fog_enabled = true
	env.fog_light_color = Color(0.018, 0.020, 0.030)
	env.fog_light_energy = 0.35
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.30
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0032
	env.volumetric_fog_albedo = Color(0.30, 0.33, 0.45)
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_detail_spread = 0.6
	env.volumetric_fog_gi_inject = 0.25
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_ambient_inject = 0.18
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.04
	we.environment = env
	world_env = env
	add_child(we)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = BM.floor_mat()
	mi.name = "Ground"
	add_child(mi)
	# raised central service plate
	var parts: Array = []
	_p(parts, MK.disc(23.0, 0.08, 160, 0.03), BM.hull(), Vector3(0, -0.02, 0))
	_p(parts, MK.ring(22.80, 23.10, 0.05, 160, 0.012), BM.steel_dark(), Vector3(0, 0.008, 0))
	for k in 24:
		var a := TAU * float(k) / 24.0
		var p := Vector3(cos(a), 0, sin(a)) * 21.8
		_p(parts, MK.prism(8, 0.11, 0.09, 0.05), BM.steel(), p + Vector3(0, 0.025, 0))
	# radial inlays
	for k in 12:
		var a2 := TAU * float(k) / 12.0 + 0.13
		var p0 := Vector3(cos(a2), 0, sin(a2)) * 4.0
		var p1 := Vector3(cos(a2), 0, sin(a2)) * 21.6
		_p(parts, SK.beam(p0, p1, 0.055, 0.02, 0.045, 0.02, 0.3), BM.trim(), Vector3(0, 0.022, 0))
	# hazard chevrons near the rim, flat on the plate
	for k in 32:
		var a3 := TAU * float(k) / 32.0
		var p := Vector3(cos(a3), 0, sin(a3)) * 19.6
		_p(parts, MK.plate(0.60, 0.15, 0.025, 0.008),
			BM.emissive(Color(1.0, 0.28, 0.04), 1.6) if k % 2 == 0 else BM.steel_dark(),
			p + Vector3(0, 0.021, 0), Basis(Vector3.UP, -a3) * Basis(Vector3.RIGHT, -90.0 * PI / 180.0))
	# add all
	for e in SK.bake(parts):
		var mi2 := MeshInstance3D.new()
		mi2.mesh = e["mesh"]
		mi2.material_override = e["mat"]
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi2)
	# plinth under the boss shadow
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var sh := MeshInstance3D.new()
	sh.mesh = q
	sh.material_override = BM.contact_shadow()
	sh.rotation_degrees = Vector3(-90, 0, 0)
	sh.scale = Vector3.ONE * 5.2
	sh.position = Vector3(0, 0.035, 0)
	add_child(sh)


func _build_arena() -> void:
	var parts: Array = []
	var steel := BM.steel_dark()
	var trim := BM.trim()
	var glow := BM.emissive(Color(1.0, 0.30, 0.05), 2.6)
	# containment ring segments (broken ring)
	for k in 24:
		var a := TAU * float(k) / 24.0
		var p := Vector3(cos(a), 0, sin(a)) * 24.6
		var b := Basis(Vector3.UP, -a)
		_p(parts, MK.plate(3.4, 0.6, 0.45, 0.04), steel, p + Vector3(0, 0.45, 0), b)
		if k % 2 == 0:
			_p(parts, MK.plate(2.6, 0.055, 0.02, 0.01), glow,
				p + Vector3(0, 0.78, 0) + Vector3(cos(a), 0, sin(a)) * 0.0, b)
	# low bollards
	for k in 16:
		var a := TAU * float(k) / 16.0 + 0.2
		var p := Vector3(cos(a), 0, sin(a)) * 27.6
		_p(parts, MK.prism(10, 0.26, 0.18, 1.5), steel, p + Vector3(0, 0.75, 0))
		_p(parts, MK.ring(0.18, 0.24, 0.05, 20, 0.01), glow, p + Vector3(0, 1.42, 0))
	for e in SK.bake(parts):
		var mi := MeshInstance3D.new()
		mi.mesh = e["mesh"]
		mi.material_override = e["mat"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)


func _build_pylons() -> void:
	var steel := BM.steel_dark()
	var black := BM.hull()
	var glow := BM.emissive(Color(1.0, 0.28, 0.04), 3.2)
	var cool := BM.emissive(Color(0.28, 0.52, 1.0), 2.2)
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.18
		var r := 32.0 + 2.5 * float(i % 3)
		var h := 15.0 + 5.0 * float((i * 3) % 4)
		var p := Vector3(cos(a) * r, h * 0.5, sin(a) * r)
		var b := Basis(Vector3.UP, -a)
		var root := Node3D.new()
		root.position = p
		root.basis = b
		add_child(root)
		MK.add(root, MK.plate(1.4, h, 0.9, 0.05), black, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
		MK.add(root, MK.plate(1.6, 1.1, 1.0, 0.04), steel, Vector3(0, h * 0.5 - 0.8, 0))
		MK.add(root, MK.plate(0.14, h * 0.52, 0.02, 0.01), glow,
			Vector3(0.0, 0.0, 0.47), Vector3.ZERO, Vector3.ONE)
		MK.add(root, MK.plate(0.05, h * 0.34, 0.02, 0.01), cool,
			Vector3(0.72, -h * 0.1, 0.02), Vector3(0, 0, 0), Vector3.ONE)
		# crown
		MK.add(root, MK.prism(8, 0.9, 0.3, 1.2), steel, Vector3(0, h * 0.5 + 0.4, 0))
		MK.add(root, MK.prism(12, 0.35, 0.05, 0.30), glow, Vector3(0, h * 0.5 + 1.2, 0))


func _build_horizon() -> void:
	# perimeter monoliths
	for i in 22:
		var a := TAU * float(i) / 22.0 + 0.07
		var h := 22.0 + 8.0 * float((i * 5) % 4)
		var r := 42.0
		var pos := Vector3(cos(a) * r, h * 0.5 - 1.0, sin(a) * r)
		var mi := MK.add(self, MK.plate(5.0, h, 0.9, 0.05), BM.hull(), pos,
			Vector3(0, 90.0 - rad_to_deg(a), 0), Vector3.ONE)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % 3 == 0:
			MK.add(self, MK.plate(0.10, h * 0.6, 0.02, 0.01),
				BM.emissive(Color(0.55, 0.18, 0.04), 1.6),
				pos + Vector3(-sin(a) * 0.48, 0, cos(a) * 0.48),
				Vector3(0, 90.0 - rad_to_deg(a), 0), Vector3.ONE)
	# distant neon bars
	for i in 7:
		var a := -1.35 + float(i) * 0.45
		var pos := Vector3(cos(a) * 34.0, 6.0 + 2.0 * float(i % 3), -absf(sin(a)) * 34.0 - 6.0)
		var b := MK.add(self, MK.plate(0.18, 10.0, 0.18, 0.01),
			BM.emissive(Color(1.0, 0.24, 0.05) if i % 2 == 0 else Color(0.30, 0.46, 1.0), 2.2),
			pos, Vector3(0, a * 60.0, 0), Vector3.ONE)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_haze() -> void:
	var p := GPUParticles3D.new()
	p.amount = 220
	p.lifetime = 16.0
	p.preprocess = 8.0
	p.position = Vector3(0, 6.0, 0)
	p.visibility_aabb = AABB(Vector3(-30, -8, -30), Vector3(60, 26, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30.0, 8.0, 30.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.14
	pm.gravity = Vector3(0.004, 0.006, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.8
	pm.color = Color(0.65, 0.62, 0.80, 0.20)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.10, 0.10)
	quad.material = BM.dust(Color(0.62, 0.66, 0.95, 0.13))
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

	# ground mist planes
	for i in 3:
		var q := QuadMesh.new()
		q.size = Vector2(44, 44)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = BM.dust(Color(0.30, 0.32, 0.45, 0.045))
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.position = Vector3(0, 0.7 + 0.5 * float(i), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _build_probe() -> void:
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0, 6.0, 4.0)
	probe.size = Vector3(34.0, 20.0, 34.0)
	probe.origin_offset = Vector3.ZERO
	probe.intensity = 0.9
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.name = "StageProbe"
	add_child(probe)


func _build_lights() -> void:
	var key := SpotLight3D.new()
	key.position = Vector3(17.0, 25.0, 20.0)
	key.look_at_from_position(key.position, Vector3(0, 5.0, 2.0), Vector3.UP)
	key.light_color = Color(1.0, 0.94, 0.88)
	key.light_energy = 480.0
	key.spot_range = 70.0
	key.spot_angle = 34.0
	key.spot_angle_attenuation = 1.0
	key.shadow_enabled = true
	key.shadow_bias = 0.03
	key.shadow_blur = 1.6
	key.name = "KeySpot"
	add_child(key)
	camera_key = key

	var fill := SpotLight3D.new()
	fill.position = Vector3(-21.0, 14.0, 12.0)
	fill.look_at_from_position(fill.position, Vector3(0, 5.0, 2.0), Vector3.UP)
	fill.light_color = Color(0.62, 0.74, 1.0)
	fill.light_energy = 150.0
	fill.spot_range = 55.0
	fill.spot_angle = 30.0
	fill.spot_angle_attenuation = 1.2
	fill.name = "Fill"
	add_child(fill)

	var rim := SpotLight3D.new()
	rim.position = Vector3(-13.0, 18.0, -20.0)
	rim.look_at_from_position(rim.position, Vector3(0, 6.0, 0.0), Vector3.UP)
	rim.light_color = Color(0.82, 0.42, 1.0)
	rim.light_energy = 90.0
	rim.spot_range = 55.0
	rim.spot_angle = 26.0
	rim.spot_angle_attenuation = 1.3
	rim.name = "RimMagenta"
	add_child(rim)

	var back := SpotLight3D.new()
	back.position = Vector3(16.0, 12.0, -18.0)
	back.look_at_from_position(back.position, Vector3(0, 6.0, 0.0), Vector3.UP)
	back.light_color = Color(0.42, 0.70, 1.0)
	back.light_energy = 100.0
	back.spot_range = 55.0
	back.spot_angle = 24.0
	back.spot_angle_attenuation = 1.4
	back.name = "BackRim"
	add_child(back)

	var front := SpotLight3D.new()
	front.position = Vector3(-3.0, 6.0, 24.0)
	front.look_at_from_position(front.position, Vector3(0, 5.0, 2.0), Vector3.UP)
	front.light_color = Color(0.95, 0.85, 0.80)
	front.light_energy = 95.0
	front.spot_range = 45.0
	front.spot_angle = 30.0
	front.name = "FrontFill"
	add_child(front)

	var warm := OmniLight3D.new()
	warm.position = Vector3(0.0, 2.0, 8.0)
	warm.light_color = Color(1.0, 0.30, 0.06)
	warm.light_energy = 6.0
	warm.omni_range = 18.0
	warm.omni_attenuation = 1.8
	warm.name = "FloorWarm"
	add_child(warm)

	var cool := OmniLight3D.new()
	cool.position = Vector3(-10.0, 2.5, -6.0)
	cool.light_color = Color(0.26, 0.44, 1.0)
	cool.light_energy = 3.0
	cool.omni_range = 20.0
	cool.name = "FloorCool"
	add_child(cool)

	# rim bars right behind the boss: long neon highlights on black metal
	var bar1 := MK.add(self, MK.plate(0.16, 8.0, 0.16, 0.01),
		BM.emissive(Color(1.0, 0.22, 0.04), 2.6), Vector3(-9.0, 4.2, -10.0),
		Vector3(0, 18, 0), Vector3.ONE)
	bar1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bar2 := MK.add(self, MK.plate(0.12, 6.5, 0.12, 0.01),
		BM.emissive(Color(0.22, 0.46, 1.0), 2.4), Vector3(10.5, 3.6, -9.0),
		Vector3(0, -16, 0), Vector3.ONE)
	bar2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_color = Color(0.58, 0.66, 0.92)
	sun.light_energy = 0.45
	sun.shadow_enabled = false
	sun.name = "Sun"
	add_child(sun)


func _p(parts: Array, mesh: Mesh, mat: Material, pos: Vector3,
		basis := Basis.IDENTITY) -> void:
	parts.append({"mesh": mesh, "mat": mat, "xf": Transform3D(basis, pos)})
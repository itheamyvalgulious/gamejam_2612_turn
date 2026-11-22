class_name Atmosphere
extends Node3D

## Valley mist, waterfall spray and local fog volumes.
## The 3D noise textures are generated here — no image assets.

var mist_mat: ShaderMaterial
var volumes: Array[FogVolume] = []
var base_densities: PackedFloat32Array = PackedFloat32Array()

func build() -> void:
	mist_mat = ShaderMaterial.new()
	mist_mat.shader = load("res://shaders/mist.gdshader")

	var n1 := _noise3d(48, 0.06, 4, 11)
	var n2 := _noise3d(40, 0.10, 3, 23)
	_add_volume(Vector3(0, 110, 200), Vector3(3200, 220, 2800), 0.0022, Color(0.70, 0.76, 0.86), n1, 0.45)
	_add_volume(Vector3(-120, 185, 640), Vector3(1900, 180, 1500), 0.0045, Color(0.74, 0.80, 0.88), n2, 0.5)
	_add_volume(Vector3(-200, 350, -170), Vector3(300, 380, 240), 0.014, Color(0.86, 0.90, 0.95), n2, 0.55)
	_add_volume(Vector3(0, 660, -700), Vector3(2400, 240, 1600), 0.0025, Color(0.86, 0.90, 0.97), n1, 0.45)
	_add_spray(Vector3(-208, 340, -202))
	_add_spray(Vector3(-210, 440, -208))
	_add_spray(Vector3(-204, 299, -193), 26, 0.028, 9.0, 22.0)
	_add_splash(Vector3(-204, 298, -197))
	_add_splash(Vector3(-203, 296, -194), 260, 0.32, 0.10, 0.36, 3.0, 9.0)

func _noise3d(size: int, freq: float, oct: int, seed: int) -> NoiseTexture3D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	var t := NoiseTexture3D.new()
	t.width = size
	t.height = size
	t.depth = size
	t.seamless = true
	t.noise = n
	t.normalize = true
	return t

func _add_volume(pos: Vector3, size: Vector3, density: float, albedo: Color, tex: NoiseTexture3D, falloff: float) -> void:
	var fv := FogVolume.new()
	fv.position = pos
	fv.size = size
	fv.shape = 3
	var m := FogMaterial.new()
	m.density = density
	m.albedo = albedo
	m.height_falloff = falloff
	m.edge_fade = 0.25
	m.density_texture = tex
	fv.material = m
	volumes.append(fv)
	base_densities.append(density)
	add_child(fv)

func set_density_scale(scale: float) -> void:
	for i in volumes.size():
		var m := volumes[i].material as FogMaterial
		if m != null:
			m.density = base_densities[i] * scale

func _add_splash(pos: Vector3, amount: int = 760, alpha: float = 0.9, smin: float = 0.035, smax: float = 0.16, vmin: float = 7.0, vmax: float = 17.0) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 1.6
	p.preprocess = 2.0
	p.randomness = 0.85
	p.interpolate = true
	p.fixed_fps = 60
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 2.5, 9)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = smin
	pm.scale_max = smax
	pm.color = Color(0.95, 0.97, 1.0, alpha)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/splash.gdshader")
	q.material = sm
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-120, -80, -120), Vector3(240, 240, 240))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

func _add_spray(pos: Vector3, amount: int = 70, alpha: float = 0.055, smin: float = 18.0, smax: float = 48.0) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 11.0
	p.preprocess = 5.0
	p.randomness = 0.6
	p.interpolate = true
	p.fixed_fps = 30
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(38, 8, 30)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 38.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = smin
	pm.scale_max = smax
	pm.color = Color(0.82, 0.87, 0.92, alpha)
	pm.damping_min = 0.2
	pm.damping_max = 0.4
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = mist_mat
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-200, -100, -200), Vector3(400, 400, 400))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
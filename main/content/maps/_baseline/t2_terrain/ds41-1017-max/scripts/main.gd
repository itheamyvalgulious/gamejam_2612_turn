extends Node3D

## AETHER — procedural wilds.  Host: terrain, sky, light, camera, still capture.
## CLI: godot --path . -- --shot=hero,valley --res=512 --size=1600x900

const Field := preload("res://scripts/terrain_field.gd")
const Builder := preload("res://scripts/terrain_builder.gd")
const Water := preload("res://scripts/water_builder.gd")
const Forest := preload("res://scripts/forest_builder.gd")
const Cover := preload("res://scripts/ground_cover.gd")
const Atmo := preload("res://scripts/atmosphere.gd")
const Canopy := preload("res://scripts/canopy_carpet.gd")
const Rocks := preload("res://scripts/rock_builder.gd")
const Backdrop := preload("res://scripts/backdrop.gd")

var field: TerrainField
var terrain: TerrainBuilder
var world: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var atmo_node: Node
var fog_begin0 := 10.0
var fog_end0 := 100.0
var fog_curve0 := 1.0
var vfog0 := 0.0
var viewport: SubViewport

var res := 768
var shot_mode := false
var shot_names: Array[String] = []
var shot_prefix := ""
var shot_size := Vector2i(1600, 900)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--res="):
			res = int(a.split("=")[1])
		if a.begins_with("--size="):
			var wh := a.split("=")[1].split("x")
			shot_size = Vector2i(int(wh[0]), int(wh[1]))
		if a.begins_with("--shot="):
			shot_mode = true
			for s in a.split("=")[1].split(","):
				shot_names.append(s)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	if shot_mode:
		viewport = SubViewport.new()
		viewport.size = shot_size
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.own_world_3d = true
		add_child(viewport)
		world.reparent(viewport)
	_build_environment()
	_build_world()
	_build_camera()
	cam.current = true
	if shot_mode:
		await _run_shots()
	else:
		_apply_shot("hero_dusk")
		_configure("hero_dusk")
		print("viewport=", get_viewport().get_visible_rect().size, " window=", DisplayServer.window_get_size())

func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sky_mat = sm
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.58
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.6
	env.ssao_power = 1.3
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.00022
	env.volumetric_fog_albedo = Color(0.82, 0.86, 0.92)
	env.volumetric_fog_emission = Color(0.02, 0.025, 0.03)
	env.volumetric_fog_emission_energy = 0.0
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 700.0
	env.volumetric_fog_detail_spread = 1.3
	env.volumetric_fog_ambient_inject = 0.6
	env.volumetric_fog_sky_affect = 0.08
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	env.adjustment_brightness = 1.0
	env.glow_bloom = 0.02
	env.fog_enabled = true
	env.fog_light_color = Color(0.52, 0.58, 0.70)
	env.fog_light_energy = 0.85
	env.fog_density = 0.00024
	env.fog_aerial_perspective = 0.72
	env.fog_sky_affect = 0.18
	fog_begin0 = env.fog_depth_begin
	fog_end0 = env.fog_depth_end
	fog_curve0 = env.fog_depth_curve
	vfog0 = env.volumetric_fog_density
	env.fog_height = 120.0
	env.fog_height_density = 0.0009
	world_env.environment = env
	world.add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-8.5, -74.0, 0.0)
	sun.light_color = Color(1.0, 0.73, 0.50)
	sun.light_energy = 3.2
	sun.light_angular_distance = 0.55
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 1900.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.48
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.6
	world.add_child(sun)

func _build_world() -> void:
	field = Field.new()
	terrain = Builder.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	terrain.build(field, res, 8, mat)

	var water := Water.new()
	water.name = "Water"
	world.add_child(water)
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water.gdshader")
	water.build(field, wmat)
	var fmat := ShaderMaterial.new()
	fmat.shader = load("res://shaders/waterfall.gdshader")
	water.build_fall(fmat)

	var bark := ShaderMaterial.new()
	bark.shader = load("res://shaders/bark.gdshader")
	var leaves := ShaderMaterial.new()
	leaves.shader = load("res://shaders/leaves.gdshader")
	var palm := ShaderMaterial.new()
	palm.shader = load("res://shaders/palm_frond.gdshader")
	var needles := ShaderMaterial.new()
	needles.shader = load("res://shaders/needles.gdshader")
	var far := ShaderMaterial.new()
	far.shader = load("res://shaders/foliage_far.gdshader")
	var forest := Forest.new()
	forest.name = "Forest"
	world.add_child(forest)
	forest.build(field, terrain, {"bark": bark, "leaves": leaves, "palm": palm, "needles": needles, "far": far})

	var grass := ShaderMaterial.new()
	grass.shader = load("res://shaders/grass.gdshader")
	var fern := ShaderMaterial.new()
	fern.shader = load("res://shaders/fern.gdshader")
	var cover := Cover.new()
	cover.name = "GroundCover"
	world.add_child(cover)
	cover.build(field, terrain, {"grass": grass, "fern": fern, "reed": grass, "bush": far})

	var cab := ShaderMaterial.new()
	cab.shader = load("res://shaders/canopy.gdshader")
	var canopy := Canopy.new()
	canopy.name = "Canopy"
	world.add_child(canopy)
	canopy.build(field, terrain, cab)

	var rockmat := ShaderMaterial.new()
	rockmat.shader = load("res://shaders/rock.gdshader")
	var rocks := Rocks.new()
	rocks.name = "Rocks"
	world.add_child(rocks)
	rocks.build(field, terrain, rockmat)

	var dmat := ShaderMaterial.new()
	dmat.shader = load("res://shaders/distant.gdshader")
	var back := Backdrop.new()
	back.name = "Backdrop"
	world.add_child(back)
	back.build(dmat)

	var atmo := Atmo.new()
	atmo.name = "Atmosphere"
	world.add_child(atmo)
	atmo.build()
	atmo_node = atmo

func _build_camera() -> void:
	if shot_mode:
		cam = Camera3D.new()
	else:
		cam = load("res://scripts/fly_camera.gd").new()
	cam.fov = 52.0
	cam.near = 0.4
	cam.far = 6000.0
	world.add_child(cam)

func _configure(shot: String) -> void:
	var p := {
		"hero": [Vector3(-8.5, -74.0, 0.0), Color(1.0, 0.73, 0.50), 3.2, 0.58, 0.90, 0.00018, Color(0.055, 0.125, 0.285), Color(0.60, 0.60, 0.66), 0.52],
		"hero_dusk": [Vector3(-6.0, 178.0, 0.0), Color(1.0, 0.62, 0.34), 3.6, 0.50, 0.90, 0.00020, Color(0.035, 0.085, 0.22), Color(0.86, 0.50, 0.34), 0.55],
		"forest": [Vector3(-13.0, -95.0, 0.0), Color(1.0, 0.84, 0.64), 3.0, 0.66, 0.96, 0.00032, Color(0.07, 0.15, 0.32), Color(0.68, 0.64, 0.64), 0.50],
		"waterfall": [Vector3(-11.0, -104.0, 0.0), Color(1.0, 0.80, 0.58), 3.1, 0.55, 0.94, 0.00028, Color(0.06, 0.14, 0.31), Color(0.66, 0.62, 0.64), 0.50],
		"gorge": [Vector3(-10.0, -84.0, 0.0), Color(1.0, 0.78, 0.55), 3.2, 0.55, 0.95, 0.00026, Color(0.06, 0.14, 0.32), Color(0.64, 0.62, 0.65), 0.50],
		"snow": [Vector3(-19.0, 58.0, 0.0), Color(1.0, 0.93, 0.86), 2.7, 0.82, 0.84, 0.00016, Color(0.10, 0.20, 0.40), Color(0.78, 0.70, 0.68), 0.58],
		"snow_edge": [Vector3(-17.0, 66.0, 0.0), Color(1.0, 0.94, 0.90), 1.5, 0.60, 0.38, 0.00018, Color(0.10, 0.20, 0.40), Color(0.78, 0.70, 0.68), 0.58],
		"snow_dawn": [Vector3(-13.0, 76.0, 0.0), Color(1.0, 0.90, 0.82), 2.7, 0.78, 0.82, 0.00018, Color(0.10, 0.20, 0.40), Color(0.80, 0.68, 0.62), 0.55],
		"panorama": [Vector3(-36.0, -62.0, 0.0), Color(1.0, 0.95, 0.90), 2.5, 0.82, 0.86, 0.00012, Color(0.09, 0.18, 0.35), Color(0.66, 0.70, 0.76), 0.44],
	}
	var d: Array = p.get(shot, p["hero"])
	sun.rotation_degrees = d[0]
	sun.light_color = d[1]
	sun.light_energy = d[2]
	world_env.environment.ambient_light_energy = d[3]
	world_env.environment.tonemap_exposure = d[4]
	var e: Environment = world_env.environment
	e.fog_density = d[5]
	e.fog_depth_begin = fog_begin0
	e.fog_depth_end = fog_end0
	e.fog_depth_curve = fog_curve0
	e.volumetric_fog_density = vfog0
	if atmo_node != null:
		atmo_node.set_density_scale(1.0)
	if shot == "hero_dusk":
		e.fog_density = 0.00010
		e.fog_depth_begin = 220.0
		e.fog_depth_end = 2600.0
		e.fog_depth_curve = 1.6
		e.volumetric_fog_density = 0.00012
		if atmo_node != null:
			atmo_node.set_density_scale(0.55)
	sky_mat.set_shader_parameter("zenith_col", d[6])
	sky_mat.set_shader_parameter("horizon_col", d[7])
	sky_mat.set_shader_parameter("cloud_cover", d[8])

func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	for name in shot_names:
		if not _apply_shot(name):
			print("unknown shot ", name)
			continue
		_configure(name)
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := viewport.get_texture().get_image()
		var path := "res://screenshots/%s%s.png" % [shot_prefix, name]
		img.save_png(ProjectSettings.globalize_path(path))
		print("saved ", path, " ", img.get_size())
	get_tree().quit()

func _shot_defs() -> Dictionary:
	return {
		"hero": [Vector3(150, 560, 1300), Vector3(-120, 330, -260), 55.0],
		"valley": [Vector3(120, 400, 620), Vector3(-170, 300, -220), 60.0],
		"top": [Vector3(0, 2350, 1750), Vector3(-60, 0, -350), 48.0],
		"cliff": [Vector3(-380, 330, 80), Vector3(-205, 400, -235), 58.0],
		"snow": [Vector3(-380, 640, -560), Vector3(-560, 560, -1250), 55.0],
		"forest": [Vector3(-520, 430, 960), Vector3(-50, 120, 430), 55.0],
		"waterfall": [Vector3(-640, 500, 0), Vector3(-205, 380, -230), 50.0],
		"river": [Vector3(-260, 430, 820), Vector3(0, 200, 300), 55.0],
		"panorama": [Vector3(300, 1150, 1450), Vector3(-100, 300, -500), 48.0],
		"snow_edge": [Vector3(-520, 640, -360), Vector3(-100, 330, 250), 55.0],
		"gorge": [Vector3(-620, 520, 520), Vector3(-100, 300, -150), 55.0],
		"hero_dusk": [Vector3(250, 520, 1100), Vector3(-150, 380, -250), 55.0],
		"snow_dawn": [Vector3(-950, 690, -800), Vector3(-250, 600, -1150), 52.0],
	}

func goto_shot(name: String) -> void:
	if _apply_shot(name):
		_configure(name)

func _apply_shot(name: String) -> bool:
	var d: Array = _shot_defs().get(name, [])
	if d.is_empty():
		return false
	cam.fov = d[2]
	cam.global_position = d[0]
	cam.look_at(d[1], Vector3.UP)
	return true
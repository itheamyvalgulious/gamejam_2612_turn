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
const Detail := preload("res://scripts/detail_scenes.gd")
const Hero := preload("res://scripts/hero_tree.gd")

var field: TerrainField
var terrain: TerrainBuilder
var world: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var atmo_node: Node
var detail_node: Node
var fill: OmniLight3D
var fog_begin0 := 10.0
var fog_end0 := 100.0
var fog_curve0 := 1.0
var vfog0 := 0.0
var viewport: SubViewport
var dof_off := false

var res := 768
var shot_mode := false
var shot_names: Array[String] = []
var anim_name := ""
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
		if a.begins_with("--anim="):
			shot_mode = true
			anim_name = a.split("=")[1]
			shot_names.append(anim_name)
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
	var fx := OS.get_environment("DBG_FX")
	if fx != "":
		var e: Environment = world_env.environment
		if "nossao" in fx: e.ssao_enabled = false
		if "noglow" in fx: e.glow_enabled = false
		if "nofog" in fx: e.fog_enabled = false
		if "noshadow" in fx: sun.shadow_enabled = false
		if "noenv" in fx: e.ssao_enabled = false; e.glow_enabled = false; e.fog_enabled = false
		print("[dbg] fx ", fx)
	if shot_mode:
		if anim_name != "":
			await _run_anim(anim_name)
		else:
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
	env.volumetric_fog_enabled = false
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
	var mat: Material = ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain_pbr.gdshader")
	var Bank := preload("res://scripts/texture_bank.gd")
	for key in ["rock", "snow", "ground", "gravel"]:
		for m in ["albedo", "normal", "rough", "height"]:
			var tex = Bank.load_raw("res://assets/textures/%s_%s.png" % [key, m])
			if tex != null:
				mat.set_shader_parameter("%s_%s" % [key, m], tex)
	for m in ["albedo", "normal", "rough", "height"]:
		var dt = Bank.load_raw("res://assets/textures/rock_detail_%s.png" % m)
		if dt != null:
			mat.set_shader_parameter("rock_detail_%s" % m, dt)
	if OS.get_environment("DBG_FLAT") != "":
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.42, 0.40, 0.34)
		flat.roughness = 0.85
		mat = flat
	terrain.build(field, res, 8, mat)
	if OS.get_environment("NO_TERRAIN") != "":
		terrain.visible = false

	var detail_mat: ShaderMaterial = mat.duplicate()
	detail_mat.set_shader_parameter("detail_boost", 1.9)
	var rmat := ShaderMaterial.new()
	rmat.shader = load("res://shaders/rock_pbr.gdshader")
	for m in ["albedo", "normal", "rough", "height"]:
		var rt = Bank.load_raw("res://assets/textures/rock_%s.png" % m)
		if rt != null:
			rmat.set_shader_parameter("rock_%s" % m, rt)
		var rd = Bank.load_raw("res://assets/textures/rock_detail_%s.png" % m)
		if rd != null:
			rmat.set_shader_parameter("rock_detail_%s" % m, rd)
	# baked cliff face material (mesh carries the form, maps the material)
	var face := ShaderMaterial.new()
	face.shader = load("res://shaders/rock_face.gdshader")
	for m in ["albedo", "normal", "height", "rough"]:
		var ft = Bank.load_raw("res://assets/textures/rock_face_%s.png" % m)
		if ft != null:
			face.set_shader_parameter("face_%s" % m, ft)
		var st = Bank.load_raw("res://assets/textures/rock_struct_%s.png" % m)
		if st != null:
			face.set_shader_parameter("struct_%s" % m, st)
	var detail := Detail.new()
	detail.name = "DetailScenes"
	world.add_child(detail)
	var foamm := ShaderMaterial.new()
	foamm.shader = load("res://shaders/foam.gdshader")
	detail.build(field, terrain, detail_mat, rmat, foamm, face)
	detail_node = detail

	var barkp := ShaderMaterial.new()
	barkp.shader = load("res://shaders/bark_pbr.gdshader")
	barkp.set_shader_parameter("bark_albedo", Bank.load_raw("res://assets/textures/bark_albedo.png"))
	barkp.set_shader_parameter("bark_normal", Bank.load_raw("res://assets/textures/bark_normal.png"))
	var leafm := ShaderMaterial.new()
	leafm.shader = load("res://shaders/hero_leaf.gdshader")
	leafm.set_shader_parameter("leaf_albedo", Bank.load_raw("res://assets/textures/leaf_albedo.png"))
	var tree1 := Hero.new()
	tree1.name = "HeroTreeForest"
	world.add_child(tree1)
	tree1.build(Vector3(-62.0, terrain.sample_height(-62.0, 760.0) - 0.2, 760.0), 22.0, barkp, leafm, 101, Vector3(0.05, 0.0, -0.02))
	var tree2 := Hero.new()
	tree2.name = "HeroTreeRiver"
	world.add_child(tree2)
	tree2.build(Vector3(-112.0, terrain.sample_height(-112.0, 748.0) - 0.2, 748.0), 18.0, barkp, leafm, 202, Vector3(-0.22, 0.0, 0.04))

	fill = OmniLight3D.new()
	fill.light_color = Color(1.0, 0.88, 0.74)
	fill.light_energy = 0.0
	fill.omni_range = 18.0
	fill.shadow_enabled = false
	world.add_child(fill)

	var water := Water.new()
	water.name = "Water"
	world.add_child(water)
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water.gdshader")
	for i in 3:
		var wz := 756.0 + float(i) * 8.0
		var wx: float = field.river_x(wz) + (2.5 if i == 1 else -2.0)
		var sz := 1.4 + 0.4 * float(i)
		wmat.set_shader_parameter("rock_%s" % ["a", "b", "c"][i], Vector4(wx, wz, sz, 0.0))
	wmat.set_shader_parameter("water_normal", Bank.load_raw("res://assets/textures/water_normal.png"))
	wmat.set_shader_parameter("foam_mask", Bank.load_raw("res://assets/textures/foam_mask.png"))
	water.build(field, wmat)
	var fmat := ShaderMaterial.new()
	fmat.shader = load("res://shaders/waterfall.gdshader")
	water.build_fall(fmat)
	var pmat := ShaderMaterial.new()
	pmat.shader = load("res://shaders/plunge.gdshader")
	water.build_plunge(pmat)

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

	# debug switches used while iterating on the falls; harmless in normal runs
	if OS.get_environment("DBG_HIDE") != "":
		for hid in OS.get_environment("DBG_HIDE").split(","):
			var hn: Node = world.get_node_or_null(hid)
			if hn != null:
				hn.visible = false
				print("[dbg] hidden ", hid)
			else:
				print("[dbg] missing ", hid)
	if OS.get_environment("DBG_NO_DOF") != "":
		dof_off = true

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
		"forest": [Vector3(-30.0, -70.0, 0.0), Color(1.0, 0.95, 0.88), 3.2, 0.76, 0.94, 0.00006, Color(0.08, 0.20, 0.44), Color(0.56, 0.70, 0.84), 0.38],
		"waterfall": [Vector3(-11.0, -104.0, 0.0), Color(1.0, 0.80, 0.58), 3.1, 0.55, 0.94, 0.00028, Color(0.06, 0.14, 0.31), Color(0.66, 0.62, 0.64), 0.50],
		"gorge": [Vector3(-10.0, -84.0, 0.0), Color(1.0, 0.78, 0.55), 3.2, 0.55, 0.95, 0.00026, Color(0.06, 0.14, 0.32), Color(0.64, 0.62, 0.65), 0.50],
		"snow": [Vector3(-19.0, 58.0, 0.0), Color(1.0, 0.93, 0.86), 2.7, 0.82, 0.84, 0.00016, Color(0.10, 0.20, 0.40), Color(0.78, 0.70, 0.68), 0.58],
		"snow_edge": [Vector3(-17.0, 66.0, 0.0), Color(1.0, 0.94, 0.90), 2.0, 0.62, 0.55, 0.00018, Color(0.10, 0.20, 0.40), Color(0.78, 0.70, 0.68), 0.58],
		"snow_dawn": [Vector3(-13.0, 76.0, 0.0), Color(1.0, 0.90, 0.82), 2.7, 0.78, 0.82, 0.00018, Color(0.10, 0.20, 0.40), Color(0.80, 0.68, 0.62), 0.55],
		"panorama": [Vector3(-36.0, -62.0, 0.0), Color(1.0, 0.95, 0.90), 2.5, 0.82, 0.86, 0.00012, Color(0.09, 0.18, 0.35), Color(0.66, 0.70, 0.76), 0.44],
		"detail_rock": [Vector3(-27.0, -45.0, 0.0), Color(1.0, 0.96, 0.92), 3.6, 0.52, 1.05, 0.00006, Color(0.055, 0.125, 0.28), Color(0.62, 0.58, 0.55), 0.42],
		"rock_1m": [Vector3(-30.0, -70.0, 0.0), Color(1.0, 0.97, 0.94), 4.0, 0.55, 1.08, 0.00004, Color(0.06, 0.13, 0.28), Color(0.64, 0.60, 0.56), 0.40],
		"waterfall_20m": [Vector3(-20.0, -78.0, 0.0), Color(1.0, 0.86, 0.70), 3.5, 0.60, 1.0, 0.00008, Color(0.06, 0.14, 0.30), Color(0.64, 0.60, 0.58), 0.46],
		"detail_tree": [Vector3(-30.0, -30.0, 0.0), Color(1.0, 0.90, 0.74), 3.6, 0.72, 1.0, 0.00010, Color(0.06, 0.14, 0.30), Color(0.60, 0.58, 0.54), 0.50],
		"detail_water": [Vector3(-35.0, -60.0, 0.0), Color(1.0, 0.94, 0.86), 3.2, 0.72, 0.92, 0.00004, Color(0.08, 0.20, 0.45), Color(0.55, 0.70, 0.85), 0.34],
		"river": [Vector3(-35.0, -62.0, 0.0), Color(1.0, 0.96, 0.90), 3.2, 0.76, 0.92, 0.00005, Color(0.08, 0.20, 0.45), Color(0.56, 0.70, 0.84), 0.36],
		"detail_leaf": [Vector3(-30.0, -35.0, 0.0), Color(1.0, 0.92, 0.76), 3.7, 0.72, 1.0, 0.00006, Color(0.06, 0.14, 0.30), Color(0.62, 0.58, 0.54), 0.45],
		"detail_waterfall": [Vector3(-20.0, -78.0, 0.0), Color(1.0, 0.86, 0.70), 3.4, 0.62, 0.95, 0.00010, Color(0.06, 0.14, 0.30), Color(0.64, 0.60, 0.58), 0.48],
		"detail_snow": [Vector3(-38.0, 64.0, 0.0), Color(1.0, 0.97, 0.94), 2.3, 0.82, 0.42, 0.00006, Color(0.10, 0.20, 0.40), Color(0.80, 0.76, 0.72), 0.55],
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
	if (shot.begins_with("detail") or shot == "rock_1m" or shot == "waterfall_20m") and atmo_node != null:
		atmo_node.set_density_scale(0.35)
	if shot == "waterfall_20m" or shot == "detail_waterfall":
		# a waterfall reads by contrast: low warm sun raking the sheet, cool
		# sky fill, and no depth-of-field (its bokeh put a weave over the frame)
		sun.rotation_degrees = Vector3(-26.0, 35.0, 0.0)
		sun.light_color = Color(1.0, 0.92, 0.82)
		sun.light_energy = 2.2
		e.ambient_light_energy = 0.40
		e.tonemap_exposure = 0.80
		e.fog_density = 0.00020
		e.adjustment_contrast = 1.12
		e.adjustment_saturation = 1.02
	if shot == "rock_1m" or shot == "detail_rock":
		# raking light: at 1 m the face must read by shading, not by texture
		sun.rotation_degrees = Vector3(-27.0, -57.0, 0.0)
		sun.light_energy = 6.2
		sun.light_color = Color(1.0, 0.97, 0.93)
		e.ambient_light_energy = 0.26
		e.tonemap_exposure = 0.94
		e.fog_density = 0.00002
	sky_mat.set_shader_parameter("zenith_col", d[6])
	sky_mat.set_shader_parameter("horizon_col", d[7])
	sky_mat.set_shader_parameter("cloud_cover", d[8])

func _run_anim(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/anim"))
	if not _apply_shot(name):
		print("unknown anim ", name)
		get_tree().quit()
		return
	_configure(name)
	for i in 25:
		await get_tree().process_frame
	for f in 150:
		await get_tree().process_frame
		var img := viewport.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/anim/%s_%03d.png" % [name, f]))
	print("anim frames done")
	get_tree().quit()

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
		"snow_edge": [Vector3(-500, 700, -620), Vector3(-100, 360, 300), 55.0],
		"gorge": [Vector3(-620, 520, 520), Vector3(-100, 300, -150), 55.0],
		"hero_dusk": [Vector3(250, 520, 1100), Vector3(-150, 380, -250), 55.0],
		"snow_dawn": [Vector3(-950, 690, -800), Vector3(-250, 600, -1150), 52.0],
		"detail_rock": [Vector3(-420, 0, -176.9), Vector3(-420, 0, -179.5), 42.0],
		"detail_tree": [Vector3(-53.5, 0, 769.0), Vector3(-62, 0, 760), 55.0],
		"detail_leaf": [Vector3(-56.3, 8.4, 764.6), Vector3(-58.2, 7.4, 762.4), 55.0],
		"detail_waterfall": [Vector3(-190.0, 0, -166.0), Vector3(-203.5, 0, -198.0), 60.0],
		"rock_1m": [Vector3(-420.35, 0, -178.42), Vector3(-420.45, 0, -180.0), 44.0],
		"waterfall_20m": [Vector3(-182.0, 0, -149.0), Vector3(-203.5, 0, -198.0), 62.0],
		"detail_water": [Vector3(0, 0, 748.0), Vector3(0, 0, 772.0), 55.0],
		"detail_snow": [Vector3(-750, 0, -950), Vector3(-748, 0, -956), 55.0],
	}

func goto_shot(name: String) -> void:
	if _apply_shot(name):
		_configure(name)

func _apply_shot(name: String) -> bool:
	var d: Array = _shot_defs().get(name, [])
	if d.is_empty():
		return false
	if name == "detail_rock":
		var wall_base: float = terrain.sample_height(-420.0, -179.30) - 0.25
		d[0].y = wall_base + 2.55
		d[1].y = wall_base + 2.15
	if name == "rock_1m":
		var wall_base2: float = terrain.sample_height(-420.0, -179.30) - 0.25
		d[0].y = wall_base2 + 1.62
		d[1].y = wall_base2 + 1.50
	if name == "waterfall_20m":
		var base_y: float = field.water_level(-198.0)
		d[0].y = base_y + 15.0
		d[1].y = base_y + 23.5
	if name == "detail_tree":
		d[0].y = terrain.sample_height(d[0].x, d[0].z) + 1.7
		d[1].y = terrain.sample_height(d[1].x, d[1].z) + 7.0
	if name == "detail_leaf":
		d[0].y = terrain.sample_height(d[0].x, d[0].z) + 7.5
		d[1].y = terrain.sample_height(d[1].x, d[1].z) + 6.7
	if name == "detail_water":
		var wz := 756.0
		var wx: float = field.river_x(wz) - 2.0
		var wl: float = field.water_level(wz)
		d[0].x = wx + 3.4
		d[0].z = wz - 3.6
		d[0].y = wl + 2.2
		d[1].x = wx
		d[1].z = wz + 2.0
		d[1].y = wl + 0.15
	if name == "detail_snow":
		d[0].y = terrain.sample_height(d[0].x, d[0].z) + 1.6
		d[1].y = terrain.sample_height(d[1].x, d[1].z) + 0.9
	if name == "detail_waterfall":
		var base_y2: float = field.water_level(-198.0)
		d[0].y = base_y2 + 11.0
		d[1].y = base_y2 + 18.0
	cam.fov = d[2]
	cam.global_position = d[0]
	cam.look_at(d[1], Vector3.UP)
	print("[shot] ", name, " pos=", cam.global_position, " rot=", cam.rotation_degrees, " fwd=", -cam.global_transform.basis.z, " top=", cam.project_ray_normal(Vector2(0.5, 0.0)), " bottom=", cam.project_ray_normal(Vector2(0.5, 1.0)))
	if name.begins_with("detail") or name == "rock_1m" or name == "waterfall_20m":
		if dof_off or name == "waterfall_20m" or name == "detail_waterfall":
			cam.attributes = null
			fill.light_energy = 0.55
			fill.light_color = Color(1.0, 0.95, 0.88)
			fill.omni_range = 55.0
			fill.global_position = cam.global_position + Vector3(2.0, 2.6, 2.0)
			return true
		var ca := CameraAttributesPractical.new()
		ca.dof_blur_far_enabled = true
		ca.dof_blur_far_distance = 220.0 if name == "waterfall_20m" else (500.0 if name == "detail_waterfall" else (14.0 if name == "detail_water" else (6.0 if name == "rock_1m" or name == "detail_rock" else 8.0)))
		ca.dof_blur_far_transition = 4.0
		ca.dof_blur_amount = 0.09 if name == "detail_tree" else 0.06
		cam.attributes = ca
		fill.light_energy = 1.8 if name == "rock_1m" else (1.4 if name == "detail_rock" else (1.25 if name == "waterfall_20m" else 0.65))
		fill.light_color = Color(0.86, 0.91, 1.0) if (name == "rock_1m" or name == "detail_rock") else Color(1.0, 0.88, 0.74)
		fill.global_position = cam.global_position + Vector3(1.2, 1.6, 1.2)
	else:
		cam.attributes = null
		fill.light_energy = 0.0
	return true
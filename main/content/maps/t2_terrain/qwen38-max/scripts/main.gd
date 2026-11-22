extends Node3D
## Main orchestrator: builds the whole procedural world (terrain, water, vegetation,
## sky/sun/atmosphere), drives the interactive camera and the multi-view capture.

const TerrainGen := preload("res://scripts/terrain_gen.gd")
const TerrainLOD := preload("res://scripts/terrain_lod.gd")
const Vegetation := preload("res://scripts/vegetation.gd")
const WaterBody := preload("res://scripts/water.gd")

const ENABLE_WATER := true
const ENABLE_VEG := true
const DEBUG_FOG := true

var data: TerrainGen
var terrain: TerrainLOD
var veg: Vegetation
var rockface := Vector3.ZERO
var cam: Camera3D
var sun: DirectionalLight3D

# capture viewpoints: name, position, look-at, fov
var VIEWS := [
	{"n": "01_overview", "p": Vector3(2000, 760, 2480), "l": Vector3(2000, 60, 600), "f": 55.0},
	{"n": "02_jungle_river", "p": Vector3(1900, 70, 2300), "l": Vector3(2000, 25, 1500), "f": 65.0},
	{"n": "03_mountain_gorge", "p": Vector3(2100, 300, 1950), "l": Vector3(2100, 60, 1250), "f": 60.0},
	{"n": "04_snowfield", "p": Vector3(2000, 230, 760), "l": Vector3(2000, 120, 60), "f": 60.0},
	{"n": "05_jungle_ground", "p": Vector3(1417, 0, 2080), "l": Vector3(1611, 0, 1700), "f": 70.0, "snap": 3.5, "lsnap": 2.0},
	{"n": "06_gorge_river", "p": Vector3(2350, 330, 1650), "l": Vector3(2100, 60, 1250), "f": 60.0},
	{"n": "07_snow_close", "p": Vector3(1735, 0, 545), "l": Vector3(1810, 0, 470), "f": 65.0, "snap": 2.4, "lsnap": 1.0},
	{"n": "08_rock_close", "p": Vector3(0, 0, 0), "l": Vector3(0, 0, 0), "f": 60.0, "rockface": true},
	{"n": "09_snow_micro", "p": Vector3(1750, 0, 560), "l": Vector3(1753, 0, 563), "f": 60.0, "snap": 0.8, "lsnap": 1.1},
	{"n": "10_tree_close", "p": Vector3(0, 0, 0), "l": Vector3(0, 0, 0), "f": 60.0, "tree": "conifer_n_v0", "idx": 3},
	{"n": "11_river_close", "p": Vector3(0, 0, 0), "l": Vector3(0, 0, 0), "f": 65.0, "rz": 2000.0, "roff": 0.0, "snap": 2.2, "lrz": 1970.0, "loff": 0.0, "lsnap": 0.4},
	{"n": "12_waterfall", "p": Vector3(0, 0, 0), "l": Vector3(0, 0, 0), "f": 60.0, "rz": 1128.0, "roff": -120.0, "snap": 26.0, "lrz": 1152.0, "loff": 10.0, "lsnap": 4.0},
]

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_find_rockface()
	if ENABLE_WATER:
		var w := WaterBody.new()
		add_child(w)
		w.setup(data)
	if ENABLE_VEG:
		var foc: Array = []
		for v in VIEWS:
			if v.has("rz"):
				foc.push_back(Vector3(data.river_x(float(v.rz)), 0.0, float(v.rz)))
			elif v.p != Vector3.ZERO:
				foc.push_back(v.p)
		veg = Vegetation.new()
		add_child(veg)
		veg.setup(data, foc)
	_build_camera()
	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		set_process(false)
		_capture_all()

# ------------------------------------------------------------------ environment
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.34, 0.62)
	sm.sky_horizon_color = Color(0.62, 0.74, 0.86)
	sm.ground_bottom_color = Color(0.34, 0.41, 0.49)
	sm.ground_horizon_color = Color(0.56, 0.64, 0.73)
	sm.sun_angle_max = 12.0
	sm.sun_curve = 0.4
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 5.5
	# atmospheric height fog for aerial perspective
	e.fog_enabled = DEBUG_FOG
	e.fog_light_color = Color(0.65, 0.74, 0.85)
	e.fog_sun_scatter = 0.35
	e.fog_density = 0.00012
	e.fog_height = 60.0
	e.fog_height_density = 0.0025
	# volumetric fog (god rays / haze)
	e.volumetric_fog_enabled = DEBUG_FOG
	e.volumetric_fog_density = 0.0004
	e.volumetric_fog_albedo = Color(0.7, 0.78, 0.88)
	e.volumetric_fog_anisotropy = 0.55
	e.volumetric_fog_length = 2600.0
	e.fog_sky_affect = 0.0
	e.volumetric_fog_sky_affect = 0.0
	we.environment = e
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.0
	sun.shadow_blur = 3.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 2600.0
	sun.light_angular_distance = 1.2
	# low warm sun from the west for long shadows / golden light
	sun.rotation_degrees = Vector3(-32.0, -62.0, 0.0)
	add_child(sun)

	# procedural cloud deck (math-only fBm coverage on a high plane)
	var cp := MeshInstance3D.new()
	var cpm := PlaneMesh.new()
	cpm.size = Vector2(16000, 16000)
	var cmat := ShaderMaterial.new()
	cmat.shader = load("res://shaders/clouds.gdshader")
	cpm.material = cmat
	cp.mesh = cpm
	cp.position = Vector3(2000, 1900, 1250)
	cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cp)

# ------------------------------------------------------------------ terrain
func _find_rockface() -> void:
	var sunH := Vector3(-0.88, 0.0, 0.47)   # horizontal direction toward sun
	var z := 1500.0
	while z < 1950.0 and rockface == Vector3.ZERO:
		var x := 1500.0
		while x < 2500.0:
			var s := data.splat_at(x, z)
			var nrm := data.normal_at(x, z)
			var sl := 1.0 - nrm.y
			var h := data.height_at(x, z)
			var horiz := Vector3(nrm.x, 0.0, nrm.z).normalized()
			if s.y > 0.5 and sl > 0.40 and sl < 0.70 and h > 30.0 and h < 90.0 and horiz.dot(sunH) > 0.3:
				rockface = Vector3(x, h, z)
				break
			x += 20.0
		z += 20.0

func _build_terrain() -> void:
	data = TerrainGen.new()
	data.generate()
	var sh := load("res://shaders/terrain.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	terrain = TerrainLOD.new()
	add_child(terrain)
	terrain.setup(data, mat)
	terrain.update(Vector3(2000, 200, 2000), true)

# ------------------------------------------------------------------ camera
func _build_camera() -> void:
	cam = Camera3D.new()
	cam.current = true
	cam.fov = 60.0
	cam.far = 12000.0
	cam.near = 0.3
	add_child(cam)
	_place(cam, VIEWS[0].p, VIEWS[0].l)

func _place(c: Camera3D, p: Vector3, l: Vector3) -> void:
	c.global_position = p
	c.look_at_from_position(p, l, Vector3.UP)

# ------------------------------------------------------------------ capture
func _capture_all() -> void:
	_capture_impl()

func _capture_impl() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(2560, 1440)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.world_3d = get_tree().root.world_3d
	add_child(sv)
	var c := Camera3D.new()
	c.far = 12000.0
	c.near = 0.3
	sv.add_child(c)
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if str(a) != "--capture":
			only.push_back(str(a))
	for v in VIEWS:
		if not only.is_empty():
			var hit := false
			for o in only:
				if str(v.n).find(o) >= 0:
					hit = true
			if not hit:
				continue
		var pp: Vector3 = v.p
		var ll: Vector3 = v.l
		if v.has("rz"):
			pp.x = data.river_x(float(v.rz)) + float(v.get("roff", 0.0))
			pp.z = float(v.rz)
		if v.has("lrz"):
			ll.x = data.river_x(float(v.lrz)) + float(v.get("loff", 0.0))
			ll.z = float(v.lrz)
		if v.has("wallx"):
			ll = Vector3(data.river_x(float(v.rz)) + float(v.wallx), data.river_wl(float(v.rz)) + float(v.wally), float(v.rz) + 20.0)
		if v.has("tree"):
			var tp: Vector3 = veg.instance_pos(str(v.tree), int(v.get("idx", 0)))
			pp = tp + Vector3(2.0, 5.0, -14.0)
			ll = tp + Vector3(0.0, 5.5, 0.0)
		if v.has("rockface"):
			var nrm := data.normal_at(rockface.x, rockface.z)
			var horiz := Vector3(nrm.x, 0.0, nrm.z).normalized()
			if horiz.length_squared() < 0.5:
				horiz = Vector3(1, 0, 0)
			var tang := horiz.cross(Vector3.UP).normalized()
			pp = rockface + horiz * 5.0 + tang * 7.0 + Vector3(0.0, 2.2, 0.0)
			ll = rockface + tang * 1.0 + Vector3(0.0, 0.6, 0.0)
		if v.has("rock"):
			var rp: Vector3 = veg.instance_pos(str(v.rock), int(v.get("idx", 0)))
			pp = rp + Vector3(4.0, 1.8, 4.0)
			pp.y = maxf(pp.y, data.height_at(pp.x, pp.z) + 1.4)
			ll = rp + Vector3(0.0, 0.8, 0.0)
		if v.has("snap"):
			pp.y = (data.river_wl(float(v.rz)) if v.has("rz") else data.height_at(pp.x, pp.z)) + float(v.snap)
		if v.has("lsnap"):
			ll.y = (data.river_wl(float(v.lrz)) if v.has("lrz") else data.height_at(ll.x, ll.z)) + float(v.lsnap)
		_place(c, pp, ll)
		c.fov = v.f
		terrain.update(pp, true)
		for i in range(6):
			await RenderingServer.frame_post_draw
		var img := sv.get_texture().get_image()
		var path: String = dir + "/" + str(v.n) + ".png"
		img.save_png(path)
		print("CAPTURED:", path)
	get_tree().quit()

# ------------------------------------------------------------------ interactive
var _cam_yaw := 0.0
var _cam_pitch := -0.2
var _cam_pos := Vector3(2000, 300, 2200)
var _mouse_delta := Vector2.ZERO

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_mouse_delta += ev.relative

func _process(delta: float) -> void:
	# simple fly camera
	var speed := 120.0 * delta
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 4.0
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move += fwd
	if Input.is_key_pressed(KEY_S): move -= fwd
	if Input.is_key_pressed(KEY_D): move += right
	if Input.is_key_pressed(KEY_A): move -= right
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP
	if move.length_squared() > 0.0:
		_cam_pos += move.normalized() * speed
	if _mouse_delta.length_squared() > 0.0:
		_cam_yaw -= _mouse_delta.x * 0.003
		_cam_pitch = clampf(_cam_pitch - _mouse_delta.y * 0.003, -1.4, 1.4)
		_mouse_delta = Vector2.ZERO
	var dirv := Vector3(
		cos(_cam_pitch) * sin(_cam_yaw),
		sin(_cam_pitch),
		cos(_cam_pitch) * cos(_cam_yaw))
	cam.global_position = _cam_pos
	cam.look_at_from_position(_cam_pos, _cam_pos + dirv, Vector3.UP)
	terrain.update(_cam_pos)

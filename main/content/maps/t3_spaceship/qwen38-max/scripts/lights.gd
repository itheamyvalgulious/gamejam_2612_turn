class_name Lights
extends RefCounted
## Environment (procedural sky, SSAO, glow, volumetric fog) + all light
## placement derived from the layout. Shadow casters use distance fade so
## only lights near the camera pay for shadows.

var lay: Layout
var volfog := true

func _init(layout: Layout) -> void:
	lay = layout

func build(root: Node) -> void:
	_environment(root)
	_sun(root)
	_room_lights(root)
	_fog_volumes(root)

func _environment(root: Node) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("u_planet_dir", Vector3(0.45, 0.1, -0.89).normalized())
	sm.set_shader_parameter("u_planet_rad", 0.185)
	sm.set_shader_parameter("u_sun_dir", Vector3(0.42, 0.28, -0.86).normalized())
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	env.ambient_light_color = Color(0.55, 0.64, 0.8)
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 5.0
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.5
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.062, 0.085)
	env.fog_light_energy = 0.7
	env.fog_density = 0.0008
	env.fog_sky_affect = 0.0
	env.tonemap_exposure = 1.0
	we.environment = env
	root.add_child(we)

func _sun(root: Node) -> void:
	# distant sun (exterior key light) + planet fill
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 155.0, 0.0)
	sun.light_color = Color(0.95, 0.95, 1.0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-6.0, -55.0, 0.0)
	fill.light_color = Color(0.35, 0.5, 0.85)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	root.add_child(fill)

func _spot(parent: Node, pos: Vector3, dir: Vector3, color: Color, energy: float,
		range_m: float, angle_deg: float, shadow: bool) -> SpotLight3D:
	var l := SpotLight3D.new()
	parent.add_child(l)
	l.position = pos
	if dir == Vector3.DOWN:
		l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	else:
		l.look_at(pos + dir, Vector3.UP)
	l.light_color = color
	l.light_energy = energy * 0.55
	l.spot_range = range_m
	l.spot_angle = angle_deg
	l.shadow_enabled = shadow
	l.light_angular_distance = 0.7
	l.distance_fade_enabled = true
	l.distance_fade_begin = 52.0
	l.distance_fade_shadow = 26.0
	l.distance_fade_length = 44.0
	l.light_volumetric_fog_energy = 1.5
	return l

func _omni(parent: Node, pos: Vector3, color: Color, energy: float, range_m: float, shadow: bool) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy * 0.55
	l.omni_range = range_m
	l.shadow_enabled = shadow
	l.distance_fade_enabled = true
	l.distance_fade_begin = 60.0
	l.distance_fade_shadow = 30.0
	l.distance_fade_length = 50.0
	l.light_volumetric_fog_energy = 1.4
	parent.add_child(l)
	return l

func _room_lights(root: Node) -> void:
	var ln := Node3D.new()
	ln.name = "Lights"
	root.add_child(ln)
	for r in lay.rooms:
		var style: String = r["style"]
		var y0: float = r["y0"]; var y1: float = r["y1"]
		var cx: float = (r["x0"] + r["x1"]) * 0.5
		var cz: float = (r["z0"] + r["z1"]) * 0.5
		var lx: float = r["x1"] - r["x0"]
		var lz: float = r["z1"] - r["z0"]
		match style:
			"corridor":
				var along_x: bool = lx >= lz
				var length: float = lx if along_x else lz
				var n := maxi(int(length / 7.0), 1)
				for i in n:
					var t := lerpf(3.0, length - 3.0, float(i) / maxf(float(n - 1), 1.0)) if n > 1 else length * 0.5
					var pos := Vector3(r["x0"] + t, y1 - 0.35, cz) if along_x else Vector3(cx, y1 - 0.35, r["z0"] + t)
					_spot(ln, pos, Vector3.DOWN, Color(0.8, 0.87, 1.0), 22.0, 11.0, 60.0, r["detail"] >= 2)
			"engine":
				_spot(ln, Vector3(16, 4.6, -14), Vector3.DOWN, Color(1.0, 0.72, 0.42), 40.0, 16, 64, true)
				_spot(ln, Vector3(44, 4.6, 14), Vector3.DOWN, Color(1.0, 0.72, 0.42), 40.0, 16, 64, true)
				_spot(ln, Vector3(16, 4.6, 20), Vector3.DOWN, Color(1.0, 0.75, 0.45), 30.0, 15, 64, false)
				_spot(ln, Vector3(44, 4.6, -20), Vector3.DOWN, Color(1.0, 0.75, 0.45), 30.0, 15, 64, false)
				_spot(ln, Vector3(30, 4.6, 26), Vector3.DOWN, Color(1.0, 0.78, 0.5), 30.0, 15, 70, false)
				_spot(ln, Vector3(30, 4.6, -26), Vector3.DOWN, Color(1.0, 0.78, 0.5), 30.0, 15, 70, false)
				_spot(ln, Vector3(18, 4.6, 0), Vector3.DOWN, Color(0.95, 0.88, 0.78), 22.0, 14, 66, false)
				_spot(ln, Vector3(42, 4.6, 0), Vector3.DOWN, Color(0.95, 0.88, 0.78), 22.0, 14, 66, false)
				_omni(ln, Vector3(30, 3.4, 0), Color(1.0, 0.55, 0.2), 22.0, 24.0, true)
				_omni(ln, Vector3(30, 0.8, 0), Color(1.0, 0.45, 0.15), 20.0, 14.0, false)
				_omni(ln, Vector3(0, 3.0, 18), Color(0.5, 0.7, 1.0), 24.0, 15.0, false)
				_omni(ln, Vector3(0, 3.0, -18), Color(0.5, 0.7, 1.0), 24.0, 15.0, false)
			"control":
				_spot(ln, Vector3(59, y1 - 0.4, -5), Vector3.DOWN, Color(0.85, 0.9, 1.0), 24.0, 12, 62, true)
				_spot(ln, Vector3(62, y1 - 0.4, 6), Vector3.DOWN, Color(0.85, 0.9, 1.0), 24.0, 12, 62, true)
				_omni(ln, Vector3(62.5, 2.2, 0), Color(0.4, 0.75, 1.0), 10.0, 8.0, false)
			"airlock":
				_omni(ln, Vector3(70, 4.2, 0), Color(1.0, 0.35, 0.2), 14.0, 10.0, true)
				_spot(ln, Vector3(70, y1 - 0.3, 0), Vector3.DOWN, Color(1.0, 0.85, 0.75), 12.0, 9, 64, false)
			"junction":
				_spot(ln, Vector3(cx, y1 - 0.35, cz), Vector3.DOWN, Color(0.8, 0.88, 1.0), 18.0, 11, 60, true)
				_spot(ln, Vector3(cx - lx * 0.25, y1 - 0.35, cz - lz * 0.25), Vector3.DOWN, Color(0.8, 0.88, 1.0), 12.0, 9, 58, false)
			"ramp":
				var i := 0
				while i < 6:
					var xx := 80.0 + float(i) * 6.8
					var fy := 0.0 if xx <= 78.0 else minf((xx - 78.0) * 7.5 / 36.0, 7.5)
					_spot(ln, Vector3(xx, fy + 4.1, -13.0), Vector3.DOWN, Color(1.0, 0.88, 0.72), 40.0, 12, 62, true)
					i += 1
			"shaft":
				_spot(ln, Vector3(cx, y1 - 0.4, cz), Vector3.DOWN, Color(0.8, 0.87, 1.0), 32.0, 13, 62, r["detail"] >= 1)
			"hangar":
				for k in 4:
					for j in 2:
						_spot(ln, Vector3(136.0 + float(k) * 16.0, 18.0, -16.0 - float(j) * 18.0), Vector3.DOWN, Color(0.92, 0.94, 1.0), 85.0, 24, 48, k < 2)
				_omni(ln, Vector3(184, 13.0, -11), Color(0.5, 0.8, 1.0), 12.0, 11.0, false)
				for fo in [Vector3(140, 12.0, -18), Vector3(172, 12.0, -18), Vector3(140, 12.0, -34), Vector3(172, 12.0, -34)]:
					_omni(ln, fo, Color(0.85, 0.9, 1.0), 10.0, 26.0, false)
				_spot(ln, Vector3(150, 10.0, -24), Vector3(0, 0.35, -1), Color(0.95, 0.95, 1.0), 35.0, 30, 55, false)
				_spot(ln, Vector3(172, 10.0, -24), Vector3(0, 0.35, -1), Color(0.95, 0.95, 1.0), 35.0, 30, 55, false)
				_spot(ln, Vector3(136, 11.0, -4.0), Vector3(0.2, -0.6, -0.8), Color(1.0, 0.8, 0.4), 20.0, 14, 58, false)
			"catwalk":
				_spot(ln, Vector3(150, 20.5, -5.5), Vector3.DOWN, Color(0.9, 0.92, 1.0), 22.0, 12, 60, false)
				_spot(ln, Vector3(192, 20.5, -24.0), Vector3.DOWN, Color(0.9, 0.92, 1.0), 18.0, 14, 60, false)
			"mess":
				var n := 2 if r["name"] == "WARDROOM" else 3
				for k in n:
					_spot(ln, Vector3(lerpf(r["x0"] + 4.0, r["x1"] - 4.0, float(k) / maxf(float(n - 1), 1.0)), y1 - 0.4, cz), Vector3.DOWN, Color(1.0, 0.85, 0.66), 36.0, 13, 74, true)
				_omni(ln, Vector3(r["x0"] + 2.5, y1 - 1.6, cz), Color(1.0, 0.82, 0.6), 8.0, 9.0, false)
			"medical":
				_spot(ln, Vector3(136, y1 - 0.4, 10), Vector3.DOWN, Color(0.92, 0.96, 1.0), 30.0, 13, 62, true)
				_spot(ln, Vector3(150, y1 - 0.4, 20), Vector3.DOWN, Color(0.92, 0.96, 1.0), 26.0, 13, 62, true)
				_omni(ln, Vector3(154, y1 - 1.9, 16), Color(1.0, 1.0, 0.96), 20.0, 9.0, false)
			"hydro":
				for k in 3:
					_spot(ln, Vector3(168.0 + float(k) * 10.0, y1 - 0.4, 18.0), Vector3.DOWN, Color(1.0, 0.7, 0.95), 42.0, 14, 62, k == 1)
				_omni(ln, Vector3(180, 2.0, 12), Color(0.9, 0.35, 1.0), 10.0, 12.0, false)
				_omni(ln, Vector3(194, 2.4, 10), Color(0.4, 1.0, 0.5), 7.0, 9.0, false)
			"lab":
				for k in 2:
					_spot(ln, Vector3(lerpf(r["x0"] + 4.0, r["x1"] - 4.0, float(k)), y1 - 0.4, cz), Vector3.DOWN, Color(0.9, 0.96, 1.0), 24.0, 13, 62, k == 0)
			"server":
				for k in 3:
					_spot(ln, Vector3(158.0 + float(k) * 13.0, y1 - 0.4, 17.0), Vector3.DOWN, Color(0.65, 0.82, 1.0), 26.0, 14, 62, false)
				_omni(ln, Vector3(172, y0 + 2.2, 12), Color(0.3, 0.7, 1.0), 12.0, 10.0, false)
			"lounge":
				_spot(ln, Vector3(205, y1 - 0.4, -20), Vector3.DOWN, Color(1.0, 0.86, 0.68), 32.0, 13, 64, true)
				_spot(ln, Vector3(218, y1 - 0.4, -30), Vector3.DOWN, Color(1.0, 0.86, 0.68), 24.0, 13, 64, false)
				_omni(ln, Vector3(211, y0 + 2.0, -41), Color(0.5, 0.65, 1.0), 5.0, 11.0, false)
			"bridge":
				if r["name"] == "BRIDGE":
					_spot(ln, Vector3(254, y1 - 0.5, -6), Vector3.DOWN, Color(0.8, 0.88, 1.0), 26.0, 13, 62, true)
					_spot(ln, Vector3(262, y1 - 0.5, 0), Vector3.DOWN, Color(0.8, 0.88, 1.0), 22.0, 13, 62, true)
					_spot(ln, Vector3(254, y1 - 0.5, 10), Vector3.DOWN, Color(0.8, 0.88, 1.0), 16.0, 12, 62, false)
					_omni(ln, Vector3(263, y0 + 2.0, 0), Color(0.4, 0.75, 1.0), 10.0, 11.0, false)
					_omni(ln, Vector3(256, 19.0, -8), Color(0.6, 0.8, 1.0), 8.0, 12.0, false)
					_omni(ln, Vector3(256, 19.0, 8), Color(0.6, 0.8, 1.0), 8.0, 12.0, false)
					_omni(ln, Vector3(252, 18.0, 16), Color(1.0, 0.82, 0.6), 6.0, 9.0, false)
					_omni(ln, Vector3(254.5, y0 + 2.4, 13), Color(0.3, 0.8, 1.0), 10.0, 9.0, false)
					_omni(ln, Vector3(252, y0 + 1.8, 16), Color(1.0, 0.8, 0.55), 4.0, 8.0, false)
			"quarters":
				_spot(ln, Vector3(cx, y1 - 0.4, cz), Vector3.DOWN, Color(1.0, 0.82, 0.6), 34.0, 12, 68, r["detail"] >= 2)
			"gym":
				_spot(ln, Vector3(cx, y1 - 0.4, cz), Vector3.DOWN, Color(0.95, 0.95, 1.0), 22.0, 13, 64, false)
			"cargo":
				for k in 3:
					_spot(ln, Vector3(lerpf(r["x0"] + 4.0, r["x1"] - 4.0, float(k) / 2.0), y1 - 1.2, cz), Vector3.DOWN, Color(1.0, 0.88, 0.7), 64.0, 15, 62, k == 1)
			"pods":
				_spot(ln, Vector3(cx, y1 - 0.4, cz), Vector3.DOWN, Color(1.0, 0.8, 0.55), 18.0, 12, 62, false)
			"eva":
				if r["name"] == "EVA AIRLOCK":
					_spot(ln, Vector3(65, y1 - 0.4, -16), Vector3.DOWN, Color(1.0, 0.85, 0.65), 20.0, 12, 62, true)
				else:
					_omni(ln, Vector3(64, 9.4, -36), Color(1.0, 0.75, 0.45), 11.0, 11.0, false)
			_:
				# utility / storage / office / tanks / life: one or two modest fixtures
				var n := 1 if lx * lz < 500.0 else 2
				for k in n:
					var px := lerpf(r["x0"] + lx * 0.3, r["x1"] - lx * 0.3, float(k) / maxf(float(n - 1), 1.0))
					var col := Color(0.85, 0.9, 1.0)
					if style == "life":
						col = Color(0.75, 1.0, 0.85)
					elif style == "tanks":
						col = Color(0.75, 0.9, 1.0)
					_spot(ln, Vector3(px, y1 - 0.4, cz), Vector3.DOWN, col, 20.0, 13, 64, false)

func _fog_volumes(root: Node) -> void:
	if not volfog:
		return
	var specs := [
		[Vector3(30, 3.0, 0), Vector3(52, 6.0, 80), 0.05],
		[Vector3(160, 14.2, -23.5), Vector3(72, 13.4, 41), 0.006],
		[Vector3(94, 2.6, -13), Vector3(40, 5.0, 6), 0.06],
		[Vector3(150, 10.5, 0), Vector3(150, 6.0, 6), 0.045],
		[Vector3(156, 3.0, 0), Vector3(138, 6.0, 6), 0.045],
		[Vector3(150, 18.0, 0), Vector3(150, 6.0, 6), 0.03],
		[Vector3(258, 18.0, 0), Vector3(26, 6.0, 44), 0.03],
		[Vector3(232, 11.25, 0), Vector3(12, 22.5, 16), 0.05],
		[Vector3(211, 18.0, -23.5), Vector3(30, 6.0, 41), 0.028],
		[Vector3(172, 18.0, 17.5), Vector3(40, 6.0, 29), 0.03],
		[Vector3(181, 10.5, 19.5), Vector3(38, 6.0, 33), 0.035],
		[Vector3(106, 10.5, 17.5), Vector3(40, 6.0, 29), 0.03],
		[Vector3(80, 3.0, 0), Vector3(12, 6.0, 20), 0.05],
	]
	for s in specs:
		var fv := FogVolume.new()
		fv.shape = 3  # SHAPE_BOX (enum not exposed to GDScript in this build)
		fv.size = s[1]
		fv.position = s[0]
		var fm := FogMaterial.new()
		fm.density = s[2]
		fm.albedo = Color(0.72, 0.76, 0.86)
		fm.emission = Color(0.0, 0.0, 0.0)
		fv.material = fm
		root.add_child(fv)

var _probe_specs := [
	[Vector3(258, 17.5, 0), Vector3(28, 5.5, 42)],
	[Vector3(172, 16.8, 17), Vector3(38, 5.5, 28)],
	[Vector3(211, 17.0, -24), Vector3(27, 5.5, 40)],
	[Vector3(106, 9.5, 18), Vector3(38, 5.5, 28)],
	[Vector3(144, 9.5, 16), Vector3(30, 5.5, 26)],
	[Vector3(30, 3.0, 0), Vector3(48, 5.5, 76)],
	[Vector3(160, 13.0, -24), Vector3(68, 12.0, 38)],
	[Vector3(61, 3.0, 0), Vector3(10, 5.5, 48)],
]

func probe_count() -> int:
	return _probe_specs.size()

## Spawn one reflection probe per call (staggered across frames by main).
func spawn_probe(i: int, root: Node) -> void:
	var s: Array = _probe_specs[i]
	var p := ReflectionProbe.new()
	p.position = s[0]
	p.size = s[1]
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.box_projection = true
	p.intensity = 0.7
	p.max_distance = 60.0
	root.add_child(p)

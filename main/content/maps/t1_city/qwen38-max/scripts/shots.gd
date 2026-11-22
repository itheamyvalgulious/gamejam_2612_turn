extends Node3D
## Automated screenshot runner: builds the city then tours a camera list,
## saving PNGs to res://shots/. Run: DISPLAY=:0 godot --path . res://scenes/shots.tscn -- --seed=7

var _cam: Camera3D
var _sv: SubViewport
var _gen: CityGen

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			out["seed"] = int(a.trim_prefix("--seed="))
		elif a.begins_with("--focus="):
			var parts := a.trim_prefix("--focus=").split(",")
			if parts.size() == 2:
				out["focus"] = Vector3(float(parts[0]), 0, float(parts[1]))
		elif a.begins_with("--only="):
			out["only"] = a.trim_prefix("--only=").split(",")
		elif a == "--day":
			out["day"] = true
		elif a == "--nofog":
			out["nofog"] = true
		elif a == "--noglow":
			out["noglow"] = true
		elif a == "--nomsaa":
			out["nomsaa"] = true
		elif a == "--dayfull":
			out["dayfull"] = true
	return out

func _ready() -> void:
	var args := _parse_args()
	var t0 := Time.get_ticks_msec()
	var gen := CityGen.new()
	gen.params = args
	gen.build(self)
	_gen = gen
	print("[shots] city built in %.1fs buildings=%d tris=%d" % [
		(Time.get_ticks_msec() - t0) / 1000.0, gen.stat_buildings, gen.stat_tris])

	_sv = SubViewport.new()
	_sv.size = Vector2i(1920, 1080)
	_sv.msaa_3d = Viewport.MSAA_DISABLED if args.has("nomsaa") else Viewport.MSAA_4X
	_sv.disable_3d = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	_cam = Camera3D.new()
	_cam.far = 16000.0
	_cam.fov = 60.0
	_sv.add_child(_cam)
	_cam.current = true
	if args.has("dayfull"):
		for c in get_children():
			if c is DirectionalLight3D:
				c.light_energy = 3.2
				c.light_color = Color(1.0, 0.96, 0.9)
				c.rotation_degrees = Vector3(-48, 30, 0)
			if c is WorldEnvironment:
				var e: Environment = c.environment
				e.background_mode = Environment.BG_SKY
				if _gen.sky_mat:
					_gen.sky_mat.set_shader_parameter("zenith", Color(0.16, 0.36, 0.72))
					_gen.sky_mat.set_shader_parameter("horizon", Color(0.62, 0.68, 0.76))
					_gen.sky_mat.set_shader_parameter("dome", Color(0.0, 0.0, 0.0))
					_gen.sky_mat.set_shader_parameter("dome_strength", 0.0)
					_gen.sky_mat.set_shader_parameter("star_scale", 0.0)
				e.ambient_light_source = Environment.AMBIENT_SOURCE_BG
				e.ambient_light_energy = 1.0
				e.glow_enabled = false
				e.tonemap_mode = Environment.TONE_MAPPER_ACES
	if args.has("noglow"):
		for c in get_children():
			if c is WorldEnvironment:
				c.environment.glow_enabled = false
	if args.has("nofog"):
		for c in get_children():
			if c is WorldEnvironment:
				c.environment.fog_enabled = false
	if args.has("day"):
		for c in get_children():
			if c is DirectionalLight3D:
				c.light_energy = 4.0
				c.light_color = Color(1, 1, 1)
			if c is WorldEnvironment:
				c.environment.fog_enabled = false
				c.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
				c.environment.ambient_light_energy = 1.0

	var only: Array = args.get("only", [])
	var shots: Array = _shot_list()
	# auto-place the interior shot: pick a curtain-wall tower with clear LOS
	var cands := []
	for t in _gen.interior_targets:
		if t.get("lobby", false):
			continue
		if (t.frame.origin - Vector3.ZERO).length() < 500.0:
			cands.append(t)
	cands.sort_custom(func(a, b): return a.h > b.h)
	var placed := false
	for t in cands.slice(0, 10):
		if t.get("lobby", false):
			continue
		var o: Vector3 = t.frame.origin
		for cand in [t.frame.basis.x, -t.frame.basis.x, t.frame.basis.z, -t.frame.basis.z]:
			var n: Vector3 = cand.normalized()
			var ext := 0.0
			for pv in t.fp:
				ext = maxf(ext, (Vector3(pv.x, 0, pv.y) - o).dot(n))
			var cam0: Vector3 = o + n * (ext + 58.0) + Vector3(0, 26.0, 0)
			if absf(n.x) > 0.5:
				cam0.x = round((cam0.x + 1750.0) / 125.0) * 125.0 - 1750.0
			else:
				cam0.z = round((cam0.z + 1500.0) / 125.0) * 125.0 - 1500.0
			# line-of-sight check against other building centers
			var blocked := false
			var to := o + Vector3(0, 30.0, 0)
			var steps := int((to - cam0).length() / 12.0)
			for stx in steps:
				var sp: Vector3 = cam0.lerp(to, float(stx) / float(maxi(steps, 1)))
				for sg in _gen.sign_targets:
					var c: Vector3 = sg.pos
					if (c - o).length() < 5.0:
						continue
					if (Vector3(c.x, sp.y, c.z) - sp).length() < 42.0:
						blocked = true
						break
				if blocked:
					break
			if not blocked:
				for s2 in shots:
					if s2.name == "a07_glass_interior":
						s2.pos = cam0
						s2.fov = 50
						s2.target = o + n * ext * 0.4 + Vector3(0, 24.0, 0)
				print("[shots] a07 auto: origin=", o, " cam=", cam0)
				placed = true
				break
		if placed:
			break
	# a13: camera 1.8 m off a mid-rise facade, raking along the wall
	var wall_pick: Dictionary = {}
	for st in _gen.sign_targets:
		if st.tier > 1 or st.h < 12.0 or st.h > 40.0:
			continue
		if (st.pos - Vector3.ZERO).length() > 400.0:
			continue
		if st.style != 1 and st.style != 2 and st.style != 3:
			continue
		var good_face: Dictionary = {}
		for dd in st.dirs:
			if dd.len < 20.0:
				continue
			var probe: Vector3 = dd.pos + dd.n * 14.0
			var clear := true
			for oo in _gen.sign_targets:
				var oc: Vector3 = oo.pos
				if (oc - st.pos).length() < 5.0:
					continue
				if (Vector3(oc.x, probe.y, oc.z) - probe).length() < 30.0:
					clear = false
					break
			if clear:
				good_face = dd
				break
		if good_face.is_empty():
			continue
		wall_pick = st
		wall_pick.face = good_face
		break
	if not wall_pick.is_empty():
		var d0: Dictionary = wall_pick.face
		var n0: Vector3 = d0.n
		var tg0 := Vector3(-n0.z, 0, n0.x)
		var base: Vector3 = d0.pos + n0 * 1.8 + Vector3(0, 13.3, 0)
		for s3 in shots:
			if s3.name == "a13_wall_1m":
				s3.pos = base
				s3.target = base + tg0 * 1.4 + n0 * 4.0 + Vector3(0, -0.2, 0)
		print("[shots] a13: pos=", base, " n=", n0, " style=", wall_pick.style, " h=", wall_pick.h)
	for s in shots:
		if only.size() > 0 and not only.has(s.name):
			continue
		_cam.fov = s.get("fov", 60.0)
		_cam.position = s.pos
		_cam.look_at(s.target, Vector3.UP)
		if _gen.interior_streamer:
			_gen.interior_streamer.force_at(s.pos)
		var wait := int(s.get("frames", 14))
		for k in wait:
			await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := _sv.get_texture().get_image()
		var path := "res://shots/%s.png" % s.name
		img.save_png(path)
		print("[shots] saved ", path)
	print("[shots] done  interior_tris=", _gen.stat_interior_tris)
	get_tree().quit()

func _shot_list() -> Array:
	return [
		{"name": "a01_skyline_high", "pos": Vector3(-1500, 1500, 2300), "target": Vector3(0, 150, 0), "fov": 55},
		{"name": "a02_downtown_oblique", "pos": Vector3(-750, 520, 1150), "target": Vector3(0, 160, -100), "fov": 58},
		{"name": "a03_street_canyon", "pos": Vector3(14, 9, 380), "target": Vector3(0, 55, -250), "fov": 70},
		{"name": "a04_city_edge", "pos": Vector3(1500, 260, 1900), "target": Vector3(-300, 120, -400), "fov": 55},
		{"name": "a05_river_bridges", "pos": Vector3(350, 240, 2150), "target": Vector3(0, 30, 850), "fov": 58},
		{"name": "a06_elevated", "pos": Vector3(-900, 90, 350), "target": Vector3(400, 40, 0), "fov": 65},
		{"name": "a07_glass_interior", "pos": Vector3(235, 42, 195), "target": Vector3(70, 52, 30), "fov": 55},
		{"name": "a08_harbor_ferris", "pos": Vector3(830, 70, 1420), "target": Vector3(1180, 45, 900), "fov": 60},
		{"name": "a09_topdown", "pos": Vector3(0, 2600, 40), "target": Vector3(0, 0, 20), "fov": 60},
		{"name": "a10_school_park", "pos": Vector3(300, 60, 780), "target": Vector3(480, 20, 620), "fov": 62},
		{"name": "a11_facade_close", "pos": Vector3(-260, 9, 330), "target": Vector3(-232, 26, 250), "fov": 55},
		{"name": "a12_riverside_walk", "pos": Vector3(500, 6, 780), "target": Vector3(430, 8, 900), "fov": 62},
		{"name": "a13_wall_1m", "pos": Vector3(0, 3.5, 0), "target": Vector3(1, 4, 1), "fov": 65},
	]

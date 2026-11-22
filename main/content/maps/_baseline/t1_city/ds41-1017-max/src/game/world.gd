## World: assembles plan, ground, streamed buildings and gameplay camera.
class_name World
extends Node3D

const MID_RADIUS := 980.0
const FULL_RADIUS := 300.0

class Chunk:
	var key := Vector2i.ZERO
	var blds: Array = []
	var shell: MeshInstance3D
	var mid: MeshInstance3D
	var props: MeshInstance3D
	var props_built := false
	var full_nodes: Array = []
	var nodes := {}
	var interior_nodes := {}
	var int_lights := {}
	var full_built := false
	var mid_built := false
	var shell_built := false
	var dist := 0.0
	var lamps: Array = []

var plan: CityPlan
var env: Env
var ground: MeshInstance3D
var water: MeshInstance3D
var shell_root: Node3D
var chunk_root: Node3D
var chunks := {}
var order: Array = []
var pending: Array = []
var player: Node3D
var cam: Camera3D
var hud: CanvasLayer
var label: Label
var loading := true
var t := 0.0
var lod_timer := 0.0
var stats_timer := 0.0
var shot_mode := ""
var shot_path := ""
var shot_frames := 40
var shot_ready := false
var frames := 0
var args := {}
var tri_total := 0
var light_pool: Array = []
var int_light_pool: Array = []
var interior_queue: Array = []
var interior_done := {}
var xray_target := -1
var xray_on := false
var interior_timer := 0.0
var xray_delay := 0.0
var inside_bld := -1
var traffic: Traffic
var fx: Fx
var light_pos: Array = []
var light_timer := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=")
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	shot_mode = str(args.get("shot", ""))
	if shot_mode != "":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	shot_path = str(args.get("out", "user://shot.png"))
	shot_frames = int(args.get("frames", "40"))
	Mats.build()
	if str(args.get("simplemat", "0")) == "1":
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.45, 0.45, 0.48)
		sm.roughness = 0.7
		Mats.surface = sm
	env = Env.new()
	add_child(env)
	env.setup(str(args.get("preset", "night")))
	env.rain = float(args.get("rain", "0.85"))
	if str(args.get("fog", "1")) == "0":
		env.env.volumetric_fog_enabled = false
		env.env.fog_enabled = false
	if str(args.get("vol", "1")) == "0":
		env.env.volumetric_fog_enabled = false
	if str(args.get("ssao", "1")) == "0":
		env.env.ssao_enabled = false
	if str(args.get("ssr", "1")) == "0":
		env.env.ssr_enabled = false
	if str(args.get("glow", "1")) == "0":
		env.env.glow_enabled = false
	if str(args.get("shadow", "1")) == "0":
		env.sun.shadow_enabled = false
	var t0 := Time.get_ticks_msec()
	plan = CityPlan.new()
	plan.generate(int(args.get("seed", "1337")))
	Builder.setup(plan)
	print("plan: ", plan.blds.size(), " buildings, ", plan.blocks.size(), " blocks in ", Time.get_ticks_msec() - t0, " ms")
	shell_root = Node3D.new()
	shell_root.name = "Shell"
	add_child(shell_root)
	chunk_root = Node3D.new()
	chunk_root.name = "Chunks"
	add_child(chunk_root)
	# ground
	var gmb := MB.new()
	Ground.build(plan, gmb)
	ground = gmb.instance(Mats.surface, Mats.glass, false)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	# water
	water = _make_water()
	add_child(water)
	# elevated expressway
	var imb := MB.new()
	var hw_route := Infra.build(plan, imb, 1280.0)
	var hw_mi := imb.instance(Mats.surface, Mats.glass, false)
	hw_mi.name = "Expressway"
	add_child(hw_mi)
	# street routes for traffic
	var routes: Array = []
	for r in plan.roads:
		if r.cls < 2:
			continue
		var a: Vector2 = r.path[0]
		var b: Vector2 = r.path[r.path.size() - 1]
		if r.vertical and absf(a.x - plan.river_x(0.0)) < plan.river_w * 0.6:
			continue
		var pts := PackedVector3Array()
		for v in r.path:
			pts.append(Vector3(v.x, 0.05, v.y))
		var total := 0.0
		for i in pts.size() - 1:
			total += pts[i].distance_to(pts[i + 1])
		routes.append({"pts": pts, "len": total, "loop": false})
	routes.append(hw_route)
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(plan, env, routes)
	if str(args.get("traffic", "1")) == "0":
		traffic.enabled = false
	fx = Fx.new()
	add_child(fx)
	fx.setup()
	fx.set_intensity(env.rain)
	# chunks
	for cx in 20:
		for cz in 20:
			var c := Chunk.new()
			c.key = Vector2i(cx, cz)
			c.blds = plan.bld_in_chunk(c.key)
			chunks[c.key] = c
	order = chunks.values()
	# pooled street lights
	for i in 36:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 30.0
		l.omni_attenuation = 1.2
		l.light_specular = 0.6
		l.shadow_enabled = false
		l.light_color = Color(1.0, 0.82, 0.62) if i % 3 != 0 else Color(0.62, 0.82, 1.0)
		l.light_volumetric_fog_energy = 1.6
		add_child(l)
		light_pool.append(l)
	for i in 30:
		var il := OmniLight3D.new()
		il.light_energy = 0.0
		il.omni_range = 13.0
		il.light_color = Color(1.0, 0.86, 0.68)
		il.shadow_enabled = false
		il.light_volumetric_fog_energy = 0.2
		add_child(il)
		int_light_pool.append(il)
	# camera / player
	_spawn_player()
	_make_hud()
	# build the far-city shell up front (single pass)
	_sort_pending()
	var tb := Time.get_ticks_msec()
	while pending.size() > 0:
		_build_shell(pending.pop_front())
	loading = false
	print("shell prebuilt in ", Time.get_ticks_msec() - tb, " ms")
	print("setup: ", Time.get_ticks_msec() - t0, " ms  tris=", gmb.tri_count())

func _sort_pending() -> void:
	pending.clear()
	for c in chunks.values():
		pending.append(c)
	var pp := cam.global_position if cam else Vector3.ZERO
	pending.sort_custom(func(a, b):
		var ca := Vector3(-CityPlan.HALF + (a.key.x + 0.5) * CityPlan.CELL, 0, -CityPlan.HALF + (a.key.y + 0.5) * CityPlan.CELL)
		var cb := Vector3(-CityPlan.HALF + (b.key.x + 0.5) * CityPlan.CELL, 0, -CityPlan.HALF + (b.key.y + 0.5) * CityPlan.CELL)
		return ca.distance_squared_to(pp) < cb.distance_squared_to(pp))

func _make_water() -> MeshInstance3D:
	var mb := MB.new()
	var rx := plan.river_x(0.0)
	var hw := plan.river_w * 0.5
	var z0 := -CityPlan.HALF - 80.0
	var z1 := CityPlan.HALF + 80.0
	mb.setm(M.ASPHALT, Color(0.05, 0.10, 0.12), 0.1)
	mb.quad(Vector3(rx - hw + 0.2, -1.55, z0), Vector3(rx - hw + 0.2, -1.55, z1),
		Vector3(rx + hw - 0.2, -1.55, z1), Vector3(rx + hw - 0.2, -1.55, z0))
	var mi := MeshInstance3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://gfx/water.gdshader")
	mi.mesh = mb.commit(mat, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _spawn_player() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 68.0
	cam.far = 4200.0
	cam.near = 0.15
	add_child(cam)
	var p := Node3D.new()
	p.set_script(load("res://src/game/player.gd"))
	add_child(p)
	p.set("cam", cam)
	p.set("world", self)
	player = p
	var preset := str(args.get("view", "street"))
	var pos := Vector3(11.0, 2.1, 352)
	var look := Vector3(-60.0, 18.0, 150)
	if shot_mode != "":
		preset = shot_mode
	match preset:
		"aerial":
			pos = Vector3(-300, 330, 980)
			look = Vector3(0, 10, -40)
		"aerial2":
			pos = Vector3(760, 180, 620)
			look = Vector3(120, 60, -260)
		"street":
			pos = Vector3(11.0, 2.1, 352)
			look = Vector3(-60.0, 18.0, 150)
		"canal":
			pos = Vector3(870, 4.0, -200)
			look = Vector3(960, 3.0, 200)
		"tower":
			pos = Vector3(240, 120, 420)
			look = Vector3(-60, 110, 40)
		"roof":
			pos = Vector3(-150, 120, 190)
			look = Vector3(-120, 20, 120)
		"interior":
			pos = Vector3(-96, 2.1, 260)
			look = Vector3(-40, 9.0, 40)
	if args.has("campos"):
		var v: PackedStringArray = str(args["campos"]).split(",")
		pos = Vector3(float(v[0]), float(v[1]), float(v[2]))
	if args.has("camlook"):
		var v: PackedStringArray = str(args["camlook"]).split(",")
		look = Vector3(float(v[0]), float(v[1]), float(v[2]))
	if str(args.get("view", "")) == "room":
		var q2 := Vector3(0, 0, 300)
		if args.has("nearbld"):
			q2 = Vector3(float(args["nearbld"].split(",")[0]), 0, float(args["nearbld"].split(",")[1]))
		var best2: CityPlan.Bld = null
		var bd2 := 1e9
		for b in plan.blds:
			if b.kind != CityPlan.K_OFFICE and b.kind != CityPlan.K_TOWER:
				continue
			if b.floors < 5 or b.h < 18.0 or b.h > 140.0:
				continue
			var d2: float = Vector2(b.cx - q2.x, b.cz - q2.z).length()
			if d2 < bd2:
				bd2 = d2
				best2 = b
		if best2:
			var bb2 := Poly.bbox(best2.poly)
			var fh2 := Builder.floor_h(best2)
			var fl: int = int(args.get("floor", "3"))
			var fy2: float = 0.16 + 5.0 + (fl - 1) * fh2 + 1.55
			var ctr := Poly.centroid(best2.poly)
			var room := Vector3(ctr.x - bb2.size.x * 0.16, fy2, ctr.y - bb2.size.y * 0.14)
			var look2 := Vector3(ctr.x + bb2.size.x * 0.5, fy2 - 0.3, ctr.y + bb2.size.y * 0.42)
			pos = room
			look = look2
			inside_bld = best2.id
			print("ROOM bld ", best2.id, " floors=", best2.floors, " size=", bb2.size, " y=", fy2,
				" campos=", pos, " inside=", Poly.contains(best2.poly, Vector2(pos.x, pos.z)))
	if str(args.get("view", "")) == "inside":
		var q := Vector3(0, 0, 300)
		if args.has("nearbld"):
			q = Vector3(float(args["nearbld"].split(",")[0]), 0, float(args["nearbld"].split(",")[1]))
		var best: CityPlan.Bld = null
		var bd := 1e9
		for b in plan.blds:
			if b.h < 20.0 or b.floors < 4:
				continue
			var d: float = Vector2(b.cx - q.x, b.cz - q.z).length()
			if d < bd:
				bd = d
				best = b
		if best:
			var bb := Poly.bbox(best.poly)
			var fy: float = float(args.get("insidey", "11"))
			pos = Vector3(best.cx + bb.size.x * 0.18, fy, best.cz)
			look = Vector3(best.cx - bb.size.x * 0.4, fy - 1.0, best.cz + 2.0)
			inside_bld = best.id
			print("INSIDE bld ", best.id, " floors=", best.floors, " h=", best.h, " kind=", best.kind, " size=", bb.size)
	if args.has("nearbld"):
		# frame the building nearest to the given point
		var q := Vector3(float(args["nearbld"].split(",")[0]), 0, float(args["nearbld"].split(",")[1]))
		var best: CityPlan.Bld = null
		var bd := 1e9
		for b in plan.blds:
			var d: float = Vector2(b.cx - q.x, b.cz - q.z).length()
			if d < bd:
				bd = d
				best = b
		if best:
			var py: float = float(args.get("bldy", "12"))
			var dist: float = float(args.get("bldd", "26"))
			var dirv := Vector3(best.cx - q.x, 0, best.cz - q.z).normalized()
			pos = Vector3(best.cx, 0, best.cz) - dirv * dist + Vector3(0, py, 0)
			look = Vector3(best.cx, py * 0.85, best.cz)
			print("framing bld ", best.id, " kind=", best.kind, " h=", best.h, " style=", best.style, " at ", best.cx, ",", best.cz, " poly=", best.poly.size())
	cam.position = pos
	cam.look_at(look)
	if shot_mode != "":
		# freeze the camera for a screenshot
		cam.set_process(false)
		cam.set_physics_process(false)
		if player.has_method("set"):
			player.set("frozen", true)

func _make_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.035, 0.55)
	sb.border_color = Color(0.35, 0.9, 0.85, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	hud.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	label = Label.new()
	label.position = Vector2.ZERO
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	var sh := Label.new()
	sh.position = Vector2(16, 34)
	sh.add_theme_font_size_override("font_size", 13)
	sh.add_theme_color_override("font_color", Color(1.0, 0.55, 0.85))
	sh.text = "WASD fly  ·  Shift boost  ·  T time  ·  R rain  ·  X x-ray  ·  F fps"
	vb.add_child(label)
	vb.add_child(sh)
	if shot_mode != "" or str(args.get("hud", "1")) == "0":
		hud.visible = false

func _process(delta: float) -> void:
	t += delta
	frames += 1
	if loading:
		_update_label()
		return
	lod_timer += delta
	if lod_timer > 0.25:
		lod_timer = 0.0
		_update_lod()
	if fx:
		fx.follow(cam.global_position)
	light_timer += delta
	if light_timer > 0.35:
		light_timer = 0.0
		_update_lights()
	if xray_delay > 0.0:
		xray_delay -= delta
		if xray_delay <= 0.0:
			set_xray(true)
	interior_timer += delta
	if interior_timer > 0.15:
		interior_timer = 0.0
		_update_interiors(delta)
	stats_timer += delta
	if stats_timer > 0.5:
		stats_timer = 0.0
		stats_timer = 0.0
		_update_label()
	if str(args.get("bench", "0")) == "1":
		if str(args.get("vsync", "0")) == "0" and not bench_vsync_off:
			bench_vsync_off = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_bench(delta)
	if shot_mode != "" and frames >= shot_frames and not shot_ready:
		shot_ready = true
		_take_shot()
		await get_tree().create_timer(0.15).timeout
		get_tree().quit()

func _build_shell_budget(ms: float) -> void:
	var start := Time.get_ticks_usec()
	var pp := cam.global_position
	while pending.size() > 0 and (Time.get_ticks_usec() - start) < ms * 1000.0:
		var c: Chunk = pending.pop_front()
		_build_shell(c)
	# still sort by distance so the nearest are built first
	if pending.size() > 0 and frames % 30 == 0:
		pending.sort_custom(func(a, b):
			var ca := _chunk_center(a)
			var cb := _chunk_center(b)
			return ca.distance_squared_to(pp) < cb.distance_squared_to(pp))

func _chunk_center(c: Chunk) -> Vector3:
	return Vector3(-CityPlan.HALF + (c.key.x + 0.5) * CityPlan.CELL, 0, -CityPlan.HALF + (c.key.y + 0.5) * CityPlan.CELL)

func _build_shell(c: Chunk) -> void:
	if c.shell_built:
		return
	c.shell_built = true
	if c.blds.is_empty():
		return
	var mb := MB.new()
	for b in c.blds:
		Builder.far(b, mb)
	if mb.is_empty():
		return
	var mi := mb.instance(Mats.surface, Mats.glass, true)
	mi.name = "shell_%d_%d" % [c.key.x, c.key.y]
	shell_root.add_child(mi)
	c.shell = mi

func _update_lod() -> void:
	var pp := cam.global_position

	for c in chunks.values():
		var ctr := _chunk_center(c)
		var d := ctr.distance_to(pp)
		c.dist = d
		if d > MID_RADIUS + 160.0:
			_set_shell(c, true)
			_set_mid(c, false, false)
			continue
		_set_shell(c, d > FULL_RADIUS + 60.0)
		if d <= FULL_RADIUS + 60.0:
			_ensure_full(c)
			_set_mid(c, false, false)
		else:
			_ensure_mid(c)
			_set_mid(c, true, false)

func _set_shell(c: Chunk, on: bool) -> void:
	if c.shell:
		c.shell.visible = on

func _ensure_mid(c: Chunk) -> void:
	if c.mid_built:
		return
	c.mid_built = true
	var mb := MB.new()
	for b in c.blds:
		Builder.mid(b, mb)
	if not mb.is_empty():
		var mi := mb.instance(Mats.surface, Mats.glass, true)
		mi.name = "mid_%d_%d" % [c.key.x, c.key.y]
		chunk_root.add_child(mi)
		c.mid = mi
	_build_props(c, mb)

func _build_props(c: Chunk, _mb: MB) -> void:
	if c.props_built:
		return
	c.props_built = true
	var mb := MB.new()
	c.lamps = []
	Props.chunk(plan, mb, c.key, true, c.lamps)
	if not mb.is_empty():
		var mi := mb.instance(Mats.surface, Mats.glass, false)
		mi.name = "props_%d_%d" % [c.key.x, c.key.y]
		chunk_root.add_child(mi)
		c.props = mi

func _set_mid(c: Chunk, on: bool, _x: bool) -> void:
	if c.mid:
		c.mid.visible = on
	if c.props:
		c.props.visible = on or c.full_built

func _ensure_full(c: Chunk) -> void:
	if c.full_built:
		return
	c.full_built = true
	if c.mid:
		c.mid.visible = false
	for b in c.blds:
		var mb := MB.new()
		Builder.full(b, mb)
		if mb.is_empty():
			continue
		var mi := mb.instance(Mats.surface, Mats.glass, true)
		mi.name = "bld_%d" % b.id
		mi.set_meta("bld", b.id)
		chunk_root.add_child(mi)
		c.full_nodes.append(mi)
		c.nodes[b.id] = mi
	for b in c.blds:
		if c.nodes.has(b.id):
			continue
		for mi in c.full_nodes:
			if mi.get_meta("bld", -1) == b.id:
				c.nodes[b.id] = mi
	if c.props == null:
		_build_props(c, null)

func _nearest_bld() -> CityPlan.Bld:
	var pp := cam.global_position
	var best: CityPlan.Bld = null
	var bd := 1e9
	for c in chunks.values():
		if not c.full_built:
			continue
		for b in c.blds:
			if b.h < 12.0:
				continue
			var d: float = Vector2(b.cx - pp.x, b.cz - pp.z).length()
			if d > 120.0:
				continue
			# inside the footprint counts as closest
			var inside := Poly.contains(b.poly, Vector2(pp.x, pp.z))
			if inside:
				d = 0.0
			if d < bd:
				bd = d
				best = b
	return best

var interior_budget := 3
func _update_interiors(_delta: float) -> void:
	if str(args.get("nointerior", "0")) == "1":
		return
	interior_budget = 3
	var pp := cam.global_position
	var cand: Array = []
	for c in chunks.values():
		if not c.full_built:
			continue
		for b in c.blds:
			var d: float = Vector2(b.cx - pp.x, b.cz - pp.z).length()
			if d > 150.0 and b.id != xray_target:
				continue
			cand.append([d, b, c])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for it in cand:
		var d: float = it[0]
		var b: CityPlan.Bld = it[1]
		var c: Chunk = it[2]
		var want_hi := 0
		var lo := 0
		var hi := 0
		var fh := Builder.floor_h(b)
		if b.id == xray_target and xray_on:
			lo = 0
			hi = mini(b.floors - 1, 24)
			want_hi = hi
		elif d < 72.0:
			var fy := int((pp.y - 5.16) / fh) + 1
			lo = maxi(0, mini(fy - 1, b.floors - 1))
			hi = mini(fy + 3, b.floors - 1)
			hi = mini(hi, 7)
			if pp.y < 9.0:
				lo = 0
				hi = maxi(hi, 2)
			want_hi = hi
		else:
			want_hi = 0
		if interior_done.has(b.id):
			var got: Array = interior_done[b.id]
			if got[1] >= want_hi:
				continue
		interior_done[b.id] = [lo, hi]
		_build_interior(b, c, lo, hi)
		interior_budget -= 1
		if interior_budget <= 0:
			break

func _build_interior(b: CityPlan.Bld, c: Chunk, lo: int, hi: int) -> void:
	var mb := MB.new()
	var n := Interior.build(b, mb, lo, hi)
	if mb.is_empty():
		return
	var mi := mb.instance(Mats.surface, Mats.glass, false)
	mi.name = "int_%d" % b.id
	chunk_root.add_child(mi)
	if c.interior_nodes.has(b.id):
		var old: MeshInstance3D = c.interior_nodes[b.id]
		old.queue_free()
	c.interior_nodes[b.id] = mi
	var fh2 := Builder.floor_h(b)
	var lps: Array = []
	var ib := Poly.bbox(Poly.inset(b.poly, 2.0))
	for f in range(lo, hi + 1):
		var yy := 0.16 + (5.0 + (f - 1) * fh2) + 1.0 if f > 0 else 3.0
		for gx in 3:
			for gz in 3:
				if gx == 1 and gz == 1:
					continue
				lps.append(Vector3(ib.position.x + ib.size.x * (gx + 0.5) / 3.0,
					yy + 1.6, ib.position.y + ib.size.y * (gz + 0.5) / 3.0))
		lps.append(Vector3(b.cx, yy + 1.6, b.cz))
	c.int_lights[b.id] = lps
	if str(args.get("debug", "0")) == "1":
		print("interior bld ", b.id, " floors ", lo, "..", hi, " tris ", mb.tri_count(),
			" aabb=", mi.mesh.get_aabb(), " pos=", mi.global_position)

func set_xray(on: bool) -> void:
	xray_on = on
	var b := _nearest_bld()
	var prev := xray_target
	xray_target = b.id if (b != null and on) else -1
	# restore previous
	if prev != -1:
		_apply_xray_to(prev, -1)
	if xray_target != -1:
		_apply_xray_to(xray_target, 1)
		interior_done.erase(xray_target)
		print("XRAY building ", xray_target, " floors ", b.floors, " h ", b.h, " kind ", b.kind)

func _apply_xray_to(id: int, mode: int) -> void:
	for c in chunks.values():
		if not c.full_built:
			continue
		for b in c.blds:
			if b.id == id:
				var node: MeshInstance3D = c.nodes.get(id, null)
				if node:
					node.transparency = 0.86 if mode == 1 else 0.0
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				return

func hud_msg(t: String) -> void:
	if label:
		label.text = t

func _update_lights() -> void:
	var pp := cam.global_position
	var cand: Array = []
	for c in chunks.values():
		if c.dist > 260.0 or c.lamps.is_empty():
			continue
		for lp in c.lamps:
			var d: float = (lp as Vector3).distance_squared_to(pp)
			if d < 260.0 * 260.0:
				cand.append([d, lp])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(light_pool.size(), cand.size())
	for i in light_pool.size():
		if i < n:
			var l: OmniLight3D = light_pool[i]
			var lp: Vector3 = cand[i][1]
			l.global_position = lp
			l.light_energy = 9.0 if i < 16 else 4.0
		else:
			light_pool[i].light_energy = 0.0
	# interior fill lights: nearest generated floors
	var icand: Array = []
	for c in chunks.values():
		if c.int_lights.is_empty():
			continue
		for k in c.int_lights:
			for lp2 in c.int_lights[k]:
				var d2: float = (lp2 as Vector3).distance_squared_to(pp)
				if d2 < 90.0 * 90.0:
					icand.append([d2, lp2])
	icand.sort_custom(func(a, b): return a[0] < b[0])
	for i in int_light_pool.size():
		var il: OmniLight3D = int_light_pool[i]
		if i < icand.size():
			il.global_position = icand[i][1]
			il.light_energy = 2.0 if xray_on else 0.95
		else:
			il.light_energy = 0.0

func _count_tris() -> int:
	var n := 0
	for c in chunks.values():
		if c.shell:
			n += c.shell.mesh.get_faces().size() / 3
	return n

func _update_label() -> void:
	if label == null:
		return
	var info := "NEON SPRAWL  ·  %d buildings  ·  10.2 km²  ·  %.0f fps" % [plan.blds.size(), Engine.get_frames_per_second()]
	if loading:
		info = "BUILDING CITY  %d%%" % int(100.0 * (1.0 - float(pending.size()) / maxf(1.0, chunks.size())))
	label.text = info

var bench_vsync_off := false
var bench_frames := 0
var bench_time := 0.0
func _bench(delta: float) -> void:
	if loading:
		return
	bench_frames += 1
	if bench_frames > 30:
		bench_time += delta
	if bench_frames == 200:
		print("BENCH vsync=", DisplayServer.window_get_vsync_mode(), " fps=", 170.0 / bench_time, " draws=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			" prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			" objects=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
		get_tree().quit()

func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	print("shot: ", shot_path, " ", img.get_width(), "x", img.get_height(), " fps=", Engine.get_frames_per_second())

# -------------------------------------------------------------- interactions
func toggle_time() -> void:
	var order := ["night", "dusk", "day", "storm"]
	var i := order.find(env.current)
	env.apply(order[(i + 1) % order.size()])

func toggle_rain() -> void:
	env.rain = 0.15 if env.rain > 0.5 else 0.95
	env.apply(env.current)
	Mats.sun(env.night, env.rain)
	if fx:
		fx.set_intensity(env.rain)

func toggle_xray() -> void:
	set_xray(not xray_on)

func toggle_cutaway() -> void:
	set_xray(not xray_on)

func toggle_hud() -> void:
	if hud:
		hud.visible = not hud.visible

func enter_interior() -> void:
	var b := _nearest_bld()
	if b == null:
		return
	# teleport inside the ground floor lobby
	var fh := Builder.floor_h(b)
	var p := Vector3(b.cx, 1.7, b.cz)
	player.set("pos", p)
	player.set("frozen", false)
	cam.global_position = p
	set_xray(true)
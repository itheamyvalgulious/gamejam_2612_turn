class_name Props
extends PropsCore
## Per-room content: functional zones each get their own spatial language.

var lay: Layout

func _init(geom: Geom, layout: Layout) -> void:
	super._init(geom)
	lay = layout

func variant_of(r: Dictionary) -> int:
	return int(float(r["seed"]) * 3.999) % 3

func damage_of(r: Dictionary) -> int:
	if r["name"] == "CARGO HOLD B":
		return 2
	if r["name"] == "WASTE RECYCLING":
		return 1
	if r["name"] == "SPINE C-1 DECK 1":
		return 1
	var h := int(hash(r["name"] + "dmg") % 11)
	if h == 0:
		return 2
	if h < 3:
		return 1
	return 0

func build_all() -> void:
	for r in lay.rooms:
		seed_room(r)
		match String(r["style"]):
			"corridor": _corridor(r)
			"engine": _engine_bay(r)
			"control": _control(r)
			"airlock": _airlock(r)
			"junction": _junction(r)
			"cargo": _cargo(r)
			"utility": _utility(r)
			"life": _life(r)
			"mess": _mess(r)
			"medical": _medical(r)
			"hydro": _hydro(r)
			"lab": _lab(r)
			"quarters": _quarters(r)
			"gym": _gym(r)
			"hangar": _hangar(r)
			"catwalk": _catwalk(r)
			"server": _server(r)
			"lounge": _lounge(r)
			"bridge": _bridge(r)
			"office": _office(r)
			"storage": _storage(r)
			"eva": _eva(r)
			"pods": _pods(r)
			"tanks": _tanks(r)
			"shaft": _shaft(r)
			"ramp": pass
		var dmg := damage_of(r)
		if dmg > 0 and r["custom"] == "" and r["style"] != "shaft":
			_damage(r, dmg)
		var ar: float = (r["x1"] - r["x0"]) * (r["z1"] - r["z0"])
		if ar > 60.0 and not (r["style"] in ["corridor", "shaft", "ramp", "catwalk", "bridge"]):
			_clutter(r)

# --------------------------------------------------------------- corridors

func _corridor(r: Dictionary) -> void:
	var y0: float = r["y0"]; var y1: float = r["y1"]
	var detail: int = r["detail"]
	var command: bool = r["name"] == "COMMAND PASSAGE"
	var accent: String = "strip_cyan"
	var along_x: bool = (r["x1"] - r["x0"]) >= (r["z1"] - r["z0"])
	var length: float = (r["x1"] - r["x0"]) if along_x else (r["z1"] - r["z0"])
	if length < 8.0:
		# short link corridor: just lights + strips
		ceiling_lights(r, accent, 1)
		return
	var mid_c: float = (r["z0"] + r["z1"]) * 0.5 if along_x else (r["x0"] + r["x1"]) * 0.5
	var halfw: float = (r["z1"] - r["z0"]) * 0.5 if along_x else (r["x1"] - r["x0"]) * 0.5
	# ribs + ceiling beams every 3m
	var n := int(length / 3.0)
	for i in n + 1:
		var t := float(i) * 3.0 + 1.0
		if t > length - 0.8:
			break
		if along_x:
			var xx: float = r["x0"] + t
			g.box("panel_dark", Vector3(xx, (y0 + y1) * 0.5, r["z0"] + 0.11), Vector3(0.3, y1 - y0 - 0.15, 0.22), COL_DARK)
			g.box("panel_dark", Vector3(xx, (y0 + y1) * 0.5, r["z1"] - 0.11), Vector3(0.3, y1 - y0 - 0.15, 0.22), COL_DARK)
			g.box("frame", Vector3(xx, y1 - 0.14, mid_c), Vector3(0.26, 0.28, halfw * 2.0 - 0.3), COL_MACH)
		else:
			var zz: float = r["z0"] + t
			g.box("panel_dark", Vector3(r["x0"] + 0.11, (y0 + y1) * 0.5, zz), Vector3(0.22, y1 - y0 - 0.15, 0.3), COL_DARK)
			g.box("panel_dark", Vector3(r["x1"] - 0.11, (y0 + y1) * 0.5, zz), Vector3(0.22, y1 - y0 - 0.15, 0.3), COL_DARK)
			g.box("frame", Vector3(mid_c, y1 - 0.14, zz), Vector3(halfw * 2.0 - 0.3, 0.28, 0.26), COL_MACH)
	# cove light strips (2 lines)
	for s in [-1.0, 1.0]:
		if along_x:
			strip_along(accent, Vector3(r["x0"] + 0.8, y1 - 0.1, mid_c + s * halfw * 0.45), Vector3(r["x1"] - 0.8, y1 - 0.1, mid_c + s * halfw * 0.45), 0.18)
		else:
			strip_along(accent, Vector3(mid_c + s * halfw * 0.45, y1 - 0.1, r["z0"] + 0.8), Vector3(mid_c + s * halfw * 0.45, y1 - 0.1, r["z1"] - 0.8), 0.18)
	# high wall pipes + brackets
	for s in [-1.0, 1.0]:
		for k in 2:
			var off := halfw - 0.32 - float(k) * 0.16
			var yy := y1 - 0.75 - float(k) * 0.28
			if along_x:
				g.cylinder("metal_dark", Vector3(r["x0"] + 0.3, yy, mid_c + s * off), Vector3(r["x1"] - 0.3, yy, mid_c + s * off), 0.06 - float(k) * 0.012, COL_MACH, 8)
			else:
				g.cylinder("metal_dark", Vector3(mid_c + s * off, yy, r["z0"] + 0.3), Vector3(mid_c + s * off, yy, r["z1"] - 0.3), 0.06 - float(k) * 0.012, COL_MACH, 8)
	# floor cable trenches both sides
	for s in [-1.0, 1.0]:
		if along_x:
			var zt: float = mid_c + s * (halfw - 0.58)
			g.box("metal_dark", Vector3((r["x0"] + r["x1"]) * 0.5, y0 + 0.012, zt), Vector3(length - 0.4, 0.025, 0.5), Color(0.16, 0.165, 0.18))
			g.box("strip_cyan", Vector3((r["x0"] + r["x1"]) * 0.5, y0 + 0.03, zt + s * 0.15), Vector3(length - 0.6, 0.02, 0.035), Color.WHITE)
			g.box("grate_std", Vector3((r["x0"] + r["x1"]) * 0.5, y0 + 0.035, zt - s * 0.05), Vector3(length - 0.4, 0.02, 0.3), Color.WHITE)
		else:
			var xt: float = mid_c + s * (halfw - 0.58)
			g.box("metal_dark", Vector3(xt, y0 + 0.012, (r["z0"] + r["z1"]) * 0.5), Vector3(0.5, 0.025, length - 0.4), Color(0.16, 0.165, 0.18))
			g.box("strip_cyan", Vector3(xt + s * 0.15, y0 + 0.03, (r["z0"] + r["z1"]) * 0.5), Vector3(0.035, 0.02, length - 0.6), Color.WHITE)
	# kick plates
	for s in [-1.0, 1.0]:
		if along_x:
			g.box("metal_dark", Vector3((r["x0"] + r["x1"]) * 0.5, y0 + 0.07, mid_c + s * (halfw - 0.16)), Vector3(length, 0.14, 0.02), COL_DARK)
		else:
			g.box("metal_dark", Vector3(mid_c + s * (halfw - 0.16), y0 + 0.07, (r["z0"] + r["z1"]) * 0.5), Vector3(0.02, 0.14, length), COL_DARK)
	if command:
		# carpet runner + brass trim
		if along_x:
			g.box("fabric", Vector3((r["x0"] + r["x1"]) * 0.5, y0 + 0.02, mid_c), Vector3(length, 0.03, 1.8), Color(0.16, 0.18, 0.3))
			for s in [-1.0, 1.0]:
				g.box("metal_warm", Vector3((r["x0"] + r["x1"]) * 0.5, y0 + 0.09, mid_c + s * (halfw - 0.3)), Vector3(length, 0.18, 0.05), Color(0.65, 0.55, 0.35))
	if damage_of(r) > 0:
		var hx := lerpf(r["x0"] + 8.0, r["x1"] - 8.0, rng.randf())
		g.box_basis("panel_dark", Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(18.0)), Vector3(hx, y1 - 0.5, mid_c - halfw + 0.35)), Vector3(2.4, 0.05, 0.8), Color(0.3, 0.31, 0.33))
		g.pipe("rubber", [Vector3(hx - 1.0, y1 - 0.1, mid_c - halfw + 0.4), Vector3(hx - 0.6, y1 - 1.4, mid_c - halfw + 0.7), Vector3(hx - 0.2, y1 - 0.3, mid_c - halfw + 0.5)], 0.03, Color(0.1, 0.1, 0.11), 5)
		for k in 5:
			g.box("metal_dark", Vector3(hx + (rng.randf() - 0.5) * 3.0, y0 + 0.06, mid_c + (rng.randf() - 0.5) * 2.0), Vector3(0.3, 0.1, 0.25), Color(0.2, 0.19, 0.18), rng.randf() * 3.0)
		g.box("rubber", Vector3(hx, y0 + 0.015, mid_c), Vector3(2.4, 0.03, 1.4), Color(0.05, 0.045, 0.04))
	if detail >= 2:
		# wall screens + extinguisher niches periodically
		var k := 0
		var xw: float = r["x0"] + 12.0
		while xw < r["x1"] - 3.0:
			if along_x:
				var sk: String = "screen_bars" if k % 2 == 0 else "screen_cyan"
				wall_screen(sk, Vector3(xw, y0 + 2.05, mid_c - (halfw - 0.17)), Vector3(0, 0, 1), 1.0, 0.64)
				# extinguisher niche opposite side
				g.box("metal_dark", Vector3(xw + 6.0, y0 + 1.0, mid_c + (halfw - 0.1)), Vector3(0.5, 0.9, 0.14), COL_DARK)
				g.cylinder("metal", Vector3(xw + 6.0, y0 + 0.72, mid_c + halfw - 0.22), Vector3(xw + 6.0, y0 + 1.25, mid_c + halfw - 0.22), 0.08, COL_RED, 8)
			k += 1
			xw += 24.0

# --------------------------------------------------------------- engine bay

func _engine_bay(r: Dictionary) -> void:
	var c := Vector3(30.0, 0.0, 0.0)
	# reactor pedestal
	g.cylinder("metal_dark", Vector3(30, 0, 0), Vector3(30, 0.55, 0), 5.2, Color(0.3, 0.3, 0.33), 28)
	g.torus("frame_rust", Vector3(30, 0.58, 0), Basis(), 5.2, 0.14, COL_DARK, 32, 8)
	# core column + glowing bands
	g.cylinder("metal", Vector3(30, 0.55, 0), Vector3(30, 5.5, 0), 2.2, Color(0.4, 0.41, 0.45), 24)
	for yy in [1.3, 2.6, 3.9, 5.0]:
		g.torus("emit_amber", Vector3(30, yy, 0), Basis(), 2.26, 0.09, Color.WHITE, 26, 8)
	# containment coils (tilted toruses)
	for k in 3:
		var b := Basis(Vector3(1, 0, 0), deg_to_rad(14.0 + float(k) * 8.0)) * Basis(Vector3(0, 1, 0), float(k) * 1.1)
		g.torus("frame_rust", Vector3(30, 1.6 + float(k) * 1.35, 0), b, 3.35, 0.26, Color(0.45, 0.42, 0.38), 28, 10)
		g.torus("emit_amber", Vector3(30, 1.6 + float(k) * 1.35, 0), b, 3.35, 0.07, Color.WHITE, 28, 6)
	# top dome + ceiling penetration
	g.sphere("metal_dark", Vector3(30, 5.5, 0), Vector3(2.2, 0.9, 2.2), Color(0.35, 0.36, 0.4), 20, 8, 0.0, TAU, 0.0, PI * 0.5)
	g.torus("frame", Vector3(30, 5.95, 0), Basis(), 1.1, 0.16, COL_MACH, 20, 8)
	g.cylinder("metal_dark", Vector3(30, 5.85, 0), Vector3(30, 6.3, 0), 0.9, COL_DARK, 16)
	# coolant pipes: 4 runs from pedestal to walls
	for k in 4:
		var a := TAU * (float(k) / 4.0 + 0.2)
		var p0 := Vector3(30.0 + cos(a) * 4.6, 1.1, sin(a) * 4.6)
		var p1 := Vector3(30.0 + cos(a) * 9.0, 1.1, sin(a) * 9.0)
		var p2 := Vector3(30.0 + cos(a) * 9.0, 4.8, sin(a) * 9.0)
		var wx := 54.0 if cos(a) > 0.3 else (6.5 if cos(a) < -0.3 else p2.x)
		var wz := 37.0 * signf(sin(a)) if absf(sin(a)) > 0.5 else p2.z
		var p3 := Vector3(clampf(p2.x + cos(a) * 12.0, 7.0, 53.0), 4.8, clampf(p2.z + sin(a) * 12.0, -37.0, 37.0))
		g.pipe("metal_dark", [p0, p1, p2, p3], 0.3, Color(0.42, 0.44, 0.5), 10)
		g.torus("frame", p1, Basis(), 0.42, 0.08, COL_DARK, 12, 6)
	# catwalk ring y=3.5
	var rc_in := 5.8; var rc_out := 7.4
	var seg := 28
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var am := (a0 + a1) * 0.5
		var chord := 2.0 * 6.6 * sin((a1 - a0) * 0.5) + 0.06
		var pos := Vector3(30.0 + cos(am) * 6.6, 3.44, sin(am) * 6.6)
		g.box("grate_std", pos, Vector3(chord, 0.08, rc_out - rc_in), Color.WHITE, -am)
		g.box("frame", pos - Vector3(0, 0.14, 0), Vector3(chord, 0.22, rc_out - rc_in + 0.1), Color(0.4, 0.4, 0.43), -am)
	# ring railings
	var pts_in: Array = []
	var pts_out: Array = []
	for i in 17:
		var a := TAU * float(i) / 16.0
		pts_in.append(Vector3(30.0 + cos(a) * (rc_in + 0.1), 3.5, sin(a) * (rc_in + 0.1)))
		pts_out.append(Vector3(30.0 + cos(a) * (rc_out - 0.1), 3.5, sin(a) * (rc_out - 0.1)))
	g.railing("metal_dark", pts_in, 1.0, Color.WHITE)
	g.railing("metal_dark", pts_out, 1.0, Color.WHITE)
	# catwalk supports + stairs
	for k in 6:
		var a := TAU * float(k) / 6.0 + 0.5
		var p := Vector3(30.0 + cos(a) * 6.6, 0.0, sin(a) * 6.6)
		g.cylinder("frame", p, p + Vector3(0, 3.4, 0), 0.13, COL_MACH, 8)
		g.strut("frame", p + Vector3(0, 1.2, 0), Vector3(30.0 + cos(a) * 5.2, 3.3, sin(a) * 5.2), 0.08, 0.08, COL_MACH)
	g.stairs("metal", Vector3(30, 0, 10.2), Vector3(0, 0, -1), 3.44, 2.9, 1.6, 16, Color(0.5, 0.52, 0.55), "", Color.WHITE)
	g.stairs("metal", Vector3(30, 0, -10.2), Vector3(0, 0, 1), 3.44, 2.9, 1.6, 16, Color(0.5, 0.52, 0.55), "", Color.WHITE)
	# console arc south of core
	for k in 5:
		var a := deg_to_rad(-44.0 + float(k) * 22.0)
		var pos := Vector3(30.0 + sin(a) * 11.5, 0.0, cos(a) * 11.5)
		console(pos, a + PI, "screen_amber", 2.3)
		chair(pos + (pos - c).normalized() * 1.3, a + PI, COL_DARK)
	# drive units interior dressing (nacelles at z=+-18 run through bay)
	for zs in [-18.0, 18.0]:
		for xx in [10.0, 18.0]:
			g.strut("frame_rust", Vector3(xx, 0.0, zs - 3.2 * signf(zs)), Vector3(xx, 3.0, zs - 1.5 * signf(zs)), 0.3, 0.3, Color(0.45, 0.43, 0.4))
		g.torus("frame_rust", Vector3(6.0, 3.0, zs), Basis(Vector3.UP, PI * 0.5), 5.75, 0.3, Color(0.45, 0.42, 0.38), 26, 8)
		g.torus("frame_rust", Vector3(-4.0, 3.0, zs), Basis(Vector3.UP, PI * 0.5), 5.75, 0.3, Color(0.45, 0.42, 0.38), 26, 8)
		g.box("strip_amber", Vector3(1.0, 8.62, zs), Vector3(14.0, 0.08, 0.12), Color.WHITE)
	# fuel tanks + lines
	for zs in [-28.0, 28.0]:
		tank_v(Vector3(12.0, 0.0, zs), 1.3, 3.4, Color(0.45, 0.4, 0.34), "strip_amber")
		g.pipe("metal_dark", [Vector3(12.0, 3.9, zs), Vector3(12.0, 4.9, zs), Vector3(16.0, 4.9, zs * 0.7), Vector3(16.0, 3.4, zs * 0.62)], 0.16, COL_DARK, 8)
	# generator row along north wall
	for k in 4:
		machine_box(Vector3(14.0 + float(k) * 8.5, 0.0, -35.5), 0.0, Vector3(3.4, 2.3, 2.2), Color(0.38, 0.39, 0.42), 2)
		g.cylinder("metal_dark", Vector3(14.0 + float(k) * 8.5 + 1.9, 0.6, -35.5), Vector3(14.0 + float(k) * 8.5 + 1.9, 0.6, -33.2), 0.18, COL_DARK, 8)
	ceiling_pipes(r, 3, 0.55, 0.16)
	# heat exchanger bank east-north
	g.box("metal", Vector3(46.0, 1.6, -36.0), Vector3(7.0, 3.0, 1.4), COL_MACH)
	for i in 9:
		g.box("metal_dark", Vector3(42.8 + float(i) * 0.8, 1.6, -35.2), Vector3(0.1, 2.6, 0.1), COL_DARK)
	g.pipe("metal_dark", [Vector3(46.0, 3.4, -36.0), Vector3(46.0, 5.2, -36.0), Vector3(38.0, 5.2, -36.0)], 0.22, COL_MACH, 8)
	# overhead crane
	g.ibeam("frame_yellow", Vector3(20.0, 5.35, -38.0), Vector3(20.0, 5.35, 38.0), 0.7, 0.3, Color.WHITE)
	g.box("metal_dark", Vector3(20.0, 4.85, 14.0), Vector3(1.0, 0.5, 1.6), COL_DARK)
	g.cylinder("metal_dark", Vector3(20.0, 4.6, 14.0), Vector3(20.0, 2.6, 14.0), 0.03, COL_DARK, 6)
	g.box("metal", Vector3(20.0, 2.5, 14.0), Vector3(0.5, 0.3, 0.4), COL_YELLOW)
	# warning beacons on posts
	for p in [Vector3(12, 0, 12), Vector3(48, 0, -12), Vector3(48, 0, 12), Vector3(12, 0, -12)]:
		g.cylinder("metal_dark", p, p + Vector3(0, 2.4, 0), 0.07, COL_DARK, 8)
		g.cylinder("strip_red", p + Vector3(0, 2.4, 0), p + Vector3(0, 2.62, 0), 0.12, Color.WHITE, 8)
	# toolboxes, reels, manhole covers
	for k in 6:
		var px := 36.0 + rng.randf() * 14.0
		var pz := (16.0 + rng.randf() * 16.0) * (1.0 if k % 2 == 0 else -1.0)
		crate(Vector3(px, 0.0, pz), Vector3(0.7, 0.4, 0.45), [COL_RED.darkened(0.1), COL_YELLOW.darkened(0.15), COL_MACH][k % 3], rng.randf() * 0.6)
	for k in 3:
		g.cylinder("metal_dark", Vector3(52.0, 0.45, 20.0 + float(k) * 2.2), Vector3(52.0, 0.45, 20.0 + float(k) * 2.2) + Vector3(0, 0, 0), 0.01, COL_DARK, 6)
		g.cylinder("metal", Vector3(51.4, 0.55, 24.0 + float(k) * 3.0), Vector3(52.4, 0.55, 24.0 + float(k) * 3.0), 0.55, Color(0.3, 0.3, 0.33), 12)
	for k in 4:
		var mx := 10.0 + float(k) * 12.0
		g.cylinder("metal_dark", Vector3(mx, 0.06, 30.0), Vector3(mx, 0.08, 30.0), 0.45, Color(0.25, 0.25, 0.27), 12)
		g.torus("frame_rust", Vector3(mx, 0.09, 30.0), Basis(), 0.46, 0.03, COL_DARK, 12, 6)

func _control(r: Dictionary) -> void:
	# console row facing the observation window (x=56)
	for zz in [-7.0, -3.0, 3.0, 7.0]:
		console(Vector3(58.9, 0.0, zz), -PI * 0.5, "screen_amber" if absf(zz) > 5 else "screen_cyan", 2.0)
		chair(Vector3(60.2, 0.0, zz), -PI * 0.5, COL_DARK)
	# holo status table
	g.cylinder("metal_dark", Vector3(62.5, 0, 0), Vector3(62.5, 0.9, 0), 0.85, COL_DARK, 16)
	g.torus("strip_cyan", Vector3(62.5, 0.92, 0), Basis(), 0.86, 0.04, Color.WHITE, 18, 6)
	g.sphere("holo", Vector3(62.5, 1.75, 0), Vector3(0.62, 0.62, 0.62), Color.WHITE, 16, 12)
	g.torus("holo", Vector3(62.5, 1.75, 0), Basis(Vector3(1, 0, 0), 0.5), 0.95, 0.02, Color.WHITE, 24, 6)
	# wall racks east
	for k in 3:
		locker(Vector3(65.2, 0.0, -14.0 + float(k) * 2.2), PI * 0.5, 2, 0.8, 2.1, 0.7, COL_MACH)
		g.quad_uv("screen_bars", Vector3(64.83, 1.2, -14.6 + float(k) * 2.2), Vector3(64.83, 1.2, -13.4 + float(k) * 2.2),
			Vector3(64.83, 1.85, -13.4 + float(k) * 2.2), Vector3(64.83, 1.85, -14.6 + float(k) * 2.2), Color.WHITE)
	# big status wall screen south
	wall_screen("screen_bars", Vector3(62.0, 2.1, 23.6), Vector3(0, 0, -1), 3.4, 1.5)
	wall_screen("screen_radar", Vector3(58.0, 2.1, -23.6), Vector3(0, 0, 1), 2.6, 1.5)
	ceiling_pipes(r, 2, 0.5, 0.1)
	ceiling_lights(r, "strip_cyan", 2)

func _airlock(r: Dictionary) -> void:
	# control panels beside both doors
	for xx in [67.0, 73.0]:
		g.box("metal_dark", Vector3(xx, 1.5, 4.6), Vector3(0.7, 0.9, 0.14), COL_DARK)
		screen_panel("screen_amber", Vector3(xx, 1.25, 4.5), 0.0, 0.5, 0.34, 0.15)
	# manual pump handles + gauges
	for k in 3:
		var zz := -4.4
		g.cylinder("metal", Vector3(68.5 + float(k) * 1.2, 1.1, zz), Vector3(68.5 + float(k) * 1.2, 1.1, zz + 0.25), 0.04, COL_MACH, 6)
		g.torus("metal_warm", Vector3(68.5 + float(k) * 1.2, 1.1, zz + 0.3), Basis(Vector3.RIGHT, PI * 0.5), 0.16, 0.03, Color(0.6, 0.5, 0.3), 10, 6)
		g.cylinder("white_mat", Vector3(68.5 + float(k) * 1.2, 1.8, zz + 0.08), Vector3(68.5 + float(k) * 1.2, 1.8, zz + 0.12), 0.14, COL_WHITE, 10)
	# suit lockers
	locker(Vector3(70.0, 0.0, 5.2), PI, 3, 1.8, 2.2, 0.65, COL_LIGHT)
	# ceiling beacon + strips
	g.cylinder("strip_red", Vector3(70, 5.7, 0), Vector3(70, 5.9, 0), 0.16, Color.WHITE, 8)
	strip_along("strip_red", Vector3(66.4, 5.85, -4.5), Vector3(66.4, 5.85, 4.5), 0.1)
	strip_along("strip_red", Vector3(73.6, 5.85, -4.5), Vector3(73.6, 5.85, 4.5), 0.1)
	# heavy pipes around frame
	g.pipe("metal_dark", [Vector3(66.5, 4.8, -5.5), Vector3(73.5, 4.8, -5.5), Vector3(73.5, 4.8, 5.5), Vector3(66.5, 4.8, 5.5)], 0.12, COL_MACH, 8)

func _junction(r: Dictionary) -> void:
	# signage column
	g.box("metal_dark", Vector3(77.0, 1.3, 6.5), Vector3(0.5, 2.6, 0.5), COL_DARK)
	for k in 4:
		var a := PI * 0.5 * float(k)
		var pos := Vector3(77.0, 2.35, 6.5) + Basis(Vector3.UP, a) * Vector3(0, 0, 0.27)
		g.quad_uv("screen_bars", pos + Basis(Vector3.UP, a) * Vector3(-0.2, -0.25, 0.01), pos + Basis(Vector3.UP, a) * Vector3(0.2, -0.25, 0.01),
			pos + Basis(Vector3.UP, a) * Vector3(0.2, 0.25, 0.01), pos + Basis(Vector3.UP, a) * Vector3(-0.2, 0.25, 0.01), Color.WHITE)
	# bench + vending
	g.box("metal", Vector3(84.0, 0.45, 7.0), Vector3(2.4, 0.08, 0.55), COL_LIGHT)
	for s in [-1.0, 1.0]:
		g.box("metal_dark", Vector3(84.0 + s * 1.0, 0.22, 7.0), Vector3(0.1, 0.44, 0.5), COL_DARK)
	g.box("metal", Vector3(84.0, 0.98, -7.6), Vector3(1.1, 1.95, 0.85), Color(0.35, 0.3, 0.45))
	g.quad_uv("screen_bars", Vector3(83.5, 0.7, -7.16), Vector3(84.5, 0.7, -7.16), Vector3(84.5, 1.5, -7.16), Vector3(83.5, 1.5, -7.16), Color.WHITE)
	# wall map display
	wall_screen("screen_radar", Vector3(85.7, 2.1, -7.5), Vector3(-1, 0, 0), 2.2, 1.4)
	ceiling_lights(r, "strip_cyan", 1)
	# floor direction inlay
	g.box("strip_route", Vector3(81.0, 0.03, -4.0), Vector3(1.6, 0.02, 0.5), Color.WHITE)

func _shaft(r: Dictionary) -> void:
	var y0: float = r["y0"]; var y1: float = r["y1"]
	# vertical pipes expressing continuity between decks
	for corner in [Vector2(r["x0"] + 0.5, r["z1"] - 0.5), Vector2(r["x1"] - 0.5, r["z1"] - 0.5)]:
		g.cylinder("metal_dark", Vector3(corner.x, y0, corner.y), Vector3(corner.x, y1, corner.y), 0.1, COL_MACH, 8)
		g.cylinder("metal_dark", Vector3(corner.x + 0.28, y0, corner.y), Vector3(corner.x + 0.28, y1, corner.y), 0.07, COL_MACH, 8)
	# corner light strips
	strip_along("strip_cyan", Vector3(r["x0"] + 0.2, y1 - 0.25, r["z0"] + 0.2), Vector3(r["x1"] - 0.2, y1 - 0.25, r["z0"] + 0.2), 0.08)
	g.box("strip_cyan", Vector3(r["x1"] - 0.2, y1 - 0.25, (r["z0"] + r["z1"]) * 0.5), Vector3(0.08, 0.06, r["z1"] - r["z0"] - 0.4), Color.WHITE)
	# small utility box
	g.box("metal_dark", Vector3(r["x0"] + 0.5, y0 + 0.5, r["z0"] + 0.5), Vector3(0.6, 1.0, 0.4), COL_DARK)

# --------------------------------------------------------------- cargo

func _cargo(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var z0: float = r["z0"]; var z1: float = r["z1"]
	var cx: float = (x0 + x1) * 0.5; var cz: float = (z0 + z1) * 0.5
	var cols := [Color(0.42, 0.4, 0.32), Color(0.34, 0.4, 0.45), Color(0.45, 0.38, 0.3), Color(0.3, 0.36, 0.34)]
	var v := variant_of(r)
	if r["name"] == "CARGO HOLD B":
		v = 0
	if v == 0:
		var zz := z0 + 5.0
		while zz < z1 - 4.0:
			var xx := x0 + 3.5
			while xx < x1 - 4.0:
				container(Vector3(xx, y0, zz), 0.0, cols[int(rng.randf() * 4) % 4])
				if rng.randf() > 0.62:
					container(Vector3(xx, y0 + 2.62, zz), 0.0, cols[int(rng.randf() * 4) % 4])
				xx += 6.6
			zz += 6.2
	elif v == 1:
		shelf_rack(Vector3(cx, y0, z0 + 1.2), 0.0, (x1 - x0) - 4.0, 3, 2.6, COL_MACH, 0.7)
		shelf_rack(Vector3(cx, y0, z1 - 1.2), 0.0, (x1 - x0) - 4.0, 3, 2.6, COL_MACH, 0.6)
		for k in 2:
			container(Vector3(cx - 3.2 + float(k) * 6.4, y0, cz), PI * 0.5, cols[k % 4])
			if rng.randf() > 0.4:
				container(Vector3(cx - 3.2 + float(k) * 6.4, y0 + 2.62, cz), PI * 0.5, cols[(k + 1) % 4])
		var i := 0
		while i < 14:
			var px := lerpf(x0 + 2.0, x1 - 2.0, rng.randf())
			var pz := lerpf(z0 + 4.0, z1 - 4.0, rng.randf())
			if absf(px - cx) < 5.5 and absf(pz - cz) < 4.5:
				i += 1
				continue
			var sv := Vector3(0.8 + rng.randf() * 0.6, 0.6 + rng.randf() * 0.5, 0.8 + rng.randf() * 0.5)
			crate(Vector3(px, y0, pz), sv, cols[int(rng.randf() * 4) % 4].darkened(0.1), rng.randf() * 0.8)
			if rng.randf() > 0.6:
				crate(Vector3(px, y0 + sv.y, pz), sv * 0.8, cols[int(rng.randf() * 4) % 4], rng.randf())
			i += 1
	else:
		for k in 6:
			var px := x0 + 5.0 + float(k % 3) * 7.0
			var pz := z0 + 7.0 + float(k / 3) * 10.0
			if pz > z1 - 3.0:
				continue
			tank_v(Vector3(px, y0, pz), 1.6, 4.2, Color(0.4, 0.42, 0.45), "strip_hazardmark")
		g.box("metal_dark", Vector3(cx + 6.0, y0 + 0.9, cz), Vector3(1.0, 0.14, (z1 - z0) * 0.6), COL_DARK)
		for k in 8:
			var rz2 := cz - (z1 - z0) * 0.3 + float(k) * (z1 - z0) * 0.6 / 7.0
			g.cylinder("metal", Vector3(cx + 5.5, y0 + 0.98, rz2), Vector3(cx + 6.5, y0 + 0.98, rz2), 0.07, COL_LIGHT, 8)
		for k in 5:
			var pz3 := z0 + 4.0 + float(k) * 4.5
			if pz3 > z1 - 2.0:
				continue
			g.box("metal_warm", Vector3(x1 - 4.0, y0 + 0.08, pz3), Vector3(1.2, 0.16, 1.0), COL_WARM)
			crate(Vector3(x1 - 4.0, y0 + 0.16, pz3), Vector3(0.9, 0.7, 0.8), cols[k % 4], 0.0)
	# shared tail: forklift + hanging lamps + guide line
	_forklift(Vector3(cx + 4.0, y0, cz - 3.0), PI * 0.5)
	var lx := x0 + 4.0
	while lx < x1 - 3.0:
		g.cylinder("metal_dark", Vector3(lx, r["y1"], cz), Vector3(lx, r["y1"] - 0.8, cz), 0.03, COL_DARK, 6)
		g.cylinder("metal_dark", Vector3(lx, r["y1"] - 0.95, cz), Vector3(lx, r["y1"] - 0.8, cz), 0.3, COL_MACH, 10, false, 0.12)
		g.cylinder("strip_warm", Vector3(lx, r["y1"] - 0.98, cz), Vector3(lx, r["y1"] - 0.94, cz), 0.22, Color.WHITE, 10)
		lx += 8.0
	g.quad_ds("strip_hazardmark", Vector3(x0 + 1.0, y0 + 0.05, cz - 0.12), Vector3(x1 - 1.0, y0 + 0.05, cz - 0.12),
		Vector3(x1 - 1.0, y0 + 0.05, cz + 0.12), Vector3(x0 + 1.0, y0 + 0.05, cz + 0.12), Color.WHITE)

func _forklift(pos: Vector3, rot_y: float) -> void:
	var b := Basis(Vector3.UP, rot_y)
	g.box("metal", pos + b * Vector3(0, 0.55, 0), Vector3(1.7, 0.5, 1.1), COL_YELLOW, rot_y)
	g.box("metal_dark", pos + b * Vector3(-0.75, 0.5, 0), Vector3(0.5, 0.7, 1.0), COL_DARK, rot_y)
	# cab frame + roof
	for s in [-1.0, 1.0]:
		g.strut("metal_dark", pos + b * Vector3(-0.2, 0.8, s * 0.5), pos + b * Vector3(-0.2, 2.1, s * 0.5), 0.06, 0.06, COL_DARK)
	g.box("metal_dark", pos + b * Vector3(-0.3, 2.15, 0), Vector3(1.0, 0.08, 1.2), COL_DARK, rot_y)
	g.box("strip_amber", pos + b * Vector3(-0.3, 2.25, 0), Vector3(0.2, 0.1, 0.2), Color.WHITE, rot_y)
	# mast + forks
	g.strut("metal", pos + b * Vector3(0.95, 0.3, -0.4), pos + b * Vector3(0.95, 2.6, -0.4), 0.1, 0.14, COL_YELLOW.darkened(0.1))
	g.strut("metal", pos + b * Vector3(0.95, 0.3, 0.4), pos + b * Vector3(0.95, 2.6, 0.4), 0.1, 0.14, COL_YELLOW.darkened(0.1))
	g.box("metal_dark", pos + b * Vector3(1.0, 0.35, 0), Vector3(0.12, 0.5, 1.0), COL_DARK, rot_y)
	for s in [-1.0, 1.0]:
		g.box("metal", pos + b * Vector3(1.45, 0.1, s * 0.3), Vector3(0.9, 0.06, 0.12), COL_LIGHT, rot_y)
	# wheels
	for wx in [-0.6, 0.6]:
		for wz in [-0.5, 0.5]:
			var wp := pos + b * Vector3(wx, 0.28, wz)
			g.cylinder("rubber", wp + b * Vector3(0, 0, -0.08), wp + b * Vector3(0, 0, 0.08), 0.28, Color(0.1, 0.1, 0.11), 10)
	# seat
	chair(pos + b * Vector3(-0.25, 0.5, 0), rot_y, COL_DARK)

# --------------------------------------------------------------- utility / machinery

func _utility(r: Dictionary) -> void:
	var name: String = r["name"]
	var y0: float = r["y0"]
	match name:
		"MACHINE WORKSHOP":
			_workshop(r)
			return
		"COOLANT PLANT", "COOLANT PUMPS":
			_coolant(r)
			return
		"LIFE SUPPORT":
			_life(r)
			return
		"WASTE RECYCLING":
			_waste(r)
			return
		"TURBINE AUX", "DRIVE MACHINERY UPPER", "TURBINE GALLERY":
			_machinery_hall(r)
			return
		"HVAC BAY":
			for k in 3:
				machine_box(Vector3(84.0 + float(k) * 9.0, y0, -26.0), 0.0, Vector3(3.4, 2.4, 2.4), COL_MACH, 2)
			duct_run(Vector3(80.0, r["y1"] - 0.9, -20.0), Vector3(112.0, r["y1"] - 0.9, -20.0), 1.0, 0.8)
			duct_run(Vector3(96.0, r["y1"] - 0.9, -33.0), Vector3(96.0, r["y1"] - 0.9, -20.4), 0.8, 0.7)
			ceiling_lights(r, "strip_warm", 1)
			return
		"HYDRAULICS":
			for k in 3:
				pump(Vector3(90.0 + float(k) * 4.0, y0, -6.0), 0.0, 1.1)
			for k in 4:
				var px := 90.0 + float(k) * 3.0
				g.cylinder("metal", Vector3(px, y0, -8.5), Vector3(px, y0 + 2.0, -8.5), 0.38, Color(0.5, 0.42, 0.3), 10)
				g.torus("metal_dark", Vector3(px, y0 + 2.0, -8.5), Basis(), 0.4, 0.06, COL_DARK, 10, 6)
			pipe_run(Vector3(88.0, y0 + 2.4, -7.0), Vector3(112.0, y0 + 2.4, -7.0), 0.12, COL_MACH)
			ceiling_lights(r, "strip_warm", 1)
			return
		"SENSOR BAY":
			for k in 3:
				locker(Vector3(240.0 + float(k) * 1.6, y0, 18.0), PI, 2, 1.2, 2.1, 0.8, COL_MACH)
				g.quad_uv("screen_radar", Vector3(239.55 + float(k) * 1.6, 1.2, 17.58), Vector3(240.45 + float(k) * 1.6, 1.2, 17.58),
					Vector3(240.45 + float(k) * 1.6, 1.9, 17.58), Vector3(239.55 + float(k) * 1.6, 1.9, 17.58), Color.WHITE)
			g.cylinder("metal_dark", Vector3(242, y0, 8), Vector3(242, y0 + 0.9, 8), 0.5, COL_DARK, 10)
			g.torus("metal", Vector3(242, y0 + 1.1, 8), Basis(Vector3(1, 0, 0), 0.6), 0.45, 0.04, COL_LIGHT, 14, 6)
			ceiling_lights(r, "strip_cyan", 1)
			return
		"CABLE CELLAR":
			for k in 5:
				g.cylinder("rubber", Vector3(74.3, y0 + 0.4 + float(k) * 0.3, -32.0), Vector3(74.3, y0 + 0.4 + float(k) * 0.3, -18.0), 0.11, Color(0.12, 0.12, 0.13), 6)
			g.box("metal_dark", Vector3(76.0, y0 + 0.7, -25.0), Vector3(0.8, 1.2, 0.5), COL_DARK)
			g.box("strip_amber", Vector3(76.0, y0 + 2.9, -25.0), Vector3(0.5, 0.05, 0.1), Color.WHITE)
			return
	# generic machinery filler — three arrangement variants
	var area: float = (r["x1"] - r["x0"]) * (r["z1"] - r["z0"])
	var n := clampi(int(area / 55.0), 2, 9)
	var v := variant_of(r)
	var cx: float = (r["x0"] + r["x1"]) * 0.5
	var cz: float = (r["z0"] + r["z1"]) * 0.5
	if v == 1:
		# pump row + overhead manifold
		for k in n:
			var px := lerpf(r["x0"] + 2.5, r["x1"] - 2.5, float(k) / maxf(float(n - 1), 1.0))
			pump(Vector3(px, y0, cz + (r["z1"] - r["z0"]) * 0.2), 0.0, 1.0 + rng.randf() * 0.4)
		pipe_run(Vector3(r["x0"] + 1.5, y0 + 3.2, cz + (r["z1"] - r["z0"]) * 0.2), Vector3(r["x1"] - 1.5, y0 + 3.2, cz + (r["z1"] - r["z0"]) * 0.2), 0.18, COL_MACH)
		for k in n:
			var px := lerpf(r["x0"] + 2.5, r["x1"] - 2.5, float(k) / maxf(float(n - 1), 1.0))
			g.cylinder("metal_dark", Vector3(px, y0 + 1.2, cz + (r["z1"] - r["z0"]) * 0.2), Vector3(px, y0 + 3.1, cz + (r["z1"] - r["z0"]) * 0.2), 0.08, COL_DARK, 6)
		cabinet(Vector3(r["x1"] - 1.2, y0, cz - (r["z1"] - r["z0"]) * 0.25), PI * 0.5, 1.4, 2.1, 0.6, COL_LIGHT)
	elif v == 2:
		# tank farm + step catwalk
		var nt := clampi(int(n / 2), 2, 4)
		for k in nt:
			tank_v(Vector3(lerpf(r["x0"] + 3.0, r["x1"] - 3.0, float(k) / maxf(float(nt - 1), 1.0)), y0, cz - (r["z1"] - r["z0"]) * 0.18), 1.1 + rng.randf() * 0.4, 2.8 + rng.randf(), Color(0.42, 0.44, 0.46))
		g.box("grate_std", Vector3(cx, y0 + 0.03, cz + (r["z1"] - r["z0"]) * 0.25), Vector3((r["x1"] - r["x0"]) * 0.7, 0.06, 1.4), Color.WHITE)
		for k in 4:
			var px := lerpf(r["x0"] + 3.0, r["x1"] - 3.0, float(k) / 3.0)
			g.cylinder("frame", Vector3(px, y0, cz + (r["z1"] - r["z0"]) * 0.25 - 0.6), Vector3(px, y0 + 0.0, cz + (r["z1"] - r["z0"]) * 0.25 - 0.6), 0.05, COL_MACH, 6)
		pipe_run(Vector3(r["x0"] + 1.5, y0 + 3.6, cz - (r["z1"] - r["z0"]) * 0.18), Vector3(r["x1"] - 1.5, y0 + 3.6, cz - (r["z1"] - r["z0"]) * 0.18), 0.14, COL_MACH)
		machine_box(Vector3(r["x1"] - 2.5, y0, cz + (r["z1"] - r["z0"]) * 0.3), 0.0, Vector3(1.6, 1.6, 1.2), COL_MACH, 2)
	else:
		for k in n:
			var px := lerpf(r["x0"] + 2.0, r["x1"] - 2.0, rng.randf())
			var pz := lerpf(r["z0"] + 2.0, r["z1"] - 2.0, rng.randf())
			var t := rng.randf()
			if t < 0.3:
				pump(Vector3(px, y0, pz), rng.randf() * TAU, 0.9 + rng.randf() * 0.4)
			elif t < 0.55:
				tank_v(Vector3(px, y0, pz), 0.8 + rng.randf() * 0.5, 2.4 + rng.randf(), Color(0.42, 0.44, 0.46))
			elif t < 0.8:
				machine_box(Vector3(px, y0, pz), rng.randf() * 0.4 - 0.2, Vector3(1.6 + rng.randf(), 1.4 + rng.randf(), 1.2 + rng.randf() * 0.6), COL_MACH, 1)
			else:
				cabinet(Vector3(px, y0, pz), rng.randf() * TAU, 1.2, 2.0, 0.6, COL_LIGHT)
	if area > 300.0:
		ceiling_pipes(r, 2, 0.6, 0.12)
	ceiling_lights(r, "strip_warm" if r["detail"] > 0 else "strip_amber", 1)

func _workshop(r: Dictionary) -> void:
	var y0: float = r["y0"]
	# workbench along south wall (z=-3 side is spine; use north wall z=-34)
	g.box("metal", Vector3(128.0, y0 + 0.85, -31.5), Vector3(14.0, 0.08, 1.4), COL_LIGHT)
	for k in 7:
		g.box("metal_dark", Vector3(121.5 + float(k) * 2.1, y0 + 0.42, -31.5), Vector3(0.12, 0.84, 1.2), COL_DARK)
	# vises + tools
	for k in 3:
		g.box("metal_dark", Vector3(123.0 + float(k) * 4.0, y0 + 1.02, -31.9), Vector3(0.35, 0.26, 0.3), COL_DARK)
	g.box("metal_dark", Vector3(128.0, y0 + 1.6, -33.4), Vector3(12.0, 1.4, 0.1), Color(0.3, 0.28, 0.25))
	for k in 10:
		g.cylinder("metal", Vector3(122.5 + float(k) * 1.1, y0 + 1.7, -33.3), Vector3(122.5 + float(k) * 1.1, y0 + 2.1, -33.3), 0.03, COL_LIGHT, 5)
	# lathe
	g.box("metal", Vector3(120.0, y0 + 0.6, -20.0), Vector3(2.6, 1.2, 1.0), Color(0.35, 0.42, 0.38))
	g.cylinder("metal_dark", Vector3(121.4, y0 + 1.35, -20.0), Vector3(122.3, y0 + 1.35, -20.0), 0.3, COL_DARK, 12)
	g.box("strip_green", Vector3(120.0, y0 + 1.25, -19.48), Vector3(0.6, 0.06, 0.02), Color.WHITE)
	# welding station
	g.box("metal_dark", Vector3(138.0, y0 + 0.8, -18.0), Vector3(1.8, 0.08, 1.2), COL_DARK)
	g.box("metal_dark", Vector3(138.0, y0 + 0.4, -18.0), Vector3(1.6, 0.8, 1.0), COL_MACH)
	screen_panel("screen_amber", Vector3(138.0, y0 + 1.3, -18.4), 0.0, 0.7, 0.5, 0.2)
	for k in 2:
		g.cylinder("metal", Vector3(139.4, y0, -17.0 + float(k) * 0.8), Vector3(139.4, y0 + 1.4, -17.0 + float(k) * 0.8), 0.16, [COL_GREEN.darkened(0.2), COL_RED.darkened(0.1)][k], 8)
	# material rack: horizontal bars
	for k in 4:
		g.cylinder("metal_dark", Vector3(116.5, y0 + 0.5 + float(k) * 0.45, -8.0), Vector3(116.5, y0 + 0.5 + float(k) * 0.45, -14.0), 0.05, COL_DARK, 6)
		for j in 5:
			g.cylinder("metal", Vector3(116.5, y0 + 0.5 + float(k) * 0.45, -8.4 - float(j) * 1.1), Vector3(116.5, y0 + 0.5 + float(k) * 0.45, -8.4 - float(j) * 1.1) + Vector3(0, 0, 0), 0.001, COL_LIGHT, 4)
			g.cylinder("metal", Vector3(116.2, y0 + 0.5 + float(k) * 0.45, -8.4 - float(j) * 1.1), Vector3(116.8, y0 + 0.5 + float(k) * 0.45, -8.4 - float(j) * 1.1), 0.045, Color(0.5, 0.5, 0.53), 6)
	# parts bins
	shelf_rack(Vector3(130.0, y0, -6.0), PI, 5.0, 3, 1.8, COL_MACH, 0.7)
	ceiling_pipes(r, 2, 0.5, 0.1)
	ceiling_lights(r, "strip_white", 2)

func _coolant(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var big: bool = r["name"] == "COOLANT PLANT"
	if big:
		# heat exchanger + pump row
		g.box("metal", Vector3(60.0, y0 + 1.4, 30.0), Vector3(6.0, 2.6, 1.8), COL_CYAN.darkened(0.15))
		for i in 8:
			g.box("metal_dark", Vector3(57.4 + float(i) * 0.72, y0 + 1.4, 30.95), Vector3(0.12, 2.3, 0.1), COL_DARK)
		for k in 3:
			pump(Vector3(58.0 + float(k) * 2.6, y0, 35.5), PI, 1.2)
		pipe_run(Vector3(57.0, y0 + 3.2, 30.0), Vector3(65.5, y0 + 3.2, 30.0), 0.22, COL_CYAN.darkened(0.3))
		g.pipe("metal_dark", [Vector3(60.0, y0 + 2.8, 30.0), Vector3(60.0, y0 + 4.6, 30.0), Vector3(56.5, y0 + 4.6, 26.0), Vector3(56.5, y0 + 4.6, 24.5)], 0.2, COL_MACH, 8)
		wall_screen("screen_green", Vector3(63.5, 2.0, 24.4), Vector3(0, 0, 1), 1.6, 1.0)
	else:
		for k in 3:
			pump(Vector3(68.0 + float(k) * 2.0, y0, 32.0), 0.0, 1.0)
		tank_v(Vector3(71.5, y0, 37.0), 1.0, 2.8, COL_CYAN.darkened(0.2))
		pipe_run(Vector3(67.0, y0 + 2.6, 35.0), Vector3(73.5, y0 + 2.6, 35.0), 0.14, COL_MACH)
	ceiling_lights(r, "strip_cyan", 1)

func _life(r: Dictionary) -> void:
	var y0: float = r["y0"]
	# scrubber columns
	for k in 4:
		var px := 172.0 + float(k % 2) * 8.0
		var pz := 10.0 + float(k / 2) * 12.0
		g.cylinder("metal", Vector3(px, y0, pz), Vector3(px, y0 + 2.9, pz), 1.15, Color(0.42, 0.46, 0.44), 16)
		g.torus("metal_dark", Vector3(px, y0 + 2.9, pz), Basis(), 1.2, 0.12, COL_DARK, 16, 6)
		g.torus("strip_green", Vector3(px, y0 + 1.6, pz), Basis(), 1.18, 0.05, Color.WHITE, 16, 6)
		for j in 6:
			var a := TAU * float(j) / 6.0
			g.strut("metal_dark", Vector3(px + cos(a) * 0.9, y0 + 3.05, pz + sin(a) * 0.9), Vector3(px + cos(a) * 0.4, y0 + 3.35, pz + sin(a) * 0.4), 0.05, 0.05, COL_DARK)
	# algae tanks (glass with green glow)
	for k in 3:
		var px := 190.0
		var pz := 8.0 + float(k) * 6.0
		g.cylinder("glass", Vector3(px, y0 + 0.2, pz), Vector3(px, y0 + 2.4, pz), 0.75, Color.WHITE, 14, false)
		g.cylinder("strip_green", Vector3(px, y0 + 0.3, pz), Vector3(px, y0 + 2.3, pz), 0.16, Color.WHITE, 8)
		g.cylinder("metal_dark", Vector3(px, y0, pz), Vector3(px, y0 + 0.25, pz), 0.85, COL_DARK, 14)
		g.cylinder("metal_dark", Vector3(px, y0 + 2.35, pz), Vector3(px, y0 + 2.6, pz), 0.85, COL_DARK, 14)
	# consoles + pipes
	console(Vector3(172.0, y0, 30.0), PI, "screen_green", 2.4)
	pipe_run(Vector3(170.0, r["y1"] - 0.7, 6.0), Vector3(170.0, r["y1"] - 0.7, 34.0), 0.16, COL_CYAN.darkened(0.3))
	pipe_run(Vector3(196.0, r["y1"] - 0.9, 6.0), Vector3(196.0, r["y1"] - 0.9, 34.0), 0.13, COL_MACH)
	ceiling_lights(r, "strip_green", 2)

func _waste(r: Dictionary) -> void:
	var y0: float = r["y0"]
	g.box("metal", Vector3(186.0, y0 + 1.1, -22.0), Vector3(4.0, 2.2, 3.0), COL_MACH)
	g.cylinder("metal_dark", Vector3(186.0, y0 + 2.6, -22.0), Vector3(186.0, y0 + 3.4, -22.0), 0.6, COL_DARK, 12)
	g.box("strip_amber", Vector3(186.0, y0 + 1.6, -20.45), Vector3(1.2, 0.08, 0.03), Color.WHITE)
	# conveyor
	g.box("metal_dark", Vector3(192.0, y0 + 0.8, -14.0), Vector3(8.0, 0.16, 1.0), COL_DARK)
	for k in 8:
		g.cylinder("metal", Vector3(188.4 + float(k) * 1.0, y0 + 0.92, -14.0), Vector3(188.4 + float(k) * 1.0, y0 + 0.92, -14.0) + Vector3(0, 0, 0), 0.09, COL_LIGHT, 8)
		g.cylinder("metal", Vector3(188.4 + float(k) * 1.0, y0 + 0.92, -14.5), Vector3(188.4 + float(k) * 1.0, y0 + 0.92, -13.5), 0.09, COL_LIGHT, 8)
	for k in 5:
		barrel(Vector3(181.0 + float(k % 3) * 0.9, y0, -26.0 + float(k / 3) * 1.0), [COL_MACH, COL_GREEN.darkened(0.1), COL_YELLOW.darkened(0.2)][k % 3])
	ceiling_lights(r, "strip_warm", 1)

func _machinery_hall(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var z0: float = r["z0"]; var z1: float = r["z1"]
	# rows of big machines + central grating walkway
	g.box("grate_std", Vector3((x0 + x1) * 0.5, y0 + 0.03, (z0 + z1) * 0.5), Vector3(minf(x1 - x0 - 4.0, 44.0), 0.06, 3.0), Color.WHITE)
	var kk := 0
	var xx := x0 + 6.0
	while xx < x1 - 5.0:
		for zs in [-1.0, 1.0]:
			var pz: float = (z0 + z1) * 0.5 + zs * 12.0
			if kk % 3 == 0:
				g.cylinder("metal", Vector3(xx, y0, pz), Vector3(xx, y0 + 3.2, pz), 1.5, Color(0.4, 0.41, 0.45), 14)
				g.torus("metal_dark", Vector3(xx, y0 + 3.2, pz), Basis(), 1.55, 0.14, COL_DARK, 14, 6)
				g.torus("strip_amber", Vector3(xx, y0 + 1.8, pz), Basis(), 1.54, 0.05, Color.WHITE, 14, 6)
			else:
				machine_box(Vector3(xx, y0, pz), 0.0, Vector3(4.0, 2.6, 3.0), COL_MACH, 2)
		xx += 9.0
		kk += 1
	# wall duct runs
	duct_run(Vector3(x0 + 2.0, r["y1"] - 1.0, z0 + 1.5), Vector3(x1 - 2.0, r["y1"] - 1.0, z0 + 1.5), 1.1, 0.9)
	duct_run(Vector3(x0 + 2.0, r["y1"] - 1.0, z1 - 1.5), Vector3(x1 - 2.0, r["y1"] - 1.0, z1 - 1.5), 1.1, 0.9)
	ceiling_lights(r, "strip_amber", 2)

# --------------------------------------------------------------- living

func _mess(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var wardroom: bool = r["name"] == "WARDROOM"
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var z0: float = r["z0"]; var z1: float = r["z1"]
	var cx: float = (x0 + x1) * 0.5; var cz: float = (z0 + z1) * 0.5
	var v := variant_of(r) if not wardroom else 0
	# serving counter along west wall (all variants)
	var cwx := x0 + 2.0
	g.box("metal", Vector3(cwx, y0 + 0.5, cz), Vector3(1.3, 1.0, (z1 - z0) * 0.55), COL_LIGHT)
	g.box("metal_dark", Vector3(cwx, y0 + 1.03, cz), Vector3(1.4, 0.06, (z1 - z0) * 0.56), Color(0.3, 0.31, 0.33))
	g.box("glass", Vector3(cwx + 0.55, y0 + 1.5, cz), Vector3(0.06, 0.8, (z1 - z0) * 0.5), Color(0.8, 0.9, 1.0))
	for k in 3:
		g.box("metal_warm", Vector3(cwx - 0.1, y0 + 1.12, cz - 3.0 + float(k) * 3.0), Vector3(0.8, 0.14, 1.1), COL_MACH)
		g.box("strip_warm", Vector3(cwx - 0.1, y0 + 1.22, cz - 3.0 + float(k) * 3.0), Vector3(0.7, 0.03, 0.9), Color.WHITE)
	g.box("metal_dark", Vector3(cwx, y0 + 1.35, cz - (z1 - z0) * 0.2), Vector3(0.9, 0.6, 0.7), COL_DARK)
	if v == 0:
		for k in 6:
			var tx := x0 + 6.0 + float(k % 3) * ((x1 - x0) - 10.0) * 0.5
			var tz := z0 + 5.0 + float(k / 3) * ((z1 - z0) - 10.0)
			table_round(Vector3(tx, y0, tz), 0.85, COL_LIGHT)
			for j in 4:
				var a := TAU * float(j) / 4.0 + 0.4
				stool(Vector3(tx + cos(a) * 1.35, y0, tz + sin(a) * 1.35), COL_FAB)
	elif v == 1:
		for k in 2:
			var tz := z0 + 6.0 + float(k) * ((z1 - z0) - 12.0)
			g.box("metal", Vector3(cx + 2.0, y0 + 0.74, tz), Vector3((x1 - x0) * 0.5, 0.06, 1.3), COL_LIGHT)
			for j in 4:
				g.box("metal_dark", Vector3(cx + 2.0 - (x1 - x0) * 0.2 + float(j) * (x1 - x0) * 0.13, y0 + 0.36, tz), Vector3(0.1, 0.72, 1.1), COL_DARK)
			for j in 6:
				for s2 in [-1.0, 1.0]:
					g.box("fabric", Vector3(cx + 2.0 - (x1 - x0) * 0.22 + float(j) * (x1 - x0) * 0.09, y0 + 0.45, tz + s2 * 1.05), Vector3(0.5, 0.08, 0.4), COL_FAB2)
					g.box("metal_dark", Vector3(cx + 2.0 - (x1 - x0) * 0.22 + float(j) * (x1 - x0) * 0.09, y0 + 0.2, tz + s2 * 1.05), Vector3(0.4, 0.4, 0.3), COL_DARK)
	else:
		for k in 4:
			var tz := z0 + 4.0 + float(k) * ((z1 - z0) - 8.0) / 3.0
			g.box("fabric", Vector3(x1 - 1.6, y0 + 0.45, tz), Vector3(1.0, 0.5, 2.2), Color(0.42, 0.3, 0.24))
			g.box("fabric", Vector3(x1 - 1.15, y0 + 0.85, tz), Vector3(0.16, 0.9, 2.2), Color(0.42, 0.3, 0.24))
			g.box("metal", Vector3(x1 - 2.7, y0 + 0.72, tz), Vector3(0.9, 0.05, 1.8), COL_LIGHT)
		for k in 2:
			table_round(Vector3(cx, y0, z0 + 6.0 + float(k) * ((z1 - z0) - 12.0)), 0.9, COL_LIGHT)
			for j in 4:
				var a := TAU * float(j) / 4.0
				stool(Vector3(cx + cos(a) * 1.4, y0, z0 + 6.0 + float(k) * ((z1 - z0) - 12.0) + sin(a) * 1.4), COL_FAB)
	# shared: menu screens, plants, recycler, vending
	wall_screen("screen_amber", Vector3(cx, y0 + 2.4, z0 + 0.4), Vector3(0, 0, 1), 2.0, 1.1)
	plant(Vector3(x1 - 1.5, y0, z1 - 1.5), 1.3)
	plant(Vector3(cwx + 1.0, y0, z0 + 1.0), 1.1)
	g.box("metal_dark", Vector3(x1 - 1.2, y0 + 0.6, z0 + 3.0), Vector3(0.9, 1.2, 0.7), COL_DARK)
	g.box("strip_green", Vector3(x1 - 1.2, y0 + 1.25, z0 + 3.0), Vector3(0.4, 0.04, 0.4), Color.WHITE)
	if not wardroom:
		for k in 2:
			g.box("metal", Vector3(x1 - 0.8, y0, z0 + 6.0 + float(k) * 2.2), Vector3(1.05, 1.95, 0.9), [Color(0.3, 0.36, 0.5), Color(0.4, 0.3, 0.34)][k])
			g.quad_uv("screen_bars", Vector3(x1 - 1.36, y0 + 0.9, z0 + 5.6 + float(k) * 2.2), Vector3(x1 - 1.36, y0 + 0.9, z0 + 6.4 + float(k) * 2.2),
				Vector3(x1 - 1.36, y0 + 1.6, z0 + 6.4 + float(k) * 2.2), Vector3(x1 - 1.36, y0 + 1.6, z0 + 5.6 + float(k) * 2.2), Color.WHITE)
	ceiling_lights(r, "strip_warm", 2)

func _medical(r: Dictionary) -> void:
	var y0: float = r["y0"]
	# 4 beds in two pairs
	for k in 4:
		var bx := 133.0 + float(k % 2) * 12.0
		var bz := 8.0 + float(k / 2) * 13.0
		var rot := 0.0 if k % 2 == 0 else PI
		g.box("white_mat", Vector3(bx, y0 + 0.42, bz), Vector3(2.1, 0.16, 0.95), COL_WHITE)
		g.box("metal", Vector3(bx, y0 + 0.3, bz), Vector3(1.9, 0.14, 0.8), COL_LIGHT)
		for s in [-1.0, 1.0]:
			g.box("metal_dark", Vector3(bx + s * 0.8, y0 + 0.16, bz), Vector3(0.1, 0.32, 0.7), COL_DARK)
		g.box("fabric", Vector3(bx - 0.55, y0 + 0.54, bz), Vector3(0.9, 0.08, 0.85), Color(0.75, 0.8, 0.85))
		g.box("white_mat", Vector3(bx + 0.8, y0 + 0.56, bz), Vector3(0.4, 0.1, 0.5), COL_WHITE)
		g.box("fabric", Vector3(bx + 0.1, y0 + 0.53, bz), Vector3(1.1, 0.06, 0.9), Color(0.5, 0.7, 0.75))
		# monitor arm + vitals screen
		g.strut("metal_dark", Vector3(bx + 1.15, y0, bz + 0.5), Vector3(bx + 1.15, y0 + 1.5, bz + 0.5), 0.06, 0.06, COL_DARK)
		g.strut("metal_dark", Vector3(bx + 1.15, y0 + 1.5, bz + 0.5), Vector3(bx + 0.75, y0 + 1.5, bz + 0.3), 0.05, 0.05, COL_DARK)
		screen_panel("screen_med", Vector3(bx + 0.5, y0 + 1.28, bz + 0.28), -0.6, 0.55, 0.4, 0.0)
		# ceiling curtain rail + curtain
		g.cylinder("metal_dark", Vector3(bx - 1.4, r["y1"] - 0.35, bz - 0.9), Vector3(bx + 1.4, r["y1"] - 0.35, bz - 0.9), 0.03, COL_DARK, 6)
		g.box("plastic", Vector3(bx, y0 + 1.6, bz - 0.9), Vector3(2.6, 2.1, 0.03), Color(0.72, 0.78, 0.8, 0.6))
	# surgical area east
	g.box("white_mat", Vector3(154.0, y0 + 0.75, 16.0), Vector3(2.2, 0.12, 1.0), COL_WHITE)
	g.box("metal", Vector3(154.0, y0 + 0.35, 16.0), Vector3(1.0, 0.7, 0.5), COL_LIGHT)
	g.torus("metal_dark", Vector3(154.0, y0 + 0.02, 16.0), Basis(), 0.55, 0.05, COL_DARK, 12, 6)
	g.strut("metal_dark", Vector3(156.0, y0, 16.0), Vector3(156.0, r["y1"] - 1.2, 16.0), 0.1, 0.1, COL_DARK)
	g.strut("metal_dark", Vector3(156.0, r["y1"] - 1.2, 16.0), Vector3(154.3, r["y1"] - 1.6, 16.0), 0.08, 0.08, COL_DARK)
	g.cylinder("white_mat", Vector3(154.3, r["y1"] - 1.75, 16.0), Vector3(154.3, r["y1"] - 1.62, 16.0), 0.5, COL_WHITE, 14)
	g.cylinder("strip_white", Vector3(154.3, r["y1"] - 1.79, 16.0), Vector3(154.3, r["y1"] - 1.76, 16.0), 0.44, Color.WHITE, 14)
	# supply cabinets + fridge west
	for k in 4:
		cabinet(Vector3(129.6, y0, 7.0 + float(k) * 4.5), PI * 0.5, 2.0, 2.1, 0.6, COL_WHITE.darkened(0.05))
	g.box("metal", Vector3(158.5, y0 + 1.0, 8.0), Vector3(1.4, 2.0, 1.0), COL_LIGHT)
	screen_panel("screen_bars", Vector3(158.5, y0 + 1.5, 7.45), 0.0, 0.6, 0.4, 0.1)
	# IV stands
	for k in 2:
		var px := 145.0 + float(k) * 3.0
		g.cylinder("metal_dark", Vector3(px, y0, 26.0), Vector3(px, y0 + 1.8, 26.0), 0.03, COL_DARK, 6)
		g.box("plastic", Vector3(px + 0.12, y0 + 1.6, 26.0), Vector3(0.12, 0.26, 0.08), Color(0.85, 0.9, 0.95))
		g.torus("metal_dark", Vector3(px, y0 + 0.04, 26.0), Basis(), 0.24, 0.03, COL_DARK, 10, 6)
	wall_screen("screen_med", Vector3(144.0, y0 + 2.2, 3.4), Vector3(0, 0, 1), 2.2, 1.2)
	ceiling_lights(r, "strip_white", 2)

func _hydro(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var rows: Array = [8.0, 12.5, 17.0, 21.5, 26.0, 30.5]
	for rz in rows:
		if rz > r["z1"] - 2.0:
			continue
		var len := (x1 - x0) - 5.0
		var cx := (x0 + x1) * 0.5 - 1.0
		# uprights
		var nseg := int(len / 2.0)
		for i in nseg + 1:
			var px := cx - len * 0.5 + float(i) * len / float(nseg)
			for s in [-1.0, 1.0]:
				g.strut("metal", Vector3(px, y0, rz + s * 0.62), Vector3(px, y0 + 2.5, rz + s * 0.62), 0.07, 0.07, COL_LIGHT)
		# tiers
		for t in 4:
			var ty := y0 + 0.42 + float(t) * 0.62
			g.box("metal_dark", Vector3(cx, ty, rz), Vector3(len, 0.07, 1.3), COL_MACH)
			g.box("plastic", Vector3(cx, ty + 0.13, rz), Vector3(len - 0.1, 0.2, 1.15), Color(0.28, 0.3, 0.3))
			strip_along("strip_magenta", Vector3(cx - len * 0.5 + 0.3, ty + 0.6, rz), Vector3(cx + len * 0.5 - 0.3, ty + 0.6, rz), 0.1)
			# plants
			var i := 0
			while i < nseg * 2:
				if rng.randf() < 0.75 and t < 3 or (t == 3 and rng.randf() < 0.4):
					var px := cx - len * 0.5 + (float(i) + 0.5) * len / float(nseg * 2)
					var gc := Color(0.22 + rng.randf() * 0.18, 0.45 + rng.randf() * 0.25, 0.18)
					g.box("rubber", Vector3(px, ty + 0.32, rz + (rng.randf() - 0.5) * 0.5), Vector3(0.55, 0.24 + rng.randf() * 0.14, 0.85), gc)
					if rng.randf() < 0.3:
						g.sphere("rubber", Vector3(px + 0.2, ty + 0.5, rz), Vector3(0.16, 0.13, 0.16), gc.lightened(0.1), 6, 4)
				i += 1
	# aisle grating
	for rz in rows:
		if rz > r["z1"] - 4.0:
			continue
		g.box("grate_std", Vector3((x0 + x1) * 0.5 - 1.0, y0 + 0.025, rz + 2.25), Vector3((x1 - x0) - 5.0, 0.05, 1.1), Color.WHITE)
	# nutrient tanks + console east
	tank_v(Vector3(x1 - 2.5, y0, 8.0), 0.95, 2.3, Color(0.4, 0.45, 0.42), "strip_green")
	tank_v(Vector3(x1 - 2.5, y0, 12.0), 0.95, 2.3, Color(0.4, 0.45, 0.42), "strip_green")
	console(Vector3(x1 - 2.5, y0, 17.0), -PI * 0.5, "screen_green", 1.8)
	pipe_run(Vector3(x0 + 2.0, r["y1"] - 0.55, 6.0), Vector3(x0 + 2.0, r["y1"] - 0.55, r["z1"] - 2.0), 0.1, COL_CYAN.darkened(0.25))
	ceiling_lights(r, "strip_white", 2)

func _quarters(r: Dictionary) -> void:
	var y0: float = r["y0"]
	if r["name"] == "READY ROOM":
		desk(Vector3(252.0, y0, 17.0), PI * 0.5, "screen_bars", 1.8)
		chair(Vector3(253.2, y0, 17.0), -PI * 0.5, COL_FAB2)
		locker(Vector3(249.0, y0, 13.0), PI * 0.5, 3, 0.9, 2.1, 0.5, COL_WARM.darkened(0.15))
		g.box("fabric", Vector3(252.5, y0 + 0.02, 14.0), Vector3(2.6, 0.03, 1.8), Color(0.35, 0.25, 0.2))
		ceiling_lights(r, "strip_warm", 1)
		return
	if r["name"] == "CAPTAIN'S QUARTERS":
		bed_double(Vector3(204.0, y0, -25.0), PI * 0.5)
		desk(Vector3(198.5, y0, -12.0), PI * 0.5, "screen_bars", 1.7)
		chair(Vector3(199.8, y0, -12.0), -PI * 0.5, COL_FAB)
		g.box("fabric", Vector3(206.0, y0 + 0.3, -8.0), Vector3(2.4, 0.35, 0.9), Color(0.42, 0.3, 0.24))
		g.box("fabric", Vector3(206.0, y0 + 0.62, -8.4), Vector3(2.4, 0.55, 0.18), Color(0.42, 0.3, 0.24))
		locker(Vector3(208.0, y0, -26.0), 0.0, 4, 2.6, 2.2, 0.62, COL_WARM.darkened(0.2))
		g.box("fabric", Vector3(201.0, y0 + 0.015, -14.0), Vector3(3.0, 0.025, 2.2), Color(0.32, 0.22, 0.18))
		g.box("metal", Vector3(197.5, y0 + 1.7, -22.0), Vector3(0.12, 0.05, 2.4), COL_LIGHT)
		for k in 7:
			g.box("plastic", Vector3(197.5, y0 + 1.85, -23.0 + float(k) * 0.3), Vector3(0.1, 0.24, 0.08),
				[COL_RED, COL_BLUE, COL_GREEN, COL_YELLOW, COL_WARM][k % 5])
		g.quad_uv("strip_warm", Vector3(209.6, y0 + 1.6, -14.0), Vector3(209.6, y0 + 1.6, -12.2), Vector3(209.6, y0 + 2.7, -12.2), Vector3(209.6, y0 + 2.7, -14.0), Color(0.9, 0.75, 0.55))
		plant(Vector3(208.0, y0, -6.0), 1.2)
		ceiling_lights(r, "strip_warm", 1)
		return
	# crew quarters: three layout variants
	var v := variant_of(r)
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var z0: float = r["z0"]; var z1: float = r["z1"]
	var cx: float = (x0 + x1) * 0.5; var cz: float = (z0 + z1) * 0.5
	if v == 0:
		for k in 2:
			bunk(Vector3(x0 + 2.0 + float(k) * 5.0, y0, z0 + 4.0), 0.0, 2, Color(0.55, 0.6, 0.68))
			bunk(Vector3(x0 + 2.0 + float(k) * 5.0, y0, z1 - 4.0), 0.0, 2, Color(0.55, 0.6, 0.68))
		locker(Vector3(x1 - 1.0, y0, cz), PI * 0.5, 4, 1.0, 2.0, 0.55, COL_MACH)
		table_round(Vector3(cx, y0, cz), 0.6, COL_LIGHT)
	elif v == 1:
		bunk(Vector3(x0 + 2.0, y0, z0 + 3.0), 0.0, 2, Color(0.55, 0.6, 0.68))
		bunk(Vector3(x1 - 2.0, y0, z0 + 3.0), 0.0, 2, Color(0.5, 0.58, 0.62))
		bunk(Vector3(x0 + 2.0, y0, z1 - 3.0), 0.0, 2, Color(0.6, 0.55, 0.5))
		bunk(Vector3(x1 - 2.0, y0, z1 - 3.0), 0.0, 2, Color(0.55, 0.6, 0.68))
		table_round(Vector3(cx, y0, cz), 0.75, COL_LIGHT)
		stool(Vector3(cx - 1.1, y0, cz), COL_FAB2)
		stool(Vector3(cx + 1.1, y0, cz), COL_FAB2)
		locker(Vector3(cx, y0, z0 + 0.8), 0.0, 4, 1.0, 2.0, 0.55, COL_MACH)
	else:
		for k in 3:
			bunk(Vector3(x0 + 1.8, y0, z0 + 3.0 + float(k) * 4.5), PI * 0.5, 2, Color(0.55, 0.6, 0.68))
		# partitioned study nook
		g.box("panel_std", Vector3(cx + 1.0, y0 + 1.1, cz), Vector3(0.12, 2.2, (z1 - z0) * 0.6), Color(0.9, 0.9, 0.92))
		desk(Vector3(x1 - 2.2, y0, cz - 3.0), -PI * 0.5, "screen_bars", 1.4)
		desk(Vector3(x1 - 2.2, y0, cz + 3.0), -PI * 0.5, "screen_bars", 1.4)
		chair(Vector3(x1 - 3.2, y0, cz - 3.0), -PI * 0.5, COL_FAB2)
		chair(Vector3(x1 - 3.2, y0, cz + 3.0), -PI * 0.5, COL_FAB2)
		locker(Vector3(x1 - 0.8, y0, z1 - 1.0), PI * 0.5, 3, 0.9, 2.0, 0.5, COL_MACH)
	wall_screen("screen_bars", Vector3(cx, y0 + 2.0, z1 - 0.4), Vector3(0, 0, -1), 1.2, 0.7)
	ceiling_lights(r, "strip_warm", 1)

func _gym(r: Dictionary) -> void:
	var y0: float = r["y0"]
	if r["name"] == "RECREATION":
		g.box("fabric", Vector3(218.0, y0 + 0.35, -35.0), Vector3(2.6, 0.4, 1.0), Color(0.35, 0.3, 0.42))
		g.box("fabric", Vector3(218.0, y0 + 0.7, -35.4), Vector3(2.6, 0.6, 0.2), Color(0.35, 0.3, 0.42))
		g.box("metal", Vector3(218.0, y0 + 0.4, -32.5), Vector3(1.4, 0.06, 0.8), COL_LIGHT)
		g.sphere("holo", Vector3(218.0, y0 + 0.75, -32.5), Vector3(0.18, 0.18, 0.18), Color.WHITE, 10, 8)
		shelf_rack(Vector3(214.0, y0, -38.0), 0.0, 3.0, 2, 1.6, COL_MACH, 0.4)
		ceiling_lights(r, "strip_warm", 1)
		return
	# treadmills
	for k in 2:
		var px := 199.0 + float(k) * 2.4
		g.box_basis("metal_dark", Transform3D(Basis(Vector3(0, 0, 1), -0.28), Vector3(px, y0 + 0.35, -36.0)), Vector3(0.9, 0.12, 2.0), COL_DARK)
		g.strut("metal_dark", Vector3(px - 0.4, y0 + 0.3, -36.8), Vector3(px - 0.4, y0 + 1.35, -36.8), 0.06, 0.06, COL_DARK)
		g.strut("metal_dark", Vector3(px + 0.4, y0 + 0.3, -36.8), Vector3(px + 0.4, y0 + 1.35, -36.8), 0.06, 0.06, COL_DARK)
		g.strut("metal_dark", Vector3(px - 0.4, y0 + 1.35, -36.8), Vector3(px + 0.4, y0 + 1.35, -36.8), 0.05, 0.05, COL_DARK)
		screen_panel("screen_bars", Vector3(px, y0 + 1.15, -36.75), PI, 0.5, 0.35, 0.3)
	# weight rack
	g.box("metal_dark", Vector3(206.0, y0 + 0.7, -40.0), Vector3(2.4, 0.1, 0.8), COL_DARK)
	for s in [-1.0, 1.0]:
		g.box("metal_dark", Vector3(206.0 + s * 1.1, y0 + 0.35, -40.0), Vector3(0.12, 0.7, 0.7), COL_DARK)
	for k in 5:
		g.cylinder("metal_dark", Vector3(205.0 + float(k) * 0.5, y0 + 0.78, -40.0), Vector3(205.0 + float(k) * 0.5, y0 + 0.78, -40.0) + Vector3(0, 0.16, 0), 0.19, Color(0.2, 0.2, 0.22), 10)
	g.cylinder("metal", Vector3(204.6, y0 + 1.3, -40.0), Vector3(207.4, y0 + 1.3, -40.0), 0.035, COL_LIGHT, 8)
	# bench + punching bag + mat
	g.box("fabric", Vector3(200.0, y0 + 0.5, -31.0), Vector3(1.4, 0.12, 0.45), Color(0.25, 0.25, 0.3))
	g.box("metal_dark", Vector3(200.0, y0 + 0.25, -31.0), Vector3(1.0, 0.4, 0.1), COL_DARK)
	g.cylinder("metal_dark", Vector3(206.5, r["y1"], -30.0), Vector3(206.5, r["y1"] - 0.5, -30.0), 0.04, COL_DARK, 6)
	g.cylinder("rubber", Vector3(206.5, r["y1"] - 1.25, -30.0), Vector3(206.5, r["y1"] - 0.5, -30.0), 0.22, Color(0.4, 0.16, 0.12), 10)
	g.box("rubber", Vector3(202.0, y0 + 0.02, -20.0), Vector3(5.0, 0.04, 5.0), Color(0.18, 0.2, 0.24))
	# mirror wall
	g.quad("floor_gloss", Vector3(196.4, y0 + 0.3, -8.0), Vector3(196.4, y0 + 0.3, -26.0), Vector3(196.4, y0 + 2.6, -26.0), Vector3(196.4, y0 + 2.6, -8.0), Color(0.5, 0.55, 0.6), Vector3(1, 0, 0))
	ceiling_lights(r, "strip_white", 2)

func _lounge(r: Dictionary) -> void:
	var y0: float = r["y0"]
	# window-side bench along glass (north wall z=-44 side => z0=-44)
	g.box("metal_dark", Vector3(211.0, y0 + 0.28, -41.8), Vector3(18.0, 0.5, 1.3), COL_DARK)
	g.box("fabric", Vector3(211.0, y0 + 0.58, -41.8), Vector3(18.0, 0.14, 1.3), Color(0.4, 0.32, 0.28))
	g.box("fabric", Vector3(211.0, y0 + 0.85, -42.35), Vector3(18.0, 0.5, 0.2), Color(0.4, 0.32, 0.28))
	for k in 3:
		g.box("metal", Vector3(204.0 + float(k) * 6.0, y0 + 0.4, -39.8), Vector3(1.1, 0.06, 0.6), COL_LIGHT)
		g.box("metal_dark", Vector3(204.0 + float(k) * 6.0, y0 + 0.2, -39.8), Vector3(0.12, 0.4, 0.5), COL_DARK)
	# armchairs
	for k in 4:
		var px := 202.0 + float(k % 2) * 4.0
		var pz := -20.0 - float(k / 2) * 8.0
		g.box("fabric", Vector3(px, y0 + 0.3, pz), Vector3(0.9, 0.3, 0.9), Color(0.3, 0.36, 0.48))
		g.box("fabric", Vector3(px - 0.36, y0 + 0.62, pz), Vector3(0.18, 0.6, 0.9), Color(0.3, 0.36, 0.48))
		g.box("fabric", Vector3(px, y0 + 0.52, pz - 0.36), Vector3(0.9, 0.12, 0.18), Color(0.3, 0.36, 0.48))
		g.box("fabric", Vector3(px, y0 + 0.52, pz + 0.36), Vector3(0.9, 0.12, 0.18), Color(0.3, 0.36, 0.48))
	# bar corner (south-east)
	g.box("metal_dark", Vector3(221.0, y0 + 0.55, -8.0), Vector3(4.0, 1.1, 1.0), COL_DARK)
	g.box("metal", Vector3(221.0, y0 + 1.13, -8.0), Vector3(4.2, 0.06, 1.2), Color(0.55, 0.5, 0.4))
	g.box("strip_warm", Vector3(221.0, y0 + 0.25, -7.48), Vector3(3.8, 0.06, 0.03), Color.WHITE)
	for k in 8:
		g.cylinder("glass", Vector3(219.4 + float(k) * 0.45, y0 + 1.16, -8.0), Vector3(219.4 + float(k) * 0.45, y0 + 1.42, -8.0), 0.05, Color(0.8, 0.85, 0.9), 6)
	for k in 3:
		stool(Vector3(220.0 + float(k) * 1.2, y0, -6.8), COL_FAB)
	# plants + art
	plant(Vector3(198.5, y0, -6.0), 1.5)
	plant(Vector3(223.5, y0, -30.0), 1.4)
	g.quad_uv("strip_cyan", Vector3(210.0, y0 + 1.8, -3.35), Vector3(213.0, y0 + 1.8, -3.35), Vector3(213.0, y0 + 3.0, -3.35), Vector3(210.0, y0 + 3.0, -3.35), Color(0.5, 0.7, 1.0))
	# telescope
	g.strut("metal_dark", Vector3(216.0, y0, -38.0), Vector3(215.7, y0 + 1.2, -38.4), 0.05, 0.05, COL_DARK)
	g.strut("metal_dark", Vector3(216.0, y0, -38.0), Vector3(216.3, y0 + 1.2, -38.4), 0.05, 0.05, COL_DARK)
	g.strut("metal_dark", Vector3(216.0, y0, -38.0), Vector3(216.0, y0 + 1.2, -37.5), 0.05, 0.05, COL_DARK)
	g.cylinder("metal", Vector3(215.8, y0 + 1.5, -38.7), Vector3(216.3, y0 + 1.15, -37.6), 0.09, COL_LIGHT, 8)
	# cove lighting perimeter
	strip_along("strip_warm", Vector3(198.0, r["y1"] - 0.35, -42.0), Vector3(224.0, r["y1"] - 0.35, -42.0), 0.12)
	ceiling_lights(r, "strip_warm", 2)

# --------------------------------------------------------------- hangar

func _hangar(r: Dictionary) -> void:
	var y0: float = r["y0"]
	# landing circles
	for cc in [Vector3(160.0, y0 + 0.06, -24.0), Vector3(138.0, y0 + 0.06, -14.0)]:
		var rad: float = 8.0 if float(cc.x) > 150.0 else 5.0
		for i in 32:
			var a0 := TAU * float(i) / 32.0
			var a1 := TAU * float(i + 1) / 32.0
			var q0: Vector3 = cc + Vector3(cos(a0) * rad, 0, sin(a0) * rad)
			var q1: Vector3 = cc + Vector3(cos(a1) * rad, 0, sin(a1) * rad)
			var q2: Vector3 = cc + Vector3(cos(a1) * (rad + 0.5), 0, sin(a1) * (rad + 0.5))
			var q3: Vector3 = cc + Vector3(cos(a0) * (rad + 0.5), 0, sin(a0) * (rad + 0.5))
			g.quad("strip_hazardmark", q0, q1, q2, q3, Color.WHITE, Vector3.UP)
	# pedestrian lane lines
	g.quad_ds("strip_hazardmark", Vector3(126.0, y0 + 0.05, -5.3), Vector3(194.0, y0 + 0.05, -5.3), Vector3(194.0, y0 + 0.05, -4.9), Vector3(126.0, y0 + 0.05, -4.9), Color.WHITE)
	g.quad_ds("strip_hazardmark", Vector3(176.0, y0 + 0.05, -16.0), Vector3(176.4, y0 + 0.05, -16.0), Vector3(176.4, y0 + 0.05, -5.0), Vector3(176.0, y0 + 0.05, -5.0), Color.WHITE)
	# two shuttles
	_shuttle(Vector3(160.0, y0, -24.0), 0.0)
	_shuttle(Vector3(138.0, y0, -14.0), 0.35)
	# gantry crane
	g.ibeam("frame_yellow", Vector3(128.0, 19.0, -12.0), Vector3(192.0, 19.0, -12.0), 0.8, 0.34, Color.WHITE)
	g.ibeam("frame_yellow", Vector3(128.0, 19.0, -38.0), Vector3(192.0, 19.0, -38.0), 0.8, 0.34, Color.WHITE)
	g.ibeam("frame_yellow", Vector3(158.0, 18.3, -12.5), Vector3(158.0, 18.3, -37.5), 0.7, 0.3, Color.WHITE)
	g.box("metal_dark", Vector3(158.0, 17.8, -25.0), Vector3(1.3, 0.6, 1.8), COL_DARK)
	g.cylinder("metal_dark", Vector3(158.0, 17.5, -25.0), Vector3(158.0, 12.8, -25.0), 0.035, COL_DARK, 6)
	g.box("metal", Vector3(158.0, 12.6, -25.0), Vector3(0.6, 0.4, 0.5), COL_YELLOW)
	# control booth (mezzanine)
	var bx0 := 178.0; var bx1 := 190.0; var bz0 := -16.0; var bz1 := -6.0
	for cx in [bx0 + 0.3, bx1 - 0.3]:
		for cz in [bz0 + 0.3, bz1 - 0.3]:
			g.cylinder("frame", Vector3(cx, y0, cz), Vector3(cx, 11.0, cz), 0.16, COL_MACH, 8)
	g.box("metal_dark", Vector3((bx0 + bx1) * 0.5, 10.95, (bz0 + bz1) * 0.5), Vector3(bx1 - bx0, 0.3, bz1 - bz0), COL_DARK)
	g.box("grate_std", Vector3((bx0 + bx1) * 0.5, 11.12, (bz0 + bz1) * 0.5), Vector3(bx1 - bx0 - 0.2, 0.05, bz1 - bz0 - 0.2), Color.WHITE)
	# booth glass front (west + north)
	g.quad_ds("glass", Vector3(bx0, 11.1, bz0 + 0.2), Vector3(bx0, 11.1, bz1 - 0.2), Vector3(bx0, 13.4, bz1 - 0.2), Vector3(bx0, 13.4, bz0 + 0.2), Color(0.75, 0.87, 1.0, 0.3))
	g.quad_ds("glass", Vector3(bx0 + 0.2, 11.1, bz0), Vector3(bx1 - 0.2, 11.1, bz0), Vector3(bx1 - 0.2, 13.4, bz0), Vector3(bx0 + 0.2, 13.4, bz0), Color(0.75, 0.87, 1.0, 0.3))
	g.box("panel_grimy", Vector3((bx0 + bx1) * 0.5, 12.25, bz1 - 0.1), Vector3(bx1 - bx0, 2.3, 0.2), Color(0.9, 0.9, 0.92))
	g.box("metal_dark", Vector3(bx0, 13.5, (bz0 + bz1) * 0.5), Vector3(0.2, 0.16, bz1 - bz0), COL_DARK)
	# booth interior consoles
	console(Vector3(181.5, 11.15, -8.0), -PI * 0.5, "screen_radar", 1.6)
	console(Vector3(181.5, 11.15, -13.0), -PI * 0.5, "screen_bars", 1.6)
	chair(Vector3(183.0, 11.15, -8.0), -PI * 0.5, COL_DARK)
	# booth stairs (external, south side)
	g.stairs("metal", Vector3(184.0, y0, -4.6), Vector3(-1, 0, 0), 3.6, 5.0, 1.3, 18, Color(0.5, 0.52, 0.55), "metal_dark", Color.WHITE)
	g.box("metal_dark", Vector3(181.2, y0 + 3.5, -5.3), Vector3(4.6, 0.2, 1.4), COL_DARK)
	# tool cabinets + workbench along south wall
	for k in 4:
		cabinet(Vector3(148.0 + float(k) * 3.2, y0, -4.6), PI, 2.2, 2.0, 0.7, [COL_RED.darkened(0.15), COL_MACH, COL_YELLOW.darkened(0.25), COL_MACH][k])
	g.box("metal", Vector3(166.0, y0 + 0.9, -4.8), Vector3(8.0, 0.08, 1.2), COL_LIGHT)
	for k in 4:
		g.box("metal_dark", Vector3(162.5 + float(k) * 2.2, y0 + 0.45, -4.8), Vector3(0.12, 0.9, 1.0), COL_DARK)
	# fuel tanker
	g.cylinder("metal", Vector3(130.0, y0 + 1.0, -36.0), Vector3(134.0, y0 + 1.0, -36.0), 0.95, Color(0.5, 0.44, 0.32), 14)
	for wx in [130.6, 133.4]:
		g.cylinder("rubber", Vector3(wx, y0 + 0.42, -36.9), Vector3(wx, y0 + 0.42, -36.5), 0.42, Color(0.1, 0.1, 0.11), 10)
		g.cylinder("rubber", Vector3(wx, y0 + 0.42, -35.5), Vector3(wx, y0 + 0.42, -35.1), 0.42, Color(0.1, 0.1, 0.11), 10)
	g.box("metal_dark", Vector3(134.6, y0 + 0.8, -36.0), Vector3(0.8, 1.0, 1.0), COL_DARK)
	# container stack east corner
	container(Vector3(188.0, y0, -40.0), PI * 0.5, Color(0.34, 0.4, 0.45))
	container(Vector3(188.0, y0 + 2.62, -40.0), PI * 0.5, Color(0.42, 0.4, 0.32))
	# fire station near big door
	g.box("metal", Vector3(131.0, y0 + 0.8, -8.0), Vector3(0.9, 1.6, 0.35), COL_RED)
	g.torus("metal_dark", Vector3(131.0, y0 + 1.2, -7.8), Basis(Vector3.RIGHT, PI * 0.5), 0.28, 0.07, COL_RED.darkened(0.2), 12, 6)
	# interior face of the hull hangar door (north wall z=-44)
	g.box("metal_dark", Vector3(162.0, y0 + 3.0, -43.4), Vector3(46.0, 6.2, 0.5), Color(0.3, 0.31, 0.34))
	g.box("metal", Vector3(150.0, y0 + 3.0, -43.1), Vector3(22.0, 5.8, 0.16), Color(0.42, 0.43, 0.47))
	g.box("metal_dark", Vector3(162.0, y0 + 6.15, -43.0), Vector3(48.0, 0.4, 0.7), COL_YELLOW.darkened(0.2))
	g.ibeam("frame", Vector3(137.0, y0 + 6.6, -42.6), Vector3(187.0, y0 + 6.6, -42.6), 0.5, 0.3, COL_MACH)
	for i in 6:
		g.cylinder("metal_dark", Vector3(140.0 + float(i) * 8.6, y0 + 6.85, -42.6), Vector3(140.0 + float(i) * 8.6, y0 + 6.85, -42.6) + Vector3(0, 0.001, 0), 0.22, COL_DARK, 8)
		g.torus("metal_dark", Vector3(140.0 + float(i) * 8.6, y0 + 6.6, -42.6), Basis(Vector3.RIGHT, PI * 0.5), 0.24, 0.05, COL_DARK, 10, 6)
	for i in 10:
		g.quad_ds("strip_hazardmark", Vector3(140.0 + float(i) * 4.4, y0 + 5.95, -42.72), Vector3(142.2 + float(i) * 4.4, y0 + 5.95, -42.72),
			Vector3(142.2 + float(i) * 4.4, y0 + 6.35, -42.72), Vector3(140.0 + float(i) * 4.4, y0 + 6.35, -42.72), Color.WHITE)
	# support columns for cross catwalk
	for cx in [190.0, 194.5]:
		for cz in [-20.0, -36.0]:
			g.cylinder("frame", Vector3(cx, y0, cz), Vector3(cx, 15.0, cz), 0.22, COL_MACH, 10)
			g.torus("frame", Vector3(cx, y0 + 0.3, cz), Basis(), 0.4, 0.08, COL_DARK, 12, 6)
	# high wall lights
	for k in 6:
		g.box("strip_white", Vector3(130.0 + float(k) * 11.0, y0 + 7.2, -3.3), Vector3(1.6, 0.1, 0.12), Color.WHITE)
		g.box("strip_white", Vector3(130.0 + float(k) * 11.0, y0 + 5.0, -43.5), Vector3(1.6, 0.1, 0.12), Color.WHITE)

func _sh(pos: Vector3, b: Basis, lx: float, ly: float, lz: float) -> Vector3:
	return pos + b * Vector3(lx, ly, lz)

func _shuttle(pos: Vector3, rot_y: float) -> void:
	var b := Basis(Vector3.UP, rot_y)
	var col := Color(0.62, 0.63, 0.66)
	# fuselage + nose
	g.sphere("metal", _sh(pos, b, 0, 1.9, 0), Vector3(4.4, 1.45, 1.6), col, 20, 12)
	g.cylinder("metal", _sh(pos, b, 4.0, 1.9, 0), _sh(pos, b, 5.4, 1.75, 0), 0.85, col, 14, false, 0.3)
	# cockpit glass
	g.sphere("glass", _sh(pos, b, 3.3, 2.3, 0), Vector3(1.3, 0.7, 1.0), Color(0.6, 0.75, 0.95), 12, 8)
	# wings
	for s in [-1.0, 1.0]:
		g.box_basis("metal", Transform3D(Basis(Vector3.UP, rot_y + s * 0.45) , _sh(pos, b, -1.4, 1.75, s * 2.6)), Vector3(3.0, 0.12, 3.4), col)
		g.box("metal_dark", _sh(pos, b, -2.6, 1.5, s * 3.4), Vector3(0.7, 0.5, 0.16), COL_DARK, rot_y)
		g.box("strip_red" if s < 0 else "strip_green", _sh(pos, b, -2.6, 1.82, s * 4.1), Vector3(0.14, 0.08, 0.14), Color.WHITE, rot_y)
	# tail fin
	g.box_basis("metal", Transform3D(Basis(Vector3.UP, rot_y), _sh(pos, b, -3.4, 2.8, 0)), Vector3(1.5, 1.7, 0.1), col)
	# engines
	for s in [-1.0, 1.0]:
		g.cylinder("metal_dark", _sh(pos, b, -4.2, 1.9, s * 1.1), _sh(pos, b, -5.1, 1.9, s * 1.1), 0.55, COL_DARK, 12)
		g.torus("frame", _sh(pos, b, -5.1, 1.9, s * 1.1), b * Basis(Vector3.UP, PI * 0.5), 0.56, 0.07, COL_MACH, 12, 6)
		g.cylinder("strip_cyan", _sh(pos, b, -5.12, 1.9, s * 1.1), _sh(pos, b, -5.16, 1.9, s * 1.1), 0.45, Color.WHITE, 12)
	# landing gear
	for gp in [Vector3(3.2, 0, 0), Vector3(-1.8, 0, -1.3), Vector3(-1.8, 0, 1.3)]:
		var wp: Vector3 = pos + b * gp
		g.strut("metal_dark", wp + Vector3(0, 0.5, 0), wp + Vector3(0, 1.2, 0) * 0.5 + Vector3(0, 0.6, 0), 0.07, 0.07, COL_DARK)
		g.box("metal_dark", wp + Vector3(0, 0.08, 0), Vector3(0.4, 0.16, 0.25), COL_DARK, rot_y)
	# hull accents
	g.box("metal_dark", _sh(pos, b, 0.5, 2.5, 0), Vector3(3.4, 0.1, 1.2), COL_DARK, rot_y)
	g.box("strip_hazardmark", _sh(pos, b, 1.0, 1.2, 1.55), Vector3(1.6, 0.18, 0.02), Color.WHITE, rot_y)

func _catwalk(r: Dictionary) -> void:
	var y0: float = r["y0"]
	if r["name"] == "HANGAR CATWALK X":
		return
	# support brackets under catwalk + ladder down to hangar floor
	for k in 6:
		var xx := 128.0 + float(k) * 12.0
		g.strut("frame", Vector3(xx, y0 - 0.2, -7.6), Vector3(xx, y0 - 2.4, -4.0), 0.14, 0.14, COL_MACH)
		g.strut("frame", Vector3(xx, y0 - 0.2, -4.0), Vector3(xx, y0 - 2.4, -7.6), 0.14, 0.14, COL_MACH)
	# ladder at west end
	for k in 22:
		var yy := 14.7 - float(k) * 0.34
		g.box("metal_dark", Vector3(126.0, yy, -6.6), Vector3(0.5, 0.04, 0.05), COL_DARK)
	g.cylinder("metal_dark", Vector3(125.75, 7.6, -6.6), Vector3(125.75, 15.0, -6.6), 0.03, COL_DARK, 6)
	g.cylinder("metal_dark", Vector3(126.25, 7.6, -6.6), Vector3(126.25, 15.0, -6.6), 0.03, COL_DARK, 6)
	# under-catwalk lights
	for k in 5:
		g.box("strip_warm", Vector3(130.0 + float(k) * 15.0, y0 - 0.18, -5.5), Vector3(1.2, 0.06, 0.1), Color.WHITE)
	# crates staged on catwalk
	crate(Vector3(150.0, y0, -4.5), Vector3(0.7, 0.5, 0.5), COL_YELLOW.darkened(0.2))
	crate(Vector3(151.0, y0, -4.2), Vector3(0.6, 0.4, 0.5), COL_MACH.darkened(0.1), 0.4)

# --------------------------------------------------------------- server / bridge

func _server(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var rows: Array = [[7.0, 9.0], [14.0, 16.0], [21.0, 23.0], [27.0, 29.0]]
	for pair in rows:
		for rz in pair:
			for seg in 2:
				var xb0 := 154.0 if seg == 0 else 176.0
				var xb1 := 168.0 if seg == 0 else 190.0
				var xx := xb0
				while xx < xb1 - 0.6:
					g.box("metal_dark", Vector3(xx + 0.55, y0 + 1.05, rz), Vector3(1.05, 2.1, 0.95), Color(0.17, 0.18, 0.2))
					# LED front (faces the cold aisle of its pair)
					var face_z: float = rz + (0.48 if rz == pair[0] else -0.48)
					g.quad_uv("screen_bars", Vector3(xx + 0.08, y0 + 0.25, face_z), Vector3(xx + 1.02, y0 + 0.25, face_z),
						Vector3(xx + 1.02, y0 + 1.9, face_z), Vector3(xx + 0.08, y0 + 1.9, face_z), Color.WHITE)
					g.box("metal_dark", Vector3(xx + 0.55, y0 + 2.16, rz), Vector3(1.1, 0.08, 1.0), COL_DARK)
					xx += 1.15
			# aisle floor glow line
			g.box("strip_cyan", Vector3((154.0 + 190.0) * 0.5, y0 + 0.03, (pair[0] + pair[1]) * 0.5), Vector3(34.0, 0.02, 0.08), Color.WHITE)
	# cable trays above rows
	for pair in rows:
		for rz in pair:
			duct_run(Vector3(154.0, r["y1"] - 0.45, rz), Vector3(190.0, r["y1"] - 0.45, rz), 0.4, 0.18)
			for k in 6:
				g.cylinder("rubber", Vector3(156.0 + float(k) * 6.0, r["y1"] - 0.6, rz), Vector3(156.0 + float(k) * 6.0, y0 + 2.2, rz), 0.035, Color(0.12, 0.12, 0.14), 5)
	# holo status table in cross aisle
	g.cylinder("metal_dark", Vector3(172.0, y0, 12.0), Vector3(172.0, y0 + 0.85, 12.0), 0.75, COL_DARK, 14)
	g.torus("strip_cyan", Vector3(172.0, y0 + 0.87, 12.0), Basis(), 0.76, 0.04, Color.WHITE, 16, 6)
	g.sphere("holo", Vector3(172.0, y0 + 1.6, 12.0), Vector3(0.55, 0.55, 0.55), Color.WHITE, 14, 10)
	# CRAC units on outer wall
	for k in 2:
		machine_box(Vector3(158.0 + float(k) * 16.0, y0, 30.6), 0.0, Vector3(2.6, 2.3, 1.2), Color(0.35, 0.4, 0.45), 1)
		g.torus("metal_dark", Vector3(158.0 + float(k) * 16.0, y0 + 1.4, 29.95), Basis(Vector3.RIGHT, PI * 0.5), 0.5, 0.06, COL_DARK, 12, 6)
	ceiling_lights(r, "strip_cyan", 2)

func _bridge(r: Dictionary) -> void:
	if r["name"] != "BRIDGE":
		return
	var y0 := 15.0
	# helm console arc facing the viewport
	for k in 4:
		var zz: float = [-6.2, -2.6, 2.6, 6.2][k]
		console(Vector3(263.2, y0, zz), PI * 0.5, "screen_cyan" if k % 2 == 0 else "screen_radar", 2.3)
		chair(Vector3(261.6, y0, zz), PI * 0.5, Color(0.25, 0.27, 0.32))
	# joysticks on inner helm consoles
	for zz in [-2.6, 2.6]:
		g.cylinder("metal_dark", Vector3(262.9, y0 + 0.92, zz + 0.5), Vector3(262.9, y0 + 1.12, zz + 0.5), 0.035, COL_DARK, 6)
		g.sphere("rubber", Vector3(262.9, y0 + 1.17, zz + 0.5), Vector3(0.06, 0.07, 0.06), Color(0.5, 0.15, 0.12), 8, 6)
	# captain dais + chair (offset north of centerline route)
	g.box("metal_dark", Vector3(257.0, y0 + 0.15, -6.0), Vector3(5.0, 0.3, 5.0), Color(0.22, 0.23, 0.27))
	g.box("strip_cyan", Vector3(257.0, y0 + 0.31, -3.55), Vector3(5.0, 0.03, 0.08), Color.WHITE)
	g.railing("metal_dark", [Vector3(254.5, y0 + 0.3, -3.6), Vector3(259.5, y0 + 0.3, -3.6)], 0.9, Color.WHITE)
	# captain chair
	var cp := Vector3(257.0, y0 + 0.3, -6.0)
	g.cylinder("metal_dark", cp, cp + Vector3(0, 0.35, 0), 0.32, COL_DARK, 10)
	g.box("fabric", cp + Vector3(0, 0.55, 0), Vector3(0.72, 0.14, 0.7), Color(0.28, 0.24, 0.2))
	g.box("fabric", cp + Vector3(0, 1.0, -0.3), Vector3(0.7, 0.95, 0.14), Color(0.28, 0.24, 0.2))
	g.box("fabric", cp + Vector3(0, 1.55, -0.28), Vector3(0.46, 0.24, 0.12), Color(0.32, 0.27, 0.22))
	for s in [-1.0, 1.0]:
		g.box("metal_dark", cp + Vector3(s * 0.42, 0.72, -0.05), Vector3(0.1, 0.1, 0.6), COL_DARK)
	g.box("metal_warm", cp + Vector3(0, 0.62, -0.36), Vector3(0.78, 0.04, 0.04), Color(0.62, 0.5, 0.3))
	# ops consoles south side
	console(Vector3(256.0, y0, 7.5), -PI * 0.5, "screen_bars", 2.6)
	chair(Vector3(257.6, y0, 7.5), -PI * 0.5, Color(0.25, 0.27, 0.32))
	# holo table south
	g.cylinder("metal_dark", Vector3(254.5, y0, 13.0), Vector3(254.5, y0 + 0.9, 13.0), 1.3, COL_DARK, 16)
	g.torus("strip_cyan", Vector3(254.5, y0 + 0.92, 13.0), Basis(), 1.32, 0.05, Color.WHITE, 18, 6)
	g.sphere("holo", Vector3(254.5, y0 + 1.9, 13.0), Vector3(0.9, 0.9, 0.9), Color.WHITE, 16, 12)
	g.torus("holo", Vector3(254.5, y0 + 1.9, 13.0), Basis(Vector3(1, 0, 0), 0.7), 1.35, 0.025, Color.WHITE, 26, 6)
	g.torus("holo", Vector3(254.5, y0 + 1.9, 13.0), Basis(Vector3(1, 0, 0), -0.4) * Basis(Vector3(0, 1, 0), 0.8), 1.55, 0.02, Color.WHITE, 26, 6)
	# aft status wall
	wall_screen("screen_bars", Vector3(248.6, y0 + 2.6, -13.0), Vector3(1, 0, 0), 7.5, 2.1)
	g.box("metal_warm", Vector3(248.55, y0 + 1.5, -13.0), Vector3(0.04, 0.08, 7.9), Color(0.6, 0.5, 0.32))
	g.box("metal_warm", Vector3(248.55, y0 + 4.9, -13.0), Vector3(0.04, 0.08, 7.9), Color(0.6, 0.5, 0.32))
	# side consoles along walls
	for k in 3:
		console(Vector3(251.0 + float(k) * 3.4, y0, -20.8), 0.0, "screen_cyan", 2.0)
		locker(Vector3(252.0 + float(k) * 3.6, y0, 20.8), PI, 2, 2.2, 1.8, 0.6, COL_MACH)
		g.quad_uv("screen_bars", Vector3(251.0 + float(k) * 3.6 - 0.5, y0 + 0.8, 20.45), Vector3(251.0 + float(k) * 3.6 + 0.5, y0 + 0.8, 20.45),
			Vector3(251.0 + float(k) * 3.6 + 0.5, y0 + 1.5, 20.45), Vector3(251.0 + float(k) * 3.6 - 0.5, y0 + 1.5, 20.45), Color.WHITE)
	# observation bench at viewport
	g.box("metal_dark", Vector3(266.6, y0 + 0.3, 0.0), Vector3(1.1, 0.55, 9.0), COL_DARK)
	g.box("fabric", Vector3(266.6, y0 + 0.62, 0.0), Vector3(1.15, 0.1, 9.0), Color(0.3, 0.33, 0.42))
	# ceiling light rings
	g.torus("emit_cyan", Vector3(258.0, 20.82, 0.0), Basis(), 6.2, 0.07, Color.WHITE, 40, 6)
	g.torus("emit_cyan", Vector3(258.0, 20.82, 0.0), Basis(), 3.0, 0.06, Color.WHITE, 28, 6)
	g.torus("emit_cyan", Vector3(265.0, 20.82, 0.0), Basis(), 2.4, 0.05, Color.WHITE, 22, 6)
	# deck inlay stripe from door to helm
	g.box("strip_cyan", Vector3(253.0, y0 + 0.02, -2.2), Vector3(16.0, 0.02, 0.06), Color.WHITE)
	g.box("strip_cyan", Vector3(253.0, y0 + 0.02, 2.2), Vector3(16.0, 0.02, 0.06), Color.WHITE)

# --------------------------------------------------------------- misc rooms

func _lab(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var brief: bool = r["style"] == "lab" and r["name"] == "BRIEFING ROOM"
	if brief:
		g.box("metal", Vector3(209.0, y0 + 0.72, 14.0), Vector3(7.0, 0.1, 3.2), COL_LIGHT)
		g.box("metal_dark", Vector3(209.0, y0 + 0.36, 14.0), Vector3(5.6, 0.6, 2.0), COL_DARK)
		for k in 8:
			var a := TAU * float(k) / 8.0
			chair(Vector3(209.0 + cos(a) * 4.4, y0, 14.0 + sin(a) * 2.4), -a, COL_FAB2)
		wall_screen("screen_radar", Vector3(209.0, y0 + 2.3, 3.4), Vector3(0, 0, 1), 3.0, 1.6)
		g.cylinder("metal_dark", Vector3(209.0, y0 + 0.78, 14.0), Vector3(209.0, y0 + 1.1, 14.0), 0.28, COL_DARK, 10)
		g.sphere("holo", Vector3(209.0, y0 + 1.5, 14.0), Vector3(0.4, 0.4, 0.4), Color.WHITE, 12, 8)
		ceiling_lights(r, "strip_white", 2)
		return
	# science lab
	for k in 2:
		var bz := 8.0 + float(k) * 9.0
		g.box("metal", Vector3(212.0, y0 + 0.9, bz), Vector3(14.0, 0.08, 1.5), COL_WHITE.darkened(0.08))
		for j in 6:
			g.box("metal_dark", Vector3(205.5 + float(j) * 2.4, y0 + 0.45, bz), Vector3(0.1, 0.9, 1.3), COL_DARK)
		g.box("metal", Vector3(212.0, y0 + 1.55, bz - 0.55), Vector3(14.0, 0.06, 0.35), COL_LIGHT)
		for j in 8:
			var ex := 206.0 + float(j) * 1.7
			if rng.randf() < 0.7:
				g.cylinder("glass", Vector3(ex, y0 + 0.94, bz + 0.3), Vector3(ex, y0 + 1.24, bz + 0.3), 0.07, Color(0.85, 0.9, 0.95), 6)
			if rng.randf() < 0.4:
				g.box("plastic", Vector3(ex, y0 + 1.02, bz - 0.1), Vector3(0.22, 0.16, 0.22), Color(0.7, 0.72, 0.75))
	# fume hood
	g.box("metal_dark", Vector3(220.0, y0 + 1.0, 22.0), Vector3(2.4, 2.0, 1.2), COL_MACH)
	g.quad_ds("glass", Vector3(218.85, y0 + 0.5, 21.5), Vector3(218.85, y0 + 0.5, 22.5), Vector3(218.85, y0 + 1.7, 22.5), Vector3(218.85, y0 + 1.7, 21.5), Color.WHITE)
	g.box("strip_green", Vector3(220.0, y0 + 2.05, 22.0), Vector3(1.0, 0.05, 0.1), Color.WHITE)
	# centrifuge + freezers + holo analyzer
	g.cylinder("white_mat", Vector3(205.0, y0 + 0.9, 20.0), Vector3(205.0, y0 + 1.25, 20.0), 0.45, COL_WHITE, 14)
	g.box("metal_dark", Vector3(205.0, y0 + 0.45, 20.0), Vector3(0.9, 0.9, 0.9), COL_DARK)
	for k in 2:
		g.box("metal", Vector3(222.0, y0 + 0.95, 6.0 + float(k) * 2.4), Vector3(1.3, 1.9, 1.1), COL_LIGHT)
		g.quad_uv("screen_bars", Vector3(221.3, y0 + 1.2, 5.5 + float(k) * 2.4), Vector3(221.3, y0 + 1.2, 6.5 + float(k) * 2.4),
			Vector3(221.3, y0 + 1.7, 6.5 + float(k) * 2.4), Vector3(221.3, y0 + 1.7, 5.5 + float(k) * 2.4), Color.WHITE)
	wall_screen("screen_cyan", Vector3(210.0, y0 + 2.2, 3.4), Vector3(0, 0, 1), 2.4, 1.3)
	for k in 3:
		stool(Vector3(208.0 + float(k) * 2.2, y0, 10.5), COL_FAB2)
	ceiling_lights(r, "strip_white", 2)

func _office(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var z0: float = r["z0"]; var z1: float = r["z1"]
	var cx: float = (x0 + x1) * 0.5; var cz: float = (z0 + z1) * 0.5
	var area := (x1 - x0) * (z1 - z0)
	var v := variant_of(r)
	var nd := clampi(int(area / 90.0), 2, 6)
	if v == 1:
		# U-shaped console cluster + partition
		for k in 3:
			console(Vector3(cx - 3.0 + float(k) * 3.0, y0, z0 + 3.0), 0.0, "screen_bars", 2.0)
		for k in 2:
			console(Vector3(x0 + 2.5, y0, cz - 2.0 + float(k) * 4.0), PI * 0.5, "screen_cyan", 1.8)
		g.box("panel_std", Vector3(cx, y0 + 1.1, cz + 3.0), Vector3((x1 - x0) * 0.6, 2.2, 0.12), Color(0.9, 0.9, 0.92))
		for k in 2:
			chair(Vector3(cx - 1.5 + float(k) * 3.0, y0, z0 + 4.2), 0.0, COL_FAB2)
	else:
		for k in nd:
			var px := lerpf(x0 + 2.5, x1 - 2.5, float(k % 3) / 2.0)
			var pz := lerpf(z0 + 3.0, z1 - 3.0, float(k / 3) / maxf(float(nd / 3 - 1), 1.0))
			desk(Vector3(px, y0, pz), rng.randf() * TAU, "screen_bars", 1.5)
			chair(Vector3(px + 0.9, y0, pz + 0.5), rng.randf() * TAU, COL_FAB2)
		if v == 2:
			g.box("metal", Vector3(cx, y0 + 0.72, cz), Vector3(3.0, 0.08, 1.6), COL_LIGHT)
			for k in 6:
				chair(Vector3(cx - 1.8 + float(k % 3) * 1.8, y0, cz + (1.3 if k < 3 else -1.3)), 0.0 if k < 3 else PI, COL_FAB2)
	for k in 2:
		cabinet(Vector3(x0 + 1.0, y0, lerpf(z0 + 2.0, z1 - 2.0, float(k))), PI * 0.5, 1.6, 2.0, 0.55, COL_LIGHT)
	ceiling_lights(r, "strip_cyan", 1)

func _storage(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var z0: float = r["z0"]; var z1: float = r["z1"]
	var area := (x1 - x0) * (z1 - z0)
	var along_x: bool = (x1 - x0) > (z1 - z0)
	var v := variant_of(r)
	var nrows := clampi(int((z1 - z0 if along_x else x1 - x0) / 4.0), 1, 4)
	if v == 1:
		# crate stacks + single rack row
		if along_x:
			shelf_rack(Vector3((x0 + x1) * 0.5, y0, z0 + 1.5), 0.0, (x1 - x0) - 3.0, 3, 2.3, COL_MACH, 0.6)
		else:
			shelf_rack(Vector3(x0 + 1.5, y0, (z0 + z1) * 0.5), PI * 0.5, (z1 - z0) - 3.0, 3, 2.3, COL_MACH, 0.6)
		var i := 0
		while i < int(area / 25.0):
			var px := lerpf(x0 + 2.0, x1 - 2.0, rng.randf())
			var pz := lerpf(z0 + 3.5, z1 - 2.0, rng.randf())
			var sv := Vector3(0.9, 0.7, 0.9)
			crate(Vector3(px, y0, pz), sv, COL_WARM.darkened(0.05), rng.randf() * 0.5)
			if rng.randf() > 0.5:
				crate(Vector3(px, y0 + sv.y, pz), sv * 0.85, COL_MACH.darkened(0.1), rng.randf())
			i += 1
	elif v == 2:
		# barrel rows + pallets
		var i := 0
		while i < int(area / 18.0):
			var px := lerpf(x0 + 1.5, x1 - 1.5, rng.randf())
			var pz := lerpf(z0 + 1.5, z1 - 1.5, rng.randf())
			if rng.randf() < 0.6:
				barrel(Vector3(px, y0, pz), [COL_MACH.darkened(0.1), COL_YELLOW.darkened(0.25), COL_BLUE.darkened(0.1)][int(rng.randf() * 3) % 3])
			else:
				g.box("metal_warm", Vector3(px, y0 + 0.08, pz), Vector3(1.2, 0.16, 1.0), COL_WARM)
				crate(Vector3(px, y0 + 0.16, pz), Vector3(1.0, 0.6, 0.8), COL_MACH.darkened(0.05), 0.0)
			i += 1
	else:
		for k in nrows:
			if along_x:
				var pz := lerpf(z0 + 2.0, z1 - 2.0, float(k) / maxf(float(nrows - 1), 1.0))
				shelf_rack(Vector3((x0 + x1) * 0.5, y0, pz), 0.0, (x1 - x0) - 3.0, 3, 2.3, COL_MACH, 0.55)
			else:
				var px := lerpf(x0 + 2.0, x1 - 2.0, float(k) / maxf(float(nrows - 1), 1.0))
				shelf_rack(Vector3(px, y0, (z0 + z1) * 0.5), PI * 0.5, (z1 - z0) - 3.0, 3, 2.3, COL_MACH, 0.55)
	for k in int(clampi(area / 120.0, 1, 5)):
		crate(Vector3(lerpf(x0 + 1.5, x1 - 1.5, rng.randf()), y0, lerpf(z0 + 1.5, z1 - 1.5, rng.randf())),
			Vector3(0.7 + rng.randf() * 0.4, 0.5 + rng.randf() * 0.4, 0.6), COL_WARM.darkened(0.05), rng.randf())
	ceiling_lights(r, "strip_warm", 1)

func _pods(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var along_x: bool = (r["x1"] - r["x0"]) > (r["z1"] - r["z0"])
	var n := 3
	for k in n:
		for s in [-1.0, 1.0]:
			var px: float = lerpf(r["x0"] + 3.0, r["x1"] - 3.0, float(k) / float(n - 1)) if along_x else (r["x0"] + r["x1"]) * 0.5 + s * 4.0
			var pz: float = (r["z0"] + r["z1"]) * 0.5 + s * ((r["z1"] - r["z0"]) * 0.5 - 2.2) if along_x else lerpf(r["z0"] + 3.0, r["z1"] - 3.0, float(k) / float(n - 1))
			var rot := 0.0 if along_x else PI * 0.5
			# rack frame
			g.box("metal_dark", Vector3(px, y0 + 0.2, pz), Vector3(3.1, 0.4, 1.5) if along_x else Vector3(1.5, 0.4, 3.1), COL_DARK, rot)
			# capsule
			var b := Basis(Vector3.UP, rot)
			g.cylinder("metal", Vector3(px, y0 + 1.15, pz) + b * Vector3(-1.1, 0, 0), Vector3(px, y0 + 1.15, pz) + b * Vector3(1.1, 0, 0), 0.72, Color(0.75, 0.72, 0.62), 14, false)
			g.sphere("metal", Vector3(px, y0 + 1.15, pz) + b * Vector3(1.1, 0, 0), Vector3(0.75, 0.72, 0.72), Color(0.75, 0.72, 0.62), 12, 8)
			g.sphere("metal", Vector3(px, y0 + 1.15, pz) + b * Vector3(-1.1, 0, 0), Vector3(0.6, 0.72, 0.72), Color(0.7, 0.67, 0.58), 12, 8)
			# hatch ring + window
			g.torus("metal_dark", Vector3(px, y0 + 1.15, pz) + b * Vector3(0.55, 0, 0), b * Basis(Vector3.UP, PI * 0.5), 0.5, 0.06, COL_DARK, 14, 6)
			g.cylinder("glass", Vector3(px, y0 + 1.15, pz) + b * Vector3(0.58, 0, 0), Vector3(px, y0 + 1.15, pz) + b * Vector3(0.62, 0, 0), 0.3, Color(0.6, 0.75, 0.9), 10)
			# status light
			g.box("strip_green" if (k + int(s)) % 2 == 0 else "strip_red", Vector3(px, y0 + 1.95, pz) + b * Vector3(-0.8, 0, 0), Vector3(0.16, 0.06, 0.06), Color.WHITE, rot)
			g.strut("metal_dark", Vector3(px, y0 + 0.4, pz) + b * Vector3(-0.9, 0, 0), Vector3(px, y0 + 0.55, pz) + b * Vector3(-0.9, 0.5, 0), 0.06, 0.06, COL_DARK)
	ceiling_lights(r, "strip_amber", 1)

func _tanks(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var along_x: bool = (r["x1"] - r["x0"]) > (r["z1"] - r["z0"])
	for k in 3:
		if along_x:
			var pz := lerpf(r["z0"] + 2.5, r["z1"] - 2.5, float(k) / 2.0)
			var cx: float = (r["x0"] + r["x1"]) * 0.5
			var len2 := minf((r["x1"] - r["x0"]) * 0.4, 5.0)
			g.cylinder("metal", Vector3(cx - len2, y0 + 1.3, pz), Vector3(cx + len2, y0 + 1.3, pz), 1.15, Color(0.45, 0.48, 0.5), 14)
			for s in [-1.0, 1.0]:
				g.box("metal_dark", Vector3(cx + s * len2 * 0.6, y0 + 0.45, pz), Vector3(0.4, 0.9, 1.6), COL_DARK)
			g.torus("metal_dark", Vector3(cx, y0 + 2.45, pz), Basis(Vector3.RIGHT, PI * 0.5), 0.14, 0.04, COL_DARK, 8, 6)
		else:
			var px := lerpf(r["x0"] + 2.5, r["x1"] - 2.5, float(k) / 2.0)
			tank_v(Vector3(px, y0, (r["z0"] + r["z1"]) * 0.5), 1.1, 3.2, Color(0.45, 0.48, 0.5), "strip_cyan")
	pipe_run(Vector3(r["x0"] + 1.0, y0 + 3.6, r["z0"] + 1.0), Vector3(r["x1"] - 1.0, y0 + 3.6, r["z0"] + 1.0), 0.1, COL_MACH)
	ceiling_lights(r, "strip_cyan", 1)

func _eva(r: Dictionary) -> void:
	if r["name"] == "EVA TUBE":
		return
	var y0: float = r["y0"]
	# two EVA suits on stands
	for k in 2:
		var px := 59.0 + float(k) * 2.4
		var pz := -18.0
		g.cylinder("metal_dark", Vector3(px, y0, pz), Vector3(px, y0 + 1.0, pz), 0.05, COL_DARK, 6)
		g.box("white_mat", Vector3(px, y0 + 1.45, pz), Vector3(0.6, 0.8, 0.42), Color(0.88, 0.88, 0.9))
		g.sphere("white_mat", Vector3(px, y0 + 2.05, pz), Vector3(0.21, 0.24, 0.21), Color(0.9, 0.9, 0.92), 10, 8)
		g.sphere("glass", Vector3(px, y0 + 2.05, pz + 0.12), Vector3(0.15, 0.17, 0.12), Color(0.5, 0.6, 0.75), 8, 6)
		g.box("white_mat", Vector3(px, y0 + 1.5, pz - 0.3), Vector3(0.44, 0.6, 0.22), Color(0.85, 0.85, 0.87))
		g.box("strip_amber", Vector3(px, y0 + 1.75, pz + 0.22), Vector3(0.3, 0.05, 0.02), Color.WHITE)
		g.cylinder("white_mat", Vector3(px - 0.38, y0 + 1.05, pz), Vector3(px - 0.38, y0 + 1.7, pz), 0.09, Color(0.88, 0.88, 0.9), 6)
		g.cylinder("white_mat", Vector3(px + 0.38, y0 + 1.05, pz), Vector3(px + 0.38, y0 + 1.7, pz), 0.09, Color(0.88, 0.88, 0.9), 6)
	# lockers + tool rack + mission screen
	locker(Vector3(66.0, y0, -12.0), PI * 0.5, 4, 1.1, 2.2, 0.6, COL_LIGHT)
	g.box("metal_dark", Vector3(73.6, y0 + 1.4, -16.0), Vector3(0.12, 1.4, 4.0), COL_DARK)
	for k in 6:
		g.cylinder("metal", Vector3(73.5, y0 + 1.7, -17.6 + float(k) * 0.6), Vector3(73.5, y0 + 1.7, -17.6 + float(k) * 0.6) + Vector3(0, -0.3, 0), 0.03, COL_LIGHT, 5)
	wall_screen("screen_radar", Vector3(62.0, y0 + 2.0, -23.6), Vector3(0, 0, 1), 2.0, 1.2)
	# prep bench
	g.box("metal", Vector3(68.0, y0 + 0.85, -21.0), Vector3(4.0, 0.07, 1.1), COL_LIGHT)
	for k in 2:
		g.box("metal_dark", Vector3(66.5 + float(k) * 3.0, y0 + 0.42, -21.0), Vector3(0.1, 0.84, 0.9), COL_DARK)
	ceiling_lights(r, "strip_amber", 1)

# --------------------------------------------------------------- damage & clutter

func _damage(r: Dictionary, lvl: int) -> void:
	var y0: float = r["y0"]; var y1: float = r["y1"]
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var z0: float = r["z0"]; var z1: float = r["z1"]
	for k in 1 + lvl:
		var px := lerpf(x0 + 2.0, x1 - 2.0, rng.randf())
		var pz := lerpf(z0 + 2.0, z1 - 2.0, rng.randf())
		var sc := 1.2 + rng.randf() * 2.2
		g.box("rubber", Vector3(px, y0 + 0.015, pz), Vector3(sc, 0.03, sc * (0.6 + rng.randf() * 0.7)), Color(0.05, 0.045, 0.04), rng.randf() * 0.5)
		var nd := 4 + lvl * 5
		for j in nd:
			var dx := px + (rng.randf() - 0.5) * (sc + 1.5)
			var dz := pz + (rng.randf() - 0.5) * (sc + 1.5)
			var t := rng.randf()
			if t < 0.5:
				g.box("metal_dark", Vector3(dx, y0 + 0.06, dz), Vector3(0.2 + rng.randf() * 0.4, 0.12, 0.15 + rng.randf() * 0.3), Color(0.2, 0.19, 0.18), rng.randf() * 3.0)
			elif t < 0.8:
				g.box("panel_dark", Vector3(dx, y0 + 0.03, dz), Vector3(0.5 + rng.randf() * 0.6, 0.05, 0.4 + rng.randf() * 0.5), Color(0.3, 0.31, 0.33), rng.randf())
			else:
				g.cylinder("metal_dark", Vector3(dx, y0 + 0.08, dz), Vector3(dx + 0.3, y0 + 0.14, dz + 0.2), 0.05, COL_DARK, 6)
	for k in lvl:
		var wx := lerpf(x0 + 1.0, x1 - 1.0, rng.randf())
		g.box_basis("panel_dark", Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(12.0 + rng.randf() * 10.0)), Vector3(wx, y0 + 0.9, z0 + 0.6)), Vector3(1.8, 0.06, 1.9), Color(0.3, 0.31, 0.33))
	for k in lvl + 1:
		var ax := lerpf(x0 + 1.5, x1 - 1.5, rng.randf())
		var az := lerpf(z0 + 1.5, z1 - 1.5, rng.randf())
		g.pipe("rubber", [Vector3(ax, y1 - 0.05, az), Vector3(ax + 0.4, y1 - 1.1 - rng.randf(), az + 0.3), Vector3(ax + 0.9, y1 - 0.2, az + 0.7)], 0.03, Color(0.1, 0.1, 0.11), 5)
	if lvl >= 2:
		g.box("strip_flicker", Vector3((x0 + x1) * 0.5, y1 - 0.14, (z0 + z1) * 0.5), Vector3(1.6, 0.06, 0.18), Color.WHITE)
		g.cylinder("strip_red", Vector3(x0 + 0.6, y1 - 0.6, z0 + 0.6), Vector3(x0 + 0.6, y1 - 0.4, z0 + 0.6), 0.1, Color.WHITE, 8)

func _clutter(r: Dictionary) -> void:
	var y0: float = r["y0"]
	var area: float = (r["x1"] - r["x0"]) * (r["z1"] - r["z0"])
	var n := clampi(int(area / 90.0), 2, 7)
	for k in n:
		var edge := int(rng.randf() * 4)
		var px: float
		var pz: float
		if edge == 0:
			px = lerpf(r["x0"] + 0.8, r["x1"] - 0.8, rng.randf()); pz = r["z0"] + 0.7
		elif edge == 1:
			px = lerpf(r["x0"] + 0.8, r["x1"] - 0.8, rng.randf()); pz = r["z1"] - 0.7
		elif edge == 2:
			px = r["x0"] + 0.7; pz = lerpf(r["z0"] + 0.8, r["z1"] - 0.8, rng.randf())
		else:
			px = r["x1"] - 0.7; pz = lerpf(r["z0"] + 0.8, r["z1"] - 0.8, rng.randf())
		var t := rng.randf()
		if t < 0.3:
			crate(Vector3(px, y0, pz), Vector3(0.45, 0.3, 0.3), [COL_RED.darkened(0.1), COL_YELLOW.darkened(0.2), COL_MACH][int(rng.randf() * 3) % 3], rng.randf() * 0.6)
		elif t < 0.5:
			g.torus("rubber", Vector3(px, y0 + 0.08, pz), Basis(), 0.28, 0.07, Color(0.12, 0.12, 0.13), 10, 6)
		elif t < 0.65:
			g.cylinder("metal", Vector3(px, y0 + 0.9, pz), Vector3(px, y0 + 1.35, pz), 0.07, COL_RED, 8)
			g.box("metal_dark", Vector3(px, y0 + 1.1, pz), Vector3(0.05, 0.35, 0.05), COL_DARK)
		elif t < 0.8:
			g.box("plastic", Vector3(px, y0 + 0.16, pz), Vector3(0.35, 0.32, 0.28), Color(0.5, 0.48, 0.42), rng.randf())
		else:
			g.cylinder("white_mat", Vector3(px, y0 + 0.95, pz), Vector3(px, y0 + 1.05, pz), 0.045, COL_WHITE, 6)
			g.box("metal_dark", Vector3(px, y0 + 0.9, pz), Vector3(0.3, 0.02, 0.22), COL_DARK)

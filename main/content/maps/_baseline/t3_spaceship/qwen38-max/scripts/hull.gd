class_name Hull
extends RefCounted
## Layered hull: outer plating (parametric superellipse loft), inner skin,
## station ribs + longitudinal stringers (framework layer), transom cap,
## engine nacelles with exhaust plumes, dorsal sensor mast, radiator fins,
## running light strips. Window/bow/nacelle regions are masked out of the
## plating so interiors can look out through glass.

var g: Geom
var lay: Layout

func _init(geom: Geom, layout: Layout) -> void:
	g = geom
	lay = layout

const NU := 140
const NV := 48

func _section(x: float, th: float, inset: float = 0.0) -> Vector3:
	var b: float = lay.hull_half_width(x) - inset
	var hh: float = lay.hull_half_height(x) - inset
	if b <= 0.2 or hh <= 0.2:
		return Vector3(NAN, NAN, NAN)
	var yc: float = lay.hull_center_y()
	var n := 2.8
	var e := 2.0 / n
	var cz := cos(th); var sy := sin(th)
	var z := b * signf(cz) * pow(absf(cz), e)
	var y := yc + hh * signf(sy) * pow(absf(sy), e)
	return Vector3(x, y, z)

func _masked(x: float, y: float, z: float) -> bool:
	# engine nacelle exits
	if x < 13.0:
		if Vector2(y - 3.0, z - 18.0).length() < 6.7:
			return true
		if Vector2(y - 3.0, z + 18.0).length() < 6.7:
			return true
	# bridge bow viewport
	if x > 261.0 and x < 275.0 and y > 15.0 and y < 20.7:
		if absf(z) < lay.hull_half_width(x) * 0.94:
			return true
	# observation lounge window band (port flank)
	if x > 199.0 and x < 223.0 and y > 16.0 and y < 20.0 and z < -43.0:
		return true
	return false

func _pt_outer(u: float, v: float) -> Vector3:
	var p := _section(u, v, 0.0)
	if _bad(p) or _masked(p.x, p.y, p.z):
		return Vector3(NAN, NAN, NAN)
	return p

func _pt_inner(u: float, v: float) -> Vector3:
	var p := _section(u, v, 0.7)
	if _bad(p) or _masked(p.x, p.y, p.z):
		return Vector3(NAN, NAN, NAN)
	return p

func _bad(p: Vector3) -> bool:
	return is_nan(p.x)

func build() -> void:
	var col := Color.WHITE
	# outer plating
	g.parametric("hull", _pt_outer, 0.0, 280.0, 0.0, TAU, NU, NV, col)
	# inner skin (inward facing)
	g.parametric("hull_inner", _pt_inner, 0.0, 280.0, 0.0, TAU, NU, NV, col, true)
	_transom()
	_ribs_and_stringers()
	_nacelles()
	_dorsal()
	_running_lights()
	_lounge_reveal()

func _transom() -> void:
	# flat stern cap at x=0 with nacelle holes, built from a masked quad grid
	var yc: float = lay.hull_center_y()
	var b := 44.0; var hh := 13.75; var n := 2.8
	var step := 1.1
	var y := yc - hh
	while y < yc + hh:
		var z := -b
		while z < b:
			var cz1 := y + step * 0.5 - yc
			var cz2 := z + step * 0.5
			var inside := pow(absf(cz2) / b, n) + pow(absf(cz1) / hh, n) <= 1.0
			var dn := minf(Vector2(cz1, cz2 - 18.0).length(), Vector2(cz1, cz2 + 18.0).length())
			if inside and dn > 6.3:
				var p0 := Vector3(0.05, y, z)
				var p1 := Vector3(0.05, y, z + step)
				var p2 := Vector3(0.05, y + step, z + step)
				var p3 := Vector3(0.05, y + step, z)
				g.quad("hull_inner", p0, p1, p2, p3, Color.WHITE, Vector3(-1, 0, 0))
			z += step
		y += step
	# nacelle fairing rings on transom
	for zs in [-18.0, 18.0]:
		g.torus("frame_rust", Vector3(0.1, 3.0, zs), Basis(Vector3.UP, PI * 0.5), 6.1, 0.42, Color(0.42, 0.4, 0.37), 28, 10)

func _ribs_and_stringers() -> void:
	# station ribs every 8m (box-section ring following the superellipse)
	var col := Color(0.45, 0.45, 0.48, 0.3)
	var x := 4.0
	while x < 252.0:
		var pts: Array = []
		var seg := 36
		for i in seg + 1:
			var th := TAU * float(i) / float(seg)
			var p := _section(x, th, 1.0)
			if not _bad(p):
				pts.append(p)
		for i in pts.size() - 1:
			g.strut("frame", pts[i], pts[i + 1], 0.5, 0.28, col)
		x += 8.0
	# longitudinal stringers at 16 angles
	for k in 16:
		var th := TAU * (float(k) / 16.0 + 0.031)
		var prev := _section(4.0, th, 1.0)
		var xx := 12.0
		while xx <= 252.0:
			var p := _section(xx, th, 1.0)
			if not _bad(p) and not _bad(prev):
				g.strut("frame", prev, p, 0.24, 0.24, col)
			prev = p
			xx += 8.0

func _nacelles() -> void:
	for zs in [-18.0, 18.0]:
		var c := Vector3(0.0, 3.0, zs)
		# drive tube
		g.cylinder("hull", Vector3(-16.0, 3.0, zs), Vector3(9.0, 3.0, zs), 5.5, Color.WHITE, 28, false)
		# nozzle rim + inner ring
		g.torus("frame_rust", Vector3(-16.0, 3.0, zs), Basis(Vector3.UP, PI * 0.5), 5.55, 0.4, Color(0.4, 0.4, 0.43), 30, 10)
		g.torus("metal_dark", Vector3(-14.6, 3.0, zs), Basis(Vector3.UP, PI * 0.5), 4.6, 0.22, Color(0.3, 0.31, 0.34), 26, 8)
		# exhaust plume cone + bright core disc
		g.cylinder("exhaust", Vector3(-16.2, 3.0, zs), Vector3(-36.0, 3.0, zs), 5.0, Color.WHITE, 24, false, 8.2)
		g.cylinder("exhaust", Vector3(-16.2, 3.0, zs), Vector3(-18.5, 3.0, zs), 4.6, Color.WHITE, 20, false, 4.2)
		var disc := Basis(Vector3.UP, PI * 0.5)
		g.torus("strip_white", Vector3(-16.4, 3.0, zs), disc, 3.2, 1.1, Color.WHITE, 24, 10)
		g.cylinder("strip_cyan", Vector3(-16.5, 3.0, zs), Vector3(-16.3, 3.0, zs), 4.4, Color.WHITE, 20, true)
		# running strip along nacelle
		g.box("strip_cyan", Vector3(-6.0, 8.62, zs), Vector3(16.0, 0.1, 0.14), Color.WHITE)
		# pylon fairings to hull
		g.strut("hull", Vector3(4.0, 8.4, zs), Vector3(9.0, 13.5, zs * 1.35), 1.6, 0.9, Color.WHITE)

func _dorsal() -> void:
	# radiator fins (two, canted)
	for side in [-1.0, 1.0]:
		var b := Basis(Vector3(1, 0, 0), deg_to_rad(24.0 * side))
		var xf := Transform3D(b, Vector3(112.0, 25.6, side * 11.0))
		g.box_basis("frame", xf, Vector3(30.0, 0.22, 8.6), Color(0.4, 0.41, 0.44))
		# glowing coolant veins on fin faces
		for k in 5:
			var zz := -3.4 + float(k) * 1.7
			g.box_basis("strip_cyan", Transform3D(b, Vector3(112.0, 25.75, side * 11.0 + zz * cos(deg_to_rad(24.0 * side)))), Vector3(28.0, 0.03, 0.16), Color.WHITE)
		g.strut("frame", Vector3(100.0, 24.0, side * 7.4), Vector3(100.0, 25.4, side * 8.6), 0.5, 0.5, Color(0.4, 0.41, 0.44))
		g.strut("frame", Vector3(124.0, 24.0, side * 7.4), Vector3(124.0, 25.4, side * 8.6), 0.5, 0.5, Color(0.4, 0.41, 0.44))
	# sensor dome + mast
	g.sphere("hull", Vector3(206.0, 23.6, 0.0), Vector3(3.2, 2.6, 3.2), Color.WHITE, 20, 8, 0.0, TAU, 0.0, PI * 0.55)
	g.torus("frame", Vector3(206.0, 23.7, 0.0), Basis(), 3.25, 0.18, Color(0.42, 0.42, 0.45), 24, 8)
	g.cylinder("frame", Vector3(196.0, 24.0, 0.0), Vector3(196.0, 31.0, 0.0), 0.16, Color(0.42, 0.42, 0.45), 8)
	g.torus("frame", Vector3(196.0, 29.2, 0.0), Basis(), 0.85, 0.06, Color(0.42, 0.42, 0.45), 14, 6)
	g.torus("frame", Vector3(196.0, 30.2, 0.0), Basis(), 0.6, 0.05, Color(0.42, 0.42, 0.45), 14, 6)
	g.box("strip_red", Vector3(196.0, 31.15, 0.0), Vector3(0.22, 0.22, 0.22), Color.WHITE)
	# bow antenna cluster
	for k in 4:
		var zz := -1.8 + float(k) * 1.2
		g.strut("frame", Vector3(238.0, 23.2, zz), Vector3(238.0 + 2.0 - absf(zz) * 0.4, 26.4 - absf(zz) * 0.3, zz), 0.07, 0.07, Color(0.45, 0.45, 0.48))
	g.box("strip_cyan", Vector3(238.0, 23.1, 0.0), Vector3(0.3, 0.1, 5.0), Color.WHITE)

func _running_lights() -> void:
	var x := 16.0
	while x < 240.0:
		var b: float = lay.hull_half_width(x + 4.0)
		for side in [-1.0, 1.0]:
			g.box("strip_cyan", Vector3(x + 4.0, 13.0, side * (b - 0.55)), Vector3(7.2, 0.1, 0.1), Color.WHITE)
		x += 8.0
	# nav lights: port red / starboard green
	g.box("strip_red", Vector3(140.0, 13.6, -(lay.hull_half_width(140.0) - 0.4)), Vector3(0.5, 0.35, 0.2), Color.WHITE)
	g.box("strip_green", Vector3(140.0, 13.6, lay.hull_half_width(140.0) - 0.4), Vector3(0.5, 0.35, 0.2), Color.WHITE)
	# stern docking lights
	g.box("strip_amber", Vector3(1.0, 20.0, -10.0), Vector3(0.2, 0.2, 0.9), Color.WHITE)
	g.box("strip_amber", Vector3(1.0, 20.0, 10.0), Vector3(0.2, 0.2, 0.9), Color.WHITE)

func _lounge_reveal() -> void:
	# window reveal box connecting lounge glass (z=-44) to hull cut (z ~ -47.5)
	var y0 := 16.1; var y1 := 19.9
	var x0 := 199.9; var x1 := 222.1
	var zc := -47.3
	var col := Color.WHITE
	g.box("hull_inner", Vector3((x0 + x1) * 0.5, y1 + 0.1, (zc + -44.0) * 0.5), Vector3(x1 - x0, 0.2, -44.0 - zc), col)
	g.box("hull_inner", Vector3((x0 + x1) * 0.5, y0 - 0.1, (zc + -44.0) * 0.5), Vector3(x1 - x0, 0.2, -44.0 - zc), col)
	g.box("hull_inner", Vector3(x0 + 0.1, (y0 + y1) * 0.5, (zc + -44.0) * 0.5), Vector3(0.2, y1 - y0, -44.0 - zc), col)
	g.box("hull_inner", Vector3(x1 - 0.1, (y0 + y1) * 0.5, (zc + -44.0) * 0.5), Vector3(0.2, y1 - y0, -44.0 - zc), col)
	# mullion strips in the reveal
	for i in 5:
		var xx := lerpf(x0 + 1.0, x1 - 1.0, float(i) / 4.0)
		g.box("frame", Vector3(xx, (y0 + y1) * 0.5, (zc + -44.0) * 0.5), Vector3(0.14, y1 - y0, 3.4), Color(0.42, 0.42, 0.45))
	# bow viewport reveal frame around hull cut
	var bx := 261.0
	while bx < 275.0:
		var b: float = lay.hull_half_width(bx + 1.0) * 0.94
		g.box("frame", Vector3(bx + 1.0, 15.0, 0.0), Vector3(2.1, 0.3, 0.3), Color(0.42, 0.42, 0.45))
		bx += 2.0

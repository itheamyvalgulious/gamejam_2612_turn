extends RefCounted

const GeoKit = preload("res://src/kit.gd")
const ShipLayout = preload("res://src/layout.gd")

## Architectural shell: floor / ceiling slabs, walls with door & window
## openings, corridors, stairs, and the room-cell carver that lays out a zone's
## side rooms separated by service gaps.

var k: GeoKit
var L: ShipLayout


func _init(kit: GeoKit, lay: ShipLayout) -> void:
	k = kit
	L = lay


# ------------------------------------------------------------------ slabs ---
func slab(mat: String, x0: float, x1: float, z0: float, z1: float,
		y: float, thick := 0.3, holes: Array = []) -> void:
	k.hrange(y, y + thick)
	# holes: Array of Rect2 in XZ cut out of the slab
	var rects: Array = [Rect2(x0, z0, x1 - x0, z1 - z0)]
	for h in holes:
		rects = _subtract_all(rects, h)
	for r in rects:
		k.box(mat, Vector3(r.size.x, thick, r.size.y),
			Vector3(r.position.x + r.size.x * 0.5, y, r.position.y + r.size.y * 0.5))


static func _subtract_all(rects: Array, hole: Rect2) -> Array:
	var out := []
	for r: Rect2 in rects:
		if not r.intersects(hole):
			out.append(r)
			continue
		var i := r.intersection(hole)
		# left / right / top / bottom remainders
		if i.position.x > r.position.x:
			out.append(Rect2(r.position.x, r.position.y,
				i.position.x - r.position.x, r.size.y))
		if i.end.x < r.end.x:
			out.append(Rect2(i.end.x, r.position.y,
				r.end.x - i.end.x, r.size.y))
		if i.position.y > r.position.y:
			out.append(Rect2(i.position.x, r.position.y,
				i.size.x, i.position.y - r.position.y))
		if i.end.y < r.end.y:
			out.append(Rect2(i.position.x, i.end.y,
				i.size.x, r.end.y - i.end.y))
	return out


# ------------------------------------------------------------------ walls ---
## Wall spanning x0..x1 at fixed z, thickness t, y0..y1.
## openings: Array of [x_centre, width, sill_height_rel, height_rel, kind]
##   kind: "door" (frame+slit), "open" (bare), "win" (glass), "gate" (wide+frame)
func wall_x(mat: String, z: float, x0: float, x1: float, y0: float, y1: float,
		t := 0.25, openings: Array = []) -> void:
	k.hrange(y0, y1)
	var segs := _segments(x0, x1, y0, y1, openings)
	for s in segs:
		k.box(mat, Vector3(s[1] - s[0], s[3] - s[2], t),
			Vector3((s[0] + s[1]) * 0.5, (s[2] + s[3]) * 0.5, z))
	for o in openings:
		var cx: float = o[0]
		var w: float = o[1]
		var sy: float = y0 + o[2]
		var hy: float = y0 + o[2] + o[3]
		var kind: String = o[4] if o.size() > 4 else "door"
		_dress_x(cx, w, sy, hy, z, t, kind)


## Wall spanning z0..z1 at fixed x.
func wall_z(mat: String, x: float, z0: float, z1: float, y0: float, y1: float,
		t := 0.25, openings: Array = []) -> void:
	k.hrange(y0, y1)
	var segs := _segments(z0, z1, y0, y1, openings)
	for s in segs:
		k.box(mat, Vector3(t, s[3] - s[2], s[1] - s[0]),
			Vector3(x, (s[2] + s[3]) * 0.5, (s[0] + s[1]) * 0.5))
	for o in openings:
		var cx: float = o[0]
		var w: float = o[1]
		var sy: float = y0 + o[2]
		var hy: float = y0 + o[2] + o[3]
		var kind: String = o[4] if o.size() > 4 else "door"
		_dress_z(cx, w, sy, hy, x, t, kind)


## Carve a wall into solid boxes around openings. Returns [a0,a1,y0,y1] boxes.
static func _segments(p0: float, p1: float, y0: float, y1: float,
		opens: Array) -> Array:
	var xs := [p0, p1]
	for o in opens:
		xs.append(o[0] - o[1] * 0.5)
		xs.append(o[0] + o[1] * 0.5)
	xs.sort()
	var out := []
	for i in range(xs.size() - 1):
		var a: float = xs[i]
		var b: float = xs[i + 1]
		if b - a < 0.02:
			continue
		var mid := (a + b) * 0.5
		var covered := false
		for o in opens:
			if mid > o[0] - o[1] * 0.5 - 0.001 and mid < o[0] + o[1] * 0.5 + 0.001:
				# column under / over opening
				var sy: float = o[2]
				var hy: float = o[2] + o[3]
				if sy > 0.01:
					out.append([a, b, y0, y0 + sy])
				if y1 - (y0 + hy) > 0.01:
					out.append([a, b, y0 + hy, y1])
				covered = true
				break
		if not covered:
			out.append([a, b, y0, y1])
	return out


func _dress_x(cx: float, w: float, sy: float, hy: float, z: float,
		t: float, kind: String) -> void:
	k.hrange(sy, hy)
	if kind == "win":
		# glass pane flush in the hole
		k.box("glass", Vector3(w - 0.1, hy - sy - 0.1, 0.06),
			Vector3(cx, (sy + hy) * 0.5, z))
		return
	if kind == "open":
		# bare cut — used for room-side doorways that sit behind the
		# corridor wall's leaf; a frame out there just reads as a black
		# rectangle floating in the service gap
		return
	# frame: two jambs + lintel, flush with the wall so doorways read as
	# recesses rather than protruding black bars
	var jw := 0.24
	var depth := t + 0.04
	for sgn in [-1, 1]:
		k.boxb("metal_d", Vector3(jw, hy - sy, depth),
			Vector3(cx + sgn * (w * 0.5 - jw * 0.4), (sy + hy) * 0.5, z), 0.03)
	k.boxb("metal_d", Vector3(w, 0.24, depth),
		Vector3(cx, hy - 0.1, z), 0.03)
	if kind == "gate":
		# hazard threshold
		k.box("hazard", Vector3(w, 0.06, depth),
			Vector3(cx, sy + 0.03, z))
		# lit jamb edge strips so the portal reads from down the corridor —
		# thin low-energy bars; fat bright ones read as twin light pillars
		for sgn in [-1, 1]:
			k.box("u_light_c", Vector3(0.03, hy - sy - 0.4, 0.05),
				Vector3(cx + sgn * (w * 0.5 - 0.12), (sy + hy) * 0.5, z))
		return
	if kind == "open":
		return
	# closed door leaf: fills the opening except 8cm reveal all around and
	# spans the full wall depth — a thin leaf hides inside the reveal at
	# grazing angles and shows the dark gap through the doorway
	var dw := w - 0.16
	var lh := hy - sy - 0.16
	k.boxb("metal_d", Vector3(dw * 0.5 - 0.04, lh, depth),
		Vector3(cx - dw * 0.25 - 0.02, sy + lh * 0.5 + 0.06, z), 0.02)
	k.boxb("metal_d", Vector3(dw * 0.5 - 0.04, lh, depth),
		Vector3(cx + dw * 0.25 + 0.02, sy + lh * 0.5 + 0.06, z), 0.02)
	# centre strip: small accent bar above the leaf seam, not a full-height
	# pillar — tall strips read as white masts in corridor shots
	k.box("u_light_c", Vector3(0.04, 0.7, depth + 0.005),
		Vector3(cx, sy + lh - 0.35, z))
	# lock-pad indicator only — the metal_a housing stacked door-after-door
	# read as a continuous dark rail along the wall at waist height
	k.box("u_light_c", Vector3(0.06, 0.06, 0.1),
		Vector3(cx + w * 0.5 - 0.5, sy + 1.1, z))
	# lit jamb edges + transom: thin strips flush with the frame face —
	# fatter boxes that protrude read as a cage of white rails down the
	# corridor at grazing angles
	for sgn in [-1, 1]:
		k.box("u_light_c", Vector3(0.03, 1.3, depth + 0.005),
			Vector3(cx + sgn * (w * 0.5 - 0.06), sy + lh * 0.55 + 0.06, z))
	k.box("u_light_c", Vector3(w - 0.2, 0.035, depth + 0.005),
		Vector3(cx, hy - 0.16, z))


func _dress_z(cx: float, w: float, sy: float, hy: float, x: float,
		t: float, kind: String) -> void:
	k.hrange(sy, hy)
	if kind == "win":
		k.box("glass", Vector3(0.06, hy - sy - 0.1, w - 0.1),
			Vector3(x, (sy + hy) * 0.5, cx))
		return
	if kind == "open":
		return
	var jw := 0.24
	var depth := t + 0.04
	for sgn in [-1, 1]:
		k.boxb("metal_d", Vector3(depth, hy - sy, jw),
			Vector3(x, (sy + hy) * 0.5, cx + sgn * (w * 0.5 - jw * 0.4)), 0.03)
	k.boxb("metal_d", Vector3(depth, 0.24, w),
		Vector3(x, hy - 0.1, cx), 0.03)
	if kind == "gate":
		k.box("hazard", Vector3(depth, 0.06, w),
			Vector3(x, sy + 0.03, cx))
		for sgn in [-1, 1]:
			k.box("u_light_c", Vector3(0.05, hy - sy - 0.4, 0.03),
				Vector3(x, (sy + hy) * 0.5, cx + sgn * (w * 0.5 - 0.12)))
		return
	if kind == "open":
		return
	var dw := w - 0.16
	var lh := hy - sy - 0.16
	k.boxb("metal_d", Vector3(depth, lh, dw * 0.5 - 0.04),
		Vector3(x, sy + lh * 0.5 + 0.06, cx - dw * 0.25 - 0.02), 0.02)
	k.boxb("metal_d", Vector3(depth, lh, dw * 0.5 - 0.04),
		Vector3(x, sy + lh * 0.5 + 0.06, cx + dw * 0.25 + 0.02), 0.02)
	k.box("u_light_c", Vector3(depth + 0.005, 0.7, 0.04),
		Vector3(x, sy + lh - 0.35, cx))
	# lock-pad indicator only (see _dress_x: metal housing rows → black rail)
	k.box("u_light_c", Vector3(0.1, 0.06, 0.06),
		Vector3(x, sy + 1.1, cx + w * 0.5 - 0.5))
	for sgn in [-1, 1]:
		k.box("u_light_c", Vector3(depth + 0.005, 1.3, 0.03),
			Vector3(x, sy + lh * 0.55 + 0.06, cx + sgn * (w * 0.5 - 0.06)))
	k.box("u_light_c", Vector3(depth + 0.005, 0.035, w - 0.2),
		Vector3(x, hy - 0.16, cx))


# ------------------------------------------------------------------ stair ---
## Straight stair along -Z rising from (x±w/2, y0, z0) to (x±w/2, y1, z1).
func stair(mat: String, xc: float, z0: float, z1: float, y0: float, y1: float,
		w: float) -> void:
	var rise := y1 - y0
	var run := absf(z1 - z0)
	var steps := maxi(4, int(run / 0.5))
	var riser := rise / steps
	var tread := run / steps
	for i in steps:
		# walking toward -Z
		var za := z0 - i * tread
		var zb := za - tread
		var yh := y0 + (i + 1) * riser
		k.box(mat, Vector3(w, riser + 0.08, tread + 0.02),
			Vector3(xc, yh - (riser + 0.08) * 0.5, (za + zb) * 0.5))
	# side stringers
	var slope := atan2(rise, run)
	var len := sqrt(rise * rise + run * run)
	var b := Basis(Vector3.RIGHT, slope)
	k.push(Transform3D(b, Vector3(xc - w * 0.5 + 0.12, y0 + rise * 0.5 - 0.3, (z0 + z1) * 0.5)))
	k.box("metal_a", Vector3(0.16, 0.5, len + 0.4))
	k.pop()
	k.push(Transform3D(b, Vector3(xc + w * 0.5 - 0.12, y0 + rise * 0.5 - 0.3, (z0 + z1) * 0.5)))
	k.box("metal_a", Vector3(0.16, 0.5, len + 0.4))
	k.pop()
	# handrails (two heights, both sides)
	for sgn in [-1, 1]:
		for hh in [0.95]:
			var pa := Vector3(xc + sgn * (w * 0.5 - 0.12), y0 + hh, z0)
			var pb := Vector3(xc + sgn * (w * 0.5 - 0.12), y1 + hh, z1)
			k.tube("metal_d", [pa, pb], 0.035, 6, true)
			# rail posts
			var n := 6
			for i in range(n + 1):
				var t := float(i) / n
				var px: float = lerpf(pa.x, pb.x, t)
				var py: float = lerpf(pa.y, pb.y, t) - hh
				var pz: float = lerpf(pa.z, pb.z, t)
				k.cyl("metal_d", 0.02, 0.02, hh, 6, Vector3(px, py, pz), true)


## Balustrade along x or z edges.
func rail(mat: String, a0: Vector3, a1: Vector3, h := 1.05, pitch := 1.6) -> void:
	var top := [a0 + Vector3(0, h, 0), a1 + Vector3(0, h, 0)]
	k.tube(mat, top, 0.04, 6, true)
	k.tube(mat, [a0 + Vector3(0, h * 0.55, 0), a1 + Vector3(0, h * 0.55, 0)], 0.02, 6, true)
	var n := maxi(2, int(a0.distance_to(a1) / pitch))
	for i in range(n + 1):
		var p := a0.lerp(a1, float(i) / n)
		k.cyl(mat, 0.025, 0.025, h, 6, p, true)


# ------------------------------------------------------------ room cells ----
## Build one room shell inside a zone wing.
## rect: Rect2(x0, z0, w, d); door_side: which wall faces the corridor
## ("xp","xn","zp","zn"); floor/ceil inherited. Returns nothing.
func room(mat_wall: String, mat_floor: String, mat_ceil: String,
		r: Rect2, y0: float, y1: float, door_side: String,
		door_w := 2.2, extras := {}) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	slab(mat_floor, x0, x1, z0, z1, y0, 0.25)
	slab(mat_ceil, x0, x1, z0, z1, y1, 0.2)
	var door := []
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# room-side doorway stays "open": the corridor wall already carries the
	# leaf — a second leaf 2 m deep would read as nested black frames
	match door_side:
		"xp":
			door = [[cz, door_w, 0.0, y1 - y0 - 0.7, "open"]]
			wall_z(mat_wall, x1, z0, z1, y0, y1, 0.22, door)
		"xn":
			door = [[cz, door_w, 0.0, y1 - y0 - 0.7, "open"]]
			wall_z(mat_wall, x0, z0, z1, y0, y1, 0.22, door)
		"zp":
			door = [[cx, door_w, 0.0, y1 - y0 - 0.7, "open"]]
			wall_x(mat_wall, z1, x0, x1, y0, y1, 0.22, door)
		"zn":
			door = [[cx, door_w, 0.0, y1 - y0 - 0.7, "open"]]
			wall_x(mat_wall, z0, x0, x1, y0, y1, 0.22, door)
	# other three walls solid (service gap lives between neighbours)
	if door_side != "xp":
		wall_z(mat_wall, x1, z0, z1, y0, y1, 0.18)
	if door_side != "xn":
		wall_z(mat_wall, x0, z0, z1, y0, y1, 0.18)
	if door_side != "zp":
		wall_x(mat_wall, z1, x0, x1, y0, y1, 0.18)
	if door_side != "zn":
		wall_x(mat_wall, z0, x0, x1, y0, y1, 0.18)


## A simple corridor segment: floor + ceiling + two side walls with optional
## door list per side. Returns the corridor centre line for props.
func corridor(mat_wall: String, mat_floor: String, mat_ceil: String,
		x0: float, x1: float, z0: float, z1: float, y0: float, y1: float,
		doors_l: Array = [], doors_r: Array = [], open_ends := "") -> void:
	slab(mat_floor, x0, x1, z0, z1, y0, 0.25)
	slab(mat_ceil, x0, x1, z0, z1, y1, 0.22)
	wall_z(mat_wall, x0, z0, z1, y0, y1, 0.22, doors_l)
	wall_z(mat_wall, x1, z0, z1, y0, y1, 0.22, doors_r)
	if not "z0" in open_ends:
		wall_x(mat_wall, z0, x0, x1, y0, y1, 0.22)
	if not "z1" in open_ends:
		wall_x(mat_wall, z1, x0, x1, y0, y1, 0.22)


## Ceiling light bar run along a corridor.
func light_run(mat: String, x: float, z0: float, z1: float, y: float,
		w := 0.3, step := 4.0) -> void:
	var n := maxi(1, int(absf(z1 - z0) / step))
	for i in range(n + 1):
		var z := lerpf(z0, z1, float(i) / n)
		k.box(mat, Vector3(w, 0.07, step * 0.62), Vector3(x, y, z))


func light_run_x(mat: String, z: float, x0: float, x1: float, y: float,
		w := 0.3, step := 4.0) -> void:
	var n := maxi(1, int(absf(x1 - x0) / step))
	for i in range(n + 1):
		var x := lerpf(x0, x1, float(i) / n)
		k.box(mat, Vector3(step * 0.62, 0.07, w), Vector3(x, y, z))

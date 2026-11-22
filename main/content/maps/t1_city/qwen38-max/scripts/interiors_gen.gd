class_name InteriorsGen
extends RefCounted
## Interior v2: per-building-type floor plans (core with elevators/stairs/WC/
## risers, corridors, room partitions with door openings, type-specific
## furniture that varies by floor), lobby & mechanical floors, streamed per
## chunk around the camera with a frame-time budget.

const R_FULL := 240.0
const R_MED := 650.0

func tier_for(dist: float) -> int:
	if dist < R_FULL:
		return 0
	if dist < R_MED:
		return 1
	return 2

# ---------------------------------------------------------------- public API

func build_building(gen: CityGen, t: Dictionary, cam: Vector3) -> MeshBuf:
	var b := MeshBuf.new()
	var frame: Transform3D = t.frame
	var inv := frame.affine_inverse()
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in t.fp:
		var lp: Vector3 = inv * Vector3(p.x, 0, p.y)
		mn.x = minf(mn.x, lp.x)
		mn.y = minf(mn.y, lp.z)
		mx.x = maxf(mx.x, lp.x)
		mx.y = maxf(mx.y, lp.z)
	var w := mx.x - mn.x
	var d := mx.y - mn.y
	if w < 8.0 or d < 8.0:
		return b
	var ctr := Vector2((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5)
	var fh: float = t.fh
	var h: float = t.h
	var sd: float = t.seed
	var lobby_only: bool = t.get("lobby", false)
	var center_w: Vector3 = frame * Vector3(ctr.x, 0, ctr.y)
	var dist := (center_w - cam).length()
	var tier := tier_for(dist)
	if lobby_only:
		tier = mini(tier, 1)
	var floors := int(h / fh)
	if lobby_only:
		floors = 1
	var fmax := floors
	if tier == 0 and not lobby_only:
		fmax = mini(floors, 14)
	for f in fmax:
		var y := float(f) * fh + 0.12
		if y > h - 1.0:
			break
		var frng := RandomNumberGenerator.new()
		frng.seed = int(sd * 131.0) + f * 7919
		var kind := "std"
		if f == 0:
			kind = "lobby"
		elif f % 12 == 11:
			kind = "mech"
		elif frng.randf() < 0.22:
			kind = "open"
		_gen_floor(b, frame, mn, mx, ctr, w, d, y, fh, kind, tier, frng, sd, f, t, f == fmax - 1)
	return b

# ---------------------------------------------------------------- floor plan

func _gen_floor(b: MeshBuf, frame: Transform3D, mn: Vector2, mx: Vector2,
		ctr: Vector2, w: float, d: float, y: float, fh: float, kind: String,
		tier: int, rng: RandomNumberGenerator, sd: float, f: int, t: Dictionary,
		is_top := false) -> void:
	var wall_c := Color(0.32, 0.31, 0.29)
	var floor_c := Color(0.20, 0.19, 0.18)
	var emis_c := Color(1.0, 0.88, 0.70)
	# slab
	_quad(b, frame, Vector2(mn.x, mn.y), Vector2(mx.x, mn.y), Vector2(mx.x, mx.y), Vector2(mn.x, mx.y), y, floor_c, 0.0)
	# ceiling light strips (never on the top generated floor: no slab above)
	if (tier == 0 or kind == "lobby") and not is_top:
		for ls in 3:
			var lz := mn.y + (float(ls) + 0.5) * (mx.y - mn.y) / 3.0
			_quad(b, frame, Vector2(mn.x + 1.5, lz - 0.5), Vector2(mx.x - 1.5, lz - 0.5),
				Vector2(mx.x - 1.5, lz + 0.5), Vector2(mn.x + 1.5, lz + 0.5), y + fh - 0.30, emis_c, 0.8)
	# columns grid
	var cs := 8.0
	var nx := int(w / cs)
	var nz := int(d / cs)
	for i in range(1, nx + 1):
		for j in range(1, nz + 1):
			var px := mn.x + float(i) * w / float(nx + 1)
			var pz := mn.y + float(j) * d / float(nz + 1)
			_box(b, frame, Vector2(px, pz), Vector2(0.45, 0.45), y, fh - 0.3, Color(0.28, 0.28, 0.30), 0.0)
	# core block: elevators + stairs + wc + risers
	var core_w := clampf(w * 0.28, 5.0, 12.0)
	var core_d := clampf(d * 0.34, 4.5, 10.0)
	var core_c := ctr + Vector2(0.0, -d * 0.18)
	var n_e := int(clampf(w * d / 900.0, 2, 6))
	var ew := 2.5
	for e in n_e:
		var ex := core_c.x - core_w * 0.5 + ew * 0.5 + float(e) * (core_w / float(n_e))
		_room_shell(b, frame, Vector2(ex - ew * 0.5, core_c.y - 1.4), Vector2(ex + ew * 0.5, core_c.y + 1.4), y, fh - 0.3, wall_c, 0.0, -1.0, 0.0)
		# elevator door glow on south face
		_quad(b, frame, Vector2(ex - 0.9, core_c.y - 1.42), Vector2(ex + 0.9, core_c.y - 1.42),
			Vector2(ex + 0.9, core_c.y - 1.42), Vector2(ex - 0.9, core_c.y - 1.42), y + 1.1, Color(0.7, 0.8, 0.9), 1.0, true)
	# stairs (two), with steps at full detail
	for sgn in [-1.0, 1.0]:
		var sgn_f := float(sgn)
		var sx := core_c.x + sgn_f * (core_w * 0.5 + 1.8)
		var sz := core_c.y
		_room_shell(b, frame, Vector2(sx - 1.6, sz - 2.8), Vector2(sx + 1.6, sz + 2.8), y, fh - 0.3, wall_c, 0.0, -1.0, 0.0)
		if tier == 0:
			for st in 8:
				var sy := y + 0.18 * float(st)
				var szp := sz - 2.4 + float(st) * 0.6
				_box(b, frame, Vector2(sx, szp), Vector2(2.6, 0.6), sy, 0.18, Color(0.3, 0.3, 0.32), 0.0)
	# wc room with stalls
	var wc_c := core_c + Vector2(core_w * 0.5 + 4.6, 0.0)
	if wc_c.x + 2.2 < mx.x - 0.5:
		_room_shell(b, frame, Vector2(wc_c.x - 2.2, wc_c.y - 3.0), Vector2(wc_c.x + 2.2, wc_c.y + 3.0), y, fh - 0.3, wall_c, 0.0, 0.9, 1.0)
		if tier == 0:
			for k in 3:
				var zp := wc_c.y - 2.0 + float(k) * 2.0
				_quad(b, frame, Vector2(wc_c.x - 1.8, zp), Vector2(wc_c.x + 0.4, zp), Vector2(wc_c.x + 0.4, zp), Vector2(wc_c.x - 1.8, zp), y + 1.8, wall_c, 0.0, true)
				_box(b, frame, Vector2(wc_c.x + 1.4, zp + 0.5), Vector2(0.5, 0.7), y, 0.45, Color(0.7, 0.7, 0.72), 0.0)
	# risers (pipe shafts)
	for k in 2:
		var rx := mn.x + 1.0 + float(k) * (w - 2.0)
		_box(b, frame, Vector2(rx, mx.y - 1.0), Vector2(1.1, 1.1), y, fh - 0.3, Color(0.25, 0.25, 0.27), 0.0)

	if kind == "lobby":
		_lobby(b, frame, mn, mx, ctr, w, d, y, fh, rng, tier)
	elif kind == "mech":
		_mech_floor(b, frame, mn, mx, w, d, y, fh, rng)
	elif kind == "open":
		_open_office(b, frame, mn, mx, w, d, y, fh, rng, tier)
	else:
		_rooms(b, frame, mn, mx, ctr, w, d, y, fh, rng, tier, sd, f, t)

# ---------------------------------------------------------------- room layouts

func _rooms(b: MeshBuf, frame: Transform3D, mn: Vector2, mx: Vector2, ctr: Vector2,
		w: float, d: float, y: float, fh: float, rng: RandomNumberGenerator,
		tier: int, sd: float, f: int, t: Dictionary) -> void:
	var wall_c := Color(0.32, 0.31, 0.29)
	# corridor along center-x (double loaded): walls with door openings
	var cor_w := 1.7
	var zc := ctr.y + d * 0.10
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var zz := zc + side_f * cor_w * 0.5
		var x := mn.x + 1.0
		while x < mx.x - 4.0:
			var rw := rng.randf_range(4.0, 7.0)
			rw = minf(rw, mx.x - 1.0 - x)
			if rw < 3.0:
				break
			var door_at := x + rw * rng.randf_range(0.3, 0.7)
			_wall_door(b, frame, Vector2(x, zz), Vector2(x + rw, zz), y, fh - 0.35, wall_c, door_at, 1.0)
			if tier == 0:
				_furnish(b, frame, Vector2(x + rw * 0.5, zz + side_f * (d * 0.25)), Vector2(rw, d * 0.4), y, fh, rng, t, f)
			x += rw
	# corridor side rooms opposite band (single loaded near facade)
	if tier == 0 and rng.randf() < 0.6:
		var x2 := mn.x + 2.0
		while x2 < mx.x - 6.0:
			var rw2 := rng.randf_range(5.0, 9.0)
			rw2 = minf(rw2, mx.x - 2.0 - x2)
			if rw2 < 4.0:
				break
			_wall_door(b, frame, Vector2(x2, zc - cor_w * 0.5 - 0.0), Vector2(x2, zc - cor_w * 0.5 - d * 0.22), y, fh - 0.35, wall_c, zc - cor_w * 0.5 - d * 0.11, 1.0)
			x2 += rw2

func _furnish(b: MeshBuf, frame: Transform3D, c: Vector2, sz: Vector2, y: float,
		fh: float, rng: RandomNumberGenerator, t: Dictionary, f: int) -> void:
	var dtype: int = t.get("dtype", 0)
	var style: int = t.get("style", 0)
	var r := rng.randf()
	if style == 2 or dtype == 2 or dtype == 3:
		# apartment: bed / sofa / kitchen counter / table
		if r < 0.35:
			_box(b, frame, c + Vector2(-sz.x * 0.2, 0), Vector2(2.0, 1.6), y, 0.5, Color(0.45, 0.4, 0.38), 0.0)
			_box(b, frame, c + Vector2(-sz.x * 0.2, -0.9), Vector2(2.0, 0.3), y + 0.5, 0.35, Color(0.6, 0.6, 0.62), 0.0)
		elif r < 0.6:
			_box(b, frame, c, Vector2(2.2, 0.9), y, 0.45, Color(0.3, 0.32, 0.4), 0.0)
			_box(b, frame, c + Vector2(0, 1.2), Vector2(1.2, 0.6), y, 0.4, Color(0.4, 0.35, 0.3), 0.0)
		elif r < 0.8:
			_box(b, frame, c + Vector2(0, sz.y * 0.35), Vector2(sz.x * 0.8, 0.65), y, 0.9, Color(0.35, 0.33, 0.3), 0.0)
			_box(b, frame, c + Vector2(sz.x * 0.2, sz.y * 0.35 - 0.5), Vector2(0.5, 0.4), y + 0.9, 0.5, Color(0.5, 0.5, 0.52), 0.0)
		else:
			_box(b, frame, c, Vector2(1.6, 0.9), y, 0.72, Color(0.4, 0.36, 0.3), 0.0)
			for k in 4:
				var a := float(k) * PI * 0.5 + 0.4
				_box(b, frame, c + Vector2(cos(a), sin(a)) * 1.1, Vector2(0.45, 0.45), y, 0.45, Color(0.3, 0.3, 0.32), 0.0)
	else:
		# office: desks with monitors / meeting table / shelves
		if r < 0.5:
			for k in 2:
				var dx := c.x + (float(k) - 0.5) * 2.4
				_box(b, frame, Vector2(dx, c.y), Vector2(1.6, 0.8), y, 0.72, Color(0.32, 0.32, 0.35), 0.0)
				_quad(b, frame, Vector2(dx - 0.35, c.y - 0.1), Vector2(dx + 0.35, c.y - 0.1), Vector2(dx + 0.35, c.y - 0.1), Vector2(dx - 0.35, c.y - 0.1), y + 1.05, Color(0.55, 0.75, 1.0), 1.0, true)
				_box(b, frame, Vector2(dx, c.y + 0.8), Vector2(0.5, 0.5), y, 0.5, Color(0.15, 0.15, 0.18), 0.0)
		elif r < 0.7:
			_box(b, frame, c, Vector2(3.0, 1.2), y, 0.72, Color(0.35, 0.33, 0.3), 0.0)
			for k in 6:
				var a := float(k) / 6.0 * TAU
				_box(b, frame, c + Vector2(cos(a) * 2.0, sin(a) * 1.2), Vector2(0.45, 0.45), y, 0.45, Color(0.2, 0.2, 0.24), 0.0)
		elif r < 0.85:
			_box(b, frame, c + Vector2(0, sz.y * 0.4), Vector2(sz.x * 0.7, 0.4), y, 1.8, Color(0.3, 0.28, 0.26), 0.0)
		else:
			_box(b, frame, c, Vector2(0.8, 0.8), y, 1.2, Color(0.1, 0.2, 0.08), 0.0)  # plant

func _open_office(b: MeshBuf, frame: Transform3D, mn: Vector2, mx: Vector2,
		w: float, d: float, y: float, fh: float, rng: RandomNumberGenerator, tier: int) -> void:
	if tier != 0:
		return
	var rows := int(d / 5.0)
	for r in rows:
		var zz := mn.y + 3.0 + float(r) * 5.0
		if zz > mx.y - 3.0:
			break
		var cols := int(w / 3.2)
		for cix in cols:
			var xx := mn.x + 3.0 + float(cix) * 3.2
			if xx > mx.x - 3.0:
				break
			if rng.randf() < 0.3:
				continue
			_box(b, frame, Vector2(xx, zz), Vector2(1.6, 0.8), y, 0.72, Color(0.32, 0.32, 0.35), 0.0)
			if rng.randf() < 0.7:
				_quad(b, frame, Vector2(xx - 0.3, zz - 0.1), Vector2(xx + 0.3, zz - 0.1), Vector2(xx + 0.3, zz - 0.1), Vector2(xx - 0.3, zz - 0.1), y + 1.05, Color(0.55, 0.75, 1.0), 1.0, true)

func _mech_floor(b: MeshBuf, frame: Transform3D, mn: Vector2, mx: Vector2,
		w: float, d: float, y: float, fh: float, rng: RandomNumberGenerator) -> void:
	for k in 4:
		var zz := mn.y + 2.0 + float(k) * (d - 4.0) / 3.0
		_pipe(b, frame, Vector2(mn.x + 1.0, zz), Vector2(mx.x - 1.0, zz), y + 0.5 + float(k % 2) * 0.4, 0.18)
	for k in 2:
		var px := mn.x + w * (0.3 + 0.4 * float(k))
		_cyl(b, frame, Vector2(px, mn.y + d * 0.5), 1.4, 2.6, y, Color(0.4, 0.42, 0.45))
	_box(b, frame, Vector2(mx.x - 2.5, mn.y + 2.0), Vector2(1.6, 1.0), y, 1.4, Color(0.3, 0.32, 0.35), 0.0)

func _lobby(b: MeshBuf, frame: Transform3D, mn: Vector2, mx: Vector2, ctr: Vector2,
		w: float, d: float, y: float, fh: float, rng: RandomNumberGenerator, tier: int) -> void:
	# reception desk + back wall glow
	var rc := ctr + Vector2(0, -d * 0.1)
	_box(b, frame, rc, Vector2(4.5, 1.1), y, 1.1, Color(0.25, 0.22, 0.2), 0.0)
	_quad(b, frame, Vector2(rc.x - 3.0, rc.y - 1.4), Vector2(rc.x + 3.0, rc.y - 1.4),
		Vector2(rc.x + 3.0, rc.y - 1.4), Vector2(rc.x - 3.0, rc.y - 1.4), y + 2.2, Color(1.0, 0.8, 0.55), 1.0, true)
	# lounge
	for k in 3:
		var a := float(k) * 2.1 + 0.5
		var lc := ctr + Vector2(cos(a), sin(a)) * Vector2(w * 0.28, d * 0.28)
		_box(b, frame, lc, Vector2(2.2, 0.9), y, 0.45, Color(0.3, 0.32, 0.4), 0.0)
		_box(b, frame, lc + Vector2(0, -0.6), Vector2(2.2, 0.25), y + 0.45, 0.5, Color(0.3, 0.32, 0.4), 0.0)
	# plants
	for k in 4:
		var pc := Vector2(mn.x + 2.0 + float(k) * (w - 4.0) / 3.0, mx.y - 2.0)
		_box(b, frame, pc, Vector2(0.9, 0.9), y, 1.4, Color(0.08, 0.18, 0.07), 0.0)
	# polished floor sheen strip (emissive guide line)
	_quad(b, frame, Vector2(ctr.x - 0.15, mn.y + 1.0), Vector2(ctr.x + 0.15, mn.y + 1.0),
		Vector2(ctr.x + 0.15, mx.y - 1.0), Vector2(ctr.x - 0.15, mx.y - 1.0), y + 0.02, Color(0.9, 0.75, 0.5), 1.0)

# ---------------------------------------------------------------- primitives

func _lw(frame: Transform3D, p: Vector2, y: float) -> Vector3:
	return frame * Vector3(p.x, y, p.y)

func _quad(b: MeshBuf, frame: Transform3D, a: Vector2, bq: Vector2, c: Vector2,
		d: Vector2, y: float, col: Color, emis: float, vert := false) -> void:
	if vert:
		var pa := _lw(frame, a, y - 0.9)
		var pb := _lw(frame, bq, y - 0.9)
		var pc := _lw(frame, c, y + 0.9)
		var pd := _lw(frame, d, y + 0.9)
		var nn := (pb - pa).cross(pc - pa).normalized()
		b.quad_o(pa, pb, pc, pd, nn, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), Vector2(emis, 0), col)
	else:
		b.quad_o(_lw(frame, a, y), _lw(frame, bq, y), _lw(frame, c, y), _lw(frame, d, y),
			Vector3.UP, PackedVector2Array([a * 0.2, bq * 0.2, c * 0.2, d * 0.2]), Vector2(emis, 0), col)

func _box(b: MeshBuf, frame: Transform3D, c2: Vector2, sz: Vector2, y: float,
		hgt: float, col: Color, emis: float) -> void:
	var xf := Transform3D(frame.basis, _lw(frame, c2, y + hgt * 0.5))
	b.box(Vector3.ZERO, Vector3(sz.x, hgt, sz.y), Vector2(emis, 0), col, 0.4, xf)

func _cyl(b: MeshBuf, frame: Transform3D, c2: Vector2, r: float, hgt: float,
		y: float, col: Color) -> void:
	var xf := Transform3D(frame.basis, _lw(frame, c2, y))
	b.cylinder(Vector3.ZERO, r, r, hgt, 10, xf, Vector2.ZERO, col)

func _pipe(b: MeshBuf, frame: Transform3D, a: Vector2, bq: Vector2, y: float, r: float) -> void:
	var pa := _lw(frame, a, y)
	var pb := _lw(frame, bq, y)
	var d := pb - pa
	var ln := d.length()
	var xf := Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), pa)
	b.cylinder(Vector3.ZERO, r, r, ln, 6, xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO), Vector2.ZERO, Color(0.4, 0.4, 0.44))

func _room_shell(b: MeshBuf, frame: Transform3D, a: Vector2, c: Vector2, y: float,
		hgt: float, col: Color, emis: float, door_side: float, door_w: float) -> void:
	# 4 walls; door_side -1 = opening on south wall center
	var m1 := Vector2(c.x, a.y)
	var m2 := Vector2(a.x, c.y)
	if door_side < 0.0:
		var dm := (a.x + c.x) * 0.5
		_wall_door(b, frame, a, m1, y, hgt, col, dm, door_w)
		_quad(b, frame, m1, c, c, m1, y, col, emis, true) if false else null
		b.quad_o(_lw(frame, m1, y), _lw(frame, c, y), _lw(frame, c, y + hgt), _lw(frame, m1, y + hgt),
			Vector3.RIGHT, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), Vector2(emis, 0), col)
		b.quad_o(_lw(frame, c, y), _lw(frame, m2, y), _lw(frame, m2, y + hgt), _lw(frame, c, y + hgt),
			Vector3.UP.cross(Vector3.RIGHT), PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), Vector2(emis, 0), col)
		b.quad_o(_lw(frame, m2, y), _lw(frame, a, y), _lw(frame, a, y + hgt), _lw(frame, m2, y + hgt),
			Vector3.RIGHT, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), Vector2(emis, 0), col)
	else:
		_wall_door(b, frame, a, m1, y, hgt, col, -10.0, 0.0)
		_wall_door(b, frame, m1, c, y, hgt, col, -10.0, 0.0)
		_wall_door(b, frame, c, m2, y, hgt, col, -10.0, 0.0)
		_wall_door(b, frame, m2, a, y, hgt, col, -10.0, 0.0)

func _wall_door(b: MeshBuf, frame: Transform3D, a: Vector2, bq: Vector2, y: float,
		hgt: float, col: Color, door_pos: float, door_w: float) -> void:
	# wall from a to bq (axis aligned), with optional door gap at door_pos along x or y
	var horiz := absf(bq.x - a.x) >= absf(bq.y - a.y)
	var l0 := (a.x if horiz else a.y)
	var l1 := (bq.x if horiz else bq.y)
	if l1 < l0:
		var tmp := l0
		l0 = l1
		l1 = tmp
	var segs := []
	if door_w > 0.1 and door_pos > l0 and door_pos < l1:
		segs.append([l0, door_pos - door_w * 0.5])
		segs.append([door_pos + door_w * 0.5, l1])
	else:
		segs.append([l0, l1])
	for sg in segs:
		var s0: float = sg[0]
		var s1: float = sg[1]
		if s1 - s0 < 0.05:
			continue
		var pa: Vector2 = Vector2(s0, a.y) if horiz else Vector2(a.x, s0)
		var pb: Vector2 = Vector2(s1, a.y) if horiz else Vector2(bq.x, s1)
		var wa := _lw(frame, pa, y)
		var wb := _lw(frame, pb, y)
		var nn := (wb - wa).cross(Vector3.UP).normalized()
		b.quad_o(wa, wb, wb + Vector3.UP * hgt, wa + Vector3.UP * hgt, nn,
			PackedVector2Array([Vector2(0, 0), Vector2(s1 - s0, 0), Vector2(s1 - s0, hgt), Vector2(0, hgt)]),
			Vector2(0, 0), col)
		# header above door
		if door_w > 0.1 and sg == segs[0] and segs.size() > 1:
			continue


## CityPlan — deterministic procedural layout of a 3.2 x 3.2 km cyberpunk city
## (10.24 km²), incl. road network, canal, diagonal boulevard, districts,
## blocks, lots and building briefs.
class_name CityPlan
extends RefCounted

const HALF := 1600.0
const CELL := 160.0
const SIDEWALK := 4.2

enum { CBD, COMMERCIAL, RESIDENTIAL, CAMPUS, INDUSTRIAL, WATERFRONT, MIXED, PARK }

enum { K_OFFICE, K_TOWER, K_APARTMENT, K_HOUSE, K_MALL, K_SHOP, K_SCHOOL,
	K_WAREHOUSE, K_FACTORY, K_PARKING, K_HOTEL, K_HOSPITAL,
	K_TWIST, K_COOLING, K_WHEEL }

const DNAME := ["CBD", "commercial", "residential", "campus", "industrial",
	"waterfront", "mixed", "park"]

class Road:
	var path := PackedVector2Array()
	var w := 16.0
	var cls := 0        # 0 lane, 1 street, 2 avenue, 3 boulevard
	var vertical := true

class Block:
	var poly := PackedVector2Array()
	var district := 0
	var water := false
	var park := false
	var downtown := 0.0

class Bld:
	var id := 0
	var poly := PackedVector2Array()
	var cx := 0.0
	var cz := 0.0
	var h := 20.0
	var floors := 5
	var kind := 0
	var style := 0.0
	var district := 0
	var sd := 0.0
	var podium := 0.0      # podium height (0 = none)
	var tower_scale := 1.0
	var chunk := Vector2i.ZERO
	var landmark := false
	var roofflag := 0
	var ghost := false

var rng := H.rng(97731, 3301)
var roads: Array = []
var blocks: Array = []
var blds: Array = []
var xlines: Array = []
var zlines: Array = []
var river_pts := PackedVector2Array()
var river_w := 96.0
var diagonal := PackedVector2Array()
var seed := 1337
var wheel_pos := Vector2.ZERO
var wheel_r := 0.0

# stats
var lot_count := 0

func generate(sd := 1337) -> void:
	seed = sd
	rng = H.rng(sd, 7717, 991)
	_make_lines()
	_make_roads()
	_make_blocks()
	_make_river()
	_make_diagonal()
	_place_lots()
	_place_landmarks()
	_place_structures()
	var kept := []
	for b in blds:
		if b.ghost:
			continue
		b.chunk = Vector2i(int(floor((b.cx + HALF) / CELL)), int(floor((b.cz + HALF) / CELL)))
		kept.append(b)
	blds = kept

func _make_lines() -> void:
	xlines.clear()
	zlines.clear()
	for i in 21:
		var x := -HALF + i * CELL
		var w := _road_w(i)
		if i > 0 and i < 20:
			x += rng.randf_range(-4.5, 4.5)
		xlines.append({"p": x, "w": w})
		var z := -HALF + i * CELL
		if i > 0 and i < 20:
			z += rng.randf_range(-4.5, 4.5)
		zlines.append({"p": z, "w": w})

func _road_w(i: int) -> float:
	if i % 4 == 0:
		return 34.0
	if i % 2 == 0:
		return 21.0
	return 13.0

func _make_roads() -> void:
	for i in xlines.size():
		var x: float = xlines[i]["p"]
		var w: float = xlines[i]["w"]
		var r := Road.new()
		r.path = PackedVector2Array([Vector2(x, -HALF), Vector2(x, HALF)])
		r.w = w
		r.cls = 3 if w > 30.0 else (2 if w > 18.0 else 1)
		r.vertical = true
		roads.append(r)
	for i in zlines.size():
		var z: float = zlines[i]["p"]
		var w: float = zlines[i]["w"]
		var r := Road.new()
		r.path = PackedVector2Array([Vector2(-HALF, z), Vector2(HALF, z)])
		r.w = w
		r.cls = 3 if w > 30.0 else (2 if w > 18.0 else 1)
		r.vertical = false
		roads.append(r)

func river_x(_z: float) -> float:
	return 962.0

func _make_river() -> void:
	river_pts.clear()
	var z := -HALF - 60.0
	while z <= HALF + 60.0:
		river_pts.append(Vector2(river_x(z), z))
		z += 40.0

func _make_diagonal() -> void:
	diagonal = PackedVector2Array([
		Vector2(-HALF - 80.0, -1420.0),
		Vector2(-640.0, -360.0),
		Vector2(120.0, 180.0),
		Vector2(940.0, 520.0),
		Vector2(HALF + 80.0, 760.0),
	])
	var r := Road.new()
	r.path = diagonal
	r.w = 40.0
	r.cls = 3
	r.vertical = false
	roads.append(r)

func _make_blocks() -> void:
	blocks.clear()
	for i in 20:
		for j in 20:
			var x0: float = xlines[i]["p"] + xlines[i]["w"] * 0.5
			var x1: float = xlines[i + 1]["p"] - xlines[i + 1]["w"] * 0.5
			var z0: float = zlines[j]["p"] + zlines[j]["w"] * 0.5
			var z1: float = zlines[j + 1]["p"] - zlines[j + 1]["w"] * 0.5
			if x1 - x0 < 30.0 or z1 - z0 < 30.0:
				continue
			var rect := PackedVector2Array([
				Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
			var c := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			var dist := district_at(c.x, c.y)
			var dt := downtown_factor(c.x, c.y)
			# diagonal boulevard cut
			for sp in _cut_corridor(rect, diagonal, 24.0):
				if absf(Poly.area(sp)) < 300.0:
					continue
				# canal cut (axis aligned strip)
				_add_with_canal(sp, dist, dt)

func _add_with_canal(p: PackedVector2Array, dist: int, dt: float) -> void:
	var rx := river_x(0.0)
	var l := rx - river_w * 0.5
	var r := rx + river_w * 0.5
	var bb := Poly.bbox(p)
	if bb.position.x > l and bb.end.x < r:
		var wb := Block.new()
		wb.poly = p
		wb.water = true
		wb.district = WATERFRONT
		blocks.append(wb)
		return
	if bb.end.x < l or bb.position.x > r:
		var b2 := Block.new()
		b2.poly = p
		b2.district = dist
		b2.downtown = dt
		blocks.append(b2)
		return
	var west := Poly.clip(p, Vector2(l, 0), Vector2.RIGHT)
	var east := Poly.clip(p, Vector2(r, 0), Vector2.LEFT)
	var water := Poly.clip(Poly.clip(p, Vector2(l, 0), Vector2.LEFT), Vector2(r, 0), Vector2.RIGHT)
	if absf(Poly.area(west)) > 300.0:
		var b3 := Block.new()
		b3.poly = west
		b3.district = dist
		b3.downtown = dt
		blocks.append(b3)
	if absf(Poly.area(east)) > 300.0:
		var b4 := Block.new()
		b4.poly = east
		b4.district = dist
		b4.downtown = dt
		blocks.append(b4)
	if absf(Poly.area(water)) > 100.0:
		var b5 := Block.new()
		b5.poly = water
		b5.water = true
		b5.district = WATERFRONT
		blocks.append(b5)

func _cut_canal(p: PackedVector2Array, c: Vector2) -> Array:
	# keep the block whole if far from the canal
	var d := absf(c.x - river_x(c.y))
	if d > river_w * 0.75 + 110.0:
		return [p]
	# local canal direction
	var dz := 40.0
	var a := Vector2(river_x(c.y - dz), c.y - dz)
	var b := Vector2(river_x(c.y + dz), c.y + dz)
	var t := (b - a).normalized()
	var n := Vector2(-t.y, t.x)
	var center := Vector2(river_x(c.y), c.y)
	var half := river_w * 0.5
	# land pieces either side
	var left := Poly.clip(p, center + n * half, -n)
	var right := Poly.clip(p, center - n * half, n)
	var out := []
	if absf(Poly.area(left)) > 200.0:
		out.append(left)
	if absf(Poly.area(right)) > 200.0:
		out.append(right)
	# water piece (marked)
	var wat := Poly.clip(Poly.clip(p, center + n * half, n), center - n * half, -n)
	if absf(Poly.area(wat)) > 100.0:
		# negative area marker used by caller
		var w2 := PackedVector2Array()
		for v in wat:
			w2.append(Vector2(v.x - 100000.0, v.y))
		out.append(w2)
	if out.is_empty():
		out.append(p)
	return out

func _cut_corridor(p: PackedVector2Array, path: PackedVector2Array, half_w: float) -> Array:
	# only test segments near the polygon bbox
	var bb := Poly.bbox(p)
	var res := [p]
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var tb := Rect2(a, Vector2.ZERO).expand(b).grow(half_w + 2.0)
		if not bb.intersects(tb):
			continue
		var t := (b - a).normalized()
		var nn := Vector2(-t.y, t.x)
		var next := []
		for poly in res:
			var keep1 := Poly.clip(poly, a + nn * half_w, -nn)
			var keep2 := Poly.clip(poly, a - nn * half_w, nn)
			if absf(Poly.area(keep1)) > 260.0:
				next.append(keep1)
			if absf(Poly.area(keep2)) > 260.0:
				next.append(keep2)
		res = next
	return res

func district_at(x: float, z: float) -> int:
	if absf(x - river_x(z)) < river_w * 0.5 + 90.0:
		return WATERFRONT
	var best := MIXED
	var bs := 0.06 + H.f(int(x * 0.5) + 900, int(z * 0.5) + 900) * 0.22
	var arr := [
		[CBD, 0.0, 0.0, 620.0, 1.0],
		[COMMERCIAL, 820.0, -780.0, 620.0, 0.82],
		[COMMERCIAL, 260.0, -980.0, 420.0, 0.6],
		[CAMPUS, -1080.0, -1080.0, 480.0, 0.95],
		[INDUSTRIAL, 900.0, 1080.0, 560.0, 0.9],
		[RESIDENTIAL, -940.0, 260.0, 780.0, 0.9],
		[RESIDENTIAL, -260.0, 1100.0, 560.0, 0.75],
		[RESIDENTIAL, -1180.0, 900.0, 420.0, 0.8],
		[MIXED, 300.0, 300.0, 700.0, 0.45],
	]
	for a in arr:
		var d: float = Vector2(x - a[1], z - a[2]).length()
		var s: float = a[4] * exp(-pow(d / a[3], 2.0) * 2.2)
		if s > bs:
			bs = s
			best = a[0]
	return best

func downtown_factor(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	return clampf(1.0 - d / 1350.0, 0.0, 1.0)

func _place_lots() -> void:
	blds.clear()
	lot_count = 0
	for blk in blocks:
		if blk.water:
			continue
		var d: int = blk.district
		var is_park := rng.randf() < (0.07 if d == RESIDENTIAL else 0.05)
		if blk.downtown > 0.75 and rng.randf() < 0.08:
			is_park = true
		var bc := Poly.centroid(blk.poly)
		if bc.distance_to(Vector2(-560.0, -160.0)) < 260.0 and blk.district != CAMPUS:
			blk.park = true
			continue
		if bc.distance_to(Vector2(80.0, -900.0)) < 170.0:
			blk.park = true
			continue
		if is_park:
			blk.park = true
			continue
		var build := Poly.inset(blk.poly, SIDEWALK if d != CBD else 5.5)
		if build.size() < 3 or absf(Poly.area(build)) < 120.0:
			continue
		var lots: Array = []
		match d:
			CBD:
				lots = Poly.subdivide(build, rng, 30.0, 64.0, true)
			COMMERCIAL:
				lots = Poly.subdivide(build, rng, 22.0, 50.0, true)
			RESIDENTIAL:
				lots = Poly.subdivide(build, rng, 26.0, 44.0, true)
			CAMPUS:
				lots = Poly.subdivide(build, rng, 26.0, 64.0, false)
			INDUSTRIAL:
				lots = Poly.subdivide(build, rng, 46.0, 100.0, false)
			WATERFRONT:
				lots = Poly.subdivide(build, rng, 26.0, 52.0, true)
			_:
				lots = Poly.subdivide(build, rng, 26.0, 58.0, true)
		for lot in lots:
			if absf(Poly.area(lot)) < 110.0:
				continue
			lot_count += 1
			# small chance of open space / parking instead of a building
			if rng.randf() < 0.10 and d != CBD:
				continue
			if _in_canal(lot, river_w * 0.5 + 9.0):
				continue
			_make_building(lot, d, blk.downtown)

func _make_building(lot: PackedVector2Array, d: int, dt: float) -> void:
	var b := Bld.new()
	b.id = blds.size()
	b.district = d
	b.sd = rng.randf()
	var c := Poly.centroid(lot)
	b.cx = c.x
	b.cz = c.y
	var inset := rng.randf_range(0.8, 2.4)
	var fp := Poly.inset(lot, inset)
	if fp.size() < 3 or absf(Poly.area(fp)) < 60.0:
		return
	# chamfer random corners
	fp = _chamfer(fp, b.sd)
	# pick kind
	var kind := K_OFFICE
	match d:
		CBD:
			var r := rng.randf()
			kind = K_TOWER if r < 0.62 else (K_OFFICE if r < 0.9 else K_HOTEL)
			if dt > 0.85 and rng.randf() < 0.25:
				kind = K_TOWER
		COMMERCIAL:
			var r := rng.randf()
			kind = K_OFFICE if r < 0.3 else (K_SHOP if r < 0.55 else (K_MALL if r < 0.7 else (K_HOTEL if r < 0.85 else K_APARTMENT)))
		RESIDENTIAL:
			var r := rng.randf()
			kind = K_APARTMENT if r < 0.72 else (K_SHOP if r < 0.82 else (K_HOUSE if r < 0.9 else (K_SCHOOL if r < 0.96 else K_PARKING)))
		CAMPUS:
			kind = K_SCHOOL if rng.randf() < 0.78 else (K_APARTMENT if rng.randf() < 0.6 else K_PARKING)
		INDUSTRIAL:
			var r := rng.randf()
			kind = K_WAREHOUSE if r < 0.62 else (K_FACTORY if r < 0.88 else K_PARKING)
		WATERFRONT:
			var r := rng.randf()
			kind = K_APARTMENT if r < 0.62 else (K_HOTEL if r < 0.8 else K_OFFICE)
		_:
			var r := rng.randf()
			kind = K_OFFICE if r < 0.35 else (K_APARTMENT if r < 0.7 else K_SHOP)
	b.kind = kind
	var h := 20.0
	var floors := 5
	match kind:
		K_TOWER:
			h = 55.0 + pow(rng.randf(), 2.0) * 175.0 * (0.4 + dt)
			floors = maxi(12, int(h / rng.randf_range(3.6, 4.3)))
		K_OFFICE:
			h = 22.0 + pow(rng.randf(), 1.4) * 100.0 * (0.4 + dt)
			floors = maxi(4, int(h / 4.0))
		K_HOTEL:
			h = 42.0 + rng.randf() * 120.0
			floors = int(h / 3.6)
		K_APARTMENT:
			h = 14.0 + pow(rng.randf(), 1.3) * 62.0 * (0.5 + dt * 0.7)
			floors = maxi(3, int(h / 3.2))
		K_HOUSE:
			h = 7.0 + rng.randf() * 5.0
			floors = 2 + int(rng.randf() * 2.0)
		K_MALL:
			h = 14.0 + rng.randf() * 16.0
			floors = 3 + int(rng.randf() * 2.0)
		K_SHOP:
			h = 8.0 + rng.randf() * 18.0
			floors = 2 + int(rng.randf() * 3.0)
		K_SCHOOL:
			h = 10.0 + rng.randf() * 16.0
			floors = 3 + int(rng.randf() * 2.0)
		K_WAREHOUSE:
			h = 8.0 + rng.randf() * 9.0
			floors = 1
		K_FACTORY:
			h = 12.0 + rng.randf() * 16.0
			floors = 2
		K_PARKING:
			h = 9.0 + rng.randf() * 15.0
			floors = 3 + int(rng.randf() * 3.0)
		K_HOSPITAL:
			h = 30.0 + rng.randf() * 40.0
			floors = int(h / 3.9)
	h = maxf(h, 5.0)
	b.h = h
	b.floors = maxi(floors, 1)
	# facade style
	match kind:
		K_TOWER:
			var rt := rng.randf()
			b.style = M.STY_CURTAIN if rt < 0.40 else (M.STY_FINS if rt < 0.58 else (M.STY_PANEL if rt < 0.80 else M.STY_PUNCHED))
		K_OFFICE:
			var ro := rng.randf()
			b.style = M.STY_PANEL if ro < 0.22 else (M.STY_RIBBON if ro < 0.42 else (M.STY_CURTAIN if ro < 0.66 else M.STY_PUNCHED))
		K_APARTMENT:
			b.style = M.STY_BRICK if rng.randf() < 0.55 else M.STY_PUNCHED
		K_HOUSE:
			b.style = M.STY_BRICK
		K_SCHOOL:
			b.style = M.STY_RIBBON if rng.randf() < 0.6 else M.STY_PUNCHED
		K_WAREHOUSE, K_FACTORY:
			b.style = M.STY_INDUSTRIAL
		K_MALL, K_SHOP:
			b.style = M.STY_SHOPFRONT if rng.randf() < 0.5 else M.STY_CURTAIN
		_:
			b.style = M.STY_PUNCHED
	# podium + shaft for tall towers
	if b.h > 85.0:
		b.podium = 12.0 + rng.randf() * 10.0
		b.tower_scale = rng.randf_range(0.45, 0.72)
	# tapered footprint for some towers
	b.poly = fp
	# courtyard / open notch for residential
	if kind == K_APARTMENT and b.h > 24.0 and rng.randf() < 0.3:
		var q := Poly.inset(fp, rng.randf_range(3.0, 6.0))
		if q.size() >= 3 and absf(Poly.area(q)) > 90.0:
			b.poly = fp
	blds.append(b)

func _in_canal(p: PackedVector2Array, margin: float) -> bool:
	for v in p:
		if absf(v.x - river_x(v.y)) < margin:
			return true
	var c := Poly.centroid(p)
	if absf(c.x - river_x(c.y)) < margin:
		return true
	# sample along the edges too
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		for k in 3:
			var q := a.lerp(b, (k + 0.5) / 3.0)
			if absf(q.x - river_x(q.y)) < margin:
				return true
	return false

func _chamfer(p: PackedVector2Array, sd: float) -> PackedVector2Array:
	var n := p.size()
	var cuts := []
	for i in n:
		if H.f(int(sd * 1000) + i, 7) > 0.5:
			continue
		var a := p[i]
		var prev := p[(i + n - 1) % n]
		var next := p[(i + 1) % n]
		var da := (a - prev)
		var db := (next - a)
		if da.length() < 2.0 or db.length() < 2.0:
			continue
		var nn := (da.normalized() + db.normalized()).normalized()
		var cut := minf(da.length(), db.length()) * 0.26
		if cut < 1.4:
			continue
		cuts.append([a - nn * cut, -nn])
	var q := p
	for c in cuts:
		q = Poly.clip(q, c[0], c[1])
		if q.size() < 3 or absf(Poly.area(q)) < 80.0:
			return p
	return q

func _place_landmarks() -> void:
	# hand-picked landmark towers near the core for skyline drama
	var spots := [
		[-120.0, -260.0, 330.0], [260.0, 120.0, 300.0], [-420.0, 300.0, 250.0],
		[120.0, 520.0, 230.0], [430.0, -330.0, 270.0], [-260.0, -640.0, 210.0],
	]
	for s in spots:
		var p := Vector2(s[0], s[1])
		var best: Bld = null
		var bd := 1e9
		for b in blds:
			if b.district != CBD:
				continue
			var d: float = Vector2(b.cx - p.x, b.cz - p.y).length()
			if d < bd:
				bd = d
				best = b
		if best == null or bd > 220.0:
			continue
		best.h = maxf(best.h, s[2])
		best.floors = int(best.h / 3.9)
		best.kind = K_TOWER
		best.landmark = true
		best.podium = 16.0
		best.tower_scale = 0.55
		best.style = M.STY_FINS if best.style == M.STY_PANEL else best.style

## Force specific landmark structures into existing lots (keeps the urban fabric).
func _place_structures() -> void:
	_force_kind(Vector2(360.0, -300.0), K_TWIST, 380.0, 34.0)
	# clear a small plaza around the signature tower
	for b in blds:
		if b.kind == K_TWIST:
			continue
		if Vector2(b.cx, b.cz).distance_to(Vector2(360.0, -300.0)) < 46.0 and b.kind != K_APARTMENT:
			b.ghost = true
	var cool := [Vector2(760.0, 900.0), Vector2(930.0, 1010.0), Vector2(1080.0, 880.0), Vector2(880.0, 1150.0)]
	for p in cool:
		_force_kind(p, K_COOLING, math_randf_range(80.0, 105.0), 30.0)
	# ferris wheel on a cleared plaza in the entertainment district
	var wp := Vector2(560.0, -640.0)
	var best: Bld = null
	var bd := 1e9
	for b in blds:
		if b.kind == K_TWIST or b.kind == K_COOLING:
			continue
		var d: float = Vector2(b.cx - wp.x, b.cz - wp.y).length()
		if d < bd:
			bd = d
			best = b
	if best != null and bd < 260.0:
		wheel_pos = Vector2(best.cx, best.cz)
		wheel_r = 34.0
		best.kind = K_WHEEL
		best.h = 78.0
		best.floors = 1
		best.poly = _circle_poly(best.cx, best.cz, 30.0, 16)
		best.style = M.STY_PANEL
		# clear the surrounding block so the wheel reads against the skyline
		for b in blds:
			if b == best:
				continue
			if Vector2(b.cx, b.cz).distance_to(wheel_pos) < 62.0:
				b.ghost = true

func _force_kind(p: Vector2, kind: int, h: float, radius: float) -> void:
	var best: Bld = null
	var bd := 1e9
	for b in blds:
		if b.kind == K_TWIST or b.kind == K_COOLING or b.kind == K_WHEEL:
			continue
		var d: float = Vector2(b.cx - p.x, b.cz - p.y).length()
		if d < bd:
			bd = d
			best = b
	if best == null:
		return
	best.kind = kind
	best.h = h
	best.floors = maxi(1, int(h / 4.0))
	best.poly = _circle_poly(best.cx, best.cz, radius, 20)
	best.podium = 0.0
	best.tower_scale = 1.0
	best.style = M.STY_CURTAIN if kind == K_TWIST else M.STY_PANEL

func _circle_poly(cx: float, cz: float, r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / n
		p.append(Vector2(cx + cos(a) * r, cz + sin(a) * r))
	return p

func math_randf_range(a: float, b2: float) -> float:
	return a + (b2 - a) * rng.randf()

func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x + HALF) / CELL)), int(floor((z + HALF) / CELL)))

func bld_in_chunk(c: Vector2i) -> Array:
	var out := []
	for b in blds:
		if b.chunk == c:
			out.append(b)
	return out

func count_by_kind() -> Dictionary:
	var d := {}
	for b in blds:
		d[b.kind] = d.get(b.kind, 0) + 1
	return d
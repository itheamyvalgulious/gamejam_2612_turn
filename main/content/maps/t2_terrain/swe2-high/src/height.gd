class_name HeightField
extends RefCounted
## height.gd — analytic terrain height + biome splat for the Vale.
## World: x ∈ [-2048, 2048], z ∈ [-1280, 1280]  (4096 × 2560 m = 10.24 km²)
## Biomes along Z:  snow plateau (z < -400) · mountain ridge + gorge
## (z ≈ -350..350) · jungle basin + lake (z > 400).

const X0 := -2048.0
const X1 := 2048.0
const Z0 := -1280.0
const Z1 := 1280.0

var _n := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _nr := FastNoiseLite.new()
var _ns := FastNoiseLite.new()
var _nw := FastNoiseLite.new()

var river_pts: PackedVector2Array
var river_stride := 6
var _coarse: PackedVector2Array        # every stride-th point (plus tail)
var _coarse_idx: PackedInt32Array      # coarse i -> original index
var _segcum: PackedFloat32Array        # cumulative arc length per vertex
var lake := {"c": Vector2(500, 980), "r": 320.0, "y": 2.0}

func _init() -> void:
	_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n.fractal_octaves = 5
	_n.frequency = 1.0 / 640.0
	_n.seed = 1207
	_n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n2.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n2.fractal_octaves = 4
	_n2.frequency = 1.0 / 130.0
	_n2.seed = 9182
	_nr.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_nr.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_nr.fractal_octaves = 5
	_nr.frequency = 1.0 / 520.0
	_nr.fractal_lacunarity = 2.1
	_nr.seed = 5541
	_ns.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ns.fractal_type = FastNoiseLite.FRACTAL_FBM
	_ns.fractal_octaves = 3
	_ns.frequency = 1.0 / 210.0
	_ns.seed = 8871
	_nw.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_nw.fractal_type = FastNoiseLite.FRACTAL_FBM
	_nw.fractal_octaves = 3
	_nw.frequency = 1.0 / 90.0
	_nw.seed = 3349
	_build_river()


# ------------------------------------------------------------- river spline
func _build_river() -> void:
	# source on the snow plateau → north flank → gorge → falls → delta → lake
	river_pts = PackedVector2Array()
	var raw := [
		Vector2(-620, -1180), Vector2(-560, -1040), Vector2(-470, -900),
		Vector2(-400, -760), Vector2(-310, -640), Vector2(-240, -520),
		Vector2(-160, -430), Vector2(-90, -350), Vector2(-30, -290),
		Vector2(10, -240), Vector2(40, -190),                    # gorge head
		Vector2(60, -60),  Vector2(90, 80),                     # through cliffs
		Vector2(130, 170),                                       # waterfall lip
		Vector2(160, 230),                                       # plunge basin
		Vector2(200, 330), Vector2(260, 430), Vector2(330, 540),
		Vector2(390, 660), Vector2(440, 780), Vector2(480, 900),
		Vector2(500, 980),                                       # lake centre
	]
	# Chaikin ×3 for a smooth spline
	var pts := raw
	for i in 3:
		var np := PackedVector2Array()
		np.append(pts[0])
		for j in range(pts.size() - 1):
			var a: Vector2 = pts[j]
			var b: Vector2 = pts[j + 1]
			np.append(a.lerp(b, 0.25))
			np.append(a.lerp(b, 0.75))
		np.append(pts[pts.size() - 1])
		pts = np
	river_pts = pts
	# coarse acceleration polyline for river_dist()
	_coarse = PackedVector2Array()
	_coarse_idx = PackedInt32Array()
	for i in range(0, pts.size(), river_stride):
		_coarse.append(pts[i])
		_coarse_idx.append(i)
	if _coarse_idx[_coarse_idx.size() - 1] != pts.size() - 1:
		_coarse.append(pts[pts.size() - 1])
		_coarse_idx.append(pts.size() - 1)
	# cumulative arc length per segment
	_segcum = PackedFloat32Array()
	_segcum.resize(pts.size())
	_segcum[0] = 0.0
	for i in range(pts.size() - 1):
		_segcum[i + 1] = _segcum[i] + pts[i].distance_to(pts[i + 1])

## Up to 2 nearest (dist, arc_t) candidates. The carve consumes BOTH so
## that across a tight bend — where the nearest segment flips and bed
## height would jump tens of metres — min() of two continuous targets
## keeps the heightfield continuous instead of tearing a crevasse.
func river_near2(p: Vector2) -> Array:
	var best_ci := 0
	var best_cd := 1e18
	for i in range(_coarse.size() - 1):
		var a := _coarse[i]
		var b := _coarse[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var tt := clampf((p - a).dot(ab) / maxf(l2, 0.001), 0.0, 1.0)
		var dx := p.x - (a.x + ab.x * tt)
		var dz := p.y - (a.y + ab.y * tt)
		var d2 := dx * dx + dz * dz
		if d2 < best_cd:
			best_cd = d2
			best_ci = i
	# widen the bracket by one more coarse segment on each side so the
	# second-nearest original segment is also covered
	var i0: int = _coarse_idx[maxi(best_ci - 2, 0)]
	var i1: int = mini(
		_coarse_idx[mini(best_ci + 2, _coarse_idx.size() - 1)],
		river_pts.size() - 2)
	i1 = maxi(i1, i0)
	var cands: Array = []           # entries: Vector2(dist, arc_t)
	var total := _segcum[_segcum.size() - 1]
	for i in range(i0, i1 + 1):
		var a := river_pts[i]
		var b := river_pts[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var tt := clampf((p - a).dot(ab) / maxf(l2, 0.001), 0.0, 1.0)
		var d := p.distance_to(a + ab * tt)
		cands.append(Vector2(d, (_segcum[i] + ab.length() * tt) / total))
	cands.sort_custom(func(x, y): return (x as Vector2).x < (y as Vector2).x)
	return cands.slice(0, mini(1, cands.size() - 1))

## Distance from p to the river polyline + arc position t (0=source,1=lake).
## Two-level: nearest segment on the coarse polyline brackets the search,
## then only original segments around it are tested exactly.
func river_dist(p: Vector2) -> Vector2:
	var best_ci := 0
	var best_cd := 1e18
	for i in range(_coarse.size() - 1):
		var a := _coarse[i]
		var b := _coarse[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var tt := clampf((p - a).dot(ab) / maxf(l2, 0.001), 0.0, 1.0)
		var dx := p.x - (a.x + ab.x * tt)
		var dz := p.y - (a.y + ab.y * tt)
		var d2 := dx * dx + dz * dz
		if d2 < best_cd:
			best_cd = d2
			best_ci = i
	# exact pass over original segs covered by winning coarse seg (±1)
	var i0: int = _coarse_idx[maxi(best_ci - 1, 0)]
	var i1: int = mini(_coarse_idx[mini(best_ci + 1, _coarse_idx.size() - 1)],
		river_pts.size() - 2)
	i1 = maxi(i1, i0)
	var best := 1e9
	var best_i := i0
	var best_tt := 0.0
	for i in range(i0, i1 + 1):
		var a := river_pts[i]
		var b := river_pts[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var tt := clampf((p - a).dot(ab) / maxf(l2, 0.001), 0.0, 1.0)
		var d := p.distance_to(a + ab * tt)
		if d < best:
			best = d
			best_i = i
			best_tt = tt
	# arc position from the precomputed cumulative table
	var total := _segcum[_segcum.size() - 1]
	var upto := _segcum[best_i]
	var best_t := (upto + river_pts[best_i].distance_to(river_pts[best_i + 1]) * best_tt) / total
	return Vector2(best, best_t)

## River surface height at arc t (bed sits ~2.4 m under this on the plains).
func river_water_y(t: float) -> float:
	# plateau source 118 → runs downhill → gorge 46 → falls lip 40 →
	# basin 12 → lake 2
	var keys := [
		Vector2(0.00, 118.0), Vector2(0.12, 96.0), Vector2(0.26, 66.0),
		Vector2(0.36, 50.0),  Vector2(0.44, 46.0), Vector2(0.52, 42.0),
		Vector2(0.555, 40.0),                                    # lip
		Vector2(0.585, 12.0),                                    # plunge pool
		Vector2(0.68, 8.0),  Vector2(0.82, 4.0),
		Vector2(0.94, 2.0),  Vector2(1.0, 2.0)]
	for i in range(keys.size() - 1):
		if t <= keys[i + 1].x:
			var u: float = (t - keys[i].x) / maxf(keys[i + 1].x - keys[i].x, 0.0001)
			return lerpf(keys[i].y, keys[i + 1].y, u)
	return 2.0


# --------------------------------------------------------------- height ---
func h(x: float, z: float) -> float:
	var p := Vector2(x, z)
	# domain-warped continent base
	var wx := _ns.get_noise_2d(x * 1.4 + 900, z * 1.4 - 300) * 60.0
	var wz := _ns.get_noise_2d(x * 1.4 - 700, z * 1.4 + 500) * 60.0
	var base := _n.get_noise_2d(x + wx, z + wz) * 0.5 + 0.5

	# --- latitudinal climate band: snow north → ridge → jungle south
	var band := smoothstep(-460.0, -260.0, z)          # 0 snow .. 1 mountains
	var jungle := smoothstep(300.0, 620.0, z)          # 0 mid .. 1 jungle basin

	# snow plateau: high gentle field
	var snow_h := 105.0 + base * 30.0 + _n2.get_noise_2d(x, z) * 12.0

	# mountain band: ridged massif, crest along z≈-40..160, peaks ~400 m
	# Mountains: proper range — foothill apron (~150 m roll) → mid slopes →
	# ridged crest row along z≈60. Everything smooth, no vertical curtains.
	var rid := _nr.get_noise_2d(x * 0.7, z * 0.7)
	rid = pow(maxf(1.0 - absf(rid), 0.0), 0.9)
	var dz_m := z - 60.0
	# wide apron eases plains into the massif (no cliff at the boundary)
	var apron := smoothstep(480.0, 140.0, absf(dz_m))
	# crest line meanders along x and its tooth amplitude varies — a dead-
	# straight saw of identical teeth is what made the range read mechanical
	var wob := _n2.get_noise_2d(x * 0.8, 7.0) * 90.0
	var crest := exp(-pow((dz_m + wob) / 190.0, 2.0))
	var bulk := _n.get_noise_2d(x * 0.55 + 300, z * 0.55) * 0.5 + 0.5
	# mid-frequency crag keeps faces from collapsing into silk-smooth
	# folds — pure low-frequency bulk is what produced the paper look
	var crag := _n2.get_noise_2d(x * 2.2, z * 2.2)
	var mtn_h := 40.0 + apron * (55.0 + bulk * 120.0) \
		+ crest * (60.0 + rid * (110.0 + bulk * 90.0)) \
		+ apron * crag * 26.0
	# gentle terracing on the crest only — large fins read as curtains
	if crest > 0.3:
		var q := floorf(mtn_h / 26.0) * 26.0
		mtn_h = lerpf(mtn_h, q + 13.0, crest * 0.10)

	# jungle basin: low rolling ground falling toward the lake
	var jun_h := 26.0 + base * 22.0 + _n2.get_noise_2d(x * 0.8, z * 0.8) * 8.0
	jun_h = lerpf(jun_h, 6.0, smoothstep(700.0, 1050.0, z))
	var ld := p.distance_to(lake.c)
	jun_h = lerpf(jun_h, -4.0, smoothstep(lake.r + 120.0, lake.r - 60.0, ld))

	var hh := lerpf(snow_h, mtn_h, band)
	hh = lerpf(hh, jun_h, jungle)

	# foothills blend noise everywhere — gentler inside the gorge band:
	# 6 m rills carved into near-vertical walls read as torn-cloth veins
	# when viewed from the canyon floor
	hh += _n2.get_noise_2d(x * 1.7, z * 1.7) * 6.0 * (1.0 - jungle * 0.7)

	# --- river valley carve
	# Evaluate the two nearest spline segments and take the min target:
	# each candidate is continuous in its own d/t, so their min is still
	# continuous — the single-segment version tore crevasse-like cracks
	# wherever the nearest segment flipped across a tight bend.
	var cands := river_near2(p)
	var d: float = (cands[0] as Vector2).x
	var t: float = (cands[0] as Vector2).y
	if d < 340.0:
		var target := 1e9
		for cand in cands:
			var d_i: float = (cand as Vector2).x
			var t_i: float = (cand as Vector2).y
			var w_half := lerpf(30.0, 60.0, jungle) \
				+ lerpf(4.0, 10.0, jungle) * sin(t_i * 31.0) * 0.4
			# bed = water level − ~1.4 m: the river surface must sit inside
			# its channel, not float above a barely-carved floor
			var bed := river_water_y(t_i) - lerpf(2.8, 1.6, jungle)
			# steeper-walled channel in the snow/mountain band so the river
			# reads as incised, not a ribbon floating on snow
			var spread := lerpf(90.0, 220.0, jungle)
			var lift := pow(smoothstep(w_half, w_half + spread, d_i), 1.8)
			target = minf(target, bed + lift * (hh - bed))
			# wide funnel mouth in the gorge: the canyon opens outward
			# above the channel instead of staying a 60 m slot
			var funnel := smoothstep(w_half, w_half + 300.0, d_i)
			if funnel > 0.0 and jungle < 0.5:
				target += funnel * hh * 0.25
		hh = minf(hh, target)
		# soften rills inside the canyon band so walls don't fray
		var rill_in := _n2.get_noise_2d(x * 1.7, z * 1.7) * 6.0
		hh -= rill_in * 0.6 * (1.0 - jungle) * (1.0 - smoothstep(140.0, 240.0, d))
		# keep the gorge walls tall: pull terrain UP slightly away from river
		if z > -320 and z < 220 and d < 150.0:
			hh += smoothstep(40.0, 150.0, d) * 18.0 * (1.0 - jungle)
	# cliff face band beside the gorge: gentle strata terracing only —
	# the earlier 50% quantize carved knife-edge fins that read as torn
	# cloth walls at any oblique view
	if z > -260 and z < 240:
		var side := smoothstep(60.0, 150.0, d) * (1.0 - smoothstep(180.0, 260.0, d))
		if side > 0.01:
			var q := floorf(hh / 14.0) * 14.0
			hh = lerpf(hh, q, side * 0.18)

	return hh


# --------------------------------------------------------------- splat ----
## Returns Color(snow, rock, jungle, sand) — weights sum ≈1.
func splat(x: float, z: float, y: float, slope: float) -> Color:
	var band := smoothstep(-460.0, -260.0, z)
	var jungle := smoothstep(300.0, 620.0, z)
	var snow := (1.0 - band) * smoothstep(60.0, 100.0, y)
	snow += smoothstep(210.0, 330.0, y) * 0.9          # peaks always snow
	snow += smoothstep(-420.0, -520.0, z) * 0.8
	# rock owns anything steeper than ~35°; gentler rolling ground in the
	# jungle basin stays jungle (earlier 0.30 cut painted the rolling
	# floor as an orange rock/jungle checkerboard at distance)
	var steep := smoothstep(0.45, 0.7, slope)
	var rock := steep + band * (1.0 - jungle) * 0.35
	var sand := 0.0
	var rv := river_dist(Vector2(x, z))
	if rv.x < 20.0 and jungle > 0.2:
		# wet shoreline only — a narrow dark rim at the waterline, not a
		# pale beach blanketing the whole bank
		sand = smoothstep(18.0, 8.0, rv.x) * jungle * (1.0 - steep) \
			* smoothstep(360.0, 500.0, z) * 0.7
	var jw := jungle * (1.0 - steep) * smoothstep(0.5, 0.3, slope)
	# gorge floor is bare stone, never jungle — hard z-gate plus a
	# river-distance gate so the basin can't creep up the canyon walls
	jw *= smoothstep(340.0, 440.0, z)
	jw *= smoothstep(90.0, 150.0, rv.x)
	var total := snow + rock + jw + sand + 0.02
	return Color(snow / total, rock / total, jw / total, sand / total)

## Approx slope (0 flat → ~1.3 cliff).
func slope(x: float, z: float, e := 4.0) -> float:
	var dx := (h(x + e, z) - h(x - e, z)) / (2.0 * e)
	var dz := (h(x, z + e) - h(x, z - e)) / (2.0 * e)
	return sqrt(dx * dx + dz * dz)

func water_y(x: float, z: float) -> float:
	var rv := river_dist(Vector2(x, z))
	return river_water_y(rv.y)

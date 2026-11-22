class_name TerrainField
extends RefCounted

## AETHER — procedural 10.24 km² terrain field.
##
## Everything below is analytic: domain-warped fractal noise, explicit mountain
## massifs, a raised snow plateau with an amphitheatre escarpment, and a spline
## river incised into the basin.  Deterministic from SEED, zero assets.
##
## World: X east, Z south, Y up; square [-1600,1600]² = 3.2 × 3.2 km.
##
##   north  (-Z) : snowfield plateau 520–700 m, hanging glacial valley
##   centre      : 250 m amphitheatre cliff + 200 m waterfall, river gorge
##   east        : granite wall, peaks 750–1020 m
##   south  (+Z) : warm rainforest basin 20–300 m

const EXTENT := 1600.0
const AREA_KM2 := 10.24
const SEED := 20261115

const LIP_Z := -232.0
const POOL_Z := -168.0
const LIP_Y := 500.0
const POOL_Y := 292.0

var n_warp: FastNoiseLite
var n_base: FastNoiseLite
var n_ridge: FastNoiseLite
var n_detail: FastNoiseLite
var n_micro: FastNoiseLite
var n_mask: FastNoiseLite
var n_dune: FastNoiseLite
var n_cell: FastNoiseLite

var river_xs: PackedVector2Array
var river_ws: PackedVector2Array

# (x, z, summit height, falloff radius)
var peaks := [
	Vector4(500.0, -1500.0, 900.0, 560.0),
	Vector4(650.0, -1050.0, 1000.0, 500.0),
	Vector4(790.0, -640.0, 970.0, 480.0),
	Vector4(900.0, -200.0, 880.0, 440.0),
	Vector4(1060.0, 320.0, 780.0, 440.0),
	Vector4(1250.0, 850.0, 680.0, 430.0),
	Vector4(1480.0, 1450.0, 620.0, 430.0),
	Vector4(150.0, -1760.0, 820.0, 380.0),
	Vector4(-420.0, -1740.0, 790.0, 380.0),
	Vector4(-980.0, -1700.0, 750.0, 390.0),
	Vector4(-1450.0, -1600.0, 690.0, 400.0),
]

func _init() -> void:
	n_warp = _noise(SEED + 1, 0.00072, 4, 2.0, 0.5, FastNoiseLite.FRACTAL_FBM)
	n_base = _noise(SEED + 2, 0.00068, 4, 2.0, 0.5, FastNoiseLite.FRACTAL_FBM)
	n_ridge = _noise(SEED + 3, 0.00130, 5, 2.05, 0.5, FastNoiseLite.FRACTAL_RIDGED)
	n_detail = _noise(SEED + 4, 0.0058, 4, 2.0, 0.5, FastNoiseLite.FRACTAL_FBM)
	n_micro = _noise(SEED + 5, 0.034, 3, 2.0, 0.5, FastNoiseLite.FRACTAL_FBM)
	n_mask = _noise(SEED + 6, 0.0021, 3, 2.0, 0.5, FastNoiseLite.FRACTAL_FBM)
	n_dune = _noise(SEED + 7, 0.0065, 3, 2.0, 0.5, FastNoiseLite.FRACTAL_RIDGED)
	n_cell = _noise(SEED + 8, 0.008, 2, 2.0, 0.5, FastNoiseLite.FRACTAL_FBM)
	n_cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	n_cell.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n_cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB

	# river centreline from far north to southern exit (z, x)
	river_xs = PackedVector2Array([
		Vector2(-1600.0, -600.0), Vector2(-1350.0, -570.0), Vector2(-1100.0, -548.0),
		Vector2(-900.0, -505.0), Vector2(-700.0, -460.0), Vector2(-520.0, -416.0),
		Vector2(-380.0, -350.0), Vector2(-290.0, -278.0), Vector2(-205.0, -208.0),
		Vector2(-120.0, -162.0), Vector2(-40.0, -102.0), Vector2(20.0, -22.0),
		Vector2(40.0, 78.0), Vector2(188.0, 4.0), Vector2(300.0, -52.0),
		Vector2(410.0, -24.0), Vector2(540.0, -86.0), Vector2(660.0, -128.0),
		Vector2(800.0, -178.0), Vector2(980.0, -268.0), Vector2(1160.0, -336.0),
		Vector2(1330.0, -372.0), Vector2(1470.0, -404.0), Vector2(1600.0, -430.0),
	])
	river_ws = PackedVector2Array([
		Vector2(-1600.0, 9.0), Vector2(-500.0, 10.0), Vector2(-232.0, 15.0),
		Vector2(-168.0, 18.0), Vector2(0.0, 24.0), Vector2(200.0, 30.0),
		Vector2(450.0, 38.0), Vector2(800.0, 47.0), Vector2(1100.0, 55.0),
		Vector2(1600.0, 64.0),
	])


func _noise(s: int, f: float, octaves: int, lac: float, gain: float, ftype: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = f
	n.fractal_type = ftype
	n.fractal_octaves = octaves
	n.fractal_lacunarity = lac
	n.fractal_gain = gain
	return n


func smoothmax(a: float, b: float, k: float) -> float:
	return 0.5 * (a + b + sqrt((a - b) * (a - b) + k * k))


# --------------------------------------------------------------------------
# river
# --------------------------------------------------------------------------

func _spline(pts: PackedVector2Array, z: float) -> float:
	var n := pts.size()
	if z <= pts[0].x:
		return pts[0].y
	if z >= pts[n - 1].x:
		return pts[n - 1].y
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if pts[mid].x <= z:
			lo = mid
		else:
			hi = mid
	var p0 := pts[maxi(lo - 1, 0)]
	var p1 := pts[lo]
	var p2 := pts[mini(lo + 1, n - 1)]
	var p3 := pts[mini(lo + 2, n - 1)]
	var dz := maxf(p2.x - p1.x, 0.001)
	var t := (z - p1.x) / dz
	var m0 := (p2.y - p0.y) / maxf(p2.x - p0.x, 0.001) * dz
	var m1 := (p3.y - p1.y) / maxf(p3.x - p1.x, 0.001) * dz
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * p1.y + (t3 - 2.0 * t2 + t) * m0 + (-2.0 * t3 + 3.0 * t2) * p2.y + (t3 - t2) * m1


func river_x(z: float) -> float:
	return _spline(river_xs, clampf(z, -EXTENT, EXTENT))

func river_dx(z: float) -> float:
	return (river_x(z + 6.0) - river_x(z - 6.0)) / 12.0

func river_dist(x: float, z: float) -> float:
	var dx := river_dx(z)
	return absf(x - river_x(z)) / sqrt(1.0 + dx * dx)

func river_halfwidth(z: float) -> float:
	return _spline(river_ws, clampf(z, -EXTENT, EXTENT))

func water_level(z: float) -> float:
	if z <= LIP_Z:
		var t := LIP_Y + (LIP_Z - clampf(z, -1600.0, LIP_Z)) * 0.070
		return t + 1.2 * sin((z - LIP_Z) * 0.016)
	var u := clampf((z - POOL_Z) / 1980.0, 0.0, 0.96)
	var wl := POOL_Y * pow(1.0 - u, 1.35) + 2.0
	wl += 2.2 * sin(z * 0.0125 + 1.2) + 0.9 * sin(z * 0.029)
	return wl

func river_zone(z: float) -> float:
	return smoothstep(-140.0, 1000.0, z)


# --------------------------------------------------------------------------
# landform
# --------------------------------------------------------------------------

func _warp(x: float, z: float) -> Vector2:
	var wx := x + 165.0 * n_warp.get_noise_2d(x, z)
	var wz := z + 165.0 * n_warp.get_noise_2d(x + 731.0, z - 419.0)
	return Vector2(wx, wz)


func _mountain(x: float, z: float) -> float:
	var m := 0.0
	for p: Vector4 in peaks:
		var dx: float = x - p.x
		var dz: float = z - p.y
		var w: float = p.w * (0.62 if dx < 0.0 else 1.0)
		var d: float = sqrt(dx * dx + dz * dz * 0.8)
		var v: float = p.z * exp(-pow(d / w, 1.75))
		m = maxf(m, v)
	return m


func plateau_edge(x: float) -> float:
	var e := -238.0 + 0.00027 * x * x
	e += 58.0 * n_mask.get_noise_2d(x * 0.85, 37.0)
	e += 23.0 * n_detail.get_noise_2d(x * 1.7, 80.0)
	e += 9.0 * n_detail.get_noise_2d(x * 4.6, 210.0)
	return e


func height(x: float, z: float) -> float:
	var w := _warp(x, z)
	var wx := w.x
	var wz := w.y

	var north_plateau := smoothstep(-450.0, -1100.0, z)

	# ---- warm basin floor (follows the river's long profile) --------------
	var base := water_level(clampf(z, POOL_Z, 1600.0)) + 46.0
	base += 46.0 * n_base.get_noise_2d(wx, wz)
	base += 18.0 * n_detail.get_noise_2d(wx * 0.7, wz * 0.7)
	base += 130.0 * smoothstep(-450.0, -1300.0, x) * (0.55 + 0.45 * n_base.get_noise_2d(wx + 500.0, wz))
	base += 70.0 * smoothstep(800.0, 1550.0, z) * (0.5 + 0.5 * n_detail.get_noise_2d(wx, wz))

	# ---- snow plateau + amphitheatre escarpment ---------------------------
	var edge := plateau_edge(x)
	var facew := 64.0 + 26.0 * n_mask.get_noise_2d(x * 1.1, 400.0)
	var pm := smoothstep(edge + facew, edge - facew, z)
	var u := clampf((edge + facew - z) / (2.0 * facew), 0.0, 1.0)
	var steps: float = 4.0 + floorf(2.5 * (0.5 + 0.5 * n_mask.get_noise_2d(x * 1.7, z * 0.4)))
	var qu: float = u * steps
	var fl: float = floorf(qu)
	var terr: float = (fl + smoothstep(0.18, 0.82, qu - fl)) / steps
	terr = u
	var pmt := smoothstep(0.0, 1.0, terr)
	var plat := 548.0 + 48.0 * n_base.get_noise_2d(wx + 400.0, wz - 400.0)
	plat += 12.0 * n_detail.get_noise_2d(wx, wz)
	plat += 7.0 * n_dune.get_noise_2d(wx * 1.4, wz * 0.42) * north_plateau
	plat += 70.0 * smoothstep(-950.0, -1550.0, z)
	plat += 30.0 * smoothstep(-900.0, -1250.0, z) * n_ridge.get_noise_2d(wx * 1.4, wz * 1.4)
	# castellate the rim
	plat += maxf(0.0, n_ridge.get_noise_2d(wx * 2.6 + 500.0, wz * 1.9 + 300.0) - 0.52) * 150.0 * clampf(1.0 - absf(pm - 0.75) * 3.0, 0.0, 1.0)
	var h: float = lerp(base, maxf(base, plat), pmt)

	# ---- east / north granite massif -------------------------------------
	var m := _mountain(wx, wz)
	h = smoothmax(h, m, 55.0)
	var hi := smoothstep(320.0, 720.0, m) * smoothstep(0.05, 0.35, pm * -1.0 + 1.0)
	h += (n_ridge.get_noise_2d(wx * 1.9, wz * 1.9) - 0.28) * 118.0 * hi
	h += (n_ridge.get_noise_2d(wx * 4.8 + 210.0, wz * 4.8) - 0.32) * 52.0 * hi
	h += (n_detail.get_noise_2d(wx * 9.0, wz * 9.0)) * 13.0 * hi
	h += (n_ridge.get_noise_2d(wx * 8.0 + 400.0, wz * 8.0) - 0.32) * 24.0 * hi
	var gul := 1.0 - absf(n_detail.get_noise_2d(wx * 3.6 + 77.0, wz * 1.8))
	h -= pow(gul, 5.0) * 36.0 * hi

	# ---- cliff face buttresses, ledges, flutes ---------------------------
	var face := pm * (1.0 - pm) * 4.0
	var warp_face := n_detail.get_noise_2d(wx * 0.055, wz * 0.08) * 260.0
	h += face * (n_ridge.get_noise_2d(wx * 1.15, wz * 0.7) - 0.30) * 30.0
	h += face * (n_detail.get_noise_2d(wx * 2.3, wz * 1.5)) * 8.0
	h += face * (n_cell.get_noise_2d(wx * 1.2 + warp_face, wz * 1.2) - 0.5) * 8.0
	h += face * (n_ridge.get_noise_2d(wx * 3.4 + warp_face, wz * 3.4) - 0.5) * 4.0
	h += face * sin(u * 3.14159 * 7.0 + n_detail.get_noise_2d(wx * 2.0, wz * 2.0) * 3.0) * 3.0
	h -= face * pow(maxf(0.0, 1.0 - absf(n_detail.get_noise_2d(wx * 4.0, wz * 4.0) * 2.0 - 1.0)), 7.0) * 6.0

	# ---- river incision ---------------------------------------------------
	var d := river_dist(x, z)
	var wl := water_level(z)
	var hw := river_halfwidth(z)
	if z > LIP_Z and z < POOL_Z:
		# the falls: keep the plateau cliff intact, cut only a narrow chute
		var notch := smoothstep(52.0, 13.0, d)
		h = lerp(h, water_level(POOL_Z) - 2.0, notch * 0.96)
	else:
		var zone := river_zone(z)
		var vw: float = lerp(190.0, 460.0, zone)
		if z < POOL_Z:
			vw = 140.0
		var wall: float = lerp(250.0, 120.0, zone)
		var prof := (wl - 3.4) + pow(clampf((d - hw * 0.8) / (vw - hw), 0.0, 1.0), 1.55) * wall
		var vm := smoothstep(vw * 1.30, vw * 0.45, d)
		h = lerp(h, minf(h, prof), vm)
		# gravel bars / flat banks
		if d < hw * 3.4:
			h = minf(h, wl + 1.8 + maxf(d - hw, 0.0) * 0.05)

	# plunge pool bowl
	var pdx := x - river_x(POOL_Z)
	var pdz := z - POOL_Z
	var pd := sqrt(pdx * pdx + pdz * pdz)
	h = lerp(h, wl - 4.0, smoothstep(105.0, 34.0, pd) * 0.9)

	# ---- glacial lake basin -----------------------------------------------
	var ldx := x + 553.0
	var ldz := z + 1052.0
	var lr := sqrt(ldx * ldx + ldz * ldz)
	var lake_lvl := 556.5
	if lr < 250.0:
		h = lerp(h, minf(h, lake_lvl - 1.5), smoothstep(250.0, 130.0, lr) * 0.95)

	# ---- surface detail ---------------------------------------------------
	h += 2.4 * n_detail.get_noise_2d(wx * 5.2, wz * 5.2)
	h += 1.1 * n_micro.get_noise_2d(wx * 21.0, wz * 21.0)
	h += 3.0 * n_dune.get_noise_2d(wx * 0.9, wz * 0.32) * smoothstep(-300.0, -600.0, z)

	# keep the water channel below its banks
	if z < LIP_Z - 6.0 or z > POOL_Z + 6.0:
		if d < hw * 1.05:
			h = minf(h, wl - 1.9)
	return h


func normal(x: float, z: float, eps: float = 2.0) -> Vector3:
	var hl := height(x - eps, z)
	var hr := height(x + eps, z)
	var hd := height(x, z - eps)
	var hu := height(x, z + eps)
	return Vector3(hl - hr, 2.0 * eps, hd - hu).normalized()


func slope(x: float, z: float) -> float:
	return 1.0 - normal(x, z).y


# --------------------------------------------------------------------------
# biome weights (shader mirrors these rules)
# --------------------------------------------------------------------------

func snow(x: float, z: float, h: float, sl: float) -> float:
	var n := n_mask.get_noise_2d(x * 1.9 + 610.0, z * 1.9)
	var line := 545.0 + 38.0 * n
	if z < -260.0 and x < 300.0:
		line = 502.0 + 24.0 * n
	var s := smoothstep(line, line + 42.0, h)
	s *= smoothstep(0.66, 0.42, sl)
	var nz := normal(x, z).z
	s = maxf(s, maxf(0.0, -nz) * smoothstep(360.0, 470.0, h) * 0.55)
	return clampf(s, 0.0, 1.0)


func forest(x: float, z: float, h: float, sl: float) -> float:
	var warm := smoothstep(-330.0, -80.0, z)
	var low := smoothstep(360.0, 260.0, h)
	var flat := smoothstep(0.52, 0.26, sl)
	var d := river_dist(x, z)
	var damp := smoothstep(300.0, 60.0, d)
	var n := n_mask.get_noise_2d(x * 2.3 - 310.0, z * 2.3 + 150.0)
	return clampf(warm * low * flat * (0.62 + 0.38 * damp) * (0.72 + 0.38 * n), 0.0, 1.0)


func rock(x: float, z: float, h: float, sl: float) -> float:
	return clampf(smoothstep(0.30, 0.55, sl) + smoothstep(660.0, 820.0, h) * 0.45, 0.0, 1.0)
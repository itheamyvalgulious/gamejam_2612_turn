class_name TerrainGen
extends RefCounted
## Procedural heightfield + biome/splat generation for a ~10 km^2 natural terrain.
## Everything is computed from math (layered value/simplex noise, ridged multifractal,
## analytic river-valley carving, latitude/altitude climate model). No external data.

# ---- world extents (exactly 10 km^2) ----
const WORLD_X := 4000.0
const WORLD_Z := 2500.0
const CELL := 5.0
const NX := int(WORLD_X / CELL)   # 800 cells -> 801 verts
const NZ := int(WORLD_Z / CELL)   # 500 cells -> 501 verts
const VX := NX + 1
const VZ := NZ + 1

# climate / layout
const SNOW_Z := 0.0          # north edge (cold)
const JUNGLE_Z := WORLD_Z    # south edge (warm)
const MTN_CENTER := 1250.0   # mountain belt center (z)
const MTN_HALF := 520.0      # mountain belt half width

# river water level from north (high) to south (low)
const RIVER_WL_N := 96.0
const RIVER_WL_S := 6.0

var height := PackedFloat32Array()
var splat := PackedFloat32Array()   # RGBA = grass, rock, snow, sand
var temp := PackedFloat32Array()    # temperature proxy 0..1 (1 = hot)
var moist := PackedFloat32Array()   # moisture proxy 0..1
var water_level := PackedFloat32Array()  # per-vertex standing-water level (river/lake), -1 if none

# noise sources
var _n_cont: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_moist: FastNoiseLite
var _n_warp: FastNoiseLite
var _n_micro: FastNoiseLite

func _init() -> void:
	_n_cont = _mk(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 5, 0.0009, 11)
	_n_ridge = _mk(FastNoiseLite.TYPE_SIMPLEX, 5, 0.0022, 23)
	_n_detail = _mk(FastNoiseLite.TYPE_SIMPLEX, 4, 0.011, 37)
	_n_moist = _mk(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4, 0.0016, 51)
	_n_warp = _mk(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3, 0.0007, 71)
	_n_micro = _mk(FastNoiseLite.TYPE_SIMPLEX, 3, 0.05, 91)

func _mk(t: int, oct: int, freq: float, seed: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = t
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	n.fractal_lacunarity = 2.03
	n.fractal_gain = 0.5
	n.frequency = freq
	n.seed = seed
	return n

# ---------------------------------------------------------------- river centerline
## Meandering river x-position as a function of z (river flows north -> south).
func river_x(z: float) -> float:
	var t := z / WORLD_Z
	var base := WORLD_X * 0.5
	# broad meander + secondary wiggle; amplitude shrinks inside the mountain gorge
	var amp := 420.0 * (0.35 + 0.65 * smoothstep(0.0, 0.35, absf(t - 0.5) * 2.0))
	var x := base \
		+ amp * sin(t * 5.1 + 0.7) \
		+ 150.0 * sin(t * 11.7 + 2.1) \
		+ 60.0 * sin(t * 23.3 + 4.4)
	return clampf(x, 200.0, WORLD_X - 200.0)

## Standing water level along the river (downhill north -> south), plus a southern lake.
func river_wl(z: float) -> float:
	var t := clampf(z / WORLD_Z, 0.0, 1.0)
	# gentle downhill with a couple of steeper drops (waterfall steps)
	var wl := lerpf(RIVER_WL_N, RIVER_WL_S, t)
	wl -= 6.0 * smoothstep(0.42, 0.46, t) * (1.0 - smoothstep(0.50, 0.54, t))
	wl -= 5.0 * smoothstep(0.66, 0.70, t) * (1.0 - smoothstep(0.74, 0.78, t))
	return wl

# ---------------------------------------------------------------- helpers
static func smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func ridged(v: float) -> float:
	return 1.0 - absf(v)

# ---------------------------------------------------------------- generate
func generate() -> void:
	height.resize(VX * VZ)
	splat.resize(VX * VZ * 4)
	temp.resize(VX * VZ)
	moist.resize(VX * VZ)
	water_level.resize(VX * VZ)

	for iz in range(VZ):
		var z := iz * CELL
		var tz := z / WORLD_Z                       # 0 north .. 1 south
		var rz := river_x(z)
		var wl := river_wl(z)
		# mountain belt mask (smooth)
		var mtn := 1.0 - smoothstep(MTN_HALF * 0.55, MTN_HALF, absf(z - MTN_CENTER))
		# snowfield mask (north) and jungle mask (south), with noisy boundary
		var bound_warp := _n_warp.get_noise_2d(z * 0.5, 3.7) * 0.12
		var snow_band := 1.0 - smoothstep(0.30 + bound_warp, 0.46 + bound_warp, tz)
		var jungle_band := smoothstep(0.56 + bound_warp, 0.72 + bound_warp, tz)

		for ix in range(VX):
			var x := ix * CELL
			var i := iz * VX + ix

			# --- domain warp for organic shapes
			var wx := _n_warp.get_noise_2d(x, z) * 160.0
			var wz := _n_warp.get_noise_2d(x + 999.0, z - 777.0) * 160.0
			var px := x + wx
			var pz := z + wz

			# --- continental base (rolling land)
			var cont := _n_cont.get_noise_2d(px, pz)          # -1..1
			var base := 30.0 + cont * 26.0

			# --- snowfield plateau: smooth, elevated, gently undulating with dunes
			var plateau := 120.0 + _n_cont.get_noise_2d(px * 0.6, pz * 0.6) * 22.0 \
				+ _n_cont.get_noise_2d(px * 0.25 + 5.0, pz * 0.25) * 16.0 \
				+ _n_detail.get_noise_2d(px * 0.3, pz * 0.9) * 8.0 \
				+ _n_detail.get_noise_2d(px, pz) * 4.0
			base = lerpf(base, plateau, snow_band * 0.9)

			# --- jungle lowland: low, humid, small hills (kept above lake level)
			var lowland := 20.0 + _n_cont.get_noise_2d(px * 1.4, pz * 1.4) * 8.0 \
				+ _n_detail.get_noise_2d(px * 1.5, pz * 1.5) * 3.0
			base = lerpf(base, lowland, jungle_band * 0.9)

			# --- mountain belt: ridged multifractal peaks + cliffs
			var rr := ridged(_n_ridge.get_noise_2d(px * 0.55, pz * 1.5))
			rr = pow(rr, 1.5)
			var rp := ridged(_n_ridge.get_noise_2d(px * 1.3 + 31.0, pz * 1.3 - 17.0))
			rp = pow(rp, 2.0)
			var valley_n := _n_cont.get_noise_2d(px * 0.5 + 77.0, pz * 0.5 - 41.0)
			var valley_mask := smoothstep(-0.1, 0.6, valley_n)
			var mtn_h := (rr * 230.0 * valley_mask + rp * 90.0) * mtn
			# terraced cliff strata: quantize part of the height for rock shelves
			var strata: float = floorf(mtn_h / 30.0) * 30.0
			mtn_h = lerpf(mtn_h, strata, 0.3 * mtn * smoothstep(60.0, 180.0, mtn_h))
			base += mtn_h
			# extra high-ridge sharpening
			base += mtn * smoothstep(0.6, 0.95, rr) * 30.0

			# --- micro detail everywhere
			base += _n_micro.get_noise_2d(x, z) * 1.6
			base += _n_detail.get_noise_2d(px * 3.0, pz * 3.0) * 2.2 * (1.0 - mtn * 0.5)

			# --- river valley carving
			var dx := absf(x - rz)
			# valley half-width: wide U in plains, narrow V gorge in mountains
			var gorge := mtn
			var half_w := lerpf(160.0, 80.0, gorge)
			var depth := lerpf(30.0, 170.0, gorge)
			var vd := dx / half_w
			var carve := 0.0
			if vd < 1.0:
				# U shape in plains, V shape in gorge
				var u := (1.0 - vd * vd)
				var v := (1.0 - vd)
				carve = lerpf(u, pow(v, 1.35), gorge) * depth
			# smooth outer shoulder
			var shoulder := (1.0 - smoothstep(1.0, 2.4, vd)) * depth * 0.25
			var bed := wl - lerpf(3.0, 8.0, gorge)   # riverbed below water level
			var carved := base - carve - shoulder
			carved = maxf(carved, bed - 2.0)
			base = carved

			# --- southern lake basin
			var lake_c := Vector2(WORLD_X * 0.5, WORLD_Z * 0.93)
			var dl := Vector2(x - lake_c.x, (z - lake_c.y) * 1.6).length()
			var lake := 1.0 - smoothstep(380.0, 700.0, dl)
			var lake_bed := 2.0
			base = lerpf(base, minf(base, lake_bed), lake)

			height[i] = base

			# --- climate
			var alt := base
			var t := 1.0 - tz * 0.0                      # placeholder
			var temperature := (1.0 - tz)                # north=1(cold)? invert: we want north cold
			temperature = tz                             # 0 north(cold) .. 1 south(hot)
			temperature -= alt * 0.0009                  # lapse rate
			temperature = clampf(temperature * 1.35 + 0.12, 0.0, 1.0)
			var m := _n_moist.get_noise_2d(px, pz) * 0.5 + 0.5
			m = m * 0.6 + jungle_band * 0.35 + (1.0 - smoothstep(0.0, 60.0, absf(dx))) * 0.2
			m = clampf(m, 0.0, 1.0)
			temp[i] = temperature
			moist[i] = m
			water_level[i] = wl if dx < half_w * 2.6 else (-1.0 if lake <= 0.0 else wl)
			if lake > 0.0:
				water_level[i] = RIVER_WL_S + 1.0

			# --- splat weights: grass, rock, snow, sand
			var slope := 0.0  # computed after; approximate with local noise for now, refine below
			var snow_w := (1.0 - smoothstep(0.30, 0.42, temperature)) * snow_band
			snow_w = maxf(snow_w, (1.0 - smoothstep(0.28, 0.40, temperature)))  # snow caps by temp
			var jungle_w := jungle_band * smoothstep(0.35, 0.55, m) * (1.0 - smoothstep(120.0, 200.0, alt))
			var grass_w := maxf(jungle_w, (1.0 - jungle_band) * (1.0 - snow_band) * 0.8)
			grass_w = maxf(grass_w, jungle_w)
			var rock_w := mtn * 0.9 + smoothstep(150.0, 260.0, alt) * 0.8
			grass_w *= (1.0 - mtn * 0.75)
			rock_w += mtn * 0.3
			var sand_w := (1.0 - smoothstep(2.0, 9.0, absf(base - wl))) * (1.0 - snow_band) * 0.9
			sand_w = maxf(sand_w, lake * (1.0 - smoothstep(1.0, 6.0, absf(base - (RIVER_WL_S + 1.0)))) * 0.9)
			# normalize
			var tot := grass_w + rock_w + snow_w + sand_w + 1e-5
			splat[i * 4 + 0] = grass_w / tot
			splat[i * 4 + 1] = rock_w / tot
			splat[i * 4 + 2] = snow_w / tot
			splat[i * 4 + 3] = sand_w / tot

	# --- second pass: slope-aware rock boost using real normals
	_refine_slope()

func _refine_slope() -> void:
	for iz in range(1, VZ - 1):
		for ix in range(1, VX - 1):
			var i := iz * VX + ix
			var hl := height[i - 1]
			var hr := height[i + 1]
			var hd := height[i - VX]
			var hu := height[i + VX]
			var sx := (hr - hl) / (2.0 * CELL)
			var sz := (hu - hd) / (2.0 * CELL)
			var slope := sqrt(sx * sx + sz * sz)   # tan of slope
			var rock_boost := smoothstep(0.55, 1.15, slope)
			var snow_keep := 1.0 - smoothstep(0.9, 1.6, slope) * 0.7
			var g := splat[i * 4 + 0]
			var r := splat[i * 4 + 1]
			var s := splat[i * 4 + 2]
			var a := splat[i * 4 + 3]
			r = minf(1.0, r + rock_boost * (g * 0.85 + s * 0.35 + a * 0.5))
			g *= (1.0 - rock_boost * 0.85)
			s *= snow_keep
			a *= (1.0 - rock_boost * 0.7)
			var tot := g + r + s + a + 1e-5
			splat[i * 4 + 0] = g / tot
			splat[i * 4 + 1] = r / tot
			splat[i * 4 + 2] = s / tot
			splat[i * 4 + 3] = a / tot

# ---------------------------------------------------------------- sampling
func _idx(ix: int, iz: int) -> int:
	return iz * VX + ix

func height_at(x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, NX - 0.001)
	var fz := clampf(z / CELL, 0.0, NZ - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := height[_idx(ix, iz)]
	var h10 := height[_idx(ix + 1, iz)]
	var h01 := height[_idx(ix, iz + 1)]
	var h11 := height[_idx(ix + 1, iz + 1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func splat_at(x: float, z: float) -> Vector4:
	var fx := clampf(x / CELL, 0.0, NX - 0.001)
	var fz := clampf(z / CELL, 0.0, NZ - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var i := _idx(ix, iz)
	return Vector4(splat[i * 4], splat[i * 4 + 1], splat[i * 4 + 2], splat[i * 4 + 3])

func temp_at(x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, NX - 0.001)
	var fz := clampf(z / CELL, 0.0, NZ - 0.001)
	return temp[_idx(int(fx), int(fz))]

func moist_at(x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, NX - 0.001)
	var fz := clampf(z / CELL, 0.0, NZ - 0.001)
	return moist[_idx(int(fx), int(fz))]

func normal_at(x: float, z: float) -> Vector3:
	var e := CELL
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()

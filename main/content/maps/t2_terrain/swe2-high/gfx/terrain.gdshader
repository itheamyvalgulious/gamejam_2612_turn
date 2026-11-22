// terrain.gdshader — biome splat surface for the Vale.
// COLOR packs weights: r=snow, g=rock, b=jungle, a=sand.
// UV = world XZ metres. All detail is procedural + distance-faded so
// nothing blurs or moirés at range.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://gfx/common.gdshaderinc"

uniform vec3 snow_col   : source_color = vec3(0.96, 0.97, 1.05);
uniform vec3 snow_shad  : source_color = vec3(0.70, 0.78, 0.98);
uniform vec3 rock_lo    : source_color = vec3(0.32, 0.28, 0.24);
uniform vec3 rock_hi    : source_color = vec3(0.54, 0.48, 0.40);
uniform vec3 rock_moss  : source_color = vec3(0.23, 0.38, 0.16);
uniform vec3 jung_lo    : source_color = vec3(0.07, 0.13, 0.05);
uniform vec3 jung_hi    : source_color = vec3(0.15, 0.26, 0.08);
uniform vec3 jung_dirt  : source_color = vec3(0.28, 0.22, 0.13);
uniform vec3 sand_col   : source_color = vec3(0.42, 0.34, 0.22);   // wet pebble shore, not bright beach
uniform vec3 mead_lo    : source_color = vec3(0.22, 0.22, 0.10);   // dry-steppe meadow
uniform vec3 mead_hi    : source_color = vec3(0.38, 0.35, 0.16);
uniform vec3 ley_col    : source_color = vec3(0.15, 0.55, 0.48);
uniform float detail_amp = 1.0;

varying vec3 wpos;
varying vec4 splat;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// splat weights ride in CUSTOM0 (COLOR can be dropped by the driver
	// when material_override is used on an ArrayMesh)
	splat = CUSTOM0;
	wnorm = NORMAL;
}

void fragment() {
	vec2 uv = wpos.xz;
	float px = max(fwidth(uv.x), fwidth(uv.y));   // metres per pixel
	// micro detail survives to ~1.5 m/px so close-range shots still show
	// ground grain; macro mottle fades by ~3 m/px to kill far-field lanes
	float micro = 1.0 - smoothstep(0.06, 1.5, px);
	float macro = 1.0 - smoothstep(0.4, 8.0, px);

	vec4 w = splat / max(splat.r + splat.g + splat.b + splat.a, 0.001);

	// ------------------------------------------------------------- snow --
	vec2 sas_dir = vec2(0.86, 0.5);                  // wind-aligned ripples
	float sas = sin(dot(uv, sas_dir) * 1.7 + fbm(uv * 0.14, 3) * 9.0);
	float drift = fbm(uv * 0.045, 4);
	vec3 snow = mix(snow_shad, snow_col,
		0.72 + sas * 0.10 * micro + drift * 0.28);
	// sparse glints: tiny voronoi centres sparkle only up close
	vec3 sp = worley(uv * 7.0);
	float glint = step(0.985, 1.0 - sp.x) * micro;
	snow += vec3(0.55) * glint;

	// ------------------------------------------------------------- rock --
	// Triplanar: steep faces sample in the YZ/XY plane so detail doesn't
	// stretch into vertical "drapery" stripes on cliffs.
	vec3 an = abs(wnorm);
	float cliff_w = 1.0 - smoothstep(0.45, 0.75, an.y);
	vec2 cliff_uv = (an.x > an.z) ? wpos.zy : wpos.xy;

	float wy = wpos.y + fbm(uv * 0.05, 3) * 12.0;
	float band = fbm(vec2(wy * 0.045, h21(floor(uv * 0.02)) * 8.0), 3);
	// blocky jointed rock, not sinusoidal ridges — fbm cells + sharp
	// fracture pockets so faces break into slabs, not drawn-on curves
	float crag = fbm(cliff_uv * 0.09, 4);
	float frac_pok = smoothstep(0.72, 0.85, fbm(cliff_uv * 0.35, 3));
	crag = mix(crag, crag * 0.35, frac_pok);
	vec3 rock = mix(rock_lo, rock_hi, band);
	rock = mix(rock, mix(rock_lo * 0.75, rock_hi * 1.1, crag), cliff_w);
	// vertical fracture seams — steep walls get dark crack lines so the
	// face reads as jointed rock, not smeared clay
	// fracture seams removed — the crag fbm already reads as jointed
	// rock; drawn-on crack curves looked like doodles on the walls
	// strata grooves removed — they printed as continuous wavy lines
	// across every face. Bedding comes from the rock fbm bands instead.
	float groove = 0.0;
	// crumble speckle (planar on flats, triplanar on cliffs)
	float crumb_flat = fbm(uv * 0.8, 3);
	float crumb_cliff = fbm(cliff_uv * 0.8, 3);
	rock *= 0.9 + mix(crumb_flat, crumb_cliff, cliff_w) * 0.2 * micro;
	// moss creep on flat-ish, lower rock — jungle-side patina only; the
	// gorge floor stays bare stone
	float moss = fbm(uv * 0.11 + 40.0, 4) * (1.0 - w.r) *
		smoothstep(200.0, 60.0, wpos.y) * (1.0 - cliff_w) *
		smoothstep(360.0, 480.0, wpos.z);
	rock = mix(rock, rock_moss, clamp(moss - 0.35, 0.0, 0.45));

	// ----------------------------------------------------------- jungle --
	// low-contrast mottle: strong fbm bands print as lane markings from
	// altitude, so keep the modulation shallow and let canopy cover do
	// the visual work
	float jmot = fbm(uv * 0.09, 4);
	float jfine = fbm(uv * 0.55, 3);
	vec3 jung = mix(jung_lo, jung_hi, clamp(0.35 + jmot * 0.5 + jfine * 0.35 * micro, 0.0, 1.0));
	// canopy-floor dirt + leaf-litter patches along noise lanes
	float dirt = smoothstep(0.60, 0.80, fbm(uv * 0.07 + 91.0, 3));
	jung = mix(jung, jung_dirt, dirt * 0.55 * macro);
	// dark humus pools under stands — deep shadow pockets make the
	// forest floor read as shaded, not sunlit carpet
	float humus = smoothstep(0.55, 0.78, fbm(uv * 0.05 + 33.0, 4));
	jung = mix(jung, jung_lo * 0.4, humus * 0.65 * macro);
	// leaf litter: warm-brown speckle drift only in close view — broad
	// mottled patches under the canopy so the floor never reads flat
	float litter = fbm(uv * 0.9 + 61.0, 4);
	float lit_band = smoothstep(0.50, 0.72, litter) * micro;
	jung = mix(jung, vec3(0.16, 0.12, 0.06), lit_band * 0.75);
	// mossy stones: cool grey-green blotches at mid scale
	float moss_st = smoothstep(0.68, 0.82, fbm(uv * 0.23 + 97.0, 3));
	jung = mix(jung, vec3(0.16, 0.22, 0.14), moss_st * 0.4 * macro);
	// bare-earth patches: irregular clearings where litter fails —
	// breaks the monotony of moss-green at any range
	float barren = smoothstep(0.62, 0.78, fbm(uv * 0.11 + 51.0, 3));
	jung = mix(jung, vec3(0.22, 0.17, 0.09), barren * 0.5 * macro);
	// grass tufts: sparse bright flecks that only survive in close view —
	// jittered within-cell points, not whole quads
	vec2 tc = floor(uv * 4.0);
	vec2 tf = fract(uv * 4.0);
	float tuft = step(0.975, h21(tc)) *
		smoothstep(0.30, 0.12, length(tf - vec2(0.25 + 0.5 * h21(tc + 3.0), 0.25 + 0.5 * h21(tc + 9.0)))) * micro;
	jung += vec3(0.08, 0.12, 0.02) * tuft;
	float vein = 0.0;   // ley veins removed: read as lane markings at range
	// ------------------------------------------------------------- sand --
	// pebbled shore: wet gravel with noise pockets, not flat sand
	float dune = sin(uv.x * 0.35 + fbm(uv * 0.1, 3) * 5.0);
	vec3 sand = sand_col * (0.80 + dune * 0.07 + fbm(uv * 0.4, 2) * 0.12 * micro);
	float peb = fbm(uv * 1.4 + 23.0, 3);
	sand = mix(sand, sand * vec3(0.55, 0.5, 0.42), smoothstep(0.62, 0.80, peb) * micro);

	// ----------------------------------------------------------- blend ---
	vec3 col = snow * w.r + rock * w.g + jung * w.b + sand * w.a;
	// meadow takeover: flat, low "rock" ground between the massif and the
	// basin is dry steppe, not bare stone — the band*0.35 splat term would
	// otherwise paint a thousand-square-kilometre slab of brown rock
	float meadow = w.g * smoothstep(0.4, 0.15, w.b) * smoothstep(0.65, 0.9, an.y) *
		smoothstep(150.0, 60.0, wpos.y) *
		smoothstep(-180.0, -40.0, wpos.z) * smoothstep(300.0, 450.0, wpos.z) *
		smoothstep(40.0, 90.0, wpos.y);
	float m_mot = fbm(uv * 0.06 + 17.0, 4);
	vec3 mead = mix(mead_lo, mead_hi, clamp(0.3 + m_mot * 0.7 + jfine * 0.2 * micro, 0.0, 1.0));
	mead = mix(mead, jung_dirt, smoothstep(0.62, 0.8, fbm(uv * 0.045 + 55.0, 3)) * 0.45 * macro);
	col = mix(col, mead, meadow * 0.9);
	col += ley_col * vein * 0.35 * macro;

	// roughness + normal micro
	float rough = 0.55 * w.r + 0.9 * w.g + 0.92 * w.b + 0.8 * w.a;
	float hgt = drift * w.r + band * w.g + jfine * w.b + (dune * 0.5 + 0.5) * w.a;
	// jungle floor relief: roots / litter mounds at 0.3–2 m scale
	float jrel = fbm(uv * 0.9 + 7.0, 4) * 0.6 + fbm(uv * 3.1 + 13.0, 3) * 0.4;
	hgt += jrel * w.b * 0.8;

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.4, 0.95);
	SPECULAR = 0.22 + glint * 0.5;
	METALLIC = 0.0;
	EMISSION = ley_col * vein * 0.08 * macro;
	// crease AO from strata grooves only where rock wins
	AO = 1.0 - groove * 0.3 * w.g * macro;
	NORMAL = bumpn(wnorm, VERTEX, hgt * detail_amp, 0.9 * micro + 0.2);
}

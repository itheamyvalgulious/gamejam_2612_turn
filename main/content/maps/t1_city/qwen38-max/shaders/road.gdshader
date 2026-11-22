shader_type spatial;
// Asphalt v2: aggregate, crack network w/ bump, repairs, tire wear tracks,
// manholes, puddles with neon reflection + moon glint, worn markings.
// UV.x = meters along road, UV.y = across normalized -1..1.
uniform bool show_markings = true;
uniform vec4 haze_col : source_color = vec4(0.085, 0.055, 0.15, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.6;
varying float vdist;
varying float vhy;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.07 + 13.3; a *= 0.5; }
	return v;
}
float ridged(vec2 p) {
	return 1.0 - abs(2.0 * fbm(p) - 1.0);
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec2 uvw = vec2(UV.x, UV.y * 10.0);
	float n = fbm(uvw * 0.6);
	float fine = fbm(uvw * 6.0);
	float agg = vnoise(uvw * 22.0);           // aggregate speckle
	vec3 asphalt = mix(vec3(0.026, 0.026, 0.030), vec3(0.062, 0.060, 0.064), n);
	asphalt *= 0.72 + 0.45 * fine;
	asphalt += (agg - 0.5) * 0.012;

	// crack network
	float crack = smoothstep(0.80, 0.95, ridged(uvw * 0.35 + 11.0));
	asphalt *= 1.0 - crack * 0.6;
	// patch repairs (different tone + roughness)
	float patch = smoothstep(0.62, 0.75, fbm(uvw * 0.15 + 40.0));
	asphalt = mix(asphalt, asphalt * 1.6 + vec3(0.008), patch * 0.5);
	// tire wear tracks at lane positions
	float lane_t = smoothstep(0.10, 0.0, abs(abs(UV.y) - 0.42)) + smoothstep(0.10, 0.0, abs(abs(UV.y) - 0.72));
	asphalt *= 1.0 - lane_t * 0.22;
	// manholes / drains along center-ish
	float mh_cell = floor(UV.x / 37.0);
	float mh_present = step(0.72, hash21(vec2(mh_cell, 3.3)));
	float mh_u = fract(UV.x / 37.0);
	float mh_d = length((vec2(mh_u, UV.y * 0.5 + 0.25) - vec2(0.5, 0.0)) * vec2(2.4, 8.0));
	float manhole = mh_present * (1.0 - smoothstep(0.8, 0.9, mh_d));
	asphalt = mix(asphalt, vec3(0.045, 0.043, 0.040) * (0.7 + 0.6 * vnoise(uvw * 30.0)), manhole);

	vec3 v = vec3(0.0);
	float rough = 0.62 + 0.30 * n - lane_t * 0.10;
	rough = mix(rough, 0.75, patch * 0.5);
	rough = mix(rough, 0.5, manhole);

	if (show_markings) {
		float av = abs(UV.y);
		float along = UV.x;
		float cy = smoothstep(0.045, 0.030, abs(av - 0.028)) * smoothstep(0.0, 0.012, av);
		vec3 yellow = vec3(0.85, 0.65, 0.1);
		float edge = smoothstep(0.90, 0.885, av) * smoothstep(0.86, 0.875, av);
		float lane_pos = abs(av - 0.46);
		float dash = smoothstep(0.035, 0.020, lane_pos) * step(0.5, fract(along / 9.0));
		float wear = 0.45 + 0.55 * fbm(vec2(along * 2.0, UV.y * 30.0));
		wear *= 1.0 - crack * 0.7;
		asphalt = mix(asphalt, yellow * 0.55, cy * wear);
		asphalt = mix(asphalt, vec3(0.45) * 0.55, (edge + dash) * wear);
		v = vec3(cy * yellow + (edge + dash) * vec3(0.4)) * 0.25 * wear;
		rough = mix(rough, 0.42, max(cy, max(edge, dash)) * wear);
	}

	// puddles: metaball-ish noise, mirror roughness, neon + moon reflection
	float pud = smoothstep(0.62, 0.80, fbm(uvw * 0.22 + 17.0));
	pud *= 1.0 - smoothstep(0.85, 1.0, abs(UV.y));   // crown drains at edges
	rough = mix(rough, 0.05, pud);
	vec3 puddle_neon = mix(vec3(0.9, 0.25, 0.5), vec3(0.2, 0.8, 1.0), step(0.5, hash21(floor(vec2(UV.x / 9.0, 1.0)))));
	puddle_neon = mix(puddle_neon, vec3(1.0, 0.7, 0.25), step(0.8, hash21(floor(vec2(UV.x / 9.0, 5.0)))));
	float ripple = 0.6 + 0.4 * sin(UV.x * 3.1 + UV.y * 40.0 + TIME * 1.5);
	v += pud * puddle_neon * 0.10 * ripple * smoothstep(0.3, 0.9, abs(UV.y));
	v += pud * vec3(0.5, 0.55, 0.7) * 0.03;          // moon/sky glint

	// storefront neon spill washing curb lanes
	float edge_d = smoothstep(0.70, 0.98, abs(UV.y));
	vec3 shopcol = mix(vec3(1.0, 0.3, 0.55), vec3(0.25, 0.9, 1.0), step(0.5, hash21(vec2(floor(UV.x / 7.0), 1.7))));
	shopcol = mix(shopcol, vec3(1.0, 0.7, 0.25), step(0.8, hash21(vec2(floor(UV.x / 7.0), 4.2))));
	float spillm = edge_d * (0.05 + 0.20 * pud) * (0.65 + 0.35 * sin(UV.x * 0.9 + hash21(vec2(floor(UV.x / 7.0), 0.0)) * 6.0));
	v += shopcol * spillm;
	rough = mix(rough, 0.12, edge_d * pud);

	// city skyglow floor lift
	v += vec3(0.014, 0.011, 0.022) * (0.6 + 0.8 * n);

	// crack bump
	vec2 bw = fwidth(UV);
	float c0 = ridged(uvw * 0.35 + 11.0);
	float cx = ridged((uvw + vec2(bw.x * 60.0, 0.0)) * 0.35 + 11.0) - c0;
	float cyy = ridged((uvw + vec2(0.0, bw.y * 60.0)) * 0.35 + 11.0) - c0;
	NORMAL = normalize(NORMAL - (TANGENT * (cx / max(bw.x, 1e-6)) + BINORMAL * (cyy / max(bw.y, 1e-6))) * 0.004);

	ALBEDO = asphalt;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	EMISSION = v;

	// aerial perspective + height fog
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * haze_den * hfac - vdist * vdist * 3.5e-8);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
}

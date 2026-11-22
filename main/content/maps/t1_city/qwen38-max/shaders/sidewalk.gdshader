shader_type spatial;
// Sidewalk v2: paving slabs with joints, curb chips, gum stains, litter,
// wall-edge grime, storefront neon spill band at building edge.
// UV.x = meters along, UV.y = meters across (0 = curb, UV2.x = width).
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
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.11 + 9.3; a *= 0.5; }
	return v;
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// paving slabs 1.5 m grid, per-slab tone + joints
	vec2 slab = vec2(UV.x / 1.5, UV.y / 1.5);
	vec2 sid = floor(slab);
	vec2 sf = fract(slab);
	float joint = smoothstep(0.05, 0.0, min(min(sf.x, 1.0 - sf.x), min(sf.y, 1.0 - sf.y)));
	float slabtone = 0.8 + 0.4 * hash21(sid + 7.7);
	vec3 c = vec3(0.155, 0.155, 0.175) * slabtone;
	c *= 0.75 + 0.5 * fbm(UV * 2.2);
	c *= 1.0 - joint * 0.55;
	// gum spots + litter specks
	float gum = step(0.965, hash21(floor(slab * 3.0) + 31.0));
	c *= 1.0 - gum * 0.5;
	float litter = step(0.992, hash21(floor(slab * 6.0) + 77.0));
	c += litter * vec3(0.10, 0.09, 0.08);
	// grime gradient toward wall edge + curb wear
	float sw = max(UV2.x, 2.0);
	c *= 1.0 - 0.35 * smoothstep(sw - 1.2, sw, UV.y);
	c *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.35, UV.y));

	float rough = 0.85;
	vec3 emis = vec3(0.0);

	// storefront neon spill band
	float band = smoothstep(max(sw - 1.8, 0.0), sw - 0.3, UV.y);
	vec3 shopcol = mix(vec3(1.0, 0.3, 0.55), vec3(0.25, 0.9, 1.0), step(0.5, hash21(vec2(floor(UV.x / 7.0), 1.7))));
	shopcol = mix(shopcol, vec3(1.0, 0.7, 0.25), step(0.8, hash21(vec2(floor(UV.x / 7.0), 4.2))));
	float flick = (0.45 + 0.55 * vnoise(vec2(UV.x * 1.3, 2.2))) * (0.7 + 0.3 * vnoise(vec2(UV.x * 0.5, 7.7)));
	emis += band * shopcol * 0.09 * flick;
	rough = mix(rough, 0.4, band * 0.6);
	// wet patches hold reflections
	float wet = smoothstep(0.6, 0.85, fbm(UV * 0.5 + 13.0));
	rough = mix(rough, 0.18, wet * 0.7);
	emis += wet * band * shopcol * 0.05;
	// skyglow lift
	emis += vec3(0.014, 0.012, 0.024) * (0.5 + 0.8 * fbm(UV * 1.5));

	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.06;
	EMISSION = emis;

	// aerial perspective + height fog
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * haze_den * hfac - vdist * vdist * 3.5e-8);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
}

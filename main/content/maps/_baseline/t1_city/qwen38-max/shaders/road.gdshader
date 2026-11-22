shader_type spatial;
uniform vec4 haze_col : source_color = vec4(0.055, 0.04, 0.105, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.5;
// Asphalt with procedural markings.
// UV.x = meters along road, UV.y = across, normalized -1..1 (edge to edge).
uniform bool show_markings = true;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.3, 7.7);
		a *= 0.5;
	}
	return v;
}

varying float vdist;
varying float vhy;

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec2 uvw = vec2(UV.x, UV.y * 10.0);
	float n = fbm(uvw * 0.6);
	float fine = fbm(uvw * 6.0);
	vec3 asphalt = mix(vec3(0.028, 0.028, 0.032), vec3(0.06, 0.058, 0.062), n);
	asphalt *= 0.75 + 0.5 * fine;
	// patches / repairs
	float patch = smoothstep(0.62, 0.75, fbm(uvw * 0.15 + 40.0));
	asphalt = mix(asphalt, asphalt * 1.5, patch * 0.4);

	vec3 v = vec3(0.0);
	float rough = 0.55 + 0.35 * n;

	if (show_markings) {
		float av = abs(UV.y);
		float along = UV.x;
		// center double yellow
		float cy = smoothstep(0.045, 0.03, abs(av - 0.028)) * smoothstep(0.0, 0.012, av);
		vec3 yellow = vec3(0.85, 0.65, 0.1);
		// edge lines
		float edge = smoothstep(0.90, 0.885, av) * smoothstep(0.86, 0.875, av);
		// lane dashes between center and edge
		float lane_pos = abs(av - 0.46);
		float dash = smoothstep(0.035, 0.02, lane_pos) * step(0.5, fract(along / 9.0));
		float wear = 0.55 + 0.45 * fbm(vec2(along * 2.0, UV.y * 30.0));
		asphalt = mix(asphalt, yellow * 0.55, cy * wear);
		asphalt = mix(asphalt, vec3(0.45) * 0.55, (edge + dash) * wear);
		v = vec3(cy * yellow + (edge + dash) * vec3(0.4)) * 0.25 * wear;
		rough = mix(rough, 0.4, max(cy, max(edge, dash)));
	}

	// wet sheen: puddles reflect a hint of neon
	float pud = smoothstep(0.55, 0.8, fbm(uvw * 0.25 + 17.0));
	rough = mix(rough, 0.06, pud);
	vec3 puddle_glow = mix(vec3(0.4, 0.1, 0.5), vec3(0.1, 0.4, 0.5), hash21(floor(uvw * 0.02))) * pud * 0.08;
	// storefront neon spill washing the curb lanes (wet reflection)
	float edge_d = smoothstep(0.70, 0.98, abs(UV.y));
	vec3 shopcol = mix(vec3(1.0, 0.3, 0.55), vec3(0.25, 0.9, 1.0), step(0.5, hash21(vec2(floor(UV.x / 7.0), 1.7))));
	shopcol = mix(shopcol, vec3(1.0, 0.7, 0.25), step(0.8, hash21(vec2(floor(UV.x / 7.0), 4.2))));
	float spillm = edge_d * (0.05 + 0.18 * pud) * (0.65 + 0.35 * sin(UV.x * 0.9 + hash21(vec2(floor(UV.x / 7.0), 0.0)) * 6.0));
	v += shopcol * spillm;
	rough = mix(rough, 0.12, edge_d * pud);
	// city skyglow floor lift
	v += vec3(0.014, 0.011, 0.022) * (0.6 + 0.8 * n);

	// aerial perspective + height fog
	SPECULAR = 0.06;
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * 0.00022 * hfac);
	ALBEDO = mix(asphalt, vec3(0.085, 0.055, 0.15), hz);
	ROUGHNESS = rough;
	METALLIC = 0.0;
	EMISSION = mix(v + puddle_glow, vec3(0.085, 0.055, 0.15) * 1.1 *
			(0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
}



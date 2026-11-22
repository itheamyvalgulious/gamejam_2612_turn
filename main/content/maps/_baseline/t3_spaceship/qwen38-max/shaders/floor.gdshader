shader_type spatial;
render_mode specular_schlick_ggx;

// Deck plating: staggered floor plates, anti-slip grain, scuffs, oil,
// faint stencil markings, optional hazard stripes and gloss variant.

uniform float u_grime : hint_range(0.0, 1.6) = 0.5;
uniform float u_gloss : hint_range(0.0, 1.0) = 0.0;
uniform float u_hazard : hint_range(0.0, 1.0) = 0.0;
uniform vec3 u_base = vec3(0.19, 0.2, 0.225);
uniform vec3 u_hazard_a = vec3(0.85, 0.62, 0.06);
uniform vec3 u_hazard_b = vec3(0.06, 0.06, 0.07);
uniform vec3 u_stencil = vec3(0.42, 0.4, 0.2);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.27);
	return fract(p.x * p.y * 95.43);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec2 uv = wpos.xz;
	// staggered plates 2m x 1m
	float row = floor(uv.y);
	float off = mod(row, 2.0) * 0.5;
	vec2 g = vec2((uv.x + off) / 2.0, uv.y);
	vec2 id = floor(g);
	vec2 f = fract(g);
	float hs = hash21(id + COLOR.a * 17.0);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float seam = 1.0 - smoothstep(0.0, 0.017, d);
	float bevel = (1.0 - smoothstep(0.017, 0.04, d)) * smoothstep(0.005, 0.017, d);

	float grain = vnoise(uv * 160.0) * 0.35 + vnoise(uv * 61.0) * 0.2;
	float scuff = smoothstep(0.55, 0.9, fbm(uv * 1.6 + 8.0));
	float oil = smoothstep(0.62, 0.92, fbm(uv * 0.8 + 23.0)) * u_grime;
	float dirt = fbm(uv * 0.4 + 3.0) * u_grime * 0.4;

	vec3 alb = u_base * COLOR.rgb;
	alb *= (0.92 + 0.16 * fract(hs * 7.7));
	alb *= (1.0 - seam * 0.55);
	alb = mix(alb, vec3(0.4, 0.41, 0.42), bevel * 0.35);
	alb = mix(alb, alb * 1.12 + vec3(0.02), scuff * 0.25);
	alb = mix(alb, vec3(0.04, 0.033, 0.026), oil * 0.8);
	alb *= (1.0 - dirt * 0.4);

	// faint stencil marking in some 8m cells
	vec2 cid = floor(uv / 8.0);
	float ch = hash21(cid + 41.0);
	if (ch > 0.995) {
		vec2 cf = fract(uv / 8.0);
		float band = step(0.42, cf.x) * step(cf.x, 0.58) * step(0.3, cf.y) * step(cf.y, 0.7);
		float chev = step(0.5, fract((cf.y - cf.x) * 6.0)) * band;
		alb = mix(alb, u_stencil * 0.3, chev * 0.12);
	}

	// hazard stripes (airlocks / engine core ring)
	if (u_hazard > 0.01) {
		float hz = step(0.5, fract((uv.x + uv.y) * 0.65));
		vec3 hcol = mix(u_hazard_b, u_hazard_a, hz);
		alb = mix(alb, hcol, u_hazard);
	}

	float rough = 0.7 + grain * 0.12 + scuff * 0.12 + dirt * 0.25 - oil * 0.12 - bevel * 0.1;
	rough = mix(rough, 0.18, u_gloss);
	float metal = mix(0.22, 0.4, u_gloss) * (1.0 - oil * 0.5);

	// height-based normal perturbation (seams + grain)
	float e = 0.05;
	vec2 uvp = uv + vec2(e, 0.0);
	vec2 uvq = uv + vec2(0.0, e);
	float h0 = -seam * 0.5 + grain * 0.06;
	float rowp = floor(uvp.y); float offp = mod(rowp, 2.0) * 0.5;
	vec2 gp = vec2((uvp.x + offp) / 2.0, uvp.y); vec2 fp = fract(gp);
	float dp = min(min(fp.x, 1.0 - fp.x), min(fp.y, 1.0 - fp.y));
	float hp = -(1.0 - smoothstep(0.0, 0.017, dp)) * 0.5 + vnoise(uvp * 160.0) * 0.35 * 0.06;
	float rowq = floor(uvq.y); float offq = mod(rowq, 2.0) * 0.5;
	vec2 gq = vec2((uvq.x + offq) / 2.0, uvq.y); vec2 fq = fract(gq);
	float dq = min(min(fq.x, 1.0 - fq.x), min(fq.y, 1.0 - fq.y));
	float hq = -(1.0 - smoothstep(0.0, 0.017, dq)) * 0.5 + vnoise(uvq * 160.0) * 0.35 * 0.06;
	vec3 G = vec3((hp - h0) / e, 0.0, (hq - h0) / e);
	vec3 npert = n;  // flat-shaded normals come from geometry

	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.05, 0.95);
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = mix(0.5, 0.9, u_gloss);
	NORMAL = normalize((VIEW_MATRIX * vec4(npert, 0.0)).xyz);
}

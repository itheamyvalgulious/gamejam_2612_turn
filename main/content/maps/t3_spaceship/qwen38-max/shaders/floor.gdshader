shader_type spatial;
render_mode specular_schlick_ggx;

// Deck plating v2 — staggered plates with weld beads, worn paint markings,
// oil puddles (sharp-edge gloss), dust, traffic scuffs. Metric scale, reads
// at 1-2 m. Roughness/metal separated per layer.

uniform float u_grime : hint_range(0.0, 1.6) = 0.5;
uniform float u_gloss : hint_range(0.0, 1.0) = 0.0;
uniform float u_hazard : hint_range(0.0, 1.0) = 0.0;
uniform vec3 u_base = vec3(0.19, 0.2, 0.225);
uniform vec3 u_hazard_a = vec3(0.85, 0.62, 0.06);
uniform vec3 u_hazard_b = vec3(0.06, 0.06, 0.07);
uniform vec3 u_stencil = vec3(0.42, 0.4, 0.2);
uniform float u_dust : hint_range(0.0, 1.5) = 0.5;

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
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return v;
}

float wfbm(vec2 p) {
	vec2 q = vec2(fbm(p), fbm(p + vec2(5.2, 1.3)));
	return fbm(p + 1.5 * q);
}

// plate grid height: seams + weld bead + anti-slip grain + micro
float height_field(vec2 uv, float seedv) {
	float row = floor(uv.y);
	float off = mod(row, 2.0) * 0.5;
	vec2 g = vec2((uv.x + off) / 2.0, uv.y) + seedv;
	vec2 f = fract(g);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float groove = 1.0 - smoothstep(0.0, 0.016, d);
	float weld = (1.0 - smoothstep(0.016, 0.036, d)) * smoothstep(0.005, 0.016, d);
	weld *= 0.55 + 0.45 * sin((uv.x + uv.y) * 160.0);
	float grain = (vnoise(uv * 150.0) - 0.5) * 0.02 + (vnoise(uv * 40.0) - 0.5) * 0.015;
	return -groove * 0.45 + weld * 0.07 + grain;
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec2 uv = wpos.xz;
	float seedv = COLOR.a * 17.0;
	float row = floor(uv.y);
	float off = mod(row, 2.0) * 0.5;
	vec2 g = vec2((uv.x + off) / 2.0, uv.y) + seedv;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float hs = hash21(id);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float seam = 1.0 - smoothstep(0.0, 0.016, d);
	float bevel = (1.0 - smoothstep(0.016, 0.04, d)) * smoothstep(0.005, 0.016, d);
	float weld = (1.0 - smoothstep(0.016, 0.036, d)) * smoothstep(0.005, 0.016, d);
	weld *= 0.55 + 0.45 * sin((uv.x + uv.y) * 160.0);

	// traffic scuffs: anisotropic streaks along x + arc turns
	float scuff = smoothstep(0.5, 0.88, fbm(vec2(uv.x * 0.9, uv.y * 4.5) + 8.0)) * 0.6
		+ smoothstep(0.6, 0.9, fbm(vec2(uv.x * 3.0, uv.y * 3.0) + 40.0)) * 0.25;
	// oil puddles: sharp warped edges, glossy
	float pud = smoothstep(0.66, 0.70, wfbm(uv * 0.35 + 23.0));
	float oilfilm = smoothstep(0.55, 0.8, wfbm(uv * 1.4 + 61.0)) * 0.5;   // thin sheen outside puddle
	// grease smear near plate seams
	float grease = seam * smoothstep(0.5, 0.9, fbm(vec2(uv.x * 2.0, uv.y * 0.6) + 5.0)) * u_grime;
	float dust = (0.3 + 0.7 * fbm(uv * 1.3 + 71.0)) * u_dust * (0.4 + 0.6 * smoothstep(0.4, 0.9, fbm(uv * 0.22 + 3.0)));
	float grain = vnoise(uv * 160.0) * 0.35 + vnoise(uv * 61.0) * 0.2;

	vec3 alb = u_base * COLOR.rgb;
	alb *= (0.9 + 0.2 * fract(hs * 7.7));
	alb *= (1.0 - seam * 0.5);
	alb = mix(alb, vec3(0.42, 0.43, 0.45), bevel * 0.3);          // worn plate edges
	alb = mix(alb, vec3(0.5, 0.48, 0.44), weld * 0.3);            // weld discolor
	alb = mix(alb, alb * 1.15 + vec3(0.02), scuff * 0.3);
	alb = mix(alb, vec3(0.03, 0.026, 0.02), clamp(pud + grease * 0.7, 0.0, 1.0) * 0.9);
	alb = mix(alb, vec3(0.33, 0.32, 0.29), dust * 0.4);

	// worn painted markings (hazard / stencil): paint flakes off with traffic
	float mark = 0.0;
	vec3 markcol = u_stencil;
	if (u_hazard > 0.01) {
		float hz = step(0.5, fract((uv.x + uv.y) * 0.65));
		markcol = mix(u_hazard_b, u_hazard_a, hz);
		mark = u_hazard;
	} else {
		vec2 cid = floor(uv / 8.0);
		float ch = hash21(cid + 41.0);
		if (ch > 0.86) {
			vec2 cf = fract(uv / 8.0);
			float band = step(0.42, cf.x) * step(cf.x, 0.58) * step(0.3, cf.y) * step(cf.y, 0.7);
			mark = step(0.5, fract((cf.y - cf.x) * 6.0)) * band;
		}
	}
	float mark_wear = smoothstep(0.35, 0.75, wfbm(uv * 1.1 + 15.0)) * 0.7 + scuff * 0.5;
	mark *= clamp(1.0 - mark_wear, 0.15, 1.0);
	alb = mix(alb, markcol * 0.55, mark * 0.8);

	float rough = 0.62 + grain * 0.12 + scuff * 0.1 + dust * 0.25 - bevel * 0.08;
	rough = mix(rough, 0.09, pud);                       // puddle mirror
	rough = mix(rough, 0.3, oilfilm * (1.0 - pud));      // thin sheen
	rough = mix(rough, 0.5, grease * 0.6);
	rough = mix(rough, 0.14, u_gloss);
	rough = clamp(rough, 0.05, 0.95);
	float metal = mix(0.3, 0.85, bevel * 0.6 + weld * 0.4);
	metal *= (1.0 - dust * 0.6) * (1.0 - clamp(pud + grease, 0.0, 1.0) * 0.5);
	metal = mix(metal, 0.4, u_gloss * 0.5);
	metal = clamp(metal, 0.0, 1.0);

	// normal from height field
	float e = 0.04;
	float h0 = height_field(uv, seedv);
	float hx = height_field(uv + vec2(e, 0.0), seedv);
	float hz = height_field(uv + vec2(0.0, e), seedv);
	vec3 G = vec3((hx - h0) / e, 0.0, (hz - h0) / e);
	G *= 1.0 - pud;   // puddles flatten the bump
	vec3 npert = normalize(n - 0.5 * (G - n * dot(n, G)));

	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(0.5, 0.95, max(u_gloss, pud));
	NORMAL = normalize((VIEW_MATRIX * vec4(npert, 0.0)).xyz);
}

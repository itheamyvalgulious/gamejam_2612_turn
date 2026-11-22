shader_type spatial;
render_mode specular_schlick_ggx;

// Structural steel v2 — painted frame with peel-to-bare metal, rust drips
// under bolt lines, weld beads at flange edges, grime in crevices.

uniform vec3 u_base = vec3(0.125, 0.13, 0.145);
uniform vec3 u_paint = vec3(0.0, 0.0, 0.0);   // if nonzero: painted frame color
uniform float u_rust = 0.25;
uniform vec3 u_rust_col = vec3(0.32, 0.19, 0.1);
uniform float u_wear : hint_range(0.0, 2.0) = 1.0;

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
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
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

float height_field(vec2 uv) {
	// flange bolt line + weld bead along section edges + micro
	float boltline = (1.0 - smoothstep(0.02, 0.05, abs(fract(uv.x * 0.8) - 0.5) - 0.42));
	float bead = 0.0;
	vec2 f = fract(uv / 1.25);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	bead = (1.0 - smoothstep(0.015, 0.04, d)) * smoothstep(0.004, 0.015, d);
	bead *= 0.55 + 0.45 * sin((uv.x + uv.y) * 150.0);
	float micro = (vnoise(uv * 180.0) - 0.5) * 0.015;
	return boltline * 0.05 + bead * 0.08 + micro;
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec3 bn = abs(n);
	vec3 w = pow(bn, vec3(5.0));
	w /= (w.x + w.y + w.z);
	vec2 uvd = (w.x > w.y && w.x > w.z) ? wpos.zy : ((w.y > w.z) ? wpos.xz : wpos.xy);

	// bolt rows along flanges
	float boltrow = 1.0 - smoothstep(0.03, 0.06, abs(fract(uvd.x * 0.8 + 0.25) - 0.5) - 0.4);
	float bolt = boltrow * (1.0 - smoothstep(0.05, 0.09, abs(fract(uvd.y * 0.8) - 0.5)));
	// rust drips below bolts / crevices
	float drip = smoothstep(0.55, 0.85, fbm(vec2(uvd.x * 6.0, uvd.y * 0.8) + 19.0));
	float rust = clamp(smoothstep(0.5, 0.8, wfbm(uvd * 1.1 + 33.0)) * (0.3 + 0.7 * bolt) + drip * 0.35 * boltrow, 0.0, 1.0) * u_rust;
	// paint peel (only when painted)
	float painted = step(0.001, dot(u_paint, u_paint));
	float peel = smoothstep(0.58, 0.75, wfbm(uvd * 1.6 + 7.7)) * u_wear * painted;
	peel = clamp(peel * (0.4 + 0.8 * bolt + 0.5 * rust), 0.0, 1.0);
	// edge wear from triplanar blend (corners)
	float edgemix = 1.0 - max(max(w.x, w.y), w.z);
	float wear = smoothstep(0.12, 0.4, edgemix) * 0.5 + vnoise(vec2(uvd.x * 5.0, uvd.y * 320.0)) * 0.12;
	float grime = fbm(uvd * 0.7 + 3.0) * 0.4;

	vec3 paintc = mix(u_base, u_paint, painted);
	vec3 bare = vec3(0.38, 0.39, 0.41) * (0.85 + 0.3 * vnoise(uvd * 30.0));
	vec3 alb = mix(paintc, bare, max(peel, wear * 0.55));
	alb = mix(alb, u_rust_col, rust * 0.65);
	alb = mix(alb, alb * 0.6, grime * 0.5);
	alb *= 1.0 - bolt * 0.15;

	float rough = 0.5 + rust * 0.3 + grime * 0.2 - wear * 0.12 + vnoise(vec2(uvd.x * 4.0, uvd.y * 300.0)) * 0.08;
	rough = mix(rough, 0.28, peel * 0.7);
	float metal = mix(0.45, 0.9, max(peel, wear * 0.5));
	metal *= (1.0 - rust * 0.6);

	// normal
	float e = 0.04;
	float h0 = height_field(uvd);
	float hu = height_field(uvd + vec2(e, 0.0));
	float hv = height_field(uvd + vec2(0.0, e));
	vec3 G = vec3(0.0);
	if (w.x > w.y && w.x > w.z) {
		G = vec3(0.0, (hv - h0) / e, (hu - h0) / e);
	} else if (w.y > w.z) {
		G = vec3((hu - h0) / e, 0.0, (hv - h0) / e);
	} else {
		G = vec3((hu - h0) / e, (hv - h0) / e, 0.0);
	}
	vec3 npert = normalize(n - 0.4 * (G - n * dot(n, G)));

	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.08, 0.95);
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(npert, 0.0)).xyz);
}

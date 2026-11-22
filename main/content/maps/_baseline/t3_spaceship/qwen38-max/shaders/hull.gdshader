shader_type spatial;
render_mode specular_schlick_ggx;

// Exterior hull plating: large plates, deep seams, space grime, heat
// staining near stern, lit windows, nav lights, hangar door decal.

uniform vec3 u_base = vec3(0.33, 0.345, 0.39);
uniform float u_plate = 9.0;
uniform float u_grime = 0.4;
uniform vec3 u_warm = vec3(0.42, 0.3, 0.22);

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

vec4 plate_info(vec2 uv) {
	vec2 g = uv / u_plate;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float hs = hash21(id);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float seam = 1.0 - smoothstep(0.0, 0.012, d);
	float bevel = (1.0 - smoothstep(0.012, 0.03, d)) * smoothstep(0.004, 0.012, d);
	// sub-plates
	vec2 f2 = fract(uv / (u_plate * 0.25));
	float d2 = min(min(f2.x, 1.0 - f2.x), min(min(f2.y, 1.0 - f2.y), 1.0 - f2.y));
	float sub = (1.0 - smoothstep(0.0, 0.008, d2)) * 0.4;
	// lit window in some sub-cells
	float win = 0.0;
	vec2 wg = uv / 2.2;
	vec2 wid = floor(wg);
	vec2 wf = fract(wg);
	float wh = hash21(wid + 7.7);
	if (wh > 0.955) {
		win = step(0.3, wf.x) * step(wf.x, 0.7) * step(0.38, wf.y) * step(wf.y, 0.62);
	}
	return vec4(-(seam * 0.6 + sub * 0.15) + bevel * 0.25, hs, bevel + seam * 0.2, win);
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec3 bn = abs(n);
	vec3 w = pow(bn, vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec2 uvX = wpos.zy * 0.5;
	vec2 uvY = wpos.xz * 0.5;
	vec2 uvZ = wpos.xy * 0.5;
	vec4 ix = plate_info(uvX);
	vec4 iy = plate_info(uvY);
	vec4 iz = plate_info(uvZ);
	float h = ix.x * w.x + iy.x * w.y + iz.x * w.z;
	float hs = ix.y * w.x + iy.y * w.y + iz.y * w.z;
	float wear = ix.z * w.x + iy.z * w.y + iz.z * w.z;
	float win = ix.w * w.x + iy.w * w.y + iz.w * w.z;
	vec2 uvd = (w.x > w.y && w.x > w.z) ? uvX : ((w.y > w.z) ? uvY : uvZ);

	float grime = fbm(uvd * 0.28) * u_grime;
	float pitting = smoothstep(0.9955, 0.9995, vnoise(uvd * 90.0));
	float heat = smoothstep(64.0, 4.0, wpos.x);

	vec3 alb = u_base * (0.9 + 0.2 * fract(hs * 5.13)) * COLOR.rgb;
	alb *= (1.0 + h * 0.85);
	alb = mix(alb, vec3(0.5, 0.51, 0.53), wear * 0.3);
	alb = mix(alb, alb * 0.55, grime * 0.5);
	alb = mix(alb, u_warm, heat * 0.4);
	alb = mix(alb, vec3(0.22), pitting * 0.6);

	// hangar door decal (world-space rect on port flank)
	float in_door = step(138.0, wpos.x) * step(wpos.x, 186.0) * step(8.6, wpos.y) * step(wpos.y, 13.6) * step(43.5, -wpos.z);
	if (in_door > 0.5) {
		float dx = min(min(wpos.x - 138.0, 186.0 - wpos.x), min(wpos.y - 8.6, 13.6 - wpos.y));
		float dborder = 1.0 - smoothstep(0.3, 0.9, dx);
		float hz = step(0.5, fract((wpos.x + wpos.y) * 0.7)) * step(dx, 2.2) * step(0.6, dx);
		float cseam = (1.0 - smoothstep(0.0, 0.14, abs(wpos.x - 162.0))) * 0.8;
		alb = mix(alb, vec3(0.16, 0.17, 0.19), dborder * 0.6);
		alb = mix(alb, mix(vec3(0.75, 0.55, 0.05), vec3(0.09), hz), step(0.5, hz) * 0.75);
		alb *= (1.0 - cseam * 0.5);
	}

	// nav lights (red port / green starboard), blinking
	float navmask = step(34.0, abs(wpos.z));
	float side = step(0.0, wpos.z);
	float blink = step(0.55, fract(TIME * 0.55));
	vec3 navcol = mix(vec3(1.0, 0.12, 0.1), vec3(0.15, 1.0, 0.3), side);
	float navdot = step(0.985, fract(uvd.y * 0.35)) * navmask * blink;

	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(0.55 + h * 0.15 + grime * 0.25 - wear * 0.1 + pitting * 0.2, 0.08, 0.95);
	METALLIC = 0.42 * (1.0 - grime * 0.35);
	SPECULAR = 0.5;
	EMISSION = win * vec3(1.0, 0.85, 0.6) * 1.6 + navcol * navdot * 3.0;
	NORMAL = normalize(n);
}

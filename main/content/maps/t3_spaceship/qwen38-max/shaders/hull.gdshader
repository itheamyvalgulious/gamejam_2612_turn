shader_type spatial;
render_mode specular_schlick_ggx;

// Exterior hull v2 — big welded plates with bead seams, sun-faded paint peel,
// micrometeoroid pits with raised rims, soft panel dents, grime in grooves,
// lit windows, nav lights, world-space decals (hangar door / EVA hatch).

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

// plate seams + weld bead + dents + micro
float height_field(vec2 uv) {
	vec2 g = uv / u_plate;
	vec2 f = fract(g);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float groove = 1.0 - smoothstep(0.0, 0.012, d);
	float bead = (1.0 - smoothstep(0.012, 0.032, d)) * smoothstep(0.004, 0.012, d);
	bead *= 0.55 + 0.45 * sin((uv.x + uv.y) * 60.0);
	float dent = (fbm(uv * 0.13 + 3.3) - 0.5) * 0.25;      // soft panel waviness
	float micro = (vnoise(uv * 90.0) - 0.5) * 0.01;
	return -groove * 0.6 + bead * 0.12 + dent + micro;
}

vec4 plate_info(vec2 uv) {
	vec2 g = uv / u_plate;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float hs = hash21(id);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float seam = 1.0 - smoothstep(0.0, 0.012, d);
	float bevel = (1.0 - smoothstep(0.012, 0.03, d)) * smoothstep(0.004, 0.012, d);
	vec2 f2 = fract(uv / (u_plate * 0.25));
	float d2 = min(min(f2.x, 1.0 - f2.x), min(f2.y, 1.0 - f2.y));
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

	// space weathering: sun-faded paint peel patches, grime in grooves
	float fade = smoothstep(0.45, 0.8, wfbm(uvd * 0.22 + 12.0));
	float peel = smoothstep(0.62, 0.78, wfbm(uvd * 0.5 + 44.0)) * 0.6 + wear * 0.25;
	float grime = fbm(uvd * 0.28) * u_grime * (0.4 + 0.6 * smoothstep(0.02, 0.001, min(min(fract(uvd.x / u_plate), 1.0 - fract(uvd.x / u_plate)), min(fract(uvd.y / u_plate), 1.0 - fract(uvd.y / u_plate)))));
	// micrometeoroid pits with raised rims
	vec2 pg = uvd * 6.0;
	vec2 pid = floor(pg);
	vec2 pf = fract(pg) - 0.5;
	vec2 pj = vec2(hash21(pid), hash21(pid + 8.8)) - 0.5;
	float pdist = length(pf - pj * 0.6);
	float ph = hash21(pid + 3.3);
	float pit = (1.0 - smoothstep(0.05, 0.11, pdist)) * step(0.93, ph);
	float rim = (1.0 - smoothstep(0.11, 0.17, pdist)) * step(0.93, ph) - pit;
	float heat = smoothstep(64.0, 4.0, wpos.x);

	vec3 paintc = u_base * (0.9 + 0.2 * fract(hs * 5.13)) * COLOR.rgb;
	paintc = mix(paintc, paintc * 1.25 + vec3(0.02, 0.02, 0.015), fade * 0.5);   // sun bleach
	vec3 bare = vec3(0.46, 0.47, 0.5);
	vec3 alb = mix(paintc, bare, clamp(peel, 0.0, 1.0) * 0.7);
	alb *= (1.0 + h * 0.85);
	alb = mix(alb, vec3(0.52, 0.53, 0.55), wear * 0.3);
	alb = mix(alb, alb * 0.5, grime * 0.55);
	alb = mix(alb, u_warm, heat * 0.4);
	alb = mix(alb, vec3(0.18), pit * 0.8);
	alb = mix(alb, vec3(0.5), rim * 0.5);

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
	// EVA hatch decal
	float hatchd = length(vec2(wpos.x - 64.0, wpos.y - 9.0));
	float hatch = step(-wpos.z, -43.0) * step(61.0, wpos.x) * step(wpos.x, 67.0);
	if (hatch > 0.5) {
		float ring = (1.0 - smoothstep(0.02, 0.06, abs(hatchd - 1.25))) + (1.0 - smoothstep(0.02, 0.05, abs(hatchd - 1.05)));
		alb = mix(alb, vec3(0.42, 0.4, 0.36), clamp(ring, 0.0, 1.0) * 0.8);
		alb = mix(alb, vec3(0.3, 0.3, 0.32), (1.0 - smoothstep(0.9, 1.05, hatchd)) * 0.5);
	}

	// nav lights
	float navmask = step(34.0, abs(wpos.z));
	float side = step(0.0, wpos.z);
	float blink = step(0.55, fract(TIME * 0.55));
	vec3 navcol = mix(vec3(1.0, 0.12, 0.1), vec3(0.15, 1.0, 0.3), side);
	float navdot = step(0.985, fract(uvd.y * 0.35)) * navmask * blink;

	// normal
	float e = 0.06;
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
	vec3 npert = normalize(n - 0.5 * (G - n * dot(n, G)));

	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(0.55 + h * 0.15 + grime * 0.25 - wear * 0.12 + pit * 0.25 + fade * 0.08, 0.08, 0.95);
	METALLIC = clamp(mix(0.42, 0.85, clamp(peel, 0.0, 1.0)) * (1.0 - grime * 0.35), 0.0, 1.0);
	SPECULAR = 0.5;
	EMISSION = win * vec3(1.0, 0.85, 0.6) * 1.6 + navcol * navdot * 3.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(npert, 0.0)).xyz);
}

shader_type spatial;
render_mode specular_schlick_ggx;

// Interior plating v2 — two-layer paint/bare-metal with weld beads, peel,
// oil drips, dust, scratches, micro-orange-peel bump. Triplanar, world space.
// Reads well at 1-2 m: all features are metric-scaled.

uniform float u_grime : hint_range(0.0, 1.6) = 0.45;
uniform vec3 u_base_a = vec3(0.275, 0.295, 0.335);   // paint tone A
uniform vec3 u_base_b = vec3(0.195, 0.21, 0.24);     // paint tone B
uniform float u_panel = 2.0;        // main panel size (m)
uniform float u_sub = 0.5;          // sub-panel size (m)
uniform float u_bolts = 1.0;
uniform vec3 u_accent = vec3(0.4, 0.78, 1.0);
uniform float u_accent_amt : hint_range(0.0, 1.0) = 0.3;
uniform float u_deck_pitch = 7.5;
uniform float u_wear : hint_range(0.0, 2.0) = 1.0;   // peel/scratch multiplier
uniform float u_dust : hint_range(0.0, 1.5) = 0.6;

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

// warped fbm for organic peel edges
float wfbm(vec2 p) {
	vec2 q = vec2(fbm(p + vec2(0.0, 0.0)), fbm(p + vec2(5.2, 1.3)));
	return fbm(p + 1.6 * q);
}

// geometry-only height field (cheap, used for normals): grid + weld bead + micro
float height_field(vec2 uv, float seed_off) {
	vec2 g = uv / u_panel + seed_off;
	vec2 f = fract(g);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float groove = 1.0 - smoothstep(0.0, 0.02, d);
	float bevel = (1.0 - smoothstep(0.02, 0.05, d)) * smoothstep(0.006, 0.02, d);
	// weld bead: raised rippled ridge just inside the groove
	float weld = (1.0 - smoothstep(0.02, 0.045, d)) * smoothstep(0.008, 0.02, d);
	weld *= 0.55 + 0.45 * sin((uv.x + uv.y) * 140.0);
	float bolt = 0.0;
	if (u_bolts > 0.5) {
		vec2 bp = min(f, 1.0 - f);
		bolt = 1.0 - smoothstep(0.016, 0.026, length(bp - vec2(0.06, 0.06)));
	}
	vec2 f2 = fract(uv / u_sub);
	float d2 = min(min(f2.x, 1.0 - f2.x), min(f2.y, 1.0 - f2.y));
	float subline = (1.0 - smoothstep(0.0, 0.011, d2)) * 0.3;
	// micro orange-peel + brushed ripple
	float micro = (vnoise(uv * 210.0) - 0.5) * 0.012 + (vnoise(vec2(uv.x * 4.0, uv.y * 300.0)) - 0.5) * 0.008;
	return -groove * 0.5 + bevel * 0.18 + weld * 0.09 + bolt * 0.26 - subline * 0.1 + micro;
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec3 bn = abs(n);
	vec3 w = pow(bn, vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec2 uvX = wpos.zy;
	vec2 uvY = wpos.xz;
	vec2 uvZ = wpos.xy;
	float seed_off = COLOR.a * 13.0;

	// dominant projection for noise-driven masks (coherent, cheap)
	vec2 uvd = (w.x > w.y && w.x > w.z) ? uvX : ((w.y > w.z) ? uvY : uvZ);

	// ---- panel grid masks (blended triplanar for color stability)
	vec2 gX = uvX / u_panel + seed_off;
	vec2 gY = uvY / u_panel + seed_off * 1.7;
	vec2 gZ = uvZ / u_panel + seed_off * 2.3;
	vec2 idX = floor(gX); vec2 idY = floor(gY); vec2 idZ = floor(gZ);
	vec2 fX = fract(gX); vec2 fY = fract(gY); vec2 fZ = fract(gZ);
	vec2 dX = min(min(fX.x, 1.0 - fX.x), min(fX.y, 1.0 - fX.y)) * vec2(1.0);
	float d2X = min(min(fX.x, 1.0 - fX.x), min(fX.y, 1.0 - fX.y));
	float d2Y = min(min(fY.x, 1.0 - fY.x), min(fY.y, 1.0 - fY.y));
	float d2Z = min(min(fZ.x, 1.0 - fZ.x), min(fZ.y, 1.0 - fZ.y));
	float dd = d2X * w.x + d2Y * w.y + d2Z * w.z;
	float groove = 1.0 - smoothstep(0.0, 0.02, dd);
	float bevel = (1.0 - smoothstep(0.02, 0.05, dd)) * smoothstep(0.006, 0.02, dd);
	float weld = (1.0 - smoothstep(0.02, 0.045, dd)) * smoothstep(0.008, 0.02, dd);
	weld *= 0.55 + 0.45 * sin((uvd.x + uvd.y) * 140.0);
	vec2 hsX = vec2(hash21(idX), hash21(idX + 3.1));
	vec2 hsY = vec2(hash21(idY + 7.7), hash21(idY + 11.3));
	vec2 hsZ = vec2(hash21(idZ + 5.1), hash21(idZ + 9.9));
	float phash = hsX.x * w.x + hsY.x * w.y + hsZ.x * w.z;
	float phash2 = hsX.y * w.x + hsY.y * w.y + hsZ.y * w.z;

	// ---- wear / peel / dirt masks
	float relh = mod(wpos.y, u_deck_pitch);
	float low = smoothstep(2.6, 0.0, relh);                 // splash zone near deck
	float upf = smoothstep(0.45, 0.85, n.y);                // upward faces collect dust
	float edge = clamp(bevel * 0.9 + groove * 0.35 + weld * 0.5, 0.0, 1.0);
	float peel_m = smoothstep(0.55, 0.72, wfbm(uvd * 0.9 + 4.2));
	peel_m = peel_m * (0.25 + 0.9 * edge) + smoothstep(0.78, 0.9, wfbm(uvd * 2.3 + 9.1)) * 0.35;
	peel_m = clamp(peel_m * u_wear, 0.0, 1.0);
	float dirt = smoothstep(0.42, 0.82, fbm(uvd * 0.55 + 3.7)) * u_grime * (0.25 + 0.75 * low) * 0.5;
	// oil drips: vertical streaks seeded at seams/bolts, running down
	float drip_src = smoothstep(0.05, 0.015, dd) + step(0.985, hash21(floor(vec2(uvd.x * 3.0, 0.0)) + floor(wpos.y / u_deck_pitch)));
	float drip = smoothstep(0.62, 0.9, fbm(vec2(uvd.x * 5.0, uvd.y * 0.7) + 11.0));
	float oil = clamp(drip * (0.25 + 0.75 * low) * (0.3 + 0.9 * min(drip_src, 1.0)) * u_grime, 0.0, 1.0);
	float oil_gloss = step(0.5, hash21(floor(uvd * 0.35) + 2.2));   // wet vs dry patches
	// scratches: sparse bright hairlines, two directions
	float sc1 = smoothstep(0.988, 0.997, vnoise(vec2(uvd.x * 43.0, uvd.y * 2.3 + 31.0)));
	float sc2 = smoothstep(0.99, 0.998, vnoise(vec2(uvd.x * 2.1 + 7.0, uvd.y * 51.0)));
	float scratch = clamp(sc1 + sc2 * 0.7, 0.0, 1.0) * (0.4 + 0.6 * u_wear);
	// dust settle
	float dust = upf * (0.35 + 0.65 * fbm(uvd * 1.7 + 21.0)) * u_dust;
	// brushed metal streaks (roughness anisotropy fake)
	float brush = vnoise(vec2(uvd.x * 3.0, uvd.y * 240.0)) * 0.5 + vnoise(vec2(uvd.x * 9.0, uvd.y * 520.0)) * 0.25;

	// ---- albedo: paint layer vs bare metal vs contaminants
	vec3 paint = mix(u_base_a, u_base_b, step(0.45, fract(phash * 7.31))) * COLOR.rgb;
	paint *= 0.94 + 0.12 * fract(phash2 * 3.7);
	vec3 bare = vec3(0.40, 0.41, 0.435) * (0.82 + 0.36 * vnoise(uvd * 26.0));
	bare = mix(bare, vec3(0.55, 0.56, 0.58), scratch * 0.6);
	vec3 alb = mix(paint, bare, peel_m);
	alb *= 1.0 - groove * 0.42;                       // seam occlusion
	alb = mix(alb, alb * 1.25 + vec3(0.03), weld * 0.35);  // weld discoloration
	alb = mix(alb, vec3(0.045, 0.036, 0.028), oil * 0.85);
	alb = mix(alb, vec3(0.34, 0.33, 0.30), dust * 0.55);
	alb *= 1.0 - dirt * 0.45;
	alb = mix(alb, bare * 1.15, scratch * 0.5 * peel_m);

	// ---- roughness / metal: layer separation
	float rough_paint = 0.44 + brush * 0.1 + dirt * 0.3 + dust * 0.35 - weld * 0.05;
	float rough_bare = 0.24 + brush * 0.16 + scratch * -0.06 + dirt * 0.2;
	float rough = mix(rough_paint, rough_bare, peel_m);
	rough = mix(rough, mix(0.55, 0.13, oil_gloss), oil * 0.8);   // wet oil = glossy
	rough = mix(rough, 0.85, dust * 0.5);
	rough += groove * 0.12;
	float metal = mix(0.12, 0.92, peel_m);
	metal *= (1.0 - oil * 0.55) * (1.0 - dust * 0.75) * (1.0 - dirt * 0.35);

	// ---- normal: triplanar height gradient (dominant axis, one-sided diffs)
	float e = 0.035;
	vec2 axu = (w.x > w.y && w.x > w.z) ? vec2(0.0, 1.0) : ((w.y > w.z) ? vec2(1.0, 0.0) : vec2(1.0, 0.0));
	vec2 axv = (w.x > w.y && w.x > w.z) ? vec2(1.0, 0.0) : ((w.y > w.z) ? vec2(0.0, 1.0) : vec2(0.0, 1.0));
	float h0 = height_field(uvd, seed_off);
	float hu = height_field(uvd + axu * e, seed_off);
	float hv = height_field(uvd + axv * e, seed_off);
	vec3 G = vec3(0.0);
	if (w.x > w.y && w.x > w.z) {
		G = vec3(0.0, (hv - h0) / e, (hu - h0) / e);
	} else if (w.y > w.z) {
		G = vec3((hu - h0) / e, 0.0, (hv - h0) / e);
	} else {
		G = vec3((hu - h0) / e, (hv - h0) / e, 0.0);
	}
	vec3 npert = normalize(n - 0.42 * (G - n * dot(n, G)));

	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.05, 0.95);
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = 0.55;
	float emis = step(0.94, phash) * (1.0 - smoothstep(0.012, 0.03, length((fract(gZ) - vec2(0.5, 0.86)) * vec2(1.0, 3.5))));
	EMISSION = u_accent * emis * u_accent_amt * (0.75 + 0.25 * sin(TIME * 2.3 + phash * 40.0)) * 2.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(npert, 0.0)).xyz);
}

shader_type spatial;
render_mode specular_schlick_ggx;

// Interior wall / ceiling / structure plating. Fully mathematical:
// panel grid + corner bolts + sub-panel lines + vent slits + brushed metal
// + wear at seams + oil streaks + dirt + scratches. Triplanar in world space.

uniform float u_grime : hint_range(0.0, 1.6) = 0.45;
uniform vec3 u_base_a = vec3(0.275, 0.295, 0.335);
uniform vec3 u_base_b = vec3(0.195, 0.21, 0.24);
uniform float u_panel = 2.0;      // main panel size (m)
uniform float u_sub = 0.5;        // sub-panel size (m)
uniform float u_bolts = 1.0;      // corner bolts on/off
uniform vec3 u_accent = vec3(0.4, 0.78, 1.0);
uniform float u_accent_amt : hint_range(0.0, 1.0) = 0.3;
uniform float u_deck_pitch = 7.5;

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

// x = height, y = per-panel variation, z = wear, w = emissive marker
vec4 panel_info(vec2 uv, float seed_off) {
	vec2 g = uv / u_panel;
	vec2 id = floor(g + seed_off);
	vec2 f = fract(g + seed_off);
	float hs = hash21(id + seed_off * 3.7);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float groove = 1.0 - smoothstep(0.0, 0.02, d);
	float bevel = (1.0 - smoothstep(0.02, 0.05, d)) * smoothstep(0.006, 0.02, d);
	float bolt = 0.0;
	if (u_bolts > 0.5) {
		vec2 bp = min(f, 1.0 - f);
		float bd = length(bp - vec2(0.06, 0.06));
		bolt = 1.0 - smoothstep(0.016, 0.024, bd);
	}
	vec2 f2 = fract(uv / u_sub);
	float d2 = min(min(f2.x, 1.0 - f2.x), min(f2.y, 1.0 - f2.y));
	float subline = (1.0 - smoothstep(0.0, 0.011, d2)) * 0.3;
	float h = -groove * 0.5 + bevel * 0.2 + bolt * 0.28 - subline * 0.1;
	float variation = hs;
	float wear = bevel * 0.75 + groove * 0.15 + bolt * 0.3;
	float emis = 0.0;
	if (hs > 0.94) {
		vec2 mp = vec2(f.x - 0.5, f.y - 0.86);
		emis = (1.0 - smoothstep(0.012, 0.03, length(mp * vec2(1.0, 3.5)))) * 0.9;
	}
	if (hs > 0.85 && hs < 0.9) {
		float sl = step(0.28, f.y) * step(f.y, 0.72) * step(0.55, fract(f.x * 11.0));
		h -= sl * 0.35;
		variation = mix(variation, 0.08, sl);
		wear = mix(wear, 0.5, sl);
	}
	return vec4(h, variation, wear, emis);
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
	vec4 ix = panel_info(uvX, seed_off);
	vec4 iy = panel_info(uvY, seed_off + 5.0);
	vec4 iz = panel_info(uvZ, seed_off + 9.0);
	float h = ix.x * w.x + iy.x * w.y + iz.x * w.z;
	float variation = ix.y * w.x + iy.y * w.y + iz.y * w.z;
	float wear = ix.z * w.x + iy.z * w.y + iz.z * w.z;
	float emis = ix.w * w.x + iy.w * w.y + iz.w * w.z;

	vec2 uvd = (w.x > w.y && w.x > w.z) ? uvX : ((w.y > w.z) ? uvY : uvZ);
	float relh = mod(wpos.y, u_deck_pitch);
	float low = smoothstep(2.8, 0.0, relh);
	float ceilg = smoothstep(5.4, 7.0, relh);

	// brushed metal (fine horizontal streaks)
	float brush = vnoise(vec2(uvd.x * 3.0, uvd.y * 210.0)) * 0.5 + vnoise(vec2(uvd.x * 9.0, uvd.y * 480.0)) * 0.2;
	// grime / oil / scratches
	float dirt = fbm(uvd * 0.55 + 3.7) * u_grime * (0.25 + 0.75 * low) * 0.55;
	float oil = smoothstep(0.52, 0.88, fbm(vec2(uvd.x * 2.6, uvd.y * 0.65) + 11.0)) * low * u_grime;
	float sc = vnoise(vec2(uvd.x * 47.0, uvd.y * 2.1 + 31.0));
	float scratch = smoothstep(0.987, 0.996, sc) * 0.55;

	vec3 base = mix(u_base_a, u_base_b, fract(variation * 7.31));
	vec3 alb = base * COLOR.rgb;
	alb *= (1.0 + h * 0.85);
	alb = mix(alb, vec3(0.46, 0.47, 0.49), wear * 0.4);
	alb = mix(alb, vec3(0.045, 0.036, 0.028), oil * 0.85);
	alb *= (1.0 - dirt * 0.55);
	alb *= (1.0 + scratch * 0.5);

	float rough = 0.45 + h * 0.16 + dirt * 0.4 + brush * 0.1 - wear * 0.14 - scratch * 0.1 - oil * 0.06;
	float metal = 0.3 * (1.0 - oil * 0.5) * (1.0 - dirt * 0.4);

	// world-space normal perturbation from panel height (dominant axis)
	float e = 0.04;
	float hx = panel_info(uvd + vec2(e, 0.0), seed_off).x - h;
	float hy = panel_info(uvd + vec2(0.0, e), seed_off).x - h;
	vec3 G = vec3(0.0);
	if (w.x > w.y && w.x > w.z) {
		G = vec3(0.0, hy / e, hx / e);
	} else if (w.y > w.z) {
		G = vec3(hx / e, 0.0, hy / e);
	} else {
		G = vec3(hx / e, hy / e, 0.0);
	}
	vec3 npert = n;

	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.06, 0.95);
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = 0.55;
	EMISSION = u_accent * emis * u_accent_amt * (0.75 + 0.25 * sin(TIME * 2.3 + variation * 40.0)) * 2.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(npert, 0.0)).xyz);
}

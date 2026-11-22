shader_type sky;

uniform vec3 zenith_col : source_color = vec3(0.055, 0.125, 0.285);
uniform vec3 horizon_col : source_color = vec3(0.60, 0.60, 0.66);
uniform vec3 ground_col : source_color = vec3(0.52, 0.57, 0.65);
uniform vec3 sun_col : source_color = vec3(1.0, 0.66, 0.38);
uniform vec3 moon_dir = vec3(0.45, 0.30, -0.84);
uniform float cloud_cover = 0.52;
uniform float time_scale = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= oct) { break; }
		v += a * vnoise(p);
		p = p * 2.03 + vec2(11.3, 5.7);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);
	float sd = dot(dir, sun_dir);
	float up = clamp(dir.y, 0.0, 1.0);

	// base atmosphere: cool zenith, warm haze at the sun side
	vec3 col = mix(horizon_col, zenith_col, pow(up, 0.55));
	float sun_side = pow(max(sd, 0.0), 3.0);
	col = mix(col, vec3(0.95, 0.58, 0.34), sun_side * 0.55 * (1.0 - up * 0.45));
	col = mix(col, vec3(1.0, 0.76, 0.48), pow(max(sd, 0.0), 9.0) * 0.55);
	if (dir.y < 0.0) {
		col = mix(col, ground_col, smoothstep(0.0, -0.06, dir.y));
	}

	// sun disc + halo
	float disc = smoothstep(0.9996, 0.99985, sd);
	col += sun_col * disc * 12.0;
	col += sun_col * pow(max(sd, 0.0), 220.0) * 3.0;
	col += sun_col * pow(max(sd, 0.0), 18.0) * 0.28;

	// ---------------------------------------------------------- clouds
	if (dir.y > 0.005) {
		float t = 1.0 / (dir.y + 0.16);
		vec2 wind = vec2(TIME * 0.0018 * time_scale, TIME * 0.0008 * time_scale);
		vec2 uv = dir.xz * t * 0.95 + wind;
		vec2 warp = vec2(fbm(uv * 0.7 + 1.3, 3), fbm(uv * 0.7 + 6.7, 3)) - 0.5;
		vec2 quv = uv + warp * 0.55;
		float base = fbm(quv * 1.55, 5);
		float detail = fbm(quv * 5.2 + vec2(3.1, 8.4), 4);
		float dens = base * 0.70 + detail * 0.30;
		dens += 0.08 * fbm(uv * 0.45 + 1.7, 3);
		float mask = smoothstep(cloud_cover, cloud_cover + 0.075, dens);
		mask *= smoothstep(0.0, 0.09, dir.y);
		// second thin high layer
		vec2 uv2 = dir.xz * t * 0.30 + wind * 2.0;
		float hi = smoothstep(0.66, 0.84, fbm(uv2 * 1.4 + 9.0, 4));
		hi *= 0.42 * smoothstep(0.05, 0.25, dir.y);

		// sun-side silver lining and shadowed base
		float lit = pow(clamp(sd, 0.0, 1.0), 2.2);
		float dens_light = fbm((uv - sun_dir.xz * 0.10) * 1.5, 5);
		float shadow = smoothstep(0.46, 0.62, base * 0.7 + dens_light * 0.3);
		vec3 cbase = mix(vec3(0.15, 0.16, 0.21), vec3(0.95, 0.66, 0.44), 0.18 + 0.82 * lit);
		cbase = mix(cbase, vec3(1.0, 0.78, 0.52), pow(clamp(sd, 0.0, 1.0), 8.0) * 0.7);
		cbase *= 0.72 + 0.38 * shadow;
		col = mix(col, cbase, mask * 0.92);
		col = mix(col, vec3(0.92, 0.72, 0.60) * (0.7 + 0.5 * lit), hi * 0.35);
	}

	// ---------------------------------------------------------- moon
	vec3 md = normalize(moon_dir);
	float mdot = dot(dir, md);
	float mdisc = smoothstep(0.99935, 0.99965, mdot);
	if (mdisc > 0.0) {
		vec2 muv = (dir.xz - md.xz) * 220.0;
		float cr = fbm(muv * 6.0, 4);
		float cr2 = fbm(muv * 20.0 + 3.0, 3);
		vec3 mcol = mix(vec3(0.62, 0.66, 0.72), vec3(0.92, 0.94, 0.97), smoothstep(0.35, 0.7, cr));
		mcol *= 0.86 + 0.14 * cr2;
		col = mix(col, mcol * 1.15, mdisc * 0.75);
	}
	col += vec3(0.55, 0.62, 0.72) * pow(max(mdot, 0.0), 400.0) * 0.35;

	COLOR = col;
}
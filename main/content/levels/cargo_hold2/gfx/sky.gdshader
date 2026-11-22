// Procedural dusk/night sky: smog gradient, low sun, drifting cloud deck,
// stars and city glow — pure maths, no panorama texture.
shader_type sky;

uniform vec3 zenith_col : source_color = vec3(0.045, 0.055, 0.14);
uniform vec3 mid_col : source_color = vec3(0.20, 0.11, 0.32);
uniform vec3 horizon_col : source_color = vec3(0.85, 0.34, 0.30);
uniform vec3 city_glow : source_color = vec3(0.55, 0.18, 0.42);
uniform float smog : hint_range(0.0, 1.0) = 0.65;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.62;
uniform float stars : hint_range(0.0, 1.0) = 0.4;
uniform float sun_size = 0.0016;
uniform float night : hint_range(0.0, 1.0) = 0.7;
uniform float sky_gain = 1.0;
uniform vec3 moon_dir = vec3(0.35, 0.42, -0.84);

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), u.x),
		mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 dv = EYEDIR;
	float dl = length(dv);
	vec3 d = dl > 0.0001 ? dv / dl : vec3(0.0, 1.0, 0.0);
	float y = clamp(d.y, -1.0, 1.0);
	float up = pow(clamp(y, 0.0, 1.0), 0.55);
	vec3 col = mix(horizon_col, mid_col, smoothstep(0.0, 0.36, y));
	col = mix(col, zenith_col, smoothstep(0.16, 0.95, up));

	// sun direction from the first directional light
	vec3 sd_raw = LIGHT0_DIRECTION;
	float sdl = length(sd_raw);
	vec3 sd = sdl > 0.0001 ? sd_raw / sdl : vec3(0.0, 0.25, 1.0);
	float sun_energy = max(LIGHT0_ENERGY, 0.0);
	float sun_dot = dot(d, -sd);
	float sun = pow(clamp(sun_dot, 0.0, 1.0), 2200.0) * 8.0;
	float halo = pow(clamp(sun_dot, 0.0, 1.0), 12.0) * 0.9;
	float disc = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.4, sun_dot) * 12.0;
	col += vec3(1.0, 0.55, 0.28) * (sun + halo * 0.55 + disc * sun_energy);
	col += vec3(1.0, 0.35, 0.55) * pow(clamp(sun_dot, 0.0, 1.0), 3.0) * 0.35;

	// horizon haze / city glow (inverse distance to ground ring)
	float horizon_band = exp(-abs(y) * 9.0);
	col += city_glow * horizon_band * (0.28 + 0.9 * night);
	col += city_glow * exp(-abs(y) * 2.2) * 0.16;

	// cloud deck: project onto a plane above the camera
	if (y > -0.02) {
		vec2 cuv = d.xz / max(y + 0.09, 0.02) * 0.55;
		float cl = fbm(cuv * 1.35 + vec2(TIME * 0.006, TIME * 0.003));
		float cl2 = fbm(cuv * 3.1 - vec2(TIME * 0.012, TIME * 0.005));
		float cov = smoothstep(0.5 - cloud_cover * 0.32, 0.86, cl + cl2 * 0.25);
		cov *= smoothstep(0.0, 0.12, y);
		vec3 lit = mix(vec3(0.16, 0.10, 0.18), horizon_col * 0.9, smoothstep(0.6, 0.0, up));
		lit += vec3(1.0, 0.42, 0.24) * pow(clamp(sun_dot, 0.0, 1.0), 5.0) * 0.9;
		lit += vec3(0.55, 0.18, 0.5) * 0.35 * (1.0 - up) * night;
		col = mix(col, lit, cov * 0.82);
	}

	// stars
	if (y > 0.02) {
		vec2 sp = d.xz / (y + 0.28) * 42.0;
		vec2 si = floor(sp);
		float s = h12(si);
		float sbase = clamp(1.0 - length(fract(sp) - 0.5) * 2.0, 0.0, 1.0);
		float star = step(0.995, s) * pow(sbase, 6.0);
		star *= smoothstep(0.0, 0.35, y) * stars;
		star *= 0.6 + 0.4 * sin(TIME * 2.0 + s * 40.0);
		col += vec3(0.8, 0.85, 1.0) * star * 3.0;
	}

	// moon
	vec3 md = normalize(moon_dir);
	float mdot = dot(d, md);
	col += vec3(0.75, 0.8, 0.95) * pow(clamp(mdot, 0.0, 1.0), 4000.0) * 2.2 * stars;
	col += vec3(0.35, 0.4, 0.6) * pow(clamp(mdot, 0.0, 1.0), 90.0) * 0.08 * stars;

	// aerial perspective toward horizon
	col = mix(col, horizon_col * 0.55 + city_glow * 0.35, smog * exp(-max(y, 0.0) * 5.0) * 0.45);

	if (any(isnan(col)) || any(isinf(col))) {
		col = vec3(0.12, 0.08, 0.16);
	}
	COLOR = max(col, vec3(0.0)) * sky_gain;
}
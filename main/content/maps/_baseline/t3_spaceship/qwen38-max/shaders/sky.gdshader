shader_type sky;

// Procedural deep-space sky: 3 star layers, galactic band, nebulae, distant
// sun, and an analytically shaded planet (ray-sphere intersect) with clouds,
// ice caps, night-side city lights and atmosphere rim.

uniform vec3 u_planet_dir = vec3(0.55, 0.12, -0.83);
uniform float u_planet_rad = 0.155;
uniform vec3 u_sun_dir = vec3(-0.62, 0.34, 0.71);
uniform float u_star_gain = 1.0;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash31(vec3(i, 0.0)), hash31(vec3(i + vec2(1, 0), 0.0)), u.x),
			mix(hash31(vec3(i + vec2(0, 1), 0.0)), hash31(vec3(i + vec2(1, 1), 0.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.09 + vec2(9.1, 4.7);
		a *= 0.5;
	}
	return v;
}

vec3 star_layer(vec3 dir, float scale, float thresh, float bright) {
	vec3 p = dir * scale;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash31(id);
	vec3 jit = vec3(hash31(id + 1.3), hash31(id + 2.7), hash31(id + 4.1)) - 0.5;
	float d = length(f - jit * 0.66);
	float m = max(h - thresh, 0.0) / max(1.0 - thresh, 0.001);
	vec3 tint = mix(vec3(1.0, 0.82, 0.68), vec3(0.72, 0.84, 1.0), hash31(id + 9.1));
	return tint * smoothstep(0.1, 0.0, d) * m * m * bright;
}

void sky() {
	vec3 e = normalize(EYEDIR);
	vec3 col = vec3(0.004, 0.005, 0.011);

	// galactic band
	vec3 mb = normalize(vec3(0.35, 0.85, -0.4));
	float band_d = dot(e, mb);
	float band = exp(-band_d * band_d * 9.0);
	vec2 sph = vec2(atan(e.z, e.x) * 1.5, asin(clamp(e.y, -1.0, 1.0)) * 3.0);
	float dust = fbm(sph * 1.7 + band_d * 1.3);
	col += mix(vec3(0.03, 0.034, 0.075), vec3(0.07, 0.06, 0.105), dust) * band * 0.6 * (0.35 + 0.65 * dust);
	// emission nebula patch
	vec3 n2 = normalize(vec3(-0.55, 0.12, 0.82));
	float nb = pow(max(dot(e, n2), 0.0), 9.0);
	col += vec3(0.06, 0.02, 0.05) * nb * (0.5 + fbm(sph * 3.1));
	vec3 n3 = normalize(vec3(0.15, -0.6, 0.78));
	float nb3 = pow(max(dot(e, n3), 0.0), 14.0);
	col += vec3(0.012, 0.036, 0.055) * nb3;

	// stars
	col += star_layer(e, 150.0, 0.972, 4.2) * u_star_gain;
	col += star_layer(e, 320.0, 0.935, 2.0) * u_star_gain;
	col += star_layer(e, 640.0, 0.87, 0.8) * u_star_gain;

	// sun
	float sd = dot(e, normalize(u_sun_dir));
	col += vec3(1.0, 0.97, 0.9) * smoothstep(0.99988, 0.99995, sd) * 40.0;
	col += vec3(1.0, 0.9, 0.7) * pow(max(sd, 0.0), 2200.0) * 4.0;
	col += vec3(0.7, 0.8, 1.0) * pow(max(sd, 0.0), 90.0) * 0.12;

	// planet (ray vs sphere at unit distance)
	vec3 D = normalize(u_planet_dir);
	float r = u_planet_rad;
	float tca = dot(e, D);
	float d2 = tca * tca - 1.0 + r * r;
	vec3 ax = normalize(vec3(0.18, 0.96, -0.2));
	if (d2 > 0.0 && tca > 0.0) {
		float thc = sqrt(d2);
		float t = tca - thc;
		vec3 pn = (e * t - D) / r; // surface normal
		vec3 e1 = normalize(cross(ax, vec3(0.0, 0.0, 1.0) + ax * 0.3));
		vec3 e2 = cross(ax, e1);
		float lat = dot(pn, ax);
		float lon = atan(dot(pn, e2), dot(pn, e1));
		vec2 sp2 = vec2(lon * 1.7, lat * 3.4);
		float cont = fbm(sp2 * 1.9 + 4.0);
		float land = smoothstep(0.5, 0.56, cont);
		float detail = fbm(sp2 * 7.5);
		vec3 ocean = mix(vec3(0.012, 0.045, 0.13), vec3(0.025, 0.09, 0.2), detail);
		vec3 landc = mix(mix(vec3(0.07, 0.17, 0.1), vec3(0.16, 0.14, 0.08), detail), vec3(0.2, 0.2, 0.18), smoothstep(0.62, 0.8, cont));
		vec3 surf = mix(ocean, landc, land);
		float ice = smoothstep(0.74, 0.88, abs(lat));
		surf = mix(surf, vec3(0.85, 0.9, 0.95), ice);
		float cl = fbm(sp2 * 2.6 + vec2(11.0, 3.0));
		float clouds = smoothstep(0.52, 0.74, cl);
		surf = mix(surf, vec3(0.88, 0.9, 0.94), clouds * 0.55);
		// lighting
		float sunf = dot(pn, normalize(u_sun_dir));
		float day = smoothstep(-0.12, 0.25, sunf);
		vec3 lit = surf * (0.02 + 0.6 * day);
		// city lights on night side
		float citycell = step(0.982, vnoise(vec2(lon * 34.0, lat * 60.0)));
		lit += vec3(1.0, 0.75, 0.35) * citycell * land * (1.0 - ice) * (1.0 - day) * 0.55;
		// limb atmosphere
		float rim = smoothstep(r * 0.86, r * 0.995, length(cross(e, D)));
		lit += vec3(0.25, 0.45, 0.9) * rim * (0.35 + 0.65 * day) * 0.3;
		col = lit;
		// thin outer glow ring
	} else {
		float a = length(cross(e, D));
		float halo = smoothstep(r * 1.25, r * 1.0, a) * step(r, a);
		float sunside = 0.4 + 0.6 * max(dot(normalize(e - D * dot(e, D)), normalize(u_sun_dir - D * dot(normalize(u_sun_dir), D))), 0.0);
		col += vec3(0.18, 0.34, 0.7) * halo * 0.14 * sunside;
	}

	COLOR = col;
}

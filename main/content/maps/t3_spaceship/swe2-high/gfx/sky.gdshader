// sky.gdshader — starfield + distant planet + milky band.
shader_type sky;

#include "res://gfx/common.gdshaderinc"

uniform vec3 sun_dir = vec3(0.5, 0.3, -0.8);
uniform vec3 planet_dir = vec3(-0.45, -0.2, 0.87);
uniform float planet_ang = 0.055;   // angular radius
uniform vec3 neb_a : source_color = vec3(0.06, 0.09, 0.16);
uniform vec3 neb_b : source_color = vec3(0.16, 0.07, 0.13);

void sky() {
	vec3 d = EYEDIR;

	// star layers via 3D-ish cell hash on direction
	vec3 col = vec3(0.004, 0.006, 0.012);
	for (int layer = 0; layer < 3; layer++) {
		float sc = 90.0 + float(layer) * 130.0;
		vec3 p = d * sc;
		vec3 i = floor(p);
		vec3 f = fract(p) - 0.5;
		float r = h31(i + float(layer) * 7.0);
		float star = 1.0 - smoothstep(0.0, 0.09 + r * 0.06, length(f));
		float bright = step(0.945 - float(layer) * 0.025, r);
		float tw = 0.75 + 0.25 * sin(TIME * (1.0 + r * 3.0) + r * 40.0);
		col += vec3(0.9 + r * 0.1, 0.92, 1.0 - r * 0.15) * star * bright * tw * (7.0 - float(layer) * 1.2);
	}

	// milky band: tilted great circle haze
	vec3 band_n = normalize(vec3(0.4, 0.8, 0.3));
	float band = exp(-abs(dot(d, band_n)) * 4.5);
	float neb = fbm(vec2(atan(d.y, d.x) * 3.0, d.z * 3.0), 5);
	col += mix(neb_a, neb_b, neb) * band * (0.4 + neb * 0.8);

	// distant ringed planet
	float pd = dot(normalize(d), normalize(planet_dir));
	float pang = acos(clamp(pd, -1.0, 1.0));
	float disc = 1.0 - smoothstep(planet_ang * 0.96, planet_ang, pang);
	if (disc > 0.0) {
		vec3 pl = normalize(d - planet_dir);
		float bands = fbm(vec2(atan(pl.y, pl.x) * 4.0, pl.z * 9.0), 4);
		vec3 pcol = mix(vec3(0.45, 0.35, 0.25), vec3(0.65, 0.55, 0.4), bands);
		// lit limb toward sun
		float lit = clamp(dot(normalize(pl + 0.001), normalize(sun_dir - planet_dir)) * 0.5 + 0.75, 0.05, 1.0);
		col = mix(col, pcol * lit * 0.8, disc);
	}

	// sun: small HDR disc + halo
	float sd = acos(clamp(dot(normalize(d), normalize(sun_dir)), -1.0, 1.0));
	col += vec3(1.0, 0.95, 0.85) * (smoothstep(0.012, 0.004, sd) * 3.0 + exp(-sd * 24.0) * 0.35);

	COLOR = col;
}

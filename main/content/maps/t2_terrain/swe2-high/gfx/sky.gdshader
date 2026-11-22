// sky.gdshader — fantasy dusk dome for the Vale.
// Warm amber horizon → indigo zenith, low sun + halo, slow cirrus bands,
// faint early stars and two thin aurora curtains.
shader_type sky;
render_mode use_half_res_pass;

#include "res://gfx/common.gdshaderinc"

uniform vec3 zenith  : source_color = vec3(0.06, 0.10, 0.22);
uniform vec3 mid     : source_color = vec3(0.22, 0.30, 0.46);
uniform vec3 horizon : source_color = vec3(0.74, 0.60, 0.46);
uniform vec3 sun_col : source_color = vec3(1.0, 0.82, 0.58);
uniform vec3 cloud_warm : source_color = vec3(0.88, 0.62, 0.48);
uniform vec3 cloud_cool : source_color = vec3(0.26, 0.28, 0.44);
uniform vec3 aurora  : source_color = vec3(0.2, 0.85, 0.55);
uniform float cloud_amt = 0.55;
uniform float star_amt  = 0.6;

void sky() {
	vec3 dir = normalize(EYEDIR);
	float y = dir.y;
	float sun_dot = max(dot(dir, LIGHT0_DIRECTION), 0.0);

	// vertical gradient: horizon band compresses warm tones near y≈0
	float t1 = smoothstep(-0.05, 0.35, y);
	float t0 = exp(-max(y + 0.04, 0.0) * 5.5);
	vec3 col = mix(mid, zenith, t1);
	col = mix(col, horizon, t0 * 0.75);

	// sun disc + tight halo + broad warm wedge under it
	float disc = smoothstep(0.9994, 0.9997, sun_dot);
	float halo = pow(sun_dot, 48.0) * 0.6 + pow(sun_dot, 8.0) * 0.18;
	col += sun_col * (disc * 5.0 + halo);

	// cirrus bands: project direction onto a flat plane, drift with TIME
	if (y > 0.015) {
		vec2 cp = dir.xz / (y + 0.18) * 1.6 + vec2(TIME * 0.004, 0.0);
		float cl = fbm(cp * 0.8, 5);
		cl = smoothstep(0.45, 0.75, cl) * cloud_amt;
		vec3 ccol = mix(cloud_cool, cloud_warm, pow(sun_dot, 3.0) * 0.9 + 0.1);
		col = mix(col, ccol, cl * smoothstep(0.015, 0.12, y));
	}

	// early stars: sparse sub-pixel twinkles in the upper dome
	if (y > 0.15) {
		vec2 sp2 = dir.xz / (y + 0.55) * 90.0;
		vec2 cell = floor(sp2);
		vec2 f = fract(sp2);
		float st = h21(cell);
		float tw = step(0.998, st) * (0.5 + 0.5 * sin(TIME * 2.0 + st * 40.0));
		// sub-pixel point, not a cell quad
		float d = length(f - vec2(0.5 + 0.3 * h21(cell + 7.0), 0.5 + 0.3 * h21(cell + 13.0)));
		tw *= smoothstep(0.06, 0.02, d);
		col += vec3(0.9, 0.95, 1.0) * tw * star_amt * smoothstep(0.15, 0.5, y);
	}

	// aurora: two faint curtains, narrower + softer so they read as
	// light, not painted bands
	float az = atan(dir.z, dir.x);
	float rb1 = 0.32 + sin(az * 2.0 + TIME * 0.05) * 0.06;
	float rb2 = 0.46 + sin(az * 3.0 - TIME * 0.04 + 2.0) * 0.08;
	float band = stripe(y, rb1, 0.008) * 0.22 + stripe(y, rb2, 0.012) * 0.12;
	float north = smoothstep(0.15, 0.65, -dir.z);
	col += aurora * band * north * (0.15 + fbm(vec2(az * 4.0, TIME * 0.03), 3) * 0.25);

	COLOR = col;
}

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Flat foam skirt on the plunge pool: lacy rafts and run-off that carry the
// impact white out into the green water.  The foam is world-space noise with
// only a soft radial bias - no angular bands, so it never reads as a grid.

uniform sampler2D sheet_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D mist_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 center = vec2(-203.9, -198.0);
uniform float r_in = 12.0;
uniform float r_out = 96.0;
uniform float strength = 1.0;

varying vec3 wpos;

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
float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(5.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 d = wpos.xz - center;
	float r = length(d);
	vec2 dir = d / max(r, 1e-4);
	float ang = atan(dir.y, dir.x);
	float warp = fbm3(wpos.xz * 0.035);
	float warp2 = fbm3(wpos.xz * 0.12 + 7.0);

	// organic lace drifting outward
	vec2 q1 = wpos.xz * 0.055 + vec2(warp * 0.8, -TIME * 0.012);
	vec2 q2 = wpos.xz * 0.125 + vec2(-warp2 * 0.6, -TIME * 0.022);
	float lace = texture(sheet_tex, q1).r;
	float lace2 = texture(sheet_tex, q2).g;
	// long radial run-off: a noise field that is stretched along the radius
	float streak = fbm3(vec2(ang * 2.2 + warp * 2.0, r * 0.13 - TIME * 0.16));
	float f = lace * 0.58 + lace2 * 0.42 + streak * 0.55 + warp2 * 0.25;

	float foam = smoothstep(0.58, 1.02, f);
	// fray outward: dense right at the impact, lace at the rim
	float fade = smoothstep(r_in, r_in + 12.0, r) * smoothstep(r_out, r_out * 0.55, r);
	float a_out = clamp(foam * fade * (0.45 + 0.50 * (1.0 - r / r_out)), 0.0, 0.72) * strength;

	vec3 col = mix(vec3(0.20, 0.27, 0.29), vec3(0.56, 0.62, 0.63), smoothstep(0.1, 0.75, foam));
	ALBEDO = col;
	ALPHA = a_out;
	ROUGHNESS = 0.55;
}
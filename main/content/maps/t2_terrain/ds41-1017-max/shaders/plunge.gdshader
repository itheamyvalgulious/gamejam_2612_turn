shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Boiling whitewater at the foot of the fall.  Foam is world-space noise
// (no angular bands) swept outward by a radial bias, so the ring reads as
// water thrown away from the column instead of a patterned disc.

uniform sampler2D sheet_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D mist_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 center = vec2(-203.9, -198.0);
uniform float radius = 14.0;
uniform float alpha_gain = 1.0;
uniform float flow = 0.55;
uniform vec3 tint : source_color = vec3(1.0);

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
		p = p * 2.06 + vec2(3.3, 8.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	float d = length(UV - 0.5) * 2.0;
	// heaving mound of foam
	VERTEX.y += (1.0 - d) * (0.45 + 0.40 * sin(d * 7.0 - TIME * 2.0 + UV.x * 9.0));
	VERTEX.y += fbm3(UV * 9.0 + vec2(0.0, -TIME * 0.6)) * 0.75 * (1.0 - d * 0.6);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 d = wpos.xz - center;
	float r = length(d);
	float ang = atan(d.y, d.x);
	float warp = fbm3(wpos.xz * 0.16 + vec2(0.0, TIME * 0.10));
	// outward-swept broken foam
	vec2 q1 = wpos.xz * 0.16 + vec2(warp * 0.5, -TIME * flow * 0.035);
	vec2 q2 = wpos.xz * 0.42 + vec2(-warp * 0.4, -TIME * flow * 0.070);
	float f1 = texture(sheet_tex, q1).g;
	float f2 = texture(sheet_tex, q2).r;
	float streak = fbm3(vec2(ang * 2.0 + warp * 1.6, r * 0.30 - TIME * flow * 0.5));
	float lace = f1 * 0.5 + f2 * 0.45 + streak * 0.55 + warp * 0.2;

	float foam = smoothstep(0.44, 0.98, lace);
	// dense white core right under the column, laced rim further out
	float core = smoothstep(0.66, 0.05, r / radius);
	float a = clamp(foam * 0.80 + core * 0.75, 0.0, 1.0);

	vec3 col = mix(vec3(0.12, 0.17, 0.19), vec3(0.44, 0.50, 0.52), a);
	col = mix(col, tint.rgb, 0.16);
	ALBEDO = col;
	ROUGHNESS = mix(0.45, 0.16, a);
	SPECULAR = 0.45;
	vec3 nrm = normalize(vec3((f1 - 0.5) * 1.2, 1.0, (f2 - 0.5) * 1.2));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	ALPHA = clamp(a * alpha_gain * smoothstep(1.0, 0.55, r / radius), 0.0, 0.92);
}
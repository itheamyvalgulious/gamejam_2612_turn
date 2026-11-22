shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

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
		p = p * 2.05 + vec2(11.1, 6.3);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float fall = fbm3(vec2(uv.x * 6.0, uv.y * 18.0 - TIME * 2.4));
	float fine = fbm3(vec2(uv.x * 22.0, uv.y * 60.0 - TIME * 5.0));
	float sheet = smoothstep(0.18, 0.55, fall * 0.6 + fine * 0.5 + 0.18);
	vec3 col = mix(vec3(0.42, 0.60, 0.64), vec3(0.86, 0.92, 0.94), sheet);
	col = mix(col, vec3(0.86, 0.92, 0.94), smoothstep(0.55, 0.9, uv.y) * 0.6);
	float edge = smoothstep(0.0, 0.22, uv.x) * smoothstep(1.0, 0.78, uv.x);
	ALBEDO = col;
	ROUGHNESS = 0.18;
	SPECULAR = 0.55;
	ALPHA = clamp(0.30 + sheet * 0.45, 0.2, 0.78) * edge;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3((uv.x - 0.5) * 0.5, 0.4, 0.6)), 0.0)).xyz);
}

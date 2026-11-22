shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = INSTANCE_CUSTOM.g * 6.2831;
	VERTEX.y += sin(TIME * 1.4 + ph + UV.y * 4.0) * 0.18 * UV.y;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float edge = smoothstep(0.5, 0.12, abs(u - 0.5));
	float teeth = smoothstep(0.28, 0.55, abs(sin(v * 46.0 + abs(u - 0.5) * 9.0)));
	float alpha = edge * teeth;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	if (alpha < 0.45) { discard; }
	vec3 n = normalize(vnoise(vec2(u * 4.0, v * 4.0)) * vec3(0.3, 0.0, 0.3) + vec3(0.0, 0.8, 0.4));
	if (!FRONT_FACING) { n = -n; }
	vec3 col = mix(vec3(0.10, 0.24, 0.05), vec3(0.24, 0.38, 0.08), hash12(floor(vec2(u * 9.0, 0.0))));
	col = mix(col, vec3(0.38, 0.40, 0.12), smoothstep(0.5, 1.0, v) * 0.3);
	ALBEDO = col;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.14, 0.22, 0.05);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
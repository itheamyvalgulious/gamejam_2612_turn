shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = INSTANCE_CUSTOM.g * 6.2831;
	VERTEX.y += sin(TIME * 1.2 + ph + UV.y * 3.0) * 0.05 * UV.y;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float spine = smoothstep(0.5, 0.06, abs(u - 0.5));
	float leaflets = smoothstep(0.55, 0.25, abs(sin(v * 42.0 + abs(u - 0.5) * 10.0)));
	float alpha = spine * leaflets;
	alpha = max(alpha, smoothstep(0.02, 0.0, abs(u - 0.5)) * 0.9);
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	if (alpha < 0.4) { discard; }
	vec3 n = normalize(vec3((u - 0.5) * 0.7, 0.9, 0.35));
	if (!FRONT_FACING) { n = -n; }
	vec3 col = mix(vec3(0.045, 0.115, 0.025), vec3(0.115, 0.215, 0.045), hash12(floor(vec2(u * 12.0, v * 12.0))) * 0.6 + 0.4);
	col = mix(col, vec3(0.16, 0.23, 0.06), smoothstep(0.6, 1.0, v) * 0.3);
	ALBEDO = col;
	ROUGHNESS = 0.65;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.06, 0.11, 0.02);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform sampler2D opaque_scene : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float phase_amount : hint_range(0.0, 1.0) = 0.0;
uniform float phase_time = 0.0;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 eye = normalize(VIEW);
	float face = clamp(dot(normal, eye), 0.0, 1.0);
	float rim = pow(1.0 - face, 2.9);
	vec3 transmitted = refract(-eye, normal, 0.72);
	vec2 aspect = vec2(VIEWPORT_SIZE.y / VIEWPORT_SIZE.x, 1.0);
	vec2 ripple = vec2(sin(world_point.y * 9.0 + world_point.z * 2.0 - phase_time * 4.2),
		cos(world_point.x * 5.0 + world_point.y * 6.0 + phase_time * 3.8));
	vec2 offset = (transmitted.xy + eye.xy) * (0.076 + rim * 0.026) + ripple * (0.0019 + rim * 0.0022);
	offset *= aspect * phase_amount;
	vec2 uv = SCREEN_UV + offset;
	float blur = 0.08 + rim * 0.75;
	vec3 scene = vec3(
		textureLod(opaque_scene, uv + offset * 0.24, blur).r,
		textureLod(opaque_scene, uv, blur).g,
		textureLod(opaque_scene, uv - offset * 0.20, blur).b);
	float glint = pow(max(dot(normal, normalize(vec3(-0.4, 0.72, 0.56))), 0.0), 27.0);
	vec3 tint = vec3(0.003, 0.014, 0.022) + rim * vec3(0.045, 0.20, 0.27);
	ALBEDO = scene * vec3(0.97, 1.00, 1.02) + tint + glint * vec3(0.055, 0.086, 0.11);
	ALPHA = smoothstep(0.012, 0.88, phase_amount);
}

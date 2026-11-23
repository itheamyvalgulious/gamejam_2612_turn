shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float phase_amount : hint_range(0.0, 1.0) = 0.0;
uniform float phase_time = 0.0;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 eye = normalize(VIEW);
	float facing = clamp(dot(normal, eye), 0.0, 1.0);
	float edge = pow(1.0 - facing, 3.0);
	vec3 bounce = normalize(mat3(INV_VIEW_MATRIX) * reflect(-eye, normal));
	float prism = dot(bounce, vec3(0.53, 0.70, -0.42)) * 1.16 + edge * 0.60;
	prism += sin(dot(world_point, vec3(0.74, 1.45, -0.31)) - phase_time * 0.82) * 0.16;
	float spectrum = 0.5 + 0.5 * cos(6.28318 * prism);
	vec3 spectral = mix(vec3(0.10, 0.76, 1.08), vec3(0.77, 0.22, 1.05), smoothstep(0.12, 0.94, spectrum));
	float gold = smoothstep(0.84, 0.995, cos(6.28318 * (prism + 0.28))) * pow(edge, 0.67);
	spectral = mix(spectral, vec3(1.05, 0.65, 0.18), gold * 0.71);
	float key = pow(max(dot(bounce, normalize(vec3(-0.55, 0.79, -0.36))), 0.0), 21.0);
	float strip = pow(max(dot(bounce, normalize(vec3(0.64, 0.43, 0.64))), 0.0), 13.0);
	float veil = pow(max(dot(bounce, normalize(vec3(0.62, 0.58, -0.51))), 0.0), 4.0);
	ALBEDO = mix(vec3(0.040, 0.055, 0.105), spectral * 0.42, 0.34 + edge * 0.32);
	METALLIC = 0.63;
	ROUGHNESS = 0.17 + 0.16 * facing;
	SPECULAR = 0.65;
	EMISSION = (spectral * (0.05 + 0.49 * edge + 0.30 * veil)
		+ vec3(0.88, 1.03, 1.15) * key * 0.95 + spectral * strip * 0.72) * phase_amount;
	ALPHA = phase_amount * (0.64 + edge * 0.30);
}

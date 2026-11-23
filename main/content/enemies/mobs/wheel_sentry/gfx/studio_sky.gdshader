shader_type sky;

// Broad studio panels define the metallic reflections on the model.
void sky() {
	vec3 direction = EYEDIR;
	float up = max(direction.y, 0.0);
	vec3 base = mix(vec3(0.061, 0.086, 0.112), vec3(0.23, 0.28, 0.32), up);
	float key = pow(max(dot(direction, normalize(vec3(-0.62, 0.76, -0.45))), 0.0), 10.0);
	float cool_strip = pow(max(dot(direction, normalize(vec3(0.82, 0.45, 0.27))), 0.0), 8.0);
	float warm_fill = pow(max(dot(direction, normalize(vec3(-0.38, 0.38, 0.86))), 0.0), 14.0);
	COLOR = base + key * vec3(1.20, 1.17, 1.09)
		+ cool_strip * vec3(0.26, 0.48, 0.66) + warm_fill * vec3(0.60, 0.40, 0.27);
}

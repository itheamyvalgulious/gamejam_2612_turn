shader_type sky;

uniform vec3 top_color : source_color = vec3(0.013, 0.017, 0.034);
uniform vec3 horizon_color : source_color = vec3(0.050, 0.035, 0.020);
uniform vec3 bottom_color : source_color = vec3(0.016, 0.014, 0.012);
uniform vec3 ember_color : source_color = vec3(0.62, 0.34, 0.09);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 dir = EYEDIR;
	float h = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(bottom_color, horizon_color, smoothstep(0.0, 0.52, h));
	col = mix(col, top_color, smoothstep(0.45, 1.0, h));

	// Soft glow behind the weapon, low on the horizon.
	vec3 glow_dir = normalize(vec3(0.0, 0.08, 1.0));
	float g = pow(max(dot(dir, glow_dir), 0.0), 5.0);
	col += ember_color * g * 0.075;

	// A second, broader wash so the background never feels like flat black.
	float wide = pow(max(dot(dir, normalize(vec3(0.15, 0.25, 1.0))), 0.0), 1.6);
	col += ember_color * wide * 0.012;

	// Dither the very dark gradient to keep it smooth.
	vec2 sp = vec2(atan(dir.x, dir.z) * 40.0, dir.y * 40.0);
	col += (hash12(sp) - 0.5) * 0.004;

	COLOR = col;
}
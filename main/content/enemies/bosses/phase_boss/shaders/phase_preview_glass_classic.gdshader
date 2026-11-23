shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform sampler2D opaque_scene : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float phase_amount : hint_range(0.0, 1.0) = 0.0;
uniform bool spectral_fire = true;

float studio_panel(vec3 direction, vec3 center, vec2 width) {
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), center));
	vec3 up = cross(center, side);
	float forward = max(dot(direction, center), 0.001);
	vec2 angle = vec2(dot(direction, side), dot(direction, up)) / forward;
	vec2 edge = 1.0 - smoothstep(width, width + vec2(0.075), abs(angle));
	return edge.x * edge.y * smoothstep(0.0, 0.35, dot(direction, center));
}

void fragment() {
	vec3 smooth_normal = normalize(NORMAL);
	vec3 face_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	face_normal *= dot(face_normal, smooth_normal) < 0.0 ? -1.0 : 1.0;
	vec3 normal = normalize(mix(smooth_normal, face_normal, 0.58));
	vec3 eye = normalize(VIEW);
	float facing = clamp(dot(normal, eye), 0.0, 1.0);
	float rim = 1.0 - facing;
	float fresnel = 0.045 + 0.955 * pow(rim, 4.0);
	float thickness = 1.0 / max(facing, 0.28);

	// Refractive index rises from red to blue, spreading edges in the scene.
	vec2 aspect = vec2(VIEWPORT_SIZE.y / VIEWPORT_SIZE.x, 1.0);
	float zoom = clamp(PROJECTION_MATRIX[1][1] * 5.2, 0.65, 1.80);
	vec2 scale = aspect * (0.088 + 0.026 * rim) * zoom * phase_amount;
	vec2 green = (refract(-eye, normal, 1.0 / 1.52).xy + eye.xy) * scale;
	vec3 transmitted = textureLod(opaque_scene, SCREEN_UV + green, 0.15).rgb;
	if (spectral_fire) {
		vec2 red = (refract(-eye, normal, 1.0 / 1.46).xy + eye.xy) * scale;
		vec2 blue = (refract(-eye, normal, 1.0 / 1.61).xy + eye.xy) * scale;
		transmitted.r = textureLod(opaque_scene, SCREEN_UV + red, 0.15).r;
		transmitted.b = textureLod(opaque_scene, SCREEN_UV + blue, 0.15).b;
	}
	transmitted *= exp(-vec3(0.16, 0.085, 0.062) * thickness);

	vec3 bounce = normalize(mat3(INV_VIEW_MATRIX) * reflect(-eye, normal));
	// The white strip separates at its edges on the more oblique cuts.
	vec3 key = normalize(vec3(-0.62, 0.76, -0.45));
	vec2 key_width = vec2(0.49, 0.12);
	vec3 color_split = spectral_fire ? vec3(0.016, -0.065, 0.040) * (0.18 + rim) : vec3(0.0);
	vec3 white_strip = vec3(
		studio_panel(normalize(bounce + color_split), key, key_width),
		studio_panel(bounce, key, key_width),
		studio_panel(normalize(bounce - color_split), key, key_width)
	);
	float blue_strip = studio_panel(bounce, normalize(vec3(0.82, 0.45, 0.27)), vec2(0.15, 0.51));
	float warm_strip = studio_panel(bounce, normalize(vec3(-0.38, 0.38, 0.86)), vec2(0.34, 0.085));
	vec3 reflection = vec3(0.048, 0.098, 0.135) * (0.8 + 0.55 * max(bounce.y, 0.0));
	reflection += white_strip * vec3(1.60, 1.66, 1.73);
	reflection += blue_strip * vec3(0.29, 0.57, 0.78);
	vec3 fill_color = spectral_fire ? vec3(1.00, 0.63, 0.27) : vec3(0.76, 0.85, 0.95);
	reflection += warm_strip * fill_color;
	float side = spectral_fire ? clamp(0.5 + 0.75 * bounce.x, 0.0, 1.0) : 0.0;
	vec3 edge_tint = mix(vec3(0.10, 0.36, 0.58), vec3(0.46, 0.22, 0.24), side) * pow(rim, 4.8);

	ALBEDO = transmitted * (1.0 - fresnel) + reflection * (0.17 + 0.83 * fresnel) + edge_tint;
	ALPHA = smoothstep(0.012, 0.88, phase_amount);
}


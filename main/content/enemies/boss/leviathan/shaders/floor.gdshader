shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Matte machined floor with a technical grid and one neon accent ring.

uniform vec4 base_color : source_color = vec4(0.026, 0.028, 0.036, 1.0);
uniform vec4 grid_color : source_color = vec4(0.32, 0.40, 0.62, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 0.40, 0.10, 1.0);
uniform float grid_scale = 1.6;
uniform float grid_glow = 0.30;
uniform float accent_radius = 4.6;
uniform float accent_width = 0.02;
uniform float accent_glow = 1.4;
uniform float roughness_value = 0.42;
uniform float metallic_value = 0.55;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(world_pos.xz * grid_scale) - 0.5) / fwidth(world_pos.xz * grid_scale);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	line = pow(line, 1.6);
	float dist = distance(CAMERA_POSITION_WORLD, world_pos);
	line *= smoothstep(24.0, 4.0, dist);
	float r = length(world_pos.xz);
	float ring = smoothstep(accent_width, 0.0, abs(r - accent_radius));
	float ring_soft = smoothstep(accent_width * 6.0, 0.0, abs(r - accent_radius));
	float inner = smoothstep(accent_radius - 0.12, accent_radius, r) * smoothstep(accent_radius + 0.4, accent_radius, r);
	ALBEDO = base_color.rgb;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	EMISSION = grid_color.rgb * line * grid_glow
		+ accent_color.rgb * (ring * accent_glow + ring_soft * 0.18 * accent_glow + inner * 0.05);
}
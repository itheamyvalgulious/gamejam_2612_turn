shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Arena floor: polar service rings, radial seams, faint square grid, hazard
// band and a hot containment ring under the boss.

uniform vec4 base_color : source_color = vec4(0.020, 0.021, 0.028, 1.0);
uniform vec4 grid_color : source_color = vec4(0.26, 0.34, 0.52, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 0.32, 0.06, 1.0);
uniform vec4 cold_color : source_color = vec4(0.30, 0.42, 0.78, 1.0);
uniform float ring_radius = 9.0;
uniform float ring_glow = 1.3;
uniform float roughness_value = 0.66;
uniform float metallic_value = 0.24;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = length(world_pos.xz);
	float ang = atan(world_pos.z, world_pos.x);

	// square micro grid (fades with distance)
	vec2 g = abs(fract(world_pos.xz * 1.25) - 0.5) / fwidth(world_pos.xz * 1.25);
	float sq = 1.0 - min(min(g.x, g.y), 1.0);
	sq = pow(sq, 1.7);
	float cam_d = distance(CAMERA_POSITION_WORLD, world_pos);
	sq *= smoothstep(48.0, 8.0, cam_d) * 0.10;

	// concentric service rings
	float rings = 0.0;
	for (int i = 0; i < 7; i++) {
		float rr = 3.0 + float(i) * 2.6;
		float w = 0.012 + float(i) * 0.002;
		rings += smoothstep(w, 0.0, abs(r - rr));
	}
	float radial = pow(0.5 + 0.5 * cos(ang * 18.0), 90.0);
	radial *= smoothstep(3.0, 5.0, r) * smoothstep(18.0, 14.0, r);

	// hazard band
	float band = smoothstep(0.55, 0.0, abs(mod(ang * 9.0, 1.0) - 0.5))
		* smoothstep(0.10, 0.0, abs(r - 12.5));

	// containment ring
	float ring = smoothstep(0.06, 0.0, abs(r - ring_radius));
	float ring_soft = smoothstep(0.55, 0.0, abs(r - ring_radius));
	float pulse = 0.78 + 0.22 * sin(TIME * 1.6);

	// subtle grime
	float grime = smoothstep(0.35, 0.9,
		sin(world_pos.x * 0.8 + world_pos.z * 0.55) * sin(world_pos.z * 1.1 - world_pos.x * 0.3));
	float tile = hash21(floor(world_pos.xz * 1.7)) * 0.009;

	ALBEDO = base_color.rgb + vec3(tile) + vec3(grime * 0.004);
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value + tile * 3.0;
	EMISSION = grid_color.rgb * (sq + rings * 0.12 + radial * 0.08)
		+ cold_color.rgb * rings * 0.10
		+ accent_color.rgb * (ring * ring_glow * pulse + ring_soft * 0.15 * pulse)
		+ accent_color.rgb * band * 0.22;
	AO = clamp(1.0 - grime * 0.18, 0.0, 1.0);
}
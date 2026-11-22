shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Flight-only motion streak behind each swarm chunk. UV.x across, UV.y 0 head..1 tail.
uniform vec4 tint : source_color = vec4(1.0, 0.20, 0.03, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.70, 0.38, 1.0);
uniform float intensity = 2.2;
instance uniform float fx_seed = 0.0;

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = UV.y;
	float a = pow(max(across, 0.0), 1.6) * pow(max(1.0 - along, 0.0), 2.2);
	vec3 col = mix(hot.rgb, tint.rgb, clamp(along * 1.6, 0.0, 1.0));
	ALBEDO = col * intensity;
	ALPHA = clamp(a * 0.85, 0.0, 1.0);
}

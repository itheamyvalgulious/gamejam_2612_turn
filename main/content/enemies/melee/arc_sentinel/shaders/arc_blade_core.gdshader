shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, specular_disabled;

// ARC // SENTINEL v2 — additive silhouette under the stochastic arc blade.
// Keeps the sword readable at gameplay distance without replacing the bolts.

uniform vec4 tint : source_color = vec4(1.0, 0.30, 0.05, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float edge_power : hint_range(0.5, 6.0) = 2.4;
uniform float scan_scale = 18.0;

void fragment() {
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), edge_power);
	// UV.y runs root->tip along the core mesh
	float bands = 0.70 + 0.30 * sin(UV.y * scan_scale - TIME * 9.0);
	float tip = smoothstep(0.70, 1.0, UV.y);
	vec3 hot = mix(tint.rgb, vec3(1.0, 0.72, 0.38), edge * 0.65 + tip * 0.25);
	ALBEDO = hot * (0.55 + 1.45 * edge + tip * 0.5) * bands * intensity;
	ALPHA = clamp((0.10 + 0.55 * edge + 0.12 * tip) * intensity, 0.0, 0.75);
}
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// =============================================================================
// VESPER // blade aura
// Soft volumetric plasma corona that fades cleanly to 0 at the outer mesh
// silhouette (across -> 1.0) so there are zero double-edge shell outlines.
// =============================================================================

uniform vec4 color : source_color = vec4(0.10, 0.44, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.55, 0.88, 1.0, 1.0);
uniform float strength = 0.65;
uniform float flicker = 0.14;
uniform float edge_power : hint_range(0.5, 6.0) = 1.8;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	float t = UV.y;
	float across = abs(UV.x * 2.0 - 1.0);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));

	// Smooth falloff to 0 at outer mesh edges & grazing silhouettes (no ghost line!)
	float radial_fade = pow(clamp(1.0 - across, 0.0, 1.0), edge_power);
	float angle_fade = smoothstep(0.05, 0.48, facing);
	float env = radial_fade * angle_fade;

	float wisp = vnoise(vec2(UV.x * 5.0, t * 9.0 - TIME * 4.2)) * 0.65
		+ vnoise(vec2(UV.x * 11.0, t * 19.0 - TIME * 7.6)) * 0.35;
	float surge = smoothstep(0.13, 0.0, abs(t - fract(TIME * 0.72))) * 0.70;
	float along = smoothstep(0.0, 0.06, t) * smoothstep(1.0, 0.86, t);
	float flutter = 0.88 + flicker * sin(TIME * 26.0 + t * 19.0);

	vec3 c = mix(color.rgb, edge_color.rgb, clamp(env * 0.55 + surge * 0.4, 0.0, 1.0));
	float density = (0.45 + 0.65 * wisp + surge * 0.55) * env;
	ALBEDO = c * strength * density * along * flutter * 1.65;
	ALPHA = clamp(density * along * flutter * strength * 0.52, 0.0, 0.85);
}

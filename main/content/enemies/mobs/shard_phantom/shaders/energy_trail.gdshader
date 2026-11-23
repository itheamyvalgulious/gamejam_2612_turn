shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Additive trail ribbon. UV.x across, UV.y 0 = newest / 1 = oldest.
// Broken energy filaments + a hot leading edge read as a thrown shuriken's
// wake, not a solid smoke sheet.

uniform vec4 hot_color : source_color = vec4(1.0, 0.92, 0.78, 1.0);
uniform vec4 energy_color : source_color = vec4(1.0, 0.22, 0.03, 1.0);
uniform float intensity = 2.4;
uniform float seed = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract(p * p);
}

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float age = UV.y;
	float core = pow(max(across, 0.0), 2.6) * pow(max(1.0 - age, 0.0), 1.4);
	float fil = pow(0.5 + 0.5 * sin(age * 60.0 - TIME * 6.0 + seed * 13.0
		+ hash11(floor(age * 14.0) + seed) * 9.0), 8.0);
	float flick = 0.7 + 0.3 * sin(TIME * 28.0 + age * 45.0 + seed * 7.0);
	float fade = 1.0 - smoothstep(0.55, 1.0, age);
	ALBEDO = mix(energy_color.rgb, hot_color.rgb, core) * intensity * (1.0 + fil) * flick;
	ALPHA = clamp(core * fade * (0.55 + 0.65 * fil), 0.0, 1.0);
}
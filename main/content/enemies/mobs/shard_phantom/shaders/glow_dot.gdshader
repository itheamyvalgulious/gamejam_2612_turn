shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, billboard_keep_scale;

// Round additive glow (sparks, lens flare, module signal lights).
// `instance uniform` tint lets one material serve a whole crowd.

uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.10, 1.0);
uniform float intensity = 2.2;
uniform float falloff = 2.6;
uniform float core_size = 0.18;
uniform float seed = 0.0;
instance uniform vec4 fx_tint : source_color = vec4(1.0, 0.45, 0.10, 1.0);
instance uniform float fx_seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float glow = exp(-d * d * falloff);
	float core = smoothstep(core_size, 0.0, d);
	float fl = 0.82 + 0.18 * sin(TIME * 9.0 + (seed + fx_seed) * 27.0);
	vec3 col = mix(tint.rgb, fx_tint.rgb, 0.8);
	ALBEDO = col * intensity * (1.0 + core * 1.8) * fl;
	ALPHA = clamp(glow * (0.55 + 0.6 * core) * fl, 0.0, 1.0);
}
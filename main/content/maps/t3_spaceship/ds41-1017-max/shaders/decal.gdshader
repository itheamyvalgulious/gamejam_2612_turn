// ============================================================================
//  decal.gdshader — floor stains, oil pools, scorch marks, scuffs
//  Applied to flat quads 3 mm above the deck; alpha is a procedural mask.
// ============================================================================
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 col : source_color = vec3(0.03, 0.025, 0.02);
uniform float strength : hint_range(0.0, 1.0) = 0.8;
uniform int kind : hint_range(0, 3) = 0;   // 0 grime, 1 oil, 2 dust, 3 scorch
uniform float seed = 0.0;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 27.0;
	vec2 p = (uv - 0.5) * 2.0;
	float r = length(p);
	// irregular puddle outline
	float edge = m_fbm2(p * 2.2 + s, 4);
	float mask = smoothstep(1.0, 0.15, r + (edge - 0.5) * 0.45);
	float grain = m_fbm2(uv * 7.0 + s * 2.0, 4);
	mask *= smoothstep(0.25, 0.65, grain + 0.35);
	vec3 c = col;
	float rough = 0.9;
	float alpha = mask * strength;
	if (kind == 1) {
		// oil: dark, glossy, rainbow-ish film at the rim
		c = mix(vec3(0.025, 0.022, 0.018), vec3(0.06, 0.05, 0.04), grain);
		float film = smoothstep(0.35, 0.9, r) * (1.0 - smoothstep(0.85, 1.0, r));
		c += vec3(0.06, 0.03, 0.10) * film * m_noise2(uv * 9.0 + s);
		rough = mix(0.12, 0.42, grain);
		alpha = mask * strength;
	} else if (kind == 2) {
		// dust / grime accumulation
		c = vec3(0.23, 0.21, 0.18);
		rough = 0.95;
		alpha = mask * strength * 0.55;
	} else if (kind == 3) {
		// scorch
		c = mix(vec3(0.02), vec3(0.11, 0.06, 0.03), grain);
		mask *= smoothstep(0.0, 0.7, m_noise2(p * 5.0 + s));
		rough = 0.85;
		alpha = mask * strength;
	}
	ALBEDO = c;
	ALPHA = clamp(alpha, 0.0, 0.95);
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = kind == 1 ? 0.8 : 0.25;
}
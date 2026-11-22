// ============================================================================
//  emit.gdshader — self-illuminated strips, panels, route markings
// ============================================================================
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 color : source_color = vec3(0.85, 0.92, 1.0);
uniform float energy : hint_range(0.0, 40.0) = 2.6;
uniform int mode : hint_range(0, 5) = 0;
uniform float seed = 0.0;
uniform float speed : hint_range(0.0, 8.0) = 1.0;
uniform float aspect = 1.0;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 13.0;
	float v = 1.0;

	if (mode == 1) {
		// chevrons / arrows (UV.y = direction of travel), tile every 1.0 m
		float y = fract(uv.y * aspect + TIME * speed * 0.25);
		float x = uv.x - 0.5;
		float chev = abs(abs(x) * 1.2 - (0.5 - y)) ;
		float arrow = 1.0 - smoothstep(0.035, 0.075, chev);
		arrow *= smoothstep(0.0, 0.12, y) * (1.0 - smoothstep(0.55, 0.92, y));
		v = 0.12 + arrow * 1.1;
	} else if (mode == 2) {
		// dashed strip (zero outside dashes)
		float d = step(fract(uv.y * 2.2 + s), 0.62);
		v = 0.05 + d * 1.0;
	} else if (mode == 3) {
		// flickering emergency tube
		float flick = 0.7 + 0.3 * sin(TIME * 31.0 + s * 90.0) * sin(TIME * 7.3 + s * 12.0);
		flick = mix(0.25, 1.0, m_sat(flick));
		v = flick;
	} else if (mode == 4) {
		// segmented ring / panel with gaps
		float seg = step(0.08, fract(uv.x * 8.0 + s)) * step(0.08, fract(uv.y * 3.0 + s));
		v = 0.25 + 0.75 * seg;
	} else if (mode == 5) {
		// soft, slightly noisy light panel (ceiling luminaires)
		float n = m_noise2(uv * 2.0 + s) * 0.06;
		float edge = smoothstep(0.0, 0.04, uv.x) * smoothstep(1.0, 0.96, uv.x)
			* smoothstep(0.0, 0.03, uv.y) * smoothstep(1.0, 0.97, uv.y);
		v = (0.85 + n) * (0.55 + 0.45 * edge);
	}

	ALBEDO = color * energy * v;
	ALPHA = 1.0;
}
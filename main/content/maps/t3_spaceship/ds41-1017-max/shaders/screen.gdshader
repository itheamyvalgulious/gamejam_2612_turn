// ============================================================================
//  screen.gdshader — procedural console / status screens
//  No textures: each screen is drawn from formulas in screen space.
// ============================================================================
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 ink : source_color = vec3(0.25, 0.85, 1.0);
uniform vec3 bg : source_color = vec3(0.008, 0.016, 0.026);
uniform float seed = 0.0;
uniform float energy : hint_range(0.0, 8.0) = 1.7;
uniform int mode : hint_range(0, 4) = 0;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 43.0;
	float aspect = 1.6;

	// bezel / glass curvature mask
	vec2 q = (uv - 0.5) * vec2(1.0, 0.65);
	float lens = smoothstep(0.52, 0.30, length(q));

	vec3 col = bg;
	float t = TIME;

	// generic chrome: header bar + frame
	col += ink * 0.5 * step(0.90, uv.y) * step(0.05, uv.x) * step(uv.x, 0.95) * 0.4;
	col += ink * 0.7 * (1.0 - smoothstep(0.0, 0.006, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y))));

	// scanlines
	col *= 0.85 + 0.15 * step(0.5, fract(uv.y * 220.0));

	if (mode == 0) {
		// navigation: orbit rings + ship marker + grid
		vec2 p = uv - vec2(0.5, 0.46);
		p.x *= aspect;
		float grid = max(m_grid_line(p.x * 8.0, 0.82), m_grid_line(p.y * 8.0, 0.82));
		col += ink * 0.10 * grid;
		for (int i = 0; i < 3; i++) {
			float r = 0.16 + float(i) * 0.11 + 0.01 * sin(t * 0.5 + float(i));
			float ring = 1.0 - smoothstep(0.0, 0.004, abs(length(p) - r));
			float arc = step(0.25 + float(i) * 0.2, fract(atan(p.y, p.x) / 6.2831 + t * 0.02));
			col += ink * ring * arc * 1.2;
		}
		float ship = 1.0 - smoothstep(0.0, 0.022, length(p - vec2(0.05, 0.03)));
		col += vec3(1.0, 0.6, 0.2) * ship;
		// target blips
		vec2 blip = floor(m_hash22(floor(p * 18.0 + vec2(3.0, 7.0))) * 20.0);
		float bd = length(fract(p * 18.0) - 0.5);
		col += ink * step(0.93, m_hash21(floor(p * 18.0))) * (1.0 - smoothstep(0.02, 0.06, bd));
	} else if (mode == 1) {
		// power: bar graph + waveform
		float bars = floor(uv.x * 14.0);
		float bh = 0.15 + 0.45 * m_hash21(vec2(bars, s)) * (0.6 + 0.4 * sin(t * 1.1 + bars));
		float bmask = step(0.18, uv.y) * step(uv.y, 0.18 + bh) * step(0.12, fract(uv.x * 14.0)) * step(fract(uv.x * 14.0), 0.85);
		col += mix(ink, vec3(1.0, 0.45, 0.15), step(0.75, m_hash21(vec2(bars, 9.0)))) * bmask * 0.9;
		float wave = 0.5 + 0.12 * sin(uv.x * 30.0 + t * 2.0) + 0.05 * sin(uv.x * 77.0 - t);
		float line = 1.0 - smoothstep(0.0, 0.012, abs(uv.y - wave));
		col += vec3(1.0, 0.35, 0.2) * line;
	} else if (mode == 2) {
		// medical: ecg + torso wireframe
		vec2 p = uv - vec2(0.5, 0.5);
		p.x *= aspect;
		float ecg = 0.5 + 0.20 * sin(p.x * 46.0) * exp(-abs(p.x) * 3.0);
		ecg += step(0.42, abs(p.x - 0.02)) * 0.0;
		float spike = exp(-pow((p.x - 0.02) * 30.0, 2.0)) * 0.22;
		float line = 1.0 - smoothstep(0.0, 0.010, abs(uv.y - (ecg + spike)));
		col += vec3(0.3, 1.0, 0.55) * line * 1.3;
		float body = 1.0 - smoothstep(0.0, 0.006, abs(length(vec2(p.x * 0.6, p.y * 1.2)) - 0.14));
		col += vec3(0.4, 0.9, 1.0) * body * 0.6;
		col += ink * 0.25 * step(0.5, fract(uv.y * 4.0)) * step(0.5, fract(uv.x * 2.0));
	} else if (mode == 3) {
		// engineering: reactor schematic, scrolling data
		vec2 p = uv - vec2(0.5, 0.52);
		p.x *= aspect;
		float torus = abs(length(p) - 0.19);
		col += ink * (1.0 - smoothstep(0.0, 0.008, torus)) * 1.2;
		col += vec3(1.0, 0.5, 0.15) * (1.0 - smoothstep(0.0, 0.06, length(p))) * (0.5 + 0.5 * sin(t * 4.0));
		for (int i = 0; i < 3; i++) {
			float y = fract(uv.y * 0.6 + t * 0.03 + float(i) * 0.33);
			col += ink * 0.35 * (1.0 - smoothstep(0.0, 0.004, abs(uv.y - y))) * step(0.1, uv.x) * step(uv.x, 0.9);
		}
	} else {
		// bars of fake text / logs
		float row = floor(uv.y * 16.0);
		float rw = 0.2 + m_hash21(vec2(row, s)) * 0.6;
		float on = step(0.12, uv.x) * step(uv.x, 0.12 + rw) * step(0.2, fract(uv.y * 16.0)) * step(fract(uv.y * 16.0), 0.62);
		col += ink * on * 0.7 * step(0.25, m_hash21(vec2(row, 3.0 + s)));
		col += vec3(1.0, 0.5, 0.2) * step(0.93, m_hash21(vec2(row, 7.0 + s))) * on;
	}

	col *= lens;
	col += bg * 0.35;
	ALBEDO = col * energy;
}
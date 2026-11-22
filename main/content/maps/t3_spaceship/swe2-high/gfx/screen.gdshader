// screen.gdshader — console / status displays. Unit UV.
// style 0: telemetry dashboard, 1: star map, 2: text rows
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://gfx/common.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.20, 0.65, 0.85);
uniform vec3 accent : source_color = vec3(0.95, 0.55, 0.15);
uniform float brightness = 1.6;
uniform int style : hint_range(0, 2) = 0;
uniform float seed = 1.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 col = vec3(0.015, 0.03, 0.045);          // screen backing
	float e = 0.0;

	// bezel: darker border
	float bez = step(uv.x, 0.03) + step(0.97, uv.x) + step(uv.y, 0.05) + step(0.95, uv.y);
	vec2 su = uv;

	if (style == 0) {
		// dashboard: value bars + waveform + digits grid
		vec2 g = floor(vec2(su.x * 6.0, su.y * 4.0));
		vec2 f = fract(vec2(su.x * 6.0, su.y * 4.0));
		float r = h21(g + seed);
		float val = fract(r * 7.13 + t * 0.11 * (0.3 + r));
		float bar = step(f.y, 0.75) * step(0.1, f.y) * step(f.x, val * 0.9);
		vec3 bc = mix(tint, accent, step(0.78, r));
		col += bc * bar * (0.5 + 0.5 * r);
		// waveform strip across middle
		float wy = 0.52 + (vnoise(vec2(su.x * 14.0 + t * 1.4, seed)) - 0.5) * 0.16;
		col += tint * stripe(abs(su.y - wy), 0.006, 0.006) * 1.2;
		// header
		col += accent * step(0.9, su.y) * step(0.05, fract(su.x * 24.0)) * 0.7;
		e = brightness;
	}
	else if (style == 1) {
		// nav star-map: dots + orbit arcs + reticle
		vec3 v = voro(su * 26.0 + seed);
		float star = 1.0 - smoothstep(0.0, 0.06, v.x);
		col += vec3(0.9, 0.95, 1.0) * star * (0.4 + v.z);
		// orbit rings
		float r1 = length(su - vec2(0.5, 0.55));
		col += tint * stripe(abs(r1 - 0.22), 0.004, 0.004) * 0.8;
		col += tint * stripe(abs(r1 - 0.34), 0.003, 0.004) * 0.5;
		// rotating sweep
		float ang = atan(su.y - 0.55, su.x - 0.5);
		float sw = fract(ang / 6.2831 - t * 0.04);
		col += tint * smoothstep(0.12, 0.0, sw) * 0.35;
		// target marker
		vec2 tp = vec2(0.5 + 0.22 * cos(t * 0.23 + seed), 0.55 + 0.22 * sin(t * 0.23 + seed));
		col += accent * stripe(length(su - tp) - 0.014, 0.004, 0.005) * 1.4;
		col += accent * stripe(abs(su.x - tp.x), 0.002, 0.003) * step(abs(su.y - tp.y), 0.03) * 0.8;
		col += accent * stripe(abs(su.y - tp.y), 0.002, 0.003) * step(abs(su.x - tp.x), 0.03) * 0.8;
		e = brightness;
	}
	else {
		// scrolling data rows
		vec2 g = vec2(floor(su.x * 8.0), floor(su.y * 18.0 + t * (0.4 + seed * 0.1)));
		float r = h21(g + seed * 3.0);
		vec2 f = fract(vec2(su.x * 8.0, su.y * 18.0 + t * (0.4 + seed * 0.1)));
		float seg = step(0.15, f.x) * step(f.x, 0.85 * r + 0.1) * step(0.3, f.y) * step(f.y, 0.7);
		col += mix(tint * 0.7, accent, step(0.9, r)) * seg;
		e = brightness * 0.8;
	}

	// scanlines + glass tint + flicker
	col *= 0.85 + 0.15 * sin(su.y * 500.0);
	float flick = 0.96 + 0.04 * sin(t * 31.0 + seed);

	ALBEDO = col;
	EMISSION = col * e * flick * (1.0 - bez);
	ROUGHNESS = 0.35;
	METALLIC = 0.1;
}

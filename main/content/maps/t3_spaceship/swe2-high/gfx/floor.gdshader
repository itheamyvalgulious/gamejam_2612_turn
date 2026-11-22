// floor.gdshader — deck plates, tread plates, carpet-ish zones.
// style 0: metal deck plates   1: tread/diamond plate   2: walkway ribbed
// UV in metres; COLOR.r seed.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://gfx/common.gdshaderinc"

uniform vec3 base : source_color = vec3(0.30, 0.31, 0.335);
uniform vec3 seam_col : source_color = vec3(0.10, 0.105, 0.115);
uniform vec3 line_col : source_color = vec3(0.85, 0.55, 0.10);
uniform int style : hint_range(0, 2) = 0;
uniform float line_pitch = 4.0;      // painted guide line interval (0 = off)
uniform float grime : hint_range(0, 2) = 1.0;
uniform float seed = 0.0;

varying vec4 vcol;

void vertex() { vcol = COLOR; }

void fragment() {
	vec2 uv = UV;
	float s = seed + vcol.r * 53.0;
	float wear = vcol.a;

	vec3 col = base;
	float rough = 0.6;
	float metal = 0.42;
	float h = 0.5;

	float pxf = max(fwidth(uv.x), fwidth(uv.y));
	// seams/ribs die by ~8 m — dark groove lines at grazing angle alias into
	// continuous rope-like bands running down the corridor floor edges
	float sfade = 1.0 - smoothstep(0.02, 0.09, pxf);
	if (style == 0) {
		// large deck plates with varied sub-panels
		vec2 cid; vec2 f; float rnd;
		float seam = panels(uv, vec2(3.6, 3.6), 0.0, s, cid, f, rnd);
		col *= 0.9 + rnd * 0.2;
		float sub = panels(uv + vec2(0.8), vec2(1.2, 1.2), 0.0, s + 9.0, cid, f, rnd) * 0.14;
		seam = max(seam, sub) * sfade;
		h = 1.0 - seam * 0.5;
		col *= 1.0 - seam * 0.4;
		// brushed direction alternates per plate
		float br = brushed(uv, 14.0, step(0.5, rnd));
		col *= 0.96 + br * 0.07 * sfade;
		rough = 0.55 + br * 0.15 + seam * 0.4;
		metal = 0.35 * (1.0 - seam * 0.6);
	}
	else if (style == 1) {
		// diamond tread plate
		vec2 g = abs(fract(mat2(vec2(0.7, 0.7), vec2(-0.7, 0.7)) * uv * 1.35) - 0.5);
		float lug = 1.0 - smoothstep(0.14, 0.30, min(g.x, g.y));
		h = lug * 0.5;
		col *= 0.94 + lug * 0.08;
		rough = 0.62 + (1.0 - lug) * 0.15;
		vec2 cid; vec2 f; float rnd;
		float seam = panels(uv, vec2(3.0, 3.0), 0.0, s, cid, f, rnd) * sfade;
		metal = 0.4 * (1.0 - seam * 0.6);
		col *= 0.9 + rnd * 0.15;
		h -= seam * 0.4;
		col *= 1.0 - seam * 0.45;
	}
	else {
		// ribbed walkway (corridors) — the 12.5cm ribs and 1.2m seams alias
		// into a continuous black rope hugging each wall at grazing angles;
		// fade both to flat by ~8 m
		float px2 = max(fwidth(uv.x), fwidth(uv.y));
		float df = 1.0 - smoothstep(0.02, 0.09, px2);
		float rib = (1.0 - smoothstep(0.012, 0.02, abs(fract(uv.y * 8.0) - 0.5) / 8.0)) * df;
		vec2 cid; vec2 f; float rnd;
		float seam = panels(uv, vec2(1.2, 2.4), 0.0, s, cid, f, rnd) * df;
		h = rib * 0.6 + (1.0 - seam) * 0.4;
		col *= 0.9 + rnd * 0.16;
		col = mix(col, col * 0.7, rib * 0.5);
		rough = 0.62 + rib * 0.15 + seam * 0.35;
		metal = 0.35 * (1.0 - seam * 0.6);
	}

	// painted guide line along X direction
	if (line_pitch > 0.5) {
		float ln = stripe(abs(fract(uv.x / line_pitch) - 0.5) * line_pitch, 0.045, 0.012);
		float fade = 0.6 + fbm(uv * 2.0, 3) * 0.4;
		col = mix(col, line_col, ln * 0.75 * fade);
		rough = mix(rough, 0.7, ln);
		metal = mix(metal, 0.1, ln);
	}

	// grime pools into seams and random blotches
	float gr = fbm(uv * 1.4 + s, 4);
	col *= 1.0 - gr * 0.18 * grime * wear;
	float scr = fbm(uv * 9.0, 3);
	rough += scr * 0.08;

	ALBEDO = col;
	ROUGHNESS = clamp(rough + 0.12, 0.45, 0.95);
	METALLIC = metal * 0.7;
	SPECULAR = 0.25;
	NORMAL = bumpn(NORMAL, VERTEX, h, 0.4);
	AO = 1.0 - (1.0 - h) * 0.35;
}

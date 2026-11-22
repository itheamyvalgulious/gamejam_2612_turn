// metal.gdshader — structural / machinery metal.
// style 0: raw dark structure, 1: painted machinery, 2: bright alloy, 3: copper bus
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://gfx/common.gdshaderinc"

uniform vec3 base : source_color = vec3(0.23, 0.24, 0.26);
uniform int style : hint_range(0, 3) = 0;
uniform float wear_k : hint_range(0, 1) = 0.6;
uniform float seed = 0.0;

varying vec4 vcol;

void vertex() { vcol = COLOR; }

void fragment() {
	vec2 uv = UV;
	float s = seed + vcol.r * 89.0;
	float wear = vcol.a * wear_k;

	vec3 col = base;
	float rough = 0.62;
	// metallic is crushed hard: with no reflection probes/SSR a metallic
	// surface at grazing angle reflects the black starfield and renders as
	// a void — interiors must stay diffuse-driven
	float metal = 0.05;
	float h = 0.5;

	if (style == 0) {
		// dark welded structure: plates + weld beads + oil stains
		vec2 cid; vec2 f; float rnd;
		float seam = panels(uv, vec2(1.8, 2.4), 0.0, s, cid, f, rnd) * 0.8;
		h = fbm(uv * 2.5, 3) * 0.12 - seam * 0.18;
		col *= 1.0 - seam * 0.35;
		col *= 0.94 + rnd * 0.12;
		float oil = fbm(uv * 1.3 + s, 4);
		col = mix(col, col * vec3(0.62, 0.66, 0.68), smoothstep(0.6, 0.85, oil) * wear);
		rough = 0.62 + oil * 0.25;
		float rv = rivets(uv, 1.8, 0.012);
		h += rv * 0.06;
		col = mix(col, col * 0.75, rv * 0.5);
	}
	else if (style == 1) {
		// painted machine enamel, chipped edges reveal metal
		vec2 cid; vec2 f; float rnd;
		float seam = panels(uv, vec2(0.8, 1.0), 0.0, s, cid, f, rnd);
		h = fbm(uv * 3.0, 3) * 0.1 - seam * 0.15;
		col *= 1.0 - seam * 0.35;
		col *= 0.9 + rnd * 0.18;
		float chip = fbm(uv * 7.0 + s, 3);
		float chipped = smoothstep(0.72, 0.82, chip) * wear;
		col = mix(col, vec3(0.35, 0.35, 0.36), chipped);
		rough = 0.55 + chipped * 0.3;
		metal = mix(0.04, 0.10, chipped);
	}
	else if (style == 2) {
		// bright machined alloy: broad directional brushing only — fine
		// per-pixel noise reads as TV static up close
		float br = brushed(uv, 4.0, step(0.5, h21(floor(uv / 0.8) + s)));
		col *= 0.94 + br * 0.06;
		rough = 0.55 + br * 0.10;
		metal = 0.08;
		h = (br - 0.5) * 0.01;
		float stain = fbm(uv * 0.7 + s, 3);
		col *= 1.0 - stain * 0.08;
	}
	else {
		// copper / busbar
		float br = brushed(uv, 22.0, 1.0);
		col *= 0.92 + br * 0.12;
		float pat = fbm(uv * 3.0 + s, 4);
		col = mix(col, vec3(0.22, 0.34, 0.30), smoothstep(0.62, 0.8, pat) * 0.5);
		rough = 0.3 + br * 0.15;
		metal = 0.12;
		h = (br - 0.5) * 0.03;
	}

	float gr = fbm(uv * 0.9 + s * 0.7, 4);
	col *= 1.0 - gr * 0.10 * wear;

	ALBEDO = col;
	ROUGHNESS = clamp(rough + 0.22, 0.55, 0.97);
	SPECULAR = 0.28;
	METALLIC = metal;
	NORMAL = bumpn(NORMAL, VERTEX, h, 0.35);
}

// wall.gdshader — painted interior wall panels.
// UV in metres. COLOR.r = part seed, .g = local height 0..1, .a = wear.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://gfx/common.gdshaderinc"

uniform vec3 base : source_color = vec3(0.42, 0.43, 0.45);
uniform vec3 trim : source_color = vec3(0.15, 0.16, 0.18);
uniform vec3 accent : source_color = vec3(0.82, 0.36, 0.06);
uniform float accent_chance : hint_range(0, 1) = 0.08;
uniform vec2 panel_size = vec2(1.30, 0.82);
uniform float grime : hint_range(0, 2) = 0.7;
uniform float bump = 0.25;
uniform float seed = 0.0;

varying vec4 vcol;

void vertex() { vcol = COLOR; }

void fragment() {
	vec2 uv = UV;
	float s = seed + vcol.r * 71.0;
	float lh = clamp(vcol.g, 0.0, 1.0);
	float wear = vcol.a;

	vec2 cid; vec2 f; float rnd;
	float px = max(fwidth(uv.x), fwidth(uv.y));
	float dfade = 1.0 - smoothstep(0.03, 0.12, px);
	// panel seams: crisp 1 px groove up close, dead past ~6 m — a hard dark
	// line at grazing angle moires into what reads as a braided black cable
	// running the whole corridor, so kill it by distance, not by softening
	float seam = panels(uv, panel_size, 0.0, s, cid, f, rnd);
	seam *= 1.0 - smoothstep(0.012, 0.045, px);

	vec3 col = base;
	col *= 0.93 + rnd * 0.14;                        // gentle per-panel shift
	float r2 = h21(cid + s);                         // second per-panel hash
	col = mix(col, base * vec3(0.88, 0.94, 1.08), step(0.88, r2) * 0.25); // cool alt panels
	col = mix(col, accent, step(rnd, accent_chance * 0.3) * 0.8);

	// kick plate at the very bottom + crown trim near the top — painted
	// bands, not black cable runs: keep them soft and let them melt away
	// with distance so they don't read as floating black bars
	// kick + crown bands disabled: at grazing angles ANY dark painted band
	// running the wall base reads as a floating black cable to the eye.
	// A 2 px AO-line at the true wall/floor junction gives the depth cue
	// instead of a 15 cm stripe
	float rail = stripe(lh - 0.02, 0.008, 0.006) * 0.18;
	float crown = 0.0;
	col *= 1.0 - clamp(rail + crown, 0.0, 0.6) * dfade;
	// occasional vertical stiffener (only every 3rd panel) — distance-faded:
	// a trim-coloured stripe at grazing angle reads as a conduit, not paint
	float rib = 1.0 - smoothstep(0.0, 0.045, abs(fract(uv.x / (panel_size.x * 3.0)) - 0.5) * panel_size.x * 3.0 - panel_size.x);
	col = mix(col, trim * 0.9, rib * 0.55 * dfade);

	// corner fasteners (fade at range so they don't speckle)
	vec2 cp = abs(f - 0.5) * panel_size - (panel_size * 0.5 - 0.05);
	float bolt = (1.0 - smoothstep(0.012, 0.02, length(max(cp, 0.0)))) * dfade;
	col = mix(col, trim * 0.8, bolt * 0.6);

	// broad low-frequency grime (avoid high-freq speckle)
	float gr = fbm(uv * 0.55 + s, 4);
	col *= 1.0 - smoothstep(0.55, 0.85, gr) * 0.16 * grime * wear;
	float drip = fbm(vec2(uv.x * 3.0, uv.y * 0.5) + s, 3);
	col *= 1.0 - smoothstep(0.6, 0.9, drip) * 0.10 * grime * wear;

	// painted surface: dielectric, mid roughness
	float rough = 0.85 + gr * 0.12 + seam * 0.10;

	ALBEDO = col * (1.0 - seam * 0.10);
	ROUGHNESS = clamp(rough, 0.35, 0.95);
	METALLIC = 0.02;
	SPECULAR = 0.15;
	float h = fbm(uv * 1.4 + s, 3) * 0.3 - bolt * 0.25;
	NORMAL = bumpn(NORMAL, VERTEX, h, bump * 0.5);
	AO = 1.0 - seam * 0.12;
}

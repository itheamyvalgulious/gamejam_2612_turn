shader_type spatial;
// =============================================================================
// VESPER smoked visor — 50% transmission with real optical effects
// -----------------------------------------------------------------------------
// * REFRACTION: the shell samples the screen behind it with a view-normal
//   offset, so the blue optic and the black cavity are visibly bent.
// * DISPERSION: R/G/B are refracted with slightly different strengths, so the
//   edges of what is behind the glass split into a faint chromatic fringe.
// * REFLECTION: a Fresnel sky reflection plus a moving polished-glint band.
// * The glass is 50% opaque (ALPHA 0.50) - a smoked window, not a mirror ball.
// The shell is single-sided: the inside of the front glass is never drawn, so
// the head interior cannot bleed through from behind.
// =============================================================================
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform vec4 tint : source_color = vec4(0.020, 0.040, 0.095, 1.0);
uniform vec4 rim_color : source_color = vec4(0.28, 0.55, 1.0, 1.0);
uniform vec4 sky_color : source_color = vec4(0.45, 0.62, 0.95, 1.0);
uniform float base_alpha = 0.50;
uniform float refract_strength = 0.008;
uniform float dispersion = 0.18;
uniform float reflect_strength = 0.55;
uniform float rim_alpha = 0.55;
uniform float rim_power = 2.6;
uniform float sheen = 0.85;
uniform float scan_speed = 2.4;
uniform float scan_strength = 0.16;
uniform float inner_glow = 0.28;
uniform float seed = 0.0;

void fragment() {
	vec3 N = normalize(NORMAL);
	vec3 V = normalize(VIEW);
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	float fres = pow(1.0 - ndv, rim_power);

	// ---- refraction + dispersion ------------------------------------------
	// N.xy is the view-space surface slope; larger at the curved edges.
	vec2 off = N.xy * refract_strength * (0.35 + 0.65 * fres);
	vec2 uvR = SCREEN_UV + off * (1.0 - dispersion);
	vec2 uvG = SCREEN_UV + off;
	vec2 uvB = SCREEN_UV + off * (1.0 + dispersion);
	vec3 refr = vec3(
		texture(screen_tex, uvR).r,
		texture(screen_tex, uvG).g,
		texture(screen_tex, uvB).b);

	// smoked absorption on the refracted light (blue-shifted smoke)
	vec3 smoked = refr * mix(vec3(0.86, 0.92, 1.0), tint.rgb * 6.0, 0.35);

	// ---- reflections -------------------------------------------------------
	// sky gradient on the curved glass + a polished glint that slides over it
	vec3 refl_col = mix(vec3(0.10, 0.16, 0.30), sky_color.rgb, clamp(N.y * 0.5 + 0.5, 0.0, 1.0));
	float polish = pow(0.5 + 0.5 * sin(UV.x * 22.0 + UV.y * 3.0 + TIME * 0.12 + seed), 12.0);
	float glint = polish * (0.25 + 0.75 * fres) * sheen;
	float streak = 0.5 + 0.5 * sin(UV.y * 52.0 + UV.x * 13.0);
	float edge = smoothstep(0.93, 0.995, UV.y) + smoothstep(0.06, 0.005, UV.y);
	edge += smoothstep(0.06, 0.005, UV.x) + smoothstep(0.94, 0.995, UV.x);

	// ---- scan band ---------------------------------------------------------
	float scan = smoothstep(0.6, 1.0, 0.5 + 0.5 * sin(UV.y * 140.0 - TIME * scan_speed * 6.0));

	ALBEDO = smoked;
	METALLIC = 0.0;
	ROUGHNESS = 0.05;
	SPECULAR = 0.85;

	EMISSION = refl_col * reflect_strength * (0.18 + 0.82 * fres)
		+ rim_color.rgb * fres * sheen * 0.30
		+ vec3(0.75, 0.88, 1.0) * (glint * 0.45 + edge * 0.18)
		+ vec3(0.45, 0.70, 1.0) * scan * scan_strength * 0.12;

	// 50% transmission: the eye behind is half-visible through the smoked glass
	float alpha = base_alpha + fres * 0.10 + scan * scan_strength * 0.06;
	ALPHA = clamp(alpha, 0.0, 0.72);
}
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled, shadows_disabled, specular_disabled;

// Camera-facing arc ribbons. Ported from the Voltaic Edge sword shader, with a
// deep orange-red aura and a white-hot orange core instead of pale gold.

uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform float fade : hint_range(0.0, 1.5) = 1.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

varying vec2 v_uv;
varying vec4 v_params;
varying float v_fade;

void vertex() {
	vec3 other = CUSTOM0.xyz;
	float half_world = CUSTOM0.w;

	vec4 va = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 vb = MODELVIEW_MATRIX * vec4(other, 1.0);
	vec4 ca = PROJECTION_MATRIX * va;
	vec4 cb = PROJECTION_MATRIX * vb;

	vec2 pa = (ca.xy / ca.w * 0.5 + 0.5) * screen_size;
	vec2 pb = (cb.xy / cb.w * 0.5 + 0.5) * screen_size;
	// For A-side vertices CUSTOM0 points to B, and for B-side vertices it
	// points back to A. Flip the B-side vector so every corner of the ribbon
	// agrees on one screen-space direction. Without this, the quad twists
	// into a bow-tie and can flash as a large triangle.
	vec2 dir = pb - pa;
	if (UV.x > 0.5) {
		dir = -dir;
	}
	float seg_len = length(dir);
	if (seg_len < 0.0001) {
		dir = vec2(1.0, 0.0);
	} else {
		dir /= seg_len;
	}
	vec2 perp = vec2(-dir.y, dir.x);

	vec4 clip = PROJECTION_MATRIX * va;
	float half_px = half_world * PROJECTION_MATRIX[1][1] / max(clip.w, 0.001) * screen_size.y * 0.5;
	float cap = mix(9.0, 11.0, clamp(CUSTOM1.w, 0.0, 1.0));
	half_px = clamp(half_px, 4.4, cap);

	// Expand perpendicular to the projected segment, then slightly along it
	// so neighbouring segments overlap and leave no dark cracks at the joints.
	vec2 offset_px = perp * half_px * UV.y;
	offset_px += dir * half_px * (UV.x * 2.0 - 1.0) * 0.32;

	clip.xy += (offset_px / screen_size) * 2.0 * clip.w;
	POSITION = clip;

	v_uv = UV;
	v_params = CUSTOM1;
	v_fade = fade;
}

void fragment() {
	float d = abs(v_uv.y);

	// Thin white-hot orange filament inside a wide, very soft orange-red aura.
	float leader = clamp(v_params.w, 0.0, 1.0);
	float core_edge = mix(0.32, 0.42, leader);
	float core = smoothstep(core_edge, 0.0, d);
	float halo = pow(max(1.0 - d, 0.0), 1.9);

	float energy = v_params.x * v_fade * intensity;

	vec3 gold = vec3(1.00, 0.040, 0.002);                      // deep orange-red aura
	vec3 hot = mix(vec3(2.45, 0.58, 0.035), vec3(1.55, 0.24, 0.010), v_params.y);
	hot = mix(hot, vec3(3.05, 1.20, 0.16), leader * 0.55);     // white-hot orange core

	vec3 col = gold * halo * 1.80 + hot * core;
	ALBEDO = col;
	float a = (halo * 0.30 + core * 0.78) * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
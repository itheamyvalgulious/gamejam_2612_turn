shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// =============================================================================
// VESPER // thruster plume — layered engine flame
//
// One additive material renders a co-annular-style plume as three stacked
// layers keyed off the cone UVs:
//   * inner core   — white-blue, narrow, hottest right at the nozzle
//   * middle sheath — electric blue, carries the shock diamonds / turbulence
//   * outer halo   — deep blue, wide, soft, feathers out to transparency
//
// UV mapping (set by the cone meshes in body_builder.gd):
//   UV.y  nozzle (0) -> tail (1)
//   UV.x  wraps around the plume; UV.x = 0.5 is the on-axis "center", 0/1 the
//         silhouette seam. The across term folds this into a smooth radial
//         profile so core -> sheath -> halo stack outward.
//
// It always moves: a multi-frequency flicker plus a travelling shock-diamond /
// turbulence wave are driven by TIME, so even an idle burn visibly boils.
// `boost` (0 = idle burn, 1 = boost jet) keeps the SAME colour palette and only
// lengthens, brightens and speeds the plume, so idle and boost never disagree.
// =============================================================================

uniform vec4 color : source_color = vec4(0.08, 0.28, 1.0, 1.0);    // outer halo
uniform vec4 rim_color : source_color = vec4(0.20, 0.55, 1.0, 1.0); // middle sheath
uniform vec4 hot_color : source_color = vec4(0.68, 0.88, 1.0, 1.0); // inner core
uniform float energy = 0.95;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float flicker_speed = 17.0;
uniform float seed = 0.0;
uniform float length_power : hint_range(0.3, 4.0) = 1.7;
uniform float boost : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// across: 0 at the silhouette seam, 1 up the plume axis.
	// along:  1 at the nozzle, 0 at the tail tip.
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float rr = clamp(across, 0.0, 1.0);
	float along = clamp(1.0 - UV.y, 0.0, 1.0);

	float t = TIME;

	// --- multi-frequency flicker (always active, even at idle) --------------
	// Four detuned sines + seed offsets give a broad, organically ragged flicker
	// that never fully extinguishes the burn (baseline 0.76 keeps it alive).
	float fl = 0.76
		+ 0.14 * sin(t * flicker_speed * 1.00 + seed * 41.0)
		+ 0.09 * sin(t * flicker_speed * 1.73 + seed * 13.0 + 1.7)
		+ 0.06 * sin(t * flicker_speed * 0.49 + seed * 29.0 + 4.2)
		+ 0.035 * sin(t * flicker_speed * 3.10 + seed * 7.0);

	// --- travelling shock diamonds / turbulence -----------------------------
	// Phase runs along the plume and advances with TIME, so the bands and
	// kinks visibly stream tailward. Boost accelerates and deepens them.
	float dspeed = (2.0 + flicker_speed * 0.10) * (1.0 + 1.6 * boost);
	float shock = sin(UV.y * 19.0 - t * dspeed + seed * 5.0)
		+ 0.60 * sin(UV.y * 41.0 + t * dspeed * 1.30 + seed * 11.0)
		+ 0.35 * sin(UV.y * 73.0 - t * dspeed * 2.10 + seed * 17.0);
	float turb = 0.5 + 0.5 * shock * 0.30; // ~0.35..0.65 intensity modulation
	// Width wobble: the plume edges undulate as turbulence streams past.
	float pinch = 1.0 + 0.09 * sin(UV.y * 13.0 + t * dspeed * 0.9 + seed * 23.0);
	rr = clamp(rr * pinch, 0.0, 1.0);

	// --- boost: lengthen (stretch the along profile toward the tail) and
	//     brighten, without touching the colour ramp --------------------------
	float ay = clamp(along * mix(1.0, 0.72, boost), 0.0, 1.0);
	float bright = 0.85 + 0.55 * boost + 0.20 * boost * fl;

	// --- layer masks --------------------------------------------------------
	// inner core: narrow, on-axis, stalls before mid-tail (hottest at nozzle)
	float core_x = smoothstep(0.80, 0.98, rr);
	float core_y = smoothstep(0.42, 0.95, ay);
	float core_amt = core_x * core_y;

	// middle sheath: electric blue, mid radius, carries the turbulence
	float sheath_x = smoothstep(0.46, 0.84, rr) * (1.0 - smoothstep(0.84, 0.98, rr));
	float sheath_y = smoothstep(0.06, 1.0, ay);
	float sheath_amt = sheath_x * sheath_y;

	// outer halo: deep blue, widest, softest feather (fades soonest in radius)
	float halo_x = smoothstep(0.03, 0.62, rr) * (1.0 - smoothstep(0.62, 0.94, rr));
	float halo_y = smoothstep(0.03, 1.0, ay) * pow(clamp(ay, 0.0, 1.0), length_power * 0.9);
	float halo_amt = halo_x * halo_y;

	// --- colour assembly ----------------------------------------------------
	vec3 layer = hot_color.rgb * core_amt
		+ rim_color.rgb * sheath_amt * turb
		+ color.rgb * halo_amt;

	// Smoothly kill the very tip so the additive plume dies to deep blue then
	// transparent instead of ending in a hard point.
	float tail_fade = pow(smoothstep(0.0, 0.18, along), mix(length_power * 0.45, 0.5, boost));

	// blend_add uses src_alpha, so ALPHA = 1 keeps the full HDR colour we
	// already shaped into ALBEDO.
	ALBEDO = layer * fl * bright * tail_fade * energy * intensity;
	ALPHA = 1.0;
}
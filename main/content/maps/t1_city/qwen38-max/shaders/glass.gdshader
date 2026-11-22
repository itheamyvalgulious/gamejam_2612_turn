shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// Curtain-wall glass v2: layered mullions, grime streaks, fake neon city
// reflection by view direction, per-floor office glow, sees interiors behind.
// UV = (meters along, world height). UV2 = (seed, floor_h). COLOR.a = style code.

uniform vec4 haze_col : source_color = vec4(0.085, 0.055, 0.15, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.6;
varying float vdist;
varying float vhy;
varying vec4 vmeta;
varying vec3 vtint;
varying float vdot;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = p * 2.11 + 5.3; a *= 0.5; }
	return v;
}

void vertex() {
	vmeta = vec4(UV2.x, UV2.y, 0.0, COLOR.a * 255.0);
	vtint = COLOR.rgb;
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n_view = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vdot = dot(n_view, normalize(-view_pos));
}

void fragment() {
	float sd = floor(vmeta.x + 0.5);
	float fh = max(vmeta.y, 2.6);
	float gh = vmeta.w - floor(vmeta.w / 16.0) * 16.0;
	float bay = 3.4;
	vec2 g = vec2(UV.x / bay, max(UV.y - gh, 0.0) / fh);
	vec2 id = floor(g);
	vec2 f = fract(g);

	// mullion grid: cap profile with bevel shading
	float mx = min(f.x, 1.0 - f.x);
	float my = min(f.y, 1.0 - f.y);
	float mull = smoothstep(0.045, 0.020, mx) + smoothstep(0.050, 0.022, my);
	mull = clamp(mull, 0.0, 1.0);
	float bevel = smoothstep(0.020, 0.045, mx) * (1.0 - smoothstep(0.045, 0.075, mx))
			+ smoothstep(0.022, 0.050, my) * (1.0 - smoothstep(0.050, 0.080, my));

	// grime: vertical streaks from mullions + bottom dust
	float grime = 0.35 * smoothstep(0.55, 0.95, fbm(vec2(UV.x * 0.8, UV.y * 0.25) + sd))
			+ 0.45 * smoothstep(0.7, 0.95, hash21(vec2(id.x, sd))) * (1.0 - smoothstep(0.0, 0.5, f.y));
	grime = clamp(grime, 0.0, 0.8);

	// lit floors: office glow bands with fixture rows
	float litf = step(0.45, hash21(vec2(id.y, sd * 3.7)));
	vec3 litcol = mix(vec3(1.0, 0.72, 0.42), vec3(0.6, 0.82, 1.0), step(0.7, hash21(vec2(id.y * 3.1, sd))));
	float band = smoothstep(0.10, 0.22, f.y) * (1.0 - smoothstep(0.82, 0.95, f.y));
	float fixtures = 0.75 + 0.25 * step(0.5, fract(f.x * 3.0 + hash21(id) * 3.0));
	vec3 emis = litf * band * litcol * (0.9 + 1.0 * hash21(id + sd)) * fixtures * (1.0 - mull);

	// fake reflection: fresnel-weighted sky + neon city streaks by view azimuth
	float fr = pow(1.0 - clamp(vdot, 0.0, 1.0), 3.0);
	float az = atan(VIEW.x, -VIEW.z);
	vec3 refl = mix(vec3(0.04, 0.05, 0.10), vec3(0.20, 0.24, 0.38), fr);
	float colid = floor(az * 9.0 + UV.y * 0.05);
	vec3 ncol = mix(vec3(1.0, 0.25, 0.55), vec3(0.2, 0.9, 1.0), step(0.5, hash21(vec2(colid, 1.0))));
	ncol = mix(ncol, vec3(1.0, 0.7, 0.2), step(0.8, hash21(vec2(colid, 4.0))));
	float streak = smoothstep(0.55, 0.95, hash21(vec2(colid, floor(UV.y * 0.15))))
			* (0.5 + 0.5 * sin(UV.y * 1.3 + hash21(vec2(colid, 2.0)) * 9.0));
	refl += ncol * streak * fr * 0.55;
	refl *= 1.0 - grime * 0.6;

	// edge tint at grazing (blue-green thickness)
	refl += vec3(0.05, 0.12, 0.10) * pow(1.0 - clamp(vdot, 0.0, 1.0), 5.0);

	ALBEDO = mix(vtint * 0.10 + refl * 0.55, vec3(0.02), mull);
	ALBEDO = mix(ALBEDO, ALBEDO * 1.6, bevel * 0.5);
	METALLIC = mix(0.0, 0.85, mull);
	ROUGHNESS = mix(0.05 + grime * 0.30, 0.38, mull);
	SPECULAR = 0.7;
	EMISSION = emis + refl * 0.12;
	ALPHA = mix(0.34 + grime * 0.25, 0.95, mull);

	// aerial perspective + height fog
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * haze_den * hfac - vdist * vdist * 3.5e-8);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
	ALPHA = mix(ALPHA, 1.0, hz);
}

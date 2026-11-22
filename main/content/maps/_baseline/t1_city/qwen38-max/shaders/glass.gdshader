shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform vec4 haze_col : source_color = vec4(0.055, 0.04, 0.105, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.5;
varying float vdist;
// Curtain-wall glass: translucent, shows procedural interiors behind.
// CUSTOM0 same contract as facade.gdshader.

varying vec4 vmeta;
varying vec3 vtint;
varying float vdot;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vmeta = vec4(UV2.x, UV2.y, 0.0, COLOR.a * 255.0);
	vtint = COLOR.rgb;
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

	// mullion grid
	float mull = smoothstep(0.045, 0.02, min(f.x, 1.0 - f.x)) +
			smoothstep(0.05, 0.02, min(f.y, 1.0 - f.y));
	mull = clamp(mull, 0.0, 1.0);

	// lit floors: warm office glow bands
	float litf = step(0.45, hash21(vec2(id.y, sd * 3.7)));
	vec3 litcol = mix(vec3(1.0, 0.72, 0.42), vec3(0.6, 0.82, 1.0), step(0.7, hash21(vec2(id.y * 3.1, sd))));
	float band = smoothstep(0.1, 0.2, f.y) * (1.0 - smoothstep(0.85, 0.95, f.y));
	vec3 emis = litf * band * litcol * (1.0 + 1.1 * hash21(id + sd));

	// reflection sheen
	float fres = pow(1.0 - clamp(vdot, 0.0, 1.0), 3.0);
	vec3 refl = mix(vec3(0.05, 0.07, 0.12), vec3(0.25, 0.3, 0.45), fres) +
			vec3(0.4, 0.15, 0.5) * fres * 0.35 * (0.5 + 0.5 * sin(UV.x * 0.05 + sd));

	ALBEDO = mix(vtint * 0.10 + refl * 0.5, vec3(0.02), mull);
	METALLIC = 0.85;
	ROUGHNESS = mix(0.06, 0.4, mull);
	EMISSION = emis * (1.0 - mull) + refl * 0.15;
	ALPHA = mix(0.34, 0.95, mull);
	// aerial perspective haze (Environment fog replacement)
	float hz = 1.0 - exp(-vdist * haze_den);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis, hz);
}


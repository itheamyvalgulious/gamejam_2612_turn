shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Falling water curtain.
//   mode 0 : the main sheet - a folded surface with real silhouette
//   mode 1 : the dark back wall - the mass of the fall seen through its gaps
//   mode 2 : the ropes - narrow extruded tubes that keep hard edges
// Colour is driven by the baked sheet structure (R mass, G filaments, B foam),
// and the vertical scroll is measured in metres so the near base really moves.

uniform sampler2D sheet_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D sheet_normal : filter_linear_mipmap, repeat_enable;
uniform float tile_x = 34.0;
uniform float tile_y = 34.0;
uniform float flow_speed = 44.0;
uniform float alpha_gain = 1.0;
uniform float aeration = 1.0;
uniform float mode = 0.0;
uniform float bump = 0.85;
uniform vec3 tint : source_color = vec3(1.0);
uniform float emission_gain = 0.018;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;
varying float fall_s;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	fall_s = UV.y;
	vcol = COLOR;
	// slow lateral breathing of the whole curtain; grows downward
	float w = clamp(UV.y / 200.0, 0.0, 1.0);
	VERTEX.x += sin(UV.y * 0.21 + TIME * 0.9 + COLOR.g * 11.0) * 0.16 * w;
	VERTEX.z += cos(UV.y * 0.17 + TIME * 0.7 + COLOR.g * 8.0) * 0.30 * w;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// --- scroll in metres; the water accelerates down the face
	float sp = mix(flow_speed * 0.55, flow_speed, smoothstep(0.0, 170.0, fall_s));
	float s = fall_s - TIME * sp;
	// stretch the pattern with speed: the same water is smeared into streaks
	float stretch = mix(1.0, 0.55, smoothstep(60.0, 210.0, fall_s));
	vec2 uv1 = vec2(UV.x / tile_x, s / (tile_y * stretch));
	vec2 uv2 = vec2(UV.x / (tile_x * 0.43) + 0.37, s / (tile_y * stretch * 0.61) + 0.11);

	vec3 t1 = texture(sheet_tex, uv1).rgb;
	vec3 t2 = texture(sheet_tex, uv2).rgb;
	// three vertically offset samples = motion smear inside the frame
	vec3 t1b = texture(sheet_tex, uv1 + vec2(0.0, 0.06)).rgb;

	float mass = max(t1.r, 0.65 * t1b.r + 0.35 * t1.r);
	float fil = max(t1.g, t1b.g * 0.75);
	float foam = max(t1.b, t1b.b * 0.6);
	float mass2 = t2.r;
	float fil2 = t2.g;

	float big = fbm3(vec2(wpos.x * 0.055, wpos.y * 0.045 + TIME * 0.35));
	float large = fbm3(vec2(wpos.x * 0.018, wpos.y * 0.012));
	float dense = mass * 0.92 + fil * 0.18 + mass2 * 0.16 + large * 0.14;
	dense = clamp(dense, 0.0, 1.4);

	// hard-edged break-up: the real holes are where both scales thin out
	float hole = smoothstep(0.26, 0.50, dense + (big - 0.5) * 0.22);
	float edge = vcol.a;

	vec3 deep = vec3(0.045, 0.062, 0.075);
	vec3 mid = vec3(0.185, 0.225, 0.245);
	vec3 aer = vec3(0.50, 0.545, 0.565);
	vec3 col = mix(deep, mid, smoothstep(0.10, 0.55, dense));
	col = mix(col, aer, smoothstep(0.48, 0.95, fil * 0.50 + foam * 0.70 + mass * 0.35 + large * 0.20));
	col *= tint;
	// strand-to-strand tone: sunlit faces vs. shaded ones
	col *= mix(0.62, 1.08, clamp(vcol.r, 0.0, 1.0));
	// interior of the fall is darker and colder
	col = mix(col, vec3(0.030, 0.045, 0.055) * (0.7 + 0.5 * large), 1.0 - smoothstep(0.22, 0.95, dense));

	float alpha = dense * alpha_gain * edge;
	alpha *= hole;
	alpha = clamp(alpha, 0.0, 1.0);

	vec3 nm = wnrm;
	if (mode > 1.5) {
		// ---- strands: the mesh already carries the silhouette, the gaps and
		// the dissolve; the texture only adds internal brightness.
		float g = fbm3(vec2(UV.x * 2.6, s * 0.055));
		float gg = fbm3(vec2(UV.x * 7.0 + 3.0, s * 0.015));
		col = mix(vec3(0.16, 0.20, 0.22), vec3(0.55, 0.60, 0.62), 0.35 + 0.65 * g);
		col = mix(col, vec3(0.66, 0.71, 0.73), smoothstep(0.55, 0.95, gg) * 0.6);
		col *= 0.82 + 0.34 * vcol.r;
		alpha = clamp(vcol.a * (0.34 + 0.50 * g) * alpha_gain, 0.0, 1.0);
		nm = normalize(wnrm + vec3((g - 0.5) * 0.35, 0.0, 0.0));
		ROUGHNESS = 0.45;
		SPECULAR = 0.12;
	} else if (mode > 0.5) {
		// ---- back wall: the shaded interior of the fall
		col = mix(vec3(0.055, 0.080, 0.095), vec3(0.20, 0.26, 0.29), smoothstep(0.2, 0.85, mass + large * 0.4));
		alpha = clamp(0.80 + 0.25 * smoothstep(0.15, 0.75, mass + large * 0.5), 0.0, 1.0) * alpha_gain;
		ROUGHNESS = 0.75;
		SPECULAR = 0.05;
	} else {
		// ---- the sheet: coherent film at the lip, torn lower down
		vec3 tn = texture(sheet_normal, uv1 * vec2(1.7, 1.0) + vec2(0.0, TIME * 0.05)).xyz * 2.0 - 1.0;
		nm = normalize(wnrm + vec3(tn.x, tn.y * 0.6, 0.0) * bump);
		ROUGHNESS = mix(0.62, 0.34, clamp(fil * 0.8 + foam * 0.5, 0.0, 1.0));
		SPECULAR = 0.18;
	}

	ALBEDO = col;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(nm, 0.0)).xyz);
	EMISSION = vec3(0.42, 0.47, 0.49) * smoothstep(0.60, 0.98, fil * 0.5 + foam * 0.5) * emission_gain * tint;
	ALPHA = alpha;
}
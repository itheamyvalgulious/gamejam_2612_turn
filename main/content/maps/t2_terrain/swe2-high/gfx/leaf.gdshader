shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Shared foliage material for trunks + canopies + needles + bushes.
// Vertex colour convention (packed in ARRAY_COLOR):
//   COLOR.r = 0 bark/trunk, 1 foliage/needle
//   COLOR.g = per-vertex jitter (unused for now, kept for tint variety)
//   COLOR.b = vertical tip factor (0 base -> 1 top)

uniform vec3 bark_color : source_color = vec3(0.30, 0.20, 0.12);
uniform vec3 leaf_hi : source_color = vec3(0.12, 0.30, 0.11);
uniform vec3 leaf_lo : source_color = vec3(0.06, 0.17, 0.06);
uniform vec3 leaf_dark : source_color = vec3(0.03, 0.09, 0.03);
uniform vec3 snow_color : source_color = vec3(0.90, 0.93, 0.97);
uniform vec3 tip_glow : source_color = vec3(0.32, 0.40, 0.14);
uniform float snow_line = 120.0;
uniform float snow_soft = 35.0;
uniform float wind_strength = 0.28;
uniform float wind_speed = 1.1;

varying vec3 v_world;
varying float v_mask;
varying float v_tip;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_mask = COLOR.r;
	v_tip = COLOR.b;

	float sway = mix(0.05, 1.0, v_mask);
	float height = 0.15 + 0.85 * v_tip;
	float t = TIME * wind_speed;
	vec2 wp = v_world.xz;
	float n = sin(t + wp.x * 0.05 + wp.y * 0.04)
			+ 0.5 * sin(t * 1.7 + wp.y * 0.09 + wp.x * 0.07)
			+ 0.25 * sin(t * 2.9 + wp.x * 0.11 - wp.y * 0.06);
	VERTEX.x += n * 0.55 * sway * height * wind_strength;
	VERTEX.z += (cos(t * 0.9 + wp.y * 0.05) + 0.4 * cos(t * 1.4 + wp.x * 0.06))
			* 0.55 * sway * height * wind_strength;
}

void fragment() {
	float leaf = v_mask;
	vec3 bark = bark_color * (0.85 + 0.3 * fbm(v_world.xz * 0.25));
	// vertical banding + patchy canopy mottle — real crowns are lumpy,
	// not one flat green
	float vband = clamp(v_tip * 1.15, 0.0, 1.0);
	float mott = fbm(v_world.xz * 0.18 + vec2(3.1, 7.7));
	vec3 fol = mix(leaf_dark, mix(leaf_lo, leaf_hi, mott), vband);
	// clump-level patches: darker pockets inside the crown
	float clump = fbm(v_world.xz * 0.6 + vec2(v_world.y * 0.31, v_world.y * 0.17));
	fol = mix(fol, fol * vec3(0.55, 0.7, 0.5), smoothstep(0.62, 0.85, clump));
	// stand-level tint drift: hashed 40 m cells give clumps of slightly
	// different hue so a forest never reads as one repeated tree
	float stand = hash21(floor(v_world.xz / 40.0));
	fol *= vec3(0.88 + stand * 0.24, 0.92 + stand * 0.16,
		0.85 + (1.0 - stand) * 0.28);
	vec3 alb = mix(bark, fol, leaf);

	float snow = smoothstep(snow_line - snow_soft, snow_line + snow_soft, v_world.y);
	snow = max(snow, smoothstep(-360.0, -560.0, v_world.z) * 0.85);
	snow = clamp(snow, 0.0, 1.0);
	snow *= 0.55 + 0.45 * v_tip;
	alb = mix(alb, snow_color, snow);

	ALBEDO = alb;
	ROUGHNESS = 0.9;
	// canopy translucency: sky light filters through the crown so the
	// underside isn't a black void
	EMISSION = fol * leaf * 0.18 + tip_glow * v_tip * leaf * 0.06;
	// sky-side ambient keeps shadowed crowns readable
	BACKLIGHT = vec3(0.25, 0.35, 0.28);
}

shader_type spatial;
render_mode specular_schlick_ggx;

// Structural framework: dark gunmetal beams with edge wear, bolt lines and
// optional rust/oil streaks. Used for ribs, stringers, girders, catwalk frames.

uniform vec3 u_base = vec3(0.125, 0.13, 0.145);
uniform float u_rust = 0.25;
uniform vec3 u_rust_col = vec3(0.32, 0.19, 0.1);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.27);
	return fract(p.x * p.y * 95.43);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec3 bn = abs(n);
	vec3 w = pow(bn, vec3(5.0));
	w /= (w.x + w.y + w.z);
	vec2 uvd = (w.x > w.y && w.x > w.z) ? wpos.zy : ((w.y > w.z) ? wpos.xz : wpos.xy);

	// flange bolt line every 1.25m along beam length approximations
	float boltline = 0.0;
	vec2 gb = uvd / 1.25;
	vec2 fb = fract(gb);
	float db = min(min(fb.x, 1.0 - fb.x), min(fb.y, 1.0 - fb.y));
	float seamline = 1.0 - smoothstep(0.0, 0.015, db);
	boltline = (1.0 - smoothstep(0.03, 0.055, abs(fract(uvd.x * 4.0) - 0.5))) * seamline;

	float grain = vnoise(vec2(uvd.x * 5.0, uvd.y * 320.0)) * 0.4;
	float rust = smoothstep(0.55, 0.85, fbm(uvd * 0.9 + 19.0)) * u_rust;
	float oil = smoothstep(0.68, 0.95, fbm(vec2(uvd.x * 2.0, uvd.y * 0.5) + 40.0)) * u_rust * 0.8;
	// edge wear: brighter where triplanar weights mix (corners)
	float edgemix = 1.0 - max(max(w.x, w.y), w.z);
	float wear = smoothstep(0.12, 0.4, edgemix) * 0.5 + grain * 0.15;

	vec3 alb = u_base * COLOR.rgb;
	alb *= (0.85 + 0.3 * grain);
	alb = mix(alb, vec3(0.4, 0.41, 0.43), wear * 0.55);
	alb = mix(alb, u_rust_col, rust * 0.55);
	alb = mix(alb, vec3(0.035, 0.03, 0.024), oil * 0.8);
	alb *= (1.0 - seamline * 0.25);

	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(0.5 + rust * 0.3 + oil * 0.15 - wear * 0.15 + grain * 0.08, 0.1, 0.95);
	METALLIC = 0.45 * (1.0 - rust * 0.5);
	SPECULAR = 0.5;
}

shader_type spatial;
render_mode cull_disabled;
// Neon sign v2: rusted backing panel, tube core + halo, dead tube segments,
// glyph strokes as bent tubes, glass cover sheen, flicker.
// UV = 0..1 over quad, UV2 = (seed, kind)  kind: 0 vertical blade, 1 rooftop.
uniform vec4 haze_col : source_color = vec4(0.085, 0.055, 0.15, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.6;
varying vec2 vmeta;
varying float vdist;
varying float vhy;
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

float glyph(vec2 p, float hs) {
	float d = 1.0;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float hk = hash21(vec2(hs * 7.13 + fk * 13.7, hs * 3.31 - fk * 5.1));
		float ang = floor(hash21(vec2(hk * 31.7, fk * 3.3)) * 4.0);
		vec2 a = vec2(0.18 + 0.44 * hash21(vec2(hk * 17.3, fk * 3.1)),
				0.18 + 0.44 * hash21(vec2(hk * 23.9, fk * 5.7)));
		vec2 dv = ang < 0.5 ? vec2(1, 0) : ang < 1.5 ? vec2(0, 1) :
				ang < 2.5 ? vec2(0.707, 0.707) : vec2(0.707, -0.707);
		float len = 0.28 + 0.5 * hash21(vec2(hk * 41.1, fk * 7.7));
		vec2 pa = p - a;
		float t = clamp(dot(pa, dv), 0.0, len);
		d = min(d, length(pa - dv * t));
	}
	return d;
}

void vertex() {
	vmeta = UV2;
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n_view = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vdot = dot(n_view, normalize(-view_pos));
}

void fragment() {
	float sd = floor(vmeta.x + 0.5);
	float kind = vmeta.y;
	vec2 p = UV;
	float cp = hash21(vec2(sd, 3.7));
	vec3 col = cp < 0.3 ? vec3(1.0, 0.2, 0.5) : cp < 0.55 ? vec3(0.2, 0.95, 1.0) :
			cp < 0.75 ? vec3(1.0, 0.65, 0.15) : cp < 0.9 ? vec3(0.45, 1.0, 0.35) : vec3(0.7, 0.3, 1.0);

	// rusted backing panel
	vec3 back = vec3(0.045, 0.040, 0.038) * (0.6 + 0.8 * vnoise(p * 14.0 + sd));
	back = mix(back, vec3(0.12, 0.05, 0.03), smoothstep(0.6, 0.9, vnoise(p * 6.0 + sd * 2.0)) * 0.7);
	float back_rough = 0.75;

	// glyph tubes
	vec2 gp = kind < 0.5 ? vec2(p.x, p.y * 5.0) : vec2(p.x * 6.0, p.y);
	vec2 gid = floor(gp);
	vec2 gf = fract(gp);
	float gd = glyph(gf, hash21(gid + sd * 11.3) * 61.0);
	float tube_d = gd;
	// border tube distance
	vec2 bd = abs(p - 0.5) * 2.0;
	float bdist = max(bd.x, bd.y);
	float border_d = abs(bdist - 0.90) * 4.0;
	tube_d = min(tube_d, border_d);

	// dead segments along tube path
	float seg = floor((kind < 0.5 ? p.y : p.x) * 14.0);
	float dead = step(0.93, hash21(vec2(seg, sd * 1.3)));
	float flick = 0.8 + 0.2 * step(0.94, hash21(vec2(sd, floor(TIME * 7.0))));
	float whole_dead = step(0.97, hash21(vec2(sd, 9.1)));
	flick *= 1.0 - whole_dead * 0.9;

	// tube core + halo
	float core = 1.0 - smoothstep(0.05, 0.10, tube_d);
	float halo = exp(-max(tube_d, 0.0) * 5.5) * 0.55;
	float on = (1.0 - dead) * flick;
	vec3 emis = col * (core * 3.2 * on + halo * on + core * 0.15 + 0.05);
	// unlit tube glass still visible
	vec3 alb = mix(back, vec3(0.10, 0.09, 0.09), core * 0.7);
	float rough = mix(back_rough, 0.25, core);
	// glass cover sheen
	float sheen = pow(1.0 - clamp(abs(vdot), 0.0, 1.0), 4.0);
	emis += vec3(0.35, 0.4, 0.5) * sheen * 0.10;

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = 0.3;
	EMISSION = emis;

	// aerial perspective + height fog
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * haze_den * hfac - vdist * vdist * 3.5e-8);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
}

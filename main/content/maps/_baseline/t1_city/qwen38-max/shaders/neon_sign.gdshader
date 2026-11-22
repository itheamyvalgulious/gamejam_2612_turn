shader_type spatial;
render_mode cull_disabled;
// Neon sign panel: procedural glyph column / row + border tube + flicker.
// UV = 0..1 over quad, UV2 = (seed, kind)  kind: 0 vertical blade, 1 rooftop.
varying vec2 vmeta;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
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
}

void fragment() {
	float sd = floor(vmeta.x + 0.5);
	float kind = vmeta.y;
	vec2 p = UV;
	// sign color palette
	float cp = hash21(vec2(sd, 3.7));
	vec3 col = cp < 0.3 ? vec3(1.0, 0.2, 0.5) : cp < 0.55 ? vec3(0.2, 0.95, 1.0) :
			cp < 0.75 ? vec3(1.0, 0.65, 0.15) : cp < 0.9 ? vec3(0.45, 1.0, 0.35) : vec3(0.7, 0.3, 1.0);
	// glyph grid: vertical blade = column of glyphs; rooftop = row
	vec2 gp = kind < 0.5 ? vec2(p.x, p.y * 5.0) : vec2(p.x * 6.0, p.y);
	vec2 gid = floor(gp);
	vec2 gf = fract(gp);
	float gd = glyph(gf, hash21(gid + sd * 11.3) * 61.0);
	float gm = 1.0 - smoothstep(0.07, 0.13, gd);
	// border tube
	vec2 bd = abs(p - 0.5) * 2.0;
	float tube = smoothstep(0.82, 0.9, max(bd.x, bd.y)) * (1.0 - smoothstep(0.96, 1.0, max(bd.x, bd.y)));
	// flicker
	float fl = 0.8 + 0.2 * step(0.94, hash21(vec2(sd, floor(TIME * 7.0))));
	float dead = step(0.97, hash21(vec2(sd, 9.1)));
	fl *= 1.0 - dead * 0.85;
	vec3 emis = col * (gm * 2.4 + tube * 2.0 + 0.12) * fl;
	ALBEDO = vec3(0.015);
	ROUGHNESS = 0.4;
	EMISSION = emis;
}

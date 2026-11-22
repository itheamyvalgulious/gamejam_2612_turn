shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform int u_mode : hint_range(0, 2) = 0;   // 0 = leafy canopy (noise holes), 1 = grass blade, 2 = solid
uniform vec3 u_col_a : source_color = vec3(0.1, 0.3, 0.08);
uniform vec3 u_col_b : source_color = vec3(0.2, 0.45, 0.12);
uniform float u_hole_scale : hint_range(0.01, 4.0) = 0.6;
uniform float u_threshold : hint_range(0.0, 1.0) = 0.42;
uniform float u_sway : hint_range(0.0, 1.0) = 0.15;
uniform float u_snowtint : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;
varying vec3 v_nworld;
varying vec2 v_uv;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1,0,0)), f.x),
			mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x),
			mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p, int oct) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= oct) break;
		s += a * vnoise(p);
		p = p * 2.03 + vec3(3.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// gentle wind sway, stronger at top of the instance
	float sway = u_sway * sin(TIME * 1.3 + w.x * 0.05 + w.z * 0.04);
	VERTEX.x += sway * clamp(VERTEX.y * 0.15, 0.0, 1.0);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nworld = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_uv = UV;
}

void fragment() {
	float a = 1.0;
	float n1 = fbm(v_world * 0.25, 3);
	vec3 col = mix(u_col_a, u_col_b, n1);
	if (u_mode == 0) {
		float n = fbm(v_world * u_hole_scale, 3);
		a = step(u_threshold, n);
		col *= 0.75 + 0.5 * fbm(v_world * 1.7, 2);
	} else if (u_mode == 1) {
		float w = (1.0 - v_uv.y) * 0.45 + 0.04;
		a = step(abs(v_uv.x - 0.5), w);
		col = mix(u_col_a, u_col_b, v_uv.y);
		col *= 0.8 + 0.4 * fbm(vec3(v_uv * 4.0, 0.0), 2);
	} else if (u_mode == 3) {
		// compound leaf sprig: stem + 3 pairs of serrated leaflets + tip leaflet
		vec2 p = v_uv;
		float mask = smoothstep(0.020, 0.006, abs(p.x - 0.5)) * step(p.y, 0.97);
		for (int k = 0; k < 3; k++) {
			float yy = 0.22 + 0.26 * float(k);
			for (int sgi = 0; sgi < 2; sgi++) {
				float sgn = float(sgi) * 2.0 - 1.0;
				vec2 d = p - vec2(0.5, yy);
				float c = cos(0.85 * sgn);
				float s = sin(0.85 * sgn);
				vec2 q = vec2(d.x * c - d.y * s, d.x * s + d.y * c);
				float L = 0.24;
				float ty = clamp(q.y / L, 0.0, 1.0);
				float w = 0.055 * sin(ty * PI) + 0.004;
				w *= 1.0 + 0.12 * sin(ty * 26.0);   // serrated edge
				mask = max(mask, step(abs(q.x), w) * step(0.0, q.y) * step(q.y, L));
			}
		}
		vec2 dt = p - vec2(0.5, 0.80);
		float Lt = 0.20;
		float tyt = clamp(dt.y / Lt, 0.0, 1.0);
		mask = max(mask, step(abs(dt.x), 0.05 * sin(tyt * PI) + 0.004) * step(0.0, dt.y) * step(dt.y, Lt));
		a = mask;
		col *= 1.0 - 0.30 * smoothstep(0.03, 0.0, abs(p.x - 0.5));  // midrib
		col *= 0.85 + 0.30 * v_uv.y;                                 // tip lighter
	} else if (u_mode == 4) {
		// fir sprig silhouette: stem + 7 pairs of thin tapered needles (no stripe lattice)
		vec2 p = v_uv;
		float mask = smoothstep(0.025, 0.008, abs(p.x - 0.5)) * step(p.y, 0.98);
		for (int k = 0; k < 10; k++) {
			float yy = 0.06 + 0.09 * float(k);
			float llen = 0.32 * (1.0 - 0.55 * yy);
			for (int sgi = 0; sgi < 2; sgi++) {
				float sgn = float(sgi) * 2.0 - 1.0;
				vec2 d = p - vec2(0.5, yy);
				float c = cos(1.15 * sgn);
				float s = sin(1.15 * sgn);
				vec2 q = vec2(d.x * c - d.y * s, d.x * s + d.y * c);
				float ty = clamp(q.y / llen, 0.0, 1.0);
				float w = 0.026 * (1.0 - ty) + 0.003;
				mask = max(mask, step(abs(q.x), w) * step(0.0, q.y) * step(q.y, llen));
			}
		}
		a = mask;
		col *= 0.8 + 0.4 * p.y;
	}
	if (a < 0.5) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// per-vertex baked AO / tint
	col *= COLOR.rgb;
	// snow accumulation on upward-facing foliage
	if (u_snowtint > 0.0) {
		float upf = clamp(v_nworld.y, 0.0, 1.0);
		float sn = u_snowtint * smoothstep(0.55, 0.90, upf) * (0.4 + 0.6 * fbm(v_world * 0.8, 2));
		col = mix(col, vec3(0.92, 0.95, 0.99), clamp(sn, 0.0, 1.0));
	}
	// warm ground-bounce on undersides relieves blue-shadow dullness
	col += col * vec3(0.55, 0.42, 0.28) * (1.0 - clamp(v_nworld.y, 0.0, 1.0)) * 0.35;
	// backlit leaf translucency: canopy glowing instead of black shards
	vec3 camW = (INV_VIEW_MATRIX * vec4(0, 0, 0, 1)).xyz;
	vec3 Vv = normalize(camW - v_world);
	vec3 Ls = normalize(vec3(-0.696, 0.530, 0.370));
	float bl = pow(clamp(dot(Vv, -Ls) * 0.5 + 0.5, 0.0, 1.0), 3.0);
	col += col * vec3(1.5, 1.15, 0.7) * bl * 0.9;
	ALBEDO = col;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	// cheap translucency: brighten when facing away from view toward light
	ALBEDO += col * 0.15;
}

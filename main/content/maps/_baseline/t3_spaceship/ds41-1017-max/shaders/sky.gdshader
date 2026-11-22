// ============================================================================
//  sky.gdshader — deep-space background: star fields, nebula, ringed planet
//  Every element is analytic (hash star cells, fbm nebulae, ray-sphere planet).
// ============================================================================
shader_type sky;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 nebula_a : source_color = vec3(0.10, 0.035, 0.16);
uniform vec3 nebula_b : source_color = vec3(0.02, 0.11, 0.14);
uniform vec3 nebula_c : source_color = vec3(0.30, 0.10, 0.05);
uniform vec3 galaxy_normal = vec3(0.35, 0.82, -0.45);
uniform vec3 planet_dir = vec3(-0.30, 0.17, -0.94);
uniform float planet_radius : hint_range(1.0, 40.0) = 13.0;
uniform float planet_dist : hint_range(20.0, 400.0) = 100.0;
uniform float ring_enabled : hint_range(0.0, 1.0) = 1.0;
uniform vec3 ring_normal = vec3(0.18, 1.0, 0.24);
uniform vec3 sun_dir = vec3(0.50, 0.55, 0.67);
uniform float star_energy : hint_range(0.0, 6.0) = 1.4;

vec3 star_layer(vec3 d, float density, float thresh, float size, float bright) {
	vec3 p = d * density;
	vec3 cell = floor(p);
	vec3 f = fract(p);
	vec3 seed3 = m_hash33(cell);
	if (m_hash31(cell + 19.7) < thresh) {
		return vec3(0.0);
	}
	vec3 star_pos = 0.5 + (seed3 - 0.5) * 0.26;
	float dist = length(f - star_pos);
	float core = exp(-dist * dist / (size * size));
	float halo = exp(-dist * dist / (size * size * 9.0)) * 0.16;
	vec3 tint = mix(vec3(0.65, 0.78, 1.0), vec3(1.0, 0.82, 0.62), seed3.z);
	float twinkle = 0.75 + 0.25 * sin(TIME * (2.0 + seed3.x * 5.0) + seed3.y * 40.0);
	return (core + halo) * bright * twinkle * tint;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = vec3(0.0035, 0.005, 0.010);

	// ---------- galactic band ----------
	float band = exp(-pow(dot(d, normalize(galaxy_normal)) * 2.6, 2.0));
	float n1 = m_fbm3(d * 4.0 + 3.0, 5);
	float n2 = m_fbm3(d * 11.0 - 7.0, 4);
	float dust = m_fbm3(d * 22.0 + n1 * 2.0, 3);
	col += nebula_a * band * (n1 * 0.9 + 0.12) * 0.55;
	col += nebula_b * pow(n1, 2.0) * band * 0.7;
	col += nebula_c * pow(m_sat(n2 * 1.4 - 0.25), 3.0) * band * 0.45;
	col *= mix(1.0, 0.55, m_sat(dust * 1.8 - 0.55));

	// ---------- stars ----------
	vec3 st = vec3(0.0);
	st += star_layer(d, 55.0, 0.968, 0.085, 2.2);
	st += star_layer(d, 120.0, 0.930, 0.075, 1.0);
	st += star_layer(d, 220.0, 0.870, 0.070, 0.42);
	// thin galactic star dust
	st += vec3(m_sat(m_noise3(d * 900.0) - 0.72)) * 0.35 * band;
	col += st * star_energy;

	// ---------- planet ----------
	vec3 pc = normalize(planet_dir) * planet_dist;
	float R = planet_radius;
	vec3 oc = -pc;
	float b = dot(oc, d);
	float c2 = dot(oc, oc) - R * R;
	float disc = b * b - c2;

	vec3 sun = normalize(sun_dir);
	float t_sph = 1e20;
	bool hit = false;
	vec3 pn = vec3(0.0);
	if (disc > 0.0) {
		float t = -b - sqrt(disc);
		if (t > 0.0) {
			hit = true;
			t_sph = t;
			pn = normalize(d * t - pc);
		}
	}

	// rings (intersect the planet's equatorial plane)
	float t_ring = 1e20;
	float ring_alpha = 0.0;
	vec3 ring_col = vec3(0.0);
	if (ring_enabled > 0.5) {
		vec3 rn = normalize(ring_normal);
		float denom = dot(d, rn);
		if (abs(denom) > 0.0005) {
			float t = dot(pc, rn) / denom;
			if (t > 0.0) {
				vec3 rp = d * t - pc;
				float r = length(rp);
				float inner = R * 1.42;
				float outer = R * 2.30;
				if (r > inner && r < outer) {
					float bandv = fract((r - inner) / (outer - inner) * 7.0 + 0.15);
					float gap = smoothstep(0.0, 0.04, abs(bandv - 0.5) - 0.18);
					float fine = m_fbm2(vec2((r - inner) * 0.55, 0.0), 4);
					ring_alpha = (0.28 + fine * 0.55) * gap;
					ring_col = mix(vec3(0.58, 0.50, 0.39), vec3(0.82, 0.76, 0.62), fine);
					ring_alpha *= smoothstep(inner, inner + 1.2, r) * smoothstep(outer, outer - 1.5, r);
					t_ring = t;
				}
			}
		}
	}

	// composite rings behind the planet first
	vec3 ring_sky = mix(col, ring_col, ring_alpha * 0.85);
	if (t_ring < t_sph) {
		col = ring_sky;
	}

	if (hit) {
		vec3 n = normalize(pn);
		float ndl = dot(n, sun);
		float day = smoothstep(-0.12, 0.25, ndl);
		float land = step(0.52, m_fbm3(n * 2.4 + 5.0, 5));
		float ice = smoothstep(0.62, 0.80, abs(n.y) + m_noise3(n * 8.0) * 0.12);
		vec3 ocean = mix(vec3(0.008, 0.035, 0.085), vec3(0.02, 0.10, 0.16), m_fbm3(n * 4.0, 3));
		vec3 terrain = mix(vec3(0.12, 0.11, 0.07), vec3(0.20, 0.16, 0.10), m_fbm3(n * 9.0, 4));
		vec3 surf = mix(ocean, terrain, land);
		surf = mix(surf, vec3(0.72, 0.78, 0.82), ice * 0.85);
		float clouds = m_fbm3(n * 5.5 + vec3(TIME * 0.004, 0.0, 0.0), 5);
		float cloud_mask = smoothstep(0.52, 0.72, clouds);
		surf = mix(surf, vec3(0.85, 0.88, 0.92), cloud_mask * 0.80);
		// ocean glint
		vec3 h = normalize(sun - d);
		float glint = pow(max(dot(n, h), 0.0), 90.0) * (1.0 - land) * (1.0 - cloud_mask) * 2.5;
		// atmosphere
		float rim = pow(1.0 - max(dot(n, -d), 0.0), 3.5);
		vec3 lit = surf * (0.05 + day * 2.4) + vec3(glint);
		lit += vec3(0.18, 0.38, 0.62) * rim * (0.25 + day * 1.1);
		col = lit;
		// atmospheric halo outside the disc
		float ang = length(cross(d, normalize(planet_dir)));
		col += vec3(0.20, 0.44, 0.72) * exp(-max(ang - R / planet_dist, 0.0) * 45.0) * 0.55;
	}

	// sun disc + glare
	float sd = max(dot(d, sun), 0.0);
	col += vec3(1.0, 0.94, 0.82) * pow(sd, 2800.0) * 60.0;
	col += vec3(1.0, 0.72, 0.45) * pow(sd, 90.0) * 0.06;

	COLOR = col;
}
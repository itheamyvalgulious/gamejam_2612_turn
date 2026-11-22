shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Baked cliff face: the mesh carries beds, joints, blocks, chips and baked
// occlusion; these maps carry only the sub-centimetre material.

uniform sampler2D face_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D face_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D face_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D face_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D struct_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D struct_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D struct_rough : filter_linear_mipmap, repeat_enable;
uniform float tile = 2.0;
uniform float struct_tile = 6.0;
uniform float bump_amp = 0.0016;   // metres of relief in the height map
uniform float pom_depth = 0.006;   // parallax depth at close range
uniform float detail_fade_near = 6.0;
uniform float detail_fade_far = 16.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;

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
		p = p * 2.07 + vec2(5.3, 2.9);
		a *= 0.5;
	}
	return v;
}
vec3 srgb2lin(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

void fragment() {
	vec3 p = wpos;
	vec3 n = normalize(wnrm);
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - p);
	float dist = distance(p, CAMERA_POSITION_WORLD);
	vec2 uv = p.xy / tile;

	// --- keep the close range sharp: pick mip 0 explicitly inside 3 m
	float lod = dist < 3.0 ? 0.0 : 1.5;
	vec2 uv2 = p.xy / struct_tile;
	vec3 alb = srgb2lin(textureLod(face_albedo, uv, lod).rgb);
	vec3 col = alb * vcol.rgb;

	// --- broad hue drift so the 2 m tile never reads as a repeat
	float m1 = fbm3(p.xy * 0.42 + p.z * 0.1);
	float m2 = fbm3(p.xy * 1.35 + 11.0);
	col *= mix(vec3(0.90, 0.93, 1.02), vec3(1.07, 1.00, 0.90), clamp(m1 * 1.5, 0.0, 1.0));
	col *= 0.90 + 0.22 * m2;

	// --- dry dust in the hollows (baked AO already darkened them)
	float ao = clamp(vcol.r, 0.0, 1.5);
	float rough = mix(textureLod(face_rough, uv, lod).r, vcol.a, 0.45);
	rough = mix(rough, textureLod(struct_rough, uv2, 0.0).r, 0.35);

	// --- detail normal.  The face is a plane in XY with +Z out, so the
	// tangent-space map maps straight onto world axes.
	vec3 tn = textureLod(face_normal, uv, lod).xyz * 2.0 - 1.0;
	vec3 sn = textureLod(struct_normal, uv2, 0.0).xyz * 2.0 - 1.0;
	float bf = 1.0 - smoothstep(11.0, 30.0, dist);
	n = normalize(n + vec3(tn.xy * 0.9 * bf + sn.xy * 0.25, 0.0));

	// --- sheen: wet runnels and polished facets are darker and smoother
	float wet = clamp((0.55 - rough) * 2.2, 0.0, 1.0);
	col *= 1.0 - 0.10 * wet;

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.18, 0.98);
	SPECULAR = 0.24;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
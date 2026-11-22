shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Spray / mist card for the plunge.  Two scrolling octaves of the baked plume
// texture; many overlapping cards build a volume without volumetric fog.
// Per-vertex COLOR = (tint, phase, -, alpha).

uniform sampler2D mist_tex : filter_linear_mipmap, repeat_enable;
uniform float rise = 0.6;
uniform float glow = 0.12;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + vcol.g * 7.0;
	vec4 a = texture(mist_tex, uv + vec2(0.0, -t * rise * 0.010));
	vec4 b = texture(mist_tex, uv * 1.73 + vec2(0.31, -t * rise * 0.017));
	float dens = a.a * 0.62 + b.a * 0.42;
	vec2 q = UV - 0.5;
	float edge = smoothstep(0.52, 0.28, length(q * vec2(1.0, 1.12)));
	float vfade = smoothstep(0.0, 0.20, UV.y) * smoothstep(1.0, 0.62, UV.y);
	float al = clamp(dens * vcol.a * edge * vfade * 1.15, 0.0, 0.30);
	// spray picks up the sky: cooler up top, brighter where the sun hits
	vec3 tint = mix(vec3(0.80, 0.87, 0.94), vec3(0.97, 0.98, 1.0), smoothstep(0.2, 0.9, dens));
	tint *= 0.92 + 0.12 * vcol.r;
	ALBEDO = tint;
	ALPHA = al;
	EMISSION = tint * glow * al;
	ROUGHNESS = 1.0;
}
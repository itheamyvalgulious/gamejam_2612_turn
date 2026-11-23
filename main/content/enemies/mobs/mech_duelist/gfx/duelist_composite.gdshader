shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 coating : source_color = vec4(0.67, 0.69, 0.65, 1.0);
uniform float metalness = 0.38;
uniform float finish_roughness = 0.36;
varying vec3 machining_position;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float grain(vec3 p) {
	vec3 cell = floor(p);
	vec3 u = fract(p);
	u = u * u * (3.0 - 2.0 * u);
	return mix(mix(mix(hash31(cell), hash31(cell + vec3(1,0,0)), u.x),
		mix(hash31(cell + vec3(0,1,0)), hash31(cell + vec3(1,1,0)), u.x), u.y),
		mix(mix(hash31(cell + vec3(0,0,1)), hash31(cell + vec3(1,0,1)), u.x),
		mix(hash31(cell + vec3(0,1,1)), hash31(cell + vec3(1,1,1)), u.x), u.y), u.z);
}

void vertex() {
	machining_position = VERTEX;
}

void fragment() {
	vec3 grit_position = machining_position * vec3(110.0, 19.0, 110.0);
	float footprint = length(fwidth(grit_position));
	float machining_grain = (grain(grit_position) - 0.5) * (1.0 - smoothstep(0.7, 2.6, footprint));
	float coating_variation = grain(machining_position * 8.5) - 0.5;
	ALBEDO = coating.rgb * (1.0 + 0.12 * machining_grain + 0.06 * coating_variation);
	METALLIC = metalness;
	ROUGHNESS = clamp(finish_roughness + 0.11 * machining_grain + 0.13 * coating_variation, 0.08, 0.88);
	SPECULAR = 0.46;
}

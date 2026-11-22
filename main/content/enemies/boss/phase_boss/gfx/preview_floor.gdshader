shader_type spatial;
varying vec3 stage_point;

void vertex() {
	stage_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = stage_point.xz / 1.828;
	vec2 spacing = abs(fract(coord - 0.5) - 0.5) / max(fwidth(coord), vec2(0.0001));
	float stripe = 1.0 - smoothstep(0.30, 1.25, min(spacing.x, spacing.y));
	float fade = 1.0 - smoothstep(16.0, 63.0, length(stage_point.xz));
	ALBEDO = mix(vec3(0.012, 0.018, 0.026), vec3(0.036, 0.049, 0.066), stripe * fade);
	ROUGHNESS = 0.88;
}

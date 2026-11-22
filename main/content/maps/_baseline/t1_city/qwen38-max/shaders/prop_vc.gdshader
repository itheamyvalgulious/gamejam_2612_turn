shader_type spatial;
// Vertex-color prop material: COLOR.rgb = albedo tint, COLOR.a = emissive mask.
uniform float emis = 8.0;
varying float vdist;

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	ALBEDO = COLOR.rgb * (0.22 + 0.4 * (1.0 - COLOR.a));
	METALLIC = 0.6 * (1.0 - COLOR.a);
	ROUGHNESS = 0.35 + 0.3 * (1.0 - COLOR.a);
	EMISSION = COLOR.rgb * COLOR.a * emis;
	// aerial perspective haze (Environment fog replacement)
	float hz = 1.0 - exp(-vdist * 0.00032);
	ALBEDO = mix(ALBEDO, vec3(0.055, 0.04, 0.105), hz);
	EMISSION = mix(EMISSION, vec3(0.055, 0.04, 0.105) * 0.5, hz);
}

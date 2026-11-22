shader_type spatial;
uniform vec4 haze_col : source_color = vec4(0.055, 0.04, 0.105, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.5;
varying float vdist;
// Vertex-color emissive (neon trim, beacons).
uniform float energy = 4.0;

void fragment() {
	ALBEDO = COLOR.rgb * 0.12;
	ROUGHNESS = 0.4;
	EMISSION = COLOR.rgb * energy;
	// aerial perspective haze (Environment fog replacement)
	float hz = 1.0 - exp(-vdist * haze_den);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis, hz);
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}


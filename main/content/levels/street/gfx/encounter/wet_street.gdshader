shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://gfx/encounter/lib/math.gdshaderinc"
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p = world_pos.xz;
	float px = max(length(fwidth(p)),0.0001);
	float aggregate = m_noise2(p*85.0);
	float fine = (aggregate-0.5)*(1.0-smoothstep(0.008,0.04,px));
	float patch = m_fbm2(p*0.26,4);
	float water = smoothstep(0.44,0.65,patch);
	float cracks = m_scratches(p*0.7,1.1,6.0)*0.35;
	float tire = smoothstep(0.1,0.0,abs(abs(p.x)-3.3)) * 0.12;
	vec2 cell = floor(p*2.8);
	vec2 q = fract(p*2.8)-0.5;
	float phase = fract(TIME*0.85+m_hash21(cell)*7.0);
	float ripple = sin((length(q)-phase*0.55)*80.0)*exp(-45.0*abs(length(q)-phase*0.55))*(1.0-phase);
	float h = fine*0.006*(1.0-water) - cracks*0.004 + ripple*0.0007*water;
	ALBEDO = mix(vec3(0.065,0.071,0.08)*(0.75+patch*0.5),vec3(0.028,0.035,0.042),water);
	ALBEDO *= 1.0-cracks*0.35-tire;
	METALLIC = 0.02;
	ROUGHNESS = mix(0.55+fine*0.18,0.11,water);
	SPECULAR = 0.5;
	NORMAL = m_bump(NORMAL,VERTEX,h,1.0);
}

shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://gfx/encounter/lib/math.gdshaderinc"
uniform float weathering = 0.2;
uniform vec3 glass_tint : source_color = vec3(0.04,0.08,0.11);
void fragment() {
	float grime = smoothstep(0.4,0.8,m_fbm2(UV*0.8,3))*weathering;
	float streak = m_noise2(UV*vec2(14.0,0.4));
	float dirt = grime*(0.4+0.6*streak);
	float px = max(length(fwidth(UV)),0.0001);
	float scratches = m_scratches(UV*2.0,0.7,3.0)*(1.0-smoothstep(0.005,0.03,px));
	ALBEDO = mix(glass_tint,vec3(0.14,0.12,0.10),dirt*0.45);
	ROUGHNESS = 0.13+dirt*0.32+scratches*0.12;
	METALLIC = 0.12;
	SPECULAR = 0.65;
	NORMAL = m_bump(NORMAL,VERTEX,streak*weathering*0.0005,1.0);
}

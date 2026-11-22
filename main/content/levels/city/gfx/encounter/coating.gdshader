shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://gfx/encounter/lib/math.gdshaderinc"
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 paint : source_color = vec3(0.20,0.32,0.37);
uniform float wear = 0.3;
void fragment() {
	float px = max(length(fwidth(UV)),0.0001);
	float detail = 1.0-smoothstep(0.008,0.05,px);
	float dirt = m_fbm2(UV*0.7,3);
	float scratch = m_scratches(UV*vec2(2.0,4.0),1.2,7.0)*detail;
	float chip = smoothstep(0.66,0.84,m_turb2(UV*3.8,3))*wear;
	float grain = (m_noise2(UV*190.0)-0.5)*(1.0-smoothstep(0.002,0.012,px));
	ALBEDO = mix(paint*(0.85+dirt*0.25),vec3(0.30,0.24,0.19),chip);
	ALBEDO = mix(ALBEDO,vec3(0.46,0.49,0.53),scratch*0.35);
	METALLIC = 0.32+scratch*0.4;
	ROUGHNESS = clamp(0.34+grain*0.09+dirt*wear*0.26-scratch*0.1,0.18,0.7);
	NORMAL_MAP = texture(surface_normal,UV/0.75).rgb;
	NORMAL_MAP_DEPTH = 0.65;
}

shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D leaf_albedo : filter_linear_mipmap, repeat_enable;

varying vec3 vcol;

void vertex() {
	vcol = COLOR.rgb;
}

void fragment() {
	vec3 alb = texture(leaf_albedo, UV).rgb * 1.35;
	float hue = vcol.r;
	float ao = clamp(vcol.g, 0.0, 1.0);
	vec3 tint = mix(vec3(0.56, 0.92, 0.44), vec3(1.24, 0.86, 0.42), hue);
	ALBEDO = alb * tint * ao * (0.72 + 0.38 * clamp(UV.y, 0.0, 1.0));
	ROUGHNESS = 0.58;
	SPECULAR = 0.32;
	BACKLIGHT = alb * (0.35 + 0.95 * clamp(UV.y, 0.0, 1.0)) * ao;
}

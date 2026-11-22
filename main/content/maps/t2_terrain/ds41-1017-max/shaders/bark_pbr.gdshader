shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D bark_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_normal : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 vcol;

vec3 srgb2lin(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
vec3 tri_color(sampler2D t, vec3 p, vec3 w, float s, vec2 off) {
	return srgb2lin(texture(t, p.zy * s + off).rgb) * w.x + srgb2lin(texture(t, p.xz * s + off).rgb) * w.y + srgb2lin(texture(t, p.xy * s + off).rgb) * w.z;
}
vec3 tri_normal(sampler2D t, vec3 p, vec3 w, float s, vec2 off) {
	vec3 nx = texture(t, p.zy * s + off).xyz * 2.0 - 1.0;
	vec3 ny = texture(t, p.xz * s + off).xyz * 2.0 - 1.0;
	vec3 nz = texture(t, p.xy * s + off).xyz * 2.0 - 1.0;
	vec3 wx = vec3(nx.z, nx.y, nx.x);
	vec3 wy = vec3(ny.x, ny.z, ny.y);
	vec3 wz = vec3(nz.x, nz.y, nz.z);
	return normalize(wx * w.x + wy * w.y + wz * w.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR.rgb;
}

void fragment() {
	vec3 p = wpos;
	vec3 n = normalize(wnrm);
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= max(tw.x + tw.y + tw.z, 1e-4);
	vec3 col = (tri_color(bark_albedo, p, tw, 0.9, vec2(0.0)) * 0.7 + tri_color(bark_albedo, p, tw, 2.6, vec2(0.37, 0.71)) * 0.3) * 2.4;
	col *= mix(0.55, 1.2, vcol.r);
	float moss = smoothstep(0.55, 0.85, texture(bark_albedo, p.xz * 0.7).g * 2.0) * smoothstep(0.55, 0.9, n.y);
	col = mix(col, vec3(0.06, 0.12, 0.030), moss * 0.45);
	vec3 ntex = normalize(tri_normal(bark_normal, p, tw, 0.9, vec2(0.0)) + tri_normal(bark_normal, p, tw, 2.6, vec2(0.37, 0.71)) * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.14;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(ntex, 0.0)).xyz);
}

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform sampler2D opaque_scene : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float phase_amount : hint_range(0.0, 1.0) = 0.0;
uniform float flow_time = 0.0;
instance uniform float part_seed : instance_index(4) = 0.0;
instance uniform vec3 part_center : instance_index(5) = vec3(0.0);
instance uniform vec3 part_half_size : instance_index(6) = vec3(0.5);

const vec3 IOR = vec3(1.49, 1.56, 1.64);
const float NO_HIT = 1e5;
varying vec3 part_point;
varying flat vec3 bounds;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	part_point = (VERTEX - part_center) * scale;
	bounds = part_half_size * scale;
}

float trace_plane(vec3 point, vec3 ray, vec3 axis, float offset, float depth) {
	float facing = dot(ray, axis);
	if (abs(facing) < 0.001) {
		return NO_HIT;
	}
	float distance_along_ray = (offset - dot(point, axis)) / facing;
	return distance_along_ray > 0.02 && distance_along_ray < depth ? distance_along_ray : NO_HIT;
}

vec3 spectral_transmission(vec2 uv, vec2 shift, vec2 spread) {
	return vec3(
		textureLod(opaque_scene, uv + shift - spread, 0.0).r,
		textureLod(opaque_scene, uv + shift, 0.0).g,
		textureLod(opaque_scene, uv + shift + spread * 1.17, 0.0).b
	);
}

vec3 internal_lights(vec3 direction, float progress) {
	vec3 cool = normalize(vec3(-0.73 + sin(progress) * 0.13, 0.51, -0.45));
	vec3 warm = normalize(vec3(0.68, 0.55 + cos(progress * 0.87) * 0.11, 0.42));
	vec3 lilac = normalize(vec3(0.25, -0.48, -0.73 + sin(progress * 0.79) * 0.15));
	float key = pow(max(dot(direction, cool), 0.0), 22.0);
	float fill = pow(max(dot(direction, warm), 0.0), 18.0);
	float bounce = pow(max(dot(direction, lilac), 0.0), 24.0);
	return vec3(6.0, 8.8, 10.4) * key + vec3(10.4, 7.7, 5.8) * fill + vec3(6.8, 4.2, 7.7) * bounce;
}

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 eye = normalize(VIEW);
	vec3 view_ray = refract(-eye, normal, 1.0 / IOR.g);
	mat3 axes = mat3(normalize(MODEL_MATRIX[0].xyz), normalize(MODEL_MATRIX[1].xyz), normalize(MODEL_MATRIX[2].xyz));
	mat3 part_to_view = mat3(VIEW_MATRIX) * axes;
	vec3 inside_ray = normalize(transpose(part_to_view) * view_ray);
	float facing = clamp(dot(normal, eye), 0.0, 1.0);
	float zoom = clamp(PROJECTION_MATRIX[1][1] * 5.2, 0.66, 1.80);
	vec2 aspect = vec2(VIEWPORT_SIZE.y / VIEWPORT_SIZE.x, 1.0);
	vec2 scale = aspect * zoom * phase_amount;
	vec2 uv = SCREEN_UV + (view_ray.xy + eye.xy) * scale * (0.095 + (1.0 - facing) * 0.022);
	vec3 transmitted = textureLod(opaque_scene, uv, 0.0).rgb * (0.92 + 0.068 * facing);
	vec3 reflected = vec3(0.0);

	// Trace to the first of a few nonrepeating internal interfaces of this rigid piece.
	float angle = part_seed * 6.283185;
	vec3 cut_a = normalize(vec3(cos(angle), 0.42, sin(angle)));
	vec3 cut_b = normalize(vec3(-sin(angle + 0.60), 0.86, cos(angle + 0.60)));
	vec3 cut_c = normalize(vec3(cos(angle + 1.31), -0.59, sin(angle + 1.31)));
	vec3 sign_ray = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), inside_ray));
	vec3 exit = (sign_ray * bounds - part_point) * sign_ray / max(abs(inside_ray), vec3(0.001));
	float depth = min(1.9, min(exit.x, min(exit.y, exit.z)));
	vec3 intersections = vec3(
		trace_plane(part_point, inside_ray, cut_a, (part_seed - 0.45) * 0.46, depth),
		trace_plane(part_point, inside_ray, cut_b, -0.15 - part_seed * 0.25, depth),
		trace_plane(part_point, inside_ray, cut_c, 0.22 + part_seed * 0.32, depth)
	);
	float at = min(intersections.x, min(intersections.y, intersections.z));
	if (at < NO_HIT) {
		vec3 axis = at == intersections.x ? cut_a : (at == intersections.y ? cut_b : cut_c);
		axis *= dot(inside_ray, axis) > 0.0 ? -1.0 : 1.0;
		vec3 cut_normal = part_to_view * axis;
		vec3 internal_point = part_point + inside_ray * at;
		float cos_incidence = clamp(-dot(inside_ray, axis), 0.0, 1.0);
		float sin_squared = 1.0 - cos_incidence * cos_incidence;

		// Snell's law evaluated per wavelength at the internal glass-to-air cut.
		vec3 escape = vec3(1.0) - sin_squared * IOR * IOR;
		vec3 trapped = 1.0 - smoothstep(vec3(-0.035), vec3(0.035), escape);
		vec3 leaving = refract(view_ray, cut_normal, IOR.g);
		vec2 lateral = (leaving.xy - view_ray.xy) * scale * 0.056;
		vec2 dispersion_axis = cut_normal.xy - view_ray.xy * dot(cut_normal, view_ray);
		vec2 spread = dispersion_axis * scale * (0.003 + 0.010 * sin_squared + 0.008 * at);
		float inside_fade = smoothstep(0.023, 0.078, at) * (1.0 - smoothstep(depth - 0.035, depth, at));
		vec3 through_cut = spectral_transmission(uv, lateral * (1.0 - trapped.g), spread);
		through_cut *= mix(vec3(1.0), vec3(0.66, 0.70, 0.75), trapped);
		transmitted = mix(transmitted, through_cut, inside_fade);

		vec3 bounce = normalize(mat3(INV_VIEW_MATRIX) * reflect(view_ray, cut_normal));
		float progress = flow_time * (0.38 + part_seed * 0.22) + angle;
		vec3 hotspot = cut_a * sin(progress) * 0.43 + cut_b * cos(progress * 0.87) * 0.34;
		vec3 delta = internal_point - hotspot;
		float local_light = 0.62 + 0.38 * exp(-dot(delta, delta) * 1.6);
		float smallest = min(bounds.x, min(bounds.y, bounds.z));
		float largest = max(bounds.x, max(bounds.y, bounds.z));
		float breadth = bounds.x + bounds.y + bounds.z - smallest - largest;
		float cut_area = mix(0.23, 1.0, smoothstep(0.11, 0.46, breadth));
		vec3 the_lights = internal_lights(bounce, progress);
		reflected = (vec3(0.055, 0.077, 0.097) + the_lights * local_light * cut_area) * trapped * inside_fade;
	}

	ALBEDO = transmitted + reflected;
	ALPHA = smoothstep(0.012, 0.88, phase_amount);
}


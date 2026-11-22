class_name MatLib
extends RefCounted

## Builds every procedural ShaderMaterial used by the ship.
## Keys are short strings referenced by the builders.

const S := "res://shaders/"

var table: Dictionary = {}


func _init(seed_value: int = 7) -> void:
	# keep shader seeds small: procedural hashes lose precision with huge floats
	var seed_small: float = 3.0 + float(seed_value % 89) * 0.37
	# ------------------------------------------------------------ exterior ---
	_add("hull", "hull.gdshader", {
		"paint": Color(0.56, 0.575, 0.60), "paint_dark": Color(0.10, 0.11, 0.13),
		"accent": Color(0.78, 0.29, 0.05), "seed": seed_small, "grime": 0.9,
	})
	_add("hull_dark", "hull.gdshader", {
		"paint": Color(0.115, 0.125, 0.15), "paint_dark": Color(0.055, 0.06, 0.07),
		"accent": Color(0.75, 0.28, 0.05), "seed": 3.7, "grime": 1.1,
	})
	_add("hull_accent", "hull.gdshader", {
		"paint": Color(0.72, 0.27, 0.05), "paint_dark": Color(0.12, 0.10, 0.09),
		"accent": Color(0.85, 0.80, 0.72), "seed": 9.1, "grime": 0.7,
	})
	_add("hull_soot", "hull.gdshader", {
		"paint": Color(0.20, 0.19, 0.185), "paint_dark": Color(0.05, 0.05, 0.055),
		"accent": Color(0.6, 0.25, 0.05), "seed": 5.3, "grime": 1.4,
	})

	# -------------------------------------------------------------- floors ---
	_add("floor", "plate.gdshader", {
		"base_col": Color(0.27, 0.285, 0.30), "deep_col": Color(0.045, 0.05, 0.055),
		"rust_col": Color(0.18, 0.09, 0.05), "seed": 1.0, "tile_m": 1.22,
	})
	_add("floor_grate", "plate.gdshader", {
		"base_col": Color(0.20, 0.21, 0.225), "deep_col": Color(0.006, 0.006, 0.008),
		"seed": 2.0, "grate": 1.0, "wear_amount": 1.3,
	})
	_add("floor_warm", "plate.gdshader", {
		"base_col": Color(0.34, 0.315, 0.285), "deep_col": Color(0.07, 0.06, 0.05),
		"seed": 3.0, "tile_m": 1.6, "wear_amount": 0.7,
	})
	_add("floor_med", "plate.gdshader", {
		"base_col": Color(0.36, 0.375, 0.385), "deep_col": Color(0.10, 0.105, 0.11),
		"seed": 4.0, "tile_m": 0.85, "wear_amount": 0.35,
	})
	_add("floor_dark", "plate.gdshader", {
		"base_col": Color(0.105, 0.11, 0.12), "deep_col": Color(0.015, 0.015, 0.018),
		"seed": 5.0, "wear_amount": 1.2, "metal_scale": 0.25, "rough_bias": 0.18,
	})

	# --------------------------------------------------------------- walls ---
	_add("wall", "wall.gdshader", {
		"base_col": Color(0.305, 0.32, 0.335), "trim_col": Color(0.085, 0.09, 0.10),
		"accent_col": Color(0.80, 0.42, 0.07), "style": 0, "seed": 11.0, "grime": 0.85,
	})
	_add("wall_warm", "wall.gdshader", {
		"base_col": Color(0.355, 0.335, 0.30), "trim_col": Color(0.11, 0.095, 0.08),
		"accent_col": Color(0.20, 0.60, 0.55), "style": 0, "seed": 12.0, "grime": 0.55,
	})
	_add("wall_white", "wall.gdshader", {
		"base_col": Color(0.52, 0.53, 0.54), "trim_col": Color(0.16, 0.17, 0.18),
		"accent_col": Color(0.85, 0.45, 0.08), "style": 0, "seed": 13.0, "grime": 0.5,
	})
	_add("wall_dark", "wall.gdshader", {
		"base_col": Color(0.135, 0.145, 0.16), "trim_col": Color(0.03, 0.032, 0.036),
		"accent_col": Color(0.85, 0.38, 0.06), "style": 4, "seed": 14.0, "grime": 1.0,
	})
	_add("wall_struct", "wall.gdshader", {
		"base_col": Color(0.255, 0.265, 0.28), "trim_col": Color(0.055, 0.06, 0.065),
		"style": 1, "seed": 15.0, "grime": 0.9,
	})
	_add("wall_med", "wall.gdshader", {
		"base_col": Color(0.62, 0.635, 0.64), "trim_col": Color(0.20, 0.22, 0.23),
		"style": 3, "seed": 16.0, "grime": 0.35,
	})
	_add("wall_pad", "wall.gdshader", {
		"base_col": Color(0.285, 0.265, 0.235), "trim_col": Color(0.075, 0.065, 0.055),
		"style": 2, "seed": 17.0, "grime": 0.5,
	})
	_add("wall_atrium", "wall.gdshader", {
		"base_col": Color(0.40, 0.37, 0.335), "trim_col": Color(0.14, 0.12, 0.10),
		"accent_col": Color(0.15, 0.55, 0.52), "style": 0, "seed": 18.0, "grime": 0.45,
	})
	_add("wall_hydro", "wall.gdshader", {
		"base_col": Color(0.26, 0.30, 0.275), "trim_col": Color(0.08, 0.10, 0.085),
		"accent_col": Color(0.35, 0.75, 0.25), "style": 0, "seed": 19.0, "grime": 0.75,
	})

	# --------------------------------------------------------------- metal ---
	_add("metal", "metal.gdshader", {"tint": Color(0.30, 0.31, 0.33), "seed": 1.3, "pattern": 0})
	_add("metal_dark", "metal.gdshader", {
		"tint": Color(0.115, 0.12, 0.13), "seed": 2.3, "pattern": 0,
		"rust_amount": 0.6, "oil_grime": 0.8,
	})
	_add("metal_light", "metal.gdshader", {
		"tint": Color(0.55, 0.56, 0.575), "seed": 3.3, "pattern": 1,
		"rust_amount": 0.25, "rough_base": 0.34,
	})
	_add("metal_painted", "metal.gdshader", {
		"tint": Color(0.30, 0.34, 0.33), "seed": 4.3, "pattern": 1,
		"rust_amount": 0.5, "rough_base": 0.5,
	})
	_add("metal_cast", "metal.gdshader", {
		"tint": Color(0.22, 0.225, 0.235), "seed": 5.3, "pattern": 2,
		"rust_amount": 0.55, "rough_base": 0.62,
	})
	_add("rubber", "metal.gdshader", {
		"tint": Color(0.022, 0.022, 0.024), "seed": 6.3, "pattern": 2,
		"rust_amount": 0.0, "oil_grime": 0.2, "rough_base": 0.92, "metal_amount": 0.0,
	})
	_add("copper", "metal.gdshader", {
		"tint": Color(0.52, 0.28, 0.14), "seed": 7.3, "pattern": 0,
		"rust_amount": 0.25, "rough_base": 0.3, "metal_amount": 0.95,
	})
	_add("brass", "metal.gdshader", {
		"tint": Color(0.62, 0.47, 0.20), "seed": 8.3, "pattern": 0,
		"rust_amount": 0.15, "rough_base": 0.28, "metal_amount": 0.95,
	})
	_add("pipe_orange", "metal.gdshader", {
		"tint": Color(0.60, 0.26, 0.06), "seed": 9.3, "pattern": 1,
		"rust_amount": 0.35, "rough_base": 0.44,
	})
	_add("pipe_teal", "metal.gdshader", {
		"tint": Color(0.10, 0.36, 0.36), "seed": 10.3, "pattern": 1,
		"rust_amount": 0.30, "rough_base": 0.40,
	})
	_add("pipe_cream", "metal.gdshader", {
		"tint": Color(0.52, 0.50, 0.44), "seed": 11.3, "pattern": 1,
		"rust_amount": 0.40, "rough_base": 0.48,
	})
	_add("hazard", "hazard.gdshader", {"seed": 1.0})
	_add("hazard_worn", "hazard.gdshader", {"seed": 2.0, "wear": 0.85, "col_a": Color(0.62, 0.44, 0.05)})

	# ---------------------------------------------------------- containers ---
	_add("container_a", "container.gdshader", {"paint": Color(0.13, 0.26, 0.32), "seed": 1.0})
	_add("container_b", "container.gdshader", {"paint": Color(0.34, 0.16, 0.09), "seed": 2.0})
	_add("container_c", "container.gdshader", {"paint": Color(0.22, 0.235, 0.21), "seed": 3.0})
	_add("container_d", "container.gdshader", {"paint": Color(0.32, 0.30, 0.14), "seed": 4.0})

	# ------------------------------------------------------------- emission --
	_add("emit_white", "emit.gdshader", {"color": Color(0.92, 0.95, 1.0), "energy": 3.4, "mode": 5})
	_add("emit_cool", "emit.gdshader", {"color": Color(0.62, 0.82, 1.0), "energy": 3.0, "mode": 0})
	_add("emit_warm", "emit.gdshader", {"color": Color(1.0, 0.76, 0.48), "energy": 2.8, "mode": 0})
	_add("emit_green", "emit.gdshader", {"color": Color(0.30, 1.0, 0.45), "energy": 3.0, "mode": 0})
	_add("emit_red", "emit.gdshader", {"color": Color(1.0, 0.12, 0.08), "energy": 3.4, "mode": 3})
	_add("emit_amber", "emit.gdshader", {"color": Color(1.0, 0.45, 0.06), "energy": 3.0, "mode": 0})
	_add("emit_blue", "emit.gdshader", {"color": Color(0.20, 0.55, 1.0), "energy": 3.2, "mode": 0})
	_add("emit_strip_cool", "emit.gdshader", {"color": Color(0.55, 0.80, 1.0), "energy": 2.4, "mode": 2, "seed": 2.0})
	_add("emit_strip_warm", "emit.gdshader", {"color": Color(1.0, 0.78, 0.52), "energy": 2.2, "mode": 2, "seed": 3.0})
	_add("emit_seg_blue", "emit.gdshader", {"color": Color(0.25, 0.65, 1.0), "energy": 2.6, "mode": 4})
	_add("emit_seg_amber", "emit.gdshader", {"color": Color(1.0, 0.50, 0.12), "energy": 2.4, "mode": 4})
	_add("emit_strip_dim", "emit.gdshader", {"color": Color(0.62, 0.78, 1.0), "energy": 1.1, "mode": 2})
	_add("route", "emit.gdshader", {
		"color": Color(0.20, 1.0, 0.50), "energy": 2.6, "mode": 1, "speed": 1.0, "aspect": 1.0,
	})
	_add("route_amber", "emit.gdshader", {
		"color": Color(1.0, 0.55, 0.10), "energy": 2.2, "mode": 1, "speed": 0.6,
	})

	# -------------------------------------------------------------- screens --
	_add("screen_nav", "screen.gdshader", {"mode": 0, "ink": Color(0.30, 0.85, 1.0), "seed": 1.0, "energy": 1.0})
	_add("screen_power", "screen.gdshader", {
		"mode": 1, "ink": Color(0.35, 0.90, 0.85), "seed": 2.0, "energy": 0.75,
	})
	_add("screen_med", "screen.gdshader", {
		"mode": 2, "ink": Color(0.45, 1.0, 0.65), "seed": 3.0, "energy": 0.75,
	})
	_add("screen_eng", "screen.gdshader", {
		"mode": 3, "ink": Color(0.95, 0.62, 0.22), "seed": 4.0, "energy": 1.2,
	})
	_add("screen_log", "screen.gdshader", {"mode": 4, "ink": Color(0.55, 0.80, 1.0), "seed": 5.0, "energy": 1.0})

	# --------------------------------------------------------------- energy --
	_add("plasma_engine", "plasma.gdshader", {
		"hot": Color(1.0, 0.93, 0.75), "mid": Color(1.0, 0.42, 0.10),
		"cold": Color(0.45, 0.10, 0.04), "energy": 5.0, "flow": 6.0, "mode": 0,
	})
	_add("plasma_reactor", "plasma.gdshader", {
		"hot": Color(0.80, 0.95, 1.0), "mid": Color(0.20, 0.55, 1.0),
		"cold": Color(0.06, 0.12, 0.42), "energy": 1.8, "flow": 2.5, "mode": 1,
	})
	_add("plasma_conduit", "plasma.gdshader", {
		"hot": Color(0.90, 0.98, 1.0), "mid": Color(0.20, 0.70, 1.0),
		"cold": Color(0.05, 0.15, 0.5), "energy": 2.4, "flow": 3.0, "mode": 2,
	})
	_add("holo", "hologram.gdshader", {"color": Color(0.22, 0.70, 1.0), "energy": 1.3, "mode": 0})
	_add("holo_soft", "hologram.gdshader", {
		"color": Color(0.30, 0.85, 0.95), "energy": 0.9, "mode": 2,
	})
	_add("holo_dim", "hologram.gdshader", {"color": Color(0.20, 0.62, 1.0), "energy": 0.55, "mode": 0})

	# ---------------------------------------------------------------- glass ---
	_add("glass", "glass.gdshader", {"tint": Color(0.62, 0.77, 0.86), "base_alpha": 0.055, "dirt": 0.30})
	_add("glass_dark", "glass.gdshader", {
		"tint": Color(0.20, 0.28, 0.34), "base_alpha": 0.30, "dirt": 0.55,
	})
	_add("glass_med", "glass.gdshader", {
		"tint": Color(0.70, 0.85, 0.85), "base_alpha": 0.06, "dirt": 0.1,
	})
	_add("plant", "plant.gdshader", {"seed": 1.0})
	_add("plant_b", "plant.gdshader", {
		"seed": 2.0, "leaf": Color(0.16, 0.26, 0.05), "leaf_tip": Color(0.38, 0.55, 0.12),
	})

	# ---------------------------------------------------- soft goods / decals --
	_add("fabric_grey", "fabric.gdshader", {
		"base_col": Color(0.255, 0.245, 0.225), "thread_col": Color(0.36, 0.345, 0.315),
		"seed": 1.0, "weave_m": 0.006, "grime": 0.7,
	})
	_add("fabric_olive", "fabric.gdshader", {
		"base_col": Color(0.20, 0.21, 0.15), "thread_col": Color(0.30, 0.31, 0.22),
		"seed": 2.0, "weave_m": 0.008, "grime": 0.8,
	})
	_add("fabric_rust", "fabric.gdshader", {
		"base_col": Color(0.32, 0.13, 0.07), "thread_col": Color(0.45, 0.20, 0.10),
		"seed": 3.0, "weave_m": 0.007, "grime": 0.6,
	})
	_add("fabric_teal", "fabric.gdshader", {
		"base_col": Color(0.06, 0.22, 0.22), "thread_col": Color(0.10, 0.32, 0.30),
		"seed": 4.0, "weave_m": 0.009, "grime": 0.5,
	})
	_add("fabric_white", "fabric.gdshader", {
		"base_col": Color(0.62, 0.62, 0.60), "thread_col": Color(0.74, 0.74, 0.72),
		"seed": 5.0, "weave_m": 0.005, "grime": 0.35,
	})
	_add("fabric_orange", "fabric.gdshader", {
		"base_col": Color(0.62, 0.24, 0.05), "thread_col": Color(0.78, 0.34, 0.08),
		"seed": 6.0, "weave_m": 0.007, "grime": 0.5,
	})
	_add("fabric_dark", "fabric.gdshader", {
		"base_col": Color(0.045, 0.045, 0.055), "thread_col": Color(0.08, 0.08, 0.09),
		"seed": 7.0, "weave_m": 0.01, "grime": 0.9,
	})

	_add("decal_grime", "decal.gdshader", {"kind": 0, "strength": 0.7, "seed": 1.0})
	_add("decal_oil", "decal.gdshader", {
		"kind": 1, "strength": 0.85, "seed": 2.0, "col": Color(0.02, 0.018, 0.016),
	})
	_add("decal_dust", "decal.gdshader", {
		"kind": 2, "strength": 0.55, "seed": 3.0, "col": Color(0.28, 0.26, 0.22),
	})
	_add("decal_scorch", "decal.gdshader", {"kind": 3, "strength": 0.9, "seed": 4.0})

	# simple std materials for tiny set dressing
	_add_std("paper", Color(0.78, 0.76, 0.70), 0.9, 0.0)
	_add_std("paper_b", Color(0.55, 0.60, 0.66), 0.85, 0.0)
	_add_std("ceramic", Color(0.80, 0.80, 0.78), 0.28, 0.0)
	_add_std("ceramic_dark", Color(0.20, 0.21, 0.22), 0.35, 0.0)
	_add_std("food_a", Color(0.55, 0.30, 0.10), 0.75, 0.0)
	_add_std("food_b", Color(0.62, 0.50, 0.20), 0.75, 0.0)
	_add_std("cloth_dark", Color(0.06, 0.06, 0.07), 0.95, 0.0)
	_add_std("suit_white", Color(0.72, 0.72, 0.68), 0.65, 0.0)
	_add_std("glass_bottle", Color(0.25, 0.42, 0.38), 0.10, 0.0)
	_add_std("rubber_worn", Color(0.035, 0.035, 0.038), 0.9, 0.0)


func _add_std(key: String, col: Color, rough: float, metal: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	table[key] = m


func _add(key: String, shader_file: String, params: Dictionary) -> void:
	var m := ShaderMaterial.new()
	m.shader = load(S + shader_file)
	for k in params:
		m.set_shader_parameter(k, params[k])
	table[key] = m


func m(key: String) -> Material:
	if not table.has(key):
		push_error("MatLib: missing material '%s'" % key)
		return null
	return table[key]


func sky_material(planet_dir: Vector3, sun_dir: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(S + "sky.gdshader")
	m.set_shader_parameter("planet_dir", planet_dir)
	m.set_shader_parameter("sun_dir", sun_dir)
	m.set_shader_parameter("planet_radius", 15.0)
	m.set_shader_parameter("planet_dist", 110.0)
	m.set_shader_parameter("star_energy", 1.5)
	m.set_shader_parameter("ring_enabled", 1.0)
	return m
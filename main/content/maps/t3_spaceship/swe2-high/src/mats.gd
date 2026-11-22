extends RefCounted

const GeoKit = preload("res://src/kit.gd")

## Material library: every key maps to one ShaderMaterial.
## Zones differ only by shader params — geometry batches stay per-key.

var table := {}


func _init() -> void:
	_add("wall_a", _mk(load("res://gfx/wall.gdshader"), {
		"base": Color(0.30, 0.31, 0.33), "trim": Color(0.13, 0.14, 0.16),
		"accent": Color(0.82, 0.36, 0.06), "accent_chance": 0.10, "grime": 0.7, "seed": 3.0, "panel_size": Vector2(2.6, 1.1)}))
	_add("wall_b", _mk(load("res://gfx/wall.gdshader"), {
		"base": Color(0.30, 0.285, 0.255), "trim": Color(0.15, 0.14, 0.135),
		"accent": Color(0.55, 0.30, 0.10), "accent_chance": 0.06, "grime": 0.4, "seed": 11.0, "panel_size": Vector2(2.8, 1.15)}))
	_add("wall_c", _mk(load("res://gfx/wall.gdshader"), {
		"base": Color(0.20, 0.23, 0.28), "trim": Color(0.08, 0.09, 0.12),
		"accent": Color(0.15, 0.55, 0.75), "accent_chance": 0.12, "grime": 0.3, "seed": 23.0, "panel_size": Vector2(2.4, 1.1)}))
	_add("ceil", _mk(load("res://gfx/wall.gdshader"), {
		"base": Color(0.26, 0.27, 0.29), "trim": Color(0.09, 0.10, 0.11),
		"accent": Color(0.5, 0.5, 0.5), "accent_chance": 0.02,
		"panel_size": Vector2(2.4, 1.4), "grime": 0.3, "seed": 31.0, "bump": 0.05}))
	_add("floor_a", _mk(load("res://gfx/floor.gdshader"), {
		"style": 1, "base": Color(0.27, 0.28, 0.30), "grime": 1.1, "seed": 5.0}))
	_add("floor_b", _mk(load("res://gfx/floor.gdshader"), {
		"style": 0, "base": Color(0.27, 0.26, 0.245), "line_pitch": 5.0,
		"line_col": Color(0.80, 0.55, 0.10), "grime": 0.9, "seed": 13.0}))
	_add("floor_c", _mk(load("res://gfx/floor.gdshader"), {
		"style": 0, "base": Color(0.20, 0.22, 0.26),
		"line_col": Color(0.15, 0.55, 0.75), "line_pitch": 8.0, "grime": 0.45, "seed": 29.0}))
	_add("hull", _mk(load("res://gfx/hull.gdshader"), {"seed": 0.0}))
	_add("metal_a", _mk(load("res://gfx/metal.gdshader"), {
		"style": 2, "base": Color(0.34, 0.35, 0.37), "seed": 7.0}))
	_add("metal_b", _mk(load("res://gfx/metal.gdshader"), {
		"style": 1, "base": Color(0.33, 0.29, 0.20), "seed": 17.0}))   # ochre machinery
	_add("metal_c", _mk(load("res://gfx/metal.gdshader"), {
		"style": 1, "base": Color(0.24, 0.33, 0.36), "seed": 19.0}))   # teal machinery
	_add("metal_d", _mk(load("res://gfx/metal.gdshader"), {
		"style": 2, "base": Color(0.44, 0.46, 0.49), "seed": 37.0}))   # bright alloy
	_add("copper", _mk(load("res://gfx/metal.gdshader"), {
		"style": 3, "base": Color(0.45, 0.24, 0.12), "seed": 41.0}))
	_add("dark", _mk(load("res://gfx/metal.gdshader"), {
		"style": 0, "base": Color(0.24, 0.25, 0.28), "seed": 43.0}))
	_add("fabric", _mk(load("res://gfx/fabric.gdshader"), {}))
	_add("fabric_b", _mk(load("res://gfx/fabric.gdshader"), {
		"base": Color(0.30, 0.20, 0.18), "seam_col": Color(0.16, 0.11, 0.10)}))
	_add("crate", _mk(load("res://gfx/crate.gdshader"), {}))
	_add("hazard", _mk(load("res://gfx/hazard.gdshader"), {}))
	_add("glass", _mk(load("res://gfx/glass.gdshader"), {}))
	_add("screen_a", _mk(load("res://gfx/screen.gdshader"), {"style": 0, "seed": 2.0}))
	_add("screen_b", _mk(load("res://gfx/screen.gdshader"), {
		"style": 1, "seed": 7.0, "tint": Color(0.2, 0.7, 0.9)}))
	_add("screen_c", _mk(load("res://gfx/screen.gdshader"), {
		"style": 2, "seed": 5.0, "tint": Color(0.3, 0.8, 0.5)}))
	_add("u_light", _mk(load("res://gfx/emit.gdshader"), {
		"col": Color(1.0, 0.93, 0.82), "energy": 1.8}))
	_add("u_light_c", _mk(load("res://gfx/emit.gdshader"), {
		"col": Color(0.55, 0.8, 1.0), "energy": 0.9}))
	_add("u_light_r", _mk(load("res://gfx/emit.gdshader"), {
		"col": Color(1.0, 0.25, 0.12), "energy": 1.8}))
	_add("u_light_o", _mk(load("res://gfx/emit.gdshader"), {
		"col": Color(1.0, 0.55, 0.15), "energy": 1.5}))
	_add("u_segm", _mk(load("res://gfx/emit.gdshader"), {
		"style": 1, "col": Color(0.85, 0.9, 1.0), "energy": 1.2, "segs": 20.0}))
	_add("u_chev", _mk(load("res://gfx/emit.gdshader"), {
		"style": 2, "col": Color(0.15, 0.8, 0.4), "col_b": Color(0.05, 0.08, 0.07),
		"energy": 1.2, "segs": 6.0, "scroll": 0.6}))
	_add("u_chev2", _mk(load("res://gfx/emit.gdshader"), {
		"style": 2, "col": Color(1.0, 0.6, 0.1), "col_b": Color(0.08, 0.05, 0.02),
		"energy": 1.0, "segs": 5.0, "scroll": 0.4}))
	_add("plasma", _mk(load("res://gfx/plasma.gdshader"), {}))
	_add("plasma_o", _mk(load("res://gfx/plasma.gdshader"), {
		"col": Color(1.0, 0.5, 0.15), "hot": Color(1.0, 0.9, 0.6), "energy": 4.0}))
	_add("holo", _mk(load("res://gfx/holo.gdshader"), {}))
	_add("holo_o", _mk(load("res://gfx/holo.gdshader"), {
		"col": Color(1.0, 0.6, 0.2), "energy": 1.6}))
	_add("plant", _mk(load("res://gfx/plant.gdshader"), {}))


func _mk(sh: Shader, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func _add(key: String, m: Material) -> void:
	table[key] = m


func m(key: String) -> Material:
	return table[key]


func register(kit) -> void:
	for k in table:
		kit.material(k, table[k])

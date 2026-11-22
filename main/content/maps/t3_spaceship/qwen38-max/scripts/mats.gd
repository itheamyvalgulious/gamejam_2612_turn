class_name Mats
extends RefCounted
## Material factory: all materials are procedural (shaders with math textures
## or plain PBR with vertex-color tint). Keys match Geom batch keys.

static func build() -> Dictionary:
	var m := {}
	var sh_panel: Shader = load("res://shaders/panel.gdshader")
	var sh_floor: Shader = load("res://shaders/floor.gdshader")
	var sh_grate: Shader = load("res://shaders/grate.gdshader")
	var sh_strip: Shader = load("res://shaders/strip.gdshader")
	var sh_screen: Shader = load("res://shaders/screen.gdshader")
	var sh_frame: Shader = load("res://shaders/frame.gdshader")
	var sh_hull: Shader = load("res://shaders/hull.gdshader")
	var sh_glass: Shader = load("res://shaders/glass.gdshader")
	var sh_exhaust: Shader = load("res://shaders/exhaust.gdshader")
	var sh_holo: Shader = load("res://shaders/holo.gdshader")

	m["panel_clean"] = _panel(sh_panel, 0.12, Color(0.34, 0.36, 0.41), Color(0.26, 0.28, 0.32), 0.35, 0.45, 0.25)
	m["panel_std"] = _panel(sh_panel, 0.4, Color(0.28, 0.3, 0.34), Color(0.2, 0.215, 0.245), 0.3, 1.0, 0.6)
	m["panel_grimy"] = _panel(sh_panel, 1.15, Color(0.235, 0.228, 0.21), Color(0.165, 0.155, 0.14), 0.26, 1.6, 1.0)
	m["panel_dark"] = _panel(sh_panel, 0.7, Color(0.14, 0.145, 0.16), Color(0.1, 0.105, 0.12), 0.15, 1.2, 0.8)

	m["floor_std"] = _floor(sh_floor, 0.5, 0.0, 0.0, Color(0.2, 0.21, 0.235))
	m["floor_gloss"] = _floor(sh_floor, 0.16, 0.85, 0.0, Color(0.14, 0.15, 0.18))
	m["floor_hazard"] = _floor(sh_floor, 0.65, 0.0, 1.0, Color(0.2, 0.2, 0.2))
	m["floor_grimy"] = _floor(sh_floor, 0.95, 0.0, 0.0, Color(0.17, 0.165, 0.155))
	(m["floor_grimy"] as ShaderMaterial).set_shader_parameter("u_dust", 0.9)

	m["grate_std"] = _mat(sh_grate, {"u_rust": 0.22, "u_under": Color(0.02, 0.02, 0.025), "u_under_gain": 1.0})
	m["grate_engine"] = _mat(sh_grate, {"u_rust": 0.5, "u_under": Color(1.0, 0.42, 0.12), "u_under_gain": 1.7})
	m["grate_cool"] = _mat(sh_grate, {"u_rust": 0.3, "u_under": Color(0.25, 0.6, 1.0), "u_under_gain": 1.35})

	m["frame"] = _mat(sh_frame, {"u_rust": 0.15})
	m["frame_rust"] = _mat(sh_frame, {"u_rust": 0.65})
	m["frame_yellow"] = _mat(sh_frame, {"u_rust": 0.4, "u_paint": Color(0.55, 0.4, 0.06), "u_wear": 1.3})
	m["frame_red"] = _mat(sh_frame, {"u_rust": 0.35, "u_paint": Color(0.4, 0.08, 0.06), "u_wear": 1.2})

	m["strip_cyan"] = _strip(Color(0.55, 0.82, 1.0), 3.0)
	m["strip_warm"] = _strip(Color(1.0, 0.78, 0.5), 2.7)
	m["strip_amber"] = _strip(Color(1.0, 0.6, 0.2), 3.0)
	m["strip_red"] = _strip(Color(1.0, 0.25, 0.15), 2.8)
	m["strip_green"] = _strip(Color(0.4, 1.0, 0.55), 2.6)
	m["strip_magenta"] = _strip(Color(1.0, 0.4, 0.9), 3.4)
	m["strip_white"] = _strip(Color(0.92, 0.95, 1.0), 2.4)
	m["strip_route"] = _strip(Color(0.35, 1.0, 0.85), 4.5)
	(m["strip_route"] as ShaderMaterial).set_shader_parameter("u_arrow", 1.0)
	(m["strip_route"] as ShaderMaterial).set_shader_parameter("u_speed", 0.55)
	m["strip_hazardmark"] = _strip(Color(1.0, 0.75, 0.15), 2.0)
	m["strip_flicker"] = _strip(Color(0.75, 0.85, 1.0), 2.6)
	(m["strip_flicker"] as ShaderMaterial).set_shader_parameter("u_flicker", 0.85)
	(m["strip_flicker"] as ShaderMaterial).set_shader_parameter("u_phase", 3.7)
	m["strip_amber_r"] = _strip(Color(1.0, 0.6, 0.2), 3.0)
	(m["strip_amber_r"] as ShaderMaterial).set_shader_parameter("u_edge_fade", 0.0)
	m["strip_cyan_r"] = _strip(Color(0.55, 0.82, 1.0), 3.0)
	(m["strip_cyan_r"] as ShaderMaterial).set_shader_parameter("u_edge_fade", 0.0)

	m["screen_cyan"] = _screen(0, Color(0.4, 0.85, 1.0))
	m["screen_amber"] = _screen(0, Color(1.0, 0.72, 0.3))
	m["screen_green"] = _screen(1, Color(0.45, 1.0, 0.6))
	m["screen_radar"] = _screen(2, Color(0.45, 0.95, 0.8))
	m["screen_bars"] = _screen(3, Color(0.55, 0.8, 1.0))
	m["screen_med"] = _screen(1, Color(0.5, 0.9, 1.0))

	m["emit_cyan"] = _emit(Color(0.45, 0.78, 1.0), 3.2)
	m["emit_amber"] = _emit(Color(1.0, 0.58, 0.18), 1.8)
	m["emit_white"] = _emit(Color(0.95, 0.97, 1.0), 3.0)
	m["emit_warm"] = _emit(Color(1.0, 0.8, 0.55), 2.4)
	m["emit_route"] = _emit(Color(0.25, 1.0, 0.8), 1.3)
	m["emit_green"] = _emit(Color(0.45, 1.0, 0.6), 2.4)

	m["glass"] = _mat(sh_glass, {})

	m["hull"] = _mat(sh_hull, {})
	m["hull_inner"] = _mat(sh_hull, {"u_base": Color(0.1, 0.105, 0.12), "u_grime": 0.8, "u_plate": 5.0})
	(m["hull_inner"] as ShaderMaterial).set_shader_parameter("u_warm", Color(0.2, 0.16, 0.13))

	m["exhaust"] = _mat(sh_exhaust, {})
	m["exhaust_warm"] = _mat(sh_exhaust, {"u_core": Color(1.0, 0.85, 0.6), "u_edge": Color(1.0, 0.45, 0.15)})
	(m["exhaust"] as ShaderMaterial).set_shader_parameter("u_len", 20.0)
	(m["exhaust"] as ShaderMaterial).set_shader_parameter("u_gain", 3.4)
	m["holo"] = _mat(sh_holo, {})

	# plain PBR metals for props (vertex-color tinted)
	m["metal"] = _std(Color.WHITE, 0.72, 0.5)
	m["metal_dark"] = _std(Color(0.55, 0.57, 0.62), 0.6, 0.55)
	m["metal_warm"] = _std(Color(0.75, 0.66, 0.55), 0.55, 0.6)
	m["rubber"] = _std(Color(0.16, 0.16, 0.17), 0.05, 0.92)
	m["plastic"] = _std(Color(0.8, 0.8, 0.82), 0.0, 0.55)
	m["fabric"] = _std(Color(0.85, 0.85, 0.85), 0.0, 0.95)
	m["white_mat"] = _std(Color(0.9, 0.91, 0.93), 0.1, 0.4)
	return m

static func _panel(sh: Shader, grime: float, a: Color, b: Color, accent: float, wear: float = 1.0, dust: float = 0.6) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("u_grime", grime)
	sm.set_shader_parameter("u_base_a", Vector3(a.r, a.g, a.b))
	sm.set_shader_parameter("u_base_b", Vector3(b.r, b.g, b.b))
	sm.set_shader_parameter("u_accent_amt", accent)
	sm.set_shader_parameter("u_wear", wear)
	sm.set_shader_parameter("u_dust", dust)
	return sm

static func _floor(sh: Shader, grime: float, gloss: float, hazard: float, base: Color) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("u_grime", grime)
	sm.set_shader_parameter("u_gloss", gloss)
	sm.set_shader_parameter("u_hazard", hazard)
	sm.set_shader_parameter("u_base", Vector3(base.r, base.g, base.b))
	return sm

static func _strip(col: Color, gain: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/strip.gdshader")
	sm.set_shader_parameter("u_color", Vector3(col.r, col.g, col.b))
	sm.set_shader_parameter("u_gain", gain)
	return sm

static func _screen(style: int, col: Color) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/screen.gdshader")
	sm.set_shader_parameter("u_style", style)
	sm.set_shader_parameter("u_color", Vector3(col.r, col.g, col.b))
	sm.set_shader_parameter("u_gain", 2.2)
	return sm

static func _mat(sh: Shader, params: Dictionary) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = sh
	for k in params:
		var v = params[k]
		if v is Color:
			v = Vector3(v.r, v.g, v.b)
		sm.set_shader_parameter(k, v)
	return sm

static func _emit(col: Color, energy: float) -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.02, 0.02, 0.025)
	sm.emission_enabled = true
	sm.emission = col
	sm.emission_energy = energy
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.roughness = 0.5
	sm.metallic = 0.0
	return sm

static func _std(col: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = col
	sm.metallic = metallic
	sm.roughness = rough
	sm.metallic_specular = 0.6
	return sm

extends Node

const SHADER := preload("res://shaders/fx_vol_screen.gdshader")
const W := 1264
const H := 710

var mat: ShaderMaterial
var vp: SubViewport


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 1))
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cr := ColorRect.new()
	cr.color = Color(1, 1, 1, 1)
	cr.position = Vector2.ZERO
	cr.size = Vector2(W, H)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("noise_tex", load("res://shaders/ich0_rgba_noise_medium.png"))
	mat.set_shader_parameter("noise2_tex", load("res://shaders/ich2_grey_noise_small.png"))
	mat.set_shader_parameter("variant", int(OS.get_environment("FX_VARIANT")))
	mat.set_shader_parameter("debug_mode", int(OS.get_environment("FX_DEBUG")))
	mat.set_shader_parameter("zoom_key", float(OS.get_environment("FX_ZOOM")))
	cr.material = mat
	vp.add_child(cr)
	var outdir := OS.get_environment("FX_OUT")
	if outdir == "":
		outdir = "/tmp/opencode/fx_test"
	DirAccess.make_dir_recursive_absolute(outdir)
	await get_tree().process_frame
	var times: Array = []
	if OS.get_environment("FX_T1") != "":
		var t0 := float(OS.get_environment("FX_T0"))
		var t1 := float(OS.get_environment("FX_T1"))
		var dt := float(OS.get_environment("FX_DT"))
		var v := t0
		while v <= t1 + 0.0001:
			times.append(v)
			v += dt
	else:
		times = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0]
	for t in times:
		mat.set_shader_parameter("t_override", t)
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(outdir.path_join("t_%05.2f.png" % t))
		print("saved ", t)
	get_tree().quit()
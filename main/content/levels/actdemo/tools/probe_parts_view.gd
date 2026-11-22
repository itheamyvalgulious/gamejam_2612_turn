extends Node3D
## 判定件可视化截图：把敌人 hit_parts() 的胶囊画成线框，核对它们是否贴合机体。
##
##   DISPLAY=:0 godot --path . res://scenes/probe_parts_view.tscn

const MainScene = preload("res://main.tscn")
const Shot = preload("res://tools/shot.gd")

var game
var dbg: MeshInstance3D
var shot = Shot.new()
var target


func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("mob.aggro_range", 0.0)
	game.level.start_level(0)
	await get_tree().process_frame
	await get_tree().process_frame
	game.player.reset(Transform3D(Basis(), Vector3(0, 0, 6.0)))
	game.cam.yaw = 0.0
	var i := 0
	for e in game.level.enemies:
		if e.alive:
			if target == null:
				target = e
				e.global_position = Vector3(0, 0, 0)
				e.rig.rotation.y = 0.0
			else:
				e.global_position = Vector3(60.0 + 6.0 * i, 0, 60.0)
			i += 1
	dbg = MeshInstance3D.new()
	dbg.name = "PartsDebug"
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.95)
	dbg.material_override = m
	dbg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dbg)
	await shot.wait_frames(get_tree(), 16)
	# 冻结主循环，自己摆机位（战场光照保留）
	game.set_process(false)
	game.hud.visible = false
	var cam3d: Camera3D = game.cam.camera
	cam3d.global_position = Vector3(5.2, 3.0, 5.2)
	cam3d.look_at(Vector3(0, 1.9, 0), Vector3.UP)
	await shot.capture(self, "res://shots/part_debug.png", 6)
	cam3d.global_position = Vector3(2.2, 1.2, 2.2)
	cam3d.look_at(Vector3(1.2, 0.9, 1.2), Vector3.UP)
	await shot.capture(self, "res://shots/part_debug_leg.png", 6)
	get_tree().quit()


func _process(_dt: float) -> void:
	if dbg == null or target == null or not is_instance_valid(target):
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for p in target.hit_parts():
		var a: Vector3 = p["a"]
		var b: Vector3 = p["b"]
		var r: float = float(p["r"])
		_line(st, a, b, Color(0.25, 0.95, 1.0, 0.95))
		var steps := 10
		for k in steps:
			var a0 := TAU * float(k) / float(steps)
			var a1 := TAU * float(k + 1) / float(steps)
			_line(st, a + Vector3(cos(a0), 0, sin(a0)) * r,
				a + Vector3(cos(a1), 0, sin(a1)) * r, Color(0.25, 0.95, 1.0, 0.8))
			if a.distance_to(b) > 0.2:
				_line(st, b + Vector3(cos(a0), 0, sin(a0)) * r,
					b + Vector3(cos(a1), 0, sin(a1)) * r, Color(0.25, 0.95, 1.0, 0.8))
	dbg.mesh = st.commit()


func _line(st: SurfaceTool, a: Vector3, b: Vector3, c: Color) -> void:
	st.set_color(c)
	st.add_vertex(a)
	st.set_color(c)
	st.add_vertex(b)

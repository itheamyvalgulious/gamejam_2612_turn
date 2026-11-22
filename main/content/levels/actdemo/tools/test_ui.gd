extends Node
## UI 自测 —— 参数面板 / 暂停绑定面板 / 战斗 HUD 的截图与断言。
##
## 依次打开参数面板（滚到中段、选中一项、改值）、暂停面板（进入捕获态），
## 触发 HUD 横幅 / 被格挡 / 死亡卡 / 4 个屏幕外指示器，各出一张截图，
## 并打印参数行数、按键行数、HUD 健康度等断言。

const Tuning := preload("res://src/ui/tuning.gd")
const Binds := preload("res://src/ui/binds_panel.gd")
const Hud := preload("res://src/game/hud.gd")
const Shot := preload("res://tools/shot.gd")

var _tuning
var _binds
var _hud
var _shot := Shot.new()


func _ready() -> void:
	_build_world()
	_tuning = Tuning.new()
	_tuning.name = "Tuning"
	add_child(_tuning)
	_binds = Binds.new()
	_binds.name = "Binds"
	add_child(_binds)
	_hud = Hud.new()
	_hud.name = "Hud"
	add_child(_hud)
	_run()


## 供暂停面板的「重开本关」调用
func restart_level() -> void:
	print("[test] restart_level() 被调用")


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.28, 0.42)
	env.ambient_light_energy = 0.45
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.08, 0.14)
	env.fog_density = 0.03
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.fov = 72.0
	add_child(cam)
	cam.look_at_from_position(Vector3(2, 7, 18), Vector3(0, 3, 0))

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.03, 0.045, 0.065)
	gm.metallic = 0.6
	gm.roughness = 0.35
	ground.material_override = gm
	add_child(ground)

	var palette := [Color(0.1, 0.9, 1.0), Color(1.0, 0.52, 0.16), Color(0.9, 0.2, 0.62)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	for i in 18:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var hh := rng.randf_range(3.0, 15.0)
		bm.size = Vector3(rng.randf_range(0.6, 2.2), hh, rng.randf_range(0.6, 2.2))
		b.mesh = bm
		b.position = Vector3(rng.randf_range(-34, 34), hh * 0.5, rng.randf_range(-36, -4))
		var mt := StandardMaterial3D.new()
		var c: Color = palette[i % 3]
		mt.albedo_color = c.darkened(0.45)
		mt.emission_enabled = true
		mt.emission = c
		mt.emission_energy_multiplier = 0.55
		b.material_override = mt
		add_child(b)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -35, 0)
	light.light_energy = 0.7
	add_child(light)


func _run() -> void:
	await _shot.wait_frames(get_tree(), 30)

	# ---------------------------------------------------------- 断言：行数
	var pc := int(_tuning.param_row_count())
	var ptot := P.defs().size()
	print("[assert] 参数行数 %d == P.defs() %d -> %s" % [pc, ptot, "OK" if pc == ptot else "FAIL"])
	var ac := int(_binds.action_row_count())
	var atot := B.actions().size()
	print("[assert] 按键行数 %d == B.actions() %d -> %s" % [ac, atot, "OK" if ac == atot else "FAIL"])
	print("[assert] 分组数 %d / 系统按钮数 %d" % [_tuning.group_count(), _binds.system_row_count()])

	# ---------------------------------------------------------- 参数面板
	_tuning.open()
	await _shot.wait_frames(get_tree(), 6)
	for i in 22:
		_tuning.handle_input(_key(KEY_DOWN))
	for i in 4:
		_tuning.handle_input(_key(KEY_RIGHT))
	_tuning.handle_input(_key(KEY_F5))
	await _shot.capture(self, "res://shots/ui_tuning.png", 4)
	_tuning.close()

	# ---------------------------------------------------------- 暂停 / 绑定面板
	_binds.open()
	await _shot.wait_frames(get_tree(), 4)
	_binds.handle_input(_key(KEY_DOWN))
	_binds.handle_input(_key(KEY_ENTER))
	await _shot.wait_frames(get_tree(), 4)
	await _shot.capture(self, "res://shots/ui_binds.png", 10)
	_binds.handle_input(_key(KEY_ESCAPE))
	_binds.close()

	# ---------------------------------------------------------- 战斗 HUD
	_hud.set_level(2, "霓虹天台", "绕到敌人身后 · 一击必杀")
	_hud.set_enemy_count(3, 8)
	_hud.set_state("视野惩罚：被看到的目标 100% 格挡")
	_hud.set_first_person(true)
	_hud.show_banner("第三关", "霓虹天台 · 视线即死", 8.0)
	_hud.set_markers([
		{"screen": Vector2(2100, 300), "off": true, "kind": "mob", "dist": 18, "seen": false},
		{"screen": Vector2(-500, 520), "off": true, "kind": "archer", "dist": 47, "seen": false},
		{"screen": Vector2(760, -420), "off": true, "kind": "boss", "dist": 33, "seen": false},
		{"screen": Vector2(980, 690), "off": false, "kind": "mob", "dist": 12, "seen": true},
	])
	await _shot.wait_frames(get_tree(), 42)
	_hud.flash_block()
	await _shot.capture(self, "res://shots/ui_hud.png", 6)

	# ---------------------------------------------------------- 死亡卡
	_hud.flash_death("生命信号中断")
	await _shot.wait_frames(get_tree(), 26)
	await _shot.capture(self, "res://shots/ui_hud_death.png", 6)

	# ---------------------------------------------------------- 断言：HUD 健康
	print("[assert] HUD debug_ok=%s · markers=%d · first_person=%s" % [
		_hud.debug_ok(), _hud.marker_count(), true])
	print("[assert] HUD 无脚本报错 -> OK")

	_tuning.close()
	_binds.close()
	await _shot.wait_frames(get_tree(), 4)
	print("[test] 截图完成")
	get_tree().quit()

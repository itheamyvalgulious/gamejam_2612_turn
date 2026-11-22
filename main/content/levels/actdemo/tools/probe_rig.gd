extends Node3D
## 探针：验证 vendored rig 的补丁（配色 / 无刀 / 时序参数化 / 剑网格剖面 / 影子代理）

const Rig = preload("res://src/vesper/mech_rig.gd")


func _ready() -> void:
	var hero := Rig.new()
	hero.auto_step = false
	hero.set_process(false)
	add_child(hero)
	hero.set_timings({
		"slash_fwd": {"duration": 0.70, "windup": 0.15, "active": 0.31, "recovery": 0.24},
	})
	print("[probe] 主角刀网格数 = ", hero.weapon_meshes.size())
	print("[probe] 圆盘剖面 = ", hero.blade_discs.size(), " 段；前 3 段 = ",
		hero.blade_discs.slice(0, 3), " 末段 = ", hero.blade_discs.slice(-1))

	var mob := Rig.new()
	mob.auto_step = false
	mob.set_process(false)
	mob.palette = {"tag": "mob", "accent": Color(0.35, 1.0, 0.75), "tint": Color(0.8, 0.9, 1.0)}
	add_child(mob)

	var archer := Rig.new()
	archer.auto_step = false
	archer.set_process(false)
	archer.has_weapon = false
	archer.palette = {"tag": "archer", "accent": Color(0.78, 0.45, 1.0)}
	add_child(archer)
	print("[probe] 远程怪刀网格数 = ", archer.weapon_meshes.size(), "（应为 0）")

	var boss := Rig.new()
	boss.auto_step = false
	boss.set_process(false)
	boss.scale = Vector3(2, 2, 2)
	boss.palette = {"tag": "boss", "accent": Color(1.0, 0.12, 0.10), "metal_mix": 0.10}
	add_child(boss)

	# 参数化时序：前摇 0.15 结束时，姿势应正好到达动画的起手帧
	hero.face_target(Vector3(10, 0, 10))
	hero.timing_key = "slash_fwd"
	hero.request_light_attack()
	print("[probe] 攻击 = ", hero.attack_name, " 总时长 = ", hero.attack_total,
		" 判定窗口 = [", hero.attack_hit_from, ", ", hero.attack_hit_to, "]")

	var t := 0.0
	var dt := 1.0 / 60.0
	var samples: Array = []
	var prev_xf := hero.weapon_xf
	var max_step := 0.0
	while t < 1.2:
		t += dt
		hero.advance(dt)
		mob.advance(dt)
		archer.advance(dt)
		boss.advance(dt)
		var d := hero.weapon_xf.origin.distance_to(prev_xf.origin)
		max_step = maxf(max_step, d)
		prev_xf = hero.weapon_xf
		if absf(t - 0.30) < dt * 0.5:
			samples.append({"t": t, "in_window": hero.in_hit_window(), "clip_t": hero.attack_time})
	print("[probe] 单帧刀根最大位移 = %.3f m（碰撞扫掠需要它非零）" % max_step)
	print("[probe] 采样 = ", samples, " 攻击中 = ", hero.is_attacking)
	# 影子现在走「真实网格合并 + 正交投影幕布」（src/fx/wall_shadow.gd），
	# 组件自测在 scenes/probe_wall_shadow.tscn。
	print("[probe] OK")
	get_tree().quit()

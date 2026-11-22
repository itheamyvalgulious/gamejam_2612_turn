extends Node3D
## 探针：核对「2.5 m 机体 + 所有距离参数都在同一把尺子上」。
##   godot --headless --path . res://scenes/probe_scale.tscn
##
## 判据全部用真实米：世界单位 × Units.M_PER_UNIT。

const Rig = preload("res://src/vesper/mech_rig.gd")
const Units = preload("res://src/core/units.gd")
const Qa = preload("res://tools/qa_lib.gd")

var q: Qa


func _mesh_top(n: Node, xf := Transform3D.IDENTITY) -> float:
	var top := -1e9
	for c in n.get_children():
		if String(c.name) in ["Greatsword", "GreatswordTrail", "FX"]:
			continue
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			var b: AABB = (xf * mi.transform) * mi.mesh.get_aabb()
			top = maxf(top, b.position.y + b.size.y)
		if c is Node3D and not (c is MeshInstance3D):
			top = maxf(top, _mesh_top(c, xf * (c as Node3D).transform))
	return top


func _ready() -> void:
	q = Qa.new("probe_scale")
	print("\n---- 比例基准 ----")
	q.info("1 世界单位 = %.3f m" % Units.M_PER_UNIT)

	var hero := Rig.new()
	hero.auto_step = false
	hero.set_process(false)
	add_child(hero)
	hero.advance(1.0 / 60.0)
	var top_u := _mesh_top(hero)
	q.ok(absf(Units.to_meters(top_u) - 2.5) < 0.03, "玩家机体高度 2.5 m",
		"%.3f 世界单位 = %.3f m" % [top_u, Units.to_meters(top_u)])

	# 小怪 / 大怪（同一套 rig，只是缩放系数不同）
	for case in [["小怪", 1.0], ["大怪", 2.0]]:
		var e := Rig.new()
		e.auto_step = false
		e.set_process(false)
		e.scale = Vector3.ONE * float(case[1])
		add_child(e)
		e.advance(1.0 / 60.0)
		var h := Units.to_meters(_mesh_top(e) * float(case[1]))
		q.ok(absf(h - 2.5 * float(case[1])) < 0.05, "%s 高度 %.2f m" % [case[0], 2.5 * float(case[1])],
			"实测 %.3f m" % h)

	# ---------------------------------------------------------------- 跳跃
	print("\n---- 跳跃（重力 %.1f m/s²，高度 %.2f m）----" % [
		P.getm("jump.gravity"), P.getm("jump.height")])
	hero.grav = P.getf("jump.gravity")
	hero.jump_vel = P.jump_velocity()
	hero.takeoff_time = P.getf("jump.takeoff_time")
	hero.land_time = P.getf("jump.land_time")
	q.info("起跳初速 = %.3f m/s" % Units.to_meters(hero.jump_vel))
	hero.request_jump()
	var dt := 1.0 / 240.0
	var y_max := 0.0
	var t := 0.0
	var air_t := 0.0
	while t < 3.0:
		hero.advance(dt)
		t += dt
		y_max = maxf(y_max, hero.position.y)
		if hero.jump_state == "AIR":
			air_t += dt
		if t > 0.2 and hero.jump_state == "GROUND":
			break
	var apex := Units.to_meters(y_max)
	q.ok(absf(apex - P.getm("jump.height")) < 0.05, "跳跃顶点 1.50 m", "实测 %.3f m" % apex)
	q.ok(absf(air_t - 2.0 * sqrt(2.0 * P.getm("jump.height") / P.getm("jump.gravity"))) < 0.08,
		"滞空时间 %.2f s（10 m/s² 下 1.5 m 的自然值）" % air_t, "实测 %.3f s" % air_t)

	# ---------------------------------------------------------------- 冲刺
	print("\n---- 冲刺（距离 %.2f m / %.2f s）----" % [
		P.getm("dash.distance"), P.getm("dash.duration")])
	hero.position = Vector3.ZERO
	hero.jump_state = "GROUND"
	hero._dash_cooldown = 0.0
	hero.dash_distance = P.getf("dash.distance")
	hero.dash_duration = P.getf("dash.duration")
	hero.dash_cd = P.getf("dash.cooldown")
	var start := hero.position
	hero.request_dash()
	t = 0.0
	while t < 1.0:
		hero.advance(dt)
		t += dt
		if hero.dash_time <= 0.0 and t > 0.1:
			break
	var dash_m := Units.to_meters(Vector2(hero.position.x - start.x, hero.position.z - start.z).length())
	q.ok(absf(dash_m - P.getm("dash.distance")) < 0.15, "冲刺位移 3.00 m", "实测 %.3f m" % dash_m)

	# ---------------------------------------------------------------- 攻击时间轴
	print("\n---- 攻击时间轴（米 / 秒）----")
	for id in [["slash_left", "左斩"], ["slash_right", "右斩"], ["slash_back", "回身斩"],
			["spin", "回旋斩"], ["slash_fwd", "正前斩"], ["heavy", "重斩"]]:
		var key: String = id[0]
		var act := P.attack_active(key)
		q.info("%s：总 %.2f s = 前摇 %.2f + 判定 %.2f + 后摇 %.2f；前冲 %.2f m；击退 %.2f m" % [
			id[1], P.getm("attack.%s.duration" % key), P.getm("attack.%s.windup" % key),
			act, P.getm("attack.%s.recovery" % key),
			P.getm("attack.%s.lunge" % key), P.getm("attack.%s.knockback" % key)])

	# ---------------------------------------------------------------- 判定范围
	print("\n---- 判定 / 镜头（米）----")
	q.info("弹反半径 %.2f m · 小怪挥刀 %.2f m · 大怪重击 %.2f m · 刀气半径 %.2f m" % [
		P.getm("parry.radius"), P.getm("mob.attack_range"), P.getm("boss.slam_radius"),
		P.getm("boss.qi_radius")])
	q.info("第三人称距离 %.2f m / 眼高 %.2f m / 看向高度 %.2f m" % [
		P.getm("cam.distance"), P.getm("cam.first_height"), P.getm("cam.focus_height")])
	q.info("走 %.2f · 跑 %.2f · 冲刺跑 %.2f m/s；小怪 %.2f · 远程 %.2f · 大怪 %.2f m/s" % [
		P.getm("move.walk_speed"), P.getm("move.run_speed"), P.getm("move.sprint_speed"),
		P.getm("mob.speed"), P.getm("archer.speed"), P.getm("boss.speed")])

	# ---------------------------------------------------------------- 全部长度参数（真实米）
	print("\n---- 全部长度参数（米；面板里显示的就是这些值）----")
	var rows: Array = []
	for d in P.defs():
		if bool(d.get("len", false)):
			rows.append("%s=%s%s" % [d["path"], str(P.getm(d["path"])), d["unit"]])
	q.info("共 %d 项" % rows.size())
	for i in range(0, rows.size(), 3):
		print("   " + "   ".join(rows.slice(i, i + 3)))

	# 换算闭合：面板值(米) → 内部世界单位 → 再回米
	var round_trip := Units.to_meters(P.getf("parry.radius"))
	q.ok(absf(round_trip - P.getm("parry.radius")) < 1e-5, "米 ↔ 世界单位 换算闭合",
		"%.3f m" % round_trip)
	q.ok(P.getf("jump.height") > P.getm("jump.height"), "长度参数内部确实换算成了世界单位",
		"%.2f u vs %.2f m" % [P.getf("jump.height"), P.getm("jump.height")])

	var fails := q.summary()
	get_tree().quit(1 if fails != 0 else 0)

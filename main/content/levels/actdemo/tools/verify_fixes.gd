extends Node3D
## 复核 QA 报的三个致命问题是否真的修好（临时探针）

const MainScene = preload("res://main.tscn")

var game


func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("move.facing_mode", "camera")

	await _move_dirs()
	await _enemy_reach()
	await _archer_range()
	await _boss_slam()
	await _blind_kill()
	await _cam_inside()
	print("[verify] 完成")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _move_dirs() -> void:
	print("\n[1] A/D/S 真的横移/后退")
	P.set_value("cam.mode", "third")
	game.cam.yaw = 0.0
	game.player.reset(Transform3D(Basis(), Vector3.ZERO))
	await _frames(4)
	var fwd: Vector3 = game.cam.flat_forward()
	var right: Vector3 = game.cam.flat_right()
	for key in ["move_forward", "move_back", "move_left", "move_right"]:
		game.player.reset(Transform3D(Basis(), Vector3.ZERO))
		game.cam.yaw = 0.0
		await _frames(3)
		var p0: Vector3 = game.player.rig.global_position
		Input.action_press(key)
		for i in 30:
			game.player.step(1.0 / 60.0, game.level.arena)
		Input.action_release(key)
		var d: Vector3 = game.player.rig.global_position - p0
		d.y = 0.0
		if d.length() > 0.01:
			d = d.normalized()
		print("   %-12s 位移 %s  |fwd点乘=%.2f  right点乘=%.2f  |d|=%.2f" % [
			key, str(d.snapped(Vector3(0.01, 0.01, 0.01))), d.dot(fwd), d.dot(right),
			(game.player.rig.global_position - p0).length()])


func _enemy_reach() -> void:
	print("\n[2] 第一关小怪能不能走到玩家身边")
	game.level.start_level(0)
	await _frames(10)
	var mob = game.level.enemies[0]
	P.set_value("rules.god_mode", true)
	var p0: float = mob.dist_to_player()
	var mins := 999.0
	for i in 900:
		game.player.step(1.0 / 60.0, game.level.arena)
		mob.step(1.0 / 60.0, game.level.context())
		mins = minf(mins, mob.dist_to_player())
	print("   初始距离 %.1f m → 20 s 内最近 %.1f m（应 < 8）" % [p0, mins])


func _archer_range() -> void:
	print("\n[3] 远程怪保持距离")
	game.level.start_level(1)
	await _frames(10)
	var archer = game.level.archers[0]
	var dmin := 999.0
	var dmax := 0.0
	for i in 1200:
		game.player.step(1.0 / 60.0, game.level.arena)
		for e in game.level.enemies:
			e.step(1.0 / 60.0, game.level.context())
		var d: float = archer.dist_to_player()
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
	print("   20 s 距离范围 %.1f ~ %.1f m（keep_dist=20，应 > 12）" % [dmin, dmax])


func _blind_kill() -> void:
	print("\n[5] 背对敌人 + 回身斩 能不能打死它（第三人称）")
	game.level.start_level(0)
	await _frames(6)
	P.set_value("cam.mode", "first")
	P.set_value("move.facing_mode", "camera")
	var mob = game.level.enemies[0]
	var player = game.player
	player.reset(Transform3D(Basis(), Vector3.ZERO))
	await _frames(4)
	# 把怪放到正前方 6 m，相机朝前 → 应该被格挡
	mob.global_position = Vector3(0, 0, -4.6)
	game.cam.yaw = 0.0
	await _frames(4)
	var vis_front: bool = Vision.is_visible(game.cam.camera, mob.center(), mob.mark_radius())
	player._attack_from_input(Vector2.ZERO)
	var hp0: float = mob.hp
	for i in 90:
		player.step(1.0 / 60.0, game.level.arena)
		Combat.player_swing(player, game.level.enemies, game.cam, game.level.arena.get("walls", []))
	print("   正面朝它：可见=%s  hp %.0f→%.0f（应可见且不掉血）" % [str(vis_front), hp0, mob.hp])
	# 第一人称下转身 180°（怪在镜头背后）→ 回身斩
	game.cam.yaw = PI
	await _frames(40)
	print("   转身后 heading=%.2f（应≈3.14）" % player.rig.heading)
	var vis_back: bool = not Vision.fully_offscreen(game.cam.camera, mob.center(), mob.mark_radius())
	var hp1: float = mob.hp
	player._attack_from_input(Vector2(0, 1))
	print("   last_attack=%s yaw=%.2f hit窗口=[%.2f,%.2f]" % [player.last_attack,
		player.rig.attack_yaw, player.rig.attack_hit_from, player.rig.attack_hit_to])
	var evs: Array = []
	for i in 120:
		player.step(1.0 / 60.0, game.level.arena)
		evs.append_array(Combat.player_swing(player, game.level.enemies, game.cam,
			game.level.arena.get("walls", [])))
	print("   事件 = ", evs.size(), "  末尾 mob 位置=", str(mob.global_position),
		" 玩家=", str(player.rig.global_position), " heading=%.2f" % player.rig.heading)
	print("   转身背对：可见=%s  hp %.0f→%.0f（应不可见且掉血）" % [str(vis_back), hp1, mob.hp])


func _cam_inside() -> void:
	print("\n[6] 相机不会穿墙跑出场外（distance=26）")
	P.set_value("cam.distance", 26.0)
	for idx in 3:
		game.level.start_level(idx)
		await _frames(6)
		var b: AABB = game.level.arena["bounds"]
		var bad := 0
		var tested := 0
		for spot in [Vector3(0, 0, b.size.z * 0.5 - 4.0), Vector3(b.size.x * 0.5 - 4.0, 0, 0),
				Vector3(0, 0, -(b.size.z * 0.5 - 4.0)), Vector3(-(b.size.x * 0.5 - 4.0), 0, 0)]:
			game.player.reset(Transform3D(Basis(), spot))
			for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
				game.cam.yaw = yaw
				game.cam.step(1.0 / 60.0, game.level.arena)
				game.cam.step(1.0 / 60.0, game.level.arena)
				var p: Vector3 = game.cam.camera.global_position
				tested += 1
				if p.x < b.position.x - 0.5 or p.x > b.position.x + b.size.x + 0.5 \
						or p.z < b.position.z - 0.5 or p.z > b.position.z + b.size.z + 0.5:
					bad += 1
		print("   第 %d 关：%d/%d 个机位在场地外" % [idx + 1, bad, tested])
	P.set_value("cam.distance", 13.0)


func _boss_slam() -> void:
	print("\n[4] 大怪每轮重击落点")
	game.level.start_level(2)
	await _frames(10)
	P.set_value("boss.laser_trigger", "disabled")
	var boss = game.level.enemies[0]
	var player = game.player
	player.rig.global_position = boss.rig.global_position + Vector3(0, 0, 12)
	var slams: Array = []
	var was: bool = boss.slam_done
	for i in 2400:
		player.step(1.0 / 60.0, game.level.arena)
		boss.step(1.0 / 60.0, game.level.context())
		if boss.slam_done and not was:
			slams.append(snappedf(player.rig.global_position.distance_to(boss.rig.global_position), 0.1))
		was = boss.slam_done
	print("   重击 %d 次，落点距离 = %s（slam_radius=9，应逐步接近 <=9）" % [slams.size(), str(slams)])

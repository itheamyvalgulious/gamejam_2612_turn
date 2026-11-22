extends Node3D
## QA —— 回放要把「位置 + 旋转 + 缩放」全部还原。
##
## 用户报的问题：回放时大怪变成细柱子。原因是录制只存了位置+四元数，回放时
## `global_transform = Transform3D(Basis(quat), pos)` 把每个节点的缩放写成 1，
## 于是 rig ×2、torso ×1.45、head ×1.42 全被抹掉，机体被压成一根细柱。
##
## 跑法： godot --headless --path . res://scenes/qa_replay.tscn

const Qa = preload("res://tools/qa_lib.gd")
const MainScene = preload("res://main.tscn")

var q
var game
var boss


func _ready() -> void:
	q = Qa.new("qa_replay")
	P.set_value("rules.god_mode", true)
	P.set_value("boss.laser_trigger", "disabled")
	P.set_value("boss.scale", 2.0)
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.level.start_level(2)
	await get_tree().process_frame
	await get_tree().process_frame
	for e in game.level.enemies:
		if e.alive:
			boss = e
			break
	if boss == null:
		q.ok(false, "大怪关没有大怪")
		q.summary()
		get_tree().quit()
		return
	boss.global_position = game.player.rig.global_position + Vector3(0, 0, -9.0)
	await _t_body_scale()
	await _t_playback()
	q.summary()
	get_tree().quit()


func _t_body_scale() -> void:
	q.section("录制前的机体缩放")
	q.ok(absf(boss.rig.global_transform.basis.get_scale().x - 2.0) < 0.01,
		"大怪 rig ×2", "%.2f" % boss.rig.global_transform.basis.get_scale().x)
	q.ok(absf(boss.rig.torso.global_transform.basis.get_scale().x - 2.9) < 0.02,
		"torso ×1.45（×2 后 2.90）", "%.2f" % boss.rig.torso.global_transform.basis.get_scale().x)
	q.ok(absf(boss.rig.head.global_transform.basis.get_scale().x - 4.118) < 0.03,
		"head ×1.42（×2 后 4.12）", "%.2f" % boss.rig.head.global_transform.basis.get_scale().x)


func _t_playback() -> void:
	q.section("回放逐帧比对：位置 + 缩放都要对")
	# 录够帧数（大怪在正前 9 m 处，姿势/位置每帧都在变）
	for i in 30:
		await get_tree().process_frame
	var rep = game.replay
	rep.start()
	q.ok(rep.active, "进入回放")
	var list: Array = rep._nodes_for(boss.rig)
	var n: int = rep.stride
	var bulk: int = 1 + 24 * int(rep.NODE_FLOATS)
	var bad_pos := 0
	var bad_rot := 0
	var bad_scale := 0
	var checked := 0
	var rig_scale := 0.0
	var torso_scale := 0.0
	for i in 24:
		await get_tree().process_frame
		if not rep.active:
			break
		var fi: int = int(rep.play_frame)
		if fi <= 0 or fi >= rep.head:
			continue
		var p0: int = fi * n + 2 + bulk          # 敌人槽 1（大怪）的标记位
		if rep.buf[p0] < 0.5:
			continue
		for ni in list.size():
			var o: int = p0 + 1 + ni * rep.NODE_FLOATS
			var nd = list[ni]
			if not is_instance_valid(nd):
				continue
			var want_pos := Vector3(rep.buf[o], rep.buf[o + 1], rep.buf[o + 2])
			var want_quat := Quaternion(rep.buf[o + 3], rep.buf[o + 4], rep.buf[o + 5],
				rep.buf[o + 6]).normalized()
			var want_sc := Vector3(rep.buf[o + 7], rep.buf[o + 8], rep.buf[o + 9])
			var got: Transform3D = (nd as Node3D).global_transform
			var got_quat := got.basis.get_rotation_quaternion()
			checked += 1
			if want_pos.distance_to(got.origin) > 0.02:
				bad_pos += 1
			if absf(got_quat.dot(want_quat)) < 0.999:
				bad_rot += 1
			if (got.basis.get_scale() - want_sc).length() > 0.02:
				bad_scale += 1
			if ni == 0:
				rig_scale = got.basis.get_scale().x
			elif ni == 2:
				torso_scale = got.basis.get_scale().x
	q.ok(checked > 300, "比对样本足够", "%d 个节点帧" % checked)
	q.ok(bad_pos == 0, "回放位置完全一致", "%d 个不一致" % bad_pos)
	q.ok(bad_rot == 0, "回放旋转完全一致", "%d 个不一致" % bad_rot)
	q.ok(bad_scale == 0, "回放缩放完全一致（细柱子已修）", "%d 个不一致" % bad_scale)
	q.ok(absf(rig_scale - 2.0) < 0.02, "回放中大怪 rig 仍是 ×2", "%.2f" % rig_scale)
	q.ok(absf(torso_scale - 2.9) < 0.02, "回放中 torso 仍是 ×1.45", "%.2f" % torso_scale)

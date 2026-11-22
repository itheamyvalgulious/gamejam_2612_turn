extends Node3D
## 探针：混音开销 + 输出链路是否活着

func _ready() -> void:
	print("[audio] mix_rate=", AudioServer.get_mix_rate(), " driver=", AudioServer.get_driver_name())
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 4.4, 0)
	cam.rotation = Vector3.ZERO
	var node := Node3D.new()
	add_child(node)
	node.global_position = Vector3(-6, 1, -8)
	Snd.listener_pos = cam.global_position
	Snd.listener_basis = cam.global_transform.basis
	for i in 30:
		await get_tree().process_frame
	print("[audio] 空闲时混音 = %.3f ms/帧" % (float(Snd.last_mix_usec) / 1000.0))
	for k in ["step", "swing_light", "clang", "laser", "slam", "parry"]:
		Snd.play_at(k, Vector3(3, 1, 3))
	var ids: Array = []
	for i in 6:
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(-4 + i * 2, 1, -6)
		ids.append(Snd.loop_on("arrow_whistle", n))
	var times: Array = []
	for i in 240:
		await get_tree().process_frame
		times.append(float(Snd.last_mix_usec) / 1000.0)
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	print("[audio] 6 音源 + 循环音：平均 %.3f ms  中位 %.3f ms  p95 %.3f ms  峰值 %.3f ms  声部 %d"
		% [sum / times.size(), times[times.size() / 2], times[int(times.size() * 0.95)],
			times[times.size() - 1], Snd.voice_count()])
	print("[audio] ids=", ids, " by_id=", Snd._by_id.keys())
	for id in ids:
		Snd.stop(int(id))
	print("[audio] stop 后 by_id=", Snd._by_id.keys(), " voices=", Snd._voices.size())
	print("[audio] 逐个 stop 后 = ", Snd.voice_count())
	for i in 20:
		await get_tree().process_frame
	Snd.stop_all()
	for i in 20:
		await get_tree().process_frame
	print("[audio] stop_all 后声部 = ", Snd.voice_count(), " 缓存音色 = ", Snd.cached_kinds())
	# 端到端：真的推出去了非静音数据？
	Snd.play_at("clang", Vector3(0, 1, -3), {"gain": 1.0})
	var pk := 0.0
	for i in 30:
		await get_tree().process_frame
		pk = maxf(pk, Snd.last_peak)
	print("[audio] 端到端输出峰值 = %.3f（0 表示链路断了）" % pk)
	get_tree().quit()

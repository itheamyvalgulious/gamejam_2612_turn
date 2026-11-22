extends SceneTree
func _init() -> void:
	var kit = load("res://src/audio/synth.gd")
	print("[snd] 音色频谱性格（低频占比 <0.25 = 不像鼓）")
	var kinds := ["step", "swing_light", "swing_heavy", "arrow_whistle", "clang", "parry", "hit",
		"qi", "laser", "slam", "death", "arrow_hit"]
	for k in kinds:
		var buf: PackedFloat32Array = kit.samples(k, 0)
		var st: Dictionary = kit.stats(buf)
		print("   %-14s 峰 %.2f  RMS %.3f  低频占比 %.2f  时长 %.2fs" % [k, st["peak"], st["rms"],
			st["low_ratio"], float(st["n"]) / 12000.0])
	quit()

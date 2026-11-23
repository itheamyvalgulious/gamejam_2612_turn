extends SceneTree

const SynthAct = preload("res://runtime/audio/act/synth.gd")

func _init() -> void:
	for kind in ["step", "swing_light", "swing_heavy", "arrow_whistle", "clang",
			"arrow_hit", "hit", "qi", "sentry_charge", "laser", "slam", "death",
			"player_death", "parry", "chime", "ping"]:
		var times: Array = []
		for v in 4:
			var t0 := Time.get_ticks_usec()
			var buf: PackedFloat32Array = SynthAct.samples(kind, v)
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
		print("%-14s %s" % [kind, times])
	quit()

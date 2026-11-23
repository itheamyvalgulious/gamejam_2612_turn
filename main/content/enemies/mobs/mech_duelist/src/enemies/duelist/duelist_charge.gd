extends RefCounted
## Timing begins when the support palm is planted. The same clock drives picture and sound.

const SynthKit = preload("res://src/audio/synth.gd")
const DURATION := 2.0
const BLADE_FILLED_AT := 1.14
const QUIET_AT := 1.85
const FLASH_DURATION := 0.14
const AUDIO_DURATION := DURATION + 0.32


static func load_at(age: float) -> float:
	return smoothstep(1.05, 1.805, age) * (1.0 - smoothstep(DURATION + FLASH_DURATION, DURATION + 0.85, age))


static func vibration_at(age: float) -> Vector3:
	var active := smoothstep(0.48, 1.755, age) * (1.0 - smoothstep(1.77, QUIET_AT, age))
	var t := maxf(0.0, age - 0.48) * 2.0
	var phase := TAU * (6.0 * t + 1.52 * t * t)
	return Vector3(0.46 * cos(phase), 0.0, 0.72 * sin(phase)) * active


static func red_flash_at(age: float) -> float:
	if age < DURATION or age >= DURATION + FLASH_DURATION:
		return 0.0
	return 1.0 - smoothstep(DURATION + 0.054, DURATION + FLASH_DURATION, age)


static func make_sound() -> AudioStreamWAV:
	var drive := [[0.0, 0.0], [0.15, 0.05], [0.55, 0.26], [1.10, 0.51], [1.78, 0.91], [QUIET_AT, 0.0]]
	var layers := [
		{"osc": "sine", "f0": 79, "f1": 29, "filt": "none", "gain": 0.38,
			"env": [[0.0, 0.0], [0.013, 1.0], [0.105, 0.28], [0.24, 0.0]]},
		{"osc": "noise", "f0": 490, "f1": 490, "q": 0.9, "gain": 0.38,
			"env": [[0.0, 0.0], [0.005, 1.0], [0.085, 0.15], [0.14, 0.0]]},
		{"osc": "sine", "f0": 42, "f1": 134, "fmode": "exp", "filt": "none", "gain": 0.32, "env": drive},
		{"osc": "saw", "f0": 73, "f1": 218, "fmode": "exp", "filt": "lp", "q": 1.6, "gain": 0.26, "env": drive},
		{"osc": "sine", "f0": 260, "f1": 668, "filt": "none", "gain": 0.095, "env": drive},
		{"osc": "noise", "f0": 2070, "f1": 1780, "q": 3.0, "gain": 0.50,
			"env": [[DURATION, 0.0], [DURATION + 0.007, 1.0], [DURATION + 0.056, 0.21], [DURATION + 0.19, 0.0]]},
		{"osc": "sine", "f0": 166, "f1": 88, "filt": "none", "gain": 0.32,
			"env": [[DURATION, 0.0], [DURATION + 0.009, 1.0], [DURATION + 0.13, 0.32], [AUDIO_DURATION, 0.0]]},
	]
	return SynthKit.to_wav(SynthKit.render_layers(AUDIO_DURATION, layers, 40821))

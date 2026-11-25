extends Node
## Optional recordings for enemy cues. Each stream is resolved once per game run.

const ENEMIES := {
	"duelist": "mobs/mech_duelist",
	"wheel": "mobs/wheel_sentry",
	"fold": "bosses/phase_boss",
}
const FORMATS := ["wav", "ogg", "mp3"]
const EMITTER_GROUP := &"turn_enemy_audio_emitter"
var _streams: Dictionary = {}


func stream(enemy: String, cue: String, loop := false) -> AudioStream:
	var key := "%s/%s:%s" % [enemy, cue, loop]
	if not _streams.has(key):
		_streams[key] = _find_stream(enemy, cue, loop)
	return _streams[key]


func _find_stream(enemy: String, cue: String, loop: bool) -> AudioStream:
	var folder := "res://runtime/enemies/%s/design/assets/audio/" % ENEMIES[enemy]
	for format: String in FORMATS:
		var path := "%s%s.%s" % [folder, cue, format]
		if not ResourceLoader.exists(path, "AudioStream"):
			continue
		var asset := ResourceLoader.load(path, "AudioStream") as AudioStream
		if asset == null or asset.get_length() <= 0.0:
			continue
		# A shared recording can be a loop in one cue and a one-shot in another.
		var sample := asset.duplicate() as AudioStream
		if sample is AudioStreamWAV:
			sample.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
			if loop:
				sample.loop_begin = 0
				sample.loop_end = roundi(sample.get_length() * sample.mix_rate)
		elif sample is AudioStreamOggVorbis or sample is AudioStreamMP3:
			sample.loop = loop
			sample.loop_offset = 0.0
		return sample
	return null


func play_at(owner: Node3D, enemy: String, cue: String, kind: String, at: Vector3,
		options: Dictionary, sound_bus: Node) -> bool:
	var sample := stream(enemy, cue)
	if sample == null:
		return false
	if sound_bus.master <= 0.001:
		return true
	var player := AudioStreamPlayer3D.new()
	player.stream = sample
	player.add_to_group(EMITTER_GROUP)
	owner.add_child(player)
	player.top_level = true
	player.global_position = at
	mix(player, sound_bus, kind, float(options.get("gain", 1.0)), float(options.get("rate", 1.0)))
	player.finished.connect(player.queue_free)
	player.play()
	return true


func mix(player: AudioStreamPlayer3D, sound_bus: Node, kind: String, gain: float, rate: float) -> void:
	player.volume_db = linear_to_db(maxf(0.00001, gain * sound_bus.master * sound_bus._kind_gain(kind)))
	player.pitch_scale = rate
	player.max_distance = sound_bus.max_dist if sound_bus.spatial else 0.0
	player.panning_strength = 1.0 if sound_bus.spatial else 0.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE if sound_bus.spatial \
		else AudioStreamPlayer3D.ATTENUATION_DISABLED


func stop_one_shots(owner: Node3D) -> void:
	for child in owner.get_children():
		if child.is_in_group(EMITTER_GROUP):
			child.stop()
			child.queue_free()

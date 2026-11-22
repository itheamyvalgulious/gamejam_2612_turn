extends Node3D
## Deterministic frame-strip renderer for ARC // GRINDER v3.
##
##   DISPLAY=:10 godot --path . res://scenes/v3_shots.tscn
##
## Writes renders/v3/frames/<clip>/<view>_<index>.png at 960x540.

const STUDIO := preload("res://scenes/studio.tscn")
const CLIPS := ["idle", "run", "attack1", "attack2", "block"]
const VIEWS := {
	"three_q": {"yaw": -36.0, "pitch": 7.0, "dist": 3.55, "target": Vector3(0, 0.92, 0)},
	"front": {"yaw": 0.0, "pitch": 5.0, "dist": 3.45, "target": Vector3(0, 0.92, 0)},
	"side": {"yaw": 270.0, "pitch": 5.0, "dist": 3.45, "target": Vector3(0, 0.92, 0)},
	"back": {"yaw": 180.0, "pitch": 7.0, "dist": 3.45, "target": Vector3(0, 0.92, 0)},
}
const NFRAMES := 16

var studio
var ch
var out_dir := "res://renders/v3/frames"
var _nframes := NFRAMES


func _ready() -> void:
	get_window().size = Vector2i(960, 540)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	studio = STUDIO.instantiate()
	add_child(studio)
	await _frames(6)
	studio.ui_root.visible = false
	if studio._overlay:
		studio._overlay.visible = false
	studio._shot_mode = true
	ch = studio.character
	ch.set_param("lens_track", 0.0)
	var only := OS.get_environment("V3_ONLY")
	var views := OS.get_environment("V3_VIEWS")
	if views != "":
		var keep: Array = []
		for v in views.split(",", false):
			if VIEWS.has(v):
				keep.append(v)
		for v in VIEWS.keys():
			if not (v in keep):
				VIEWS.erase(v)
	if OS.get_environment("V3_FRAMES") != "":
		_nframes = int(OS.get_environment("V3_FRAMES"))
	for clip in CLIPS:
		if only != "" and not (clip in only.split(",", false)):
			continue
		ch.set_block_threat(0.0, 0.0)
		await _render_clip(clip)
	print("[v3_shots] done")
	get_tree().quit(0)


func _render_clip(clip: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir.path_join(clip)))
	var dur: float = ch.anim.duration(clip)
	for view in VIEWS:
		var vd: Dictionary = VIEWS[view]
		if clip == "attack1" or clip == "attack2":
			studio.set_view(vd["yaw"], vd["pitch"], 4.15, Vector3(0, 1.08, 0))
		else:
			studio.set_view(vd["yaw"], vd["pitch"], vd["dist"], vd["target"])
		for i in _nframes:
			var t := dur * float(i) / float(_nframes - 1)
			ch.current_anim = clip
			ch._playing = false
			ch._loop = false
			ch._t = t
			ch._prev_t = t
			ch._manual = false
			ch._fade_t = 0.0
			ch._apply_now(t)
			# locomotion is deterministic per still: run advances the belts at
			# run_speed, every other clip holds them still
			var travel := 0.0
			if clip == "run":
				travel = ch.get_param("run_speed") * t
			ch.set_track_travel(travel, travel)
			ch._update_fx(0.016)
			await _frames(1)
			var path: String = out_dir.path_join(clip).path_join("%s_%02d.png" % [view, i])
			await studio.snap(path)
	print("  rendered ", clip, " x", _nframes, " x", VIEWS.size())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
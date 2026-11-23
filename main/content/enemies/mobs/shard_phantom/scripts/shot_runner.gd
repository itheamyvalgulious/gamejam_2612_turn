extends Node3D
## Shot runner: renders a deterministic contact sheet for visual review.
##
## Usage (from the project root):
##   DISPLAY=:10 godot --path . res://scenes/shots.tscn
##
## Env:
##   SHOT_DIR      output dir (default res://renders/contact)
##   SHOT_ANIMS    comma list, e.g. "idle,run,attack"
##   SHOT_TIMES    comma list of t/duration fractions, default "0,0.3,0.55,0.8"
##   SHOT_VIEWS    comma list of view ids: front,three_q,side,back,low,top
##   SHOT_W/SHOT_H window size (default 1600x900)
##   SHOT_OVERLAY  1 to keep the screen-grade overlay (default 1 in-app)

const STUDIO := preload("res://scenes/studio.tscn")

var studio: Studio

const VIEWS := {
	"three_q": {"yaw": 34.0, "pitch": 8.0, "dist": 4.9, "target": Vector3(0, 0.95, 0)},
	"front": {"yaw": 0.0, "pitch": 5.0, "dist": 4.6, "target": Vector3(0, 0.95, 0)},
	"side": {"yaw": 90.0, "pitch": 5.0, "dist": 4.6, "target": Vector3(0, 0.95, 0)},
	"back": {"yaw": 180.0, "pitch": 7.0, "dist": 4.8, "target": Vector3(0, 0.95, 0)},
	"low": {"yaw": 28.0, "pitch": -4.0, "dist": 4.4, "target": Vector3(0, 0.75, 0)},
	"top": {"yaw": 20.0, "pitch": 50.0, "dist": 5.6, "target": Vector3(0, 0.90, 0)},
}


func _ready() -> void:
	var out_dir := OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "res://renders/contact"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	studio = STUDIO.instantiate()
	add_child(studio)
	await _frames(4)
	studio.ui_root.visible = false
	studio._shot_mode = true
	var ch: Node3D = studio.character
	if ch == null:
		push_error("[shots] no character")
		get_tree().quit(1)
		return

	var anims := _env_list("SHOT_ANIMS", "")
	var all_anims: PackedStringArray = ch.anim_names()
	var pick: PackedStringArray = PackedStringArray()
	if anims.is_empty():
		pick = all_anims
	else:
		for a in anims:
			if a in all_anims:
				pick.append(a)

	var times := _env_floats("SHOT_TIMES", [0.0, 0.35, 0.6, 0.85])
	var view_ids := _env_list("SHOT_VIEWS", "three_q,front,side")
	var index_lines: PackedStringArray = PackedStringArray()
	var count := 0
	for anim in pick:
		ch.play_anim(anim)
		ch.set_playing(false)
		var dur: float = maxf(ch.anim_duration(), 0.001)
		for v in view_ids:
			if not VIEWS.has(v):
				continue
			var vd: Dictionary = VIEWS[v]
			studio.set_view(vd["yaw"], vd["pitch"], vd["dist"], vd["target"])
			for tf in times:
				var t: float = clampf(tf, 0.0, 1.0) * dur
				ch.set_anim_time(t)
				await _frames(2)
				var safe := "%s__%s__%03d.png" % [anim, v, int(tf * 100.0)]
				var path: String = out_dir.path_join(safe)
				await studio.snap(path)
				index_lines.append("%s  anim=%s t=%.3f view=%s" % [safe, anim, t, v])
				count += 1
	print("[shots] rendered %d stills into %s" % [count, out_dir])
	var f := FileAccess.open(out_dir.path_join("index.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(index_lines))
		f.close()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _env_list(key: String, fallback: String) -> PackedStringArray:
	var s := OS.get_environment(key)
	if s == "":
		s = fallback
	var out := PackedStringArray()
	for p in s.split(",", false):
		out.append(p.strip_edges())
	return out


func _env_floats(key: String, fallback: Array) -> Array:
	var s := OS.get_environment(key)
	if s == "":
		return fallback
	var out: Array = []
	for p in s.split(",", false):
		out.append(float(p))
	return out if not out.is_empty() else fallback
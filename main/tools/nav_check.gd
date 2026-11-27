extends SceneTree
## 导航元信息离线校验：对每个关卡建 arena + NavField，打印
## region/line/obstacle 计数、连通分量、采样的 nav 高度与寻路冒烟测试。
##
## 用法：godot --headless --path main -s tools/nav_check.gd [--level=5]
## 需要先 `python3 main/tools/prepare_game.py`（runtime 资源是构建产物）。

const NavField = preload("res://core/nav_field.gd")

## 每关：{名称, arena 脚本(runtime), build 方式, 采样点}
const LEVELS := [
	{"name": "霓虹窄巷", "arena": "res://runtime/levels/act/arena/arena.gd",
		"call": "kind:alley", "samples": [Vector3(0, 0, 0), Vector3(10, 0, 6)]},
	{"name": "雨夜广场", "arena": "res://runtime/levels/act/arena/arena.gd",
		"call": "kind:plaza", "samples": [Vector3(0, 0, 0), Vector3(-12, 0, 8)]},
	{"name": "灯墙之厅", "arena": "res://runtime/levels/shadow_chamber/arena/arena.gd",
		"call": "kind:chamber", "samples": [Vector3(0, 0, 0)]},
	{"name": "货舱02", "arena": "res://runtime/levels/cargo/cargo_hold2/arena.gd",
		"call": "empty", "samples": [Vector3(0, 0, 25), Vector3(0, 0, -25)]},
	{"name": "霓虹街区", "arena": "res://runtime/levels/city/encounter/arena.gd",
		"call": "empty", "samples": [Vector3(0, 0, 25), Vector3(-12, 0, -6)]},
	{"name": "坠击中庭", "arena": "res://runtime/levels/galleria/encounter/arena.gd",
		"call": "flag:false", "samples": [Vector3(0, 0, 10), Vector3(29, 0, -10), Vector3(29, 8, 18)]},
	{"name": "仓库", "arena": "res://runtime/levels/warehouse/arena/warehouse_arena.gd",
		"call": "origin", "samples": [Vector3(0, 0, 2), Vector3(39.4, 4.4, 10), Vector3(39.4, 8.8, -5.2)]},
	{"name": "回廊实验舱", "arena": "res://runtime/levels/panopticon/arena/panopticon_arena.gd",
		"call": "origin", "samples": [Vector3(0, 0, 24)]},
	{"name": "病房夜班", "arena": "res://runtime/levels/ward/arena/ward_arena.gd",
		"call": "origin", "samples": [Vector3(10, 0, 4.9)]},
	{"name": "坠击中庭高低差", "arena": "res://runtime/levels/galleria/encounter/arena.gd",
		"call": "flag:true", "samples": [Vector3(0, 8, 25), Vector3(29, 0, -10)]},
	{"name": "三号船坞", "arena": "res://runtime/levels/hangar/arena/hangar_arena.gd",
		"call": "origin", "samples": [Vector3(0, 0, 0), Vector3(-12, 0, 39)]},
]


func _init() -> void:
	# 延后一帧：autoload（TurnSession 等）要先注册完，arena 脚本的编译
	# 才能解析这些全局符号。
	call_deferred("_run")


func _run() -> void:
	var only := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			only = int(arg.split("=")[1])
	var failures := 0
	for i in LEVELS.size():
		if only >= 0 and i != only:
			continue
		failures += _check(i, LEVELS[i])
	print("==== nav_check: %s ====" % ("FAIL %d" % failures if failures else "OK"))
	quit(1 if failures else 0)


func _check(idx: int, entry: Dictionary) -> int:
	var errors := 0
	var script: GDScript = load(String(entry["arena"]))
	if script == null:
		print("[%d] %s — arena script failed to load" % [idx, entry["name"]])
		return 1
	var arena: Dictionary
	match String(entry["call"]):
		"kind:alley":
			arena = script.build("alley", Vector3.ZERO)
		"kind:plaza":
			arena = script.build("plaza", Vector3.ZERO)
		"kind:chamber":
			arena = script.build("chamber", Vector3.ZERO)
		"flag:true":
			arena = script.build(true)
		"flag:false":
			arena = script.build(false)
		"origin":
			arena = script.build(Vector3.ZERO)
		_:
			arena = script.build()
	if not arena is Dictionary or arena.is_empty() or not arena.has("bounds"):
		print("[%d] %s — arena.build() returned bad dict" % [idx, entry["name"]])
		return 1
	var spec: Dictionary = {}
	for m in script.get_script_method_list():
		if String(m.get("name", "")) == "nav_spec":
			spec = script.nav_spec(arena)
	var nav = NavField.build(arena, spec)
	var st: Dictionary = nav.stats()
	var conn: Dictionary = nav.connectivity()
	print("[%d] %-9s regions=%d lines=%d obstacles=%d components=%d" % [
		idx, entry["name"], st["regions"], st["lines"], st["obstacles"], conn["components"]])
	if st["regions"] == 0:
		print("    ERROR: no regions")
		errors += 1
	if conn["components"] > 1:
		print("    WARN: %d disconnected region groups: %s" % [
			conn["components"], conn["groups"]])
	for s in entry["samples"]:
		var h: float = nav.height_at(s)
		var r: int = nav.region_at(s)
		var l: int = nav.stair_at(s)
		print("    sample %-28s h=%7.3f region=%d line=%d" % [s, h, r, l])
		if r < 0 and l < 0:
			print("    WARN: no nav support at %s" % s)
	# 冒烟寻路：第一个采样点 → 最后一个采样点。
	var samples: Array = entry["samples"]
	if samples.size() >= 2:
		var pts: Array = nav.path(samples[0], samples[-1], 1.2)
		print("    path %s → %s : %d waypoints" % [samples[0], samples[-1], pts.size()])
	arena["node"].queue_free()
	return errors

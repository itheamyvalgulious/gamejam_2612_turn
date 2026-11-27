extends Node

const Catalog = preload("res://core/level_catalog.gd")
# 冒烟：连续过几关确认场景能加载、敌人能生成
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for id in ["rain_plaza", "cargo_hold_02", "warehouse", "neon_district", "galleria_height_test"]:
		var idx := Catalog.index_for_id(id)
		TurnSession.open_level(idx)
		while TurnSession.active_level_index() != idx or get_tree().current_scene == null:
			await get_tree().process_frame
		for i in 60:
			await get_tree().process_frame
		var level = get_tree().current_scene.get("level")
		var names := ""
		var elist: Array = level.enemies if level != null else []
		for e in elist:
			names += "%s(%s) " % [e.kind, "alive" if e.alive else "dead"]
		print("[smoke] level %d enemies: %s" % [idx, names])
	get_tree().quit()

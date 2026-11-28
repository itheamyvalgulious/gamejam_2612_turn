extends Node
## 临时直入：打开「轨道船背」。

const Catalog := preload("res://core/level_catalog.gd")


func _ready() -> void:
	TurnSession.open_level(Catalog.index_for_id("space_hull"))

extends Node
## 临时直入：打开「暮色楼顶」。

const Catalog := preload("res://core/level_catalog.gd")


func _ready() -> void:
	TurnSession.open_level(Catalog.index_for_id("rooftop"))

extends RefCounted

const LEVELS := [
	["货舱 02", "适应义体，击倒巡检哨兵，沿指引撤离。", "cargo", "", [], "cargo_hold_02"],
	["坠击中庭", "从高台跳下，落地前按左键发动范围坠击。", "galleria", "", [], "galleria"],
	["回廊实验舱", "绕中央玻璃罐，经环形长廊抵达检修台。", "panopticon", "", [], "panopticon", "room_shared"],
	["仓库", "沿货架、集装箱和环廊穿过装卸区。", "warehouse", "", [], "warehouse", "room_shared"],
	["霓虹窄巷", "移开视线，从侧面攻击。", "act", "", ["--act-level=1"], "neon_alley"],
	["雨夜广场", "小激光可弹反。看到长束预警后横移。", "act", "", ["--act-level=2"], "rain_plaza"],
	["灯墙之厅", "持续注视折相会加快虚化充能。", "shadow_chamber", "", [], "shadow_chamber"],
	["霓虹街区", "沿街边小巷绕到掩体后方，肃清街区。", "city", "", [], "neon_district"],
	["病房 · 夜班", "穿过病床区、中央隔墙和镜面走廊。", "ward", "", [], "night_ward", "room_shared"],
	["坠击中庭 · 高低差", "下层有一名刀客。可在右侧楼梯利用高低差交战。", "galleria", "", ["--galleria-height-test"], "galleria_height_test"],
	["三号船坞", "空间样段：沿地面黄色走道绕到东南气闸。甲板中央是 Boss 占位。", "hangar", "", [], "hangar", "room_shared"],
]

static func level_count() -> int:
	return LEVELS.size()


static func get_entry(index: int) -> Array:
	return LEVELS[index]


static func level_id(index: int) -> String:
	return LEVELS[index][5]


static func index_for_id(id: String) -> int:
	for index in level_count():
		if level_id(index) == id:
			return index
	return -1


static func services_for(index: int) -> String:
	var entry := get_entry(index)
	return String(entry[6] if entry.size() > 6 else entry[2])


static func play_hint(index: int) -> String:
	return LEVELS[index][1]


static func preview_id(index: int) -> String:
	var entry := get_entry(index)
	return String(entry[7]) if entry.size() > 7 else level_id(index)

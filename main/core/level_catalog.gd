extends RefCounted

const LEVELS := [
	["霓虹窄巷", "移开视线，从侧面攻击。", "act", "", ["--act-level=1"], "neon_alley"],
	["雨夜广场", "迎战近战与远程敌人，试着弹反射来的攻击。", "act", "", ["--act-level=2"], "rain_plaza"],
	["灯墙之厅", "挑战折相，留意观察带来的虚化充能。", "shadow_chamber", "", [], "shadow_chamber"],
	["货舱 02", "利用集装箱遮挡，趁位移敌人重组时接近。", "cargo", "", [], "cargo_hold_02"],
	["霓虹街区", "沿街边小巷绕到掩体后方，肃清街区。", "city", "", [], "neon_district"],
	["坠击中庭", "从高台跳下，落地前按左键发动范围坠击。", "galleria", "", [], "galleria"],
	["仓库", "沿货架、集装箱和环廊穿过装卸区。敌人待配置。", "warehouse", "", [], "warehouse", "room_shared"],
	["回廊实验舱", "绕中央玻璃罐，经环形长廊抵达检修台。敌人待配置。", "panopticon", "", [], "panopticon", "room_shared"],
	["病房 · 夜班", "穿过病床区、中央隔墙和镜面走廊。敌人待配置。", "ward", "", [], "night_ward", "room_shared"],
]

static func level_count() -> int:
	return LEVELS.size()


static func get_entry(index: int) -> Array:
	return LEVELS[index]


static func services_for(index: int) -> String:
	var entry := get_entry(index)
	return String(entry[6] if entry.size() > 6 else entry[2])

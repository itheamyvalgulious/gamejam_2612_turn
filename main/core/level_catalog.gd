extends RefCounted

const BATTLE := [
	["霓虹窄巷", "移开视线，从侧面攻击。", "act", "", ["--act-level=1"], "neon_alley"],
	["雨夜广场", "迎战近战与远程敌人，试着弹反射来的攻击。", "act", "", ["--act-level=2"], "rain_plaza"],
	["灯墙之厅", "挑战折相，留意观察带来的虚化充能。", "shadow_chamber", "", [], "shadow_chamber"],
	["货舱 02", "利用集装箱遮挡，趁位移敌人重组时接近。", "cargo", "", [], "cargo_hold_02"],
	["霓虹街区", "沿街边小巷绕到掩体后方，肃清街区。", "city", "", [], "neon_district"],
	["坠击中庭", "从高台跳下，落地前按左键发动范围坠击。", "galleria", "", [], "galleria"],
]

const EXPLORE := [
	["仓库", "沿货架、集装箱和环廊探索装卸区。", "lab", "", ["--warehouse"], "warehouse"],
	["回廊实验舱", "探索中央玻璃罐、环形长廊和检修台。", "lab", "", ["--panopticon"], "panopticon"],
	["病房 · 夜班", "探索隔帘后的病床、中央隔墙和镜面走廊。", "lab", "", ["--ward"], "night_ward"],
]

static func level_count() -> int:
	return BATTLE.size() + EXPLORE.size()


static func get_entry(index: int) -> Array:
	if index < BATTLE.size():
		return BATTLE[index]
	return EXPLORE[index - BATTLE.size()]

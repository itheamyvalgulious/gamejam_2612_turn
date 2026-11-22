extends Node
## P — every tunable "feel" parameter of the demo.
##
## One flat registry of typed entries, driven by the ~ overlay and read by every
## gameplay system.  Values are live-editable, clamp to their spec range and are
## persisted to user://actdemo_params.json.
##
## 单位约定（重要）：**这里的每一个长度都是真实米**（米 / 米每秒 / 米每秒²）。
## 仿真内部走「世界单位」，1 世界单位 = 0.547 m —— 见 src/core/units.gd。
## 换算只发生在 getf()（米 → 世界单位）与 ~ 面板显示（直接用存档里的米）两处。
## 所以：机甲高 2.5 m、小怪 2.5 m、大怪 5.0 m，所有距离参数与它们同一把尺子。
##
## Entry shape:
##   {path, group, label, type: float|int|bool|enum, default, min, max, step,
##    unit, note, options:[{v,label}], len}
##   len = true 表示这一项是长度量纲（米 / 米每秒 / 米每秒²），读取时换算成世界单位

signal changed(path: String, value: Variant)
signal bulk_changed()

const Units = preload("res://src/core/units.gd")
const SAVE_PATH := "user://actdemo_params.json"
## 这些是「调试开关」，不写进存档（否则下次启动会带着无敌/慢动作）
const NO_SAVE := ["rules.god_mode", "rules.time_scale"]
## 长度量纲的单位：这些参数的 default/min/max/step 存的是米
const LEN_UNITS := ["m", "m/s", "m/s²"]

var _defs: Array = []
var _by_path: Dictionary = {}
var _vals: Dictionary = {}
var _groups: Array = []


func _ready() -> void:
	_build_defs()
	load_from_disk()


# ------------------------------------------------------------------ schema
func _f(path: String, group: String, label: String, dflt: float, mn: float, mx: float,
		step: float, unit := "", note := "") -> void:
	_add({"path": path, "group": group, "label": label, "type": "float", "default": dflt,
		"min": mn, "max": mx, "step": step, "unit": unit, "note": note,
		"len": LEN_UNITS.has(unit)})


func _i(path: String, group: String, label: String, dflt: int, mn: int, mx: int, unit := "", note := "") -> void:
	_add({"path": path, "group": group, "label": label, "type": "int", "default": dflt,
		"min": mn, "max": mx, "step": 1, "unit": unit, "note": note, "len": false})


func _b(path: String, group: String, label: String, dflt: bool, note := "") -> void:
	_add({"path": path, "group": group, "label": label, "type": "bool", "default": dflt,
		"min": 0, "max": 0, "step": 0, "unit": "", "note": note, "len": false})


func _e(path: String, group: String, label: String, dflt: String, options: Array, note := "") -> void:
	_add({"path": path, "group": group, "label": label, "type": "enum", "default": dflt,
		"min": 0, "max": 0, "step": 0, "unit": "", "options": options, "note": note, "len": false})


func _add(d: Dictionary) -> void:
	if not _groups.has(d["group"]):
		_groups.append(d["group"])
	_defs.append(d)
	_by_path[d["path"]] = d
	_vals[d["path"]] = d["default"]


func _build_defs() -> void:
	# ---------------------------------------------------------------- 移动
	var G := "移动"
	_f("move.walk_speed", G, "走速", 2.19, 0.0, 16.4, 0.05, "m/s")
	_f("move.run_speed", G, "跑速（上限）", 5.20, 0.0, 21.9, 0.05, "m/s")
	_f("move.sprint_speed", G, "冲刺跑速度", 7.66, 0.0, 27.4, 0.05, "m/s")
	_f("move.accel", G, "加速度", 13.1, 0.0, 109.0, 0.3, "m/s²")
	_f("move.decel", G, "减速度", 25.2, 0.0, 109.0, 0.3, "m/s²")
	_f("move.turn_rate", G, "转向速率", 14.0, 1.0, 40.0, 0.5, "", "数值越大转身越快")
	_f("move.air_control", G, "空中操控", 0.45, 0.0, 1.0, 0.01)
	_f("move.attack_drag", G, "攻击时移动衰减", 0.10, 0.0, 1.0, 0.01, "", "攻击中允许保留多少移动速度")
	_b("move.auto_sprint", G, "持续移动后自动提速", true, "连续移动 1.4 s 后从跑速提到冲刺跑速度")
	_e("move.facing_mode", G, "朝向模式", "camera",
		[{"v": "camera", "label": "相机前方"}, {"v": "movement", "label": "移动方向"}])

	# ---------------------------------------------------------------- 跳跃
	G = "跳跃"
	_f("jump.height", G, "跳跃高度", 1.50, 0.0, 11.0, 0.03, "m", "直接给高度，起跳速度由重力反算")
	_f("jump.gravity", G, "重力", 10.0, 1.0, 49.0, 0.3, "m/s²")
	_f("jump.takeoff_time", G, "起跳前摇", 0.10, 0.0, 0.6, 0.01, "s")
	_f("jump.land_time", G, "落地硬直", 0.22, 0.0, 1.2, 0.01, "s")
	_f("jump.air_steer", G, "空中转向", 0.55, 0.0, 2.0, 0.01, "rad/s")
	_f("jump.coyote_time", G, "落地起跳宽容", 0.10, 0.0, 0.4, 0.01, "s", "落地后仍允许起跳的时间窗")
	_f("jump.buffer_time", G, "跳跃输入缓冲", 0.12, 0.0, 0.4, 0.01, "s")
	_b("jump.double_jump", G, "允许二段跳", false)

	# ---------------------------------------------------------------- 冲刺
	G = "冲刺"
	_f("dash.distance", G, "冲刺距离", 3.00, 0.0, 21.9, 0.05, "m")
	_f("dash.duration", G, "冲刺时长", 0.28, 0.05, 1.5, 0.01, "s")
	_f("dash.cooldown", G, "冲刺冷却", 0.50, 0.0, 3.0, 0.01, "s")
	_f("dash.invuln", G, "冲刺无敌帧", 0.0, 0.0, 1.0, 0.01, "s")

	# ---------------------------------------------------------------- 攻击
	G = "攻击"
	# 每项：id, 中文名, 总时长, 前摇, 后摇, 伤害, 前冲(m), 击退(m), 命中停顿(s)
	var atk := [
		["slash_fwd", "正前斩", 0.70, 0.15, 0.24, 1.0, 0.60, 1.09, 0.05],
		["slash_left", "左斩", 0.55, 0.05, 0.25, 1.0, 0.19, 1.09, 0.05],
		["slash_right", "右斩", 0.55, 0.05, 0.25, 1.0, 0.19, 1.09, 0.05],
		["slash_back", "回身斩", 0.50, 0.02, 0.20, 1.0, 0.05, 1.31, 0.05],
		["heavy", "重斩", 1.30, 0.46, 0.34, 1.0, 0.55, 2.46, 0.09],
		["spin", "回旋斩", 1.10, 0.15, 0.50, 1.0, 0.00, 1.64, 0.06],
	]
	for a in atk:
		var p := "attack.%s" % a[0]
		_f(p + ".duration", G, "%s · 总时长" % a[1], a[2], 0.1, 4.0, 0.01, "s",
			"总时长 = 前摇 + 判定 + 后摇；动作动画会被压进这条时间轴")
		_f(p + ".windup", G, "%s · 前摇" % a[1], a[3], 0.0, 2.0, 0.01, "s")
		_f(p + ".recovery", G, "%s · 后摇" % a[1], a[4], 0.0, 2.0, 0.01, "s")
		_f(p + ".damage", G, "%s · 伤害" % a[1], a[5], 0.0, 999.0, 1.0)
		_f(p + ".lunge", G, "%s · 前冲距离" % a[1], a[6], 0.0, 4.4, 0.01, "m")
		_f(p + ".knockback", G, "%s · 击退" % a[1], a[7], 0.0, 11.0, 0.05, "m")
		_f(p + ".hitstop", G, "%s · 命中停顿" % a[1], a[8], 0.0, 0.3, 0.005, "s")

	# ---------------------------------------------------------------- 弹反 / 格挡
	G = "弹反"
	_f("parry.window", G, "弹反判定区间", 0.24, 0.02, 1.0, 0.01, "s",
		"按下后这段时间内可以起手架招（刀还在架着就一直挡得住）")
	_f("parry.cooldown", G, "弹反冷却", 0.35, 0.0, 2.0, 0.01, "s")
	_f("parry.reflect_speed", G, "弹回速度倍率", 1.5, 0.2, 5.0, 0.05)
	_b("parry.melee_block", G, "近战也能格挡（剑挡剑）", true,
		"两把刀的真几何交在一起就架住：免伤 + 被击退")
	_f("parry.pose_time", G, "收势时长", 0.32, 0.05, 1.2, 0.01, "s", "窗口过后把刀放回自然位的时间")
	_f("parry.radius", G, "拦截规划半径", 3.83, 0.55, 11.0, 0.05, "m",
		"这个球内的飞行物会被纳入拦截规划（0.547 m/u × 7 u）")
	_f("parry.arc_deg", G, "拦截夹角上限", 160.0, 30.0, 360.0, 5.0, "°",
		"飞行物「冲我来」的最大夹角：正对 180° 才把背后飞来的也架")
	_b("parry.auto_aim", G, "按刀路自动拦截", true,
		"读威胁的下一个位置，规划一条机械臂路径把刀送到那里；关掉 = 只把刀举起来")
	_f("parry.plan_lead", G, "提前规划时间", 0.45, 0.05, 1.5, 0.01, "s",
		"威胁还有这么久到达时，就开始挥刀过去")
	_f("parry.plan_speed", G, "机械臂出刀速度", 14.2, 1.1, 49.2, 0.3, "m/s", "送刀速度上限")
	_f("parry.torso_turn", G, "腰环跟随比例", 0.9, 0.0, 1.0, 0.05, "",
		"目标在侧面时腰环转多少（剩下的交给手臂）")
	_f("parry.intercept_margin", G, "拦截让出距离", 0.33, 0.05, 1.37, 0.03, "m",
		"刀架在离身体这么远的地方 —— 它的刀还没打到你")
	_f("parry.block_knockback", G, "格挡击退速度", 3.83, 0.0, 16.4, 0.3, "m/s",
		"架住一刀后被推开的速度")
	_f("parry.block_hitstop", G, "格挡顿帧", 0.06, 0.0, 0.3, 0.005, "s")

	# ---------------------------------------------------------------- 小怪
	G = "小怪"
	_f("mob.hp", G, "血量", 1.0, 1.0, 2000.0, 5.0)
	_f("mob.speed", G, "移速", 2.84, 0.0, 16.4, 0.05, "m/s")
	_f("mob.aggro_range", G, "发现距离", 32.8, 0.5, 109.0, 0.5, "m")
	_f("mob.attack_range", G, "挥刀距离", 3.39, 0.3, 16.4, 0.05, "m")
	_f("mob.chase_stop", G, "贴身距离", 2.52, 0.3, 16.4, 0.05, "m")
	_f("mob.windup", G, "前摇", 0.52, 0.0, 3.0, 0.01, "s")
	_f("mob.active", G, "判定时长", 0.16, 0.02, 2.0, 0.01, "s")
	_f("mob.recovery", G, "后摇", 0.55, 0.0, 3.0, 0.01, "s")
	_f("mob.damage", G, "伤害", 1.0, 0.0, 999.0, 1.0)
	_f("mob.damage_scale", G, "模型缩放", 1.0, 0.5, 3.0, 0.05, "", "1.0 = 和玩家同高（2.5 m）")
	_b("mob.block_when_visible", G, "被看到时 100% 格挡", true,
		"核心机制：只要它在你的相机画面里，你就伤不到它")
	_f("mob.turn_rate", G, "转身速率", 6.0, 0.5, 30.0, 0.1)

	# ---------------------------------------------------------------- 远程怪
	G = "远程怪"
	_f("archer.hp", G, "血量", 1.0, 1.0, 2000.0, 5.0)
	_f("archer.speed", G, "移速", 2.41, 0.0, 16.4, 0.05, "m/s")
	_f("archer.keep_dist", G, "保持距离", 10.9, 1.0, 43.8, 0.25, "m")
	_f("archer.fire_interval", G, "射击间隔", 2.4, 0.2, 10.0, 0.05, "s")
	_f("archer.telegraph", G, "拉弓前摇", 0.55, 0.0, 3.0, 0.01, "s")
	_f("archer.arrow_speed", G, "箭速", 16.4, 1.0, 65.6, 0.25, "m/s")
	_f("archer.arrow_damage", G, "箭伤", 1.0, 0.0, 999.0, 1.0)
	_b("archer.parry_counter", G, "正对时补射一支拦截箭", true,
		"你在弹反瞬间正对着它 → 它立刻补一箭把你的弹回箭打掉")
	_f("archer.counter_speed", G, "拦截箭速度", 18.6, 1.0, 76.6, 0.25, "m/s")
	_f("archer.aim_lead", G, "预瞄提前量", 0.6, 0.0, 2.0, 0.05)
	_f("archer.aggro_range", G, "发现距离", 49.2, 0.5, 164.0, 0.5, "m")

	# ---------------------------------------------------------------- 大怪
	G = "大怪"
	_f("boss.hp", G, "血量", 3.0, 1.0, 6000.0, 10.0)
	_f("boss.scale", G, "模型缩放", 2.0, 1.0, 4.0, 0.05, "", "2.0 = 玩家两倍高（5.0 m）")
	_f("boss.speed", G, "走路速度", 2.19, 0.0, 10.9, 0.05, "m/s")
	_f("boss.phase1", G, "阶段1 原地放刀气", 3.4, 0.2, 20.0, 0.1, "s")
	_f("boss.phase2", G, "阶段2 冲撞重击", 3.2, 0.2, 20.0, 0.1, "s")
	_f("boss.cycle_gap", G, "阶段间停顿", 0.8, 0.0, 5.0, 0.05, "s")
	_f("boss.qi_speed", G, "刀气速度", 12.0, 0.5, 49.2, 0.25, "m/s")
	_f("boss.qi_damage", G, "刀气伤害", 1.0, 0.0, 999.0, 1.0)
	_f("boss.qi_radius", G, "刀气半径", 0.77, 0.1, 3.3, 0.03, "m")
	_f("boss.charge_speed", G, "冲撞速度", 9.30, 0.5, 32.8, 0.25, "m/s")
	_f("boss.slam_radius", G, "重击范围半径", 4.92, 0.5, 16.4, 0.05, "m")
	_f("boss.slam_damage", G, "重击伤害", 1.0, 0.0, 999.0, 1.0)
	_f("boss.windup", G, "起手前摇倍率", 1.0, 0.2, 4.0, 0.05)
	_e("boss.laser_trigger", G, "激光触发方式", "player_sees",
		[{"v": "player_sees", "label": "你看到它"}, {"v": "disabled", "label": "关闭激光"}])
	_f("boss.laser_cooldown", G, "激光冷却", 2.0, 0.0, 20.0, 0.05, "s")
	_f("boss.laser_warn", G, "激光预警", 0.0, 0.0, 3.0, 0.01, "s", "0 = 出现即死")
	_f("boss.laser_damage", G, "激光伤害", 1.0, 0.0, 999.0, 1.0)
	_f("boss.laser_width", G, "激光束宽度", 0.33, 0.03, 2.2, 0.03, "m")
	_f("boss.shadow_intensity", G, "墙上影子浓度", 0.66, 0.0, 1.0, 0.01, "×",
		"四面墙把场上所有角色（含你自己）投成剪影；这是剪影的浓度")
	_f("boss.shadow_size", G, "墙上影子大小", 1.0, 0.5, 2.0, 0.01, "×",
		"1.0 = 1:1 正交投影（绕角色脚下缩放；>1 时影子可能顶到墙上沿）")
	_f("boss.shadow_softness", G, "墙上影子柔化", 0.6, 0.0, 1.0, 0.05, "×",
		"剪影边缘的柔化半径（0 = 硬边）")

	# ---------------------------------------------------------------- 相机
	G = "相机"
	_e("cam.mode", G, "视角模式", "first",
		[{"v": "third", "label": "第三人称"}, {"v": "first", "label": "第一人称"}])
	_f("cam.distance", G, "第三人称距离", 7.11, 1.64, 16.4, 0.05, "m")
	_f("cam.height", G, "第三人称高度", 2.30, -1.1, 6.6, 0.03, "m")
	_f("cam.focus_height", G, "看向高度", 2.13, 0.0, 6.6, 0.03, "m")
	_f("cam.fov", G, "第三人称 FOV", 68.0, 30.0, 120.0, 0.5)
	_f("cam.first_fov", G, "第一人称 FOV", 80.0, 30.0, 130.0, 0.5)
	_f("cam.first_height", G, "第一人称眼高", 1.94, 0.27, 4.4, 0.03, "m")
	_b("cam.first_show_weapon", G, "第一人称显示世界模型里的刀", false, "默认用手持模型（好看得多）；开了这个会看到机甲那把大刀（刀身 1.3 m、全长 1.6 m）")
	_f("cam.sensitivity", G, "鼠标灵敏度", 0.0022, 0.0002, 0.02, 0.0001)
	_f("cam.pitch_min", G, "最低俯仰", -1.25, -1.55, 0.0, 0.01, "rad")
	_f("cam.pitch_max", G, "最高俯仰", 0.62, 0.0, 1.55, 0.01, "rad")
	_f("cam.follow_rate", G, "跟随平滑", 12.0, 1.0, 40.0, 0.5)
	_b("cam.collision", G, "相机避让墙面", true)
	_f("cam.shake_scale", G, "抖屏强度", 1.0, 0.0, 4.0, 0.05)
	_f("cam.mask_soft", G, "FP 视野黑幕边界柔化", 0.008, 0.0, 0.08, 0.001, "",
		"第三人称按 Tab：第一人称视锥外全部涂黑。0 = 像素级硬边（和零余量视野判定完全一致），数值越大边界越软")

	# ---------------------------------------------------------------- 音频
	G = "音频"
	_f("audio.master", G, "总音量", 1.0, 0.0, 1.5, 0.01, "×")
	_f("audio.step_volume", G, "脚步音量", 1.0, 0.0, 3.0, 0.05, "×")
	_f("audio.swing_volume", G, "挥剑/刀气音量", 1.0, 0.0, 3.0, 0.05, "×")
	_f("audio.arrow_volume", G, "箭啸音量", 1.0, 0.0, 3.0, 0.05, "×")
	_f("audio.max_distance", G, "最远可闻距离", 32.8, 5.5, 137.0, 2.5, "m")
	_b("audio.spatial", G, "空间化（双耳定位）", true, "关掉 = 所有声音居中，用来对比")
	_b("audio.occlusion", G, "墙体遮挡衰减", true, "被墙挡住的声音会变闷变小")
	_f("audio.doppler", G, "多普勒强度", 1.0, 0.0, 1.0, 0.05, "×")
	_f("audio.reverb", G, "空间混响", 0.22, 0.0, 0.6, 0.01, "×", "街道/大厅的残响，0=干声")
	_b("rules.audio_debug", G, "音频调试输出", false, "打开后每帧打印混音耗时与峰值")

	# ---------------------------------------------------------------- 规则
	G = "规则"
	_b("rules.one_hit_kill", G, "玩家一击必死", true, "关闭后可调血量手感")
	_f("rules.player_hp", G, "玩家血量", 1.0, 1.0, 5000.0, 10.0)
	_f("rules.hit_damage_scale", G, "非一击必死时每击扣血比例", 0.34, 0.01, 1.0, 0.01, "×血量")
	_f("rules.invuln_time", G, "受击无敌时间", 0.5, 0.0, 3.0, 0.05, "s")
	_f("rules.death_delay", G, "死亡到重开延时", 1.6, 0.2, 6.0, 0.05, "s")
	_f("rules.banner_time", G, "关卡横幅时长", 2.2, 0.5, 8.0, 0.1, "s")
	_b("rules.edge_markers", G, "屏幕外敌人指示器", true)
	_f("rules.marker_range", G, "指示器距离", 30.1, 2.7, 109.0, 0.5, "m")
	_b("rules.vision_occlusion", G, "视野叠加墙体遮挡", false,
		"关 = 只看相机画面；开 = 被墙挡住也算看不见")
	_b("rules.hitstop", G, "命中停顿", true)
	_f("rules.time_scale", G, "全局时间倍率", 1.0, 0.05, 2.0, 0.05, "×")
	_b("rules.god_mode", G, "无敌调试", false)
	_b("rules.enemy_lod", G, "远处敌人降频动画", true)


# ------------------------------------------------------------------ access
## 游戏逻辑用：长度量纲的参数转换成世界单位后返回，其余原样返回。
func getf(path: String) -> float:
	var v = _vals.get(path)
	if v == null:
		return 0.0
	var f := float(v)
	if bool(_by_path[path].get("len", false)):
		f = Units.to_units(f)
	return f


## 面板/调试用：原样返回存档里的真实米（或该参数自己的单位）。
func getm(path: String) -> float:
	var v = _vals.get(path)
	return float(v) if v != null else 0.0


func geti(path: String) -> int:
	return int(getf(path))


func getb(path: String) -> bool:
	return bool(_vals.get(path, false))


func gets(path: String) -> String:
	return str(_vals.get(path, ""))


func set_value(path: String, v) -> void:
	if not _by_path.has(path):
		return
	var d: Dictionary = _by_path[path]
	var out = v
	match String(d["type"]):
		"float":
			out = clampf(float(v), float(d["min"]), float(d["max"]))
		"int":
			out = clampi(int(v), int(d["min"]), int(d["max"]))
		"bool":
			out = bool(v)
		"enum":
			var ok := false
			for o in d["options"]:
				if String(o["v"]) == String(v):
					ok = true
			if not ok:
				return
			out = String(v)
	if _vals.get(path) == out:
		return
	_vals[path] = out
	changed.emit(path, out)


func add_value(path: String, delta: float) -> void:
	if not _by_path.has(path):
		return
	var d: Dictionary = _by_path[path]
	match String(d["type"]):
		"float":
			# 全程在「真实米」这一侧算，别拿世界单位去加米的步长
			var step: float = float(d["step"])
			var base := float(_vals[path])
			base = roundf(base / step) * step if step > 0.0 else base
			set_value(path, base + delta * step)
		"int":
			set_value(path, geti(path) + int(signf(delta)))
		"bool":
			if delta != 0.0:
				set_value(path, not getb(path))
		"enum":
			var opts: Array = d["options"]
			var idx := 0
			for i in opts.size():
				if String(opts[i]["v"]) == gets(path):
					idx = i
			idx = wrapi(idx + int(signf(delta)), 0, opts.size())
			set_value(path, String(opts[idx]["v"]))


func defs(group := "") -> Array:
	if group == "":
		return _defs
	var out: Array = []
	for d in _defs:
		if String(d["group"]) == group:
			out.append(d)
	return out


func groups() -> Array:
	return _groups


func spec(path: String) -> Dictionary:
	return _by_path.get(path, {})


func value(path: String):
	return _vals.get(path)


func snapshot() -> Dictionary:
	return _vals.duplicate(true)


func apply_snapshot(snap: Dictionary) -> void:
	for k in snap.keys():
		set_value(String(k), snap[k])


# ------------------------------------------------------------------ persist
func save() -> void:
	var out := {}
	for k in _vals.keys():
		if not NO_SAVE.has(String(k)):
			out[k] = _vals[k]
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()


func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for k in parsed.keys():
		if NO_SAVE.has(String(k)):
			continue
		set_value(String(k), parsed[k])
	bulk_changed.emit()


func reset_all() -> void:
	for d in _defs:
		_vals[d["path"]] = d["default"]
	bulk_changed.emit()
	changed.emit("*", null)


func reset_group(group: String) -> void:
	for d in _defs:
		if String(d["group"]) == group:
			_vals[d["path"]] = d["default"]
	bulk_changed.emit()
	changed.emit("*", null)


# ------------------------------------------------------------------ handy
## 派生值：由跳跃高度 + 重力反算起跳初速（不存表，永远跟着两个参数走）
func jump_velocity() -> float:
	return sqrt(maxf(0.001, 2.0 * getf("jump.gravity") * getf("jump.height")))


## 攻击判定窗口：总时长 - 前摇 - 后摇
func attack_active(name: String) -> float:
	return maxf(0.02, getf("attack.%s.duration" % name)
		- getf("attack.%s.windup" % name)
		- getf("attack.%s.recovery" % name))


## 机甲当前站立高度（真实米）—— 给调试面板/探针用，不是可调参数
func body_height_m(rig_scale := 1.0) -> float:
	return 2.50 * rig_scale

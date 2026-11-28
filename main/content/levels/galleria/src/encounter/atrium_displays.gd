extends RefCounted

const INTERLOCK := "interlock"
const ACTUATOR := "actuator"
const FACE_DEPTH := 0.242
const FONT := preload("res://assets/fonts/ui_font.tres")
const DISPLAY_SHADER := preload("res://gfx/encounter/monitor_glass.gdshader")
const SYSTEM_DISPLAYS := [INTERLOCK, ACTUATOR, "power", "air_handling"]
const TITLE_TINT := Color("c7d5d5")
const DATA_TINT := Color("a7bbbb")
const CONTENT := {
	"supply": {
		"effect": 0, "primary": Color("e5aa64"), "secondary": Color("ec6b58"),
		"image": preload("res://assets/displays/supply.svg"), "title": "货运批次", "channel": "H02 / MANIFEST",
		"labels": [
			["本批交接", Vector2(0.084, 0.364), 0.031], ["货舱 02 / 中庭", Vector2(0.51, 0.364), 0.032],
			["减振件", Vector2(0.085, 0.492), 0.046], ["机械备件", Vector2(0.51, 0.493), 0.033],
			["备用电芯", Vector2(0.085, 0.635), 0.046], ["储能备件", Vector2(0.51, 0.636), 0.033],
			["批次标签 / H02", Vector2(0.052, 0.814), 0.027],
		],
	},
	"rollers": {
		"effect": 1, "primary": Color("e5a136"), "secondary": Color("55d4ce"),
		"image": preload("res://assets/displays/rollers.svg"), "title": "补给辊道", "channel": "STATION / HANDOFF",
		"labels": [
			["进料段", Vector2(0.14, 0.36), 0.032], ["验收台", Vector2(0.54, 0.36), 0.036],
			["周转区", Vector2(0.74, 0.36), 0.032], ["低速转运截面", Vector2(0.10, 0.875), 0.027],
		],
	},
	"maintenance": {
		"effect": 2, "primary": Color("bf85ed"), "secondary": Color("65d6e1"),
		"image": preload("res://assets/displays/maintenance.svg"), "title": "检修网络", "channel": "SERVICE / R-11",
		"labels": [
			["回风", Vector2(0.113, 0.799), 0.031], ["补给", Vector2(0.285, 0.871), 0.031],
			["中庭支路", Vector2(0.43, 0.294), 0.027], ["实验舱", Vector2(0.75, 0.407), 0.033],
		],
	},
	"airlock": {
		"effect": 3, "primary": Color("61d8f0"), "secondary": Color("ef9c64"),
		"image": preload("res://assets/displays/airlock.svg"), "title": "气闸压差", "channel": "H02 / PRESSURE",
		"labels": [
			["货舱侧", Vector2(0.768, 0.378), 0.037], ["中庭侧", Vector2(0.768, 0.628), 0.037],
			["最近一次均压记录", Vector2(0.053, 0.884), 0.029],
		],
	},
	"habitat": {
		"effect": 4, "primary": Color("66e3a9"), "secondary": Color("be84f1"),
		"image": preload("res://assets/displays/habitat.svg"), "title": "乘员区环境", "channel": "CREW / LIFE SUPPORT",
		"labels": [
			["温度", Vector2(0.05, 0.317), 0.031], ["21.6 °C", Vector2(0.05, 0.442), 0.068],
			["相对湿度", Vector2(0.367, 0.317), 0.031], ["43 %", Vector2(0.367, 0.442), 0.068],
			["空气循环", Vector2(0.694, 0.317), 0.031], ["正常", Vector2(0.694, 0.442), 0.062],
		],
	},
	"stairs": {
		"effect": 5, "primary": Color("63cee3"), "secondary": Color("a37dea"),
		"image": preload("res://assets/displays/stairs.svg"), "title": "返程通廊", "channel": "DECK / SECTION",
		"labels": [
			["下层中庭", Vector2(0.082, 0.68), 0.030], ["上层通廊", Vector2(0.755, 0.284), 0.030],
			["楼梯剖面", Vector2(0.084, 0.874), 0.029],
		],
	},
	"air_handling": {
		"effect": 6, "primary": Color("6edbc9"), "secondary": Color("748af2"),
		"image": preload("res://assets/displays/air_handling.svg"), "title": "空气处理", "channel": "R-11 / R-12",
		"labels": [
			["送风", Vector2(0.102, 0.338), 0.028], ["回风", Vector2(0.102, 0.593), 0.028],
			["双列过滤 / 设计流向", Vector2(0.09, 0.912), 0.027],
		],
	},
	INTERLOCK: {
		"effect": 7, "primary": Color("f1a353"), "secondary": Color("60dbd1"),
		"image": preload("res://assets/displays/interlock.svg"), "title": "实验舱联锁", "channel": "LAB / INTERLOCK",
		"labels": [["回廊实验舱 / 主舱门", Vector2(0.057, 0.778), 0.036]],
	},
	ACTUATOR: {
		"effect": 8, "primary": Color("71dcea"), "secondary": Color("af83f2"),
		"image": preload("res://assets/displays/actuator.svg"), "title": "舱门执行器", "channel": "LAB / ACTUATOR",
		"labels": [["实时行程", Vector2(0.713, 0.339), 0.038], ["闭合", Vector2(0.091, 0.896), 0.026],
			["全开", Vector2(0.85, 0.896), 0.026]],
	},
	"power": {
		"effect": 9, "primary": Color("b490f4"), "secondary": Color("e0b25f"),
		"image": preload("res://assets/displays/power.svg"), "title": "实验区供电", "channel": "LAB / BUS A",
		"labels": [
			["主供电母线", Vector2(0.069, 0.352), 0.035], ["观测设备", Vector2(0.12, 0.654), 0.030],
			["舱门联锁", Vector2(0.437, 0.654), 0.030], ["环境维持", Vector2(0.753, 0.654), 0.030],
		],
	},
}

var _materials: Dictionary = {}


func mount(parent: Node3D, kit, at: Vector3, yaw: float, width: float, subject: String,
		stand_off: float) -> Dictionary:
	var height := width * 0.5
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	kit.push_xf(xf)
	for x in [-width * 0.36, width * 0.36]:
		kit.box_bevel("metal", Vector3(0.57, height * 0.83, 0.17), Vector3(x, 0, -0.04), 0.04)
		for y in [-height * 0.34, height * 0.34]:
			kit.box_bevel("frame", Vector3(0.43, 0.24, stand_off + 0.14),
				Vector3(x, y, stand_off * 0.5), 0.045)
	kit.pop_xf()

	var front := xf.translated_local(Vector3.BACK * stand_off)
	kit.push_xf(front)
	kit.box_bevel("frame", Vector3(width + 0.46, height + 0.49, 0.26), Vector3.ZERO, 0.075)
	kit.box_bevel("dark", Vector3(width + 0.24, height + 0.23, 0.16), Vector3.BACK * 0.14, 0.035)
	for x in [-width * 0.43, width * 0.43]:
		kit.box_bevel("metal", Vector3(0.39, 0.26, 0.24), Vector3(x, -height * 0.5 - 0.22, 0.06), 0.038)
		kit.box("frame", Vector3(0.14, 0.08, 0.06), Vector3(x, -height * 0.5 - 0.22, 0.195))
	if subject in SYSTEM_DISPLAYS:
		var lower := -height * 0.5 - 0.26
		kit.box_bevel("frame", Vector3(width * 0.53, 0.44, 0.40), Vector3(0, lower - 0.11, 0.015), 0.060)
		for i in range(-7, 8):
			kit.box("dark", Vector3(width * 0.019, 0.13, 0.027),
				Vector3(width * 0.031 * i, lower - 0.11, 0.218))
	kit.pop_xf()

	var housing := Node3D.new()
	housing.name = "WallDisplay_" + subject
	housing.transform = front
	parent.add_child(housing, true)
	var display := MeshInstance3D.new()
	var panel := QuadMesh.new()
	panel.size = Vector2(width, height)
	display.mesh = panel
	display.position.z = FACE_DEPTH
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _screen_material(subject)
	display.material_override = material
	housing.add_child(display)

	var content: Dictionary = CONTENT[subject]
	_caption(housing, content["title"], Vector2(0.047, 0.128), 0.052, width, TITLE_TINT)
	_caption(housing, content["channel"], Vector2(0.625, 0.133), 0.027, width,
		content["primary"].lerp(DATA_TINT, 0.36))
	for label: Array in content["labels"]:
		_caption(housing, label[0], label[1], label[2], width, DATA_TINT)
	if subject == INTERLOCK:
		var status := _caption(housing, "安全闭锁", Vector2(0.091, 0.456), 0.109, width, Color("cfb18b"))
		return {"status": status, "material": material}
	if subject == ACTUATOR:
		var position_label := _caption(housing, "00 %", Vector2(0.708, 0.518), 0.093, width, TITLE_TINT)
		return {"position_label": position_label, "material": material}
	return {}


func _screen_material(subject: String) -> ShaderMaterial:
	if not _materials.has(subject):
		var material := ShaderMaterial.new()
		material.shader = DISPLAY_SHADER
		var instrument: Dictionary = CONTENT[subject]
		var source: Texture2D = instrument["image"]
		var pixels := source.get_image()
		pixels.generate_mipmaps()
		material.set_shader_parameter("instrument", ImageTexture.create_from_image(pixels))
		material.set_shader_parameter("channel", instrument["effect"])
		material.set_shader_parameter("primary", instrument["primary"])
		material.set_shader_parameter("secondary", instrument["secondary"])
		material.set_shader_parameter("scan_offset", float(posmod(subject.hash(), 100)) / 100.0)
		_materials[subject] = material
	return _materials[subject]


func _caption(parent: Node3D, value: String, uv: Vector2, size: float, width: float, tint: Color) -> Label3D:
	var caption := Label3D.new()
	caption.text = value
	caption.font = FONT
	caption.font_size = 96
	caption.pixel_size = width * size / caption.font_size
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.position = Vector3((uv.x - 0.5) * width, (0.5 - uv.y) * width * 0.5, FACE_DEPTH + 0.024)
	caption.modulate = tint
	caption.outline_size = 0
	parent.add_child(caption)
	return caption

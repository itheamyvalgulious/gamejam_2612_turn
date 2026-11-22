extends RefCounted
## MechPalette — 同一套材质工厂 + 四套配色 = 主角 / 小怪 / 远程怪 / 大怪。
##
## 用法（mech_rig.gd 里）：
##     var m := PAL.for_palette(palette)
##     MK.add(... , m.armor(), ...)      # 方法与 materials.gd 的静态函数一一对应
##
## 之所以单独一个文件：GDScript 的内嵌类拿不到外层脚本的常量，所以 Palette
## 通过实例成员 `base` 持有 materials.gd 这份「基类材质表」。

const MAT = preload("res://src/vesper/materials.gd")

static var _palettes: Dictionary = {}


static func for_palette(pal: Dictionary) -> Palette:
	var key := "%s|%s|%s|%.2f" % [String(pal.get("tag", "")), str(pal.get("accent", "")),
		str(pal.get("tint", "")), float(pal.get("metal_mix", 0.16))]
	if _palettes.has(key):
		return _palettes[key]
	var p := Palette.new()
	p.base = MAT
	p.setup(pal)
	_palettes[key] = p
	return p


class Palette extends RefCounted:
	var base                        # materials.gd（静态材质工厂）
	var tag := ""
	var accent := Color(1.0, 0.30, 0.06)
	var tint := Color(1, 1, 1)
	var metal_mix := 0.16
	var paint_hue_mix := 0.85
	var cache: Dictionary = {}

	func setup(d: Dictionary) -> void:
		tag = String(d.get("tag", ""))
		accent = d.get("accent", accent)
		tint = d.get("tint", tint)
		metal_mix = float(d.get("metal_mix", metal_mix))
		paint_hue_mix = float(d.get("paint_hue_mix", paint_hue_mix))

	## 把任意自发光色的色相迁到主题色（保留明度），所有橙色发光因此统一换色
	func _hue_to_accent(c: Color) -> Color:
		var h: Color = Color.from_hsv(accent.h, clampf(lerpf(c.s, accent.s, 0.45), 0.0, 1.0), c.v)
		return h.lerp(accent, 0.30)

	func _metal(c: Color) -> Color:
		var t: Color = Color(c.r * tint.r, c.g * tint.g, c.b * tint.b)
		return t.lerp(accent * (0.35 + 0.25 * c.v), metal_mix)

	func _dup_std(src: StandardMaterial3D, key: String, col: Color) -> StandardMaterial3D:
		if cache.has(key):
			return cache[key]
		var m: StandardMaterial3D = src.duplicate()
		m.albedo_color = col
		cache[key] = m
		return m

	func armor() -> StandardMaterial3D:
		return _dup_std(base.armor(), "armor", _metal(base.armor().albedo_color))

	func armor_shadow() -> StandardMaterial3D:
		return _dup_std(base.armor_shadow(), "armor_shadow", _metal(base.armor_shadow().albedo_color))

	func armor_edge() -> StandardMaterial3D:
		return _dup_std(base.armor_edge(), "armor_edge", _metal(base.armor_edge().albedo_color))

	func frame() -> StandardMaterial3D:
		return _dup_std(base.frame(), "frame", _metal(base.frame().albedo_color))

	func frame_light() -> StandardMaterial3D:
		return _dup_std(base.frame_light(), "frame_light", _metal(base.frame_light().albedo_color))

	func paint() -> StandardMaterial3D:
		var b: Color = base.paint().albedo_color
		var col: Color = b.lerp(Color.from_hsv(accent.h, clampf(b.s * 1.2, 0.0, 1.0), b.v * 0.85),
			paint_hue_mix)
		return _dup_std(base.paint(), "paint", col)

	func emissive(color := Color(1.0, 0.30, 0.06), energy := 5.0) -> StandardMaterial3D:
		var col := _hue_to_accent(color)
		var key := "emit_%s_%.2f" % [col.to_html(false), energy]
		if cache.has(key):
			return cache[key]
		var m := StandardMaterial3D.new()
		m.albedo_color = col.darkened(0.55)
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = energy
		m.roughness = 0.4
		m.metallic = 0.2
		m.resource_name = "emissive_" + tag
		cache[key] = m
		return m

	func visor_orange() -> StandardMaterial3D:
		if cache.has("visor"):
			return cache["visor"]
		var m := StandardMaterial3D.new()
		m.albedo_color = accent.darkened(0.35)
		m.emission_enabled = true
		m.emission = accent
		m.emission_energy_multiplier = 8.0
		m.metallic = 0.5
		m.roughness = 0.12
		cache["visor"] = m
		return m

	func blade_core() -> ShaderMaterial:
		if cache.has("blade_core"):
			return cache["blade_core"]
		var m: ShaderMaterial = base.blade_core().duplicate()
		var hot: Color = Color(1.0, 0.96, 0.88).lerp(accent.lerp(Color.WHITE, 0.6), 0.55)
		m.set_shader_parameter("hot_color", hot)
		m.set_shader_parameter("mid_color", accent)
		m.set_shader_parameter("tip_color", accent.darkened(0.35))
		cache["blade_core"] = m
		return m

	func blade_glow() -> ShaderMaterial:
		if cache.has("blade_glow"):
			return cache["blade_glow"]
		var m: ShaderMaterial = base.blade_glow().duplicate()
		m.set_shader_parameter("color", accent)
		cache["blade_glow"] = m
		return m

	# 与配色无关的共享材质，直接透传
	func rubber() -> StandardMaterial3D: return base.rubber()
	func copper() -> StandardMaterial3D: return base.copper()
	func glass() -> StandardMaterial3D: return base.glass()
	func trail() -> ShaderMaterial: return base.trail()
	func ring_fx() -> ShaderMaterial: return base.ring_fx()
	func floor() -> ShaderMaterial: return base.floor()
	func contact_shadow() -> StandardMaterial3D: return base.contact_shadow()
	func mote() -> StandardMaterial3D: return base.mote()
	func spark() -> StandardMaterial3D: return base.spark()
	func smoke() -> StandardMaterial3D: return base.smoke()
	func dust() -> StandardMaterial3D: return base.dust()
	func hit_flash() -> StandardMaterial3D: return base.hit_flash()
	func speed_streak() -> StandardMaterial3D: return base.speed_streak()
	func pylon() -> StandardMaterial3D: return base.pylon()
	func radial_texture() -> GradientTexture2D: return base.radial_texture()

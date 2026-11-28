extends "res://src/encounter/art.gd"
## The campaign deck keeps the established drop and stair heights.

const Controls = preload("res://src/encounter/gallery_controls.gd")
const HALF_WIDTH := 36.0
const HALF_DEPTH := 32.0
const CAMPAIGN_HALF_WIDTH := 41.5
const CEILING := 25.0
const STAIR_X := 29.0
const STAIR_WIDTH := 6.0
const STAIR_BOTTOM := -10.0
const STAIR_TOP := 18.0
const DECK_HEIGHT := 8.0
const ENTRY_Z := 31.0
const LAB_GATE_Z := -27.0
const LAB_GATE_STROKE := 6.65
const LAB_PASSAGE_HALF_WIDTH := 4.93
const LAB_PASSAGE_BACK := -42.45
const LAB_EXIT := Rect2(-LAB_PASSAGE_HALF_WIDTH, -39.0, LAB_PASSAGE_HALF_WIDTH * 2.0, 6.60)
const LANDING := Vector3(0, 0, 12.1)

var controls := Controls.new()


func build_campaign() -> Dictionary:
	root.name = "CentralGalleria"
	_materials()
	_build_shell()
	_arrival()
	_upper_deck()
	_return_stairs()
	_concourse_floor()
	_public_gallery()
	_landing_bay()
	_research_bulkhead()
	var lab := _lab_access()
	_lighting()
	controls.attach(root)
	var encounters := [
		{"kind": "mob", "pos": LANDING + Vector3(-2.35, 0, -1.55)},
		{"kind": "mob", "pos": LANDING + Vector3(2.35, 0, 0.55)},
		{"kind": "archer", "pos": Vector3(20.9, 0, -11.9)},
	]
	var result := finish("坠击中庭", "由货舱气闸进入中庭，穿过中庭前往实验舱。",
		Vector2(CAMPAIGN_HALF_WIDTH, HALF_DEPTH), Vector3(0, DECK_HEIGHT, 29.0), encounters, [], false)
	result["vertical"] = true
	result["height_test"] = false
	result["player_bounds_managed_by_level"] = true
	result["lab"] = lab
	result["dynamic_solid_indices"] = [lab["index"]]
	result["controls"] = controls
	return result


func _materials() -> void:
	kit.material("floor", shader_mat("plate", {"base_col": Color("818484"), "tile_m": 4.0,
		"rough_bias": -0.16, "wear_amount": 0.42}))
	kit.material("grate", shader_mat("plate", {"base_col": Color("555c64"), "tile_m": 1.2,
		"grate": 0.85, "rough_bias": 0.02}))
	kit.material("wall", shader_mat("wall", {"base_col": Color("616b73"), "trim_col": Color("3b464e"),
		"accent_col": Color("887d6e"), "style": 1, "grime": 0.27}))
	for spec in [["metal", "b7bbc1", 0.27], ["dark", "363c45", 0.43], ["frame", "5d636d", 0.29],
		["teal", "557b82", 0.41], ["warm", "a99a83", 0.41], ["ceramic", "c9c9c5", 0.38],
		["bronze", "876a4c", 0.35], ["lab_enamel", "8b9c9c", 0.26]]:
		kit.material(spec[0], shader_mat("metal", {"tint": Color(spec[1]), "rough_base": spec[2],
			"rust_amount": 0.045, "oil_grime": 0.10}))
	kit.material("cyan", glow(Color("72d6df"), 1.40))
	kit.material("white", glow(Color("eeeef2"), 1.75))
	kit.material("amber", glow(Color("e1b883"), 0.95))
	kit.material("red", glow(Color("f66472"), 1.10))
	kit.material("paint", glow(Color("b8ac97"), 0.13))
	kit.material("worklight", glow(Color("ffcf94"), 2.15))
	kit.material("lounge_light", glow(Color("a5becb"), 1.22))
	kit.material("lab_light", glow(Color("a2e7f5"), 2.45))
	kit.material("concourse", shader_mat("plate", {"base_col": Color("535f65"), "tile_m": 3.55,
		"rough_bias": -0.02, "wear_amount": 0.33}))
	kit.material("supply_deck", shader_mat("plate", {"base_col": Color("6f5f50"), "tile_m": 2.2,
		"grate": 0.40, "rough_bias": 0.01}))
	kit.material("lounge_deck", shader_mat("plate", {"base_col": Color("4f646b"), "tile_m": 2.55,
		"rough_bias": 0.24, "wear_amount": 0.24}))
	kit.material("upholstery", shader_mat("wall", {"base_col": Color("657b83"),
		"trim_col": Color("404d55"), "style": 2, "grime": 0.14}))
	kit.material("glass", shader_mat("glazing", {"glass_tint": Color("344551"), "weathering": 0.12}))
	var soffit := StandardMaterial3D.new()
	soffit.albedo_color = Color("5b626a")
	soffit.metallic = 0.30
	soffit.roughness = 0.63
	kit.material("soffit", soffit)


func _build_shell() -> void:
	var span := CAMPAIGN_HALF_WIDTH * 2.0 + 1.0
	block("floor", Vector3(span, 0.60, 64), Vector3(0, -0.30, 0))
	block("soffit", Vector3(span, 0.60, 64), Vector3(0, 25.30, 0))
	for x in [-26.0, -19.5, -12.5, 12.5, 19.5, 26.0]:
		block("frame", Vector3(0.18, 0.12, 62.3), Vector3(x, 24.94, 0), false)
	for x in [-9.4, 9.4]:
		block("dark", Vector3(0.69, 0.27, 55.5), Vector3(x, 24.73, 0.25), false)
		for z in [-23.0, -8.0, 8.0, 23.0]:
			block("metal", Vector3(0.92, 0.31, 0.37), Vector3(x, 24.65, z), false)
	for side in [-1.0, 1.0]:
		var x: float = side * (CAMPAIGN_HALF_WIDTH + 0.45)
		block("wall", Vector3(0.90, 25, 65), Vector3(x, 12.50, 0))
		block("dark", Vector3(0.28, 0.34, 63), Vector3(x - side * 0.55, 0.19, 0))
		block("frame", Vector3(0.44, 0.54, 63), Vector3(x - side * 0.59, 11.10, 0), false)
		for z in [-25.0, -12.5, 0.0, 12.5, 25.0]:
			block("frame", Vector3(0.35, 5.3, 11.62), Vector3(x - side * 0.53, 3.11, z), false)
			block("dark", Vector3(0.39, 0.16, 11.90), Vector3(x - side * 0.55, 5.82, z), false)
		for z in [-26.0, -13.0, 0.0, 13.0, 26.0]:
			var rib := Vector3(x - side * 0.57, 12.50, z)
			block("frame", Vector3(0.81, 25, 0.55), rib)
			block("metal", Vector3(0.87, 0.43, 0.72), rib - Vector3.UP * 11.92, false)
			block("metal", Vector3(0.87, 0.52, 0.72), rib + Vector3.UP * 11.84, false)
		for z in [-17.6, 0.0, 17.6]:
			_upper_observation_bays(Vector3(x - side * 0.53, 16.50, z), side)
	block("wall", Vector3(span, 25, 0.90), Vector3(0, 12.50, 32.45))
	block("wall", Vector3(span, 17.0, 0.90), Vector3(0, 16.50, -32.45))
	for side in [-1.0, 1.0]:
		const OPENING_HALF_WIDTH := 5.3
		var width := span * 0.5 - OPENING_HALF_WIDTH
		block("wall", Vector3(width, 8.0, 0.90), Vector3(side * (OPENING_HALF_WIDTH + width * 0.5), 4.0, -32.45))
	for z in [-23.0, -8.0, 8.0, 23.0]:
		block("frame", Vector3(CAMPAIGN_HALF_WIDTH * 2.0, 0.84, 0.70), Vector3(0, 24.4, z), false)
		for x in [-27.0, 0.0, 27.0]:
			_ceiling_fixture(Vector3(x, 23.72, z), 7.6)
	for side in [-1.0, 1.0]:
		for z in [-19.0, -1.0, 16.0]:
			var x: float = 28.9 if side > 0 and z < -10.0 else side * 21.5
			var position_z: float = -23.0 if side > 0 and z < -10.0 else z
			block("frame", Vector3(1.15, 25.0, 1.45), Vector3(x, 12.50, position_z))
			block("dark", Vector3(1.48, 0.60, 1.80), Vector3(x, 0.30, position_z), true, true)
			block("metal", Vector3(1.53, 0.32, 1.83), Vector3(x, 8.05, position_z), false)
			block("warm", Vector3(0.068, 0.25, 0.91), Vector3(x - side * 0.60, 2.45, position_z), false)


func _upper_observation_bays(at: Vector3, side: float) -> void:
	block("dark", Vector3(0.22, 6.9, 13.64), at, false)
	block("glass", Vector3(0.13, 5.96, 12.75), at + Vector3.LEFT * (side * 0.14), false)
	for y in [-3.08, 3.08]:
		block("frame", Vector3(0.34, 0.27, 13.35), at + Vector3(-side * 0.14, y, 0), false)
	for z in [-6.51, -2.17, 2.17, 6.51]:
		block("frame", Vector3(0.41, 6.14, 0.21), at + Vector3(-side * 0.16, 0, z), false)
	for z in [-4.33, 0.0, 4.33]:
		block("metal", Vector3(0.25, 0.18, 3.76), at + Vector3(-side * 0.21, -2.81, z), false)
		block("white", Vector3(0.03, 0.065, 3.24), at + Vector3(-side * 0.212, 2.53, z), false)
		for y in [-2.61, -2.43, -2.25]:
			block("dark", Vector3(0.045, 0.046, 3.60), at + Vector3(-side * 0.245, y, z), false)


func _arrival() -> void:
	# The reverse face matches the hatch and jambs at the end of Cargo Hold 02.
	var center := Vector3(0, DECK_HEIGHT, ENTRY_Z)
	_hatch_frame(center, -1.0, "CARGO HOLD 02")
	block("frame", Vector3(9.43, 7.2, 0.34), center + Vector3(0, 3.68, 0.23))
	block("dark", Vector3(7.89, 6.14, 0.14), center + Vector3(0, 3.34, -0.014), false)
	block("metal", Vector3(6.24, 0.10, 0.08), center + Vector3(0, 1.02, -0.093), false)
	block("frame", Vector3(0.12, 5.92, 0.11), center + Vector3(0, 3.36, -0.11), false)
	block("frame", Vector3(12.0, 0.40, 6.45), Vector3(0, 15.85, 28.17))
	_ceiling_fixture(Vector3(0, 15.52, 27.40), 6.1)
	for side in [-1.0, 1.0]:
		var x: float = side * 5.48
		block("wall", Vector3(0.55, 7.55, 6.42), Vector3(x, 11.77, 28.16))
		block("metal", Vector3(0.16, 7.66, 0.47), Vector3(x - side * 0.34, 11.85, 25.02), false)
		_duct(Vector3(x - side * 0.36, 13.48, 28.13), -side * PI * 0.5, 2.6, "AIR RETURN")
		block("dark", Vector3(0.065, 0.18, 5.70), Vector3(side * 3.97, 8.012, 28.35), false)
	for z in [24.35, 26.55, 28.75]:
		_arrow(kit, Vector3(0, 8.044, z))
	light(Vector3(0, 14.35, 28.30), Color("e8ebf1"), 2.6, 12.0)
	light(Vector3(4.75, 14.76, 30.22), Color("fb7282"), 0.65, 5.8)


func _hatch_frame(at: Vector3, front: float, title: String) -> void:
	for side in [-1.0, 1.0]:
		var jamb := at + Vector3(side * 4.91, 3.89, 0)
		block("frame", Vector3(0.40, 7.78, 0.85), jamb)
		block("metal", Vector3(0.13, 6.68, 0.18),
			jamb + Vector3(-side * 0.12, -0.06, front * 0.46), false)
		block("cyan", Vector3(0.072, 3.32, 0.11),
			jamb + Vector3(-side * 0.23, 0.13, front * 0.25), false)
		for y in [1.39, 3.49, 5.59]:
			var bolt := at + Vector3(side * 4.91, y, front * 0.36)
			block("dark", Vector3(0.70, 0.47, 0.43), bolt, false)
			block("metal", Vector3(0.38, 0.25, 0.24), bolt + Vector3(-side * 0.14, 0, front * 0.27), false)
			block("amber", Vector3(0.13, 0.055, 0.062), bolt + Vector3(side * 0.18, 0, front * 0.26), false)
	block("frame", Vector3(10.46, 0.54, 0.85), at + Vector3.UP * 7.62)
	block("white", Vector3(6.12, 0.057, 0.25), at + Vector3(0, 7.327, front * 0.16), false)
	block("grate", Vector3(9.25, 0.042, 1.45), at + Vector3(0, 0.036, front * 0.58), false)
	_sign(title, at + Vector3(0, 7.69, front * 0.458), 0.0065, PI if front < 0 else 0.0)


func _upper_deck() -> void:
	block("frame", Vector3(30, 0.62, 15), Vector3(0, 7.69, 24.5), true, true)
	block("frame", Vector3(17.5, 0.62, 11.4), Vector3(23.55, 7.69, 23.7), true, true)
	block("floor", Vector3(29.78, 0.059, 14.80), Vector3(0, 7.978, 24.5), false)
	block("floor", Vector3(17.19, 0.059, 11.26), Vector3(23.55, 7.978, 23.7), false)
	for x in [-11.0, 0.0, 11.0]:
		block("dark", Vector3(0.57, 0.64, 13.9), Vector3(x, 7.08, 24.5), true)
		block("white", Vector3(0.32, 0.050, 5.00), Vector3(x, 6.724, 20.85), false)
	for x in [-12.0, 12.0]:
		block("frame", Vector3(0.78, 6.70, 0.92), Vector3(x, 3.35, 26.9))
		block("metal", Vector3(1.38, 0.19, 1.47), Vector3(x, 0.11, 26.9), false)
	for endpoints in [Vector2(-14.85, -5.15), Vector2(5.15, 14.85)]:
		_rail(Vector3(endpoints.x, 8, 17.22), Vector3(endpoints.y, 8, 17.22))
	_rail(Vector3(-14.85, 8, 17.22), Vector3(-14.85, 8, 31.79))
	_rail(Vector3(15.0, 8, 18.22), Vector3(25.86, 8, 18.22))
	_rail(Vector3(32.22, 8, 18.25), Vector3(32.22, 8, 29.30))
	_rail(Vector3(15.0, 8, 29.30), Vector3(32.22, 8, 29.30))
	# The central gap is an unbroken apron with recessed arrows and visible edge strips.
	block("grate", Vector3(9.71, 0.052, 1.1), Vector3(0, 8.014, 17.63), false)
	for i in 11:
		block("paint", Vector3(0.51, 0.027, 0.17), Vector3(-4.45 + i * 0.89, 8.051, 17.29), false)
	for z in [18.55, 20.75, 22.95]:
		_arrow(kit, Vector3(0, 8.045, z))
	# A directory fin and its attached bench identify this as a crew mezzanine.
	var directory := Vector3(-9.9, 8.0, 22.38)
	block("frame", Vector3(3.25, 0.20, 0.76), directory + Vector3.UP * 0.10, false)
	block("dark", Vector3(2.82, 2.92, 0.27), directory + Vector3.UP * 1.53)
	block("teal", Vector3(2.52, 1.93, 0.046), directory + Vector3(0, 1.76, 0.16), false)
	_sign("CENTRAL GALLERIA", directory + Vector3(0, 2.32, 0.195), 0.0031)
	_sign("中庭上层", directory + Vector3(0, 1.71, 0.195), 0.0045)
	for y in [1.42, 1.22]:
		block("cyan", Vector3(1.84 if y > 1.3 else 1.32, 0.026, 0.027),
			directory + Vector3(-0.14, y, 0.185), false)
	var key := directory + Vector3(1.02, 1.27, 0.227)
	_station_switch(key, 0.0)
	var destination := _sign("", directory + Vector3(0.04, 1.00, 0.20), 0.0039)
	controls.directory = {"id": "directory", "at": key + Vector3.BACK * 0.11, "normal": Vector3.BACK,
		"guide": _stair_guide(), "status": destination}
	_bench(Vector3(-11.67, 8.0, 28.79), 4.2, "warm", PI)


func _stair_guide() -> Node3D:
	var guides := Kit.new()
	guides.material("cyan", kit.mats["cyan"])
	for x in [-7.0, -4.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0]:
		guides.push_xf(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, 8.057, 25.13)))
		_arrow(guides, Vector3.ZERO)
		guides.pop_xf()
	_arrow(guides, Vector3(29.0, 8.057, 22.76))
	return guides.commit(root, "ReturnStairGuide", false)


func _return_stairs() -> void:
	for i in 28:
		var h := (i + 1) * DECK_HEIGHT / 28.0
		var z := STAIR_BOTTOM + i + 0.5
		block("frame", Vector3(STAIR_WIDTH, h, 1), Vector3(STAIR_X, h * 0.5, z), true, true, 0.02)
		block("grate", Vector3(5.74, 0.028, 0.93), Vector3(STAIR_X, h + 0.012, z), false)
		block("metal", Vector3(5.78, 0.030, 0.105), Vector3(STAIR_X, h + 0.028, z - 0.43), false)
		for x in [25.8, 32.2]:
			block("dark", Vector3(0.18, 1.0, 1), Vector3(x, h + 0.50, z))
			if i % 4 == 0:
				block("amber", Vector3(0.047, 0.11, 0.68), Vector3(x, h + 0.34, z), false)
	for x in [25.8, 32.2]:
		for i in range(0, 29, 4):
			block("metal", Vector3(0.17, 1.20, 0.16),
				Vector3(x, 0.58 + i * DECK_HEIGHT / 28, STAIR_BOTTOM + i), false)
		kit.tube("metal", [Vector3(x, 1.25, STAIR_BOTTOM), Vector3(x, 9.25, STAIR_TOP)], 0.075, 12)
	var base := Vector3(32.36, 0, -10.9)
	block("dark", Vector3(0.52, 3.82, 1.12), base + Vector3.UP * 1.91)
	block("paint", Vector3(0.044, 2.63, 0.83), base + Vector3(-0.28, 2.08, 0), false)
	_sign("↑  上层", base + Vector3(-0.308, 2.36, 0), 0.005, -PI * 0.5)


func _rail(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var horizontal := absf(a.x - b.x) > absf(a.z - b.z)
	var center := (a + b) * 0.5
	var guard := Vector3(length, 1.18, 0.16) if horizontal else Vector3(0.16, 1.18, length)
	solid_box(center + Vector3.UP * 0.59, guard)
	var kickplate := Vector3(length, 0.15, 0.14) if horizontal else Vector3(0.14, 0.15, length)
	block("frame", kickplate, center + Vector3.UP * 0.11, false)
	for y in [0.54, 1.18]:
		kit.tube("metal", [a + Vector3.UP * y, b + Vector3.UP * y], 0.063 if y < 1 else 0.083, 12)
	var posts := maxi(1, ceili(length / 3.2))
	for i in posts + 1:
		var p := a.lerp(b, float(i) / posts)
		block("frame", Vector3(0.15, 1.16, 0.15), p + Vector3.UP * 0.58, false)
		block("metal", Vector3(0.39, 0.075, 0.35), p + Vector3.UP * 0.048, false)


func _public_gallery() -> void:
	_supply_bay(Vector3(-33.65, 0, -5.05))
	_service_shutters(Vector3(CAMPAIGN_HALF_WIDTH - 0.65, 0, -6.4))
	_information_island(Vector3(-14.6, 0, -7.4))
	_lounge(Vector3(17.55, 0, -21.75))
	_duct(Vector3(-CAMPAIGN_HALF_WIDTH + 0.42, 5.73, -22.5), PI * 0.5, 4.7, "RETURN / R-11")
	_duct(Vector3(CAMPAIGN_HALF_WIDTH - 0.42, 5.73, 12.5), -PI * 0.5, 4.2, "RETURN / R-12")
	# The wheel starts behind this load-bearing divider off the main fall axis.
	block("frame", Vector3(3.57, 8.2, 1.22), Vector3(15.70, 4.1, -3.92))
	block("dark", Vector3(3.72, 0.24, 1.41), Vector3(15.70, 0.15, -3.92), false)
	block("frame", Vector3(7.3, 0.64, 1.35), Vector3(17.65, 8.19, -3.92))
	block("frame", Vector3(1.13, 0.66, 3.0), Vector3(21.25, 8.19, -2.59), false)
	block("dark", Vector3(3.36, 0.29, 1.46), Vector3(15.70, 7.80, -3.91), false)
	for x in [14.22, 17.18]:
		block("metal", Vector3(0.16, 4.54, 0.049), Vector3(x, 2.75, -3.28), false)


func _concourse_floor() -> void:
	block("concourse", Vector3(34.2, 0.026, 33.8), Vector3(0, 0.013, -8.18), false)
	for x in [-17.22, 17.22]:
		block("metal", Vector3(0.12, 0.026, 33.8), Vector3(x, 0.022, -8.18), false)
	for z in [-18.6, -5.4, 6.5]:
		block("grate", Vector3(31.6, 0.023, 0.32), Vector3(0, 0.028, z), false)
	for x in [-4.85, 4.85]:
		block("dark", Vector3(0.20, 0.028, 12.5), Vector3(x, 0.032, -20.63), false)
		for z in [-15.5, -18.9, -22.3, -25.7]:
			block("lab_light", Vector3(0.080, 0.021, 1.20), Vector3(x, 0.052, z), false)


func _supply_bay(at: Vector3) -> void:
	block("supply_deck", Vector3(14.7, 0.036, 20.6), at + Vector3(0.45, 0.018, 0), false)
	block("bronze", Vector3(14.0, 0.64, 21.45), at + Vector3(0.12, 8.60, 0))
	block("dark", Vector3(13.75, 0.25, 20.97), at + Vector3(0.07, 8.18, 0), false)
	# The open front has two bolted posts, with task lighting wired across the header.
	for z in [-9.85, 9.85]:
		var post := at + Vector3(6.94, 4.24, z)
		block("frame", Vector3(0.84, 8.48, 0.88), post)
		block("dark", Vector3(1.29, 0.49, 1.37), post - Vector3.UP * 3.995, true, true)
		block("worklight", Vector3(0.072, 2.54, 0.27), post + Vector3(0.45, 1.31, 0), false)
		block("panel_ship", Vector3(6.88, 5.64, 0.26), at + Vector3(-3.65, 2.96, z))
		block("bronze", Vector3(7.02, 0.26, 0.38), at + Vector3(-3.65, 5.86, z), false)
	block("bronze", Vector3(1.13, 1.02, 20.94), at + Vector3(6.99, 8.45, 0))
	block("worklight", Vector3(0.095, 0.26, 18.38), at + Vector3(7.58, 8.41, 0), false)
	for z in [-7.0, 0.0, 7.0]:
		block("frame", Vector3(13.9, 0.32, 0.48), at + Vector3(0, 7.97, z), false)
		block("worklight", Vector3(9.2, 0.055, 0.19), at + Vector3(0.14, 7.783, z), false)
		light(at + Vector3(2.2, 6.62, z), Color("ffc18b"), 2.1, 8.7)
	for z in range(-8, 9, 2):
		block("bronze", Vector3(0.18, 0.022, 0.9), at + Vector3(7.72, 0.044, z), false)
	_pantry(at + Vector3(-4.5, 0, 0))
	for z in [-7.95, 7.95]:
		var station := at + Vector3(-3.7, 0, z)
		block("dark", Vector3(4.54, 0.49, 1.92), station + Vector3.UP * 0.245, true, true)
		for x in range(-2, 3):
			block("metal", Vector3(0.48, 0.11, 1.72), station + Vector3(x * 0.81, 0.51, 0), false)
		block("warm", Vector3(1.69, 0.98, 1.48), station + Vector3(-0.85, 0.99, 0), true, true)
		for x in [-1.34, -0.36]:
			block("dark", Vector3(0.13, 0.11, 1.51), station + Vector3(x, 1.46, 0), false)


func _pantry(at: Vector3) -> void:
	# Warm shutters, stocked bins, and a service counter form the crew supply bay.
	block("dark", Vector3(0.28, 6.32, 12.0), at + Vector3(-3.18, 3.16, 0))
	block("warm", Vector3(0.25, 5.94, 12.4), at + Vector3(-2.88, 3.13, 0), false)
	block("frame", Vector3(4.70, 0.30, 12.20), at + Vector3(-0.12, 6.10, 0), false)
	block("frame", Vector3(4.42, 0.46, 12.4), at + Vector3(0.14, 6.26, 0), false)
	_sign("CREW SUPPLY", at + Vector3(2.39, 6.27, 0), 0.010, PI * 0.5)
	for z in [-5.81, 5.81]:
		block("frame", Vector3(4.46, 6.20, 0.36), at + Vector3(0.08, 3.10, z))
	for z in [-3.78, 0.0, 3.78]:
		block("frame", Vector3(0.72, 5.15, 3.48), at + Vector3(-1.19, 2.58, z), false)
		for y in [0.56, 1.87, 3.15, 4.46]:
			block("metal", Vector3(1.05, 0.10, 3.07), at + Vector3(-0.72, y, z), false)
			for shift in [-0.78, 0.72]:
				var bin := at + Vector3(-0.65, y + 0.36, z + shift)
				block("warm" if y > 2.0 else "teal", Vector3(0.72, 0.54, 1.08), bin, false)
				block("dark", Vector3(0.038, 0.084, 0.51), bin + Vector3(0.38, 0.09, 0), false)
	block("frame", Vector3(2.05, 1.66, 10.94), at + Vector3(1.82, 0.83, 0), true, true)
	block("ceramic", Vector3(2.32, 0.18, 11.16), at + Vector3(1.84, 1.74, 0), false)
	for z in [-3.6, 0.0, 3.6]:
		block("teal", Vector3(0.053, 1.18, 3.38), at + Vector3(2.88, 0.83, z), false)
		block("metal", Vector3(0.105, 0.10, 0.28), at + Vector3(2.95, 1.17, z + 1.12), false)
	block("worklight", Vector3(0.16, 0.06, 9.02), at + Vector3(1.86, 5.91, 0), false)
	light(at + Vector3(3.48, 5.25, 0), Color("ffdba9"), 2.55, 10.0)
	_supply_reader(at + Vector3(1.84, 1.83, -3.54))


func _supply_reader(at: Vector3) -> void:
	block("dark", Vector3(1.47, 0.11, 1.98), at + Vector3.UP * 0.055, false)
	block("metal", Vector3(1.22, 0.08, 1.66), at + Vector3.UP * 0.112, false)
	block("bronze", Vector3(0.67, 0.34, 0.92), at + Vector3(-0.05, 0.32, 0), false)
	for z in [-0.29, 0.29]:
		block("dark", Vector3(0.69, 0.034, 0.085), at + Vector3(-0.05, 0.504, z), false)
	for z in [-0.87, 0.87]:
		block("frame", Vector3(0.26, 0.88, 0.14), at + Vector3(-0.49, 0.51, z), false)
	block("frame", Vector3(0.32, 0.15, 1.92), at + Vector3(-0.49, 0.93, 0), false)
	block("teal", Vector3(0.038, 0.39, 1.45), at + Vector3(-0.31, 1.03, 0), false)
	var status := _sign("", at + Vector3(-0.283, 1.03, 0), 0.00375, PI * 0.5)
	var beam := Kit.new()
	beam.material("cyan", kit.mats["cyan"])
	beam.box("cyan", Vector3(1.09, 0.022, 0.06), Vector3.ZERO)
	var scan := beam.commit(root, "SupplyScanLine", false)
	var key := at + Vector3(1.21, -0.11, 0.82)
	_station_switch(key, PI * 0.5)
	controls.supply = {"id": "supply", "at": key + Vector3.RIGHT * 0.11, "normal": Vector3.RIGHT,
		"beam": scan, "scan_start": at + Vector3(-0.05, 0.535, 0), "status": status}


func _service_shutters(at: Vector3) -> void:
	block("frame", Vector3(1.14, 6.59, 14.5), at + Vector3(0, 3.30, 0))
	for z in [-3.73, 3.73]:
		for i in 11:
			block("panel_ship", Vector3(0.17, 0.45, 6.72),
				at + Vector3(-0.639, 0.24 + i * 0.465, z), false)
		for edge in [-3.47, 3.47]:
			block("metal", Vector3(0.22, 5.40, 0.17), at + Vector3(-0.70, 2.72, z + edge), false)
		block("dark", Vector3(0.28, 0.68, 6.92), at + Vector3(-0.69, 5.66, z), false)
	block("white", Vector3(0.094, 0.83, 0.16), at + Vector3(-0.86, 5.82, -6.79), false)
	_sign("CREW SERVICES", at + Vector3(-0.863, 5.67, -3.73), 0.008, -PI * 0.5)
	_sign("CLOSED", at + Vector3(-0.861, 2.73, 3.72), 0.007, -PI * 0.5)


func _bench(at: Vector3, width: float, material: String, yaw: float) -> void:
	var local := Transform3D(Basis(Vector3.UP, yaw), at)
	kit.push_xf(local)
	kit.box_bevel(material, Vector3(width, 0.23, 1.02), Vector3(0, 0.90, 0.03), 0.065)
	kit.box_bevel("dark", Vector3(width, 0.78, 0.18), Vector3(0, 1.33, -0.43), 0.046)
	for x in [-0.37 * width, 0.37 * width]:
		kit.box_bevel("frame", Vector3(0.34, 0.86, 0.84), Vector3(x, 0.43, 0), 0.048)
		kit.box("metal", Vector3(0.51, 0.086, 0.92), Vector3(x, 0.056, 0))
	for i in 3:
		var x := width * (float(i) / 3.0 - 0.335) + width / 6.0
		kit.box_bevel("metal", Vector3(0.06, 0.25, 0.66), Vector3(x, 1.11, -0.04), 0.024)
	kit.pop_xf()
	for part in [AABB(Vector3(-width * 0.5, 0.0, -0.48), Vector3(width, 1.015, 1.02)),
			AABB(Vector3(-width * 0.5, 1.015, -0.52), Vector3(width, 0.705, 0.18))]:
		var box: AABB = local * part
		solid_box(box.get_center(), box.size, part.position.y == 0.0)


func _information_island(at: Vector3) -> void:
	block("frame", Vector3(5.1, 1.19, 3.36), at + Vector3.UP * 0.595)
	block("dark", Vector3(5.34, 0.18, 3.51), at + Vector3.UP * 1.16, false)
	block("ceramic", Vector3(4.88, 0.16, 3.10), at + Vector3.UP * 1.27, false)
	block("frame", Vector3(3.30, 1.75, 0.42), at + Vector3(0, 2.13, -0.71))
	block("teal", Vector3(2.92, 1.39, 0.048), at + Vector3(0, 2.19, -0.477), false)
	_sign("DECK DIRECTORY", at + Vector3(0, 2.62, -0.442), 0.0048)
	_sign("实验舱 ↑", at + Vector3(0.46, 2.14, -0.438), 0.0046)
	for i in 3:
		block("cyan", Vector3(0.74 + 0.17 * i, 0.040, 0.019),
			at + Vector3(-0.69, 2.11 - i * 0.164, -0.445), false)


func _lounge(at: Vector3) -> void:
	kit.cyl("lounge_deck", 8.32, 8.32, 0.042, 32, at + Vector3.UP * 0.021)
	kit.torus("metal", 8.06, 0.052, 48, 8, at + Vector3.UP * 0.036)
	kit.cyl("teal", 7.38, 6.85, 0.57, 32, at + Vector3.UP * 6.87)
	kit.cyl("dark", 6.82, 6.82, 0.23, 32, at + Vector3.UP * 6.59)
	kit.torus("lounge_light", 5.84, 0.077, 48, 10, at + Vector3.UP * 6.435)
	kit.torus("lounge_light", 7.07, 0.057, 48, 10, at + Vector3.UP * 6.86)
	# Inscribed strips track the curved solid canopy without filling the diagonal corners.
	const ROOF_RADIUS := 6.81
	for strip in range(-6, 7):
		var extent := absf(float(strip)) + 0.5
		var width := 2.0 * sqrt(ROOF_RADIUS * ROOF_RADIUS - extent * extent)
		solid_box(at + Vector3(0, 6.80, strip), Vector3(width, 0.65, 1.0))
	for dx in [-4.8, 4.8]:
		var column := at + Vector3(dx, 3.34, -3.75)
		block("frame", Vector3(0.58, 6.68, 0.64), column)
		block("lab_enamel", Vector3(0.09, 3.17, 0.52), column + Vector3(-signf(dx) * 0.30, 0.71, 0), false)
		block("frame", Vector3(1.04, 0.17, 1.13), column - Vector3.UP * 3.255, true, true)
		_bench(at + Vector3(dx, 0, 0.10), 4.32, "upholstery", -signf(dx) * PI * 0.5)
	block("teal", Vector3(9.04, 2.09, 0.43), at + Vector3(0, 1.045, -4.18))
	for x in [-3.1, 0.0, 3.1]:
		block("upholstery", Vector3(2.89, 1.83, 0.105), at + Vector3(x, 1.06, -3.93), false)
	block("frame", Vector3(1.78, 0.77, 1.02), at + Vector3(0, 0.385, -0.52), true, true)
	block("ceramic", Vector3(3.15, 0.18, 1.61), at + Vector3(0, 0.86, -0.52), true, true, 0.12)
	var lamps: Array[OmniLight3D] = []
	for x in [-2.35, 2.35]:
		lamps.append(light(at + Vector3(x, 5.45, -0.50), Color("b8d3e2"), Controls.LAMP_POWER, 9.35))
	var key := at + Vector3(-4.42, 2.27, -3.75)
	_station_switch(key, PI * 0.5)
	controls.lounge = {"id": "lounge", "at": key + Vector3.RIGHT * 0.11, "normal": Vector3.RIGHT,
		"material": kit.mats["lounge_light"], "lamps": lamps}


func _station_switch(at: Vector3, yaw: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), at))
	kit.box_bevel("dark", Vector3(0.44, 0.49, 0.085), Vector3.ZERO, 0.024)
	kit.box_bevel("metal", Vector3(0.27, 0.25, 0.052), Vector3(0, 0, 0.055), 0.013)
	kit.box("paint", Vector3(0.12, 0.064, 0.025), Vector3(0, 0, 0.087))
	kit.pop_xf()


func _landing_bay() -> void:
	# Brass-edged inlaid plates and four corners mark the clear lower concourse.
	block("grate", Vector3(11.4, 0.022, 5.30), LANDING + Vector3(0, 0.012, 0), false)
	block("floor", Vector3(9.7, 0.020, 4.14), LANDING + Vector3(0, 0.026, 0), false)
	for x in [-5.1, 5.1]:
		for z in [-2.30, 2.30]:
			var pos := LANDING + Vector3(x, 0.045, z)
			block("cyan", Vector3(0.07, 0.026, 0.78), pos, false)
			block("cyan", Vector3(0.88, 0.026, 0.07),
				pos + Vector3(-signf(x) * 0.38, 0, signf(z) * 0.35), false)
	for x in [-3.2, 3.2]:
		block("paint", Vector3(0.16, 0.023, 1.04), LANDING + Vector3(x, 0.043, 0), false)


func _research_bulkhead() -> void:
	# The taller frame reads as a sealed research section behind the public concourse.
	block("teal", Vector3(18.9, 7.70, 0.48), Vector3(0, 11.85, -31.57), false)
	for side in [-1.0, 1.0]:
		block("teal", Vector3(4.46, 8.0, 0.48), Vector3(side * 7.22, 4.0, -31.57), false)
	block("frame", Vector3(20.80, 0.65, 1.07), Vector3(0, 15.71, -31.21), false)
	block("dark", Vector3(17.75, 1.72, 0.36), Vector3(0, 14.39, -31.15), false)
	block("metal", Vector3(16.85, 0.10, 0.16), Vector3(0, 14.62, -30.91), false)
	for x in [-6.72, 6.72]:
		_duct(Vector3(x, 11.94, -31.01), 0.0, 3.56, "RESEARCH RETURN")
	for x in [-31.7, -20.7, 20.7, 31.7]:
		block("panel_ship", Vector3(10.75, 5.7, 0.24), Vector3(x, 18.25, -31.87), false)
		block("frame", Vector3(10.9, 0.25, 0.37), Vector3(x, 15.40, -31.79), false)
		block("frame", Vector3(10.9, 0.25, 0.37), Vector3(x, 21.13, -31.79), false)
		for dx in [-4.70, 4.70]:
			block("metal", Vector3(0.077, 4.76, 0.085), Vector3(x + dx, 18.25, -31.721), false)
	for x in [-12.6, 12.6, -17.25, 17.25]:
		var column := Vector3(x, 11.25, -31.5)
		block("frame", Vector3(0.66, 22.50, 0.65), column, false)
		block("metal", Vector3(0.73, 0.30, 0.81), column + Vector3.UP * 4.48, false)
	_research_utilities()
	for side in [-1.0, 1.0]:
		var x: float = side * 10.25
		var collar := Vector3(x, 15.4, -30.89)
		block("dark", Vector3(1.32, 1.22, 0.62), collar, false)
		for y in [0.0, 0.22]:
			kit.tube("metal", [collar + Vector3(side * 0.51, y, 0),
				Vector3(side * 22.45, collar.y + y, -30.89),
				Vector3(side * 24.1, 13.57 + y, -30.89)], 0.102, 12)
		for span in [12.6, 17.25, 22.45]:
			block("frame", Vector3(0.22, 0.69, 0.48),
				Vector3(side * span, 15.48, -31.14), false)
		block("frame", Vector3(0.98, 1.04, 0.64), Vector3(side * 24.24, 13.66, -31.10), false)
		block("dark", Vector3(3.46, 2.18, 0.73), Vector3(side * 7.76, 1.09, -28.07))
	block("frame", Vector3(3.78, 3.95, 0.66), Vector3(-7.76, 4.04, -28.06), false)
	block("dark", Vector3(3.50, 3.68, 0.098), Vector3(-7.76, 4.04, -27.708), false)
	block("teal", Vector3(3.18, 1.81, 0.044), Vector3(-7.76, 4.53, -27.648), false)
	_sign("ACCESS CONTROL", Vector3(-7.76, 5.02, -27.618), 0.0035)
	for i in 3:
		var y := 4.53 - 0.28 * i
		block("cyan", Vector3(0.14, 0.075, 0.026), Vector3(-8.97, y, -27.616), false)
		block("metal", Vector3(1.96 - i * 0.22, 0.056, 0.022), Vector3(-7.65, y, -27.613), false)
	block("metal", Vector3(2.68, 0.18, 0.49), Vector3(-7.76, 2.69, -27.50), false)
	block("frame", Vector3(3.79, 4.04, 0.68), Vector3(7.76, 4.04, -28.05), false)
	_duct(Vector3(7.76, 4.82, -27.68), 0.0, 3.18, "FILTER BANK")
	block("dark", Vector3(3.22, 1.28, 0.18), Vector3(7.76, 3.11, -27.67), false)
	for x in [6.78, 7.76, 8.74]:
		block("metal", Vector3(0.71, 0.74, 0.11), Vector3(x, 3.09, -27.56), false)
		block("amber", Vector3(0.17, 0.063, 0.043), Vector3(x, 3.29, -27.49), false)


func _research_utilities() -> void:
	# Wall-depth service cases give the two wings different silhouettes from the deck.
	var vents := Vector3(-24.2, 10.04, -31.32)
	block("frame", Vector3(10.15, 6.38, 1.86), vents, false)
	block("dark", Vector3(9.43, 5.59, 0.36), vents + Vector3(0, 0, 0.89), false)
	for x in [-2.35, 2.35]:
		block("teal", Vector3(4.39, 4.18, 0.31), vents + Vector3(x, -0.36, 1.00), false)
		for slat in 9:
			block("dark", Vector3(3.90, 0.19, 0.35),
				vents + Vector3(x, -1.88 + 0.38 * slat, 1.16), false)
		block("metal", Vector3(1.04, 0.28, 2.45), vents + Vector3(x, -3.31, -0.09), false)
	_sign("AIR HANDLING", vents + Vector3(0, 2.20, 1.16), 0.0068)
	var power := Vector3(24.2, 9.64, -31.36)
	block("frame", Vector3(7.02, 7.89, 1.79), power, false)
	block("dark", Vector3(6.44, 7.20, 0.31), power + Vector3(0, 0, 0.91), false)
	for i in 3:
		var x := -2.1 + i * 2.1
		block("metal", Vector3(1.84, 4.83, 0.54), power + Vector3(x, -0.42, 1.09), false)
		block("dark", Vector3(1.34, 2.03, 0.11), power + Vector3(x, 0.42, 1.40), false)
		block("amber", Vector3(0.47, 0.08, 0.073), power + Vector3(x, 0.87, 1.47), false)
		block("frame", Vector3(0.34, 1.12, 0.27), power + Vector3(x, -1.51, 1.46), false)
		block("dark", Vector3(0.58, 1.64, 0.30), power + Vector3(x, -4.61, 0.57), false)
	_sign("RESEARCH POWER", power + Vector3(0, 2.82, 1.13), 0.0065)


func _lab_access() -> Dictionary:
	var at := Vector3(0, 0, LAB_GATE_Z)
	# Tall layered bastions silhouette the clinical pressure lock from the upper deck.
	for side in [-1.0, 1.0]:
		var x: float = side * 6.53
		block("frame", Vector3(1.57, 12.54, 2.35), at + Vector3(x, 6.27, -0.32))
		block("lab_enamel", Vector3(1.13, 10.76, 0.21), at + Vector3(x, 6.23, 0.94), false)
		block("dark", Vector3(0.34, 7.86, 0.36), at + Vector3(x - side * 0.19, 5.97, 1.03), false)
		block("lab_light", Vector3(0.095, 6.74, 0.13), at + Vector3(x - side * 0.19, 5.97, 1.25), false)
		block("dark", Vector3(2.02, 0.49, 2.52), at + Vector3(x, 0.245, -0.20), true, true)
	block("frame", Vector3(14.48, 1.42, 2.54), at + Vector3(0, 12.35, -0.60))
	block("lab_enamel", Vector3(13.32, 0.90, 0.18), at + Vector3(0, 12.30, 0.73), false)
	block("lab_light", Vector3(10.6, 0.094, 0.18), at + Vector3(0, 11.93, 0.86), false)
	for side in [-1.0, 1.0]:
		var x: float = side * 5.49
		block("teal", Vector3(0.73, 8.31, 5.10), Vector3(x, 4.16, -29.32))
		block("frame", Vector3(0.85, 8.7, 1.12), Vector3(x, 4.35, LAB_GATE_Z + 0.20))
		block("metal", Vector3(0.37, 6.94, 0.14), at + Vector3(x, 3.71, 0.78), false)
	block("frame", Vector3(12.20, 0.69, 3.95), at + Vector3(0, 8.64, -0.86))
	block("dark", Vector3(10.22, 1.36, 0.35), at + Vector3(0, 8.56, 1.09), false)
	_sign("回廊实验舱", at + Vector3(0, 8.83, 1.29), 0.012)
	_sign("RESEARCH ACCESS", at + Vector3(0, 8.21, 1.29), 0.0062)
	_research_passage()
	block("grate", Vector3(9.54, 0.035, 1.25), at + Vector3(0, 0.025, 0.53), false)
	_ceiling_fixture(at + Vector3(0, 8.20, -1.92), 6.93)
	var route := Node3D.new()
	route.name = "ResearchRoute"
	root.add_child(route)
	var arrows := Kit.new()
	arrows.material("cyan", kit.mats["cyan"])
	for z in [-18.4, -21.1, -23.8, -26.05, -29.06, -31.5, -34.2]:
		_arrow(arrows, Vector3(0, 0.048, z))
	arrows.commit(route, "LightedGuide", false)
	route.hide()

	var shutter := Node3D.new()
	shutter.name = "ResearchGate"
	shutter.position = at
	root.add_child(shutter)
	var leaf := Kit.new()
	for key in ["dark", "frame", "teal", "metal"]:
		leaf.material(key, kit.mats[key])
	var size := Vector3(10.45, 7.54, 0.53)
	var center := Vector3(0, 3.77, 0)
	leaf.box_bevel("frame", size, center, 0.12)
	for side in [-1.0, 1.0]:
		leaf.box_bevel("teal", Vector3(4.86, 6.88, 0.17), Vector3(side * 2.52, 3.82, 0.27), 0.095)
		leaf.box_bevel("dark", Vector3(0.23, 6.04, 0.21), Vector3(side * 4.86, 3.82, 0.28), 0.046)
		leaf.box_bevel("metal", Vector3(4.54, 0.17, 0.093), Vector3(side * 2.52, 1.04, 0.363), 0.028)
	leaf.commit(shutter, "GateLeaf", true, 1)
	var body := StaticBody3D.new()
	body.name = "ResearchGateCollider"
	body.position = center + Vector3.BACK * 0.15
	var shape := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = Vector3(size.x, size.y, 0.75)
	shape.shape = volume
	body.add_child(shape)
	shutter.add_child(body)
	var box := AABB(at + center - Vector3(size.x, size.y, 0.45) * 0.5,
		Vector3(size.x, size.y, 0.75))
	var index := solids.size()
	solids.append(box)
	var lamp := MeshInstance3D.new()
	var lens := BoxMesh.new()
	lens.size = Vector3(0.83, 0.20, 0.08)
	lamp.mesh = lens
	lamp.position = at + Vector3(4.17, 8.31, 1.304)
	var status := glow(Color("b68b63"), 0.90)
	lamp.material_override = status
	root.add_child(lamp)
	return {"shutter": shutter, "base": box, "index": index, "lamp": status, "route": route}


func _research_passage() -> void:
	# The transition happens inside this passage, beyond the shutter's actual plane.
	block("floor", Vector3(10.18, 0.60, 10.8), Vector3(0, -0.30, -37.28))
	block("teal", Vector3(10.18, 0.60, 10.8), Vector3(0, 8.10, -37.28))
	block("dark", Vector3(10.30, 8.0, 0.49), Vector3(0, 4.0, LAB_PASSAGE_BACK - 0.245))
	for side in [-1.0, 1.0]:
		var x: float = side * 5.14
		block("teal", Vector3(0.42, 8.0, 10.8), Vector3(x, 4.0, -37.28))
		for z in [-32.80, -36.76, -40.70]:
			block("frame", Vector3(0.53, 7.87, 0.57), Vector3(x - side * 0.32, 3.94, z), false)
			block("cyan", Vector3(0.10, 0.82, 0.075), Vector3(x - side * 0.62, 2.18, z), false)
		block("dark", Vector3(0.20, 0.31, 10.75), Vector3(x - side * 0.25, 0.16, -37.28), false)
	for z in [-32.80, -37.10, -41.35]:
		_ceiling_fixture(Vector3(0, 7.58, z), 6.24)
		block("grate", Vector3(9.65, 0.036, 0.52), Vector3(0, 0.022, z), false)
	light(Vector3(0, 6.3, -35.2), Color("d7e8e6"), 2.5, 12.0)


func _ceiling_fixture(at: Vector3, width: float) -> void:
	block("dark", Vector3(width, 0.24, 0.64), at, false)
	block("metal", Vector3(width - 0.18, 0.12, 0.52), at - Vector3.UP * 0.13, false)
	block("white", Vector3(width - 0.40, 0.050, 0.33), at - Vector3.UP * 0.19, false)
	for x in [-width * 0.39, width * 0.39]:
		block("frame", Vector3(0.41, 0.31, 0.51), at + Vector3(x, 0.23, 0), false)


func _duct(at: Vector3, yaw: float, width: float, label: String) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	kit.push_xf(xf)
	kit.box_bevel("frame", Vector3(width + 0.18, 1.36, 0.31), Vector3.ZERO, 0.058)
	kit.box_bevel("dark", Vector3(width, 1.07, 0.10), Vector3(0, 0, 0.17), 0.046)
	for i in 6:
		kit.box_bevel("metal", Vector3(width - 0.22, 0.055, 0.11), Vector3(0, -0.34 + i * 0.125, 0.24), 0.019)
	for side in [-1.0, 1.0]:
		for y in [-0.53, 0.53]:
			var screw := Vector3(side * (width * 0.5 - 0.04), y, 0.207)
			kit.tube("metal", [screw, screw + Vector3.BACK * 0.027], 0.038, 8)
	kit.box_bevel("dark", Vector3(1.24, 0.20, 0.30), Vector3(0, -0.73, 0.11), 0.038)
	kit.pop_xf()
	_sign(label, xf * Vector3(0, -0.73, 0.278), 0.0019, yaw)


func _arrow(batch, at: Vector3) -> void:
	batch.tube("cyan", [at + Vector3(-0.45, 0, 0.29), at - Vector3.BACK * 0.32,
		at + Vector3(0.45, 0, 0.29)], 0.036, 8)


func _sign(text: String, at: Vector3, size: float, yaw := 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = size
	label.modulate = Color("dedee2")
	label.outline_size = 4
	label.outline_modulate = Color("2d333b")
	label.position = at
	label.rotation.y = yaw
	root.add_child(label)
	return label


func _lighting() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("24282f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d7dbe5")
	env.ambient_light_energy = 0.39
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.25
	env.glow_enabled = true
	env.glow_intensity = 0.19
	var post := bool(TurnSession.get_option("display.post_fx", true))
	env.ssao_enabled = post
	env.ssao_radius = 0.88
	env.ssao_intensity = 1.06
	env.ssr_enabled = post
	env.ssr_max_steps = 22
	env.ssr_fade_out = 1.8
	env.ssr_depth_tolerance = 0.27
	world.environment = env
	root.add_child(world)
	for z in [-21.0, -7.0, 8.0, 22.0]:
		for x in [-25.0, 0.0, 25.0]:
			light(Vector3(x, 12.7 if x == 0 else 11.2, z), Color("e4e9f1"), 2.08, 19.0)
	light(Vector3(0.0, 18.2, 18.7), Color("e7ecf7"), 2.8, 22.0)
	light(Vector3(0.0, 6.45, -24.4), Color("b3e3f5"), 3.6, 13.9)
	for x in [-5.5, 5.5]:
		light(Vector3(x, 9.5, -23.95), Color("99d6ec"), 2.4, 8.8)
	for x in [-25.0, 25.0]:
		var wash := SpotLight3D.new()
		wash.light_color = Color("ccd6df")
		wash.light_energy = 3.2
		wash.spot_range = 22.0
		wash.spot_angle = 44.0
		var source := Vector3(x, 23.37, -23.0)
		var toward_wall := Vector3(0, -9.27, -8.8)
		wash.transform = Transform3D(Basis.looking_at(toward_wall, Vector3.UP), source)
		root.add_child(wash)

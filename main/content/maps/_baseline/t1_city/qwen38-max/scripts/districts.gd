class_name Districts
extends RefCounted
## Voronoi district map over normalized city space (0..1).

enum D { DOWNTOWN, COMMERCIAL, RES_HIGH, RES_LOW, SCHOOL, INDUSTRIAL, PARK, CIVIC }

var seeds := []

func _init(sd: int) -> void:
	var raw := [
		[0.50, 0.46, D.DOWNTOWN], [0.565, 0.535, D.DOWNTOWN],
		[0.425, 0.525, D.COMMERCIAL], [0.625, 0.415, D.COMMERCIAL], [0.505, 0.635, D.COMMERCIAL],
		[0.31, 0.36, D.RES_HIGH], [0.70, 0.60, D.RES_HIGH], [0.36, 0.685, D.RES_HIGH],
		[0.165, 0.50, D.RES_LOW], [0.80, 0.30, D.RES_LOW], [0.765, 0.745, D.RES_LOW], [0.24, 0.195, D.RES_LOW],
		[0.635, 0.705, D.SCHOOL], [0.285, 0.565, D.SCHOOL],
		[0.085, 0.135, D.INDUSTRIAL], [0.915, 0.865, D.INDUSTRIAL], [0.885, 0.10, D.INDUSTRIAL],
		[0.455, 0.285, D.PARK], [0.195, 0.78, D.PARK],
		[0.565, 0.355, D.CIVIC],
	]
	for r in raw:
		seeds.append({"pos": Vector2(r[0], r[1]), "type": int(r[2])})

func at(nx: float, nz: float) -> int:
	var best := 1e9
	var bt := int(D.DOWNTOWN)
	for s in seeds:
		var p: Vector2 = s.pos
		var d := (Vector2(nx, nz) - p).length()
		if d < best:
			best = d
			bt = s.type
	return bt

static func type_name(t: int) -> String:
	return ["downtown", "commercial", "res_high", "res_low", "school", "industrial", "park", "civic"][t]

## Height envelope + typology parameters per district.
static func params(t: int) -> Dictionary:
	match t:
		D.DOWNTOWN:
			return {"hmin": 70.0, "hmax": 330.0, "lot": 2600.0,
				"styles": [0, 0, 1, 6, 7, 0, 1], "neon": 0.9, "trees": 0.15, "podium": 0.8}
		D.COMMERCIAL:
			return {"hmin": 18.0, "hmax": 70.0, "lot": 1100.0,
				"styles": [1, 2, 3, 7, 1, 2], "neon": 1.0, "trees": 0.35, "podium": 0.3}
		D.RES_HIGH:
			return {"hmin": 35.0, "hmax": 110.0, "lot": 1500.0,
				"styles": [2, 2, 1, 0, 2], "neon": 0.35, "trees": 0.5, "podium": 0.2}
		D.RES_LOW:
			return {"hmin": 8.0, "hmax": 26.0, "lot": 480.0,
				"styles": [3, 2, 3, 2], "neon": 0.25, "trees": 0.8, "podium": 0.0}
		D.SCHOOL:
			return {"hmin": 10.0, "hmax": 24.0, "lot": 2200.0,
				"styles": [5, 5, 5, 1], "neon": 0.1, "trees": 0.9, "podium": 0.0}
		D.INDUSTRIAL:
			return {"hmin": 8.0, "hmax": 28.0, "lot": 3200.0,
				"styles": [4, 4, 4, 1], "neon": 0.2, "trees": 0.05, "podium": 0.0}
		D.PARK:
			return {"hmin": 0.0, "hmax": 0.0, "lot": 0.0,
				"styles": [], "neon": 0.1, "trees": 1.0, "podium": 0.0}
		_:
			return {"hmin": 25.0, "hmax": 70.0, "lot": 1600.0,
				"styles": [1, 7, 6, 1], "neon": 0.4, "trees": 0.4, "podium": 0.4}

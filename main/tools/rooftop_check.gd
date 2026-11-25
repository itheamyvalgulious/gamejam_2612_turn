extends SceneTree
## 临时路线检查：在真实 arena 数据上验证「计划站位 + 台面高度 + 侧墙不推人」。

const Arena = preload("res://runtime/levels/rooftop/arena/rooftop_arena.gd")
const Hit = preload("res://runtime/systems/room_shared/core/hitgd.gd")
const U := 1.0 / 0.547

# 米制：x, 期望台面高度, z
const ROUTE := [
	[-43.0, 0.0, 15.0, "出生点（大屋面）"],
	[-36.0, 1.0, 9.5, "垃圾箱顶"],
	[-31.8, 2.0, 10.0, "集装箱顶"],
	[-28.0, 3.0, 10.0, "机组顶"],
	[-25.6, 3.6, 6.0, "R1 西沿（落点）"],
	[-17.0, 3.6, -2.0, "R1 屋面中央"],
	[-7.6, 3.6, -2.0, "R1 东沿（起跳）"],
	[-2.4, 4.4, -3.0, "R2 西沿（落点）"],
	[8.0, 4.4, -3.0, "R2 屋面中央"],
	[18.4, 4.4, -3.0, "R2 东沿（起跳）"],
	[23.4, 3.4, 3.0, "R3 西沿（落点）"],
	[33.0, 3.4, 3.0, "R3 屋面中央"],
	[42.4, 3.4, 3.0, "R3 东沿（起跳）"],
	[47.4, 4.2, 4.0, "F 西沿（落点）"],
	[50.0, 4.2, 4.0, "F 屋面中央"],
]


func _init() -> void:
	var arena: Dictionary = Arena.build(Vector3.ZERO)
	var plats: Array = arena["platforms"]
	var cover: Array = arena["cover"]
	print("platforms=%d cover=%d" % [plats.size(), cover.size()])
	var bad := 0
	for r in ROUTE:
		var p := Vector3(float(r[0]), float(r[1]), float(r[2])) * U
		var want: float = float(r[1]) * U
		var got := _platform_height(plats, p)
		var moved := Hit.resolve_circles(p, 1.1, cover, p.y)
		var push := Vector2(moved.x - p.x, moved.z - p.z).length() / U
		var ok := absf(got - want) < 0.12 and push < 0.05
		if not ok:
			bad += 1
		print("%s  %-18s  台面=%.2fm 期望=%.2fm 侧推=%.2fm" % [
			"OK  " if ok else "BAD ", String(r[3]), got / U, want / U, push])
	print("路线节点异常：%d" % bad)

	# 每个台面至少要有能站住的点（窄圆顶会被侧墙一直推开）
	var dead := 0
	for pl in plats:
		var c: Vector3 = pl["c"]
		var hx: float = float(pl["hx"])
		var hz: float = float(pl["hz"])
		var top: float = float(pl["h"])
		var free := 0
		for ix in 5:
			for iz in 5:
				var px := c.x + (float(ix) / 4.0 * 2.0 - 1.0) * hx * 0.8
				var pz := c.z + (float(iz) / 4.0 * 2.0 - 1.0) * hz * 0.8
				var q := Vector3(px, top, pz)
				var r := Hit.resolve_circles(q, 1.1, cover, top)
				if Vector2(r.x - q.x, r.z - q.z).length() < 0.02:
					free += 1
		if free == 0:
			dead += 1
			print("DEAD 台面 %s 顶=%.2fm 无站立点" % [str(c / U), top / U])
	print("无法站立的台面：%d" % dead)
	quit(0 if bad == 0 and dead == 0 else 1)


func _platform_height(plats: Array, p: Vector3) -> float:
	var best := 0.0
	const MARGIN := 0.6
	for pl in plats:
		var c: Vector3 = pl["c"]
		var hx: float = float(pl["hx"])
		var hz: float = float(pl["hz"])
		var top: float = float(pl["h"])
		var mx: float = hx if bool(pl.get("strict", false)) else hx + MARGIN
		var mz: float = hz if bool(pl.get("strict", false)) else hz + MARGIN
		if absf(p.x - c.x) <= mx and absf(p.z - c.z) <= mz:
			if p.y >= top - 0.10 and top >= best:
				best = top
	return best

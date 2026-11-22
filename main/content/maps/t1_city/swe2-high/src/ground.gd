extends RefCounted

## Flat city pad: gentle relief, dredged river channel, quay walls.
## h(x,z) is cheap (fbm + channel carve) so 4×2.5 km stays fast.

var river_pts: PackedVector2Array
var _seed := 1


func setup(river: PackedVector2Array, seed: int) -> void:
	river_pts = river
	_seed = seed


func _n2(x: float, z: float, s: int) -> float:
	var v := sin(x * 0.0173 + float(s) * 13.7) * cos(z * 0.0211 + float(s) * 7.3)
	return v * 0.5 + 0.5


func _fbm2(x: float, z: float) -> float:
	var s := 0.0
	var a := 0.5
	var fx := x
	var fz := z
	for i in 4:
		s += a * _n2(fx, fz, i * 131)
		fx = fx * 2.03 + 11.7
		fz = fz * 2.01 + 3.1
		a *= 0.5
	return s


func river_dist(p: Vector2) -> float:
	var d := 1e9
	for i in river_pts.size():
		d = minf(d, p.distance_to(river_pts[i]))
	return d


func h(x: float, z: float) -> float:
	# base relief: gentle 0–14 m swell, flattened inside the CBD grid
	var y := _fbm2(x * 0.004, z * 0.004) * 14.0 - 4.0
	# river channel: dredge 9 m below water level (y=-6 water surface)
	var rd := river_dist(Vector2(x, z))
	var chan := smoothstep(46.0, 12.0, rd)
	y = lerpf(y, -11.0, chan)
	# quay walls: flat +0.5 m apron right at the water edge
	var quay := smoothstep(60.0, 46.0, rd) * (1.0 - chan)
	y = lerpf(y, 0.6, quay)
	# gentle bowl toward the centre so towers sit on believable ground
	var r := Vector2(x, z).length()
	y += smoothstep(1600.0, 400.0, r) * 2.0
	return y

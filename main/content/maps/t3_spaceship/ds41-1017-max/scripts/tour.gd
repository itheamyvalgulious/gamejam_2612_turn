extends Node

## Guided tour: follows the main route from the stern engine bays to the bridge.
## Starts in a "preview" state and can be toggled with F.

var main: Node
var cfg: ShipConfig
var camera: Camera3D

var running := false
var dist := 0.0
var speed := 7.5
var total := 0.0
var segments: Array = []     # [start_dist, a, b, length]
var pos := Vector3.ZERO
var look := Vector3.ZERO
var initialised := false
var pause_timer := 0.0
var pause_at: Array = []
var next_pause := 0


func _ready() -> void:
	_build()
	pos = camera.global_position
	look = pos + Vector3(0, 0, -8)


func _build() -> void:
	total = 0.0
	segments.clear()
	for i in range(cfg.route.size() - 1):
		var a: Vector3 = cfg.route[i]
		var b: Vector3 = cfg.route[i + 1]
		var len := a.distance_to(b)
		segments.append([total, a, b, len])
		total += len
	# pause roughly at the entry of each signature space
	pause_at = [20.0, 104.0, 170.0, 216.0, 266.0]


func is_running() -> bool:
	return running


func toggle() -> void:
	if main.tour == null:
		return
	running = not running
	if running:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if main.hud:
			main.hud.tour_active = true
		dist = 0.0
		pause_timer = 0.0
		next_pause = 0
		snap_to(dist)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if main.hud:
			main.hud.tour_active = false


func snap_to(d: float) -> void:
	dist = clampf(d, 0.0, total)
	var s := sample(dist)
	pos = s[0]
	look = s[0] + s[1] * 9.0
	camera.global_position = pos
	camera.look_at(look, Vector3.UP)


func sample(d: float) -> Array:
	d = clampf(d, 0.0, total)
	for i in range(segments.size() - 1, -1, -1):
		var seg: Array = segments[i]
		if d >= float(seg[0]) or i == 0:
			var t: float = clampf((d - float(seg[0])) / maxf(float(seg[3]), 0.001), 0.0, 1.0)
			var p: Vector3 = (seg[1] as Vector3).lerp(seg[2], t)
			var look_pt: Vector3 = p + Vector3(0, 0, -6)
			if cfg.route_look.size() == cfg.route.size():
				var la: Vector3 = cfg.route_look[i]
				var lb: Vector3 = cfg.route_look[i + 1]
				look_pt = la.lerp(lb, t)
			var dir := (look_pt - p)
			if dir.length() < 0.01:
				dir = (seg[2] - seg[1])
			return [p, dir.normalized()]
	return [cfg.route[0], Vector3.FORWARD]


func _raw_sample(d: float) -> Vector3:
	d = clampf(d, 0.0, total)
	for i in range(segments.size() - 1, -1, -1):
		var seg: Array = segments[i]
		if d >= float(seg[0]) or i == 0:
			var t: float = clampf((d - float(seg[0])) / maxf(float(seg[3]), 0.001), 0.0, 1.0)
			return (seg[1] as Vector3).lerp(seg[2], t)
	return cfg.route[0]


func _process(dt: float) -> void:
	if not running or camera == null:
		return
	if pause_timer > 0.0:
		pause_timer -= dt
		camera.global_position = camera.global_position.lerp(pos, 0.1)
		camera.look_at(look, Vector3.UP)
		return
	dist += speed * dt
	if next_pause < pause_at.size() and dist >= float(pause_at[next_pause]):
		pause_timer = 2.2
		next_pause += 1
	if dist >= total:
		dist = total
		running = false
		if main.hud:
			main.hud.tour_active = false
	var s := sample(dist)
	pos = pos.lerp(s[0], 0.18)
	var target: Vector3 = s[0] + (s[1] as Vector3) * 9.0
	look = look.lerp(target, 0.10)
	camera.global_position = pos
	camera.look_at(look, Vector3.UP)
	if main.hud:
		main.hud.tour_progress = dist / maxf(total, 1.0)
extends Node3D
## Third-person combat camera with cinematic shot support, spring damping,
## FOV kick and deterministic shake.

var camera: Camera3D
var target: Node3D

# shot parameters (distance/height/focus are in metres)
var yaw := 2.60
var distance := 6.4
var height := 1.65
var focus_height := 1.25
var fov := 40.0
var world_yaw := 0.0
var use_world_yaw := false
var follow_rate := 5.5

var shake_energy := 0.0
var speed_kick := 0.0

# ---------------- FPS / custom anchor mode -------------------------------
## fps_mode welds the camera to the character.  The anchor is the head camera
## pod (the blue eye) when present, else a fixed head-height point.  The boom
## arm is a character-space vector: fps_offset sets it directly (the 1-6 keys,
## +X right / +Y up / +Z back) and fps_orbit_lon/lat rotate the SAME basis for
## both the arm and the view direction (the 7-0 keys):
##   position = anchor + char_basis * orbit(fps_offset + (0,0,fps_dolly))
##   view     = char_basis * orbit(-Z)        — keys own the aim, always.
## A pure +Z boom lies on the view axis, so orbiting it yields a natural
## orbit-around-the-head rig; adding X/Y shifts gives a parallel view.
## fps_dolly is the dedicated "camera<->subject" distance along the view axis
## ([ / ] keys and the wheel): + pulls the camera back (arms look smaller),
## - pushes in (bigger).  It is tracked separately from offset.z so export
## and HUD read the intent, not a merged value.
var fps_mode := false
var fps_offset := Vector3.ZERO
var fps_orbit_lon := 0.0     # rad; + pans the view right (camera swings left)
var fps_orbit_lat := 0.0     # rad; + pitches the view up (camera dives low)
var fps_fov := 55.0          # uniform FOV, degrees (- / = keys)
var fps_dolly := 0.0         # m along view axis; + farther / - nearer
var fps_follow_rate := 30.0

const FPS_OFFSET_LIMIT := Vector3(1.2, 1.2, 4.0)
const FPS_DOLLY_LIMIT := Vector2(-2.0, 6.0)
const FPS_LON_LIMIT := PI
const FPS_LAT_LIMIT := PI * 0.5
const FPS_FOV_LIMIT := Vector2(10.0, 160.0)

var _sm_pos := Vector3.ZERO
var _sm_focus := Vector3.ZERO
var _initialized := false
var _shake_t := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.08
	camera.far = 180.0
	add_child(camera)


func snap() -> void:
	_initialized = false


func set_shot(p_yaw: float, p_distance: float, p_height: float, p_focus: float, p_fov: float,
		p_world := false, p_world_yaw := 0.0) -> void:
	yaw = p_yaw
	distance = p_distance
	height = p_height
	focus_height = p_focus
	fov = p_fov
	use_world_yaw = p_world
	world_yaw = p_world_yaw


func add_shake(amount: float) -> void:
	shake_energy = minf(1.4, shake_energy + amount)


func set_fps_mode(on: bool) -> void:
	fps_mode = on
	if on:
		fps_offset = Vector3.ZERO
		fps_orbit_lon = 0.0
		fps_orbit_lat = 0.0
		fps_fov = 55.0
		fps_dolly = 0.0
	_initialized = false    # same as snap()
	if target != null and target.has_method("set_body_hidden"):
		# FPS shows only arms + sword; everything else is hidden by the rig.
		target.set_body_hidden(on)


## d_offset in character space (+X right / +Y up / +Z back),
## d_lon / d_lat in radians.
func adjust_fps(d_offset: Vector3, d_lon: float, d_lat: float) -> void:
	var o := fps_offset + d_offset
	fps_offset = Vector3(
		clampf(o.x, -FPS_OFFSET_LIMIT.x, FPS_OFFSET_LIMIT.x),
		clampf(o.y, -FPS_OFFSET_LIMIT.y, FPS_OFFSET_LIMIT.y),
		clampf(o.z, -FPS_OFFSET_LIMIT.z, FPS_OFFSET_LIMIT.z))
	fps_orbit_lon = clampf(fps_orbit_lon + d_lon, -FPS_LON_LIMIT, FPS_LON_LIMIT)
	fps_orbit_lat = clampf(fps_orbit_lat + d_lat, -FPS_LAT_LIMIT, FPS_LAT_LIMIT)


## Uniform FOV zoom, degrees (- / = keys).
func adjust_fov(d: float) -> void:
	fps_fov = clampf(fps_fov + d, FPS_FOV_LIMIT.x, FPS_FOV_LIMIT.y)


## Camera<->subject distance along the view axis, metres ([ / ] + wheel).
func adjust_dolly(d: float) -> void:
	fps_dolly = clampf(fps_dolly + d, FPS_DOLLY_LIMIT.x, FPS_DOLLY_LIMIT.y)


## Export the live camera transform + all tuning parameters as JSON.
## Writes to res://renders/ when possible (falls back to user://) and mirrors
## the text to the clipboard.  Returns the JSON string.
func export_camera_transform(path := "res://renders/fps_camera_export.json") -> String:
	var gt := camera.global_transform
	var b := gt.basis
	var data := {
		"mode": "fps" if fps_mode else "third_person",
		"time_unix": int(Time.get_unix_time_from_system()),
		"transform": {
			"position": _v3(gt.origin),
			"basis": {
				"x": _v3(b.x), "y": _v3(b.y), "z": _v3(b.z),
			},
			"euler_yxz": _v3(gt.basis.get_euler()),
			"forward": _v3(-b.z),
		},
		"camera": {"fov": camera.fov, "near": camera.near, "far": camera.far},
		"fps": {
			"offset": _v3(fps_offset),
			"orbit_lon": fps_orbit_lon,
			"orbit_lat": fps_orbit_lat,
			"fov": fps_fov,
			"dolly": fps_dolly,
		},
		"third_person": {
			"yaw": yaw, "distance": distance, "height": height,
			"focus_height": focus_height, "fov": fov,
			"use_world_yaw": use_world_yaw, "world_yaw": world_yaw,
		},
	}
	if target != null:
		data["target"] = {
			"position": _v3(target.global_position),
			"rotation_y": target.rotation.y,
		}
		if target.get("heading") != null:
			data["target"]["heading"] = target.heading
	var text := JSON.stringify(data, "  ")
	var dir := path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(path, FileAccess.WRITE)
	var written := ""
	if f != null:
		f.store_string(text)
		f.close()
		written = path
	else:
		var alt := "user://fps_camera_export.json"
		f = FileAccess.open(alt, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			written = alt
	DisplayServer.clipboard_set(text)
	print("[camera] transform exported -> %s" % (written if written != "" else "(clipboard only)"))
	return text


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Desired camera position + focus for the FPS boom (world space).
func _fps_desired() -> Array:
	var basis := target.global_transform.basis
	var anchor: Vector3 = target.global_position + Vector3(0, 1.9, 0)
	var hc = target.get("head_camera")
	if hc != null and is_instance_valid(hc):
		anchor = (hc as Node3D).global_position
	var orbit := Basis(Vector3.UP, -fps_orbit_lon) * Basis(Vector3.RIGHT, fps_orbit_lat)
	var local: Vector3 = orbit * (fps_offset + Vector3(0, 0, fps_dolly))
	var pos: Vector3 = anchor + basis * local
	pos.y = maxf(pos.y, 0.45)
	# The view direction is always the character forward swung by lon/lat —
	# never a look-at-head fallback.  A pure +Z offset happens to lie on that
	# ray, which is why a back boom auto-frames the head while orbiting.
	var focus: Vector3 = pos + basis * (orbit * Vector3(0, 0, -8.0))
	return [pos, focus]


## look_at with an up vector that survives near-vertical views (lat ~ +-90°).
func _look_at_safe(look: Vector3) -> void:
	var fwd := look - camera.global_position
	if fwd.length_squared() < 1e-6:
		return
	var up := Vector3.UP
	if absf(fwd.normalized().y) > 0.985:
		up = -target.global_transform.basis.z
		up.y = 0.0
		up = up.normalized() if up.length_squared() > 1e-4 else Vector3.BACK
	camera.look_at(look, up)


func update_camera(dt: float, speed: float) -> void:
	if target == null:
		return
	_shake_t += dt
	var des: Vector3
	var focus: Vector3
	var rate := follow_rate
	var want_fov := fov
	if fps_mode:
		var fps := _fps_desired()
		des = fps[0]
		focus = fps[1]
		rate = fps_follow_rate
		want_fov = fps_fov
	else:
		var base_yaw: float = world_yaw if use_world_yaw else target.rotation.y + yaw
		focus = target.global_position + Vector3(0, focus_height, 0)
		des = target.global_position + Vector3(0, height, 0) \
			+ Basis(Vector3.UP, base_yaw) * Vector3(0, 0, distance)
		# keep the lens off the floor
		des.y = maxf(des.y, 0.55)
	if not _initialized:
		_sm_pos = des
		_sm_focus = focus
		_initialized = true
	else:
		var k := 1.0 - exp(-rate * dt)
		_sm_pos = _sm_pos.lerp(des, k)
		_sm_focus = _sm_focus.lerp(focus, 1.0 - exp(-8.0 * dt))
	speed_kick = lerpf(speed_kick, clampf((speed - 2.0) * 0.25, 0.0, 3.2), 1.0 - exp(-4.0 * dt))
	shake_energy = maxf(0.0, shake_energy - dt * 2.4)
	var sh := shake_energy * shake_energy
	var shake_off := Vector3(
		sin(_shake_t * 87.0) * sh * 0.12,
		cos(_shake_t * 71.0) * sh * 0.09,
		sin(_shake_t * 53.0 + 1.0) * sh * 0.07)
	camera.global_position = _sm_pos + shake_off
	var look := _sm_focus + Vector3(sin(_shake_t * 93.0), cos(_shake_t * 67.0), 0.0) * sh * 0.045
	_look_at_safe(look)
	camera.fov = lerpf(camera.fov, want_fov + speed_kick, 1.0 - exp(-6.0 * dt))
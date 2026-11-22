extends Node3D
## Standalone geometry probe for the VESPER chassis.
##
##   godot --headless --path . res://scenes/test_body.tscn
##
## Builds only BodyBuilder (no rig motion, no weapon animation) and measures the
## world AABB of every mesh.  The greatsword and the contact-shadow decal are
## excluded from the silhouette numbers: the sword is a held prop and its raised
## tip would dominate the height.
##
## Checks
##   total height (head included)     1.95 .. 2.05 m
##   upper-chassis horizontal radius  <= 0.55 m
##   lowest point                     >= -0.01 m
##   rest knee interior angle         130 .. 140 deg

const BB = preload("res://scripts/mech/body_builder.gd")
const P := {
	"hip_y": 1.235, "hip_r": 0.30, "femur": 0.60, "tibia": 0.66,
	"foot_r": 0.50, "ankle_h": 0.08, "waist_y": 0.12,
	"torso_scale": 0.82, "upper": 0.452, "fore": 0.422, "grip": 0.16,
	"arm_w": 0.74,
	"upper_scale": 1.35, "lower_scale": 0.78,
	"blade_y0": 0.28, "blade_len": 1.25,
}

var body: Node3D
var lower_body: Node3D
var torso: Node3D
var head: Node3D
var reactor_ring: Node3D
var chest_light: OmniLight3D
var thruster_light: OmniLight3D
var weapon_root: Node3D
var weapon_spin: Node3D
var weapon_light: OmniLight3D
var blade_base: Marker3D
var blade_tip: Marker3D
var contact_shadow: MeshInstance3D
var head_camera: Node3D
var head_green_dot: MeshInstance3D
var lens_material: ShaderMaterial
var lens_light: OmniLight3D
var legs: Array = []
var arms: Array = []
var pauldrons: Array = []
var thruster_nodes: Array = []
var engine_petals: Array = []
var left_indicator_meshes: Array = []
var hair_anchor: Node3D

var _fails: Array[String] = []
var _cam: Camera3D


func _ready() -> void:
	BB.build(self)
	_build_stage()
	await get_tree().process_frame
	await get_tree().process_frame
	_report()
	var shot := OS.get_environment("VESPER_SHOT")
	if shot != "":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("SHOT=", shot)
	get_tree().quit(0 if _fails.is_empty() else 1)


# ------------------------------------------------------------------- measure
func _collect() -> Dictionary:
	var all_bb := AABB()
	var upper_bb := AABB()
	var leg_bb := AABB()
	var have := {"all": false, "upper": false, "leg": false}
	var floor_y := INF
	var top_y := -INF
	var radius_all := 0.0
	var radius_upper := 0.0
	var per_leg_floor := [INF, INF, INF, INF]
	var wide: Array = []
	var upper_wide: Array = []

	var stack: Array = [body]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var in_weapon: bool = n == weapon_root or (weapon_root != null and weapon_root.is_ancestor_of(n))
		var in_shadow: bool = n == contact_shadow
		var leg_index := -1
		for i in legs.size():
			var lr: Node3D = legs[i]["root"]
			if n == lr or lr.is_ancestor_of(n):
				leg_index = i
				break
		if n is MeshInstance3D and not in_weapon and not in_shadow:
			var mi: MeshInstance3D = n
			var mbx := _mesh_bounds(mi)
			var mb: AABB = mbx["aabb"]
			var mr: float = mbx["radius"]
			all_bb = mb if not have["all"] else all_bb.merge(mb)
			have["all"] = true
			floor_y = minf(floor_y, mb.position.y)
			top_y = maxf(top_y, mb.end.y)
			radius_all = maxf(radius_all, mr)
			if mr > 0.48:
				wide.append([String(mi.name), mr, mb.position, mb.end])
			if leg_index >= 0:
				leg_bb = mb if not have["leg"] else leg_bb.merge(mb)
				have["leg"] = true
				per_leg_floor[leg_index] = minf(per_leg_floor[leg_index], mb.position.y)
			else:
				upper_bb = mb if not have["upper"] else upper_bb.merge(mb)
				have["upper"] = true
				radius_upper = maxf(radius_upper, mr)
				if mr > 0.45:
					upper_wide.append([String(mi.name), mr, mb.position, mb.end])
		for c in n.get_children():
			if c is Node3D:
				stack.append(c)

	return {
		"all": all_bb, "upper": upper_bb, "leg": leg_bb,
		"floor": floor_y, "top": top_y,
		"radius_all": radius_all, "radius_upper": radius_upper,
		"leg_floors": per_leg_floor, "wide": wide, "upper_wide": upper_wide,
	}


func _radius_of(a: AABB) -> float:
	var r := 0.0
	for i in 8:
		var p := a.get_endpoint(i)
		r = maxf(r, sqrt(p.x * p.x + p.z * p.z))
	return r


## Exact world-space bounds: transforms every vertex instead of trusting the
## axis-aligned box of a yawed / bent leg, which overstates radius badly.
func _mesh_bounds(mi: MeshInstance3D) -> Dictionary:
	var xf := mi.global_transform
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		var b: AABB = xf * mi.mesh.get_aabb()
		return {"aabb": b, "radius": _radius_of(b)}
	var p0 := xf * verts[0]
	var mn := p0
	var mx := p0
	var r := 0.0
	for i in verts.size():
		var p := xf * verts[i]
		mn = mn.min(p)
		mx = mx.max(p)
		r = maxf(r, sqrt(p.x * p.x + p.z * p.z))
	return {"aabb": AABB(mn, mx - mn), "radius": r}


func _report() -> void:
	print("\n=== VESPER BODY BUILD ===")
	var m := _collect()
	var height: float = float(m["top"]) - float(m["floor"])

	print("HEIGHT=%.3f m   (top %.3f / floor %.3f)" % [height, m["top"], m["floor"]])
	print("CHASSIS_RADIUS=%.3f m" % m["radius_upper"])
	print("STANCE_RADIUS=%.3f m   (incl. splayed legs)" % m["radius_all"])
	print("KNEE_ANALYTIC=%.2f deg" % _knee_from_params())
	if not m["upper_wide"].is_empty():
		m["upper_wide"].sort_custom(func(a, b): return float(a[1]) > float(b[1]))
		print("WIDEST_CHASSIS=", m["upper_wide"].slice(0, 3))

	var knee_sum := 0.0
	for i in legs.size():
		var hip: Node3D = legs[i]["hip"]
		var knee: Node3D = legs[i]["knee"]
		var ankle: Node3D = legs[i]["ankle"]
		var a := hip.global_position - knee.global_position
		var b := ankle.global_position - knee.global_position
		var ang := rad_to_deg(a.angle_to(b))
		knee_sum += ang
		print("KNEE%d=%.2f deg   foot_floor=%.4f" % [i, ang, m["leg_floors"][i]])
	var knee := knee_sum / float(maxi(legs.size(), 1))
	print("KNEE_MEAN=%.2f deg" % knee)

	print("NODES legs=%d arms=%d pauldrons=%d thrusters=%d indicators=%d" % [
		legs.size(), arms.size(), pauldrons.size(), thruster_nodes.size(),
		left_indicator_meshes.size()])
	print("LINKS head=%s hair_anchor=%s reactor=%s chest_light=%s blade_markers=%s" % [
		head != null, hair_anchor != null, reactor_ring != null, chest_light != null,
		blade_base != null and blade_tip != null])

	# ---- contract checks -------------------------------------------------
	var params: Dictionary = BB.params()
	var params_ok := true
	for k in P:
		if not params.has(k) or params[k] != P[k]:
			params_ok = false
			print("  PARAM MISMATCH ", k, " got ", params.get(k), " want ", P[k])
	_check(params_ok, "P matches the contract dict")
	_check(absf(body.position.y - float(P["hip_y"]) * float(P["lower_scale"])) < 0.001, "body at hip_y * lower_scale")
	_check(absf(torso.position.y - float(P["waist_y"])) < 0.001, "torso at waist_y")
	_check(absf(torso.scale.x - float(P["torso_scale"]) * float(P["upper_scale"])) < 0.001, "torso scale = 0.82 * upper_scale")
	_check(absf(weapon_spin.rotation.y - 2.35) < 0.001, "weapon_spin yaw 2.35")
	_check(legs.size() == 4 and arms.size() == 2, "4 legs / 2 arms")
	_check(thruster_nodes.size() == 2, "dual symmetrical vector engines")
	_check(engine_petals.size() >= 16, "iris nozzle petals")
	for t in thruster_nodes:
		var flame: Node = t.get_node_or_null("flame")
		_check(flame != null and flame is MeshInstance3D, "thruster has flame child")
	_check(left_indicator_meshes.size() >= 4, "left forearm indicator array")
	_check(arms.size() == 2 and float(arms[0]["side"]) > 0.0, "arms[0] is the right arm")

	# blade geometry: markers must sit inside the 0.28 .. 1.53 blade span
	var by0: float = float(P["blade_y0"])
	var by1: float = by0 + float(P["blade_len"])
	var b0: float = blade_base.position.y
	var b1: float = blade_tip.position.y
	_check(b0 > by0 and b0 < by1 and b1 > b0 and b1 <= by1 + 0.001,
		"blade markers inside 0.28..1.53")
	print("BLADE_MARKERS y=%.3f .. %.3f" % [b0, b1])

	# ---- silhouette ------------------------------------------------------
	_check(height >= 1.95 and height <= 2.10, "height 1.95-2.10 m")
	_check(float(m["radius_upper"]) <= 0.80, "chassis radius <= 0.80 m")
	_check(float(m["floor"]) >= -0.01, "lowest point >= -0.01 m")
	_check(knee >= 130.0 and knee <= 140.0, "rest knee 130-140 deg")
	# every sole should be on the ground, not just the average
	for i in legs.size():
		_check(absf(float(m["leg_floors"][i])) <= 0.012, "leg %d sole on ground" % i)

	if _fails.is_empty():
		print("RESULT: PASS\n")
	else:
		print("RESULT: FAIL -> ", _fails, "\n")


func _knee_from_params() -> float:
	var f: float = float(P["femur"])
	var t: float = float(P["tibia"])
	var d := float(P["foot_r"]) - float(P["hip_r"])
	var h := float(P["ankle_h"]) - float(P["hip_y"])
	var reach := sqrt(d * d + h * h)
	var bb := acos(clampf((f * f + t * t - reach * reach) / (2.0 * f * t), -1.0, 1.0))
	return rad_to_deg(bb)


func _check(ok: bool, label: String) -> void:
	var tag := "PASS" if ok else "FAIL"
	print("  [%s] %s" % [tag, label])
	if not ok:
		_fails.append(label)


# --------------------------------------------------------------------- stage
func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skm := ProceduralSkyMaterial.new()
	skm.sky_top_color = Color(0.05, 0.07, 0.12)
	skm.sky_horizon_color = Color(0.11, 0.14, 0.20)
	skm.ground_horizon_color = Color(0.05, 0.06, 0.08)
	skm.ground_bottom_color = Color(0.02, 0.022, 0.03)
	sky.sky_material = skm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.09, 0.10, 0.12)
	gm.metallic = 0.15
	gm.roughness = 0.82
	ground.material_override = gm
	self.add_child(ground)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, 135, 0)
	key.light_energy = 2.4
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -135, 0)
	fill.light_energy = 0.9
	fill.light_color = Color(0.50, 0.70, 1.0)
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12, 10, 0)
	rim.light_energy = 1.0
	rim.light_color = Color(0.55, 0.78, 1.0)
	add_child(rim)

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	_cam = cam
	var eye := Vector3(2.35, 1.35, -3.10)
	var look := Vector3(0.0, 1.06, 0.0)
	var custom := OS.get_environment("VESPER_CAM")
	if custom != "":
		var v := custom.split(",")
		if v.size() == 6:
			eye = Vector3(float(v[0]), float(v[1]), float(v[2]))
			look = Vector3(float(v[3]), float(v[4]), float(v[5]))
	cam.look_at_from_position(eye, look, Vector3.UP)
extends RefCounted
## Isolated Cargo Hold2. Geometry and collision share the same measurements.
const Kit = preload("res://src/cargo_hold2/mesh_kit.gd")
const CargoContainer = preload("res://src/cargo_hold2/container.gd")
const HALF_WIDTH := 40.0
const HALF_DEPTH := 30.0
const CEILING := 16.0
const PLAYER_SPAWN := Vector3(0, 0, 25)
const BASIC_SPAWN := Vector3(0, 0, -25)
const NormalMap = preload("res://src/cargo_hold2/container_normal.gd")
const SIZE := Vector3(8.0, 6.0, 6.0)
const CYAN := Color("36dceb")
const AMBER := Color("ffb45e")

static func shader_mat(file: String, values: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://gfx/cargo_hold2/" + file + ".gdshader")
	for key in values:
		mat.set_shader_parameter(key, values[key])
	return mat

static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.lerp(Color.WHITE, 0.25)
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.28
	return mat

static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "CargoHold2Environment"
	var kit := Kit.new()
	kit.material("floor", shader_mat("plate", {"base_col": Color("303c46"), "tile_m": 2.0, "rough_bias": 0.15}))
	kit.material("wall", shader_mat("wall", {"base_col": Color("414d5b"), "trim_col": Color("202833"), "style": 4, "grime": 0.55}))
	for pair in [["metal", "8796a5"], ["metal_dark", "202833"], ["orion_frame", "414d5b"]]:
		kit.material(pair[0], shader_mat("metal", {"tint": Color(pair[1]), "rough_base": 0.52, "rust_amount": 0.14, "oil_grime": 0.2}))
	for i in 3:
		kit.material("container_" + str(i), shader_mat("container", {"paint": [Color("315c66"), Color("aa783f"), Color("536377")][i], "seed": float(i + 2), "rust": 0.15, "surface_normal": NormalMap.texture()}))
	kit.material("cyan", glow(CYAN))
	kit.material("laser_cyan", shader_mat("neon_flow", {"tint": CYAN}))
	kit.material("laser_violet", shader_mat("neon_flow", {"tint": Color("ae69ff"), "speed": -0.5}))
	kit.material("amber", glow(AMBER, 1.6))
	kit.material("white", glow(Color("dceaf2"), 2.4))
	# Floor top is exactly y=0. Walls start outside the playable footprint.
	kit.box("floor", Vector3(81, 0.6, 61), Vector3(0, -0.3, 0))
	kit.box("metal_dark", Vector3(81, 0.6, 61), Vector3(0, 16.3, 0))
	var solids: Array[AABB] = []
	var walls: Array = []
	for x in [-40.4, 40.4]:
		kit.box("wall", Vector3(0.8, 16, 60), Vector3(x, 8, 0))
		body(root, Vector3(x, 8, 0), Vector3(0.8, 16, 60))
	for z in [-30.4, 30.4]:
		kit.box("wall", Vector3(81.6, 16, 0.8), Vector3(0, 8, z))
		body(root, Vector3(0, 8, z), Vector3(81.6, 16, 0.8))
	add_rect_walls(walls, Rect2(-40, -30, 80, 60), 16)
	body(root, Vector3(0, -0.3, 0), Vector3(81, 0.6, 61))
	body(root, Vector3(0, 16.3, 0), Vector3(81, 0.6, 61))
	var props := CargoContainer.new(kit)
	var anchors: Array[Vector3] = []
	var ordinal := 0
	for z in [11.0, -11.0]:
		for x in [-28.0, -8.0, 12.0]:
			var p := Vector3(x, 0, z)
			props.container(p, "container_" + str(ordinal % 3), 0.0, SIZE)
			# Include structural frames and lock bars in collision extents.
			var box := AABB(p + Vector3(-4.30, 0, -3.20), Vector3(8.60, 6.05, 6.40))
			solids.append(box)
			body(root, box.get_center(), box.size)
			add_rect_walls(walls, Rect2(box.position.x, box.position.z, box.size.x, box.size.z), box.size.y)
			var anchor := Vector3(x + 10, 0, z)
			anchors.append(anchor)
			kit.torus("cyan", 1.50, 0.035, 48, 8, anchor + Vector3(0, 0.045, 0))
			for side in [-1.0, 1.0]:
				kit.box("amber", Vector3(0.08, 0.025, 2.5), anchor + Vector3(side * 2.0, 0.025, 0))
			ordinal += 1
	# Structural ribs sit above the actor envelope or at the room boundary.
	for z in [-27.0, -18.0, -9.0, 0.0, 9.0, 18.0, 27.0]:
		kit.box_bevel("orion_frame", Vector3(79.8, 0.65, 0.6), Vector3(0, 15.6, z), 0.08)
		for x in [-39.8, 39.8]:
			kit.box_bevel("orion_frame", Vector3(0.4, 15.4, 0.6), Vector3(x, 7.7, z), 0.05)
	# Neon tubes have metal housings, cylindrical cores and capped ends.
	for x in [-32.0, 0.0, 32.0]:
		for z in [-20.0, 0.0, 20.0]:
			kit.box_bevel("metal_dark", Vector3(0.45, 0.3, 5), Vector3(x, 14.6, z), 0.06)
			lit_tube(kit, root, "cyan" if x != 0 else "white", [Vector3(x, 14.4, z-2.3), Vector3(x, 14.4, z+2.3)], 0.065, 12)
			for dz in [-2.35, 2.35]:
				kit.box("metal", Vector3(0.28, 0.22, 0.18), Vector3(x, 14.45, z+dz))
	for x in [-39.65, 39.65]:
		for z in [-20.0, 0.0, 20.0]:
			kit.box("metal_dark", Vector3(0.16, 0.4, 7), Vector3(x, 3.5, z))
			lit_tube(kit, root, "cyan", [Vector3(x-signf(x)*0.1, 3.5, z-3), Vector3(x-signf(x)*0.1, 3.5, z+3)], 0.045, 10)
	# Raised service trunks, clamps and solid vent slats add industrial depth.
	for side in [-1.0, 1.0]:
		for y in [7.8, 8.4]:
			lit_tube(kit, root, "metal", [Vector3(side*39.55,y,-29.5), Vector3(side*39.55,y,29.5)], 0.13, 12)
			for z in [-27.0,-18.0,-9.0,0.0,9.0,18.0,27.0]:
				kit.box_bevel("metal_dark",Vector3(0.36,0.6,0.2),Vector3(side*39.7,y,z),0.04)
		for z in [-24.0,24.0]:
			kit.box("metal_dark",Vector3(0.15,2.0,3.4),Vector3(side*39.9,5.5,z))
			for j in 8:
				kit.box("orion_frame",Vector3(0.2,0.09,3.1),Vector3(side*39.76,4.7+j*0.22,z))
	# Flush solid route strips are lifted off the floor to avoid z-fighting.
	for x in [-36.0,34.0]:
		for z in range(-26,27,4):
			kit.box("orion_frame",Vector3(0.12,0.018,1.8),Vector3(x,0.018,float(z)))
	# Closed bulkheads, no passage into the rest of the ship.
	for z in [-29.85, 29.85]:
		kit.box_bevel("metal_dark", Vector3(9, 8, 0.25), Vector3(0, 4, z), 0.08)
		kit.box("metal", Vector3(0.07, 7, 0.06), Vector3(0, 3.5, z-signf(z)*0.16))
		kit.box("amber", Vector3(7.8, 0.1, 0.08), Vector3(0, 7.7, z-signf(z)*0.16))
	kit.torus("amber", 2.2, 0.055, 64, 8, PLAYER_SPAWN + Vector3(0, 0.06, 0))
	neon_details(kit, root)
	details(kit)
	kit.commit(root, "CargoGeometry")
	lighting(root)
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = PLAYER_SPAWN
	root.add_child(spawn)
	for i in anchors.size():
		var marker := Marker3D.new()
		marker.name = "PhasePoint%02d" % (i + 1)
		marker.position = anchors[i]
		root.add_child(marker)
	return {"node": root, "kind": "cargo_hold2", "name_cn": "货舱 02 · 相位伏击", "hint": "位移怪被看见即瞬移 · 利用集装箱遮挡接近", "floor_y": 0.0,
		"bounds": AABB(Vector3(-HALF_WIDTH,0,-HALF_DEPTH), Vector3(HALF_WIDTH*2,CEILING,HALF_DEPTH*2)), "walls": walls, "cover": [], "solids": solids, "anchors": anchors,
		"player_spawn": spawn.transform, "spawns": [], "lamps": [], "wall_slots": []}

static func add_rect_walls(walls: Array, rect: Rect2, height: float) -> void:
	var a := rect.position
	var b := rect.end
	for edge in [[a, Vector2(b.x,a.y)], [Vector2(b.x,a.y), b], [b, Vector2(a.x,b.y)], [Vector2(a.x,b.y), a]]:
		var d: Vector2 = edge[1] - edge[0]
		walls.append({"a": edge[0], "b": edge[1], "h": height, "n": Vector2(-d.y,d.x).normalized()})

static func body(root: Node3D, center: Vector3, size: Vector3) -> void:
	var node := StaticBody3D.new()
	node.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	node.add_child(shape)
	root.add_child(node)

static func neon_details(kit: CargoMeshKit, root: Node3D) -> void:
	# Laser guides on the outer lanes; never span the player's eye line.
	for x in [-35.0,32.0]:
		for z in [-21.0,-7.0,7.0,21.0]:
			kit.box_bevel("metal_dark",Vector3(0.32,0.055,9.2),Vector3(x,0.035,z),0.02)
			lit_tube(kit, root, "laser_cyan",[Vector3(x,0.08,z-4.4),Vector3(x,0.08,z+4.4)],0.045,10)
	# Suspended paired energy conduits, with clear gaps between the gantries.
	for x in [-18.0,18.0]:
		for z in [-20.0,0.0,20.0]:
			kit.box_bevel("metal_dark",Vector3(0.5,0.25,10.6),Vector3(x,12.9,z),0.05)
			lit_tube(kit, root, "laser_violet",[Vector3(x,12.7,z-5),Vector3(x,12.7,z+5)],0.065,12)
			for dz in [-5.1,5.1]:
				kit.box("metal",Vector3(0.34,0.22,0.16),Vector3(x,12.76,z+dz))
	for side in [-1.0,1.0]:
		for z in [-25.0,-15.0,-5.0,5.0,15.0,25.0]:
			kit.box_bevel("metal_dark",Vector3(0.3,6.4,0.4),Vector3(side*39.3,5,z),0.04)
			lit_tube(kit, root, "laser_cyan",[Vector3(side*39.1,2,z),Vector3(side*39.1,8,z)],0.06,12)
	# Segmented overhead transverse lasers emphasize the breadth of the room.
	for z in [-26.0,26.0]:
		for x in [-26.0,-8.0,10.0,28.0]:
			kit.box("metal_dark",Vector3(10.4,0.2,0.3),Vector3(x,14.9,z))
			lit_tube(kit, root, "laser_cyan",[Vector3(x-5,14.74,z),Vector3(x+5,14.74,z)],0.045,12)

static func details(kit: CargoMeshKit) -> void:
	# Low-profile deck joints and service grates; all below actor clearance.
	for x in [-35.0, 34.0]:
		for z in range(-24,25,6):
			kit.box_bevel("metal_dark", Vector3(1.2,0.035,2.2), Vector3(x,0.02,z),0.02)
			for i in 12:
				kit.box("metal",Vector3(1.05,0.025,0.045),Vector3(x,0.05,z-0.96+i*0.17))
	for x in range(-32,33,8):
		for z in [-23.0,0.0,23.0]:
			# Recessed access covers with retaining bolts, no floating decals.
			kit.box_bevel("orion_frame",Vector3(2.4,0.035,1.4),Vector3(x,0.02,z),0.025)
			kit.box("metal_dark",Vector3(0.5,0.018,0.09),Vector3(x,0.045,z))
			for dx in [-1.04,1.04]:
				for dz in [-0.53,0.53]:
					kit.cyl("metal",0.045,0.045,0.025,8,Vector3(x+dx,0.04,z+dz))
	# Wall service bays remain outside the playable collision boundary.
	for side in [-1.0,1.0]:
		for z in [-24.0,-12.0,0.0,12.0,24.0]:
			kit.box_bevel("orion_frame",Vector3(0.4,4.8,6.6),Vector3(side*39.7,5.6,z),0.08)
			kit.box_bevel("metal_dark",Vector3(0.12,4.3,6.1),Vector3(side*39.44,5.6,z),0.04)
			for j in 14:
				kit.box_bevel("metal",Vector3(0.17,0.09,5.6),Vector3(side*39.34,3.8+j*0.27,z),0.025)
			for dz in [-3.0,3.0]:
				kit.box("amber",Vector3(0.06,0.12,0.35),Vector3(side*39.23,8.2,z+dz))
	# Ceiling equipment, cross-members and suspended cable trays above all actors.
	for x in [-20.0,20.0]:
		kit.box_bevel("metal_dark",Vector3(1.0,0.5,57.0),Vector3(x,14.9,0),0.08)
		for z in range(-26,27,4):
			kit.box("metal",Vector3(1.2,0.16,0.16),Vector3(x,14.6,z))
			kit.box("orion_frame",Vector3(0.1,0.7,0.14),Vector3(x,15.55,z))
	for z in [-29.65,29.65]:
		for x in [-29.0,-18.0,18.0,29.0]:
			kit.box_bevel("orion_frame",Vector3(7.8,8.2,0.35),Vector3(x,5,z),0.12)
			kit.box_bevel("metal_dark",Vector3(7.2,7.6,0.12),Vector3(x,5,z-signf(z)*0.24),0.06)
			for dx in [-3.2,3.2]:
				kit.box("metal",Vector3(0.1,7.2,0.1),Vector3(x+dx,5,z-signf(z)*0.33))

static func lighting(root: Node3D) -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("090f18")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("879bb4")
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.3
	env.fog_enabled = true
	env.fog_light_color = Color("182a37")
	env.fog_density = 0.0025
	world.environment = env
	root.add_child(world)
	for z in [-29.5,29.5]:
		var door_light := OmniLight3D.new()
		door_light.position = Vector3(0,7.5,z-signf(z)*0.35)
		door_light.light_color = Color("ffb87d")
		door_light.light_energy = 1.5
		door_light.omni_range = 7.0
		door_light.omni_attenuation = 1.8
		door_light.shadow_enabled = true
		root.add_child(door_light)


static func lit_tube(kit: CargoMeshKit, root: Node3D, key: String, points: Array, radius: float, segments: int) -> void:
	kit.tube(key, points, radius, segments)
	if key not in ["cyan", "white", "laser_cyan", "laser_violet"]:
		return
	var a: Vector3 = points[0]
	var b: Vector3 = points[-1]
	var length := a.distance_to(b)
	var samples := maxi(1, ceili(length/5.0))
	var color := Color("b7e8ef") if key == "white" else Color("50c5d8")
	if key == "laser_violet":
		color = Color("ac80dd")
	for i in samples:
		var pos := a.lerp(b,(float(i)+0.5)/samples)
		var lamp := OmniLight3D.new()
		lamp.name = "TubeBounce"
		lamp.position = pos
		lamp.light_color = color
		lamp.omni_attenuation = 1.7
		lamp.light_size = 0.55
		lamp.light_specular = 0.22
		if pos.y > 10.0:
			lamp.position.y -= 0.18
			lamp.light_energy = 2.5 if key == "white" else 1.5
			lamp.omni_range = 19.0 if key != "laser_violet" else 14.0
			lamp.shadow_enabled = key == "white" or key == "cyan"
			lamp.shadow_blur = 1.5
		else:
			lamp.position.y += 0.08
			lamp.light_energy = 1.1
			lamp.omni_range = 4.5
			# Short-range grazers cannot reach through the distant cargo blocks.
			lamp.shadow_enabled = false
		root.add_child(lamp)

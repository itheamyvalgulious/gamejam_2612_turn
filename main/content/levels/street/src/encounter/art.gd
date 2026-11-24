extends RefCounted
## Shared hard-surface vocabulary; dimensions also generate gameplay collision.
const STATIC_REFLECTION_LAYER := 1 << 19
const Kit = preload("res://src/encounter/mesh_kit.gd")
var urban := false
var root := Node3D.new()
var kit := Kit.new()
var solids: Array[AABB] = []
var walkables: Array[AABB] = []
var walls: Array = []

func _init() -> void:
	kit.material("floor", shader_mat("plate", {"base_col": Color("303c46"), "tile_m": 2.5, "rough_bias": 0.08}))
	kit.material("wall", shader_mat("wall", {"base_col": Color("414d5b"), "trim_col": Color("202833"), "style": 4, "grime": 0.4}))
	for pair in [["metal","8796a5"], ["dark","202833"], ["frame","414d5b"], ["teal","315c66"], ["warm","b9ad96"], ["ceramic","ccd5d9"]]:
		kit.material(pair[0], shader_mat("metal", {"tint": Color(pair[1]), "rough_base": 0.45, "rust_amount": 0.06, "oil_grime": 0.12}))
	for pair in [["cyan","36dceb"],["magenta","d95baf"],["amber","ffb45e"],["white","dceaf2"]]:
		kit.material(pair[0], shader_mat("neon_flow", {"tint": Color(pair[1])}))
	kit.material("glass",shader_mat("glazing",{}))
	for pair in [["panel_ship","536575"],["panel_rust","533b3d"]]:
		kit.material(pair[0],shader_mat("coating",{"paint":Color(pair[1]),"wear":0.25 if pair[0]=="panel_ship" else 0.85,"surface_normal":preload("res://src/encounter/surface_normal.gd").texture()}))
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("202329")
	rubber.roughness = 0.88
	kit.material("rubber",rubber)

static func shader_mat(file: String, values: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://gfx/encounter/"+file+".gdshader")
	for key in values:
		mat.set_shader_parameter(key,values[key])
	return mat

static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.lerp(Color.WHITE,0.25)
	mat.emission_energy_multiplier = energy
	return mat

func block(key: String, size: Vector3, center: Vector3, collision := true, walkable := false, bevel := 0.06) -> void:
	kit.box_bevel(key,size,center,minf(bevel,minf(size.x,minf(size.y,size.z))*0.3))
	if collision:
		solid_box(center,size,walkable)

func tube(key: String, a: Vector3, b: Vector3, radius := 0.055, _lit := true) -> void:
	neon_path(key,[a,b],radius)
	var axis := (b-a).normalized()
	for tip in [a,b]:
		kit.tube("dark",[tip-axis*0.10,tip+axis*0.10],radius*1.35,20)
		kit.tube("metal",[tip-axis*0.07,tip+axis*0.07],radius*1.46,24)
	var fixture := Node3D.new()
	fixture.name = "ContinuousNeonTube"
	fixture.set_meta("start",a)
	fixture.set_meta("end",b)
	fixture.set_meta("emitter","geometry_voxel_gi")
	root.add_child(fixture)

func neon_path(key: String, points: Array, radius := 0.055) -> void:
	ensure_neon_glass(key)
	kit.tube(key,points,radius*0.82,24)
	kit.tube("glass_neon_"+key,points,radius,32)

func neon_ring(key: String, major: float, minor: float, segments: int, sides: int, pos: Vector3) -> void:
	ensure_neon_glass(key)
	kit.torus(key,major,minor*0.82,segments,maxi(16,sides),pos)
	kit.torus("glass_neon_"+key,major,minor,segments,24,pos)

func ensure_neon_glass(key: String) -> void:
	if kit.has_material("glass_neon_"+key):
		return
	var mat: ShaderMaterial = kit.mats[key]
	kit.material("glass_neon_"+key,shader_mat("neon_glass",{"tint":mat.get_shader_parameter("tint")}))


func light(pos: Vector3, color: Color, energy: float, reach: float, shadow := false) -> void:
	var lamp := OmniLight3D.new()
	root.add_child(lamp)
	lamp.position = pos
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.6
	lamp.light_size = 0.22
	lamp.light_specular = 0.2
	lamp.shadow_enabled = shadow

func cabinet(pos: Vector3, size: Vector3, color := "teal") -> void:
	block(color,size,pos+Vector3(0,size.y*0.5,0))
	block("dark",Vector3(size.x+0.12,0.22,size.z+0.12),pos+Vector3(0,0.14,0),false)
	block("metal",Vector3(size.x+0.1,0.15,size.z+0.1),pos+Vector3(0,size.y-0.08,0),false)
	for side in [-1.0,1.0]:
		var z: float = pos.z+side*(size.z*0.5+0.035)
		block("dark",Vector3(size.x-0.35,size.y-0.55,0.08),Vector3(pos.x,pos.y+size.y*0.5,z),false)
		for i in 8:
			block("frame",Vector3(size.x-0.6,0.07,0.12),Vector3(pos.x,pos.y+0.6+i*(size.y-1.0)/8,z+side*0.06),false, false,0.015)
		for x in [-0.5,0.5]:
			for y in [0.27,size.y-0.27]:
				kit.sphere("metal",0.06,8,Vector3(pos.x+x*(size.x-0.3),pos.y+y,z+side*0.08))
		block("amber",Vector3(0.2,0.1,0.09),Vector3(pos.x+size.x*0.3,pos.y+size.y-0.4,z+side*0.05),false)

func bollard(pos: Vector3) -> void:
	block("frame",Vector3(0.48,1.25,0.48),pos+Vector3(0,0.625,0))
	block("amber",Vector3(0.5,0.12,0.5),pos+Vector3(0,1.06,0),false)

func floor_details(width: float, depth: float) -> void:
	for side in [-1.0,1.0]:
		for z in range(-int(depth)+6,int(depth)-3,7):
			var x: float = side*(width-4)
			block("dark",Vector3(0.8,0.035,2),Vector3(x,0.024,z),false, false,0.01)
			for i in 10:
				block("metal",Vector3(0.7,0.025,0.035),Vector3(x,0.052,z-0.8+i*0.18),false,false,0.008)
	for z in [-depth+5,0.0,depth-5]:
		for x in [-width+10,width-10]:
			block("frame",Vector3(2,0.03,1.3),Vector3(x,0.02,z),false,false,0.01)
			for dx in [-0.85,0.85]:
				for dz in [-0.5,0.5]:
					kit.cyl("metal",0.04,0.04,0.035,8,Vector3(x+dx,0.04,z+dz))

func environment(outside := false) -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("090f18")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("879bb4")
	env.ambient_light_energy = 0.22 if outside else 0.26
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.2
	env.fog_enabled = true
	env.fog_density = 0.004 if outside else 0.0015
	env.fog_light_color = Color("2b2028") if outside else Color("172333")
	world.environment = env
	root.add_child(world)
	var probe := ReflectionProbe.new()
	probe.name = "EnvironmentReflection"
	probe.cull_mask = STATIC_REFLECTION_LAYER
	probe.size = Vector3(74,40 if outside else 25,74 if outside else 66)
	probe.position = Vector3(0,16 if outside else 12,0)
	probe.box_projection = true
	probe.interior = not outside
	probe.intensity = 0.65
	probe.max_distance = 110
	root.add_child(probe)
	if outside:
		var sky_material := ShaderMaterial.new()
		sky_material.shader = load("res://gfx/sky.gdshader")
		for pair in [["zenith_col",Color("080c15")],["mid_col",Color("20181f")],["horizon_col",Color("4a2225")],["city_glow",Color("692723")]]:
			sky_material.set_shader_parameter(pair[0],pair[1])
		sky_material.set_shader_parameter("sky_gain",0.5)
		sky_material.set_shader_parameter("cloud_cover",0.92)
		sky_material.set_shader_parameter("stars",0.0)
		sky_material.set_shader_parameter("night",1.0)
		var sky := Sky.new()
		sky.sky_material = sky_material
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		var moon := DirectionalLight3D.new()
		moon.rotation_degrees = Vector3(-48,-28,0)
		moon.light_color = Color("9baecb")
		moon.light_energy = 0.18
		moon.shadow_enabled = true
		root.add_child(moon)

func finish(title: String, hint: String, half: Vector2, spawn: Vector3, encounters: Array, anchors: Array = []) -> Dictionary:
	floor_details(half.x,half.y)
	neon_ring("amber",2.0,0.045,64,8,spawn+Vector3(0,0.065,0))
	kit.commit(root,"EnvironmentGeometry",true,1 | STATIC_REFLECTION_LAYER)
	var marker := Marker3D.new()
	marker.name = "PlayerSpawn"
	marker.position = spawn
	root.add_child(marker)
	return {"node":root,"kind":"chamber","name_cn":title,"hint":hint,"floor_y":0.0,
		"bounds":AABB(Vector3(-half.x,0,-half.y),Vector3(half.x*2,32,half.y*2)),
		"walls":walls,"solids":solids,"walkables":walkables,"cover":[],"anchors":anchors,
		"player_spawn":Transform3D(Basis.IDENTITY,spawn),"encounters":encounters,"spawns":[],"lamps":[],"wall_slots":[]}

func configure_city() -> void:
	urban = true
	kit.material("floor",shader_mat("wet_street",{}))
	kit.material("wall",shader_mat("wall",{"base_col":Color("4b4345"),"trim_col":Color("24262d"),"style":4,"grime":0.75}))
	kit.material("glass",shader_mat("glazing",{"weathering":0.8,"glass_tint":Color("18232b")}))
	for pair in [["metal","8f949c"],["dark","23272e"],["frame","40434b"],["teal","583b3c"],["warm","766758"]]:
		kit.material(pair[0],shader_mat("metal",{"tint":Color(pair[1]),"pattern":1,"rough_base":0.38,"rust_amount":0.25,"oil_grime":0.38}))
	for pair in [["cyan","8fbbca"],["magenta","e54435"],["amber","e9aa7a"],["white","c8d5e0"]]:
		kit.material(pair[0],shader_mat("neon_flow",{"tint":Color(pair[1]),"radiance":3.2}))

func weather() -> void:
	# Use the demo's GPU rain pipeline; roof collision keeps rain out of solid cover.
	var rain = preload("res://src/arena/arena_env.gd").rain(root,Vector3(0,28,0),Vector3(35,1,35),5200,Color("a1aebd"),0.22,27.0)
	rain.lifetime = 1.8
	rain.visibility_aabb = AABB(Vector3(-40,-32,-40),Vector3(80,45,80))
	rain.process_material.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	var collision := GPUParticlesCollisionHeightField3D.new()
	collision.name = "RainRoofCollision"
	collision.size = Vector3(76,36,76)
	collision.position = Vector3(0,18,0)
	root.add_child(collision)
	for p in [Vector3(-32,0.15,3),Vector3(31,0.15,-18)]:
		preload("res://src/arena/arena_env.gd").steam(root,p,36,1.1,Color("828c9c"),0.11,1.0,2.3,5.0)

func maintenance_panel(center: Vector3, width: float, height: float, side := 1.0) -> void:
	block("dark",Vector3(width,height,0.16),center)
	block("panel_ship",Vector3(width-0.14,height-0.14,0.08),center+Vector3(0,0,side*0.12),false)
	for dx in [-0.5,0.5]:
		for dy in [-0.5,0.5]:
			kit.sphere("metal",0.045,8,center+Vector3(dx*(width-0.24),dy*(height-0.24),side*0.18))
	block("dark",Vector3(0.42,0.08,0.07),center+Vector3(0,-height*0.25,side*0.19),false,false,0.01)

func interior_detail() -> void:
	# Modular seams, inset hatches and independent struts remain off the fighting lanes.
	for z in [-30.8,30.8]:
		for x in [-26.0,-13.0,13.0,26.0]:
			maintenance_panel(Vector3(x,2.8,z),2.8,1.65,-signf(z))
	for side in [-1.0,1.0]:
		for z in [-23.0,-6.0,11.0]:
			var x: float = side*34.85
			for y in [1.2,1.7]:
				kit.tube("metal",[Vector3(x,y,z-5.3),Vector3(x,y,z+5.3)],0.1,12)
			for dz in [-4.5,-1.5,1.5,4.5]:
				block("dark",Vector3(0.3,1.0,0.16),Vector3(x,1.45,z+dz),false)
			# Wall-wash lighting runs continuously below each shop fascia.
			tube("white",Vector3(x,4.8,z-4.8),Vector3(x,4.8,z+4.8),0.035)
	# Deck underside has physical beams and continuous lights, above head clearance.
	for x in [-10.0,0.0,10.0]:
		block("dark",Vector3(0.45,0.35,10),Vector3(x,7.18,23))
		tube("white",Vector3(x,6.94,19),Vector3(x,6.94,27),0.045)
	for x in [-11.0,11.0]:
		for z in [18.5,22.5,26.5]:
			block("metal",Vector3(1.0,0.04,0.32),Vector3(x,8.025,z),false,false,0.01)
			for dx in [-0.4,0.4]:
				kit.cyl("dark",0.05,0.05,0.035,8,Vector3(x+dx,8.045,z))
	# Cabinet tops and sides gain closed housings, retaining rails and recessed ports.
	for p in [Vector3(-11,0,-5),Vector3(11,0,-7),Vector3(-11,0,10)]:
		for side in [-1.0,1.0]:
			for x in [-1.6,1.6]:
				block("metal",Vector3(0.12,2.4,0.16),p+Vector3(x,1.5,side*2.12),false)
			maintenance_panel(p+Vector3(0,1.6,side*2.11),1.35,0.85,side)
		for x in [-2.2,2.2]:
			kit.tube("metal",[p+Vector3(x,3.22,-1.7),p+Vector3(x,3.22,1.7)],0.035,10)
	# A caged continuous accent stays behind the stairs' outside guard.
	tube("cyan",Vector3(32.35,0.7,-9.5),Vector3(32.35,8.7,18.5),0.04)

func solid_box(center: Vector3,size: Vector3,walkable := false) -> void:
	var box := AABB(center-size*0.5,size)
	solids.append(box)
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = size
	shape.shape = volume
	body.add_child(shape)
	root.add_child(body)
	if walkable:
		walkables.append(box)
	var a := Vector2(box.position.x,box.position.z)
	var b := Vector2(box.end.x,box.end.z)
	for edge in [[a,Vector2(b.x,a.y)],[Vector2(b.x,a.y),b],[b,Vector2(a.x,b.y)],[Vector2(a.x,b.y),a]]:
		var d: Vector2 = edge[1]-edge[0]
		walls.append({"a":edge[0],"b":edge[1],"h":box.end.y,"base_y":box.position.y,"n":Vector2(-d.y,d.x).normalized()})

func downlight(pos: Vector3,color: Color,energy: float,reach: float) -> void:
	# A mounted luminaire illuminates the floor in one cone, with one shadow map
	# instead of six omnidirectional faces (and no upward light through the housing).
	var lamp := SpotLight3D.new()
	lamp.position=pos
	lamp.rotation_degrees=Vector3(-90,0,0)
	lamp.light_color=color
	lamp.light_energy=energy
	lamp.spot_range=reach
	lamp.spot_angle=72
	lamp.spot_attenuation=1.4
	lamp.light_size=0.4
	lamp.light_specular=0.25
	lamp.shadow_enabled=true
	root.add_child(lamp)

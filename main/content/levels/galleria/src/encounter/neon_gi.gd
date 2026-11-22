extends RefCounted
## Continuous emissive geometry drives scene irradiance; no light-node arrays.
## A standard-material bake proxy exposes procedural shader emission to VoxelGI.
const CACHE_PATH := "user://neon_geometry_gi.res"
const SOURCES := ["res://src/encounter/arena.gd","res://src/encounter/art.gd",
	"res://src/encounter/neon_gi.gd","res://src/encounter/vehicle.gd",
	"res://gfx/encounter/neon_flow.gdshader","res://gfx/encounter/neon_glass.gdshader"]

static func install(environment_root: Node3D, outside: bool) -> VoxelGI:
	if DisplayServer.get_name()=="headless":
		return null
	var gi := VoxelGI.new()
	gi.name="ContinuousNeonGI"
	gi.size=Vector3(76,36,76) if outside else Vector3(76,28,68)
	gi.position=Vector3(0,16,0) if outside else Vector3(0,12,0)
	gi.subdiv=VoxelGI.SUBDIV_128
	environment_root.add_child(gi)
	var signature := "neon-gI-v1"
	for path in SOURCES:
		if FileAccess.file_exists(path):
			signature+=FileAccess.get_file_as_string(path)
	signature=signature.sha256_text()
	var meshes := environment_root.find_children("*","MeshInstance3D",true,false)
	for instance: MeshInstance3D in meshes:
		instance.gi_mode=GeometryInstance3D.GI_MODE_STATIC
		if _is_glass_shell(instance):
			instance.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	if FileAccess.file_exists(CACHE_PATH):
		var cached=ResourceLoader.load(CACHE_PATH,"VoxelGIData",ResourceLoader.CACHE_MODE_IGNORE)
		if cached is VoxelGIData and cached.get_meta("source_signature","")==signature:
			gi.data=cached
			gi.set_meta("cache_hit",true)
			return gi
	var restore: Array=[]
	for instance: MeshInstance3D in meshes:
		if instance.mesh==null or instance.gi_mode==GeometryInstance3D.GI_MODE_DISABLED:
			continue
		for surface in instance.mesh.get_surface_count():
			var material=instance.get_active_material(surface)
			if material is ShaderMaterial:
				restore.append([instance,surface,instance.get_surface_override_material(surface)])
				instance.set_surface_override_material(surface,_bake_material(material))
	gi.bake(environment_root)
	for entry in restore:
		entry[0].set_surface_override_material(entry[1],entry[2])
	if gi.data!=null:
		gi.data.energy=1.4
		gi.data.interior=not outside
		gi.data.normal_bias=0.8
		gi.data.bias=1.0
		gi.data.use_two_bounces=true
		gi.data.set_meta("source_signature",signature)
		ResourceSaver.save(gi.data,CACHE_PATH)
	gi.set_meta("cache_hit",false)
	return gi

static func _is_glass_shell(instance: MeshInstance3D) -> bool:
	if instance.mesh==null or instance.mesh.get_surface_count()==0:
		return false
	var mat=instance.get_active_material(0)
	return mat is ShaderMaterial and mat.shader.resource_path.ends_with("neon_glass.gdshader")

static func _bake_material(source: ShaderMaterial) -> StandardMaterial3D:
	var proxy:=StandardMaterial3D.new()
	proxy.albedo_color=Color(0.25,0.28,0.32)
	proxy.roughness=0.65
	for key in ["base_col","paint","tint","glass_tint"]:
		var value=source.get_shader_parameter(key)
		if value is Color:
			proxy.albedo_color=value
			break
		if value is Vector3:
			proxy.albedo_color=Color(value.x,value.y,value.z)
			break
	if source.shader.resource_path.ends_with("neon_flow.gdshader"):
		proxy.albedo_color=Color.WHITE
		proxy.emission_enabled=true
		proxy.emission=source.get_shader_parameter("tint")
		proxy.emission_energy_multiplier=7.0
	return proxy

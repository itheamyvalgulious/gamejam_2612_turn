extends Node3D
class_name EnergyShuriken
## A single 4-blade energy shuriken + twin additive trail ribbons.
##
## The whole flight is analytic: given a launch transform, speed, spin and an
## age, the position / orientation / trail are closed-form.  The character's
## attack timeline can therefore be scrubbed deterministically.

const PK := preload("res://scripts/phantom/phantom_kit.gd")
const MK := preload("res://scripts/kit/mesh_kit.gd")
const PM := preload("res://scripts/phantom/phantom_materials.gd")

var blade: MeshInstance3D
var tip: MeshInstance3D
var trail: MeshInstance3D
var origin := Vector3.ZERO
var dir := Vector3.FORWARD
var side := Vector3.RIGHT
var speed := 13.0
var spin_deg := 480.0
var size := 0.16
var life := 1.05
var curl := 0.6
var trail_life := 0.22
var active := false
var launch_basis := Basis.IDENTITY

var _trail_mesh: ArrayMesh
var _rng := RandomNumberGenerator.new()
var _seed := 0.0


func setup(seed_v: float) -> void:
	_seed = seed_v
	_rng.seed = int(seed_v * 1000.0) + 77
	blade = MeshInstance3D.new()
	blade.mesh = PK.shuriken_mesh(4, 0.5, 0.215, 0.055)
	var mat := PM.shuriken()
	blade.material_override = mat
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blade)
	# hot tip bead on the long blade: an orbiting bright marker makes the spin
	# legible even when the additive energy silhouette is soft
	tip = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.075
	sph.height = 0.15
	sph.radial_segments = 12
	sph.rings = 6
	tip.mesh = sph
	tip.material_override = PM.emissive(Color(1.0, 0.82, 0.55), 7.0)
	tip.position = Vector3(0.60, 0.0, 0.0)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blade.add_child(tip)
	trail = MeshInstance3D.new()
	var tm := ShaderMaterial.new()
	tm.shader = PM.TRAIL_SHADER
	tm.set_shader_parameter("hot_color", Color(1.0, 0.90, 0.72))
	tm.set_shader_parameter("energy_color", PM.ENERGY)
	tm.set_shader_parameter("intensity", 1.8)
	tm.set_shader_parameter("seed", _seed)
	trail.material_override = tm
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.top_level = true
	add_child(trail)
	_trail_mesh = ArrayMesh.new()
	trail.mesh = _trail_mesh
	hide_all()


func hide_all() -> void:
	active = false
	visible = false
	if blade:
		blade.visible = false
	if trail:
		trail.visible = false


func launch(p_origin: Vector3, p_dir: Vector3, p_speed: float, p_size: float,
		p_spin: float, p_trail_life: float, yaw_offset_deg := 0.0) -> void:
	dir = p_dir.normalized()
	var b := Basis(Quaternion(Vector3.UP, deg_to_rad(yaw_offset_deg))) * Basis()
	dir = (b * dir).normalized()
	side = dir.cross(Vector3.UP)
	if side.length_squared() < 1e-5:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	# star plane faces back along the shot (readable from the muzzle side)
	var z := -dir
	var x := side
	var y := z.cross(x).normalized()
	launch_basis = Basis(x, y, z)
	origin = p_origin
	speed = p_speed
	size = p_size
	spin_deg = p_spin
	trail_life = p_trail_life
	life = 1.05
	active = true
	visible = true
	blade.visible = true
	trail.visible = true
	blade.scale = Vector3.ONE * size
	if tip:
		tip.visible = true


## Position along the flight at age a (seconds).
func arc_pos(a: float) -> Vector3:
	var p := origin + dir * (speed * a)
	p.y -= 1.55 * a * a
	p += side * (curl * 0.45 * a * a)
	p.y += 0.22 * a
	return p


func update(age: float) -> void:
	if not active:
		return
	if age < 0.0 or age > life:
		hide_all()
		return
	visible = true
	blade.visible = true
	trail.visible = true
	var p := arc_pos(age)
	# spin about the star's own normal (local +Z = back along the flight), then a
	# small local precession so the disc plane tilts 2-3 degrees and catches light
	var spin := Basis(Vector3.BACK, deg_to_rad(spin_deg) * age)
	var wob := Basis(Vector3.RIGHT, sin(age * 5.0 + _seed) * 0.045) \
		* Basis(Vector3.UP, cos(age * 3.7 + _seed) * 0.030)
	blade.global_transform = Transform3D(launch_basis * wob * spin * Basis().scaled(Vector3.ONE * size), p)
	_build_trail(age)


func _build_trail(age: float) -> void:
	var pts := PackedVector3Array()
	var widths := PackedFloat32Array()
	var n := 16
	var span := minf(trail_life, age)
	if span < 0.008:
		trail.visible = false
		return
	for i in n + 1:
		var t := age - span * float(i) / float(n)
		pts.append(arc_pos(t))
		var f := 1.0 - float(i) / float(n)
		widths.append(size * (0.12 + 0.55 * f))
	# two crossed strips so the wake has volume from any angle
	var a := PK.ribbon_strip(pts, widths, Vector3.UP)
	var b := PK.ribbon_strip(pts, widths, side)
	var merged := MK.merge([a, b])
	_trail_mesh.clear_surfaces()
	if merged.get_surface_count() > 0:
		_trail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged.surface_get_arrays(0))
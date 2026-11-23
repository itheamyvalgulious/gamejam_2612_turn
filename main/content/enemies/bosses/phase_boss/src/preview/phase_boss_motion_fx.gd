extends Node3D
## Visual and audio cues used by the exhibit and battle.

const Body = preload("res://src/enemies/phase_boss/phase_boss_body.gd")
const Motion = preload("res://src/enemies/phase_boss/phase_boss_motion.gd")
const Kit = preload("res://scripts/mech/mesh_kit.gd")
const Outline = preload("res://shaders/phase_boss_outline.gdshader")
const PHASE_TRAIL_WIDTHS := [0.16, 0.12, 0.13, 0.13, 0.10, 0.08, 0.085, 0.08, 0.085]
const TRAIL_LIFE := 0.24

var _model: Node3D
var _pieces: Array[MeshInstance3D] = []
var _phase_mat: ShaderMaterial
var _applied_shell: ShaderMaterial
var _piece_shadows: Array[GeometryInstance3D.ShadowCastingSetting] = []
var _markers: Dictionary = {}
var _coverage: Dictionary = {}
var _energy_mesh := ImmediateMesh.new()
var _glare: OmniLight3D
var _warning: StandardMaterial3D
var _audio: AudioStreamPlayer
var _cue_tones: Dictionary = {}
var _trail_mesh := ArrayMesh.new()
var _trail: Array[Dictionary] = []
var _trail_time := -1.0


func configure(model: Node3D) -> void:
	_model = model
	for piece: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		_pieces.append(piece)
		_piece_shadows.append(piece.cast_shadow)
	_phase_mat = ShaderMaterial.new()
	_phase_mat.shader = Outline
	_warning = StandardMaterial3D.new()
	_warning.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_warning.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_warning.cull_mode = BaseMaterial3D.CULL_DISABLED
	_warning.vertex_color_use_as_albedo = true
	var trace_material := StandardMaterial3D.new()
	trace_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trace_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trace_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trace_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trace_material.vertex_color_use_as_albedo = true
	var trace := Kit.add(self, _trail_mesh, trace_material)
	trace.top_level = true
	trace.global_transform = Transform3D.IDENTITY
	trace.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var energy := Kit.add(self, _energy_mesh, trace_material)
	energy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glare = OmniLight3D.new()
	_glare.omni_range = 11.0
	_glare.omni_attenuation = 1.35
	_glare.light_energy = 0.0
	add_child(_glare)
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -11.0
	add_child(_audio)
	_cue_tones["charge"] = _tone(430.0, 770.0, 0.18)
	_cue_tones["phase"] = _tone(870.0, 145.0, 0.22)
	_cue_tones["impact"] = _tone(150.0, 38.0, 0.37)
	_cue_tones["surge"] = _tone(73.0, 224.0, 0.66)
	_cue_tones["release"] = _tone(590.0, 39.0, 0.41)
	_cue_tones["roar"] = _mechanical_roar(Motion.ROAR_SOUND_DURATION, true)
	_cue_tones["wake_growl"] = _mechanical_roar(0.93, false)
	_cue_tones["cannon_lift"] = _tone(142.0, 64.0, 0.19)
	_cue_tones["cannon_charge"] = _tone(94.0, 670.0, Motion.CANNON_FIRE - Motion.CANNON_CHARGE - 0.04)
	_cue_tones["cannon_fire"] = _tone(390.0, 83.0, Motion.CANNON_RELEASE - Motion.CANNON_FIRE)
	_cue_tones["tail_sweep"] = _tone(135.0, 420.0, 0.37)


func show_pose(pose: RefCounted, enabled: bool, time: float, playing: bool,
		preview_shell: ShaderMaterial = null, preview_fade := 0.51) -> void:
	var phase: float = pose.phase if enabled else 0.0
	var shell := preview_shell if preview_shell != null else _phase_mat
	if phase <= 0.005:
		shell = null
	if shell != null:
		shell.set_shader_parameter("phase_amount", phase)
		shell.set_shader_parameter("phase_time", time)
	var fade := preview_fade if preview_shell != null else 0.51
	for i in _pieces.size():
		var piece := _pieces[i]
		piece.transparency = phase * fade
		if shell != _applied_shell:
			piece.material_overlay = shell
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if (
				shell != null and shell != _phase_mat) else _piece_shadows[i]
	_applied_shell = shell
	_model.set_motion_lights(pose.charge if enabled else 0.0,
		pose.flash if enabled else 0.0, pose.burst if enabled else 0.0, pose.cannon_heat if enabled else 0.0, phase, pose.lamp_power)
	for key: String in _markers:
		_markers[key].visible = enabled and key == pose.marker
	if enabled and not pose.marker.is_empty():
		var strike_fx := maxf(pose.jaw_cut, pose.stomp_wave)
		var opacity := (0.63 + float(pose.flash) * 0.30) * (1.0 - 0.86 * smoothstep(0.04, 0.56, strike_fx))
		_warning.albedo_color = Color(1.0, 0.36 - pose.flash * 0.16, 0.075, opacity)
	_draw_energy(pose, enabled)
	_draw_cannon(pose, time, enabled)
	var trail_phase := phase if preview_shell == null else 0.0
	if trail_phase > 0.26:
		_draw_phase_fragments(trail_phase, time)
	_draw_trail(time, enabled and playing, trail_phase, float(pose.jaw_cut))
	if not enabled:
		_audio.stop()


func _draw_trail(time: float, active: bool, phase := 0.0, jaw_cut := 0.0) -> void:
	if not active or time < _trail_time:
		_trail_mesh.clear_surfaces()
		_trail.clear()
		_trail_time = -1.0
		return
	if time <= _trail_time + 0.020:
		return
	if _trail.is_empty() and maxf(phase, jaw_cut) < 0.02:
		return
	_trail_time = time
	_trail_mesh.clear_surfaces()
	var jaw_tip: Vector3 = _model.jaw.to_global(Vector3(0.0, -0.10, -2.04))
	var jaw_axis: Vector3 = -_model.head.global_basis.z
	_trail.append({
		"time": time,
		"phase": phase,
		"points": _phase_anchors(),
		"jaw": jaw_cut,
		"jaw_inner": jaw_tip - jaw_axis * 0.75,
		"jaw_outer": jaw_tip + jaw_axis * (Motion.SWEEP_REACH * 0.88),
	})
	while not _trail.is_empty() and time - _trail.front()["time"] > TRAIL_LIFE:
		_trail.pop_front()
	if _trail.size() < 2:
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drawn := false
	for i in range(1, _trail.size()):
		var old: Dictionary = _trail[i - 1]
		var next: Dictionary = _trail[i]
		var fade_a := 1.0 - smoothstep(0.0, TRAIL_LIFE, time - float(old["time"]))
		var fade_b := 1.0 - smoothstep(0.0, TRAIL_LIFE, time - float(next["time"]))
		if maxf(old["phase"], next["phase"]) > 0.20:
			var alpha_a := fade_a * float(old["phase"])
			var alpha_b := fade_b * float(next["phase"])
			for part in PHASE_TRAIL_WIDTHS.size():
				var a: Vector3 = old["points"][part]
				var b: Vector3 = next["points"][part]
				if a.distance_squared_to(b) < 0.004:
					continue
				var vertical := absf((b - a).normalized().y) > 0.83
				var width: Vector3 = (Vector3.RIGHT if vertical else Vector3.UP) * PHASE_TRAIL_WIDTHS[part]
				var tint := Color(0.18, 0.92, 1.52) if part % 3 != 0 else Color(0.62, 0.28, 1.55)
				var slice := a.lerp(b, 0.30 if (i + part) % 3 == 0 else 0.06)
				var edge := b + width * (0.86 if part < 5 else 0.51)
				_trail_quad(surface, slice - width * 0.62, slice + width, b - width * 0.35, edge,
					Color(tint, alpha_a * 0.38), Color(tint, alpha_b * 0.65))
				_trail_quad(surface, slice + width * 0.65, slice + width, edge - width * 0.24, edge,
					Color(0.70, 1.34, 1.76, alpha_a * 0.34), Color(0.70, 1.34, 1.76, alpha_b * 0.62))
				drawn = true
		if maxf(old["jaw"], next["jaw"]) > 0.03:
			var outer_a: Vector3 = old["jaw_outer"]
			var outer_b: Vector3 = next["jaw_outer"]
			if outer_a.distance_squared_to(outer_b) < 0.003:
				continue
			var alpha_a := fade_a * float(old["jaw"])
			var alpha_b := fade_b * float(next["jaw"])
			var spectral := maxf(old["phase"], next["phase"]) > 0.20
			_draw_claw_streaks(surface, old["jaw_inner"], outer_a, next["jaw_inner"], outer_b, alpha_a, alpha_b, spectral, i)
			drawn = true
	if drawn:
		_trail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.commit_to_arrays())
	elif maxf(phase, jaw_cut) < 0.02:
		_trail.clear()


func _trail_quad(surface: SurfaceTool, a: Vector3, a_edge: Vector3, b: Vector3, b_edge: Vector3,
		first: Color, second: Color) -> void:
	for vertex: Vector3 in [a, a_edge, b_edge, a, b_edge, b]:
		surface.set_color(first if vertex == a or vertex == a_edge else second)
		surface.add_vertex(vertex)


func _phase_anchors() -> PackedVector3Array:
	var points := PackedVector3Array([
		_model.head.to_global(Vector3(0, 0.14, -2.0)),
		_model.tail_fin.to_global(Vector3(0, 0.26, 0.74)),
		_model.chest.to_global(Vector3(-2.42, 0.75, -1.85)),
		_model.chest.to_global(Vector3(2.42, 0.75, -1.85)),
		_model.chest.to_global(Vector3(0, 0.96, 0.20)),
	])
	for leg: Dictionary in _model.legs:
		points.append(leg["paw"].to_global(Vector3(0, 0.10, -0.75)))
	return points


func _draw_claw_streaks(surface: SurfaceTool, a: Vector3, a_tip: Vector3, b: Vector3, b_tip: Vector3,
		fade_a: float, fade_b: float, spectral: bool, sample: int) -> void:
	var hue := Color(0.18, 0.89, 1.55) if spectral else Color(1.66, 0.26, 0.055)
	var pale := Color(1.12, 1.50, 1.80) if spectral else Color(1.82, 1.32, 0.60)
	for lane in 3:
		var u := 0.13 + lane * 0.29
		var ridge := 0.16 + (lane % 2) * 0.045
		var cut_a := a.lerp(a_tip, u)
		var cut_b := b.lerp(b_tip, u)
		var edge_a := a.lerp(a_tip, u + ridge)
		var edge_b := b.lerp(b_tip, u + ridge)
		_trail_quad(surface, cut_a, edge_a, cut_b, edge_b,
			Color(hue, fade_a * 0.66), Color(hue, fade_b * 0.86))
		_trail_quad(surface, cut_a.lerp(edge_a, 0.74), edge_a, cut_b.lerp(edge_b, 0.74), edge_b,
			Color(pale, fade_a * 0.78), Color(pale, fade_b * 0.96))
		if (sample + lane) % 3 == 0:
			var spark := edge_a + (edge_a - cut_a) * 0.30 + Vector3.UP * (0.16 + lane * 0.12)
			var vertices := [spark, spark - Vector3.UP * 0.10, edge_b]
			for vertex: Vector3 in vertices:
				surface.set_color(Color(pale, fade_a * 0.65))
				surface.add_vertex(vertex)


func _draw_phase_fragments(phase: float, time: float) -> void:
	var points := _phase_anchors()
	var bright := smoothstep(0.26, 0.85, phase)
	_energy_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 22:
		var life := fposmod(time * (1.37 + (i % 5) * 0.11) + i * 0.417, 1.0)
		var angle := i * 2.399963
		var anchor := to_local(points[i % points.size()])
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var x := outward.rotated(Vector3.UP, time * 1.8 + i).normalized()
		var y := Vector3.UP.rotated(x, time * 2.4 + i)
		var offset := outward * (0.22 + 1.05 * life) + Vector3.UP * (0.10 + 0.72 * life)
		var at := anchor + offset
		var size := (0.15 + (i % 6) * 0.066) * (0.90 + 0.10 * life)
		var alpha := bright * smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.48, 1.0, life))
		var hue := Color(0.28, 1.14, 1.75) if i % 3 != 0 else Color(0.68, 0.37, 1.64)
		var tip := at + y * size * 1.45
		var left := at - x * size * 0.68 - y * size * 0.48
		var right := at + x * size * 0.48 - y * size * 0.90
		_energy_triangle(tip, left, right, Color(hue, alpha * 0.55))
		_energy_triangle(tip, left, left.lerp(right, 0.29), Color(0.71, 1.25, 1.65, alpha * 0.85))
	_energy_mesh.surface_end()


func advance_audio(clip: String, before: float, after: float) -> void:
	var cues: Array = []
	match clip:
		"cycle":
			if before < Motion.PhaseState.CHARGE_TIME:
				advance_audio("charge", before, minf(after, Motion.PhaseState.CHARGE_TIME))
			if after >= Motion.PhaseState.CHARGE_TIME and before < Motion.PHASE_FIGHT_START:
				advance_audio("phase_enter", before - Motion.PhaseState.CHARGE_TIME, after - Motion.PhaseState.CHARGE_TIME)
			if after >= Motion.PHASE_FIGHT_START and before < Motion.PHASE_FIGHT_END:
				var old := Motion.phase_sequence_slot(before)
				var slot := Motion.phase_sequence_slot(after)
				if int(slot.x) < Motion.PHASE_SEQUENCE.size():
					advance_audio(Motion.PHASE_SEQUENCE[int(slot.x)][0], old.y if old.x == slot.x else 0.0, slot.y)
		"charge":
			cues = [[0.23, "surge"], [0.92, "charge"], [1.49, "charge"], [2.03, "surge"],
				[2.55, "charge"]]
		"phase_enter":
			cues = [[0.16, "release"]]
		"phase_roar":
			cues = [[Motion.ROAR_SOUND_TIME, "roar"]]
		"wake_intro":
			cues = [[Motion.INTRO_SLEEP_TIME, "cannon_lift"], [Motion.INTRO_GROWL_TIME, "wake_growl"]]
		"rush_turn":
			cues = [[Motion.RUSH_TURN_LAND, "impact"]]
		"flank_leap":
			cues = [[0.145, "cannon_lift"], [Motion.FLANK_LEAP_LAND, "impact"]]
		"phase":
			cues = [[0.30, "phase"], [1.25, "impact"], [2.11, "impact"]]
		"stomp":
			cues = [[Motion.STOMP_IMPACT, "impact"]]
		"pounce":
			cues = [[Motion.SHORT_POUNCE_LAND, "impact"]]
		"high_pounce":
			cues = [[Motion.LEAP_TAKEOFF, "phase"], [Motion.LEAP_CONTACT, "impact"]]
		"run_pounce":
			cues = [[Motion.RUN_IN + Motion.LEAP_TAKEOFF, "phase"], [Motion.RUN_IN + Motion.LEAP_CONTACT, "impact"]]
		"back_cannon":
			cues = [[Motion.CANNON_OPEN, "cannon_lift"], [Motion.CANNON_SEATED, "impact"],
				[Motion.CANNON_CHARGE, "cannon_charge"], [Motion.CANNON_FIRE, "cannon_fire"], [Motion.CANNON_STOW, "cannon_lift"]]
		"tail", "tail_left":
			cues = [[Motion.TAIL_CONTACT_BEGIN + 0.08, "tail_sweep"]]
	for cue: Array in cues:
		if before < cue[0] and after >= cue[0]:
			_audio.stream = _cue_tones[cue[1]]
			_audio.play()


func prepare_clip(driver: Motion, clip: String, preserve_trail := false) -> void:
	if not preserve_trail:
		_draw_trail(0.0, false)
	var source := clip
	if not _coverage.has(source):
		var markers := {}
		for window: Array in Motion.CONTACT_WINDOWS.get(source, []):
			markers[window[0]] = _swept_marker(driver, source, window)
		_coverage[source] = markers
	for marker: MeshInstance3D in _markers.values():
		marker.hide()
	_markers = _coverage[source]


func _swept_marker(driver: Motion, clip: String, window: Array) -> MeshInstance3D:
	var kind: String = window[0]
	var samples := PackedVector2Array()
	for index in 25:
		var time := lerpf(window[1], window[2], float(index) / 24.0)
		driver.apply(driver.sample(clip, time))
		var reach := Motion.stomp_radius_at(time) if clip == "stomp" else float(window[3])
		var points: Array[Vector3] = []
		match kind:
			"head":
				points = _jaw_coverage()
			"tail":
				var path: PackedVector3Array = _model.tail_contact_path()
				var first := 0 if clip == "tail" or clip == "tail_left" else path.size() - 6
				for segment in range(first, path.size()):
					points.append(path[segment])
			"paw":
				var claw: Node3D = _model.legs[2]["paw"]
				points = [claw.to_global(Vector3(0.0, -0.25, -0.75))]
			"pounce":
				points = _jaw_coverage()
				for leg: int in [0, 2]:
					var claw: Node3D = _model.legs[leg]["paw"]
					points.append(claw.to_global(Vector3(0.0, -0.25, -0.96)))
				var scale := global_basis.x.length()
				for part: Body.Capsule in Body.posed_capsules(_model):
					for point: Vector3 in [part.a, part.b]:
						var spot := to_local(point)
						for radial in 8:
							var ray := Vector2.from_angle(TAU * float(radial) / 8.0)
							samples.append(Vector2(spot.x, spot.z) + ray * part.radius / scale)
		for point in points:
			var spot := to_local(point)
			for radial in 8:
				var ray := Vector2.from_angle(TAU * float(radial) / 8.0)
				samples.append(Vector2(spot.x, spot.z) + ray * reach)
	var hull := Geometry2D.convex_hull(samples)
	var direction := Motion.tail_sweep_direction(clip)
	if direction != 0.0:
		var clipped := PackedVector2Array()
		for i in hull.size() - 1:
			var a := hull[i]
			var b := hull[i + 1]
			var a_side := driver.tail_sweep_side_distance(to_global(Vector3(a.x, 0, a.y)), direction)
			var b_side := driver.tail_sweep_side_distance(to_global(Vector3(b.x, 0, b.y)), direction)
			if a_side >= 0.0:
				clipped.append(a)
			if a_side * b_side < 0.0:
				clipped.append(a.lerp(b, a_side / (a_side - b_side)))
		clipped.append(clipped[0])
		hull = clipped
	var center := Vector2.ZERO
	for i in hull.size() - 1:
		center += hull[i]
	center /= (hull.size() - 1)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in hull.size() - 1:
		var a := hull[i]
		var b := hull[i + 1]
		var a_in := a.lerp(center, 0.055)
		var b_in := b.lerp(center, 0.055)
		surface.set_color(Color(1, 1, 1, 0.33))
		for point: Vector2 in [center, a_in, b_in]:
			surface.add_vertex(Vector3(point.x, 0.017, point.y))
		surface.set_color(Color(1, 1, 1, 0.95))
		for point: Vector2 in [a, b, b_in, a, b_in, a_in]:
			surface.add_vertex(Vector3(point.x, 0.018, point.y))
	var marker := Kit.add(self, surface.commit(), _warning)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.hide()
	return marker


func _jaw_coverage() -> Array[Vector3]:
	return [
		_model.head.to_global(Vector3(-0.68, -0.22, -1.52)),
		_model.head.to_global(Vector3(0.68, -0.22, -1.52)),
		_model.jaw.to_global(Vector3(0.0, -0.10, -2.04)),
	]


func _draw_energy(pose: RefCounted, enabled: bool) -> void:
	_energy_mesh.clear_surfaces()
	var power: float = pose.charge if enabled and pose.release_age <= 0.0 else 0.0
	var burst: float = pose.burst if enabled else 0.0
	var impact: float = pose.impact if enabled else 0.0
	var stomp: float = pose.stomp_wave if enabled else 0.0
	_glare.visible = maxf(power, burst) > 0.025
	if maxf(maxf(power, burst), maxf(impact, stomp)) <= 0.025:
		return
	var core: Vector3 = to_local(_model.chest.global_position)
	_glare.position = core + Vector3.UP * 0.96
	_glare.light_color = Color("61caff").lerp(Color("f0faff"), maxf(power, burst))
	_glare.light_energy = power * power * 5.8 + burst * 12.0
	if stomp > 0.025:
		_draw_stomp(pose, stomp)
		return
	if impact <= 0.025:
		return
	_energy_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var floor_point: Vector3 = pose.impact_position
	floor_point.y = 0.052
	var size: float = (0.56 + (1.0 - impact) * 1.67) * pose.impact_scale
	_energy_ring(floor_point, size, size, 0.13, Color(1.0, 0.36, 0.12, 0.81 * impact))
	if pose.impact_scale > 1.0:
		_energy_ring(floor_point, size * 0.69, size * 0.69, 0.075, Color(1.0, 0.78, 0.42, 0.74 * impact))
	_energy_mesh.surface_end()


func _draw_stomp(pose: RefCounted, strength: float) -> void:
	var floor_point: Vector3 = pose.impact_position
	floor_point.y = 0.055
	var radius: float = pose.stomp_radius
	var progress := inverse_lerp(1.65, Motion.STOMP_WAVE_RADIUS, radius)
	var spectral: bool = pose.phase > 0.20
	var hot := Color(0.21, 0.94, 1.60) if spectral else Color(1.65, 0.40, 0.10)
	var pale := Color(0.78, 1.34, 1.78) if spectral else Color(1.70, 1.04, 0.46)
	_glare.visible = true
	_glare.position = floor_point + Vector3.UP * 0.44
	_glare.light_color = hot
	_glare.light_energy = strength * (1.0 - progress * 0.55) * 10.0
	_energy_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 15:
		var angle := TAU * float(i) / 15.0 + 0.12 * sin(float(i) * 7.1)
		var outward := Vector3(cos(angle), 0, sin(angle))
		var crosswise := outward.cross(Vector3.UP)
		var flip := 1.0 if i % 2 == 0 else -1.0
		var corner := floor_point + outward * radius * (0.32 + 0.06 * sin(i * 11.0)) + crosswise * 0.22 * flip
		var fork := floor_point + outward * radius * 0.67 - crosswise * 0.29 * flip
		var end := floor_point + outward * radius * (0.83 + (i % 4) * 0.056)
		var root := floor_point + outward * 0.17
		var crack := Color(hot, strength * (0.60 + (i % 3) * 0.14))
		_energy_strip(root, corner, crosswise * 0.11, crack)
		_energy_strip(corner, fork, crosswise * 0.085, crack)
		_energy_strip(fork, end, crosswise * 0.055, crack)
		_energy_strip(corner, fork, crosswise * 0.026, Color(pale, strength * 0.95))
		var branch := floor_point + outward * radius * 0.81 + crosswise * flip * 0.47
		_energy_strip(corner, branch, crosswise * 0.041, Color(hot, strength * 0.58))
		var lift := (0.23 + (i % 5) * 0.13) * (1.0 - progress * 0.35)
		var fragment := end + Vector3.UP * lift
		_energy_triangle(end - crosswise * 0.20, end + crosswise * 0.28, fragment - outward * 0.14,
			Color(hot, strength * 0.65))
		_energy_triangle(fragment, fragment + outward * 0.34 + Vector3.UP * 0.17, fragment + crosswise * 0.08,
			Color(pale, strength * 0.86))
	_energy_mesh.surface_end()


func _draw_cannon(pose: RefCounted, time: float, enabled: bool) -> void:
	var power: float = pose.cannon_power if enabled else 0.0
	var shot: float = pose.cannon_shot if enabled else 0.0
	_model.cannon.light_charge(power, shot)
	if maxf(power, shot) <= 0.02:
		return
	var muzzle: Marker3D = _model.cannon.muzzle
	var start := to_local(muzzle.global_position)
	var muzzle_basis := (global_basis.inverse() * muzzle.global_basis).orthonormalized()
	var axis := -muzzle_basis.z
	var right := muzzle_basis.x
	var up := muzzle_basis.y
	var world_scale := global_basis.x.length()
	var length: float = pose.cannon_range / world_scale
	var surface_hit: bool = pose.cannon_surface_hit
	if length < 0.0:
		var floor_range := Motion.cannon_floor_range(start, axis, -0.018)
		surface_hit = is_finite(floor_range)
		# The exhibit has a floor but no arena walls.
		length = floor_range if surface_hit else 350.0 / world_scale
	_glare.visible = true
	_glare.position = start + axis * 0.25
	var spectral: bool = pose.phase > 0.25
	var glow := Color("58a7ff") if spectral else Color("ff9d45")
	_glare.light_color = glow.lerp(Color("e6f8ff") if spectral else Color("fff0c7"), shot)
	_glare.light_energy = power * power * 5.2 + shot * 14.0
	_energy_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if shot > 0.02:
		_draw_prism_beam(start, axis, right, up, length, shot, time, spectral, surface_hit)
	elif pose.cannon_charging:
		for strand in 3:
			for i in 14:
				var a := float(i) / 14.0
				var b := float(i + 1) / 14.0
				var angle := time * lerpf(3.5, 10.0, power) + TAU * strand / 3.0
				var entry := _cannon_arc(start, axis, right, up, angle, a, power)
				var exit := _cannon_arc(start, axis, right, up, angle, b, power)
				_energy_strip(entry, exit, up * (0.018 + 0.035 * power), Color(1.1, 0.62, 0.27, power * sin(a * PI)))
	else:
		_beam_tube(start, start + axis * 0.10, right, up, 0.17 * power, Color(1.0, 0.51, 0.16, power))
	_energy_mesh.surface_end()


func _draw_prism_beam(start: Vector3, axis: Vector3, right: Vector3, up: Vector3,
		length: float, shot: float, time: float, spectral: bool, impact: bool) -> void:
	var end := start + axis * length
	var flicker := 0.95 + 0.05 * sin(time * 160.0)
	var outer := Color(0.22, 0.74, 1.58) if spectral else Color(1.65, 0.34, 0.065)
	var inner := Color(0.95, 1.50, 1.90) if spectral else Color(1.75, 1.22, 0.64)
	_beam_tube(start, end, right, up, 0.68 * shot * flicker, Color(outer, 0.28))
	_beam_tube(start, end, right, up, 0.43 * shot, Color(outer.lerp(inner, 0.50), 0.52))
	_beam_tube(start, end, right, up, 0.23 * shot * flicker, Color(inner, 0.97))
	var slices := clampi(ceili(length * 1.5), 23, 128)
	for strand in 3:
		var spin := time * (13.0 + strand * 2.3) + TAU * strand / 3.0
		for i in slices:
			var a := float(i) / slices
			var b := float(i + 1) / slices
			var r := (0.60 + 0.31 * sin(PI * a)) * shot
			var twist := spin + a * length * 0.63
			var next_twist := spin + b * length * 0.63
			var p := start + axis * (length * a) + (right * cos(twist) + up * sin(twist)) * r
			var q := start + axis * (length * b) + (right * cos(next_twist) + up * sin(next_twist)) * r
			var width := (right * cos(twist) + up * sin(twist)) * (0.085 + 0.025 * sin(twist))
			_energy_strip(p, q, width, Color(inner.lerp(outer, 0.26 + 0.18 * strand), shot * 0.78))
	for i in 9:
		var angle := (float(i) + 0.06 * sin(time * 11.0)) * TAU / 9.0
		var ray := right * cos(angle) + up * sin(angle)
		var next := right * cos(angle + 0.35) + up * sin(angle + 0.35)
		var mouth := start + axis * minf(0.22, length)
		var flash := shot * (0.65 + 0.35 * sin(time * 53.0 + i))
		_energy_triangle(mouth + ray * 0.30 * shot, mouth + ray * 1.37 * shot,
			mouth + next * 0.74 * shot, Color(inner, flash * 0.80))
		if impact:
			var radial := ray * shot * (0.75 + 0.14 * (i % 4))
			var at := end - axis * minf(0.16, length)
			_energy_triangle(at, at + radial, at - axis * minf(0.24, length) + next * 0.46 * shot,
				Color(outer, flash * 0.80))
			_energy_strip(at + radial * 0.42, at + radial * (1.34 + 0.18 * sin(time * 25.0 + i)),
				next * 0.045, Color(inner, flash * 0.92))


func _cannon_arc(start: Vector3, axis: Vector3, right: Vector3, up: Vector3,
		angle: float, u: float, power: float) -> Vector3:
	var twist := angle + u * 2.5
	var radius := lerpf(0.68 + 0.30 * power, 0.11, u)
	return start + axis * (1.1 * (1.0 - u)) + (right * cos(twist) + up * sin(twist)) * radius


func _beam_tube(start: Vector3, end: Vector3, right: Vector3, up: Vector3, radius: float, color: Color) -> void:
	for i in 12:
		var angle := TAU * i / 12.0
		var next_angle := TAU * (i + 1) / 12.0
		var a := (right * cos(angle) + up * sin(angle)) * radius
		var b := (right * cos(next_angle) + up * sin(next_angle)) * radius
		for vertex: Vector3 in [start + a, end + a, end + b, start + a, end + b, start + b]:
			_energy_mesh.surface_set_color(color)
			_energy_mesh.surface_add_vertex(vertex)


func _energy_ring(center: Vector3, x: float, z: float, width: float, color: Color) -> void:
	for i in 54:
		var a := Vector2.from_angle(TAU * float(i) / 54.0)
		var b := Vector2.from_angle(TAU * float(i + 1) / 54.0)
		var inside := center + Vector3(a.x * (x - width), 0, a.y * (z - width))
		var outside := center + Vector3(a.x * x, 0, a.y * z)
		var next_inside := center + Vector3(b.x * (x - width), 0, b.y * (z - width))
		var next_outside := center + Vector3(b.x * x, 0, b.y * z)
		for pt: Vector3 in [inside, outside, next_outside, inside, next_outside, next_inside]:
			_energy_mesh.surface_set_color(color)
			_energy_mesh.surface_add_vertex(pt)


func _energy_strip(a: Vector3, b: Vector3, width: Vector3, color: Color) -> void:
	for pt: Vector3 in [a - width, a + width, b + width, a - width, b + width, b - width]:
		_energy_mesh.surface_set_color(color)
		_energy_mesh.surface_add_vertex(pt)


func _energy_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_energy_mesh.surface_set_color(color)
	_energy_mesh.surface_add_vertex(a)
	_energy_mesh.surface_add_vertex(b)
	_energy_mesh.surface_add_vertex(c)


func _tone(from: float, to: float, duration: float) -> AudioStreamWAV:
	const RATE := 22050
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = RATE
	var pcm := PackedByteArray()
	var count := int(duration * RATE)
	pcm.resize(count * 2)
	var angle := 0.0
	for i in count:
		var u := float(i) / count
		var envelope := smoothstep(0.0, 0.08, u) * pow(1.0 - u, 1.65)
		angle += TAU * lerpf(from, to, u) / RATE
		var value := (sin(angle) * 0.78 + sin(angle * 1.51) * 0.22) * envelope
		pcm.encode_s16(i * 2, roundi(value * 18500.0))
	sound.data = pcm
	return sound


func _mechanical_roar(duration: float, two_swells: bool) -> AudioStreamWAV:
	const RATE := 22050
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = RATE
	var count := int(duration * RATE)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 3029
	var angle := 0.0
	var breath := 0.0
	for i in count:
		var u := float(i) / count
		var attack := smoothstep(0.0, 0.23, u)
		var swell := attack * (1.0 - smoothstep(0.41, 0.63, u))
		var echo := 0.69 * smoothstep(0.49, 0.67, u) * (1.0 - smoothstep(0.76, 1.0, u))
		if not two_swells:
			swell = attack * (1.0 - smoothstep(0.49, 1.0, u))
			echo = 0.0
		var envelope := maxf(swell, echo)
		var pitch := 56.0 + 34.0 * attack + 17.0 * swell + 9.0 * echo - 27.0 * u + sin(u * TAU * 9.3) * 3.3
		angle += TAU * pitch / RATE
		breath = lerpf(breath, noise.randf_range(-1.0, 1.0), 0.16)
		var throat := sin(angle) * 0.43 + sin(angle * 2.0) * 0.19 + sin(angle * 3.01) * 0.14
		var rattle := sin(angle * 5.03) * 0.09 + sin(angle * 8.1) * 0.06 + breath * 0.34
		var flutter := 0.86 + 0.14 * sin(u * TAU * 21.2)
		pcm.encode_s16(i * 2, roundi(clampf((throat + rattle) * envelope * flutter, -1.0, 1.0) * 30000.0))
	sound.data = pcm
	return sound

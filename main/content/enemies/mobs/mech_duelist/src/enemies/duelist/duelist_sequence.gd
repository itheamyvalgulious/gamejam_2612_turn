extends Node3D
## Shared choreography for the playable encounter and the model preview.

const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Brace = preload("res://src/enemies/duelist/duelist_ground_brace.gd")
const Charge = preload("res://src/enemies/duelist/duelist_charge.gd")
const Lunge = preload("res://src/enemies/duelist/duelist_lunge.gd")
const ReturnCut = preload("res://src/enemies/duelist/duelist_return_cut.gd")
const Trail = preload("res://src/vesper/blade_trail.gd")
const AttackFX = preload("res://src/enemies/duelist/duelist_attack_fx.gd")
const Afterimages = preload("res://src/enemies/duelist/duelist_afterimages.gd")
const Patrol = preload("res://src/enemies/duelist/duelist_patrol.gd")
const DoubleCut = preload("res://src/enemies/duelist/duelist_double_cut.gd")
const PursuitSweep = preload("res://src/enemies/duelist/duelist_pursuit_sweep.gd")
const SprintSlash = preload("res://src/enemies/duelist/duelist_sprint_slash.gd")
const Rebound = preload("res://src/enemies/duelist/duelist_rebound.gd")
const Guard = preload("res://src/enemies/duelist/duelist_guard.gd")
const Units = preload("res://src/core/units.gd")
const COMBO_PAUSE := 1.0
const NORMAL_WINDUP_EXTENSION := 0.3
const NORMAL_BREATHER := 0.82
const PURSUIT_SWEEP_COOLDOWN := 3.0
const ATTACK_AT := Pace.DURATION + Brace.CONTACT_TIME + Charge.DURATION
const RETURN_AT := ATTACK_AT + Lunge.DURATION
const PATROL_AT := RETURN_AT + ReturnCut.HIT_END
const END := RETURN_AT + ReturnCut.DURATION
const ATTACK_RATE := 0.5
const SWING_RATE := 1.0
const LINK_RATE := 2.0
const SPRINT_FLASH_SECONDS := (Lunge.BURST_END - Lunge.BURST_START) / ATTACK_RATE
const LINK_START := Lunge.CUT_END
const LINK_END := Lunge.DURATION + ReturnCut.TRAIL_START
const DASH_END_SECONDS := Lunge.BURST_END / ATTACK_RATE
const LINK_START_SECONDS := DASH_END_SECONDS + (LINK_START - Lunge.BURST_END) / SWING_RATE
const LINK_END_SECONDS := LINK_START_SECONDS + (LINK_END - LINK_START) / LINK_RATE

var time := 0.0
var dash: Dictionary = {}
var return_pose: Dictionary = {}
var model: Node3D
var center := Vector3.ZERO
var _cover: Array = []
var _bounds := AABB()
var patrol := Patrol.new()
var normal_pose: Dictionary = {}
var normal_move: GDScript = DoubleCut
var rebound_pose: Dictionary = {}
var rebound_time := 0.0
var normal_time := 0.0
var normal_serial := 0
var normal_attack_rate := 1.0
var normal_windup_extension := NORMAL_WINDUP_EXTENSION
var _normal_cooldown := 0.0
var _pursuit_sweep_cooldown := 0.0
var _sweep_pending := false
var _sprint_pending := false
var sprint_windup := -1.0
var _sprint_entry: Dictionary = {}
var _sprint_flash: Dictionary = {}
var _sprint_flash_age := 0.0
var _sprint_ghost_age := -1.0
var sprint_flashing: bool:
	get:
		return not _sprint_flash.is_empty()
var _patrol_focus := Vector3.INF
var _retreat_speed := 0.0
var _retreat_time := 0.0
var _guard_time := Guard.DURATION
var guarding: bool:
	get:
		return _guard_time < Guard.DURATION
var _last_focus := Vector3.ZERO
var _pace_elapsed := 0.0
var _pace_reverse := false
var _brace_from := Pace.DURATION
var finished: bool:
	get:
		return time >= END

var _trail := Trail.new()
var _effects := AttackFX.new()
var _afterimages := Afterimages.new()
var _audio: AudioStreamPlayer3D
static var _charge_sound: AudioStreamWAV


func setup(actor: Node3D, pace_center: Vector3, cover: Array = [], bounds := AABB()) -> void:
	model = actor
	center = pace_center
	_cover = cover
	_bounds = bounds
	add_child(_trail)
	_trail.lifetime = 0.105
	_trail.edge_width = 0.24
	var trail_material := _trail.material_override.duplicate() as ShaderMaterial
	trail_material.set_shader_parameter("silver_refraction", true)
	trail_material.set_shader_parameter("energy", 4.15)
	_trail.material_override = trail_material
	add_child(_effects)
	add_child(_afterimages)
	_afterimages.setup(model)
	_audio = AudioStreamPlayer3D.new()
	if _charge_sound == null:
		_charge_sound = Charge.make_sound()
	_audio.stream = _charge_sound
	_audio.unit_size = 6.0
	_audio.max_distance = 26.0
	_audio.panning_strength = 0.82
	_audio.position = Vector3(0, 0.73, -0.32)
	model.torso.add_child(_audio)


func seek(next_time: float, focus: Vector3) -> void:
	_trail.clear()
	_effects.clear_tip_sparks()
	return_pose.clear()
	patrol.reset()
	normal_pose.clear()
	normal_move = DoubleCut
	rebound_pose.clear()
	rebound_time = 0.0
	normal_time = 0.0
	normal_serial = 0
	normal_windup_extension = NORMAL_WINDUP_EXTENSION
	_normal_cooldown = 0.0
	_pursuit_sweep_cooldown = 0.0
	_sweep_pending = false
	_sprint_pending = false
	sprint_windup = -1.0
	_sprint_entry = {}
	_sprint_flash.clear()
	_sprint_flash_age = 0.0
	_sprint_ghost_age = -1.0
	_patrol_focus = Vector3.INF
	_retreat_speed = 0.0
	_retreat_time = 0.0
	_guard_time = Guard.DURATION
	dash.clear()
	_pace_elapsed = 0.0
	_pace_reverse = false
	_brace_from = Pace.DURATION
	_afterimages.clear()
	_last_focus = focus
	time = clampf(next_time, 0.0, END)
	_pose(focus)


func advance_pacing(dt: float, focus: Vector3, settle: bool) -> bool:
	var stop := Pace.brace_time(_pace_elapsed) if settle else Pace.DURATION
	_pace_elapsed += dt
	if settle:
		_pace_elapsed = minf(_pace_elapsed, stop)
	elif _pace_elapsed >= Pace.DURATION:
		_pace_elapsed -= Pace.DURATION
		_pace_reverse = not _pace_reverse
	Pace.apply(model, _pace_elapsed, center, 3.80, focus, _pace_reverse)
	if not settle or _pace_elapsed < stop:
		return false
	_brace_from = _pace_elapsed
	time = Pace.DURATION
	_last_focus = focus
	return true


func begin_guard() -> void:
	if not guarding and sprint_windup < 0.0:
		_guard_time = 0.0


func advance_guard(dt: float, focus: Vector3) -> void:
	if not guarding:
		return
	_guard_time = minf(_guard_time + dt, Guard.DURATION)
	# Let a guard begun while pacing fade out before the left hand meets the floor.
	var freedom := 1.0 if finished else 1.0 - smoothstep(Pace.DURATION + 0.16, Pace.DURATION + 0.32, time)
	if freedom <= 0.0:
		_guard_time = Guard.DURATION
		return
	Guard.apply(model, _guard_time, focus, freedom)


static func attack_seconds(clip_time: float) -> float:
	if clip_time <= Lunge.BURST_END:
		return clip_time / ATTACK_RATE
	if clip_time <= LINK_START:
		return DASH_END_SECONDS + (clip_time - Lunge.BURST_END) / SWING_RATE
	if clip_time <= LINK_END:
		return LINK_START_SECONDS + (clip_time - LINK_START) / LINK_RATE
	return LINK_END_SECONDS + (clip_time - LINK_END) / SWING_RATE


static func _attack_clip_time(seconds: float) -> float:
	if seconds <= DASH_END_SECONDS:
		return seconds * ATTACK_RATE
	if seconds <= LINK_START_SECONDS:
		return Lunge.BURST_END + (seconds - DASH_END_SECONDS) * SWING_RATE
	if seconds <= LINK_END_SECONDS:
		return LINK_START + (seconds - LINK_START_SECONDS) * LINK_RATE
	return LINK_END + (seconds - LINK_END_SECONDS) * SWING_RATE


static func normal_seconds(clip_time: float, windup_end: float, rate: float, extension := NORMAL_WINDUP_EXTENSION) -> float:
	return clip_time / rate + extension * minf(clip_time / windup_end, 1.0)


static func _normal_clip_time(seconds: float, windup_end: float, rate: float, extension: float) -> float:
	var windup_seconds := normal_seconds(windup_end, windup_end, rate, extension)
	if seconds < windup_seconds:
		return seconds * windup_end / windup_seconds
	return (seconds - extension) * rate


func advance(dt: float, focus: Vector3, rate := ATTACK_RATE) -> void:
	if finished:
		_advance_patrol(dt * rate / ATTACK_RATE, focus)
		return
	var lead_in := clampf(ATTACK_AT - time, 0.0, dt)
	var attack_dt := dt - lead_in
	var before := time - ATTACK_AT
	var blade_before: Transform3D = model.weapon_spin.global_transform
	var patrol_dt := 0.0
	if attack_dt > 0.0:
		var seconds := attack_seconds(maxf(before, 0.0)) + attack_dt * rate / ATTACK_RATE
		var next_time := ATTACK_AT + _attack_clip_time(seconds)
		patrol_dt = maxf(0.0, next_time - maxf(time, PATROL_AT))
		time = minf(next_time, END)
	else:
		time += lead_in
	var velocity := (focus - _last_focus).slide(Vector3.UP) / maxf(dt, 0.0001)
	_last_focus = focus
	_pose(focus, before, velocity, patrol_dt)
	var t := time - ATTACK_AT
	_update_slash_fx(before, t, blade_before)
	if before < Lunge.FRONT_LAND and t >= Lunge.FRONT_LAND:
		Snd.play_at("step", model.legs[0]["ankle"].global_position, {"gain": 0.75})
	if before < Lunge.TRAIL_START and t >= Lunge.TRAIL_START:
		Snd.play_at("swing_heavy", model.weapon_spin.global_position, {"gain": 0.74})
	var footfall := Lunge.DURATION + ReturnCut.RIGHT_LAND
	if before < footfall and t >= footfall:
		Snd.play_at("step", model.legs[1]["ankle"].global_position, {"gain": 0.65})
	if before < LINK_END and t >= LINK_END:
		Snd.play_at("swing_light", model.weapon_spin.global_position, {"gain": 0.86})


func _update_slash_fx(before: float, t: float, blade_before: Transform3D) -> void:
	if t < Lunge.TRAIL_START:
		return
	var blade: Transform3D = model.weapon_spin.global_transform
	var reverse_time := t - Lunge.DURATION
	var dt := t - before
	if t < Lunge.CUT_END:
		var crest := smoothstep(0.228, 0.317, t) * (1.0 - smoothstep(0.335, Lunge.CUT_END, t))
		var alpha := lerpf(0.31, 1.0, crest) * (1.0 - smoothstep(0.364, Lunge.CUT_END, t))
		_slash_ribbon(before, t, Lunge.TRAIL_START, blade_before, blade, Color(1.0, 1.0, 1.0, alpha))
	elif reverse_time >= ReturnCut.TRAIL_START and reverse_time < ReturnCut.HIT_END:
		var crest := smoothstep(ReturnCut.TRAIL_START, 0.270, reverse_time)
		var alpha := lerpf(0.38, 0.88, crest) * (1.0 - smoothstep(0.352, ReturnCut.HIT_END, reverse_time))
		_slash_ribbon(before, t, LINK_END, blade_before, blade, Color(0.70, 0.87, 1.0, alpha))
	else:
		_trail.tick(dt, false)
	if before <= Lunge.DURATION:
		_effects.sample_tip_sparks(t, _blade_tip())


func _slash_ribbon(before: float, time_now: float, start: float, blade_before: Transform3D,
		blade: Transform3D, tone: Color, metal_only := false) -> void:
	var reach: float = model.BLADE_START + model.BLADE_LENGTH if metal_only else model.SWEEP_END
	if before < start and time_now > start:
		var at_start := blade_before.interpolate_with(blade, inverse_lerp(before, time_now, start))
		_record_trail(0.0, at_start, tone, reach)
		before = start
	_record_trail(time_now - before, blade, tone, reach)


func _record_trail(dt: float, blade: Transform3D, tone: Color, reach: float) -> void:
	var heel := blade * Vector3(-0.078, model.BLADE_START + 0.34, 0)
	var crest := blade * Vector3(0.0, reach, 0.0)
	_trail.record(dt, heel, crest, tone)


func sync_audio(paused: bool, rate := ATTACK_RATE) -> void:
	var age := time - Pace.DURATION - Brace.CONTACT_TIME
	var volume := P.getf("audio.master")
	if paused or age < 0.0 or age >= Charge.AUDIO_DURATION or volume <= 0.001:
		if _audio.playing:
			_audio.stop()
		return
	var playback_rate := 1.0
	if time >= ATTACK_AT:
		playback_rate = rate * (SWING_RATE / ATTACK_RATE if time >= ATTACK_AT + Lunge.BURST_END else 1.0)
	_audio.pitch_scale = playback_rate
	_audio.volume_db = linear_to_db(volume * 0.82)
	if not _audio.playing or absf(_audio.get_playback_position() - age) > 0.16:
		_audio.play(age)



func _blade_tip() -> Vector3:
	return model.weapon_spin.to_global(Vector3(model.Blade.TIP_OFFSET, model.BLADE_START + model.BLADE_LENGTH, 0))


func _pose(focus: Vector3, before := -1.0, velocity := Vector3.ZERO, patrol_dt := 0.0) -> void:
	var attack_time := time - ATTACK_AT
	if attack_time < 0.0:
		_approach(time, focus)
	else:
		if dash.is_empty():
			_approach(ATTACK_AT, focus)
			dash = Lunge.begin(model, focus, _cover)
		var previous := model.position
		var path_position := previous
		if before < Lunge.BURST_END:
			path_position = Lunge.track_target(dash, focus, velocity, previous, before, minf(attack_time, Lunge.BURST_END))
		if attack_time >= Lunge.DURATION:
			if return_pose.is_empty():
				Lunge.apply(model, dash, Lunge.DURATION)
				return_pose = ReturnCut.begin(model, dash["watch"])
			if time >= PATROL_AT:
				if not patrol.active:
					ReturnCut.apply(model, return_pose, ReturnCut.HIT_END)
					patrol.begin(model, COMBO_PAUSE)
					if before < 0.0:
						patrol_dt = time - PATROL_AT
				_advance_patrol(patrol_dt, focus)
			else:
				ReturnCut.apply(model, return_pose, attack_time - Lunge.DURATION)
		elif attack_time > 0.0:
			Lunge.apply(model, dash, attack_time, path_position)
			if before >= 0.0:
				_afterimages.capture(model, before, attack_time, previous, model.position,
					func(sample: float, at: Vector3) -> void: Lunge.apply(model, dash, sample, at))
	if not patrol.active:
		var discharge := smoothstep(Lunge.BURST_END, Lunge.TRAIL_START + 0.015, attack_time)
		var red := 1.0 if attack_time >= 0.0 else 0.0
		model.set_charge_state(time - Pace.DURATION - Brace.CONTACT_TIME, discharge, red)
	_effects.apply(attack_time, dash, model.weapon_spin, model.legs[0]["ankle"])
	_afterimages.apply(attack_time)


func begin_rebound(focus: Vector3, normal: Vector3) -> bool:
	if normal_pose.is_empty():
		return false
	rebound_pose = Rebound.begin(model, focus, normal, normal_pose)
	rebound_time = 0.0
	normal_pose.clear()
	_trail.clear()
	model.set_charge_state(-1.0)
	return true


func _advance_patrol(dt: float, focus: Vector3) -> void:
	_update_sprint_approach(dt, focus)
	_pursuit_sweep_cooldown = maxf(0.0, _pursuit_sweep_cooldown - dt)
	if _sprint_ghost_age >= 0.0:
		_sprint_ghost_age += dt
		_afterimages.apply(Lunge.BURST_END + _sprint_ghost_age)
		if _sprint_ghost_age >= Afterimages.FADE_TIME:
			_sprint_ghost_age = -1.0
	if sprint_windup >= 0.0:
		_advance_sprint_entry(dt, focus)
		return
	if not rebound_pose.is_empty():
		_advance_rebound(dt, focus)
		return
	if not normal_pose.is_empty():
		_advance_normal(dt, focus)
		return
	_normal_cooldown = maxf(0.0, _normal_cooldown - dt)
	var ready := not guarding and _normal_cooldown == 0.0 and patrol.moving
	var sweep_ready := _pursuit_sweep_cooldown == 0.0
	var close_ready := DoubleCut.can_start(model, focus)
	var sweep_in_range := sweep_ready and PursuitSweep.can_start(model, focus, PursuitSweep.PREP_RANGE)
	if not sweep_in_range or _retreat_time >= 0.15:
		_sweep_pending = false
	elif not close_ready:
		_sweep_pending = true
	if _sweep_pending:
		_sprint_pending = false
		patrol.press_range = 0.0
	var can_strike := ready and (_sprint_pending or close_ready or sweep_in_range)
	var remainder := patrol.advance(model, dt, focus, _cover, _bounds, can_strike)
	if normal_serial == 0:
		var heat := 1.0 - smoothstep(0.0, Patrol.RECOVERY, patrol.recovery_age)
		model.set_charge_state(Charge.DURATION + 0.86, heat, heat)
	if not ready or not patrol.landed:
		return
	if not patrol.left_can_support(model):
		patrol.advance(model, remainder, focus, _cover, _bounds)
		return
	if _sprint_pending:
		var reach := SprintSlash.RETREAT_PREP_RANGE if _retreat_time >= 0.15 else SprintSlash.FIRST_CUT_RANGE
		if SprintSlash.can_start(model, focus, reach):
			_sprint_entry = SprintSlash.begin_ready(model, focus, _cover, _bounds)
			sprint_windup = 0.0
			model.set_charge_state(-1.0, 0.0, 1.0)
			_advance_sprint_entry(remainder, focus)
			return
		patrol.advance(model, remainder, focus, _cover, _bounds)
		return
	elif sweep_ready and PursuitSweep.can_start(model, focus) and (_sweep_pending
			or not DoubleCut.can_start(model, focus) or (normal_serial > 0 and normal_move == DoubleCut)):
		normal_move = PursuitSweep
	elif patrol.motion != Patrol.Step.BRAKE and DoubleCut.can_start(model, focus):
		normal_move = DoubleCut
	else:
		patrol.advance(model, remainder, focus, _cover, _bounds)
		return
	normal_windup_extension = NORMAL_WINDUP_EXTENSION
	_start_normal(normal_move.begin(model, focus, _cover, _bounds), 0.0, remainder, focus)


func _start_normal(pose: Dictionary, clip: float, dt: float, focus: Vector3) -> void:
	normal_pose = pose
	normal_time = clip
	normal_serial += 1
	_sweep_pending = false
	_sprint_pending = false
	sprint_windup = -1.0
	model.set_charge_state(-1.0, 0.0, 1.0)
	if dt > 0.0:
		_advance_normal(dt, focus)


func _advance_sprint_entry(dt: float, focus: Vector3) -> void:
	if not sprint_flashing:
		var spent := minf(dt, NORMAL_WINDUP_EXTENSION - sprint_windup)
		sprint_windup += spent
		_sprint_entry["focus"] = focus
		SprintSlash.apply_ready(model, _sprint_entry, sprint_windup / NORMAL_WINDUP_EXTENSION)
		if sprint_windup < NORMAL_WINDUP_EXTENSION:
			return
		dt -= spent
		var root := model.global_transform
		var path := Lunge.begin_path(root.origin, model.global_rotation.y, root.basis.get_scale().x, focus, _cover)
		var landing := DoubleCut._inside(path["end"], _bounds)
		if landing.distance_squared_to(root.origin) < pow(SprintSlash.MIN_FLASH_DISTANCE, 2):
			DoubleCut.place_steps(model, _sprint_entry, focus, _cover, _bounds)
			_start_sprint_cut(SprintSlash.READY_CLIP, dt, focus)
			return
		_sprint_flash = path
		_sprint_flash_age = 0.0
		_sprint_ghost_age = -1.0
		_afterimages.clear()
		_sprint_entry["flash_scale"] = root.basis.get_scale()

	if dt <= 0.0:
		return
	var elapsed := minf(dt, SPRINT_FLASH_SECONDS - _sprint_flash_age)
	var before := Lunge.BURST_START + _sprint_flash_age * ATTACK_RATE
	_sprint_flash_age += elapsed
	var clock := minf(Lunge.BURST_END, Lunge.BURST_START + _sprint_flash_age * ATTACK_RATE)
	var previous: Vector3 = model.global_position
	previous.y = (_sprint_flash["origin"] as Vector3).y
	var velocity := (focus - (_sprint_flash["watch"] as Vector3)).slide(Vector3.UP) / dt
	var next := Lunge.track_target(_sprint_flash, focus, velocity, previous, before, clock)
	next = DoubleCut._inside(next, _bounds)
	_sprint_entry["focus"] = focus
	_pose_sprint_flash(clock, next)
	_afterimages.capture(model, before, clock, previous, next, _pose_sprint_flash)
	_afterimages.apply(clock)
	if _sprint_flash_age >= SPRINT_FLASH_SECONDS:
		_sprint_ghost_age = 0.0
		_sprint_flash.clear()
		_start_sprint_cut(SprintSlash.FLASH_READY_CLIP, dt - elapsed, focus)


func _pose_sprint_flash(clock: float, point: Vector3) -> void:
	var progress := Lunge.burst_at(clock)
	var yaw := lerp_angle(_sprint_flash["yaw"], _sprint_flash["aim"], progress)
	var basis := Basis(Vector3.UP, yaw).scaled(_sprint_entry["flash_scale"])
	point.y += 0.10 * sin(PI * progress)
	model.global_transform = Transform3D(basis, point)
	# The burst supplies the translation while the lead foot and blade prepare the cut.
	DoubleCut.place_steps(model, _sprint_entry, _sprint_entry["focus"], _cover, _bounds, false)
	var clip := lerpf(SprintSlash.READY_CLIP, SprintSlash.FLASH_READY_CLIP, progress)
	DoubleCut.apply(model, _sprint_entry, clip)


func _start_sprint_cut(clip: float, dt: float, focus: Vector3) -> void:
	var pose := _sprint_entry
	_sprint_entry = {}
	normal_move = SprintSlash
	normal_windup_extension = 0.0
	_start_normal(pose, clip, dt, focus)


func _update_sprint_approach(dt: float, focus: Vector3) -> void:
	var offset := (focus - model.global_position).slide(Vector3.UP)
	var direction := offset.normalized()
	var outward := 0.0
	if _patrol_focus.is_finite() and dt > 0.0:
		outward = maxf(0.0, (focus - _patrol_focus).dot(direction) * Units.M_PER_UNIT / dt)
	_patrol_focus = focus
	_retreat_speed = lerpf(_retreat_speed, outward, 1.0 - exp(-15.0 * dt))
	_retreat_time = clampf(_retreat_time + (dt if _retreat_speed > 1.6 else -2.0 * dt), 0.0, 0.20)
	if sprint_windup >= 0.0 or not normal_pose.is_empty() or not rebound_pose.is_empty():
		return

	var gap := offset.length()
	if gap > Patrol.RUN_ENTRY_RANGE or -model.global_basis.z.normalized().dot(direction) < 0.60:
		_sprint_pending = false
	elif gap <= Patrol.RUN_RANGE and (gap > SprintSlash.PRESS_START_RANGE
			or (_retreat_time >= 0.15 and not DoubleCut.can_start(model, focus))):
		_sprint_pending = true
	var chase := smoothstep(1.6, 7.3, _retreat_speed)
	patrol.press_haste = chase
	patrol.press_range = lerpf(SprintSlash.FIRST_CUT_RANGE, SprintSlash.WINDUP_APPROACH_RANGE, chase) if _sprint_pending else 0.0


func _advance_normal(dt: float, focus: Vector3) -> void:
	var before := normal_time
	var windup_end: float = normal_move.WINDUP_END
	var elapsed := normal_seconds(before, windup_end, normal_attack_rate, normal_windup_extension) + dt
	normal_time = minf(_normal_clip_time(elapsed, windup_end, normal_attack_rate, normal_windup_extension), normal_move.DURATION)
	var blade_before: Transform3D = model.weapon_spin.global_transform
	var clip_step := normal_time - before
	if normal_move == SprintSlash and before < SprintSlash.RUN_START and normal_time >= SprintSlash.RUN_START:
		SprintSlash.prepare_run(model, normal_pose, focus, _cover, _bounds)
	normal_move.apply(model, normal_pose, normal_time)
	for footfall: Vector3 in normal_move.FOOTFALLS:
		if before < footfall.x and normal_time >= footfall.x:
			Snd.play_at("step", model.legs[int(footfall.y)]["ankle"].global_position, {"gain": footfall.z})
	var strikes: Array = normal_move.STRIKES
	var active := 0
	for i in range(1, strikes.size()):
		if normal_time >= strikes[i].y:
			active = i
	var strike: Vector4 = strikes[active]
	var thrust := normal_move == PursuitSweep and active == 0
	var trail_start := strike.y
	var hit_end := strike.w
	if before < trail_start and normal_time >= trail_start:
		Snd.play_at("swing_heavy" if active > 0 else "swing_light", model.weapon_spin.global_position, {"gain": 0.65})
	if not thrust and normal_time >= trail_start and normal_time < hit_end:
		var blade: Transform3D = model.weapon_spin.global_transform
		var tint := Color(0.88, 0.96, 1.0, 0.77) if active > 0 else Color(0.76, 0.88, 1.0, 0.54)
		_slash_ribbon(before, normal_time, trail_start, blade_before, blade, tint, true)
	else:
		_trail.tick(clip_step, false)
	var last_strike: Vector4 = strikes.back()
	if before < last_strike.w and normal_time >= last_strike.w:
		model.set_charge_state(-1.0)
	if normal_time >= normal_move.DURATION:
		normal_pose.clear()
		var remaining := elapsed - normal_seconds(normal_time, windup_end, normal_attack_rate, normal_windup_extension)
		_resume_patrol(maxf(0.0, remaining), focus)


func _advance_rebound(dt: float, focus: Vector3) -> void:
	var before := rebound_time
	rebound_time = minf(rebound_time + dt, Rebound.DURATION)
	Rebound.apply(model, rebound_pose, rebound_time)
	if rebound_time >= Rebound.DURATION:
		rebound_pose.clear()
		_resume_patrol(dt - (rebound_time - before), focus)


func _resume_patrol(dt: float, focus: Vector3) -> void:
	_normal_cooldown = NORMAL_BREATHER
	if normal_move == PursuitSweep:
		_pursuit_sweep_cooldown = PURSUIT_SWEEP_COOLDOWN
	var next_foot := 0 if normal_move == PursuitSweep else patrol.next_foot
	patrol.begin(model, 0.0, next_foot, model.sword_wrist_deviation())
	patrol.advance(model, dt, focus, _cover, _bounds)


func _approach(sample: float, focus: Vector3) -> void:
	var pacing := sample < Pace.DURATION
	Pace.apply(model, sample if pacing else _brace_from, center, 3.80, focus, _pace_reverse)
	if sample >= Pace.DURATION:
		var elapsed := sample - Pace.DURATION
		Brace.apply(model, Brace.depth_at(elapsed), true, focus, Charge.load_at(elapsed - Brace.CONTACT_TIME))

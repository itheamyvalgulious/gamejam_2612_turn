class_name ArcSwordFX2
extends Node3D

# ---------------------------------------------------------------------------
# Arc blade FX driver. Spawns staggered blade bolts and short unconstrained
# escape arcs from an ArcField2 volume. Ported from
# weapon_electricity_sword/src/arc_sword.gd without the generator hilt; attach
# this node to whatever emitter geometry the character rig provides.
#
# The blade points along local +Y, from y = 0 to y ~= 2.24 * blade_scale.
# ---------------------------------------------------------------------------

const ARC_BOLT := preload("res://scripts/ch/arc_bolt.gd")
const ARC_FIELD := preload("res://scripts/ch/arc_field.gd")

const SPAWN_INTERVAL := 0.012
const BOLT_LIFE := 0.190
const PARTIAL_SCALE := 0.80
const ESCAPE_WAVE_INTERVAL := 0.020
const ESCAPE_LIFE_MIN := 0.060
const ESCAPE_LIFE_MAX := 0.135
const FLOOR_Y := 0.035

@export_range(0.05, 2.0, 0.01) var blade_scale := 0.46
@export var external_intensity := 1.0

## Total number of bolts spawned since _ready(). Useful for profiling/demos.
var bolts_spawned := 0

var _field
var _rng := RandomNumberGenerator.new()
var _spawn_accum := 0.0
var _time := 0.0
var _intensity := 1.0
var _avg_weight := 0.0
var _escape_accum := 0.0

func _ready() -> void:
	_field = ARC_FIELD.new()
	_field.blade_scale = blade_scale
	_rng.randomize()
	# Populate instantly so the first rendered frame already has a sword.
	for i in range(6):
		_spawn_bolt(1.0)
	_spawn_escape_batch()

func _process(delta: float) -> void:
	# A long frame must not let every short-lived bolt expire and then dump a
	# budget burst in the same tick; clamp the step so the arc stays steady.
	delta = minf(delta, 0.047)
	_time += delta

	# Slow, soft swells instead of sharp strobe pulses.
	var breath := 0.5 + 0.5 * sin(_time * 0.35 + 0.8)
	_intensity = external_intensity * (0.89 + 0.025 * breath)

	_spawn_accum += delta
	var budget := 14
	while _spawn_accum >= SPAWN_INTERVAL and budget > 0:
		_spawn_accum -= SPAWN_INTERVAL
		budget -= 1
		_spawn_bolt(_intensity * _rng.randf_range(0.97, 1.03))
	if _spawn_accum > SPAWN_INTERVAL * 8.0:
		_spawn_accum = 0.0

	_escape_accum += delta
	var escape_budget := 6
	while _escape_accum >= ESCAPE_WAVE_INTERVAL and escape_budget > 0:
		_escape_accum -= ESCAPE_WAVE_INTERVAL
		escape_budget -= 1
		_spawn_escape_batch()
	if _escape_accum > ESCAPE_WAVE_INTERVAL * 8.0:
		_escape_accum = 0.0

## Change the blade length at runtime. Affects newly generated bolts only.
func set_blade_scale(value: float) -> void:
	blade_scale = clampf(value, 0.05, 2.0)
	if _field != null:
		_field.blade_scale = blade_scale

## World-space +Y extent of the blade (origin of the emitter is y = 0).
func blade_tip_y() -> float:
	if _field != null:
		return _field.tip_y()
	return 2.24 * blade_scale

func _floor_filter(edges: Array) -> Array:
	# The stochastic escape arcs are unconstrained in the field model. Clip any
	# ribbon that would cross the stage floor: a sword may be low, its sparks
	# may not pass through the floor.
	var out: Array = []
	var xf := global_transform
	for e in edges:
		var a: Vector3 = xf * (e["a"] as Vector3)
		var b: Vector3 = xf * (e["b"] as Vector3)
		if minf(a.y, b.y) < FLOOR_Y:
			continue
		out.append(e)
	return out


func _spawn_bolt(energy: float) -> void:
	var edges: Array = _floor_filter(_field.grow(_rng, PARTIAL_SCALE))
	if edges.is_empty():
		return
	var weight := 0.0
	for e in edges:
		var length: float = (e["b"] as Vector3).distance_to(e["a"] as Vector3)
		weight += float(e["width"]) * float(e["energy"]) * maxf(length, 0.01)
	if _avg_weight <= 0.0:
		_avg_weight = weight
	else:
		_avg_weight = lerpf(_avg_weight, weight, 0.14)
	var norm := clampf(pow(_avg_weight / maxf(weight, 0.0001), 0.65), 0.82, 1.14)

	var bolt = ARC_BOLT.new()
	bolt.spatial_scale = blade_scale
	add_child(bolt)
	# A long crossfade with many staggered bolts hides the 20 ms restrikes.
	bolt.setup(edges, _rng, BOLT_LIFE * _rng.randf_range(0.92, 1.08), 0.32 * _rng.randf_range(0.95, 1.05), energy * norm)
	bolts_spawned += 1

func _spawn_escape_batch() -> void:
	# Many short, unconstrained escape trees at once. They are independent
	# bolts with instant on/off (no fade), so they crackle around the blade
	# and vanish abruptly just like the other arcs. Sizes are exponential:
	# mostly small licks, occasionally a large forked tree.
	var count := _rng.randi_range(3, 6)
	for i in range(count):
		var edges: Array = _floor_filter(_field.grow_escape_one(_rng))
		if edges.is_empty():
			continue
		var bolt = ARC_BOLT.new()
		bolt.spatial_scale = blade_scale
		add_child(bolt)
		var lifetime := _rng.randf_range(ESCAPE_LIFE_MIN, ESCAPE_LIFE_MAX)
		bolt.setup(edges, _rng, lifetime, 0.55 * _rng.randf_range(0.88, 1.12), 1.0, true)
		bolts_spawned += 1
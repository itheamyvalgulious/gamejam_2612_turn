extends Node
## Snd — 运行时合成 + 双耳空间混音总线。
##
## 没有任何音频文件：所有波形都由 `Synth` 用振荡器/噪声 + 双二阶滤波 + 包络算出来，
## 缓存成 PackedFloat32Array，再由这里逐样本混音成**立体声**输出。
##
## 空间化不是"引擎摆位"，是自己按物理建模做的双耳线索：
##   ILD  双耳声级差（等功率摆位）
##   ITD  双耳时间差（远耳最多 ~0.65 ms，短历史缓冲插值）
##   头部阴影  远耳一阶低通（越偏侧越闷）
##   前后线索  声源在背后时整体变闷 + 轻微衰减（近似耳廓方向滤波）
##   距离  1/(1+d/d0) 衰减 + 空气吸收低通（越远越闷）
##   遮挡  视线被墙挡住 → 更闷更小（用关卡墙段做 2D 视线判定）
##   多普勒  按声源/听者径向相对速度改播放速率（343 m/s）
## 这些量每 64 个样本更新一次，逐样本只做取包 + 插值 + 两个一阶滤波。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const SynthKit = preload("res://src/audio/synth.gd")

const SR := 12000
const BLK := 64
const MAX_VOICES := 14
const FULL_TIER := 6          # 音量大/近的 6 个声部走完整双耳处理，其余走廉价通道
const VARIANTS := 4
const UNIT_DIST := 4.0
const SOUND_SPEED := 343.0
const ITD_MAX_SMP := 8.0

const PRIO := {"step": 1, "hit": 2, "swing": 2, "arrow": 3, "clang": 3, "qi": 2, "laser": 3,
	"slam": 3, "death": 2, "player_death": 4, "parry": 3, "chime": 2, "ping": 3}


class V:
	var id := 0
	var kind := ""
	var buf: PackedFloat32Array
	var n := 0
	var idx := 0.0
	var rate := 1.0
	var loop := false
	var alive := true
	var gain := 1.0
	var prio := 1
	var pos := Vector3.ZERO
	var prev_pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var node: Node3D = null
	var g_l := 0.7
	var g_r := 0.7
	var c_l := 0.6
	var c_r := 0.6
	var d_l := 0.0
	var d_r := 0.0
	var lp_l := 0.0
	var lp_r := 0.0
	var itd := 0.0
	var shadow_l := 1.0
	var shadow_r := 1.0
	var atend := 0.0
	var hist: PackedFloat32Array
	var hi := 0
	var fade_out_from := -1
	var tier := 0
	var cf := 0.6


var listener_pos := Vector3.ZERO
var listener_basis := Basis.IDENTITY

var master := 0.85
var vol_step := 1.0
var vol_swing := 1.0
var vol_arrow := 1.0
var max_dist := 90.0
var spatial := true
var occlusion := true
var doppler_scale := 1.0
var muted := false

var last_mix_usec := 0
var last_peak := 0.0
var voice_peak := 0

var _voices: Array = []
var _by_id: Dictionary = {}
var _cache: Dictionary = {}
var _next_id := 1
var _rng := RandomNumberGenerator.new()
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _wall_segs: Array = []
var _prev_listener := Vector3.ZERO
var _listener_vel := Vector3.ZERO
var _tmp_l := PackedFloat32Array()
var _tmp_r := PackedFloat32Array()
var _out := PackedVector2Array()
var _var_counter := 0
var _silent_frames := 0
var reverb_mix := 0.22
# Schroeder 混响状态（12 kHz 下按 44.1k 的经典延时等比缩短）
const CB1 := 424
const CB2 := 440
const AP1 := 61
var _cb1 := PackedFloat32Array()
var _cb2 := PackedFloat32Array()
var _ap1 := PackedFloat32Array()
var _ci1 := 0
var _ci2 := 0
var _ai1 := 0


func _ready() -> void:
	_rng.seed = 0x5EEDA0D1
	_player = AudioStreamPlayer.new()
	_player.name = "BinauralOut"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = float(SR)
	gen.buffer_length = 0.14
	_player.stream = gen
	_player.bus = &"Master"
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback()
	_cb1.resize(CB1)
	_cb2.resize(CB2)
	_ap1.resize(AP1)
	process_priority = 127
	for k in ["step", "swing_light", "arrow_whistle", "clang", "arrow_hit", "hit"]:
		_wave(k, 0)


func set_arena(arena: Dictionary) -> void:
	_wall_segs = arena.get("walls", [])


func sync_params() -> void:
	master = P.getf("audio.master")
	vol_step = P.getf("audio.step_volume")
	vol_swing = P.getf("audio.swing_volume")
	vol_arrow = P.getf("audio.arrow_volume")
	max_dist = P.getf("audio.max_distance")
	spatial = P.getb("audio.spatial")
	occlusion = P.getb("audio.occlusion")
	doppler_scale = P.getf("audio.doppler")
	muted = master <= 0.001


# ------------------------------------------------------------------ 波形缓存
func _wave(kind: String, variant: int) -> PackedFloat32Array:
	var key := "%s#%d" % [kind, variant]
	if _cache.has(key):
		return _cache[key]
	var buf: PackedFloat32Array = SynthKit.samples(kind, variant)
	_cache[key] = buf
	return buf


func _pick_variant() -> int:
	_var_counter += 1
	return _var_counter % VARIANTS


# ------------------------------------------------------------------ 播放 API
func play_at(kind: String, pos: Vector3, opts := {}) -> int:
	if muted:
		return 0
	var v := _alloc(kind, opts)
	if v == null:
		return 0
	v.buf = _wave(kind, _pick_variant())
	v.n = v.buf.size()
	return v.id


func loop_on(kind: String, node: Node3D, opts := {}) -> int:
	if muted or node == null:
		return 0
	var v := _alloc(kind, opts)
	if v == null:
		return 0
	v.buf = _wave(kind, _pick_variant())
	v.n = v.buf.size()
	v.loop = true
	v.node = node
	v.pos = node.global_position
	v.prev_pos = v.pos
	return v.id


func set_pos(id: int, pos: Vector3) -> void:
	var v: V = _by_id.get(id)
	if v != null:
		v.pos = pos


func stop(id: int) -> void:
	var v: V = _by_id.get(id)
	if v == null:
		return
	if v.loop:
		# 循环音的 idx 可能因为长期「听不到」而远超缓冲区长度：
		# 先绕回一个周期内，否则会把缓冲区撑到几万个样本、尾巴还会取到越界样本
		v.idx = _wrap_idx(v.idx, v.buf.size())
		# 30 ms 线性淡出，避免咔哒
		var need := int(v.idx) + int(SR * 0.03) + 1
		if need > v.buf.size():
			var ext := v.buf
			ext.resize(need)
			v.buf = ext
			v.n = need
		v.loop = false
		v.fade_out_from = int(v.idx)
	else:
		v.alive = false


func stop_all() -> void:
	for v in _voices:
		v.alive = false
	_voices.clear()
	_by_id.clear()


func _alloc(kind: String, opts: Dictionary) -> V:
	var alive_n := 0
	for q in _voices:
		if q.alive:
			alive_n += 1
	var prio: int = int(opts.get("prio", PRIO.get(kind, 1)))
	if alive_n >= MAX_VOICES:
		var worst: V = null
		for q in _voices:
			if not q.alive:
				continue
			if worst == null or q.prio < worst.prio:
				worst = q
			elif q.prio == worst.prio and q.gain < worst.gain:
				worst = q
		if worst == null or prio <= worst.prio:
			return null
		worst.alive = false
		_by_id.erase(worst.id)
	var v := V.new()
	v.id = _next_id
	_next_id += 1
	v.kind = kind
	v.prio = prio
	v.pos = opts.get("pos", Vector3.ZERO)
	v.prev_pos = v.pos
	v.gain = float(opts.get("gain", 1.0))
	v.rate = float(opts.get("rate", 1.0))
	v.hist = PackedFloat32Array()
	v.hist.resize(32)
	_voices.append(v)
	_by_id[v.id] = v
	voice_peak = maxi(voice_peak, alive_n + 1)
	return v


# ------------------------------------------------------------------ 主循环
func _process(delta: float) -> void:
	if _pb == null or muted:
		return
	var t0 := Time.get_ticks_usec()
	_update_listener(delta)
	var avail := _pb.get_frames_available()
	if avail <= 0:
		return
	avail = mini(avail, int(SR * 0.14))
	if _tmp_l.size() < avail:
		_tmp_l.resize(avail)
		_tmp_r.resize(avail)
	if _out.size() != avail:
		_out.resize(avail)
	# 没有任何声部时直接推静音（省掉整条混音链与混响）
	if _voices.is_empty():
		_silent_frames += 1
		if _silent_frames > 45:
			_cb1.fill(0.0)
			_cb2.fill(0.0)
			_ap1.fill(0.0)
			for i in avail:
				_out[i] = Vector2.ZERO
			_pb.push_buffer(_out)
			last_peak = 0.0
			last_mix_usec = Time.get_ticks_usec() - t0
			return
	else:
		_silent_frames = 0
	_tmp_l.fill(0.0)
	_tmp_r.fill(0.0)
	var done := 0
	while done < avail:
		var n: int = mini(BLK, avail - done)
		for v in _voices:
			if v.alive:
				_update_spatial(v, float(n) / float(SR))
		_assign_tiers()
		for v in _voices:
			if v.alive:
				_render(v, n, done)
		done += n
	var m := master * 1.15
	var peak := 0.0
	var rv: float = clampf(P.getf("audio.reverb"), 0.0, 1.0)
	for i in avail:
		var l := _tmp_l[i] * m
		var r := _tmp_r[i] * m
		var dry_l := l
		var dry_r := r
		if rv > 0.001:
			# 两条梳状滤波器（带阻尼）+ 一条全通
			var mono := (l + r) * 0.5
			var d1: float = _cb1[_ci1]
			_cb1[_ci1] = mono + d1 * 0.72
			_ci1 = (_ci1 + 1) % CB1
			var d2: float = _cb2[_ci2]
			_cb2[_ci2] = mono + d2 * 0.66
			_ci2 = (_ci2 + 1) % CB2
			var wet: float = (d1 + d2) * 0.5
			var ap: float = _ap1[_ai1]
			var ap_out: float = -wet * 0.5 + ap
			_ap1[_ai1] = wet + ap * 0.5
			_ai1 = (_ai1 + 1) % AP1
			l = dry_l + ap_out * rv
			r = dry_r + ap_out * rv
		l = l / (1.0 + 0.35 * absf(l))
		r = r / (1.0 + 0.35 * absf(r))
		peak = maxf(peak, maxf(absf(l), absf(r)))
		_out[i] = Vector2(l, r)
	last_peak = peak
	_pb.push_buffer(_out)
	var dead: Array = []
	for v in _voices:
		if not v.alive:
			dead.append(v)
	for v in dead:
		_voices.erase(v)
		_by_id.erase(v.id)
	last_mix_usec = Time.get_ticks_usec() - t0


## 只有最响的若干声部走完整双耳处理，其余走廉价通道（保 CPU）
func _assign_tiers() -> void:
	var sorted: Array = []
	for v in _voices:
		if v.alive:
			sorted.append(v)
	sorted.sort_custom(func(a, b): return (a.g_l + a.g_r) > (b.g_l + b.g_r))
	for i in sorted.size():
		sorted[i].tier = 0 if i < FULL_TIER else 1


func _update_listener(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		listener_pos = cam.global_position
		listener_basis = cam.global_transform.basis
	var dt := maxf(delta, 1.0 / 240.0)
	_listener_vel = (listener_pos - _prev_listener) / dt
	_prev_listener = listener_pos


func _update_spatial(v: V, dt: float) -> void:
	var p: Vector3 = v.pos
	if v.node != null:
		if not is_instance_valid(v.node):
			v.alive = false
			return
		p = v.node.global_position
	v.vel = (p - v.prev_pos) / maxf(dt, 1e-4)
	v.prev_pos = p
	v.pos = p
	var rel := p - listener_pos
	var d := rel.length()
	if d > max_dist:
		v.atend = 0.0
		v.g_l = 0.0
		v.g_r = 0.0
		v.d_l = 0.0
		v.d_r = 0.0
		return
	var dir := rel / maxf(d, 0.001)
	var att := pow(UNIT_DIST / (UNIT_DIST + d), 1.25)
	v.atend = att
	if not spatial:
		v.g_l = 0.577 * att * 1.4
		v.g_r = 0.577 * att * 1.4
		v.c_l = 0.6
		v.c_r = 0.6
		v.d_l = 0.0
		v.d_r = 0.0
		v.itd = 0.0
		return
	var pan: float = clampf(dir.dot(listener_basis.x), -1.0, 1.0)
	v.g_l = sqrt((1.0 - pan) * 0.5) * att
	v.g_r = sqrt((1.0 + pan) * 0.5) * att
	v.itd = absf(pan) * ITD_MAX_SMP
	v.d_l = maxf(0.0, pan)      # 声源在右 → 左耳拿延迟样本
	v.d_r = maxf(0.0, -pan)
	var fb: float = dir.dot(-listener_basis.z)
	var behind: float = clampf(-fb, 0.0, 1.0)
	var air: float = 1.0 / (1.0 + d / 12.0)
	var shadow: float = lerpf(1.0, 0.22, absf(pan))
	var occ := 1.0
	if occlusion and not _wall_segs.is_empty():
		if Vision.los_blocked_2d(Vector2(listener_pos.x, listener_pos.z), Vector2(p.x, p.z),
				_wall_segs):
			occ = 0.20
			v.g_l *= 0.55
			v.g_r *= 0.55
	var k_l: float = air * occ * lerpf(1.0, 0.42, behind)
	var k_r: float = air * occ * lerpf(1.0, 0.42, behind)
	if pan > 0.0:
		k_l *= lerpf(1.0, shadow, pan)
	else:
		k_r *= lerpf(1.0, shadow, -pan)
	v.c_l = clampf(0.45 * k_l, 0.02, 0.95)
	v.c_r = clampf(0.45 * k_r, 0.02, 0.95)
	# 单滤波系数（气吸/遮挡/背后变闷）—— 逐样本只跑一个一阶低通
	v.cf = clampf(0.45 * minf(k_l, k_r), 0.02, 0.95)
	v.shadow_l = lerpf(1.0, 0.72, maxf(0.0, pan))
	v.shadow_r = lerpf(1.0, 0.72, maxf(0.0, -pan))
	if doppler_scale > 0.0:
		var radial: float = (v.vel - _listener_vel).dot(dir)   # 正 = 远离
		var denom: float = SOUND_SPEED + radial
		if absf(denom) > 0.001:
			var f: float = SOUND_SPEED / denom
			if is_finite(f):
				v.rate = clampf(lerpf(1.0, f, clampf(doppler_scale, 0.0, 1.0)), 0.5, 2.0)


## 把播放位置绕回 [0, n)。循环音长期「听不到」时 idx 会一直累加，
## 不绕回一个周期内就会取到缓冲区外面（曾经直接让引擎报越界并崩掉）。
static func _wrap_idx(idx: float, n: int) -> float:
	if n <= 0 or not is_finite(idx):
		return 0.0
	var w := fmod(idx, float(n))
	if w < 0.0:
		w += float(n)
	return w


func _render(v: V, n: int, base: int) -> void:
	# 空缓冲区 / 坏掉的播放位置：直接收尾，别在这里制造越界和死循环
	if v.n <= 0 or not is_finite(v.idx):
		v.alive = false
		return
	if v.g_l + v.g_r < 0.0008 and v.atend < 0.002:
		# 听不到：只推进播放位置（但仍然要负责收尾，否则声部槽位会被占满）
		v.idx += v.rate * float(n)
		if v.loop:
			v.idx = _wrap_idx(v.idx, v.n)      # 听不到的时候也要绕回来
		elif v.idx >= float(v.n):
			v.alive = false
		return
	var buf := v.buf
	var nbuf := v.n
	var idx := v.idx
	var rate := v.rate
	var gain := v.gain * _kind_gain(v.kind)
	var fade_from := v.fade_out_from
	var full := v.tier == 0
	var gl := v.g_l * v.shadow_l
	var gr := v.g_r * v.shadow_r
	var cf := v.cf
	var lp := v.lp_l
	var hist := v.hist
	var hlen := hist.size()
	var hi := v.hi
	var itd := v.itd
	var dl := v.d_l
	var dr := v.d_r
	for i in n:
		if idx >= float(nbuf) or idx < 0.0:
			if v.loop:
				idx = _wrap_idx(idx, nbuf)
			else:
				v.alive = false
				break
		var i0 := int(idx)
		if i0 < 0:
			i0 = 0
		elif i0 >= nbuf:
			i0 = nbuf - 1
		var s := buf[i0]
		var sf := s
		var sl := s
		var sr := s
		if full:
			# 一个共享一阶低通：空气吸收 + 遮挡 + 背后变闷
			lp += (s - lp) * cf
			sf = lp
			sl = sf
			sr = sf
			if itd > 0.01:
				hist[hi] = sf
				hi += 1
				if hi >= hlen:
					hi = 0
				var back := float(hi) - 1.0 - itd
				while back < 0.0:
					back += float(hlen)
				var b0 := int(back)
				var bf := back - float(b0)
				var sd := lerpf(hist[b0 % hlen], hist[(b0 + 1) % hlen], bf)
				# 只延迟「远耳」：这是真正的耳间时间差
				sl = lerpf(sf, sd, dl)
				sr = lerpf(sf, sd, dr)
		if fade_from > 0:
			var u: float = clampf((float(i0) - float(fade_from)) / float(SR * 0.03), 0.0, 1.0)
			_tmp_l[base + i] += sl * gl * gain * (1.0 - u)
			_tmp_r[base + i] += sr * gr * gain * (1.0 - u)
		else:
			_tmp_l[base + i] += sl * gl * gain
			_tmp_r[base + i] += sr * gr * gain
		idx += rate
	v.idx = idx
	v.hi = hi
	v.lp_l = lp


const BASE_GAIN := {"step": 0.55, "swing_light": 0.75, "swing_heavy": 0.85, "arrow_whistle": 0.6,
	"arrow_hit": 0.8, "clang": 0.9, "parry": 1.0, "hit": 0.9, "qi": 0.8, "qi_loop": 0.7,
	"laser": 0.95, "slam": 1.0, "death": 1.0, "player_death": 1.0, "chime": 0.7, "ping": 0.5}


func _kind_gain(kind: String) -> float:
	var base: float = float(BASE_GAIN.get(kind, 1.0))
	if kind.begins_with("step"):
		return vol_step * base
	if kind.begins_with("swing") or kind.begins_with("qi") or kind.begins_with("slam"):
		return vol_swing * base
	if kind.begins_with("arrow"):
		return vol_arrow * base
	if kind.begins_with("clang") or kind.begins_with("parry") or kind.begins_with("hit"):
		return base
	return base


# ------------------------------------------------------------------ 自检 / 调试
## 给定世界坐标返回"应听到"的左右增益（自测 + 说明用）
func pan_preview(pos: Vector3) -> Vector2:
	var rel := pos - listener_pos
	var d := rel.length()
	if d < 0.001:
		return Vector2(0.707, 0.707)
	var dir := rel / d
	var pan: float = clampf(dir.dot(listener_basis.x), -1.0, 1.0)
	var att: float = pow(UNIT_DIST / (UNIT_DIST + d), 1.25)
	return Vector2(sqrt((1.0 - pan) * 0.5) * att, sqrt((1.0 + pan) * 0.5) * att)


## 听声辨位测试：听者周围 8 个方位依次响一声
func test_surround() -> void:
	var f := listener_basis.z
	var r := listener_basis.x
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := (r * sin(a) - f * cos(a)).normalized()
		play_at("ping", listener_pos + dir * 9.0, {"prio": 3})


func voice_count() -> int:
	var n := 0
	for v in _voices:
		if v.alive:
			n += 1
	return n


func cached_kinds() -> int:
	return _cache.size()

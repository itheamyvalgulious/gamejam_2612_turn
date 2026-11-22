extends RefCounted
class_name Synth
## 纯数学音源合成器：没有采样、没有音频文件。
##
## 每个音效 = 若干「层」，每层 = 一个声源（白噪声 / 正弦 / 锯齿）
##   → 一个双二阶滤波器（带通/低通/高通，中心频率可随时间扫描）
##   → 一条包络（分段线性，可近似 ADSR / 指数衰减）
## 逐样本叠加后量化成 16bit PCM，装进 AudioStreamWAV 给 3D 播放器。
##
## 反过来也就是真实物理味的来源：
##   脚步 = 宽带噪声激励 + 结构共振（模态）
##   挥剑 = 空气湍流噪声经过一个随刀速扫描的带通（气动声学）
##   箭啸 = 窄带自激 + 多普勒
##   打铁 = 金属板的多阶非谐模态（1 : 2.76 : 5.40 : 8.93 : 13.3）

const SR := 12000


# ------------------------------------------------------------------ 滤波器
## RBJ 双二阶：返回 [b0, b1, b2, a1, a2]
static func _coeffs(kind: String, fc: float, q: float, sr: float) -> Array:
	var w0: float = TAU * clampf(fc, 20.0, sr * 0.45) / sr
	var cw: float = cos(w0)
	var sw: float = sin(w0)
	var alpha: float = sw / (2.0 * maxf(q, 0.05))
	match kind:
		"lp":
			var b1 := 1.0 - cw
			var a0 := 1.0 + alpha
			return [(1.0 - cw) * 0.5 / a0, (1.0 - cw) / a0, (1.0 - cw) * 0.5 / a0,
				-2.0 * cw / a0, (1.0 - alpha) / a0]
		"hp":
			var a0h := 1.0 + alpha
			return [(1.0 + cw) * 0.5 / a0h, -(1.0 + cw) / a0h, (1.0 + cw) * 0.5 / a0h,
				-2.0 * cw / a0h, (1.0 - alpha) / a0h]
		"bp":
			var a0b := 1.0 + alpha
			return [alpha / a0b, 0.0, -alpha / a0b, -2.0 * cw / a0b, (1.0 - alpha) / a0b]
	return [1.0, 0.0, 0.0, 0.0, 0.0]


## 分段线性包络：env = [[t0,v0],[t1,v1],...]
static func _env_at(env: Array, t: float) -> float:
	if env.is_empty():
		return 1.0
	if t <= float(env[0][0]):
		return float(env[0][1])
	for i in env.size() - 1:
		var t0 := float(env[i][0])
		var t1 := float(env[i + 1][0])
		if t >= t0 and t <= t1:
			var u: float = (t - t0) / maxf(t1 - t0, 1e-6)
			return lerpf(float(env[i][1]), float(env[i + 1][1]), u)
	return float(env[env.size() - 1][1])


## 指数衰减包络生成器：[[0,1],[tau*1,0.37],...] 采样成 12 段
static func _exp_env(dur: float, tau: float, peak := 1.0, attack := 0.002, segs := 12) -> Array:
	var e: Array = [[0.0, 0.0], [attack, peak]]
	for i in range(1, segs + 1):
		var t := dur * float(i) / float(segs)
		e.append([t, peak * exp(-t / maxf(tau, 1e-4))])
	return e


static func _freq(f0: float, f1: float, u: float, mode: String) -> float:
	match mode:
		"exp":
			return f0 * pow(maxf(f1, 1.0) / maxf(f0, 1.0), u)
		"arc":
			# 先上后下：u<0.5 从 f0 扫到峰值，u>0.5 从峰值扫到 f1
			if u < 0.5:
				return lerpf(f0, f1, u * 2.0)
			return lerpf(f1, f0 * 0.6 + f1 * 0.4, (u - 0.5) * 2.0)
	return lerpf(f0, f1, u)


# ------------------------------------------------------------------ 渲染
## layers: [{osc:"noise"|"sine"|"saw", f0, f1, fmode:"lin"|"exp"|"arc", q, filt:"bp"|"lp"|"hp"|"none",
##           env:[[t,v]...], gain, jitter}]
static func render_layers(dur: float, layers: Array, seed_i: int) -> PackedFloat32Array:
	var n := int(maxf(dur, 0.01) * SR)
	var acc := PackedFloat32Array()
	acc.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	for L in layers:
		var osc := String(L.get("osc", "noise"))
		var f0 := float(L.get("f0", 1000.0)) * (1.0 + rng.randf_range(-1.0, 1.0) * float(L.get("jitter", 0.0)))
		var f1 := float(L.get("f1", f0))
		var fmode := String(L.get("fmode", "lin"))
		var q := float(L.get("q", 1.0))
		var filt := String(L.get("filt", "bp"))
		var gain := float(L.get("gain", 1.0))
		var env: Array = L.get("env", [[0.0, 1.0], [dur, 0.0]])
		var b0 := 0.0
		var b1 := 0.0
		var b2 := 0.0
		var a1 := 0.0
		var a2 := 0.0
		var x1 := 0.0
		var x2 := 0.0
		var y1 := 0.0
		var y2 := 0.0
		var ph := 0.0
		var blk := 64
		var i := 0
		while i < n:
			var nb: int = mini(blk, n - i)
			var u := float(i) / float(n)
			var fc := _freq(f0, f1, u, fmode)
			if filt != "none":
				var c := _coeffs(filt, fc, q, float(SR))
				b0 = c[0]
				b1 = c[1]
				b2 = c[2]
				a1 = c[3]
				a2 = c[4]
			for k in nb:
				var idx := i + k
				var t := float(idx) / float(SR)
				var s := 0.0
				match osc:
					"sine":
						s = sin(ph)
					"saw":
						var u2 := ph / TAU
						s = 2.0 * (u2 - floor(u2 + 0.5))
					_:
						s = rng.randf_range(-1.0, 1.0)
				ph += TAU * fc / float(SR)
				if ph > TAU:
					ph -= TAU
				if filt != "none":
					var y := b0 * s + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
					x2 = x1
					x1 = s
					y2 = y1
					y1 = y
					s = y
				acc[idx] += s * gain * _env_at(env, t)
			i += nb
	# 去直流 + 软限幅
	var mean := 0.0
	for v in acc:
		mean += v
	mean /= maxf(1.0, float(n))
	for idx in n:
		var v2: float = (acc[idx] - mean) * 1.6
		acc[idx] = tanh(v2)
	return acc


## 无缝循环：把尾部与头部交叉淡化，然后把尾段剪掉（循环周期 = n - f）。
## 循环回卷点落在「相邻样本」之间，所以不会有咔哒声。
static func seamless_loop(buf: PackedFloat32Array, fade_ms := 10.0) -> PackedFloat32Array:
	var n := buf.size()
	var f := int(fade_ms * 0.001 * SR)
	if n < f * 4:
		return buf
	for i in f:
		var u := float(i) / float(f)
		buf[i] = buf[i] * u + buf[n - f + i] * (1.0 - u)
	buf.resize(n - f)
	return buf


static func to_wav(buf: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	var i := 0
	for v in buf:
		var s: int = clampi(int(round(v * 32000.0)), -32768, 32767)
		bytes.encode_s16(i, s)
		i += 2
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


# ------------------------------------------------------------------ 音色库
static func _metal_modes(base: float, gain: float, dur: float) -> Array:
	var ratios := [1.0, 2.76, 5.40, 8.93, 13.3]
	var taus := [0.42, 0.28, 0.17, 0.11, 0.07]
	var out: Array = []
	for i in ratios.size():
		out.append({"osc": "sine", "f0": base * float(ratios[i]), "filt": "none",
			"env": _exp_env(dur, float(taus[i]) * dur / 0.7, gain * (1.0 - 0.14 * float(i))),
			"gain": 1.0, "jitter": 0.02})
	return out


static func samples(kind: String, variant: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	var seed_i := int(rng.randi())
	var buf: PackedFloat32Array
	match kind:
		# ---------------- 脚步：金属足垫"咔" + 伺服电机 + 极轻的低频身体感
		"step":
			var d := 0.22
			buf = render_layers(d, [
				# 1) 足垫触地：很短的宽带"咔"（不再是低频鼓）
				{"osc": "noise", "f0": 3200.0, "f1": 1800.0, "q": 0.9, "filt": "bp",
					"env": [[0.0, 0.0], [0.003, 1.0], [0.02, 0.30], [0.07, 0.03], [d, 0.0]],
					"gain": 0.9, "jitter": 0.15},
				# 2) 伺服电机：短促下滑音（机械感的关键）
				{"osc": "saw", "f0": 1350.0, "f1": 520.0, "fmode": "exp", "filt": "lp", "q": 2.6,
					"env": [[0.0, 0.0], [0.010, 0.34], [0.05, 0.12], [0.14, 0.0]], "gain": 0.30},
				# 3) 身体重量：很短很低的一下，-14 dB 级别
				{"osc": "sine", "f0": 115.0, "f1": 78.0, "filt": "none",
					"env": [[0.0, 0.55], [0.02, 0.25], [0.07, 0.0]], "gain": 0.16},
			] + _metal_modes(1650.0 + rng.randf_range(-160, 160), 0.16, 0.10) as Array, seed_i)
		# ---------------- 挥剑：钢刃切空气的高频"唰"（真实刀风几乎没有低频）
		"swing_light":
			var d2 := 0.34
			buf = render_layers(d2, [
				{"osc": "noise", "f0": 850.0, "f1": 4200.0, "fmode": "arc", "q": 1.7, "filt": "bp",
					"env": [[0.0, 0.0], [0.035, 0.45], [0.13, 1.0], [d2, 0.0]], "gain": 1.0,
					"jitter": 0.08},
				# 刃口哨音：一条随时间上扫的窄带
				{"osc": "sine", "f0": 1900.0, "f1": 3400.0, "fmode": "arc", "filt": "bp", "q": 9.0,
					"env": [[0.0, 0.0], [0.08, 0.0], [0.15, 0.45], [d2, 0.0]], "gain": 0.40},
				{"osc": "noise", "f0": 5200.0, "q": 0.8, "filt": "hp",
					"env": [[0.0, 0.0], [0.06, 0.30], [0.18, 0.22], [d2, 0.0]], "gain": 0.35},
			], seed_i)
		"swing_heavy":
			var d3 := 0.55
			buf = render_layers(d3, [
				{"osc": "noise", "f0": 420.0, "f1": 3000.0, "fmode": "arc", "q": 1.3, "filt": "bp",
					"env": [[0.0, 0.0], [0.07, 0.5], [0.26, 1.0], [d3, 0.0]], "gain": 1.0,
					"jitter": 0.08},
				{"osc": "sine", "f0": 900.0, "f1": 2200.0, "fmode": "arc", "filt": "bp", "q": 8.0,
					"env": [[0.0, 0.0], [0.16, 0.0], [0.30, 0.40], [d3, 0.0]], "gain": 0.35},
				{"osc": "noise", "f0": 4200.0, "q": 0.7, "filt": "hp",
					"env": [[0.0, 0.0], [0.12, 0.35], [0.35, 0.20], [d3, 0.0]], "gain": 0.3},
			], seed_i)
		# ---------------- 箭啸：细而尖的哨音（循环）
		"arrow_whistle":
			buf = seamless_loop(render_layers(0.25, [
				{"osc": "noise", "f0": 4200.0, "f1": 4600.0, "q": 5.0, "filt": "bp",
					"env": [[0.0, 0.85], [0.25, 1.0]], "gain": 0.42},
				{"osc": "sine", "f0": 2620.0, "f1": 2660.0, "filt": "none",
					"env": [[0.0, 0.50], [0.25, 0.54]], "gain": 1.0},
				{"osc": "sine", "f0": 2740.0, "f1": 2780.0, "filt": "none",
					"env": [[0.0, 0.40], [0.25, 0.43]], "gain": 1.0},
				{"osc": "sine", "f0": 5240.0, "f1": 5300.0, "filt": "none",
					"env": [[0.0, 0.16], [0.25, 0.18]], "gain": 1.0},
			], seed_i))
		"arrow_hit":
			buf = render_layers(0.20, [
				{"osc": "noise", "f0": 5600.0, "q": 0.8, "filt": "hp",
					"env": [[0.0, 1.0], [0.012, 0.30], [0.07, 0.0]], "gain": 0.9},
				{"osc": "noise", "f0": 1500.0, "f1": 900.0, "q": 1.2, "filt": "bp",
					"env": [[0.0, 0.7], [0.03, 0.3], [0.14, 0.0]], "gain": 0.5},
			] + _metal_modes(2100.0, 0.22, 0.16) as Array, seed_i)
		# ---------------- 打铁 / 弹反：钢件高频非谐模态（不再是"桶鼓"）
		"clang":
			buf = render_layers(0.55, [
				{"osc": "noise", "f0": 6000.0, "q": 0.7, "filt": "hp",
					"env": [[0.0, 1.0], [0.008, 0.35], [0.05, 0.0]], "gain": 0.85},
			] + _metal_modes(1850.0 + rng.randf_range(-120, 120), 0.42, 0.55) as Array, seed_i)
		"parry":
			buf = render_layers(0.7, [
				{"osc": "noise", "f0": 7200.0, "q": 0.6, "filt": "hp",
					"env": [[0.0, 1.0], [0.006, 0.40], [0.04, 0.0]], "gain": 0.9},
			] + _metal_modes(2600.0 + rng.randf_range(-150, 150), 0.46, 0.7) as Array, seed_i)
		# ---------------- 命中装甲：闷一点的金属敲击
		"hit":
			buf = render_layers(0.26, [
				{"osc": "noise", "f0": 1400.0, "q": 1.0, "filt": "bp",
					"env": [[0.0, 1.0], [0.02, 0.35], [0.12, 0.0]], "gain": 0.8},
			] + _metal_modes(760.0, 0.30, 0.24) as Array, seed_i)
		# ---------------- 刀气：中频呼啸 + 泛音
		"qi":
			buf = render_layers(0.6, [
				{"osc": "noise", "f0": 700.0, "f1": 2600.0, "fmode": "arc", "q": 2.0, "filt": "bp",
					"env": [[0.0, 0.0], [0.05, 0.8], [0.25, 1.0], [0.6, 0.0]], "gain": 0.9},
				{"osc": "sine", "f0": 1400.0, "f1": 2600.0, "fmode": "lin", "filt": "none",
					"env": [[0.0, 0.0], [0.07, 0.20], [0.6, 0.0]], "gain": 0.30},
			], seed_i)
		"qi_loop":
			buf = seamless_loop(render_layers(0.3, [
				{"osc": "noise", "f0": 2100.0, "f1": 2400.0, "q": 4.5, "filt": "bp",
					"env": [[0.0, 0.9], [0.3, 1.0]], "gain": 0.5},
			], seed_i))
		"sentry_charge":
			# 谐波保持同相位循环。蓄力升调由机甲当前的充能进度驱动。
			var hold := [[0.0, 1.0], [0.41, 1.0]]
			buf = seamless_loop(render_layers(0.41, [
				{"osc": "sine", "f0": 150.0, "filt": "none", "env": hold, "gain": 0.56},
				{"osc": "sine", "f0": 450.0, "filt": "none", "env": hold, "gain": 0.24},
				{"osc": "sine", "f0": 750.0, "filt": "none", "env": hold, "gain": 0.10},
				{"osc": "noise", "f0": 1100.0, "filt": "bp", "q": 2.5, "env": hold, "gain": 0.23},
			], seed_i))
		# ---------------- 激光：明亮锯齿上扫 + 噪声
		"laser":
			buf = render_layers(0.40, [
				{"osc": "saw", "f0": 600.0, "f1": 5200.0, "fmode": "exp", "filt": "hp", "q": 0.9,
					"env": [[0.0, 0.0], [0.03, 0.9], [0.14, 0.5], [0.40, 0.0]], "gain": 0.42},
				{"osc": "noise", "f0": 4200.0, "f1": 2000.0, "q": 2.0, "filt": "bp",
					"env": [[0.0, 1.0], [0.10, 0.6], [0.40, 0.0]], "gain": 0.55},
			], seed_i)
		# ---------------- 重击落地：次低频下扫（这个是"大砸"，保留低频但加金属碎屑）
		"slam":
			buf = render_layers(1.0, [
				{"osc": "sine", "f0": 130.0, "f1": 42.0, "fmode": "exp", "filt": "none",
					"env": _exp_env(1.0, 0.16, 1.0), "gain": 0.9},
				{"osc": "noise", "f0": 900.0, "f1": 260.0, "q": 0.6, "filt": "lp",
					"env": _exp_env(0.9, 0.20, 0.55), "gain": 1.0},
				{"osc": "noise", "f0": 3800.0, "q": 0.9, "filt": "hp",
					"env": _exp_env(0.5, 0.06, 0.45), "gain": 1.0},
			] + _metal_modes(1250.0, 0.28, 0.5) as Array, seed_i)
		# ---------------- 击破
		"death":
			buf = render_layers(1.0, [
				{"osc": "noise", "f0": 1600.0, "f1": 420.0, "q": 0.7, "filt": "lp",
					"env": _exp_env(1.0, 0.22, 0.7), "gain": 1.0},
				{"osc": "sine", "f0": 190.0, "f1": 55.0, "fmode": "exp", "filt": "none",
					"env": _exp_env(1.0, 0.16, 0.7), "gain": 0.9},
				{"osc": "noise", "f0": 4600.0, "q": 0.8, "filt": "hp",
					"env": _exp_env(0.6, 0.10, 0.5), "gain": 1.0},
			] + _metal_modes(1700.0, 0.26, 0.7) as Array, seed_i)
		"player_death":
			buf = render_layers(1.3, [
				{"osc": "noise", "f0": 1200.0, "q": 0.6, "filt": "lp",
					"env": _exp_env(1.3, 0.30, 0.75), "gain": 1.0},
				{"osc": "sine", "f0": 150.0, "f1": 40.0, "fmode": "exp", "filt": "none",
					"env": _exp_env(1.3, 0.24, 0.9), "gain": 1.0},
			] + _metal_modes(900.0, 0.30, 0.9) as Array, seed_i)
		# ---------------- 过关提示
		"chime":
			buf = render_layers(1.2, [
				{"osc": "sine", "f0": 880.0, "filt": "none", "env": _exp_env(1.2, 0.30, 0.30), "gain": 1.0},
				{"osc": "sine", "f0": 1320.0, "filt": "none", "env": _exp_env(1.2, 0.22, 0.20), "gain": 1.0},
				{"osc": "sine", "f0": 1760.0, "filt": "none", "env": _exp_env(1.2, 0.14, 0.14), "gain": 1.0},
			], seed_i)
		# ---------------- 调试定位音
		"ping":
			buf = render_layers(0.30, [
				{"osc": "sine", "f0": 1050.0, "filt": "none", "env": _exp_env(0.30, 0.07, 0.6), "gain": 1.0},
			], seed_i)
		_:
			buf = render_layers(0.2, [
				{"osc": "sine", "f0": 660.0, "filt": "none", "env": _exp_env(0.2, 0.05, 0.4), "gain": 1.0},
			], seed_i)
	return _normalize(buf)


## 峰值归一化（不用 RMS：RMS 会把瞬态推到峰值削平，听起来全像鼓）
static func _normalize(buf: PackedFloat32Array, peak_target := 0.88) -> PackedFloat32Array:
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	if peak < 1e-5:
		return buf
	var k := peak_target / peak
	for i in buf.size():
		buf[i] = buf[i] * k
	return buf


## 波形自检用：返回 {n, peak, rms, nan}
static func stats(buf: PackedFloat32Array) -> Dictionary:
	var peak := 0.0
	var sum := 0.0
	var bad := 0
	for v in buf:
		if is_nan(v) or is_inf(v):
			bad += 1
			continue
		peak = maxf(peak, absf(v))
		sum += v * v
	# 低频占比：一阶低通(≈200Hz)后的能量 / 总能量。鼓声会 > 0.5，机械碰撞应 < 0.25
	var lp := 0.0
	var c: float = clampf(0.45 * (200.0 / (SR * 0.5)), 0.01, 0.5)
	var losum := 0.0
	for v in buf:
		lp += (v - lp) * c
		losum += lp * lp
	var tot := maxf(sum, 1e-9)
	return {"n": buf.size(), "peak": peak, "rms": sqrt(sum / maxf(1.0, float(buf.size()))),
		"nan": bad, "low_ratio": sqrt(losum / tot)}

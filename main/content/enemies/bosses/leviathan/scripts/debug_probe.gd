extends Node3D
## Debug probe for the acceptance metrics. Prints, does not render.

const BOSS := preload("res://scenes/character.tscn")
const D2R := PI / 180.0
const N := 40
var boss


func _ready() -> void:
	boss = BOSS.instantiate()
	add_child(boss)
	await _frames(3)
	boss.manual = true
	boss.set_auto(false)
	boss.set_process(false)
	var what := OS.get_environment("DBG")
	if what == "":
		what = "idle"
	if what == "idle":
		_dbg_idle()
	elif what == "attack3":
		_dbg_attack3()
	elif what == "support":
		_dbg_support()
	elif what == "perf":
		_dbg_perf()
	elif what == "clear":
		_dbg_clear()
	elif what == "exit":
		_dbg_exit()
	get_tree().quit(0)


func _dbg_exit() -> void:
	_set_roles(["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle"])
	_step(120)
	for k in 8:
		var T = boss.tents[k]
		var base: Vector3 = T.base
		var bd: Vector3 = T.base_dir_w
		var line := ""
		for i in range(1, 5):
			var rel: Vector3 = T.pts[i] - base
			var d := rel.length()
			var ang := rad_to_deg(acos(clampf(rel.normalized().dot(bd), -1.0, 1.0)))
			var lat := (rel - bd * rel.dot(bd)).length()
			line += " i%d d=%.2f ang=%.0f lat=%.2f" % [i, d, ang, lat]
		var tip: Vector3 = T.pts[N - 1]
		print("EXIT T%d%s tip=(%.1f,%.1f,%.1f) r=%.1f" % [k + 1, line,
			tip.x, tip.y, tip.z, Vector2(tip.x, tip.z).length()])
		var line2 := ""
		for i in [3, 5, 8, 12, 20, 30]:
			var p2: Vector3 = T.pts[i]
			line2 += " i%d=(%.1f,%.1f,%.1f)" % [i, p2.x, p2.y, p2.z]
		print("PATH T%d%s" % [k + 1, line2])


func _dbg_clear() -> void:
	_set_roles(["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle"])
	_step(150)
	_report_pair(5, 6)
	_report_pair(0, 1)
	_report_pair(2, 3)
	var A = boss.tents[5]
	var B = boss.tents[6]
	var best := 1e9
	var best_t := 0.0
	var bi := -1
	var bj := -1
	for k in 240:
		_step(3)
		for i in range(0, N - 1):
			for j in range(0, N - 1):
				var d := _seg_dist(A.pts[i], A.pts[i + 1], B.pts[j], B.pts[j + 1])
				d -= (A.radii[i] + A.radii[i + 1] + B.radii[j] + B.radii[j + 1]) * 0.25
				if d < best:
					best = d
					best_t = k * 0.05
					bi = i
					bj = j
	print("T6/T7 MIN over 12s best=%.3f at t=%.2f i=%d j=%d" % [best, best_t, bi, bj])
	if bi >= 0:
		print("  A pts[%d]=(%.2f,%.2f,%.2f) pts[%d]=(%.2f,%.2f,%.2f)" % [bi, A.pts[bi].x, A.pts[bi].y, A.pts[bi].z, bi + 1, A.pts[bi + 1].x, A.pts[bi + 1].y, A.pts[bi + 1].z])
		print("  B pts[%d]=(%.2f,%.2f,%.2f) pts[%d]=(%.2f,%.2f,%.2f)" % [bj, B.pts[bj].x, B.pts[bj].y, B.pts[bj].z, bj + 1, B.pts[bj + 1].x, B.pts[bj + 1].y, B.pts[bj + 1].z])


func _report_pair(a: int, b: int) -> void:
	var A = boss.tents[a]
	var B = boss.tents[b]
	var best := 1e9
	var bi := -1
	var bj := -1
	for i in range(0, N - 1):
		for j in range(0, N - 1):
			var d := _seg_dist(A.pts[i], A.pts[i + 1], B.pts[j], B.pts[j + 1])
			d -= (A.radii[i] + A.radii[i + 1] + B.radii[j] + B.radii[j + 1]) * 0.25
			if d < best:
				best = d
				bi = i
				bj = j
	print("PAIR T%d/T%d best=%.3f at i=%d j=%d" % [a + 1, b + 1, best, bi, bj])
	print("  A pts[%d]=(%.2f,%.2f,%.2f) pts[%d]=(%.2f,%.2f,%.2f)" % [bi, A.pts[bi].x, A.pts[bi].y, A.pts[bi].z, bi + 1, A.pts[bi + 1].x, A.pts[bi + 1].y, A.pts[bi + 1].z])
	print("  B pts[%d]=(%.2f,%.2f,%.2f) pts[%d]=(%.2f,%.2f,%.2f)" % [bj, B.pts[bj].x, B.pts[bj].y, B.pts[bj].z, bj + 1, B.pts[bj + 1].x, B.pts[bj + 1].y, B.pts[bj + 1].z])
	print("  base A=%s base B=%s" % [str(A.base), str(B.base)])


func _dbg_perf() -> void:
	boss.reset_boss()
	boss.set_auto(true)
	boss.set_phase_force(2)
	_step(240)
	_perf("normal", 400)
	boss.debug_no_mesh = true
	_perf("no_mesh", 400)
	boss.debug_no_mesh = false
	boss.debug_no_relax = true
	_perf("no_relax", 400)
	boss.debug_no_relax = false
	boss.debug_no_tent = true
	_perf("no_tent", 400)
	boss.debug_no_tent = false
	boss.debug_no_mesh = true
	boss.debug_no_relax = true
	_perf("move_only", 400)


func _perf(label: String, n: int) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		boss.sim_step(1.0 / 60.0)
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	print("PERF %-10s %.2f ms/step" % [label, us / 1000.0])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _step(n: int) -> void:
	for i in n:
		boss.sim_step(1.0 / 60.0)


func _set_roles(roles: Array) -> void:
	boss.reset_boss()
	boss.manual = true
	boss.set_auto(false)
	for i in 8:
		boss.force_role(i, "idle")
	for i in roles.size():
		if roles[i] != "idle":
			boss.force_role(i, roles[i])


func _dbg_idle() -> void:
	_set_roles(["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle"])
	_step(120)
	var mn: Array = []
	var mx: Array = []
	for i in 8:
		var p: Vector3 = boss.tents[i].pts[N - 1]
		mn.append(p)
		mx.append(p)
	for s in 100:
		_step(6)
		for i in 8:
			var p: Vector3 = boss.tents[i].pts[N - 1]
			mn[i] = Vector3(minf(mn[i].x, p.x), minf(mn[i].y, p.y), minf(mn[i].z, p.z))
			mx[i] = Vector3(maxf(mx[i].x, p.x), maxf(mx[i].y, p.y), maxf(mx[i].z, p.z))
	for i in 8:
		var dx: float = mx[i].x - mn[i].x
		var dz: float = mx[i].z - mn[i].z
		var dy: float = mx[i].y - mn[i].y
		print("T%d role=%s tip=(%.2f,%.2f,%.2f) range x=%.2f y=%.2f z=%.2f L=%.2f" % [
			i + 1, boss.tents[i].role, boss.tents[i].pts[N - 1].x, boss.tents[i].pts[N - 1].y,
			boss.tents[i].pts[N - 1].z, dx, dy, dz, boss.tents[i].spine_length()])


func _dbg_attack3() -> void:
	_set_roles(["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle"])
	_step(30)
	boss.force_role(2, "attack3")
	var tn = boss.tents[2]
	print("start az0=%.1f start_tip=%s target=%s" % [rad_to_deg(tn.attack_az0), str(tn.attack_start_tip), str(boss.target_chest)])
	for s in 210:
		boss.sim_step(1.0 / 60.0)
		if s % 10 == 0:
			var c: Vector3 = boss.body_center
			var p: Vector3 = tn.pts[N - 1]
			var az := rad_to_deg(atan2(p.x - c.x, p.z - c.z))
			print("s=%d t=%.2f atk_t=%.2f role=%s kind=%d tip=(%.1f,%.1f,%.1f) az=%.1f r=%.1f L=%.2f" % [
				s, boss.t, tn.attack_t, tn.role, tn.attack_kind, p.x, p.y, p.z, az,
				Vector2(p.x - c.x, p.z - c.z).length(), tn.spine_length()])


func _dbg_support() -> void:
	_set_roles(["support", "support", "support", "support", "support", "idle", "idle", "idle"])
	_step(240)
	var f := FileAccess.open("/tmp/opencode/boss_shots/dbg_support.txt", FileAccess.WRITE)
	for s in 60:
		_step(6)
		for i in 5:
			var tn = boss.tents[i]
			var ln: float = tn.spine_length()
			var pin: float = tn.pts[N - 1].distance_to(tn.foot)
			var sc := _self_worst(tn)
			f.store_line("s=%d T%d L=%.3f target=%.3f tip=(%.2f,%.2f,%.2f) foot=(%.2f,%.2f,%.2f) pin=%.3f self=%.3f idx=%d,%d" % [
				s, i + 1, ln, tn.L, tn.pts[N - 1].x, tn.pts[N - 1].y, tn.pts[N - 1].z,
				tn.foot.x, tn.foot.y, tn.foot.z, pin, sc[0], sc[1], sc[2]])
	f.close()
	print("support debug written")


func _self_worst(tn) -> Array:
	var best := 1e9
	var bi := -1
	var bj := -1
	var p: PackedVector3Array = tn.pts
	for i in range(0, N - 2):
		for j in range(i + 1, N - 1):
			if j - i < 4:
				continue
			var d := _seg_dist(p[i], p[i + 1], p[j], p[j + 1])
			d -= (tn.radii[i] + tn.radii[i + 1] + tn.radii[j] + tn.radii[j + 1]) * 0.25
			if d < best:
				best = d
				bi = i
				bj = j
	return [best, bi, bj]


func _seg_dist(p1: Vector3, p2: Vector3, q1: Vector3, q2: Vector3) -> float:
	var d1 := p2 - p1
	var d2 := q2 - q1
	var r := p1 - q1
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return p1.distance_to(q1)
	if a <= 1e-9:
		s = 0.0
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var denom := a * e - bb * bb
			if absf(denom) > 1e-9:
				s = clampf((bb * f - c * e) / denom, 0.0, 1.0)
			else:
				s = 0.0
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(q1 + d2 * t)
#!/usr/bin/env python3
"""One-shot codemod: swap blade collision from disc profiles to BladeProxy.

Run once from the worktree root. Replaces the disc-based functions in every
src/core/hitgd.gd copy and rewrites the call sites in combat.gd / intercept.gd /
player.gd / enemy rigs. Idempotent: aborts if markers are missing.
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
LEVELS = [ROOT / "main/content/levels" / d for d in
          ("actdemo", "cargo_hold2", "city", "galleria", "shadow_chamber", "shared")]
ENEMIES = [ROOT / "main/content/enemies/mobs" / d for d in ("mech_duelist", "wheel_sentry")]


NEW_BLADE_FUNCS = '''## 一次挥砍：凸体代理沿 prev_xf→cur_xf 扫掠（子采样），与目标胶囊求最深接触。
## disc_scale 参数已废弃：缩放通过变换本身表达。
static func sweep_blade(prev_xf: Transform3D, cur_xf: Transform3D, proxy: BladeProxy,
		cap_a: Vector3, cap_b: Vector3, cap_r: float) -> Dictionary:
	if proxy == null or proxy.pieces.is_empty():
		return {"hit": false}
	return BladeProxy.sweep_capsule(prev_xf, cur_xf, proxy, cap_a, cap_b, cap_r)


## 飞行物这一帧的位移线段 prev→pos 是否穿过刀身（凸体代理）
static func segment_vs_blade(prev: Vector3, pos: Vector3, xf: Transform3D,
		proxy: BladeProxy, sphere_r: float) -> Dictionary:
	return BladeProxy.segment_vs_proxy(prev, pos, xf, proxy, sphere_r)


## 剑挡剑：两把凸体刀求表面最短距离（不再有圆盘半径和）。
## 只要两把刀真的交在一起就算挡住 —— 与「谁在谁的画面里」毫无关系。
static func blade_vs_blade(xf_a: Transform3D, proxy_a: BladeProxy,
		xf_b: Transform3D, proxy_b: BladeProxy, slack := 0.03,
		span_a := Vector2(-INF, INF), span_b := Vector2(-INF, INF)) -> Dictionary:
	return BladeProxy.blade_vs_blade(xf_a, proxy_a, xf_b, proxy_b, slack, span_a, span_b)


## 扫掠版剑挡剑：两把刀这一帧各自从 prev 扫到 cur，3×4 子采样。
## 快刀单帧能扫过 2 m，只比「当前一瞬间」会漏判，所以格挡必须用扫掠。
static func blade_vs_blade_swept(prev_a: Transform3D, cur_a: Transform3D,
		proxy_a: BladeProxy, prev_b: Transform3D, cur_b: Transform3D,
		proxy_b: BladeProxy, slack := 0.03,
		span_a := Vector2(-INF, INF), span_b := Vector2(-INF, INF)) -> Dictionary:
	return BladeProxy.blade_vs_blade_swept(prev_a, cur_a, proxy_a,
		prev_b, cur_b, proxy_b, slack, span_a, span_b)


## 静止姿态下的刀身是否碰到某个球（用于「用刀挡箭」的即时接触判定）
static func blade_vs_sphere(xf: Transform3D, proxy: BladeProxy,
		center: Vector3, radius: float) -> Dictionary:
	return BladeProxy.proxy_vs_sphere(xf, proxy, center, radius)


## 多段胶囊版挥砍：机体被拆成若干判定件（躯干/头/四肢），逐件取最深接触。
## 这样打腿、打手、打肩甲都能算命中，而不是只有躯干中心那个大胶囊。
static func sweep_blade_parts(prev_xf: Transform3D, cur_xf: Transform3D,
		proxy: BladeProxy, parts: Array) -> Dictionary:
	return BladeProxy.sweep_capsule_parts(prev_xf, cur_xf, proxy, parts)
'''

GALLERIA_BLADE_ENTRY = '''## Rewind the confirmed blade contact to its most recent outside-to-inside crossing.
## The combat sweep still decides damage. This selects the reaction and shot timing.
static func blade_entry(samples: Array, hit: Dictionary, proxy: BladeProxy) -> Dictionary:
	var a: Vector3 = hit["capsule_a"]
	var b: Vector3 = hit["capsule_b"]
	var blade_local: Vector3 = hit["blade_local"]
	for frame in range(samples.size() - 2, -1, -1):
		var from: Vector3 = samples[frame]["pose"] * blade_local
		var to: Vector3 = samples[frame + 1]["pose"] * blade_local
		if dist_point_segment(from, a, b) <= 0.0 or from.distance_squared_to(to) < EPS:
			continue
		var outside := 0.0
		var inside := 1.0
		if BladeProxy.gap_to_capsule(samples[frame + 1]["pose"], proxy, a, b,
				float(hit["capsule_r"]))["gap"] > 0.0:
			continue
		for refinement in 10:
			var middle := (outside + inside) * 0.5
			var xf: Transform3D = samples[frame]["pose"].interpolate_with(
				samples[frame + 1]["pose"], middle)
			if float(BladeProxy.gap_to_capsule(xf, proxy, a, b,
					float(hit["capsule_r"]))["gap"]) > 0.0:
				outside = middle
			else:
				inside = middle
		var xf2: Transform3D = samples[frame]["pose"].interpolate_with(
			samples[frame + 1]["pose"], inside)
		var blade := xf2 * blade_local
		var axis := Geometry3D.get_closest_point_to_segment(blade, a, b)
		var outward := axis.direction_to(blade)
		var cut := from.direction_to(to)
		if cut.dot(outward) >= -0.02:
			continue
		return {"contact": axis + outward * float(hit["capsule_r"]), "normal": outward,
			"force": cut.lerp(-outward, 0.58).normalized(), "travel": to - from,
			"contact_time": lerpf(samples[frame]["time"], samples[frame + 1]["time"], inside)}
	return {}
'''


def replace_between(text, start_re, end_re, new_block, keep_end=True):
    m = re.search(start_re, text)
    if not m:
        raise ValueError("start marker missing")
    n = re.search(end_re, text[m.end():])
    if not n:
        raise ValueError("end marker missing")
    end_start = m.end() + (n.start() if keep_end else n.end())
    return text[:m.start()] + new_block + text[end_start:]


def patch_hitgd(path: Path, galleria: bool):
    text = path.read_text()
    if "proxy: BladeProxy" in text:
        print(f"skip {path} (already patched)")
        return
    # Header doc comment: discs → convex proxy
    text = text.replace(
        "## 「剑」不是一个粗胶囊：rig 会把它建模出来的每个剑网格的顶点读出来，滚筒式地\n"
        "## 切成 30 段圆盘剖面 [{y, r}]（见 mech_rig.build_blade_discs）。这里把这些圆盘\n"
        "## 在「上一帧变换 → 当前帧变换」之间连成扫掠线段，与目标的胶囊做线段-线段最近\n"
        "## 距离检测。所以挥砍/格挡/用刀挡箭都是真几何，不是射线或球形近似。",
        "## 「剑」不是一个粗胶囊：rig 把建模网格顶点拟合成「少顶点凸体」代理\n"
        "## （BladeProxy，见 res://core/blade_proxy.gd）。这里把这些凸体在\n"
        "## 「上一帧变换 → 当前帧变换」之间扫掠，与目标的胶囊做 GJK 最短距离检测。\n"
        "## 所以挥砍/格挡/用刀挡箭都是真几何，不是射线或球形近似。")
    # Cut the OLD sweep_blade_parts first (anchored on its discs: Array signature,
    # so it can't match the new proxy one inserted below).
    m = re.search(r"## 多段胶囊版挥砍：机体被拆成若干判定件（躯干/头/四肢），逐件取最深接触。\n"
                  r"(?:## .*\n)*static func sweep_blade_parts\(prev_xf: Transform3D, cur_xf: Transform3D, discs: Array.*?"
                  r"(?=## 球体扫掠 vs 一组判定件)", text, re.DOTALL)
    if not m:
        raise ValueError(f"sweep_blade_parts not found in {path}")
    text = text[:m.start()] + text[m.end():]
    # Replace the disc functions block: from sweep_blade comment through blade_vs_sphere end.
    start = re.compile(r"## 一次挥砍：把刀的圆盘剖面沿 prev_xf→cur_xf 扫掠")
    end = re.compile(r"## 球体扫掠 vs 胶囊（箭矢/刀气/冲撞用），返回进入时间")
    text = replace_between(text, start, end, NEW_BLADE_FUNCS + "\n\n")
    if galleria:
        # The old blade_entry was cut together with old sweep_blade_parts;
        # re-add the proxy version before sweep_sphere_parts.
        marker = "## 球体扫掠 vs 一组判定件（弹回的飞行物打怪）"
        if marker not in text:
            raise ValueError("galleria sweep_sphere_parts marker missing")
        text = text.replace(marker, GALLERIA_BLADE_ENTRY + "\n\n" + marker, 1)
    text = text.rstrip() + "\n"
    path.write_text(text)
    print(f"patched {path.relative_to(ROOT)}")


def patch_combat(text, module):
    """rig.blade_discs → rig.blade_proxy call-site rewrites (regex, whitespace-tolerant)."""
    subs = [
        (r"Hit\.sweep_blade_parts\(rig\.weapon_prev_xf, rig\.weapon_xf, rig\.blade_discs,\s*\n?\s*rig\.weapon_scale,\s*",
         "Hit.sweep_blade_parts(rig.weapon_prev_xf, rig.weapon_xf, rig.blade_proxy,\n\t\t\t"),
        (r"Hit\.blade_vs_blade_swept\(\s*\n?\s*player\.rig\.weapon_prev_xf, player\.rig\.weapon_xf, player\.rig\.blade_discs,\s*\n?\s*player\.rig\.weapon_scale, player\.rig\.blade_span\(\),\s*\n?\s*rig\.weapon_prev_xf, rig\.weapon_xf, rig\.blade_discs, rig\.weapon_scale, rig\.blade_span\(\)\s*\)",
         "Hit.blade_vs_blade_swept(\n\t\t\tplayer.rig.weapon_prev_xf, player.rig.weapon_xf, player.rig.blade_proxy,\n\t\t\trig.weapon_prev_xf, rig.weapon_xf, rig.blade_proxy, 0.03,\n\t\t\tplayer.rig.blade_span(), rig.blade_span())"),
        (r"Hit\.segment_vs_blade\(prev, pos, rig\.weapon_xf, rig\.blade_discs,\s*\n?\s*rig\.weapon_scale, radius\)",
         "Hit.segment_vs_blade(prev, pos, rig.weapon_xf, rig.blade_proxy, radius)"),
        (r"Hit\.blade_vs_sphere\(rig\.weapon_xf, rig\.blade_discs, rig\.weapon_scale, p, radius\)",
         "Hit.blade_vs_sphere(rig.weapon_xf, rig.blade_proxy, p, radius)"),
    ]
    for pattern, repl in subs:
        text, n = re.subn(pattern, repl, text)
    if "blade_discs" in text:
        raise ValueError(f"combat {module}: blade_discs remains:\n"
                         + "\n".join(l for l in text.splitlines() if "blade_discs" in l))
    if module == "galleria":
        text = text.replace(
            "entry = Hit.blade_entry(replay.blade_samples(rig, dt), res)",
            "entry = Hit.blade_entry(replay.blade_samples(rig, dt), res, rig.blade_proxy)")
    return text


NEAREST_ON_BLADE_NEW = '''## 机体胶囊（线段 a-b，半径 r）离敌人刀身最近的那一对点（凸体代理版）
static func nearest_on_blade(xf: Transform3D, rig, a: Vector3, b: Vector3, cap_r: float) -> Dictionary:
	var best := {"gap": 1e9, "blade_pt": xf.origin, "body_pt": a, "y": 1.2}
	var proxy: BladeProxy = rig.blade_proxy
	if proxy == null or proxy.pieces.is_empty():
		return best
	# 跳过刀柄/配重区（y<0.2 的 piece 不参与接近度估计）
	var res: Dictionary = BladeProxy.gap_to_capsule(xf, proxy, a, b, cap_r,
		Vector2(0.2, INF))
	var q: Vector3 = res["body_pt"]
	var dir: Vector3 = (res["blade_pt"] as Vector3) - q
	var surf := q
	if dir.length_squared() > 0.0001:
		surf = q + dir.normalized() * cap_r
	var local: Vector3 = res["blade_local"]
	return {"gap": float(res["gap"]), "blade_pt": res["blade_pt"],
		"body_pt": surf, "y": local.y}
'''


def patch_intercept(path: Path):
    text = path.read_text()
    if "blade_proxy" in text:
        print(f"skip {path} (already patched)")
        return
    # 1) melee_threat 的空判定
    text, n1 = re.subn(r"if rig\.blade_discs\.is_empty\(\):\s*\n",
                       "if rig.blade_proxy == null or rig.blade_proxy.pieces.is_empty():\n", text)
    assert n1 == 1, f"{path}: melee_threat disc check ({n1})"
    # 2) nearest_on_blade 整个替换（按函数边界切）
    m = re.search(r"## 机体胶囊（线段 a-b，半径 r）离敌人刀身最近的那一对点\n"
                  r"static func nearest_on_blade.*?(?=## 收尾)", text, re.DOTALL)
    assert m, f"{path}: nearest_on_blade missing"
    text = text[:m.start()] + NEAREST_ON_BLADE_NEW + "\n\n" + text[m.end():]
    assert "blade_discs" not in text, path
    path.write_text(text)
    print(f"patched {path.relative_to(ROOT)}")


PLAYER_FIND_NEW = '''func _find_reachable_intercept(erig, best: Dictionary, torso_turn: float, t_start := -1.0) -> Dictionary:
	if erig == null or not erig.has_method("predict_weapon_xf"):
		return {}
	var hit_to: float = float(erig.get("attack_hit_to"))
	# 落点优先落在「判定窗内」：窗外的交叠不算格挡，刀架到窗外经过的
	# 位置，等窗口打开敌刀早已掠过去 → 看起来举刀了却没挡住。
	var hit_from: float = float(erig.get("attack_hit_from"))
	var t_elapsed: float = float(erig.get("attack_elapsed"))
	var t_now := t_start
	if t_now < 0.0:
		var strict := _find_reachable_intercept(erig, best, torso_turn,
			maxf(t_elapsed, hit_from))
		if not strict.is_empty() or hit_from <= t_elapsed + 0.001:
			return strict
		# 窗内没有可达解（连段窗口极短）时才放宽到「从此刻起」。
		t_now = t_elapsed
	var eproxy: BladeProxy = erig.get("blade_proxy")
	if hit_to <= t_now or eproxy == null or eproxy.pieces.is_empty():
		return {}
	var out_dir: Vector3 = best["normal"]
	var cap: Dictionary = capsule()
	# 敌刀参与判定的轴区间：有 blade_span() 就用（duelist 的开刀扫掠段），
	# 否则取凸体代理自身的包围区间（arc sentinel）。
	var espan: Vector2 = erig.blade_span() if erig.has_method("blade_span") else eproxy.span
	# 敌刀全程刀位姿缓存 + 胶囊接触时刻（第一次有刀体碰到胶囊）。
	const STEPS := 8
	var e_times: Array = []
	var e_xfs: Array = []
	var e_segs: Array = []
	var e_contact := hit_to
	for i in STEPS + 1:
		var e: float = lerpf(t_now, hit_to, float(i) / float(STEPS))
		var xf: Transform3D = erig.predict_weapon_xf(e)
		e_times.append(e)
		e_xfs.append(xf)
		e_segs.append([xf * Vector3(0.0, espan.x, 0.0), xf * Vector3(0.0, espan.y, 0.0)])
		if i > 0 and e_contact >= hit_to:
			if float(BladeProxy.gap_to_capsule(xf, eproxy, cap["a"], cap["b"],
					float(cap["r"]))["gap"]) <= 0.0:
				e_contact = e
	if e_contact <= t_now + 0.02:
		return {}
	# 不回归的判据：原方案若静止姿态就能切进敌刀路径（gap≈0），一律不动。
	# 只有原方案静态不相交、而新候选静态真相交（gap≈0）时才替换。
	var orig_gap := _predicted_gap(rig, best["point"], best["axis"], out_dir,
		torso_turn, e_xfs, e_segs, eproxy, espan)
	# 与剑挡剑同口径：凸体表面间隙 ≤ slack 就算「切进去了」。
	const CLASH_GAP := 0.30
	if orig_gap <= CLASH_GAP:
		return {}
	var best_gap := CLASH_GAP
	# 由上到下（时间升序）找第一个可行解就返回：越早拦越安全，也省算力。
	# 落点离胸口超过 ~2.7u（刀柄可达 + 整条刀长）时直接跳过，不做完整求解。
	var chest: Vector3 = rig.global_position + Vector3(0, 2.2, 0)
	# ── 优先：落点不动，只改刀轴 ──
	# 手要留在「敌刀真正威胁身体的位置」，只把刀转成横切来路。这样既挡得住，
	# 又不会出现「横斩把手举到头顶 / 上劈把刀垂到腰」这种明显错误的位置。
	var pick := {}
	var pick_miss := 1e9
	var base_pt: Vector3 = best["point"]
	var base_reach: float = rig.blade_reach_miss(base_pt, best["axis"], out_dir, torso_turn)
	var max_shift: float = 1.80 if base_reach > 0.30 else 0.90
	var base_axes: Array = [best["axis"], Vector3.UP, Vector3.FORWARD, Vector3.RIGHT]
	if erig.has_method("predict_weapon_xf"):
		base_axes.append((e_xfs[0].basis * Vector3(0, 1, 0)).normalized())
	for ax0 in base_axes:
		if ax0.length_squared() < 0.01:
			continue
		if _predicted_gap(rig, base_pt, ax0, out_dir, torso_turn, e_xfs, e_segs,
				eproxy, espan) > CLASH_GAP:
			continue
		var m0: float = rig.blade_reach_miss(base_pt, ax0, out_dir, torso_turn)
		if m0 <= 0.32 and m0 < pick_miss:
			pick_miss = m0
			pick = {"point": base_pt, "axis": ax0, "eta": maxf(float(best.get("eta", 0.05)), 0.04)}
	if not pick.is_empty():
		return pick
	pick_miss = 1e9
	const CANDIDATE_RANGE := 2.9
	# 贴脸点不许要：落在身体周围 1.45u 以内的话，刀放过去也来不及、
	# 而且会被身体自身挡住，表现就是「举起来了但没挡住」。
	const MIN_CANDIDATE_GAP := 1.45
	var cand_pts: Array = eproxy.sample_points(0.05)
	for i in e_times.size():
		var e: float = e_times[i]
		if e >= e_contact:
			continue
		var xf: Transform3D = e_xfs[i]
		# 凸体顶点抽稀采样：逐帧全枚举会卡顿；抽稀后仍能覆盖整条刀身。
		for pi in range(0, cand_pts.size(), 4):
			var pt: Vector3 = xf * (cand_pts[pi] as Vector3)
			var chest_gap := pt.distance_to(chest)
			if chest_gap > CANDIDATE_RANGE or chest_gap < MIN_CANDIDATE_GAP:
				continue
			# 必须在我和敌人之间：跑到敌人身后（或超出敌我距离）的点
			# 看起来就是「手放到错误位置」，而且根本拦不到朝我来的刀。
			var mine_flat: Vector3 = (pt - rig.global_position).slide(Vector3.UP)
			var to_enemy_flat: Vector3 = (erig.global_position - rig.global_position).slide(Vector3.UP)
			if mine_flat.length() > to_enemy_flat.length() - 0.20:
				continue
			# 局部范围约束：原落点本来就够得到时只许微调（手不许乱跑）；
			# 原落点够不到时才放开半径去找真正可达的交点。
			if pt.distance_to(best["point"]) > max_shift:
				continue
			# 刀尖前指 / 横切来路摆前面：这是拦预接触路径最有效的两个姿态
			var daxes: Array = []
			var jab: Vector3 = pt - chest
			if jab.length_squared() > 0.01:
				daxes.append(jab.normalized())
				var step_t: float = minf(e + 0.016, hit_to)
				var xf2: Transform3D = erig.predict_weapon_xf(step_t)
				var motion: Vector3 = xf2 * Vector3(0, 1.2, 0) - xf * Vector3(0, 1.2, 0)
				if motion.length_squared() > 0.0001:
					var chop: Vector3 = motion.normalized().cross(jab.normalized())
					if chop.length_squared() > 0.01:
						daxes.append(chop.normalized())
			daxes.append(best["axis"])
			daxes.append((xf.basis * Vector3(0, 1, 0)).normalized())
			daxes.append(Vector3.UP)
			daxes.append(Vector3.FORWARD)
			daxes.append(Vector3.RIGHT)
			for ax in daxes:
				if ax.length_squared() < 0.01:
					continue
				var gap := _predicted_gap(rig, pt, ax, out_dir, torso_turn,
					e_xfs, e_segs, eproxy, espan)
				if gap < best_gap:
					# 兜底路径：沿敌刀路径取最早可达的交点（改刀轴失败的极端情况）
					return {"point": pt, "axis": ax, "eta": clampf(e - t_now, 0.04, 0.20)}
	return {}
'''


PLAYER_PREDICTED_GAP_NEW = '''## 预测「刀架在该落点后，敌刀全程扫过来」的最小真实间隙。
## 先按刀轴线段距离粗筛（凸体半径上界），过关的候选再用凸体最短距离
## 精确度量——「架在那里都碰不到」才算挡不住，避免线模型把格挡判死。
func _predicted_gap(rig, point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float, e_xfs: Array, e_segs: Array,
		eproxy: BladeProxy, espan: Vector2) -> float:
	var seg: Array = rig.intercept_blade_segment(point, axis, face, torso_turn)
	if seg.is_empty():
		return 1e9
	# 粗筛：刀轴线段最小距离超过包络上界就肯定交不上
	const PRUNE := 0.55
	var min_axis := 1e9
	for k in e_segs.size():
		min_axis = minf(min_axis, _seg_seg_dist(seg[0], seg[1], e_segs[k][0], e_segs[k][1]))
	if min_axis > PRUNE:
		return min_axis
	var res: Dictionary = rig.intercept_blade_xf(point, axis, face, torso_turn)
	if res.is_empty():
		return 1e9
	var wx: Transform3D = res["xf"]
	var own: BladeProxy = rig.blade_proxy
	if own == null or own.pieces.is_empty():
		return min_axis
	var ospan: Vector2 = rig.blade_span()
	var gap := 1e9
	for xf in e_xfs:
		var g := BladeProxy.closest_gap(wx, own, xf, eproxy, ospan, espan)
		gap = minf(gap, float(g["gap"]))
		if gap <= 0.0:
			break
	return gap
'''


def patch_player(path: Path):
    text = path.read_text()
    if "eproxy" in text:
        print(f"skip {path} (already patched)")
        return
    # 整段替换 _find_reachable_intercept（函数体在 6 个模块完全相同）
    m = re.search(r"func _find_reachable_intercept.*?(?=## 预测「刀架在该落点后)",
                  text, re.DOTALL)
    assert m, f"{path}: _find_reachable_intercept missing"
    text = text[:m.start()] + PLAYER_FIND_NEW + "\n\n" + text[m.end():]
    m = re.search(r"## 预测「刀架在该落点后，敌刀全程扫过来」的最小刀段间隙。\n"
                  r"(?:## .*\n)*func _predicted_gap.*?(?=## 刀身 discs 的 y 范围)",
                  text, re.DOTALL)
    assert m, f"{path}: _predicted_gap missing"
    text = text[:m.start()] + PLAYER_PREDICTED_GAP_NEW + "\n\n" + text[m.end():]
    # _piece_span 只为 discs 服务，删掉
    m = re.search(r"## 刀身 discs 的 y 范围 → 刀段端点参数\n"
                  r"static func _piece_span.*?(?=static func _pt_seg_dist)", text, re.DOTALL)
    assert m, f"{path}: _piece_span missing"
    text = text[:m.start()] + text[m.end():]
    assert "blade_discs" not in text, f"{path} still has blade_discs"
    path.write_text(text)
    print(f"patched {path.relative_to(ROOT)}")


def main():
    for root in LEVELS:
        patch_hitgd(root / "src/core/hitgd.gd", root.name == "galleria")
        combat = root / "src/game/combat.gd"
        combat.write_text(patch_combat(combat.read_text(), root.name))
        patch_intercept(root / "src/game/intercept.gd")
        patch_player(root / "src/game/player.gd")
    for root in ENEMIES:
        patch_hitgd(root / "src/core/hitgd.gd", False)
        combat = root / "src/game/combat.gd"
        combat.write_text(patch_combat(combat.read_text(), root.name))
        patch_intercept(root / "src/game/intercept.gd")


if __name__ == "__main__":
    main()

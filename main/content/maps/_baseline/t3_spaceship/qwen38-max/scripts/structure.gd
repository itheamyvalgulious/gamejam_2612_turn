class_name Structure
extends RefCounted
## Builds ship structure from Layout: floor/ceiling slabs, walls with
## auto-paired door/window openings, door assemblies, stairs, railings,
## plus custom builds (engine bay, ramp, bridge, EVA tube).

const WT := Layout.WALL_T
var g: Geom
var lay: Layout
var C := Color.WHITE

const WALL_MAT := {
	"engine": "panel_grimy", "control": "panel_clean", "airlock": "panel_grimy",
	"junction": "panel_std", "ramp": "panel_grimy", "shaft": "panel_std",
	"corridor": "panel_std", "cargo": "panel_grimy", "utility": "panel_grimy",
	"life": "panel_std", "mess": "panel_clean", "medical": "panel_clean",
	"hydro": "panel_std", "lab": "panel_clean", "quarters": "panel_std",
	"gym": "panel_std", "hangar": "panel_grimy", "catwalk": "panel_grimy",
	"server": "panel_clean", "lounge": "panel_clean", "bridge": "panel_clean",
	"office": "panel_std", "storage": "panel_grimy", "eva": "panel_std",
	"pods": "panel_std", "tanks": "panel_dark",
}
const FLOOR_MAT := {
	"engine": "floor_grimy", "control": "floor_std", "airlock": "floor_hazard",
	"junction": "floor_std", "ramp": "floor_grimy", "shaft": "floor_std",
	"corridor": "floor_std", "cargo": "floor_grimy", "utility": "floor_grimy",
	"life": "floor_std", "mess": "floor_std", "medical": "floor_gloss",
	"hydro": "floor_std", "lab": "floor_gloss", "quarters": "floor_std",
	"gym": "floor_std", "hangar": "floor_std", "catwalk": "grate_std",
	"server": "floor_gloss", "lounge": "floor_gloss", "bridge": "floor_gloss",
	"office": "floor_std", "storage": "floor_grimy", "eva": "floor_hazard",
	"pods": "floor_std", "tanks": "floor_grimy",
}
const CEIL_MAT := {
	"engine": "panel_dark", "control": "panel_std", "airlock": "panel_dark",
	"junction": "panel_std", "ramp": "panel_dark", "shaft": "panel_dark",
	"corridor": "panel_std", "cargo": "panel_dark", "utility": "panel_dark",
	"life": "panel_std", "mess": "panel_clean", "medical": "panel_clean",
	"hydro": "panel_std", "lab": "panel_std", "quarters": "panel_std",
	"gym": "panel_std", "hangar": "panel_dark", "catwalk": "panel_dark",
	"server": "panel_std", "lounge": "panel_clean", "bridge": "panel_clean",
	"office": "panel_std", "storage": "panel_dark", "eva": "panel_std",
	"pods": "panel_std", "tanks": "panel_dark",
}

func _init(geom: Geom, layout: Layout) -> void:
	g = geom
	lay = layout

func tint_for(r: Dictionary) -> Color:
	var t := Color(0.95, 0.96, 1.0)
	match String(r["style"]):
		"engine", "cargo", "utility", "hangar": t = Color(1.0, 0.96, 0.9)
		"medical", "server", "lab", "lounge", "bridge": t = Color(0.93, 0.97, 1.0)
		"quarters", "mess", "gym": t = Color(1.0, 0.97, 0.92)
		"hydro": t = Color(0.96, 1.0, 0.94)
	t.a = clampf(float(r["seed"]), 0.02, 0.98)
	return t

func accent_key(style: String) -> String:
	match style:
		"engine", "ramp", "airlock", "eva", "pods": return "amber"
		"medical", "server", "bridge", "lab", "control": return "cyan"
		"life", "hydro": return "green"
		"quarters", "mess", "gym", "lounge": return "warm"
		"hangar", "cargo": return "hazardmark"
	return "cyan"

func build_all() -> void:
	for r in lay.rooms:
		match String(r["custom"]):
			"ramp":
				continue  # built separately via build_ramp()
			"bridge":
				_build_bridge(r)
			"bridge2":
				pass
			"ready":
				pass
			"tube":
				_build_tube(r)
			_:
				if r["no_walls"] and r["name"] == "ENGINE BAY":
					_build_engine_bay(r)
				else:
					_build_room(r)
	# stairs
	for deck in [0, 1]:
		_stairs_shaft_a(deck)
		_stairs_shaft_b(deck)
	# ramp void railing on deck 1 (south edge of the hole, z=-10)
	g.railing("metal_dark", [Vector3(74.5, 7.5, -10.25), Vector3(113.8, 7.5, -10.25)], 1.0, C)
	# hangar catwalk railings (gap at x 188..196 for cross catwalk)
	g.railing("metal_dark", [Vector3(124.2, 15.0, -7.85), Vector3(187.9, 15.0, -7.85)], 1.05, C)
	g.railing("metal_dark", [Vector3(188.15, 15.0, -8.5), Vector3(188.15, 15.0, -39.5)], 1.05, C)
	g.railing("metal_dark", [Vector3(195.85, 15.0, -8.5), Vector3(195.85, 15.0, -39.5)], 1.05, C)

# --------------------------------------------------------------- generic room

func _build_room(r: Dictionary) -> void:
	var tint := tint_for(r)
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var z0: float = r["z0"]; var z1: float = r["z1"]
	var y0: float = r["y0"]; var y1: float = r["y1"]
	var fmat: String = FLOOR_MAT.get(r["style"], "floor_std")
	var wmat: String = WALL_MAT.get(r["style"], "panel_std")
	var cmat: String = CEIL_MAT.get(r["style"], "panel_std")

	if not r["no_floor"]:
		var frects := _rect_minus_holes(x0, x1, z0, z1, r["floor_holes"])
		for rc in frects:
			g.box(fmat, Vector3((rc[0] + rc[1]) * 0.5, y0 - 0.15, (rc[2] + rc[3]) * 0.5),
				Vector3(rc[1] - rc[0], 0.3, rc[3] - rc[2]), tint)
		for h in r["floor_holes"]:
			var hr: Rect2 = h
			var hx0: float = hr.position.x; var hz0: float = hr.position.y
			var hx1: float = hx0 + hr.size.x; var hz1: float = hz0 + hr.size.y
			var pts := [
				Vector3(hx0 + 0.12, y0, hz0 + 0.12), Vector3(hx1 - 0.12, y0, hz0 + 0.12),
				Vector3(hx1 - 0.12, y0, hz1 - 0.12), Vector3(hx0 + 0.12, y0, hz1 - 0.12),
			]
			for i in 4:
				g.railing("metal_dark", [pts[i], pts[(i + 1) % 4]], 1.0, C)
	if not r["no_ceil"]:
		var crects := _rect_minus_holes(x0, x1, z0, z1, r["ceil_holes"])
		for rc in crects:
			g.box(cmat, Vector3((rc[0] + rc[1]) * 0.5, y1 + 0.15, (rc[2] + rc[3]) * 0.5),
				Vector3(rc[1] - rc[0], 0.3, rc[3] - rc[2]), tint)
	if not r["no_walls"]:
		for side in ["N", "S", "E", "W"]:
			if side in r["open_sides"]:
				continue
			_build_wall(r, side, tint, wmat)

func _rect_minus_holes(x0: float, x1: float, z0: float, z1: float, holes: Array) -> Array:
	var rects: Array = [[x0, x1, z0, z1]]
	for h in holes:
		var hr: Rect2 = h
		var hx0 := hr.position.x; var hx1 := hr.position.x + hr.size.x
		var hz0 := hr.position.y; var hz1 := hr.position.y + hr.size.y
		var out: Array = []
		for rc in rects:
			if hx1 <= rc[0] or hx0 >= rc[1] or hz1 <= rc[2] or hz0 >= rc[3]:
				out.append(rc)
				continue
			if rc[0] < hx0: out.append([rc[0], hx0, rc[2], rc[3]])
			if hx1 < rc[1]: out.append([hx1, rc[1], rc[2], rc[3]])
			if rc[2] < hz0: out.append([maxf(rc[0], hx0), minf(rc[1], hx1), rc[2], hz0])
			if hz1 < rc[3]: out.append([maxf(rc[0], hx0), minf(rc[1], hx1), hz1, rc[3]])
		rects = out
	return rects

func _build_wall(r: Dictionary, side: String, tint: Color, wmat: String) -> void:
	var x0: float = r["x0"]; var x1: float = r["x1"]
	var z0: float = r["z0"]; var z1: float = r["z1"]
	var y0: float = r["y0"]; var y1: float = r["y1"]
	var ops := _collect_openings(r, side)
	var a_lo: float; var a_hi: float; var fixed: float
	if side == "N" or side == "S":
		a_lo = x0; a_hi = x1
		fixed = z0 if side == "N" else z1
	else:
		a_lo = z0; a_hi = z1
		fixed = x0 if side == "W" else x1
	var fpos := fixed + WT * 0.5 if (side == "N" or side == "W") else fixed - WT * 0.5
	var cursor := a_lo
	for op in ops:
		var oa0: float = maxf(op["a0"], a_lo)
		var oa1: float = minf(op["a1"], a_hi)
		if oa1 <= oa0:
			continue
		if oa0 > cursor + 0.01:
			_wall_box(side, cursor, oa0, y0, y1, fpos, tint, wmat)
		if op["y1"] < y1 - 0.01:
			_wall_box(side, oa0, oa1, op["y1"], y1, fpos, tint, wmat)
		if op["y0"] > y0 + 0.01:
			_wall_box(side, oa0, oa1, y0, op["y0"], fpos, tint, wmat)
		cursor = oa1
	if cursor < a_hi - 0.01:
		_wall_box(side, cursor, a_hi, y0, y1, fpos, tint, wmat)
	for op in ops:
		if op["kind"] == "window":
			_build_window(r, side, op, tint)
		else:
			_build_door(r, side, op, tint)

func _wall_box(side: String, a0: float, a1: float, yb: float, yt: float, fpos: float, tint: Color, wmat: String) -> void:
	if a1 - a0 < 0.01 or yt - yb < 0.01:
		return
	if side == "N" or side == "S":
		g.box(wmat, Vector3((a0 + a1) * 0.5, (yb + yt) * 0.5, fpos), Vector3(a1 - a0, yt - yb, WT), tint)
	else:
		g.box(wmat, Vector3(fpos, (yb + yt) * 0.5, (a0 + a1) * 0.5), Vector3(WT, yt - yb, a1 - a0), tint)

func _collect_openings(r: Dictionary, side: String) -> Array:
	var ops: Array = []
	var y0: float = r["y0"]
	for d in r["doors"]:
		if d["side"] == side:
			ops.append({"a0": d["pos"] - d["w"] * 0.5, "a1": d["pos"] + d["w"] * 0.5,
				"y0": y0, "y1": y0 + d["h"], "kind": d["kind"], "open": d["open"]})
	for wn in r["win"]:
		if wn["side"] == side:
			ops.append({"a0": wn["a0"], "a1": wn["a1"], "y0": wn["y0"], "y1": wn["y1"],
				"kind": "window", "open": false})
	for q in lay.rooms:
		if q == r or q["deck"] != r["deck"] or q["no_walls"] or q["custom"] == "ramp":
			continue
		var oside := ""
		match side:
			"N":
				if absf(q["z1"] - r["z0"]) < 0.05: oside = "S"
			"S":
				if absf(q["z0"] - r["z1"]) < 0.05: oside = "N"
			"W":
				if absf(q["x1"] - r["x0"]) < 0.05: oside = "E"
			"E":
				if absf(q["x0"] - r["x1"]) < 0.05: oside = "W"
		if oside == "":
			continue
		for d in q["doors"]:
			if d["side"] != oside:
				continue
			var lo: float; var hi: float
			if side == "N" or side == "S":
				lo = maxf(r["x0"], q["x0"]); hi = minf(r["x1"], q["x1"])
			else:
				lo = maxf(r["z0"], q["z0"]); hi = minf(r["z1"], q["z1"])
			if d["pos"] < lo or d["pos"] > hi:
				continue
			ops.append({"a0": d["pos"] - d["w"] * 0.5, "a1": d["pos"] + d["w"] * 0.5,
				"y0": q["y0"], "y1": q["y0"] + d["h"], "kind": d["kind"], "open": d["open"]})
	ops.sort_custom(func(a, b): return a["a0"] < b["a0"])
	var merged: Array = []
	for op in ops:
		if merged.size() > 0:
			var last: Dictionary = merged[merged.size() - 1]
			if op["a0"] < last["a1"] - 0.005:
				last["a1"] = maxf(last["a1"], op["a1"])
				last["y1"] = maxf(last["y1"], op["y1"])
				last["y0"] = minf(last["y0"], op["y0"])
				continue
		merged.append(op.duplicate())
	return merged

# --------------------------------------------------------------- doors

func _door_center(side: String, fpos_raw: float, mid: float, yy: float) -> Vector3:
	var s := 1.0 if (side == "N" or side == "W") else -1.0
	var fz := fpos_raw + WT * 0.5 * s
	if side == "N" or side == "S":
		return Vector3(mid, yy, fz)
	return Vector3(fz, yy, mid)

func _build_door(r: Dictionary, side: String, op: Dictionary, tint: Color) -> void:
	var a0: float = op["a0"]; var a1: float = op["a1"]
	var y0: float = op["y0"]; var y1: float = op["y1"]
	var w := a1 - a0
	var mid := (a0 + a1) * 0.5
	var horiz := (side == "N" or side == "S")
	var fraw: float
	if side == "N": fraw = r["z0"]
	elif side == "S": fraw = r["z1"]
	elif side == "W": fraw = r["x0"]
	else: fraw = r["x1"]
	var sgn := 1.0 if (side == "N" or side == "W") else -1.0
	var accent: String = "strip_" + accent_key(r["style"])
	var col_frame := Color(0.3, 0.31, 0.34, tint.a)
	var col_leaf := Color(0.5, 0.52, 0.56, tint.a)

	if op["kind"] == "airlock":
		var rr := minf(w, y1 - y0) * 0.5
		var center := _door_center(side, fraw, mid, y0 + rr + 0.1)
		var b := Basis(Vector3.UP, 0.0) if horiz else Basis(Vector3.UP, PI * 0.5)
		var axis := Vector3(0, 0, 1) if horiz else Vector3(1, 0, 0)
		g.torus("metal_dark", center, b, rr + 0.07, 0.1, col_frame, 24, 8)
		if op["open"]:
			# iris door slid sideways into wall pocket: only a sliver shows
			var slide := Vector3(0, 0, rr * 1.55) if horiz else Vector3(rr * 1.55, 0, 0)
			var c2 := center + slide
			g.cylinder("metal", c2 - axis * 0.05, c2 + axis * 0.05, rr - 0.03, Color(0.55, 0.5, 0.42, tint.a), 20)
			g.cylinder("metal_dark", c2 - axis * 0.09, c2 + axis * 0.09, rr * 0.26, col_frame, 12)
			# pocket frame lip at opening edge
			var lip := center + slide * 0.45
			g.box("metal_dark", lip + Vector3(0, 0, 0), Vector3(0.1, rr * 2.2, 0.12) if horiz else Vector3(0.12, rr * 2.2, 0.1), col_frame)
		else:
			g.cylinder("metal", center - axis * 0.05, center + axis * 0.05, rr - 0.03, Color(0.55, 0.5, 0.42, tint.a), 20)
			g.cylinder("metal_dark", center - axis * 0.1, center + axis * 0.1, rr * 0.26, col_frame, 12)
			var tang := axis.cross(Vector3.UP).normalized()
			if tang.length() < 0.1:
				tang = axis.cross(Vector3.RIGHT).normalized()
			for k in 3:
				var d4 := tang.rotated(axis, TAU * float(k) / 3.0)
				g.strut("metal_dark", center + axis * 0.12, center + axis * 0.12 + d4 * rr * 0.8, 0.055, 0.055, col_frame)
		# status lamp
		var lamp_off := Vector3(0, 0, 0)
		if horiz:
			lamp_off = Vector3(w * 0.5 + 0.45, 0, 0)
		else:
			lamp_off = Vector3(0, 0, w * 0.5 + 0.45)
		var lamp := _door_center(side, fraw, mid, y0 + (y1 - y0) + 0.5) + lamp_off * Vector3(1 if horiz else 0, 0, 0 if horiz else 1)
		var lkey: String = "strip_green" if op["open"] else "strip_red"
		g.box(lkey, lamp, Vector3(0.2, 0.1, 0.06) if horiz else Vector3(0.06, 0.1, 0.2), Color.WHITE)
		return

	if op["kind"] == "hangar":
		_build_hangar_door(r, side, op, tint)
		return

	# ---- sliding door (std / wide) ----
	var leaf_h := y1 - y0 - 0.08
	var ymid := (y0 + y1) * 0.5
	# frame: jambs + head (opening stays open)
	if horiz:
		g.box("metal_dark", Vector3(a0 - 0.14, ymid, fraw + WT * 0.5 * sgn), Vector3(0.28, y1 - y0 + 0.3, WT + 0.08), col_frame)
		g.box("metal_dark", Vector3(a1 + 0.14, ymid, fraw + WT * 0.5 * sgn), Vector3(0.28, y1 - y0 + 0.3, WT + 0.08), col_frame)
		g.box("metal_dark", Vector3(mid, y1 + 0.16, fraw + WT * 0.5 * sgn), Vector3(w + 0.56, 0.32, WT + 0.08), col_frame)
	else:
		g.box("metal_dark", Vector3(fraw + WT * 0.5 * sgn, ymid, a0 - 0.14), Vector3(WT + 0.08, y1 - y0 + 0.3, 0.28), col_frame)
		g.box("metal_dark", Vector3(fraw + WT * 0.5 * sgn, ymid, a1 + 0.14), Vector3(WT + 0.08, y1 - y0 + 0.3, 0.28), col_frame)
		g.box("metal_dark", Vector3(fraw + WT * 0.5 * sgn, y1 + 0.16, mid), Vector3(WT + 0.08, 0.32, w + 0.56), col_frame)
	# leaves (open => retracted fully into pockets, hidden inside wall)
	if not op["open"]:
		if horiz:
			g.box("metal", Vector3(mid - w * 0.25, y0 + leaf_h * 0.5 + 0.04, fraw + WT * 0.5 * sgn), Vector3(w * 0.5 - 0.02, leaf_h, 0.07), col_leaf)
			g.box("metal", Vector3(mid + w * 0.25, y0 + leaf_h * 0.5 + 0.04, fraw + WT * 0.5 * sgn), Vector3(w * 0.5 - 0.02, leaf_h, 0.07), col_leaf)
			g.box(accent, Vector3(mid - w * 0.25, y0 + leaf_h * 0.5, fraw + (WT * 0.5 + 0.045) * sgn), Vector3(w * 0.4, 0.05, 0.012), Color.WHITE)
			g.box(accent, Vector3(mid + w * 0.25, y0 + leaf_h * 0.5, fraw + (WT * 0.5 + 0.045) * sgn), Vector3(w * 0.4, 0.05, 0.012), Color.WHITE)
		else:
			g.box("metal", Vector3(fraw + WT * 0.5 * sgn, y0 + leaf_h * 0.5 + 0.04, mid - w * 0.25), Vector3(0.07, leaf_h, w * 0.5 - 0.02), col_leaf)
			g.box("metal", Vector3(fraw + WT * 0.5 * sgn, y0 + leaf_h * 0.5 + 0.04, mid + w * 0.25), Vector3(0.07, leaf_h, w * 0.5 - 0.02), col_leaf)
	else:
		# thin visible leaf edge parked in pocket
		if horiz:
			g.box("metal", Vector3(a0 - w * 0.27, y0 + leaf_h * 0.5 + 0.04, fraw + WT * 0.5 * sgn), Vector3(w * 0.46, leaf_h, 0.06), col_leaf)
			g.box("metal", Vector3(a1 + w * 0.27, y0 + leaf_h * 0.5 + 0.04, fraw + WT * 0.5 * sgn), Vector3(w * 0.46, leaf_h, 0.06), col_leaf)
		else:
			g.box("metal", Vector3(fraw + WT * 0.5 * sgn, y0 + leaf_h * 0.5 + 0.04, a0 - w * 0.27), Vector3(0.06, leaf_h, w * 0.46), col_leaf)
			g.box("metal", Vector3(fraw + WT * 0.5 * sgn, y0 + leaf_h * 0.5 + 0.04, a1 + w * 0.27), Vector3(0.06, leaf_h, w * 0.46), col_leaf)
	# threshold plate + emissive sill strip + transom light
	if horiz:
		g.box("metal_dark", Vector3(mid, y0 + 0.015, fraw + WT * 0.5 * sgn), Vector3(w + 0.3, 0.03, 0.7), Color(0.3, 0.31, 0.33, tint.a))
		g.quad_ds(accent,
			Vector3(a0 - 0.1, y0 + 0.035, fraw - 0.32), Vector3(a1 + 0.1, y0 + 0.035, fraw - 0.32),
			Vector3(a1 + 0.1, y0 + 0.035, fraw + 0.32), Vector3(a0 - 0.1, y0 + 0.035, fraw + 0.32), Color.WHITE)
		g.box(accent, Vector3(mid, y1 + 0.16, fraw + (WT * 0.5 + 0.055) * sgn), Vector3(w * 0.8, 0.1, 0.03), Color.WHITE)
	else:
		g.box("metal_dark", Vector3(fraw + WT * 0.5 * sgn, y0 + 0.015, mid), Vector3(0.7, 0.03, w + 0.3), Color(0.3, 0.31, 0.33, tint.a))
		g.quad_ds(accent,
			Vector3(fraw - 0.32, y0 + 0.035, a0 - 0.1), Vector3(fraw - 0.32, y0 + 0.035, a1 + 0.1),
			Vector3(fraw + 0.32, y0 + 0.035, a1 + 0.1), Vector3(fraw + 0.32, y0 + 0.035, a0 - 0.1), Color.WHITE)
		g.box(accent, Vector3(fraw + (WT * 0.5 + 0.055) * sgn, y1 + 0.16, mid), Vector3(0.03, 0.1, w * 0.8), Color.WHITE)

func _build_hangar_door(r: Dictionary, side: String, op: Dictionary, tint: Color) -> void:
	var a0: float = op["a0"]; var a1: float = op["a1"]
	var y0: float = op["y0"]; var y1: float = op["y1"]
	var mid := (a0 + a1) * 0.5
	var w := a1 - a0
	var fpos: float = r["z1"] if side == "S" else r["z0"]
	var sgn := -1.0 if side == "S" else 1.0
	var fz := fpos + WT * 0.5 * sgn
	# massive frame: jambs + head (opening open)
	g.box("frame", Vector3(a0 - 0.5, (y0 + y1) * 0.5, fz), Vector3(1.0, y1 - y0 + 1.0, WT + 0.4), Color(0.45, 0.45, 0.47, tint.a))
	g.box("frame", Vector3(a1 + 0.5, (y0 + y1) * 0.5, fz), Vector3(1.0, y1 - y0 + 1.0, WT + 0.4), Color(0.45, 0.45, 0.47, tint.a))
	g.box("frame", Vector3(mid, y1 + 0.55, fz), Vector3(w + 2.0, 1.1, WT + 0.4), Color(0.45, 0.45, 0.47, tint.a))
	# leaf pockets + partially visible leaf edges
	var pocket_len := w * 0.42
	g.box("metal_dark", Vector3(a0 - pocket_len * 0.5 - 0.6, y0 + (y1 - y0) * 0.5, fz), Vector3(pocket_len, y1 - y0, 0.55), Color(0.4, 0.41, 0.44, tint.a))
	g.box("metal_dark", Vector3(a1 + pocket_len * 0.5 + 0.6, y0 + (y1 - y0) * 0.5, fz), Vector3(pocket_len, y1 - y0, 0.55), Color(0.4, 0.41, 0.44, tint.a))
	g.box("metal", Vector3(a0 + 0.45, y0 + (y1 - y0) * 0.5, fz), Vector3(0.9, y1 - y0 - 0.15, 0.16), Color(0.55, 0.56, 0.6, tint.a))
	g.box("metal", Vector3(a1 - 0.45, y0 + (y1 - y0) * 0.5, fz), Vector3(0.9, y1 - y0 - 0.15, 0.16), Color(0.55, 0.56, 0.6, tint.a))
	# hazard strips across the doorway
	for i in 5:
		var zz := fpos + sgn * (0.6 + float(i) * 0.8)
		g.quad_ds("floor_hazard", Vector3(a0 + 0.3, y0 + 0.05, zz - 0.25), Vector3(a1 - 0.3, y0 + 0.05, zz - 0.25),
			Vector3(a1 - 0.3, y0 + 0.05, zz + 0.25), Vector3(a0 + 0.3, y0 + 0.05, zz + 0.25), Color.WHITE)
	# warning beacons above head
	g.cylinder("strip_red", Vector3(a0 - 0.4, y1 + 1.25, fz), Vector3(a0 - 0.4, y1 + 1.5, fz), 0.13, Color.WHITE, 8)
	g.cylinder("strip_red", Vector3(a1 + 0.4, y1 + 1.25, fz), Vector3(a1 + 0.4, y1 + 1.5, fz), 0.13, Color.WHITE, 8)

func _build_window(r: Dictionary, side: String, op: Dictionary, tint: Color) -> void:
	var a0: float = op["a0"]; var a1: float = op["a1"]
	var yb: float = op["y0"]; var yt: float = op["y1"]
	var horiz := (side == "N" or side == "S")
	var fraw: float
	if side == "N": fraw = r["z0"]
	elif side == "S": fraw = r["z1"]
	elif side == "W": fraw = r["x0"]
	else: fraw = r["x1"]
	var sgn := 1.0 if (side == "N" or side == "W") else -1.0
	var fz := fraw + WT * 0.5 * sgn
	var mid := (a0 + a1) * 0.5
	var frame_col := Color(0.36, 0.38, 0.42, tint.a)
	var gw := a1 - a0
	var gh := yt - yb
	if horiz:
		g.quad_ds("glass", Vector3(a0, yb, fz), Vector3(a1, yb, fz), Vector3(a1, yt, fz), Vector3(a0, yt, fz), Color(0.7, 0.85, 1.0, 0.35))
		g.box("metal_dark", Vector3(mid, yb - 0.09, fz), Vector3(gw + 0.3, 0.18, WT + 0.08), frame_col)
		g.box("metal_dark", Vector3(mid, yt + 0.09, fz), Vector3(gw + 0.3, 0.18, WT + 0.08), frame_col)
		var nmul := maxi(int(gw / 2.5), 1)
		for i in range(1, nmul):
			var mx: float = a0 + gw * float(i) / float(nmul)
			g.box("metal_dark", Vector3(mx, (yb + yt) * 0.5, fz), Vector3(0.1, gh, 0.12), frame_col)
		g.railing("metal_dark", [Vector3(a0 + 0.2, r["y0"], fz + 0.6 * sgn),
			Vector3(a1 - 0.2, r["y0"], fz + 0.6 * sgn)], 0.95, Color.WHITE)
	else:
		g.quad_ds("glass", Vector3(fz, yb, a0), Vector3(fz, yb, a1), Vector3(fz, yt, a1), Vector3(fz, yt, a0), Color(0.7, 0.85, 1.0, 0.35))
		g.box("metal_dark", Vector3(fz, yb - 0.09, mid), Vector3(WT + 0.08, 0.18, gw + 0.3), frame_col)
		g.box("metal_dark", Vector3(fz, yt + 0.09, mid), Vector3(WT + 0.08, 0.18, gw + 0.3), frame_col)
		var nmul := maxi(int(gw / 2.5), 1)
		for i in range(1, nmul):
			var mz: float = a0 + gw * float(i) / float(nmul)
			g.box("metal_dark", Vector3(fz, (yb + yt) * 0.5, mz), Vector3(0.12, gh, 0.1), frame_col)

# --------------------------------------------------------------- stairs

func _stairs_shaft_a(deck: int) -> void:
	var y0: float = Layout.DECK_Y[deck]
	var col := Color(0.5, 0.52, 0.55, 0.5)
	g.stairs("metal", Vector3(76.4, y0, 20.5), Vector3(0, 0, -1), 3.75, 8.5, 2.0, 20, col, "metal_dark", Color.WHITE)
	g.box("grate_std", Vector3(78.0, y0 + 3.75 - 0.12, 11.15), Vector3(7.0, 0.24, 1.7), Color.WHITE)
	g.box("frame", Vector3(78.0, y0 + 3.75 - 0.32, 11.15), Vector3(7.2, 0.16, 1.9), Color(0.4, 0.4, 0.42, 0.5))
	g.stairs("metal", Vector3(79.6, y0 + 3.75, 12.0), Vector3(0, 0, 1), 3.75, 8.5, 2.0, 20, col, "metal_dark", Color.WHITE)
	# landing railing (north edge)
	g.railing("metal_dark", [Vector3(74.7, y0 + 3.75, 10.4), Vector3(75.3, y0 + 3.75, 10.4)], 1.0, Color.WHITE)
	g.railing("metal_dark", [Vector3(77.5, y0 + 3.75, 10.4), Vector3(78.5, y0 + 3.75, 10.4)], 1.0, Color.WHITE)
	g.railing("metal_dark", [Vector3(80.7, y0 + 3.75, 10.4), Vector3(81.4, y0 + 3.75, 10.4)], 1.0, Color.WHITE)

func _stairs_shaft_b(deck: int) -> void:
	var y0: float = Layout.DECK_Y[deck]
	var col := Color(0.5, 0.52, 0.55, 0.5)
	g.stairs("metal", Vector3(228.5, y0, 6.0), Vector3(0, 0, -1), 3.75, 12.0, 2.2, 20, col, "metal_dark", Color.WHITE)
	g.box("grate_std", Vector3(232.2, y0 + 3.75 - 0.12, -7.0), Vector3(10.4, 0.24, 2.0), Color.WHITE)
	g.box("frame", Vector3(232.2, y0 + 3.75 - 0.32, -7.0), Vector3(10.6, 0.16, 2.2), Color(0.4, 0.4, 0.42, 0.5))
	g.stairs("metal", Vector3(235.5, y0 + 3.75, -6.0), Vector3(0, 0, 1), 3.75, 12.0, 2.2, 20, col, "metal_dark", Color.WHITE)
	# landing railing between flights
	g.railing("metal_dark", [Vector3(229.9, y0 + 3.75, -6.15), Vector3(234.1, y0 + 3.75, -6.15)], 1.0, Color.WHITE)

# --------------------------------------------------------------- engine bay

func _build_engine_bay(r: Dictionary) -> void:
	var tint := tint_for(r)
	var y0: float = r["y0"]; var y1: float = r["y1"]
	var wmat := "panel_grimy"
	# floor: plating border + grating center + hazard ring around reactor
	g.box("floor_grimy", Vector3(30.0, y0 - 0.15, 0.0), Vector3(52.0, 0.3, 80.0), tint)
	g.box("grate_engine", Vector3(30.0, y0 + 0.03, 0.0), Vector3(40.0, 0.06, 62.0), Color.WHITE)
	for i in 28:
		var a0 := TAU * float(i) / 28.0
		var a1 := TAU * float(i + 1) / 28.0
		var c := Vector3(30.0, y0 + 0.075, 0.0)
		var q0 := c + Vector3(cos(a0) * 8.0, 0, sin(a0) * 8.0)
		var q1 := c + Vector3(cos(a1) * 8.0, 0, sin(a1) * 8.0)
		var q2 := c + Vector3(cos(a1) * 9.3, 0, sin(a1) * 9.3)
		var q3 := c + Vector3(cos(a0) * 9.3, 0, sin(a0) * 9.3)
		g.quad("floor_hazard", q0, q1, q2, q3, Color.WHITE, Vector3.UP)
	# ceiling + heavy beams
	g.box("panel_dark", Vector3(30.0, y1 + 0.15, 0.0), Vector3(52.0, 0.3, 80.0), tint)
	for i in 12:
		var xx := 6.0 + float(i) * 4.2
		g.ibeam("frame_rust", Vector3(xx, y1 - 0.5, -39.0), Vector3(xx, y1 - 0.5, 39.0), 0.9, 0.35, Color(0.4, 0.4, 0.42, tint.a))
	# east wall x=56 with observation window + 2 doors
	var ex := 56.0
	var segs: Array = [
		[-40.0, -20.0, y0, y1], [-17.5, -10.0, y0, y1], [10.0, 17.5, y0, y1], [20.0, 40.0, y0, y1],
		[-20.0, -17.5, 3.0, y1], [17.5, 20.0, 3.0, y1],
		[-10.0, 10.0, y0, 1.0], [-10.0, 10.0, 4.2, y1],
	]
	for s in segs:
		g.box(wmat, Vector3(ex - WT * 0.5, (s[2] + s[3]) * 0.5, (s[0] + s[1]) * 0.5),
			Vector3(WT, s[3] - s[2], s[1] - s[0]), tint)
	_wp_window_x(ex, -10.0, 10.0, 1.0, 4.2, tint)
	# door jambs + heads (open doorways to control)
	for zs in [-18.75, 18.75]:
		g.box("metal_dark", Vector3(ex - WT * 0.5, 1.5, zs - 1.4), Vector3(WT + 0.1, 3.3, 0.3), Color(0.32, 0.33, 0.36, tint.a))
		g.box("metal_dark", Vector3(ex - WT * 0.5, 1.5, zs + 1.4), Vector3(WT + 0.1, 3.3, 0.3), Color(0.32, 0.33, 0.36, tint.a))
		g.box("metal_dark", Vector3(ex - WT * 0.5, 3.15, zs), Vector3(WT + 0.1, 0.3, 3.1), Color(0.32, 0.33, 0.36, tint.a))
		g.box("strip_amber", Vector3(ex - WT - 0.03, 3.42, zs), Vector3(0.03, 0.09, 2.6), Color.WHITE)
	# west wall x=4 with nacelle penetrations
	var wx := 4.0
	var cell := 2.0
	var zc := -40.0
	while zc < 40.0:
		var yc := y0
		while yc < y1:
			var cyy := yc + cell * 0.5
			var czz := zc + cell * 0.5
			var dist_n := minf(Vector2(cyy - 3.0, czz - 18.0).length(), Vector2(cyy - 3.0, czz + 18.0).length())
			if dist_n > 6.4:
				g.box(wmat, Vector3(wx + WT * 0.5, cyy, czz), Vector3(WT, cell, cell), tint)
			yc += cell
		zc += cell
	for zs in [-18.0, 18.0]:
		g.torus("frame_rust", Vector3(wx + 0.25, 3.0, zs), Basis(Vector3.UP, PI * 0.5), 6.05, 0.4, Color(0.45, 0.42, 0.38, tint.a), 28, 10)
	# north/south walls: plating lower band + open framework above
	for zs in [-40.0, 40.0]:
		var inner: float = zs + (WT * 0.5 if zs < 0 else -WT * 0.5)
		g.box(wmat, Vector3(30.0, y0 + 1.4, inner), Vector3(52.0, 2.8, WT), tint)
		var i := 0
		while i <= 13:
			var xx := 4.0 + float(i) * 4.0
			g.strut("frame_rust", Vector3(xx, y0 + 2.8, zs), Vector3(xx, y1, zs), 0.34, 0.34, Color(0.42, 0.42, 0.45, tint.a))
			i += 1
		for yy in [3.6, 4.7, 5.7]:
			g.strut("frame_rust", Vector3(4.0, yy, zs), Vector3(56.0, yy, zs), 0.2, 0.24, Color(0.42, 0.42, 0.45, tint.a))
		for k in 6:
			var xb := 6.0 + float(k) * 8.5
			g.strut("frame_rust", Vector3(xb, y0 + 2.9, zs), Vector3(xb + 4.0, y1 - 0.3, zs), 0.12, 0.12, Color(0.4, 0.4, 0.43, tint.a))

func _wp_window_x(ex: float, a0: float, a1: float, yb: float, yt: float, tint: Color) -> void:
	var mid := (a0 + a1) * 0.5
	g.quad_ds("glass", Vector3(ex, yb, a0), Vector3(ex, yb, a1), Vector3(ex, yt, a1), Vector3(ex, yt, a0), Color(0.75, 0.88, 1.0, 0.32))
	g.box("metal_dark", Vector3(ex, yb - 0.1, mid), Vector3(0.4, 0.2, a1 - a0 + 0.4), Color(0.34, 0.35, 0.38, tint.a))
	g.box("metal_dark", Vector3(ex, yt + 0.1, mid), Vector3(0.4, 0.2, a1 - a0 + 0.4), Color(0.34, 0.35, 0.38, tint.a))
	for i in range(1, 8):
		var mz: float = a0 + (a1 - a0) * float(i) / 8.0
		g.box("metal_dark", Vector3(ex, (yb + yt) * 0.5, mz), Vector3(0.14, yt - yb, 0.12), Color(0.34, 0.35, 0.38, tint.a))
	g.railing("metal_dark", [Vector3(ex + 0.75, 0.0, a0 + 0.3), Vector3(ex + 0.75, 0.0, a1 - 0.3)], 0.95, Color.WHITE)

# --------------------------------------------------------------- ramp

func build_ramp(r: Dictionary) -> void:
	var tint := tint_for(r)
	var x0 := 74.0; var xs := 78.0; var x1 := 114.0
	var rise := 7.5; var run := x1 - xs
	var ang := atan2(rise, run)
	var z0 := -16.0; var z1 := -10.0
	var hh := 4.6
	# apron floor
	g.box("floor_grimy", Vector3((x0 + xs) * 0.5, -0.15, (z0 + z1) * 0.5), Vector3(xs - x0, 0.3, z1 - z0), tint)
	# sloped floor slab
	var len := sqrt(run * run + rise * rise)
	var cx := xs + run * 0.5
	var b := Basis(Vector3(0, 0, 1), -ang)
	g.box_basis("floor_grimy", Transform3D(b, Vector3(cx, rise * 0.5 - 0.17, (z0 + z1) * 0.5)), Vector3(len, 0.3, z1 - z0), tint)
	# anti-slip hazard stripes
	var i := 0
	while i < 15:
		var xx := xs + 1.2 + float(i) * 2.4
		var yy := (xx - xs) * rise / run
		g.box_basis("floor_hazard", Transform3D(b, Vector3(xx, yy + 0.02, (z0 + z1) * 0.5)), Vector3(0.5, 0.04, z1 - z0 - 0.5), Color.WHITE)
		i += 1
	# sloped ceiling + apron ceiling
	g.box_basis("panel_dark", Transform3D(b, Vector3(cx, rise * 0.5 + hh, (z0 + z1) * 0.5)), Vector3(len, 0.3, z1 - z0), tint)
	g.box("panel_dark", Vector3((x0 + xs) * 0.5, hh - 0.15, (z0 + z1) * 0.5), Vector3(xs - x0, 0.3, z1 - z0), tint)
	# side walls
	_ramp_wall(z1 - WT * 0.5, xs, x0, x1, rise, hh, tint, "panel_grimy", 78.0, 84.0)
	_ramp_wall(z0 + WT * 0.5, xs, x0, x1, rise, hh, tint, "panel_grimy", 94.8, 97.2)
	# west end wall
	g.box("panel_grimy", Vector3(x0 + WT * 0.5, hh * 0.5 - 0.4, (z0 + z1) * 0.5), Vector3(WT, hh, z1 - z0), tint)
	# railings following slope
	g.railing("metal_dark", [Vector3(xs + 0.3, 0.05, z1 - 0.4), Vector3(x1 - 0.3, rise + 0.05, z1 - 0.4)], 1.0, Color.WHITE)
	g.railing("metal_dark", [Vector3(xs + 0.3, 0.05, z0 + 0.4), Vector3(x1 - 0.3, rise + 0.05, z0 + 0.4)], 1.0, Color.WHITE)
	# overhead light strips
	var k := 0
	while k < 8:
		var xx := xs + 2.0 + float(k) * 4.4
		var yy := (xx - xs) * rise / run
		g.box("strip_warm", Vector3(xx, yy + hh - 0.35, (z0 + z1) * 0.5), Vector3(2.6, 0.07, 0.24), Color.WHITE)
		k += 1
	# pipes along south wall
	g.pipe("metal_dark", [Vector3(xs, 1.2, z1 - 0.55), Vector3(x1, rise + 1.2, z1 - 0.55)], 0.09, Color(0.5, 0.5, 0.52, tint.a))
	g.pipe("metal_dark", [Vector3(xs, 1.55, z1 - 0.7), Vector3(x1, rise + 1.55, z1 - 0.7)], 0.07, Color(0.45, 0.46, 0.5, tint.a))

func _ramp_wall(fz: float, xs: float, x0: float, x1: float, rise: float, hh: float, tint: Color, mat: String, d0: float, d1: float) -> void:
	var pts: Array = []
	var n := 24
	for i in n + 1:
		var xx := lerpf(x0, x1, float(i) / float(n))
		var fy := 0.0 if xx <= xs else (xx - xs) * rise / (x1 - xs)
		pts.append([xx, fy])
	for i in n:
		var xa: float = pts[i][0]; var ya: float = pts[i][1]
		var xb2: float = pts[i + 1][0]; var yb2: float = pts[i + 1][1]
		if xb2 > d0 and xa < d1:
			var topy := maxf(ya, yb2) + 2.9
			if ya + hh > topy:
				g.box(mat, Vector3((xa + xb2) * 0.5, (topy + ya + hh) * 0.5, fz), Vector3(xb2 - xa + 0.02, ya + hh - topy, WT), tint)
			continue
		g.box(mat, Vector3((xa + xb2) * 0.5, ya + hh * 0.5, fz), Vector3(xb2 - xa + 0.02, hh, WT), tint)

# --------------------------------------------------------------- EVA tube

func _build_tube(r: Dictionary) -> void:
	var tint := tint_for(r)
	var y0 := 7.5; var y1 := 10.1
	g.box("floor_hazard", Vector3(64.0, y0 - 0.15, -36.0), Vector3(4.0, 0.3, 24.0), tint)
	g.box("panel_std", Vector3(64.0, y1 + 0.15, -36.0), Vector3(4.0, 0.3, 24.0), tint)
	g.box("panel_std", Vector3(62.0 + WT * 0.5, (y0 + y1) * 0.5, -36.0), Vector3(WT, y1 - y0, 24.0), tint)
	g.box("panel_std", Vector3(66.0 - WT * 0.5, (y0 + y1) * 0.5, -36.0), Vector3(WT, y1 - y0, 24.0), tint)
	var i := 0
	while i < 8:
		var zz := -46.5 + float(i) * 3.0
		g.strut("frame", Vector3(62.1, y0 + 0.1, zz), Vector3(62.1, y1 - 0.1, zz), 0.14, 0.14, Color.WHITE)
		g.strut("frame", Vector3(65.9, y0 + 0.1, zz), Vector3(65.9, y1 - 0.1, zz), 0.14, 0.14, Color.WHITE)
		g.strut("frame", Vector3(62.1, y1 - 0.12, zz), Vector3(65.9, y1 - 0.12, zz), 0.14, 0.14, Color.WHITE)
		g.box("strip_amber", Vector3(64.0, y1 - 0.05, zz + 1.2), Vector3(0.5, 0.04, 0.08), Color.WHITE)
		i += 1
	# outer hatch (z=-48): torus frame + sealed disc + wheel + lamp
	g.torus("metal_dark", Vector3(64.0, (y0 + y1) * 0.5 - 0.15, -47.75), Basis(Vector3.UP, PI * 0.5), 1.05, 0.1, Color(0.4, 0.41, 0.44, tint.a), 20, 8)
	g.cylinder("metal", Vector3(64.0, (y0 + y1) * 0.5 - 0.15, -47.88), Vector3(64.0, (y0 + y1) * 0.5 - 0.15, -47.62), 0.95, Color(0.52, 0.48, 0.4, tint.a), 18)
	g.cylinder("metal_dark", Vector3(64.0, (y0 + y1) * 0.5 - 0.15, -47.58), Vector3(64.0, (y0 + y1) * 0.5 - 0.15, -47.46), 0.22, Color(0.35, 0.36, 0.38, tint.a), 10)
	for k in 4:
		var ang := TAU * float(k) / 4.0 + 0.4
		g.strut("metal_dark", Vector3(64.0, (y0 + y1) * 0.5 - 0.15, -47.5),
			Vector3(64.0 + cos(ang) * 0.8, (y0 + y1) * 0.5 - 0.15 + sin(ang) * 0.8, -47.5), 0.06, 0.06, Color(0.35, 0.36, 0.38, tint.a))
	g.box("strip_red", Vector3(64.0, y1 - 0.3, -47.55), Vector3(0.3, 0.08, 0.05), Color.WHITE)
	# inner doorway at z=-24 (open): jambs + head + one parked leaf
	g.box("metal_dark", Vector3(62.9, y0 + 1.3, -24.05), Vector3(0.25, 2.8, WT + 0.1), Color(0.34, 0.35, 0.38, tint.a))
	g.box("metal_dark", Vector3(65.1, y0 + 1.3, -24.05), Vector3(0.25, 2.8, WT + 0.1), Color(0.34, 0.35, 0.38, tint.a))
	g.box("metal_dark", Vector3(64.0, y0 + 2.72, -24.05), Vector3(2.65, 0.3, WT + 0.1), Color(0.34, 0.35, 0.38, tint.a))
	g.box("strip_amber", Vector3(64.0, y0 + 2.92, -24.2), Vector3(2.2, 0.07, 0.03), Color.WHITE)
	g.box("metal", Vector3(62.4, y0 + 1.25, -24.15), Vector3(0.06, 2.5, 0.95), Color(0.5, 0.51, 0.54, tint.a))

# --------------------------------------------------------------- bridge

func _build_bridge(r: Dictionary) -> void:
	var tint := tint_for(r)
	var y0 := 15.0; var y1 := 21.0
	# floors / ceilings
	g.box("floor_gloss", Vector3(255.0, y0 - 0.15, 0.0), Vector3(14.0, 0.3, 44.0), tint)
	g.box("panel_clean", Vector3(255.0, y1 + 0.15, 0.0), Vector3(14.0, 0.3, 44.0), tint)
	g.box("floor_gloss", Vector3(265.0, y0 - 0.15, 0.0), Vector3(6.0, 0.3, 32.0), tint)
	g.box("panel_clean", Vector3(265.0, y1 + 0.15, 0.0), Vector3(6.0, 0.3, 32.0), tint)
	# west wall x=248: opening z[-2.5,2.5] h3.6
	var segs: Array = [
		[-22.0, -2.5, y0, y1], [2.5, 22.0, y0, y1], [-2.5, 2.5, y0 + 3.6, y1],
	]
	for s in segs:
		g.box("panel_clean", Vector3(248.0 + WT * 0.5, (s[2] + s[3]) * 0.5, (s[0] + s[1]) * 0.5), Vector3(WT, s[3] - s[2], s[1] - s[0]), tint)
	# west door frame + open leaves + threshold
	g.box("metal_dark", Vector3(248.0 + WT * 0.5, y0 + 1.8, -2.68), Vector3(WT + 0.12, 3.9, 0.36), Color(0.33, 0.34, 0.37, tint.a))
	g.box("metal_dark", Vector3(248.0 + WT * 0.5, y0 + 1.8, 2.68), Vector3(WT + 0.12, 3.9, 0.36), Color(0.33, 0.34, 0.37, tint.a))
	g.box("metal_dark", Vector3(248.0 + WT * 0.5, y0 + 3.78, 0.0), Vector3(WT + 0.12, 0.36, 5.7), Color(0.33, 0.34, 0.37, tint.a))
	g.box("strip_cyan", Vector3(248.0 + WT * 0.5 - 0.07, y0 + 3.78, 0.0), Vector3(0.03, 0.1, 5.0), Color.WHITE)
	g.quad_ds("strip_cyan", Vector3(247.7, y0 + 0.04, -2.6), Vector3(247.7, y0 + 0.04, 2.6), Vector3(248.5, y0 + 0.04, 2.6), Vector3(248.5, y0 + 0.04, -2.6), Color.WHITE)
	# ready room: x=256 wall z[10,22] + z=10 wall x[248,256] with door at x=252
	g.box("panel_clean", Vector3(256.0 - WT * 0.5, (y0 + y1) * 0.5, 16.0), Vector3(WT, y1 - y0, 12.0), tint)
	g.box("panel_clean", Vector3(249.5, (y0 + y1) * 0.5, 10.0 + WT * 0.5), Vector3(2.9, y1 - y0, WT), tint)
	g.box("panel_clean", Vector3(254.6, (y0 + y1) * 0.5, 10.0 + WT * 0.5), Vector3(2.7, y1 - y0, WT), tint)
	g.box("panel_clean", Vector3(252.0, y0 + 2.6 + (y1 - y0 - 2.6) * 0.5, 10.0 + WT * 0.5), Vector3(2.4, y1 - y0 - 2.6, WT), tint)
	g.box("metal_dark", Vector3(250.85, y0 + 1.3, 10.15), Vector3(0.22, 2.7, WT + 0.08), Color(0.33, 0.34, 0.37, tint.a))
	g.box("metal_dark", Vector3(253.15, y0 + 1.3, 10.15), Vector3(0.22, 2.7, WT + 0.08), Color(0.33, 0.34, 0.37, tint.a))
	g.box("metal_dark", Vector3(252.0, y0 + 2.72, 10.15), Vector3(2.52, 0.24, WT + 0.08), Color(0.33, 0.34, 0.37, tint.a))
	g.box("metal", Vector3(250.2, y0 + 1.25, 10.15), Vector3(0.06, 2.45, 1.0), Color(0.5, 0.51, 0.54, tint.a))
	g.box("strip_warm", Vector3(252.0, y0 + 2.9, 9.9), Vector3(2.0, 0.06, 0.03), Color.WHITE)
	# side walls z=+-22 (x 248..262) and z=+-16 (x 262..268), step walls at x=262
	g.box("panel_clean", Vector3(255.0, (y0 + y1) * 0.5, -22.0 + WT * 0.5), Vector3(14.0, y1 - y0, WT), tint)
	g.box("panel_clean", Vector3(255.0, (y0 + y1) * 0.5, 22.0 - WT * 0.5), Vector3(14.0, y1 - y0, WT), tint)
	g.box("panel_clean", Vector3(262.0 + WT * 0.5, (y0 + y1) * 0.5, -19.0), Vector3(WT, y1 - y0, 6.0), tint)
	g.box("panel_clean", Vector3(262.0 + WT * 0.5, (y0 + y1) * 0.5, 19.0), Vector3(WT, y1 - y0, 6.0), tint)
	g.box("panel_clean", Vector3(265.0, (y0 + y1) * 0.5, -16.0 + WT * 0.5), Vector3(6.0, y1 - y0, WT), tint)
	g.box("panel_clean", Vector3(265.0, (y0 + y1) * 0.5, 16.0 - WT * 0.5), Vector3(6.0, y1 - y0, WT), tint)
	# viewport wall x=268: mullions + glass band y[15.5,20.3]
	var gw0 := -15.7; var gw1 := 15.7
	g.box("panel_clean", Vector3(268.0 - WT * 0.5, y0 + 0.25, 0.0), Vector3(WT, 0.5, gw1 - gw0), tint)
	g.box("panel_clean", Vector3(268.0 - WT * 0.5, y1 - 0.35, 0.0), Vector3(WT, 0.7, gw1 - gw0), tint)
	g.quad_ds("glass", Vector3(268.0, y0 + 0.5, gw0), Vector3(268.0, y0 + 0.5, gw1), Vector3(268.0, y1 - 0.7, gw1), Vector3(268.0, y1 - 0.7, gw0), Color(0.72, 0.86, 1.0, 0.3))
	var nmul := 9
	for i in nmul + 1:
		var mz := lerpf(gw0, gw1, float(i) / float(nmul))
		g.box("metal_dark", Vector3(268.0, (y0 + y1) * 0.5 - 0.1, mz), Vector3(0.22, y1 - y0 - 1.1, 0.16), Color(0.3, 0.31, 0.35, tint.a))
	g.box("metal_dark", Vector3(268.0, y0 + 0.52, 0.0), Vector3(0.3, 0.16, gw1 - gw0 + 0.4), Color(0.3, 0.31, 0.35, tint.a))
	g.box("metal_dark", Vector3(268.0, y1 - 0.72, 0.0), Vector3(0.3, 0.16, gw1 - gw0 + 0.4), Color(0.3, 0.31, 0.35, tint.a))

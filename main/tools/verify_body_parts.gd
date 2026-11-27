extends Node
## verify_body_parts — verificador de contención de los colliders multi-cilindro.
##
## Para cada personaje (jugador + cada tipo de enemigo) instancia el rig real,
## pide sus hit_parts()/body_colliders() y comprueba que TODOS los vértices de
## TODOS los MeshInstance3D cubiertos caen dentro de la unión de cápsulas
## (tolerancia 1e-3). Además perturba cada articulación ancla ±0.3 rad y repite
## el chequeo en la pose movida: si una malla quedó anclada al joint equivocado
## aparece aquí como violación.
##
## Uso:
##   DISPLAY=:10 godot --path main --headless -- --verify-body
##   flags: --no-perturb  (omite el barrido de poses)

const TOL := 0.001
const PERTURB := 0.3
const BodyColliders = preload("res://core/body_colliders.gd")

var _args := {}
var _failures := 0
var _report: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", false, 1)
			if kv.is_empty():
				continue
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _ready() -> void:
	_run.call_deferred()


func _log(s: String) -> void:
	print("[verify-body] " + s)
	_report.append(s)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	_log("== verificación de colliders multi-cilindro (tol %.3f) ==" % TOL)

	for entry in [_rig_vesper, _rig_arc, _rig_shard, _rig_wheel, _rig_duelist, _rig_boss]:
		await _verify(entry)

	_log("== fin: %.1fs — %s ==" % [(Time.get_ticks_msec() - t0) / 1000.0,
		"TODO OK ✓" if _failures == 0 else "%d FALLOS ✗" % _failures])
	var out: String = _args.get("report", "")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string("\n".join(_report) + "\n")
		f.close()
	get_tree().quit(0 if _failures == 0 else 1)


# ------------------------------------------------------------------ rigs
# Cada factory devuelve:
#   label       nombre para el log
#   node        nodo a añadir al árbol (el rig/contenedor)
#   built_fn    → BodyColliders.build(...) result ({parts, covered, anchors…})
#   extra       → [MeshInstance3D] adicionales a verificar (módulos…)
#   refresh     → callable que re-sincroniza meshes tras perturbar (opcional)
#   skip_perturb → true para rigs con merges de anchors (falsos positivos)

func _rig_vesper() -> Callable:
	return func() -> Dictionary:
		var Rig = load("res://runtime/characters/vesper/design/integration/campaign_rig.gd")
		var rig = Rig.new()
		return {"label": "player (vesper)", "node": rig,
			"built_fn": func(): return rig._build_body_colliders()}


func _rig_arc() -> Callable:
	return func() -> Dictionary:
		var S = load("res://runtime/enemies/mobs/arc_sentinel/design/scripts/ch/arc_sentinel.gd")
		var n = S.new()
		return {"label": "arc sentinel", "node": n,
			"built_fn": func(): return n.rig._build_body_colliders()}


func _rig_shard() -> Callable:
	return func() -> Dictionary:
		var S = load("res://runtime/enemies/mobs/shard_phantom/design/scripts/character.gd")
		var n = S.new()
		n.encounter_projectile = true
		return {"label": "shard phantom", "node": n,
			"built_fn": func(): return n._build_body_colliders(),
			"extra": func():
				var out: Array = []
				for m: Dictionary in n.field.mods:
					out.append(m["node"])
				return out,
			"refresh": func(): n.field.update_assembled(0.003, 0.0, 6.0)}


func _rig_wheel() -> Callable:
	return func() -> Dictionary:
		var scene: PackedScene = load("res://runtime/enemies/mobs/wheel_sentry/design/scenes/ranged/wheel_sentry_model.tscn")
		var n = scene.instantiate()
		return {"label": "wheel sentry", "node": n,
			"built_fn": func(): return n._build_body_colliders(),
			"skip_perturb": true}   # _turret_column escala en runtime (no rígida)


func _rig_duelist() -> Callable:
	return func() -> Dictionary:
		var S = load("res://runtime/enemies/mobs/mech_duelist/design/src/enemies/duelist/duelist_combat_rig.gd")
		var n = S.new()
		return {"label": "mech duelist", "node": n,
			"built_fn": func(): return n._build_body_colliders(),
			"skip_perturb": true}   # fingers→palm merge: perturbar la palma daría falsos +


func _rig_boss() -> Callable:
	return func() -> Dictionary:
		var S = load("res://runtime/enemies/bosses/phase_boss/design/src/enemies/phase_boss/phase_boss_combat.gd")
		var n = S.new()
		return {"label": "phase boss", "node": n,
			"built_fn": func(): return n._build_body_colliders()}


# ------------------------------------------------------------------ verify

func _verify(factory: Callable) -> void:
	var make: Callable = factory.call()
	var spec: Dictionary = make.call()
	var label: String = spec["label"]
	var t0 := Time.get_ticks_msec()
	var node: Node = spec["node"]
	add_child(node)
	for i in 8:
		await get_tree().process_frame

	var built: Dictionary = spec["built_fn"].call()
	var parts: Array = BodyColliders.world_parts(built)["parts"]
	if parts.is_empty():
		_fail(label, "0 piezas generadas")
		remove_child(node)
		node.queue_free()
		return

	var extra: Array = spec["extra"].call() if spec.has("extra") else []
	var covered: Array = built.get("covered", [])
	var skipped: Array = built.get("skipped", [])
	var all_mis: Array = covered.duplicate()
	all_mis.append_array(extra)

	var st := _check(parts, all_mis)
	# Coste por frame de world_parts (muestreo de cápsulas + broadphase AABB)
	var wt0 := Time.get_ticks_usec()
	for i in 20:
		BodyColliders.world_parts(built)
	var world_us := (Time.get_ticks_usec() - wt0) / 20.0
	_log("%s: %d piezas | %d meshes (%d excluidas) | %d vértices | violación máx %.4f | world_parts %.0fµs" % [
		label, parts.size(), covered.size(), skipped.size(), st["verts"], st["worst"], world_us])
	if _args.has("dump"):
		var per_anchor := {}
		for p: Dictionary in built["parts"]:
			var an: String = String(p["anchor"].name) if p.get("anchor") is Node3D else "?"
			per_anchor[an] = int(per_anchor.get(an, 0)) + 1
		for cname in built.get("clusters", {}):
			_log("  · %s ×%d → %d piezas (%s)" % [cname, built["clusters"][cname],
				per_anchor.get(cname, 0), cname.trim_suffix("_Geometry")])
	if st["worst"] > TOL:
		_fail(label, "%d vértices fuera (peor %.4f en %s)" % [st["out"], st["worst"], st["pt"]])

	if not _args.has("no-perturb") and not spec.get("skip_perturb", false):
		await _perturb(label, built, spec, all_mis)

	remove_child(node)
	node.queue_free()
	_log("  %d ms" % (Time.get_ticks_msec() - t0))


func _check(parts: Array, mis: Array) -> Dictionary:
	var verts := 0
	var out := 0
	var worst := -1e9
	var worst_pt := Vector3.ZERO
	for mi: MeshInstance3D in mis:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var xf := mi.global_transform
		for v in mi.mesh.get_faces():
			var d := BodyColliders.violation(xf * v, parts)
			verts += 1
			if d > worst:
				worst = d
				worst_pt = xf * v
			if d > TOL:
				out += 1
	return {"verts": verts, "out": out, "worst": worst, "pt": worst_pt}


func _perturb(label: String, built: Dictionary, spec: Dictionary, mis: Array) -> void:
	# Rota cada anchor y vuelve a verificar: los meshes rígidos se mueven con
	# su cápsula; una malla mal anclada (o no rígida) se delata aquí.
	# Los joints fusionados por budget también se rotan: si articulan en
	# runtime, sus vértices salen de la cápsula del padre → debe reportarse.
	var anchors := {}
	for p: Dictionary in built["parts"]:
		var a = p.get("anchor")
		if a != null and is_instance_valid(a):
			anchors[a] = (a as Node3D).transform
	var merged_nodes: Dictionary = built.get("merged", {})
	var vacuous := 0
	for a in merged_nodes:
		if not is_instance_valid(a):
			continue
		anchors[a] = (a as Node3D).transform
		# ¿el subárbol del merged contiene meshes verificados? Si no, rotarlo
		# no prueba nada (nada se mueve): se anota para el informe.
		var under := 0
		for mi: MeshInstance3D in mis:
			if is_instance_valid(mi) and (a as Node3D).is_ancestor_of(mi):
				under += 1
		if under == 0:
			vacuous += 1
			_log("  · merged %s: 0 meshes bajo él (perturbación vacua)" % a.name)
	var flagged := 0
	for a in anchors:
		var tag := " (merged)" if merged_nodes.has(a) else ""
		(a as Node3D).rotation += Vector3(PERTURB, PERTURB * 0.6, -PERTURB * 0.4)
		if spec.has("refresh"):
			spec["refresh"].call()
		var parts: Array = BodyColliders.world_parts(built)["parts"]
		var st := _check(parts, mis)
		if st["worst"] > TOL:
			flagged += 1
			_log("  ⚠ ancla %s%s: violación %.4f tras rotación" % [a.name, tag, st["worst"]])
		(a as Node3D).transform = anchors[a]
	if spec.has("refresh"):
		spec["refresh"].call()
	if flagged == 0:
		_log("  ✓ %d anclas perturbadas (%d merged), contención mantenida" % [
			anchors.size(), merged_nodes.size()])
	else:
		_fail(label, "%d anclas rompen contención al rotarlas" % flagged)


func _fail(label: String, msg: String) -> void:
	_failures += 1
	_log("✗ %s — %s" % [label, msg])

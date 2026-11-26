extends Node3D
## CrowdInstancer — 同种敌人的静态零件跨实例合批渲染。
##
## 每个敌人登记一批「槽位」：{key, anchor, rel}。
##   key    = 稳定键（锚点索引路径 + mesh 几何指纹 + 材质签名 + 渲染标志）
##   anchor = 会被代码驱动的 pivot（锚点子树内叶子相对它静止）
##   rel    = 叶子相对锚点的变换（静态件恒等，已合并的 mesh 直接 == IDENTITY）
##
## 同 key 的所有敌人共用一个 MultiMeshInstance3D；每帧把
## `anchor.global_transform * rel` 写进该敌人在组里的实例槽。
## 20 只同种怪 = 1 只的 draw call 数。
##
## 死亡/卸载的槽位用零缩放矩阵占位（不重建 MMI）。

const MAX_INSTANCES := 96

var _groups: Dictionary = {}   # key -> {"mmi": MMI, "slots": {owner->index}, "free": [i]}
var _parts: Dictionary = {}    # owner -> [{key, anchor, rel}]
var _dirty := false


func register_enemy(owner: Node3D, slots: Array) -> void:
	if _parts.has(owner):
		unregister_enemy(owner)
	var list := []
	for s in slots:
		var key: String = s["key"]
		var g: Dictionary = _groups.get(key, {})
		if g.is_empty():
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Crowd"
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = s["mesh"]
			mmi.multimesh = mm
			mmi.cast_shadow = s["flags"]["cast_shadow"]
			mmi.layers = s["flags"]["layers"]
			mmi.gi_mode = s["flags"]["gi_mode"]
			mmi.visible = s["flags"]["visible"]
			mmi.top_level = true
			mmi.global_transform = Transform3D.IDENTITY
			if s["flags"]["material_override"] != null:
				mmi.material_override = s["flags"]["material_override"]
			for i in s["flags"]["overrides"].size():
				mmi.set_surface_override_material(i, s["flags"]["overrides"][i])
			add_child(mmi)
			g = {"mmi": mmi, "slots": {}, "free": [], "count": 0}
			_groups[key] = g
		var idx := -1
		if not g["free"].is_empty():
			idx = g["free"].pop_back()
		elif g["count"] < MAX_INSTANCES:
			idx = g["count"]
			g["count"] += 1
			g["mmi"].multimesh.instance_count = g["count"]
		if idx < 0:
			continue
		g["slots"][owner] = idx
		list.append({"key": key, "anchor": s["anchor"], "rel": s["rel"],
			"idx": idx, "node": s.get("node")})
		# 原件改走共享 MMI：隐藏原 MeshInstance（保留树结构供逻辑查询）
		if s.has("node") and is_instance_valid(s["node"]):
			s["node"].visible = false
	_parts[owner] = list
	_dirty = true


func unregister_enemy(owner: Node3D) -> void:
	if not _parts.has(owner):
		return
	for p in _parts[owner]:
		var g: Dictionary = _groups.get(p["key"], {})
		if g.is_empty():
			continue
		g["mmi"].multimesh.set_instance_transform(p["idx"], Transform3D(Basis(), Vector3.ZERO))
		g["slots"].erase(owner)
		g["free"].append(p["idx"])
		if p.has("node") and is_instance_valid(p["node"]):
			p["node"].visible = true
	_parts.erase(owner)


func _process(_dt: float) -> void:
	if _parts.is_empty():
		return
	for owner in _parts:
		if not is_instance_valid(owner) or not owner.is_inside_tree():
			continue
		for p in _parts[owner]:
			var anchor: Node3D = p["anchor"]
			if not is_instance_valid(anchor) or not anchor.is_inside_tree():
				continue
			var g: Dictionary = _groups[p["key"]]
			g["mmi"].multimesh.set_instance_transform(
				p["idx"], anchor.global_transform * p["rel"])


## 收一个锚点子树里的全部静态 MeshInstance3D 叶子，吐成 slots。
## xf 为相对锚点的累计变换（内部用）。
static func collect_slots(model_root: Node3D, anchors: Array) -> Array:
	var anchor_set := {}
	for a in anchors:
		if a != null:
			anchor_set[a] = true
	var slots := []
	var seen := {}
	for a in anchors:
		if a == null:
			continue
		_collect_into(model_root, a, Transform3D.IDENTITY, anchor_set, slots, seen)
	return slots


static func _collect_into(root: Node3D, anchor: Node3D, xf: Transform3D,
		anchor_set: Dictionary, slots: Array, seen: Dictionary) -> void:
	for child in anchor.get_children():
		if child is MeshInstance3D and child.get_child_count() == 0:
			if child.has_meta("no_merge") or child.mesh == null:
				continue
			if seen.has(child):
				continue
			seen[child] = true
			slots.append(_make_slot(root, anchor, child, xf * child.transform))
		elif child is Node3D:
			if anchor_set.has(child):
				continue  # 子锚点自己收，不并到父锚点
			_collect_into(root, child, xf * (child as Node3D).transform,
				anchor_set, slots, seen)


static func _make_slot(root: Node3D, anchor: Node3D, mi: MeshInstance3D,
		rel: Transform3D) -> Dictionary:
	var mat_sig := ""
	var overrides := []
	for s in mi.mesh.get_surface_count():
		var m: Material = mi.get_surface_override_material(s)
		if m != null:
			overrides.append(m)
			mat_sig += _mat_sig(m) + ";"
	var flags := {
		"cast_shadow": mi.cast_shadow,
		"layers": mi.layers,
		"gi_mode": mi.gi_mode,
		"visible": mi.visible,
		"material_override": mi.material_override,
		"overrides": overrides,
	}
	var key := "%s|%s|%s|%d|%d|%d|%d" % [
		_anchor_path(root, anchor), _fp(mi.mesh),
		mat_sig + _mat_sig(mi.material_override),
		mi.cast_shadow, mi.layers, mi.gi_mode,
		1 if mi.visible else 0]
	return {"key": key, "anchor": anchor, "rel": rel,
		"mesh": mi.mesh, "flags": flags, "node": mi}


## 锚点在 model 下的稳定索引路径（不同实例的同位置节点路径相同）。
static func _anchor_path(root: Node, n: Node) -> String:
	var parts := []
	var cur := n
	while cur != null and cur != root:
		parts.append(str(cur.get_index()))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)


static func _fp(mesh: Mesh) -> String:
	var fp := ""
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts = arrays[Mesh.ARRAY_VERTEX]
		var idxs = arrays[Mesh.ARRAY_INDEX]
		var n: int = verts.size() if verts is PackedVector3Array else 0
		var m: int = idxs.size() if idxs is PackedInt32Array else 0
		var bb := ""
		if n > 0:
			var aabb := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				aabb = aabb.expand(v)
			bb = "%v|%v" % [aabb.position, aabb.size]
		fp += "%d|%d|%s;" % [n, m, bb]
	return fp


## 材质按「内容」签名，不按实例 id：每台怪 .duplicate() 出的材质
## 参数相同 → 同签名 → 同组共享 MMI。
static func _mat_sig(m: Material) -> String:
	if m == null:
		return "null"
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		return "std|%s|%s|%s|%.2f|%.2f|%d|%d|%.2f|%d" % [
			sm.albedo_color, sm.emission, sm.emission_enabled,
			sm.metallic, sm.roughness, int(sm.transparency),
			int(sm.shading_mode), sm.emission_energy_multiplier,
			int(sm.cull_mode)]
	if m is ShaderMaterial:
		var sh := m as ShaderMaterial
		var sig := "shd|%s|" % (sh.shader.resource_path if sh.shader else "null")
		for p in sh.shader.get_shader_uniform_list():
			var nm: String = p["name"]
			sig += "%s=%s;" % [nm, str(sh.get_shader_parameter(nm))]
		return sig
	return str(m)

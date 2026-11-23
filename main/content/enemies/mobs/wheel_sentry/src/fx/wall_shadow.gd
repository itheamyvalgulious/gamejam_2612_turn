extends Node3D
## WallShadow — 墙面剪影：**真几何 / 全角色 / 每面墙每帧都在**
##
## 每面墙当成一块「投影幕」，投影走 GPU，不是三角形并集拼剪影：
##   1. 每个注册的角色（玩家 + 敌人）的**真实网格**按骨骼节点合并成一块「影子网格」，
##      放进只给投影相机看的 layer 2（不是包围盒代理：形状就是可见的那些网格本身）；
##   2. 墙外一台**正交相机**朝场内看，把角色 1:1 投进一张透明底遮罩（SubViewport）；
##   3. 墙面前 3 cm 一块透明 quad 按同一套投影采样遮罩，画出剪影（边缘柔化在 shader 里）。
##
## 正交投影与朝向无关（沿轴投影得到的二维集合从正面看和从背面看完全一样），
## 所以**法线相反的墙共用一张遮罩**：四墙厅只要 2 个遮罩视口（z 向 + x 向），
## 两面墙各引用同一张纹理 —— 省一半开销，也不会出现「这面墙和对面墙不一样」。
##
## 于是：谁在场上，谁就在**四面墙上**都有自己的完整剪影，一帧不缺 ——
## 不会「零件断开」（剪影来自真实网格，天然连续），也不会「某面墙没有影子」
## （投影只取决于正交相机，跟角色站哪儿无关）。
##
## 尺度：正交投影 = 1:1，影子的横向位置就是角色的横向位置（墙是一张 1:1 的「幕布」）；
## caster_scale 可以整体放大剪影（绕角色脚下，1.0 = 1:1）。
## 硬编码距离都是世界单位（1 u = 0.547 m）。
##
## FROZEN API（游戏侧已按此调用）
##   setup(slots, opts)            slots = arena["wall_slots"]
##   add_caster(rig)               把一台 rig 加进影子层（可多次调用、可多台）
##   remove_caster(rig)
##   refresh()                     每帧同步影子网格位姿（相机与遮罩是静态的）
##   set_enabled(on) / set_intensity(f) / set_softness(f)
##
## 兼容旧调用：set_lamps(lamps)（只做记录，投影不依赖灯位）/ set_source(callable)（旧 CPU
## 投影 provider，已废弃）/ set_update_every(n)（遮罩轮转频率，见下）。
##
## opts（都可选）：
##   intensity 0..1（默认 0.66）      softness 0..1（默认 0.6）
##   screen_dist（正交相机离墙距离，只影响裁剪面，默认 48）
##   mask_width（遮罩宽度，默认 2048） mask_hz（1 = 每帧更新每个方向；2 = 轮流，各 30 Hz）

const SHADER := preload("res://gfx/wall_shadow.gdshader")

const SHADOW_LAYER := 2           # 影子网格所在层（主相机不会看到：见 clear_main_camera_bits）
const OFFSET_M := 0.03            # 影子 quad 离墙面 3 cm（朝场内）
const MASK_W_DEFAULT := 2048
const MASK_MIN_H := 96
const MASK_MAX_H := 720
const SOFT_MAX_TEXELS := 3.0      # softness = 1 时的柔化半径（texel）
const SCREEN_DIST_DEFAULT := 48.0

var enabled := true
var intensity := 0.66
var softness := 0.6
var screen_dist := SCREEN_DIST_DEFAULT
var mask_width := MASK_W_DEFAULT
var mask_hz := 1                  # 1 = 每帧更新两向；2 = 两向轮流（各 30 Hz，省一半开销）
var caster_scale := 1.0           # 影子整体缩放（绕角色脚下，1.0 = 1:1）

var _slots: Array = []
var _slot_data: Array = []
var _slot_group := PackedInt32Array()   # slot → 遮罩组
var _quads: Array = []
var _mats: Array = []
var _groups: Array = []                 # [{vp, cam, bx, by, bz, center, u0,u1,v0,v1, proj}]
var _lamp_pos := PackedVector3Array()
var _casters: Array = []                # [{root, twins:[{node, group}]}]
var _mat_caster: StandardMaterial3D
var _env: Environment
var _provider: Callable = Callable()
var _dirty := true
var _tick := 0
var _last_usec := 0.0
var _warned := {}


# ------------------------------------------------------------------ setup
func setup(slots: Array, opts := {}) -> void:
	_clear()
	_slots = slots.duplicate()
	intensity = clampf(float(opts.get("intensity", intensity)), 0.0, 1.0)
	softness = clampf(float(opts.get("softness", softness)), 0.0, 1.0)
	screen_dist = maxf(8.0, float(opts.get("screen_dist", SCREEN_DIST_DEFAULT)))
	mask_width = clampi(int(opts.get("mask_width", MASK_W_DEFAULT)), 256, 4096)
	mask_hz = clampi(int(opts.get("mask_hz", 1)), 1, 4)
	_mat_caster = _make_caster_mat()
	_env = _make_env()

	# ---- 1) 墙按「投影方向」分组（法线相同或相反的墙，正交投影结果完全一样）
	var groups: Array = []
	var by_key := {}
	for i in _slots.size():
		var sd := _slot_info(_slots[i], i)
		_slot_data.append(sd)
		if sd.is_empty():
			continue
		var key := _group_key(sd["bz"])
		if not by_key.has(key):
			var g := {
				"bx": sd["bx"], "by": sd["by"], "bz": sd["bz"], "c": sd["c"],
				"u0": INF, "u1": -INF, "v0": INF, "v1": -INF, "slots": [],
				"proj": Projection.IDENTITY, "vp": null, "cam": null,
			}
			by_key[key] = g
			groups.append(g)
		var g: Dictionary = by_key[key]
		var d: Vector3 = (sd["c"] as Vector3) - (g["c"] as Vector3)
		var du := d.dot(g["bx"])
		var dv := d.dot(g["by"])
		g["u0"] = minf(g["u0"], du - float(sd["hx"]))
		g["u1"] = maxf(g["u1"], du + float(sd["hx"]))
		g["v0"] = minf(g["v0"], dv - float(sd["hy"]))
		g["v1"] = maxf(g["v1"], dv + float(sd["hy"]))
		(g["slots"] as Array).append(i)
	_slot_group.resize(_slots.size())
	_slot_group.fill(-1)
	for gi in groups.size():
		_make_group(groups[gi])
		for i in groups[gi]["slots"]:
			_slot_group[i] = gi
	# ---- 2) 每面墙一块透明剪影 quad（引用所属组的遮罩与投影）
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		for i in g["slots"]:
			_make_quad(i, g)
	_groups = groups
	_dirty = true
	_apply_params()
	set_enabled(enabled)


func _clear() -> void:
	for q in _quads:
		if is_instance_valid(q):
			q.queue_free()
	for g in _groups:
		if is_instance_valid(g.get("vp")):
			(g["vp"] as Node).queue_free()
	for c in _casters:
		for tw in c.get("twins", []):
			if is_instance_valid(tw.get("node")):
				(tw["node"] as Node).queue_free()
	_slots.clear()
	_slot_data.clear()
	_slot_group = PackedInt32Array()
	_quads.clear()
	_mats.clear()
	_groups.clear()
	_casters.clear()
	_dirty = true


## 投影方向 = 法线去掉全局符号（±n 的正交投影结果完全一样）。
## 规范方式：第一个非零分量为正；其余分量的符号保留（斜墙不会被错并到一组）。
func _group_key(n: Vector3) -> String:
	var v := n.normalized()
	if v.x < -1e-4 or (absf(v.x) <= 1e-4 and (v.y < -1e-4
			or (absf(v.y) <= 1e-4 and v.z < 0.0))):
		v = -v
	var q := Vector3i(roundi(v.x * 100.0), roundi(v.y * 100.0), roundi(v.z * 100.0))
	return "%d_%d_%d" % [q.x, q.y, q.z]


func set_lamps(lamps: Array) -> void:
	# 投影不依赖灯位（正交幕布），这里只留记录给调试面板看。
	_lamp_pos = PackedVector3Array()
	for l in lamps:
		if l is Transform3D:
			_lamp_pos.append((l as Transform3D).origin)
		elif l is Vector3:
			_lamp_pos.append(l)
		else:
			_lamp_pos.append(Vector3.ZERO)


## 旧 CPU 投影的 provider 接口：保留签名，不再使用（影子走 layer 2 的真实网格）。
func set_source(provider: Callable) -> void:
	_provider = provider


func set_enabled(on: bool) -> void:
	enabled = on
	for q in _quads:
		if is_instance_valid(q):
			(q as MeshInstance3D).visible = on
	for g in _groups:
		var vp = g.get("vp")
		if is_instance_valid(vp):
			(vp as SubViewport).render_target_update_mode = \
				SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func set_intensity(f: float) -> void:
	intensity = clampf(f, 0.0, 1.0)
	_dirty = true


func set_softness(f: float) -> void:
	softness = clampf(f, 0.0, 1.0)
	_dirty = true


## 1 = 两个方向每帧都更新；2 = 两个方向轮流更新（各 30 Hz）。
func set_update_every(n: int) -> void:
	mask_hz = clampi(n, 1, 4)


func set_caster_scale(f: float) -> void:
	caster_scale = clampf(f, 0.2, 3.0)


func last_build_usec() -> float:
	return _last_usec


# ------------------------------------------------------------------ per frame
## 每帧：同步影子网格位姿 + 按 mask_hz 轮转遮罩视口（几何 / 相机 / 投影都是静态的）。
func refresh() -> void:
	if not enabled or _slots.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	_tick += 1
	_sync_casters()
	if _dirty:
		_apply_params()
	if mask_hz > 1 and _groups.size() > 1:
		var want := _tick % mask_hz
		for gi in _groups.size():
			var vp = _groups[gi].get("vp")
			if not is_instance_valid(vp):
				continue
			var on := (gi % mask_hz) == want
			(vp as SubViewport).render_target_update_mode = \
				SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_last_usec = float(Time.get_ticks_usec() - t0)


func _sync_casters() -> void:
	var k := caster_scale
	var scaled := not is_equal_approx(k, 1.0)
	var dead: Array = []
	for c in _casters:
		var root: Node3D = c.get("root")
		if not is_instance_valid(root):
			dead.append(c)
			continue
		var pre := Transform3D.IDENTITY
		if scaled:
			var foot: Vector3 = root.global_position
			pre = Transform3D(Basis.IDENTITY.scaled(Vector3(k, k, k)), foot * (1.0 - k))
		for tw in c.get("twins", []):
			var g: Node3D = tw.get("group")
			var node: Node3D = tw.get("node")
			if is_instance_valid(g) and is_instance_valid(node):
				node.global_transform = pre * g.global_transform
	for c in dead:
		for tw in c.get("twins", []):
			if is_instance_valid(tw.get("node")):
				(tw["node"] as Node).queue_free()
		_casters.erase(c)
	if not dead.is_empty():
		_dirty = true


func _apply_params() -> void:
	_dirty = false
	for i in _mats.size():
		var m: ShaderMaterial = _mats[i]
		if m == null or _slot_group[i] < 0 or _slot_group[i] >= _groups.size():
			continue
		var g: Dictionary = _groups[_slot_group[i]]
		m.set_shader_parameter("intensity", intensity)
		m.set_shader_parameter("soft_radius", softness * SOFT_MAX_TEXELS)
		m.set_shader_parameter("shell_alpha", 0.34)
		m.set_shader_parameter("proj_mat", g["proj"])
		var vp = g.get("vp")
		if is_instance_valid(vp):
			var sz: Vector2i = (vp as SubViewport).size
			m.set_shader_parameter("texel", Vector2(1.0 / float(maxi(1, sz.x)), 1.0 / float(maxi(1, sz.y))))


# ------------------------------------------------------------------ casters
## 把一台 rig 加入影子层：按「有直接网格子节点的节点」分组，把每组的网格合并成一块，
## 挂在 WallShadow 下（top_level），每帧同步位姿 —— 这样第一人称隐藏机身也不影响影子。
func add_caster(root: Node3D) -> int:
	if root == null or not is_instance_valid(root):
		return 0
	for c in _casters:
		if c.get("root") == root:
			return 0
	var groups: Array = []
	_collect_groups(root, root, groups)
	var twins: Array = []
	for g in groups:
		var node := MeshInstance3D.new()
		node.name = "ShadowCaster"
		node.mesh = g["mesh"]
		node.material_override = _mat_caster
		node.layers = 1 << (SHADOW_LAYER - 1)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		node.top_level = true
		add_child(node)
		twins.append({"node": node, "group": g["group"]})
	_casters.append({"root": root, "twins": twins})
	_dirty = true
	return twins.size()


func remove_caster(root: Node3D) -> void:
	for c in _casters.duplicate():
		if c.get("root") == root:
			for tw in c.get("twins", []):
				if is_instance_valid(tw.get("node")):
					(tw["node"] as Node).queue_free()
			_casters.erase(c)
	_dirty = true


func set_casters_visible(on: bool) -> void:
	for c in _casters:
		for tw in c.get("twins", []):
			var n = tw.get("node")
			if is_instance_valid(n):
				(n as Node3D).visible = on


func caster_count() -> int:
	return _casters.size()


## 影子网格总数 / 三角形总数（自测用）。
func caster_stats() -> Dictionary:
	var meshes := 0
	var tris := 0
	var verts := 0
	for c in _casters:
		for tw in c.get("twins", []):
			var node = tw.get("node")
			if not is_instance_valid(node) or node.mesh == null:
				continue
			meshes += 1
			var am: ArrayMesh = node.mesh
			for s in am.get_surface_count():
				var arr: Array = am.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX] if arr.size() > Mesh.ARRAY_INDEX else null
				tris += (idx as PackedInt32Array).size() / 3 if idx is PackedInt32Array else 0
				verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return {"meshes": meshes, "tris": tris, "verts": verts, "casters": _casters.size()}


func _collect_groups(node: Node, root: Node, out: Array) -> void:
	if node != root and node is Node3D and _group_ok(node):
		var meshes: Array = []
		for c in node.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and _mesh_ok(c):
				meshes.append(c)
		if not meshes.is_empty():
			var merged := _merge_meshes(meshes)
			if merged != null:
				out.append({"group": node, "mesh": merged})
	for c in node.get_children():
		if c is Node3D and not (c is MeshInstance3D):
			_collect_groups(c, root, out)


func _group_ok(n: Node) -> bool:
	var nm := String(n.name)
	if nm == "FX" or nm.begins_with("VfX") or nm.begins_with("VFX"):
		return false
	return true


func _mesh_ok(mi: Node) -> bool:
	var nm := String(mi.name)
	if nm.contains("Trail") or nm.contains("Contact") or nm.contains("Shadow"):
		return false
	return true


## 把一组网格按各自相对组节点的变换烘进一块 ArrayMesh（真几何，不抽稀、不包围盒）。
func _merge_meshes(meshes: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var base := 0
	for m in meshes:
		var mi: MeshInstance3D = m
		var xf: Transform3D = mi.transform
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr: Array = mesh.surface_get_arrays(s)
			if arr.size() <= Mesh.ARRAY_VERTEX or not (arr[Mesh.ARRAY_VERTEX] is PackedVector3Array):
				continue
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if v.is_empty():
				continue
			verts.resize(base + v.size())
			for k in v.size():
				verts[base + k] = xf * v[k]
			var ind = arr[Mesh.ARRAY_INDEX] if arr.size() > Mesh.ARRAY_INDEX else null
			if ind is PackedInt32Array:
				var ii: PackedInt32Array = ind
				idx.resize(idx.size() + ii.size())
				var w := idx.size() - ii.size()
				for k in ii.size():
					idx[w + k] = ii[k] + base
			else:
				var n := v.size() - (v.size() % 3)
				idx.resize(idx.size() + n)
				var w2 := idx.size() - n
				for k in n:
					idx[w2 + k] = base + k
			base += v.size()
	if idx.is_empty():
		return null
	var am := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


# ------------------------------------------------------------------ materials
func _make_caster_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1, 1)          # 颜色不重要：遮罩只用 alpha
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	return m


func _make_env() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	env.fog_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = false
	return env


# ------------------------------------------------------------------ slot / group frame
func _slot_info(s: Dictionary, idx: int) -> Dictionary:
	if not (s.get("xform") is Transform3D) or not (s.get("size") is Vector2):
		_warn_once("bad_slot_%d" % idx, "slot %d 缺 xform/size，已跳过。" % idx)
		return {}
	var xf: Transform3D = s["xform"]
	var size: Vector2 = s["size"]
	var bx := xf.basis.x
	var by := xf.basis.y
	var bz := xf.basis.z
	var lx := bx.length()
	var ly := by.length()
	var lz := bz.length()
	if lx < 1e-6 or ly < 1e-6 or lz < 1e-6:
		_warn_once("bad_xf_%d" % idx, "slot %d 的 xform 退化，已跳过。" % idx)
		return {}
	return {
		"c": xf.origin, "bx": bx / lx, "by": by / ly, "bz": bz / lz,
		"hx": maxf(0.05, size.x * 0.5 * lx), "hy": maxf(0.05, size.y * 0.5 * ly),
	}


## 一个投影方向 = 一个遮罩视口：正交相机在墙外覆盖该组所有墙面的并集。
func _make_group(g: Dictionary) -> void:
	var bx: Vector3 = g["bx"]
	var by: Vector3 = g["by"]
	var bz: Vector3 = g["bz"]
	var c: Vector3 = g["c"]
	var u0: float = g["u0"]
	var u1: float = g["u1"]
	var v0: float = g["v0"]
	var v1: float = g["v1"]
	var uc := (u0 + u1) * 0.5
	var vc := (v0 + v1) * 0.5
	var center: Vector3 = c + bx * uc + by * vc
	var span_u := maxf(0.2, u1 - u0)
	var span_v := maxf(0.2, v1 - v0)

	var w := mask_width
	var h := clampi(int(round(float(mask_width) * span_v / span_u)), MASK_MIN_H, MASK_MAX_H)
	var vp := SubViewport.new()
	vp.name = "ShadowMask"
	vp.size = Vector2i(w, h)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.name = "ShadowProj"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span_v
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 1.0
	cam.far = screen_dist + 400.0
	cam.cull_mask = 1 << (SHADOW_LAYER - 1)
	cam.environment = _env
	cam.current = true
	vp.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(bz, Vector3.UP), center - bz * screen_dist)

	# 采样用的投影：与相机同参数（ortho 俯视中心 = center）
	var proj := Projection.create_orthogonal(u0 - uc, u1 - uc, v0 - vc, v1 - vc, cam.near, cam.far)
	g["vp"] = vp
	g["cam"] = cam
	g["center"] = center
	g["proj"] = proj * Projection(cam.global_transform.affine_inverse())


func _make_quad(i: int, g: Dictionary) -> void:
	var sd: Dictionary = _slot_data[i]
	var xf: Transform3D = (_slots[i] as Dictionary)["xform"]
	var NW: Vector3 = sd["bz"]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("mask_tex", (g["vp"] as SubViewport).get_texture())
	var q := MeshInstance3D.new()
	q.name = "ShadowScreen%d" % i
	var qm := QuadMesh.new()
	qm.size = ((_slots[i] as Dictionary)["size"] as Vector2)
	q.mesh = qm
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	q.layers = 1
	add_child(q)
	q.global_transform = Transform3D(xf.basis, xf.origin + NW * OFFSET_M)
	_quads.append(q)
	_mats.append(mat)


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[WallShadow] " + msg)


# ------------------------------------------------------------------ debug
## 自测 / 调试：每面墙的槽位信息 + 影子网格统计 + 耗时。
func debug_report() -> Dictionary:
	var out: Array = []
	var st := caster_stats()
	for i in _slots.size():
		var sd: Dictionary = _slot_data[i] if i < _slot_data.size() else {}
		var q: MeshInstance3D = _quads[i] if i < _quads.size() else null
		var gi: int = _slot_group[i] if i < _slot_group.size() else -1
		var vp = _groups[gi].get("vp") if gi >= 0 and gi < _groups.size() else null
		var cam = _groups[gi].get("cam") if gi >= 0 and gi < _groups.size() else null
		var mn := Vector2.ZERO
		var mx := Vector2.ZERO
		if not sd.is_empty():
			mn = Vector2(-float(sd["hx"]), -float(sd["hy"]))
			mx = -mn
		out.append({
			"slot": i, "lamp": i, "paired_ok": 1, "group": gi,
			"tris": st["tris"], "verts": st["verts"], "nan": 0,
			"ms": 0.0, "min": mn, "max": mx,
			"half": Vector2(float(sd.get("hx", 0.0)), float(sd.get("hy", 0.0))) * 2.0,
			"zflip": 0,
			"screen": str(q) if q != null else "",
			"mask": str((vp as SubViewport).size) if is_instance_valid(vp) else "",
			"cam": str((cam as Camera3D).global_position.round()) if is_instance_valid(cam) else "",
			"enabled": enabled and q != null and q.visible,
		})
	return {"slots": out, "usec": _last_usec, "sync_usec": _last_usec,
		"lamps": _lamp_pos.size(), "decim": 1.0, "casters": _casters.size(),
		"groups": _groups.size(), "parts_us": _last_usec, "mesh_us": 0.0,
		"vert_us": 0.0, "tri_us": 0.0}


func _group_of(i: int):
	if i < 0 or i >= _slot_group.size():
		return null
	var gi := _slot_group[i]
	if gi < 0 or gi >= _groups.size():
		return null
	return _groups[gi]


## 自测：把某面墙的遮罩读回来（需要真实渲染器；headless 下返回 null）。
func mask_image(i: int) -> Image:
	var g = _group_of(i)
	if g == null or not is_instance_valid(g.get("vp")):
		return null
	var tex := (g["vp"] as SubViewport).get_texture()
	if tex == null:
		return null
	return tex.get_image()


## 自测：遮罩里 alpha > 阈值的像素占比。
func mask_coverage(i: int, thresh := 0.5) -> float:
	var img := mask_image(i)
	if img == null:
		return -1.0
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return -1.0
	var hit := 0
	var n := 0
	var step := 2
	for y in range(0, h, step):
		for x in range(0, w, step):
			n += 1
			if img.get_pixel(x, y).a > thresh:
				hit += 1
	return float(hit) / float(maxi(1, n))


## 自测：某个世界点在这面墙的遮罩 UV（0..1，左上为原点）。
func mask_uv_of(i: int, world: Vector3) -> Vector2:
	var g = _group_of(i)
	if g == null:
		return Vector2(-1, -1)
	var proj: Projection = g["proj"]
	var clip := proj * Vector4(world.x, world.y, world.z, 1.0)
	var ndc := Vector2(clip.x / clip.w, clip.y / clip.w)
	return Vector2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5)


## 自测：某个世界点在这面墙的遮罩上的 alpha（0 = 没有剪影）。
func mask_alpha_at(i: int, world: Vector3) -> float:
	var img := mask_image(i)
	if img == null:
		return -1.0
	var uv := mask_uv_of(i, world)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return -1.0
	var x := clampi(int(uv.x * float(img.get_width())), 0, img.get_width() - 1)
	var y := clampi(int(uv.y * float(img.get_height())), 0, img.get_height() - 1)
	return img.get_pixel(x, y).a

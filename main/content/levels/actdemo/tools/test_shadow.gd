extends Node3D
## test_shadow —— WallShadow（投影幕布）验收场景。不属于游戏本体。
##
## 契约：
##   * 每面墙一块透明剪影 quad，法线相反的墙共用一张遮罩（4 墙 → 2 个 SubViewport）
##   * 剪影来自**真实网格**（把每台 rig 的 MeshInstance3D 按骨骼节点合并），不是盒子代理
##   * 场上每个角色（玩家 + 敌人）在**每一面墙**上都有剪影：角落、贴墙、多个角色同时
##   * 正交投影 1:1：世界 x（或 z）与墙面横向位置一致，脚在墙底
##   * enabled / intensity / softness / caster_scale / remove_caster 都生效
##
## 运行：DISPLAY=:0 godot --path <proj> res://scenes/test_shadow.tscn

const WallShadow := preload("res://src/fx/wall_shadow.gd")
const ArenaKit := preload("res://src/arena/arena.gd")
const MK := preload("res://src/vesper/mesh_kit.gd")
const MAT := preload("res://src/vesper/materials.gd")

var _fails: Array = []
var _checks := 0
var _ws: Node3D
var _arena: Dictionary = {}
var _slots: Array = []
var _rigs: Array = []


func _ready() -> void:
	print("=== test_shadow（投影幕布）===")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_arena = ArenaKit.build("chamber", Vector3.ZERO)
	_slots = _arena["wall_slots"]
	add_child(_arena["node"])
	_ws = WallShadow.new()
	_ws.name = "WallShadow"
	add_child(_ws)
	_ws.setup(_slots, {"intensity": 0.7, "softness": 0.5})
	_ws.set_lamps(_arena["lamps"])
	await _frames(2)

	_phase_contract()
	await _phase_geometry()
	await _phase_presence()
	await _phase_projection()
	await _phase_toggles()
	_phase_robust()
	_summary()
	get_tree().quit(0 if _fails.is_empty() else 1)


# ------------------------------------------------------------------ A 结构契约
func _phase_contract() -> void:
	print("\n--- A 结构契约（4 墙 / 2 个投影方向）---")
	_check(_ws._quads.size() == 4, "4 面墙各有一块剪影 quad（%d）" % _ws._quads.size())
	_check(_ws._groups.size() == 2, "法线相反的墙共用遮罩 → 2 个遮罩视口（%d）" % _ws._groups.size())
	var seen := {}
	for i in _ws._slots.size():
		var gi := int(_ws._slot_group[i])
		seen[gi] = true
		var q: MeshInstance3D = _ws._quads[i]
		var mat: ShaderMaterial = q.material_override
		_check(mat != null and mat.shader != null, "墙 %d 的剪影材质装上了 shader" % i)
		_check(mat.get_shader_parameter("mask_tex") != null, "墙 %d 的遮罩纹理已绑定" % i)
	_check(seen.size() == 2, "4 面墙分到 2 组（%s）" % str(seen.keys()))
	for gi in _ws._groups.size():
		var g: Dictionary = _ws._groups[gi]
		var vp: SubViewport = g["vp"]
		_check(vp != null and vp.transparent_bg, "遮罩视口 %d 透明底（影子里不会有墙/天空）" % gi)
		_check(int(g["cam"].cull_mask) == 2, "遮罩相机只看影子层 layer 2（%d）" % int(g["cam"].cull_mask))
		_check(vp.size.x >= 1024, "遮罩横向 %d px（够读刀口）" % vp.size.x)


# ------------------------------------------------------------------ B 真几何
func _phase_geometry() -> void:
	print("\n--- B 影子网格 = 真实网格（不是盒子代理）---")
	var rig := _make_rig("boss", Vector3(0, 0, 0))
	_rigs.append(rig)
	var src_tris := _count_tris(rig)
	var src_meshes := _count_meshes(rig)
	var made: int = _ws.add_caster(rig)
	await _frames(2)
	var st: Dictionary = _ws.caster_stats()
	print("    rig: %d 个网格 / %d 三角形 → 合并成 %d 块骨架网格，总数 %d 三角形"
		% [src_meshes, src_tris, made, int(st["tris"])])
	_check(made >= 20, "按骨骼节点合并成多块（%d ≥ 20）" % made)
	_check(absi(int(st["tris"]) - src_tris) <= 4,
		"影子三角形数 ≈ rig 真实三角形数（%d vs %d；差值是排除掉的脚下接触阴影 quad）"
		% [st["tris"], src_tris])
	_check(int(st["tris"]) > 3000, "远多于旧盒子代理的 240 个三角形（%d）" % st["tris"])
	# 每个影子网格都必须是 layer 2 + 不投影 + top_level
	var ok_layer := true
	var ok_top := true
	for c in _ws._casters:
		for tw in c["twins"]:
			var n: MeshInstance3D = tw["node"]
			if n.layers != 2:
				ok_layer = false
			if not n.top_level:
				ok_top = false
	_check(ok_layer, "影子网格只在 layer 2（主相机看不到）")
	_check(ok_top, "影子网格是 top_level（第一人称隐藏机身时自己的影子仍在）")


# ------------------------------------------------------------------ C 四面墙常驻
func _phase_presence() -> void:
	print("\n--- C 每个角色在每面墙上都有剪影 ---")
	var boss: Node3D = _rigs[0]
	var player := _make_rig("player", Vector3(0, 0, 20))
	_rigs.append(player)
	_ws.add_caster(player)
	await _frames(3)
	var cases := [
		{"boss": Vector3(0, 0, 10), "player": Vector3(0, 0, 30), "tag": "场地中间"},
		{"boss": Vector3(-50, 0, -50), "player": Vector3(55, 0, 55), "tag": "对角角落"},
		{"boss": Vector3(0, 0, 54), "player": Vector3(-54, 0, 0), "tag": "贴着南墙 / 西墙"},
	]
	for c in cases:
		_place(boss, c["boss"])
		_place(player, c["player"])
		await _frames(4)
		var cov := []
		var all_ok := true
		for i in _ws._slots.size():
			var v: float = _ws.mask_coverage(i)
			cov.append(snappedf(v, 0.0001))
			if v <= 0.0005:
				all_ok = false
		_check(all_ok, "%s：四面墙都有剪影 %s" % [c["tag"], str(cov)])
	# 两个角色都在场上 → 每个方向都同时有 2 团剪影（覆盖率 > 单个）
	_place(boss, Vector3(-30, 0, 0))
	_place(player, Vector3(30, 0, 0))
	await _frames(4)
	var cov2 := []
	for i in _ws._slots.size():
		cov2.append(snappedf(_ws.mask_coverage(i), 0.0001))
	_check(float(cov2[0]) > 0.004, "两个角色同时出现在墙 0（覆盖率 %s）" % str(cov2[0]))


# ------------------------------------------------------------------ D 投影位置
func _phase_projection() -> void:
	print("\n--- D 1:1 正交投影：横向 = 世界坐标，脚在墙底 ---")
	var boss: Node3D = _rigs[0]
	var player: Node3D = _rigs[1]
	_place(boss, Vector3(20, 0, 0))
	_place(player, Vector3(-50, 0, -50))
	await _frames(4)
	# 墙 0（北墙，法线 +z）：世界 x=20 的剪影应落在 x=20 对应的遮罩位置
	var a_hit: float = _ws.mask_alpha_at(0, Vector3(20, 3, 0))
	var a_miss: float = _ws.mask_alpha_at(0, Vector3(-20, 3, 0))
	var uv: Vector2 = _ws.mask_uv_of(0, Vector3(20, 0, 0))
	print("    wall0 uv(20,0)=%s  alpha(20,3)=%.2f  alpha(-20,3)=%.2f" % [str(uv), a_hit, a_miss])
	_check(a_hit > 0.5, "boss 在 x=+20 → 北墙该处有剪影（%.2f）" % a_hit)
	_check(a_miss < 0.1, "x=-20 处没有剪影（%.2f，说明没镜像/没错位）" % a_miss)
	_check(absf(uv.y - 1.0) < 0.02, "脚（y=0）落在墙面底部 v≈1.0（%.3f）" % uv.y)
	# 垂直方向：头顶应在墙高的 9.1/19 ≈ 0.48 附近有剪影，墙顶没有
	var head_uv: Vector2 = _ws.mask_uv_of(0, Vector3(20, 9.0, 0))
	var top_uv: Vector2 = _ws.mask_uv_of(0, Vector3(20, 18.0, 0))
	_check(absf(head_uv.y - (1.0 - 9.0 / 19.0)) < 0.03, "y=9 映射到 v=%.2f" % head_uv.y)
	_check(_ws.mask_alpha_at(0, Vector3(20, 18.0, 0)) < 0.1, "墙顶（y=18）没有剪影")
	# 墙 2（西墙，法线 +x）：同一个 boss 的剪影在 z=0 附近
	_place(boss, Vector3(0, 0, 30))
	await _frames(4)
	var b_hit: float = _ws.mask_alpha_at(2, Vector3(0, 3, 30))
	var b_miss: float = _ws.mask_alpha_at(2, Vector3(0, 3, -30))
	_check(b_hit > 0.5, "西墙按世界 z 投影（z=30 有剪影 %.2f）" % b_hit)
	_check(b_miss < 0.1, "西墙 z=-30 没有剪影（%.2f）" % b_miss)


# ------------------------------------------------------------------ E 开关
func _phase_toggles() -> void:
	print("\n--- E enabled / intensity / softness / caster_scale ---")
	_ws.set_intensity(0.33)
	_ws.set_softness(0.9)
	_ws.refresh()
	await _frames(1)
	var m: ShaderMaterial = _ws._quads[0].material_override
	_check(absf(float(m.get_shader_parameter("intensity")) - 0.33) < 1e-4,
		"intensity 写进 shader（%.2f）" % m.get_shader_parameter("intensity"))
	_check(absf(float(m.get_shader_parameter("soft_radius")) - 0.9 * 3.0) < 1e-4,
		"softness 写进 shader（%.2f texel）" % m.get_shader_parameter("soft_radius"))
	var cov_before: float = _ws.mask_coverage(0)
	_ws.set_caster_scale(1.5)
	_ws.refresh()
	await _frames(4)
	var cov_big: float = _ws.mask_coverage(0)
	_check(cov_big > cov_before * 1.5, "caster_scale 1.5 → 剪影变大（%.4f → %.4f）" % [cov_before, cov_big])
	_ws.set_caster_scale(1.0)
	_ws.refresh()
	await _frames(3)
	_ws.set_enabled(false)
	await _frames(2)
	var q: MeshInstance3D = _ws._quads[0]
	_check(not q.visible, "set_enabled(false) 隐藏剪影 quad")
	_check(_ws._groups[0]["vp"].render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"set_enabled(false) 停掉遮罩渲染（省 GPU）")
	_ws.set_enabled(true)
	_ws.set_intensity(0.66)
	await _frames(3)
	_check(q.visible, "重新打开后剪影恢复")
	# 移出 casters
	var n0: int = _ws.caster_count()
	_ws.remove_caster(_rigs[1])
	await _frames(3)
	_check(_ws.caster_count() == n0 - 1, "remove_caster 生效（%d → %d）" % [n0, _ws.caster_count()])


# ------------------------------------------------------------------ F 健壮性
func _phase_robust() -> void:
	print("\n--- F 健壮性（空槽 / 退化 xform / 无角色）---")
	var ws2 := WallShadow.new()
	add_child(ws2)
	ws2.setup([], {})
	ws2.refresh()
	_check(ws2._quads.is_empty() and ws2._groups.is_empty(), "空 slots 不崩、不建任何东西")
	var bad := [{"xform": Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO), "size": Vector2(10, 10)}]
	var ws3 := WallShadow.new()
	add_child(ws3)
	ws3.setup(bad, {})
	_check(ws3._quads.is_empty(), "退化 xform 的槽位被跳过（不产生 NaN 几何）")
	# 没有 caster 时遮罩为空，但 quad 还在（影子是透明的，不影响画面）
	var cov: float = _ws.mask_coverage(0)
	_check(cov >= 0.0, "遮罩可读回（覆盖率 %.4f）" % cov)


# ------------------------------------------------------------------ helpers
func _make_rig(tag: String, pos: Vector3) -> Node3D:
	var rig = load("res://src/vesper/mech_rig.gd").new()
	rig.auto_step = false
	rig.set_process(false)
	rig.palette = {"tag": tag, "accent": Color(1.0, 0.4, 0.2), "tint": Color(0.9, 0.9, 1.0),
		"metal_mix": 0.2}
	add_child(rig)
	rig.advance(0.0)
	rig.global_position = pos
	return rig


func _place(rig: Node3D, pos: Vector3) -> void:
	rig.global_position = pos
	rig.heading = 0.0
	rig.rotation.y = 0.0
	_ws.refresh()          # 游戏里由 level.step 每帧调用


func _count_meshes(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c += 1
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c


func _count_tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and n.mesh != null:
		var mesh: Mesh = n.mesh
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX] if arr.size() > Mesh.ARRAY_INDEX else null
			t += (idx as PackedInt32Array).size() / 3 if idx is PackedInt32Array else \
				(arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for ch in n.get_children():
		t += _count_tris(ch)
	return t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  ", msg)
	else:
		print("  FAIL  ", msg)
		_fails.append(msg)


func _summary() -> void:
	print("\n== test_shadow: %d checks, %d failed ==" % [_checks, _fails.size()])
	if not _fails.is_empty():
		for f in _fails:
			print("   FAILED: ", f)

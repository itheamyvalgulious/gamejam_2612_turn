extends Node3D
## 防空 / 供能节点的可视状态。
##
## 场景初稿只负责“看起来是通电还是断电”：炮塔红条、闸门光条、供能核心、
## 状态灯都挂在这个节点下。节点带脚本，StaticBatch 会整棵跳过，
## 所以运行时换材质不会打散合批。
##
## 真正的流程（清完一波怪 → 按住清除 3 s）由主程序接；
## 这里只暴露 set_online()，初稿用 F8 预览。

var online := true

var _parts: Array = []
var _lights: Array = []
var _blockers: Array = []


func part(mi: MeshInstance3D, on: Material, off: Material) -> void:
	if mi == null:
		return
	_parts.append({"mi": mi, "on": on, "off": off})
	mi.material_override = on if online else off


## 门面实体碰撞：entry 是 arena["cover"] 里的字典；断电时把 h 归零，
## 玩家就能真正从门里走过去，而不是靠传送。
func blocker(entry: Dictionary) -> void:
	_blockers.append({"e": entry, "h": float(entry.get("h", 0.0))})


func light(l: Light3D, energy: float) -> void:
	if l == null:
		return
	_lights.append({"l": l, "e": energy})
	l.light_energy = energy if online else 0.0


func set_online(on: bool) -> void:
	online = on
	for p in _parts:
		var mi: MeshInstance3D = p["mi"]
		if is_instance_valid(mi):
			mi.material_override = p["on"] if on else p["off"]
	for e in _lights:
		var l: Light3D = e["l"]
		if is_instance_valid(l):
			l.light_energy = e["e"] if on else 0.0
	for b in _blockers:
		var entry: Dictionary = b["e"]
		entry["h"] = float(b["h"]) if on else 0.0

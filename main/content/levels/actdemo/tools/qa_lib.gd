extends RefCounted
class_name QaLog
## QA 输出工具：统一 PASS / FAIL 行格式，方便脚本汇总。

var checks := 0
var fails := 0
var name := ""


func _init(p_name := "") -> void:
	name = p_name


func section(title: String) -> void:
	print("\n---- %s ----" % title)


func ok(cond: bool, label: String, detail := "") -> bool:
	checks += 1
	var d := ("  " + detail) if detail != "" else ""
	if cond:
		print("  PASS  ", label, d)
	else:
		fails += 1
		print("  FAIL  ", label, d)
	return cond


func info(label: String, detail := "") -> void:
	print("  ....  ", label, (("  " + detail) if detail != "" else ""))


func summary() -> int:
	print("\n== %s: %d checks, %d failed ==" % [name, checks, fails])
	return 0 if fails == 0 else 1

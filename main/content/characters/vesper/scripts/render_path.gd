extends RefCounted
## 渲染输出路径。项目整体迁移目录后仍然有效：不再写死任何绝对路径。

## `res://renders` 的绝对路径；目录不存在时按需创建。
static func dir() -> String:
	var d := ProjectSettings.globalize_path("res://renders")
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d


## `res://renders/<name>` 的绝对路径。
static func file(name: String) -> String:
	return dir().path_join(name)


## 把命令行传入的路径解析成绝对路径；相对路径按项目根目录解析。
static func resolve(path: String) -> String:
	if path.is_absolute_path():
		return path
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return ProjectSettings.globalize_path("res://").path_join(path)

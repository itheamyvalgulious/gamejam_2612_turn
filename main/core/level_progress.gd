extends RefCounted

const Catalog = preload("res://core/level_catalog.gd")
const SAVE_PATH := "user://turn_progress.cfg"
const SECTION := "levels"

var _cleared := PackedStringArray()
var _resume_id := ""
var _dirty := false


func load_progress() -> void:
	var save := ConfigFile.new()
	if save.load(SAVE_PATH) != OK:
		return
	var cleared: Variant = save.get_value(SECTION, "cleared", PackedStringArray())
	if cleared is PackedStringArray:
		for id: String in cleared:
			if Catalog.index_for_id(id) >= 0 and not _cleared.has(id):
				_cleared.append(id)
	var resume: Variant = save.get_value(SECTION, "resume", "")
	if resume is String and Catalog.index_for_id(resume) >= 0 and not _cleared.has(resume):
		_resume_id = resume
	elif not _cleared.is_empty():
		_resume_id = _next_unfinished_id(-1)


func resume_index() -> int:
	return Catalog.index_for_id(_resume_id)


func is_cleared(index: int) -> bool:
	return _cleared.has(Catalog.level_id(index))


func cleared_count() -> int:
	return _cleared.size()


func visit(index: int) -> Error:
	var id := Catalog.level_id(index)
	if id != _resume_id and not _cleared.has(id):
		_resume_id = id
		_dirty = true
	return flush()


func complete(index: int) -> Error:
	var id := Catalog.level_id(index)
	if not _cleared.has(id):
		_cleared.append(id)
		if _resume_id.is_empty() or _resume_id == id:
			_resume_id = _next_unfinished_id(index)
		_dirty = true
	return flush()


func flush() -> Error:
	if not _dirty:
		return OK
	var save := ConfigFile.new()
	save.set_value(SECTION, "resume", _resume_id)
	save.set_value(SECTION, "cleared", _cleared)
	var temporary := "%s.%d.tmp" % [SAVE_PATH, OS.get_process_id()]
	var result := save.save(temporary)
	if result == OK:
		result = DirAccess.rename_absolute(temporary, SAVE_PATH)
	if result != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	_dirty = result != OK
	return result


func _next_unfinished_id(after: int) -> String:
	for offset in range(1, Catalog.level_count() + 1):
		var id := Catalog.level_id((after + offset) % Catalog.level_count())
		if not _cleared.has(id):
			return id
	return ""

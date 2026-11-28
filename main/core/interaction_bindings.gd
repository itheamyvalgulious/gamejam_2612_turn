extends RefCounted

# Keep the first level's saved binding available in the other playable levels.
const SAVE_PATH := "user://turn_cargo_interaction.json"


static func load_events(actions: Dictionary, same_desc: Callable) -> Array:
	if FileAccess.file_exists(SAVE_PATH):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if value is Array:
			var saved: Array = []
			for entry in value:
				if entry is Dictionary:
					saved.append({"t": String(entry.get("t", "key")),
						"k": int(entry.get("k", 0)), "b": int(entry.get("b", 0))})
			if saved.is_empty() or not _in_use(saved[0], actions, same_desc):
				return saved
	for key in [KEY_F, KEY_G, KEY_T]:
		var candidate := {"t": "key", "k": key}
		if not _in_use(candidate, actions, same_desc):
			return [candidate]
	return []


static func save_events(events: Array) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(events))


static func _in_use(candidate: Dictionary, actions: Dictionary, same_desc: Callable) -> bool:
	for action in actions:
		if action == "interact":
			continue
		for existing in actions[action]:
			if same_desc.call(candidate, existing):
				return true
	return false

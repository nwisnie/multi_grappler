extends RefCounted
## Local, playable snapshots shared by browsing, hosting, and the pause menu.

signal changed

const SAVE_PATH := "user://saved_levels.json"
var path: String
var load_error := ""
var _levels: Array[Dictionary] = []

func _init(storage_path: String = SAVE_PATH) -> void:
	path = storage_path

func load_levels() -> void:
	_levels.clear()
	load_error = ""
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_error = "Could not read saved levels on this device."
		return
	var payload = JSON.parse_string(file.get_as_text())
	if not payload is Dictionary or payload.get("version") != 1 or not payload.get("levels") is Array:
		load_error = "Saved levels could not be read on this device."
		return
	var seen := {}
	for entry in payload["levels"]:
		if not entry is Dictionary or not entry.get("level_code") is String:
			continue
		var decoded := LevelCodec.decode_level(entry["level_code"])
		if not decoded["error"].is_empty():
			continue
		var document: LevelDocument = decoded["document"]
		if not document.playtest_error().is_empty():
			continue
		var code := LevelCodec.encode_level(document)
		if seen.has(code):
			continue
		seen[code] = true
		_levels.append(_entry(code, entry))

func list_levels() -> Array[Dictionary]:
	return _levels.duplicate(true)

func find_level(document: LevelDocument) -> Dictionary:
	var code := LevelCodec.encode_level(document)
	for entry in _levels:
		if entry["level_code"] == code:
			return entry.duplicate(true)
	return {}

func has_source(id: String) -> bool:
	if id.is_empty():
		return false
	for entry in _levels:
		if entry.get("source_id", "") == id:
			return true
	return false

func save_level(document: LevelDocument, metadata: Dictionary = {}) -> String:
	var problem := document.playtest_error()
	if not problem.is_empty():
		return problem
	# Preserve an unreadable collection instead of replacing it with one level.
	if not load_error.is_empty():
		return load_error
	var code := LevelCodec.encode_level(document)
	var existing := find_level(document)
	var details := existing.duplicate(true)
	for key in ["title", "author", "source_id", "id"]:
		if metadata.get(key) is String and not metadata[key].strip_edges().is_empty():
			details[key] = metadata[key]
	var entry := _entry(code, details)
	var updated: Array[Dictionary] = [entry]
	for saved in _levels:
		if saved["level_code"] != code:
			updated.append(saved)
	# Replace the file only after writing a complete snapshot successfully.
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Could not save this level on this device. Try again."
	file.store_string(JSON.stringify({"version": 1, "levels": updated}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return "Could not save this level on this device. Try again."
	_levels = updated
	changed.emit()
	return ""

func _entry(code: String, metadata: Dictionary) -> Dictionary:
	var title := str(metadata.get("title", "")).replace("\n", " ").replace("\r", " ").strip_edges().left(64)
	return {
		"level_code": code,
		"title": title if not title.is_empty() else "Saved level " + code.sha256_text().left(8),
		"author": str(metadata.get("author", "")).replace("\n", " ").replace("\r", " ").strip_edges().left(32),
		"source_id": str(metadata.get("id", metadata.get("source_id", ""))).left(64),
	}

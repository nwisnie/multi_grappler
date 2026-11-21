extends RefCounted
## Local, playable snapshots scoped to the signed-in account and level service.

signal changed

const SAVE_PATH := "user://saved_levels.json"
const LibraryClient := preload("res://scripts/levels/level_library_client.gd")
var path: String
var load_error := ""
var _levels: Array[Dictionary] = []
var _profiles: Dictionary = {}
var _legacy_levels: Array[Dictionary] = []
var _account: Node
var _scope := ""

func _init(storage_path: String = SAVE_PATH) -> void:
	path = storage_path

func bind_account(account: Node) -> void:
	if is_instance_valid(_account) and _account.changed.is_connected(_account_changed):
		_account.changed.disconnect(_account_changed)
	_account = account
	_account.changed.connect(_account_changed)
	_account_changed()

func _account_key() -> String:
	if not is_instance_valid(_account) or not _account.is_signed_in():
		return ""
	return (LibraryClient.base_url().trim_suffix("/") + "\n" + _account.user_id).sha256_text()

func _account_changed() -> void:
	var scope := _account_key()
	if scope == _scope:
		return
	_scope = scope
	_levels = []
	_levels.assign(_profiles.get(scope, []))
	changed.emit()

func load_levels() -> void:
	_levels = []
	_profiles.clear()
	_legacy_levels.clear()
	load_error = ""
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_error = "Could not read saved levels on this device."
		return
	var payload = JSON.parse_string(file.get_as_text())
	if not payload is Dictionary:
		load_error = "Saved levels could not be read on this device."
		return
	if payload.get("version") == 1 and payload.get("levels") is Array:
		# Earlier files do not identify who saved each level. Keep them unassigned
		# until a signed-in player explicitly imports them into their account.
		_legacy_levels = _validated_levels(payload["levels"])
	elif payload.get("version") == 2 and payload.get("profiles") is Dictionary and payload.get("legacy_levels") is Array:
		for scope in payload["profiles"]:
			if scope is String and scope.length() == 64 and scope.is_valid_hex_number(false) and payload["profiles"][scope] is Array:
				_profiles[scope] = _validated_levels(payload["profiles"][scope])
		_legacy_levels = _validated_levels(payload["legacy_levels"])
	else:
		load_error = "Saved levels could not be read on this device."
		return
	_scope = _account_key()
	_levels.assign(_profiles.get(_scope, []))

func _validated_levels(entries: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for entry in entries:
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
		result.append(_entry(code, entry))
	return result

func list_levels() -> Array[Dictionary]:
	_account_changed()
	return _levels.duplicate(true)

func find_level(document: LevelDocument) -> Dictionary:
	_account_changed()
	var code := LevelCodec.encode_level(document)
	for entry in _levels:
		if entry["level_code"] == code:
			return entry.duplicate(true)
	return {}

func has_source(id: String) -> bool:
	return not find_source(id).is_empty()

func find_source(id: String) -> Dictionary:
	_account_changed()
	if id.is_empty():
		return {}
	for entry in _levels:
		if entry.get("source_id", "") == id:
			return entry.duplicate(true)
	return {}

func save_level(document: LevelDocument, metadata: Dictionary = {}) -> String:
	_account_changed()
	if _scope.is_empty():
		return "Sign in to save levels to your account."
	var problem := document.playtest_error()
	if not problem.is_empty():
		return problem
	# Preserve an unreadable collection instead of replacing it with one level.
	if not load_error.is_empty():
		return load_error
	var code := LevelCodec.encode_level(document)
	var existing := find_level(document)
	var details := existing.duplicate(true)
	for key in ["title", "author", "author_id", "source_id", "id"]:
		if metadata.get(key) is String and not metadata[key].strip_edges().is_empty():
			details[key] = metadata[key]
	var entry := _entry(code, details)
	var updated: Array[Dictionary] = [entry]
	for saved in _levels:
		if saved["level_code"] != code:
			updated.append(saved)
	return _write_levels(updated, _legacy_levels)

func has_legacy_levels() -> bool:
	_account_changed()
	return not _scope.is_empty() and not _legacy_levels.is_empty()

func import_legacy_levels() -> String:
	_account_changed()
	if _scope.is_empty():
		return "Sign in to import earlier saved levels."
	var updated := _levels.duplicate(true)
	var seen := {}
	for entry in updated:
		seen[entry["level_code"]] = true
	for entry in _legacy_levels:
		if not seen.has(entry["level_code"]):
			updated.append(entry)
			seen[entry["level_code"]] = true
	return _write_levels(updated, [])

func _write_levels(updated: Array[Dictionary], legacy: Array[Dictionary]) -> String:
	if not load_error.is_empty():
		return load_error
	var profiles := _profiles.duplicate(true)
	profiles[_scope] = updated
	# Replace the file only after writing a complete snapshot successfully.
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Could not save this level on this device. Try again."
	file.store_string(JSON.stringify({"version": 2, "profiles": profiles, "legacy_levels": legacy}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return "Could not save this level on this device. Try again."
	_levels = updated.duplicate(true)
	_profiles = profiles
	_legacy_levels = legacy
	changed.emit()
	return ""

func _entry(code: String, metadata: Dictionary) -> Dictionary:
	var title := str(metadata.get("title", "")).replace("\n", " ").replace("\r", " ").strip_edges().left(64)
	var source_id := str(metadata.get("id", metadata.get("source_id", ""))).left(64)
	if source_id.is_empty():
		# Published IDs hash the portable payload, including for multiplayer saves
		# that arrive without library metadata or use different compression.
		source_id = LevelCodec.publication_id_from_code(code)
	return {
		"level_code": code,
		"title": title if not title.is_empty() else "Saved level " + code.sha256_text().left(8),
		"author": str(metadata.get("author", "")).replace("\n", " ").replace("\r", " ").strip_edges().left(32),
		"author_id": str(metadata.get("author_id", "")).left(128),
		"source_id": source_id,
	}

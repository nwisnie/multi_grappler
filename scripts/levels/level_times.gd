extends Node
## Shared, account-scoped time summaries. Submissions survive level restarts and exits.

signal changed

const LibraryClient := preload("res://scripts/levels/level_library_client.gd")
const MAX_TIME_MS := 86400000
var summaries: Dictionary = {}
var summary_error := ""
var account: Node
var summary_client: LibraryClient
var _scope := ""
var _level_versions: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	account = get_node("/root/AccountSession")
	account.changed.connect(_account_changed)
	summary_client = LibraryClient.new()
	add_child(summary_client)
	summary_client.completed.connect(_received_summaries)
	_account_changed()

func current_user_id() -> String:
	return account.user_id if account.is_signed_in() else ""

func _account_changed() -> void:
	var scope := LibraryClient.base_url() + "\n" + current_user_id()
	if scope == _scope:
		return
	var had_scope := not _scope.is_empty()
	_scope = scope
	summary_client.cancel()
	summaries.clear()
	_level_versions.clear()
	summary_error = ""
	changed.emit()
	if had_scope:
		summary_client.fetch_levels()

static func format_time(milliseconds: Variant) -> String:
	if typeof(milliseconds) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(milliseconds)) or float(milliseconds) < 0:
		return "-"
	var value := int(milliseconds)
	return "%02d:%02d.%03d" % [value / 60000, (value / 1000) % 60, value % 1000]

func summary(id: String) -> Dictionary:
	return summaries.get(id, {})

func forget_level(id: String) -> void:
	# Pending reads and finishes must not restore a deleted publication's records.
	summary_client.cancel()
	_level_versions[id] = int(_level_versions.get(id, 0)) + 1
	summaries.erase(id)
	changed.emit()

func cache_time(id: String, payload: Dictionary) -> void:
	summaries[id] = {"top_time_ms": payload.get("top_time_ms"), "personal_time_ms": payload.get("personal_time_ms")}
	summary_error = ""
	changed.emit()

func cache_levels(levels: Array) -> void:
	for level in levels:
		if level is Dictionary and level.get("id") is String:
			summaries[level["id"]] = {"top_time_ms": level.get("top_time_ms"), "personal_time_ms": level.get("personal_time_ms")}
	summary_error = ""
	changed.emit()

func refresh_summaries() -> void:
	_account_changed()
	summary_client.fetch_levels()

func _received_summaries(_code: int, payload: Dictionary, error: String) -> void:
	summary_error = error
	if error.is_empty() and not payload.get("levels") is Array:
		summary_error = "Times could not be loaded. Try refreshing."
	if error.is_empty() and payload.get("levels") is Array:
		summaries.clear()
		cache_levels(payload["levels"])
	else:
		changed.emit()

func submit_time(id: String, seconds: float, run_user_id: String, callback: Callable) -> void:
	_account_changed()
	if run_user_id.is_empty() or run_user_id != current_user_id():
		callback.call({}, "Sign in before starting a run to save your time.")
		return
	if not is_finite(seconds) or seconds <= 0.0 or seconds * 1000.0 > MAX_TIME_MS:
		callback.call({}, "This completion time could not be saved.")
		return
	var client := LibraryClient.new()
	add_child(client)
	var scope := _scope
	var version := int(_level_versions.get(id, 0))
	client.completed.connect(func(_code: int, payload: Dictionary, error: String) -> void:
		if scope == _scope:
			if error.is_empty() and version == int(_level_versions.get(id, 0)):
				cache_time(id, payload)
			if callback.is_valid():
				callback.call(payload, error)
		client.queue_free()
	, CONNECT_ONE_SHOT)
	client.submit_time(id, maxi(1, roundi(seconds * 1000.0)))

extends Node
## One in-memory account session shared by Settings and the level editor.
## Passwords are only sent for authentication and are never saved to disk.

signal changed
signal completed(action: String, error: String)

const LibraryClient := preload("res://scripts/levels/level_library_client.gd")
var username := ""
var user_id := ""
var busy := false
var _token := ""
var _endpoint := ""
var _expires_at := 0
var _action := ""
var _request: HTTPRequest
var _request_endpoint := ""
var _request_url := ""
var _check_elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_request = HTTPRequest.new()
	_request.timeout = 20.0
	_request.max_redirects = 0
	_request.body_size_limit = 8192
	_request.request_completed.connect(_received)
	add_child(_request)

func _process(delta: float) -> void:
	_check_elapsed += delta
	if _check_elapsed >= 1.0:
		_check_elapsed = 0.0
		if not _token.is_empty() and not is_signed_in():
			invalidate()

static func secure_endpoint(url: String) -> bool:
	if url.begins_with("https://"):
		return true
	if not url.begins_with("http://"):
		return false
	var authority := url.trim_prefix("http://").get_slice("/", 0)
	var local_host := RegEx.new()
	local_host.compile("^(localhost|127\\.0\\.0\\.1|\\[::1\\])(:[0-9]{1,5})?$")
	return local_host.search(authority) != null

func is_signed_in() -> bool:
	return not _token.is_empty() and _expires_at > int(Time.get_unix_time_from_system()) and _endpoint == LibraryClient.base_url()

func authorization_header() -> String:
	return "Authorization: Bearer " + _token if is_signed_in() else ""

func sign_in(name: String, password: String) -> void:
	_send("login", {"username": name.strip_edges(), "password": password})

func create_account(name: String, password: String) -> void:
	_send("register", {"username": name.strip_edges(), "password": password})

func sign_out() -> void:
	if busy:
		return
	var authorization := authorization_header()
	_send("logout", {}, authorization)
	# Clear local access immediately, including when the server is unreachable.
	invalidate()

func invalidate() -> void:
	username = ""
	user_id = ""
	_token = ""
	_endpoint = ""
	_expires_at = 0
	changed.emit()

func cancel_authentication() -> void:
	if _action in ["login", "register"]:
		_request.cancel_request()
		_action = ""
		busy = false
		changed.emit()

func _send(action: String, body: Dictionary, authorization: String = "") -> void:
	if busy:
		completed.emit(action, "An account request is already in progress.")
		return
	var endpoint := LibraryClient.base_url()
	if not endpoint.ends_with("/levels") or not secure_endpoint(endpoint):
		completed.emit(action, "Accounts require an HTTPS library URL, or localhost for testing.")
		return
	_action = action
	_request_endpoint = endpoint
	busy = true
	changed.emit()
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not authorization.is_empty():
		headers.append(authorization)
	_request_url = endpoint.trim_suffix("/levels") + "/auth/" + action
	var error := _request.request(_request_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		_finish("Could not start the account request: %s." % error_string(error))

func _received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish(LibraryClient.connection_error(result, _request_url, "Account service"))
		return
	var payload = JSON.parse_string(body.get_string_from_utf8())
	if not payload is Dictionary:
		_finish("The account service returned an invalid response.")
		return
	if response_code < 200 or response_code >= 300:
		_finish(str(payload.get("error", "The account service is unavailable.")).left(300))
		return
	if _action in ["login", "register"] and _request_endpoint != LibraryClient.base_url():
		_finish("The account service URL changed. Please sign in again.")
		return
	if _action in ["login", "register"] and not _apply_session(payload):
		_finish("The account service returned an invalid session.")
		return
	_finish("")

func _apply_session(payload: Dictionary) -> bool:
	if not payload.get("user") is Dictionary or not payload.get("token") is String or typeof(payload.get("expires_at")) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var user: Dictionary = payload["user"]
	var token: String = payload["token"]
	var expiry := int(float(payload["expires_at"]) / 1000.0)
	if not user.get("username") is String or not user.get("id") is String or token.length() != 64 or not token.is_valid_hex_number(false) or expiry <= int(Time.get_unix_time_from_system()):
		return false
	username = user["username"]
	user_id = user["id"]
	_token = token
	_endpoint = LibraryClient.base_url()
	_expires_at = expiry
	changed.emit()
	return true

func _finish(error: String) -> void:
	var action := _action
	_action = ""
	busy = false
	changed.emit()
	completed.emit(action, error)

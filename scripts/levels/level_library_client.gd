extends Node
## Public browsing and authenticated uploads through the Worker.

signal completed(response_code: int, payload: Dictionary, error: String)

const SessionScript := preload("res://scripts/network/network_session.gd")
var request: HTTPRequest
var _request_url := ""

func _ready() -> void:
	request = HTTPRequest.new()
	request.timeout = 15.0
	request.max_redirects = 0
	request.body_size_limit = 131072
	request.request_completed.connect(_received)
	add_child(request)

static func base_url() -> String:
	var configured := str(ProjectSettings.get_setting("network/level_library_url", ""))
	if OS.has_feature("web"):
		var override = JavaScriptBridge.eval("window.MULTI_GRAPPLER_LEVELS_URL || ''")
		if override is String and not override.is_empty():
			configured = override
	if not configured.is_empty():
		return local_url(configured.trim_suffix("/"))
	return local_url(SessionScript.lobby_list_url(SessionScript.default_url()).trim_suffix("/lobbies") + "/levels")

static func local_url(url: String) -> String:
	# Use the same explicit loopback address as Wrangler on Windows and Linux.
	# Leave HTTPS hostnames intact so certificate validation is unchanged.
	if not url.begins_with("http://"):
		return url
	var authority := url.substr(7).get_slice("/", 0)
	var local_host := RegEx.new()
	local_host.compile("^localhost(:[0-9]{1,5})?$")
	if local_host.search(authority) != null:
		return "http://127.0.0.1" + authority.trim_prefix("localhost") + url.substr(7 + authority.length())
	return url

static func connection_error(result: int, url: String, service: String) -> String:
	# Do not expose URL credentials, query strings, or fragments in error messages.
	var address := url.get_slice("?", 0).get_slice("#", 0)
	var scheme_end := address.find("://")
	if scheme_end >= 0:
		var rest := address.substr(scheme_end + 3)
		var authority := rest.get_slice("/", 0)
		if authority.contains("@"):
			address = address.left(scheme_end + 3) + authority.get_slice("@", authority.get_slice_count("@") - 1) + rest.substr(authority.length())
	var reason := "request failed"
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			reason = "could not connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			reason = "could not resolve the hostname"
		HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_NO_RESPONSE:
			reason = "the connection closed without a complete response"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			reason = "HTTPS connection failed; check the server URL and certificate"
		HTTPRequest.RESULT_TIMEOUT:
			reason = "the request timed out"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			reason = "the server redirected the request; use its final URL"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			reason = "the server response was too large"
	var message := "%s: %s. Server: %s" % [service, reason, address]
	if OS.is_debug_build():
		message += " (HTTP result %d)" % result
	if url.begins_with("http://127.0.0.1:"):
		message += ". Check that npm run dev is running on this computer at this address."
	return message

func fetch_levels() -> void:
	_send("")

func fetch_level(id: String) -> void:
	_send("/" + id.uri_encode())

func upload_level(title: String, code: String) -> void:
	_send("", HTTPClient.METHOD_POST, JSON.stringify({"title": title, "level_code": code}))

func cancel() -> void:
	request.cancel_request()

func _send(path: String, method: int = HTTPClient.METHOD_GET, body: String = "") -> void:
	cancel()
	var url := base_url()
	if not url.begins_with("https://") and not url.begins_with("http://"):
		completed.emit(0, {}, "The level library URL must use http:// or https://.")
		return
	var headers := PackedStringArray(["Content-Type: application/json"]) if method == HTTPClient.METHOD_POST else PackedStringArray()
	if method == HTTPClient.METHOD_POST:
		var account := get_node_or_null("/root/AccountSession")
		if account == null or not account.is_signed_in():
			completed.emit(401, {}, "Sign in or create an account to upload levels.")
			return
		if not account.secure_endpoint(url):
			completed.emit(0, {}, "Account uploads require HTTPS, or localhost for testing.")
			return
		headers.append(account.authorization_header())
	_request_url = url + path
	var error := request.request(_request_url, headers, method, body)
	if error != OK:
		completed.emit(0, {}, "Could not start the level library request: %s." % error_string(error))

func _received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		completed.emit(response_code, {}, connection_error(result, _request_url, "Level library"))
		return
	var decoded = JSON.parse_string(body.get_string_from_utf8())
	if not decoded is Dictionary:
		completed.emit(response_code, {}, "The level library returned an invalid response. Try again later.")
		return
	var payload: Dictionary = decoded
	var error := ""
	if response_code < 200 or response_code >= 300:
		error = str(payload.get("error", "The level library is unavailable. Try again later.")).left(300)
	completed.emit(response_code, payload, error)

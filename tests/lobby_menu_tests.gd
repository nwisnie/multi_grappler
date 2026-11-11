extends SceneTree

class CaptureSession extends NetworkSession:
	func host_game(_url: String, level_code: String, limit: int, game_name: String, is_public: bool = false) -> void:
		request = {"type": "create", "level_code": level_code, "max_players": limit, "name": game_name, "public": is_public}
	func join_game(_url: String, code: String) -> void:
		request = {"type": "join", "room": code}

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	check(NetworkSession.lobby_list_url("ws://localhost:9080/") == "http://localhost:9080/lobbies", "Local lobby browsing uses HTTP")
	check(NetworkSession.lobby_list_url("wss://rooms.wizkinews.com") == "https://rooms.wizkinews.com/lobbies", "Public lobby browsing uses HTTPS")
	check(NetworkSession.lobby_list_url("bad-url").is_empty(), "Invalid lobby directory URL is rejected")
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	var original_session = shell.session
	var session := CaptureSession.new()
	shell.session = session
	check(not shell.host_visibility.button_pressed and shell.host_visibility.text == "Private (join by code only)", "Host menu defaults to private")
	var document := LevelDocument.new()
	document.spawn = Vector2i(12, 8)
	shell.host_level_code.text = LevelCodec.encode_level(document)
	shell.host_visibility.button_pressed = true
	shell.host_visibility.pressed.emit()
	shell._submit_host()
	check(session.request.get("public") == true and shell.host_visibility.text == "Public (anyone can join)", "Public host button updates its description and the room request")
	shell.host_visibility.button_pressed = false
	shell.host_visibility.pressed.emit()
	shell._submit_host()
	check(session.request.get("public") == false and shell.host_visibility.text == "Private (join by code only)", "Private host button updates its description and the room request")
	shell.show_join_menu()
	shell.loading_screen.hide()
	shell._cancel_lobby_refresh()
	var rooms := {"rooms": [
		{"room": "00123456", "name": "Open race", "players": 1, "max_players": 4},
		{"room": "00987654", "name": "Full race", "players": 2, "max_players": 2},
		{"room": "bad", "name": "Invalid", "players": 1, "max_players": 4},
		{"room": "11111111", "name": "Invalid", "players": {}, "max_players": 4},
	]}
	shell._public_lobbies_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(rooms).to_utf8_buffer())
	check(shell.public_lobbies.get_child_count() == 2, "Lobby browser displays valid rooms and rejects malformed entries")
	check(shell.public_lobbies.get_child(0).text.contains("Open race") and shell.public_lobbies.get_child(0).text.contains("1/4"), "Lobby rows show the game name and capacity")
	check(shell.public_lobbies.get_child(1).disabled and shell.public_lobbies.get_child(1).text.contains("Full"), "Full lobbies are visible and cannot be selected")
	shell.public_lobbies.get_child(0).pressed.emit()
	check(session.request == {"type": "join", "room": "00123456"}, "Selecting a public room joins it and preserves leading zeroes")
	check(shell.loading_screen.visible and shell.pending_room_code == "00123456", "Public joins use the normal loading and join flow")
	shell.show_join_menu()
	shell.loading_screen.hide()
	shell._cancel_lobby_refresh()
	shell._public_lobbies_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"rooms":[]}'.to_utf8_buffer())
	check(shell.public_lobbies.get_child_count() == 0 and shell.public_lobby_status.text.contains("No public"), "Empty public directory has an actionable message")
	shell._public_lobbies_received(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	check(shell.public_lobby_status.text.contains("join by code") and not shell.refresh_lobbies_button.disabled, "Directory errors preserve code joining and allow retry")
	shell.room_code.text = "00001111"
	shell._submit_join()
	check(session.request == {"type": "join", "room": "00001111"}, "Manual code joining remains available")
	shell.session = original_session
	session.free()
	shell.free()
	await process_frame
	print("LOBBY MENUS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

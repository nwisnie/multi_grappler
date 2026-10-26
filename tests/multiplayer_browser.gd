extends Node
## Test-only browser entry point. Export via the temporary project described in README.

var shell: Node
var error_message := ""
var loading_seen := false

func _ready() -> void:
	ProjectSettings.set_setting("network/signaling_url", "ws://127.0.0.1:9080")
	shell = preload("res://scenes/game_shell.tscn").instantiate()
	add_child(shell)
	shell.session.session_ended.connect(func(reason: String) -> void: error_message = reason)
	var role = JavaScriptBridge.eval("new URLSearchParams(location.search).get('role') || 'host'")
	if role == "menus":
		shell.show_host_menu()
	elif role == "host":
		var document := LevelDocument.new()
		document.spawn = Vector2i(12, 8)
		document.segments.append({"kind": 0, "a": Vector2i(1, 10), "b": Vector2i(90, 10)})
		shell.host_level_code.text = LevelCodec.encode_level(document)
		shell._submit_host()
	else:
		shell.room_code.text = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('room') || ''"))
		shell._submit_join()
	loading_seen = shell.loading_screen.visible

func _process(_delta: float) -> void:
	loading_seen = loading_seen or shell.loading_screen.visible
	var command = JavaScriptBridge.eval("window.multiplayerCommand || ''")
	if command is String and not command.is_empty():
		JavaScriptBridge.eval("window.multiplayerCommand = ''")
		match command:
			"pause": shell.pause_game()
			"resume": shell.resume_game()
			"leave": shell.show_main_menu()
			"respawn": shell._player().position = Vector2(-200, -200)
	var state := {"room": shell.session.room, "error": error_message, "paused": get_tree().paused, "menu": shell.pause_dialog.visible, "players": {}}
	state["host_dialog_fits"] = shell.host_dialog.size.y <= get_viewport().get_visible_rect().size.y and shell.host_dialog.position.y >= 0
	state["room_card_text"] = shell.copy_room_button.text
	state["loading"] = shell.loading_screen.visible
	state["loading_seen"] = loading_seen
	state["room_card_fits"] = get_viewport().get_visible_rect().encloses(shell.room_card.get_global_rect()) and shell.room_card.size.x <= 320
	if is_instance_valid(shell.world) and shell.world.get("players") != null:
		for ball in shell.world.players.get_children():
			state["players"][str(ball.name)] = {"x": ball.position.x, "y": ball.position.y, "local": ball.is_multiplayer_authority(), "camera": ball.camera.enabled, "locked": ball.controls_locked, "grapple": ball.network_grapple_active, "name_upright": is_zero_approx(ball.nameplate.global_rotation), "name_above": ball.nameplate.global_position.y < ball.global_position.y - 60}
	JavaScriptBridge.eval("window.multiplayerState = " + JSON.stringify(state))

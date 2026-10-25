extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func key(shell: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	shell._unhandled_input(event)

func _run() -> void:
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	check(shell.title_screen.visible and shell.world == null, "Start on title, without running tutorial")
	check(shell.title_screen.tutorial_button.text == "Tutorial" and shell.title_screen.editor_button.text == "Level Editor", "Title has tutorial and editor routes")
	# Real GUI pointer/key events must share a persistent selection.
	shell.title_screen.tutorial_button.grab_focus()
	var pointer := InputEventMouseMotion.new()
	pointer.position = shell.title_screen.host_button.get_global_rect().get_center()
	root.push_input(pointer, true)
	await process_frame
	check(shell.title_screen.host_button.has_focus(), "Hover replaces previous keyboard selection")
	pointer = InputEventMouseMotion.new()
	pointer.position = Vector2(10, 10)
	root.push_input(pointer, true)
	await process_frame
	check(shell.title_screen.host_button.has_focus(), "Mouse selection persists after leaving a button")
	var arrow := InputEventKey.new()
	arrow.keycode = KEY_UP
	arrow.pressed = true
	root.push_input(arrow, true)
	arrow = InputEventKey.new()
	arrow.keycode = KEY_UP
	arrow.pressed = false
	root.push_input(arrow, true)
	await process_frame
	check(shell.title_screen.join_button.has_focus(), "Arrow navigation continues from last mouse selection")
	pointer = InputEventMouseMotion.new()
	pointer.position = shell.title_screen.editor_button.get_global_rect().get_center()
	root.push_input(pointer, true)
	await process_frame
	pointer = InputEventMouseMotion.new()
	pointer.position = Vector2(10, 10)
	root.push_input(pointer, true)
	await process_frame
	check(shell.title_screen.editor_button.has_focus(), "New hover selection does not revert to arrow selection")
	shell.title_screen.join_button.pressed.emit()
	check(shell.join_dialog.visible and shell.join_dialog.exclusive and shell.dimmer.visible, "Join opens modal popup")
	for invalid in ["", "1234567", "123456789", "abcdefgh", "+1234567", "1234 678"]:
		check(not shell.valid_room_code(invalid), "Reject malformed room code: " + invalid)
	shell.room_code.text = "00123456"
	shell._submit_join()
	check(shell.pending_room_code == "00123456", "Room code preserves leading zeroes")
	check(shell.world == null and shell.join_message.text.contains("not available"), "Join does not simulate an unimplemented connection")
	shell.join_dialog.hide()
	shell.join_dialog.canceled.emit()
	check(not shell.dimmer.visible, "Closing title popup removes dimmer")
	shell.title_screen.host_button.pressed.emit()
	check(shell.host_dialog.visible and shell.host_player_limit.value == 4, "Host has initial setup form")
	check(shell.host_dialog.get_ok_button().disabled, "Room creation is clearly unavailable")
	shell.host_dialog.hide()
	shell.title_screen.tutorial_button.pressed.emit()
	await physics_frame
	check(shell.world != null and not shell.title_screen.visible, "Tutorial opens base level")
	check(shell._player() != null and not shell.has_node("Navigation"), "Gameplay has a player and no top navigation")
	key(shell, KEY_ESCAPE)
	check(paused and shell.pause_dialog.visible and shell._player().controls_locked, "Escape freezes gameplay and opens pause menu")
	var position: Vector2 = shell._player().position
	for frame in range(4):
		await physics_frame
	check(shell._player().position == position, "Physics remains frozen while paused")
	shell.show_settings()
	check(paused and shell.settings_dialog.visible and not shell.pause_dialog.visible, "Settings stays paused")
	shell.camera_zoom_slider.value = 0.57
	shell.wall_cursor_toggle.button_pressed = true
	check(shell._player().initial_camera_zoom == Vector2.ONE * 0.57 and shell._player().show_grapple_cursor, "Settings update player")
	shell._close_settings()
	check(paused and shell.pause_dialog.visible, "Back from settings returns to paused menu")
	key(shell, KEY_ESCAPE)
	await process_frame
	await process_frame
	check(not paused and not shell.pause_dialog.visible and not shell._player().controls_locked, "Escape resumes gameplay")
	key(shell, KEY_P)
	check(paused and shell.pause_dialog.visible, "P is an alternative pause key")
	var held_space := InputEventKey.new()
	held_space.keycode = KEY_SPACE
	held_space.pressed = true
	Input.parse_input_event(held_space)
	Input.flush_buffered_events()
	shell.resume_game()
	await process_frame
	await process_frame
	check(shell._player().controls_locked, "Held grapple key cannot fire after menu resume")
	held_space.pressed = false
	Input.parse_input_event(held_space)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	check(not shell._player().controls_locked, "Controls resume once held key is released")
	shell.show_main_menu()
	check(not paused and shell.world == null and shell.title_screen.visible, "Return to main menu clears pause and disposes world")
	shell.title_screen.editor_button.pressed.emit()
	await process_frame
	await process_frame
	var document := LevelDocument.new()
	document.spawn = Vector2i(12, 8)
	document.segments.append({"kind": 0, "a": Vector2i(10, 10), "b": Vector2i(20, 10)})
	shell.editor._commit(document)
	var code := LevelCodec.encode_level(shell.editor.document)
	shell.editor.exit_requested.emit()
	check(shell.title_screen.visible and LevelCodec.encode_level(shell.editor.document) == code, "Editor main menu preserves draft")
	shell.show_editor()
	shell.playtest(document.copy())
	await physics_frame
	check(shell.world is CustomLevel and shell._player().show_grapple_cursor, "Playtest uses session settings")
	check(shell._player().initial_camera_zoom == Vector2.ONE * 0.57, "Playtest uses selected zoom")
	shell.pause_game()
	check(shell.pause_editor_button.visible and shell.pause_restart_button.visible, "Playtest pause retains return/restart options")
	var player_id: int = shell._player().get_instance_id()
	shell._restart_playtest()
	check(not paused and shell._player().get_instance_id() != player_id, "Restart from pause creates a fresh player")
	check(shell._player().initial_camera_zoom == Vector2.ONE * 0.57 and shell._player().show_grapple_cursor, "Respawn preserves settings")
	shell.pause_game()
	shell.show_editor()
	check(not paused and LevelCodec.encode_level(shell.editor.document) == code, "Back to editor unpauses and preserves draft")
	key(shell, KEY_ESCAPE)
	check(not paused, "Editor Escape does not open gameplay pause menu")
	shell.show_demo()
	shell.pause_game()
	shell.free()
	await process_frame
	check(not paused, "Removing shell clears paused state")
	print("MENUS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

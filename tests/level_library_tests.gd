extends SceneTree

const Client := preload("res://scripts/levels/level_library_client.gd")
var account_session: Node
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
	account_session = root.get_node("AccountSession")
	ProjectSettings.set_setting("network/level_library_url", "invalid-url")
	account_session.invalidate()
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	shell.title_screen.editor_button.pressed.emit()
	check(shell.title_screen.editor_actions.visible and shell.editor == null, "Level Editor opens submenu")
	shell.title_screen.browse_levels_button.pressed.emit()
	check(shell.level_browser.visible and not shell.title_screen.visible and shell.world == null, "Browse opens its own screen")
	check(shell.level_browser.status.text.contains("http"), "Browser displays connection/configuration errors")
	shell.level_browser._received(200, {"levels": []}, "")
	check(shell.level_browser.status.text.contains("No levels"), "Empty library has a useful message")
	var id := "a".repeat(64)
	shell.level_browser._received(200, {"levels": [{"id": id, "title": "Community course", "author": "Tester", "created_at": "2026-11-10T00:00:00Z"}, {"id": "bad", "title": "Bad"}]}, "")
	check(shell.level_browser.rows.get_child_count() == 1, "Browser lists valid metadata and ignores malformed IDs")
	check(shell.level_browser.status.text.contains("1 / 100"), "Browser shows library capacity")
	key(shell, KEY_ESCAPE)
	check(shell.title_screen.editor_actions.visible and not shell.level_browser.visible, "Escape returns browser to submenu")
	shell.title_screen.create_level_button.pressed.emit()
	await process_frame
	var editor: GridLevelEditor = shell.editor
	editor._open_upload()
	check(editor.account_dialog.visible and not editor.upload_dialog.visible, "Upload prompts signed-out players to sign in or create an account")
	editor.account_dialog.dismiss()
	account_session._apply_session({"user": {"id": "test-user", "username": "Tester"}, "token": "b".repeat(64), "expires_at": (Time.get_unix_time_from_system() + 3600) * 1000})
	editor._open_upload()
	check(not editor.upload_dialog.visible, "Uploading requires a playable spawn")
	var document := LevelDocument.new()
	document.spawn = Vector2i(10, 2)
	document.segments.append({"kind": 0, "a": Vector2i(0, 5), "b": Vector2i(100, 5)})
	document.segments.append({"kind": 1, "a": Vector2i(10, 20), "b": Vector2i(20, 20), "m": Vector2i(15, 15)})
	document.orbs.append(Vector2i(25, 25))
	document.checkpoints.assign([Vector2i(20, 10), Vector2i(30, 10)])
	document.race_laps = 3
	editor._commit(document)
	var draft := LevelCodec.encode_level(editor.document)
	editor._open_upload()
	await process_frame
	await process_frame
	await process_frame
	check(editor.upload_dialog.visible and editor.upload_code == draft, "Upload captures a playable level snapshot")
	check(editor.upload_dialog.size.y < root.get_visible_rect().size.y, "Upload dialog and action buttons fit in viewport")
	editor._submit_upload()
	check(editor.upload_message.text.contains("name"), "Upload requires a level name")
	editor.upload_title.text = "Test course"
	editor._submit_upload()
	check(not editor.uploading and not editor.upload_dialog.get_ok_button().disabled, "Connection error permits upload retry")
	editor._upload_completed(409, {}, "The level library is full (100/100).")
	check(editor.upload_message.text.contains("full") and LevelCodec.encode_level(editor.document) == draft, "Library full preserves draft and displays error")
	editor._upload_completed(201, {"id": id}, "")
	check(editor.upload_message.text.contains("published") and editor.upload_dialog.get_ok_button().disabled, "Successful upload confirms publication")
	editor.upload_dialog.hide()
	shell.show_level_browser()
	check(not editor.visible and not editor.upload_dialog.visible, "Browsing suspends editor and its dialogs")
	shell.level_browser.loading_level = true
	shell.level_browser._received(200, {"level": {"level_code": draft}}, "")
	await physics_frame
	check(shell.screen == shell.Screen.COMMUNITY_LEVEL and shell.world is CustomLevel, "Downloaded community level opens in gameplay")
	check(LevelCodec.encode_level(editor.document) == draft, "Playing a published level preserves editor draft")
	shell.pause_game()
	check(paused and shell.pause_browser_button.visible and shell.pause_restart_button.visible and not shell.pause_editor_button.visible, "Community pause offers browser and restart")
	shell.pause_browser_button.pressed.emit()
	check(not paused and shell.level_browser.visible and shell.world == null, "Returning to browser clears gameplay and pause")
	shell._leave_level_browser()
	shell.title_screen.create_level_button.pressed.emit()
	check(LevelCodec.encode_level(editor.document) == draft, "Create New opens existing editor without discarding draft")
	var endpoint := OS.get_environment("LEVEL_LIBRARY_TEST_URL")
	if not endpoint.is_empty():
		await _http_checks(shell, endpoint, draft)
	shell.free()
	account_session.invalidate()
	await process_frame
	print("LEVEL LIBRARY: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _http_checks(shell: Node, endpoint: String, code: String) -> void:
	ProjectSettings.set_setting("network/level_library_url", endpoint)
	var editor: GridLevelEditor = shell.editor
	account_session.invalidate()
	editor._open_upload()
	check(editor.account_dialog.visible, "Real upload begins with the account prompt")
	var account = editor.account_dialog
	account._show_form(true)
	account.username_input.text = "Grappler%d" % (Time.get_ticks_usec() % 100000000)
	account.password_input.text = "Godot integration password."
	account.confirm_password.text = account.password_input.text
	account._submit()
	var deadline := Time.get_ticks_msec() + 22000
	while account_session.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(account_session.is_signed_in(), "Godot creates a D1 account: " + account.message.text)
	check(not account.visible and editor.upload_dialog.visible, "Account creation returns to the upload form")
	check(editor.upload_author.text.contains(account_session.username), "Upload shows the authenticated username")
	if not account_session.is_signed_in():
		return
	var login_name: String = account_session.username
	editor._open_upload()
	editor.upload_title.text = "Godot integration course"
	editor._submit_upload()
	deadline = Time.get_ticks_msec() + 18000
	while editor.uploading and Time.get_ticks_msec() < deadline:
		await process_frame
	check(editor.upload_message.text.contains("published"), "Godot uploads its real MG1 code through HTTP to D1: " + editor.upload_message.text)
	editor.upload_dialog.hide()
	shell.show_level_browser()
	deadline = Time.get_ticks_msec() + 18000
	while shell.level_browser.refresh_button.disabled and Time.get_ticks_msec() < deadline:
		await process_frame
	check(shell.level_browser.rows.get_child_count() > 0, "Godot browses real D1 records: " + shell.level_browser.status.text)
	if shell.level_browser.play_buttons.is_empty():
		return
	shell.level_browser.play_buttons[0].pressed.emit()
	deadline = Time.get_ticks_msec() + 18000
	while shell.screen == shell.Screen.LEVEL_BROWSER and shell.level_browser.refresh_button.disabled and Time.get_ticks_msec() < deadline:
		await process_frame
	check(shell.screen == shell.Screen.COMMUNITY_LEVEL, "Godot downloads and plays uploaded D1 level: " + shell.level_browser.status.text)
	check(LevelCodec.encode_level(shell.editor.document) == code, "HTTP round trip preserves editor draft")
	account_session.sign_out()
	deadline = Time.get_ticks_msec() + 22000
	while account_session.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not account_session.is_signed_in(), "Godot signs out through the Worker")
	shell.show_main_menu()
	shell.show_settings()
	shell.account_sign_in.pressed.emit()
	var settings_account = shell.account_dialog
	settings_account._show_form(false)
	settings_account.username_input.text = login_name
	settings_account.password_input.text = "Godot integration password."
	settings_account._submit()
	deadline = Time.get_ticks_msec() + 22000
	while account_session.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(account_session.is_signed_in() and shell.settings_dialog.visible and shell.account_sign_out.visible, "Settings signs in and displays the account: " + settings_account.message.text)
	shell.account_sign_out.pressed.emit()
	deadline = Time.get_ticks_msec() + 22000
	while account_session.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not account_session.is_signed_in() and shell.account_sign_in.visible, "Settings signs out and restores sign-in")

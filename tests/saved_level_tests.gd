extends SceneTree

const SavedLevels := preload("res://scripts/levels/saved_levels.gd")
const TEST_PATH := "res://build/saved-level-tests.json"

class CaptureLibrary extends "res://scripts/levels/level_library_client.gd":
	var fetched_id := ""
	func fetch_levels() -> void:
		pass
	func fetch_level(id: String) -> void:
		fetched_id = id

class CaptureSession extends NetworkSession:
	func host_game(_url: String, code: String, limit: int, game_name: String, is_public: bool = false) -> void:
		request = {"level_code": code, "max_players": limit, "name": game_name, "public": is_public}

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
	preload("res://scripts/ui/menu_slide.gd").duration_scale = 0.0
	ProjectSettings.set_setting("network/level_library_url", "http://127.0.0.1:9080/levels")
	var account := root.get_node("AccountSession")
	account._apply_session({"user": {"id": "saved-test-user", "username": "Tester"}, "token": "b".repeat(64), "expires_at": (Time.get_unix_time_from_system() + 3600) * 1000})
	DirAccess.remove_absolute(TEST_PATH)
	var store := SavedLevels.new(TEST_PATH)
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.saved_levels = store
	root.add_child(shell)
	await process_frame
	await process_frame
	var browser = shell.level_browser
	var original_client = browser.client
	browser.remove_child(original_client)
	original_client.free()
	var client := CaptureLibrary.new()
	browser.client = client
	browser.add_child(client)
	client.completed.connect(browser._received)
	var original_session = shell.session
	var session := CaptureSession.new()
	shell.session = session
	var id := "a".repeat(64)
	var metadata := {"id": id, "title": "Saved community race", "author": "Tester"}
	var document := LevelDocument.new()
	document.spawn = Vector2i(10, 2)
	document.segments.append({"kind": 0, "a": Vector2i(0, 5), "b": Vector2i(100, 5)})
	document.checkpoints.assign([Vector2i(20, 10), Vector2i(30, 10)])
	document.race_laps = 3
	var code := LevelCodec.encode_level(document)
	var level := {"level": {"id": id, "title": metadata["title"], "author": "Tester", "level_code": code}}

	shell.show_host_menu()
	check(shell.host_dialog.get_ok_button().disabled, "Hosting requires an explicit level selection")
	shell.host_saved_button.pressed.emit()
	check(browser.visible and browser.current_view == browser.View.SAVED and browser.rows.get_child_count() == 0 and browser.status.text.contains("No saved"), "Saved view explains how to save a first level")
	browser.back_button.pressed.emit()
	check(shell.host_dialog.visible and shell.dimmer.visible, "Back from saved picker returns to the host form")

	shell.show_level_browser()
	client.completed.emit(200, {"levels": [metadata]}, "")
	check(browser.play_buttons[0].text == "Play" and browser.save_buttons[id].text == "Save", "Community row offers Save next to Play")
	browser.save_buttons[id].pressed.emit()
	check(client.fetched_id == id and browser.refresh_button.disabled and browser.play_buttons[0].disabled and browser.save_buttons[id].disabled, "Saving downloads the level and locks row actions until completion")
	client.completed.emit(200, level, "")
	check(shell.screen == shell.Screen.LEVEL_BROWSER and shell.world == null, "Saving keeps the player in the browser")
	check(store.list_levels().size() == 1 and browser.status.text.contains("saved"), "Saving records a playable snapshot and confirms success")
	check(not browser.save_buttons.has(id) and browser.rows.get_child_count() == 0, "Saving immediately removes the row from the community list")
	browser.saved_button.pressed.emit()
	check(browser.rows.get_child_count() == 1 and browser.save_buttons.is_empty() and not browser.play_buttons[0].disabled, "Saved view lists the local copy with Play and no duplicate Save action")
	var reopened := SavedLevels.new(TEST_PATH)
	reopened.bind_account(account)
	reopened.load_levels()
	check(reopened.list_levels().size() == 1 and reopened.list_levels()[0]["level_code"] == code, "Saved terrain and race data survive reloading the file")
	check(reopened.list_levels()[0]["title"] == metadata["title"] and reopened.list_levels()[0]["author"] == "Tester", "Published names and authors survive reloading")
	check(store.save_level(document).is_empty() and store.list_levels().size() == 1 and store.list_levels()[0]["title"] == metadata["title"], "Saving the same document again keeps one entry and preserves its title")

	shell.show_main_menu()
	shell.show_host_menu()
	shell.host_name.text = "Friday race"
	shell.host_player_limit.value = 7
	shell.host_visibility.button_pressed = true
	shell.host_visibility.pressed.emit()
	shell.host_saved_button.pressed.emit()
	check(browser.rows.get_child_count() == 1 and browser.entries.values()[0]["title"] == metadata["title"], "Host saved view lists saved levels with their names")
	browser.play_buttons[0].pressed.emit()
	check(shell.host_dialog.visible and not browser.visible and shell.host_level_label.text == metadata["title"], "Choosing a saved level returns to Host with its title")
	check(not shell.host_dialog.get_ok_button().disabled, "Saved selection enables room creation")
	shell._submit_host()
	check(session.request == {"level_code": code, "max_players": 7, "name": "Friday race", "public": true}, "Hosting uses the saved snapshot and current lobby settings without a library download")
	shell._session_ended("Try again")
	check(shell.host_dialog.visible and not shell.host_dialog.get_ok_button().disabled and LevelCodec.encode_level(shell.host_level_document) == code, "Failed connections preserve the chosen level and permit retry")

	shell.host_browse_button.pressed.emit()
	check(shell.browsing_for_host and browser.visible and not shell.host_dialog.visible, "Host Browse opens the community browser in selection mode")
	client.completed.emit(200, {"levels": [metadata]}, "")
	check(browser.rows.get_child_count() == 0 and browser.saved_button.visible, "Host community browsing hides saved levels and offers the saved view")
	browser.saved_button.pressed.emit()
	check(browser.play_buttons[0].text == "Select" and browser.save_buttons.is_empty(), "Host saved view selects local levels without a duplicate Save action")
	browser.back_button.pressed.emit()
	check(shell.host_dialog.visible and not browser.visible and shell.host_name.text == "Friday race" and shell.host_player_limit.value == 7 and shell.host_visibility.button_pressed, "Browser Back restores the host form and lobby settings")
	check(LevelCodec.encode_level(shell.host_level_document) == code, "Canceling host browsing preserves the previous level")

	var second := document.copy()
	second.spawn = Vector2i(12, 2)
	var second_code := LevelCodec.encode_level(second)
	var second_id := "b".repeat(64)
	var second_metadata := {"id": second_id, "title": "Second course", "author": "Creator"}
	var second_level := {"level": {"id": second_id, "title": "Second course", "author": "Creator", "level_code": second_code}}
	shell.host_browse_button.pressed.emit()
	client.completed.emit(200, {"levels": [second_metadata]}, "")
	browser.play_buttons[0].pressed.emit()
	client.completed.emit(200, second_level, "")
	check(shell.host_dialog.visible and not browser.visible and shell.world == null and shell.screen == shell.Screen.MAIN_MENU, "Selecting a community level returns to Host without starting solo gameplay")
	check(shell.host_level_label.text == "Second course" and LevelCodec.encode_level(shell.host_level_document) == second_code, "The selected community snapshot replaces the previous host level")
	check(shell.host_name.text == "Friday race" and shell.host_player_limit.value == 7 and shell.host_visibility.button_pressed, "Selecting a new community level preserves lobby settings")
	check(store.list_levels().size() == 1, "Browse selection does not require saving the level")
	shell._submit_host()
	check(session.request["level_code"] == second_code, "A directly browsed level can be hosted")
	shell.loading_screen.hide()

	shell.show_level_browser()
	client.completed.emit(200, {"levels": [second_metadata]}, "")
	browser.play_buttons[0].pressed.emit()
	client.completed.emit(200, second_level, "")
	await physics_frame
	shell.pause_game()
	check(paused and shell.pause_save_button.visible and not shell.pause_save_button.disabled, "Community gameplay offers Save Level while paused")
	shell.pause_save_button.pressed.emit()
	check(paused and shell.pause_dialog.visible and shell.pause_save_button.disabled and store.list_levels().size() == 2, "Pause Save stores the current level without resuming or leaving gameplay")
	check(store.find_level(second)["title"] == "Second course" and store.find_level(second)["author"] == "Creator", "Pause Save retains community metadata")
	await process_frame
	await process_frame
	await process_frame
	check(shell.pause_dialog.size.y < root.get_visible_rect().size.y, "Pause menu fits the viewport after save feedback")
	shell.pause_browser_button.pressed.emit()
	client.completed.emit(200, {"levels": [second_metadata]}, "")
	check(not paused and not browser.save_buttons.has(second_id) and browser.rows.get_child_count() == 0, "Returning from gameplay hides the newly saved community level")

	# Failed downloads and writes must never create an unusable saved entry.
	var third_id := "c".repeat(64)
	client.completed.emit(200, {"levels": [{"id": third_id, "title": "Broken level"}]}, "")
	browser.save_buttons[third_id].pressed.emit()
	client.completed.emit(503, {}, "Library unavailable")
	check(store.list_levels().size() == 2 and not browser.save_buttons[third_id].disabled and not browser.refresh_button.disabled, "Download failures preserve saved levels and permit retry")
	browser.save_buttons[third_id].pressed.emit()
	client.completed.emit(200, {"level": {"level_code": "bad-code"}}, "")
	check(store.list_levels().size() == 2 and browser.status.text.contains("MG1-"), "Damaged level codes cannot be saved")
	browser.save_buttons[third_id].pressed.emit()
	browser.back_button.pressed.emit()
	client.completed.emit(200, level, "")
	check(store.list_levels().size() == 2 and not browser.visible and shell.world == null, "Leaving during a download prevents a late response from saving or starting gameplay")
	var invalid := LevelDocument.new()
	check(not store.save_level(invalid).is_empty() and store.list_levels().size() == 2, "Unplayable documents cannot be saved")
	var blocked_store := SavedLevels.new("res://build/missing-saved-level-directory/levels.json")
	blocked_store.bind_account(account)
	check(not blocked_store.save_level(document).is_empty() and blocked_store.list_levels().is_empty(), "Write failures do not report success or change the saved collection")

	# Joined multiplayer levels use the same portable document as solo levels.
	shell.session = original_session
	shell._start_network_world("00123456", second_code, false)
	await process_frame
	await process_frame
	shell.pause_game()
	check(not paused and shell.pause_save_button.visible and shell.pause_save_button.disabled, "Multiplayer pause recognizes an already saved level without pausing other players")
	var joined := second.copy()
	joined.spawn = Vector2i(14, 2)
	shell._start_network_world("00123456", LevelCodec.encode_level(joined), false)
	await process_frame
	await process_frame
	shell.pause_game()
	check(shell.pause_save_button.visible and not shell.pause_save_button.disabled, "An unsaved joined level can be saved from multiplayer pause")
	shell.pause_save_button.pressed.emit()
	check(not paused and shell.pause_dialog.visible and not store.find_level(joined).is_empty(), "Multiplayer Save stores the received level without pausing the network world")
	shell.show_editor()
	var draft := joined.copy()
	draft.spawn = Vector2i(16, 2)
	shell.editor._commit(draft)
	shell.playtest(draft)
	await physics_frame
	shell.pause_game()
	shell.pause_save_button.pressed.emit()
	check(paused and not store.find_level(draft).is_empty() and LevelCodec.encode_level(shell.editor.document) == LevelCodec.encode_level(draft), "Playtest Save stores a snapshot and preserves the editor draft")
	check(not store.find_level(draft)["title"].is_empty(), "Levels without published metadata get a usable saved name")
	shell.show_demo()
	shell.pause_game()
	check(not shell.pause_save_button.visible, "Tutorial scene does not offer an unsupported portable save")
	shell.show_main_menu()
	shell.show_host_menu()
	await process_frame
	await process_frame
	await process_frame
	check(shell.host_dialog.size.y < root.get_visible_rect().size.y, "Host menu fits the viewport with both level choices")
	shell.free()
	session.free()
	await process_frame
	# A new shell reloads saves without relying on the original browser or world.
	var fresh_shell = load("res://scenes/game_shell.tscn").instantiate()
	fresh_shell.saved_levels = SavedLevels.new(TEST_PATH)
	root.add_child(fresh_shell)
	fresh_shell.show_host_menu()
	fresh_shell.host_saved_button.pressed.emit()
	check(fresh_shell.level_browser.rows.get_child_count() == 4, "A fresh game session lists previously saved levels for hosting")
	fresh_shell.free()
	account.invalidate()
	await process_frame
	DirAccess.remove_absolute(TEST_PATH)
	print("SAVED LEVELS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

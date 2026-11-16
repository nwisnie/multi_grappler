extends SceneTree

const SavedLevels := preload("res://scripts/levels/saved_levels.gd")
const TEST_PATH := "res://build/level-views-tests.json"

class CaptureLibrary extends "res://scripts/levels/level_library_client.gd":
	var list_requests := 0
	var downloads: Array[String] = []
	func fetch_levels() -> void:
		list_requests += 1
	func fetch_level(id: String) -> void:
		downloads.append(id)

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

func sign_in(account: Node, id: String) -> void:
	account._apply_session({"user": {"id": id, "username": "Owner"}, "token": "b".repeat(64), "expires_at": (Time.get_unix_time_from_system() + 3600) * 1000})

func _run() -> void:
	preload("res://scripts/ui/menu_slide.gd").duration_scale = 0.0
	ProjectSettings.set_setting("network/level_library_url", "http://127.0.0.1:9080/levels")
	var account := root.get_node("AccountSession")
	account.invalidate()
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
	var mine := {"id": "d".repeat(64), "title": "My published course", "author": "Owner", "author_id": "owner-id"}
	var other := {"id": "e".repeat(64), "title": "Another course", "author": "Owner", "author_id": "other-id"}
	var legacy := {"id": "f".repeat(64), "title": "Legacy course", "author": "Owner"}
	var library := {"levels": [mine, other, legacy]}
	var document := LevelDocument.new()
	document.spawn = Vector2i(10, 2)
	document.segments.append({"kind": 0, "a": Vector2i(0, 5), "b": Vector2i(100, 5)})
	var code := LevelCodec.encode_level(document)
	var downloaded := mine.duplicate(true)
	downloaded["level_code"] = code

	shell.show_level_browser()
	client.completed.emit(200, library, "")
	check(browser.rows.get_child_count() == 3 and browser.saved_button.visible and browser.my_levels_button.visible, "Community has top-right Saved Levels and My Levels navigation")
	var requests := client.list_requests
	browser.my_levels_button.pressed.emit()
	check(browser.current_view == browser.View.MY_LEVELS and browser.rows.get_child_count() == 0 and browser.sign_in_button.visible, "Signed-out My Levels offers account sign-in")
	check(client.list_requests == requests, "Signed-out My Levels does not request a user's levels")
	browser.sign_in_button.pressed.emit()
	check(shell.account_dialog.visible and shell.dimmer.visible and browser.visible, "My Levels opens the account prompt in the browser")
	shell.account_dialog.get_cancel_button().pressed.emit()
	check(not shell.account_dialog.visible and not shell.settings_dialog.visible and not shell.dimmer.visible and browser.visible, "Canceling browser sign-in returns to My Levels")
	sign_in(account, "owner-id")
	client.completed.emit(200, library, "")
	check(not browser.sign_in_button.visible and browser.rows.get_child_count() == 1 and browser.entries.has(mine["id"]), "My Levels filters by the signed-in creator ID")
	check(not browser.entries.has(other["id"]) and not browser.entries.has(legacy["id"]), "Matching display names and unclaimed legacy authors do not establish ownership")
	browser.save_buttons[mine["id"]].pressed.emit()
	client.completed.emit(200, {"level": downloaded}, "")
	check(browser.rows.get_child_count() == 1 and browser.save_buttons.is_empty(), "Saving your level retains it in My Levels using its local copy")
	check(store.find_level(document)["author_id"] == "owner-id", "Saved snapshots retain creator IDs")
	var reloaded := SavedLevels.new(TEST_PATH)
	reloaded.bind_account(account)
	reloaded.load_levels()
	check(reloaded.find_level(document)["author_id"] == "owner-id", "Creator IDs survive reloading saved data")

	requests = client.list_requests
	var downloads := client.downloads.size()
	browser.saved_button.pressed.emit()
	check(browser.current_view == browser.View.SAVED and browser.rows.get_child_count() == 1 and client.list_requests == requests, "Saved Levels lists local snapshots without a server request")
	browser.play_buttons[0].pressed.emit()
	await physics_frame
	check(shell.screen == shell.Screen.COMMUNITY_LEVEL and LevelCodec.encode_level(shell.world.document) == code and client.downloads.size() == downloads, "Saved Play uses the complete local snapshot without downloading")
	shell.pause_game()
	check(shell.pause_browser_button.text == "Back to Saved Levels", "Saved gameplay remembers its browser origin")
	shell.pause_browser_button.pressed.emit()
	check(not paused and browser.current_view == browser.View.SAVED and browser.rows.get_child_count() == 1, "Returning from a saved level restores Saved Levels")
	browser.community_button.pressed.emit()
	client.completed.emit(200, library, "")
	check(browser.rows.get_child_count() == 2 and not browser.entries.has(mine["id"]), "Saved levels remain hidden after refreshing the community list")
	browser.my_levels_button.pressed.emit()
	client.completed.emit(200, library, "")
	check(browser.rows.get_child_count() == 1, "My Levels shows one row when the same published level is also saved")
	client.completed.emit(503, {}, "Library offline")
	check(browser.rows.get_child_count() == 1 and not browser.play_buttons[0].disabled, "A library failure preserves playable saved copies of your levels")
	account.invalidate()
	check(browser.rows.get_child_count() == 0 and browser.sign_in_button.visible, "Signing out clears My Levels immediately")
	sign_in(account, "other-id")
	client.completed.emit(200, library, "")
	check(browser.rows.get_child_count() == 1 and browser.entries.has(other["id"]), "Switching accounts shows the new account's published levels")
	check(not browser.entries.has(mine["id"]), "Switching accounts does not retain the previous account's saved My Levels rows")
	var other_document := document.copy()
	other_document.spawn = Vector2i(12, 2)
	var other_download := other.duplicate(true)
	other_download["level_code"] = LevelCodec.encode_level(other_document)
	browser.play_buttons[0].pressed.emit()
	client.completed.emit(200, {"level": other_download}, "")
	await physics_frame
	check(shell.screen == shell.Screen.COMMUNITY_LEVEL and shell.active_level_metadata["author_id"] == "other-id", "My Levels downloads and plays an unsaved published level with its creator metadata")
	shell.pause_game()
	shell.pause_browser_button.pressed.emit()
	client.completed.emit(200, library, "")
	check(browser.current_view == browser.View.MY_LEVELS and browser.rows.get_child_count() == 1, "Returning from My Levels gameplay restores My Levels")
	sign_in(account, "empty-id")
	client.completed.emit(200, library, "")
	check(browser.rows.get_child_count() == 0 and browser.status.text.contains("haven't published"), "An account without uploads gets a useful empty state")
	account.invalidate()
	browser.saved_button.pressed.emit()
	check(browser.rows.get_child_count() == 0 and browser.sign_in_button.visible, "Signed-out Saved Levels hides account saves and offers sign-in")
	sign_in(account, "owner-id")

	# Metadata-free multiplayer saves still match the public library's payload ID.
	var multiplayer_document := document.copy()
	multiplayer_document.spawn = Vector2i(20, 2)
	check(store.save_level(multiplayer_document).is_empty(), "A metadata-free level can still be saved")
	var payload_id := "9aa38116eac9b1cd5bd548c5d4fb4751014711cbc639c150e9529bb45e2f6d82"
	check(store.has_source(payload_id), "Metadata-free saves derive the same ID as the publishing API")
	browser.community_button.pressed.emit()
	client.completed.emit(200, {"levels": [{"id": payload_id, "title": "Multiplayer course"}, other]}, "")
	check(browser.rows.get_child_count() == 1 and browser.entries.has(other["id"]), "Community also hides levels saved from multiplayer without library metadata")

	shell.show_main_menu()
	sign_in(account, "owner-id")
	shell.show_host_menu()
	shell.host_name.text = "My courses lobby"
	shell.host_player_limit.value = 6
	shell.host_visibility.button_pressed = true
	shell.host_visibility.pressed.emit()
	shell.host_my_levels_button.pressed.emit()
	client.completed.emit(200, library, "")
	check(shell.browsing_for_host and browser.selecting_level and browser.current_view == browser.View.MY_LEVELS and browser.play_buttons[0].text == "Select", "Host My Levels opens the shared view in selection mode")
	browser.play_buttons[0].pressed.emit()
	check(shell.host_dialog.visible and not browser.visible and shell.host_level_label.text == mine["title"], "Selecting your level restores the host form with its name")
	check(shell.host_name.text == "My courses lobby" and shell.host_player_limit.value == 6 and shell.host_visibility.button_pressed, "My Levels selection preserves all lobby settings")
	var original_session = shell.session
	var capture_session := CaptureSession.new()
	shell.session = capture_session
	shell._submit_host()
	check(capture_session.request == {"level_code": code, "max_players": 6, "name": "My courses lobby", "public": true}, "Host uses the selected My Levels snapshot and lobby options")
	shell._session_ended("Retry")
	requests = client.list_requests
	shell.host_saved_button.pressed.emit()
	check(browser.current_view == browser.View.SAVED and browser.play_buttons[0].text == "Select" and client.list_requests == requests, "Host Saved Levels opens immediately without the library")
	browser.back_button.pressed.emit()
	check(shell.host_dialog.visible and shell.host_level_label.text == mine["title"], "Back from host Saved Levels preserves the current selection")
	shell.host_browse_button.pressed.emit()
	client.completed.emit(200, library, "")
	check(browser.rows.get_child_count() == 2 and browser.saved_button.visible and browser.my_levels_button.visible, "Host community view excludes saved levels and exposes both other menus")
	browser.my_levels_button.pressed.emit()
	client.completed.emit(200, library, "")
	check(shell.browsing_for_host and browser.selecting_level and browser.rows.get_child_count() == 1, "Switching browser views preserves host selection mode")
	browser.back_button.pressed.emit()
	check(shell.host_dialog.visible and shell.host_level_label.text == mine["title"], "Back from host My Levels restores the prior selection")
	shell.session = original_session
	capture_session.free()
	shell.free()
	account.invalidate()
	await process_frame
	DirAccess.remove_absolute(TEST_PATH)
	print("LEVEL VIEWS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

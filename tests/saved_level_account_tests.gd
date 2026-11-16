extends SceneTree

const SavedLevels := preload("res://scripts/levels/saved_levels.gd")
const TEST_PATH := "res://build/saved-level-account-tests.json"
const ENDPOINT := "http://127.0.0.1:9080/levels"

class CaptureLibrary extends "res://scripts/levels/level_library_client.gd":
	var downloads := 0
	func fetch_levels() -> void:
		pass
	func fetch_level(_id: String) -> void:
		downloads += 1

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func sign_in(account: Node, id: String, username: String = "Player") -> void:
	account._apply_session({"user": {"id": id, "username": username}, "token": "b".repeat(64), "expires_at": (Time.get_unix_time_from_system() + 3600) * 1000})

func file_text() -> String:
	return FileAccess.open(TEST_PATH, FileAccess.READ).get_as_text()

func _run() -> void:
	preload("res://scripts/ui/menu_slide.gd").duration_scale = 0.0
	ProjectSettings.set_setting("network/level_library_url", ENDPOINT)
	var account := root.get_node("AccountSession")
	account.invalidate()
	var document := LevelDocument.new()
	document.spawn = Vector2i(10, 2)
	document.segments.append({"kind": 0, "a": Vector2i(0, 5), "b": Vector2i(100, 5)})
	var metadata := {"id": "a".repeat(64), "title": "Baby Steps", "author": "Wizkinews", "author_id": "creator-id"}
	var legacy_entry := metadata.duplicate(true)
	legacy_entry["level_code"] = LevelCodec.encode_level(document)
	var original := JSON.stringify({"version": 1, "levels": [legacy_entry]})
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(original)
	file.close()
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
	check(store.list_levels().is_empty() and not store.has_source(metadata["id"]), "Signed-out players do not inherit earlier device saves")
	check(file_text() == original, "Loading earlier saves leaves the original file intact")
	check(not store.save_level(document, metadata).is_empty() and file_text() == original, "Signed-out saves are rejected without changing stored data")
	check(not store.import_legacy_levels().is_empty(), "Signed-out players cannot import earlier saves")
	shell.show_level_browser(false, browser.View.SAVED)
	check(browser.rows.get_child_count() == 0 and browser.sign_in_button.visible and not browser.import_button.visible, "Signed-out Saved Levels offers sign-in and exposes no account or legacy rows")
	sign_in(account, "player-a")
	check(store.list_levels().is_empty() and browser.import_button.visible, "Signing in does not silently claim older device saves")
	var second := document.copy()
	second.spawn = Vector2i(12, 2)
	check(store.save_level(second, {"id": "b".repeat(64), "title": "A's new save"}).is_empty(), "An account can save a new level before importing earlier saves")
	var before_import = JSON.parse_string(file_text())
	check(before_import["version"] == 2 and before_import["legacy_levels"].size() == 1, "Writing account saves preserves unassigned legacy levels")
	browser.import_button.pressed.emit()
	check(store.list_levels().size() == 2 and store.find_level(document)["author"] == "Wizkinews", "Import assigns earlier saves to the selected account while preserving creator metadata")
	check(not browser.import_button.visible and not store.has_legacy_levels(), "Imported legacy saves are not offered to another account")
	account.invalidate()
	check(store.list_levels().is_empty() and store.find_level(document).is_empty() and not store.has_source(metadata["id"]), "Signing out clears saved-list, document, and community-filter lookups")
	check(browser.rows.get_child_count() == 0 and browser.sign_in_button.visible, "Signing out immediately clears the visible Saved Levels list")
	browser.community_button.pressed.emit()
	client.completed.emit(200, {"levels": [metadata]}, "")
	check(browser.rows.get_child_count() == 1 and browser.save_buttons.has(metadata["id"]), "Baby Steps reappears as an unsaved community level while signed out")
	var before_guest_save := file_text()
	browser.save_buttons[metadata["id"]].pressed.emit()
	check(shell.account_dialog.visible and client.downloads == 0 and file_text() == before_guest_save, "Guest Save opens sign-in without downloading or writing a level")
	shell.account_dialog.get_cancel_button().pressed.emit()
	check(browser.visible and not shell.settings_dialog.visible, "Canceling save sign-in returns to the browser")
	sign_in(account, "player-b")
	client.completed.emit(200, {"levels": [metadata]}, "")
	check(browser.rows.get_child_count() == 1 and not store.has_source(metadata["id"]), "Another account does not hide levels saved by the first account")
	browser.saved_button.pressed.emit()
	check(browser.rows.get_child_count() == 0, "Another account starts with its own empty Saved Levels list")
	var third := document.copy()
	third.spawn = Vector2i(14, 2)
	check(store.save_level(third, {"title": "B's save"}).is_empty(), "The second account can save independently")
	sign_in(account, "player-a")
	check(store.list_levels().size() == 2 and not store.find_level(document).is_empty() and store.find_level(third).is_empty(), "Signing back in restores only the first account's saves")
	sign_in(account, "player-b")
	check(store.list_levels().size() == 1 and not store.find_level(third).is_empty() and store.find_level(document).is_empty(), "The second account retains its own collection after account switching")
	sign_in(account, "creator-id", "Wizkinews")
	check(store.list_levels().is_empty(), "A level's creator does not inherit another player's saved collection")
	sign_in(account, "player-a")
	var reloaded := SavedLevels.new(TEST_PATH)
	reloaded.bind_account(account)
	reloaded.load_levels()
	check(reloaded.list_levels().size() == 2, "A new store restores the matching account's persisted saves")
	sign_in(account, "player-b")
	check(reloaded.list_levels().size() == 1 and not reloaded.find_level(third).is_empty(), "Reloaded data preserves other accounts without combining their collections")
	sign_in(account, "player-a")
	account._expires_at = int(Time.get_unix_time_from_system()) - 1
	check(store.list_levels().is_empty() and not store.save_level(document).is_empty(), "Expired sessions cannot expose or add account saves before the expiry timer runs")
	ProjectSettings.set_setting("network/level_library_url", "http://127.0.0.1:9081/levels")
	sign_in(account, "player-a")
	check(store.list_levels().is_empty(), "Equal account IDs on different level services have separate collections")
	ProjectSettings.set_setting("network/level_library_url", ENDPOINT)
	sign_in(account, "player-a")
	check(store.list_levels().size() == 2, "Returning to the original service restores its account saves")

	account.invalidate()
	shell.play_community_level(document)
	await physics_frame
	shell.pause_game()
	check(shell.pause_save_button.text == "Save Level" and not shell.pause_save_button.disabled, "Signed-out pause does not show another account's Level Saved badge")
	shell.pause_save_button.pressed.emit()
	check(paused and shell.account_dialog.visible and not shell.pause_dialog.visible, "Pause Save requests sign-in while keeping gameplay paused")
	shell.account_dialog.get_cancel_button().pressed.emit()
	check(paused and shell.pause_dialog.visible and not shell.account_dialog.visible, "Canceling pause sign-in restores the pause menu")
	shell.pause_save_button.pressed.emit()
	sign_in(account, "player-c")
	shell.account_dialog.dismiss(false)
	shell.account_dialog.authenticated.emit()
	check(paused and shell.pause_dialog.visible and not shell.pause_save_button.disabled, "Signing in from pause restores the correct account's save controls")
	shell.pause_save_button.pressed.emit()
	check(shell.pause_save_button.disabled and store.list_levels().size() == 1, "The signed-in player can save the paused level")
	shell.show_settings()
	account.invalidate()
	check(not shell.pause_save_button.disabled and shell.pause_save_button.text == "Save Level" and not shell.pause_save_message.visible, "Signing out through pause settings removes saved badges and confirmation text")
	shell.settings_back_button.pressed.emit()
	check(paused and shell.pause_dialog.visible and not shell.pause_save_button.disabled, "Returning from signed-out settings keeps the pause save state correct")
	shell.show_main_menu()
	shell.show_host_menu()
	shell.host_saved_button.pressed.emit()
	check(browser.rows.get_child_count() == 0 and browser.sign_in_button.visible and shell.browsing_for_host, "Signed-out host selection cannot list another account's saved levels")
	shell.free()
	account.invalidate()
	await process_frame
	DirAccess.remove_absolute(TEST_PATH)
	print("SAVED LEVEL ACCOUNTS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

extends SceneTree

const LibraryClient := preload("res://scripts/levels/level_library_client.gd")
const SavedLevels := preload("res://scripts/levels/saved_levels.gd")
const TEST_PATH := "res://build/level-deletion-tests.json"

class CaptureLibrary extends "res://scripts/levels/level_library_client.gd":
	var deletions: Array[String] = []
	func fetch_levels() -> void:
		pass
	func delete_level(id: String) -> void:
		deletions.append(id)

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

func replace_client(parent: Node, original: Node) -> CaptureLibrary:
	parent.remove_child(original)
	original.free()
	var client := CaptureLibrary.new()
	parent.add_child(client)
	return client

func _run() -> void:
	root.size = Vector2i(1280, 720)
	preload("res://scripts/ui/menu_slide.gd").duration_scale = 0.0
	ProjectSettings.set_setting("network/level_library_url", "http://127.0.0.1:9080/levels")
	var account := root.get_node("AccountSession")
	account.invalidate()
	DirAccess.remove_absolute(TEST_PATH)
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.saved_levels = SavedLevels.new(TEST_PATH)
	root.add_child(shell)
	await process_frame
	var browser = shell.level_browser
	var library := replace_client(browser, browser.client)
	browser.client = library
	library.completed.connect(browser._received)
	var deletion := replace_client(browser, browser.delete_client)
	browser.delete_client = deletion
	deletion.completed.connect(browser._deleted)
	var summaries := replace_client(shell.time_records, shell.time_records.summary_client)
	shell.time_records.summary_client = summaries
	summaries.completed.connect(shell.time_records._received_summaries)
	var detail := replace_client(browser, browser.leaderboard_client)
	browser.leaderboard_client = detail
	detail.completed.connect(browser._received_leaderboard)
	var document := LevelDocument.new()
	document.spawn = Vector2i(10, 10)
	document.checkpoints.assign([Vector2i(20, 10)])
	document.finish_checkpoint = 2
	var id := LevelCodec.publication_id(document)
	var mine := {"id": id, "title": "My race", "author": "Owner", "author_id": "owner", "top_time_ms": 1000, "personal_time_ms": 2000}
	var other := {"id": "b".repeat(64), "title": "Another race", "author": "Owner", "author_id": "other"}
	var legacy := {"id": "c".repeat(64), "title": "Legacy race", "author": "Owner"}
	var levels := {"levels": [mine, other, legacy]}

	shell.show_level_browser(false, browser.View.MY_LEVELS)
	check(browser.delete_buttons.is_empty(), "Guests have no delete actions")
	sign_in(account, "owner")
	library.completed.emit(200, levels, "")
	check(browser.delete_buttons.size() == 1 and browser.delete_buttons.has(id), "My Levels exposes Delete only for the account's upload")
	browser.delete_buttons[id].pressed.emit()
	await process_frame
	check(browser.delete_dialog.visible and deletion.deletions.is_empty(), "Delete opens confirmation without sending a request")
	check(browser.delete_dialog.exclusive and browser.delete_dialog.size.x <= root.size.x and browser.delete_dialog.size.y < root.size.y, "Delete confirmation is modal and fits the viewport (%s inside %s)" % [browser.delete_dialog.size, root.size])
	check(browser.delete_dialog.dialog_text.contains("My race") and browser.delete_dialog.dialog_text.contains("times and records") and browser.delete_dialog.dialog_text.contains("cannot be undone"), "Confirmation names the level and explains permanent record deletion")
	browser.delete_dialog.canceled.emit()
	check(not browser.delete_dialog.visible and browser.pending_delete_id.is_empty() and deletion.deletions.is_empty(), "Cancel preserves the publication")
	browser.delete_buttons[id].pressed.emit()
	browser.show_view(browser.View.COMMUNITY)
	check(not browser.delete_dialog.visible and browser.pending_delete_id.is_empty(), "Changing views dismisses an unconfirmed deletion")
	library.completed.emit(200, levels, "")
	check(browser.delete_buttons.is_empty(), "Community browsing leaves deletion in My Levels")
	browser.show_view(browser.View.MY_LEVELS)
	library.completed.emit(200, levels, "")
	browser.delete_buttons[id].pressed.emit()
	account.invalidate()
	browser._confirm_delete()
	check(not browser.delete_dialog.visible and deletion.deletions.is_empty(), "Signing out cancels confirmation and cannot issue a stale delete")
	sign_in(account, "owner")
	library.completed.emit(200, levels, "")
	browser.delete_buttons[id].pressed.emit()
	browser.delete_dialog.confirmed.emit()
	check(deletion.deletions == [id] and browser.delete_buttons[id].disabled and browser.play_buttons[0].disabled, "Confirmation sends the publication ID and blocks conflicting actions")
	browser._confirm_delete()
	check(deletion.deletions.size() == 1, "Repeated confirmation cannot start another deletion")
	deletion.completed.emit(503, {}, "Library offline")
	check(browser.entries.has(id) and not browser.delete_buttons[id].disabled and browser.status.text == "Library offline", "A failed deletion preserves the row and allows retry")
	check(shell.time_records.summary(id).get("top_time_ms") == 1000, "A failed deletion preserves cached records")
	var earlier_copies: Array[Dictionary] = [shell.saved_levels._entry(LevelCodec.encode_level(document), mine)]
	var no_legacy: Array[Dictionary] = []
	check(shell.saved_levels._write_levels(earlier_copies, no_legacy).is_empty(), "An uploader can have a downloaded copy saved by an earlier version")
	var saved_id := "saved:" + LevelCodec.encode_level(document).sha256_text()
	check(browser.delete_buttons.has(saved_id), "An upload with a saved copy still has a Delete action")
	browser.leaderboard_buttons[saved_id].pressed.emit()
	check(browser.leaderboard_dialog.visible, "The upload's leaderboard can be viewed before deletion")
	browser.leaderboard_dialog.hide()
	browser.delete_buttons[saved_id].pressed.emit()
	browser.delete_dialog.confirmed.emit()
	check(deletion.deletions == [id, id], "Deleting a saved upload uses its publication ID rather than its local row ID")
	deletion.completed.emit(200, {"id": id}, "")
	check(browser.rows.get_child_count() == 0 and browser.remote_levels.size() == 2, "Successful deletion removes the publication from My Levels and the cached library")
	check(shell.time_records.summary(id).is_empty(), "Successful deletion clears the record and personal-best cache")
	check(browser.status.text.contains("deleted") and browser.status.text.contains("records"), "Deletion reports that level records were removed")
	check(shell.saved_levels.has_source(id), "Previously downloaded snapshots remain playable")
	browser.refresh()
	library.completed.emit(200, {"levels": [other, legacy]}, "")
	check(browser.rows.get_child_count() == 0, "Refreshing does not resurrect a deleted upload from its saved snapshot")
	browser.show_view(browser.View.SAVED)
	check(browser.rows.get_child_count() == 1 and browser.delete_buttons.is_empty(), "Saved Levels retains its offline copy without offering publication deletion")

	# Navigation and account changes cannot cancel a delete already sent to the server.
	browser.show_view(browser.View.MY_LEVELS)
	library.completed.emit(200, levels, "")
	browser.delete_buttons[saved_id].pressed.emit()
	browser.delete_dialog.confirmed.emit()
	sign_in(account, "other")
	library.completed.emit(200, levels, "")
	deletion.completed.emit(200, {"id": id}, "")
	check(browser.rows.get_child_count() == 1 and browser.entries.has(other["id"]) and browser.remote_levels.size() == 2, "A completed deletion after switching accounts preserves the new account's rows")
	sign_in(account, "owner")
	library.completed.emit(200, levels, "")
	browser.delete_buttons[saved_id].pressed.emit()
	browser.delete_dialog.confirmed.emit()
	browser.close()
	deletion.completed.emit(404, {}, "Already deleted")
	check(browser.remote_levels.size() == 2 and browser.deleting_level_id.is_empty(), "A deletion completed after leaving the browser still reconciles an already-missing publication")

	var client := LibraryClient.new()
	root.add_child(client)
	account.invalidate()
	var responses: Array = []
	client.completed.connect(func(code: int, _payload: Dictionary, error: String) -> void: responses.append([code, error]))
	client.delete_level(id)
	check(responses.size() == 1 and responses[0][0] == 401, "The HTTP client refuses signed-out deletion before connecting")
	ProjectSettings.set_setting("network/level_library_url", "http://untrusted.example/levels")
	sign_in(account, "owner")
	client.delete_level(id)
	check(responses.size() == 2 and responses[1][1].contains("HTTPS"), "The HTTP client refuses to send deletion credentials over insecure remote HTTP")
	client.free()
	shell.free()
	account.invalidate()
	var endpoint := OS.get_environment("LEVEL_DELETION_TEST_URL")
	if not endpoint.is_empty():
		await _http_checks(endpoint)
	await process_frame
	DirAccess.remove_absolute(TEST_PATH)
	print("LEVEL DELETION: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _http_checks(endpoint: String) -> void:
	ProjectSettings.set_setting("network/level_library_url", endpoint)
	var account := root.get_node("AccountSession")
	account.create_account("Delete%d" % (Time.get_ticks_usec() % 100000000), "Godot deletion test password.")
	var authentication = await account.completed
	check(authentication[1].is_empty() and account.is_signed_in(), "Integration creates an account: " + str(authentication[1]))
	if not account.is_signed_in():
		return
	var client := LibraryClient.new()
	root.add_child(client)
	var document := LevelDocument.new()
	document.spawn = Vector2i(10, 10)
	document.checkpoints.assign([Vector2i(20, 10)])
	document.finish_checkpoint = 2
	var id := LevelCodec.publication_id(document)
	client.upload_level("Deletion integration race", LevelCodec.encode_level(document))
	var published = await client.completed
	check(published[0] == 201, "Integration publishes a race: " + str(published[2]))
	if published[0] != 201:
		client.free()
		return
	client.submit_time(id, 1234)
	var timed = await client.completed
	check(timed[2].is_empty() and timed[1].get("top_time_ms") == 1234, "Integration stores a record before deleting the level")
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.saved_levels = SavedLevels.new(TEST_PATH)
	root.add_child(shell)
	await process_frame
	var browser = shell.level_browser
	shell.show_level_browser(false, browser.View.MY_LEVELS)
	var deadline := Time.get_ticks_msec() + 18000
	while browser.request_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(browser.delete_buttons.has(id), "Integration shows Delete for the real account's uploaded race")
	if browser.delete_buttons.has(id):
		browser.delete_buttons[id].pressed.emit()
		browser.delete_dialog.confirmed.emit()
		deadline = Time.get_ticks_msec() + 18000
		while not browser.deleting_level_id.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		check(browser.rows.get_child_count() == 0 and browser.status.text.contains("deleted"), "Integration deletes through the real browser and Worker: " + browser.status.text)
		check(shell.time_records.summary(id).is_empty(), "Integration clears the deleted race's cached records")
	client.fetch_level(id)
	var missing = await client.completed
	check(missing[0] == 404, "Integration can no longer download the deleted publication")
	client.fetch_times(id)
	missing = await client.completed
	check(missing[0] == 404, "Integration can no longer read the deleted leaderboard")
	client.upload_level("Republished integration race", LevelCodec.encode_level(document))
	var republished = await client.completed
	check(republished[0] == 201, "Integration can republish the deleted payload")
	client.fetch_times(id)
	var times = await client.completed
	check(times[2].is_empty() and times[1].get("leaderboard") == [] and times[1].get("personal_time_ms") == null, "Integration verifies republication has no old times or records")
	client.delete_level(id)
	await client.completed
	account.sign_out()
	await account.completed
	client.free()
	shell.free()

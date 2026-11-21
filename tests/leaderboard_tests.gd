extends SceneTree

const LevelTimes := preload("res://scripts/levels/level_times.gd")
const LibraryClient := preload("res://scripts/levels/level_library_client.gd")
const SavedLevels := preload("res://scripts/levels/saved_levels.gd")
const TEST_PATH := "res://build/leaderboard-tests.json"

class CaptureLibrary extends "res://scripts/levels/level_library_client.gd":
	var requested_id := ""
	func fetch_levels() -> void:
		pass
	func fetch_times(id: String) -> void:
		requested_id = id

class CaptureRecords extends Node:
	var user_id := "owner"
	var submissions: Array[Dictionary] = []
	var callbacks: Array[Callable] = []
	func current_user_id() -> String:
		return user_id
	func summary(_id: String) -> Dictionary:
		return {"top_time_ms": 10000, "personal_time_ms": 12000}
	func submit_time(id: String, seconds: float, owner: String, callback: Callable) -> void:
		submissions.append({"id": id, "seconds": seconds, "owner": owner})
		callbacks.append(callback)

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

func course() -> LevelDocument:
	var document := LevelDocument.new()
	document.spawn = Vector2i(10, 10)
	document.checkpoints.assign([Vector2i(15, 10), Vector2i(20, 10)])
	document.finish_checkpoint = 3
	return document

func _run() -> void:
	preload("res://scripts/ui/menu_slide.gd").duration_scale = 0.0
	ProjectSettings.set_setting("network/level_library_url", "http://127.0.0.1:9080/levels")
	var account := root.get_node("AccountSession")
	account.invalidate()
	check(LevelTimes.format_time(61023) == "01:01.023", "Times preserve millisecond precision across minutes")
	check(LevelTimes.format_time(null) == "—", "Absent times have a distinct placeholder")
	DirAccess.remove_absolute(TEST_PATH)
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.saved_levels = SavedLevels.new(TEST_PATH)
	root.add_child(shell)
	await process_frame
	var browser = shell.level_browser
	var original = browser.client
	browser.remove_child(original)
	original.free()
	var library := CaptureLibrary.new()
	browser.client = library
	browser.add_child(library)
	library.completed.connect(browser._received)
	original = browser.leaderboard_client
	browser.remove_child(original)
	original.free()
	var detail := CaptureLibrary.new()
	browser.leaderboard_client = detail
	browser.add_child(detail)
	detail.completed.connect(browser._received_leaderboard)
	original = shell.time_records.summary_client
	shell.time_records.remove_child(original)
	original.free()
	var summaries := CaptureLibrary.new()
	shell.time_records.summary_client = summaries
	shell.time_records.add_child(summaries)
	summaries.completed.connect(shell.time_records._received_summaries)
	var document := course()
	var id := LevelCodec.publication_id(document)
	var entry := {"id": id, "title": "Timed course", "author": "Owner", "author_id": "owner", "top_time_ms": 10000, "personal_time_ms": null}
	shell.show_level_browser()
	library.completed.emit(200, {"levels": [entry]}, "")
	check(browser.time_labels[id].text.contains("00:10.000") and browser.time_labels[id].text.contains("Sign in"), "Guests see the record and a sign-in hint")
	browser.leaderboard_buttons[id].pressed.emit()
	check(detail.requested_id == id and browser.leaderboard_dialog.visible, "Top Times requests the selected published level")
	detail.completed.emit(200, {"leaderboard": [], "top_time_ms": null, "personal_time_ms": null}, "")
	check(browser.leaderboard_text.text.contains("No times yet"), "Empty leaderboards invite the first finish")
	sign_in(account, "owner")
	check(not browser.leaderboard_dialog.visible, "Account changes dismiss pending personal leaderboard reads")
	entry["personal_time_ms"] = 12000
	library.completed.emit(200, {"levels": [entry]}, "")
	check(browser.time_labels[id].text.contains("00:12.000"), "Published rows display the signed-in player's best")
	browser.leaderboard_buttons[id].pressed.emit()
	detail.completed.emit(200, {"leaderboard": [{"rank": 1, "user_id": "owner", "username": "Owner", "time_ms": 10000}], "top_time_ms": 10000, "personal_time_ms": 10000}, "")
	check(browser.leaderboard_text.text.contains("1.  Owner (you)") and browser.leaderboard_text.text.contains("Your best: 00:10.000"), "Top Times shows ranks, usernames, times, and the personal best")
	browser.leaderboard_dialog.hide()
	check(shell.saved_levels.save_level(document, entry).is_empty(), "Published race can be saved")
	browser.show_view(browser.View.SAVED)
	summaries.completed.emit(200, {"levels": [entry]}, "")
	var saved_id: String = browser.entries.keys()[0]
	check(browser.time_labels[saved_id].text.contains("00:10.000") and browser.time_labels[saved_id].text.contains("00:12.000"), "Saved rows use their published ID for both times")
	browser.leaderboard_buttons[saved_id].pressed.emit()
	check(detail.requested_id == id, "Saved Top Times shares the original publication's leaderboard")
	detail.completed.emit(503, {}, "Times unavailable")
	check(browser.leaderboard_text.text == "Times unavailable", "Leaderboard failures are visible")
	browser.leaderboard_dialog.hide()
	summaries.completed.emit(503, {}, "Offline")
	check(not browser.play_buttons[0].disabled and browser.time_labels[saved_id].text.contains("Times unavailable"), "A time-service failure leaves saved levels playable")
	browser.play_buttons[0].pressed.emit()
	check(shell.world.leaderboard_id == id and shell.world.time_records == shell.time_records, "Playing a saved race enables its original leaderboard")
	shell.show_main_menu()
	shell.show_editor()
	shell.playtest(document)
	check(shell.world.time_records == null and shell.world.leaderboard_id.is_empty(), "Editor playtests do not submit published times")
	shell.show_main_menu()
	shell.time_records.cache_time(id, {"top_time_ms": 10000, "personal_time_ms": 12000})
	account.invalidate()
	check(shell.time_records.summary(id).is_empty(), "Signing out clears personal time caches")
	var rejected := []
	shell.time_records.submit_time(id, 12.0, "", func(_payload: Dictionary, error: String) -> void: rejected.append(error))
	check(rejected.size() == 1 and rejected[0].contains("Sign in"), "Signed-out finishes never start a time upload")
	sign_in(account, "another-owner")
	rejected.clear()
	shell.time_records.submit_time(id, 12.0, "owner", func(_payload: Dictionary, error: String) -> void: rejected.append(error))
	check(rejected.size() == 1, "Changing accounts during a run cannot credit the new account")
	shell.free()
	account.invalidate()
	await _race_checks(document, id)
	if not OS.get_environment("LEADERBOARD_TEST_URL").is_empty():
		await _integration(document)
	DirAccess.remove_absolute(TEST_PATH)
	print("LEADERBOARDS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _race_checks(document: LevelDocument, id: String) -> void:
	var records := CaptureRecords.new()
	root.add_child(records)
	var custom = load("res://scenes/custom_level.tscn").instantiate()
	check(custom.prepare(document).is_empty(), "Timed race prepares")
	custom.time_records = records
	custom.leaderboard_id = id
	root.add_child(custom)
	custom.set_physics_process(false)
	custom.race.set_physics_process(false)
	var race = custom.race
	race.elapsed = 12.345
	race._reach_checkpoint()
	check(records.submissions.is_empty(), "Intermediate checkpoints never submit times")
	race._reach_checkpoint()
	check(records.submissions.size() == 1 and records.submissions[0] == {"id": id, "seconds": 12.345, "owner": "owner"}, "Completing every checkpoint submits the full race time once")
	race.advance_between(Vector2.ZERO, Vector2.ONE)
	check(records.submissions.size() == 1, "Continuing after the finish cannot submit duplicates")
	race.hud._process(0.0)
	check(race.hud.status.text.contains("Race finished!") and race.hud.status.text.contains("00:12.345") and race.hud.status.text.contains("Top: 00:10.000"), "Finish HUD displays current time and the level record")
	race.reset()
	records.callbacks[0].call({"improved": true}, "")
	check(race.time_status.is_empty(), "A previous attempt's save response cannot overwrite a restarted run")
	race.elapsed = 11.0
	race._reach_checkpoint()
	race._reach_checkpoint()
	records.callbacks[1].call({"improved": true}, "")
	check(race.time_status == "New personal best saved!", "Finished runs confirm successful personal best saves")
	custom.free()
	records.free()

func _integration(document: LevelDocument) -> void:
	ProjectSettings.set_setting("network/level_library_url", OS.get_environment("LEADERBOARD_TEST_URL"))
	var account := root.get_node("AccountSession")
	account.create_account("Times_" + str(Time.get_ticks_usec()), "Leaderboard integration password")
	await account.completed
	check(account.is_signed_in(), "Integration account signs in")
	if not account.is_signed_in():
		return
	var client := LibraryClient.new()
	root.add_child(client)
	client.upload_level("Leaderboard integration course", LevelCodec.encode_level(document))
	var upload = await client.completed
	check(upload[2].is_empty(), "Integration publishes the timed course: " + str(upload[2]))
	if not upload[2].is_empty():
		client.free()
		return
	var id: String = upload[1]["id"]
	check(id == LevelCodec.publication_id(document), "Godot and Worker derive the same leaderboard ID")
	client.submit_time(id, 12345)
	var saved = await client.completed
	check(saved[2].is_empty() and saved[1].get("personal_time_ms") == 12345, "Godot saves an authenticated personal time in D1")
	client.submit_time(id, 14000)
	saved = await client.completed
	check(saved[2].is_empty() and saved[1].get("personal_time_ms") == 12345 and not saved[1].get("improved", true), "A slower Godot run preserves the faster time")
	client.fetch_levels()
	var listed = await client.completed
	var found := false
	for level in listed[1].get("levels", []):
		if level["id"] == id:
			found = level.get("personal_time_ms") == 12345 and typeof(level.get("top_time_ms")) in [TYPE_INT, TYPE_FLOAT]
	check(found, "Published-level summaries return both times to Godot")
	client.fetch_times(id)
	var loaded = await client.completed
	check(loaded[2].is_empty() and loaded[1].get("leaderboard", []).size() > 0, "Godot downloads the per-level top 10")
	var records := LevelTimes.new()
	root.add_child(records)
	var custom = load("res://scenes/custom_level.tscn").instantiate()
	custom.prepare(document)
	custom.time_records = records
	custom.leaderboard_id = id
	root.add_child(custom)
	custom.race.elapsed = 11.234
	custom.race._reach_checkpoint()
	custom.race._reach_checkpoint()
	custom.free()
	var deadline := Time.get_ticks_msec() + 20000
	while records.summary(id).get("personal_time_ms") != 11234 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(records.summary(id).get("personal_time_ms") == 11234, "An actual race finish saves to D1 even after the world is freed")
	records.free()
	account.sign_out()
	await account.completed
	var denied := []
	client.completed.connect(func(code: int, _payload: Dictionary, _error: String) -> void: denied.append(code), CONNECT_ONE_SHOT)
	client.submit_time(id, 10000)
	check(not account.is_signed_in() and denied == [401], "Godot blocks signed-out time submissions before HTTP")
	client.free()

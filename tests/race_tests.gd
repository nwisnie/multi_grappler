extends SceneTree

const CustomScene := preload("res://scenes/custom_level.tscn")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func course() -> LevelDocument:
	var result := LevelDocument.new()
	result.spawn = Vector2i(10, 10)
	result.checkpoints.assign([Vector2i(15, 10), Vector2i(20, 10), Vector2i(25, 10)])
	result.race_laps = 2
	return result

func pass_hoop(race: Node2D, number: int) -> void:
	var point: Vector2 = race.hoops[number - 1].global_position
	var approach := LevelDocument.CHECKPOINT_RADIUS + LevelDocument.PLAYER_RADIUS + 2.0
	race.advance_between(point + Vector2(-approach, 0), point + Vector2(approach, 0))

func _run() -> void:
	_data_checks()
	await _editor_checks()
	await _race_checks()
	await _network_checks()
	print("RACES: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _data_checks() -> void:
	var document := course()
	var code := LevelCodec.encode_level(document)
	var decoded := LevelCodec.decode_level(code)
	check(decoded["error"].is_empty(), "Race course exports and imports")
	if decoded.has("document"):
		check(decoded["document"].checkpoints == document.checkpoints and decoded["document"].race_laps == 2 and decoded["document"].finish_checkpoint == 1, "Checkpoint order, laps and finish survive the code")
		check(LevelCodec.encode_level(decoded["document"]) == code, "Race codes are deterministic")
	var legacy_payload := PackedByteArray([1, 0, 0, 0, 255, 255])
	var legacy := LevelCodec.PREFIX + Marshalls.raw_to_base64(legacy_payload.compress(FileAccess.COMPRESSION_DEFLATE))
	var old := LevelCodec.decode_level(legacy)
	check(old["error"].is_empty() and old["document"].checkpoints.is_empty(), "Existing MG1 codes still import without checkpoints")
	check(LevelCodec.encode_level(LevelDocument.new()) == legacy, "Unchanged non-race courses keep their original code")
	var lap_limit := document.copy()
	lap_limit.race_laps = 50
	check(lap_limit.validate().is_empty() and LevelCodec.decode_level(LevelCodec.encode_level(lap_limit))["document"].race_laps == 50, "The 50-lap maximum survives level code export/import")
	lap_limit.race_laps = 51
	check(not lap_limit.validate().is_empty(), "More than 50 laps is rejected")
	lap_limit.race_laps = 0
	check(not lap_limit.validate().is_empty(), "Fewer than one lap is rejected")
	var changed := document.copy()
	changed.reorder_checkpoint(0, 4)
	check(changed.checkpoints == [Vector2i(20, 10), Vector2i(25, 10), Vector2i(15, 10)] and document.checkpoints[0] == Vector2i(15, 10), "Renumbering reorders a deep copy without changing spawn")
	changed.mark_finish(0)
	check(changed.finish_checkpoint == 4 and changed.checkpoints[-1] == Vector2i(20, 10) and changed.race_laps == 1, "Any hoop can become the last finish checkpoint")
	check(changed.validate().is_empty() and LevelCodec.decode_level(LevelCodec.encode_level(changed))["document"].finish_checkpoint == 4, "Separate finish survives export")
	changed.remove_checkpoint(0)
	check(changed.finish_checkpoint == 3, "Removing an earlier checkpoint renumbers finish")
	changed.remove_checkpoint(1)
	check(changed.finish_checkpoint == 1, "Deleting the finish restores finish at spawn")
	for trailer in [PackedByteArray([82]), PackedByteArray([82, 2, 1, 1, 20, 20]), PackedByteArray([82, 0, 0, 1]), PackedByteArray([82, 0, 51, 1]), PackedByteArray([82, 1, 1, 3, 20, 20]), PackedByteArray([82, 1, 1, 1, 100, 20]), PackedByteArray([83, 0, 1, 1])]:
		var payload := legacy_payload.duplicate()
		payload.append_array(trailer)
		var invalid := LevelCodec.PREFIX + Marshalls.raw_to_base64(payload.compress(FileAccess.COMPRESSION_DEFLATE))
		check(not LevelCodec.decode_level(invalid)["error"].is_empty(), "Malformed or invalid race trailer is rejected")
	changed = document.copy()
	changed.checkpoints.append(document.spawn)
	check(not changed.validate().is_empty(), "A hoop cannot duplicate spawn")
	changed = document.copy()
	changed.checkpoints.append(changed.checkpoints[0])
	check(not changed.validate().is_empty(), "Duplicate checkpoint cells are rejected")
	changed = LevelDocument.new()
	for index in range(LevelDocument.MAX_CHECKPOINTS):
		changed.checkpoints.append(Vector2i(index % 100, index / 100))
	changed.finish_checkpoint = 129
	var maximum := LevelCodec.decode_level(LevelCodec.encode_level(changed))
	check(maximum["error"].is_empty() and maximum["document"].checkpoints.size() == 128 and maximum["document"].finish_checkpoint == 129, "Maximum numbered checkpoint count round trips")

func _editor_checks() -> void:
	var editor: GridLevelEditor = load("res://scenes/level_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame
	await process_frame
	editor._set_tool(GridLevelEditor.Tool.CHECKPOINT)
	check(editor.checkpoint_properties.visible and editor.checkpoint_order.text == "2", "Checkpoint submenu opens immediately, including on an empty course")
	check(editor.checkpoint_order_up.disabled and editor.checkpoint_order_down.disabled and editor.checkpoint_finish.disabled, "Next checkpoint preview cannot change an unplaced hoop")
	editor._set_tool(GridLevelEditor.Tool.LINE)
	check(not editor.checkpoint_properties.visible, "Unselected checkpoint submenu hides on other tools")
	editor._commit(course())
	editor._set_tool(GridLevelEditor.Tool.CHECKPOINT)
	check(editor.checkpoint_properties.visible and editor.checkpoint_order.text == "5", "Checkpoint submenu previews the next course number before placement")
	editor.mouse_on_board = true
	editor.hover_cell = Vector2i(30, 10)
	editor._click(LevelDocument.cell_position(editor.hover_cell))
	check(editor.document.checkpoints.size() == 4 and editor.checkpoint_properties.visible, "Checkpoint tool places a numbered hoop and shows its properties")
	check(editor.checkpoint_order is Label and editor.checkpoint_order.text == "5" and editor.checkpoint_order_up.disabled, "Checkpoint number is a read-only display with its upper arrow disabled at the last number")
	editor.checkpoint_order_down.pressed.emit()
	check(editor.selection["index"] == 2 and editor.checkpoint_order.text == "4", "Custom down arrow decreases the checkpoint number")
	editor.checkpoint_order_up.pressed.emit()
	check(editor.selection["index"] == 3 and editor.checkpoint_order.text == "5", "Custom up arrow increases the checkpoint number")
	editor._change_checkpoint_number(2)
	check(editor.document.checkpoints[0] == Vector2i(30, 10) and editor.selection["index"] == 0, "Selected hoop can be renumbered")
	editor.undo()
	check(editor.document.checkpoints[-1] == Vector2i(30, 10), "Renumbering is undoable")
	editor.selection = {"kind": "checkpoint", "index": 0}
	editor._refresh_checkpoint_properties()
	check(editor.checkpoint_finish.text == "Set Finish Checkpoint" and not editor.checkpoint_finish.toggle_mode and editor.checkpoint_order_down.disabled, "Finish uses an action button and the first checkpoint cannot move earlier")
	editor.checkpoint_finish.pressed.emit()
	check(editor.document.finish_checkpoint == 5 and editor.document.checkpoints[-1] == Vector2i(15, 10) and editor.checkpoint_finish.text == "Unset Finish Checkpoint", "Setting finish moves the checkpoint to the end and updates the button text")
	check(editor.checkpoint_order_up.disabled and editor.checkpoint_order_down.disabled, "Finish numbering stays last")
	editor.hover_cell = Vector2i(35, 10)
	editor._click(LevelDocument.cell_position(editor.hover_cell))
	check(editor.document.finish_checkpoint == 6 and editor.document.checkpoints[-1] == Vector2i(15, 10) and editor.document.checkpoints[-2] == Vector2i(35, 10), "New hoops insert before a separate finish")
	editor._set_tool(GridLevelEditor.Tool.SELECT)
	editor._select_at(LevelDocument.cell_position(Vector2i(35, 10)))
	check(editor.selection.get("kind") == "checkpoint", "Select can pick checkpoint hoops")
	editor._update_drag(LevelDocument.cell_position(Vector2i(36, 10)))
	editor._finish_drag()
	check(editor.document.checkpoints[-2] == Vector2i(36, 10), "Checkpoint hoops move on the grid")
	var before := LevelCodec.encode_level(editor.document)
	editor._delete_selection()
	check(editor.document.checkpoints.size() == 4 and editor.document.finish_checkpoint == 5, "Erasing a checkpoint preserves finish and contiguous numbering")
	editor.undo()
	check(LevelCodec.encode_level(editor.document) == before, "Deletion undo restores race data exactly")
	editor._open_race_settings()
	check(editor.race_unset_finish.visible and editor.race_laps_up.disabled and editor.race_laps_down.disabled and editor.race_laps_reset.disabled, "Separate finish offers a direct unset button and disables lap arrows")
	editor.race_unset_finish.pressed.emit()
	editor.race_laps_up.pressed.emit()
	check(not editor.race_unset_finish.visible and editor.race_laps.text == "2", "Unset finish immediately enables the custom lap counter in the dialog")
	editor.race_dialog.hide()
	check(editor.document.finish_checkpoint == 6 and editor.document.race_laps == 1, "Canceling race settings leaves finish and laps unchanged")
	editor._open_race_settings()
	check(editor.race_laps.text == "1" and editor.race_unset_finish.visible, "Reopening settings discards canceled lap changes")
	editor.race_unset_finish.pressed.emit()
	for step in range(2):
		editor.race_laps_up.pressed.emit()
	editor._apply_race_settings()
	editor.race_dialog.hide()
	check(editor.document.finish_checkpoint == 1 and editor.document.race_laps == 3, "Race settings can unset finish and apply laps together")
	editor.undo()
	check(editor.document.finish_checkpoint == 6 and editor.document.race_laps == 1, "Undo restores finish and laps together")
	editor.selection = {"kind": "checkpoint", "index": editor.document.checkpoints.size() - 1}
	editor._refresh_checkpoint_properties()
	editor.checkpoint_finish.pressed.emit()
	check(editor.checkpoint_finish.text == "Set Finish Checkpoint", "Unsetting finish restores the Set Finish Checkpoint action")
	editor._open_race_settings()
	check(editor.race_laps is Label and editor.race_laps_down.disabled, "Lap count uses a read-only display and cannot decrease below one")
	editor.race_laps_down.pressed.emit()
	check(editor.race_laps.text == "1", "Lap count stays at its minimum")
	for step in range(100):
		editor.race_laps_up.pressed.emit()
	check(editor.race_laps.text == "50" and editor.race_laps_up.disabled, "Lap count caps at 50 and disables its upper arrow")
	for step in range(47):
		editor.race_laps_down.pressed.emit()
	check(editor.race_laps.text == "3" and not editor.race_laps_up.disabled, "Lap arrows decrease from the maximum and re-enable incrementing")
	check(not editor.race_laps_reset.disabled, "Reset is available when more than one lap is selected")
	editor.race_laps_reset.pressed.emit()
	check(editor.race_laps.text == "1" and editor.race_laps_down.disabled and editor.race_laps_reset.disabled and not editor.race_laps_up.disabled, "Reset returns to one lap and updates arrow/button states")
	for step in range(2):
		editor.race_laps_up.pressed.emit()
	editor._apply_race_settings()
	editor.race_dialog.hide()
	await process_frame
	await process_frame
	await process_frame
	check(editor.document.finish_checkpoint == 1 and editor.document.race_laps == 3, "Returning finish to spawn enables editable laps")
	editor._open_race_settings()
	editor.race_laps_reset.pressed.emit()
	editor.race_dialog.hide()
	check(editor.document.race_laps == 3, "Canceling a lap reset preserves the saved lap count")
	editor._open_race_settings()
	check(editor.race_laps.text == "3", "Reopening settings discards a canceled lap reset")
	editor.race_laps_reset.pressed.emit()
	editor._apply_race_settings()
	editor.race_dialog.hide()
	check(editor.document.race_laps == 1, "Confirming a lap reset saves one lap")
	editor.undo()
	check(editor.document.race_laps == 3, "Undo restores the lap count before reset")
	var race_code := LevelCodec.encode_level(editor.document)
	editor.clear_level()
	check(editor.import_code(race_code).is_empty() and editor.document.race_laps == 3 and editor.document.checkpoints.size() == 5, "Editor export/import preserves the entire race")
	editor.free()
	await process_frame

func _race_checks() -> void:
	var level = CustomScene.instantiate()
	check(level.prepare(course()).is_empty(), "Race course prepares for playtest")
	root.add_child(level)
	level.player.freeze = true
	var race = level.race
	race.set_physics_process(false)
	check(race.hoops.size() == 4 and race.next_number == 2 and race.lap == 1, "Spawn is checkpoint 1 and the first target is hoop 2")
	race.advance_between(race.hoops[0].global_position, race.hoops[3].global_position + Vector2(240, 0))
	check(race.next_number == 1, "One fast movement can cross multiple required hoops in travel order")
	race.reset()
	race.advance_between(race.hoops[3].global_position + Vector2(240, 0), race.hoops[1].global_position - Vector2(240, 0))
	check(race.next_number == 3, "Fast movement cannot count later hoops crossed before the required hoop")
	race.reset()
	var stationary: Vector2 = race.next_position()
	race.advance_between(stationary, stationary)
	check(race.next_number == 2, "Standing inside a hoop does not count as passing through it")
	level.player.set_controls_locked(true)
	race._physics_process(1.0)
	check(is_zero_approx(race.elapsed), "Opening a gameplay menu freezes the local race timer")
	level.player.set_controls_locked(false)
	race._physics_process(0.5)
	check(is_equal_approx(race.elapsed, 0.5), "Race timer advances while the player has control")
	pass_hoop(race, 4)
	pass_hoop(race, 1)
	check(race.next_number == 2 and not race.finished, "Skipping hoops or crossing finish early cannot finish a lap")
	var target: Vector2 = race.next_position()
	var pass_radius := LevelDocument.CHECKPOINT_RADIUS + LevelDocument.PLAYER_RADIUS
	race.advance_between(target + Vector2(-360, pass_radius + 24.0), target + Vector2(360, pass_radius + 24.0))
	check(race.next_number == 2, "Passing entirely outside the hoop and ball overlap does not count")
	race.advance_between(target + Vector2(-360, pass_radius - 16.0), target + Vector2(360, pass_radius - 16.0))
	check(race.next_number == 3, "Partial ball contact near the hoop rim counts as a forgiving checkpoint pass")
	race.reset()
	pass_hoop(race, 2)
	check(race.next_number == 3 and race.hoops[2].active and race.next_position() == race.hoops[2].global_position, "Passing hoop 2 advances the highlighted hoop and indicator target")
	pass_hoop(race, 4)
	check(race.next_number == 3, "A later hoop still cannot be skipped to")
	pass_hoop(race, 3)
	pass_hoop(race, 4)
	check(race.next_number == 1 and race.lap == 1 and not race.finished, "All hoops must be passed before returning to spawn")
	pass_hoop(race, 1)
	check(race.lap == 2 and race.next_number == 2 and not race.finished, "A completed circuit starts the next lap")
	pass_hoop(race, 1)
	check(race.lap == 2 and race.next_number == 2, "Remaining on spawn cannot farm laps")
	for number in [2, 3, 4, 1]:
		pass_hoop(race, number)
	check(race.finished and race.lap == 2, "Race finishes only after all hoops in all laps")
	await process_frame
	check(race.hud.status.text.contains("Race finished"), "The player's screen reports race completion")
	level.restart()
	check(level.race != race and not level.race.finished and level.race.next_number == 2 and level.race.lap == 1, "Restart resets the race, laps and target")
	level.free()
	await process_frame
	var document := course()
	document.mark_finish(0)
	level = CustomScene.instantiate()
	level.prepare(document)
	root.add_child(level)
	level.player.freeze = true
	race = level.race
	race.set_physics_process(false)
	pass_hoop(race, 4)
	check(not race.finished, "A separate finish cannot complete before earlier hoops")
	for number in [2, 3, 4]:
		pass_hoop(race, number)
	check(race.finished and race.lap == 1, "Separate finish completes without returning to spawn")
	level.free()
	await process_frame

func _network_checks() -> void:
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	shell._start_network_world("00123456", LevelCodec.encode_level(course()), true)
	await process_frame
	await process_frame
	var race = shell.world.race
	check(race != null and race.player == shell.world.player, "Hosted races attach progress and HUD to the local network player")
	race.set_physics_process(false)
	pass_hoop(race, 2)
	var player_id: int = shell.world.player.get_instance_id()
	shell.world.player.position = Vector2(-200, -200)
	for frame in range(6):
		await physics_frame
	check(race.next_number == 2 and race.lap == 1 and not race.finished, "Network respawn resets the local race")
	check(shell.world.player.get_instance_id() == player_id, "Race reset preserves the replicated player's identity")
	shell.free()
	await process_frame

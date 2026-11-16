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
	result.checkpoints.assign([Vector2i(20, 10), Vector2i(30, 10), Vector2i(40, 10)])
	result.set_checkpoint_line(1, Vector2i(10, 7), Vector2i(10, 13))
	result.set_checkpoint_line(2, Vector2i(20, 4), Vector2i(20, 16))
	result.set_checkpoint_line(4, Vector2i(40, 5), Vector2i(40, 15))
	result.spawn_line_position = 25
	result.race_laps = 2
	return result

func click_cell(editor: GridLevelEditor, point: Vector2i) -> void:
	editor.mouse_on_board = true
	editor.hover_cell = point
	editor._click(LevelDocument.cell_position(point))

func _run() -> void:
	_data_checks()
	await _editor_checks()
	await _race_checks()
	await _network_checks()
	print("CHECKPOINT LINES: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _data_checks() -> void:
	var document := course()
	check(document.validate().is_empty(), "Mixed hoop and line course validates")
	var code := LevelCodec.encode_level(document)
	var decoded := LevelCodec.decode_level(code)
	check(decoded["error"].is_empty(), "Line course imports")
	if decoded.has("document"):
		var imported: LevelDocument = decoded["document"]
		check(imported.checkpoint_lines == document.checkpoint_lines and imported.spawn_line_position == 25, "Endpoints and spawn percentage round trip")
		check(LevelCodec.encode_level(imported) == code, "Line codes are deterministic")
	check(document.spawn_position() == Vector2(1260, 1080), "Spawn uses the chosen point along its line")
	var changed := document.copy()
	changed.checkpoint_lines[2]["a"] = Vector2i(20, 2)
	check(document.checkpoint_lines[2]["a"] == Vector2i(20, 4), "Line endpoints are deeply copied")
	changed = document.copy()
	changed.reorder_checkpoint(0, 4)
	check(changed.checkpoint_lines[4] == document.checkpoint_lines[2] and changed.checkpoint_lines[3] == document.checkpoint_lines[4] and not changed.checkpoint_lines.has(2), "Renumbering moves line geometry with its checkpoint")
	check(changed.checkpoint_lines[1] == document.checkpoint_lines[1], "Renumbering preserves the spawn line")
	changed.mark_finish(2)
	changed.insert_checkpoint(2, Vector2i(35, 10))
	check(changed.finish_checkpoint == 5 and changed.checkpoint_lines[5] == document.checkpoint_lines[2], "Insertion before a separate finish preserves its line")
	changed.remove_checkpoint(0)
	check(changed.finish_checkpoint == 4 and changed.checkpoint_lines[4] == document.checkpoint_lines[2], "Deletion renumbers line geometry and finish together")
	changed.remove_checkpoint(2)
	check(changed.finish_checkpoint == 1 and not changed.checkpoint_lines.has(4), "Deleting the finish removes its line geometry")
	changed = document.copy()
	changed.move_checkpoint(2, Vector2i(22, 12))
	check(changed.checkpoint_lines[2] == {"a": Vector2i(22, 6), "b": Vector2i(22, 18)}, "Moving a whole line translates both endpoints")
	for line in [{"a": Vector2i(20, 4), "b": Vector2i(20, 4)}, {"a": Vector2i(-1, 4), "b": Vector2i(20, 16)}, {"a": Vector2i(20, 4)}, {"a": "bad", "b": Vector2i(20, 16)}]:
		changed = document.copy()
		changed.checkpoint_lines[2] = line
		check(not changed.validate().is_empty(), "Invalid checkpoint line endpoints are rejected")
	changed = document.copy()
	changed.checkpoint_lines[5] = changed.checkpoint_lines[2]
	check(not changed.validate().is_empty(), "Orphaned line geometry is rejected")
	changed = document.copy()
	changed.spawn_line_position = 101
	check(not changed.validate().is_empty(), "Spawn position outside its line is rejected")
	changed = document.copy()
	changed.segments.append({"kind": 0, "a": Vector2i(5, 9), "b": Vector2i(15, 9)})
	check(not changed.playtest_error().is_empty(), "Spawn clearance checks the actual point on the line")
	changed.spawn_line_position = 100
	check(changed.playtest_error().is_empty(), "Terrain may cross a spawn line away from the player start")
	var plain := LevelDocument.new()
	plain.spawn = Vector2i(10, 10)
	plain.checkpoints.append(Vector2i(20, 10))
	var payload := Marshalls.base64_to_raw(LevelCodec.encode_level(plain).substr(4)).decompress_dynamic(LevelCodec.MAX_PAYLOAD, FileAccess.COMPRESSION_DEFLATE)
	for trailer in [[76], [76, 0, 50], [76, 1, 101, 2, 20, 5, 20, 15], [76, 1, 50, 3, 20, 5, 20, 15], [76, 1, 50, 2, 20, 5, 20, 5], [76, 1, 50, 2, 100, 5, 20, 15], [76, 2, 50, 2, 20, 5, 20, 15, 2, 25, 5, 25, 15]]:
		var invalid := payload.duplicate()
		invalid.append_array(PackedByteArray(trailer))
		check(not LevelCodec.decode_level(LevelCodec.PREFIX + Marshalls.raw_to_base64(invalid.compress(FileAccess.COMPRESSION_DEFLATE)))["error"].is_empty(), "Malformed line trailer is rejected")
	changed = LevelDocument.new()
	changed.spawn = Vector2i(99, 99)
	for index in range(LevelDocument.MAX_CHECKPOINTS):
		changed.checkpoints.append(Vector2i(index % 100, index / 100))
	for number in range(1, LevelDocument.MAX_CHECKPOINTS + 2):
		var point := changed.checkpoint_cell(number)
		changed.checkpoint_lines[number] = {"a": point, "b": point + Vector2i(0, -1 if number == 1 else 1)}
	check(LevelCodec.decode_level(LevelCodec.encode_level(changed))["document"].checkpoint_lines.size() == 129, "All 129 checkpoints can be lines")

func _editor_checks() -> void:
	var editor: GridLevelEditor = load("res://scenes/level_editor.tscn").instantiate()
	root.add_child(editor)
	for frame in range(3):
		await process_frame
	editor.camera.zoom = Vector2.ONE
	editor._commit(course())
	editor._set_tool(GridLevelEditor.Tool.CHECKPOINT)
	click_cell(editor, Vector2i(30, 10))
	check(editor.selection == {"kind": "checkpoint", "index": 1}, "Race checkpoint tool selects an existing hoop")
	editor.checkpoint_type.item_selected.emit(1)
	check(editor.document.checkpoint_lines.has(3) and editor.checkpoint_endpoints.visible, "Selected hoop converts to a line through its properties")
	editor.checkpoint_endpoints.pressed.emit()
	click_cell(editor, Vector2i(28, 7))
	click_cell(editor, Vector2i(32, 13))
	check(editor.document.checkpoint_lines[3] == {"a": Vector2i(28, 7), "b": Vector2i(32, 13)}, "Set endpoints defines an existing line with two clicks")
	editor.undo()
	check(editor.document.checkpoint_lines[3]["a"] == Vector2i(30, 8), "Endpoint replacement is undoable")
	editor.undo()
	check(not editor.document.checkpoint_lines.has(3), "Shape conversion is undoable")
	editor.redo()
	check(editor.document.checkpoint_lines.has(3), "Shape conversion supports redo")
	editor._set_tool(GridLevelEditor.Tool.SELECT)
	editor._select_at(LevelDocument.cell_position(Vector2i(30, 10)))
	editor._update_drag(LevelDocument.cell_position(Vector2i(31, 11)))
	editor._finish_drag()
	check(editor.document.checkpoint_lines[3] == {"a": Vector2i(31, 9), "b": Vector2i(31, 13)}, "Dragging a whole checkpoint translates both endpoints")
	editor.undo()
	editor._select_at(LevelDocument.cell_position(Vector2i(30, 8)))
	check(editor.drag.get("kind") == "checkpoint_endpoint", "Select picks a line endpoint")
	editor._update_drag(LevelDocument.cell_position(Vector2i(27, 7)))
	editor._finish_drag()
	check(editor.document.checkpoint_lines[3]["a"] == Vector2i(27, 7), "Dragging reshapes a line independently")
	var before := LevelCodec.encode_level(editor.document)
	editor._select_at(LevelDocument.cell_position(Vector2i(27, 7)))
	editor._update_drag(LevelDocument.cell_position(Vector2i(30, 12)))
	editor._finish_drag()
	check(LevelCodec.encode_level(editor.document) == before, "Collapsing endpoints rolls back the drag")
	editor._set_tool(GridLevelEditor.Tool.CHECKPOINT)
	editor._change_checkpoint_type(1)
	click_cell(editor, Vector2i(50, 5))
	click_cell(editor, Vector2i(50, 5))
	check(editor.pending.size() == 1 and editor.document.checkpoints.size() == 3, "New line rejects coincident endpoints without losing the first point")
	click_cell(editor, Vector2i(50, 15))
	check(editor.document.checkpoint_lines[5] == {"a": Vector2i(50, 5), "b": Vector2i(50, 15)}, "New line placement uses two clicks")
	editor._change_checkpoint_type(0)
	check(not editor.document.checkpoint_lines.has(5), "Line converts back to a hoop")
	editor._set_tool(GridLevelEditor.Tool.CHECKPOINT)
	click_cell(editor, Vector2i(10, 10))
	check(editor.selection.get("kind") == "spawn" and editor.checkpoint_order.text == "1" and editor.spawn_position_controls.visible, "Race checkpoint tool exposes spawn line properties")
	editor.spawn_position.value = 75
	check(editor.document.spawn_position() == Vector2(1260, 1440), "Spawn percentage moves the actual point on its line")
	editor.undo()
	check(editor.document.spawn_line_position == 25, "Spawn position change is undoable")
	editor._set_tool(GridLevelEditor.Tool.SELECT)
	editor._select_at(LevelDocument.cell_position(Vector2i(10, 10)))
	editor._update_drag(LevelDocument.cell_position(Vector2i(12, 12)))
	editor._finish_drag()
	check(editor.document.spawn_position() == Vector2(1500, 1320) and editor.document.spawn_line_position == 25, "Dragging a spawn line preserves the relative player position")
	editor.undo()
	editor._set_tool(GridLevelEditor.Tool.SPAWN)
	editor._change_checkpoint_type(1)
	click_cell(editor, Vector2i(5, 20))
	click_cell(editor, Vector2i(15, 20))
	check(editor.document.checkpoint_lines[1] == {"a": Vector2i(5, 20), "b": Vector2i(15, 20)}, "Spawn tool places a two-point line")
	editor._change_checkpoint_type(0)
	check(not editor.document.checkpoint_lines.has(1), "Spawn line converts back to a point with a hoop")
	var exported := LevelCodec.encode_level(editor.document)
	editor.clear_level()
	check(editor.import_code(exported).is_empty() and LevelCodec.encode_level(editor.document) == exported, "Editor import/export preserves all line data")
	editor._set_tool(GridLevelEditor.Tool.CHECKPOINT)
	editor._change_checkpoint_type(1)
	click_cell(editor, Vector2i(70, 5))
	editor._cancel_action()
	check(editor.pending.is_empty() and editor.endpoint_checkpoint == 0 and LevelCodec.encode_level(editor.document) == exported, "Cancel discards an incomplete line")
	click_cell(editor, Vector2i(20, 10))
	editor._set_checkpoint_endpoints()
	click_cell(editor, Vector2i(20, 3))
	editor._change_checkpoint_number(3)
	check(editor.pending.is_empty() and editor.endpoint_checkpoint == 0 and editor.document.checkpoint_lines.has(3), "Renumbering cancels an unfinished endpoint replacement")
	editor._set_checkpoint_endpoints()
	click_cell(editor, Vector2i(20, 3))
	editor._delete_selection()
	check(editor.pending.is_empty() and editor.endpoint_checkpoint == 0 and editor.document.validate().is_empty(), "Deleting during endpoint replacement cancels placement and removes the line")
	editor._set_tool(GridLevelEditor.Tool.SPAWN)
	editor._change_checkpoint_type(1)
	editor._delete_selection()
	check(not editor.document.checkpoint_lines.has(1) and not LevelDocument.valid_cell(editor.document.spawn), "Deleting spawn also removes its line geometry")
	editor.undo()
	check(editor.document.checkpoint_lines.has(1), "Undo restores the deleted spawn line")
	editor.free()
	await process_frame

func _race_checks() -> void:
	var document := course()
	var level = CustomScene.instantiate()
	check(level.prepare(document).is_empty(), "Line course prepares for play")
	root.add_child(level)
	level.player.freeze = true
	level.player.set_controls_locked(false)
	var race = level.race
	race.set_physics_process(false)
	check(level.player.position == document.spawn_position(), "Local player spawns on the line at the selected percentage")
	check(race.hoops[1].line_points.size() == 2 and race.hoops[2].line_points.is_empty(), "Runtime renders both line and hoop shapes")
	var center := document.checkpoint_position(2)
	race.advance_between(center, center)
	check(race.next_number == 2, "Standing on a line cannot award checkpoints")
	race.advance_between(center + Vector2(-500, -600), center + Vector2(500, -600))
	check(race.next_number == 3, "Fast passage counts anywhere along a long line")
	race.reset()
	race.advance_between(center + Vector2(500, 0), center + Vector2(-500, 0))
	check(race.next_number == 3, "Lines count passage in either direction")
	race.reset()
	var outside := -720.0 - LevelDocument.PLAYER_RADIUS - 1.0
	race.advance_between(center + Vector2(-500, outside), center + Vector2(500, outside))
	check(race.next_number == 2, "Passing beyond the finite line endpoints does not count")
	outside += 2.0
	race.advance_between(center + Vector2(-500, outside), center + Vector2(500, outside))
	check(race.next_number == 3, "Ball contact with a line endpoint counts")
	race.reset()
	race.advance_between(center, center + Vector2(500, 0))
	check(race.next_number == 2, "Starting inside the line cannot farm progress")
	race.advance_between(document.spawn_position(), document.checkpoint_position(4) + Vector2(500, 0))
	check(race.next_number == 1, "One fast motion crosses mixed line and hoop checkpoints in order")
	var start := document.checkpoint_position(1)
	race.advance_between(start + Vector2(500, 0), start - Vector2(500, 0))
	check(race.lap == 2 and race.next_number == 2, "Spawn line closes a lap")
	race.advance_between(document.spawn_position(), document.checkpoint_position(4) + Vector2(500, 0))
	race.advance_between(start + Vector2(500, 0), start - Vector2(500, 0))
	check(race.finished, "Spawn line finishes the final lap")
	level.restart()
	check(level.player.position == document.spawn_position() and level.race.next_number == 2, "Restart restores the chosen point and race progress")
	level.free()
	await process_frame
	document.mark_finish(2)
	level = CustomScene.instantiate()
	level.prepare(document)
	root.add_child(level)
	level.player.freeze = true
	race = level.race
	race.set_physics_process(false)
	race.advance_between(document.spawn_position(), document.checkpoint_position(4) + Vector2(500, 0))
	check(race.finished and race.lap == 1, "A separate line finish ends the race")
	level.free()
	await process_frame
	document = course()
	document.set_checkpoint_line(2, Vector2i(15, 10), Vector2i(25, 10))
	document.set_checkpoint_line(3, Vector2i(27, 7), Vector2i(33, 13))
	level = CustomScene.instantiate()
	level.prepare(document)
	root.add_child(level)
	level.player.freeze = true
	race = level.race
	race.set_physics_process(false)
	center = document.checkpoint_position(2)
	race.advance_between(center - Vector2(0, 500), center + Vector2(0, 500))
	check(race.next_number == 3, "Horizontal lines count vertical passage")
	center = document.checkpoint_position(3)
	var normal := Vector2(1, -1).normalized() * 500
	race.advance_between(center - normal, center + normal)
	check(race.next_number == 4, "Diagonal lines count perpendicular passage")
	race.reset()
	level.player.position = LevelDocument.cell_position(Vector2i(15, 5))
	check(race.next_position() == LevelDocument.cell_position(Vector2i(15, 10)), "HUD targets the nearest point on a line")
	level.free()
	await process_frame

func _network_checks() -> void:
	var document := course()
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	shell._start_network_world("00123456", LevelCodec.encode_level(document), true)
	await process_frame
	await process_frame
	var player = shell.world.player
	check(player.spawn_position == document.spawn_position(), "Network player receives the chosen spawn point on the line")
	player.position = Vector2(-200, -200)
	for frame in range(6):
		await physics_frame
	check(player.position.distance_to(document.spawn_position()) < 5.0 and shell.world.race.next_number == 2, "Network respawn restores the line spawn and resets progress")
	shell.free()
	await process_frame

extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func line(a: Vector2i, b: Vector2i) -> Dictionary:
	return {"kind": LevelDocument.SegmentKind.LINE, "a": a, "b": b}

func curve(a: Vector2i, b: Vector2i, m: Vector2i) -> Dictionary:
	return {"kind": LevelDocument.SegmentKind.CURVE, "a": a, "b": b, "m": m}

func document_with(segments: Array) -> LevelDocument:
	var document := LevelDocument.new()
	document.segments.assign(segments)
	return document

func geometry_check(name: String, document: LevelDocument, expected_contours: int) -> Dictionary:
	var result := LevelGeometry.union_boundaries(LevelGeometry.polygons_for(document))
	check(result["error"].is_empty(), name + ": closed union boundaries")
	if not result["error"].is_empty():
		print(name, " diagnostic: ", result.get("debug", []))
	if result["error"].is_empty():
		check(result["contours"].size() == expected_contours, name + ": expected contour count " + str(expected_contours) + ", got " + str(result["contours"].size()))
	return result

func _run() -> void:
	var document := LevelDocument.new()
	check(LevelDocument.BOARD_SIZE == 12000.0, "100 cells of 120 world units")
	check(LevelDocument.valid_vertex(Vector2i(100, 100)) and not LevelDocument.valid_cell(Vector2i(100, 100)), "101 intersections, 100 cell centers")
	check(document.snap_vertex(Vector2(121, 238)) == Vector2i(1, 2), "integer grid snapping")
	document.segments.append(line(Vector2i(2, 2), Vector2i(4, 2)))
	check(document.snap_vertex(Vector2(285, 240)) == Vector2i(2, 2), "endpoint snap inside half a cell")
	check(document.snap_vertex(Vector2(310, 240)) == Vector2i(3, 2), "adjacent grid points do not weld")
	var curved := curve(Vector2i(10, 10), Vector2i(20, 10), Vector2i(15, 5))
	var sampled := LevelDocument.sample_segment(curved)
	check(sampled[0] == Vector2(1200, 1200) and sampled[-1] == Vector2(2400, 1200), "curve preserves endpoints")
	check(sampled[sampled.size() / 2] == Vector2(1800, 600), "curve passes exactly through third point")
	check(not LevelDocument.segment_error(curve(Vector2i(0, 0), Vector2i(100, 0), Vector2i(1, 1))).is_empty(), "analytic out-of-board curve rejection")
	check(not LevelDocument.segment_error(line(Vector2i.ZERO, Vector2i.ZERO)).is_empty(), "zero length rejected")
	document.segments.append(curve(Vector2i(4, 2), Vector2i(10, 2), Vector2i(7, 4)))
	document.move_vertex(Vector2i(4, 2), Vector2i(5, 2))
	check(document.segments[0]["b"] == Vector2i(5, 2) and document.segments[1]["a"] == Vector2i(5, 2), "shared vertex moves line and curve")
	document.spawn = Vector2i(1, 10)
	document.orbs.assign([Vector2i(20, 20), Vector2i(21, 22)])
	var code := LevelCodec.encode_level(document)
	var decoded := LevelCodec.decode_level(code)
	check(decoded["error"].is_empty(), "valid code decoded")
	if decoded.has("document"):
		check(LevelCodec.encode_level(decoded["document"]) == code, "exact deterministic code round trip")
		check(decoded["document"].segments == document.segments and decoded["document"].orbs == document.orbs and decoded["document"].spawn == document.spawn, "all defining data preserved")
	check(LevelCodec.decode_level("  " + code.substr(0, 12) + "\n" + code.substr(12) + "  ")["error"].is_empty(), "pasted whitespace accepted")
	for invalid in ["", "MG2-AAAA", "MG1-%bad", code.substr(0, code.length() - 3), "MG1-" + "A".repeat(LevelCodec.MAX_CODE_LENGTH)]:
		check(not LevelCodec.decode_level(invalid)["error"].is_empty(), "invalid code rejected")
	for invalid_payload in [PackedByteArray([2, 0, 0, 0, 255, 255]), PackedByteArray([1, 1, 0, 0, 255, 255]), PackedByteArray([1, 0, 0, 0, 255, 255, 10]), PackedByteArray([1, 1, 0, 0, 255, 255, 7, 1, 1, 2, 2]), PackedByteArray([1, 1, 0, 0, 255, 255, 0, 101, 0, 1, 0]), PackedByteArray([1, 1, 4, 0, 255, 255]), PackedByteArray([1, 0, 0, 129, 255, 255])]:
		var invalid_code := LevelCodec.PREFIX + Marshalls.raw_to_base64(invalid_payload.compress(FileAccess.COMPRESSION_DEFLATE))
		check(not LevelCodec.decode_level(invalid_code)["error"].is_empty(), "invalid payload rejected")
	var maximum := LevelDocument.new()
	for index in range(LevelDocument.MAX_SEGMENTS):
		var x := index % 99
		var y := (index / 99) % 100
		maximum.segments.append(line(Vector2i(x, y), Vector2i(x + 1, y)))
	for index in range(LevelDocument.MAX_ORBS):
		maximum.orbs.append(Vector2i(index % 100, index / 100))
	var max_code := LevelCodec.encode_level(maximum)
	check(LevelCodec.decode_level(max_code)["error"].is_empty(), "maximum counts round trip")
	var max_curves := maximum.copy()
	max_curves.segments.clear()
	for index in range(LevelDocument.MAX_SEGMENTS):
		var x := index % 97
		var y := index / 97 + 2
		max_curves.segments.append(curve(Vector2i(x, y), Vector2i(x + 2, y), Vector2i(x + 1, y - 1)))
	var curve_code := LevelCodec.encode_level(max_curves)
	var curves_decoded := LevelCodec.decode_level(curve_code)
	check(curves_decoded["error"].is_empty() and not curve_code.is_empty(), "maximum seven-byte curve payload and orbs round trip")
	if curves_decoded.has("document"):
		check(curves_decoded["document"].segments == max_curves.segments, "maximum curve points preserved exactly")
	maximum.segments.append(line(Vector2i(1, 1), Vector2i(2, 1)))
	check(not maximum.validate().is_empty() and LevelCodec.encode_level(maximum).is_empty(), "over-limit export rejected")
	print("CODE SIZES: mixed small = ", code.length(), "; 1024 lines + 128 orbs = ", max_code.length())
	var reversed := document_with([line(Vector2i(20, 10), Vector2i(10, 10)), line(Vector2i(20, 10), Vector2i(30, 10))])
	var joined := geometry_check("reversed shared endpoints", reversed, 1)
	if joined["error"].is_empty():
		var seam_distance := INF
		var ring: PackedVector2Array = joined["contours"][0]
		for index in range(ring.size()):
			seam_distance = minf(seam_distance, Vector2(2400, 1200).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(2400, 1200), ring[index], ring[(index + 1) % ring.size()])))
		check(seam_distance > 59.0, "shared joint has no internal collision cap")
	geometry_check("duplicate strokes", document_with([line(Vector2i(10, 10), Vector2i(20, 10)), line(Vector2i(20, 10), Vector2i(10, 10))]), 1)
	geometry_check("collinear overlap", document_with([line(Vector2i(10, 10), Vector2i(20, 10)), line(Vector2i(15, 10), Vector2i(25, 10))]), 1)
	geometry_check("branch", document_with([line(Vector2i(10, 10), Vector2i(20, 10)), line(Vector2i(20, 10), Vector2i(30, 10)), line(Vector2i(20, 10), Vector2i(20, 20))]), 1)
	geometry_check("crossing without shared endpoint", document_with([line(Vector2i(10, 20), Vector2i(30, 20)), line(Vector2i(20, 10), Vector2i(20, 30))]), 1)
	geometry_check("line curve joint", document_with([line(Vector2i(5, 10), Vector2i(10, 10)), curved]), 1)
	var loop := document_with([line(Vector2i(10, 10), Vector2i(20, 10)), line(Vector2i(20, 10), Vector2i(20, 20)), line(Vector2i(20, 20), Vector2i(10, 20)), line(Vector2i(10, 20), Vector2i(10, 10))])
	geometry_check("closed loop preserves hole", loop, 2)
	loop.segments.append(line(Vector2i(13, 15), Vector2i(17, 15)))
	geometry_check("island within a hole", loop, 3)
	loop.segments.append(line(Vector2i(15, 10), Vector2i(15, 20)))
	geometry_check("bridge splits hole", loop, 3)
	var spawn_test := document_with([line(Vector2i(0, 5), Vector2i(100, 5))])
	check(not spawn_test.playtest_error().is_empty(), "missing spawn blocked")
	spawn_test.spawn = Vector2i(10, 4)
	check(not spawn_test.playtest_error().is_empty(), "overlapping spawn blocked")
	spawn_test.spawn = Vector2i(10, 2)
	check(spawn_test.playtest_error().is_empty(), "clear spawn accepted")
	await _editor_checks(spawn_test)
	await _game_checks(spawn_test)
	print("LEVEL EDITOR: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _editor_checks(playable: LevelDocument) -> void:
	var editor: GridLevelEditor = load("res://scenes/level_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame
	await process_frame
	editor._commit(playable.copy())
	var original := LevelCodec.encode_level(editor.document)
	editor.clear_level()
	check(editor.document.segments.is_empty(), "clear removes terrain")
	editor.undo()
	check(LevelCodec.encode_level(editor.document) == original, "undo clear restores exact draft")
	editor.redo()
	check(editor.document.segments.is_empty(), "redo clear")
	editor.undo()
	check(not editor.import_code("bad").is_empty() and LevelCodec.encode_level(editor.document) == original, "failed import preserves draft")
	var replacement := LevelDocument.new()
	replacement.orbs.append(Vector2i(2, 3))
	check(editor.import_code(LevelCodec.encode_level(replacement)).is_empty(), "valid import replaces draft")
	editor.undo()
	check(LevelCodec.encode_level(editor.document) == original, "import is undoable")
	editor.zoom_at(Vector2(300, 300), 8.0)
	var world := editor.screen_to_world(Vector2(300, 300))
	editor.zoom_at(Vector2(300, 300), 1.2)
	check(editor.screen_to_world(Vector2(300, 300)).distance_to(world) < 0.01, "cursor anchored zoom")
	for zoom in [0.04, 0.5, 2.0]:
		editor.camera.zoom = Vector2.ONE * zoom
		var grid := Vector2(1200, 2400)
		var screen: Vector2 = (grid - editor.camera.position) * zoom + editor.get_viewport_rect().size * 0.5
		check(editor.document.snap_vertex(editor.screen_to_world(screen)) == Vector2i(10, 20), "snapping invariant at zoom " + str(zoom))
	editor._set_tool(GridLevelEditor.Tool.LINE)
	editor.mouse_on_board = true
	editor.hover_vertex = Vector2i(4, 10)
	editor._click(Vector2(480, 1200))
	editor.hover_vertex = Vector2i(8, 10)
	editor._click(Vector2(960, 1200))
	check(editor.document.segments.size() == playable.segments.size() + 1, "two click line placement")
	editor._set_tool(GridLevelEditor.Tool.CURVE)
	for vertex in [Vector2i(8, 10), Vector2i(14, 10), Vector2i(11, 13)]:
		editor.hover_vertex = vertex
		editor._click(LevelDocument.vertex_position(vertex))
	check(editor.document.segments.back()["kind"] == LevelDocument.SegmentKind.CURVE, "three click curve placement")
	var before_drag := LevelCodec.encode_level(editor.document)
	editor.drag = {"kind": "vertex", "old": Vector2i(8, 10)}
	editor.drag_original = editor.document.copy()
	editor._update_drag(Vector2(1080, 1200))
	editor._finish_drag()
	check(editor.document.segments[-2]["b"] == Vector2i(9, 10) and editor.document.segments[-1]["a"] == Vector2i(9, 10), "editor shared joint drag")
	editor.undo()
	check(LevelCodec.encode_level(editor.document) == before_drag, "joint drag undo")
	editor.drag = {"kind": "vertex", "old": Vector2i(8, 10)}
	editor.drag_original = editor.document.copy()
	editor.last_drag_grid = Vector2i(-999, -999)
	editor._update_drag(Vector2(480, 1200))
	editor._finish_drag()
	check(LevelCodec.encode_level(editor.document) == before_drag, "invalid shared vertex collapse is rejected atomically")
	editor.selection = {"kind": "segment", "index": editor.document.segments.size() - 1}
	editor._delete_selection()
	check(editor.document.segments.back()["b"] == Vector2i(8, 10), "deletion preserves neighboring segment")
	editor.undo()
	editor._set_tool(GridLevelEditor.Tool.CURVE)
	editor.hover_vertex = Vector2i(40, 40)
	editor._click(Vector2(4800, 4800))
	editor._cancel_action()
	check(editor.pending.is_empty(), "Escape cancels unfinished placement")
	editor._open_code(false)
	await process_frame
	await process_frame
	check(editor.code_dialog.size.y < editor.get_viewport_rect().size.y, "code dialog buttons fit on screen")
	check(not editor.code_text.editable and editor.code_text.text.begins_with("MG1-") and editor.copy_button.visible, "export has selectable code and clipboard fallback")
	editor.code_dialog.hide()
	editor.free()
	await process_frame

func _game_checks(playable: LevelDocument) -> void:
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	check(shell.world == null and shell.title_screen.visible, "game starts on title screen")
	shell.show_demo()
	check(shell.world != null and not shell.title_screen.visible, "tutorial opens demo")
	shell.show_editor()
	await process_frame
	await process_frame
	await process_frame
	shell.editor._commit(playable.copy())
	var draft := LevelCodec.encode_level(shell.editor.document)
	var editor_position: Vector2 = shell.editor.camera.position
	for iteration in range(3):
		shell.playtest(playable.copy())
		await physics_frame
		check(shell.world is CustomLevel and shell.world.player != null, "fresh playtest world and player")
		check(shell.world.player.scale == Vector2.ONE * 1.18, "playtest matches demo player size")
		shell.show_editor()
		await process_frame
		check(LevelCodec.encode_level(shell.editor.document) == draft and shell.editor.camera.position == editor_position, "playtest return preserves draft and camera")
	shell.playtest(playable.copy())
	await physics_frame
	var custom: CustomLevel = shell.world
	var previous_id := custom.player.get_instance_id()
	custom.player.position = Vector2(-200, -200)
	await physics_frame
	await physics_frame
	await process_frame
	check(custom.player.get_instance_id() != previous_id and custom.player.position.distance_to(LevelDocument.cell_position(playable.spawn)) < 10, "out of board respawns fresh player")
	var space := custom.get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(Vector2(1260, 0), Vector2(1260, 1200), 1)
	ray.exclude = [custom.player.get_rid()]
	var hit := space.intersect_ray(ray)
	check(not hit.is_empty() and absf(hit["position"].y - 540.0) < 1.0, "terrain physics surface matches visual half width")
	shell.show_editor()
	shell.show_demo()
	await process_frame
	shell.show_editor()
	check(LevelCodec.encode_level(shell.editor.document) == draft, "draft survives visiting demo")
	shell.free()
	await process_frame

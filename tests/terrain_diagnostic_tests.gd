extends SceneTree

const LEVEL_CODE := "MG1-eJwFwUkOgjAABVC/Ci5IaEBQSQlGqxuZZLA24gA2UjTIwvsfxvdgjca0g634EAzgQ9fIN7Yv3oYKvK3vN4muKVKZo76nohJIxe6w5yjShEURdoeLG1IkTFIR4OLGpLYgqTK+DpThmZGOmPiMOfDZ9kUreCaJ5xQkthWplmv3+NM0lJ/HqaTC8J1ezxHIVT8u2nKYXMUzm2ZLHmhnImb6ZrGw/4H/Gfc="
const JOIN_POINT := Vector2(6486.872, 9419.605)

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func issue() -> Dictionary:
	return {
		"error": "Terrain edges could not be joined. Adjust the nearby curve handles or endpoints.",
		"error_points": PackedVector2Array([JOIN_POINT, Vector2(6486.861, 9419.606)]),
		"segment_indices": [0, 1],
	}

func _run() -> void:
	var decoded := LevelCodec.decode_level(LEVEL_CODE)
	check(decoded["error"].is_empty(), "Reported level decodes")
	var document: LevelDocument = decoded["document"]
	_geometry_checks(document)
	await _editor_checks(document)
	print("TERRAIN DIAGNOSTICS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _geometry_checks(document: LevelDocument) -> void:
	check(document.playtest_error().is_empty(), "Reported level has valid definitions and a clear line spawn")
	var before := LevelCodec.encode_level(document)
	var result := LevelGeometry.union_boundaries(LevelGeometry.polygons_for(document))
	check(result["error"].is_empty(), "Tiny fragments at the reported curve joint weld correctly")
	check(result.get("contours", []).size() == 4, "Reported course retains its four terrain contours")
	var reversed := document.copy()
	reversed.segments.reverse()
	result = LevelGeometry.union_boundaries(LevelGeometry.polygons_for(reversed))
	check(result["error"].is_empty() and result.get("contours", []).size() == 4, "The same curve joins succeed in reverse segment order")
	var level = load("res://scenes/custom_level.tscn").instantiate()
	check(level.prepare(document).is_empty() and level.terrain_error.is_empty(), "Reported course prepares for play without a geometry error")
	level.free()
	check(LevelCodec.encode_level(document) == before, "Joining does not move or rewrite any level definitions")
	var nearby := LevelGeometry.segments_near_points(document, issue()["error_points"])
	check(nearby == [0, 1], "Join diagnostics identify the two affected curves")
	var lookup := {}
	var parents := {}
	var keys: Array[Vector2i] = []
	for point in [Vector2(1000, 1000), Vector2(1000.015, 1000), Vector2(1000.03, 1000), Vector2(1000.08, 1000)]:
		keys.append(LevelGeometry._weld_key(point, lookup, parents))
	check(LevelGeometry._weld_root(keys[0], parents) == LevelGeometry._weld_root(keys[2], parents), "Nearby fragment chains weld transitively")
	check(LevelGeometry._weld_root(keys[0], parents) != LevelGeometry._weld_root(keys[3], parents), "Welding preserves endpoints beyond the precision tolerance")
	var edges: Array[Dictionary] = [{"a": Vector2i(0, 0), "b": Vector2i(1000, 0)}, {"a": Vector2i(1000, 0), "b": Vector2i(2000, 0)}]
	var points := LevelGeometry._unjoined_points(edges, Vector2i.ZERO, Vector2i(2000, 0))
	check(points.size() == 2 and points.has(Vector2.ZERO) and points.has(Vector2(2, 0)), "Unjoined boundary diagnostics mark dangling ends and exclude valid intermediate joints")
	edges.append({"a": Vector2i(2000, 0), "b": Vector2i(0, 0)})
	points = LevelGeometry._unjoined_points(edges, Vector2i.ZERO, Vector2i(2000, 0))
	check(not points.is_empty(), "Contour traversal errors retain a location even with balanced vertices")

func _editor_checks(document: LevelDocument) -> void:
	var editor: GridLevelEditor = load("res://scenes/level_editor.tscn").instantiate()
	root.add_child(editor)
	for frame in range(3):
		await process_frame
	editor._commit(document.copy())
	var code := LevelCodec.encode_level(editor.document)
	editor.show_geometry_error(issue())
	check(editor.geometry_issue_button.visible, "Geometry errors expose the Show terrain issue action")
	check(editor.geometry_error_points.size() == 1, "Nearby failed endpoints share one visible marker")
	check(editor.geometry_error_segments == [0, 1], "Editor highlights both affected curves")
	check(editor.status.text.contains("54.06, 78.50") and editor.status.text.contains("Show terrain issue"), "Error text gives grid coordinates and directs the player to the marker")
	check(editor.status.modulate == Color("fda397"), "Terrain error message uses the error color")
	for frame in range(3):
		await process_frame
	var zoom := editor.camera.zoom.x
	editor.geometry_issue_button.pressed.emit()
	var screen := (JOIN_POINT - editor.camera.position) * editor.camera.zoom.x + editor.get_viewport_rect().size * 0.5
	check(editor.camera.zoom.x > zoom, "Show terrain issue zooms into the joint")
	check(screen.y > editor.top_panel.size.y and screen.y < editor.get_viewport_rect().size.y - editor.bottom_panel.size.y and screen.x > 0 and screen.x < editor.get_viewport_rect().size.x, "Focused joint stays in the workspace between toolbar and footer")
	check(LevelCodec.encode_level(editor.document) == code, "Displaying and focusing an error preserves the draft")
	editor._set_tool(GridLevelEditor.Tool.SELECT)
	check(not editor.geometry_error_points.is_empty(), "Changing tools keeps the marker visible while choosing how to edit")
	editor._select_at(LevelDocument.vertex_position(editor.document.segments[0]["a"]))
	editor._update_drag(LevelDocument.vertex_position(Vector2i(19, 71)))
	editor._cancel_action()
	check(not editor.geometry_error_points.is_empty() and LevelCodec.encode_level(editor.document) == code, "Canceling a drag preserves the original diagnostic")
	var next := editor.document.copy()
	next.race_laps = 6
	editor._commit(next)
	check(not editor.geometry_error_points.is_empty(), "Race setting changes do not hide a terrain issue")
	editor.undo()
	check(not editor.geometry_error_points.is_empty(), "Undo of non-terrain data preserves the marker")
	next = editor.document.copy()
	next.move_vertex(Vector2i(54, 78), Vector2i(55, 78))
	editor._commit(next)
	check(editor.geometry_error_points.is_empty() and editor.geometry_error_segments.is_empty() and not editor.geometry_issue_button.visible, "Terrain edits clear stale markers and highlights")
	check(not editor.status.text.contains("Red markers"), "Clearing markers removes obsolete error directions")
	editor.undo()
	editor.show_geometry_error(issue())
	editor.redo()
	check(editor.geometry_error_points.is_empty(), "Redo of terrain edits clears obsolete issue coordinates")
	editor.show_geometry_error(issue())
	editor.undo()
	check(editor.geometry_error_points.is_empty(), "Undo of terrain edits clears obsolete issue coordinates")
	editor.show_geometry_error(issue())
	editor.clear_level()
	check(editor.geometry_error_points.is_empty() and not editor.geometry_issue_button.visible, "Clearing the draft also clears diagnostic markers")
	editor.show_geometry_error({}, "Place a player spawn before playtesting.")
	check(not editor.geometry_issue_button.visible and editor.status.text == "Place a player spawn before playtesting.", "Non-geometry errors retain their message without a misleading terrain marker")
	editor.free()
	await process_frame

extends SceneTree
## Run with a desktop display driver to inspect real rendered frames.

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.is_empty():
		push_error("Desktop screenshot was empty")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://build/screenshots")
	image.save_png("res://build/screenshots/desktop-" + name + ".png")
	print("DESKTOP SCREENSHOT: ", name)

func _run() -> void:
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	await capture("title")
	shell.show_join_menu()
	await process_frame
	await process_frame
	await capture("join")
	shell.join_dialog.hide()
	shell.show_host_menu()
	await process_frame
	await process_frame
	await capture("host")
	shell.host_dialog.hide()
	shell.show_demo()
	await capture("demo")
	shell.pause_game()
	await capture("pause")
	shell.show_settings()
	await process_frame
	await process_frame
	await capture("settings")
	shell.resume_game()
	shell.show_editor()
	await process_frame
	await process_frame
	await process_frame
	print("FONT: ", shell.editor.tool_buttons[0].get_theme_font("font").resource_path)
	var document := LevelDocument.new()
	document.segments.append({"kind": 0, "a": Vector2i(10, 10), "b": Vector2i(20, 10)})
	document.segments.append({"kind": 1, "a": Vector2i(20, 10), "b": Vector2i(30, 10), "m": Vector2i(25, 5)})
	document.spawn = Vector2i(12, 8)
	document.orbs.append(Vector2i(25, 3))
	shell.editor._commit(document)
	shell.editor.camera.position = Vector2(2400, 900)
	shell.editor.camera.zoom = Vector2.ONE * 0.35
	shell.editor.queue_redraw()
	await capture("editor")
	shell.editor._set_tool(GridLevelEditor.Tool.SELECT)
	shell.editor._update_hover((Vector2(2400, 1200) - shell.editor.camera.position) * shell.editor.camera.zoom.x + Vector2(root.size) * 0.5)
	await capture("handles-hover")
	shell.editor._open_code(false)
	await capture("code")
	print("DIALOG FONT: ", shell.editor.code_text.get_theme_font("font").resource_path)
	if shell.editor.code_dialog.size.y >= root.size.y:
		push_error("Desktop code dialog overflowed the viewport")
		quit(1)
		return
	shell.editor.code_dialog.hide()
	shell.playtest(document.copy())
	await create_timer(0.5).timeout
	await capture("playtest")
	shell.pause_game()
	await process_frame
	await process_frame
	await capture("playtest-pause")
	shell.resume_game()
	shell.show_editor()
	await capture("return")
	shell.free()
	print("DESKTOP SMOKE: rendered demo, editor, code dialog, playtest, and return")
	quit()

extends SceneTree

const MenuSlide := preload("res://scripts/ui/menu_slide.gd")
var checks := 0
var failures := 0
var cancellations := 0
var main_menu_flashes := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	await create_timer(MenuSlide.ENTER_DURATION + MenuSlide.EXIT_DURATION + 0.12).timeout
	await process_frame

func try_drag_popup(dialog: ConfirmationDialog) -> void:
	var start := dialog.position
	var point := Vector2(start) + Vector2(dialog.size.x * 0.5, 16)
	var press := InputEventMouseButton.new()
	press.position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = point + Vector2(90, 55)
	motion.relative = Vector2(90, 55)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	press = InputEventMouseButton.new()
	press.position = motion.position
	press.button_index = MOUSE_BUTTON_LEFT
	root.push_input(press, true)
	await process_frame
	check(dialog.position == start, "Dragging the caption keeps %s fixed" % dialog.title)

func check_easing() -> void:
	var control := Control.new()
	control.size = Vector2(100, 100)
	root.add_child(control)
	MenuSlide.enter(control)
	var motion = control.get_node("MenuSlide")
	motion._tween.pause()
	var start := control.position.y
	motion._tween.custom_step(MenuSlide.ENTER_DURATION * 0.25)
	var first := control.position.y
	motion._tween.custom_step(MenuSlide.ENTER_DURATION * 0.25)
	var second := control.position.y
	motion._tween.custom_step(MenuSlide.ENTER_DURATION * 0.25)
	var third := control.position.y
	check(first - start > second - first and second - first > third - second, "Entrance starts fast and slows as it approaches its resting position")
	motion._tween.custom_step(MenuSlide.ENTER_DURATION * 0.25)
	MenuSlide.dismiss(control)
	motion._tween.pause()
	start = control.position.y
	motion._tween.custom_step(MenuSlide.EXIT_DURATION * 0.25)
	first = control.position.y
	motion._tween.custom_step(MenuSlide.EXIT_DURATION * 0.25)
	second = control.position.y
	motion._tween.custom_step(MenuSlide.EXIT_DURATION * 0.25)
	third = control.position.y
	check(start - first < first - second and first - second < second - third, "Exit starts slowly and accelerates toward the top of the screen")
	control.free()

func check_editor_popup(dialog: ConfirmationDialog, opener: Callable) -> void:
	opener.call()
	check(dialog.borderless and dialog.unresizable, "Editor %s has no draggable native title bar or resize handles" % dialog.title)
	check(dialog.visible and dialog.position.y < 0, "Editor %s swoops in from above" % dialog.title)
	await settle()
	check(dialog.position.y >= 0 and dialog.size.y < root.get_visible_rect().size.y, "Editor %s settles inside the viewport" % dialog.title)
	await try_drag_popup(dialog)
	dialog.get_cancel_button().pressed.emit()
	check(dialog.visible, "Editor %s stays visible during its exit" % dialog.title)
	await settle()
	check(not dialog.visible, "Editor %s finishes its dismissal" % dialog.title)

func _run() -> void:
	check_easing()
	ProjectSettings.set_setting("network/signaling_url", "invalid-url")
	ProjectSettings.set_setting("network/level_library_url", "invalid-url")
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	var title = shell.title_screen
	check(title.background == shell.level_browser.background and title.sky == shell.level_browser.sky, "Title and browser share one sky and parallax state")
	var original_sky: Vector2 = title.sky.position
	title.show_multiplayer_options()
	await create_timer(MenuSlide.EXIT_DURATION + 0.02).timeout
	check(title.multiplayer_actions.visible and title.multiplayer_actions.position.y < 0.0, "Multiplayer options enter from above after the main options leave")
	await settle()
	check(title.multiplayer_actions.position.is_equal_approx(Vector2.ZERO) and title.join_button.has_focus(), "Submenu finishes at its layout position with keyboard focus")
	check(title.sky.position.distance_to(original_sky) < 20.0, "Menu slides do not move the background offscreen")
	title.show_main_options()
	await process_frame
	check(title.multiplayer_actions.visible, "Dismissed submenu remains visible during its exit")
	title.show_editor_options()
	await settle()
	check(title.editor_actions.visible and not title.main_actions.visible and title.browse_levels_button.has_focus(), "Rapid navigation keeps the latest requested submenu")
	title.create_level_button.pressed.emit()
	check(shell.editor != null and shell.screen == shell.Screen.EDITOR and not title.visible, "Create New opens the level editor immediately without an outgoing menu slide")
	var editor = shell.editor
	await check_editor_popup(editor.code_dialog, func() -> void: editor._open_code(false))
	await check_editor_popup(editor.race_dialog, editor._open_race_settings)
	await check_editor_popup(editor.clear_dialog, editor._open_clear_dialog)
	root.get_node("AccountSession").invalidate()
	await check_editor_popup(editor.account_dialog, editor._open_upload)
	var draft := LevelDocument.new()
	draft.spawn = Vector2i(10, 2)
	draft.checkpoints.append(Vector2i(20, 2))
	draft.segments.append({"kind": 0, "a": Vector2i(0, 5), "b": Vector2i(20, 5)})
	editor._commit(draft)
	var account = root.get_node("AccountSession")
	account._apply_session({"user": {"id": "test-user", "username": "Tester"}, "token": "b".repeat(64), "expires_at": (Time.get_unix_time_from_system() + 3600) * 1000})
	await check_editor_popup(editor.upload_dialog, editor._open_upload)
	account.invalidate()
	editor._open_code(true)
	await settle()
	editor.code_text.text = "invalid-code"
	editor._confirm_code()
	check(editor.code_dialog.visible and not editor.code_error.text.is_empty(), "Import errors keep the animated editor dialog open")
	editor.code_text.text = LevelCodec.encode_level(draft)
	editor._confirm_code()
	await settle()
	check(not editor.code_dialog.visible, "A valid import dismisses its editor dialog")
	editor._open_race_settings()
	await settle()
	editor.race_lap_count = 2
	editor.race_dialog.confirmed.emit()
	await settle()
	check(not editor.race_dialog.visible and editor.document.race_laps == 2, "Race confirmation applies the settings and dismisses the animated dialog")
	editor._open_clear_dialog()
	await settle()
	editor.clear_dialog.confirmed.emit()
	await settle()
	check(not editor.clear_dialog.visible and editor.document.segments.is_empty(), "Clear confirmation clears the draft and dismisses the animated dialog")
	editor._open_code(false)
	editor.suspend()
	editor.resume()
	await settle()
	check(not editor.code_dialog.visible, "Suspending the editor cancels its popup animation")
	shell.show_main_menu()
	shell.show_level_browser()
	var browser = shell.level_browser
	var id := "a".repeat(64)
	browser._received(200, {"levels": [{"id": id, "title": "Animated rankings"}]}, "")
	browser._show_leaderboard(id)
	check(browser.leaderboard_dialog.visible and browser.leaderboard_dialog.position.y < 0, "Top Times enters from above like the other popups")
	check(browser.leaderboard_dialog.borderless and browser.leaderboard_dialog.unresizable, "Top Times cannot be dragged or resized")
	await settle()
	check(browser.leaderboard_dialog.position.y >= 0, "Top Times settles inside the viewport after its response is laid out")
	await try_drag_popup(browser.leaderboard_dialog)
	browser.leaderboard_dialog.get_ok_button().pressed.emit()
	check(browser.leaderboard_dialog.visible, "Top Times remains visible during its animated Close")
	await settle()
	check(not browser.leaderboard_dialog.visible, "Top Times hides after its exit animation")
	browser._show_leaderboard(id)
	await settle()
	var close_times := InputEventKey.new()
	close_times.keycode = KEY_ESCAPE
	close_times.pressed = true
	root.push_input(close_times, true)
	await settle()
	check(not browser.leaderboard_dialog.visible and browser.visible, "Escape dismisses Top Times while keeping the level browser open")
	shell.show_main_menu()
	title.tutorial_button.pressed.emit()
	check(shell.screen == shell.Screen.TUTORIAL and shell.world != null and not title.visible, "Tutorial starts immediately without an outgoing menu slide")
	await settle()
	check(shell.screen == shell.Screen.TUTORIAL, "No stale menu transition changes the tutorial screen")
	shell.show_main_menu()

	shell.show_settings()
	check(shell.settings_dialog.position.y < 0, "Settings starts above the viewport")
	await settle()
	check(shell.settings_dialog.position.y >= 0, "Settings settles inside the viewport after fitting")
	check(absf(shell.settings_back_button.get_global_rect().get_center().x - float(shell.settings_dialog.size.x) * 0.5) < 1.0, "Settings Back button is centered horizontally")
	var settings_y: int = shell.settings_dialog.position.y
	shell.settings_back_button.pressed.emit()
	await create_timer(MenuSlide.EXIT_DURATION * 0.5).timeout
	check(shell.settings_dialog.visible and shell.settings_dialog.position.y < settings_y, "Back slides Settings up before hiding it")
	await settle()
	check(not shell.settings_dialog.visible and not shell.dimmer.visible and title.settings_button.has_focus(), "Settings dismissal restores the title focus and removes dimming")
	shell.show_settings()
	await settle()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await settle()
	check(not shell.settings_dialog.visible and not shell.dimmer.visible, "A GUI Escape event dismisses the active popup")

	shell.show_settings()
	await settle()
	shell.account_sign_in.pressed.emit()
	await settle()
	check(shell.account_dialog.visible and not shell.settings_dialog.visible, "Account choices slide in after Settings slides out")
	shell.account_dialog._show_form(true)
	await settle()
	check(shell.account_dialog.position.y >= 0 and shell.account_dialog.size.y < root.get_visible_rect().size.y, "Account form resizing preserves its final position")
	shell.account_dialog.get_cancel_button().pressed.emit()
	await settle()
	check(not shell.account_dialog.visible and shell.settings_dialog.visible, "Account cancellation returns to Settings after its exit")
	shell._close_settings()
	await settle()

	shell.show_join_menu()
	await settle()
	check(shell.join_dialog.position.y >= 0 and shell.join_dialog.size.y < root.get_visible_rect().size.y, "Join dialog fits after its entrance")
	shell.join_dialog.get_cancel_button().pressed.emit()
	await settle()
	check(not shell.join_dialog.visible and not shell.dimmer.visible, "Join Back completes its exit and removes the modal overlay")
	shell.show_host_menu()
	await settle()
	shell.host_dialog.canceled.connect(func() -> void: cancellations += 1)
	shell.host_dialog.get_cancel_button().pressed.emit()
	shell.host_dialog.get_cancel_button().pressed.emit()
	await settle()
	check(not shell.host_dialog.visible and cancellations == 1, "Repeated Back input emits cancellation once")

	shell.show_settings()
	await settle()
	shell._close_settings()
	shell.show_settings()
	await settle()
	check(shell.settings_dialog.visible and shell.dimmer.visible, "Reopening a closing popup cancels its old dismissal")
	shell.show_main_menu()
	await settle()
	check(not shell.settings_dialog.visible and not shell.dimmer.visible, "Screen cleanup cancels pending popup animations")

	shell.menu_background.parallax_offset = Vector2(0.6, -0.4)
	shell.menu_background._process(0.0)
	var sky_before_browser: Vector2 = title.sky.position
	var offset_before_browser: Vector2 = shell.menu_background.parallax_offset
	shell.show_level_browser()
	check(shell.menu_background.visible and shell.level_browser.sky.position.is_equal_approx(sky_before_browser) and shell.menu_background.parallax_offset.is_equal_approx(offset_before_browser), "Opening Browse Levels preserves the exact sky position and smoothing state")
	check(shell.level_browser.content.position.y < 0.0, "Community Levels content enters from above")
	await settle()
	check(shell.level_browser.content.position.is_equal_approx(Vector2.ZERO), "Community Levels content settles without changing sky parallax")
	check(not shell.menu_background.parallax_offset.is_equal_approx(offset_before_browser), "Parallax keeps responding while Browse Levels is open")
	var sky_before_return: Vector2 = shell.level_browser.sky.position
	var offset_before_return: Vector2 = shell.menu_background.parallax_offset
	shell._leave_level_browser()
	check(shell.menu_background.visible and title.sky.position.is_equal_approx(sky_before_return) and shell.menu_background.parallax_offset.is_equal_approx(offset_before_return), "Returning from Browse Levels preserves the exact sky position and smoothing state")
	check(title.menu_content.position.is_equal_approx(-offset_before_return * title.MENU_PARALLAX), "Returning menu options immediately use the current shared parallax offset")
	shell.show_level_browser()
	await settle()
	shell.level_browser.play_requested.disconnect(shell.play_community_level)
	var document := LevelDocument.new()
	document.spawn = Vector2i(10, 2)
	document.segments.append({"kind": 0, "a": Vector2i(0, 5), "b": Vector2i(20, 5)})
	shell.level_browser.loading_level = true
	shell.level_browser._received(200, {"level": {"level_code": LevelCodec.encode_level(document)}}, "")
	await settle()
	check(shell.level_browser.content.visible and shell.level_browser.content.position.is_equal_approx(Vector2.ZERO) and not shell.level_browser.refresh_button.disabled, "Failed navigation restores the browser content and permits retry")
	shell.level_browser.play_requested.connect(shell.play_community_level)
	title.main_actions.visibility_changed.connect(func() -> void:
		if title.main_actions.is_visible_in_tree():
			main_menu_flashes += 1
	)
	shell.level_browser.back_button.pressed.emit()
	await process_frame
	check(shell.level_browser.visible, "Community Levels remains visible until its content leaves")
	await create_timer(MenuSlide.EXIT_DURATION + 0.02).timeout
	check(title.editor_actions.visible and title.editor_actions.position.y < 0.0 and not title.main_actions.visible, "Browser Back slides the editor submenu in directly after the browser exits")
	await settle()
	check(not shell.level_browser.visible and title.editor_actions.visible and title.browse_levels_button.has_focus() and main_menu_flashes == 0, "Browser Back restores editor focus without ever showing the main options")
	shell.show_level_browser()
	await settle()
	escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await settle()
	check(not shell.level_browser.visible and title.editor_actions.visible and main_menu_flashes == 0, "Browser Escape also returns directly to the editor submenu")
	shell.show_level_browser()
	shell.level_browser.loading_level = true
	shell.level_browser._received(200, {"level": {"level_code": LevelCodec.encode_level(document)}}, "")
	check(shell.screen == shell.Screen.COMMUNITY_LEVEL and not shell.level_browser.visible, "Playing a community level changes screen immediately without an outgoing menu slide")

	shell.show_demo()
	check(not shell.menu_background.visible, "The menu background hides when gameplay begins")
	shell.pause_game()
	await settle()
	shell.show_settings()
	await settle()
	check(paused and shell.settings_dialog.visible and not shell.pause_dialog.visible, "Menu transitions run while gameplay stays paused")
	shell._close_settings()
	await settle()
	shell.resume_game()
	await process_frame
	check(paused, "Gameplay stays paused throughout the menu exit")
	await settle()
	check(not paused and not shell.pause_dialog.visible, "Gameplay resumes after the menu has left")
	shell.free()
	await process_frame
	print("MENU MOTION: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

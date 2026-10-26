extends Node
## Owns navigation and preserves the editor draft across menus and playtests.

const DemoScene := preload("res://base_level.tscn")
const EditorScene := preload("res://scenes/level_editor.tscn")
const CustomScene := preload("res://scenes/custom_level.tscn")
const TitleScene := preload("res://scenes/title_screen.tscn")
const DialogStyle := preload("res://scripts/ui/menu_dialog_style.gd")
const NetworkWorld := preload("res://scripts/network/network_world.gd")
const SessionScript := preload("res://scripts/network/network_session.gd")
const TitleMenuButton := preload("res://scripts/ui/title_menu_button.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")

enum Screen { MAIN_MENU, TUTORIAL, EDITOR, PLAYTEST, MULTIPLAYER }

var screen: int = Screen.MAIN_MENU
var world: Node
var editor: GridLevelEditor
var title_screen: Control
var menu_layer: CanvasLayer
var dimmer: ColorRect
var join_dialog: ConfirmationDialog
var room_code: LineEdit
var join_message: Label
var pending_room_code := ""
var host_dialog: ConfirmationDialog
var host_name: LineEdit
var host_player_limit: SpinBox
var host_level_code: TextEdit
var host_message: Label
var session: SessionScript
var room_card: Control
var copy_room_button: Button
var session_notice: ConfirmationDialog
var loading_screen: ColorRect
var loading_title: Label
var loading_message: Label
var loading_origin: ConfirmationDialog
var loading_elapsed := 0.0
var pause_dialog: ConfirmationDialog
var resume_button: Button
var pause_editor_button: Button
var pause_restart_button: Button
var settings_dialog: ConfirmationDialog
var camera_zoom_slider: HSlider
var wall_cursor_toggle: CheckButton
var fullscreen_toggle: CheckButton
var camera_zoom := 0.65
var show_wall_cursor := false
var resume_waiting_for_release := false

func _ready() -> void:
	# UI remains responsive while the gameplay subtree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 40
	add_child(menu_layer)
	title_screen = TitleScene.instantiate()
	menu_layer.add_child(title_screen)
	title_screen.tutorial_requested.connect(show_demo)
	title_screen.editor_requested.connect(show_editor)
	title_screen.join_requested.connect(show_join_menu)
	title_screen.host_requested.connect(show_host_menu)
	dimmer = ColorRect.new()
	dimmer.color = Color(0.015, 0.035, 0.06, 0.7)
	menu_layer.add_child(dimmer)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.hide()
	_build_join_menu()
	_build_host_menu()
	_build_pause_menu()
	_build_settings_menu()
	session = SessionScript.new()
	session.name = "NetworkSession"
	add_child(session)
	session.session_started.connect(_start_network_world)
	session.session_ended.connect(_session_ended)
	session.status_changed.connect(_network_status)
	session.peer_arrived.connect(_network_peer_arrived)
	session.peer_left.connect(_network_peer_left)
	_build_room_card()
	session_notice = ConfirmationDialog.new()
	session_notice.title = "Multiplayer"
	DialogStyle.apply(session_notice, true)
	session_notice.get_cancel_button().hide()
	menu_layer.add_child(session_notice)
	_build_loading_screen()
	show_main_menu()

func _build_loading_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	loading_screen = ColorRect.new()
	loading_screen.name = "NetworkLoadingScreen"
	loading_screen.color = Color("d7edff")
	loading_screen.theme = MenuTheme.get_theme()
	layer.add_child(loading_screen)
	loading_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	loading_screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 400
	column.add_theme_constant_override("separation", 20)
	center.add_child(column)
	loading_title = Label.new()
	loading_title.text = "Loading..."
	loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_title.add_theme_font_size_override("font_size", 40)
	loading_title.add_theme_color_override("font_color", Color.BLACK)
	loading_title.add_theme_constant_override("outline_size", 0)
	column.add_child(loading_title)
	loading_message = _label("")
	loading_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_message.add_theme_color_override("font_color", Color.BLACK)
	loading_message.add_theme_constant_override("outline_size", 0)
	column.add_child(loading_message)
	var cancel := TitleMenuButton.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size.y = 58
	cancel.pressed.connect(show_main_menu)
	column.add_child(cancel)
	DialogStyle.ButtonPulse.install(cancel, false, true)
	loading_screen.hide()

func _show_network_loading(message: String, origin: ConfirmationDialog = null) -> void:
	loading_origin = origin
	loading_elapsed = 0.0
	loading_message.text = message
	join_dialog.hide()
	host_dialog.hide()
	dimmer.hide()
	loading_screen.show()

func _network_player_spawned(player: RigidBody2D) -> void:
	_apply_player_settings(player)
	player.spawn_controls_pending = false
	player.set_controls_locked(true)
	_finish_network_loading.call_deferred(player)

func _finish_network_loading(player: RigidBody2D) -> void:
	# Reveal gameplay after the local player's camera and UI have had a frame to settle.
	await get_tree().process_frame
	if screen != Screen.MULTIPLAYER or not is_instance_valid(player) or _player() != player:
		return
	loading_screen.hide()
	loading_origin = null
	resume_waiting_for_release = true

func _build_room_card() -> void:
	# Fixed viewport-relative bounds keep long connection messages out of the HUD.
	room_card = Control.new()
	room_card.name = "RoomCodeCard"
	room_card.theme = MenuTheme.get_theme()
	room_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(room_card)
	room_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	room_card.offset_left = -160
	room_card.offset_right = 160
	room_card.offset_top = 12
	room_card.offset_bottom = 106
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	room_card.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var caption := Label.new()
	caption.text = "Join With This Code:"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 0)
	column.add_child(caption)
	copy_room_button = TitleMenuButton.new()
	copy_room_button.name = "RoomCode"
	copy_room_button.custom_minimum_size.y = 60
	copy_room_button.add_theme_font_size_override("font_size", 32)
	copy_room_button.add_theme_color_override("font_color", Color.BLACK)
	copy_room_button.focus_mode = Control.FOCUS_NONE
	copy_room_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	copy_room_button.tooltip_text = "Click to copy the room code"
	copy_room_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(copy_room_button.text))
	column.add_child(copy_room_button)
	DialogStyle.ButtonPulse.install(copy_room_button, false, true)
	room_card.hide()

func _exit_tree() -> void:
	# Removing this shell must never leave a later scene paused.
	if get_tree() != null:
		get_tree().paused = false

func _process(delta: float) -> void:
	if loading_screen.visible:
		loading_elapsed += delta
		loading_title.text = "Loading" + ".".repeat(1 + int(loading_elapsed * 2.0) % 3)
	if resume_waiting_for_release and not get_tree().paused:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_key_pressed(KEY_SPACE):
			resume_waiting_for_release = false
			var player := _player()
			if player != null:
				player.set_controls_locked(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			if loading_screen.visible:
				if event.keycode == KEY_ESCAPE:
					show_main_menu()
			elif settings_dialog.visible:
				_close_settings()
			elif pause_dialog.visible:
				resume_game()
			elif is_instance_valid(world):
				pause_game()
			else:
				return
			get_viewport().set_input_as_handled()

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	DialogStyle.ButtonPulse.install(button, false, true)
	return button

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 380
	return label

func _dialog(title: String, cancel_text: String) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.exclusive = true
	DialogStyle.apply(dialog, true)
	dialog.cancel_button_text = cancel_text
	menu_layer.add_child(dialog)
	for button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return dialog

func _column(dialog: ConfirmationDialog) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(380, 0)
	column.add_theme_constant_override("separation", 14)
	dialog.add_child(column)
	return column

func _popup(dialog: ConfirmationDialog) -> void:
	dialog.popup_centered(Vector2i(420, 0))
	if dialog == pause_dialog:
		resume_button.grab_focus.call_deferred()
	# Let wrapped labels settle before shrinking away their early minimum height.
	_fit_popup.call_deferred(dialog)

func _fit_popup(dialog: ConfirmationDialog) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(dialog) and dialog.visible:
		dialog.reset_size()
		dialog.move_to_center()

func _build_join_menu() -> void:
	join_dialog = _dialog("Join Game", "Back")
	join_dialog.ok_button_text = "Join"
	join_dialog.dialog_hide_on_ok = false
	join_dialog.confirmed.connect(_submit_join)
	join_dialog.canceled.connect(_cancel_connection)
	var column := _column(join_dialog)
	column.add_child(_label("Enter the 8-digit room code from your host."))
	room_code = LineEdit.new()
	room_code.placeholder_text = "00000000"
	room_code.max_length = 8
	room_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_code.add_theme_font_size_override("font_size", 30)
	room_code.add_theme_stylebox_override("normal", join_dialog.theme.get_stylebox("normal", "LineEdit"))
	room_code.add_theme_stylebox_override("focus", join_dialog.theme.get_stylebox("focus", "LineEdit"))
	room_code.text_changed.connect(_validate_room_code)
	room_code.text_submitted.connect(func(_text: String) -> void: _submit_join())
	column.add_child(room_code)
	join_message = _label("")
	column.add_child(join_message)

static func valid_room_code(text: String) -> bool:
	if text.length() != 8:
		return false
	for index in range(8):
		if text.unicode_at(index) < 48 or text.unicode_at(index) > 57:
			return false
	return true

func _validate_room_code(text: String) -> void:
	var valid := valid_room_code(text)
	join_dialog.get_ok_button().disabled = not valid
	join_message.text = "Ready to join." if valid else "Use exactly 8 digits (0-9)."

func _submit_join() -> void:
	_validate_room_code(room_code.text)
	if not valid_room_code(room_code.text):
		return
	pending_room_code = room_code.text
	join_dialog.get_ok_button().disabled = true
	_show_network_loading("Finding the host...", join_dialog)
	session.join_game(SessionScript.default_url(), pending_room_code)

func show_join_menu() -> void:
	dimmer.show()
	room_code.text = ""
	pending_room_code = ""
	_validate_room_code("")
	_popup(join_dialog)
	room_code.grab_focus.call_deferred()

func _build_host_menu() -> void:
	host_dialog = _dialog("Host Game", "Back")
	host_dialog.ok_button_text = "Create room"
	host_dialog.dialog_hide_on_ok = false
	host_dialog.canceled.connect(_cancel_connection)
	host_dialog.confirmed.connect(_submit_host)
	var column := _column(host_dialog)
	column.add_theme_constant_override("separation", 8)
	column.add_child(_label("Paste a level code from the editor, then share your room's 8-digit code. Leaving ends the session for everyone."))
	column.add_child(_label("Game name"))
	host_name = LineEdit.new()
	host_name.text = "My game"
	host_name.max_length = 32
	host_name.add_theme_stylebox_override("normal", host_dialog.theme.get_stylebox("normal", "LineEdit"))
	column.add_child(host_name)
	column.add_child(_label("Maximum players"))
	host_player_limit = SpinBox.new()
	host_player_limit.min_value = 2
	host_player_limit.max_value = 8
	host_player_limit.value = 4
	column.add_child(host_player_limit)
	column.add_child(_label("Level code"))
	host_level_code = TextEdit.new()
	host_level_code.placeholder_text = "MG1-..."
	host_level_code.custom_minimum_size = Vector2(380, 90)
	host_level_code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(host_level_code)
	host_message = _label("")
	column.add_child(host_message)

func _submit_host() -> void:
	var decoded := LevelCodec.decode_level(host_level_code.text)
	if not decoded["error"].is_empty():
		host_message.text = decoded["error"]
		return
	var document: LevelDocument = decoded["document"]
	var error := document.playtest_error()
	if not error.is_empty():
		host_message.text = error
		return
	host_dialog.get_ok_button().disabled = true
	_show_network_loading("Creating your room...", host_dialog)
	session.host_game(SessionScript.default_url(), LevelCodec.encode_level(document), int(host_player_limit.value), host_name.text)

func _cancel_connection() -> void:
	session.close()
	dimmer.hide()
	host_dialog.get_ok_button().disabled = false
	_validate_room_code(room_code.text)

func show_host_menu() -> void:
	dimmer.show()
	host_message.text = ""
	host_dialog.get_ok_button().disabled = false
	_popup(host_dialog)
	host_dialog.get_cancel_button().grab_focus.call_deferred()

func _build_pause_menu() -> void:
	pause_dialog = _dialog("Paused", "Resume")
	pause_dialog.get_ok_button().hide()
	pause_dialog.get_cancel_button().hide()
	pause_dialog.canceled.connect(resume_game)
	var column := _column(pause_dialog)
	resume_button = _button("Resume", resume_game)
	column.add_child(resume_button)
	column.add_child(_button("Return to Main Menu", show_main_menu))
	column.add_child(_button("Settings", show_settings))
	pause_editor_button = _button("Back to Level Editor", show_editor)
	pause_restart_button = _button("Restart Level", _restart_playtest)
	column.add_child(pause_editor_button)
	column.add_child(pause_restart_button)

func _build_settings_menu() -> void:
	settings_dialog = _dialog("Settings", "Back")
	settings_dialog.get_ok_button().hide()
	settings_dialog.canceled.connect(_close_settings)
	var column := _column(settings_dialog)
	var zoom_label := _label("Camera zoom: %d%%" % roundi(camera_zoom * 100.0))
	column.add_child(zoom_label)
	camera_zoom_slider = HSlider.new()
	camera_zoom_slider.min_value = 0.45
	camera_zoom_slider.max_value = 0.85
	camera_zoom_slider.step = 0.01
	camera_zoom_slider.value = camera_zoom
	camera_zoom_slider.value_changed.connect(func(value: float) -> void:
		camera_zoom = value
		zoom_label.text = "Camera zoom: %d%%" % roundi(value * 100.0)
		_apply_player_settings(_player())
	)
	column.add_child(camera_zoom_slider)
	wall_cursor_toggle = CheckButton.new()
	wall_cursor_toggle.text = "Show wall grapple cursor"
	wall_cursor_toggle.toggled.connect(func(enabled: bool) -> void:
		show_wall_cursor = enabled
		_apply_player_settings(_player())
	)
	DialogStyle.ButtonPulse.install(wall_cursor_toggle, false, true)
	column.add_child(wall_cursor_toggle)
	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "Fullscreen"
	fullscreen_toggle.toggled.connect(func(enabled: bool) -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	)
	DialogStyle.ButtonPulse.install(fullscreen_toggle, false, true)
	column.add_child(fullscreen_toggle)

func _player() -> RigidBody2D:
	if world is CustomLevel:
		return world.player
	if is_instance_valid(world):
		return world.get_node_or_null("Ball") as RigidBody2D
	return null

func _apply_player_settings(player: RigidBody2D) -> void:
	if is_instance_valid(player):
		player.initial_camera_zoom = Vector2.ONE * camera_zoom
		player.show_grapple_cursor = show_wall_cursor
		if screen == Screen.MULTIPLAYER and (pause_dialog.visible or settings_dialog.visible):
			player.spawn_controls_pending = false
			player.set_controls_locked(true)

func pause_game() -> void:
	if not is_instance_valid(world):
		return
	var player := _player()
	if player != null:
		if screen == Screen.MULTIPLAYER:
			player.spawn_controls_pending = false
		player.set_controls_locked(true)
	resume_waiting_for_release = false
	get_tree().paused = screen != Screen.MULTIPLAYER
	dimmer.show()
	pause_editor_button.visible = screen == Screen.PLAYTEST
	pause_restart_button.visible = screen == Screen.PLAYTEST
	_popup(pause_dialog)

func resume_game() -> void:
	settings_dialog.hide()
	pause_dialog.hide()
	dimmer.hide()
	get_tree().paused = false
	# A menu click or held Space must not charge an attack or fire a grapple.
	resume_waiting_for_release = true

func show_settings() -> void:
	pause_dialog.hide()
	fullscreen_toggle.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	_popup(settings_dialog)

func _close_settings() -> void:
	settings_dialog.hide()
	if is_instance_valid(world):
		_popup(pause_dialog)

func _clear_menus() -> void:
	loading_screen.hide()
	loading_origin = null
	get_tree().paused = false
	resume_waiting_for_release = false
	for dialog in [pause_dialog, settings_dialog, join_dialog, host_dialog]:
		dialog.hide()
	dimmer.hide()

func _dispose_world() -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = null

func show_main_menu() -> void:
	if is_instance_valid(session):
		session.close()
	if is_instance_valid(room_card):
		room_card.hide()
	_clear_menus()
	if is_instance_valid(editor):
		editor.suspend()
	_dispose_world()
	screen = Screen.MAIN_MENU
	title_screen.show()
	title_screen.tutorial_button.grab_focus.call_deferred()

func show_demo() -> void:
	_clear_menus()
	title_screen.hide()
	if is_instance_valid(editor):
		editor.suspend()
	_dispose_world()
	screen = Screen.TUTORIAL
	world = DemoScene.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	_apply_player_settings(_player())

func show_editor() -> void:
	_clear_menus()
	title_screen.hide()
	_dispose_world()
	screen = Screen.EDITOR
	if not is_instance_valid(editor):
		editor = EditorScene.instantiate()
		editor.exit_requested.connect(show_main_menu)
		editor.playtest_requested.connect(playtest)
		add_child(editor)
	else:
		editor.resume()

func playtest(document: LevelDocument) -> void:
	var custom: CustomLevel = CustomScene.instantiate()
	var error := custom.prepare(document)
	if not error.is_empty():
		custom.free()
		editor._set_status(error, true)
		return
	_clear_menus()
	title_screen.hide()
	editor.suspend()
	_dispose_world()
	screen = Screen.PLAYTEST
	world = custom
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	custom.player_spawned.connect(_apply_player_settings)
	add_child(world)

func _restart_playtest() -> void:
	resume_game()
	if world is CustomLevel:
		world.restart()

func _network_status(message: String) -> void:
	join_message.text = message
	host_message.text = message
	if loading_screen.visible:
		loading_message.text = message

func _start_network_world(code: String, level_code: String, _hosting: bool) -> void:
	var decoded := LevelCodec.decode_level(level_code)
	if not decoded["error"].is_empty():
		_session_ended("The host supplied an invalid level code: " + decoded["error"])
		return
	var custom := NetworkWorld.new()
	custom.name = "NetworkWorld"
	var error := custom.prepare(decoded["document"])
	if not error.is_empty():
		custom.free()
		_session_ended("Could not load the host's level: " + error)
		return
	_clear_menus()
	_show_network_loading("Loading the level and waiting for your player...")
	title_screen.hide()
	if is_instance_valid(editor):
		editor.suspend()
	_dispose_world()
	screen = Screen.MULTIPLAYER
	world = custom
	custom.player_spawned.connect(_network_player_spawned)
	add_child(custom)
	copy_room_button.text = code
	room_card.show()

func _network_peer_arrived(peer_id: int) -> void:
	if screen == Screen.MULTIPLAYER and session.hosting:
		world.add_player(peer_id)

func _network_peer_left(peer_id: int) -> void:
	if screen == Screen.MULTIPLAYER and session.hosting:
		world.remove_player(peer_id)

func _session_ended(reason: String) -> void:
	var origin := loading_origin
	loading_screen.hide()
	loading_origin = null
	if session.active:
		session.close()
	if screen == Screen.MULTIPLAYER:
		show_main_menu()
		session_notice.dialog_text = reason
		session_notice.popup_centered(Vector2i(480, 0))
	else:
		join_message.text = reason
		host_message.text = reason
		host_dialog.get_ok_button().disabled = false
		join_dialog.get_ok_button().disabled = not valid_room_code(room_code.text)
		if is_instance_valid(origin):
			dimmer.show()
			_popup(origin)

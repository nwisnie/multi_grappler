extends Node
## Owns navigation and preserves the editor draft across menus and playtests.

const DemoScene := preload("res://scenes/base_level.tscn")
const EditorScene := preload("res://scenes/level_editor.tscn")
const CustomScene := preload("res://scenes/custom_level.tscn")
const TitleScene := preload("res://scenes/title_screen.tscn")
const DialogStyle := preload("res://scripts/ui/menu_dialog_style.gd")
const NetworkWorld := preload("res://scripts/network/network_world.gd")
const SessionScript := preload("res://scripts/network/network_session.gd")
const TitleMenuButton := preload("res://scripts/ui/title_menu_button.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const LevelBrowser := preload("res://scripts/ui/level_browser.gd")
const AccountDialog := preload("res://scripts/ui/account_dialog.gd")
const MenuSlide := preload("res://scripts/ui/menu_slide.gd")
const MenuBackground := preload("res://scripts/ui/menu_background.gd")
const SavedLevels := preload("res://scripts/levels/saved_levels.gd")
const LevelTimes := preload("res://scripts/levels/level_times.gd")

enum Screen { MAIN_MENU, TUTORIAL, EDITOR, PLAYTEST, MULTIPLAYER, LEVEL_BROWSER, COMMUNITY_LEVEL }

var account_session: Node
var account_from_pause := false
var screen: int = Screen.MAIN_MENU
var world: Node
var editor: GridLevelEditor
var title_screen: Control
var level_browser: LevelBrowser
var saved_levels := SavedLevels.new()
var time_records: LevelTimes
var browsing_for_host := false
var active_level_metadata: Dictionary = {}
var return_browser_view: int = LevelBrowser.View.COMMUNITY
var pause_browser_button: Button
var menu_layer: CanvasLayer
var menu_background: MenuBackground
var dimmer: ColorRect
var join_dialog: ConfirmationDialog
var room_code: LineEdit
var join_message: Label
var public_lobbies: VBoxContainer
var public_lobby_status: Label
var refresh_lobbies_button: Button
var lobby_request: HTTPRequest
var pending_room_code := ""
var host_dialog: ConfirmationDialog
var host_name: LineEdit
var host_player_limit: SpinBox
var host_visibility: Button
var host_level_document: LevelDocument
var host_level_metadata: Dictionary = {}
var host_level_label: Label
var host_saved_button: Button
var host_browse_button: Button
var host_my_levels_button: Button
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
var tutorial_complete_dialog: ConfirmationDialog
var tutorial_menu_button: Button
var tutorial_restart_button: Button
var resume_button: Button
var pause_editor_button: Button
var pause_restart_button: Button
var pause_save_button: Button
var pause_save_message: Label
var settings_dialog: ConfirmationDialog
var settings_back_button: Button
var account_dialog: AccountDialog
var account_status: Label
var account_sign_in: Button
var account_sign_out: Button
var camera_zoom_slider: HSlider
var wall_cursor_toggle: CheckBox
var fullscreen_toggle: CheckBox
var camera_zoom: float = preload("res://scripts/player/ball.gd").CAMERA_BASE_ZOOM.x
var show_wall_cursor := false
var resume_waiting_for_release := false

func _ready() -> void:
	account_session = get_node("/root/AccountSession")
	time_records = LevelTimes.new()
	add_child(time_records)
	saved_levels.bind_account(account_session)
	saved_levels.load_levels()
	# UI remains responsive while the gameplay subtree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 40
	add_child(menu_layer)
	menu_background = MenuBackground.new()
	menu_layer.add_child(menu_background)
	title_screen = TitleScene.instantiate()
	title_screen.background = menu_background
	menu_layer.add_child(title_screen)
	title_screen.tutorial_requested.connect(show_demo)
	title_screen.editor_requested.connect(show_editor)
	title_screen.browse_levels_requested.connect(show_level_browser)
	title_screen.join_requested.connect(show_join_menu)
	title_screen.host_requested.connect(show_host_menu)
	title_screen.settings_requested.connect(show_settings)
	title_screen.fullscreen_requested.connect(_toggle_fullscreen)
	level_browser = LevelBrowser.new()
	level_browser.background = menu_background
	level_browser.saved_levels = saved_levels
	level_browser.time_records = time_records
	menu_layer.add_child(level_browser)
	level_browser.back_requested.connect(_leave_level_browser)
	level_browser.play_requested.connect(play_community_level)
	level_browser.select_requested.connect(_select_host_level)
	level_browser.sign_in_requested.connect(_show_browser_account)
	level_browser.hide()
	title_screen.visibility_changed.connect(_sync_menu_background)
	level_browser.visibility_changed.connect(_sync_menu_background)
	_sync_menu_background()
	dimmer = ColorRect.new()
	dimmer.color = Color(0.015, 0.035, 0.06, 0.7)
	menu_layer.add_child(dimmer)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.hide()
	_build_join_menu()
	_build_host_menu()
	_build_pause_menu()
	_build_tutorial_complete_menu()
	saved_levels.changed.connect(_sync_pause_save_button)
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
	MenuSlide.install_popup(session_notice)
	session_notice.dialog_hide_on_ok = false
	session_notice.confirmed.connect(func() -> void: MenuSlide.dismiss(session_notice))
	_build_loading_screen()
	show_main_menu()

func _sync_menu_background() -> void:
	menu_background.visible = title_screen.visible or level_browser.visible

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
	if title_screen.visible or settings_dialog.visible:
		_sync_fullscreen_controls()
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
			if tutorial_complete_dialog.visible:
				# Completion requires choosing a destination; keep gameplay paused.
				pass
			elif loading_screen.visible:
				if event.keycode == KEY_ESCAPE:
					show_main_menu()
			elif account_dialog.visible:
				MenuSlide.dismiss(account_dialog, func() -> void:
					account_dialog.dismiss(false)
					_return_account_settings()
				)
			elif settings_dialog.visible:
				_close_settings()
			elif pause_dialog.visible:
				resume_game()
			elif is_instance_valid(world):
				pause_game()
			elif event.keycode == KEY_ESCAPE and level_browser.visible:
				level_browser.dismiss()
			elif event.keycode == KEY_ESCAPE and title_screen.visible and (title_screen.multiplayer_actions.visible or title_screen.editor_actions.visible):
				title_screen.show_main_options()
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

func _dialog(title: String, cancel_text: String, cancellable: bool = true) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.exclusive = true
	DialogStyle.apply(dialog, true)
	dialog.cancel_button_text = cancel_text
	menu_layer.add_child(dialog)
	MenuSlide.install_popup(dialog, cancellable)
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
	MenuSlide.popup(dialog, Vector2i(420, 0))
	if dialog == pause_dialog:
		resume_button.grab_focus.call_deferred()
	# Let wrapped labels settle before shrinking away their early minimum height.
	_fit_popup.call_deferred(dialog)

func _fit_popup(dialog: ConfirmationDialog) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(dialog) and dialog.visible:
		dialog.reset_size()
		MenuSlide.recenter(dialog)

func _build_join_menu() -> void:
	join_dialog = _dialog("Join Game", "Back")
	join_dialog.ok_button_text = "Join"
	join_dialog.dialog_hide_on_ok = false
	join_dialog.confirmed.connect(_submit_join)
	join_dialog.canceled.connect(_cancel_connection)
	var column := _column(join_dialog)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var caption := Label.new()
	caption.text = "Public lobbies"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(caption)
	refresh_lobbies_button = _button("Refresh", _refresh_public_lobbies)
	heading.add_child(refresh_lobbies_button)
	var lobby_panel := PanelContainer.new()
	column.add_child(lobby_panel)
	var lobby_column := VBoxContainer.new()
	lobby_column.add_theme_constant_override("separation", 8)
	lobby_panel.add_child(lobby_column)
	public_lobby_status = _label("No public lobbies loaded yet.")
	public_lobby_status.custom_minimum_size.x = 0
	public_lobby_status.add_theme_font_size_override("font_size", 14)
	lobby_column.add_child(public_lobby_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 164
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lobby_column.add_child(scroll)
	public_lobbies = VBoxContainer.new()
	public_lobbies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(public_lobbies)
	lobby_request = HTTPRequest.new()
	lobby_request.timeout = 10.0
	lobby_request.body_size_limit = 65536
	lobby_request.request_completed.connect(_public_lobbies_received)
	add_child(lobby_request)
	column.add_child(_label("Or join with an 8-digit room code."))
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

func _cancel_lobby_refresh() -> void:
	lobby_request.cancel_request()
	refresh_lobbies_button.disabled = false

func _refresh_public_lobbies() -> void:
	_cancel_lobby_refresh()
	public_lobby_status.text = "Finding public lobbies..."
	refresh_lobbies_button.disabled = true
	_clear_public_lobbies()
	var url := SessionScript.lobby_list_url(SessionScript.default_url())
	if url.is_empty() or lobby_request.request(url) != OK:
		refresh_lobbies_button.disabled = false
		public_lobby_status.text = "Could not load public lobbies. You can still join by code."

func _clear_public_lobbies() -> void:
	for child in public_lobbies.get_children():
		public_lobbies.remove_child(child)
		child.queue_free()

func _public_lobbies_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	refresh_lobbies_button.disabled = false
	if not join_dialog.visible:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		public_lobby_status.text = "Could not load public lobbies. You can still join by code."
		return
	var payload = JSON.parse_string(body.get_string_from_utf8())
	if not payload is Dictionary or not payload.get("rooms") is Array:
		public_lobby_status.text = "Could not load public lobbies. You can still join by code."
		return
	_clear_public_lobbies()
	for entry in payload["rooms"].slice(0, 100):
		if not entry is Dictionary or not valid_room_code(str(entry.get("room", ""))):
			continue
		if typeof(entry.get("players")) not in [TYPE_INT, TYPE_FLOAT] or typeof(entry.get("max_players")) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var count := int(entry.get("players", 0))
		var limit := int(entry.get("max_players", 0))
		if count < 1 or limit < 2 or limit > 8 or count > limit:
			continue
		var code := str(entry["room"])
		var game_name := str(entry.get("name", "My game")).replace("\n", " ").replace("\r", " ").left(32)
		var button := _button("%s · %d/%d%s" % [game_name, count, limit, " · Full" if count == limit else ""], _join_public_lobby.bind(code))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.disabled = count == limit
		public_lobbies.add_child(button)
	public_lobby_status.text = "%d public lobbies · select one to join" % public_lobbies.get_child_count() if public_lobbies.get_child_count() > 0 else "No public lobbies yet. Host one or join by code."

func _join_public_lobby(code: String) -> void:
	room_code.text = code
	_submit_join()

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
	_cancel_lobby_refresh()
	_show_network_loading("Finding the host...", join_dialog)
	session.join_game(SessionScript.default_url(), pending_room_code)

func show_join_menu() -> void:
	dimmer.show()
	room_code.text = ""
	pending_room_code = ""
	_validate_room_code("")
	_popup(join_dialog)
	room_code.grab_focus.call_deferred()
	_refresh_public_lobbies()

func _build_host_menu() -> void:
	host_dialog = _dialog("Host Game", "Back")
	host_dialog.ok_button_text = "Create room"
	host_dialog.dialog_hide_on_ok = false
	host_dialog.canceled.connect(_cancel_connection)
	host_dialog.confirmed.connect(_submit_host)
	var column := _column(host_dialog)
	column.add_theme_constant_override("separation", 8)
	column.add_child(_label("Host a level, then invite players with the room code. Leaving ends the game for everyone."))
	column.add_child(_label("Game name"))
	host_name = LineEdit.new()
	host_name.text = "My game"
	host_name.max_length = 32
	host_name.add_theme_stylebox_override("normal", host_dialog.theme.get_stylebox("normal", "LineEdit"))
	column.add_child(host_name)
	column.add_child(_label("Lobby visibility"))
	host_visibility = _button("Private (join by code only)", _update_host_visibility)
	host_visibility.alignment = HORIZONTAL_ALIGNMENT_LEFT
	host_visibility.toggle_mode = true
	column.add_child(host_visibility)
	column.add_child(_label("Maximum players"))
	host_player_limit = SpinBox.new()
	host_player_limit.min_value = 2
	host_player_limit.max_value = 8
	host_player_limit.value = 4
	column.add_child(host_player_limit)
	column.add_child(_label("Level"))
	host_level_label = _label("No level selected")
	column.add_child(host_level_label)
	var level_actions := HBoxContainer.new()
	column.add_child(level_actions)
	host_saved_button = _button("Saved Levels", _browse_host_levels.bind(LevelBrowser.View.SAVED))
	host_browse_button = _button("Browse Levels", _browse_host_levels)
	host_my_levels_button = _button("My Levels", _browse_host_levels.bind(LevelBrowser.View.MY_LEVELS))
	for button in [host_browse_button, host_saved_button, host_my_levels_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		level_actions.add_child(button)
	host_message = _label("")
	column.add_child(host_message)
	_update_host_level()

func _browse_host_levels(view: int = LevelBrowser.View.COMMUNITY) -> void:
	MenuSlide.dismiss(host_dialog, func() -> void: show_level_browser(true, view))

func _select_host_level(document: LevelDocument, metadata: Dictionary = {}) -> void:
	var problem := document.playtest_error()
	if not problem.is_empty():
		if browsing_for_host:
			level_browser.status.text = problem
		else:
			host_message.text = problem
		return
	host_level_document = document.copy()
	host_level_metadata = metadata.duplicate(true)
	_update_host_level()
	if browsing_for_host:
		_leave_level_browser()
	else:
		show_host_menu()

func _update_host_level() -> void:
	host_level_label.text = str(host_level_metadata.get("title", "Selected community level")) if host_level_document != null else "No level selected"
	host_dialog.get_ok_button().disabled = host_level_document == null

func _update_host_visibility() -> void:
	host_visibility.text = "Public (anyone can join)" if host_visibility.button_pressed else "Private (join by code only)"

func _submit_host() -> void:
	if host_level_document == null:
		host_message.text = "Choose a saved level or browse community levels first."
		return
	var document := host_level_document.copy()
	var error := document.playtest_error()
	if not error.is_empty():
		host_message.text = error
		return
	host_dialog.get_ok_button().disabled = true
	_show_network_loading("Creating your room...", host_dialog)
	session.host_game(SessionScript.default_url(), LevelCodec.encode_level(document), int(host_player_limit.value), host_name.text, host_visibility.button_pressed)

func _cancel_connection() -> void:
	_cancel_lobby_refresh()
	session.close()
	dimmer.hide()
	_update_host_level()
	_validate_room_code(room_code.text)

func show_host_menu() -> void:
	dimmer.show()
	host_message.text = ""
	_update_host_level()
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
	pause_editor_button = _button("Back to Level Editor", show_editor)
	pause_restart_button = _button("Restart Level", _restart_playtest)
	pause_browser_button = _button("Back to Browse Levels", _return_to_level_browser)
	column.add_child(pause_editor_button)
	column.add_child(pause_browser_button)
	column.add_child(pause_restart_button)
	pause_save_button = _button("Save Level", _save_current_level)
	pause_save_message = _label("")
	pause_save_message.hide()
	column.add_child(pause_save_button)
	column.add_child(pause_save_message)
	column.add_child(_button("Return to Main Menu", show_main_menu))
	column.add_child(_button("Settings", show_settings))

func _build_tutorial_complete_menu() -> void:
	tutorial_complete_dialog = _dialog("Tutorial Complete!", "", false)
	tutorial_complete_dialog.get_ok_button().hide()
	tutorial_complete_dialog.get_cancel_button().hide()
	var column := _column(tutorial_complete_dialog)
	tutorial_menu_button = _button("Return to Main Menu", show_main_menu)
	tutorial_restart_button = _button("Restart Tutorial", show_demo)
	column.add_child(tutorial_menu_button)
	column.add_child(tutorial_restart_button)

func _show_tutorial_complete() -> void:
	if screen != Screen.TUTORIAL or not is_instance_valid(world) or not world.finished:
		return
	resume_waiting_for_release = false
	get_tree().paused = true
	dimmer.show()
	_popup(tutorial_complete_dialog)
	tutorial_menu_button.grab_focus.call_deferred()

func _build_settings_menu() -> void:
	settings_dialog = _dialog("Settings", "Back")
	settings_dialog.get_ok_button().hide()
	settings_dialog.get_cancel_button().hide()
	settings_dialog.canceled.connect(_close_settings)
	settings_dialog.visibility_changed.connect(func() -> void: _apply_player_settings(_player()))
	var column := _column(settings_dialog)
	var zoom_label := _label("Camera zoom: %d%%" % roundi(camera_zoom * 100.0))
	column.add_child(zoom_label)
	camera_zoom_slider = HSlider.new()
	camera_zoom_slider.custom_minimum_size.y = 32
	camera_zoom_slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	camera_zoom_slider.min_value = 0.15
	camera_zoom_slider.max_value = 0.85
	camera_zoom_slider.step = 0.01
	camera_zoom_slider.value = camera_zoom
	camera_zoom_slider.value_changed.connect(func(value: float) -> void:
		camera_zoom = value
		zoom_label.text = "Camera zoom: %d%%" % roundi(value * 100.0)
		_apply_player_settings(_player())
	)
	column.add_child(camera_zoom_slider)
	wall_cursor_toggle = CheckBox.new()
	wall_cursor_toggle.text = "Show wall grapple cursor"
	wall_cursor_toggle.toggled.connect(func(enabled: bool) -> void:
		show_wall_cursor = enabled
		_apply_player_settings(_player())
	)
	DialogStyle.ButtonPulse.install(wall_cursor_toggle, false, true)
	column.add_child(wall_cursor_toggle)
	fullscreen_toggle = CheckBox.new()
	fullscreen_toggle.text = "Fullscreen"
	fullscreen_toggle.toggled.connect(_set_fullscreen)
	DialogStyle.ButtonPulse.install(fullscreen_toggle, false, true)
	column.add_child(fullscreen_toggle)
	account_status = _label("")
	column.add_child(account_status)
	account_sign_in = _button("Sign in / Create account", _show_account_settings)
	account_sign_out = _button("Sign out", account_session.sign_out)
	column.add_child(account_sign_in)
	column.add_child(account_sign_out)
	var back_row := CenterContainer.new()
	column.add_child(back_row)
	settings_back_button = _button("Back", _close_settings)
	settings_back_button.custom_minimum_size.x = 112
	back_row.add_child(settings_back_button)
	account_dialog = AccountDialog.new()
	account_dialog.light = true
	menu_layer.add_child(account_dialog)
	account_dialog.authenticated.connect(_return_account_settings)
	account_dialog.canceled.connect(_return_account_settings)
	account_session.changed.connect(_sync_account_controls)
	account_session.completed.connect(_account_operation_completed)
	_sync_account_controls()

func _sync_account_controls() -> void:
	var signed_in: bool = account_session.is_signed_in()
	account_status.text = "Signed in as %s" % account_session.username if signed_in else "Make an account to upload levels and track your times."
	account_sign_in.visible = not signed_in
	account_sign_out.visible = signed_in
	account_sign_in.disabled = account_session.busy
	account_sign_out.disabled = account_session.busy

func _show_account_settings() -> void:
	account_from_pause = false
	MenuSlide.dismiss(settings_dialog, func() -> void:
		account_dialog.prompt("Sign in or create an account to publish your levels.")
	)

func _return_account_settings() -> void:
	_sync_account_controls()
	if account_from_pause:
		account_from_pause = false
		pause_game()
		return
	if level_browser.visible:
		dimmer.hide()
		return
	_popup(settings_dialog)

func _show_browser_account() -> void:
	account_from_pause = false
	dimmer.show()
	account_dialog.prompt("Sign in or create an account to save levels and view your saved or published levels.")

func _account_operation_completed(action: String, error: String) -> void:
	if action == "logout" and not error.is_empty():
		account_status.text = "Signed out on this device. Could not end the server session; it will expire automatically."
		_fit_popup.call_deferred(settings_dialog)

func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]

func _set_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	_sync_fullscreen_controls()

func _toggle_fullscreen() -> void:
	_set_fullscreen(not _is_fullscreen())

func _sync_fullscreen_controls() -> void:
	var enabled := _is_fullscreen()
	fullscreen_toggle.set_pressed_no_signal(enabled)
	title_screen.fullscreen_button.text = "Exit Fullscreen" if enabled else "Fullscreen"

func _player() -> RigidBody2D:
	if world is CustomLevel:
		return world.player
	if is_instance_valid(world):
		return world.get_node_or_null("Ball") as RigidBody2D
	return null

func _apply_player_settings(player: RigidBody2D) -> void:
	if is_instance_valid(player):
		player.set_camera_zoom(camera_zoom, settings_dialog.visible)
		player.show_grapple_cursor = show_wall_cursor
		if screen == Screen.MULTIPLAYER and (pause_dialog.visible or settings_dialog.visible):
			player.spawn_controls_pending = false
			player.set_controls_locked(true)

func pause_game() -> void:
	if not is_instance_valid(world) or tutorial_complete_dialog.visible:
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
	pause_restart_button.visible = screen in [Screen.PLAYTEST, Screen.COMMUNITY_LEVEL]
	pause_browser_button.visible = screen == Screen.COMMUNITY_LEVEL
	pause_browser_button.text = "Back to " + LevelBrowser.view_title(return_browser_view)
	_sync_pause_save_button()
	_popup(pause_dialog)

func _sync_pause_save_button() -> void:
	pause_save_message.hide()
	pause_save_button.visible = is_instance_valid(world) and world is CustomLevel and not saved_levels.owns_level(active_level_metadata)
	if pause_save_button.visible:
		var saved := not saved_levels.find_level(world.document).is_empty()
		pause_save_button.text = "Level Saved" if saved else "Save Level"
		pause_save_button.disabled = saved

func _save_current_level() -> void:
	if not world is CustomLevel:
		return
	if not account_session.is_signed_in():
		account_from_pause = true
		MenuSlide.dismiss(pause_dialog, func() -> void:
			account_dialog.prompt("Sign in or create an account to save this level.")
		)
		return
	var error := saved_levels.save_level(world.document, active_level_metadata)
	pause_save_message.text = error if not error.is_empty() else "Level saved! Select it from Saved Levels when hosting a game."
	pause_save_message.show()
	if error.is_empty():
		pause_save_button.text = "Level Saved"
		pause_save_button.disabled = true
	_fit_popup.call_deferred(pause_dialog)

func resume_game() -> void:
	var dialog := settings_dialog if settings_dialog.visible else pause_dialog
	MenuSlide.dismiss(dialog, _finish_resume)

func _finish_resume() -> void:
	MenuSlide.hide_now(settings_dialog)
	MenuSlide.hide_now(pause_dialog)
	dimmer.hide()
	get_tree().paused = false
	# A menu click or held Space must not charge an attack or fire a grapple.
	resume_waiting_for_release = true

func show_settings() -> void:
	if pause_dialog.visible:
		MenuSlide.dismiss(pause_dialog, show_settings)
		return
	dimmer.show()
	_sync_account_controls()
	_sync_fullscreen_controls()
	_popup(settings_dialog)
	camera_zoom_slider.grab_focus.call_deferred()

func _close_settings() -> void:
	MenuSlide.dismiss(settings_dialog, _finish_close_settings)

func _finish_close_settings() -> void:
	if is_instance_valid(world):
		_popup(pause_dialog)
	else:
		dimmer.hide()
		title_screen.settings_button.grab_focus.call_deferred()

func _clear_menus() -> void:
	account_from_pause = false
	_cancel_lobby_refresh()
	account_dialog.dismiss(false)
	level_browser.close()
	loading_screen.hide()
	loading_origin = null
	get_tree().paused = false
	resume_waiting_for_release = false
	for dialog in [pause_dialog, tutorial_complete_dialog, settings_dialog, join_dialog, host_dialog]:
		MenuSlide.hide_now(dialog)
	dimmer.hide()

func _dispose_world() -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = null
	active_level_metadata = {}

func show_main_menu(editor_submenu: bool = false) -> void:
	browsing_for_host = false
	if is_instance_valid(session):
		session.close()
	if is_instance_valid(room_card):
		room_card.hide()
	_clear_menus()
	if is_instance_valid(editor):
		editor.suspend()
	_dispose_world()
	screen = Screen.MAIN_MENU
	# Select the destination before revealing the title screen, so returning
	# from the browser never displays or dismisses the main action list.
	if editor_submenu:
		title_screen.show_editor_options(false)
	else:
		title_screen.show_main_options(false)
	title_screen.show()
	if editor_submenu:
		MenuSlide.enter(title_screen.editor_actions)

func show_demo() -> void:
	_clear_menus()
	title_screen.hide()
	if is_instance_valid(editor):
		editor.suspend()
	_dispose_world()
	screen = Screen.TUTORIAL
	world = DemoScene.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.completed.connect(_show_tutorial_complete, CONNECT_DEFERRED)
	world.restart_requested.connect(_restart_fallen_tutorial.bind(world), CONNECT_DEFERRED)
	add_child(world)
	_apply_player_settings(_player())

func _restart_fallen_tutorial(tutorial: Node) -> void:
	if screen != Screen.TUTORIAL or world != tutorial:
		return
	show_demo()
	_player().set_controls_locked(true)
	resume_waiting_for_release = true

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

func show_level_browser(for_host: bool = false, view: int = LevelBrowser.View.COMMUNITY) -> void:
	_clear_menus()
	title_screen.hide()
	if is_instance_valid(editor):
		editor.suspend()
	_dispose_world()
	screen = Screen.LEVEL_BROWSER
	browsing_for_host = for_host
	level_browser.open(for_host, view)

func _return_to_level_browser() -> void:
	show_level_browser(false, return_browser_view)

func _leave_level_browser() -> void:
	if browsing_for_host:
		level_browser.close()
		browsing_for_host = false
		screen = Screen.MAIN_MENU
		title_screen.show_multiplayer_options()
		title_screen.show()
		show_host_menu()
		return
	show_main_menu(true)

func play_community_level(document: LevelDocument) -> void:
	var custom: CustomLevel = CustomScene.instantiate()
	var error := custom.prepare(document)
	if not error.is_empty():
		custom.free()
		level_browser.status.text = error
		return
	return_browser_view = level_browser.current_view
	_clear_menus()
	title_screen.hide()
	if is_instance_valid(editor):
		editor.suspend()
	_dispose_world()
	screen = Screen.COMMUNITY_LEVEL
	active_level_metadata = level_browser.last_level_metadata.duplicate(true)
	custom.time_records = time_records
	custom.leaderboard_id = str(active_level_metadata.get("id", active_level_metadata.get("source_id", LevelCodec.publication_id(document))))
	world = custom
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	custom.player_spawned.connect(_apply_player_settings)
	add_child(world)

func playtest(document: LevelDocument) -> void:
	var custom: CustomLevel = CustomScene.instantiate()
	var error := custom.prepare(document)
	if not error.is_empty():
		editor.show_geometry_error(custom.terrain_error, error)
		custom.free()
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

func _start_network_world(code: String, level_code: String, hosting: bool) -> void:
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
	active_level_metadata = saved_levels.find_level(decoded["document"])
	if hosting and host_level_document != null and LevelCodec.encode_level(host_level_document) == LevelCodec.encode_level(decoded["document"]):
		active_level_metadata = host_level_metadata.duplicate(true)
	world = custom
	custom.player_spawned.connect(_network_player_spawned)
	custom.time_records = time_records
	custom.leaderboard_id = str(active_level_metadata.get("id", active_level_metadata.get("source_id", LevelCodec.publication_id(decoded["document"]))))
	time_records.refresh_summaries()
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
		MenuSlide.popup(session_notice, Vector2i(480, 0))
	else:
		join_message.text = reason
		host_message.text = reason
		_update_host_level()
		join_dialog.get_ok_button().disabled = not valid_room_code(room_code.text)
		if is_instance_valid(origin):
			dimmer.show()
			_popup(origin)

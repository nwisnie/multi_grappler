extends Control

signal back_requested
signal play_requested(document: LevelDocument)
signal select_requested(document: LevelDocument, metadata: Dictionary)
signal sign_in_requested

const LibraryClient := preload("res://scripts/levels/level_library_client.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const TitleMenuButton := preload("res://scripts/ui/title_menu_button.gd")
const ButtonPulse := preload("res://scripts/ui/menu_button_pulse.gd")
const MenuSlide := preload("res://scripts/ui/menu_slide.gd")
const MenuBackground := preload("res://scripts/ui/menu_background.gd")
const SavedLevels := preload("res://scripts/levels/saved_levels.gd")

enum View { COMMUNITY, SAVED, MY_LEVELS }

var background: MenuBackground
var sky: TextureRect
var client: LibraryClient
var status: Label
var rows: VBoxContainer
var refresh_button: Button
var back_button: Button
var community_button: Button
var saved_button: Button
var my_levels_button: Button
var sign_in_button: Button
var import_button: Button
var title_label: Label
var current_view: int = View.COMMUNITY
var account_session: Node
var known_user_id := ""
var remote_levels: Array[Dictionary] = []
var request_busy := false
var play_buttons: Array[Button] = []
var save_buttons: Dictionary = {}
var saved_levels: SavedLevels
var loading_level := false
var saving_level := false
var selecting_level := false
var pending_metadata: Dictionary = {}
var last_level_metadata: Dictionary = {}
var entries: Dictionary = {}
var description: Label
var content: MarginContainer

func _ready() -> void:
	theme = MenuTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if background == null:
		background = MenuBackground.new()
		add_child(background)
	sky = background.sky
	var margin := MarginContainer.new()
	content = margin
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 20)
	column.add_child(heading)
	title_label = _label("Community Levels")
	title_label.add_theme_font_size_override("font_size", 38)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	community_button = _button("Community", show_view.bind(View.COMMUNITY))
	saved_button = _button("Saved Levels", show_view.bind(View.SAVED))
	my_levels_button = _button("My Levels", show_view.bind(View.MY_LEVELS))
	heading.add_child(_button_group([community_button, saved_button, my_levels_button]))
	refresh_button = _button("Refresh", refresh)
	back_button = _button("Back", dismiss)
	heading.add_child(_button_pair(refresh_button, back_button))
	description = _label("")
	column.add_child(description)
	status = _label("")
	column.add_child(status)
	sign_in_button = _button("Sign in / Create account", func() -> void: sign_in_requested.emit())
	sign_in_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sign_in_button.hide()
	column.add_child(sign_in_button)
	import_button = _button("Import earlier saved levels", _import_legacy_levels)
	import_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	import_button.hide()
	column.add_child(import_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	client = LibraryClient.new()
	add_child(client)
	client.completed.connect(_received)
	if saved_levels == null:
		saved_levels = SavedLevels.new()
		saved_levels.bind_account(get_node("/root/AccountSession"))
		saved_levels.load_levels()
	saved_levels.changed.connect(_saved_levels_changed)
	account_session = get_node("/root/AccountSession")
	known_user_id = _signed_in_user_id()
	account_session.changed.connect(_account_changed)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("outline_size", 0)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := TitleMenuButton.new()
	button.text = text
	button.custom_minimum_size = Vector2(112, 50)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	ButtonPulse.install(button, false, true)
	return button

func _button_pair(first: Button, last: Button) -> HBoxContainer:
	return _button_group([first, last])

func _button_group(buttons: Array[Button]) -> HBoxContainer:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 0)
	for index in range(buttons.size()):
		var segment := TitleMenuButton.Segment.MIDDLE
		if buttons.size() == 1:
			segment = TitleMenuButton.Segment.SINGLE
		elif index == 0:
			segment = TitleMenuButton.Segment.FIRST
		elif index == buttons.size() - 1:
			segment = TitleMenuButton.Segment.LAST
		buttons[index].set("segment", segment)
		group.add_child(buttons[index])
	return group

func open(for_selection: bool = false, view: int = View.COMMUNITY) -> void:
	selecting_level = for_selection
	current_view = view
	show()
	MenuSlide.enter(content)
	_update_view_controls()
	refresh()
	back_button.grab_focus.call_deferred()

func close() -> void:
	client.cancel()
	loading_level = false
	saving_level = false
	_busy(false)
	MenuSlide.hide_now(content)
	hide()

func dismiss() -> void:
	client.cancel()
	loading_level = false
	saving_level = false
	_busy(false)
	MenuSlide.dismiss(content, func() -> void: back_requested.emit())

func _busy(enabled: bool) -> void:
	request_busy = enabled
	refresh_button.disabled = enabled
	for button in play_buttons:
		button.disabled = enabled
	for button in save_buttons.values():
		button.disabled = enabled

static func view_title(view: int) -> String:
	match view:
		View.SAVED:
			return "Saved Levels"
		View.MY_LEVELS:
			return "My Levels"
	return "Community Levels"

func _signed_in_user_id() -> String:
	return account_session.user_id if account_session.is_signed_in() else ""

func _account_changed() -> void:
	sign_in_button.disabled = account_session.busy
	var user_id := _signed_in_user_id()
	if known_user_id == user_id:
		return
	known_user_id = user_id
	if visible:
		refresh()

func _update_view_controls() -> void:
	title_label.text = view_title(current_view)
	community_button.disabled = current_view == View.COMMUNITY
	saved_button.disabled = current_view == View.SAVED
	my_levels_button.disabled = current_view == View.MY_LEVELS
	match current_view:
		View.SAVED:
			description.text = "Select a level saved by your account for your lobby." if selecting_level else "Play levels saved by your account on this device."
		View.MY_LEVELS:
			description.text = "Select one of your published levels for your lobby." if selecting_level else "Play and save levels you have published."
		_:
			description.text = "Select a community level for your lobby, or save it for later." if selecting_level else "Play a community level, or save it for later. Upload your own from the level editor."
	sign_in_button.visible = current_view in [View.SAVED, View.MY_LEVELS] and _signed_in_user_id().is_empty()
	sign_in_button.disabled = account_session.busy
	import_button.visible = current_view == View.SAVED and saved_levels.has_legacy_levels()
	import_button.tooltip_text = "Bring older saves from this device into the signed-in account."

func show_view(view: int) -> void:
	current_view = view
	_update_view_controls()
	refresh()

func _saved_levels_changed() -> void:
	if visible:
		_update_view_controls()
		_render_levels()

func _import_legacy_levels() -> void:
	var error := saved_levels.import_legacy_levels()
	if not error.is_empty():
		status.text = error

func refresh() -> void:
	client.cancel()
	loading_level = false
	saving_level = false
	pending_metadata = {}
	_busy(false)
	_update_view_controls()
	_render_levels()
	if current_view == View.SAVED:
		if not saved_levels.load_error.is_empty():
			status.text = saved_levels.load_error
		return
	if current_view == View.MY_LEVELS and _signed_in_user_id().is_empty():
		return
	status.text = "Loading your levels..." if current_view == View.MY_LEVELS else "Loading community levels..."
	_busy(true)
	client.fetch_levels()

func _play(id: String) -> void:
	if request_busy:
		return
	var entry: Dictionary = entries.get(id, {})
	if entry.get("level_code") is String:
		var decoded := LevelCodec.decode_level(entry["level_code"])
		if not decoded["error"].is_empty():
			status.text = decoded["error"]
			return
		_open_document(decoded["document"], entry)
		return
	_download(id, false)

func _save(id: String) -> void:
	if _signed_in_user_id().is_empty():
		status.text = "Sign in to save this level to your account."
		sign_in_requested.emit()
		return
	_download(id, true)

func _download(id: String, save_only: bool) -> void:
	if request_busy:
		return
	loading_level = true
	saving_level = save_only
	pending_metadata = entries.get(id, {}).duplicate(true)
	status.text = "Downloading level..."
	_busy(true)
	client.fetch_level(id)

func _received(_response_code: int, payload: Dictionary, error: String) -> void:
	if not visible:
		return
	_busy(false)
	if not error.is_empty():
		loading_level = false
		saving_level = false
		status.text = error
		return
	if loading_level:
		loading_level = false
		var save_only := saving_level
		saving_level = false
		if not payload.get("level") is Dictionary or not payload["level"].get("level_code") is String:
			status.text = "This level could not be loaded. Refresh and try again."
			return
		var decoded := LevelCodec.decode_level(payload["level"]["level_code"])
		if not decoded["error"].is_empty():
			status.text = decoded["error"]
			return
		var document: LevelDocument = decoded["document"]
		var problem := document.playtest_error()
		if not problem.is_empty():
			status.text = problem
			return
		last_level_metadata = pending_metadata.duplicate(true)
		for key in ["id", "title", "author", "author_id"]:
			if payload["level"].get(key) is String:
				last_level_metadata[key] = payload["level"][key]
		if save_only:
			var save_error := saved_levels.save_level(document, last_level_metadata)
			status.text = save_error if not save_error.is_empty() else "Level saved! Select it from Saved Levels when hosting a game."
			return
		_open_document(document, last_level_metadata)
		return
	if not payload.get("levels") is Array:
		status.text = "The level library returned an invalid list. Try refreshing."
		return
	remote_levels.clear()
	var seen := {}
	for entry in payload["levels"].slice(0, 100):
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("title") is String:
			continue
		var id: String = entry["id"]
		if id.length() != 64 or not id.is_valid_hex_number(false):
			continue
		if seen.has(id):
			continue
		seen[id] = true
		remote_levels.append(entry.duplicate(true))
	_render_levels()

func _open_document(document: LevelDocument, metadata: Dictionary) -> void:
	var problem := document.playtest_error()
	if not problem.is_empty():
		status.text = problem
		return
	last_level_metadata = metadata.duplicate(true)
	_busy(true)
	if selecting_level:
		select_requested.emit(document, last_level_metadata)
	else:
		play_requested.emit(document)
	# A preparation error leaves this screen open with its message and retry.
	if is_visible_in_tree():
		_busy(false)

func _visible_entries() -> Array[Dictionary]:
	if current_view == View.SAVED:
		return saved_levels.list_levels()
	var user_id := _signed_in_user_id()
	var result: Array[Dictionary] = []
	if current_view == View.MY_LEVELS and user_id.is_empty():
		return result
	var seen := {}
	for remote in remote_levels:
		var id: String = remote["id"]
		var saved := saved_levels.find_source(id)
		if current_view == View.COMMUNITY and not saved.is_empty():
			continue
		if current_view == View.MY_LEVELS and remote.get("author_id", "") != user_id:
			continue
		var entry := remote.duplicate(true)
		if not saved.is_empty():
			entry["level_code"] = saved["level_code"]
		result.append(entry)
		seen[id] = true
	if current_view == View.MY_LEVELS:
		for saved in saved_levels.list_levels():
			if saved.get("author_id", "") == user_id and not seen.has(saved["source_id"]):
				result.append(saved)
	return result

func _render_levels() -> void:
	play_buttons.clear()
	save_buttons.clear()
	entries.clear()
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for entry in _visible_entries():
		var local := entry.get("level_code") is String
		var id: String = "saved:" + str(entry["level_code"]).sha256_text() if local else entry["id"]
		entries[id] = entry
		var panel := PanelContainer.new()
		rows.add_child(panel)
		var panel_style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		# Match the visible weight of the buttons, including their antialiased edge.
		panel_style.set_border_width_all(ceili(TitleMenuButton.BORDER_WIDTH) + 1)
		panel.add_theme_stylebox_override("panel", panel_style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		panel.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(_label(str(entry["title"]).left(64)))
		var byline := "By " + str(entry.get("author", "Anonymous")).left(32)
		var created := str(entry.get("created_at", "")).left(10)
		if not created.is_empty():
			byline += " · " + created
		info.add_child(_label(byline))
		var play := _button("Select" if selecting_level else "Play", _play.bind(id))
		play_buttons.append(play)
		if local:
			row.add_child(play)
		else:
			var save := _button("Save", _save.bind(id))
			save_buttons[id] = save
			row.add_child(_button_pair(play, save))
	_busy(request_busy)
	var count := rows.get_child_count()
	match current_view:
		View.SAVED:
			if _signed_in_user_id().is_empty():
				status.text = "Sign in to view levels saved by your account."
			else:
				status.text = "%d saved level%s" % [count, "" if count == 1 else "s"] if count > 0 else "No saved levels yet. Save a community level or choose Save Level in the pause menu."
		View.MY_LEVELS:
			if _signed_in_user_id().is_empty():
				status.text = "Sign in to view levels published by your account."
			else:
				status.text = "%d published level%s" % [count, "" if count == 1 else "s"] if count > 0 else "You haven't published any levels yet. Upload a level from the level editor."
		_:
			if count > 0:
				status.text = "%d available · %d / 100 published · newest first" % [count, remote_levels.size()]
			elif not remote_levels.is_empty():
				status.text = "All community levels are saved. Open Saved Levels to play or host them."
			else:
				status.text = "No levels published yet. Create one in the level editor!"

extends Control

signal back_requested
signal play_requested(document: LevelDocument)
signal select_requested(document: LevelDocument, metadata: Dictionary)

const LibraryClient := preload("res://scripts/levels/level_library_client.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const TitleMenuButton := preload("res://scripts/ui/title_menu_button.gd")
const ButtonPulse := preload("res://scripts/ui/menu_button_pulse.gd")
const MenuSlide := preload("res://scripts/ui/menu_slide.gd")
const MenuBackground := preload("res://scripts/ui/menu_background.gd")
const SavedLevels := preload("res://scripts/levels/saved_levels.gd")

var background: MenuBackground
var sky: TextureRect
var client: LibraryClient
var status: Label
var rows: VBoxContainer
var refresh_button: Button
var back_button: Button
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
	column.add_child(heading)
	var title := _label("Community Levels")
	title.add_theme_font_size_override("font_size", 38)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	refresh_button = _button("Refresh", refresh)
	heading.add_child(refresh_button)
	back_button = _button("Back", dismiss)
	heading.add_child(back_button)
	description = _label("")
	column.add_child(description)
	status = _label("")
	column.add_child(status)
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
		saved_levels.load_levels()
	saved_levels.changed.connect(_sync_save_buttons)

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

func open(for_selection: bool = false) -> void:
	selecting_level = for_selection
	description.text = "Select a level for your lobby, or save it to host later." if selecting_level else "Play a community level, or save it to host later. Upload your own from the level editor."
	show()
	MenuSlide.enter(content)
	refresh()
	back_button.grab_focus.call_deferred()

func close() -> void:
	client.cancel()
	loading_level = false
	saving_level = false
	MenuSlide.hide_now(content)
	hide()

func dismiss() -> void:
	client.cancel()
	loading_level = false
	saving_level = false
	MenuSlide.dismiss(content, func() -> void: back_requested.emit())

func _busy(enabled: bool) -> void:
	refresh_button.disabled = enabled
	for button in play_buttons:
		button.disabled = enabled
	_sync_save_buttons()

func _sync_save_buttons() -> void:
	for id in save_buttons:
		var button: Button = save_buttons[id]
		var saved := saved_levels.has_source(id)
		button.text = "Saved" if saved else "Save"
		button.disabled = refresh_button.disabled or saved

func refresh() -> void:
	loading_level = false
	saving_level = false
	pending_metadata = {}
	status.text = "Loading community levels..."
	_busy(true)
	client.fetch_levels()

func _play(id: String) -> void:
	_download(id, false)

func _save(id: String) -> void:
	_download(id, true)

func _download(id: String, save_only: bool) -> void:
	if refresh_button.disabled:
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
		for key in ["id", "title", "author"]:
			if payload["level"].get(key) is String:
				last_level_metadata[key] = payload["level"][key]
		if save_only:
			var save_error := saved_levels.save_level(document, last_level_metadata)
			status.text = save_error if not save_error.is_empty() else "Level saved! Select it from Saved Levels when hosting a game."
			return
		_busy(true)
		if selecting_level:
			select_requested.emit(document, last_level_metadata)
		else:
			play_requested.emit(document)
		# A level preparation error leaves this screen open with a message.
		if is_visible_in_tree():
			_busy(false)
		return
	if not payload.get("levels") is Array:
		status.text = "The level library returned an invalid list. Try refreshing."
		return
	play_buttons.clear()
	save_buttons.clear()
	entries.clear()
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for entry in payload["levels"].slice(0, 100):
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("title") is String:
			continue
		var id: String = entry["id"]
		if id.length() != 64 or not id.is_valid_hex_number(false):
			continue
		if entries.has(id):
			continue
		entries[id] = entry.duplicate(true)
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
		info.add_child(_label("By %s · %s" % [str(entry.get("author", "Anonymous")).left(32), str(entry.get("created_at", "")).left(10)]))
		var play := _button("Select" if selecting_level else "Play", _play.bind(id))
		play_buttons.append(play)
		row.add_child(play)
		var save := _button("Save", _save.bind(id))
		save_buttons[id] = save
		row.add_child(save)
	_sync_save_buttons()
	status.text = "%d / 100 levels · newest first" % rows.get_child_count() if rows.get_child_count() > 0 else "No levels published yet. Create one in the level editor!"

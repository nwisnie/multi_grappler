extends Control

signal back_requested
signal play_requested(document: LevelDocument)

const LibraryClient := preload("res://scripts/levels/level_library_client.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const TitleMenuButton := preload("res://scripts/ui/title_menu_button.gd")
const ButtonPulse := preload("res://scripts/ui/menu_button_pulse.gd")

var client: LibraryClient
var status: Label
var rows: VBoxContainer
var refresh_button: Button
var back_button: Button
var play_buttons: Array[Button] = []
var loading_level := false

func _ready() -> void:
	theme = MenuTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sky := TextureRect.new()
	sky.texture = preload("res://assets/images/levels/bg_sky.png")
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
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
	back_button = _button("Back", func() -> void: back_requested.emit())
	heading.add_child(back_button)
	column.add_child(_label("Play a community level, or upload your own from the level editor."))
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

func open() -> void:
	show()
	refresh()
	back_button.grab_focus.call_deferred()

func close() -> void:
	client.cancel()
	hide()

func _busy(enabled: bool) -> void:
	refresh_button.disabled = enabled
	for button in play_buttons:
		button.disabled = enabled

func refresh() -> void:
	loading_level = false
	status.text = "Loading community levels..."
	_busy(true)
	client.fetch_levels()

func _play(id: String) -> void:
	loading_level = true
	status.text = "Downloading level..."
	_busy(true)
	client.fetch_level(id)

func _received(_response_code: int, payload: Dictionary, error: String) -> void:
	if not visible:
		return
	_busy(false)
	if not error.is_empty():
		status.text = error
		return
	if loading_level:
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
		play_requested.emit(document)
		return
	if not payload.get("levels") is Array:
		status.text = "The level library returned an invalid list. Try refreshing."
		return
	play_buttons.clear()
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for entry in payload["levels"].slice(0, 100):
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("title") is String:
			continue
		var id: String = entry["id"]
		if id.length() != 64 or not id.is_valid_hex_number(false):
			continue
		var panel := PanelContainer.new()
		rows.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		panel.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(_label(str(entry["title"]).left(64)))
		info.add_child(_label("By %s · %s" % [str(entry.get("author", "Anonymous")).left(32), str(entry.get("created_at", "")).left(10)]))
		var play := _button("Play", _play.bind(id))
		play_buttons.append(play)
		row.add_child(play)
	status.text = "%d / 100 levels · newest first" % rows.get_child_count() if rows.get_child_count() > 0 else "No levels published yet. Create one in the level editor!"

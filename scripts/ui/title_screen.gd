extends Control

signal tutorial_requested
signal editor_requested
signal join_requested
signal host_requested
signal settings_requested
signal fullscreen_requested

const SKY := preload("res://assets/images/levels/bg_sky.png")
const BALL := preload("res://assets/images/characters/player_ball/main_ball.png")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const TitleMenuButton := preload("res://scripts/ui/title_menu_button.gd")
const ButtonPulse := preload("res://scripts/ui/menu_button_pulse.gd")
const TITLE := "Speed Balls"
const WAVE_HEIGHT := 9.0
const WAVE_SPEED := 2.4

var tutorial_button: Button
var editor_button: Button
var multiplayer_button: Button
var join_button: Button
var host_button: Button
var multiplayer_back_button: Button
var settings_button: Button
var fullscreen_button: Button
var main_actions: VBoxContainer
var multiplayer_actions: VBoxContainer
var wave_items: Array[Control] = []
var wave_time := 0.0

func _ready() -> void:
	theme = MenuTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sky := TextureRect.new()
	sky.texture = SKY
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var wash := ColorRect.new()
	wash.color = Color(0.85, 0.95, 1.0, 0.12)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	center.add_child(column)
	var logo := HBoxContainer.new()
	logo.name = "GameTitle"
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", 16)
	column.add_child(logo)
	var ball_slot := Control.new()
	ball_slot.custom_minimum_size = Vector2(84, 112)
	logo.add_child(ball_slot)
	var ball := TextureRect.new()
	ball.name = "TitleBall"
	ball.texture = BALL
	ball.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ball.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ball.size = Vector2(84, 84)
	ball_slot.add_child(ball)
	wave_items.append(ball)
	var letters := HBoxContainer.new()
	letters.add_theme_constant_override("separation", 0)
	letters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_child(letters)
	var font := get_theme_font("font", "Label")
	for index in range(TITLE.length()):
		var character := TITLE.substr(index, 1)
		var slot := Control.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.custom_minimum_size = Vector2(font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x, 112)
		letters.add_child(slot)
		var letter := Label.new()
		letter.name = "Letter%d" % index
		letter.text = character
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		letter.add_theme_font_size_override("font_size", 64)
		letter.add_theme_color_override("font_color", Color.BLACK)
		letter.add_theme_constant_override("outline_size", 0)
		slot.add_child(letter)
		wave_items.append(letter)
	# No enclosing panel: the options sit directly on the sky background.
	main_actions = VBoxContainer.new()
	main_actions.name = "MainActions"
	main_actions.add_theme_constant_override("separation", 12)
	column.add_child(main_actions)
	multiplayer_button = _button("Multiplayer", show_multiplayer_options)
	tutorial_button = _button("Tutorial", func() -> void: tutorial_requested.emit())
	editor_button = _button("Level Editor", func() -> void: editor_requested.emit())
	settings_button = _button("Settings", func() -> void: settings_requested.emit())
	for button in [multiplayer_button, editor_button, tutorial_button, settings_button]:
		main_actions.add_child(button)
	multiplayer_actions = VBoxContainer.new()
	multiplayer_actions.name = "MultiplayerActions"
	multiplayer_actions.add_theme_constant_override("separation", 12)
	column.add_child(multiplayer_actions)
	join_button = _button("Join Game", func() -> void: join_requested.emit())
	host_button = _button("Host Game", func() -> void: host_requested.emit())
	multiplayer_back_button = _button("Back", show_main_options)
	for button in [join_button, host_button, multiplayer_back_button]:
		multiplayer_actions.add_child(button)
	fullscreen_button = _button("Fullscreen", func() -> void: fullscreen_requested.emit())
	fullscreen_button.name = "FullscreenButton"
	fullscreen_button.custom_minimum_size = Vector2(240, 44)
	fullscreen_button.add_theme_font_size_override("font_size", 20)
	fullscreen_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_actions.add_child(fullscreen_button)
	show_main_options()
	_update_wave()

func show_main_options() -> void:
	main_actions.show()
	multiplayer_actions.hide()
	multiplayer_button.grab_focus.call_deferred()

func show_multiplayer_options() -> void:
	main_actions.hide()
	multiplayer_actions.show()
	join_button.grab_focus.call_deferred()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	wave_time = fposmod(wave_time + delta * WAVE_SPEED, TAU)
	_update_wave()

func _update_wave() -> void:
	for index in range(wave_items.size()):
		wave_items[index].position.y = 14.0 + sin(wave_time - float(index) * 0.55) * WAVE_HEIGHT

func _button(text: String, callback: Callable) -> Button:
	var button := TitleMenuButton.new()
	button.text = text
	button.custom_minimum_size = Vector2(340, 58)
	button.add_theme_font_size_override("font_size", 28)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	ButtonPulse.install(button, false, true)
	return button

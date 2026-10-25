extends Control

signal tutorial_requested
signal editor_requested
signal join_requested
signal host_requested

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
var join_button: Button
var host_button: Button
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
	# No enclosing panel: the four options sit directly on the sky background.
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	tutorial_button = _button("Tutorial", func() -> void: tutorial_requested.emit())
	editor_button = _button("Level Editor", func() -> void: editor_requested.emit())
	join_button = _button("Join Game", func() -> void: join_requested.emit())
	host_button = _button("Host Game", func() -> void: host_requested.emit())
	for button in [tutorial_button, editor_button, join_button, host_button]:
		actions.add_child(button)
	tutorial_button.grab_focus.call_deferred()
	_update_wave()

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

extends Control

signal tutorial_requested
signal editor_requested
signal browse_levels_requested
signal join_requested
signal host_requested
signal settings_requested
signal fullscreen_requested

const BALL := preload("res://assets/images/characters/player_ball/main_ball.png")
const MenuBackground := preload("res://scripts/ui/menu_background.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const TitleMenuButton := preload("res://scripts/ui/title_menu_button.gd")
const ButtonPulse := preload("res://scripts/ui/menu_button_pulse.gd")
const MenuSlide := preload("res://scripts/ui/menu_slide.gd")
const TITLE := "Speed Balls"
const WAVE_HEIGHT := 9.0
const WAVE_SPEED := 2.4
const MENU_PARALLAX := Vector2(14.0, 9.0)

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
var editor_actions: VBoxContainer
var browse_levels_button: Button
var create_level_button: Button
var editor_back_button: Button
var wave_items: Array[Control] = []
var wave_time := 0.0
var background: MenuBackground
var sky: TextureRect
var menu_content: Control
var actions_slot: Control
var active_actions: VBoxContainer
var next_actions: VBoxContainer
var next_focus: Button
var switching_actions := false

func _ready() -> void:
	theme = MenuTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if background == null:
		background = MenuBackground.new()
		add_child(background)
	sky = background.sky
	# Move a free Control so containers can keep managing the menu layout.
	menu_content = Control.new()
	menu_content.name = "ParallaxMenu"
	menu_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_content)
	menu_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	menu_content.add_child(center)
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
	actions_slot = Control.new()
	actions_slot.name = "ActionsSlot"
	column.add_child(actions_slot)
	main_actions = VBoxContainer.new()
	main_actions.name = "MainActions"
	main_actions.add_theme_constant_override("separation", 12)
	actions_slot.add_child(main_actions)
	multiplayer_button = _button("Multiplayer", show_multiplayer_options)
	tutorial_button = _button("Tutorial", func() -> void: tutorial_requested.emit())
	editor_button = _button("Level Editor", show_editor_options)
	settings_button = _button("Settings", func() -> void: settings_requested.emit())
	for button in [multiplayer_button, editor_button, tutorial_button, settings_button]:
		main_actions.add_child(button)
	multiplayer_actions = VBoxContainer.new()
	multiplayer_actions.name = "MultiplayerActions"
	multiplayer_actions.add_theme_constant_override("separation", 12)
	actions_slot.add_child(multiplayer_actions)
	join_button = _button("Join Game", func() -> void: join_requested.emit())
	host_button = _button("Host Game", func() -> void: host_requested.emit())
	multiplayer_back_button = _button("Back", show_main_options)
	for button in [join_button, host_button, multiplayer_back_button]:
		multiplayer_actions.add_child(button)
	editor_actions = VBoxContainer.new()
	editor_actions.name = "EditorActions"
	editor_actions.add_theme_constant_override("separation", 12)
	actions_slot.add_child(editor_actions)
	browse_levels_button = _button("Browse Levels", func() -> void: _leave_options(func() -> void: browse_levels_requested.emit()))
	create_level_button = _button("Create New", func() -> void: editor_requested.emit())
	editor_back_button = _button("Back", show_main_options)
	for button in [browse_levels_button, create_level_button, editor_back_button]:
		editor_actions.add_child(button)
	fullscreen_button = _button("Fullscreen", func() -> void: fullscreen_requested.emit())
	fullscreen_button.name = "FullscreenButton"
	fullscreen_button.custom_minimum_size = Vector2(240, 44)
	fullscreen_button.add_theme_font_size_override("font_size", 20)
	fullscreen_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_actions.add_child(fullscreen_button)
	for actions in [main_actions, multiplayer_actions, editor_actions]:
		actions.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		actions_slot.custom_minimum_size = actions_slot.custom_minimum_size.max(actions.get_combined_minimum_size())
	visibility_changed.connect(_cancel_hidden_actions)
	show_main_options(false)
	_update_wave()

func show_main_options(animate: bool = true) -> void:
	_switch_options(main_actions, multiplayer_button, animate)

func show_multiplayer_options() -> void:
	_switch_options(multiplayer_actions, join_button)

func show_editor_options(animate: bool = true) -> void:
	_switch_options(editor_actions, browse_levels_button, animate)

func _switch_options(actions: VBoxContainer, focus: Button, animate: bool = true) -> void:
	next_actions = actions
	next_focus = focus
	if not animate or not is_visible_in_tree() or active_actions == null:
		_activate_options(false)
	elif switching_actions:
		return
	elif active_actions != actions:
		switching_actions = true
		MenuSlide.dismiss(active_actions, _activate_options)

func _activate_options(animate: bool = true) -> void:
	for actions in [main_actions, multiplayer_actions, editor_actions]:
		MenuSlide.hide_now(actions)
	active_actions = next_actions
	switching_actions = false
	active_actions.show()
	if animate:
		MenuSlide.enter(active_actions)
	next_focus.grab_focus.call_deferred()

func _leave_options(after: Callable) -> void:
	if not switching_actions:
		switching_actions = true
		next_actions = null
		MenuSlide.dismiss(active_actions, func() -> void:
			if next_actions != null:
				_activate_options()
			else:
				switching_actions = false
				after.call()
		)

func _cancel_hidden_actions() -> void:
	if not is_visible_in_tree():
		for actions in [main_actions, multiplayer_actions, editor_actions]:
			MenuSlide.hide_now(actions)
		active_actions = null
		next_actions = null
		switching_actions = false
	else:
		_update_parallax()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	wave_time = fposmod(wave_time + delta * WAVE_SPEED, TAU)
	_update_wave()
	_update_parallax()

func _update_parallax() -> void:
	menu_content.position = -background.parallax_offset * MENU_PARALLAX

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

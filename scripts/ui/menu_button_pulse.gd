extends Node
## Smooth hover/focus feedback without a repeating pulse.

const STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled"]

var text_only := false
var gray_hover := false
var pointer_selection := false
var acquiring_pointer_focus := false
var button: BaseButton
var strength := 0.0
var styles: Dictionary = {}
var base_colors: Dictionary = {}

static func install(target: BaseButton, pulse_text_only: bool = false, gray_hover_box: bool = false) -> void:
	if target.has_node("MenuSelectionPulse"):
		return
	var effect := Node.new()
	effect.set_script(load("res://scripts/ui/menu_button_pulse.gd"))
	effect.name = "MenuSelectionPulse"
	effect.set("text_only", pulse_text_only)
	effect.set("gray_hover", gray_hover_box)
	target.add_child(effect)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	button = get_parent() as BaseButton
	button.mouse_entered.connect(_select_from_pointer)
	button.focus_entered.connect(_focus_entered)
	button.gui_input.connect(_gui_input)
	# Capture after the caller has assigned primary/danger button variations.
	_capture_styles.call_deferred()

func _select_from_pointer() -> void:
	# Retain navigation focus, but let the hover color fade when the mouse exits.
	pointer_selection = true
	if not button.disabled and button.focus_mode != Control.FOCUS_NONE:
		acquiring_pointer_focus = true
		button.grab_focus()
		acquiring_pointer_focus = false

func _focus_entered() -> void:
	if not acquiring_pointer_focus:
		pointer_selection = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		pointer_selection = false

func _capture_styles() -> void:
	for state in STATES:
		var original := button.get_theme_stylebox(state)
		if original is StyleBoxFlat:
			var style := original.duplicate() as StyleBoxFlat
			styles[state] = style
			base_colors[state] = [style.bg_color, style.border_color]
			button.add_theme_stylebox_override(state, style)

func _process(delta: float) -> void:
	if not button.is_visible_in_tree() or not button.get_window().visible:
		return
	var hovered := button.get_viewport().gui_get_hovered_control()
	var another_hovered := hovered is BaseButton and hovered != button
	var selected := not button.disabled and (button.is_hovered() or (button.has_focus() and not pointer_selection and not another_hovered))
	strength = lerpf(strength, 1.0 if selected else 0.0, 1.0 - exp(-12.0 * delta))
	if not selected and strength < 0.001:
		strength = 0.0
	if text_only:
		var color := Color.WHITE.lerp(Color("cccccc"), strength)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(key, color)
		return
	if gray_hover:
		for state in styles:
			var style: StyleBoxFlat = styles[state]
			var colors: Array = base_colors[state]
			var background: Color = colors[0]
			style.bg_color = background.lerp(Color("bdbdbd"), strength if state != "disabled" else 0.0)
			style.border_color = colors[1]
		return
	var amount := strength * 0.16
	for state in styles:
		var style: StyleBoxFlat = styles[state]
		var colors: Array = base_colors[state]
		var background: Color = colors[0]
		var border: Color = colors[1]
		style.bg_color = background.lightened(amount if state != "disabled" else 0.0)
		style.border_color = border.lightened(amount * 0.8 if state != "disabled" else 0.0)

extends RefCounted
## Shared popup treatment for the editor, title screen, and pause menus.

const ButtonPulse := preload("res://scripts/ui/menu_button_pulse.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const THEME := preload("res://assets/themes/game_theme.tres")

class Frame extends CanvasLayer:
	var dialog: ConfirmationDialog
	var outer := Panel.new()
	var inner := Panel.new()
	var label := Label.new()
	var edge: float
	var title_height: float
	func _init(window: ConfirmationDialog, panel: StyleBoxFlat, border: StyleBoxFlat, light: bool) -> void:
		dialog = window
		layer = -1
		process_mode = Node.PROCESS_MODE_ALWAYS
		edge = 10.0 if light else 2.0
		title_height = 40.0 if light else 32.0
		outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_theme_stylebox_override("panel", border)
		add_child(outer)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_stylebox_override("panel", panel)
		add_child(inner)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_override("font", window.get_theme_font("title_font", "Window"))
		label.add_theme_font_size_override("font_size", window.get_theme_font_size("title_font_size", "Window"))
		label.add_theme_color_override("font_color", window.get_theme_color("title_color", "Window"))
		add_child(label)
	func _process(_delta: float) -> void:
		outer.size = dialog.size
		inner.position = Vector2(edge, title_height)
		inner.size = Vector2(dialog.size) - Vector2(edge * 2.0, title_height + edge)
		label.text = dialog.title
		label.position = Vector2(18, 4)
		label.size = Vector2(maxi(0, dialog.size.x - 36), title_height - 8.0)

static func apply(dialog: ConfirmationDialog, light: bool = false) -> void:
	var theme := MenuTheme.get_theme() if light else THEME
	dialog.theme = theme
	# Godot 4.3's embedded title bars always drag. Recreate the frame inside
	# the window, keeping programmatic menu motion and keyboard input.
	dialog.borderless = true
	dialog.unresizable = true
	for button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
		ButtonPulse.install(button, false, light)
	var empty_icon := ImageTexture.new()
	for icon in ["close", "close_pressed"]:
		dialog.add_theme_icon_override(icon, empty_icon)
	dialog.add_theme_constant_override("close_h_offset", 0)
	dialog.add_theme_constant_override("close_v_offset", 0)
	var panel := theme.get_stylebox("panel", "AcceptDialog").duplicate() as StyleBoxFlat
	panel.set_corner_radius_all(10)
	if light:
		panel.bg_color = Color("dedede")
		panel.set_content_margin_all(18.0)
	var border := theme.get_stylebox("embedded_border", "Window").duplicate() as StyleBoxFlat
	border.corner_radius_bottom_left = 12
	border.corner_radius_bottom_right = 12
	border.set_border_width_all(2)
	border.set_expand_margin_all(0.0)
	border.border_color = Color.BLACK if light else Color("4c7187")
	border.bg_color = Color.WHITE if light else border.border_color
	var frame := Frame.new(dialog, panel, border, light)
	dialog.add_child(frame)
	# The frame draws behind the dialog's controls; this style only reserves
	# the same space for the title band, inset panel, and content padding.
	var layout := StyleBoxEmpty.new()
	layout.content_margin_left = panel.get_margin(SIDE_LEFT) + frame.edge
	layout.content_margin_top = panel.get_margin(SIDE_TOP) + frame.title_height
	layout.content_margin_right = panel.get_margin(SIDE_RIGHT) + frame.edge
	layout.content_margin_bottom = panel.get_margin(SIDE_BOTTOM) + frame.edge
	dialog.add_theme_stylebox_override("panel", layout)
	dialog.transparent_bg = true

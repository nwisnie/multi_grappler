extends RefCounted
## Shared popup treatment for the editor, title screen, and pause menus.

const ButtonPulse := preload("res://scripts/ui/menu_button_pulse.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const THEME := preload("res://assets/themes/game_theme.tres")

static func apply(dialog: ConfirmationDialog, light: bool = false) -> void:
	var theme := MenuTheme.get_theme() if light else THEME
	dialog.theme = theme
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
	dialog.add_theme_stylebox_override("panel", panel)
	dialog.transparent_bg = true
	for key in ["embedded_border", "embedded_unfocused_border"]:
		var border := theme.get_stylebox(key, "Window").duplicate() as StyleBoxFlat
		border.corner_radius_bottom_left = 12
		border.corner_radius_bottom_right = 12
		border.border_width_left = 2
		border.border_width_right = 2
		border.border_width_bottom = 2
		border.expand_margin_left = 10.0 if light else 2.0
		border.expand_margin_right = 10.0 if light else 2.0
		border.expand_margin_bottom = 10.0 if light else 2.0
		if light:
			border.expand_margin_top = 40.0
		border.border_color = Color.BLACK if light else Color("4c7187")
		border.bg_color = Color.WHITE if light else border.border_color
		dialog.add_theme_stylebox_override(key, border)

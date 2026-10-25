extends RefCounted
## A separate menu palette; the level editor keeps its original theme.

const BASE := preload("res://assets/themes/game_theme.tres")
static var cached: Theme

static func get_theme() -> Theme:
	if cached != null:
		return cached
	var theme := Theme.new()
	theme.merge_with(BASE)
	theme.default_font = BASE.default_font
	theme.default_font_size = BASE.default_font_size
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := _box()
		if state == "disabled":
			box.bg_color = Color("eeeeee")
			box.border_color = Color("909090")
		theme.set_stylebox(state, "Button", box)
		theme.set_stylebox(state, "PrimaryButton", box)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(key, "Button", Color.BLACK)
		theme.set_color(key, "PrimaryButton", Color.BLACK)
	theme.set_color("font_disabled_color", "Button", Color("737373"))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Label", Color.BLACK)
	for state in ["normal", "focus", "read_only"]:
		theme.set_stylebox(state, "LineEdit", _box())
		theme.set_stylebox(state, "TextEdit", _box())
	for type in ["LineEdit", "TextEdit"]:
		theme.set_color("font_color", type, Color.BLACK)
		theme.set_color("font_selected_color", type, Color.BLACK)
		theme.set_color("caret_color", type, Color.BLACK)
		theme.set_color("font_placeholder_color", type, Color("666666"))
		theme.set_color("selection_color", type, Color("9bd0ff"))
	for type in ["AcceptDialog", "PanelContainer", "PopupPanel"]:
		theme.set_stylebox("panel", type, _box())
	for key in ["embedded_border", "embedded_unfocused_border"]:
		var border := BASE.get_stylebox(key, "Window").duplicate() as StyleBoxFlat
		border.bg_color = Color.WHITE
		border.border_color = Color.BLACK
		border.set_border_width_all(2)
		theme.set_stylebox(key, "Window", border)
	theme.set_color("title_color", "Window", Color.BLACK)
	theme.set_stylebox("panel", "Window", _box())
	cached = theme
	return cached

static func _box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.WHITE
	box.border_color = Color.BLACK
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 9.0
	box.content_margin_bottom = 9.0
	return box

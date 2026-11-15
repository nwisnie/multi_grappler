extends RefCounted
## A separate menu palette; the level editor keeps its original theme.

const BASE := preload("res://assets/themes/game_theme.tres")
const CHECKBOX_OFF := preload("res://assets/themes/menu_checkbox_off.svg")
const CHECKBOX_ON := preload("res://assets/themes/menu_checkbox_on.svg")
const SLIDER_THUMB := preload("res://assets/themes/menu_slider_thumb.svg")
const SLIDER_THUMB_HOVER := preload("res://assets/themes/menu_slider_thumb_hover.svg")
const SLIDER_THUMB_DISABLED := preload("res://assets/themes/menu_slider_thumb_disabled.svg")
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
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var checkbox_style := StyleBoxEmpty.new()
		checkbox_style.set_content_margin_all(6.0)
		theme.set_stylebox(state, "CheckBox", checkbox_style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(key, "CheckBox", Color.BLACK)
	theme.set_color("font_disabled_color", "CheckBox", Color("737373"))
	theme.set_stylebox("slider", "HSlider", _slider_track(Color("909090")))
	theme.set_stylebox("grabber_area", "HSlider", _slider_track(Color("404040")))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _slider_track(Color("202020")))
	theme.set_icon("grabber", "HSlider", SLIDER_THUMB)
	theme.set_icon("grabber_highlight", "HSlider", SLIDER_THUMB_HOVER)
	theme.set_icon("grabber_disabled", "HSlider", SLIDER_THUMB_DISABLED)
	theme.set_icon("unchecked", "CheckBox", CHECKBOX_OFF)
	theme.set_icon("checked", "CheckBox", CHECKBOX_ON)
	theme.set_icon("unchecked_disabled", "CheckBox", CHECKBOX_OFF)
	theme.set_icon("checked_disabled", "CheckBox", CHECKBOX_ON)
	theme.set_constant("h_separation", "CheckBox", 12)
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

static func _slider_track(color: Color) -> StyleBoxFlat:
	var track := StyleBoxFlat.new()
	track.bg_color = color
	track.border_color = Color("202020")
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	return track

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

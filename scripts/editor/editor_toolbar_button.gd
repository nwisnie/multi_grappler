class_name EditorToolbarButton
extends Button
## Native button behavior and text, with an animated, rounded/slanted face.

enum Segment { SINGLE, FIRST, MIDDLE, LAST }
const SLANT := 6.0
const GAP := 4.0

class Face extends Control:
	var button: EditorToolbarButton
	func _draw() -> void:
		button.draw_face(self)

var segment: int = Segment.SINGLE
var _face: Face
var _palettes: Dictionary = {}
var _draw_mode := -1
var _background := Color.TRANSPARENT
var _border := Color.TRANSPARENT
var _foreground := Color.WHITE
var _fade: Tween

func _ready() -> void:
	# Capture the theme (including primary/danger variations) before suppressing
	# native backgrounds. Native text, tooltips, disabled state and toggles remain.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := get_theme_stylebox(state) as StyleBoxFlat
		var font_key: String = "font_color" if state == "normal" else "font_" + state + "_color"
		_palettes[state] = [style.bg_color, style.border_color, get_theme_color(font_key)]
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 14.0 if segment == Segment.SINGLE else 18.0
	empty.content_margin_right = empty.content_margin_left
	empty.content_margin_top = 9.0
	empty.content_margin_bottom = 9.0
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	_face = Face.new()
	_face.button = self
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.show_behind_parent = true
	add_child(_face)
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_draw_mode = get_draw_mode()
	var palette: Array = _palettes[_state_name(_draw_mode)]
	_apply_colors(palette[0], palette[1], palette[2])
	resized.connect(func() -> void: _face.queue_redraw())

func _state_name(mode: int) -> String:
	match mode:
		DRAW_PRESSED: return "pressed"
		DRAW_HOVER: return "hover"
		DRAW_HOVER_PRESSED: return "hover_pressed"
		DRAW_DISABLED: return "disabled"
	return "normal"

func _process(delta: float) -> void:
	var mode := get_draw_mode()
	if not disabled and (is_hovered() or has_focus() or button_pressed):
		_face.queue_redraw()
	if mode == _draw_mode:
		return
	_draw_mode = mode
	if _fade != null:
		_fade.kill()
	var palette: Array = _palettes[_state_name(mode)]
	var start := [_background, _border, _foreground]
	var duration := 0.14 if mode in [DRAW_HOVER, DRAW_HOVER_PRESSED] else 0.20
	_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade.tween_method(func(weight: float) -> void:
		_apply_colors(start[0].lerp(palette[0], weight), start[1].lerp(palette[1], weight), start[2].lerp(palette[2], weight))
	, 0.0, 1.0, duration)

func _apply_colors(background: Color, border: Color, foreground: Color) -> void:
	_background = background
	_border = border
	_foreground = foreground
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		add_theme_color_override(key, foreground)
	_face.queue_redraw()

func _polygon(inset: float) -> PackedVector2Array:
	var top := inset
	var bottom := size.y - inset
	var slant := minf(SLANT, size.y * 0.2)
	var top_shift := slant * (1.0 - 2.0 * top / maxf(size.y, 1.0))
	var bottom_shift := slant * (1.0 - 2.0 * bottom / maxf(size.y, 1.0))
	var first := segment in [Segment.SINGLE, Segment.FIRST]
	var last := segment in [Segment.SINGLE, Segment.LAST]
	var left_top := inset if first else top_shift + GAP * 0.5 + inset
	var left_bottom := inset if first else bottom_shift + GAP * 0.5 + inset
	var right_top := size.x - inset if last else size.x + top_shift - GAP * 0.5 - inset
	var right_bottom := size.x - inset if last else size.x + bottom_shift - GAP * 0.5 - inset
	var corners := PackedVector2Array([Vector2(left_top, top), Vector2(right_top, top), Vector2(right_bottom, bottom), Vector2(left_bottom, bottom)])
	var result := PackedVector2Array()
	for index in range(4):
		var point := corners[index]
		var previous := corners[(index + 3) % 4]
		var next := corners[(index + 1) % 4]
		var outside := (first and index in [0, 3]) or (last and index in [1, 2])
		var radius := maxf((8.0 if outside else 3.0) - inset, 0.5)
		var trim := minf(radius, minf(point.distance_to(previous), point.distance_to(next)) * 0.4)
		var start := point.move_toward(previous, trim)
		var end := point.move_toward(next, trim)
		for step in range(6):
			var t := float(step) / 5.0
			result.append(start * (1.0 - t) * (1.0 - t) + point * 2.0 * t * (1.0 - t) + end * t * t)
	return result

func _has_point(point: Vector2) -> bool:
	# Match the diagonal edge so the narrow gaps never trigger either option.
	return Geometry2D.is_point_in_polygon(point, _polygon(0.0))

func draw_face(canvas: Control) -> void:
	var selected := not disabled and (is_hovered() or has_focus() or button_pressed)
	var amount := 0.12 if selected else 0.0
	canvas.draw_colored_polygon(_polygon(0.0), _border.lightened(amount * 0.8))
	canvas.draw_colored_polygon(_polygon(1.3), _background.lightened(amount))

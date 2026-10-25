extends Button
## Slanted title-menu face with native button text and navigation.

const BORDER_WIDTH := 3.0
const SLANT := 20.0
const CORNER_RADIUS := 7.0

class Face extends Control:
	var button: Button
	func _draw() -> void:
		button.draw_face(self)

var _face: Face
var _selection := -1.0

func _ready() -> void:
	# Draw the face behind the native text; the shared helper still drives hover.
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 24.0
	empty.content_margin_right = 24.0
	empty.content_margin_top = 10.0
	empty.content_margin_bottom = 10.0
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	_face = Face.new()
	_face.button = self
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.show_behind_parent = true
	add_child(_face)
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_face.queue_redraw)

func _process(_delta: float) -> void:
	var effect := get_node_or_null("MenuSelectionPulse")
	var selection: float = effect.strength if effect != null and not disabled else 0.0
	if selection != _selection:
		_selection = selection
		_face.queue_redraw()

func _polygon(inset: float) -> PackedVector2Array:
	var height := maxf(size.y, 1.0)
	var slant := minf(SLANT, height * 0.4)
	var top := inset
	var bottom := height - inset
	# Inset perpendicular to the diagonal sides to keep the outline even.
	var edge_inset := inset * sqrt(1.0 + pow(slant / height, 2.0))
	var top_shift := slant * (1.0 - top / height)
	var bottom_shift := slant * (1.0 - bottom / height)
	var corners := PackedVector2Array([
		Vector2(top_shift + edge_inset, top),
		Vector2(size.x - slant + top_shift - edge_inset, top),
		Vector2(size.x - slant + bottom_shift - edge_inset, bottom),
		Vector2(bottom_shift + edge_inset, bottom),
	])
	var polygon := PackedVector2Array()
	for index in range(4):
		var point := corners[index]
		var previous := corners[(index + 3) % 4]
		var next := corners[(index + 1) % 4]
		var radius := maxf(CORNER_RADIUS - inset, 0.5)
		var trim := minf(radius, minf(point.distance_to(previous), point.distance_to(next)) * 0.4)
		var start := point.move_toward(previous, trim)
		var end := point.move_toward(next, trim)
		for step in range(7):
			var weight := float(step) / 6.0
			polygon.append(start * (1.0 - weight) * (1.0 - weight) + point * 2.0 * weight * (1.0 - weight) + end * weight * weight)
	return polygon

func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, _polygon(0.0))

func draw_face(canvas: Control) -> void:
	canvas.draw_colored_polygon(_polygon(0.0), Color.BLACK)
	canvas.draw_colored_polygon(_polygon(BORDER_WIDTH), Color.WHITE.lerp(Color("bdbdbd"), maxf(_selection, 0.0)))

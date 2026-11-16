extends Button
## Slanted title-menu face with native button text and navigation.

enum Segment { SINGLE, FIRST, LAST, MIDDLE }

const BORDER_WIDTH := 3.0
const SLANT := 20.0
const JOIN_SLANT := 6.0
const JOIN_GAP := 4.0
const CORNER_RADIUS := 7.0
const HOVER_ROTATION := 1.5
const HOVER_SPEED := 6.0
const HOVER_SMOOTHING := 12.0

class Face extends Control:
	var button: Button
	func _draw() -> void:
		button.draw_face(self)

var _face: Face
var _selection := -1.0
var _hover_time := 0.0
var _hover_strength := 0.0
var segment: int = Segment.SINGLE

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
	resized.connect(_update_pivot)
	visibility_changed.connect(_reset_wobble)
	_update_pivot()

func _update_pivot() -> void:
	pivot_offset = size * 0.5

func _reset_wobble() -> void:
	_hover_time = 0.0
	_hover_strength = 0.0
	rotation = 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not get_window().visible:
		return
	var effect := get_node_or_null("MenuSelectionPulse")
	var selection: float = effect.strength if effect != null and not disabled else 0.0
	if selection != _selection:
		_selection = selection
		_face.queue_redraw()
	if segment != Segment.SINGLE:
		# Joined options retain hover shading without rotating their shared seam.
		_reset_wobble()
		return
	var hovered := is_hovered() and not disabled
	_hover_strength = lerpf(_hover_strength, 1.0 if hovered else 0.0, 1.0 - exp(-HOVER_SMOOTHING * delta))
	if not hovered and _hover_strength < 0.001:
		_reset_wobble()
		return
	_hover_time = fposmod(_hover_time + delta * HOVER_SPEED, TAU)
	rotation = deg_to_rad(HOVER_ROTATION) * sin(_hover_time) * _hover_strength

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
	if segment != Segment.SINGLE:
		var join_slant := minf(JOIN_SLANT, height * 0.2)
		var join_top := join_slant * (1.0 - 2.0 * top / height)
		var join_bottom := join_slant * (1.0 - 2.0 * bottom / height)
		corners = PackedVector2Array([
			Vector2(inset, top), Vector2(size.x - inset, top),
			Vector2(size.x - inset, bottom), Vector2(inset, bottom),
		])
		if segment in [Segment.FIRST, Segment.MIDDLE]:
			corners[1].x = size.x + join_top - JOIN_GAP * 0.5 - inset
			corners[2].x = size.x + join_bottom - JOIN_GAP * 0.5 - inset
		if segment in [Segment.LAST, Segment.MIDDLE]:
			corners[0].x = join_top + JOIN_GAP * 0.5 + inset
			corners[3].x = join_bottom + JOIN_GAP * 0.5 + inset
	var polygon := PackedVector2Array()
	for index in range(4):
		var point := corners[index]
		var previous := corners[(index + 3) % 4]
		var next := corners[(index + 1) % 4]
		var at_join := (segment in [Segment.FIRST, Segment.MIDDLE] and index in [1, 2]) or (segment in [Segment.LAST, Segment.MIDDLE] and index in [0, 3])
		var radius := maxf((3.0 if at_join else CORNER_RADIUS) - inset, 0.5)
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
	# Put the fill edge under an antialiased stroke, so both sides of the
	# slanted border stay smooth without enabling antialiasing for all gameplay.
	var outline := _polygon(BORDER_WIDTH * 0.5)
	canvas.draw_colored_polygon(outline, Color.WHITE.lerp(Color("bdbdbd"), maxf(_selection, 0.0)))
	outline.append(outline[0])
	canvas.draw_polyline(outline, Color.BLACK, BORDER_WIDTH, true)

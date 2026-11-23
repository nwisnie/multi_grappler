extends Control
## Smooth, tapered HUD bars, with optional speedometer marks.

const DIVISIONS := 12
const REFERENCE_WIDTH := 250.0
const OUTLINE_WIDTH := 4.0
const TITLE_POSITION := Vector2(48.0, -17.0)
const TITLE_SIDE_PADDING := 8.0

var title := ""
var fill_color := Color(0.905882, 0.6, 0.623529, 0.96)
var background_color := Color(0.22, 0.11, 0.13, 0.94)
var show_ticks := true
var value := 0.0:
	set(next_value):
		next_value = clampf(next_value, 0.0, 1.0)
		if value == next_value:
			return
		value = next_value
		queue_redraw()

var _title_label: Label
var _geometry_dirty := true
var _outline := PackedVector2Array()
var _outline_stroke := PackedVector2Array()
var _interior := PackedVector2Array()
var _interior_stroke := PackedVector2Array()

func _ready() -> void:
	resized.connect(_invalidate_geometry)
	if title.is_empty():
		return
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = title
	_title_label.position = TITLE_POSITION
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_title_label)
	_title_label.minimum_size_changed.connect(_invalidate_geometry)

func _invalidate_geometry() -> void:
	_geometry_dirty = true
	queue_redraw()

func _draw() -> void:
	if _geometry_dirty:
		_outline = _bar_outline(0.0)
		_outline_stroke = _closed(_outline)
		_interior = _bar_outline(OUTLINE_WIDTH)
		_interior_stroke = _closed(_interior) if not _interior.is_empty() else PackedVector2Array()
		_geometry_dirty = false
	draw_colored_polygon(_outline, Color.BLACK)
	draw_polyline(_outline_stroke, Color.BLACK, 1.5, true)
	if _interior.is_empty():
		return
	draw_colored_polygon(_interior, background_color)
	draw_polyline(_interior_stroke, background_color, 1.0, true)

	# Clip a fixed interior shape so its slope stays steady as the fill moves.
	var fill_end := lerpf(OUTLINE_WIDTH - 6.0, size.x + 8.0 - OUTLINE_WIDTH, value)
	if value > 0.0:
		var fill_bounds := PackedVector2Array([
			Vector2(-10.0, -10.0), Vector2(fill_end, -10.0),
			Vector2(fill_end, size.y + 10.0), Vector2(-10.0, size.y + 10.0),
		])
		for polygon in Geometry2D.intersect_polygons(_interior, fill_bounds):
			draw_colored_polygon(polygon, fill_color)
			draw_polyline(_closed(polygon), fill_color, 1.0, true)

	if show_ticks:
		for index in range(DIVISIONS + 1):
			var ratio := float(index) / float(DIVISIONS)
			var x := lerpf(14.0, size.x - 20.0, ratio)
			var top := _top_edge_y(x) + OUTLINE_WIDTH + 1.5
			var length := 8.0 if index % 3 == 0 else 4.0
			var color := Color(0.15, 0.07, 0.09, 0.9) if x <= fill_end else Color(1.0, 0.84, 0.85, 0.6)
			draw_line(Vector2(x, top), Vector2(x, top + length), color, 1.5, true)

func _top_edge_y(x: float) -> float:
	return lerpf(-6.0, size.y * 0.08, (x + 6.0) / (REFERENCE_WIDTH + 4.0))

func _bar_outline(inset: float) -> PackedVector2Array:
	# Preserve the edge angles when the shorter launch bar uses the same profile.
	var right_top := _top_edge_y(size.x - 2.0)
	var right_bottom := lerpf(size.y, size.y * 0.9, (size.x - 10.0) / (REFERENCE_WIDTH - 10.0))
	var corners := PackedVector2Array([Vector2(-6.0, -6.0)])
	if inset == 0.0 and _title_label != null:
		var tab_left := TITLE_POSITION.x - TITLE_SIDE_PADDING
		var tab_right := TITLE_POSITION.x + _title_label.get_combined_minimum_size().x + TITLE_SIDE_PADDING
		var tab_top := TITLE_POSITION.y - 2.0
		corners.append_array(PackedVector2Array([
			Vector2(tab_left, _top_edge_y(tab_left)),
			Vector2(tab_left + 5.0, tab_top),
			Vector2(tab_right - 5.0, tab_top),
			Vector2(tab_right, _top_edge_y(tab_right)),
		]))
	corners.append_array(PackedVector2Array([
		Vector2(size.x - 2.0, right_top),
		Vector2(size.x + 8.0, size.y * 0.4),
		Vector2(size.x - 10.0, right_bottom),
		Vector2(0.0, size.y),
	]))
	var outline := _round_corners(corners)
	if inset == 0.0:
		return outline
	# Inset the rounded bar by the same distance along every edge.
	var interiors := Geometry2D.offset_polygon(outline, -inset, Geometry2D.JOIN_MITER)
	return interiors[0] if not interiors.is_empty() else PackedVector2Array()

func _round_corners(corners: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := 5.0
	for index in range(corners.size()):
		var corner := corners[index]
		var before := corners[(index + corners.size() - 1) % corners.size()] - corner
		var after := corners[(index + 1) % corners.size()] - corner
		var entry := corner + before.normalized() * minf(radius, before.length() * 0.4)
		var exit_point := corner + after.normalized() * minf(radius, after.length() * 0.4)
		for step in range(7):
			var t := float(step) / 6.0
			points.append(entry.lerp(corner, t).lerp(corner.lerp(exit_point, t), t))
	return points

func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed

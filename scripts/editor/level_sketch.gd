@tool
class_name LevelSketch
extends Node2D

const GENERATED_LEVEL_NAME := "GeneratedLevel"
const LevelSketchVisualScript := preload("res://scripts/editor/level_sketch_visual.gd")
const END_CAP_SEGMENTS := 24
const VISUAL_OUTLINE_EXTRA_WIDTH := 12.0
const VISUAL_CENTERLINE_WIDTH := 4.0
const VISUAL_ROUND_PRECISION := 24
const SHADING_WIDTH_RATIO := 0.42
const SHADING_POINT_SPACING_MULTIPLIER := 1.45
const HIGHLIGHT_WIDTH_RATIO := 0.14
const HIGHLIGHT_POINT_SPACING_MULTIPLIER := 0.9
const HIGHLIGHT_OFFSET_RATIO := -0.2
const GROUND_GRASS_DEPTH := 48.0
const GROUND_SPECKLE_SPACING := 55.0
const GROUND_MAX_SPECKLES := 2000

enum DrawMode {
	LINE,
	GROUND,
}

@export_enum("Line", "Ground") var draw_mode: int = DrawMode.LINE:
	set(value):
		draw_mode = clampi(value, DrawMode.LINE, DrawMode.GROUND)
		queue_redraw()

@export_range(8.0, 256.0, 1.0) var terrain_half_width := 64.0:
	set(value):
		terrain_half_width = value
		queue_redraw()
@export_range(0.0, 100.0, 1.0) var edge_roundness := 100.0:
	set(value):
		edge_roundness = value
		queue_redraw()
@export_range(2.0, 96.0, 1.0) var min_point_spacing := 12.0
@export_range(0.0, 32.0, 0.5) var simplify_tolerance := 4.0
@export var fill_color := Color("58616b"):
	set(value):
		fill_color = value
		queue_redraw()
@export var shading_color := Color("424850"):
	set(value):
		shading_color = value
		queue_redraw()
@export var show_shading := true:
	set(value):
		show_shading = value
		queue_redraw()
@export var highlight_color := Color("d7e1e6"):
	set(value):
		highlight_color = value
		queue_redraw()
@export var show_highlight := true:
	set(value):
		show_highlight = value
		queue_redraw()
@export var outline_color := Color.BLACK:
	set(value):
		outline_color = value
		queue_redraw()
@export_range(4.0, 64.0, 1.0) var outline_point_spacing := 10.0:
	set(value):
		outline_point_spacing = value
		queue_redraw()
@export_range(0.0, 12.0, 0.25) var outline_jitter := 2.0:
	set(value):
		outline_jitter = value
		queue_redraw()
@export_range(0.0, 4.0, 0.05) var friction := 1.1
@export_flags_2d_physics var terrain_collision_layer := 1
@export_flags_2d_physics var terrain_collision_mask := 1
@export_group("Ground")
@export_range(64.0, 4096.0, 1.0) var ground_depth := 768.0:
	set(value):
		ground_depth = value
		queue_redraw()
@export_range(4.0, 512.0, 1.0) var ground_grass_height := GROUND_GRASS_DEPTH:
	set(value):
		ground_grass_height = value
		queue_redraw()
@export var ground_fill_color := Color("5f7d4e"):
	set(value):
		ground_fill_color = value
		queue_redraw()
@export var ground_shading_color := Color("6b4a35"):
	set(value):
		ground_shading_color = value
		queue_redraw()
@export var ground_show_shading := true:
	set(value):
		ground_show_shading = value
		queue_redraw()
@export var ground_highlight_color := Color("b99268"):
	set(value):
		ground_highlight_color = value
		queue_redraw()
@export var ground_show_highlight := true:
	set(value):
		ground_show_highlight = value
		queue_redraw()
@export var ground_outline_color := Color.BLACK:
	set(value):
		ground_outline_color = value
		queue_redraw()
@export_group("")
@export var strokes: Array[PackedVector2Array] = []:
	set(value):
		strokes = value
		queue_redraw()
@export var stroke_modes := PackedInt32Array():
	set(value):
		stroke_modes = value
		queue_redraw()
@export var draw_node_preview := false:
	set(value):
		draw_node_preview = value
		queue_redraw()

var active_stroke := PackedVector2Array()
var active_stroke_mode: int = DrawMode.LINE

func begin_stroke(point: Vector2) -> void:
	active_stroke_mode = draw_mode
	active_stroke = PackedVector2Array([point])
	queue_redraw()

func add_stroke_point(point: Vector2) -> void:
	if active_stroke.is_empty():
		active_stroke.append(point)
	elif active_stroke[-1].distance_to(point) >= min_point_spacing:
		active_stroke.append(point)
		queue_redraw()

func finish_stroke() -> void:
	if active_stroke.size() >= 2:
		var simplified := _simplify(active_stroke, simplify_tolerance)
		if simplified.size() >= 2:
			while stroke_modes.size() < strokes.size():
				stroke_modes.append(DrawMode.LINE)
			strokes.append(simplified)
			stroke_modes.append(active_stroke_mode)
	active_stroke.clear()
	queue_redraw()

func undo_stroke() -> void:
	if not strokes.is_empty():
		strokes.remove_at(strokes.size() - 1)
		if stroke_modes.size() > strokes.size():
			stroke_modes.resize(strokes.size())
		queue_redraw()

func clear_strokes() -> void:
	active_stroke.clear()
	strokes.clear()
	stroke_modes.clear()
	queue_redraw()

func has_strokes() -> bool:
	return not strokes.is_empty() or not active_stroke.is_empty()

func has_bakeable_strokes() -> bool:
	for stroke in strokes:
		if stroke.size() >= 2:
			return true
	return false

func get_stroke_mode(index: int) -> int:
	if index >= 0 and index < stroke_modes.size():
		return clampi(stroke_modes[index], DrawMode.LINE, DrawMode.GROUND)
	return DrawMode.LINE

func bake_to_scene() -> void:
	var parent := get_parent()
	if parent == null:
		push_warning("LevelSketch needs a parent scene node before it can bake.")
		return

	var scene_owner := _scene_owner()
	var generated := parent.get_node_or_null(GENERATED_LEVEL_NAME) as Node2D
	if generated == null:
		generated = Node2D.new()
		generated.name = GENERATED_LEVEL_NAME
		parent.add_child(generated)
	generated.owner = scene_owner

	var terrain_physics_material := PhysicsMaterial.new()
	terrain_physics_material.friction = friction

	var body := StaticBody2D.new()
	body.name = _next_terrain_name(generated)
	body.collision_layer = terrain_collision_layer
	body.collision_mask = terrain_collision_mask
	body.physics_material_override = terrain_physics_material
	generated.add_child(body)
	body.owner = scene_owner

	var baked_count := 0
	var visual_items: Array[Dictionary] = []
	for i in range(strokes.size()):
		var stroke := _simplify(strokes[i], simplify_tolerance)
		if stroke.size() < 2:
			continue
		var mode := get_stroke_mode(i)
		var polygon := _ground_to_polygon(stroke) if mode == DrawMode.GROUND else _stroke_to_polygon(stroke)
		if polygon.size() < 3:
			continue
		if mode == DrawMode.GROUND:
			_append_ground_visual_items(visual_items, stroke)
		else:
			_append_line_visual_items(visual_items, stroke)

		var collision := CollisionPolygon2D.new()
		collision.name = "CollisionPolygon2D%d" % (baked_count + 1)
		collision.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
		collision.polygon = polygon
		collision.disabled = false
		body.add_child(collision)
		collision.owner = scene_owner
		baked_count += 1

	if baked_count == 0:
		generated.remove_child(body)
		body.free()
		return

	var visual_node := LevelSketchVisualScript.new()
	visual_node.name = "Visuals"
	visual_node.draw_items = visual_items
	body.add_child(visual_node)
	body.move_child(visual_node, 0)
	visual_node.owner = scene_owner

	clear_strokes()
	hide()
	queue_redraw()

func _make_visual_item(points: PackedVector2Array, width: float, color: Color, cap_roundness: float = 1.0) -> Dictionary:
	return {
		"kind": "polyline",
		"points": points,
		"width": width,
		"color": color,
		"cap_roundness": cap_roundness,
	}

func _make_polygon_item(points: PackedVector2Array, color: Color) -> Dictionary:
	return {
		"kind": "polygon",
		"points": points,
		"color": color,
	}

func _make_speckles_item(speckles: Dictionary, color: Color) -> Dictionary:
	return {
		"kind": "speckles",
		"points": speckles.get("points", PackedVector2Array()),
		"radii": speckles.get("radii", PackedFloat32Array()),
		"color": color,
	}

func _append_line_visual_items(visual_items: Array[Dictionary], stroke: PackedVector2Array) -> void:
	var visual_stroke := make_outline_points(stroke)
	var cap_roundness := edge_roundness / 100.0
	visual_items.append(_make_visual_item(visual_stroke, terrain_half_width * 2.0 + VISUAL_OUTLINE_EXTRA_WIDTH, outline_color, cap_roundness))
	visual_items.append(_make_visual_item(visual_stroke, terrain_half_width * 2.0, fill_color, cap_roundness))
	if show_shading:
		visual_items.append(_make_visual_item(make_shading_points(stroke), terrain_half_width * 2.0 * SHADING_WIDTH_RATIO, shading_color, cap_roundness))
	if show_highlight:
		for highlight_points in make_highlight_segments(stroke):
			if highlight_points.size() >= 2:
				visual_items.append(_make_visual_item(highlight_points, terrain_half_width * 2.0 * HIGHLIGHT_WIDTH_RATIO, highlight_color, cap_roundness))

func _append_ground_visual_items(visual_items: Array[Dictionary], stroke: PackedVector2Array) -> void:
	var ground_polygon := make_ground_visual_polygon(stroke)
	var grass_polygon := make_ground_grass_polygon(stroke)
	var body_color := ground_shading_color if ground_show_shading else ground_fill_color
	visual_items.append(_make_polygon_item(ground_polygon, body_color))
	visual_items.append(_make_polygon_item(grass_polygon, ground_fill_color))
	if ground_show_highlight:
		visual_items.append(_make_speckles_item(make_ground_speckles(stroke), ground_highlight_color))
	visual_items.append(_make_visual_item(_close_polygon(ground_polygon), VISUAL_CENTERLINE_WIDTH, ground_outline_color))

func _draw() -> void:
	if not draw_node_preview:
		return
	for index in range(strokes.size()):
		_draw_stroke(strokes[index], 0.9, get_stroke_mode(index))
	if active_stroke.size() > 0:
		_draw_stroke(active_stroke, 0.55, active_stroke_mode)

func _draw_stroke(stroke: PackedVector2Array, alpha: float, mode: int = DrawMode.LINE) -> void:
	if mode == DrawMode.GROUND:
		_draw_ground_stroke(stroke, alpha)
		return
	if stroke.size() < 2:
		for point in stroke:
			draw_circle(point, terrain_half_width * 0.35, outline_color)
		return
	var fill := fill_color
	fill.a *= alpha
	var shading := shading_color
	shading.a *= alpha
	var highlight := highlight_color
	highlight.a *= alpha
	var outline := outline_color
	outline.a *= alpha
	var visual_stroke := make_outline_points(stroke)
	var cap_roundness := edge_roundness / 100.0
	_draw_rounded_polyline(visual_stroke, outline, terrain_half_width * 2.0 + VISUAL_OUTLINE_EXTRA_WIDTH, cap_roundness)
	_draw_rounded_polyline(visual_stroke, fill, terrain_half_width * 2.0, cap_roundness)
	if show_shading:
		_draw_rounded_polyline(make_shading_points(stroke), shading, terrain_half_width * 2.0 * SHADING_WIDTH_RATIO, cap_roundness)
	if show_highlight:
		for highlight_segment in make_highlight_segments(stroke):
			_draw_rounded_polyline(highlight_segment, highlight, terrain_half_width * 2.0 * HIGHLIGHT_WIDTH_RATIO, cap_roundness)
	_draw_rounded_polyline(visual_stroke, outline, VISUAL_CENTERLINE_WIDTH, cap_roundness)

func _draw_ground_stroke(stroke: PackedVector2Array, alpha: float) -> void:
	if stroke.size() < 2:
		return
	var body_color := ground_shading_color if ground_show_shading else ground_fill_color
	body_color.a *= alpha
	var grass_color := ground_fill_color
	grass_color.a *= alpha
	var edge_color := ground_outline_color
	edge_color.a *= alpha
	draw_colored_polygon(make_ground_visual_polygon(stroke), body_color)
	draw_colored_polygon(make_ground_grass_polygon(stroke), grass_color)
	if ground_show_highlight:
		var speckle_color := ground_highlight_color
		speckle_color.a *= alpha
		_draw_ground_speckles(make_ground_speckles(stroke), speckle_color)
	_draw_rounded_polyline(_close_polygon(make_ground_visual_polygon(stroke)), edge_color, VISUAL_CENTERLINE_WIDTH)

func _draw_ground_speckles(speckles: Dictionary, color: Color) -> void:
	var points: PackedVector2Array = speckles.get("points", PackedVector2Array())
	var radii: PackedFloat32Array = speckles.get("radii", PackedFloat32Array())
	for index in range(points.size()):
		var radius := radii[index] if index < radii.size() else 2.0
		draw_circle(points[index], radius, color)

func _draw_rounded_polyline(points: PackedVector2Array, color: Color, width: float, cap_roundness: float = 1.0) -> void:
	if points.size() < 2:
		return
	draw_polyline(points, color, width, true)
	var extension := width * 0.5 * clampf(cap_roundness, 0.0, 1.0)
	if extension > 0.0:
		_draw_elliptical_cap(points[0], points[1] - points[0], width * 0.5, extension, color)
		_draw_elliptical_cap(points[-1], points[-1] - points[-2], width * 0.5, extension, color)

func _draw_elliptical_cap(center: Vector2, tangent: Vector2, half_width: float, extension: float, color: Color) -> void:
	if tangent.length_squared() <= 0.001:
		return
	var forward := tangent.normalized()
	var normal := forward.orthogonal()
	var cap := PackedVector2Array()
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		cap.append(center + forward * cos(angle) * extension + normal * sin(angle) * half_width)
	draw_colored_polygon(cap, color)

func make_outline_points(stroke: PackedVector2Array) -> PackedVector2Array:
	if stroke.size() < 2:
		return stroke.duplicate()
	var resampled := _resample_stroke(stroke, outline_point_spacing)
	if outline_jitter <= 0.0 or resampled.size() < 3:
		return resampled
	var jittered := PackedVector2Array()
	for i in range(resampled.size()):
		var point := resampled[i]
		if i == 0 or i == resampled.size() - 1:
			jittered.append(point)
			continue
		var tangent := resampled[i + 1] - resampled[i - 1]
		if tangent.length_squared() <= 0.001:
			jittered.append(point)
			continue
		var normal := tangent.normalized().orthogonal()
		var amount := (_stable_random(point, i) * 2.0 - 1.0) * outline_jitter
		jittered.append(point + normal * amount)
	return jittered

func make_shading_points(stroke: PackedVector2Array) -> PackedVector2Array:
	if stroke.size() < 2:
		return stroke.duplicate()
	var spacing := maxf(4.0, outline_point_spacing * SHADING_POINT_SPACING_MULTIPLIER)
	var resampled := _resample_stroke(stroke, spacing)
	if resampled.size() < 3:
		return resampled
	var shaded := PackedVector2Array()
	for i in range(resampled.size()):
		var point := resampled[i]
		var tangent := Vector2.ZERO
		if i > 0:
			tangent += point - resampled[i - 1]
		if i < resampled.size() - 1:
			tangent += resampled[i + 1] - point
		if tangent.length_squared() <= 0.001:
			shaded.append(point)
			continue
		var normal := tangent.normalized().orthogonal()
		var lateral_seed := _stable_random(point + Vector2(91.0, -37.0), i)
		var wobble_seed := _stable_random(point + Vector2(-23.0, 109.0), i + 17)
		var lateral := (lateral_seed * 2.0 - 1.0) * maxf(outline_jitter * 1.8, terrain_half_width * 0.035)
		var wobble := (wobble_seed * 2.0 - 1.0) * outline_jitter
		shaded.append(point + normal * (lateral + wobble))
	return shaded

func make_highlight_segments(stroke: PackedVector2Array) -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	if stroke.size() < 2:
		return segments
	var spacing := maxf(4.0, outline_point_spacing * HIGHLIGHT_POINT_SPACING_MULTIPLIER)
	var resampled := _resample_stroke(stroke, spacing)
	var current := PackedVector2Array()
	for i in range(resampled.size()):
		var point := resampled[i]
		var run_index := int(floor(float(i) / 4.0))
		var visible := _stable_random(stroke[0] + Vector2(float(run_index) * 31.0, 211.0), run_index) > 0.42
		if visible:
			current.append(_highlight_point(resampled, i))
		elif current.size() > 0:
			if current.size() >= 2:
				segments.append(current)
			current = PackedVector2Array()
	if current.size() >= 2:
		segments.append(current)
	return segments

func _highlight_point(points: PackedVector2Array, index: int) -> Vector2:
	var point := points[index]
	var tangent := Vector2.ZERO
	if index > 0:
		tangent += point - points[index - 1]
	if index < points.size() - 1:
		tangent += points[index + 1] - point
	if tangent.length_squared() <= 0.001:
		return point
	var normal := tangent.normalized().orthogonal()
	var lateral_seed := _stable_random(point + Vector2(173.0, -89.0), index + 29)
	var offset := terrain_half_width * HIGHLIGHT_OFFSET_RATIO
	var wobble := (lateral_seed * 2.0 - 1.0) * maxf(1.0, outline_jitter * 0.8)
	return point + normal * (offset + wobble)

func _resample_stroke(stroke: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var resampled := PackedVector2Array([stroke[0]])
	var target_spacing := maxf(1.0, spacing)
	for i in range(stroke.size() - 1):
		var start := stroke[i]
		var end := stroke[i + 1]
		var distance := start.distance_to(end)
		var steps := maxi(1, ceili(distance / target_spacing))
		for step in range(1, steps + 1):
			resampled.append(start.lerp(end, float(step) / float(steps)))
	return resampled

func _stable_random(point: Vector2, index: int) -> float:
	var value := sin(point.x * 12.9898 + point.y * 78.233 + float(index) * 37.719) * 43758.5453
	return value - floor(value)

func make_ground_visual_polygon(stroke: PackedVector2Array) -> PackedVector2Array:
	var top := _simplify(stroke, simplify_tolerance)
	if top.size() < 2:
		return PackedVector2Array()
	var polygon := _round_ground_polygon(_ground_polygon_from_top(top, ground_depth), top.size(), ground_depth)
	var jittered := make_outline_points(_close_polygon(polygon))
	if jittered.size() > 1 and jittered[0].is_equal_approx(jittered[-1]):
		jittered.resize(jittered.size() - 1)
	return jittered

func make_ground_grass_polygon(stroke: PackedVector2Array) -> PackedVector2Array:
	var top := make_outline_points(stroke)
	var grass_depth := minf(ground_grass_height, ground_depth)
	var grass_polygon := _ground_polygon_from_top(top, grass_depth)
	var ground_polygon := make_ground_visual_polygon(stroke)
	var intersections := Geometry2D.intersect_polygons(grass_polygon, ground_polygon)
	var largest := PackedVector2Array()
	var largest_area := 0.0
	for intersection in intersections:
		var area := absf(_polygon_signed_area(intersection))
		if area > largest_area:
			largest = intersection
			largest_area = area
	return largest if not largest.is_empty() else grass_polygon

func make_ground_speckles(stroke: PackedVector2Array) -> Dictionary:
	var points := PackedVector2Array()
	var radii := PackedFloat32Array()
	if stroke.size() < 2 or not ground_show_highlight:
		return {"points": points, "radii": radii}
	var ground_polygon := make_ground_visual_polygon(stroke)
	var grass_polygon := make_ground_grass_polygon(stroke)
	if ground_polygon.size() < 3:
		return {"points": points, "radii": radii}
	var bounds := _polygon_bounds(ground_polygon)
	var start_x := floorf(bounds.position.x / GROUND_SPECKLE_SPACING) * GROUND_SPECKLE_SPACING
	var start_y := floorf(bounds.position.y / GROUND_SPECKLE_SPACING) * GROUND_SPECKLE_SPACING
	var end_x := bounds.end.x
	var end_y := bounds.end.y
	var row := 0
	var y := start_y
	while y <= end_y and points.size() < GROUND_MAX_SPECKLES:
		var column := 0
		var x := start_x
		while x <= end_x and points.size() < GROUND_MAX_SPECKLES:
			var seed_index := row * 4099 + column
			var anchor := Vector2(x, y)
			var jitter_x := (_stable_random(anchor + Vector2(19.0, 71.0), seed_index) * 2.0 - 1.0) * 19.0
			var jitter_y := (_stable_random(anchor + Vector2(-43.0, 13.0), seed_index + 7) * 2.0 - 1.0) * 19.0
			var candidate := anchor + Vector2(jitter_x, jitter_y)
			if Geometry2D.is_point_in_polygon(candidate, ground_polygon) and not Geometry2D.is_point_in_polygon(candidate, grass_polygon):
				points.append(candidate)
				radii.append(lerpf(2.0, 5.0, _stable_random(candidate, seed_index + 23)))
			x += GROUND_SPECKLE_SPACING
			column += 1
		y += GROUND_SPECKLE_SPACING
		row += 1
	return {"points": points, "radii": radii}

func _ground_to_polygon(stroke: PackedVector2Array) -> PackedVector2Array:
	var top := _simplify(stroke, simplify_tolerance)
	return _round_ground_polygon(_ground_polygon_from_top(top, ground_depth), top.size(), ground_depth)

func _ground_polygon_from_top(top: PackedVector2Array, depth: float) -> PackedVector2Array:
	if top.size() < 2:
		return PackedVector2Array()
	var polygon := PackedVector2Array()
	polygon.append_array(top)
	for index in range(top.size() - 1, -1, -1):
		polygon.append(top[index] + Vector2.DOWN * depth)
	return polygon

func _round_ground_polygon(polygon: PackedVector2Array, top_count: int, depth: float) -> PackedVector2Array:
	var amount := clampf(edge_roundness / 100.0, 0.0, 1.0)
	if amount <= 0.0 or polygon.size() < 4 or top_count < 2:
		return polygon
	var radius := minf(depth * 0.25, 256.0) * amount
	var corner_indices := [0, top_count - 1, top_count, polygon.size() - 1]
	var rounded := PackedVector2Array()
	for index in range(polygon.size()):
		if not index in corner_indices:
			rounded.append(polygon[index])
			continue
		var previous := polygon[(index - 1 + polygon.size()) % polygon.size()]
		var corner := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		var incoming_length := corner.distance_to(previous)
		var outgoing_length := corner.distance_to(next)
		var cut := minf(radius, minf(incoming_length, outgoing_length) * 0.45)
		if cut <= 0.01:
			rounded.append(corner)
			continue
		var start := corner.move_toward(previous, cut)
		var end := corner.move_toward(next, cut)
		for step in range(13):
			var weight := float(step) / 12.0
			var inverse := 1.0 - weight
			rounded.append(start * inverse * inverse + corner * 2.0 * inverse * weight + end * weight * weight)
	return rounded

func _polygon_signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(polygon.size()):
		var next_index := (index + 1) % polygon.size()
		area += polygon[index].x * polygon[next_index].y - polygon[next_index].x * polygon[index].y
	return area * 0.5

func _close_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var closed := polygon.duplicate()
	if not closed.is_empty():
		closed.append(closed[0])
	return closed

func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for index in range(1, polygon.size()):
		bounds = bounds.expand(polygon[index])
	return bounds

func _stroke_to_polygon(stroke: PackedVector2Array) -> PackedVector2Array:
	var points := _simplify(stroke, simplify_tolerance)
	if points.size() < 2:
		return PackedVector2Array()

	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(points.size()):
		var tangent := Vector2.ZERO
		if i > 0:
			tangent += points[i] - points[i - 1]
		if i < points.size() - 1:
			tangent += points[i + 1] - points[i]
		if tangent.length_squared() <= 0.001:
			tangent = Vector2.RIGHT
		var normal := tangent.normalized().orthogonal() * terrain_half_width
		left.append(points[i] + normal)
		right.append(points[i] - normal)

	var polygon := PackedVector2Array()
	polygon.append_array(left)
	_append_end_cap(polygon, points[-1], points[-1] - points[-2])
	for i in range(right.size() - 2, -1, -1):
		polygon.append(right[i])
	_append_start_cap(polygon, points[0], points[1] - points[0])
	return polygon

func _append_end_cap(polygon: PackedVector2Array, center: Vector2, tangent: Vector2) -> void:
	if tangent.length_squared() <= 0.001:
		return
	var forward := tangent.normalized()
	var normal := forward.orthogonal()
	var cap_amount := edge_roundness / 100.0
	for i in range(1, END_CAP_SEGMENTS + 1):
		var angle := PI * float(i) / float(END_CAP_SEGMENTS)
		polygon.append(center + normal * cos(angle) * terrain_half_width + forward * sin(angle) * terrain_half_width * cap_amount)

func _append_start_cap(polygon: PackedVector2Array, center: Vector2, tangent: Vector2) -> void:
	if tangent.length_squared() <= 0.001:
		return
	var forward := tangent.normalized()
	var normal := forward.orthogonal()
	var cap_amount := edge_roundness / 100.0
	for i in range(1, END_CAP_SEGMENTS + 1):
		var angle := PI * float(i) / float(END_CAP_SEGMENTS)
		polygon.append(center - normal * cos(angle) * terrain_half_width - forward * sin(angle) * terrain_half_width * cap_amount)

func _simplify(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() <= 2 or tolerance <= 0.0:
		return points.duplicate()
	var kept := PackedVector2Array([points[0]])
	_simplify_range(points, 0, points.size() - 1, tolerance, kept)
	kept.append(points[-1])
	return kept

func _simplify_range(points: PackedVector2Array, first: int, last: int, tolerance: float, kept: PackedVector2Array) -> void:
	var max_distance := 0.0
	var index := -1
	var start := points[first]
	var end := points[last]
	for i in range(first + 1, last):
		var distance := _point_line_distance(points[i], start, end)
		if distance > max_distance:
			max_distance = distance
			index = i
	if max_distance > tolerance and index > -1:
		_simplify_range(points, first, index, tolerance, kept)
		kept.append(points[index])
		_simplify_range(points, index, last, tolerance, kept)

func _point_line_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	if segment.length_squared() <= 0.001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)

func _scene_owner() -> Node:
	var current: Node = self
	var owner_candidate := owner
	while current.get_parent() != null:
		current = current.get_parent()
	if owner_candidate != null:
		return owner_candidate
	return current

func _next_terrain_name(generated: Node) -> String:
	var next_index := 1
	for child in generated.get_children():
		var child_name := String(child.name)
		if not child_name.begins_with("TerrainStroke"):
			continue
		var suffix := child_name.substr("TerrainStroke".length())
		if suffix.is_valid_int():
			next_index = maxi(next_index, suffix.to_int() + 1)
	return "TerrainStroke%d" % next_index

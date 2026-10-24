class_name LevelTerrainVisual
extends Node2D
## All outlines precede all fills, so separate editable segments read as one surface.
## Playtest uses exposed union contours, exactly matching its collision boundaries.

const SketchScript := preload("res://scripts/editor/level_sketch.gd")
var document: LevelDocument
var polygons: Array[PackedVector2Array] = []
var contours: Array[PackedVector2Array] = []
var shading: Array[PackedVector2Array] = []
var highlights: Array[PackedVector2Array] = []
var style: LevelSketch

func _init() -> void:
	style = SketchScript.new()
	style.terrain_half_width = LevelDocument.HALF_WIDTH
	style.outline_jitter = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(style):
		style.free()

func set_document(value: LevelDocument, generated_polygons: Array[PackedVector2Array] = [], generated_contours: Array[PackedVector2Array] = []) -> void:
	document = value
	polygons = generated_polygons if not generated_polygons.is_empty() else LevelGeometry.polygons_for(value)
	contours = generated_contours
	shading.clear()
	highlights.clear()
	for segment in document.segments:
		var points := LevelDocument.sample_segment(segment)
		shading.append(style.make_shading_points(points))
		highlights.append_array(style.make_highlight_segments(points))
	queue_redraw()

func _draw() -> void:
	if document == null:
		return
	if contours.is_empty():
		for polygon in polygons:
			var closed := polygon.duplicate()
			closed.append(polygon[0])
			draw_polyline(closed, style.outline_color, 12.0, true)
	for polygon in polygons:
		draw_colored_polygon(polygon, style.fill_color)
	for points in shading:
		draw_polyline(points, style.shading_color, LevelDocument.CELL_SIZE * 0.42, true)
	for points in highlights:
		draw_polyline(points, style.highlight_color, LevelDocument.CELL_SIZE * 0.14, true)
	for contour in contours:
		var closed := contour.duplicate()
		closed.append(contour[0])
		draw_polyline(closed, style.outline_color, 12.0, true)

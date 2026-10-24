@tool
class_name LevelSketchVisual
extends Node2D

@export var draw_items: Array[Dictionary] = []:
	set(value):
		draw_items = value
		queue_redraw()

func _draw() -> void:
	for item in draw_items:
		var kind := String(item.get("kind", "polyline"))
		if kind == "polygon":
			_draw_polygon_item(item)
			continue
		if kind == "speckles":
			_draw_speckles_item(item)
			continue
		var points: PackedVector2Array = item.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		var color: Color = item.get("color", Color.WHITE)
		var width := float(item.get("width", 1.0))
		var cap_roundness := float(item.get("cap_roundness", 1.0))
		_draw_rounded_polyline(points, color, width, cap_roundness)

func _draw_rounded_polyline(points: PackedVector2Array, color: Color, width: float, cap_roundness: float = 1.0) -> void:
	if points.size() < 2 or width <= 0.0:
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

func _draw_polygon_item(item: Dictionary) -> void:
	var points: PackedVector2Array = item.get("points", PackedVector2Array())
	if points.size() < 3:
		return
	var color: Color = item.get("color", Color.WHITE)
	draw_colored_polygon(points, color)

func _draw_speckles_item(item: Dictionary) -> void:
	var points: PackedVector2Array = item.get("points", PackedVector2Array())
	var radii: PackedFloat32Array = item.get("radii", PackedFloat32Array())
	var color: Color = item.get("color", Color.WHITE)
	for index in range(points.size()):
		var radius := radii[index] if index < radii.size() else 2.0
		draw_circle(points[index], radius, color)

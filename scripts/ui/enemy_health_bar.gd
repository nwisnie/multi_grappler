class_name EnemyHealthBar
extends Node2D

const HIT_SHAKE_DURATION := 0.26
const FOLLOW_RESPONSE := 16.0
const TILT_RESPONSE := 10.0
const MAX_FOLLOW_LAG := 12.0

var bar_size := Vector2(100.0, 20.0)
var fill_color := Color(0.68, 0.27, 0.29, 0.97)
var outline_width := 2.0
var pointed_right_edge := false
var idle_float_amount := 1.2
var shake_on_decrease := true
var health_ratio := 1.0
var shape_seed := 0.0
var shake_time := 0.0
var shake_offset := Vector2.ZERO
var vibration_strength := 0.0
var vibration_time := 0.0
var vibration_offset := Vector2.ZERO
var target_position := Vector2.ZERO
var follow_position := Vector2.ZERO
var target_tilt := 0.0
var current_tilt := 0.0
var idle_time := 0.0
var has_anchor := false

func _ready() -> void:
	z_as_relative = false
	z_index = 4096
	shape_seed = randf_range(0.0, TAU)
	idle_time = shape_seed
	queue_redraw()

func configure(size: Vector2) -> void:
	bar_size = size
	queue_redraw()

func set_fill_color(color: Color) -> void:
	if fill_color == color:
		return
	fill_color = color
	queue_redraw()

func set_vibration_strength(strength: float) -> void:
	vibration_strength = maxf(strength, 0.0)

func set_anchor(world_position: Vector2) -> void:
	if not has_anchor or target_position.distance_squared_to(world_position) > 10000.0:
		follow_position = world_position
		global_position = world_position
		has_anchor = true
		target_tilt = 0.0
	else:
		target_tilt = clampf((target_position.x - world_position.x) * 0.003, -0.035, 0.035)
	target_position = world_position

func set_health_ratio(value: float) -> void:
	var next_ratio := clampf(value, 0.0, 1.0)
	if shake_on_decrease and next_ratio < health_ratio:
		shake_time = HIT_SHAKE_DURATION
	health_ratio = next_ratio
	queue_redraw()

func _process(delta: float) -> void:
	if has_anchor:
		var lag := follow_position - target_position
		if lag.length() > MAX_FOLLOW_LAG:
			follow_position = target_position + lag.normalized() * MAX_FOLLOW_LAG
		follow_position = follow_position.lerp(target_position, 1.0 - exp(-FOLLOW_RESPONSE * delta))
		current_tilt = lerpf(current_tilt, target_tilt, 1.0 - exp(-TILT_RESPONSE * delta))
		idle_time += delta
		var center := bar_size * 0.5
		global_rotation = current_tilt
		global_position = follow_position + Vector2(0.0, sin(idle_time * 2.4) * idle_float_amount) + center - center.rotated(current_tilt)
	if shake_time > 0.0:
		shake_time = maxf(shake_time - delta, 0.0)
		var strength := shake_time / HIT_SHAKE_DURATION
		shake_offset = Vector2(randf_range(-4.5, 4.5), randf_range(-2.7, 2.7)) * strength
		if shake_time <= 0.0:
			shake_offset = Vector2.ZERO
		queue_redraw()
	if vibration_strength > 0.0:
		vibration_time += delta
		vibration_offset = Vector2(sin(vibration_time * 85.0), cos(vibration_time * 71.0)) * vibration_strength
		queue_redraw()
	elif vibration_offset != Vector2.ZERO:
		vibration_offset = Vector2.ZERO
		queue_redraw()

func _draw() -> void:
	draw_set_transform(shake_offset + vibration_offset, 0.0, Vector2.ONE)
	var outside := _bar_polygon(0.0, bar_size.x, 0.0)
	draw_colored_polygon(outside, Color.BLACK)
	draw_polyline(_closed(outside), Color.BLACK, outline_width, true)
	var background_inset := maxf(2.5, outline_width)
	draw_colored_polygon(_bar_polygon(background_inset, bar_size.x - background_inset, background_inset), Color(0.22, 0.11, 0.13, 0.94))
	if health_ratio > 0.0:
		var fill_inset := maxf(3.5, outline_width + 1.0)
		var fill_end := lerpf(fill_inset, bar_size.x - fill_inset, health_ratio)
		if fill_end > fill_inset + 1.5:
			draw_colored_polygon(_bar_polygon(fill_inset, fill_end, fill_inset), fill_color)

func _bar_polygon(left: float, right: float, inset: float) -> PackedVector2Array:
	if pointed_right_edge:
		return _pointed_bar_polygon(left, right, inset)
	var points := PackedVector2Array()
	var top_left := Vector2(left - 6.0, -6.0 + inset)
	var top_right := Vector2(right, bar_size.y * 0.2 + inset)
	var bottom_right := Vector2(right - minf(4.0, (right - left) * 0.18), bar_size.y * 0.8 - 2.0 - inset)
	var bottom_left := Vector2(left, bar_size.y - inset)
	var narrow_height := bottom_right.y - top_right.y
	var radius := minf(minf(3.0, (right - left) * 0.28), narrow_height * 0.4)
	var count := maxi(2, ceili((right - left) / 7.0))
	for index in range(count + 1):
		var t := float(index) / float(count)
		var x := lerpf(top_left.x + radius, top_right.x - radius, t)
		points.append(Vector2(x, lerpf(top_left.y, top_right.y, t) + _jitter(x, 0.0)))
	points.append(top_right + Vector2(-radius * 0.3, radius * 0.25))
	points.append(top_right + Vector2(0.0, radius))
	points.append(bottom_right + Vector2(0.0, -radius))
	points.append(bottom_right + Vector2(-radius * 0.3, -radius * 0.25))
	for index in range(count + 1):
		var t := float(index) / float(count)
		var x := lerpf(bottom_right.x - radius, bottom_left.x + radius, t)
		points.append(Vector2(x, lerpf(bottom_right.y, bottom_left.y, t) + _jitter(x, 1.7)))
	points.append(bottom_left + Vector2(radius * 0.3, -radius * 0.25))
	points.append(bottom_left + Vector2(0.0, -radius))
	points.append(top_left + Vector2(0.0, radius))
	points.append(top_left + Vector2(radius * 0.3, radius * 0.25))
	return points

func _pointed_bar_polygon(left: float, right: float, inset: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var top_left := Vector2(left - 6.0, -6.0 + inset)
	var top_right := Vector2(right - 2.0, bar_size.y * 0.08 + inset)
	var middle_right := Vector2(right + maxf(8.0 - inset, 0.0), bar_size.y * 0.4)
	var bottom_right := Vector2(right - 10.0, bar_size.y * 0.9 - inset)
	var bottom_left := Vector2(left, bar_size.y - inset)
	var count := maxi(2, ceili((right - left) / 7.0))
	for index in range(count):
		var t := float(index) / float(count)
		var x := lerpf(top_left.x + 3.0, top_right.x, t)
		points.append(Vector2(x, lerpf(top_left.y, top_right.y, t) + _jitter(x, 0.0)))
	points.append_array(PackedVector2Array([top_right, middle_right, bottom_right]))
	for index in range(1, count + 1):
		var t := float(index) / float(count)
		var x := lerpf(bottom_right.x, bottom_left.x + 3.0, t)
		points.append(Vector2(x, lerpf(bottom_right.y, bottom_left.y, t) + _jitter(x, 1.7)))
	points.append(bottom_left + Vector2(0.0, -3.0))
	points.append(top_left + Vector2(0.0, 3.0))
	return points

func _jitter(x: float, phase: float) -> float:
	return sin(x * 0.37 + shape_seed + phase) * 0.5 + sin(x * 0.91 + shape_seed * 1.3 + phase) * 0.25

func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed

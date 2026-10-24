extends Node2D

const INK := Color("18272e")
const METAL := Color("b5e9df")
const CONTACT_COLOR := Color("79f5e5")

var contact_normal := Vector2.UP
var landed := false
var terrain_contact := false
var contact_time := 0.0
var spear_visible := false

func reset() -> void:
	landed = false
	contact_time = 0.0
	visible = false
	spear_visible = false

func update_visual(tip: Vector2, direction: Vector2, normal: Vector2, arrived: bool, on_terrain: bool, delta: float) -> void:
	global_position = tip
	global_rotation = direction.angle()
	contact_normal = normal.rotated(-global_rotation)
	terrain_contact = on_terrain
	contact_time = contact_time + delta if landed and arrived else 0.0
	landed = arrived
	spear_visible = not arrived
	visible = true
	queue_redraw()

func _draw() -> void:
	if landed and terrain_contact:
		_draw_contact()
	if not spear_visible:
		return
	# A pointed metal head with a short shaft and a shaded central ridge.
	_round_stroke(PackedVector2Array([Vector2(-30, 0), Vector2(-18, 0)]), INK, 7.0)
	_round_stroke(PackedVector2Array([Vector2(-30, 0), Vector2(-18, 0)]), METAL, 3.0)
	var head := PackedVector2Array([Vector2.ZERO, Vector2(-15, -9), Vector2(-23, 0), Vector2(-15, 9)])
	draw_colored_polygon(head, METAL)
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(-23, 0), Vector2(-15, 9)]), Color("6caaa4"))
	head.append(head[0])
	_round_stroke(head, INK, 3.5)

func _draw_contact() -> void:
	var normal := contact_normal.normalized()
	var tangent := normal.orthogonal()
	# The small puncture and surface dash remain at the exact world anchor.
	var dash := PackedVector2Array([-tangent * 10.0, tangent * 10.0])
	_round_stroke(dash, INK, 6.0)
	_round_stroke(dash, CONTACT_COLOR, 2.5)
	draw_circle(Vector2.ZERO, 5.0, INK)
	draw_circle(normal * 1.5, 2.5, CONTACT_COLOR)
	var impact := 1.0 - clampf(contact_time / 0.22, 0.0, 1.0)
	if impact > 0.0:
		var ring_radius := lerpf(22.0, 7.0, impact)
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 40, Color(CONTACT_COLOR, impact * 0.7), 2.5, true)
		for side in [-1.0, 1.0]:
			var ray: Vector2 = (normal + tangent * float(side)).normalized()
			_round_stroke(PackedVector2Array([ray * 13.0, ray * (13.0 + impact * 8.0)]), Color(CONTACT_COLOR, impact), 2.5)

func _round_stroke(points: PackedVector2Array, color: Color, width: float) -> void:
	draw_polyline(points, color, width, true)
	draw_circle(points[0], width * 0.5, color)
	draw_circle(points[-1], width * 0.5, color)

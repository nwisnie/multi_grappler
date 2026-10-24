@tool
extends Area2D

const OUTLINE_POINTS := 96
const INK := Color("18272e")

@export_range(8.0, 80.0, 1.0) var radius := 36.0:
	set(value):
		radius = value
		_update_shape()
@export_range(0.0, 0.18, 0.01) var irregularity := 0.08:
	set(value):
		irregularity = value
		_update_shape()
@export var shape_seed := 1.0:
	set(value):
		shape_seed = value
		_update_shape()
@export var base_color := Color("6ecfc6"):
	set(value):
		base_color = value
		queue_redraw()
@export_range(16.0, 400.0, 1.0) var detection_radius := 108.0:
	set(value):
		detection_radius = value
		_update_shape()
@export_range(2.0, 16.0, 0.5) var outline_width := 8.0:
	set(value):
		outline_width = value
		queue_redraw()

var targeting_players: Dictionary = {}
var ripple_time := 0.0

func _ready() -> void:
	_update_shape()
	set_process(not Engine.is_editor_hint())

func set_grapple_targeted(player: Node, targeted: bool) -> void:
	if targeted:
		targeting_players[player.get_instance_id()] = weakref(player)
	else:
		targeting_players.erase(player.get_instance_id())

func _process(delta: float) -> void:
	ripple_time = fposmod(ripple_time + delta, TAU)
	for player_id in targeting_players.keys():
		if targeting_players[player_id].get_ref() == null:
			targeting_players.erase(player_id)
	queue_redraw()

func get_grapple_anchor_position() -> Vector2:
	return global_position

func get_grapple_ring_radius() -> float:
	return radius + outline_width * 0.5 + 16.0

func _outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(OUTLINE_POINTS):
		var angle := TAU * float(index) / float(OUTLINE_POINTS)
		# Two traveling waves ripple around the rim. Keep the stroke overlapping
		# the circular fill even at the deepest trough, so there are no gaps.
		var wave := sin(angle * 4.0 - ripple_time * 2.0 + shape_seed) * 0.7 + sin(angle * 7.0 + ripple_time + shape_seed * 1.7) * 0.3
		var amplitude := minf(radius * irregularity, outline_width * 0.4)
		points.append(Vector2.RIGHT.rotated(angle) * (radius + amplitude * wave))
	return points

func _update_shape() -> void:
	if is_node_ready():
		# A stable detection circle keeps the anchor steady as the rim ripples.
		($GrappleShape.shape as CircleShape2D).radius = maxf(radius, detection_radius)
	queue_redraw()

func _draw() -> void:
	var points := _outline()
	draw_circle(Vector2.ZERO, radius, base_color)
	points.append(points[0])
	draw_polyline(points, INK, outline_width, true)
	draw_arc(Vector2(-radius * 0.1, -radius * 0.08), radius * 0.62, PI * 1.08, PI * 1.55, 24, Color(1.0, 1.0, 1.0, 0.55), 2.5, true)

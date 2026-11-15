extends Node2D
## A compact screen-space arrow follows the actual grapple destination.

const Arrow := preload("res://scripts/ui/hand_drawn_arrow.gd")
const COLOR := Color("248d91")
const ARROW_SCALE := 0.62
const MIN_OFFSET := 46.0
const UNAVAILABLE_COLOR := Color("e26b72")

var ripple_time := 0.0
var can_grapple := false

func _ready() -> void:
	hide()

func _process(delta: float) -> void:
	if not visible:
		return
	ripple_time = fposmod(ripple_time + delta, TAU)
	queue_redraw()

func set_aim(screen_origin: Vector2, screen_target: Vector2, available: bool, player_radius: float, has_target: bool) -> void:
	can_grapple = has_target
	var direction := screen_origin.direction_to(screen_target)
	visible = available and not direction.is_zero_approx() and get_viewport_rect().has_point(screen_origin)
	if not visible:
		return
	position = screen_origin + direction * maxf(MIN_OFFSET, player_radius + 12.0)
	rotation = direction.angle()
	queue_redraw()

func _draw() -> void:
	Arrow.draw_arrow(self, Vector2.ZERO, Vector2.RIGHT, COLOR, ARROW_SCALE, ripple_time, 2.4)
	if not can_grapple:
		var badge_position := Vector2(Arrow.ARROW_LENGTH * ARROW_SCALE + 8.0, -9.0)
		# Keep the X upright as the arrow rotates around the player.
		draw_set_transform(badge_position, -rotation)
		draw_circle(Vector2.ZERO, 6.5, Arrow.OUTLINE_COLOR)
		draw_circle(Vector2.ZERO, 5.2, UNAVAILABLE_COLOR)
		draw_line(Vector2(-2.2, -2.2), Vector2(2.2, 2.2), Arrow.OUTLINE_COLOR, 1.5, true)
		draw_line(Vector2(-2.2, 2.2), Vector2(2.2, -2.2), Arrow.OUTLINE_COLOR, 1.5, true)
		draw_set_transform(Vector2.ZERO)

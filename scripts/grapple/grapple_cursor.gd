extends Node2D

const CYAN := Color("79f5e5")
const GOLD := Color("ffe6a0")
const INK := Color(0.025, 0.06, 0.09, 0.95)
const SIZE_RESPONSE := 10.0
const ATTACHED_SCALE := 0.62
const ARC_SEGMENTS := 24

var animation_time := 0.0
var attached := false
var target_position := Vector2.ZERO
var has_target := false
var spin_angle := 0.0
var spin_speed := 1.1
var marker_scale := 1.0
var marker_color := CYAN
var shape_seed := 0.0
var ring_radius := 21.0
var attached_scale := ATTACHED_SCALE
var show_glow := true

func _ready() -> void:
	visible = false
	# Keep the hand-drawn irregularities stable rather than jittering each frame.
	shape_seed = randf_range(0.0, TAU)

func set_target(screen_position: Vector2, available: bool, is_attached: bool) -> void:
	target_position = screen_position
	# The player smooths its mouse aim before raycasting. Always draw at the
	# resulting surface hit (or fixed grapple anchor), never between hits.
	position = screen_position
	attached = is_attached
	var target_visible := available and get_viewport_rect().has_point(screen_position)
	has_target = target_visible
	visible = target_visible

func _process(delta: float) -> void:
	if not has_target:
		return
	visible = get_viewport_rect().has_point(position) and get_viewport_rect().has_point(target_position)
	animation_time += delta
	var transition := 1.0 - exp(-SIZE_RESPONSE * delta)
	marker_scale = lerpf(marker_scale, attached_scale if attached else 1.0, transition)
	marker_color = marker_color.lerp(GOLD if attached else CYAN, transition)
	spin_speed = lerpf(spin_speed, 1.8 if attached else 1.1, transition)
	# Integrate rotation so changing grapple state never jumps to a new angle.
	spin_angle = fposmod(spin_angle + spin_speed * delta, TAU)
	queue_redraw()

func _draw() -> void:
	var pulse := sin(animation_time * 4.0) * 0.8
	var radius := (ring_radius + pulse) * marker_scale
	if show_glow:
		draw_circle(Vector2.ZERO, radius + 5.0 * marker_scale, Color(marker_color, 0.06))
	for index in range(3):
		var seed := shape_seed + float(index) * 2.37
		var start := spin_angle + TAU * float(index) / 3.0
		var arc_length := 1.18 + sin(seed) * 0.1
		var points := PackedVector2Array()
		for segment in range(ARC_SEGMENTS + 1):
			var t := float(segment) / float(ARC_SEGMENTS)
			var wobble := sin(t * TAU * 1.3 + seed) * 0.85 + sin(t * TAU * 2.1 + seed * 1.7) * 0.3
			points.append(Vector2.RIGHT.rotated(start + arc_length * t) * (radius + wobble * marker_scale))
		var ink_width := (7.5 + sin(seed) * 0.6) * marker_scale
		var color_width := 3.5 * marker_scale
		_draw_round_stroke(points, INK, ink_width)
		_draw_round_stroke(points, marker_color, color_width)

func _draw_round_stroke(points: PackedVector2Array, color: Color, width: float) -> void:
	draw_polyline(points, color, width, true)
	# Round caps join the outline, rather than floating outside as decorations.
	draw_circle(points[0], width * 0.5, color)
	draw_circle(points[-1], width * 0.5, color)

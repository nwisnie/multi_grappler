extends RefCounted
## A filled arrow whose continuous ink edge ripples with its silhouette.

const RippleOutline := preload("res://scripts/grapple/ripple_outline.gd")
const OUTLINE_COLOR := Color("18272e")
const ARROW_LENGTH := 47.0
const RIPPLE_AMPLITUDE := 1.0
const RIPPLE_SPACING := 2.0
const RIPPLE_SPEED := 0.5

const POINTS := [
	Vector2(0, -5), Vector2(28, -5), Vector2(28, -12),
	Vector2(47, 0), Vector2(28, 12), Vector2(28, 5), Vector2(0, 5),
]

static func _ripple_border(points: PackedVector2Array, arrow_scale: float, time: float, seed: float) -> PackedVector2Array:
	var border := PackedVector2Array()
	for index in range(points.size()):
		var start := points[index]
		var end := points[(index + 1) % points.size()]
		var edge := end - start
		var length := edge.length()
		var previous := start - points[(index - 1 + points.size()) % points.size()]
		var next := points[(index + 2) % points.size()] - end
		var start_normal := (previous.normalized() + edge.normalized()).orthogonal().normalized()
		var end_normal := (edge.normalized() + next.normalized()).orthogonal().normalized()
		var steps := maxi(1, ceili(length / RIPPLE_SPACING))
		for step in range(steps):
			var fraction := float(step) / float(steps)
			var normal := start_normal.lerp(end_normal, fraction).normalized()
			var point := start.lerp(end, fraction)
			# Sample along the local shaft instead of walking the perimeter.
			# Both wave components travel toward +X, from the tail to the tip.
			var phase := TAU * point.x / (ARROW_LENGTH * arrow_scale * 4.0) - time * RIPPLE_SPEED
			var offset := RippleOutline.wave(phase, seed, 0.0) * RIPPLE_AMPLITUDE
			border.append(point + normal * offset)
	return border

static func draw_arrow(canvas: CanvasItem, origin: Vector2, direction: Vector2, color: Color, arrow_scale: float = 1.0, time: float = 0.0, seed: float = 1.0) -> void:
	if direction.is_zero_approx():
		return
	var points := PackedVector2Array(POINTS)
	for index in range(points.size()):
		points[index] *= arrow_scale
	var transform := Transform2D(direction.angle(), origin)
	var border := transform * _ripple_border(points, arrow_scale, time, seed)
	# The fill and outline share one animated boundary, like the grapple orbs.
	canvas.draw_colored_polygon(border, color)
	border.append(border[0])
	canvas.draw_polyline(border, OUTLINE_COLOR, maxf(0.9, 1.4 * arrow_scale), true)

extends Node2D
## A hollow, non-solid race hoop. RaceProgress checks passage through its opening.

const FONT := preload("res://assets/fonts/KosugiMaru-Regular.ttf")
const INK := Color("18272e")
const RippleOutline := preload("res://scripts/grapple/ripple_outline.gd")

var number := 1
var is_start := false
var is_finish := false
var active := false
var passed := false
var ripple_time := 0.0

static func draw_hoop(canvas: Node2D, center: Vector2, radius: float, caption: String, color: Color, width: float, font_size: int, time: float = 0.0, seed: float = 1.0, ripple_amount: float = 0.0) -> void:
	var outline := RippleOutline.points(radius, width, ripple_amount, seed, time)
	for index in range(outline.size()):
		outline[index] += center
	outline.append(outline[0])
	canvas.draw_polyline(outline, INK, width + 6.0, true)
	canvas.draw_polyline(outline, color, width, true)
	var text_size := FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_position := center + Vector2(-text_size.x * 0.5, -radius - float(font_size) * 0.5)
	canvas.draw_string_outline(FONT, text_position, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(3, font_size / 5), INK)
	canvas.draw_string(FONT, text_position, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _process(delta: float) -> void:
	ripple_time = fposmod(ripple_time + delta, TAU)
	queue_redraw()

func _draw() -> void:
	var color := Color("ffc947") if active else Color("46c7bb")
	if passed:
		color = Color("55c982")
	if is_finish and not active and not passed:
		color = Color("ec839a")
	var caption := str(number)
	if is_start:
		caption += " START / FINISH" if is_finish else " START"
	elif is_finish:
		caption += " FINISH"
	draw_hoop(self, Vector2.ZERO, LevelDocument.CHECKPOINT_RADIUS, caption, color, 20.0, 34, ripple_time, float(number), 0.08)

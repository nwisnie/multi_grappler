extends Control
## A screen-space arrow beside the player points toward the required hoop.

const FONT := preload("res://assets/fonts/KosugiMaru-Regular.ttf")

var race: Node2D
var status: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status = Label.new()
	status.name = "RaceStatus"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_theme_font_size_override("font_size", 24)
	status.add_theme_color_override("font_color", Color.WHITE)
	status.add_theme_color_override("font_outline_color", Color("18272e"))
	status.add_theme_constant_override("outline_size", 6)
	add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	status.offset_left = -350.0
	status.offset_right = -24.0
	status.offset_top = 20.0
	status.offset_bottom = 130.0

func _process(_delta: float) -> void:
	if not is_instance_valid(race) or not is_instance_valid(race.player):
		hide()
		return
	var time := "%02d:%05.2f" % [int(race.elapsed / 60.0), fmod(race.elapsed, 60.0)]
	if race.finished:
		status.text = "Race finished!\n" + time
	else:
		var destination := "Finish · #%d" % race.next_number if race.next_number == race.document.finish_checkpoint else "Next hoop · #%d" % race.next_number
		status.text = "Lap %d / %d\n%s\n%s" % [race.lap, race.document.race_laps, destination, time]
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(race) or not is_instance_valid(race.player) or race.finished:
		return
	var canvas: Transform2D = race.player.get_canvas_transform()
	var origin: Vector2 = canvas * race.player.global_position
	var target: Vector2 = canvas * race.next_position()
	var direction := origin.direction_to(target)
	if direction.is_zero_approx():
		direction = Vector2.UP
	var tip := origin + direction * 122.0
	var back := origin + direction * 98.0
	var side := direction.orthogonal() * 11.0
	var points := PackedVector2Array([tip, back + side, back - side])
	draw_line(origin + direction * 78.0, back, Color("18272e"), 10.0, true)
	draw_line(origin + direction * 78.0, back, Color("ffd36f"), 5.0, true)
	draw_colored_polygon(points, Color("ffd36f"))
	points.append(points[0])
	draw_polyline(points, Color("18272e"), 3.0, true)
	var text_position := origin + direction * 148.0 + Vector2(-12, 8)
	draw_string_outline(FONT, text_position, str(race.next_number), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 5, Color("18272e"))
	draw_string(FONT, text_position, str(race.next_number), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

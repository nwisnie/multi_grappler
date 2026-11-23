extends Control
## A screen-space arrow beside the player points toward the required hoop.

const FONT := preload("res://assets/fonts/KosugiMaru-Regular.ttf")
const Arrow := preload("res://scripts/ui/hand_drawn_arrow.gd")
const ARROW_COLOR := Color("d89b26")
const LevelTimes := preload("res://scripts/levels/level_times.gd")

var race: Node2D
var status: Label
var ripple_time := 0.0

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
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _process(delta: float) -> void:
	if not is_instance_valid(race) or not is_instance_valid(race.player):
		hide()
		return
	ripple_time = fposmod(ripple_time + delta, TAU)
	var time := LevelTimes.format_time(roundi(race.elapsed * 1000.0))
	if race.finished:
		status.text = "Race finished!\n" + time
	else:
		var destination := "Finish #%d" % race.next_number if race.next_number == race.document.finish_checkpoint else "Next hoop #%d" % race.next_number
		status.text = "Lap %d / %d\n%s\n%s" % [race.lap, race.document.race_laps, destination, time]
	if is_instance_valid(race.time_records) and not race.leaderboard_id.is_empty():
		var summary: Dictionary = race.time_records.summary(race.leaderboard_id)
		status.text += "\nTop: %s\nYour best: %s" % [LevelTimes.format_time(summary.get("top_time_ms")), LevelTimes.format_time(summary.get("personal_time_ms"))]
		if not race.time_status.is_empty():
			status.text += "\n" + race.time_status
		elif race.time_records.current_user_id().is_empty():
			status.text += "\nSign in to save your time."
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
	Arrow.draw_arrow(self, origin + direction * 96.0, direction, ARROW_COLOR, 1.0, ripple_time, float(race.next_number))
	var number := str(race.next_number)
	var text_size := FONT.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	var text_position := origin + direction * 166.0 + Vector2(-text_size.x * 0.5, 8)
	draw_string_outline(FONT, text_position, number, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 4, Arrow.OUTLINE_COLOR)
	draw_string(FONT, text_position, number, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ARROW_COLOR)

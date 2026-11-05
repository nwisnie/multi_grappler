extends Node2D
## Editable Area2D polygons select the built-in tutorial's current instruction.

const InstructionArea := preload("res://scripts/levels/tutorial_instruction_area.gd")

## Vertical wave height in pixels.
@export_range(0.0, 20.0, 0.5) var wave_amplitude := 6.0
@export_range(0.1, 10.0, 0.1) var wave_frequency := 2.4

@onready var player: RigidBody2D = $Ball
@onready var instruction_label: RichTextLabel = $TutorialInstructions/Instruction

var active_areas: Array[InstructionArea] = []
var current_instruction := ""

func _ready() -> void:
	for child in $TutorialAreas.get_children():
		if child is InstructionArea:
			child.body_entered.connect(_on_area_entered.bind(child))
			child.body_exited.connect(_on_area_exited.bind(child))
			# Show the spawn prompt immediately, before the first physics overlap.
			if child.contains_point(player.global_position):
				active_areas.append(child)
	_update_instruction()

func _on_area_entered(body: Node2D, area: InstructionArea) -> void:
	if body != player:
		return
	if not active_areas.has(area):
		active_areas.append(area)
	_update_instruction()

func _on_area_exited(body: Node2D, area: InstructionArea) -> void:
	if body != player:
		return
	active_areas.erase(area)
	_update_instruction()

func _update_instruction() -> void:
	var selected: InstructionArea
	for area in active_areas:
		if selected == null or area.instruction_priority > selected.instruction_priority:
			selected = area
	var text := selected.instruction if selected != null else ""
	if current_instruction != text:
		current_instruction = text
		var escaped := text.replace("[", "[lb]")
		# Godot's built-in wave uses tenths of a pixel for amplitude.
		instruction_label.text = "[center][wave amp=%s freq=%s]%s[/wave][/center]" % [wave_amplitude * 10.0, wave_frequency, escaped]
	instruction_label.visible = not text.is_empty()

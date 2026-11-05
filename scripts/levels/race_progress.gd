extends Node2D
## Each local player must pass every hoop in order before a lap can finish.

signal checkpoint_reached(number: int)
signal lap_completed(number: int)
signal race_finished(seconds: float)

const Hoop := preload("res://scripts/levels/race_checkpoint.gd")
const HUD := preload("res://scripts/ui/race_hud.gd")
# Any part of the ball overlapping the hoop opening counts, including rim grazes.
const PASS_RADIUS := LevelDocument.CHECKPOINT_RADIUS + LevelDocument.PLAYER_RADIUS

var document: LevelDocument
var player: RigidBody2D
var hoops: Array[Node2D] = []
var next_number := 2
var lap := 1
var elapsed := 0.0
var finished := false
var previous_position := Vector2.ZERO
var hud: Control

func _ready() -> void:
	for index in range(document.checkpoints.size() + 1):
		var hoop := Hoop.new()
		hoop.name = "Checkpoint%d" % (index + 1)
		hoop.number = index + 1
		hoop.is_start = index == 0
		hoop.is_finish = index + 1 == document.finish_checkpoint
		hoop.position = LevelDocument.cell_position(document.spawn if index == 0 else document.checkpoints[index - 1])
		add_child(hoop)
		hoops.append(hoop)
	var layer := CanvasLayer.new()
	layer.name = "RaceHUD"
	layer.layer = 25
	add_child(layer)
	hud = HUD.new()
	hud.race = self
	layer.add_child(hud)
	reset()

func reset() -> void:
	next_number = 2
	lap = 1
	elapsed = 0.0
	finished = false
	previous_position = player.global_position
	_update_hoops()

func next_position() -> Vector2:
	return hoops[next_number - 1].global_position

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if finished or player.controls_locked:
		previous_position = player.global_position
		return
	elapsed += delta
	advance_between(previous_position, player.global_position)
	previous_position = player.global_position

func advance_between(from: Vector2, to: Vector2) -> void:
	if finished:
		return
	# Swept center detection cannot miss a hoop when a fast player crosses it
	# between physics frames. Process crossings in travel order, not hoop order
	# along the entire segment, so an already-passed later hoop cannot count.
	var start := from
	for crossing in range(hoops.size()):
		var motion := to - start
		var length_squared := motion.length_squared()
		var relative := start - next_position()
		# Standing in overlapping hoops cannot award checkpoints or farm laps.
		if length_squared < 0.0001 or relative.length_squared() <= PASS_RADIUS * PASS_RADIUS:
			return
		var b := relative.dot(motion)
		var c := relative.length_squared() - PASS_RADIUS * PASS_RADIUS
		var discriminant := b * b - length_squared * c
		if discriminant < 0.0:
			return
		var fraction := (-b - sqrt(discriminant)) / length_squared
		if fraction < 0.0 or fraction > 1.0:
			return
		start = start.lerp(to, fraction)
		_reach_checkpoint()
		if finished:
			return

func _reach_checkpoint() -> void:
	var reached := next_number
	checkpoint_reached.emit(reached)
	if reached == document.finish_checkpoint:
		lap_completed.emit(lap)
		if lap >= document.race_laps:
			finished = true
			race_finished.emit(elapsed)
		else:
			lap += 1
			next_number = 2
	elif reached == hoops.size():
		next_number = 1
	else:
		next_number += 1
	_update_hoops()

func _update_hoops() -> void:
	for index in range(hoops.size()):
		var hoop := hoops[index]
		hoop.active = not finished and index + 1 == next_number
		hoop.passed = finished or (index + 1 != 1 and (next_number == 1 or index + 1 < next_number))
		hoop.queue_redraw()

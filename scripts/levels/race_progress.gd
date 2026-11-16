extends Node2D
## Each local player must pass every checkpoint in order before a lap can finish.

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
		hoop.position = document.checkpoint_position(index + 1)
		if document.checkpoint_lines.has(index + 1):
			var line: Dictionary = document.checkpoint_lines[index + 1]
			hoop.line_points = PackedVector2Array([LevelDocument.cell_position(line["a"]) - hoop.position, LevelDocument.cell_position(line["b"]) - hoop.position])
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
	if document.checkpoint_lines.has(next_number):
		var line: Dictionary = document.checkpoint_lines[next_number]
		return Geometry2D.get_closest_point_to_segment(player.global_position, LevelDocument.cell_position(line["a"]), LevelDocument.cell_position(line["b"]))
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
		var fraction := _crossing_fraction(start, to)
		if fraction < 0.0:
			return
		start = start.lerp(to, fraction)
		_reach_checkpoint()
		if finished:
			return

func _crossing_fraction(from: Vector2, to: Vector2) -> float:
	var motion := to - from
	if motion.length_squared() < 0.0001:
		return -1.0
	if not document.checkpoint_lines.has(next_number):
		return _circle_entry(from, motion, hoops[next_number - 1].global_position, PASS_RADIUS)
	# A swept ball against a finite line is a capsule: a strip plus two end caps.
	var line: Dictionary = document.checkpoint_lines[next_number]
	var a := LevelDocument.cell_position(line["a"])
	var b := LevelDocument.cell_position(line["b"])
	var radius := LevelDocument.PLAYER_RADIUS
	if from.distance_squared_to(Geometry2D.get_closest_point_to_segment(from, a, b)) <= radius * radius:
		return -1.0
	var tangent := (b - a).normalized()
	var normal := tangent.orthogonal()
	var perpendicular := (from - a).dot(normal)
	var speed := motion.dot(normal)
	var earliest := 2.0
	if absf(speed) > 0.00001:
		for side in [-radius, radius]:
			var fraction: float = (side - perpendicular) / speed
			if fraction >= 0.0 and fraction <= 1.0:
				var along := (from + motion * fraction - a).dot(tangent)
				if along >= 0.0 and along <= a.distance_to(b):
					earliest = minf(earliest, fraction)
	for endpoint in [a, b]:
		var fraction := _circle_entry(from, motion, endpoint, radius)
		if fraction >= 0.0:
			earliest = minf(earliest, fraction)
	return earliest if earliest <= 1.0 else -1.0

func _circle_entry(from: Vector2, motion: Vector2, center: Vector2, radius: float) -> float:
	var relative := from - center
	if relative.length_squared() <= radius * radius:
		return -1.0
	var length_squared := motion.length_squared()
	var b := relative.dot(motion)
	var c := relative.length_squared() - radius * radius
	var discriminant := b * b - length_squared * c
	if discriminant < 0.0:
		return -1.0
	var fraction := (-b - sqrt(discriminant)) / length_squared
	return fraction if fraction >= 0.0 and fraction <= 1.0 else -1.0

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

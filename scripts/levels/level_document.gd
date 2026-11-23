class_name LevelDocument
extends RefCounted
## Portable level definitions. Coordinates are grid integers, never scene nodes.

const VERSION := 1
const GRID_SIZE := 100
const CELL_SIZE := 120.0
const BOARD_SIZE := GRID_SIZE * CELL_SIZE
const HALF_WIDTH := CELL_SIZE * 0.5
const PLAYER_RADIUS := 48.0 * 1.18
const MAX_SEGMENTS := 1024
const MAX_ORBS := 128
const MAX_CHECKPOINTS := 128
const MAX_RACE_LAPS := 50
const CHECKPOINT_RADIUS := 240.0
enum SegmentKind { LINE, CURVE }

var segments: Array[Dictionary] = []
var spawn := Vector2i(-1, -1)
var orbs: Array[Vector2i] = []
## Array order is race order; the spawn is always checkpoint 1.
var checkpoints: Array[Vector2i] = []
## Line endpoints keyed by race number. New lines use vertices; old codes retain cell centers.
var checkpoint_lines: Dictionary = {}
## Percentage along the spawn line, from endpoint A to B.
var spawn_line_position := 50
## 1 closes the course at spawn. A separate finish is always the last checkpoint.
var finish_checkpoint := 1
var race_laps := 1

func copy() -> LevelDocument:
	var result := LevelDocument.new()
	result.segments = segments.duplicate(true)
	result.spawn = spawn
	result.orbs.assign(orbs)
	result.checkpoints.assign(checkpoints)
	result.checkpoint_lines = checkpoint_lines.duplicate(true)
	result.spawn_line_position = spawn_line_position
	result.finish_checkpoint = finish_checkpoint
	result.race_laps = race_laps
	return result

func reorder_checkpoint(index: int, number: int) -> int:
	if finish_checkpoint > 1 and index == checkpoints.size() - 1:
		return index
	var last_number := checkpoints.size() if finish_checkpoint > 1 else checkpoints.size() + 1
	var destination := clampi(number, 2, last_number) - 2
	var point := checkpoints[index]
	var line: Dictionary = checkpoint_lines.get(index + 2, {})
	_shift_checkpoint_lines(index + 2, -1)
	checkpoints.remove_at(index)
	_shift_checkpoint_lines(destination + 2, 1)
	checkpoints.insert(destination, point)
	if not line.is_empty():
		checkpoint_lines[destination + 2] = line
	return destination

func mark_finish(index: int) -> int:
	var point := checkpoints[index]
	var line: Dictionary = checkpoint_lines.get(index + 2, {})
	_shift_checkpoint_lines(index + 2, -1)
	checkpoints.remove_at(index)
	checkpoints.append(point)
	if not line.is_empty():
		checkpoint_lines[checkpoints.size() + 1] = line
	finish_checkpoint = checkpoints.size() + 1
	race_laps = 1
	return checkpoints.size() - 1

func remove_checkpoint(index: int) -> void:
	var removed_finish := finish_checkpoint > 1 and index == checkpoints.size() - 1
	checkpoints.remove_at(index)
	_shift_checkpoint_lines(index + 2, -1)
	if removed_finish:
		finish_checkpoint = 1
	elif finish_checkpoint > 1:
		finish_checkpoint = checkpoints.size() + 1

func _shift_checkpoint_lines(number: int, step: int) -> void:
	var shifted := {}
	for key in checkpoint_lines:
		if step < 0 and key == number:
			continue
		shifted[key + step if key >= number else key] = checkpoint_lines[key]
	checkpoint_lines = shifted

func insert_checkpoint(index: int, point: Vector2i) -> void:
	_shift_checkpoint_lines(index + 2, 1)
	checkpoints.insert(index, point)
	if finish_checkpoint > 1:
		finish_checkpoint += 1

func checkpoint_cell(number: int) -> Vector2i:
	return spawn if number == 1 else checkpoints[number - 2]

func checkpoint_position(number: int) -> Vector2:
	if checkpoint_lines.has(number):
		return (checkpoint_endpoint(number, "a") + checkpoint_endpoint(number, "b")) * 0.5
	return cell_position(checkpoint_cell(number))

func checkpoint_endpoint(number: int, key: String) -> Vector2:
	var line: Dictionary = checkpoint_lines[number]
	return vertex_position(line[key]) if line.get("vertices", false) else cell_position(line[key])

func spawn_position() -> Vector2:
	if checkpoint_lines.has(1):
		return checkpoint_endpoint(1, "a").lerp(checkpoint_endpoint(1, "b"), spawn_line_position / 100.0)
	return cell_position(spawn)

func set_checkpoint_line(number: int, a: Vector2i, b: Vector2i, vertices: bool = true) -> void:
	checkpoint_lines[number] = {"a": a, "b": b}
	if vertices:
		checkpoint_lines[number]["vertices"] = true
	var center := snap_cell(checkpoint_position(number))
	if number == 1:
		spawn = center
	else:
		checkpoints[number - 2] = center

func move_checkpoint(number: int, point: Vector2i) -> void:
	if checkpoint_lines.has(number):
		var offset := point - checkpoint_cell(number)
		var line: Dictionary = checkpoint_lines[number]
		set_checkpoint_line(number, line["a"] + offset, line["b"] + offset, line.get("vertices", false))
	elif number == 1:
		spawn = point
	else:
		checkpoints[number - 2] = point

static func vertex_position(point: Vector2i) -> Vector2:
	return Vector2(point) * CELL_SIZE

static func cell_position(point: Vector2i) -> Vector2:
	return (Vector2(point) + Vector2.ONE * 0.5) * CELL_SIZE

static func valid_vertex(point: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x <= GRID_SIZE and point.y <= GRID_SIZE

static func valid_cell(point: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < GRID_SIZE and point.y < GRID_SIZE

func snap_vertex(world: Vector2) -> Vector2i:
	var nearest := Vector2i(roundi(world.x / CELL_SIZE), roundi(world.y / CELL_SIZE))
	var distance := HALF_WIDTH + 0.001
	# Prefer a shared endpoint to a fresh intersection. Iteration order breaks ties.
	for segment in segments:
		for key in ["a", "b"]:
			var candidate: Vector2i = segment[key]
			var candidate_distance := world.distance_to(vertex_position(candidate))
			if candidate_distance < distance:
				distance = candidate_distance
				nearest = candidate
	return nearest.clamp(Vector2i.ZERO, Vector2i(GRID_SIZE, GRID_SIZE))

static func snap_cell(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / CELL_SIZE), floori(world.y / CELL_SIZE)).clamp(Vector2i.ZERO, Vector2i(GRID_SIZE - 1, GRID_SIZE - 1))

static func curve_control(segment: Dictionary) -> Vector2:
	return vertex_position(segment["m"]) * 2.0 - (vertex_position(segment["a"]) + vertex_position(segment["b"])) * 0.5

static func sample_segment(segment: Dictionary) -> PackedVector2Array:
	var a := vertex_position(segment["a"])
	var b := vertex_position(segment["b"])
	if segment["kind"] == SegmentKind.LINE:
		return PackedVector2Array([a, b])
	var control := curve_control(segment)
	# Quadratic chord error <= |a - 2c + b| / (4 * steps^2).
	# A fixed world-space tolerance keeps geometry identical at every zoom/client.
	var steps := maxi(2, ceili(sqrt((a - 2.0 * control + b).length() / 2.0)))
	steps += steps % 2 # Include t=0.5 exactly (the third defining point).
	var points := PackedVector2Array()
	for index in range(steps + 1):
		var t := float(index) / steps
		points.append(a * (1.0 - t) * (1.0 - t) + control * 2.0 * (1.0 - t) * t + b * t * t)
	return points

static func segment_error(segment: Dictionary) -> String:
	if not segment.has_all(["kind", "a", "b"]):
		return "A segment is missing defining points."
	if typeof(segment["kind"]) != TYPE_INT or segment["kind"] not in [SegmentKind.LINE, SegmentKind.CURVE]:
		return "Unknown terrain type."
	for key in ["a", "b"]:
		if typeof(segment[key]) != TYPE_VECTOR2I or not valid_vertex(segment[key]):
			return "Terrain points must be intersections inside the grid."
	if segment["a"] == segment["b"]:
		return "Choose two different endpoints."
	if segment["kind"] == SegmentKind.CURVE:
		if not segment.has("m") or typeof(segment["m"]) != TYPE_VECTOR2I or not valid_vertex(segment["m"]):
			return "The curve needs a third grid intersection."
		if segment["m"] == segment["a"] or segment["m"] == segment["b"]:
			return "The curve point must differ from both endpoints."
		var a := vertex_position(segment["a"])
		var b := vertex_position(segment["b"])
		var c := curve_control(segment)
		# Check analytic extrema; samples alone could miss a small overshoot.
		for axis in range(2):
			var denominator := a[axis] - 2.0 * c[axis] + b[axis]
			if absf(denominator) > 0.00001:
				var t := (a[axis] - c[axis]) / denominator
				if t > 0.0 and t < 1.0:
					var value := a[axis] * pow(1.0 - t, 2) + 2.0 * c[axis] * (1.0 - t) * t + b[axis] * t * t
					if value < -0.001 or value > BOARD_SIZE + 0.001:
						return "This curve extends outside the grid. Move its third point inward."
	return ""

func validate() -> String:
	if checkpoints.size() > MAX_CHECKPOINTS:
		return "Level limit: 128 race checkpoints, plus the spawn."
	if race_laps < 1 or race_laps > MAX_RACE_LAPS:
		return "Choose between 1 and %d laps." % MAX_RACE_LAPS
	if finish_checkpoint != 1 and (checkpoints.is_empty() or finish_checkpoint != checkpoints.size() + 1):
		return "A separate finish checkpoint must be the last checkpoint."
	if finish_checkpoint > 1 and race_laps != 1:
		return "Laps require finishing at the spawn checkpoint."
	if spawn_line_position < 0 or spawn_line_position > 100:
		return "The spawn position must be between 0% and 100% of its line."
	for number in checkpoint_lines:
		if typeof(number) != TYPE_INT or number < 1 or number > checkpoints.size() + 1 or (number == 1 and not valid_cell(spawn)):
			return "A checkpoint line must belong to an existing checkpoint or spawn."
		if typeof(checkpoint_lines[number]) != TYPE_DICTIONARY:
			return "A checkpoint line needs two endpoints."
		var line: Dictionary = checkpoint_lines[number]
		if line.has("vertices") and typeof(line["vertices"]) != TYPE_BOOL:
			return "Invalid checkpoint line coordinate type."
		for key in ["a", "b"]:
			if not line.has(key) or typeof(line[key]) != TYPE_VECTOR2I:
				return "Checkpoint line endpoints must be grid points."
			if not (valid_vertex(line[key]) if line.get("vertices", false) else valid_cell(line[key])):
				return "Checkpoint line endpoints must be inside the grid."
		if line["a"] == line["b"]:
			return "Choose two different checkpoint line endpoints."
	var occupied := {}
	if valid_cell(spawn):
		occupied[spawn] = true
	for checkpoint in checkpoints:
		if not valid_cell(checkpoint):
			return "Race checkpoints must be cells inside the grid."
		if occupied.has(checkpoint):
			return "Race checkpoints and the spawn must occupy different cells."
		occupied[checkpoint] = true
	if segments.size() > MAX_SEGMENTS or orbs.size() > MAX_ORBS:
		return "Level limit: 1,024 segments and 128 grapple orbs."
	if spawn != Vector2i(-1, -1) and not valid_cell(spawn):
		return "The spawn must be a cell inside the grid."
	for orb in orbs:
		if not valid_cell(orb):
			return "Grapple orbs must be cells inside the grid."
	for segment in segments:
		var error := segment_error(segment)
		if not error.is_empty():
			return error
	return ""

func publication_error() -> String:
	var error := playtest_error()
	if not error.is_empty():
		return error
	if checkpoints.is_empty():
		return "Publishing requires at least 2 checkpoints. Add a Race checkpoint in addition to the spawn."
	return ""

func playtest_error() -> String:
	var error := validate()
	if not error.is_empty():
		return error
	if not valid_cell(spawn):
		return "Place a player spawn before playtesting."
	var position := spawn_position()
	for segment in segments:
		var points := sample_segment(segment)
		for index in range(points.size() - 1):
			if position.distance_to(Geometry2D.get_closest_point_to_segment(position, points[index], points[index + 1])) <= HALF_WIDTH + PLAYER_RADIUS + 7.0:
				return "The spawn overlaps terrain. Move it to a clear cell."
	return ""

func move_vertex(old: Vector2i, replacement: Vector2i) -> void:
	for segment in segments:
		for key in ["a", "b"]:
			if segment[key] == old:
				segment[key] = replacement

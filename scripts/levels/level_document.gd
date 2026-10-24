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
enum SegmentKind { LINE, CURVE }

var segments: Array[Dictionary] = []
var spawn := Vector2i(-1, -1)
var orbs: Array[Vector2i] = []

func copy() -> LevelDocument:
	var result := LevelDocument.new()
	result.segments = segments.duplicate(true)
	result.spawn = spawn
	result.orbs.assign(orbs)
	return result

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

func playtest_error() -> String:
	var error := validate()
	if not error.is_empty():
		return error
	if not valid_cell(spawn):
		return "Place a player spawn before playtesting."
	var position := cell_position(spawn)
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

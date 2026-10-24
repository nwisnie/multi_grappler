class_name LevelGeometry
extends RefCounted
## Builds the exposed boundary of a union of thick strokes, including hole rings.
## Splitting edges at intersections and testing both sides avoids interior seams,
## including coincident/partially overlapping edges and nested islands.

const BIN_SIZE := 480.0
const EDGE_BIN_SIZE := 120.0
const EPSILON := 0.02
const KEY_SCALE := 1000.0

static func polygons_for(document: LevelDocument) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	var straight_groups := {}
	for segment in document.segments:
		if segment["kind"] == LevelDocument.SegmentKind.LINE:
			var a: Vector2i = segment["a"]
			var b: Vector2i = segment["b"]
			var direction := b - a
			var divisor := _gcd(absi(direction.x), absi(direction.y))
			direction = Vector2i(direction.x / divisor, direction.y / divisor)
			if direction.x < 0 or (direction.x == 0 and direction.y < 0):
				direction = -direction
			var identity := Vector3i(direction.x, direction.y, direction.x * a.y - direction.y * a.x)
			if not straight_groups.has(identity):
				straight_groups[identity] = []
			var start := a.x * direction.x + a.y * direction.y
			var end := b.x * direction.x + b.y * direction.y
			straight_groups[identity].append({"start": mini(start, end), "end": maxi(start, end), "a": a if start < end else b, "b": b if start < end else a})
			continue
		for polygon in Geometry2D.offset_polyline(LevelDocument.sample_segment(segment), LevelDocument.HALF_WIDTH, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			# Godot 4.3's scaled Clipper offsets can emit >4,000 cap points.
			# Reduce those subpixel edges before rendering and boolean operations.
			polygons.append(_simplify_closed(polygon))
	# Collapse collinear runs before union, without changing editable definitions.
	# A thousand adjacent grid segments can become only a handful of surfaces.
	for identity in straight_groups:
		var intervals: Array = straight_groups[identity]
		intervals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["start"] < b["start"])
		var current: Dictionary = intervals[0].duplicate()
		for index in range(1, intervals.size()):
			var next: Dictionary = intervals[index]
			if next["start"] <= current["end"]:
				if next["end"] > current["end"]:
					current["end"] = next["end"]
					current["b"] = next["b"]
			else:
				polygons.append(_line_polygon(LevelDocument.vertex_position(current["a"]), LevelDocument.vertex_position(current["b"])))
				current = next.duplicate()
		polygons.append(_line_polygon(LevelDocument.vertex_position(current["a"]), LevelDocument.vertex_position(current["b"])))
	return polygons

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return maxi(a, 1)

static func _line_polygon(a: Vector2, b: Vector2) -> PackedVector2Array:
	var forward := (b - a).normalized()
	var normal := Vector2(-forward.y, forward.x)
	var result := PackedVector2Array()
	for index in range(33):
		var angle := PI * 0.5 - PI * float(index) / 32.0
		result.append(b + (forward * cos(angle) + normal * sin(angle)) * LevelDocument.HALF_WIDTH)
	for index in range(33):
		var angle := -PI * 0.5 - PI * float(index) / 32.0
		result.append(a + (forward * cos(angle) + normal * sin(angle)) * LevelDocument.HALF_WIDTH)
	return result

static func _simplify_open(points: PackedVector2Array) -> PackedVector2Array:
	var kept := {0: true, points.size() - 1: true}
	var pending: Array[Vector2i] = [Vector2i(0, points.size() - 1)]
	while not pending.is_empty():
		var span: Vector2i = pending.pop_back()
		var largest := 0.25
		var selected := -1
		for index in range(span.x + 1, span.y):
			var distance := points[index].distance_to(Geometry2D.get_closest_point_to_segment(points[index], points[span.x], points[span.y]))
			if distance > largest:
				largest = distance
				selected = index
		if selected != -1:
			kept[selected] = true
			pending.append(Vector2i(span.x, selected))
			pending.append(Vector2i(selected, span.y))
	var result := PackedVector2Array()
	var indices := kept.keys()
	indices.sort()
	for index in indices:
		result.append(points[index])
	return result

static func _simplify_closed(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 4:
		return points
	var split := 1
	var farthest := 0.0
	for index in range(1, points.size()):
		var distance := points[0].distance_squared_to(points[index])
		if distance > farthest:
			farthest = distance
			split = index
	var first := _simplify_open(points.slice(0, split + 1))
	var second := points.slice(split)
	second.append(points[0])
	second = _simplify_open(second)
	var result := first.slice(0, first.size() - 1)
	result.append_array(second.slice(0, second.size() - 1))
	return result

static func _bounds(points: PackedVector2Array) -> Rect2:
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect.grow(EPSILON * 2.0)

static func _bins(rect: Rect2, bin_size: float = BIN_SIZE) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start := Vector2i(floori(rect.position.x / bin_size), floori(rect.position.y / bin_size))
	var end := Vector2i(floori(rect.end.x / bin_size), floori(rect.end.y / bin_size))
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			result.append(Vector2i(x, y))
	return result

static func _insert(index: Dictionary, rect: Rect2, value: int, bin_size: float = BIN_SIZE) -> void:
	for bin_key in _bins(rect, bin_size):
		if not index.has(bin_key):
			index[bin_key] = []
		index[bin_key].append(value)

static func _point_inside(point: Vector2, polygon: PackedVector2Array) -> bool:
	# Scalar arithmetic is double precision. The native ray test in 4.3 can
	# misclassify points near long, nearly horizontal edges at this board size.
	var inside := false
	var previous := polygon.size() - 1
	for current in range(polygon.size()):
		var a := polygon[current]
		var b := polygon[previous]
		if (a.y > point.y) != (b.y > point.y):
			var crossing: float = (float(b.x) - float(a.x)) * (float(point.y) - float(a.y)) / (float(b.y) - float(a.y)) + float(a.x)
			if point.x < crossing:
				inside = not inside
		previous = current
	return inside

static func _covered(point: Vector2, source_normal: Vector2, polygons: Array[PackedVector2Array], index: Dictionary, excluded: int, winding: Array[bool], polygon_bounds: Array[Rect2]) -> bool:
	var key := Vector2i(floori(point.x / BIN_SIZE), floori(point.y / BIN_SIZE))
	for polygon_id in index.get(key, []):
		if polygon_id == excluded or not polygon_bounds[int(polygon_id)].has_point(point):
			continue
		var polygon := polygons[int(polygon_id)]
		var on_boundary := false
		for edge_id in range(polygon.size()):
			var a := polygon[edge_id]
			var b := polygon[(edge_id + 1) % polygon.size()]
			var direction := b - a
			var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
			if closest.distance_squared_to(point) <= 0.000009:
				var other_normal := Vector2(-direction.y, direction.x).normalized() * (1.0 if winding[int(polygon_id)] else -1.0)
				if absf(source_normal.normalized().cross(other_normal)) > 0.00001:
					continue
				on_boundary = true
				# Opposing interiors mean this is an internal shared edge. For
				# coincident outer boundaries, retain exactly one source polygon.
				if source_normal.dot(other_normal) < 0.0 or polygon_id < excluded:
					return true
				break
		if not on_boundary and _point_inside(point, polygon):
			return true
	return false

static func _split_parameters(a: Vector2, b: Vector2, c: Vector2, d: Vector2, splits: Array[float]) -> void:
	var r := b - a
	var s := d - c
	var cross := r.cross(s)
	if absf(cross) > 0.0000001 * maxf(1.0, r.length() * s.length()):
		var t := (c - a).cross(s) / cross
		var u := (c - a).cross(r) / cross
		if t > 0.0000001 and t < 0.9999999 and u >= -0.0000001 and u <= 1.0000001:
			splits.append(t)
	elif absf((c - a).cross(r)) <= 0.00001 * r.length():
		for point in [c, d]:
			var t: float = (point - a).dot(r) / r.length_squared()
			if t > 0.0000001 and t < 0.9999999:
				splits.append(t)

static func _key(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x * KEY_SCALE), roundi(point.y * KEY_SCALE))

static func _weld_key(point: Vector2, lookup: Dictionary) -> Vector2i:
	var precise := _key(point)
	var bin_key := Vector2i(floori(float(precise.x) / 20.0), floori(float(precise.y) / 20.0))
	for y in range(-1, 2):
		for x in range(-1, 2):
			for candidate in lookup.get(bin_key + Vector2i(x, y), []):
				if Vector2(precise).distance_squared_to(Vector2(candidate)) <= 100.0:
					return candidate
	if not lookup.has(bin_key):
		lookup[bin_key] = []
	lookup[bin_key].append(precise)
	return precise

static func union_boundaries(polygons: Array[PackedVector2Array]) -> Dictionary:
	var polygon_index := {}
	var edge_index := {}
	var edges: Array[Dictionary] = []
	var winding: Array[bool] = []
	var polygon_bounds: Array[Rect2] = []
	for polygon_id in range(polygons.size()):
		var polygon := polygons[polygon_id]
		var signed_area := 0.0
		for index in range(polygon.size()):
			signed_area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
		winding.append(signed_area > 0.0)
		var rect_bounds := _bounds(polygon)
		polygon_bounds.append(rect_bounds)
		_insert(polygon_index, rect_bounds, polygon_id)
		for index in range(polygon.size()):
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			if a.distance_squared_to(b) < 0.000001:
				continue
			var rect := _bounds(PackedVector2Array([a, b]))
			_insert(edge_index, rect, edges.size(), EDGE_BIN_SIZE)
			edges.append({"a": a, "b": b, "polygon": polygon_id, "bounds": rect, "left": signed_area > 0.0})
	var boundary: Array[Dictionary] = []
	var unique := {}
	var outgoing := {}
	var weld_lookup := {}
	for edge_id in range(edges.size()):
		var edge := edges[edge_id]
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var candidates := {}
		for bin_key in _bins(edge["bounds"], EDGE_BIN_SIZE):
			for other_id in edge_index[bin_key]:
				candidates[other_id] = true
		var splits: Array[float] = [0.0, 1.0]
		for other_id in candidates:
			var other := edges[int(other_id)]
			if other["polygon"] != edge["polygon"] and edge["bounds"].intersects(other["bounds"]):
				_split_parameters(a, b, other["a"], other["b"], splits)
		splits.sort()
		for index in range(splits.size() - 1):
			var start := a.lerp(b, splits[index])
			var end := a.lerp(b, splits[index + 1])
			var direction := end - start
			if direction.length() < 0.002:
				continue
			var normal := Vector2(-direction.y, direction.x).normalized() * EPSILON
			var middle := (start + end) * 0.5
			var left: bool = edge["left"]
			if _covered(middle, normal if left else -normal, polygons, polygon_index, edge["polygon"], winding, polygon_bounds):
				continue
			# Float32 intersections computed from opposite edges can differ by a
			# few thousandths at world coordinates near 12,000. Weld those results.
			var start_key := _weld_key(start if left else end, weld_lookup)
			var end_key := _weld_key(end if left else start, weld_lookup)
			if start_key == end_key:
				continue
			var identity := "%s/%s" % [start_key, end_key]
			if unique.has(identity):
				continue
			unique[identity] = true
			if not outgoing.has(start_key):
				outgoing[start_key] = []
			outgoing[start_key].append(boundary.size())
			boundary.append({"a": start_key, "b": end_key})
	var contours: Array[PackedVector2Array] = []
	var visited := {}
	for first_id in range(boundary.size()):
		if visited.has(first_id):
			continue
		var first: Vector2i = boundary[first_id]["a"]
		var current_id := first_id
		var points := PackedVector2Array()
		var closed := false
		while not visited.has(current_id):
			visited[current_id] = true
			var current := boundary[current_id]
			points.append(Vector2(current["a"]) / KEY_SCALE)
			var end_key: Vector2i = current["b"]
			if end_key == first:
				closed = true
				break
			var next_id := -1
			var best_turn := INF
			var direction := Vector2(current["b"] - current["a"])
			for candidate in outgoing.get(end_key, []):
				if visited.has(candidate):
					continue
				var next_direction := Vector2(boundary[candidate]["b"] - end_key)
				var turn := fposmod(direction.angle_to(next_direction), TAU)
				if turn < best_turn:
					best_turn = turn
					next_id = candidate
			if next_id == -1:
				break
			current_id = next_id
		if not closed:
			var end_key: Vector2i = boundary[current_id]["b"]
			var nearest := INF
			var nearest_key := Vector2i.ZERO
			for candidate_key in outgoing:
				var distance := Vector2(end_key).distance_to(Vector2(candidate_key)) / KEY_SCALE
				if distance < nearest:
					nearest = distance
					nearest_key = candidate_key
			return {"error": "Terrain boundaries could not be joined. Try moving the overlapping segments.", "debug": [end_key, nearest_key, nearest, boundary.size(), points.size()]}
		if points.size() >= 3:
			contours.append(points)
	return {"error": "", "contours": contours}

static func build_runtime(document: LevelDocument) -> Dictionary:
	var error := document.validate()
	if not error.is_empty():
		return {"error": error}
	var polygons := polygons_for(document)
	var result := union_boundaries(polygons)
	if not result["error"].is_empty():
		return result
	var body := StaticBody2D.new()
	body.name = "CustomTerrain"
	body.collision_layer = 1
	body.collision_mask = 1
	var material := PhysicsMaterial.new()
	material.friction = 1.1
	body.physics_material_override = material
	for contour in result["contours"]:
		var collision := CollisionPolygon2D.new()
		collision.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
		collision.polygon = contour
		body.add_child(collision)
	return {"error": "", "body": body, "polygons": polygons, "contours": result["contours"]}

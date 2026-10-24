extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 1377
	var failures := 0
	for trial in range(12):
		var document := LevelDocument.new()
		while document.segments.size() < 16:
			var a := Vector2i(random.randi_range(10, 90), random.randi_range(10, 90))
			var b := Vector2i(random.randi_range(10, 90), random.randi_range(10, 90))
			var kind := 1 if (trial + document.segments.size()) % 3 == 0 else 0
			var segment := {"kind": kind, "a": a, "b": b}
			if kind == 1:
				segment["m"] = Vector2i((Vector2(a) + Vector2(b)) * 0.5) + Vector2i(random.randi_range(-10, 10), random.randi_range(-10, 10))
			if LevelDocument.segment_error(segment).is_empty():
				document.segments.append(segment)
		var start := Time.get_ticks_msec()
		var result := LevelGeometry.union_boundaries(LevelGeometry.polygons_for(document))
		print("GEOMETRY TRIAL ", trial, ": ", Time.get_ticks_msec() - start, " ms; ", result["error"])
		if not result["error"].is_empty():
			failures += 1
			print("REPRO ", LevelCodec.encode_level(document), " ", result.get("debug", []))
		document.segments.reverse()
		var reordered := LevelGeometry.union_boundaries(LevelGeometry.polygons_for(document))
		if not reordered["error"].is_empty() or reordered.get("contours", []).size() != result.get("contours", []).size():
			failures += 1
			print("ORDER FAILURE ", trial, " ", reordered.get("debug", []))
	var maximum := LevelDocument.new()
	for index in range(LevelDocument.MAX_SEGMENTS):
		var x := index % 99
		var y := (index / 99) % 100
		maximum.segments.append({"kind": 0, "a": Vector2i(x, y), "b": Vector2i(x + 1, y)})
	var start := Time.get_ticks_msec()
	var result := LevelGeometry.union_boundaries(LevelGeometry.polygons_for(maximum))
	print("MAXIMUM GEOMETRY: ", Time.get_ticks_msec() - start, " ms; ", result["error"])
	if not result["error"].is_empty():
		failures += 1
		print(result.get("debug", []))
	print("GEOMETRY STRESS: ", failures, " failures")
	quit(1 if failures else 0)

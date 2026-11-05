extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(4):
		await physics_frame
	await process_frame

func _run() -> void:
	var level = load("res://scenes/base_level.tscn").instantiate()
	level.get_node("Ball").freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	level.get_node("Ball").freeze = true
	root.add_child(level)
	check(level.current_instruction == "WASD to move", "Spawn immediately shows movement instructions")
	check(level.instruction_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Instructions do not intercept gameplay clicks")
	check(root.get_visible_rect().encloses(level.instruction_label.get_global_rect()), "Instructions fit within the viewport")
	await settle()
	check(level.instruction_label.text.contains("[wave amp="), "Instructions use an animated per-letter wave")
	for area in level.get_node("TutorialAreas").get_children():
		check(area is Area2D and area.get_node("CollisionPolygon2D") is CollisionPolygon2D, "Instruction regions are editable collision polygons")
		check(area.collision_layer == 0, "Instruction regions do not block the player")
	var cases := [
		[Vector2(-1200, 0), "WASD to move"],
		[Vector2(-872, 600), "WASD to move"],
		[Vector2(-872, 1600), ""],
		[Vector2(-2200, 0), ""],
		[Vector2(-250, 0), "WASD to move"],
		[Vector2(-80, 0), "Left Click to launch off walls and floors."],
		[Vector2(1650, 400), "Left Click to launch off walls and floors."],
		[Vector2(1780, 400), "Space to Grapple Up Walls"],
		[Vector2(2400, -1000), "Space to Grapple Up Walls"],
		[Vector2(4500, -2300), "Space to Grapple Up Walls"],
		[Vector2(4610, -2300), "Space to Grapple Toward Orbs"],
		[Vector2(5300, -2900), "Space to Grapple Toward Orbs"],
		[Vector2(1000, 400), "Left Click to launch off walls and floors."],
		[Vector2(-872, 138), "WASD to move"],
	]
	for item in cases:
		level.player.global_position = item[0]
		await settle()
		check(level.instruction_label.get_parsed_text() == item[1], "Position %s selects the expected instruction" % item[0])
		check(level.instruction_label.visible == not String(item[1]).is_empty(), "Empty instructions are hidden")
	# Moving and reshaping a region changes its physics trigger without code edits.
	var movement = level.get_node("TutorialAreas/Movement")
	movement.position.x -= 3000.0
	await settle()
	check(not level.instruction_label.visible, "Moving the collision area removes its old trigger location")
	level.player.global_position = Vector2(-3872, 138)
	await settle()
	check(level.current_instruction == "WASD to move", "The prompt follows the moved collision area")
	movement.get_node("CollisionPolygon2D").polygon = PackedVector2Array([Vector2(-50, -50), Vector2(50, -50), Vector2(50, 50), Vector2(-50, 50)])
	await settle()
	check(not level.instruction_label.visible, "Reshaping the polygon changes its trigger boundary")
	level.player.global_position = movement.global_position
	await settle()
	check(level.current_instruction == "WASD to move", "Entering the reshaped polygon restores the prompt")
	movement.get_node("CollisionPolygon2D").disabled = true
	await settle()
	check(not level.instruction_label.visible, "Disabled collision polygons do not trigger instructions")
	level.free()
	await process_frame
	check(root.find_child("TutorialInstructions", true, false) == null, "Leaving the tutorial removes its instructions")
	print("TUTORIAL: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

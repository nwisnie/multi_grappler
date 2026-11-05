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

func wall(parent: Node2D, at: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = at
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collider.shape = rectangle
	body.add_child(collider)
	parent.add_child(body)

func aim(player: RigidBody2D, world_point: Vector2) -> void:
	var pointer := InputEventMouseMotion.new()
	pointer.position = player.get_canvas_transform() * world_point
	pointer.global_position = pointer.position
	player.get_viewport().push_input(pointer, true)
	# A tiny render step must immediately use the new pointer, without waiting
	# for another physics tick or accumulating an interpolation delay.
	player._process(0.0001)

func _run() -> void:
	# A SubViewport keeps synthetic mouse input independent of the OS pointer.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_2d = World2D.new()
	root.add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	wall(world, Vector2(600, 0), Vector2(40, 1600))
	wall(world, Vector2(0, 450), Vector2(1600, 40))
	var orb = load("res://scenes/grapple_orb.tscn").instantiate()
	orb.position = Vector2(400, -400)
	world.add_child(orb)
	var player = load("res://scenes/player_ball.tscn").instantiate()
	player.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	player.freeze = true
	player.show_grapple_cursor = true
	world.add_child(player)
	player.set_physics_process(false)
	for frame in range(3):
		await physics_frame
	await process_frame
	var cases := [
		[Vector2(600, 0), Vector2(580, 0)],
		[Vector2(0, 450), Vector2(0, 430)],
		[Vector2(400, -400), Vector2(400, -400)],
		[Vector2(0, 450), Vector2(0, 430)],
		[Vector2(600, 0), Vector2(580, 0)],
	]
	for item in cases:
		aim(player, item[0])
		var expected: Vector2 = item[1]
		check(player.grapple_target_available and player.grapple_target_position.distance_to(expected) < 0.1, "Aim immediately selects the current mouse ray's hit")
		check(player.grapple_cursor.visible and player.grapple_cursor.position.distance_to(player.get_canvas_transform() * expected) < 0.1, "Cursor immediately appears at the selected grapple destination")
		check(player._try_start_grapple() and player.grapple_anchor.distance_to(expected) < 0.1, "Actual grapple launches at exactly the previewed destination")
		player.grapple_active = true
		aim(player, Vector2(-600, 0))
		check(player.grapple_cursor.position.distance_to(player.get_canvas_transform() * expected) < 0.1, "Attached cursor stays at the fixed anchor while the mouse moves")
		player._release_grapple()
	aim(player, Vector2(-600, 0))
	check(not player.grapple_cursor.visible, "Cursor immediately disappears when the ray has no target")
	player.set_controls_locked(true)
	aim(player, Vector2(600, 0))
	check(not player.grapple_cursor.visible, "Locked gameplay controls hide the grapple cursor")
	viewport.free()
	await process_frame
	print("GRAPPLE AIM: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

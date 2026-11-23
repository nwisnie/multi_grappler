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
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	shell.camera_zoom = 0.3
	shell.show_wall_cursor = true
	shell.show_demo()
	for x in [-25000.0, 0.0, 25000.0]:
		var old_level: Node = shell.world
		var old_id := old_level.get_instance_id()
		old_level.player.global_position = Vector2(x, old_level.fall_limit_y + 5000.0)
		old_level.player.linear_velocity = Vector2(3000, 8000)
		old_level.player.angular_velocity = 20.0
		old_level.player.current_health = 1
		await settle()
		check(shell.world.get_instance_id() != old_id and shell.screen == shell.Screen.TUTORIAL and not paused, "Falling below the tutorial at X=%s restarts play" % x)
		check(shell.world.player.position.distance_to(Vector2(-872, 138)) < 20.0, "Fall respawn returns to the starting platform")
		check(shell.world.player.linear_velocity.length() < 500.0 and is_zero_approx(shell.world.player.angular_velocity), "Fall respawn clears falling and rolling momentum")
		check(shell.world.player.current_health == shell.world.player.max_health and not shell.world.player.grapple_active, "Fall respawn restores health and releases the grapple")
		check(shell.world.current_instruction == "Use A/D or the left/right arrow keys to move." and not shell.world.finished and not shell.tutorial_complete_dialog.visible, "Fall respawn restores tutorial instructions without completing the level")
		check(shell.world.player.initial_camera_zoom == Vector2.ONE * 0.3 and shell.world.player.show_grapple_cursor, "Fall respawn preserves player settings")
	var held := InputEventMouseButton.new()
	held.button_index = MOUSE_BUTTON_LEFT
	held.pressed = true
	Input.parse_input_event(held)
	Input.flush_buffered_events()
	var old_level: Node = shell.world
	var requests := [0]
	old_level.restart_requested.connect(func() -> void: requests[0] += 1)
	old_level.player.grapple_active = true
	old_level.player.position.y = old_level.fall_limit_y + 1.0
	old_level._physics_process(0.0)
	old_level._physics_process(0.0)
	check(requests[0] == 1 and not old_level.player.grapple_active, "A fall releases the grapple and requests only one restart")
	await settle()
	check(shell.world.player.controls_locked, "Fall respawn waits for the held grapple button to be released")
	held.pressed = false
	Input.parse_input_event(held)
	Input.flush_buffered_events()
	await settle()
	check(not shell.world.player.controls_locked, "Releasing the mouse button restores controls after a fall")
	# A fall queued just before leaving must not reopen the tutorial.
	old_level = shell.world
	old_level.player.position.y = old_level.fall_limit_y + 1.0
	old_level._physics_process(0.0)
	shell.show_main_menu()
	await settle()
	check(shell.screen == shell.Screen.MAIN_MENU and shell.world == null, "Leaving the tutorial cancels a queued fall restart")
	shell.free()
	await process_frame
	print("TUTORIAL FALL: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

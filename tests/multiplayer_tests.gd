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

func _run() -> void:
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	var document := LevelDocument.new()
	document.spawn = Vector2i(12, 8)
	document.segments.append({"kind": 0, "a": Vector2i(2, 10), "b": Vector2i(40, 10)})
	shell._start_network_world("00123456", LevelCodec.encode_level(document), true)
	check(shell.loading_screen.visible, "Loading covers world creation until the local player has rendered")
	await process_frame
	await process_frame
	await process_frame
	await physics_frame
	check(not shell.loading_screen.visible, "Loading ends after the local player and camera are ready")
	var world = shell.world
	check(world.name == "NetworkWorld" and world.players.get_child_count() == 1, "Host loads a stable network world and player")
	var player = world.player
	check(player != null and player.is_multiplayer_authority(), "Local player belongs to its peer")
	check(player.camera.enabled and player.player_ui_layer.visible and not player.freeze, "Only local player has active camera, UI and physics")
	var sync = player.get_node("MultiplayerSynchronizer")
	check(sync is MultiplayerSynchronizer and is_equal_approx(sync.replication_interval, 1.0 / 30.0), "Player properties synchronize at 30 Hz")
	check(sync.replication_config.get_properties().size() == 5, "Movement and grapple state are replicated")
	world.add_player(2)
	await process_frame
	var replica = world.players.get_node("2")
	check(replica.get_multiplayer_authority() == 2 and replica.get_node("MultiplayerSynchronizer").get_multiplayer_authority() == 1, "Player owns its controls while the host synchronizes snapshots")
	check(replica.freeze and not replica.camera.enabled and not replica.player_ui_layer.visible, "Replica cannot consume local input or steal the camera")
	replica.network_rotation = PI * 0.5
	await process_frame
	await process_frame
	check(is_zero_approx(replica.nameplate.global_rotation) and replica.nameplate.global_position.y < replica.global_position.y - 60, "Nameplate stays upright above a rolling remote player")
	check(replica.nameplate_panel.get_child(0).get_theme_color("font_color") == Color.BLACK and replica.nameplate_panel.get_theme_stylebox("panel").bg_color == Color.WHITE, "Nameplate has black text on a white background")
	replica.network_position = replica.position + Vector2(100, 0)
	var before: Vector2 = replica.position
	await process_frame
	await process_frame
	check(replica.position.x > before.x, "Remote motion is interpolated")
	shell.pause_game()
	check(not paused and player.controls_locked, "Multiplayer menu locks local controls without pausing the tree")
	check(not shell.pause_editor_button.visible and not shell.pause_restart_button.visible, "Multiplayer cannot restart or edit only one copy of the world")
	await physics_frame
	await physics_frame
	check(player.controls_locked, "Network player remains locked while the menu is open")
	shell.resume_game()
	await process_frame
	await process_frame
	check(not player.controls_locked, "Closing the menu restores local controls")
	var identity: int = player.get_instance_id()
	player.position = Vector2(-100, -100)
	for frame in range(5):
		await physics_frame
	check(player.get_instance_id() == identity and player.position.distance_to(player.spawn_position) < 100, "Respawn preserves replicated node identity")
	world.remove_player(2)
	await process_frame
	check(world.players.get_child_count() == 1, "Departed players are removed by the host")
	shell._session_ended("The host closed the game.")
	check(shell.world == null and shell.title_screen.visible and shell.session_notice.visible, "Session end returns to title with an explanation")
	shell.session_notice.hide()
	shell._show_network_loading("Connecting...", shell.join_dialog)
	shell._session_ended("Room not found.")
	check(not shell.loading_screen.visible and shell.join_dialog.visible and shell.join_message.text == "Room not found.", "Connection failure clears loading and restores the join form with its error")
	shell._show_network_loading("Connecting...")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	shell._unhandled_input(escape)
	check(not shell.loading_screen.visible and shell.title_screen.visible, "Escape cancels loading and returns to the title")
	shell.free()
	await process_frame
	print("MULTIPLAYER: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

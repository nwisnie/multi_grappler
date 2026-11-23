extends SceneTree

const TutorialScene := preload("res://scenes/base_level.tscn")
const MenuSlide := preload("res://scripts/ui/menu_slide.gd")

var checks := 0
var failures := 0
var completions := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(4):
		await process_frame

func key(shell: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	shell._unhandled_input(event)

func _run() -> void:
	await _checkpoint_checks()
	await _navigation_checks()
	print("TUTORIAL FINISH: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _checkpoint_checks() -> void:
	var level = TutorialScene.instantiate()
	level.get_node("Ball").freeze = true
	root.add_child(level)
	level.set_physics_process(false)
	level.completed.connect(func() -> void: completions += 1)
	var hoop: Node2D = level.finish_checkpoint
	var point := hoop.global_position
	var radius: float = level.PASS_RADIUS
	check(hoop.is_finish and hoop.active and not hoop.passed, "Tutorial ends in an active race finish hoop")
	var final_orb_x := -INF
	for orb in get_nodes_in_group("grapple_orbs"):
		if level.is_ancestor_of(orb):
			final_orb_x = maxf(final_orb_x, orb.global_position.x)
	check(final_orb_x > -INF and point.x > final_orb_x, "Finish is beyond the final grapple orb")
	check(not level.finished and completions == 0, "Spawning does not complete the tutorial")
	# A path just outside the opening must miss, even at high speed.
	level.previous_position = point + Vector2(-600, -radius - 2)
	level.player.global_position = point + Vector2(600, -radius - 2)
	level._physics_process(0.0)
	check(not level.finished, "Passing outside the finish radius does not complete the tutorial")
	# Locked players cannot finish, and their old positions are discarded.
	level.player.set_controls_locked(true)
	level.previous_position = point + Vector2(-600, 0)
	level.player.global_position = point + Vector2(600, 0)
	level._physics_process(0.0)
	check(not level.finished, "Crossing while controls are locked does not complete the tutorial")
	level.player.set_controls_locked(false)
	level._physics_process(0.0)
	check(not level.finished, "Unlocking controls does not count a stale crossing")
	# Both endpoints are outside: a swept check must still count a rim graze.
	level.previous_position = point + Vector2(-600, radius - 2)
	level.player.global_position = point + Vector2(600, radius - 2)
	level._physics_process(0.0)
	check(level.finished and completions == 1, "A fast rim graze emits completion")
	check(hoop.passed and not hoop.active, "The completed finish hoop uses the passed appearance")
	check(level.player.controls_locked and not level.instruction_label.visible, "Completion locks controls and hides instructions")
	level._update_instruction()
	check(not level.instruction_label.visible, "Instruction overlap updates cannot restore prompts after completion")
	level._physics_process(0.0)
	check(completions == 1, "Completion emits only once")
	level.free()
	await process_frame

func _navigation_checks() -> void:
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	await settle()
	shell.camera_zoom = 0.57
	shell.show_wall_cursor = true
	shell.show_demo()
	var level = shell.world
	level.player.freeze = true
	level.player.global_position = level.finish_checkpoint.global_position
	await create_timer(MenuSlide.ENTER_DURATION + 0.12).timeout
	await settle()
	check(paused and shell.tutorial_complete_dialog.visible and shell.dimmer.visible, "Reaching the finish pauses gameplay and opens the completion prompt")
	check(shell.tutorial_complete_dialog.exclusive and not shell.pause_dialog.visible, "Completion uses a dedicated modal")
	check(shell.tutorial_menu_button.text == "Return to Main Menu" and shell.tutorial_restart_button.text == "Restart Tutorial", "The prompt offers both requested choices")
	check(shell.tutorial_menu_button.has_focus(), "Completion supports immediate keyboard selection")
	var dialog_rect := Rect2(Vector2(shell.tutorial_complete_dialog.position), Vector2(shell.tutorial_complete_dialog.size))
	check(root.get_visible_rect().encloses(dialog_rect), "Completion prompt fits inside the viewport")
	var position: Vector2 = level.player.global_position
	for frame in range(4):
		await physics_frame
	check(level.player.global_position == position, "Gameplay remains still while the prompt is open")
	key(shell, KEY_ESCAPE)
	key(shell, KEY_P)
	shell.pause_game()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	shell.tutorial_complete_dialog.window_input.emit(escape)
	shell.tutorial_complete_dialog.close_requested.emit()
	await settle()
	check(paused and shell.tutorial_complete_dialog.visible and not shell.pause_dialog.visible, "Escape, pause, and window close keep the completion choices open")
	var old_id: int = level.get_instance_id()
	shell.tutorial_restart_button.pressed.emit()
	check(not paused and shell.screen == shell.Screen.TUTORIAL and shell.world.get_instance_id() != old_id, "Restart Tutorial starts a fresh tutorial and unpauses")
	check(not shell.tutorial_complete_dialog.visible and not shell.dimmer.visible, "Restart dismisses the completion UI")
	check(not shell.world.finished and shell.world.current_instruction == "Use A/D or the left/right arrow keys to move.", "Restart restores the initial tutorial state")
	check(shell.world.player.position == Vector2(-872, 138) and not shell.world.player.controls_locked, "Restart restores the spawn and player controls")
	check(shell.world.player.initial_camera_zoom == Vector2.ONE * 0.57 and shell.world.player.show_grapple_cursor, "Restart preserves player settings")
	level = shell.world
	level.player.freeze = true
	level.player.global_position = level.finish_checkpoint.global_position
	level._physics_process(0.0)
	await settle()
	check(paused and shell.tutorial_complete_dialog.visible, "The restarted tutorial can be completed again")
	shell.tutorial_menu_button.pressed.emit()
	check(not paused and shell.screen == shell.Screen.MAIN_MENU and shell.world == null and shell.title_screen.visible, "Return to Main Menu removes the tutorial and unpauses")
	check(not shell.tutorial_complete_dialog.visible and not shell.dimmer.visible, "Returning to the menu dismisses the completion UI")
	shell.show_demo()
	check(not shell.world.finished and not shell.tutorial_complete_dialog.visible, "Reopening Tutorial starts without stale completion state")
	shell.free()
	await process_frame
	check(not paused, "Removing the shell leaves the game unpaused")

extends SceneTree

class HitReceiver:
	extends Node2D
	var hit_count := 0
	var impulse := 0.0
	var damage := 0

	func receive_jab_hit(_direction: Vector2, strength: float, amount: int) -> void:
		hit_count += 1
		impulse = strength
		damage = amount

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

func click(pressed: bool, button: MouseButton = MOUSE_BUTTON_RIGHT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func aim(player: RigidBody2D, world_point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = player.get_canvas_transform() * world_point
	event.global_position = event.position
	player.get_viewport().push_input(event, true)

func velocity(player: RigidBody2D) -> Vector2:
	# Impulses update the physics server before the node's next integrated state.
	return PhysicsServer2D.body_get_state(player.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_2d = World2D.new()
	root.add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	wall(world, Vector2(300, 0), Vector2(40, 1200))
	wall(world, Vector2(0, 350), Vector2(1200, 40))
	var player = load("res://scenes/player_ball.tscn").instantiate()
	player.gravity_scale = 0.0
	player.linear_damp = 0.0
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	for frame in range(3):
		await physics_frame
	await process_frame
	click(false)
	player._update_jab(0.0)
	check(player.get_node_or_null("JabMeter") == null, "The charge meter is removed from the player")
	player._update_speed_ui(0.0)
	check(player.player_launch_bar.value == 1.0, "The separate launch bar starts full and ready")

	aim(player, Vector2(300, 0))
	click(true, MOUSE_BUTTON_LEFT)
	player._update_grapple(player._is_grapple_pressed())
	player._update_jab(0.0)
	check(player.grapple_active and player.jab_active_remaining == 0.0 and velocity(player) == Vector2.ZERO, "Left click grapples without launching the player")
	click(false, MOUSE_BUTTON_LEFT)
	player._update_grapple(player._is_grapple_pressed())
	check(not player.grapple_active, "Releasing left click releases the grapple")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	Input.flush_buffered_events()
	check(not player._is_grapple_pressed(), "Space no longer activates the grapple")
	space = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = false
	Input.parse_input_event(space)
	Input.flush_buffered_events()
	player.grapple_active = true
	click(true)
	player._update_jab(0.0)
	check(player.jab_active_remaining > 0.0 and player.jab_area.monitoring and not player._is_grapple_pressed(), "Right click launches immediately without starting a grapple")
	var wall_launch_speed := -velocity(player).x
	check(wall_launch_speed > 1200.0 and wall_launch_speed < 1800.0 and is_zero_approx(velocity(player).y), "A wall launch immediately gives the distance-based outward speed")
	check(not player.grapple_active, "Launching releases an active grapple")
	check(is_equal_approx(player.jab_cooldown_remaining, 0.8), "Launch recharge lasts 0.8 seconds")
	player._update_speed_ui(0.0)
	check(player.player_launch_bar.value == 0.0 and player.player_speed_bar.value == 0.0, "Launching empties its own bar without changing the speed bar")
	player._update_jab(0.4)
	player._update_speed_ui(0.0)
	check(is_equal_approx(player.player_launch_bar.value, 0.5) and not player._can_start_jab_attack(), "The launch bar shows half recharge while launching is still blocked")
	player._update_jab(0.4)
	player._update_speed_ui(0.0)
	check(player.player_launch_bar.value == 1.0 and player._can_start_jab_attack(), "The launch and its bar become ready together after recharge")
	check(player.jab_active_remaining == 0.0 and player.jab_cooldown_remaining == 0.0, "Holding the button does not repeat attacks after the cooldown")
	click(false)
	player._update_jab(0.0)
	check(player.jab_active_remaining == 0.0 and is_equal_approx(velocity(player).x, -wall_launch_speed), "Mouse release does not fire another launch")

	player.linear_velocity = Vector2.ZERO
	aim(player, Vector2(0, 350))
	click(true)
	player._update_jab(0.0)
	var floor_launch_speed := -velocity(player).y
	check(floor_launch_speed > 1200.0 and floor_launch_speed < wall_launch_speed and is_zero_approx(velocity(player).x), "The farther floor hit gives a weaker upward launch than the closer wall")
	click(false)
	player._update_jab(0.2)
	click(true)
	player._update_jab(0.0)
	check(player.jab_active_remaining == 0.0 and is_equal_approx(velocity(player).y, -floor_launch_speed), "Clicks during cooldown cannot add another launch")
	click(false)
	player._update_jab(1.0)
	player.linear_velocity = Vector2.ZERO
	aim(player, Vector2(-600, 0))
	click(true)
	player._update_jab(0.0)
	check(is_equal_approx(player.jab_shape.shape.size.x, 420.0), "An instant attack retains the former maximum reach")
	check(velocity(player) == Vector2.ZERO, "A launch requires hitting a surface to recoil")
	var receiver := HitReceiver.new()
	receiver.position = Vector2(-200, 0)
	world.add_child(receiver)
	player._try_apply_jab_hit(receiver)
	player._try_apply_jab_hit(receiver)
	check(receiver.hit_count == 1 and receiver.impulse == 1350.0 and receiver.damage == 10, "Each target receives the former maximum impulse and damage once per attack")
	player.set_controls_locked(true)
	player._physics_process(0.0)
	player.set_controls_locked(false)
	player._update_jab(1.0)
	check(player.jab_active_remaining == 0.0, "A mouse button held across a control lock cannot launch on resume")
	click(false)
	player._update_jab(0.0)
	click(true)
	player._update_jab(0.0)
	check(player.jab_active_remaining > 0.0, "A fresh click after unlocking launches normally")
	click(false)
	player._update_jab(1.0)

	var distance_speeds: Array[float] = []
	for distance in [0.0, 105.0, 210.0, 315.0, 420.0]:
		player.linear_velocity = Vector2.ZERO
		player._apply_jab_world_recoil(Vector2.RIGHT, distance)
		distance_speeds.append(-velocity(player).x)
	var stronger_up_close := true
	for index in range(1, distance_speeds.size()):
		stronger_up_close = stronger_up_close and distance_speeds[index - 1] > distance_speeds[index]
	check(stronger_up_close and distance_speeds[0] == 1800.0 and distance_speeds[-1] == 1200.0, "Launches smoothly strengthen from maximum reach to surface contact")
	for incoming in [Vector2.ZERO, Vector2(1500, 500), Vector2(-800, -500)]:
		player.linear_velocity = incoming
		player._apply_jab_world_recoil(Vector2.RIGHT, 210.0)
		check(is_equal_approx(velocity(player).x, -distance_speeds[2]) and is_equal_approx(velocity(player).y, incoming.y), "Launch speed is consistent with incoming velocity %s and preserves sideways momentum" % incoming)
	player.mass = 2.0
	player.linear_velocity = Vector2(1500, 500)
	player._apply_jab_world_recoil(Vector2.RIGHT, 210.0)
	check(is_equal_approx(velocity(player).x, -distance_speeds[2]), "Player mass does not change launch speed")
	player.mass = 1.0
	player.linear_velocity = Vector2(-3200, 450)
	player._apply_jab_world_recoil(Vector2.RIGHT, 0.0)
	check(velocity(player) == Vector2(-3200, 450), "Launching preserves an already faster outward escape")
	player.linear_velocity = Vector2.ZERO
	var angled_direction := Vector2(3, 1).normalized()
	player._clamp_jab_length_to_world_hit(angled_direction, player.JAB_LENGTH)
	check(absf(velocity(player).dot(-angled_direction) - wall_launch_speed) < 0.01, "Angled aim gives the same launch strength from the same surface distance")

	check(player.player_speed_bar.value == 0.0, "The speed bar starts empty at rest")
	player.linear_velocity = Vector2(1680, 0)
	check(player._get_speed_ratio() < 0.55, "Ordinary top ground speed leaves plenty of headroom on the speedometer")
	player.linear_velocity = Vector2(960, 1280)
	player._update_speed_ui(1.0 / 60.0)
	check(player.player_speed_bar.value > 0.0 and player.player_speed_bar.value < 0.5, "The bar eases toward speed instead of snapping")
	player._update_speed_ui(2.0)
	check(absf(player.player_speed_bar.value - 0.5) < 0.001, "The bar uses total movement speed in any direction")
	player.take_damage(10)
	player._update_speed_ui(0.0)
	check(absf(player.player_speed_bar.value - 0.5) < 0.001, "Health changes do not alter the speed display")
	player.linear_velocity = Vector2(0, -4000)
	player._update_speed_ui(2.0)
	check(absf(player.player_speed_bar.value - 1.0) < 0.001, "High speeds fill the bar without overflowing")
	player.linear_velocity = Vector2.ZERO
	player._update_speed_ui(1.0 / 60.0)
	check(player.player_speed_bar.value > 0.0 and player.player_speed_bar.value < 1.0, "The bar drains smoothly when movement stops")
	player._update_speed_ui(2.0)
	check(player.player_speed_bar.value < 0.001, "The speed bar empties at rest")

	player.heart_beat_phase = 0.0
	player._update_heart_ui(0.1)
	var idle_phase: float = player.heart_beat_phase
	player.linear_velocity = Vector2(3200, 0)
	player.heart_beat_phase = 0.0
	player._update_heart_ui(0.1)
	check(player.heart_beat_phase > idle_phase * 3.0, "The heart pumps faster at high speed")
	player.linear_velocity = Vector2.ZERO
	var previous_phase: float = player.heart_beat_phase
	player._update_heart_ui(0.0)
	check(player.heart_beat_phase == previous_phase, "Changing speed preserves the heartbeat phase")
	check(idle_phase < 0.075, "The resting heart beats more slowly than before")

	# Compare complete thumps at the two extremes, before either next beat starts.
	var profiles: Array[PackedFloat32Array] = []
	var peak_heights: Array[float] = []
	for speed in [0.0, 3200.0]:
		player.linear_velocity = Vector2(speed, 0)
		player.heart_beat_phase = 0.0
		player.heart_thump_time = 0.0
		var profile := PackedFloat32Array()
		var peak_height := 0.0
		var strength: float = player.HEART_IDLE_SCALE_AMOUNT if speed == 0.0 else player.HEART_MAX_SCALE_AMOUNT
		for frame in range(36):
			player._update_heart_ui(0.01)
			var height: float = player.heart_texture_rect.scale.y - 1.0
			profile.append(height / strength)
			peak_height = maxf(peak_height, height)
		profiles.append(profile)
		peak_heights.append(peak_height)
	var matching_timing := true
	for frame in range(profiles[0].size()):
		matching_timing = matching_timing and absf(profiles[0][frame] - profiles[1][frame]) < 0.0001
	check(matching_timing, "Both thumps keep identical timing and duration at every speed")
	check(peak_heights[1] > peak_heights[0] * 3.0, "High-speed thumps expand much more violently")
	check(player.heart_texture_rect.scale.is_equal_approx(Vector2.ONE), "The heart settles between beats even at maximum frequency")

	# Simulate from above the old 1,050 px/s cap, far from the release zone.
	var previous_tuning = load("res://scenes/player_ball.tscn").instantiate()
	previous_tuning.gravity_scale = 0.0
	previous_tuning.linear_damp = 0.0
	previous_tuning.position = Vector2(-5000, -8000)
	previous_tuning.orb_grapple_pull_force = 27000.0
	previous_tuning.orb_grapple_speed_limit = 1680.0
	world.add_child(previous_tuning)
	previous_tuning.set_physics_process(false)
	previous_tuning.set_process(false)
	previous_tuning.linear_velocity = Vector2(1200, 0)
	previous_tuning.grapple_anchor = previous_tuning.global_position + Vector2(2000, 0)
	previous_tuning.grapple_length = 2000.0
	previous_tuning.grapple_active = true
	previous_tuning.grapple_targets_orb = true
	player.global_position = Vector2(-5000, -5000)
	player.linear_velocity = Vector2(1200, 0)
	player.grapple_anchor = player.global_position + Vector2(2000, 0)
	player.grapple_length = 2000.0
	player.grapple_active = true
	player.grapple_targets_orb = true
	for frame in range(12):
		player._apply_grapple_pull(1.0 / 60.0)
		previous_tuning._apply_grapple_pull(1.0 / 60.0)
		await physics_frame
	check(player.linear_velocity.x > 1050.0 and player.linear_velocity.x < previous_tuning.linear_velocity.x, "Orb grapples are a little slower than the previous tuning")
	player.grapple_anchor = player.global_position + Vector2(100, 0)
	var release_velocity: Vector2 = player.linear_velocity
	player._apply_grapple_pull(1.0 / 60.0)
	check(not player.grapple_active and player.linear_velocity == release_velocity, "Fast orb approaches still release automatically and preserve momentum")

	viewport.free()
	await process_frame
	print("PLAYER MOVEMENT: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

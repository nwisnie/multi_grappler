extends "res://scripts/player/ball.gd"
## Each player simulates their own ball; replicas only render synchronized state.

var network_position := Vector2.ZERO
var network_rotation := 0.0
var network_velocity := Vector2.ZERO
var network_grapple_active := false
var network_grapple_anchor := Vector2.ZERO
var spawn_position := Vector2.ZERO
var spawn_controls_pending := true
var respawn_pending := false
var snapshot_elapsed := 0.0
var nameplate: Node2D
var nameplate_panel: PanelContainer

func _ready() -> void:
	super._ready()
	# Players share terrain, but do not push locally simulated replicas around.
	collision_layer = 4
	collision_mask = 1
	var local := is_multiplayer_authority()
	camera.enabled = local
	player_ui_layer.visible = local
	freeze = not local
	if local:
		camera.make_current()
		set_controls_locked(true)
	else:
		set_physics_process(false)
	sprite.modulate = Color.from_hsv(fposmod(get_multiplayer_authority() * 0.23, 1.0), 0.35, 1.0)
	# A separate world transform keeps the name above the ball as its body rolls.
	nameplate = Node2D.new()
	nameplate.name = "Nameplate"
	nameplate.top_level = true
	nameplate.z_as_relative = false
	nameplate.z_index = 100
	add_child(nameplate)
	nameplate_panel = PanelContainer.new()
	nameplate_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color.WHITE
	background.border_color = Color.BLACK
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	background.content_margin_left = 8
	background.content_margin_right = 8
	background.content_margin_top = 3
	background.content_margin_bottom = 3
	nameplate_panel.add_theme_stylebox_override("panel", background)
	nameplate.add_child(nameplate_panel)
	var tag := Label.new()
	tag.text = "Host" if get_multiplayer_authority() == 1 else "Player %d" % get_multiplayer_authority()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 20)
	tag.add_theme_color_override("font_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 0)
	nameplate_panel.add_child(tag)
	_update_nameplate()

func _update_nameplate() -> void:
	nameplate.global_position = global_position + Vector2(-nameplate_panel.size.x * 0.5, -70.0 - nameplate_panel.size.y)

func _process(delta: float) -> void:
	if is_multiplayer_authority():
		super._process(delta)
		network_position = position
		network_rotation = rotation
		network_velocity = linear_velocity
		network_grapple_active = grapple_active
		network_grapple_anchor = grapple_anchor
		# Guests send snapshots only to the host. Its synchronizer distributes them,
		# so in-flight updates never reference a departed guest on another client.
		if not multiplayer.is_server():
			snapshot_elapsed += delta
			if snapshot_elapsed >= 1.0 / 30.0:
				snapshot_elapsed = 0.0
				_submit_state.rpc_id(1, network_position, network_rotation, network_velocity, network_grapple_active, network_grapple_anchor)
	else:
		var weight := 1.0 - exp(-20.0 * delta)
		if position.distance_to(network_position) > 500.0:
			position = network_position
		else:
			position = position.lerp(network_position, weight)
		rotation = lerp_angle(rotation, network_rotation, weight)
		linear_velocity = network_velocity
		_update_squash_and_stretch(delta)
		grapple_line.visible = network_grapple_active
		grapple_line.set_point_position(0, global_position)
		grapple_line.set_point_position(1, network_grapple_anchor)
	_update_nameplate()

@rpc("authority", "call_remote", "unreliable_ordered")
func _submit_state(location: Vector2, angle: float, speed: Vector2, grappling: bool, anchor: Vector2) -> void:
	if not multiplayer.is_server() or not location.is_finite() or not speed.is_finite() or not anchor.is_finite() or not is_finite(angle):
		return
	network_position = location
	network_rotation = angle
	network_velocity = speed
	network_grapple_active = grappling
	network_grapple_anchor = anchor

func _physics_process(delta: float) -> void:
	if spawn_controls_pending and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_key_pressed(KEY_SPACE):
		spawn_controls_pending = false
		set_controls_locked(false)
	if not Rect2(Vector2.ZERO, Vector2.ONE * LevelDocument.BOARD_SIZE).has_point(position):
		respawn_pending = true
	super._physics_process(delta)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not is_multiplayer_authority():
		return
	if respawn_pending:
		respawn_pending = false
		_release_grapple()
		state.transform = Transform2D(0.0, spawn_position)
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
	super._integrate_forces(state)

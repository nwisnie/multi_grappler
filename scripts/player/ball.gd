extends RigidBody2D

const MOVE_FORCE := 74000.0
const GROUND_REVERSE_FORCE_MULTIPLIER := 0.24
const AIR_CONTROL_FORCE := 2700.0
const AIR_REVERSE_FORCE_MULTIPLIER := 0.35
const AIR_FRICTION := 0.7
const MAX_GROUND_SPEED := 1680.0
const MAX_AIR_SPEED := 390.0
const SUPPORT_MIN_UP := 0.05
const CAMERA_FOLLOW_SPEED := 4.5
const CAMERA_LOOK_AHEAD := 80.0
const CAMERA_VERTICAL_OFFSET := -30.0
const CAMERA_BASE_ZOOM := Vector2(0.46, 0.46)
const CAMERA_MAX_ZOOM_OUT := Vector2(0.45, 0.45)
const CAMERA_ZOOM_SPEED := 3.5
const GRAPPLE_MAX_DISTANCE := 2200.0
const GrappleCursorScript := preload("res://scripts/grapple/grapple_cursor.gd")
const GrappleDirectionScript := preload("res://scripts/grapple/grapple_direction.gd")
const GrappleEffectScript := preload("res://scripts/grapple/grapple_effect.gd")
const SpeedBarScript := preload("res://scripts/ui/speed_bar.gd")
const GRAPPLE_VISUAL_SHOOT_SPEED := 10000.0
const GRAPPLE_MIN_LENGTH := 24.0
const GRAPPLE_PULL_FORCE := 12000.0
const GRAPPLE_PULL_SPEED_LIMIT := 720.0
const GRAPPLE_TETHER_BOUNCE := 0.18
const GRAPPLE_MAX_BOUNCE_SPEED := 160.0
const JAB_LENGTH := 420.0
const JAB_WIDTH := 76.0
const JAB_ACTIVE_TIME := 0.12
const JAB_COOLDOWN := 0.8
const JAB_IMPULSE := 1350.0
const JAB_DAMAGE := 10
const JAB_UPWARD_BIAS := 0.08
const JAB_START_OFFSET := 48.0
const JAB_WORLD_LAUNCH_MIN_SPEED := 1200.0
const JAB_WORLD_LAUNCH_MAX_SPEED := 1800.0
const MOVE_STRETCH_MAX := 0.16
const MOVE_STRETCH_SPEED := 1200.0
const COLLISION_SQUASH_MAX := 0.24
const COLLISION_SQUASH_SPEED := 900.0
const COLLISION_SQUASH_DECAY := 9.0
const SQUASH_STRETCH_RESPONSE := 14.0
const SQUASH_ROTATION_RESPONSE := 18.0
const CAMERA_SHAKE_DECAY := 18.0
const IDLE_BREATH_SPEED := 1.8
const IDLE_BREATH_SCALE_X := 0.025
const IDLE_BREATH_SCALE_Y := 0.035
const IDLE_BREATH_MAX_SPEED := 45.0
const SPRITE_UPRIGHT_ROTATION := 0.0
const JAB_MACE_TEXTURE := preload("res://assets/images/characters/weapons/attack_mace/attack_mace.png")
const JAB_MACE_SCALE := Vector2(0.075, 0.075)
const JAB_VISUAL_START_DISTANCE := 42.0
const JAB_VISUAL_OUT_TIME := 0.09
const JAB_VISUAL_RETURN_TIME := 0.11
const JAB_VISUAL_Z_INDEX := 30
const JAB_CHAIN_Z_INDEX := 5
const JAB_CHAIN_WIDTH := 7.0
const HEART_TEXTURE := preload("res://assets/ui/heart.png")
const HEART_UI_POSITION := Vector2(22.0, 20.0)
const HEART_UI_SIZE := Vector2(100.0, 150.0)
const HEART_BEAT_IDLE_SPEED := 0.6
const HEART_BEAT_MAX_SPEED := 2.5
const HEART_THUMP_DURATION := 0.16
const HEART_SECOND_THUMP_DELAY := 0.18
const HEART_IDLE_SCALE_AMOUNT := 0.08
const HEART_MAX_SCALE_AMOUNT := 0.27
const HEART_IDLE_ROTATION_AMOUNT := deg_to_rad(2.0)
const HEART_MAX_ROTATION_AMOUNT := deg_to_rad(7.0)
const PLAYER_METERS_OFFSET := Vector2(62.0, 44.0)
const PLAYER_METER_ROW_SPACING := 51.0
const PLAYER_SPEED_BAR_SIZE := Vector2(250.0, 26.0)
const PLAYER_SPEED_BAR_FILL_COLOR := Color(0.905882, 0.6, 0.623529, 0.96)
const PLAYER_LAUNCH_BAR_SIZE := Vector2(180.0, PLAYER_SPEED_BAR_SIZE.y)
const PLAYER_LAUNCH_BAR_FILL_COLOR := Color("9c8aac")
const SPEED_UI_FULL_SPEED := 3200.0
const SPEED_UI_RESPONSE := 8.0
const DAMAGE_IMMUNITY_TIME := 0.65

@onready var camera: Camera2D = $Camera2D
@onready var ground_probe: RayCast2D = $GroundProbe
@onready var grapple_line: Line2D = $GrappleLine
@onready var sprite: Sprite2D = $Sprite2D

var jab_area: Area2D
var jab_shape: CollisionShape2D
var jab_mace_sprite: Sprite2D
var jab_chain_line: Line2D
var jab_visual_tween: Tween
var jab_visual_start_position := Vector2.ZERO
var player_ui_layer: CanvasLayer
var heart_texture_rect: TextureRect
var player_speed_bar: SpeedBarScript
var player_launch_bar: SpeedBarScript
var grapple_cursor: Node2D
var grapple_direction: Node2D
var grapple_target_available := false
var grapple_target_position := Vector2.ZERO
var highlighted_grapple_target: Node
var grapple_effect: Node2D
var grapple_launch_position := Vector2.ZERO
var grapple_visual_time := 0.0
var grapple_visual_duration := 0.1
var grapple_contact_normal := Vector2.UP
var grapple_hits_terrain := false
var grapple_retracting := false
var grapple_retract_origin := Vector2.ZERO
var grapple_retract_time := 0.0
var grapple_retract_duration := 0.1
var grapple_targets_orb := false

@export var initial_camera_zoom: Vector2 = CAMERA_BASE_ZOOM
@export var speed_zoom_out: Vector2 = CAMERA_MAX_ZOOM_OUT
@export var show_grapple_cursor := false
@export var show_grapple_direction := true:
	set(enabled):
		if show_grapple_direction != enabled:
			show_grapple_direction = enabled
			_update_grapple_direction()
@export_range(1, 1000, 1) var max_health: int = 20
@export_group("Orb Grapple")
@export_range(24.0, 200.0, 1.0) var orb_grapple_release_distance := 88.0
@export_range(12000.0, 40000.0, 500.0) var orb_grapple_pull_force := 22500.0
@export_range(720.0, 2400.0, 10.0) var orb_grapple_speed_limit := 1440.0
@export_range(0.0, 24.0, 0.5) var orb_grapple_steering := 12.0
@export_group("")

var current_health: int = 20
var damage_immunity_remaining := 0.0
var grapple_active: bool = false
var grapple_anchor: Vector2 = Vector2.ZERO
var grapple_length: float = 0.0
var was_launch_pressed: bool = false
var was_grapple_pressed: bool = false
var jab_cooldown_remaining: float = 0.0
var jab_active_remaining: float = 0.0
var jab_hit_bodies: Array[Node] = []
var has_support_contact: bool = false
var support_normal: Vector2 = Vector2.UP
var interaction_zoom_offset: Vector2 = Vector2.ZERO
var dialog_camera_offset: Vector2 = Vector2.ZERO
var controls_locked: bool = false
var sprite_base_scale: Vector2 = Vector2.ONE
var collision_squash_amount: float = 0.0
var collision_squash_normal: Vector2 = Vector2.UP
var previous_contact_count: int = 0
var camera_shake_amount: float = 0.0
var camera_zoom_preview := false
var idle_breath_time: float = 0.0
var heart_beat_phase: float = 0.0
var heart_thump_time: float = 0.0

func _scaled_force(base_force: float, input_direction: float, current_speed: float, reverse_multiplier: float) -> float:
	if input_direction == 0.0:
		return 0.0
	if absf(current_speed) > 0.1 and signf(current_speed) != signf(input_direction):
		return base_force * reverse_multiplier
	return base_force

func _ready() -> void:
	max_health = maxi(max_health, 1)
	current_health = max_health
	sprite_base_scale = sprite.scale
	sprite.top_level = true
	sprite.z_index = z_index
	reset_spawn_orientation()
	ground_probe.exclude_parent = true
	ground_probe.enabled = true
	camera.top_level = true
	camera.global_position = global_position + Vector2(0.0, CAMERA_VERTICAL_OFFSET)
	camera.zoom = initial_camera_zoom
	grapple_line.top_level = true
	grapple_line.visible = false
	grapple_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	grapple_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	grapple_effect = GrappleEffectScript.new()
	grapple_effect.name = "GrappleEffect"
	grapple_effect.top_level = true
	grapple_effect.z_index = 15
	grapple_effect.visible = false
	add_child(grapple_effect)
	_setup_jab_nodes()
	_setup_player_ui()
	grapple_cursor = GrappleCursorScript.new()
	grapple_cursor.name = "GrappleCursor"
	player_ui_layer.add_child(grapple_cursor)
	grapple_direction = GrappleDirectionScript.new()
	grapple_direction.name = "GrappleDirection"
	player_ui_layer.add_child(grapple_direction)

func reset_spawn_orientation() -> void:
	rotation = 0.0
	angular_velocity = 0.0
	if sprite != null:
		sprite.global_rotation = SPRITE_UPRIGHT_ROTATION

func _exit_tree() -> void:
	_set_highlighted_grapple_target(null)

func _process(delta: float) -> void:
	_update_squash_and_stretch(delta)
	_update_jab_visual_line()
	_update_speed_ui(delta)
	_update_heart_ui(delta)
	# Resolve the current mouse ray every rendered frame, with no aim smoothing.
	_refresh_grapple_target()
	_update_grapple_cursor()
	_update_grapple_direction()
	_update_grapple_visuals(delta)

func _physics_process(delta: float) -> void:
	_refresh_grapple_target()
	damage_immunity_remaining = maxf(damage_immunity_remaining - delta, 0.0)
	if controls_locked:
		_clear_control_input_state()
		_update_camera(delta)
		return

	var move_direction: float = _get_move_direction()
	var is_grapple_pressed: bool = _is_grapple_pressed()
	_update_grapple(is_grapple_pressed)

	if has_support_contact:
		var floor_normal: Vector2 = support_normal
		var floor_tangent: Vector2 = Vector2(floor_normal.y, -floor_normal.x).normalized()
		if floor_tangent.x < 0.0:
			floor_tangent = -floor_tangent

		var tangent_speed: float = linear_velocity.dot(floor_tangent)
		if move_direction != 0.0 and (absf(tangent_speed) < MAX_GROUND_SPEED or signf(tangent_speed) != signf(move_direction)):
			var ground_force: float = _scaled_force(MOVE_FORCE, move_direction, tangent_speed, GROUND_REVERSE_FORCE_MULTIPLIER)
			apply_central_force(floor_tangent * move_direction * ground_force)
	else:
		if move_direction != 0.0 and (absf(linear_velocity.x) < MAX_AIR_SPEED or signf(linear_velocity.x) != signf(move_direction)):
			var air_force: float = _scaled_force(AIR_CONTROL_FORCE, move_direction, linear_velocity.x, AIR_REVERSE_FORCE_MULTIPLIER)
			apply_central_force(Vector2(move_direction * air_force, 0.0))
		linear_velocity.x = move_toward(linear_velocity.x, 0.0, AIR_FRICTION)

	_apply_grapple_pull(delta)

	_update_camera(delta)
	_update_jab(delta)

func _apply_grapple_pull(delta: float) -> void:
	if not grapple_active:
		return
	var pull_direction := grapple_anchor - global_position
	if grapple_targets_orb:
		# Include this tick's travel so fast passes cannot skip the release zone.
		var closest := Geometry2D.get_closest_point_to_segment(grapple_anchor, global_position, global_position + linear_velocity * delta)
		if closest.distance_to(grapple_anchor) <= orb_grapple_release_distance:
			_release_grapple()
			return
	if pull_direction.length_squared() <= 1.0:
		return
	var pull_normal := pull_direction.normalized()
	var pull_speed := linear_velocity.dot(pull_normal)
	grapple_length = maxf(pull_direction.length(), GRAPPLE_MIN_LENGTH)
	var pull_force := GRAPPLE_PULL_FORCE
	var speed_limit := GRAPPLE_PULL_SPEED_LIMIT
	if grapple_targets_orb:
		# Remove sideways drift smoothly, preserving forward momentum on release.
		var sideways_velocity := linear_velocity - pull_normal * pull_speed
		linear_velocity -= sideways_velocity * (1.0 - exp(-orb_grapple_steering * delta))
		pull_force = orb_grapple_pull_force
		speed_limit = orb_grapple_speed_limit
	if pull_speed < speed_limit:
		apply_central_force(pull_normal * pull_force)

func set_controls_locked(locked: bool) -> void:
	controls_locked = locked
	if locked:
		_clear_control_input_state()

func take_damage(amount: int = 1) -> bool:
	if amount <= 0 or current_health <= 0 or damage_immunity_remaining > 0.0:
		return false
	current_health = maxi(current_health - amount, 0)
	damage_immunity_remaining = DAMAGE_IMMUNITY_TIME
	return true

func set_max_health(value: int) -> void:
	var previous_max := max_health
	max_health = maxi(value, 1)
	current_health = clampi(current_health + max_health - previous_max, 0, max_health)

func set_visual_z_index(value: int) -> void:
	z_index = value
	sprite.z_index = value

func set_visual_visible(value: bool) -> void:
	visible = value
	sprite.visible = value

func shake_camera(amount: float) -> void:
	camera_shake_amount = maxf(camera_shake_amount, amount)

func _update_squash_and_stretch(delta: float) -> void:
	sprite.global_position = global_position

	idle_breath_time += delta * IDLE_BREATH_SPEED
	var movement_speed: float = linear_velocity.length()
	var move_stretch: float = clampf(movement_speed / MOVE_STRETCH_SPEED, 0.0, 1.0) * MOVE_STRETCH_MAX
	var impact_squash: float = collision_squash_amount
	var target_rotation: float = SPRITE_UPRIGHT_ROTATION
	if impact_squash > move_stretch * 0.75:
		var impact_tangent := Vector2(collision_squash_normal.y, -collision_squash_normal.x).normalized()
		target_rotation = SPRITE_UPRIGHT_ROTATION + _upright_axis_angle(impact_tangent.angle())
	elif movement_speed > 8.0:
		target_rotation = SPRITE_UPRIGHT_ROTATION + _upright_axis_angle(linear_velocity.angle())

	var idle_ratio := 1.0 - clampf(movement_speed / IDLE_BREATH_MAX_SPEED, 0.0, 1.0)
	var breath := (sin(idle_breath_time) + 1.0) * 0.5 * idle_ratio
	var target_scale := Vector2(
		sprite_base_scale.x * (1.0 + move_stretch + impact_squash + IDLE_BREATH_SCALE_X * breath),
		sprite_base_scale.y * (1.0 - move_stretch * 0.65 - impact_squash - IDLE_BREATH_SCALE_Y * breath)
	)
	var response_weight: float = 1.0 - exp(-SQUASH_STRETCH_RESPONSE * delta)
	sprite.scale = sprite.scale.lerp(target_scale, response_weight)
	var rotation_weight: float = 1.0 - exp(-SQUASH_ROTATION_RESPONSE * delta)
	sprite.global_rotation = lerp_angle(sprite.global_rotation, target_rotation, rotation_weight)
	collision_squash_amount = move_toward(collision_squash_amount, 0.0, COLLISION_SQUASH_DECAY * delta)

func _upright_axis_angle(angle: float) -> float:
	var normalized_angle := wrapf(angle, -PI, PI)
	if normalized_angle > PI * 0.5:
		normalized_angle -= PI
	elif normalized_angle < -PI * 0.5:
		normalized_angle += PI
	return normalized_angle

func _clear_control_input_state() -> void:
	was_launch_pressed = _is_launch_pressed()
	was_grapple_pressed = _is_grapple_pressed()
	if grapple_active:
		_release_grapple()
	if jab_active_remaining > 0.0:
		jab_active_remaining = 0.0
		_end_jab_attack()

func set_camera_zoom(value: float, preview: bool = false) -> void:
	initial_camera_zoom = Vector2.ONE * value
	camera_zoom_preview = preview
	if is_instance_valid(camera):
		camera.zoom = _camera_zoom_target()
		# Paused players do not run their normal camera update.
		camera.force_update_scroll()

func _camera_zoom_target() -> Vector2:
	if camera_zoom_preview:
		return initial_camera_zoom
	var speed_ratio := clampf(linear_velocity.length() / (MAX_GROUND_SPEED * 1.35), 0.0, 1.0)
	# A wider user setting must not zoom back in as the player gains speed.
	var speed_target := speed_zoom_out.min(initial_camera_zoom)
	return initial_camera_zoom.lerp(speed_target, speed_ratio) + interaction_zoom_offset

func _update_camera(delta: float) -> void:
	var look_ahead: Vector2 = Vector2(
		clampf(linear_velocity.x / MAX_GROUND_SPEED, -1.0, 1.0) * CAMERA_LOOK_AHEAD,
		CAMERA_VERTICAL_OFFSET
	) + dialog_camera_offset
	var camera_target: Vector2 = global_position + look_ahead
	if camera_shake_amount > 0.01:
		camera_target += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * camera_shake_amount
		camera_shake_amount = move_toward(camera_shake_amount, 0.0, CAMERA_SHAKE_DECAY * delta)
	var follow_weight: float = 1.0 - exp(-CAMERA_FOLLOW_SPEED * delta)
	camera.global_position = camera.global_position.lerp(camera_target, follow_weight)

	var zoom_target := _camera_zoom_target()
	var zoom_weight: float = 1.0 - exp(-CAMERA_ZOOM_SPEED * delta)
	camera.zoom = camera.zoom.lerp(zoom_target, zoom_weight)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	has_support_contact = false
	support_normal = Vector2.UP

	var contact_count: int = state.get_contact_count()
	if contact_count > 0:
		if contact_count > previous_contact_count:
			var impact_amount: float = clampf(state.linear_velocity.length() / COLLISION_SQUASH_SPEED, 0.0, COLLISION_SQUASH_MAX)
			collision_squash_amount = maxf(collision_squash_amount, impact_amount)
			collision_squash_normal = state.transform.basis_xform(state.get_contact_local_normal(0)).normalized()
		var normal_sum: Vector2 = Vector2.ZERO
		var support_contacts: int = 0
		for i in range(contact_count):
			var contact_normal: Vector2 = state.get_contact_local_normal(i)
			if contact_normal.y <= -SUPPORT_MIN_UP:
				normal_sum += contact_normal
				support_contacts += 1

		if support_contacts > 0:
			has_support_contact = true
			support_normal = normal_sum.normalized()
	previous_contact_count = contact_count

	if not grapple_active:
		return

	var offset: Vector2 = state.transform.origin - grapple_anchor
	var distance_to_anchor: float = offset.length()
	if distance_to_anchor <= 0.001 or distance_to_anchor <= grapple_length:
		return

	var rope_direction: Vector2 = offset / distance_to_anchor
	var radial_speed: float = state.linear_velocity.dot(rope_direction)
	if radial_speed <= 0.0:
		return

	var tangential_velocity: Vector2 = state.linear_velocity - rope_direction * radial_speed
	var bounce_speed: float = minf(radial_speed * GRAPPLE_TETHER_BOUNCE, GRAPPLE_MAX_BOUNCE_SPEED)
	state.linear_velocity = tangential_velocity - rope_direction * bounce_speed


func _setup_jab_nodes() -> void:
	jab_area = Area2D.new()
	jab_area.name = "JabArea"
	jab_area.top_level = true
	jab_area.monitoring = false
	jab_area.monitorable = false
	jab_area.collision_layer = 0
	jab_area.collision_mask = 0xFFFFFFFF
	jab_area.body_entered.connect(_on_jab_body_entered)
	jab_area.area_entered.connect(_on_jab_area_entered)
	add_child(jab_area)

	var rectangle_shape := RectangleShape2D.new()
	rectangle_shape.size = Vector2(JAB_LENGTH, JAB_WIDTH)

	jab_shape = CollisionShape2D.new()
	jab_shape.name = "CollisionShape2D"
	jab_shape.shape = rectangle_shape
	jab_shape.disabled = true
	jab_area.add_child(jab_shape)

	jab_chain_line = Line2D.new()
	jab_chain_line.name = "JabChainLine"
	jab_chain_line.top_level = true
	jab_chain_line.z_index = JAB_CHAIN_Z_INDEX
	jab_chain_line.width = JAB_CHAIN_WIDTH
	jab_chain_line.default_color = Color(0.0, 0.0, 0.0, 1.0)
	jab_chain_line.visible = false
	add_child(jab_chain_line)

	jab_mace_sprite = Sprite2D.new()
	jab_mace_sprite.name = "JabMace"
	jab_mace_sprite.top_level = true
	jab_mace_sprite.z_index = JAB_VISUAL_Z_INDEX
	jab_mace_sprite.texture = JAB_MACE_TEXTURE
	jab_mace_sprite.scale = JAB_MACE_SCALE
	jab_mace_sprite.visible = false
	add_child(jab_mace_sprite)

func _setup_player_ui() -> void:
	player_ui_layer = CanvasLayer.new()
	player_ui_layer.name = "PlayerUILayer"
	player_ui_layer.layer = 20
	add_child(player_ui_layer)

	heart_texture_rect = TextureRect.new()
	heart_texture_rect.name = "Heart"
	heart_texture_rect.texture = HEART_TEXTURE
	heart_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart_texture_rect.position = HEART_UI_POSITION
	heart_texture_rect.size = HEART_UI_SIZE
	heart_texture_rect.pivot_offset = HEART_UI_SIZE * 0.5
	heart_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_ui_layer.add_child(heart_texture_rect)

	player_speed_bar = SpeedBarScript.new()
	player_speed_bar.name = "PlayerSpeedBar"
	player_speed_bar.title = "SPEED"
	player_speed_bar.fill_color = PLAYER_SPEED_BAR_FILL_COLOR
	player_speed_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_speed_bar.position = HEART_UI_POSITION + PLAYER_METERS_OFFSET
	player_speed_bar.size = PLAYER_SPEED_BAR_SIZE
	player_speed_bar.z_index = -1
	player_ui_layer.add_child(player_speed_bar)

	player_launch_bar = SpeedBarScript.new()
	player_launch_bar.name = "PlayerLaunchBar"
	player_launch_bar.title = "LAUNCH"
	player_launch_bar.fill_color = PLAYER_LAUNCH_BAR_FILL_COLOR
	player_launch_bar.background_color = Color(0.19, 0.15, 0.22, 0.96)
	player_launch_bar.show_ticks = false
	player_launch_bar.value = 1.0
	player_launch_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_launch_bar.position = player_speed_bar.position + Vector2(0.0, PLAYER_METER_ROW_SPACING)
	player_launch_bar.size = PLAYER_LAUNCH_BAR_SIZE
	player_launch_bar.z_index = -1
	player_ui_layer.add_child(player_launch_bar)

func _get_speed_ratio() -> float:
	return clampf(linear_velocity.length() / SPEED_UI_FULL_SPEED, 0.0, 1.0)

func _update_speed_ui(delta: float) -> void:
	if player_speed_bar != null:
		player_speed_bar.value = lerpf(player_speed_bar.value, _get_speed_ratio(), 1.0 - exp(-SPEED_UI_RESPONSE * delta))
	if player_launch_bar != null:
		player_launch_bar.value = 1.0 - clampf(jab_cooldown_remaining / JAB_COOLDOWN, 0.0, 1.0)

func _update_heart_ui(delta: float) -> void:
	if heart_texture_rect == null:
		return

	var speed_ratio := _get_speed_ratio()
	var beat_speed := lerpf(HEART_BEAT_IDLE_SPEED, HEART_BEAT_MAX_SPEED, speed_ratio)
	heart_thump_time += delta
	heart_beat_phase += delta * beat_speed
	if heart_beat_phase >= 1.0:
		heart_beat_phase = fmod(heart_beat_phase, 1.0)
		heart_thump_time = heart_beat_phase / beat_speed
	# Speed changes the gap between beats, while each thump runs in real seconds.
	var primary_pulse := _heart_pulse(heart_thump_time)
	var secondary_pulse := _heart_pulse(heart_thump_time - HEART_SECOND_THUMP_DELAY) * 0.55
	var pulse := maxf(primary_pulse, secondary_pulse)
	var squash := pulse * lerpf(HEART_IDLE_SCALE_AMOUNT, HEART_MAX_SCALE_AMOUNT, speed_ratio)
	heart_texture_rect.scale = Vector2(1.0 + squash * 0.55, 1.0 + squash)
	var rotation_amount := lerpf(HEART_IDLE_ROTATION_AMOUNT, HEART_MAX_ROTATION_AMOUNT, speed_ratio)
	heart_texture_rect.rotation = sin(heart_thump_time / HEART_THUMP_DURATION * TAU) * rotation_amount * pulse
	heart_texture_rect.position = HEART_UI_POSITION + Vector2(0.0, -pulse * lerpf(0.5, 4.0, speed_ratio))

func _heart_pulse(elapsed: float) -> float:
	if elapsed < 0.0 or elapsed >= HEART_THUMP_DURATION:
		return 0.0
	var normalized := elapsed / HEART_THUMP_DURATION
	return sin(normalized * PI)

func _update_jab(delta: float) -> void:
	var launch_pressed := _is_launch_pressed()

	if jab_cooldown_remaining > 0.0:
		jab_cooldown_remaining = maxf(jab_cooldown_remaining - delta, 0.0)

	if jab_active_remaining > 0.0:
		jab_active_remaining = maxf(jab_active_remaining - delta, 0.0)
		if jab_active_remaining <= 0.0:
			_end_jab_attack()

	if launch_pressed and not was_launch_pressed and _can_start_jab_attack():
		_start_jab_attack()

	was_launch_pressed = launch_pressed

func _can_start_jab_attack() -> bool:
	return jab_cooldown_remaining <= 0.0 and jab_active_remaining <= 0.0

func _start_jab_attack() -> void:
	_release_grapple()
	jab_cooldown_remaining = JAB_COOLDOWN
	jab_active_remaining = JAB_ACTIVE_TIME
	jab_hit_bodies.clear()
	_position_jab(JAB_LENGTH)
	jab_shape.disabled = false
	jab_area.monitoring = true
	call_deferred("_check_current_jab_overlaps")

func _position_jab(jab_length: float) -> void:
	var direction := get_global_mouse_position() - global_position
	if direction.length_squared() < 1.0:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	jab_length = _clamp_jab_length_to_world_hit(direction, jab_length)
	var center := global_position + direction * (JAB_START_OFFSET + jab_length * 0.5)
	var angle := direction.angle()

	var rectangle_shape := jab_shape.shape as RectangleShape2D
	rectangle_shape.size = Vector2(jab_length, JAB_WIDTH)
	jab_area.global_position = center
	jab_area.global_rotation = angle

	_animate_jab_visual(direction, jab_length, angle)

func _animate_jab_visual(direction: Vector2, jab_length: float, angle: float) -> void:
	if jab_visual_tween != null:
		jab_visual_tween.kill()

	jab_visual_start_position = global_position + direction * JAB_VISUAL_START_DISTANCE
	var end_position := global_position + direction * (JAB_START_OFFSET + jab_length)
	jab_mace_sprite.global_position = jab_visual_start_position
	jab_mace_sprite.global_rotation = angle
	jab_mace_sprite.visible = true
	jab_chain_line.visible = true
	_update_jab_visual_line()

	jab_visual_tween = create_tween()
	jab_visual_tween.tween_property(jab_mace_sprite, "global_position", end_position, JAB_VISUAL_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _clamp_jab_length_to_world_hit(direction: Vector2, jab_length: float) -> float:
	var space_state := get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, global_position + direction * (JAB_START_OFFSET + jab_length))
	query.exclude = [self]
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return jab_length

	var hit_position := result.get("position", global_position + direction * (JAB_START_OFFSET + jab_length)) as Vector2
	var hit_distance := maxf(global_position.distance_to(hit_position) - JAB_START_OFFSET, 0.0)
	if _is_jab_world_recoil_collider(result.get("collider")):
		var hit_normal := (result.get("normal", -direction) as Vector2).normalized()
		var surface_distance := maxf((global_position - hit_position).dot(hit_normal) - LevelDocument.PLAYER_RADIUS, 0.0)
		_apply_jab_world_recoil(direction, surface_distance)
	return minf(jab_length, hit_distance)

func _is_jab_world_recoil_collider(collider: Variant) -> bool:
	var collider_node := collider as Node
	if collider_node == null:
		return false
	if collider_node.has_method("receive_jab_hit"):
		return false
	var parent := collider_node.get_parent()
	return parent == null or not parent.has_method("receive_jab_hit")

func _apply_jab_world_recoil(hit_direction: Vector2, surface_distance: float) -> void:
	if hit_direction.length_squared() <= 0.001:
		return
	var launch_direction := -hit_direction.normalized()
	var proximity := 1.0 - smoothstep(0.0, JAB_LENGTH, surface_distance)
	var launch_speed := lerpf(JAB_WORLD_LAUNCH_MIN_SPEED, JAB_WORLD_LAUNCH_MAX_SPEED, proximity)
	var outward_speed := linear_velocity.dot(launch_direction)
	# Cancel closing velocity, preserve sideways motion and already-faster escapes.
	linear_velocity += launch_direction * maxf(launch_speed - outward_speed, 0.0)

func _update_jab_visual_line() -> void:
	if jab_chain_line == null or jab_mace_sprite == null or not jab_chain_line.visible:
		return
	jab_chain_line.global_position = Vector2.ZERO
	jab_chain_line.points = PackedVector2Array([global_position, jab_mace_sprite.global_position])

func _check_current_jab_overlaps() -> void:
	if jab_active_remaining <= 0.0:
		return
	for body in jab_area.get_overlapping_bodies():
		_on_jab_body_entered(body)
	for area in jab_area.get_overlapping_areas():
		_on_jab_area_entered(area)

func _on_jab_body_entered(body: Node) -> void:
	_try_apply_jab_hit(body)

func _on_jab_area_entered(area: Area2D) -> void:
	_try_apply_jab_hit(area)

func _try_apply_jab_hit(target: Node) -> void:
	if jab_active_remaining <= 0.0 or target == self:
		return

	var receiver := target
	if not receiver.has_method("receive_jab_hit") and receiver.get_parent() != null:
		receiver = receiver.get_parent()
	if receiver == self or not receiver.has_method("receive_jab_hit") and not (receiver is RigidBody2D):
		return
	if jab_hit_bodies.has(receiver):
		return

	jab_hit_bodies.append(receiver)
	var receiver_position := global_position + Vector2.RIGHT.rotated(jab_area.global_rotation)
	if receiver is Node2D:
		receiver_position = (receiver as Node2D).global_position
	var direction := receiver_position - global_position
	if direction.length_squared() < 1.0:
		direction = Vector2.RIGHT.rotated(jab_area.global_rotation)
	direction = Vector2(direction.x, direction.y - JAB_UPWARD_BIAS * direction.length()).normalized()
	if receiver.has_method("receive_jab_hit"):
		receiver.receive_jab_hit(direction, JAB_IMPULSE, JAB_DAMAGE)
	elif receiver is RigidBody2D:
		(receiver as RigidBody2D).apply_central_impulse(direction * JAB_IMPULSE)

func _end_jab_attack() -> void:
	jab_area.monitoring = false
	jab_shape.disabled = true
	if jab_visual_tween != null:
		jab_visual_tween.kill()
	if jab_mace_sprite != null and jab_chain_line != null and jab_mace_sprite.visible:
		jab_visual_tween = create_tween()
		jab_visual_tween.tween_property(jab_mace_sprite, "global_position", jab_visual_start_position, JAB_VISUAL_RETURN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		jab_visual_tween.finished.connect(_hide_jab_visual)
	jab_hit_bodies.clear()

func _hide_jab_visual() -> void:
	if jab_mace_sprite != null:
		jab_mace_sprite.visible = false
	if jab_chain_line != null:
		jab_chain_line.visible = false

func _get_move_direction() -> float:
	return clampf(
		Input.get_axis("ui_left", "ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		-1.0,
		1.0
	)

func _is_grapple_pressed() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _is_launch_pressed() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

func _update_grapple(is_grapple_pressed: bool) -> void:
	if is_grapple_pressed and not was_grapple_pressed:
		grapple_active = _try_start_grapple()

	if not is_grapple_pressed and was_grapple_pressed:
		_release_grapple()

	was_grapple_pressed = is_grapple_pressed

func _update_grapple_visuals(delta: float) -> void:
	if not is_visible_in_tree():
		grapple_line.visible = false
		grapple_effect.visible = false
		grapple_retracting = false
		return
	if not grapple_active:
		grapple_effect.visible = false
		if grapple_retracting:
			grapple_retract_time = minf(grapple_retract_time + delta, grapple_retract_duration)
			var progress := grapple_retract_time / grapple_retract_duration
			var tip := grapple_retract_origin.lerp(global_position, progress * progress)
			grapple_line.set_point_position(0, global_position)
			grapple_line.set_point_position(1, tip)
			grapple_retracting = progress < 1.0
		grapple_line.visible = grapple_retracting
		return
	grapple_visual_time = minf(grapple_visual_time + delta, grapple_visual_duration)
	var progress := clampf(grapple_visual_time / grapple_visual_duration, 0.0, 1.0)
	var extension := 1.0 - pow(1.0 - progress, 2.0)
	var tip := grapple_launch_position.lerp(grapple_anchor, extension)
	var direction := (grapple_anchor - global_position).normalized()
	grapple_line.visible = true
	grapple_line.set_point_position(0, global_position)
	grapple_line.set_point_position(1, tip)
	grapple_effect.update_visual(tip, direction, grapple_contact_normal, progress >= 1.0, grapple_hits_terrain, delta)

func _find_grapple_target() -> Dictionary:
	var origin: Vector2 = global_position
	var mouse_position: Vector2 = get_global_mouse_position()
	var ray_direction: Vector2 = mouse_position - origin
	if ray_direction.length_squared() < 1.0:
		return {}

	var ray_end: Vector2 = origin + ray_direction.normalized() * GRAPPLE_MAX_DISTANCE
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, ray_end)
	query.exclude = [self]
	# Terrain uses layer 1; pass-through grapple orbs use layer 2.
	query.collision_mask = 3
	query.collide_with_areas = true
	var space := get_world_2d().direct_space_state
	var result := space.intersect_ray(query)
	var collider := result.get("collider") as Node
	if is_instance_valid(collider) and collider.has_method("get_grapple_anchor_position"):
		var anchor: Vector2 = collider.get_grapple_anchor_position()
		# The larger aim area selects the orb, but the rope attaches to its center.
		# Check the center separately so the aim halo cannot reach through walls
		# or extend the maximum grapple distance.
		var sight_query := PhysicsRayQueryParameters2D.create(origin, anchor, 1, [get_rid()])
		if origin.distance_to(anchor) > GRAPPLE_MAX_DISTANCE or not space.intersect_ray(sight_query).is_empty():
			query.collide_with_areas = false
			return space.intersect_ray(query)
		result["position"] = anchor
	return result

func _refresh_grapple_target() -> void:
	grapple_target_available = false
	if controls_locked:
		_set_highlighted_grapple_target(null)
		return
	if grapple_active:
		return
	var result := _find_grapple_target()
	_set_highlighted_grapple_target(result.get("collider") as Node)
	if not result.is_empty():
		grapple_target_available = true
		grapple_target_position = result["position"] as Vector2

func _set_highlighted_grapple_target(target: Node) -> void:
	if is_instance_valid(highlighted_grapple_target) and highlighted_grapple_target == target:
		return
	if is_instance_valid(highlighted_grapple_target) and highlighted_grapple_target.has_method("set_grapple_targeted"):
		highlighted_grapple_target.set_grapple_targeted(self, false)
	highlighted_grapple_target = target
	if is_instance_valid(target) and target.has_method("set_grapple_targeted"):
		target.set_grapple_targeted(self, true)

func _update_grapple_cursor() -> void:
	if grapple_cursor == null:
		return
	var target := grapple_anchor if grapple_active else grapple_target_position
	var orb_selected := is_instance_valid(highlighted_grapple_target) and highlighted_grapple_target.has_method("get_grapple_ring_radius")
	if orb_selected:
		target = highlighted_grapple_target.get_grapple_anchor_position()
		grapple_cursor.ring_radius = highlighted_grapple_target.get_grapple_ring_radius() * get_canvas_transform().x.length()
		grapple_cursor.attached_scale = 0.9
	else:
		grapple_cursor.ring_radius = 21.0
		grapple_cursor.attached_scale = grapple_cursor.ATTACHED_SCALE
	grapple_cursor.show_glow = not orb_selected
	var available := (show_grapple_cursor or orb_selected) and (grapple_active or grapple_target_available) and not controls_locked and is_visible_in_tree()
	grapple_cursor.set_target(get_canvas_transform() * target, available, grapple_active)

func _update_grapple_direction() -> void:
	if grapple_direction == null:
		return
	if not show_grapple_direction:
		grapple_direction.hide()
		return
	var canvas := get_canvas_transform()
	# Aiming still has a direction when no surface is in range (often overhead).
	# Valid orb targets keep their snapped center, matching the actual launch.
	var target := grapple_target_position if grapple_target_available else get_global_mouse_position()
	var available := not grapple_active and not controls_locked and is_visible_in_tree()
	var screen_radius := LevelDocument.PLAYER_RADIUS * canvas.x.length()
	grapple_direction.set_aim(canvas * global_position, canvas * target, available, screen_radius, grapple_target_available)

func _try_start_grapple() -> bool:
	var result := _find_grapple_target()
	if result.is_empty():
		return false

	_set_highlighted_grapple_target(result.get("collider") as Node)
	grapple_anchor = result["position"] as Vector2
	grapple_length = maxf(global_position.distance_to(grapple_anchor), GRAPPLE_MIN_LENGTH)
	grapple_launch_position = global_position
	grapple_retracting = false
	grapple_visual_time = 0.0
	grapple_visual_duration = clampf(grapple_length / GRAPPLE_VISUAL_SHOOT_SPEED, 0.08, 0.22)
	grapple_contact_normal = result.get("normal", Vector2.UP) as Vector2
	grapple_hits_terrain = not highlighted_grapple_target.has_method("get_grapple_anchor_position")
	grapple_targets_orb = highlighted_grapple_target.is_in_group("grapple_orbs")
	grapple_effect.reset()
	return true

func _release_grapple() -> void:
	if grapple_active and grapple_line.visible:
		# Start at the currently drawn tip, including when released mid-flight.
		grapple_retract_origin = grapple_line.get_point_position(1)
		grapple_retract_time = 0.0
		grapple_retract_duration = clampf(global_position.distance_to(grapple_retract_origin) / GRAPPLE_VISUAL_SHOOT_SPEED, 0.08, 0.2)
		grapple_retracting = true
	grapple_active = false
	grapple_targets_orb = false
	grapple_line.visible = grapple_retracting
	if grapple_effect != null:
		grapple_effect.reset()
	_set_highlighted_grapple_target(null)

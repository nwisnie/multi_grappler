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
const CAMERA_BASE_ZOOM := Vector2(0.85, 0.85)
const CAMERA_MAX_ZOOM_OUT := Vector2(0.52, 0.52)
const CAMERA_ZOOM_SPEED := 3.5
const GRAPPLE_MAX_DISTANCE := 2200.0
const GRAPPLE_MIN_LENGTH := 24.0
const GRAPPLE_PULL_FORCE := 12000.0
const GRAPPLE_PULL_SPEED_LIMIT := 720.0
const GRAPPLE_TETHER_BOUNCE := 0.18
const GRAPPLE_MAX_BOUNCE_SPEED := 160.0
const JAB_MIN_LENGTH := 120.0
const JAB_MAX_LENGTH := 420.0
const JAB_WIDTH := 76.0
const JAB_ACTIVE_TIME := 0.12
const JAB_MAX_CHARGE_TIME := 1.4
const JAB_MIN_COOLDOWN := 0.15
const JAB_MAX_COOLDOWN := 0.9
const JAB_MIN_IMPULSE := 420.0
const JAB_MAX_IMPULSE := 1350.0
const JAB_MIN_DAMAGE := 1
const JAB_MAX_DAMAGE := 10
const JAB_METER_MAX_SHAKE := 4.0
const JAB_UPWARD_BIAS := 0.08
const JAB_FULL_CHARGE_MOVE_MULTIPLIER := 0.45
const JAB_CHARGE_BRAKE_FORCE := 18000.0
const JAB_START_OFFSET := 48.0
const JAB_WORLD_RECOIL_MIN_IMPULSE := 520.0
const JAB_WORLD_RECOIL_MAX_IMPULSE := 1450.0
const CHARGE_METER_SIZE := Vector2(168.0, 26.0)
const CHARGE_METER_OFFSET := Vector2(-84.0, -110.0)
const CHARGE_METER_EMPTY_COLOR := Color(0.25, 0.52, 0.78, 0.97)
const CHARGE_METER_ACTIVE_COLOR := Color(0.25, 0.7, 0.36, 0.97)
const CHARGE_METER_COOLDOWN_COLOR := Color(0.2, 0.44, 0.28, 0.92)
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
const HEART_BEAT_SPEED := 0.75
const HEART_BEAT_SECOND_PULSE_DELAY := 0.2
const HEART_BEAT_SCALE_AMOUNT := 0.12
const HEART_BEAT_ROTATION_AMOUNT := deg_to_rad(3.0)
const PLAYER_HEALTH_BAR_SIZE := Vector2(250.0, 26.0)
const PLAYER_HEALTH_BAR_FILL_COLOR := Color(0.905882, 0.6, 0.623529, 0.96)
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
var jab_meter: EnemyHealthBar
var player_ui_layer: CanvasLayer
var heart_texture_rect: TextureRect
var player_health_bar: EnemyHealthBar

@export var initial_camera_zoom: Vector2 = CAMERA_BASE_ZOOM
@export var speed_zoom_out: Vector2 = CAMERA_MAX_ZOOM_OUT
@export_range(1, 1000, 1) var max_health: int = 20

var current_health: int = 20
var damage_immunity_remaining := 0.0
var grapple_active: bool = false
var grapple_anchor: Vector2 = Vector2.ZERO
var grapple_length: float = 0.0
var was_left_mouse_pressed: bool = false
var was_grapple_pressed: bool = false
var jab_charging: bool = false
var jab_charge_time: float = 0.0
var jab_cooldown_remaining: float = 0.0
var jab_cooldown_total: float = 0.0
var jab_active_remaining: float = 0.0
var jab_charge_ratio: float = 0.0
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
var idle_breath_time: float = 0.0
var heart_beat_time: float = 0.0

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
	_setup_jab_nodes()
	_setup_jab_meter()
	_setup_player_ui()

func reset_spawn_orientation() -> void:
	rotation = 0.0
	angular_velocity = 0.0
	if sprite != null:
		sprite.global_rotation = SPRITE_UPRIGHT_ROTATION

func _process(delta: float) -> void:
	_update_squash_and_stretch(delta)
	_update_jab_visual_line()
	_update_heart_ui(delta)

func _physics_process(delta: float) -> void:
	damage_immunity_remaining = maxf(damage_immunity_remaining - delta, 0.0)
	if controls_locked:
		_clear_control_input_state()
		_update_camera(delta)
		return

	var move_direction: float = _get_move_direction()
	var is_grapple_pressed: bool = _is_grapple_pressed()
	var charge_move_multiplier := _get_charge_move_multiplier()
	var max_ground_speed := MAX_GROUND_SPEED * charge_move_multiplier
	_update_grapple(is_grapple_pressed)

	if has_support_contact:
		var floor_normal: Vector2 = support_normal
		var floor_tangent: Vector2 = Vector2(floor_normal.y, -floor_normal.x).normalized()
		if floor_tangent.x < 0.0:
			floor_tangent = -floor_tangent

		var tangent_speed: float = linear_velocity.dot(floor_tangent)
		if move_direction != 0.0 and (absf(tangent_speed) < max_ground_speed or signf(tangent_speed) != signf(move_direction)):
			var ground_force: float = _scaled_force(MOVE_FORCE * charge_move_multiplier, move_direction, tangent_speed, GROUND_REVERSE_FORCE_MULTIPLIER)
			apply_central_force(floor_tangent * move_direction * ground_force)
		_apply_charge_brake(floor_tangent, tangent_speed, max_ground_speed)
	else:
		if move_direction != 0.0 and (absf(linear_velocity.x) < MAX_AIR_SPEED or signf(linear_velocity.x) != signf(move_direction)):
			var air_force: float = _scaled_force(AIR_CONTROL_FORCE, move_direction, linear_velocity.x, AIR_REVERSE_FORCE_MULTIPLIER)
			apply_central_force(Vector2(move_direction * air_force, 0.0))
		linear_velocity.x = move_toward(linear_velocity.x, 0.0, AIR_FRICTION)

	if grapple_active:
		var pull_direction: Vector2 = grapple_anchor - global_position
		if pull_direction.length_squared() > 1.0:
			var pull_normal: Vector2 = pull_direction.normalized()
			var pull_speed: float = linear_velocity.dot(pull_normal)
			grapple_length = maxf(global_position.distance_to(grapple_anchor), GRAPPLE_MIN_LENGTH)
			if pull_speed < GRAPPLE_PULL_SPEED_LIMIT:
				apply_central_force(pull_normal * GRAPPLE_PULL_FORCE)

	_update_camera(delta)
	_update_jab(delta)

func set_controls_locked(locked: bool) -> void:
	controls_locked = locked
	if locked:
		_clear_control_input_state()

func take_damage(amount: int = 1) -> bool:
	if amount <= 0 or current_health <= 0 or damage_immunity_remaining > 0.0:
		return false
	current_health = maxi(current_health - amount, 0)
	damage_immunity_remaining = DAMAGE_IMMUNITY_TIME
	_update_player_health_bar()
	return true

func set_max_health(value: int) -> void:
	var previous_max := max_health
	max_health = maxi(value, 1)
	current_health = clampi(current_health + max_health - previous_max, 0, max_health)
	_update_player_health_bar()

func _update_player_health_bar() -> void:
	if player_health_bar != null:
		player_health_bar.set_health_ratio(float(current_health) / float(max_health))

func _get_charge_move_multiplier() -> float:
	if not jab_charging:
		return 1.0
	return lerpf(1.0, JAB_FULL_CHARGE_MOVE_MULTIPLIER, clampf(jab_charge_ratio, 0.0, 1.0))

func _apply_charge_brake(move_axis: Vector2, current_speed: float, max_speed: float) -> void:
	if not jab_charging or absf(current_speed) <= max_speed:
		return
	var brake_ratio := clampf(jab_charge_ratio, 0.0, 1.0)
	apply_central_force(-move_axis.normalized() * signf(current_speed) * JAB_CHARGE_BRAKE_FORCE * brake_ratio)

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
	was_left_mouse_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	was_grapple_pressed = _is_grapple_pressed()
	if grapple_active:
		_release_grapple()
	if jab_charging:
		jab_charging = false
		jab_charge_time = 0.0
		jab_charge_ratio = 0.0
	if jab_active_remaining > 0.0:
		jab_active_remaining = 0.0
		_end_jab_attack()
	_update_jab_meter()

func _update_camera(delta: float) -> void:
	var speed_ratio: float = clampf(linear_velocity.length() / (MAX_GROUND_SPEED * 1.35), 0.0, 1.0)
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

	var zoom_target: Vector2 = initial_camera_zoom.lerp(speed_zoom_out, speed_ratio) + interaction_zoom_offset
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
	rectangle_shape.size = Vector2(JAB_MIN_LENGTH, JAB_WIDTH)

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

func _setup_jab_meter() -> void:
	jab_meter = EnemyHealthBar.new()
	jab_meter.name = "JabMeter"
	jab_meter.top_level = true
	jab_meter.configure(CHARGE_METER_SIZE)
	jab_meter.shake_on_decrease = false
	jab_meter.set_fill_color(CHARGE_METER_EMPTY_COLOR)
	jab_meter.visible = false
	add_child(jab_meter)
	jab_meter.set_anchor(global_position + CHARGE_METER_OFFSET)

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

	player_health_bar = EnemyHealthBar.new()
	player_health_bar.name = "PlayerHealthBar"
	player_health_bar.configure(PLAYER_HEALTH_BAR_SIZE)
	player_health_bar.set_fill_color(PLAYER_HEALTH_BAR_FILL_COLOR)
	player_health_bar.outline_width = 5.0
	player_health_bar.pointed_right_edge = true
	player_health_bar.idle_float_amount = 0.0
	player_ui_layer.add_child(player_health_bar)
	player_health_bar.z_index = -1
	player_health_bar.set_anchor(_player_health_bar_position())
	_update_player_health_bar()

func _player_health_bar_position() -> Vector2:
	return HEART_UI_POSITION + Vector2(HEART_UI_SIZE.x * 0.78, HEART_UI_SIZE.y * 0.5 - PLAYER_HEALTH_BAR_SIZE.y * 0.5)

func _update_heart_ui(delta: float) -> void:
	if heart_texture_rect == null:
		return

	heart_beat_time += delta
	var beat_progress := fmod(heart_beat_time * HEART_BEAT_SPEED, 1.0)
	var primary_pulse := _heart_pulse(beat_progress)
	var secondary_progress := fmod(beat_progress - HEART_BEAT_SECOND_PULSE_DELAY + 1.0, 1.0)
	var secondary_pulse := _heart_pulse(secondary_progress) * 0.55
	var pulse := maxf(primary_pulse, secondary_pulse)
	var squash := pulse * HEART_BEAT_SCALE_AMOUNT
	heart_texture_rect.scale = Vector2(1.0 + squash * 0.55, 1.0 + squash)
	heart_texture_rect.rotation = sin(heart_beat_time * HEART_BEAT_SPEED * TAU) * HEART_BEAT_ROTATION_AMOUNT * pulse

func _heart_pulse(progress: float) -> float:
	var pulse_width := 0.18
	if progress > pulse_width:
		return 0.0
	var normalized := progress / pulse_width
	return sin(normalized * PI)

func _update_jab(delta: float) -> void:
	var left_mouse_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if jab_cooldown_remaining > 0.0:
		jab_cooldown_remaining = maxf(jab_cooldown_remaining - delta, 0.0)

	if jab_active_remaining > 0.0:
		jab_active_remaining = maxf(jab_active_remaining - delta, 0.0)
		if jab_active_remaining <= 0.0:
			_end_jab_attack()

	if left_mouse_pressed and not was_left_mouse_pressed and _can_start_jab_charge():
		_start_jab_charge()

	if jab_charging and left_mouse_pressed:
		jab_charge_time = minf(jab_charge_time + delta, JAB_MAX_CHARGE_TIME)
		jab_charge_ratio = jab_charge_time / JAB_MAX_CHARGE_TIME

	if jab_charging and not left_mouse_pressed and was_left_mouse_pressed:
		_release_jab_attack()

	was_left_mouse_pressed = left_mouse_pressed
	_update_jab_meter()

func _can_start_jab_charge() -> bool:
	return not jab_charging and jab_cooldown_remaining <= 0.0 and jab_active_remaining <= 0.0

func _start_jab_charge() -> void:
	grapple_active = false
	grapple_line.visible = false
	jab_charging = true
	jab_charge_time = 0.0
	jab_charge_ratio = 0.0

func _release_jab_attack() -> void:
	jab_charging = false
	var charge_ratio := clampf(jab_charge_time / JAB_MAX_CHARGE_TIME, 0.0, 1.0)
	jab_charge_ratio = charge_ratio
	var jab_length := lerpf(JAB_MIN_LENGTH, JAB_MAX_LENGTH, charge_ratio)
	var cooldown := lerpf(JAB_MIN_COOLDOWN, JAB_MAX_COOLDOWN, charge_ratio)
	jab_cooldown_total = cooldown
	jab_cooldown_remaining = cooldown
	jab_active_remaining = JAB_ACTIVE_TIME
	jab_hit_bodies.clear()
	_position_jab(jab_length)
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
		_apply_jab_world_recoil(direction)
	return minf(jab_length, hit_distance)

func _is_jab_world_recoil_collider(collider: Variant) -> bool:
	var collider_node := collider as Node
	if collider_node == null:
		return false
	if collider_node.has_method("receive_jab_hit"):
		return false
	var parent := collider_node.get_parent()
	return parent == null or not parent.has_method("receive_jab_hit")

func _apply_jab_world_recoil(hit_direction: Vector2) -> void:
	if hit_direction.length_squared() <= 0.001:
		return
	var recoil_impulse := lerpf(JAB_WORLD_RECOIL_MIN_IMPULSE, JAB_WORLD_RECOIL_MAX_IMPULSE, clampf(jab_charge_ratio, 0.0, 1.0))
	apply_central_impulse(-hit_direction.normalized() * recoil_impulse)

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
	var impulse := lerpf(JAB_MIN_IMPULSE, JAB_MAX_IMPULSE, jab_charge_ratio)
	var damage := int(round(lerpf(float(JAB_MIN_DAMAGE), float(JAB_MAX_DAMAGE), jab_charge_ratio)))
	if receiver.has_method("receive_jab_hit"):
		receiver.receive_jab_hit(direction, impulse, damage)
	elif receiver is RigidBody2D:
		(receiver as RigidBody2D).apply_central_impulse(direction * impulse)

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

func _update_jab_meter() -> void:
	if jab_meter == null:
		return

	var meter_visible := not controls_locked and (jab_charging or jab_cooldown_remaining > 0.0)
	jab_meter.visible = meter_visible
	if not meter_visible:
		jab_meter.set_vibration_strength(0.0)
		return

	var meter_ratio := 0.0
	if jab_charging:
		meter_ratio = clampf(jab_charge_time / JAB_MAX_CHARGE_TIME, 0.0, 1.0)
		jab_meter.set_fill_color(CHARGE_METER_EMPTY_COLOR.lerp(CHARGE_METER_ACTIVE_COLOR, meter_ratio))
		jab_meter.set_vibration_strength(JAB_METER_MAX_SHAKE * meter_ratio)
	else:
		meter_ratio = clampf(jab_cooldown_remaining / jab_cooldown_total, 0.0, 1.0)
		jab_meter.set_fill_color(CHARGE_METER_COOLDOWN_COLOR)
		jab_meter.set_vibration_strength(0.0)

	jab_meter.set_health_ratio(meter_ratio)
	jab_meter.set_anchor(global_position + CHARGE_METER_OFFSET)

func _get_move_direction() -> float:
	return clampf(
		Input.get_axis("ui_left", "ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		-1.0,
		1.0
	)

func _is_grapple_pressed() -> bool:
	return Input.is_key_pressed(KEY_SPACE)

func _update_grapple(is_grapple_pressed: bool) -> void:
	if is_grapple_pressed and not was_grapple_pressed:
		grapple_active = _try_start_grapple()

	if not is_grapple_pressed and was_grapple_pressed:
		_release_grapple()

	was_grapple_pressed = is_grapple_pressed

	if not is_grapple_pressed or not grapple_active:
		grapple_line.visible = false
		return

	grapple_line.visible = true
	grapple_line.set_point_position(0, global_position)
	grapple_line.set_point_position(1, grapple_anchor)

func _try_start_grapple() -> bool:
	var origin: Vector2 = global_position
	var mouse_position: Vector2 = get_global_mouse_position()
	var ray_direction: Vector2 = mouse_position - origin
	if ray_direction.length_squared() < 1.0:
		return false

	var ray_end: Vector2 = origin + ray_direction.normalized() * GRAPPLE_MAX_DISTANCE
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, ray_end)
	query.exclude = [self]
	var result: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false

	grapple_anchor = result["position"] as Vector2
	grapple_length = maxf(origin.distance_to(grapple_anchor), GRAPPLE_MIN_LENGTH)
	return true

func _release_grapple() -> void:
	grapple_active = false
	grapple_line.visible = false

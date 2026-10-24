class_name CustomLevel
extends Node2D

const PlayerScene := preload("res://scenes/player_ball.tscn")
const OrbScene := preload("res://scenes/grapple_orb.tscn")
const SkyScript := preload("res://scripts/levels/sky_background.gd")
const SkyTexture := preload("res://assets/images/levels/bg_sky.png")

var document: LevelDocument
var player: RigidBody2D
var restart_pending := false

func prepare(value: LevelDocument) -> String:
	var error := value.playtest_error()
	if not error.is_empty():
		return error
	var generated := LevelGeometry.build_runtime(value)
	if not generated["error"].is_empty():
		return generated["error"]
	document = value.copy()
	add_child(generated["body"])
	var visual := LevelTerrainVisual.new()
	visual.set_document(document, generated["polygons"], generated["contours"])
	add_child(visual)
	return ""

func _ready() -> void:
	if document == null:
		return
	var sky := SkyScript.new()
	sky.texture = SkyTexture
	sky.z_index = -4096
	add_child(sky)
	for point in document.orbs:
		var orb := OrbScene.instantiate()
		orb.position = LevelDocument.cell_position(point)
		add_child(orb)
	restart()

func restart() -> void:
	restart_pending = false
	if is_instance_valid(player):
		remove_child(player)
		player.queue_free()
	player = PlayerScene.instantiate()
	player.position = LevelDocument.cell_position(document.spawn)
	player.scale = Vector2.ONE * 1.18
	add_child(player)
	player.set_controls_locked(true)
	player.get_node("Camera2D").make_current()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if player.controls_locked and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_key_pressed(KEY_SPACE):
		player.set_controls_locked(false)
	if not Rect2(Vector2.ZERO, Vector2.ONE * LevelDocument.BOARD_SIZE).has_point(player.position) and not restart_pending:
		restart_pending = true
		restart.call_deferred()

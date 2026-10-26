extends CustomLevel
## Host owns the roster/spawner. Player authority is assigned before tree entry.

const NetworkPlayerScript := preload("res://scripts/network/network_player.gd")

var players: Node2D
var spawner: MultiplayerSpawner

func _ready() -> void:
	_setup_environment()
	players = Node2D.new()
	players.name = "Players"
	add_child(players)
	spawner = MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_limit = 8
	spawner.spawn_function = _create_player
	add_child(spawner)
	if multiplayer.is_server():
		add_player(1)

func _create_player(data: Variant) -> Node:
	var peer_id := int(data)
	var ball := PlayerScene.instantiate() as RigidBody2D
	ball.set_script(NetworkPlayerScript)
	ball.name = str(peer_id)
	ball.position = LevelDocument.cell_position(document.spawn)
	ball.scale = Vector2.ONE * 1.18
	ball.spawn_position = ball.position
	ball.network_position = ball.position
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	sync.replication_interval = 1.0 / 30.0
	var config := SceneReplicationConfig.new()
	for property in ["network_position", "network_rotation", "network_velocity", "network_grapple_active", "network_grapple_anchor"]:
		var path := NodePath(".:" + property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	ball.add_child(sync)
	ball.set_multiplayer_authority(peer_id)
	# The host relays each owner's snapshots through the synchronizer.
	sync.set_multiplayer_authority(1)
	ball.ready.connect(_player_ready.bind(ball))
	return ball

func _player_ready(ball: RigidBody2D) -> void:
	if ball.is_multiplayer_authority():
		player = ball
		player_spawned.emit(ball)

func add_player(peer_id: int) -> void:
	if multiplayer.is_server() and not players.has_node(str(peer_id)):
		spawner.spawn(peer_id)

func remove_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var ball := players.get_node_or_null(str(peer_id))
	if ball != null:
		ball.queue_free()

func _physics_process(_delta: float) -> void:
	# Network players respawn in place, preserving their replicated node identity.
	pass

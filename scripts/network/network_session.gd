class_name NetworkSession
extends Node
## WebSocket carries room discovery/SDP/ICE only. Gameplay uses WebRTC.

signal session_started(room: String, level_code: String, hosting: bool)
signal session_ended(reason: String)
signal status_changed(message: String)
signal peer_arrived(peer_id: int)
signal peer_left(peer_id: int)

const CONNECT_TIMEOUT := 25.0
const DEFAULT_URL := "ws://localhost:9080"
const PUBLIC_URL := "wss://rooms.wizkinews.com"
const HEARTBEAT_MSEC := 15000

var socket: WebSocketPeer
var rtc: WebRTCMultiplayerPeer
var connections: Dictionary = {}
var deadlines: Dictionary = {}
var ice_servers: Array = []
var room := ""
var hosting := false
var active := false
var request: Dictionary = {}
var elapsed := 0.0
var request_sent := false
var joined_game := false
var started_at_msec := 0
var background_callback: JavaScriptObject
var background_timer := -1
var next_heartbeat_msec := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.server_disconnected.connect(func() -> void: _fail("The host disconnected. The game has ended."))
	multiplayer.connection_failed.connect(func() -> void: _fail("WebRTC connection failed. Check the network and TURN configuration."))

static func default_url() -> String:
	var configured := str(ProjectSettings.get_setting("network/signaling_url", DEFAULT_URL))
	if OS.has_feature("web"):
		# Public exports can provide window.MULTI_GRAPPLER_SIGNALING_URL in the HTML head.
		var browser_url = JavaScriptBridge.eval("window.MULTI_GRAPPLER_SIGNALING_URL || ''")
		if browser_url is String and not browser_url.is_empty():
			return browser_url
		# A public export works without editing the generated HTML. Local exports
		# keep using the local service; an explicit HTML override always wins.
		var hostname = JavaScriptBridge.eval("window.location.hostname")
		if hostname == "wizkinews.com" or hostname == "www.wizkinews.com":
			return PUBLIC_URL
	return configured

func host_game(url: String, level_code: String, limit: int, game_name: String) -> void:
	_begin(url, {"type": "create", "level_code": level_code, "max_players": limit, "name": game_name}, true)

func join_game(url: String, code: String) -> void:
	_begin(url, {"type": "join", "room": code}, false)

func _begin(url: String, message: Dictionary, as_host: bool) -> void:
	close()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		session_ended.emit("Use a ws:// or wss:// signaling server URL.")
		return
	if not OS.has_feature("web") and not ClassDB.class_exists("WebRTCLibPeerConnection"):
		session_ended.emit("WebRTC is built into the browser export. Desktop play requires the Godot webrtc-native extension; see README.md.")
		return
	hosting = as_host
	request = message
	socket = WebSocketPeer.new()
	# Workers route each room to its own Durable Object before the upgrade.
	# The local Node server accepts this path too.
	var connect_url := url.trim_suffix("/")
	if not as_host:
		connect_url += "/rooms/" + str(message.get("room", ""))
	var error := socket.connect_to_url(connect_url)
	if error != OK:
		_fail("Could not connect to the signaling server (%s)." % error_string(error))
		return
	active = true
	started_at_msec = Time.get_ticks_msec()
	next_heartbeat_msec = started_at_msec
	_start_background_poll()
	status_changed.emit("Connecting to room service...")

func _start_background_poll() -> void:
	if not OS.has_feature("web"):
		return
	if background_callback == null:
		background_callback = JavaScriptBridge.create_callback(_background_tick)
	# Hidden browser tabs can stop animation frames altogether. Keep just the
	# networking alive on a timer; visible tabs retain Godot's normal frame loop.
	background_timer = int(JavaScriptBridge.get_interface("window").setInterval(background_callback, 250))

func _background_tick(_arguments: Array) -> void:
	if not active or not is_inside_tree() or not JavaScriptBridge.get_interface("document").hidden:
		return
	_poll_network()
	if active:
		multiplayer.poll()

func close() -> void:
	active = false
	if background_timer >= 0:
		JavaScriptBridge.get_interface("window").clearInterval(background_timer)
		background_timer = -1
	if socket != null:
		socket.close()
	socket = null
	if rtc != null:
		rtc.close()
	rtc = null
	if is_inside_tree():
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connections.clear()
	deadlines.clear()
	ice_servers.clear()
	room = ""
	elapsed = 0.0
	request_sent = false
	joined_game = false

func _exit_tree() -> void:
	close()
	background_callback = null

func _process(_delta: float) -> void:
	_poll_network()

func _poll_network() -> void:
	if not active or socket == null:
		return
	elapsed = float(Time.get_ticks_msec() - started_at_msec) / 1000.0
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		# Cloudflare may send an error and a close in the same poll.
		while active and socket != null and socket.get_available_packet_count() > 0:
			var message = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if message is Dictionary:
				_handle_message(message)
		if active:
			_fail("Room service disconnected. The session has ended.")
		return
	if state == WebSocketPeer.STATE_OPEN:
		if not request_sent:
			request_sent = true
			_send(request)
		if Time.get_ticks_msec() >= next_heartbeat_msec:
			# Exact bytes match Cloudflare's hibernation auto-response. No room wakeup.
			socket.send_text('{"type":"ping"}')
			next_heartbeat_msec = Time.get_ticks_msec() + HEARTBEAT_MSEC
		while active and socket != null and socket.get_available_packet_count() > 0:
			var message = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if message is Dictionary:
				_handle_message(message)
	if not active:
		return
	if (room.is_empty() or (not hosting and not joined_game)) and elapsed > CONNECT_TIMEOUT:
		if room.is_empty():
			_fail("The room service did not respond. Check that it is running, then try again.")
		else:
			_fail("Room found, but the host connection timed out. Keep the host browser running and try again. For internet play, check the TURN configuration.")
		return
	for peer_id in deadlines.keys():
		if elapsed > float(deadlines[peer_id]):
			_drop_peer(peer_id)
			_send({"type": "kick", "peer_id": peer_id})
			status_changed.emit("A player could not establish WebRTC. They can try joining again.")

func _send(message: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))

func _handle_message(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"created", "joined":
			room = str(message.get("room", ""))
			ice_servers = message.get("ice_servers", [])
			rtc = WebRTCMultiplayerPeer.new()
			var error: Error = rtc.create_server() if hosting else rtc.create_client(int(message.get("peer_id", 0)))
			if error != OK:
				_fail("Could not initialize WebRTC: " + error_string(error))
				return
			multiplayer.multiplayer_peer = rtc
			# Both worlds/spawners exist BEFORE SDP can establish a gameplay connection.
			session_started.emit(room, str(message.get("level_code", "")), hosting)
			if not active:
				return
			if not hosting:
				_add_peer(1, false)
			status_changed.emit("Room %s - %s" % [room, "share this code to invite players" if hosting else "connecting to host..."])
		"peer_joined":
			if hosting:
				_add_peer(int(message.get("peer_id", 0)), true)
		"peer_left":
			_drop_peer(int(message.get("peer_id", 0)))
		"signal":
			_receive_signal(int(message.get("from", 0)), message.get("data", {}))
		"room_closed":
			_fail("The host closed the game. The session has ended.")
		"error":
			_fail(str(message.get("message", "Room service error.")))

func _add_peer(peer_id: int, offer: bool) -> void:
	if peer_id < 1 or connections.has(peer_id):
		return
	var connection := WebRTCPeerConnection.new()
	var error := connection.initialize({"iceServers": ice_servers})
	if error != OK:
		_fail("WebRTC is unavailable: " + error_string(error))
		return
	connection.session_description_created.connect(_description_created.bind(peer_id))
	connection.ice_candidate_created.connect(_ice_created.bind(peer_id))
	error = rtc.add_peer(connection, peer_id)
	if error != OK:
		connection.close()
		_fail("Could not add WebRTC peer: " + error_string(error))
		return
	connections[peer_id] = connection
	if hosting:
		deadlines[peer_id] = elapsed + CONNECT_TIMEOUT
	if offer and connection.create_offer() != OK:
		_fail("Could not create a WebRTC offer.")

func _description_created(type: String, sdp: String, peer_id: int) -> void:
	if not connections.has(peer_id):
		return
	var connection: WebRTCPeerConnection = connections[peer_id]
	if connection.set_local_description(type, sdp) != OK:
		_fail("Could not set the local WebRTC description.")
		return
	_send({"type": "signal", "to": peer_id, "data": {"kind": "sdp", "type": type, "sdp": sdp}})

func _ice_created(media: String, index: int, candidate: String, peer_id: int) -> void:
	_send({"type": "signal", "to": peer_id, "data": {"kind": "ice", "media": media, "index": index, "candidate": candidate}})

func _receive_signal(peer_id: int, data: Dictionary) -> void:
	if not connections.has(peer_id):
		return
	var connection: WebRTCPeerConnection = connections[peer_id]
	var error := OK
	if data.get("kind") == "sdp":
		error = connection.set_remote_description(str(data.get("type", "")), str(data.get("sdp", "")))
	elif data.get("kind") == "ice":
		error = connection.add_ice_candidate(str(data.get("media", "")), int(data.get("index", 0)), str(data.get("candidate", "")))
	if error != OK:
		status_changed.emit("WebRTC negotiation error: " + error_string(error))

func _peer_connected(peer_id: int) -> void:
	if not active:
		return
	deadlines.erase(peer_id)
	if not hosting and peer_id == 1:
		joined_game = true
	status_changed.emit("Room %s - connected" % room)
	peer_arrived.emit(peer_id)

func _peer_disconnected(peer_id: int) -> void:
	if not active:
		return
	if not hosting and peer_id == 1:
		_fail("The host disconnected. The game has ended.")
	else:
		_drop_peer.call_deferred(peer_id)
		if hosting:
			_send({"type": "kick", "peer_id": peer_id})

func _drop_peer(peer_id: int) -> void:
	deadlines.erase(peer_id)
	if connections.has(peer_id):
		connections.erase(peer_id)
		if rtc != null and rtc.has_peer(peer_id):
			rtc.remove_peer(peer_id)
	peer_left.emit(peer_id)

func _fail(reason: String) -> void:
	close()
	session_ended.emit(reason)

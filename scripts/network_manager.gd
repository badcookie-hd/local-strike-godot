extends Node

signal connection_state_changed(state: String)
signal server_discovered(server: Dictionary)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const GAME_PORT := 27888
const DISCOVERY_PORT := 27889
const BROADCAST_INTERVAL := 0.8

var peer: ENetMultiplayerPeer
var discovery_listener: PacketPeerUDP
var broadcaster: PacketPeerUDP
var discovered_servers: Dictionary = {}
var is_host := false
var _broadcast_timer := 0.0
var _server_name := "Local Strike LAN"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(func(id: int): peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int): peer_left.emit(id))
	multiplayer.connected_to_server.connect(func(): connection_state_changed.emit("connected"))
	multiplayer.connection_failed.connect(func(): connection_state_changed.emit("failed"))
	multiplayer.server_disconnected.connect(func(): connection_state_changed.emit("disconnected"))

func _process(delta: float) -> void:
	_poll_discovery()
	if is_host and broadcaster != null:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = BROADCAST_INTERVAL
			_send_announcement()

func host_game(max_players := 10, server_name := "Local Strike LAN") -> Error:
	leave_game()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(GAME_PORT, max_players - 1)
	if error != OK:
		connection_state_changed.emit("host_failed")
		return error
	multiplayer.multiplayer_peer = peer
	is_host = true
	_server_name = server_name
	_start_broadcasting()
	connection_state_changed.emit("hosting")
	return OK

func join_game(address: String) -> Error:
	leave_game()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), GAME_PORT)
	if error != OK:
		connection_state_changed.emit("join_failed")
		return error
	multiplayer.multiplayer_peer = peer
	connection_state_changed.emit("connecting")
	return OK

func leave_game() -> void:
	if peer != null:
		peer.close()
	peer = null
	is_host = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if broadcaster != null:
		broadcaster.close()
	broadcaster = null
	connection_state_changed.emit("offline")

func discover_lan_games() -> Error:
	if discovery_listener != null:
		return OK
	discovery_listener = PacketPeerUDP.new()
	var error := discovery_listener.bind(DISCOVERY_PORT, "0.0.0.0")
	if error != OK:
		discovery_listener = null
	return error

func stop_discovery() -> void:
	if discovery_listener != null:
		discovery_listener.close()
	discovery_listener = null

func get_servers() -> Array:
	return discovered_servers.values()

func _start_broadcasting() -> void:
	broadcaster = PacketPeerUDP.new()
	broadcaster.set_broadcast_enabled(true)
	broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcast_timer = 0.0

func _send_announcement() -> void:
	var payload := JSON.stringify({"game": "local_strike", "name": _server_name, "port": GAME_PORT, "players": multiplayer.get_peers().size() + 1})
	broadcaster.put_packet(payload.to_utf8_buffer())

func _poll_discovery() -> void:
	if discovery_listener == null:
		return
	while discovery_listener.get_available_packet_count() > 0:
		var payload := discovery_listener.get_packet().get_string_from_utf8()
		var data = JSON.parse_string(payload)
		if data is Dictionary and data.get("game", "") == "local_strike":
			var address := discovery_listener.get_packet_ip()
			data["address"] = address
			data["last_seen"] = Time.get_ticks_msec()
			discovered_servers[address] = data
			server_discovered.emit(data)

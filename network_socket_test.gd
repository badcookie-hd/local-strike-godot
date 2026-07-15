extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var server := ENetMultiplayerPeer.new()
	var client_a := ENetMultiplayerPeer.new()
	var client_b := ENetMultiplayerPeer.new()
	var listener := PacketPeerUDP.new()
	var success := server.create_server(27988, 9) == OK
	success = success and listener.bind(27989, "127.0.0.1") == OK
	success = success and client_a.create_client("127.0.0.1", 27988) == OK
	success = success and await _wait_for_connection(server, client_a)
	# Client B joins after the host is already active to cover late joins.
	success = success and client_b.create_client("127.0.0.1", 27988) == OK
	success = success and await _wait_for_connection(server, client_b, client_a)
	for frame in range(12):
		server.poll()
		client_a.poll()
		client_b.poll()
		await process_frame
	var snapshot := JSON.stringify({"door-harbor": {"opened": true, "revision": 4}}).to_utf8_buffer()
	if success:
		server.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
		success = server.put_packet(snapshot) == OK
	var received_a := ""
	var received_b := ""
	for frame in range(180):
		server.poll()
		client_a.poll()
		client_b.poll()
		if client_a.get_available_packet_count() > 0:
			received_a = client_a.get_packet().get_string_from_utf8()
		if client_b.get_available_packet_count() > 0:
			received_b = client_b.get_packet().get_string_from_utf8()
		if not received_a.is_empty() and not received_b.is_empty():
			break
		await process_frame
	var expected := snapshot.get_string_from_utf8()
	print("NETWORK_DIAGNOSTIC connected_a=%s connected_b=%s received_a=%d received_b=%d" % [
		client_a.get_connection_status(), client_b.get_connection_status(), received_a.length(), received_b.length()
	])
	success = success and received_a == expected and received_b == expected
	server.close()
	client_a.close()
	client_b.close()
	listener.close()
	print("NETWORK_SOCKET_TEST_OK" if success else "NETWORK_SOCKET_TEST_FAILED")
	quit(0 if success else 1)

func _wait_for_connection(server: ENetMultiplayerPeer, client: ENetMultiplayerPeer, other_client: ENetMultiplayerPeer = null) -> bool:
	for frame in range(240):
		server.poll()
		client.poll()
		if other_client != null:
			other_client.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			return true
		await process_frame
	return false

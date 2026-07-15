extends SceneTree

func _initialize() -> void:
	var server := ENetMultiplayerPeer.new()
	var client_a := ENetMultiplayerPeer.new()
	var client_b := ENetMultiplayerPeer.new()
	var listener := PacketPeerUDP.new()
	var success := (
		server.create_server(27988, 9) == OK
		and client_a.create_client("127.0.0.1", 27988) == OK
		and client_b.create_client("127.0.0.1", 27988) == OK
		and listener.bind(27989, "127.0.0.1") == OK
	)
	server.close()
	client_a.close()
	client_b.close()
	listener.close()
	print("NETWORK_SOCKET_TEST_OK" if success else "NETWORK_SOCKET_TEST_FAILED")
	quit(0 if success else 1)

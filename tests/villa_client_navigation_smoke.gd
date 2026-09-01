extends SceneTree

## A real ENet client role is used here so WorldNet takes the same branch as a
## joined multiplayer peer. The Villa must become presentation-ready without
## creating any local NavigationRegion3D.

const TEST_PORT := 38991


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var holding_server := ENetMultiplayerPeer.new()
	if holding_server.create_server(TEST_PORT, 1) != OK:
		return _fail("Could not reserve the navigation smoke-test port.")
	var client := ENetMultiplayerPeer.new()
	if client.create_client("127.0.0.1", TEST_PORT) != OK:
		holding_server.close()
		return _fail("Could not create an ENet client role.")
	root.get_multiplayer().multiplayer_peer = client
	for _attempt: int in 60:
		holding_server.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await process_frame
	if client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return _cleanup_fail("ENet client role did not connect in time.", client, holding_server)
	var network_manager := root.get_node_or_null("NetworkManager")
	if not network_manager:
		return _cleanup_fail("NetworkManager autoload is missing.", client, holding_server)
	network_manager.set("session_active", true)

	var game := (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame: int in 4:
		await process_frame

	if WorldNet.is_world_authority():
		return _cleanup_fail("Smoke-test peer was not recognized as a network client.", client, holding_server)
	if not bool(game.get("navigation_is_ready")):
		return _cleanup_fail("Client Villa did not mark replicated navigation as ready.", client, holding_server)
	if game.get_node_or_null("VillaNavigationRegion"):
		return _cleanup_fail("Client still baked a VillaNavigationRegion3D.", client, holding_server)

	_cleanup_network(client, holding_server)
	print("Villa client navigation smoke test passed: no client-side navmesh bake.")
	quit()


func _cleanup_network(client: ENetMultiplayerPeer, holding_server: ENetMultiplayerPeer) -> void:
	var network_manager := root.get_node_or_null("NetworkManager")
	if network_manager:
		network_manager.set("session_active", false)
	root.get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	client.close()
	holding_server.close()


func _cleanup_fail(
	message: String,
	client: ENetMultiplayerPeer,
	holding_server: ENetMultiplayerPeer
) -> void:
	_cleanup_network(client, holding_server)
	_fail(message)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

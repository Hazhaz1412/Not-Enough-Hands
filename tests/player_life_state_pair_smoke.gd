extends SceneTree

## Two real processes verify the reliable player life-cycle channel. Periodic
## player physics is disabled deliberately, so the client cannot pass by taking
## `is_alive` from the ordinary unreliable movement snapshot.

const PORT := 47319
const RESULT_PATH := "user://player_life_state_pair_result.txt"
const SERVER_TIMEOUT := 8.0
const CLIENT_CHECK_DELAY := 2.0

var _is_client := false
var _elapsed := 0.0
var _done := false
var _player: CharacterBody3D
var _client_pid := -1


func _initialize() -> void:
	_is_client = "--client" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	var manager := root.get_node_or_null(^"/root/NetworkManager")
	if manager == null:
		return _fail("NetworkManager must be an autoload.")

	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	current_scene = world
	_player = (load("res://player/player.tscn") as PackedScene).instantiate()
	_player.name = "Player"
	_player.set("owner_peer_id", 1)
	world.add_child(_player)
	_player.set_physics_process(false)

	await process_frame
	var peer := ENetMultiplayerPeer.new()
	if _is_client:
		# This test supplies an identical scene itself; normal registration would
		# change the child process into the lobby and free the test player.
		var registered := Callable(manager, "_on_connected_to_server")
		if get_multiplayer().connected_to_server.is_connected(registered):
			get_multiplayer().connected_to_server.disconnect(registered)
		if peer.create_client("127.0.0.1", PORT) != OK:
			return _fail("The client could not open its socket.")
	else:
		if FileAccess.file_exists(RESULT_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))
		if peer.create_server(PORT, 1) != OK:
			return _fail("The server could not bind UDP %d." % PORT)
	get_multiplayer().multiplayer_peer = peer
	manager.set("session_active", true)

	if _is_client:
		return
	get_multiplayer().peer_connected.connect(func(peer_id: int) -> void:
		manager.call("_mark_replication_ready", peer_id)
		_player.set("is_alive", false)
		_player.call("_publish_life_state")
	)
	_client_pid = OS.create_process(OS.get_executable_path(), [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "tests/player_life_state_pair_smoke.gd",
		"--", "--client",
	])
	if _client_pid <= 0:
		return _fail("Could not start the client process.")


func _process(delta: float) -> bool:
	if _done or not is_instance_valid(_player):
		return false
	_elapsed += delta
	if _is_client and _elapsed >= CLIENT_CHECK_DELAY:
		_done = true
		var verdict := "PASS" if not bool(_player.get("is_alive")) else "FAIL: client still alive"
		var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
		if file == null:
			return _fail("The client could not write its verdict.")
		file.store_string(verdict)
		file.close()
		quit()
		return false
	if not _is_client and FileAccess.file_exists(RESULT_PATH):
		_done = true
		var verdict := FileAccess.open(RESULT_PATH, FileAccess.READ).get_as_text().strip_edges()
		if verdict != "PASS":
			return _fail("the client reported: " + verdict)
		print("Player life-state pair smoke test passed: reliable death reached the other peer.")
		quit()
		return false
	if not _is_client and _elapsed >= SERVER_TIMEOUT:
		_done = true
		return _fail("The client never reported within %.0f seconds." % SERVER_TIMEOUT)
	return false


func _fail(message: String) -> bool:
	if _client_pid > 0:
		OS.kill(_client_pid)
	push_error("Player life-state pair smoke test failed: " + message)
	print("Player life-state pair smoke test FAILED: " + message)
	quit(1)
	return false

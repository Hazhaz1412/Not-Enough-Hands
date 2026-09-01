extends SceneTree

## Two real ENet processes pin the door-minigame handoff race and the client
## transform ownership that single-process smoke tests cannot reproduce.

const PORT := 47319
const RESULT_PATH := "user://door_minigame_pair_result.txt"
const TIMEOUT := 9.0

var _is_client := false
var _elapsed := 0.0
var _handoff_sent := false
var _door: DefenseDoor
var _player: CharacterBody3D
var _minigame: DoorGhostMinigame
var _claim_seen_before_start := false
var _started_at := -1.0
var _minigame_position := Vector3.ZERO


func _initialize() -> void:
	_is_client = "--client" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	var manager := root.get_node_or_null(^"/root/NetworkManager")
	if manager == null or root.get_node_or_null(^"/root/WorldReplicator") == null:
		return _fail("Required multiplayer autoloads are missing.")

	var peer := ENetMultiplayerPeer.new()
	if _is_client:
		var registered := Callable(manager, "_on_connected_to_server")
		if get_multiplayer().connected_to_server.is_connected(registered):
			get_multiplayer().connected_to_server.disconnect(registered)
		if peer.create_client("127.0.0.1", PORT) != OK:
			return _fail("Client could not connect to the test server.")
		get_multiplayer().multiplayer_peer = peer
		manager.set("session_active", true)
		var deadline := Time.get_ticks_msec() + 4000
		while peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			if Time.get_ticks_msec() > deadline:
				return _fail("Client connection timed out.")
			await process_frame
		_build_world()
		return

	if DirAccess.open("user://") and FileAccess.file_exists(RESULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))
	if peer.create_server(PORT, 1) != OK:
		return _fail("Server could not bind UDP %d." % PORT)
	get_multiplayer().multiplayer_peer = peer
	manager.set("session_active", true)
	_build_world()
	get_multiplayer().peer_connected.connect(func(peer_id: int) -> void:
		_player.owner_peer_id = peer_id
		manager.call("_mark_replication_ready", peer_id)
	)
	var pid := OS.create_process(OS.get_executable_path(), [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "tests/door_minigame_pair_smoke.gd",
		"--", "--client",
	])
	if pid <= 0:
		return _fail("Could not start the client process.")


func _build_world() -> void:
	var world := Node3D.new()
	world.name = "DoorPairWorld"
	root.add_child(world)
	current_scene = world

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(30.0, 0.2, 30.0)
	ground_collision.shape = ground_shape
	ground_collision.position.y = -0.1
	ground.add_child(ground_collision)
	world.add_child(ground)

	_door = (load("res://door/defense_door.tscn") as PackedScene).instantiate() as DefenseDoor
	_door.name = "Entrance01"
	_door.entrance_id = 1
	world.add_child(_door)

	_player = (load("res://player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_player.name = "PlayerRemote"
	_player.owner_peer_id = get_multiplayer().get_unique_id() if _is_client else 0
	_player.position = Vector3(0.0, 0.9, 2.0)
	world.add_child(_player)
	_minigame = _player.get_node("DoorGhostMinigame") as DoorGhostMinigame


func _process(delta: float) -> bool:
	_elapsed += delta
	if not is_instance_valid(_door) or not is_instance_valid(_player):
		return false

	if not _is_client:
		_drive_server()
		if _elapsed >= TIMEOUT:
			_read_result()
		return false

	_drive_client()
	return false


func _drive_server() -> void:
	if _elapsed >= 2.0 and _door.attack_phase == DefenseDoor.AttackPhase.IDLE:
		_door.begin_targeting(true, 0.0)
		_door.begin_exorcism()
	# Leave a full slow-sync interval before the reliable handoff. This forces
	# the client replica to see minigame_active=true first—the old rejection race.
	if not _handoff_sent and _elapsed >= 3.0:
		_handoff_sent = true
		_player.call("_hand_encounter_to_owner", _door, &"start_door_minigame")


func _drive_client() -> void:
	if _door.minigame_active and not _minigame.is_running():
		_claim_seen_before_start = true
	if _minigame.is_running() and _started_at < 0.0:
		_started_at = _elapsed
		_minigame_position = _player.global_position
		var camera := _player.get_node("CameraPivot/Camera3D") as Camera3D
		var forward := -camera.global_basis.z
		forward.y = 0.0
		if forward.normalized().dot(_minigame.outward) < 0.999:
			_write_result("camera did not face through the attacked door")
			quit()
			return
	if _started_at >= 0.0 and _elapsed - _started_at >= 0.75:
		if not _claim_seen_before_start:
			_write_result("handoff arrived before the replicated server claim; race was not exercised")
			quit()
			return
		if not _minigame.is_running():
			_write_result("encounter closed before its transform could be checked")
			quit()
			return
		if not _player.global_position.is_equal_approx(_minigame_position):
			_write_result("server reconciliation dragged the client away from the door viewpoint")
			quit()
			return
		_write_result("OK")
		quit()
	if _elapsed >= TIMEOUT - 1.0:
		_write_result("server-claimed encounter never started on its owning client")
		quit()


func _write_result(result: String) -> void:
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(result)


func _read_result() -> void:
	if not FileAccess.file_exists(RESULT_PATH):
		return _fail("Client wrote no multiplayer minigame verdict.")
	var result := FileAccess.get_file_as_string(RESULT_PATH).strip_edges()
	if result != "OK":
		return _fail(result)
	print("Door minigame pair smoke test passed: replicated claim, owner handoff, exterior camera, and transform stability.")
	quit()


func _fail(message: String) -> void:
	push_error("Door minigame pair smoke test failed: " + message)
	quit(1)

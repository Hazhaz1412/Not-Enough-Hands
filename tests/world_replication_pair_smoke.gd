extends SceneTree

## Two real processes, one real ENet socket: the half of replication that
## `world_replication_smoke.gd` cannot reach.
##
## That test pins the two ends in isolation - the guard that stops a client
## simulating, and the `apply_network_state()` methods that take the server's
## word for it. What it cannot do is send a packet, so everything *between* the
## ends went unchecked, and a whole channel could be silently dead.
##
## It was. Ghost transforms replicated fine while the body did not: the authored
## ghosts leave their root visible and hide the rig through `_set_manifested()`,
## which only the brain calls - and a client does not run the brain. A huntsman
## arrived at four players' machines as a bare moving light with no model on it.
## Nothing that ran in one process could have noticed.
##
## ## How it runs
##
## This script is both halves. Started normally it is the server: it stands up
## the world, spawns a second copy of itself with `--client`, and waits. The
## client connects, watches its own copy of the world for six seconds, and
## writes its verdict to `user://` - which the server then reads and asserts on,
## so a failure inside the child process still fails this test.
##
## The server deliberately outlives the client. A client whose server vanishes
## takes `NetworkManager.leave_session()`, which changes scene and frees the
## world out from under it - it would die before reporting.

const PORT := 47311
const RESULT_PATH := "user://world_replication_pair_result.txt"
const SERVER_SECONDS := 15.0
const CLIENT_SECONDS := 6.0
const DAMAGE := 30.0
## A pitch no call site rolls, so hearing it on the client can only mean the
## server's own event arrived rather than the client inventing a sound.
const SOUND_PITCH := 1.37

var _is_client := false
var _elapsed := 0.0
var _done := false
var _ghost: Node3D
var _visual: Node3D
var _decoy_ghost: Node3D
var _decoy_visual: Node3D
var _door: DefenseDoor
var _clock: NightClock
var _client_pid := -1
var _full_durability := 0.0
var _sound_sent := false
## Latched on the client the first time the ghost's teleport player changes, so
## a later sound of the statue's own cannot overwrite the evidence.
var _heard_pitch := -1.0
var _initial_pitch := 1.0


func _initialize() -> void:
	_is_client = "--client" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	var manager := root.get_node_or_null(^"/root/NetworkManager")
	if manager == null or root.get_node_or_null(^"/root/WorldReplicator") == null:
		return _fail("NetworkManager and WorldReplicator must both be autoloads.")

	_build_world()
	await process_frame
	var replicator := root.get_node(^"/root/WorldReplicator")
	replicator.call("_bind_scene_if_changed")
	# The receiver's authored list is intentionally wrong. NodePath-keyed state
	# must still reach StatueGhost; the old index protocol manifests HunterGhost.
	if _is_client:
		var receiver_order := replicator.get("_ghosts") as Array
		receiver_order.reverse()
		replicator.set("_ghosts", receiver_order)

	var peer := ENetMultiplayerPeer.new()
	if _is_client:
		# NetworkManager would otherwise register a player and pull this process
		# into the lobby scene, taking the world built above with it.
		var registered := Callable(manager, "_on_connected_to_server")
		if get_multiplayer().connected_to_server.is_connected(registered):
			get_multiplayer().connected_to_server.disconnect(registered)
		if peer.create_client("127.0.0.1", PORT) != OK:
			return _fail("The client could not open a socket to the server.")
	else:
		if DirAccess.open("user://") and FileAccess.file_exists(RESULT_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))
		if peer.create_server(PORT, 4) != OK:
			return _fail("The server could not bind UDP %d." % PORT)
	get_multiplayer().multiplayer_peer = peer
	manager.set("session_active", true)

	if _is_client:
		return
	get_multiplayer().peer_connected.connect(func(peer_id: int) -> void:
		manager.call("_mark_replication_ready", peer_id)
	)
	_client_pid = OS.create_process(OS.get_executable_path(), [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "tests/world_replication_pair_smoke.gd",
		"--", "--client",
	])
	if _client_pid <= 0:
		return _fail("Could not start the second process.")


## Both halves build the same nodes under the same names. The client's private
## ghost list is reversed above to prove authored ghosts travel by NodePath,
## while doors continue to use their own entrance_id.
func _build_world() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	current_scene = world

	_ghost = (load("res://ghosts/statue_ghost.tscn") as PackedScene).instantiate() as Node3D
	_ghost.name = "StatueGhost"
	world.add_child(_ghost)
	_decoy_ghost = (load("res://ghosts/hunter_ghost.tscn") as PackedScene).instantiate() as Node3D
	_decoy_ghost.name = "HunterGhost"
	world.add_child(_decoy_ghost)

	_door = (load("res://door/defense_door.tscn") as PackedScene).instantiate() as DefenseDoor
	_door.name = "Entrance01"
	_door.entrance_id = 1
	world.add_child(_door)

	_clock = (load("res://ui/night_clock.tscn") as PackedScene).instantiate() as NightClock
	_clock.name = "NightClock"
	world.add_child(_clock)


func _process(delta: float) -> bool:
	if _done or not is_instance_valid(_ghost) or not is_instance_valid(_decoy_ghost) \
		or not is_instance_valid(_door):
		return false
	if _visual == null:
		_visual = _ghost.get("visual_root") as Node3D
		_decoy_visual = _decoy_ghost.get("visual_root") as Node3D
		_full_durability = _door.current_durability
		_initial_pitch = _teleport_audio().pitch_scale
	_elapsed += delta

	if not _is_client:
		_drive_world()
		if _elapsed > SERVER_SECONDS:
			_done = true
			_read_client_verdict()
		return false

	var pitch := _teleport_audio().pitch_scale
	if _heard_pitch < 0.0 and not is_equal_approx(pitch, _initial_pitch):
		_heard_pitch = pitch
	if _elapsed > CLIENT_SECONDS:
		_done = true
		_write_client_verdict()
		quit()
	return false


func _teleport_audio() -> AudioStreamPlayer3D:
	return _ghost.get("teleport_audio") as AudioStreamPlayer3D


## The server is the only one that touches anything. Everything here is a change
## a client has no way of arriving at on its own.
func _drive_world() -> void:
	_ghost.global_position = Vector3(_elapsed, 1.0, 0.0)
	if _visual and not _visual.visible:
		_ghost.call("_set_manifested", true)
	if is_equal_approx(_door.current_durability, _full_durability):
		_door.take_damage(DAMAGE)
	# A ghost's one-shots are fired by the brain, and a client runs no brain, so
	# unless they travel as their own event they are heard on the host alone.
	if not _sound_sent and _elapsed > 1.0:
		_sound_sent = true
		var audio := _teleport_audio()
		audio.pitch_scale = SOUND_PITCH
		WorldNet.play_shared(audio)


func _write_client_verdict() -> void:
	var failures: Array[String] = []
	if _ghost.global_position.is_equal_approx(Vector3.ZERO):
		failures.append("no ghost transform arrived on the fast channel")
	if _visual == null or not _visual.visible:
		failures.append(
			"the ghost body never manifested; a client would see a light with no model"
		)
	if _decoy_visual == null or _decoy_visual.visible:
		failures.append(
			"Statue state manifested Hunter; authored ghost identity still follows list order"
		)
	if is_equal_approx(_door.current_durability, _full_durability):
		failures.append("no door durability arrived on the slow channel")
	if _clock.elapsed_game_minutes <= 0:
		failures.append("the night never arrived on the clock channel")
	if not is_equal_approx(_heard_pitch, SOUND_PITCH):
		failures.append(
			"the ghost's one-shot never arrived; every scream, horn and teleport "
			+ "would be the host's alone"
		)

	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("The client could not write its verdict.")
		return
	file.store_string("PASS" if failures.is_empty() else "FAIL: " + ", ".join(failures))
	file.close()


func _read_client_verdict() -> void:
	if not FileAccess.file_exists(RESULT_PATH):
		return _fail("The client never reported; it died before it could check anything.")
	var verdict := FileAccess.open(RESULT_PATH, FileAccess.READ).get_as_text().strip_edges()
	if verdict != "PASS":
		return _fail("the second process reported: " + verdict)
	print(
		"World replication pair smoke test passed: over a real socket a client took "
		+ "the ghost's NodePath-keyed position and body without manifesting the decoy, its one-shot audio, "
		+ "the door's durability, and the night."
	)
	quit()


func _fail(message: String) -> void:
	if _client_pid > 0:
		OS.kill(_client_pid)
	push_error("World replication pair smoke test failed: " + message)
	print("World replication pair smoke test FAILED: " + message)
	quit(1)

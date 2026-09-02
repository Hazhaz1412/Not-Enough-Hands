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
var _test_player: CharacterBody3D
var _decoy_ghost: Node3D
var _decoy_visual: Node3D
var _darkness_ghost: DarknessGhost
var _darkness_light: OmniLight3D
var _door: DefenseDoor
var _clock: NightClock
var _ritual: TotemRitual
var _hint_totem: RitualItem
var _client_pid := -1
var _full_durability := 0.0
var _spawn_sent := false
var _sound_sent := false
var _darkness_retreat_sent := false
var _totem_hint_sent := false
## Latched on the client the first time the ghost's teleport player changes, so
## a later sound of the statue's own cannot overwrite the evidence.
var _heard_pitch := -1.0
var _initial_pitch := 1.0
## The Statue spawn cue must arrive as a reliable event carrying its anchor.
## Otherwise an unreliable manifestation transition can be missed, or an
## unanchored sound can play from the ghost's old, inaudible position.
var _heard_statue_spawn_cue := false
var _client_force_rejected := false


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
		_client_force_rejected = not bool(_ghost.call("dev_force_spawn", _test_player))
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
	# The server uses this real players-group member as the target for
	# dev_force_spawn(), so the pair covers the same final distance gate and
	# reliable spawn cue as a production hunt instead of manually toggling the
	# Statue's visual.
	_test_player = CharacterBody3D.new()
	_test_player.name = "TestPlayer"
	_test_player.add_to_group(&"players")
	world.add_child(_test_player)
	_ghost.set_physics_process(false)
	_decoy_ghost = (load("res://ghosts/hunter_ghost.tscn") as PackedScene).instantiate() as Node3D
	_decoy_ghost.name = "HunterGhost"
	world.add_child(_decoy_ghost)
	_darkness_ghost = (
		(load("res://ghosts/darkness_ghost.tscn") as PackedScene).instantiate()
		as DarknessGhost
	)
	_darkness_ghost.name = "DarknessGhost"
	_darkness_ghost.auto_manifest = false
	world.add_child(_darkness_ghost)
	_darkness_ghost.set_physics_process(false)
	_darkness_ghost._has_been_seen = false
	_darkness_ghost._set_manifested(true)
	_darkness_ghost.encounter_phase = DarknessGhost.EncounterPhase.CHASING
	_darkness_light = OmniLight3D.new()
	_darkness_light.name = "DarknessTestRoomLight"
	_darkness_light.omni_range = 8.0
	_darkness_light.light_energy = 1.0
	_darkness_light.visible = false
	_darkness_light.add_to_group(&"local_light_sources")
	world.add_child(_darkness_light)
	_darkness_light.global_position = _darkness_ghost.global_position + Vector3.UP

	_door = (load("res://door/defense_door.tscn") as PackedScene).instantiate() as DefenseDoor
	_door.name = "Entrance01"
	_door.entrance_id = 1
	world.add_child(_door)

	_clock = (load("res://ui/night_clock.tscn") as PackedScene).instantiate() as NightClock
	_clock.name = "NightClock"
	world.add_child(_clock)

	# Authored on both peers at matching paths; the authority's 77-second hint
	# event must select this totem and make the client's copy glow as well.
	var brazier_placeholder := (
		(load("res://items/totem_brazier.tscn") as PackedScene).instantiate()
		as TotemBrazier
	)
	brazier_placeholder.name = "BrazierPlaceholder"
	world.add_child(brazier_placeholder)
	_hint_totem = (load("res://items/totem.tscn") as PackedScene).instantiate() as RitualItem
	_hint_totem.name = "HintTotem"
	world.add_child(_hint_totem)
	_ritual = TotemRitual.new()
	_ritual.name = "TotemRitual"
	_ritual.is_complete = true
	world.add_child(_ritual)
	_ritual.set_process(false)


func _process(delta: float) -> bool:
	if _done or not is_instance_valid(_ghost) or not is_instance_valid(_test_player) \
		or not is_instance_valid(_decoy_ghost) \
		or not is_instance_valid(_darkness_ghost) \
		or not is_instance_valid(_door) \
		or not is_instance_valid(_ritual) \
		or not is_instance_valid(_hint_totem):
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
	if not _heard_statue_spawn_cue \
		and _teleport_audio().playing \
		and is_equal_approx(pitch, _initial_pitch) \
		and _spawn_distance() >= float(_ghost.get("ambush_min_distance")):
		_heard_statue_spawn_cue = true
	if _heard_pitch < 0.0 and not is_equal_approx(pitch, _initial_pitch):
		_heard_pitch = pitch
	if _elapsed > CLIENT_SECONDS:
		_done = true
		_write_client_verdict()
		quit()
	return false


func _teleport_audio() -> AudioStreamPlayer3D:
	return _ghost.get("teleport_audio") as AudioStreamPlayer3D


func _spawn_distance() -> float:
	return Vector2(
		_ghost.global_position.x - _test_player.global_position.x,
		_ghost.global_position.z - _test_player.global_position.z
	).length()


## The server is the only one that touches anything. Everything here is a change
## a client has no way of arriving at on its own.
func _drive_world() -> void:
	var manager := root.get_node(^"/root/NetworkManager")
	if not _spawn_sent \
		and _elapsed > 1.0 \
		and not (manager.get("replication_ready_peers") as Dictionary).is_empty():
		_spawn_sent = bool(_ghost.call("dev_force_spawn", _test_player))
	if is_equal_approx(_door.current_durability, _full_durability):
		_door.take_damage(DAMAGE)
	# A ghost's one-shots are fired by the brain, and a client runs no brain, so
	# unless they travel as their own event they are heard on the host alone.
	if _spawn_sent and not _sound_sent and _elapsed > 2.0:
		_sound_sent = true
		var audio := _teleport_audio()
		audio.pitch_scale = SOUND_PITCH
		WorldNet.play_shared(audio)
	# The server alone exposes a previously seen Darkness ghost to a real
	# environmental Light3D. The client has no local exposure, so only replicated
	# encounter state can make this manifestation retreat there.
	if not _darkness_retreat_sent and _elapsed > 3.0:
		_darkness_retreat_sent = true
		_darkness_ghost._has_been_seen = true
		_darkness_light.visible = true
		_darkness_ghost._update_light_exposure(
			_darkness_ghost.light_death_seconds + 0.01
		)
	if not _totem_hint_sent and _elapsed > 3.5:
		_totem_hint_sent = _ritual._trigger_next_totem_hint()


func _write_client_verdict() -> void:
	var failures: Array[String] = []
	if _ghost.global_position.is_equal_approx(Vector3.ZERO):
		failures.append("no ghost transform arrived on the fast channel")
	if not _client_force_rejected:
		failures.append("a client was allowed to mutate the server-owned Statue directly")
	if _spawn_distance() < float(_ghost.get("ambush_min_distance")):
		failures.append("the server manifested Statue inside a player's minimum safety radius")
	if _visual == null or not _visual.visible:
		failures.append(
			"the ghost body never manifested; a client would see a light with no model"
		)
	if _decoy_visual == null or _decoy_visual.visible:
		failures.append(
			"Statue state manifested Hunter; authored ghost identity still follows list order"
		)
	if _darkness_ghost.is_dead() or _darkness_ghost.is_manifested():
		failures.append(
			"Darkness environmental-light retreat did not replicate from server to client"
		)
	if is_equal_approx(_door.current_durability, _full_durability):
		failures.append("no door durability arrived on the slow channel")
	if _clock.elapsed_game_minutes <= 0:
		failures.append("the night never arrived on the clock channel")
	if not _hint_totem.is_guidance_highlight_active():
		failures.append("the authority's totem hint did not highlight the same client totem")
	if not _heard_statue_spawn_cue:
		failures.append(
			"the statue manifested without playing its spawn cue at the replicated position"
		)
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
		+ "the ghost's NodePath-keyed position and body without manifesting the decoy, "
		+ "could not mutate the server-owned Statue, received its reliable spawn cue "
		+ "outside the player safety radius, its one-shot audio, "
		+ "Darkness environmental-light retreat, the door's durability, the night, "
		+ "and the authority-selected totem hint."
	)
	quit()


func _fail(message: String) -> void:
	if _client_pid > 0:
		OS.kill(_client_pid)
	push_error("World replication pair smoke test failed: " + message)
	print("World replication pair smoke test FAILED: " + message)
	quit(1)

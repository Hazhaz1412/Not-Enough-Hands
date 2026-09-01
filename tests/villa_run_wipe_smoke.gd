extends SceneTree

## A wiped team hands the room back.
##
## The night had no exit. Every player dying left the villa standing with a
## Game Over card on it and `game_started` still true, so nobody could restart
## and nobody could rejoin - the room was finished but never over.
##
## The decision is made entirely on the server, so one process is enough here:
## what is pinned is that villa_main notices the house is empty of the living
## and that NetworkManager then reopens the lobby with the ready flags cleared.
## The socket half of the same story - being refused during a run and admitted
## after it - is `lobby_reset_pair_smoke.gd`.
##
## Expect one engine error in the log: `Attempt to call RPC with unknown peer
## ID: 2`. Peer 2 has no process of its own here, and that error is the death of
## the second player being handed to the machine that owns it, exactly as
## `world_replication_smoke.gd` documents for the door encounter.

const PORT := 47313
const TIMEOUT := 90.0

var _manager: Node
var _villa: Node
var _elapsed := 0.0
var _wiped := false
var _ended := false
var _done := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_manager = root.get_node_or_null(^"/root/NetworkManager")
	if _manager == null:
		return _fail("NetworkManager must be an autoload.")

	# A two-player session already in its night. The engine reports is_server()
	# off a real peer, which is what the authority guards actually ask.
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 4) != OK:
		return _fail("Could not bind UDP %d." % PORT)
	get_multiplayer().multiplayer_peer = peer
	_manager.set("session_active", true)
	_manager.set("game_started", true)
	_manager.set("players", {
		1: {"name": "Host", "ready": true},
		2: {"name": "Guest", "ready": true},
	})
	_manager.connect("run_ended", func(_reason: String) -> void: _ended = true)

	_villa = (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(_villa)
	current_scene = _villa


func _process(delta: float) -> bool:
	if _done:
		return false
	_elapsed += delta
	if _elapsed > TIMEOUT:
		_done = true
		return _fail("nothing ended the run within %.0f seconds." % TIMEOUT)

	var players: Array = get_nodes_in_group(&"players")
	if not _wiped:
		if players.size() < 2:
			return false
		_wipe(players)
		return false

	if _ended:
		_done = true
		_check_lobby_is_open()
	return false


## Reproduces the multiplayer soft-lock: every guest falls into a revivable
## downed state, then the listen host is killed last. There is nobody standing
## who can revive the guests, and presenting the host's death must not pause the
## authoritative server before it schedules the lobby return.
func _wipe(players: Array) -> void:
	_wiped = true
	var ghost := get_first_node_in_group(&"hostile_ghosts") as Node3D
	var ordered: Array[Node] = []
	var host: Node = null
	for node: Node in players:
		if int(node.get("owner_peer_id")) == 1:
			host = node
		else:
			ordered.append(node)
	if host:
		ordered.append(host)
	for node: Node in ordered:
		node.call("kill_by_ghost", ghost)
	var downed_count := 0
	for node: Node in players:
		if bool(node.get("is_alive")):
			_done = true
			_fail("a standing player survived the wipe, so the test proves nothing.")
			return
		if bool(node.get("is_downed")):
			downed_count += 1
	if downed_count == 0:
		_done = true
		_fail("the wipe created no downed teammate, so it did not reproduce the soft-lock.")
		return
	if paused:
		_done = true
		_fail("the listen host's death paused the authoritative server.")


func _check_lobby_is_open() -> bool:
	if bool(_manager.get("game_started")):
		return _fail("the run stayed started; the server would still refuse everyone.")
	var players: Dictionary = _manager.get("players")
	for peer_id: int in players:
		if bool((players[peer_id] as Dictionary).get("ready", false)):
			return _fail("a ready flag survived the wipe; the lobby would start itself again.")
	if paused:
		return _fail("the tree came back paused, so the lobby would be drawn but dead to input.")
	print(
		"Villa run wipe smoke test passed: the last death ended the run, cleared every "
		+ "ready flag and handed the room back unpaused."
	)
	quit()
	return true


func _fail(message: String) -> bool:
	push_error("Villa run wipe smoke test failed: " + message)
	print("Villa run wipe smoke test FAILED: " + message)
	quit(1)
	return false

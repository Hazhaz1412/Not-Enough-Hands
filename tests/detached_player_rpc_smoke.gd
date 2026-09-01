extends SceneTree

## An RPC that arrives after the run has ended must not be the crash.
##
## A packet is not delivered where it was sent from. Ending a night swaps the
## villa for the lobby, and for the frame or two that takes, every client is
## still streaming `_submit_network_input` at its own rate, because none of them
## has heard yet. Those packets land on a player body that has already left the
## tree with the map - and `Node.multiplayer` is null outside the tree, so a
## guard opening with `multiplayer.is_server()` dereferences null.
##
## A debug build reports "Cannot call method 'is_server' on a null value" and
## carries on, which is exactly why every headless test in this suite missed it.
## The exported Linux server has no such check and segfaulted instead: an
## Edgegap deployment died with exit code 139 every single time a wiped team was
## handed back to the lobby.
##
## So this pins the state rather than the symptom: out of the tree, every guard
## an RPC entry point opens with has to be answerable without touching
## `multiplayer`, and the entry point itself has to be a no-op.

const PLAYER_SCENE := "res://player/player.tscn"

var _player: CharacterBody3D
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as CharacterBody3D
	if _player == null:
		return _fail("player.tscn did not instantiate as a CharacterBody3D.")
	_player.owner_peer_id = 2
	root.add_child(_player)
	await process_frame

	# In the tree the body resolves a MultiplayerAPI, which is what every guard
	# below has always assumed.
	if _player.multiplayer == null:
		return _fail("A player inside the tree should resolve a MultiplayerAPI.")

	# Exactly the state a finished run leaves behind for the packets still in
	# flight towards it.
	root.remove_child(_player)
	if _player.multiplayer != null:
		return _fail(
			"This test proves nothing: a detached body still resolved a "
			+ "MultiplayerAPI, so it never reproduces the null the server died on."
		)

	_check("_network_is_reachable", not _player._network_is_reachable())
	_check("_rpc_reached_authority", not _player._rpc_reached_authority())
	_check("_rpc_sender_owns_player", not _player._rpc_sender_owns_player())

	# The entry point itself: reaching it must be a no-op, not a dereference.
	# Any input it accepted here would also be input applied to a body that is
	# on its way to being freed.
	_player._submit_network_input(
		Vector2.ONE, true, true, true, true, 1.0, 0.5, 999
	)
	if _player._last_processed_input_sequence == 999:
		_failures.append("a detached body applied input from a packet that outlived its run")

	# Paths are read off the current scene, which is the other thing that is
	# gone: `get_tree()` is null out of the tree for the same reason.
	if not _player._scene_path_of(_player).is_empty():
		_failures.append("_scene_path_of() answered from outside the tree")
	if _player._scene_node(^"Anything") != null:
		_failures.append("_scene_node() answered from outside the tree")

	_player.free()
	if not _failures.is_empty():
		return _fail(", ".join(_failures))
	print(
		"Detached player RPC smoke test passed: a packet that outlives its run "
		+ "finds every guard answerable and changes nothing."
	)
	quit()


## Each guard is called on the detached body: the call surviving at all is half
## the assertion, and the answer being "no" is the other half.
func _check(guard_name: String, held: bool) -> void:
	if not held:
		_failures.append("%s() let a packet through to a body that has left the tree" % guard_name)


func _fail(message: String) -> void:
	push_error("Detached player RPC smoke test failed: " + message)
	print("Detached player RPC smoke test FAILED: " + message)
	quit(1)

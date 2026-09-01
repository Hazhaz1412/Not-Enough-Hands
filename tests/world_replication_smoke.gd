extends SceneTree

## Covers the server-authority layer the world systems gained: the one predicate
## they all gate on, and the `apply_network_state()` methods that are the only
## way a client's world is allowed to change.
##
## What this can and cannot reach. Standing up two real peers needs two
## processes, so nothing here sends a packet. What it does instead is pin the
## two halves that a real session is made of and that a smoke test *can* hold:
##
##   1. the guard - with a session active and a non-server peer, a ghost, a
##      door, the clock and the ritual must all decline to simulate. This is the
##      half that stops four machines running four different nights.
##   2. the appliers - given the state a server would have sent, each system
##      must land in exactly that state, including the visible consequences
##      (a door that hits zero is breached, a reserve at zero is a blackout).
##
## Between them, a break in either direction fails here rather than in a
## four-player playtest.
##
## The client is faked the way the engine really reports one: an ENet peer
## created as a client and never connected already answers `is_server()` false,
## which is precisely what `WorldNet` asks. The session flag is set on the real
## NetworkManager autoload - which *does* exist under `--script`, even though
## its name is not a resolvable identifier there - rather than on a stub, since
## a second node called NetworkManager is simply renamed by the engine and the
## lookup would keep finding the real one.

const FRAME := 1.0 / 60.0

var _session_was_active: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _test_offline_is_authority():
		return
	if not _test_a_client_is_not_authority():
		return
	if not _test_guards_stop_client_simulation():
		return
	if not _test_clock_applies_server_time():
		return
	if not _test_door_applies_server_damage():
		return
	if not _test_power_applies_server_reserve():
		return
	if not _test_brazier_applies_server_fire():
		return
	if not _test_spawn_without_a_session():
		return
	if not _test_ghosts_expose_a_presentation_seam():
		return
	if not await _test_an_encounter_is_handed_to_its_owner():
		return
	print(
		'World replication smoke test passed: offline and server simulate, a client does not, '
		+ 'clock/door/power/brazier all take the server state they are given, '
		+ 'every ghost still exposes the seam a client animates it through, '
		+ 'and an encounter is handed to the peer that started it.'
	)
	quit()


## Single-player, the smoke tests and the tools scripts all run with no network
## layer at all. Authority has to be true there or every guard added for
## multiplayer would switch the whole game off.
func _test_offline_is_authority() -> bool:
	if not WorldNet.is_world_authority():
		return _fail('With no session at all the world must still simulate.')
	if WorldNet.is_network_client():
		return _fail('Nothing is a network client without a session.')
	return true


func _test_a_client_is_not_authority() -> bool:
	_become_client()
	if WorldNet.is_world_authority():
		return _fail('A peer that is not the server must not claim world authority.')
	if not WorldNet.is_network_client():
		return _fail('A non-server peer in a live session is a client.')
	_become_server()
	if not WorldNet.is_world_authority():
		return _fail('The server of a session must hold world authority.')
	_become_offline()
	return true


## The guard itself, on the four systems whose divergence the report called out:
## the night, an attacked door, the ritual's item population, and a ghost.
func _test_guards_stop_client_simulation() -> bool:
	var clock := _clock()
	var door := _door()
	var ritual := _ritual()
	root.add_child(clock)
	root.add_child(door)
	root.add_child(ritual)

	_become_client()

	var minutes_before: int = clock.elapsed_game_minutes
	clock.advance_real_seconds(60.0)
	if clock.elapsed_game_minutes != minutes_before:
		_become_offline()
		return _fail('A client advanced the night by itself.')
	if clock.skip_minutes(30) != 0:
		_become_offline()
		return _fail('A client granted itself ritual time; the burn is the server\'s.')

	door.begin_targeting(true, 0.0)
	var durability_before: float = door.current_durability
	for step: int in 240:
		door._physics_process(FRAME)
	if not is_equal_approx(door.current_durability, durability_before):
		_become_offline()
		return _fail('A client ran a door attack and damaged its own copy of the door.')

	ritual.restock()
	if not get_nodes_in_group(&'totems').is_empty():
		_become_offline()
		return _fail('A client scattered its own totems instead of taking the server\'s.')

	_become_offline()
	# The same calls, now as the authority, have to actually do something -
	# otherwise the guard above would pass by having broken the game outright.
	clock.advance_real_seconds(60.0)
	if clock.elapsed_game_minutes == minutes_before:
		return _fail('Offline the night must still run.')

	clock.queue_free()
	door.queue_free()
	ritual.queue_free()
	return true


func _test_clock_applies_server_time() -> bool:
	var clock := _clock()
	root.add_child(clock)
	var seen: Array[int] = []
	clock.minute_changed.connect(func(minutes: int, _formatted: String) -> void:
		seen.append(minutes)
	)
	var start: int = clock.elapsed_game_minutes
	clock.apply_network_time(start + 45, 90, false)
	if clock.elapsed_game_minutes != start + 45:
		clock.queue_free()
		return _fail('The clock did not take the server\'s elapsed minutes.')
	if clock.current_minutes_of_day != 90:
		clock.queue_free()
		return _fail('The clock did not take the server\'s time of day.')
	# The ritual's completion check hangs off this signal, so a jump the
	# listeners never hear would leave the objective running past its ceiling.
	if seen.is_empty():
		clock.queue_free()
		return _fail('Applying server time emitted no minute_changed.')
	clock.queue_free()
	return true


## A door is the case where the state and its visible consequence can disagree:
## a client showing an intact door it can already walk through, or a solid one
## with a hole behind it.
func _test_door_applies_server_damage() -> bool:
	var door := _door()
	root.add_child(door)
	# Counters live in arrays because a GDScript lambda captures by value: a
	# plain `breaches += 1` inside the callback increments a copy and the
	# assertion below would never see it.
	var breaches: Array[int] = [0]
	var rebuilds: Array[int] = [0]
	door.breached.connect(func(_d: Node) -> void: breaches[0] += 1)
	door.rebuilt.connect(func(_d: Node) -> void: rebuilds[0] += 1)

	door.apply_network_state(40.0, 100.0, DefenseDoor.AttackPhase.WEAK_ATTACK, false, false)
	if not is_equal_approx(door.current_durability, 40.0):
		door.queue_free()
		return _fail('The door did not take the server durability.')
	if door.attack_phase != DefenseDoor.AttackPhase.WEAK_ATTACK:
		door.queue_free()
		return _fail('The door did not take the server attack phase.')

	door.apply_network_state(0.0, 10.0, DefenseDoor.AttackPhase.IDLE, false, true)
	if breaches[0] != 1:
		door.queue_free()
		return _fail('Durability reaching zero did not breach the door on the client.')
	door.apply_network_state(60.0, 100.0, DefenseDoor.AttackPhase.IDLE, false, false)
	if rebuilds[0] != 1:
		door.queue_free()
		return _fail('A repaired door did not rebuild on the client.')
	door.queue_free()
	return true


func _test_power_applies_server_reserve() -> bool:
	var power := PowerManager.new()
	root.add_child(power)
	var blackouts: Array[int] = [0]
	var restores: Array[int] = [0]
	power.blackout.connect(func() -> void: blackouts[0] += 1)
	power.power_restored.connect(func() -> void: restores[0] += 1)

	power.apply_network_state(0.0, true, false)
	if not power.is_blackout or blackouts[0] != 1:
		power.queue_free()
		return _fail('The client did not go dark when the server said the reserve was gone.')
	power.apply_network_state(500.0, false, false)
	if power.is_blackout or restores[0] != 1:
		power.queue_free()
		return _fail('The client did not come back up with the server.')
	if not is_equal_approx(power.current_power, 500.0):
		power.queue_free()
		return _fail('The client did not take the server reserve level.')
	power.queue_free()
	return true


func _test_brazier_applies_server_fire() -> bool:
	var brazier := _brazier()
	root.add_child(brazier)
	brazier.apply_network_state(false, 1.25)
	if brazier.is_lit:
		brazier.queue_free()
		return _fail('The fire stayed lit on a client after the server put it out.')
	if not is_equal_approx(brazier.hold_progress, 1.25):
		brazier.queue_free()
		return _fail('The hold bar on a client is not the server\'s.')
	brazier.apply_network_state(true, 0.0)
	if not brazier.is_lit:
		brazier.queue_free()
		return _fail('The fire did not come back when the server relit it.')
	brazier.queue_free()
	return true


## The seam a client animates a ghost through.
##
## Every ghost keeps its body separate from its brain in the same place: an
## `_update_presentation()` that reads `state` and `velocity` and drives the
## limbs, shader, lantern and footsteps off them. A client's `_physics_process`
## returns before the brain runs, so this method is the *only* thing keeping a
## replicated ghost from sliding around frozen - and renaming it would break
## that in a way nothing else would notice.
func _test_ghosts_expose_a_presentation_seam() -> bool:
	for path: String in [
		'res://ghosts/hunter_ghost.tscn',
		'res://ghosts/crawler_ghost.tscn',
		'res://ghosts/statue_ghost.tscn',
	]:
		var ghost := (load(path) as PackedScene).instantiate()
		var has_seam: bool = ghost.has_method('_update_presentation')
		var is_body: bool = ghost is CharacterBody3D
		ghost.free()
		if not has_seam:
			return _fail(
				'%s has no _update_presentation(); a client could place it but never animate it.'
				% path
			)
		if not is_body:
			return _fail('%s is not a CharacterBody3D, so its velocity cannot be replicated.' % path)
	return true


## Outside a session - single-player, every smoke test, every tools script -
## spawn() has to be the plain add_child it replaced, whether or not a
## replicator happens to be in the tree.
func _test_spawn_without_a_session() -> bool:
	var parent := Node3D.new()
	root.add_child(parent)
	var node := WorldNet.spawn(
		load('res://items/totem.tscn') as PackedScene,
		parent,
		Vector3(3.0, 1.0, -2.0),
		1.0,
		'SpawnedTotem'
	) as Node3D
	if node == null:
		parent.queue_free()
		return _fail('spawn() returned nothing where the world is simulated locally.')
	if node.get_parent() != parent:
		parent.queue_free()
		return _fail('spawn() did not add the node under the parent it was given.')
	if node.name != 'SpawnedTotem':
		parent.queue_free()
		return _fail('spawn() did not keep the name the caller chose.')
	if not node.global_position.is_equal_approx(Vector3(3.0, 1.0, -2.0)):
		parent.queue_free()
		return _fail('spawn() placed the node at %s, not where it was asked.' % node.global_position)
	parent.queue_free()
	return true


## The door encounter must be played on the machine of whoever pressed E.
##
## On the server, another player's node is only a replica: its camera is not
## current and `_configure_player_presentation()` has hidden its HUD, so playing
## the encounter there would run it invisibly, aimed by nobody, while the person
## who pressed E watched their character stand frozen at the door. So the server
## claims the door and hands the encounter over instead.
##
## What is pinned here: the claim happens (`begin_exorcism()` ran), the local
## minigame does *not* start, and the body is marked as away so the ghosts and
## the other players see it stand still.
##
## Expect one engine error in the log - `Attempt to call RPC with unknown peer
## ID: 4242`. Peer 4242 is the point: there is no second process in a smoke
## test, so the handoff has nowhere to land. That error *is* the evidence the
## encounter was sent away rather than played here.
func _test_an_encounter_is_handed_to_its_owner() -> bool:
	var door := _door()
	root.add_child(door)
	var player := _player()
	root.add_child(player)
	await process_frame

	_become_server()
	# Somebody else's player, which is exactly what the server holds a replica of.
	player.owner_peer_id = 4242
	if not door.begin_targeting(true, 0.0):
		_become_offline()
		return _fail('Could not put the door into an attack for the encounter to answer.')

	var started: bool = player.start_door_minigame(door)
	var handed_over: bool = player.is_remote_encounter_active()
	var played_here: bool = player.is_door_minigame_active()
	var claimed: bool = door.minigame_active
	_become_offline()

	if not started:
		return _fail('The server refused an encounter it should have handed to its owner.')
	if not claimed:
		return _fail('The server did not claim the door with begin_exorcism().')
	if played_here:
		return _fail('The encounter was played on the server instead of on its owner\'s machine.')
	if not handed_over:
		return _fail('The server did not mark the player as away in an encounter.')
	if not player._is_any_minigame_active():
		return _fail('A player away in an encounter must still count as busy, or the server walks them.')

	# The other half: on the authority the outcome is applied straight to the
	# door, which is the path single-player and the host's own player take.
	var script: GDScript = load('res://player/player.gd')
	player.owner_peer_id = 1
	player.report_door_outcome(door, script.DoorOutcome.CLEARED)
	if door.minigame_active:
		return _fail('A cleared encounter did not hand the door back.')
	if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
		return _fail('A cleared encounter did not drive the attacker away.')

	door.queue_free()
	player.queue_free()
	return true


# --- fakery -----------------------------------------------------------------

## A stand-in for the NetworkManager autoload, which does not exist under
## `godot --headless --script`. WorldNet only ever reads `session_active` off
## it, so that is all this has.
func _become_client() -> void:
	_open_session()
	var peer := ENetMultiplayerPeer.new()
	peer.create_client('127.0.0.1', 47999)
	get_multiplayer().multiplayer_peer = peer


func _become_server() -> void:
	_open_session()
	var peer := ENetMultiplayerPeer.new()
	peer.create_server(47998, 3)
	get_multiplayer().multiplayer_peer = peer


func _become_offline() -> void:
	if get_multiplayer().multiplayer_peer:
		get_multiplayer().multiplayer_peer.close()
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var manager := _manager()
	if manager:
		manager.set('session_active', _session_was_active)


func _open_session() -> void:
	var manager := _manager()
	if manager == null:
		push_error('No NetworkManager autoload; the guard cannot be exercised.')
		return
	_session_was_active = bool(manager.get('session_active'))
	manager.set('session_active', true)


func _manager() -> Node:
	return root.get_node_or_null(^'/root/NetworkManager')


func _player() -> CharacterBody3D:
	return (load('res://player/player.tscn') as PackedScene).instantiate() as CharacterBody3D


func _clock() -> NightClock:
	return (load('res://ui/night_clock.tscn') as PackedScene).instantiate() as NightClock


func _door() -> DefenseDoor:
	return (load('res://door/defense_door.tscn') as PackedScene).instantiate() as DefenseDoor


func _brazier() -> TotemBrazier:
	return (load('res://items/totem_brazier.tscn') as PackedScene).instantiate() as TotemBrazier


func _ritual() -> TotemRitual:
	return TotemRitual.new()


func _fail(message: String) -> bool:
	push_error('World replication smoke test failed: ' + message)
	print('World replication smoke test FAILED: ' + message)
	quit(1)
	return false

extends Node

## Server-authoritative replication of the *world*: the ghosts, the defense
## doors, the power reserve, the totem-ritual items and the night clock.
##
## Before this existed only the players were networked. Every peer instanced
## the same map and then simulated it independently, so each one ran its own
## ghosts, drained its own battery and scattered its own totems - the players
## lined up and nothing else did. This node is the missing half.
##
## ## The split
##
## `NetworkManager.is_world_authority()` is the one predicate the world systems
## ask before they simulate anything: true in single-player and on the server,
## false on a client. Each system guards its own simulation with it; this node
## owns nothing but transport, exactly the way the breaker owns no minigame and
## the minigame owns no power logic.
##
## So a client's ghosts, doors, power manager and ritual are inert scene
## furniture, and what makes them move is the state that arrives here.
##
## ## What travels, and how often
##
## | Channel | Rate | Reliability | Carries |
## |---|---|---|---|
## | fast | 20 Hz | unreliable ordered | ghost and loose-item transforms |
## | slow | 5 Hz | reliable | door durability, power reserve, the brazier |
## | events | on change | reliable | spawn/despawn, pickup, clock, blackout |
##
## The fast channel is allowed to drop packets because a newer one is always
## right behind it. Everything whose *loss* would desynchronise the world -
## an item appearing, a door breaking, a totem burning thirty minutes off the
## night - goes reliably instead, and is repeated in the snapshot below.
##
## ## Late joiners
##
## A peer that finishes loading mid-night has none of the history. It gets one
## `_apply_snapshot()` covering every channel at once, sent off
## `NetworkManager.player_replication_ready`, so it starts from the real world
## rather than from whatever the map generated locally.
##
## ## Identity
##
## Two kinds of thing are replicated and they are addressed differently.
##
## Authored nodes - the three ghosts each map's scene contains, the seven
## defense doors, the power manager, the clock - exist on every peer already
## because they are in the same scene file. Ghosts are addressed by their index
## in a name-sorted list captured when the scene binds; doors by their own
## `entrance_id`. Nothing has to be spawned for them.
##
## Runtime things - the huntsmen that come through a breach, the totems and
## firewood the ritual drops - do not exist on a client at all, so they carry a
## replication id assigned by the server and are created on demand.

const FAST_INTERVAL := 1.0 / 20.0
const SLOW_INTERVAL := 1.0 / 5.0
## Prefix for replicated node names, so the same entity has the same NodePath
## on every peer.
const ENTITY_PREFIX := "RepEnt_"

# --- shared by both sides ---------------------------------------------------
var _scene_root: Node = null
## Ghosts the scene itself authored, name-sorted so server and client agree on
## the order without sending a path per packet.
var _ghosts: Array[Node3D] = []
## replication id -> node, for the things that are spawned rather than authored.
var _entities: Dictionary = {}

# --- server only ------------------------------------------------------------
var _entity_scene: Dictionary = {}
var _entity_ids: Dictionary = {}
var _next_entity_id: int = 1
## replication id -> peer id currently carrying it, 0 for loose in the world.
var _holders: Dictionary = {}
var _fast_accum: float = 0.0
var _slow_accum: float = 0.0
var _clock_bound: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	NetworkManager.player_replication_ready.connect(_on_peer_replication_ready)


func _physics_process(delta: float) -> void:
	if not NetworkManager.session_active:
		# Single-player: every system is its own authority and nothing here has
		# any work to do.
		return
	_bind_scene_if_changed()
	if _scene_root == null or not NetworkManager.is_world_authority():
		return
	_bind_clock_if_needed()
	_fast_accum -= delta
	if _fast_accum <= 0.0:
		_fast_accum = FAST_INTERVAL
		_broadcast_fast()
	_slow_accum -= delta
	if _slow_accum <= 0.0:
		_slow_accum = SLOW_INTERVAL
		_broadcast_slow()


# =============================================================================
# Scene binding
# =============================================================================

## The replicator outlives every map, so it re-reads the world whenever the
## current scene changes rather than being wired up by each map in turn.
func _bind_scene_if_changed() -> void:
	var current := get_tree().current_scene
	if current == _scene_root:
		return
	_scene_root = current
	_ghosts.clear()
	_entities.clear()
	_entity_scene.clear()
	_entity_ids.clear()
	_holders.clear()
	_next_entity_id = 1
	_clock_bound = false
	if _scene_root == null:
		return
	# Captured once, so a huntsman that later comes through a breach is a
	# replicated entity rather than silently shifting every ghost's index.
	var authored: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"hostile_ghosts"):
		var ghost := node as Node3D
		if ghost:
			authored.append(ghost)
	authored.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.name < b.name)
	_ghosts = authored


## The clock is the one channel that is event-driven from the other side: it
## already emits a signal every in-game minute, so there is no reason to poll it.
func _bind_clock_if_needed() -> void:
	if _clock_bound:
		return
	var clock := _clock()
	if clock == null:
		return
	_clock_bound = true
	if clock.has_signal(&"minute_changed"):
		clock.connect(&"minute_changed", _on_clock_minute_changed)
	if clock.has_signal(&"victory_reached"):
		clock.connect(&"victory_reached", _on_clock_victory)


func _clock() -> Node:
	return get_tree().get_first_node_in_group(&"night_clock")


func _power() -> Node:
	return get_tree().get_first_node_in_group(&"power_manager")


# =============================================================================
# Server: spawning replicated entities
# =============================================================================

## The server-side entry point for anything created while the night is running.
## Adds `scene` under `parent`, gives it a replication id and a name derived
## from that id, and creates the same node on every client. Returns the node so
## the caller can go on configuring it exactly as it did before.
##
## On a client this returns null: the caller is not the authority and the node
## will arrive through `_spawn_entity` instead.
## `position` and `rotation_y` are taken up front rather than left to the caller
## afterwards, so the very first packet already places the thing correctly - a
## totem that spawned at the origin and only slid to its room on the next
## 20 Hz tick would be visible doing it.
func spawn(
	scene: PackedScene,
	parent: Node,
	position: Vector3 = Vector3.ZERO,
	rotation_y: float = 0.0,
	scene_path: String = "",
	node_name: String = ""
) -> Node:
	if scene == null or parent == null:
		return null
	if not NetworkManager.is_world_authority():
		return null
	var node := scene.instantiate()
	if not node_name.is_empty():
		node.name = node_name
	parent.add_child(node)
	var node_3d := node as Node3D
	if node_3d:
		node_3d.global_position = position
		node_3d.rotation.y = rotation_y
	if not NetworkManager.session_active:
		# Single-player still wants the node, just none of the bookkeeping.
		return node
	var id := _next_entity_id
	_next_entity_id += 1
	if node_name.is_empty():
		node.name = ENTITY_PREFIX + str(id)
	_entities[id] = node
	_entity_ids[node.get_instance_id()] = id
	_entity_scene[id] = scene_path if not scene_path.is_empty() else scene.resource_path
	_holders[id] = 0
	_spawn_entity.rpc(
		id, str(_entity_scene[id]), _path_from_scene(parent), position, rotation_y, str(node.name)
	)
	return node


## Tells every client which player is carrying `item`, or that it is loose
## again. The pickup itself stays where it always was - in the player's own
## `try_pick_up_item()`/`release_held_item()` - this only mirrors the outcome.
func report_holder(item: Node, peer_id: int) -> void:
	if not NetworkManager.session_active or not NetworkManager.is_world_authority():
		return
	if item == null:
		return
	var id := int(_entity_ids.get(item.get_instance_id(), 0))
	if id == 0:
		return
	if int(_holders.get(id, 0)) == peer_id:
		return
	_holders[id] = peer_id
	_set_entity_holder.rpc(id, peer_id)


## Deliberately a sweep rather than a `tree_exiting` hook. `reparent()` fires
## the tree signals too, and an item changes parent every single time it is
## picked up or handed to the brazier - hooking those would despawn a totem on
## every client the moment somebody bent down to collect it. What actually ends
## an entity is being freed, so that is what is watched for.
func _sweep_dead_entities() -> void:
	var dead: Array[int] = []
	for id: int in _entities:
		var node: Node = _entities[id]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			dead.append(id)
	for id: int in dead:
		var node: Node = _entities[id]
		if is_instance_valid(node):
			_entity_ids.erase(node.get_instance_id())
		_entities.erase(id)
		_entity_scene.erase(id)
		_holders.erase(id)
		_despawn_entity.rpc(id)


# =============================================================================
# Server: outgoing state
# =============================================================================

func _broadcast_fast() -> void:
	_sweep_dead_entities()
	var ghosts := _collect_ghosts()
	var entities := _collect_entities()
	if ghosts.is_empty() and entities.is_empty():
		return
	for peer_id: int in NetworkManager.replication_ready_peers:
		if peer_id == NetworkManager.SERVER_PEER_ID:
			continue
		_sync_fast.rpc_id(peer_id, ghosts, entities)


func _broadcast_slow() -> void:
	var doors := _collect_doors()
	var power := _collect_power()
	var brazier := _collect_brazier()
	for peer_id: int in NetworkManager.replication_ready_peers:
		if peer_id == NetworkManager.SERVER_PEER_ID:
			continue
		_sync_slow.rpc_id(peer_id, doors, power, brazier)


## Transform, state and velocity - which is everything all three ghosts need to
## present themselves.
##
## Each of `hunter_ghost.gd`, `crawler_ghost.gd` and `statue_ghost.gd` already
## separates its body from its brain in the same place: an `_update_presentation()`
## that reads `state` and `velocity` and drives the limbs, the shader, the
## lantern and the footstep audio off them. So a client does not need the pose
## sent to it - given those two values it derives the same pose the server did,
## through the ghost's own code. That is why `state` and `velocity` travel and
## nothing about clips or sway does.
func _collect_ghosts() -> Array:
	var out: Array = []
	for ghost: Node3D in _ghosts:
		if not is_instance_valid(ghost):
			out.append([])
			continue
		out.append(_ghost_state(ghost))
	return out


func _ghost_state(ghost: Node3D) -> Array:
	var state := 0
	if "state" in ghost:
		state = int(ghost.get("state"))
	var velocity := Vector3.ZERO
	if ghost is CharacterBody3D:
		velocity = (ghost as CharacterBody3D).velocity
	return [
		ghost.global_position,
		ghost.rotation.y,
		state,
		ghost.visible,
		velocity,
		_ghost_manifested(ghost),
	]


## Whether the *body* is showing, which is not the same as `ghost.visible`.
##
## All three ghosts leave their root visible and hide the rig instead, through
## their own `_set_manifested()` - which also owns the collision layers, the
## lantern and the footstep audio. That call is only ever made by the brain, and
## a client does not run the brain, so without this a replicated huntsman
## arrived as a bare moving light with no model attached to it and a statue
## never appeared at all.
func _ghost_manifested(ghost: Node3D) -> bool:
	var body := _ghost_body(ghost)
	return body == null or body.visible


## The rig each ghost hides. The three authored ones keep it under `VisualRoot`;
## the Darkness ghost is built on the reusable WomanGhost body and hides
## `AnimatedModel` instead. A ghost whose rig is under neither name simply has
## no manifested state to replicate.
func _ghost_body(ghost: Node3D) -> Node3D:
	for path: NodePath in [^"VisualRoot", ^"AnimatedModel"]:
		var node := ghost.get_node_or_null(path) as Node3D
		if node:
			return node
	return null


func _collect_entities() -> Array:
	var out: Array = []
	for id: int in _entities:
		var node := _entities[id] as Node3D
		if not is_instance_valid(node):
			continue
		# A carried item follows its holder on the client too, so there is no
		# point streaming a transform for it.
		if int(_holders.get(id, 0)) != 0:
			continue
		# A huntsman that came through a breach is spawned rather than authored,
		# so it travels as an entity - but it is still a body with a walk cycle.
		# The longer row is what lets a client animate it instead of sliding it.
		if node.has_method(&"_update_presentation"):
			out.append([id] + _ghost_state(node))
			continue
		out.append([id, node.global_position, node.rotation.y])
	return out


func _collect_doors() -> Array:
	var out: Array = []
	for node: Node in get_tree().get_nodes_in_group(&"defense_doors"):
		if not ("entrance_id" in node):
			continue
		out.append([
			int(node.get("entrance_id")),
			float(node.get("current_durability")),
			float(node.get("repair_cap")),
			int(node.get("attack_phase")),
			bool(node.get("minigame_active")),
			bool(node.get("repair_unlocked_after_breach")),
		])
	return out


func _collect_power() -> Array:
	var power := _power()
	if power == null:
		return []
	return [
		float(power.get("current_power")),
		bool(power.get("is_blackout")),
		bool(power.get("is_regional_blackout")),
		power.get("regional_blackout_center") as Vector3,
	]


## There is only ever one brazier in a map, so it needs no id.
func _collect_brazier() -> Array:
	var brazier := get_tree().get_first_node_in_group(&"totem_braziers")
	if brazier == null:
		return []
	return [bool(brazier.get("is_lit")), float(brazier.get("hold_progress"))]


func _collect_clock() -> Array:
	var clock := _clock()
	if clock == null:
		return []
	return [
		int(clock.get("elapsed_game_minutes")),
		int(clock.get("current_minutes_of_day")),
		bool(clock.get("won")),
	]


func _on_clock_minute_changed(_minutes_of_day: int, _formatted: String) -> void:
	if not NetworkManager.session_active or not NetworkManager.is_world_authority():
		return
	var state := _collect_clock()
	if state.is_empty():
		return
	_sync_clock.rpc(state[0], state[1], state[2])


func _on_clock_victory() -> void:
	_on_clock_minute_changed(0, "")


# =============================================================================
# Server: the snapshot a late joiner starts from
# =============================================================================

func _on_peer_replication_ready(peer_id: int) -> void:
	if not NetworkManager.session_active or not NetworkManager.is_world_authority():
		return
	if peer_id == NetworkManager.SERVER_PEER_ID:
		return
	_bind_scene_if_changed()
	_apply_snapshot.rpc_id(peer_id, _build_snapshot())


func _build_snapshot() -> Dictionary:
	var spawned: Array = []
	for id: int in _entities:
		var node := _entities[id] as Node3D
		if not is_instance_valid(node):
			continue
		spawned.append([
			id,
			str(_entity_scene.get(id, "")),
			_path_from_scene(node.get_parent()),
			node.global_position,
			node.rotation.y,
			int(_holders.get(id, 0)),
			str(node.name),
		])
	return {
		"entities": spawned,
		"ghosts": _collect_ghosts(),
		"doors": _collect_doors(),
		"power": _collect_power(),
		"brazier": _collect_brazier(),
		"clock": _collect_clock(),
	}


## Node paths are sent relative to the current scene so they mean the same
## thing on a peer whose scene sits somewhere else in its own tree.
func _path_from_scene(node: Node) -> String:
	if node == null or _scene_root == null:
		return ""
	if node == _scene_root:
		return "."
	return str(_scene_root.get_path_to(node))


func _node_from_scene_path(path: String) -> Node:
	if _scene_root == null or path.is_empty():
		return null
	if path == ".":
		return _scene_root
	return _scene_root.get_node_or_null(NodePath(path))


# =============================================================================
# Client: incoming state
# =============================================================================

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _sync_fast(ghosts: Array, entities: Array) -> void:
	_bind_scene_if_changed()
	for index: int in mini(ghosts.size(), _ghosts.size()):
		var state: Array = ghosts[index]
		if state.size() < 5:
			continue
		_apply_ghost(_ghosts[index], state)
	for row: Array in entities:
		if row.size() < 3:
			continue
		var node := _entities.get(int(row[0])) as Node3D
		if not is_instance_valid(node):
			continue
		# A ghost entity carries the whole ghost state behind its id; a loose
		# totem carries only a transform.
		if row.size() > 3:
			_apply_ghost(node, row.slice(1))
			continue
		node.global_position = row[1]
		node.rotation.y = row[2]


## The ghost is placed rather than simulated, and then asked to present itself.
##
## `_update_presentation()` is the ghost's own body code - the half that reads
## `state` and `velocity` and animates. Calling it here is what keeps a crawler
## crawling and the Huntsman's legs moving on a client whose `_physics_process`
## has already returned without deciding anything. Nothing in this path chooses
## a target, opens a door or hurts anybody.
func _apply_ghost(ghost: Node3D, state: Array) -> void:
	if not is_instance_valid(ghost):
		return
	ghost.global_position = state[0]
	ghost.rotation.y = state[1]
	if "state" in ghost:
		ghost.set("state", int(state[2]))
	ghost.visible = bool(state[3])
	if ghost is CharacterBody3D:
		(ghost as CharacterBody3D).velocity = state[4]
	# Only on a change: _set_manifested(false) stops the footstep, hook and
	# breath players, so calling it twenty times a second would silence a
	# huntsman that is standing right behind you.
	if state.size() >= 6 and ghost.has_method(&"_set_manifested"):
		var manifested := bool(state[5])
		if _ghost_manifested(ghost) != manifested:
			ghost.call(&"_set_manifested", manifested)
	if ghost.has_method(&"_update_presentation"):
		ghost.call(&"_update_presentation", FAST_INTERVAL)


@rpc("authority", "call_remote", "reliable")
func _sync_slow(doors: Array, power: Array, brazier: Array) -> void:
	_bind_scene_if_changed()
	_apply_doors(doors)
	_apply_power(power)
	_apply_brazier(brazier)


func _apply_doors(doors: Array) -> void:
	if doors.is_empty():
		return
	var by_id: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(&"defense_doors"):
		if "entrance_id" in node:
			by_id[int(node.get("entrance_id"))] = node
	for row: Array in doors:
		if row.size() < 6:
			continue
		var door: Node = by_id.get(int(row[0]))
		if door == null or not door.has_method(&"apply_network_state"):
			continue
		door.call(&"apply_network_state", row[1], row[2], row[3], row[4], row[5])


func _apply_brazier(brazier: Array) -> void:
	if brazier.size() < 2:
		return
	var node := get_tree().get_first_node_in_group(&"totem_braziers")
	if node and node.has_method(&"apply_network_state"):
		node.call(&"apply_network_state", brazier[0], brazier[1])


func _apply_power(power: Array) -> void:
	if power.size() < 4:
		return
	var manager := _power()
	if manager and manager.has_method(&"apply_network_state"):
		manager.call(&"apply_network_state", power[0], power[1], power[2], power[3])


@rpc("authority", "call_remote", "reliable")
func _sync_clock(elapsed: int, minutes_of_day: int, won: bool) -> void:
	var clock := _clock()
	if clock and clock.has_method(&"apply_network_time"):
		clock.call(&"apply_network_time", elapsed, minutes_of_day, won)


@rpc("authority", "call_remote", "reliable")
func _spawn_entity(
	id: int,
	scene_path: String,
	parent_path: String,
	position: Vector3,
	yaw: float,
	node_name: String = ""
) -> void:
	_bind_scene_if_changed()
	if _entities.has(id) or scene_path.is_empty():
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_warning("WorldReplicator: cannot load replicated scene " + scene_path)
		return
	var parent := _node_from_scene_path(parent_path)
	if parent == null:
		parent = _scene_root
	if parent == null:
		return
	var node := scene.instantiate()
	node.name = node_name if not node_name.is_empty() else ENTITY_PREFIX + str(id)
	# A dropped totem is a RigidBody3D that settles under gravity on the server.
	# Left awake here it would fall on its own schedule and then be yanked back
	# by every incoming packet, so on a client it only ever follows.
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	parent.add_child(node)
	_entities[id] = node
	var node_3d := node as Node3D
	if node_3d:
		node_3d.global_position = position
		node_3d.rotation.y = yaw


@rpc("authority", "call_remote", "reliable")
func _despawn_entity(id: int) -> void:
	var node: Node = _entities.get(id)
	_entities.erase(id)
	if is_instance_valid(node):
		node.queue_free()


## Mirrors a pickup or a hand-over on the client, through the player's own
## public API rather than by reaching into the equipment slots - the same two
## calls the server made. This is what puts the item in the HUD's hand slots
## and takes it off the floor on the peer that pressed the key.
@rpc("authority", "call_remote", "reliable")
func _set_entity_holder(id: int, peer_id: int) -> void:
	var item := _entities.get(id) as Node3D
	if not is_instance_valid(item):
		return
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if not node.has_method(&"release_held_item"):
			continue
		if int(node.get("owner_peer_id")) == peer_id:
			continue
		node.call(&"release_held_item", item)
	if peer_id == 0:
		return
	var holder := _player_for_peer(peer_id)
	if holder and holder.has_method(&"try_pick_up_item"):
		holder.call(&"try_pick_up_item", item)


func _player_for_peer(peer_id: int) -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if "owner_peer_id" in node and int(node.get("owner_peer_id")) == peer_id:
			return node
	return null


@rpc("authority", "call_remote", "reliable")
func _apply_snapshot(snapshot: Dictionary) -> void:
	_bind_scene_if_changed()
	for row: Array in snapshot.get("entities", []):
		if row.size() < 7:
			continue
		_spawn_entity(int(row[0]), str(row[1]), str(row[2]), row[3], row[4], str(row[6]))
		if int(row[5]) != 0:
			_set_entity_holder(int(row[0]), int(row[5]))
	var ghosts: Array = snapshot.get("ghosts", [])
	for index: int in mini(ghosts.size(), _ghosts.size()):
		var state: Array = ghosts[index]
		if state.size() >= 5:
			_apply_ghost(_ghosts[index], state)
	_apply_doors(snapshot.get("doors", []))
	_apply_power(snapshot.get("power", []))
	_apply_brazier(snapshot.get("brazier", []))
	var clock: Array = snapshot.get("clock", [])
	if clock.size() >= 3:
		_sync_clock(clock[0], clock[1], clock[2])

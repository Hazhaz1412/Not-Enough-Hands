class_name TotemRitual
extends Node

## Director for the shared "find the totems and burn them" objective.
##
## It owns the bookkeeping the brazier deliberately does not: how many items
## exist and where they are, what a burn is worth in night-time, and when the
## ritual is over. Placement goes through the `house2_rooms` marker group both
## maps publish, so the same node works in House2 and in the villa with no
## map-specific coordinates anywhere.
##
## Nothing is scattered once at boot. The world always holds four totems and a
## flat handful of logs; each burned totem is replaced at a new random drop, and
## every drop point is chosen at random from the
## rooms that are far from *everybody* - the objective is a trip, so an item is
## never allowed to appear at somebody's feet. Within one restock pass the rooms
## already used are avoided, so a handful of logs is a handful of places.
##
## The 4:00 AM ceiling lives in NightClock (`skip_minutes()`), not here: a burn
## at 3:50 asks for 30 minutes and is handed the 10 that are left. Once the
## clock is at the ceiling there is nothing left to burn for, so every totem and
## every log still lying around is cleared out of the world.

signal totem_burned(granted_minutes: int)
signal ritual_completed()

const TOTEM_SCENE: PackedScene = preload("res://items/totem.tscn")
const FIREWOOD_SCENE: PackedScene = preload("res://items/firewood.tscn")
const BRAZIER_SCENE: PackedScene = preload("res://items/totem_brazier.tscn")

## Fixed shared population. Picking one up still counts it; burning it is what
## creates a replacement elsewhere on the map.
@export_range(0, 8, 1) var totems_in_world: int = 4
## Logs kept in the world at once, as a flat count rather than one per player.
## The fire needs one after every burn, and a single log dropped somewhere in an
## 80 x 60 m villa is not a trip back, it is a search: three of them means there
## is one within reach of wherever the last totem took you. Never drops below
## the per-player count, so a full room still gets a log each.
@export_range(0, 8, 1) var firewood_in_world: int = 3
@export_range(0, 240, 5) var minutes_per_totem: int = 30
## How far a fresh item has to be from every player. Treated as a hard rule
## wherever the map can honour it: 40 m clears most of the villa, whose farthest
## room is about 57 m from the player spawn. Where a map cannot honour it at all
## - House2 is 18 x 12 m, so nothing in it is ever 40 m from anyone - the rooms
## as far away as that map gets are used instead. The rule degrades to "the
## farthest there is", never back to "next to the player".
@export_range(0.0, 200.0, 1.0) var min_spawn_distance: float = 40.0
## Marker group the drop points come from. Both maps publish their rooms into
## `house2_rooms`; the villa adds its own markers to it as well.
@export var spawn_room_group: StringName = &"house2_rooms"
## Seconds between restock passes. Items are replaced on a timer rather than the
## instant one is consumed, because a legal drop point may not exist yet: with
## everybody spread out the pass simply finds nothing and tries again.
@export_range(0.25, 10.0, 0.25) var restock_interval: float = 2.0
## Items drop from this height and settle under gravity, which keeps them on
## top of whatever furniture is really there instead of inside it.
@export_range(0.1, 3.0, 0.05) var spawn_drop_height: float = 0.9
## Fraction of a room's half-size the drop point is nudged off centre, so a
## totem does not land on the dining table every single time. Only reached in
## full where a room publishes no cleared tile - see `CLEAR_TILE_RADIUS`.
@export_range(0.0, 0.9, 0.05) var spawn_room_spread: float = 0.34

## Half-width, in metres, of the tile a `clear_point` marks. That point is the
## one tile of the room the map's own furniture pass left empty, so the nudge
## above has to stay inside it. Measured against the whole room instead, it moved
## a log up to two metres sideways into the very wardrobe the cleared tile
## existed to avoid, and the trip back for firewood became a search of the
## furniture rather than of the house.
const CLEAR_TILE_RADIUS := 0.7

var is_complete: bool = false
var totems_burned: int = 0

var _clock: Node = null
var _rng := RandomNumberGenerator.new()
var _restock_timer: float = 0.0
var _started: bool = false


func _ready() -> void:
	add_to_group(&"totem_ritual")
	_rng.randomize()
	# The map generates its colliders in its own _ready(), which runs after
	# every child's - dropped items would fall through a floor that does not
	# exist yet, so the first restock waits for the first physics step.
	begin.call_deferred()


## Idempotent: the smoke test calls it directly, `_ready()` defers into it once.
func begin() -> void:
	if _started:
		return
	_started = true
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_clock = get_tree().get_first_node_in_group(&"night_clock")
	if _clock and _clock.has_signal(&"minute_changed"):
		_clock.connect(&"minute_changed", _on_minute_changed)
	_ensure_brazier()
	restock()
	_check_completion()


func _process(delta: float) -> void:
	if is_complete or not _started:
		return
	_restock_timer -= delta
	if _restock_timer <= 0.0:
		_restock_timer = restock_interval
		restock()


## Called by the brazier once a totem has actually gone into the fire. Returns
## the in-game minutes the burn was really worth, which is less than
## `minutes_per_totem` on the last one before the ceiling and zero after it.
func on_totem_burned() -> int:
	var granted := 0
	if _clock and _clock.has_method(&"skip_minutes"):
		granted = int(_clock.call(&"skip_minutes", minutes_per_totem))
	totems_burned += 1
	totem_burned.emit(granted)
	_check_completion()
	if not is_complete:
		# The brazier queued the consumed item for deletion just before this call.
		# Deferring lets that item leave its group before the replacement count is
		# measured, while the regular timer remains a fallback if no room is legal.
		restock.call_deferred()
	return granted


func totems_remaining() -> int:
	return get_tree().get_nodes_in_group(&"totems").size()


## Brings the shared totem population back to four and replenishes the flat log
## supply. Public so tests and map setup can force a pass without waiting.
##
## Only the authority scatters. The items are replicated entities, so a client
## that ran its own restock would put a second, invisible-to-everyone-else totem
## in a different room and then be sent the server's on top of it.
func restock() -> void:
	if is_complete or not WorldNet.is_world_authority():
		return
	_restock_group(TOTEM_SCENE, &"totems", totems_in_world)
	_restock_group(
		FIREWOOD_SCENE,
		&"fire_fuel",
		maxi(firewood_in_world, _players_in_run().size())
	)


## Carried items count towards the population: picking a totem up is not what
## puts the next one on the map, burning it is.
func _restock_group(scene: PackedScene, group: StringName, target: int) -> void:
	var existing: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(group):
		if not node.is_queued_for_deletion():
			existing.append(node)
	var used: Array[Node3D] = []
	for i: int in maxi(target - existing.size(), 0):
		var room := _pick_far_room(used)
		if room == null:
			return
		used.append(room)
		_drop_item(scene, room)
	# A player dropping out of the run lowers the target. Only items nobody is
	# carrying are taken back - never one out of somebody's hands.
	var surplus := existing.size() - target
	for node: Node in existing:
		if surplus <= 0:
			break
		var item := node as Node3D
		if item and _is_loose(item):
			item.queue_free()
			surplus -= 1


## The spawn rule. Pick at random among the rooms at least `min_spawn_distance`
## from every player, preferring one `exclude` does not already name.
func _pick_far_room(exclude: Array[Node3D] = []) -> Node3D:
	var players := _players_in_run()
	var qualifying: Array[Node3D] = []
	var rest: Array[Dictionary] = []
	for room: Node3D in _spawn_rooms():
		var distance := _distance_to_nearest(_room_floor_point(room), players)
		if distance >= min_spawn_distance:
			qualifying.append(room)
		else:
			rest.append({"room": room, "distance": distance})
	if not qualifying.is_empty():
		return _random_room(_prefer_unused(qualifying, exclude))
	if rest.is_empty():
		return null
	# Nothing on this map is far enough from everybody, so the rule degrades to
	# the farthest quarter of the rooms rather than to one fixed room: still as
	# far away as this map gets, still somewhere different every time.
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) > float(b["distance"])
	)
	var farthest: Array[Node3D] = []
	for entry: Dictionary in rest.slice(0, maxi(1, rest.size() / 4)):
		farthest.append(entry["room"] as Node3D)
	return _random_room(_prefer_unused(farthest, exclude))


## Spreading one pass over as many rooms as it has items is a preference, never
## a rule: the distance rule above has already decided which rooms are legal, and
## a second log in the only legal room still beats no second log at all.
func _prefer_unused(rooms: Array[Node3D], exclude: Array[Node3D]) -> Array[Node3D]:
	var fresh: Array[Node3D] = []
	for room: Node3D in rooms:
		if not exclude.has(room):
			fresh.append(room)
	return fresh if not fresh.is_empty() else rooms


func _random_room(rooms: Array[Node3D]) -> Node3D:
	if rooms.is_empty():
		return null
	return rooms[_rng.randi_range(0, rooms.size() - 1)]


func _distance_to_nearest(point: Vector3, players: Array[Node3D]) -> float:
	var nearest := INF
	for player: Node3D in players:
		nearest = minf(nearest, point.distance_to(player.global_position))
	return nearest


## Everyone still in the run. Spectators are out; a downed player is only down,
## and their totem should still be waiting when a teammate lifts them.
func _players_in_run() -> Array[Node3D]:
	var players: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player == null:
			continue
		if "is_spectator" in player and bool(player.get("is_spectator")):
			continue
		var alive: bool = bool(player.get("is_alive")) if "is_alive" in player else true
		var downed: bool = bool(player.get("is_downed")) if "is_downed" in player else false
		if alive or downed:
			players.append(player)
	return players


func _is_loose(item: Node3D) -> bool:
	var parent := item.get_parent()
	return parent != null and not parent.is_in_group(&"players")


func _on_minute_changed(_minutes_of_day: int, _formatted: String) -> void:
	_check_completion()


## One condition, checked from both directions: the night reaching 4:00 on its
## own ends the ritual exactly as burning the last totem does.
func _check_completion() -> void:
	if is_complete or _clock == null or not _clock.has_method(&"get_minutes_until_skip_limit"):
		return
	if int(_clock.call(&"get_minutes_until_skip_limit")) > 0:
		return
	is_complete = true
	# The sweep is a despawn like any other: the authority frees the items and
	# every client is told. A client doing it itself would race the packet.
	if WorldNet.is_world_authority():
		_clear_remaining_items()
	ritual_completed.emit()


func _clear_remaining_items() -> void:
	var players := get_tree().get_nodes_in_group(&"players")
	for group: StringName in [&"totems", &"fire_fuel"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var item := node as Node3D
			if item == null:
				continue
			for player: Node in players:
				if player.has_method(&"release_held_item"):
					player.call(&"release_held_item", item)
			item.queue_free()


func _ensure_brazier() -> void:
	if get_tree().get_first_node_in_group(&"totem_braziers"):
		return
	# Replicated rather than instanced on each peer: the position is derived
	# from where the players happen to be standing, so two peers computing it
	# independently can put the ritual site in two different rooms.
	WorldNet.spawn(BRAZIER_SCENE, get_parent(), _fallback_brazier_position(), 0.0, "RitualBrazier")


## Only used by a map that did not place a brazier itself. Unlike the items, the
## fire is meant to be found immediately: it goes in the room nearest to where
## the players start, so the ritual site is somewhere they walk past rather than
## somewhere they have to be told about.
func _fallback_brazier_position() -> Vector3:
	var anchor := get_tree().get_first_node_in_group(&"players") as Node3D
	var origin := anchor.global_position if anchor else Vector3.ZERO
	var best: Vector3 = origin
	var best_distance := INF
	for room: Node3D in _spawn_rooms():
		var point := _room_floor_point(room)
		if absf(point.y - origin.y) > 2.0:
			continue
		var distance := Vector2(point.x - origin.x, point.z - origin.z).length()
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


func _drop_item(scene: PackedScene, room: Node3D) -> void:
	var extent := Vector3(2.0, 0.0, 2.0)
	if room.has_meta(&"room_size"):
		extent = room.get_meta(&"room_size") as Vector3
	var spread_x := extent.x * 0.5 * spawn_room_spread
	var spread_z := extent.z * 0.5 * spawn_room_spread
	if room.has_meta(&"clear_point"):
		spread_x = minf(spread_x, CLEAR_TILE_RADIUS)
		spread_z = minf(spread_z, CLEAR_TILE_RADIUS)
	var drop_position := _room_floor_point(room) + Vector3(
		_rng.randf_range(-1.0, 1.0) * spread_x,
		spawn_drop_height,
		_rng.randf_range(-1.0, 1.0) * spread_z
	)
	var item := WorldNet.spawn(
		scene,
		get_parent(),
		drop_position,
		_rng.randf_range(0.0, TAU)
	) as Node3D
	if item == null:
		return
	# Unfrozen on purpose - a PickupItem sits frozen in the world, but these are
	# dropped in blind, so gravity is what settles them onto the real floor.
	# On a client the replicator freezes it again: there it only ever follows.
	if item is RigidBody3D:
		(item as RigidBody3D).freeze = false


func _spawn_rooms() -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(spawn_room_group):
		var marker := node as Node3D
		if marker:
			rooms.append(marker)
	return rooms


## The villa tags each room marker with a cell its own furniture pass left
## empty; it is stored in the same local space as the marker, so it has to go
## through the marker's parent to come out as a world point.
func _room_floor_point(room: Node3D) -> Vector3:
	var parent := room.get_parent_node_3d()
	if room.has_meta(&"clear_point") and parent:
		return parent.to_global(room.get_meta(&"clear_point") as Vector3)
	return room.global_position

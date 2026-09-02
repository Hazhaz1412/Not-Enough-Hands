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
## Nothing is scattered once at boot. The world always holds at least five
## totems plus a
## flat handful of logs; each burned totem is replaced at a new random drop,
## and every drop point is chosen at random from the
## rooms that are far from *everybody* - the objective is a trip, so an item is
## never allowed to appear at somebody's feet. Within one restock pass the rooms
## already used are avoided, so a handful of logs is a handful of places.
##
## This is the night's first and, for now, only objective: the clock does not run
## to dawn on its own any more, it runs on the runway burns pay for. How much a
## burn is worth is still decided here; how it is spent is NightClock's business
## (`add_fuel()`, never `skip_minutes()` - see the class docs there for why the
## difference matters). The bank has no ceiling: work already done is never
## deleted. The one thing that can still clip a burn is dawn, and nothing stops
## a team burning one totem too many into it - that call is theirs to read off
## the runway bar and take.
##
## When the night finally ends, every totem and log still lying around is cleared
## out of the world.

signal totem_burned(granted_minutes: int)
signal ritual_completed()

const TOTEM_SCENE: PackedScene = preload("res://items/totem.tscn")
const FIREWOOD_SCENE: PackedScene = preload("res://items/firewood.tscn")
const BATTERY_SCENE: PackedScene = preload("res://items/flashlight_battery.tscn")
const BRAZIER_SCENE: PackedScene = preload("res://items/totem_brazier.tscn")
## Floor for `totems_by_player_count`, so an emptied or mis-authored table can
## never leave the map with nothing to find.
const MIN_TOTEMS_IN_WORLD := 5

## How many totems are loose in the world, indexed by how many players are in
## the run. The hard five-totem floor upgrades legacy lower entries; picking one
## up still counts it, and burning it creates the replacement.
##
## It grows more slowly than the head count on purpose. Four players do not need
## four times the totems - what they need is not to be queueing at the same
## five - and a map carpeted in them turns the objective from a trip into a
## pickup. Past four players the fifth is enough; the shortage that creates is
## the coordination, which is the interesting part.
@export var totems_by_player_count: PackedInt32Array = PackedInt32Array([3, 4, 5, 5])
## Logs kept in the world at once, as a flat count rather than one per player.
## The fire needs one after every burn, so a log has to be findable from
## wherever the last totem left you rather than being a second search on top of
## the first. Nine keeps several options available across the Villa's 80 x 60 m
## and three storeys. It never drops below the per-player count either.
@export_range(0, 16, 1) var firewood_in_world: int = 9
## Spare torch batteries loose in the house. Not part of the ritual at all -
## they live here because this node is already the thing that keeps a live item
## population spread over both maps' room markers, and a second director would
## be the same eighty lines of room-picking written twice.
##
## Deliberately the easiest population of the three to find. A totem is the
## objective and is *meant* to be a trip; a battery is what lets you see on the
## way there, so hiding it makes the trip worse rather than harder in any way
## worth having. It gets the near slice of the rooms and almost no exclusion
## radius - see `battery_spawn_distance`.
@export_range(0, 16, 1) var batteries_in_world: int = 9
## Exclusion radius for batteries alone, and it exists only so one does not pop
## into existence in the room you are standing in. Everything past it is fair
## game, near slice included, which is the whole difference between this and the
## totems' 22 m.
@export_range(0.0, 60.0, 0.5) var battery_spawn_distance: float = 6.0

@export_category("Totem guidance")
## Periodically reveal exactly one loose totem to every peer. The reveal is an
## x-ray beacon rather than the normal line-of-sight glow and expires well
## before the next hint, preserving the search between pulses.
@export_range(5.0, 300.0, 1.0) var totem_hint_interval: float = 77.0
@export_range(1.0, 60.0, 1.0) var totem_hint_duration: float = 12.0
## Burns each player owes the night, and the only number here that is authored:
## what one burn is *worth* is derived from it so the night always costs the
## same amount of night, however many people are carrying it. Three each means
## three totems solo, six for a pair, twelve for a full room of four - the work
## scales with the hands available instead of the clock doing it.
##
## It buys runway, not a jump, so the night still has to be played through
## between burns: paying for the whole night in the first two minutes is not
## possible, and idling still stops the clock dead.
@export_range(1, 10, 1) var burns_per_player: int = 3
## How far a fresh item has to be from every player. This is an exclusion
## radius and nothing more - it exists so an item never appears at somebody's
## feet, not to make the trip long. It was 40 m, which in an 80 x 60 m villa
## meant almost the whole building qualified and every totem was a search of the
## entire map; the objective is a trip, not a hunt. Where a map cannot honour it
## at all - House2 is 18 x 12 m - the rooms as far away as that map gets are
## used instead, so the rule degrades to "the farthest there is", never back to
## "next to the player".
@export_range(0.0, 200.0, 1.0) var min_spawn_distance: float = 22.0
## Of the rooms that clear the exclusion radius, only the nearest slice is drawn
## from. This is what turns "somewhere in the villa" into "two or three rooms
## that way": without it the pick was uniform across everything beyond the
## radius, so the far corner of the map was as likely as the next corridor. Kept
## as a fraction rather than a count so a small map still offers a choice.
@export_range(0.1, 1.0, 0.05) var near_room_fraction: float = 0.4
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
var _totem_hint_timer: float = 0.0
var _last_hinted_totem_path := NodePath()
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
	_sync_runway_pricing()
	_ensure_brazier()
	restock()
	_totem_hint_timer = totem_hint_interval
	_check_completion()


func _process(delta: float) -> void:
	if is_complete or not _started:
		return
	_restock_timer -= delta
	if _restock_timer <= 0.0:
		_restock_timer = restock_interval
		restock()
	if WorldNet.is_world_authority() and totem_hint_interval > 0.0:
		_totem_hint_timer -= delta
		if _totem_hint_timer <= 0.0:
			_totem_hint_timer = totem_hint_interval
			_trigger_next_totem_hint()


## Authority chooses the destination once; clients only render that choice.
## The runtime item names are shared by WorldReplicator, so a scene-relative
## NodePath identifies the same spawned totem on every peer.
func _trigger_next_totem_hint() -> bool:
	if not WorldNet.is_world_authority():
		return false
	var candidates: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"totems"):
		var totem := node as Node3D
		if totem and not totem.is_queued_for_deletion() and _is_loose(totem) \
				and totem.has_method(&"show_guidance_highlight"):
			candidates.append(totem)
	if candidates.is_empty():
		return false
	if candidates.size() > 1 and not _last_hinted_totem_path.is_empty():
		var previous := get_node_or_null(_last_hinted_totem_path) as Node3D
		if previous in candidates:
			candidates.erase(previous)
	var selected := candidates[_rng.randi_range(0, candidates.size() - 1)]
	var selected_path := get_path_to(selected)
	_last_hinted_totem_path = selected_path
	_apply_totem_hint(selected_path, totem_hint_duration)
	if _network_session_active():
		_apply_totem_hint.rpc(selected_path, totem_hint_duration)
	return true


@rpc("authority", "call_remote", "reliable")
func _apply_totem_hint(totem_path: NodePath, duration: float) -> void:
	# Clear the prior beacon first so packet retries or a very short configured
	# interval can never leave two timed objective markers active together.
	for node: Node in get_tree().get_nodes_in_group(&"totems"):
		if node.has_method(&"clear_guidance_highlight"):
			node.call(&"clear_guidance_highlight")
	var selected := get_node_or_null(totem_path)
	if selected and selected.has_method(&"show_guidance_highlight"):
		selected.call(&"show_guidance_highlight", duration)


func _network_session_active() -> bool:
	var manager := get_node_or_null("/root/NetworkManager")
	return manager != null and bool(manager.get("session_active"))


## Called by the brazier once a totem has actually gone into the fire. Returns
## the in-game minutes the burn was really worth, which is less than
## `get_minutes_per_totem()` near the runway ceiling and near dawn.
##
## This is the night's first objective, and it pays the clock the way every
## later one will: `add_fuel()`, not `skip_minutes()`. The difference is the
## whole design - a burn buys minutes the team then *plays through* while the
## clock runs, rather than deleting them with a jump.
func on_totem_burned() -> int:
	var granted := 0
	if _clock and _clock.has_method(&"add_fuel"):
		granted = int(_clock.call(&"add_fuel", get_minutes_per_totem()))
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


## Burns the whole team owes tonight: three each, recounted live. A player
## leaving or dying lowers it, which is deliberate - the survivors inherit a
## night that is still exactly one night long, not one priced for a team they
## no longer have.
func get_burns_required() -> int:
	return maxi(burns_per_player * _head_count(), 1)


func _head_count() -> int:
	return maxi(_players_in_run().size(), 1)


## Totems the map should be holding right now. The table is indexed from one
## player, and its last entry stands for every larger team, so a five-player
## lobby is not a five-entry table's problem.
func get_totems_in_world() -> int:
	if totems_by_player_count.is_empty():
		return MIN_TOTEMS_IN_WORLD
	var index := mini(_head_count(), totems_by_player_count.size()) - 1
	return maxi(totems_by_player_count[index], MIN_TOTEMS_IN_WORLD)


## What one burn pays, in in-game minutes: the night split into one unit per
## burn owed, plus one the night hands over free at the start. Derived rather
## than authored so the payout and the requirement can never drift - a fixed
## payout against a scaling requirement is how a four-player run ends up either
## unfinishable or over in three minutes.
##
## So a solo night is four units: one given, three burned. That +1 is also what
## keeps the older design intact - the opening tank is exactly one objective's
## worth, the bank holds exactly two, and the first burn of the run fills it to
## the brim rather than being clipped by the ceiling.
func get_minutes_per_totem() -> int:
	var units := get_burns_required() + 1
	return maxi(int(ceil(float(_total_night_minutes()) / float(units))), 1)


func _total_night_minutes() -> int:
	if _clock and _clock.has_method(&"get_total_night_minutes"):
		return maxi(int(_clock.call(&"get_total_night_minutes")), 1)
	# 23:55 -> 06:00. Only reached with no clock in the scene, which is a test
	# harness rather than a run.
	return 365


## The opening tank belongs to the same arithmetic as the payout, and a payout
## that moves with the head count against a fixed tank would either clip every
## burn or hand the team a night it never bought. The ritual is what knows the
## price, so the ritual is what tells the clock.
##
## There is no bank ceiling any more. It was a flat two objectives, which meant
## a team finishing a round of trips together had its last arrivals handed
## nothing at all - a totem carried across the villa for zero minutes of night.
## Work already done is not something a number the player cannot see gets to
## delete, so the ceiling is set to the whole night: the only thing that can
## still clip a burn is dawn, which is left as the player's own gamble: the
## runway bar is drawn against the night remaining, so a full bar says plainly
## that another totem would buy nothing, and going anyway is a decision rather
## than a trap.
func _sync_runway_pricing() -> void:
	if _clock == null or not "max_fuel_minutes" in _clock:
		return
	var unit := get_minutes_per_totem()
	_clock.set("max_fuel_minutes", _total_night_minutes())
	_clock.set("start_fuel_minutes", unit)
	# The clock reset itself before this node ran, so the tank it opened with is
	# the authored solo default whatever the room actually holds. Setting it
	# rather than topping it up is the whole point: for two players or more the
	# authored tank is too *large*, and a night that opens over-fuelled is a
	# night finished in fewer burns than the team owes.
	if _clock.has_method(&"set_opening_runway"):
		_clock.call(&"set_opening_runway", unit)


## Brings the shared totem population back to at least five and replenishes the flat log
## supply. Public so tests and map setup can force a pass without waiting.
##
## Only the authority scatters. The items are replicated entities, so a client
## that ran its own restock would put a second, invisible-to-everyone-else totem
## in a different room and then be sent the server's on top of it.
func restock() -> void:
	if is_complete or not WorldNet.is_world_authority():
		return
	# The head count is read here anyway, and this is the pass that runs every
	# two seconds - so it is also where a player joining, dying or leaving gets
	# the night repriced, without a second timer to keep in step with this one.
	_sync_runway_pricing()
	# The two populations want opposite distributions. A totem is a destination,
	# so it is drawn from the rooms nearest the team - the trip should be a trip,
	# not a sweep of the villa. Firewood is a convenience the fire needs after
	# every burn, so it is spread over the whole house instead: six logs all
	# drawn from the near quarter would sit in one wing and leave the other two
	# storeys with none, which is the search the near rule exists to prevent.
	_restock_group(
		TOTEM_SCENE,
		&"totems",
		get_totems_in_world()
	)
	_restock_group(
		FIREWOOD_SCENE,
		&"fire_fuel",
		maxi(firewood_in_world, _players_in_run().size()),
		false
	)
	_restock_group(
		BATTERY_SCENE,
		&"flashlight_batteries",
		maxi(batteries_in_world, _players_in_run().size()),
		true,
		battery_spawn_distance
	)


## Carried items count towards the population: picking a totem up is not what
## puts the next one on the map, burning it is.
func _restock_group(
	scene: PackedScene,
	group: StringName,
	target: int,
	cluster_near: bool = true,
	exclusion_radius: float = -1.0
) -> void:
	var existing: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(group):
		if not node.is_queued_for_deletion():
			existing.append(node)
	var used: Array[Node3D] = []
	for i: int in maxi(target - existing.size(), 0):
		var room := _pick_far_room(used, cluster_near, exclusion_radius)
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


## The spawn rule, in two steps: throw out every room inside the exclusion
## radius, then pick at random among the *nearest* `near_room_fraction` of what
## is left, preferring one `exclude` does not already name. Both halves matter -
## the first is what stops an item landing underfoot, the second is what stops
## the trip being a sweep of the whole villa.
##
## `exclusion_radius` defaults to `min_spawn_distance`; a population that is not
## the objective passes its own, much smaller one. How hard something is to find
## is a property of that item, not of the picker.
func _pick_far_room(
	exclude: Array[Node3D] = [],
	cluster_near: bool = true,
	exclusion_radius: float = -1.0
) -> Node3D:
	var radius := min_spawn_distance if exclusion_radius < 0.0 else exclusion_radius
	var players := _players_in_run()
	var qualifying: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for room: Node3D in _spawn_rooms():
		var distance := _distance_to_nearest(_room_floor_point(room), players)
		if distance >= radius:
			qualifying.append({"room": room, "distance": distance})
		else:
			rest.append({"room": room, "distance": distance})
	if not qualifying.is_empty():
		var pool: Array[Node3D] = []
		if cluster_near:
			qualifying.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a["distance"]) < float(b["distance"])
			)
			var take := maxi(1, int(ceil(float(qualifying.size()) * near_room_fraction)))
			qualifying = qualifying.slice(0, take)
		for entry: Dictionary in qualifying:
			pool.append(entry["room"] as Node3D)
		return _random_room(_prefer_unused(pool, exclude))
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


## The ritual now ends only when the night does. It used to close at the 4:00 AM
## skip ceiling, which made sense while burning was an optional shortcut - there
## was nothing left to buy. As the night's objective it is what *reaches* dawn,
## so a ceiling short of dawn would strand the run with no way to finish it.
func _check_completion() -> void:
	if is_complete or _clock == null or not _clock.has_method(&"get_minutes_remaining"):
		return
	if int(_clock.call(&"get_minutes_remaining")) > 0:
		return
	is_complete = true
	# The sweep is a despawn like any other: the authority frees the items and
	# every client is told. A client doing it itself would race the packet.
	if WorldNet.is_world_authority():
		_clear_remaining_items()
	ritual_completed.emit()


func _clear_remaining_items() -> void:
	var players := get_tree().get_nodes_in_group(&"players")
	for group: StringName in [&"totems", &"fire_fuel", &"flashlight_batteries"]:
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

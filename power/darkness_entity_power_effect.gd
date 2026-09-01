class_name DarknessEntityPowerEffect
extends Node

## Attach this component below the darkness entity. The entity can call
## cause_random_outage() whenever its attack should darken part of the house.

@export_range(0.1, 300.0, 0.5) var outage_duration: float = 10.0

var active_zone: ElectricalZone
var darkened_zones: Array[ElectricalZone] = []

## Neighbour graph follows the villa's walkable wings and the two vertical
## links. Expansion is constrained to this graph; it never jumps to a remote
## random zone after the first outage.
var zone_neighbours: Dictionary = {
	&"Z01_B1_WEST": PackedStringArray(["Z02_B1_EAST"]),
	&"Z02_B1_EAST": PackedStringArray(["Z01_B1_WEST", "Z07_F00_EAST"]),
	&"Z03_F00_NORTH": PackedStringArray(["Z04_F00_WEST", "Z05_F00_CENTRAL_NORTH", "Z07_F00_EAST", "Z08_F01_NORTH"]),
	&"Z04_F00_WEST": PackedStringArray(["Z03_F00_NORTH", "Z05_F00_CENTRAL_NORTH", "Z06_F00_CENTRAL_SOUTH"]),
	&"Z05_F00_CENTRAL_NORTH": PackedStringArray(["Z03_F00_NORTH", "Z04_F00_WEST", "Z06_F00_CENTRAL_SOUTH", "Z07_F00_EAST", "Z10_F01_CENTRAL"]),
	&"Z06_F00_CENTRAL_SOUTH": PackedStringArray(["Z04_F00_WEST", "Z05_F00_CENTRAL_NORTH", "Z07_F00_EAST"]),
	&"Z07_F00_EAST": PackedStringArray(["Z02_B1_EAST", "Z03_F00_NORTH", "Z05_F00_CENTRAL_NORTH", "Z06_F00_CENTRAL_SOUTH", "Z12_F01_EAST"]),
	&"Z08_F01_NORTH": PackedStringArray(["Z03_F00_NORTH", "Z09_F01_WEST", "Z10_F01_CENTRAL", "Z12_F01_EAST"]),
	&"Z09_F01_WEST": PackedStringArray(["Z08_F01_NORTH", "Z10_F01_CENTRAL", "Z11_F01_SERVICE"]),
	&"Z10_F01_CENTRAL": PackedStringArray(["Z05_F00_CENTRAL_NORTH", "Z08_F01_NORTH", "Z09_F01_WEST", "Z11_F01_SERVICE", "Z12_F01_EAST"]),
	&"Z11_F01_SERVICE": PackedStringArray(["Z09_F01_WEST", "Z10_F01_CENTRAL", "Z12_F01_EAST", "Z13_F02_ATTIC"]),
	&"Z12_F01_EAST": PackedStringArray(["Z07_F00_EAST", "Z08_F01_NORTH", "Z10_F01_CENTRAL", "Z11_F01_SERVICE"]),
	&"Z13_F02_ATTIC": PackedStringArray(["Z11_F01_SERVICE"]),
}


func _ready() -> void:
	if OS.is_debug_build():
		_validate_zone_neighbours.call_deferred()


## zone_neighbours is authored by hand and is not checked by the editor, so a
## typo or renamed zone_id silently shrinks the neighbouring blackout cluster.
## This flags that mismatch loudly in debug builds instead.
func _validate_zone_neighbours() -> void:
	var known_ids: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("electrical_zones"):
		var zone := node as ElectricalZone
		if zone:
			known_ids[zone.zone_id] = true
	for zone_id: Variant in known_ids.keys():
		if not zone_neighbours.has(zone_id):
			push_warning("DarknessEntityPowerEffect: zone '%s' exists in the scene but has no entry in zone_neighbours (darkness can never expand into or out of it)." % zone_id)
	for zone_id: Variant in zone_neighbours.keys():
		if not known_ids.has(zone_id):
			push_warning("DarknessEntityPowerEffect: zone_neighbours references unknown zone '%s' (no ElectricalZone with that zone_id exists in the scene)." % zone_id)
			continue
		for neighbour_id: String in zone_neighbours[zone_id]:
			if not known_ids.has(StringName(neighbour_id)):
				push_warning("DarknessEntityPowerEffect: zone '%s' lists unknown neighbour '%s'." % [zone_id, neighbour_id])


func cause_random_outage() -> bool:
	var manager := get_tree().get_first_node_in_group("power_manager") as PowerManager
	if not manager:
		push_warning("Darkness entity could not find a PowerManager")
		return false
	return manager.trigger_random_regional_blackout(outage_duration) > 0


func clear_outage() -> void:
	var manager := get_tree().get_first_node_in_group("power_manager") as PowerManager
	if manager:
		manager.end_regional_blackout()


## Fallback used only when no Player zone can be resolved. Sort by ID so even
## this case is reproducible rather than selecting a remote random blackout.
func cause_first_available_zone_outage() -> ElectricalZone:
	_prune_restored_zones()
	var candidates: Array[ElectricalZone] = []
	for node: Node in get_tree().get_nodes_in_group("electrical_zones"):
		var zone := node as ElectricalZone
		if zone and zone.is_powered:
			candidates.append(zone)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left: ElectricalZone, right: ElectricalZone) -> bool:
		return String(left.zone_id) < String(right.zone_id)
	)
	return cause_zone_outage(candidates[0])


## `lock_chance` is forwarded per zone: the fraction of fixtures whose switch
## stays dead until the hunt is over. Zero keeps the old behaviour, where every
## cut light can be walked back on one switch at a time.
func cause_zone_outage(zone: ElectricalZone, lock_chance: float = 0.0) -> ElectricalZone:
	_prune_restored_zones()
	if not zone or not zone.is_powered:
		return null
	active_zone = zone
	if not zone.begin_switch_restore_outage(lock_chance):
		active_zone = null
		return null
	if zone not in darkened_zones:
		darkened_zones.append(zone)
	return zone


func cause_zone_outages(
	zones: Array[ElectricalZone],
	lock_chance: float = 0.0
) -> Array[ElectricalZone]:
	var result: Array[ElectricalZone] = []
	for zone: ElectricalZone in zones:
		var darkened := cause_zone_outage(zone, lock_chance)
		if darkened:
			result.append(darkened)
	return result


## Breadth-first collection of the target zone and its authored neighbours.
## Only powered zones are included so an existing failure does not shrink the
## useful outage or accidentally become owned by this encounter.
func get_zone_cluster(center: ElectricalZone, neighbour_depth: int = 1) -> Array[ElectricalZone]:
	var result: Array[ElectricalZone] = []
	if not center:
		return result
	var queue: Array = [[center, 0]]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		var zone := entry[0] as ElectricalZone
		var depth := int(entry[1])
		if not zone or visited.has(zone.zone_id):
			continue
		visited[zone.zone_id] = true
		if zone.is_powered:
			result.append(zone)
		if depth >= neighbour_depth:
			continue
		for neighbour_id: StringName in zone_neighbours.get(zone.zone_id, PackedStringArray()):
			var neighbour := _zone_by_id(neighbour_id)
			if neighbour and not visited.has(neighbour.zone_id):
				queue.append([neighbour, depth + 1])
	return result


func find_zone(zone_id: StringName) -> ElectricalZone:
	return _zone_by_id(zone_id)


## Returns the first powered frontier zone in authored neighbour order, but
## does not alter it. The ghost uses this to walk into a lit zone before it
## cuts its electricity.
func get_next_neighbouring_zone() -> ElectricalZone:
	var candidates := get_frontier_zones()
	return candidates[0] if not candidates.is_empty() else null


## Every powered zone adjacent to the darkness, in authored neighbour order.
## The order is the component's opinion; a caller that knows where the players
## are (DarknessGhost does) is free to pick a different one from this list.
func get_frontier_zones() -> Array[ElectricalZone]:
	_prune_restored_zones()
	var candidates: Array[ElectricalZone] = []
	if darkened_zones.is_empty():
		return candidates
	for source: ElectricalZone in darkened_zones:
		for neighbour_id: StringName in zone_neighbours.get(source.zone_id, PackedStringArray()):
			var neighbour := _zone_by_id(neighbour_id)
			if neighbour and neighbour.is_powered and neighbour not in candidates:
				candidates.append(neighbour)
	return candidates


## Immediate version kept as a reusable component API. DarknessGhost itself
## uses get_next_neighbouring_zone() and waits until it physically arrives.
func expand_to_neighbouring_zone() -> ElectricalZone:
	return cause_zone_outage(get_next_neighbouring_zone())


func has_active_zone_outage() -> bool:
	_prune_restored_zones()
	return not darkened_zones.is_empty()


## The hunt is what holds the pocket dark, so it comes back with the hunt. That
## is not a convenience: the next haunting selects the zone the marked player is
## standing in and can only cut a *powered* one, so a wing left off by hand would
## quietly retire itself from the rest of the night. Fixtures a player had
## deliberately switched off before the outage stay off - ElectricalDevice
## restores the state it recorded, not "on".
func clear_zone_outage(restore_power: bool = true) -> void:
	if restore_power:
		for zone: ElectricalZone in darkened_zones:
			if is_instance_valid(zone):
				zone.set_powered(true)
	active_zone = null
	darkened_zones.clear()


func _zone_by_id(zone_id: StringName) -> ElectricalZone:
	for node: Node in get_tree().get_nodes_in_group("electrical_zones"):
		var zone := node as ElectricalZone
		if zone and zone.zone_id == zone_id:
			return zone
	return null


func _prune_restored_zones() -> void:
	for index: int in range(darkened_zones.size() - 1, -1, -1):
		var zone := darkened_zones[index]
		if not is_instance_valid(zone) or (zone.is_powered and not zone.requires_switch_restore):
			darkened_zones.remove_at(index)
	if active_zone not in darkened_zones:
		active_zone = darkened_zones[0] if not darkened_zones.is_empty() else null

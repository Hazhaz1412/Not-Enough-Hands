class_name StunStickItem
extends PickupItem

## A brittle emergency tool. It only interrupts the Crawler; hitting another
## ghost intentionally teaches the player the tool is not a universal weapon.

@export_range(1, 10, 1) var durability: int = 3
@export var reach: float = 2.0
@export_range(0.1, 1.0, 0.05) var arc_dot_threshold: float = 0.55


func use(player: Node) -> bool:
	if not WorldNet.is_world_authority() or durability <= 0 or player == null:
		return false
	var target := _find_target(player)
	if target == null:
		return false
	if target.has_method(&"apply_stun"):
		target.call(&"apply_stun", 1.5)
		_consume_durability(player)
		return true
	if target.has_method(&"apply_snare"):
		_break(player)
		return true
	# The Statue receives no status effect, but the wasted strike still costs a
	# charge so trial-and-error cannot become free scouting.
	_consume_durability(player)
	return true


func _find_target(player: Node) -> Node3D:
	if not player.has_method(&"get_tactical_use_origin") or not player.has_method(&"get_tactical_use_direction"):
		return null
	var origin := player.call(&"get_tactical_use_origin") as Vector3
	var direction := (player.call(&"get_tactical_use_direction") as Vector3).normalized()
	var best: Node3D = null
	var best_distance := reach
	for node: Node in _tactical_ghosts():
		var ghost := node as Node3D
		if ghost == null:
			continue
		var offset := ghost.global_position - origin
		var distance := offset.length()
		if distance > best_distance or distance <= 0.01:
			continue
		if direction.dot(offset / distance) < arc_dot_threshold:
			continue
		best = ghost
		best_distance = distance
	return best


func _tactical_ghosts() -> Array[Node]:
	var ghosts: Array[Node] = []
	for group: StringName in [&"hostile_ghosts", &"darkness_ghosts"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node not in ghosts:
				ghosts.append(node)
	return ghosts


func _consume_durability(player: Node) -> void:
	durability = maxi(durability - 1, 0)
	if durability <= 0:
		_break(player)
	else:
		WorldNet.report_entity_state(self)


func _break(player: Node) -> void:
	if player and player.has_method(&"release_held_item"):
		player.call(&"release_held_item", self)
	queue_free()


func get_replication_state() -> Array:
	return [durability]


func apply_replication_state(state: Array) -> void:
	if not state.is_empty():
		durability = int(state[0])

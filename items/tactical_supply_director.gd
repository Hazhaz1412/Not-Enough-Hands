class_name TacticalSupplyDirector
extends Node

## A one-shot, map-agnostic supply drop. Unlike the ritual, these are finite
## emergency tools: their initial population is all the team will ever get.

const TRAP_SCENE := preload("res://items/trap_item.tscn")
const STUN_STICK_SCENE := preload("res://items/stun_stick_item.tscn")

@export_range(0, 12, 1) var traps_per_map: int = 4
@export_range(0, 12, 1) var sticks_per_map: int = 3
@export var spawn_room_group: StringName = &"house2_rooms"
@export var spawn_drop_height: float = 0.8
@export_range(1, 32, 1) var nearby_room_candidates: int = 12

var _started := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	begin.call_deferred()


func begin() -> void:
	if _started or not WorldNet.is_world_authority():
		return
	_started = true
	# Both maps create their collision in _ready(); wait so a physics item never
	# falls through a floor that has not entered the physics world yet.
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_spawn_supply(TRAP_SCENE, traps_per_map)
	_spawn_supply(STUN_STICK_SCENE, sticks_per_map)


func _spawn_supply(scene: PackedScene, count: int) -> void:
	var rooms: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(spawn_room_group):
		var room := node as Node3D
		if room:
			rooms.append(room)
	if rooms.is_empty():
		push_warning("TacticalSupplyDirector: no room markers available for supplies")
		return
	# The villa is large enough that a uniform choice can place every emergency
	# tool in an unexplored wing. Pick randomly from the rooms nearest the team
	# at match start: still a search, but players can actually discover the new
	# loop in a normal first run.
	var player_positions: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player:
			player_positions.append(player.global_position)
	if not player_positions.is_empty():
		rooms.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return _nearest_player_distance(a.global_position, player_positions) < _nearest_player_distance(b.global_position, player_positions)
		)
		rooms = rooms.slice(0, mini(nearby_room_candidates, rooms.size()))
	rooms.shuffle()
	for index in mini(count, rooms.size()):
		var room := rooms[index]
		var position := room.global_position + Vector3(0, spawn_drop_height, 0)
		var item := WorldNet.spawn(scene, get_tree().current_scene, position, _rng.randf_range(-PI, PI))
		# Pickups begin frozen so authored items do not wobble. Runtime supplies
		# need one fall to settle onto procedural furniture on the authority.
		if item is RigidBody3D:
			(item as RigidBody3D).freeze = false


func _nearest_player_distance(position: Vector3, player_positions: Array[Vector3]) -> float:
	var nearest := INF
	for player_position in player_positions:
		nearest = minf(nearest, position.distance_squared_to(player_position))
	return nearest

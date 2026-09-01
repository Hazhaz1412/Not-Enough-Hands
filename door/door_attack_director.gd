class_name DoorAttackDirector
extends Node

signal attack_wave_started(targets: Array[Node])

@export_range(1, 3, 1) var minimum_targets: int = 1
@export_range(1, 3, 1) var maximum_targets: int = 3
@export_range(0.0, 1.0, 0.01) var false_alarm_chance: float = 0.3
@export var automatic_waves: bool = false
@export var wave_delay_min: float = 18.0
@export var wave_delay_max: float = 32.0

var _wave_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_schedule_next_wave()


func _process(delta: float) -> void:
	# One schedule for the whole house. A client's copy of the wave timer would
	# pick its own doors at its own moments, so it never runs.
	if not automatic_waves or not WorldNet.is_world_authority():
		return
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		start_attack_wave()
		_schedule_next_wave()


## Starts one wave against no more than three currently idle doors. Each chosen
## door independently decides whether its scratching is a real attack or a bluff.
func start_attack_wave(requested_count: int = -1) -> Array[Node]:
	var candidates: Array[Node] = []
	var active_count := 0
	for node: Node in get_tree().get_nodes_in_group("defense_doors"):
		if not node.has_method("begin_targeting"):
			continue
		var phase := int(node.get("attack_phase"))
		if phase in [
			DefenseDoor.AttackPhase.STALKING,
			DefenseDoor.AttackPhase.WEAK_ATTACK,
			DefenseDoor.AttackPhase.STRONG_ATTACK,
		]:
			active_count += 1
			continue
		if phase != DefenseDoor.AttackPhase.IDLE:
			continue
		if float(node.get("current_durability")) <= 0.0:
			continue
		candidates.append(node)

	var available_slots := maxi(3 - active_count, 0)
	if candidates.is_empty() or available_slots == 0:
		return []

	_shuffle(candidates)
	var target_count := requested_count
	if target_count < 0:
		target_count = _rng.randi_range(minimum_targets, maximum_targets)
	target_count = clampi(target_count, 1, mini(available_slots, candidates.size()))

	var selected: Array[Node] = []
	for index: int in target_count:
		var door := candidates[index]
		var will_attack := _rng.randf() >= false_alarm_chance
		if door.call("begin_targeting", will_attack):
			selected.append(door)

	if not selected.is_empty():
		attack_wave_started.emit(selected)
	return selected


## Deterministic development hook: starts a real attack at one authored
## entrance and skips the stalking delay so the requested door reacts at once.
func start_attack_at_entrance(entrance_id: int) -> Node:
	for node: Node in get_tree().get_nodes_in_group("defense_doors"):
		if not node is DefenseDoor or int(node.get("entrance_id")) != entrance_id:
			continue
		var door := node as DefenseDoor
		if door.current_durability <= 0.0:
			return null
		if door.attack_phase in [
			DefenseDoor.AttackPhase.STALKING,
			DefenseDoor.AttackPhase.WEAK_ATTACK,
			DefenseDoor.AttackPhase.STRONG_ATTACK,
		]:
			door.drive_ghost_away()
		if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
			return null
		if door.begin_targeting(true, 0.0):
			var selected: Array[Node] = [door]
			attack_wave_started.emit(selected)
			return door
		return null
	return null


func set_random_seed(value: int) -> void:
	_rng.seed = value


func _schedule_next_wave() -> void:
	_wave_timer = _rng.randf_range(wave_delay_min, wave_delay_max)


func _shuffle(items: Array[Node]) -> void:
	for index: int in range(items.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary := items[index]
		items[index] = items[swap_index]
		items[swap_index] = temporary

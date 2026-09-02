class_name DoorAttackDirector
extends Node

signal attack_wave_started(targets: Array[Node])

@export_range(1, 3, 1) var minimum_targets: int = 1
@export_range(1, 3, 1) var maximum_targets: int = 3
@export_range(0.0, 1.0, 0.01) var false_alarm_chance: float = 0.2
@export var automatic_waves: bool = false
@export var wave_delay_min: float = 9.0
@export var wave_delay_max: float = 16.0
## How much harder a wave leans on an entrance that is already losing. A
## pristine door weighs 1; one on its last points weighs this. It is a bias and
## not a rule on purpose - the strongest door is never safe, it is only rarer -
## so a team cannot leave six entrances unwatched by sacrificing the seventh.
@export_range(1.0, 32.0, 0.5) var weak_door_focus: float = 8.0

@export_category("Short-handed tempo")
## The gap between waves is multiplied by this once per missing player,
## compounding, so the tempo steepens as the team thins instead of stepping once
## at "not four". Door warnings are now shown to every team independently of
## this pacing rule.
## At the default a trio plays at 0.82 of the authored gap, a pair at 0.67 and a
## lone survivor at 0.55.
##
## Note that the wave size itself is not scaled - three doors is still three
## doors - so if a short-handed house turns out to be *harder* rather than
## differently paced, this is the knob, and capping concurrent targets by the
## headcount is the next step after it.
@export_range(0.5, 1.0, 0.01) var short_handed_delay_scale: float = 0.82
@export_range(1, 8, 1) var full_team_size: int = 4

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

	var target_count := requested_count
	if target_count < 0:
		target_count = _rng.randi_range(minimum_targets, maximum_targets)
	target_count = clampi(target_count, 1, mini(available_slots, candidates.size()))

	var selected: Array[Node] = []
	for _index: int in target_count:
		var door := _take_weighted(candidates)
		if not door:
			break
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
	_wave_timer = _rng.randf_range(wave_delay_min, wave_delay_max) * _short_handed_scale()


## One multiplier per empty slot. Reads the roster through DefenseDoor because
## the doors are what is being balanced and this director already speaks that
## class - a second copy of "who is still in the run" is how the two drift apart.
func _short_handed_scale() -> float:
	var missing := maxi(full_team_size - DefenseDoor.players_in_run(get_tree()), 0)
	if missing <= 0:
		return 1.0
	return pow(short_handed_delay_scale, float(missing))


## Draws one door out of `items`, favouring the ones already close to breaking,
## and removes it so the same door is never picked twice in one wave.
func _take_weighted(items: Array[Node]) -> Node:
	if items.is_empty():
		return null
	var weights: Array[float] = []
	var total := 0.0
	for door: Node in items:
		var weight := _door_weight(door)
		weights.append(weight)
		total += weight
	var roll := _rng.randf() * total
	for index: int in items.size():
		roll -= weights[index]
		if roll <= 0.0:
			return items.pop_at(index)
	return items.pop_back()


## 1 for a door in the best condition it can currently be in, `weak_door_focus`
## for one about to fall.
##
## Measured against `repair_cap` rather than `max_durability` because the cap is
## what a fully repaired door actually reaches - every hit lowers it for good, so
## dividing by the original maximum would score a door the players have already
## restored as far as it will go as though it were still damaged, and the bias
## would compound onto whichever entrance was unlucky first. The cap is the
## current ceiling; how close the door is to zero *within* that is its condition.
func _door_weight(door: Node) -> float:
	var ceiling := maxf(float(door.get("repair_cap")), 0.01)
	var ratio := clampf(float(door.get("current_durability")) / ceiling, 0.0, 1.0)
	return lerpf(weak_door_focus, 1.0, ratio)

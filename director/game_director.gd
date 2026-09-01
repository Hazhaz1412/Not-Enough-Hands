class_name GameDirector
extends Node

## Paces the night so the house is never quiet for long and never piles on.
##
## Nothing here is a new threat. Every beat it plays already existed - a door
## attack wave, a wing going dark, a ghost starting its hunt cycle early - and
## each of those had its own timer that knew nothing about the other three. In a
## 548-second night that meant a statue ambush, a crawler hunt and a three-door
## wave could land inside the same ten seconds, and it also meant a team could
## get a minute of nothing at all. This is the valve on the timers that already
## exist, not another source of pressure.
##
## The loop is the familiar four beats, driven by one measured quantity:
##
##   BUILD_UP  quiet enough to add to. Events fire here and nowhere else.
##   PEAK      the pressure has arrived. Nothing new is added, so a peak costs a
##             known amount rather than snowballing into whatever else was due.
##   FADE      the peak is spent. Attacks are held for `fade_mercy_seconds` so a
##             peak can never roll straight into a kill.
##   CALM      a hard floor of quiet to repair, haul and breathe in. If it stays
##             quiet past `boredom_time` the director forces the next beat.
##
## ## The two promises
##
## *Always something happening*: CALM cannot outlast `calm_floor + boredom_time`
## without firing an event, whatever else is going on.
##
## *Never a forced death*: three rails, in falling order of bluntness.
##   1. A downed player holds every ghost's attacks until they are up or gone.
##      This is the anti-cascade rule - a downed teammate used to be the most
##      attractive target in the house, which is how one loss became a wipe.
##   2. A concurrency budget. Every engaged ghost costs 1, every door under
##      attack costs `door_threat_weight`, and the director refuses to start
##      anything it cannot afford. It refuses; it never queues.
##   3. `grip`, which drifts down when the team loses ground and up when it
##      gains, stretching or shortening every wait. Slow and invisible on
##      purpose - it is a floor under a bad night, not a rubber band.
##
## ## What it deliberately does not do
##
## It does not rewrite the ghosts' own hunt cycles. Each ghost keeps the pacing
## it was authored with; the director only ever *adds* a beat when the house is
## quiet, *refuses* to add one when it is not, and *holds* attacks during mercy.
## Writing their `hidden_delay` knobs on top of that would be two systems
## steering the same thing - the concurrency budget already covers a ghost that
## started a hunt on its own, because `is_engaged()` counts it either way.
##
## Server-only, exactly like DoorAttackDirector: one schedule for the whole
## house. Everything it triggers already replicates on its own, so the director
## itself sends nothing.

signal phase_changed(new_phase: Phase)
signal event_fired(event: Event)

enum Phase { BUILD_UP, PEAK, FADE, CALM }

## The beats it can play. Each one is a call into a system that already owns the
## behaviour - the director picks the moment and nothing else.
enum Event {
	DOOR_WAVE,
	REGIONAL_BLACKOUT,
	GHOST_HUNT,
}

@export_category("Wiring")
@export var enabled: bool = true
## Same convention ui/dev_tools.gd uses to reach it.
@export var door_director_path: NodePath = NodePath("../DoorAttackDirector")
## The world is sampled on this interval rather than every frame. Nothing here
## resolves faster than a second, and the sweep walks four node groups.
@export_range(0.05, 1.0, 0.05) var sample_interval: float = 0.25

@export_category("Stress")
## Rises instantly to whatever the worst-off player is feeling and decays from
## full to nothing over this many seconds of genuine quiet. Asymmetric on
## purpose: a scare should not be erased two seconds after it lands.
@export_range(1.0, 120.0, 0.5) var stress_decay_seconds: float = 18.0
## A player in a first-person encounter is under real pressure even with no
## ghost reporting threat at them - they cannot move or look away.
@export_range(0.0, 1.0, 0.05) var encounter_pressure: float = 0.6
## Added while the house is dark and the player is carrying no light of its own.
@export_range(0.0, 1.0, 0.05) var darkness_pressure: float = 0.15

@export_category("Phases")
@export_range(0.0, 1.0, 0.05) var peak_threshold: float = 0.65
## Leaving PEAK early: the moment the pressure drops this far the peak is over,
## without waiting out its full duration.
@export_range(0.0, 1.0, 0.05) var peak_release: float = 0.35
@export_range(1.0, 120.0, 1.0) var peak_duration_min: float = 20.0
@export_range(1.0, 120.0, 1.0) var peak_duration_max: float = 30.0
@export_range(0.0, 1.0, 0.05) var fade_exit: float = 0.15
@export_range(1.0, 120.0, 1.0) var fade_max: float = 25.0
## How long into FADE every ghost's attacks stay held. This is the window that
## stops a peak rolling straight into a kill; it is short because a house where
## the ghosts cannot hurt anybody stops being frightening quickly.
@export_range(0.0, 30.0, 0.5) var fade_mercy_seconds: float = 6.0
## Hard floor of quiet after a peak, before the boredom watch even starts.
@export_range(0.0, 180.0, 1.0) var calm_floor: float = 30.0
@export_range(0.0, 1.0, 0.01) var boredom_level: float = 0.12
@export_range(1.0, 180.0, 1.0) var boredom_time: float = 25.0
## Minimum gap between any two events, whatever their own cooldowns say. This is
## what stops two beats landing on top of each other inside one BUILD_UP.
@export_range(0.0, 60.0, 0.5) var min_event_spacing: float = 8.0

@export_category("Concurrency budget")
@export_range(0.0, 8.0, 0.25) var threat_cap_base: float = 1.5
@export_range(0.0, 4.0, 0.25) var threat_cap_per_player: float = 0.5
## A door under attack is a threat, but a slower and more answerable one than a
## ghost with a lead, so it costs less of the budget.
@export_range(0.0, 2.0, 0.05) var door_threat_weight: float = 0.5
## Holds every ghost's attacks while anybody is down. The single most important
## rail here: without it the rescue window is the most dangerous moment there is.
@export var downed_suspends_attacks: bool = true

@export_category("Difficulty drift")
@export var grip_enabled: bool = true
@export_range(0.1, 1.0, 0.05) var grip_min: float = 0.4
@export_range(1.0, 3.0, 0.05) var grip_max: float = 1.4
@export_range(0.01, 0.5, 0.01) var grip_step: float = 0.08

@export_category("Event cooldowns")
@export_range(1.0, 300.0, 1.0) var door_wave_cooldown: float = 16.0
@export_range(1.0, 300.0, 1.0) var blackout_cooldown: float = 55.0
@export_range(1.0, 300.0, 1.0) var ghost_hunt_cooldown: float = 50.0
## How far ahead a ghost asked to hunt is allowed to still be waiting. It is not
## zero: the ghost's own announcement - the crawler's omen, the statue's ambush
## placement - is the warning, and it needs a moment to happen.
@export_range(0.0, 30.0, 0.5) var ghost_hunt_lead_in: float = 3.0
@export_range(1.0, 120.0, 1.0) var regional_blackout_duration: float = 14.0

var phase: Phase = Phase.CALM
var stress: float = 0.0
var grip: float = 1.0

var _sample_accumulator: float = 0.0
var _phase_time: float = 0.0
var _boredom_time_held: float = 0.0
var _peak_target_duration: float = 0.0
var _event_cooldowns: Dictionary = {}
var _spacing_remaining: float = 0.0
var _attacks_held: bool = false

# --- world sample, refreshed once per sample_interval -------------------------
var _active_players: int = 0
var _downed_players: int = 0
var _pressure: float = 0.0
var _engaged_ghosts: int = 0
var _door_load: float = 0.0
var _damaged_door_ratio: float = 0.0
var _breached_doors: int = 0
var _is_blackout: bool = false

# --- ground gained or lost since the last phase boundary ----------------------
var _setbacks: int = 0
var _gains: int = 0
var _previous_downed: int = 0
var _previous_breached: int = 0
var _previous_totems_burned: int = 0

var _rng := RandomNumberGenerator.new()
var _door_director: Node = null


func _ready() -> void:
	add_to_group(&"game_director")
	_rng.randomize()
	_peak_target_duration = _roll_peak_duration()
	for event: Event in Event.values():
		_event_cooldowns[event] = 0.0


func _process(delta: float) -> void:
	# One schedule for the whole house, for the same reason DoorAttackDirector
	# has one: a client running its own copy would pick its own moments.
	if not enabled or not WorldNet.is_world_authority():
		return
	advance_seconds(delta)


## Drives the whole director forward by `seconds`, in fixed sample steps.
##
## Public for the same reason NightClock.advance_real_seconds() is: the smoke
## test has to run a night's worth of pacing in a few milliseconds, and stepping
## it here rather than reaching into `_process` keeps every phase boundary and
## cooldown landing exactly where it would in a real session.
func advance_seconds(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_sample_accumulator += seconds
	var step := maxf(sample_interval, 0.01)
	while _sample_accumulator >= step:
		_sample_accumulator -= step
		_tick(step)


## Whether the world can afford one more scripted escalation right now. Exposed
## so map scripts with a reinforcement of their own to spend - the villa's
## second huntsman - can ask instead of firing on a bare clock.
func can_escalate() -> bool:
	if not enabled:
		return true
	return phase == Phase.BUILD_UP \
		and _downed_players == 0 \
		and _threat_headroom() >= 1.0


func get_threat_load() -> float:
	return float(_engaged_ghosts) + _door_load


func get_threat_cap() -> float:
	return threat_cap_base + threat_cap_per_player * float(_active_players)


func set_random_seed(value: int) -> void:
	_rng.seed = value


## Deterministic hook for tests and the dev panel: runs one beat now if the
## budget allows it, bypassing cooldowns and spacing but never the cap.
func force_event(event: Event) -> bool:
	if not _can_afford(event):
		return false
	return _fire(event)


func _tick(delta: float) -> void:
	_sample_world()
	_advance_stress(delta)
	_tick_cooldowns(delta)
	_apply_attack_hold()
	_phase_time += delta
	_advance_phase(delta)


# --- measurement --------------------------------------------------------------


## One sweep of the four groups the director reads. Everything below this line
## works off the results rather than walking the tree again.
func _sample_world() -> void:
	_active_players = 0
	_downed_players = 0
	var worst := 0.0
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var downed := bool(node.get(&"is_downed"))
		var alive := bool(node.get(&"is_alive"))
		if downed:
			# A downed player is the whole picture: nothing else in the house
			# is more pressing than the clock running out on a teammate.
			_downed_players += 1
			worst = 1.0
			continue
		if not alive:
			continue
		_active_players += 1
		worst = maxf(worst, _player_pressure(node))
	_pressure = clampf(worst, 0.0, 1.0)

	_engaged_ghosts = 0
	for ghost: Node in get_tree().get_nodes_in_group(&"hostile_ghosts"):
		if ghost.has_method(&"is_engaged") and bool(ghost.call(&"is_engaged")):
			_engaged_ghosts += 1

	_door_load = 0.0
	_breached_doors = 0
	var door_count := 0
	var condition_total := 0.0
	for door: Node in get_tree().get_nodes_in_group(&"defense_doors"):
		if not door.has_method(&"begin_targeting"):
			continue
		door_count += 1
		var phase_value := int(door.get(&"attack_phase"))
		if phase_value in [
			DefenseDoor.AttackPhase.STALKING,
			DefenseDoor.AttackPhase.WEAK_ATTACK,
			DefenseDoor.AttackPhase.STRONG_ATTACK,
		]:
			_door_load += door_threat_weight
		if float(door.get(&"current_durability")) <= 0.0:
			_breached_doors += 1
		var ceiling := maxf(float(door.get(&"repair_cap")), 0.01)
		condition_total += clampf(float(door.get(&"current_durability")) / ceiling, 0.0, 1.0)
	_damaged_door_ratio = 0.0 if door_count == 0 \
		else 1.0 - condition_total / float(door_count)

	var power := _power_manager()
	_is_blackout = power != null and bool(power.get(&"is_blackout"))

	_track_ground()


func _player_pressure(player: Node) -> float:
	var value := clampf(float(player.get(&"statue_threat")), 0.0, 1.0)
	if player.has_method(&"is_door_minigame_active") \
		and bool(player.call(&"is_door_minigame_active")):
		value = maxf(value, encounter_pressure)
	if _is_blackout:
		value += darkness_pressure
	return clampf(value, 0.0, 1.0)


## Rises to the worst live pressure at once, decays only in real quiet.
func _advance_stress(delta: float) -> void:
	if _pressure >= stress:
		stress = _pressure
		return
	stress = maxf(stress - delta / maxf(stress_decay_seconds, 0.01), _pressure)


## Counts what changed since the last phase boundary, so grip can be moved once
## per boundary on evidence rather than drifting every frame on a level.
func _track_ground() -> void:
	if _downed_players > _previous_downed:
		_setbacks += _downed_players - _previous_downed
	_previous_downed = _downed_players

	if _breached_doors > _previous_breached:
		_setbacks += _breached_doors - _previous_breached
	_previous_breached = _breached_doors

	var ritual := get_tree().get_first_node_in_group(&"totem_ritual")
	if ritual != null:
		var burned := int(ritual.get(&"totems_burned"))
		if burned > _previous_totems_burned:
			_gains += burned - _previous_totems_burned
		_previous_totems_burned = burned


# --- phases -------------------------------------------------------------------


func _advance_phase(delta: float) -> void:
	match phase:
		Phase.BUILD_UP:
			_try_escalate()
			if stress >= peak_threshold:
				_enter_phase(Phase.PEAK)
		Phase.PEAK:
			if _phase_time >= _peak_target_duration or stress < peak_release:
				_enter_phase(Phase.FADE)
		Phase.FADE:
			if _phase_time >= fade_max or stress < fade_exit:
				_enter_phase(Phase.CALM)
		Phase.CALM:
			_advance_calm(delta)


## The one place the "always something happening" promise is kept. The floor is
## unconditional; past it, quiet is counted and answered.
func _advance_calm(delta: float) -> void:
	if _phase_time < calm_floor / grip:
		return
	if stress >= boredom_level:
		# Something is happening on its own - a ghost's own cycle, most likely.
		# Hand the night back to BUILD_UP and let the budget govern it.
		_boredom_time_held = 0.0
		_enter_phase(Phase.BUILD_UP)
		return
	_boredom_time_held += delta
	if _boredom_time_held < boredom_time / grip:
		return
	_boredom_time_held = 0.0
	_enter_phase(Phase.BUILD_UP)
	# Ignores spacing and cooldowns, but never the budget: boredom is a reason
	# to act, not a reason to be unfair.
	_try_escalate(true)


func _enter_phase(next_phase: Phase) -> void:
	if phase == next_phase:
		return
	phase = next_phase
	_phase_time = 0.0
	if next_phase == Phase.PEAK:
		_peak_target_duration = _roll_peak_duration()
	_settle_grip()
	phase_changed.emit(phase)


## Moved once per boundary, by one step, on what actually happened during the
## stretch that just ended. Setbacks outrank gains: a night that cost somebody a
## life does not also get credit for the totem they burned before it.
func _settle_grip() -> void:
	if not grip_enabled:
		_setbacks = 0
		_gains = 0
		return
	if _setbacks > 0:
		grip = clampf(grip - grip_step * float(_setbacks), grip_min, grip_max)
	elif _gains > 0:
		grip = clampf(grip + grip_step, grip_min, grip_max)
	_setbacks = 0
	_gains = 0


func _roll_peak_duration() -> float:
	var low := minf(peak_duration_min, peak_duration_max)
	var high := maxf(peak_duration_min, peak_duration_max)
	return _rng.randf_range(low, high)


# --- events -------------------------------------------------------------------


func _tick_cooldowns(delta: float) -> void:
	_spacing_remaining = maxf(_spacing_remaining - delta, 0.0)
	for event: Event in _event_cooldowns.keys():
		_event_cooldowns[event] = maxf(float(_event_cooldowns[event]) - delta, 0.0)


## Picks one affordable beat and plays it. Weighted rather than round-robin so
## the night does not become a rotation the players can read off.
func _try_escalate(ignore_timing: bool = false) -> void:
	if not ignore_timing and _spacing_remaining > 0.0:
		return
	if _active_players <= 0:
		return

	var candidates: Array[Event] = []
	var weights: Array[float] = []
	var total := 0.0
	for event: Event in Event.values():
		if not ignore_timing and float(_event_cooldowns[event]) > 0.0:
			continue
		if not _can_afford(event):
			continue
		var weight := _event_weight(event)
		if weight <= 0.0:
			continue
		candidates.append(event)
		weights.append(weight)
		total += weight
	if candidates.is_empty():
		return

	var roll := _rng.randf() * total
	for index: int in candidates.size():
		roll -= weights[index]
		if roll <= 0.0:
			_fire(candidates[index])
			return
	_fire(candidates[candidates.size() - 1])


func _threat_headroom() -> float:
	return get_threat_cap() - get_threat_load()


func _can_afford(event: Event) -> bool:
	if _downed_players > 0:
		# Nothing new while somebody is on the floor. The rescue is the event.
		return false
	return _threat_headroom() >= _event_cost(event)


func _event_cost(event: Event) -> float:
	match event:
		Event.DOOR_WAVE:
			return door_threat_weight
		Event.REGIONAL_BLACKOUT:
			return door_threat_weight
		Event.GHOST_HUNT:
			return 1.0
	return 1.0


## What the house is *not* currently giving the players to do. A beat is worth
## more the less the team already has on its hands of that kind - this is the
## "always work to do" axis, and it is deliberately about work, not danger.
func _event_weight(event: Event) -> float:
	match event:
		Event.DOOR_WAVE:
			return lerpf(2.5, 0.6, clampf(_damaged_door_ratio, 0.0, 1.0))
		Event.REGIONAL_BLACKOUT:
			return 0.0 if _is_blackout else 1.2
		Event.GHOST_HUNT:
			return 1.0 if _engaged_ghosts == 0 else 0.3
	return 0.0


func _fire(event: Event) -> bool:
	var fired := false
	match event:
		Event.DOOR_WAVE:
			fired = _fire_door_wave()
		Event.REGIONAL_BLACKOUT:
			fired = _fire_regional_blackout()
		Event.GHOST_HUNT:
			fired = _fire_ghost_hunt()
	if not fired:
		# Nothing was available - a short retry rather than the full cooldown,
		# or a house with every door already busy would go silent for a minute.
		_event_cooldowns[event] = maxf(min_event_spacing, 1.0)
		return false
	_event_cooldowns[event] = _cooldown_for(event) / grip
	_spacing_remaining = min_event_spacing / grip
	event_fired.emit(event)
	return true


func _cooldown_for(event: Event) -> float:
	match event:
		Event.DOOR_WAVE:
			return door_wave_cooldown
		Event.REGIONAL_BLACKOUT:
			return blackout_cooldown
		Event.GHOST_HUNT:
			return ghost_hunt_cooldown
	return 30.0


## One door at a time, always. The door director can still take three, but that
## is its own emergency ceiling - the paced night spends its budget in single
## doors so a wave is something a team can answer rather than triage.
func _fire_door_wave() -> bool:
	var director := _resolve_door_director()
	if director == null or not director.has_method(&"start_attack_wave"):
		return false
	var selected: Array = director.call(&"start_attack_wave", 1)
	return not selected.is_empty()


func _fire_regional_blackout() -> bool:
	var power := _power_manager()
	if power == null or not power.has_method(&"trigger_random_regional_blackout"):
		return false
	return int(power.call(
		&"trigger_random_regional_blackout", regional_blackout_duration
	)) > 0


## Asks whichever ghost is currently between hunts to start the next one early.
## Which ghost it is does not matter to the director - the crawler and the
## statue counter different behaviour, and letting the house pick keeps this map
## and roster agnostic.
func _fire_ghost_hunt() -> bool:
	var willing: Array[Node] = []
	for ghost: Node in get_tree().get_nodes_in_group(&"hostile_ghosts"):
		if ghost.has_method(&"request_hunt_soon"):
			willing.append(ghost)
	while not willing.is_empty():
		var index := _rng.randi_range(0, willing.size() - 1)
		var ghost: Node = willing.pop_at(index)
		if bool(ghost.call(&"request_hunt_soon", ghost_hunt_lead_in)):
			return true
	return false


# --- mercy --------------------------------------------------------------------


## The only thing the director does to a ghost that is already in the house.
## It holds attacks; it never moves one, never despawns one and never touches a
## chase that is underway - a ghost the players can see behaves exactly as
## authored, it simply cannot land the blow during the hold.
func _should_hold_attacks() -> bool:
	if downed_suspends_attacks and _downed_players > 0:
		return true
	return phase == Phase.FADE and _phase_time < fade_mercy_seconds


func _apply_attack_hold() -> void:
	var hold := _should_hold_attacks()
	if hold == _attacks_held:
		return
	_attacks_held = hold
	for ghost: Node in get_tree().get_nodes_in_group(&"hostile_ghosts"):
		if ghost.has_method(&"set_director_attacks_suspended"):
			ghost.call(&"set_director_attacks_suspended", hold)


# --- lookups ------------------------------------------------------------------


func _resolve_door_director() -> Node:
	if is_instance_valid(_door_director):
		return _door_director
	_door_director = get_node_or_null(door_director_path)
	return _door_director


func _power_manager() -> Node:
	return get_tree().get_first_node_in_group(&"power_manager")

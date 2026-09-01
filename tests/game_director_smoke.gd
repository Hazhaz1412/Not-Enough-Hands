extends SceneTree

## Pins the two promises GameDirector exists to keep, plus the rails that make
## the second one true. No map is loaded: the director reads the world through
## four node groups, so a handful of stand-ins in those groups is the whole
## world as far as it is concerned - which is also the point of it being written
## against groups instead of against House2 or the villa.


## Stands in for player/player.gd. The director reads exactly these three, so
## these three are all it needs to be.
class FakePlayer:
	extends Node
	var is_alive: bool = true
	var is_downed: bool = false
	var statue_threat: float = 0.0

	func _ready() -> void:
		add_to_group(&"players")


## Stands in for a ghost. Records the director's hold rather than acting on it,
## because what is under test is the director's decision, not the ghost's.
class FakeGhost:
	extends Node
	var engaged: bool = false
	var suspended: bool = false
	var accepts_hunts: bool = true
	var hunt_requests: int = 0

	func _ready() -> void:
		add_to_group(&"hostile_ghosts")

	func is_engaged() -> bool:
		return engaged

	func set_director_attacks_suspended(value: bool) -> void:
		suspended = value

	func request_hunt_soon(_within_seconds: float) -> bool:
		hunt_requests += 1
		return accepts_hunts


var _events: Array[int] = []
var _phases: Array[Array] = []
var _elapsed: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not await _test_quiet_is_always_answered():
		return
	if not await _test_the_budget_refuses_rather_than_queues():
		return
	if not await _test_a_downed_player_holds_every_ghost():
		return
	if not await _test_a_peak_is_bounded():
		return
	if not await _test_grip_gives_ground_after_a_setback():
		return
	if not await _test_the_hold_releases_once_nobody_is_down():
		return

	print(
		"Game director smoke test passed: quiet is answered, the budget refuses,"
		+ " a down holds every ghost and releases, peaks are bounded, grip gives ground."
	)
	quit()


## The "always something happening" promise. Nothing in the world moves, so
## stress sits at zero forever; the director has to break the silence itself,
## and it has to wait out its own calm floor before doing so.
func _test_quiet_is_always_answered() -> bool:
	var arena := await _build_arena()
	var director: GameDirector = arena[0]
	var ghost: FakeGhost = arena[2]

	_advance(director, director.calm_floor - 2.0)
	if not _events.is_empty():
		_fail("Director fired inside its own calm floor (%.1fs)." % director.calm_floor)
		return false

	_advance(director, director.boredom_time + director.min_event_spacing + 6.0)
	if _events.is_empty():
		_fail(
			"Director stayed silent for %.0fs of nothing happening; boredom never fired."
			% _elapsed
		)
		return false
	if ghost.hunt_requests <= 0:
		_fail("Boredom fired an event but never reached the only ghost that could act.")
		return false

	await _teardown(arena)
	return true


## The rail that stops a night piling on. With the budget already spent, a
## request is turned down flat - never deferred into a queue that lands the
## moment the players finish the encounter they are already in.
func _test_the_budget_refuses_rather_than_queues() -> bool:
	var arena := await _build_arena()
	var director: GameDirector = arena[0]
	var ghost: FakeGhost = arena[2]
	var second_ghost := FakeGhost.new()
	arena[3].add_child(second_ghost)

	ghost.engaged = true
	second_ghost.engaged = true
	_advance(director, director.sample_interval * 2.0)

	var cap := director.get_threat_cap()
	var threat_load := director.get_threat_load()
	if threat_load < cap:
		_fail(
			"Two engaged ghosts scored %.2f against a cap of %.2f; the test cannot"
			% [threat_load, cap] + " reach the budget it is trying to exhaust."
		)
		return false
	if director.force_event(GameDirector.Event.GHOST_HUNT):
		_fail("Director started a hunt with its concurrency budget already spent.")
		return false

	var requests_before := ghost.hunt_requests
	_advance(director, director.calm_floor + director.boredom_time + 30.0)
	if ghost.hunt_requests > requests_before:
		_fail("Boredom overrode the concurrency budget; it must never be a reason to be unfair.")
		return false

	await _teardown(arena)
	return true


## The anti-cascade rail. A downed teammate used to be the most attractive
## target in the house, which is how one loss became a wipe.
func _test_a_downed_player_holds_every_ghost() -> bool:
	var arena := await _build_arena()
	var director: GameDirector = arena[0]
	var player: FakePlayer = arena[1]
	var ghost: FakeGhost = arena[2]

	player.is_alive = false
	player.is_downed = true
	_advance(director, director.sample_interval * 2.0)

	if not ghost.suspended:
		_fail("A player went down and the director never held the ghosts' attacks.")
		return false
	if director.force_event(GameDirector.Event.GHOST_HUNT):
		_fail("Director started a hunt while a player was down and being rescued.")
		return false
	if director.can_escalate():
		_fail("Director reported room to escalate while a player was down.")
		return false

	await _teardown(arena)
	return true


## A peak has to cost a known amount. Pinning the pressure at maximum forever is
## the worst case: the phase still has to end on its own clock.
func _test_a_peak_is_bounded() -> bool:
	var arena := await _build_arena()
	var director: GameDirector = arena[0]
	var player: FakePlayer = arena[1]

	player.statue_threat = 1.0
	_advance(director, director.calm_floor + director.peak_duration_max + 20.0)

	var peak_entry := -1.0
	var fade_entry := -1.0
	for row: Array in _phases:
		if int(row[0]) == GameDirector.Phase.PEAK and peak_entry < 0.0:
			peak_entry = float(row[1])
		elif int(row[0]) == GameDirector.Phase.FADE and peak_entry >= 0.0 and fade_entry < 0.0:
			fade_entry = float(row[1])
	if peak_entry < 0.0:
		_fail("Pressure was pinned at maximum and the director never reached PEAK.")
		return false
	if fade_entry < 0.0:
		_fail("Director entered PEAK and never left it; a peak has to be bounded.")
		return false
	var held := fade_entry - peak_entry
	if held > director.peak_duration_max + director.sample_interval * 2.0:
		_fail(
			"PEAK ran %.1fs against a ceiling of %.1fs."
			% [held, director.peak_duration_max]
		)
		return false

	await _teardown(arena)
	return true


## Grip is the slow floor under a bad night. One setback is enough to move it,
## and it has to move down - a night that cost somebody a life does not get
## harder because the phase happened to turn over.
func _test_grip_gives_ground_after_a_setback() -> bool:
	var arena := await _build_arena()
	var director: GameDirector = arena[0]
	var player: FakePlayer = arena[1]

	var before := director.grip
	player.is_alive = false
	player.is_downed = true
	# Long enough to cross at least one phase boundary, which is the only place
	# grip is ever allowed to move.
	_advance(director, director.calm_floor + director.peak_duration_max + 40.0)

	if director.grip >= before:
		_fail(
			"A player went down and grip stayed at %.2f; the night never eased off."
			% director.grip
		)
		return false
	if director.grip < director.grip_min - 0.001:
		_fail("Grip fell through its floor to %.2f." % director.grip)
		return false

	await _teardown(arena)
	return true


## Mercy is a window, not a state. A held ghost that is never released is a
## house that has stopped being frightening.
func _test_the_hold_releases_once_nobody_is_down() -> bool:
	var arena := await _build_arena()
	var director: GameDirector = arena[0]
	var player: FakePlayer = arena[1]
	var ghost: FakeGhost = arena[2]

	player.is_alive = false
	player.is_downed = true
	_advance(director, director.sample_interval * 2.0)
	if not ghost.suspended:
		_fail("The hold never went on, so this test cannot show it coming off.")
		return false

	player.is_downed = false
	player.is_alive = true
	player.statue_threat = 0.0
	_advance(director, director.fade_mercy_seconds + director.fade_max + 5.0)

	if ghost.suspended:
		_fail("Everybody was back on their feet and the director never released the ghosts.")
		return false

	await _teardown(arena)
	return true


# --- harness ------------------------------------------------------------------


## [director, player, ghost, arena_root]. Each test gets a fresh one: the
## director reads whole node groups, so a leftover ghost from the previous test
## is a ghost in this one's house.
func _build_arena() -> Array:
	var arena := Node.new()
	root.add_child(arena)

	var player := FakePlayer.new()
	arena.add_child(player)
	var ghost := FakeGhost.new()
	arena.add_child(ghost)

	var director := GameDirector.new()
	arena.add_child(director)
	director.set_process(false)
	director.set_random_seed(4141)

	_events.clear()
	_phases.clear()
	_elapsed = 0.0
	director.event_fired.connect(func(event: int) -> void: _events.append(event))
	director.phase_changed.connect(
		func(new_phase: int) -> void: _phases.append([new_phase, _elapsed])
	)
	return [director, player, ghost, arena]


func _teardown(arena: Array) -> void:
	var node: Node = arena[3]
	node.queue_free()
	await process_frame


## Steps the director in slices rather than one jump, so `_elapsed` is accurate
## enough to time a phase boundary against.
func _advance(director: GameDirector, seconds: float) -> void:
	var step := maxf(director.sample_interval, 0.01)
	var remaining := seconds
	while remaining > 0.0:
		var slice := minf(step, remaining)
		director.advance_seconds(slice)
		_elapsed += slice
		remaining -= slice


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

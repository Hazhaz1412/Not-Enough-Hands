extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://door/defense_door.tscn") as PackedScene
	var arena := Node3D.new()
	root.add_child(arena)
	var doors: Array[DefenseDoor] = []
	for index: int in 4:
		var door := packed_scene.instantiate() as DefenseDoor
		door.entrance_id = index + 1
		arena.add_child(door)
		door.set_physics_process(false)
		door.get_node("WarningAudio").stream = null
		door.get_node("StrongAttackAudio").stream = null
		doors.append(door)

	var director := DoorAttackDirector.new()
	director.false_alarm_chance = 0.0
	arena.add_child(director)
	director.set_process(false)
	director.set_random_seed(12)

	var selected := director.start_attack_wave(3)
	if selected.size() != 3:
		_fail("Director did not select exactly three defense doors.")
		return
	var active_count := 0
	for door: DefenseDoor in doors:
		if door.attack_phase == DefenseDoor.AttackPhase.STALKING:
			active_count += 1
	if active_count != 3:
		_fail("Director did not activate three doors simultaneously.")
		return
	if not director.start_attack_wave(9).is_empty():
		_fail("Director exceeded the three-door global attack limit.")
		return

	# The director reads the whole `defense_doors` group, so this arena has to be
	# gone before the next one is built or its three stalking doors fill every
	# attack slot in the house.
	arena.queue_free()
	await process_frame

	if not await _test_weak_doors_are_hunted_first(packed_scene):
		return
	if not await _test_repairing_restores_the_baseline_weight(packed_scene):
		return
	if not await _test_every_team_is_shown_the_door_and_short_teams_are_charged(packed_scene):
		return

	print(
		"Door attack director smoke test passed: three-door cap, weakest-first "
		+ "targeting, repaired doors back to baseline, universal warning marker and short-handed tempo."
	)
	quit()


## Every team now gets the five-second targeted-door warning. Short-handed teams
## still pay the existing faster wave tempo independently.
func _test_every_team_is_shown_the_door_and_short_teams_are_charged(
	packed_scene: PackedScene
) -> bool:
	var arena := Node3D.new()
	root.add_child(arena)
	var door := packed_scene.instantiate() as DefenseDoor
	arena.add_child(door)
	door.set_physics_process(false)
	door.get_node("WarningAudio").stream = null
	door.get_node("StrongAttackAudio").stream = null

	var director := DoorAttackDirector.new()
	arena.add_child(director)
	director.set_process(false)

	# An empty house is the extreme of short-handed, so the full multiplier
	# applies: four missing players, four compounding steps.
	var expected := pow(director.short_handed_delay_scale, float(director.full_team_size))
	if not is_equal_approx(director._short_handed_scale(), expected):
		_fail("An empty roster did not compound the wave delay once per missing player.")
		arena.queue_free()
		return false

	# An idle door is never marked, however thin the team. The marker answers
	# "which one is screaming", never "where are the doors".
	door._refresh_distress_marker()
	if door.get_node_or_null("ShortHandedDistress") != null:
		_fail("A quiet door was marked; the marker must not double as a map aid.")
		arena.queue_free()
		return false

	door.begin_targeting(true, 30.0)
	door._refresh_distress_marker()
	if door.get_node_or_null("ShortHandedDistress") == null:
		_fail("A short-handed team was not shown the entrance under attack.")
		arena.queue_free()
		return false

	# Simulating a full roster in the pacing director must not hide the warning.
	director.full_team_size = 0
	door._refresh_distress_marker()
	if door.get_node_or_null("ShortHandedDistress") == null:
		_fail("A full team did not receive the targeted-door warning.")
		arena.queue_free()
		return false

	arena.queue_free()
	await process_frame
	return true


## Condition, not history. Every hit lowers a door's repair ceiling for good, so
## a door the players have restored as far as it can go has to score the same as
## one that was never touched - otherwise the bias compounds onto whichever
## entrance was attacked first and never lets go of it.
func _test_repairing_restores_the_baseline_weight(packed_scene: PackedScene) -> bool:
	var arena := Node3D.new()
	root.add_child(arena)
	var director := DoorAttackDirector.new()
	arena.add_child(director)
	director.set_process(false)
	var door := packed_scene.instantiate() as DefenseDoor
	arena.add_child(door)
	door.set_physics_process(false)
	door.get_node("WarningAudio").stream = null
	door.get_node("StrongAttackAudio").stream = null
	await process_frame

	var pristine: float = director.call("_door_weight", door)
	if not is_equal_approx(pristine, 1.0):
		_fail("An untouched door weighs %.3f instead of 1." % pristine)
		return false

	door.take_damage(door.max_durability * 0.8)
	var damaged: float = director.call("_door_weight", door)
	if damaged <= pristine * 2.0:
		_fail("A door at %.0f/%.0f only weighs %.3f; the bias is not biting." % [
			door.current_durability, door.repair_cap, damaged,
		])
		return false

	# Repaired as far as the door will ever go again: current_durability now sits
	# on the lowered repair_cap, which is this door's best possible condition.
	door.repair(door.max_durability)
	if door.current_durability < door.repair_cap:
		_fail("The door did not repair up to its own ceiling.")
		return false
	if door.repair_cap >= door.max_durability:
		_fail("Damage no longer lowers the repair ceiling; this test proves nothing.")
		return false
	var repaired: float = director.call("_door_weight", door)
	if not is_equal_approx(repaired, pristine):
		_fail(
			"A fully repaired door weighs %.3f against a pristine %.3f: " % [repaired, pristine]
			+ "old damage is still steering waves onto it."
		)
		return false

	arena.queue_free()
	await process_frame
	return true


## The weakest entrance is where the waves go. It is a bias rather than a rule -
## a full-strength door is rarer, never exempt - so this asserts the majority
## over many waves instead of demanding the same door every time.
func _test_weak_doors_are_hunted_first(packed_scene: PackedScene) -> bool:
	var arena := Node3D.new()
	root.add_child(arena)
	var doors: Array[DefenseDoor] = []
	for index: int in 4:
		var door := packed_scene.instantiate() as DefenseDoor
		door.entrance_id = index + 1
		arena.add_child(door)
		door.set_physics_process(false)
		door.get_node("WarningAudio").stream = null
		door.get_node("StrongAttackAudio").stream = null
		doors.append(door)
	# One entrance is nearly down; the other three are untouched.
	doors[2].take_damage(doors[2].max_durability * 0.9)

	var director := DoorAttackDirector.new()
	director.false_alarm_chance = 0.0
	arena.add_child(director)
	director.set_process(false)
	director.set_random_seed(7)

	await process_frame
	var weak_picks := 0
	const WAVES := 40
	for _wave: int in WAVES:
		var selected := director.start_attack_wave(1)
		if selected.size() != 1:
			_fail("A single-target wave did not select exactly one door.")
			return false
		if selected[0] == doors[2]:
			weak_picks += 1
		for door: DefenseDoor in doors:
			door.drive_ghost_away()
	# An unbiased draw would take the damaged door a quarter of the time.
	if weak_picks <= WAVES / 2:
		_fail("The damaged entrance was picked %d/%d times, no better than at random." % [
			weak_picks,
			WAVES,
		])
		return false

	arena.queue_free()
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

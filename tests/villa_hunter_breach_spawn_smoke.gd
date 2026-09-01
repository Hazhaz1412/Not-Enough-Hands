extends SceneTree

## The villa owns exactly two hunters. The authored first hunter can answer a
## breach immediately; the only reinforcement cannot enter before 180 in-game
## minutes, even if several entrances have already been destroyed.

const VILLA_SCENE := preload("res://house3/villa_main.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := VILLA_SCENE.instantiate()
	root.add_child(game)
	var director := game.get_node_or_null("DoorAttackDirector")
	if director:
		director.set("automatic_waves", false)
	var clock := game.get_node_or_null("NightClock") as NightClock
	if not clock:
		_fail("Villa is missing its NightClock.")
		return
	clock.real_seconds_per_game_minute = 9999.0
	var first := game.get_node_or_null("HunterGhost") as CharacterBody3D
	if not first or not bool(first.get("entry_enabled")):
		_fail("The villa's first HunterGhost is not enabled for breach entry.")
		return
	first.set("entry_delay_min", 0.05)
	first.set("entry_delay_max", 0.05)

	if not await _wait_for_navigation(game):
		_fail("Villa navigation did not become ready.")
		return

	if int(game.get("MAX_HUNTERS")) != 2 \
		or int(game.get("SECOND_HUNTER_UNLOCK_MINUTES")) != 180:
		_fail("Villa hunter count or three-hour unlock contract changed.")
		return
	var doors := get_nodes_in_group("defense_doors")
	if doors.size() < 3:
		_fail("Villa needs at least three exterior defense doors for this test.")
		return
	if int(game.call("live_hunter_count")) != 1:
		_fail("Villa did not start with exactly one hunter.")
		return

	# The attic skylight, deliberately: it is the one entrance whose two sides
	# are stacked vertically rather than laid across a threshold, and it is also
	# the weakest door in the spec, so it is the entrance a night usually opens
	# first. Entering it used to leave the huntsman standing on the roof.
	var overhead := _overhead_door(doors)
	if overhead == null:
		_fail("Villa has no overhead entrance to test the skylight breach with.")
		return
	var roof_height := overhead.global_position.y
	overhead.call("take_damage", 10000.0, true)
	if not await _wait_until_inside(first, 180):
		_fail("The first hunter did not enter through the initial breach.")
		return
	if not await _stays_in_the_house(first, roof_height, 420):
		return

	# An early second breach is remembered, but must not spawn a reinforcement.
	# Chosen by condition, never by index: the overhead entrance above is found
	# by geometry and can sit at any index, and take_damage() on an already
	# breached door is a no-op - so an aliased index would let this pass without
	# a second breach ever happening.
	var second_breach := _intact_door(doors)
	if second_breach == null:
		_fail("Villa ran out of standing entrances before the second breach.")
		return
	second_breach.call("take_damage", 10000.0, true)
	if float(second_breach.get("current_durability")) > 0.0:
		_fail("The second entrance did not actually breach.")
		return
	for _attempt: int in 20:
		await physics_frame
	if int(game.call("live_hunter_count")) != 1:
		_fail("The second hunter entered before three in-game hours elapsed.")
		return

	var until_last_minute := 179 - clock.elapsed_game_minutes
	if until_last_minute > 0:
		clock.skip_minutes(until_last_minute)
	await process_frame
	if int(game.call("live_hunter_count")) != 1:
		_fail("The second hunter entered at minute 179 instead of after minute 180.")
		return
	clock.skip_minutes(1)
	var second := await _wait_for_second_hunter()
	if not second:
		_fail("The second hunter did not enter after three in-game hours.")
		return
	if not bool(second.get("inside_house")) or not bool(second.get("manifested")):
		_fail("The delayed second hunter spawned without entering the breached doorway.")
		return

	# Further destroyed entrances never create a third body.
	var third_breach := _intact_door(doors)
	if third_breach == null:
		_fail("Villa ran out of standing entrances before the third breach.")
		return
	third_breach.call("take_damage", 10000.0, true)
	if float(third_breach.get("current_durability")) > 0.0:
		_fail("The third entrance did not actually breach.")
		return
	for _attempt: int in 30:
		await physics_frame
	if int(game.call("live_hunter_count")) != 2:
		_fail("A third hunter appeared after another villa entrance was breached.")
		return

	game.queue_free()
	await process_frame
	print("Villa hunter breach spawn smoke test passed: exactly two, second unlocked at 180 minutes.")
	quit()


func _wait_for_navigation(game: Node) -> bool:
	for _attempt: int in 600:
		if bool(game.get("navigation_is_ready")):
			return true
		await physics_frame
	return false


## The first entrance still standing, so each breach in this test is a real one.
func _intact_door(doors: Array) -> Node3D:
	for node: Node in doors:
		var door := node as Node3D
		if door and float(door.get("current_durability")) > 0.0:
			return door
	return null


## The entrance whose sides are stacked vertically instead of across a
## threshold. Found from the geometry rather than by entrance_id, so it keeps
## holding if the spec ever moves the skylight.
func _overhead_door(doors: Array) -> Node3D:
	for node: Node in doors:
		var door := node as Node3D
		if door and absf(door.global_basis.z.normalized().y) > 0.9:
			return door
	return null


## Entering is not the whole contract: the huntsman has to still be there, still
## wearing its body, and actually below the opening it came through, for long
## enough to matter. Standing on the roof reads as "the hunter vanished" to
## every player in the building, and nothing about its own state says so.
func _stays_in_the_house(
	hunter: CharacterBody3D,
	roof_height: float,
	attempts: int
) -> bool:
	var landed := hunter.global_position
	var travelled := 0.0
	for _attempt: int in attempts:
		await physics_frame
		if not is_instance_valid(hunter):
			_fail("The huntsman was freed after entering through the breach.")
			return false
		if not hunter.is_inside_tree():
			_fail("The huntsman was removed from the tree after entering.")
			return false
		if not bool(hunter.get("manifested")):
			_fail("The huntsman un-manifested after entering through the breach.")
			return false
		var rig := hunter.get_node_or_null("VisualRoot") as Node3D
		if rig == null or not rig.visible:
			_fail("The huntsman lost its body after entering through the breach.")
			return false
		travelled = maxf(travelled, landed.distance_to(hunter.global_position))
	# Still simulating, not just still present: a body that entered and then
	# stopped being stepped at all would satisfy every check above.
	if travelled < 1.0:
		_fail(
			"The huntsman never moved more than %.2f m from where it entered; "
			% travelled
			+ "it is present but no longer hunting."
		)
		return false
	if hunter.global_position.y >= roof_height:
		_fail(
			"The huntsman is at y=%.2f, at or above the %.2f m opening it came through: "
			% [hunter.global_position.y, roof_height]
			+ "it is on the roof rather than in the house."
		)
		return false
	return true


func _wait_until_inside(hunter: CharacterBody3D, attempts: int) -> bool:
	for _attempt: int in attempts:
		await physics_frame
		if is_instance_valid(hunter) and bool(hunter.get("inside_house")):
			return true
	return false


func _wait_for_second_hunter() -> CharacterBody3D:
	for _attempt: int in 60:
		await physics_frame
		for node: Node in get_nodes_in_group("hunter_ghosts"):
			if node.name.begins_with("BreachHunter"):
				return node as CharacterBody3D
	return null


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

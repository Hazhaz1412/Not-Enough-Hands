extends SceneTree


const LOCKED := 5
const TEST_SECONDS := 16.0
const REQUIRED_DISTANCE := 1.8
const SECOND_FLOOR_MIN_Y := 2.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if not packed:
		_fail("Main scene could not be loaded for the Door 05 route test.")
		return

	var game := packed.instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame

	var hunter := game.get_node("HunterGhost") as CharacterBody3D
	var player := game.get_node("Player") as CharacterBody3D
	var navigation_region := game.get_node("HouseNavigationRegion") as NavigationRegion3D
	var map_rid := navigation_region.get_navigation_map()
	var sync_deadline := Time.get_ticks_msec() + 5000
	while NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		if Time.get_ticks_msec() > sync_deadline:
			_fail("Navigation map did not sync for the Door 05 route test.")
			return
		await physics_frame

	(game.get_node("DoorAttackDirector") as Node).set("automatic_waves", false)
	(game.get_node("StatueGhost") as Node).set_physics_process(false)
	(game.get_node("CrawlerGhost") as Node).set_physics_process(false)
	player.set_physics_process(false)
	for node_name: String in [
		"FootstepAudio", "HookAudio", "BreathAudio", "SniffAudio",
		"HornAudio", "SeizeAudio", "BreachAudio",
	]:
		var audio := hunter.get_node_or_null(node_name) as AudioStreamPlayer3D
		if audio:
			audio.stream = null

	# Reproduce a live chase from the upstairs landing into the east bedroom,
	# whose outside entrance is defense Door 05. The correct route turns into
	# the bedroom on this floor and never touches the ground-floor staircase.
	var start := Vector3(1.65, 3.05, 4.24)
	var target := Vector3(7.4, 3.9, -3.0)
	player.global_position = target
	hunter.global_position = start
	hunter.set("entry_enabled", false)
	hunter.call("dev_force_spawn", null)
	hunter.global_position = start
	# The player began downstairs before slipping into Door 05's room, so the
	# dormant hunter already has a ground-floor mark under this landing. Its close
	# nose must not treat that mark as if it were on the same floor.
	if hunter.call("has_trail_lead"):
		_fail("Hunter can still read ground-floor spoor through the second-floor landing.")
		return
	hunter.set("lose_sight_time", TEST_SECONDS + 2.0)
	hunter.call("set_dev_attack_suspended", true)
	hunter.set("current_target", player)
	hunter.set("last_seen_position", target)
	hunter.call("_set_state", LOCKED)
	# The chase is held open for the whole run. Letting the sight timer lapse
	# would hand it to the fair-play disengage, which deliberately walks it away
	# from the room - correct behaviour, and the opposite of what this test is
	# about, which is purely whether it routes into Door 05's room without
	# detouring down the stairs.
	hunter.set("_sight_timer", TEST_SECONDS + 2.0)

	var nav_agent := hunter.get_node("NavigationAgent3D") as NavigationAgent3D
	var first_agent_path := PackedVector3Array()
	var closest := hunter.global_position.distance_to(target)
	var minimum_y := hunter.global_position.y
	var elapsed := 0.0
	while elapsed < TEST_SECONDS:
		await create_timer(0.1).timeout
		elapsed += 0.1
		if first_agent_path.is_empty() and nav_agent.get_current_navigation_path().size() > 1:
			first_agent_path = nav_agent.get_current_navigation_path()
		closest = minf(closest, hunter.global_position.distance_to(target))
		minimum_y = minf(minimum_y, hunter.global_position.y)
		if closest <= REQUIRED_DISTANCE:
			break

	if minimum_y < SECOND_FLOOR_MIN_Y:
		_fail(
			"Hunter detoured downstairs while chasing into Door 05's room: minimum y %.2f, end %s."
			% [minimum_y, hunter.global_position]
			+ " Initial agent path: %s." % first_agent_path
		)
		return
	if closest > REQUIRED_DISTANCE:
		_fail(
			"Hunter did not enter Door 05's room directly: end=%s closest=%.2f."
			% [hunter.global_position, closest]
		)
		return

	var end := hunter.global_position
	game.queue_free()
	await process_frame
	print(
		"Hunter Door 05 route smoke test passed: %s to %s, min y %.2f, closest %.2f."
		% [start, end, minimum_y, closest]
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

extends SceneTree


const LOCKED := 5
const TEST_SECONDS := 10.0
const REQUIRED_DISTANCE := 1.55


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if not packed:
		_fail("Main scene could not be loaded for the upper-landing test.")
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
			_fail("Navigation map did not sync for the upper-landing test.")
			return
		await physics_frame
	var sync_probe := NavigationServer3D.map_get_closest_point(
		map_rid,
		Vector3(2.35, 3.1, 3.25)
	)
	while sync_probe.distance_to(Vector3.ZERO) < 0.01:
		if Time.get_ticks_msec() > sync_deadline:
			_fail("Navigation floor never became queryable for the upper-landing test.")
			return
		await physics_frame
		sync_probe = NavigationServer3D.map_get_closest_point(
			map_rid,
			Vector3(2.35, 3.1, 3.25)
		)
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

	# This is the turn shown in the reported screenshot: the hunter has just
	# reached the stair head and must pass between the east rail and hall console
	# to reach a player inside the second-floor hall.
	player.global_position = Vector3(2.35, 3.9, 3.25)
	hunter.global_position = Vector3(0.0, 3.2, 4.6)
	hunter.set("entry_enabled", false)
	hunter.call("dev_force_spawn", null)
	hunter.global_position = Vector3(0.0, 3.2, 4.6)
	hunter.set("sight_range", 20.0)
	hunter.set("lose_sight_time", TEST_SECONDS + 2.0)
	hunter.call("set_dev_attack_suspended", true)
	hunter.set("current_target", player)
	hunter.set("last_seen_position", player.global_position)
	hunter.call("_set_state", LOCKED)
	await physics_frame
	var nav_agent := hunter.get_node("NavigationAgent3D") as NavigationAgent3D
	var nav_start := NavigationServer3D.map_get_closest_point(map_rid, hunter.global_position)
	var nav_end := NavigationServer3D.map_get_closest_point(map_rid, player.global_position)
	var landing_path := NavigationServer3D.map_get_path(map_rid, nav_start, nav_end, true)
	if landing_path.size() < 2 or landing_path[landing_path.size() - 1].distance_to(nav_end) > 0.6:
		var link_details: Array[String] = []
		for node: Node in get_nodes_in_group("smooth_stair_landing_links"):
			var landing_link := node as NavigationLink3D
			link_details.append(
				"%s %s -> %s enabled=%s" % [
					landing_link.name,
					landing_link.start_position,
					landing_link.end_position,
					landing_link.enabled,
				]
			)
		_fail(
			"The upper stair landing is still disconnected: start=%s->%s end=%s->%s path=%s links=%s"
			% [hunter.global_position, nav_start, player.global_position, nav_end, landing_path, link_details]
		)
		return

	var start := hunter.global_position
	var closest := hunter.global_position.distance_to(player.global_position)
	var elapsed := 0.0
	while elapsed < TEST_SECONDS:
		await create_timer(0.1).timeout
		elapsed += 0.1
		closest = minf(closest, hunter.global_position.distance_to(player.global_position))
		if closest <= REQUIRED_DISTANCE and hunter.global_position.x > 1.15:
			break

	if closest > REQUIRED_DISTANCE or hunter.global_position.x <= 1.15:
		_fail(
			"Hunter remained wedged at the second-floor landing: start=%s end=%s closest=%.2f."
			% [start, hunter.global_position, closest]
		)
		return

	var end := hunter.global_position
	game.queue_free()
	await process_frame
	print(
		"Hunter upper-landing smoke test passed: turned past the console from %s to %s (%.2f m from target)."
		% [start, end, closest]
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

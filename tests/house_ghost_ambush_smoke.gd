extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load('res://main.tscn') as PackedScene
	var main_scene := packed_scene.instantiate()
	root.add_child(main_scene)

	var player := main_scene.get_node('Player') as CharacterBody3D
	var statue := main_scene.get_node('StatueGhost') as CharacterBody3D
	var region := main_scene.get_node('HouseNavigationRegion') as NavigationRegion3D
	var map_rid := region.get_navigation_map()
	player.set_physics_process(false)
	player.velocity = Vector3(1.0, 0.0, 0.0)
	# The statue only moves unobserved. A zero observation cone is this
	# fixture's way of saying "nobody is watching it", now that a blink is no
	# longer a thing a player can be forced into.
	statue.set('observation_half_angle', 0.0)
	# This legacy compact-house fixture cannot supply the production 15 m
	# safety radius. Keep it focused on navmesh/route validity; the default
	# distance contract is covered by statue_hunt_cycle_smoke.gd.
	statue.set('ambush_min_distance', 6.0)
	statue.set('ambush_max_distance', 10.0)
	statue.set('hidden_timer', 100.0)
	statue.set('hunt_activation_chance', 1.0)

	var sync_deadline_msec := Time.get_ticks_msec() + 5000
	while NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		if Time.get_ticks_msec() > sync_deadline_msec:
			_fail('House navigation did not sync before the ambush test.')
			return
		await physics_frame
	var player_nav := NavigationServer3D.map_get_closest_point(map_rid, player.global_position)
	while player_nav.distance_to(Vector3.ZERO) < 0.01:
		if Time.get_ticks_msec() > sync_deadline_msec:
			_fail('Player position never became available on the house navmesh.')
			return
		await physics_frame
		player_nav = NavigationServer3D.map_get_closest_point(map_rid, player.global_position)

	var hunt_result := {}
	statue.hunt_started.connect(func(target: Node3D, position: Vector3) -> void:
		hunt_result['target'] = target
		hunt_result['position'] = position
	)
	statue.set('hidden_timer', 0.0)
	var hunt_deadline_msec := Time.get_ticks_msec() + 1500
	while hunt_result.is_empty() and Time.get_ticks_msec() <= hunt_deadline_msec:
		await physics_frame

	if hunt_result.is_empty():
		_fail('Statue could not find a hidden navmesh ambush point in the house.')
		return
	var ambush_position: Vector3 = hunt_result['position']
	var ambush_nav := NavigationServer3D.map_get_closest_point(map_rid, ambush_position)
	if ambush_nav.distance_to(ambush_position) > 0.15:
		_fail('House ambush was not placed on the navigation surface: %s.' % ambush_position)
		return
	var flat_distance := Vector2(
		ambush_position.x - player_nav.x,
		ambush_position.z - player_nav.z
	).length()
	if flat_distance < float(statue.get('ambush_min_distance')) - 0.1 \
		or flat_distance > float(statue.get('ambush_max_distance')) + 0.1:
		_fail('House ambush distance %.2f was outside the configured range.' % flat_distance)
		return
	var route := NavigationServer3D.map_get_path(map_rid, ambush_nav, player_nav, true)
	if route.is_empty() or route[route.size() - 1].distance_to(player_nav) > 0.75:
		_fail('House ambush had no valid route back to its selected target.')
		return

	statue.get_node('TeleportAudio').stop()
	statue.get_node('AttackAudio').stop()
	statue.get_node('TeleportAudio').stream = null
	statue.get_node('AttackAudio').stream = null
	main_scene.queue_free()
	await process_frame
	print('House ghost ambush smoke test passed: hidden, same-floor navmesh teleport at %.2f m.' % flat_distance)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

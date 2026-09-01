extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://main.tscn") as PackedScene
	var main_scene := packed_scene.instantiate()
	root.add_child(main_scene)

	var player := main_scene.get_node("Player") as CharacterBody3D
	var statue := main_scene.get_node("StatueGhost") as CharacterBody3D
	var region := main_scene.get_node("HouseNavigationRegion") as NavigationRegion3D
	var map_rid := region.get_navigation_map()

	# The statue only moves unobserved; a zero observation cone is how this
	# fixture keeps it moving now that a forced blink no longer exists.
	statue.set("observation_half_angle", 0.0)
	statue.set("intermittent_hunts_enabled", false)
	# Put the target just inside the upper landing and the statue at the foot
	# of the ground-floor staircase. Character origins differ: the player's
	# capsule is centred on its origin while the statue's origin is at its feet.
	player.global_position = Vector3(0.0, 3.98, 4.6)
	statue.global_position = Vector3(0.0, 0.1, -1.0)
	statue.set("unseen_grace_time", 0.0)
	statue.set("attack_range", 0.1)

	var sync_deadline_msec := Time.get_ticks_msec() + 5000
	while NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		if Time.get_ticks_msec() > sync_deadline_msec:
			_fail("Navigation map did not sync before the stair chase.")
			return
		await physics_frame

	var upper_target := NavigationServer3D.map_get_closest_point(map_rid, player.global_position)
	while upper_target.distance_to(Vector3.ZERO) < 0.01:
		if Time.get_ticks_msec() > sync_deadline_msec:
			_fail("Upper landing was not registered in the navigation map.")
			return
		await physics_frame
		upper_target = NavigationServer3D.map_get_closest_point(map_rid, player.global_position)

	var start_y := statue.global_position.y
	var highest_y := start_y
	var chase_deadline_msec := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() <= chase_deadline_msec:
		await physics_frame
		highest_y = maxf(highest_y, statue.global_position.y)
		if statue.global_position.y >= 2.15:
			print(
				"House stair chase smoke test passed: statue climbed %.2f m to the upper floor."
				% (statue.global_position.y - start_y)
			)
			quit()
			return

	var nav_agent := statue.get_node("NavigationAgent3D") as NavigationAgent3D
	var blocking_colliders: Array[String] = []
	for collision_index: int in statue.get_slide_collision_count():
		var hit := statue.get_slide_collision(collision_index)
		var collider := hit.get_collider() as Node
		blocking_colliders.append(
			"%s normal=%s" % [collider.name if collider else "unknown", hit.get_normal()]
		)
	_fail(
		(
			"Statue never reached the upper floor during a valid stair chase "
			+ "(highest y=%.2f, started y=%.2f, final=%s, next=%s, path=%s, colliders=%s)."
		)
		% [highest_y, start_y, statue.global_position, nav_agent.get_next_path_position(), nav_agent.get_current_navigation_path(), blocking_colliders]
	)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

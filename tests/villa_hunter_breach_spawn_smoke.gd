extends SceneTree

## Each destroyed villa defense door creates one additional active hunter at
## that breach, up to `MAX_BREACH_HUNTERS` and no further. The scene's dormant
## HunterGhost is retained for DevTools but must not turn the first breach into
## two hunters.

const VILLA_SCENE := preload("res://house3/villa_main.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := VILLA_SCENE.instantiate()
	root.add_child(game)
	if not await _wait_for_navigation(game):
		_fail("Villa navigation did not become ready.")
		return

	var director := game.get_node_or_null("DoorAttackDirector")
	if director:
		director.set("automatic_waves", false)
	var template := game.get_node_or_null("HunterGhost") as CharacterBody3D
	if not template or bool(template.get("entry_enabled")):
		_fail("The villa's dormant HunterGhost template can still enter on a breach.")
		return

	var cap := int(game.get("MAX_BREACH_HUNTERS"))
	var doors := get_nodes_in_group("defense_doors")
	if doors.size() < cap + 1:
		_fail("Villa needs more exterior defense doors than the hunter cap for this test.")
		return
	var initial_hunters := get_nodes_in_group("hunter_ghosts").size()
	for index: int in range(cap):
		if not await _breach_and_expect_one(doors[index] as Node, initial_hunters + index):
			return

	# The cap is the point: the villa has seven entrances and a huntsman never
	# leaves, so without it every door the player loses is another body in the
	# building for the rest of the night.
	var at_cap := get_nodes_in_group("hunter_ghosts").size()
	(doors[cap] as Node).call("take_damage", 10000.0, true)
	for _attempt: int in 30:
		await physics_frame
	if get_nodes_in_group("hunter_ghosts").size() != at_cap:
		_fail(
			"Breaching a %dth door spawned a huntsman past the cap of %d."
			% [cap + 1, cap]
		)
		return
	if int(game.call("live_breach_hunter_count")) != cap:
		_fail("Villa is not tracking exactly %d live breach huntsmen." % cap)
		return

	game.queue_free()
	await process_frame
	print("Villa hunter breach spawn smoke test passed: %d hunters, capped at %d." % [cap, cap])
	quit()


func _wait_for_navigation(game: Node) -> bool:
	for _attempt: int in 600:
		if bool(game.get("navigation_is_ready")):
			return true
		await physics_frame
	return false


func _breach_and_expect_one(door: Node, expected_before: int) -> bool:
	if not door or not door.has_method("take_damage"):
		_fail("Selected villa entrance cannot be breached.")
		return false
	door.call("take_damage", 10000.0, true)
	for _attempt: int in 20:
		await physics_frame
		var hunters := get_nodes_in_group("hunter_ghosts")
		if hunters.size() != expected_before + 1:
			continue
		for node: Node in hunters:
			if node.name.begins_with("BreachHunter"):
				var hunter := node as CharacterBody3D
				if hunter and bool(hunter.get("inside_house")) and bool(hunter.get("manifested")):
					return true
	_fail("Breaching %s did not add one active huntsman inside the villa." % door.name)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

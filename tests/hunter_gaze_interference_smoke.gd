extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player_scene := load("res://player/player.tscn") as PackedScene
	if not player_scene:
		return _fail("Player scene could not be loaded.")
	var player := player_scene.instantiate() as CharacterBody3D
	world.add_child(player)
	player.set_physics_process(false)

	# A lightweight stand-in is enough here: gaze sensing is deliberately based
	# on the public hunter_ghosts group so it also works for replicated breach
	# hunters without coupling the player to the Hunter AI script.
	var hunter := Node3D.new()
	hunter.name = "GazeTestHunter"
	hunter.add_to_group(&"hunter_ghosts")
	hunter.position = Vector3(0.0, -0.43, -3.0)
	world.add_child(hunter)
	await physics_frame

	var direct := float(player.call("_hunter_gaze_target_strength"))
	if direct < 0.95:
		return _fail("A centred, unobstructed Hunter produced only %.3f interference." % direct)

	player.rotation.y = PI * 0.5
	var turned_away := float(player.call("_hunter_gaze_target_strength"))
	if turned_away > 0.001:
		return _fail("The interference remained active after the camera turned away.")
	player.rotation.y = 0.0

	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector3(0.0, 0.62, -1.5)
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	world.add_child(wall)
	await physics_frame

	var through_wall := float(player.call("_hunter_gaze_target_strength"))
	var wall_cap := float(player.get("hunter_gaze_through_wall_strength"))
	if through_wall <= 0.02 or through_wall > wall_cap + 0.001:
		return _fail(
			"A close Hunter behind one wall should leak a light signal; got %.3f (cap %.3f)."
			% [through_wall, wall_cap]
		)
	player.rotation.y = PI
	var wall_behind := float(player.call("_hunter_gaze_target_strength"))
	if not is_equal_approx(wall_behind, through_wall):
		return _fail("Close through-wall leakage incorrectly required aiming at the Hunter.")
	player.rotation.y = 0.0

	hunter.position.z = -6.0
	var far_through_wall := float(player.call("_hunter_gaze_target_strength"))
	if far_through_wall > 0.001:
		return _fail("Wall leakage continued past its short %.1f m range." % player.hunter_gaze_through_wall_range)

	hunter.position.z = -3.0
	player.call("_update_hunter_gaze_interference", 0.1)
	var overlay := player.get_node("HorrorOverlay/VignetteAndGrain") as ColorRect
	var material := overlay.material as ShaderMaterial
	var shader_strength := float(material.get_shader_parameter("hunter_gaze_strength"))
	if shader_strength <= 0.0 or not is_equal_approx(shader_strength, player.hunter_gaze_strength):
		return _fail("Player gaze strength did not reach the post-process shader.")

	print((
		"Hunter gaze interference smoke test passed: direct %.2f, through-wall %.2f, "
		+ "turn-away and distance cutoff clear."
	) % [direct, through_wall])
	quit()


func _fail(message: String) -> void:
	push_error("Hunter gaze interference smoke test failed: " + message)
	print("Hunter gaze interference smoke test FAILED: " + message)
	quit(1)

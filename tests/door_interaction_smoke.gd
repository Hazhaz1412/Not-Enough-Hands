extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://tests/player_test.tscn") as PackedScene
	var test_scene := packed_scene.instantiate()
	root.add_child(test_scene)

	var player := test_scene.get_node("Player") as CharacterBody3D
	var door := test_scene.get_node("TestDoor") as Node3D
	player.global_position = Vector3(0.7, 1.0, 2.0)
	player.global_rotation = Vector3.ZERO

	await physics_frame
	await physics_frame
	# Pressing closer to a normal interior door opens it proportionally, with
	# no interaction press. At z=0.5 it should be a partial swing; at z=0.2 it
	# reaches the configured full swing, then closes after the player steps out.
	var hinge := door.get_node("Hinge") as Node3D
	var open_angle := float(door.get("open_angle"))
	player.global_position = Vector3(0.7, 1.0, 0.5)
	door.call("_update_player_push", 1.0)
	if int(door.get("state")) != 4 or is_zero_approx(hinge.rotation.y) \
			or absf(hinge.rotation.y) >= deg_to_rad(open_angle):
		push_error("A near player did not produce a proportional partial door push.")
		quit(1)
		return
	player.global_position = Vector3(0.7, 1.0, 0.2)
	door.call("_update_player_push", 1.0)
	if not is_equal_approx(absf(hinge.rotation.y), deg_to_rad(open_angle)):
		push_error("Pressing directly against the door did not open it fully.")
		quit(1)
		return
	var pushed_sign := signf(hinge.rotation.y)
	player.global_position = Vector3(0.7, 1.0, -0.2)
	door.call("_update_player_push", 1.0)
	if signf(hinge.rotation.y) != pushed_sign:
		push_error("The door reversed through the player as they crossed its threshold.")
		quit(1)
		return
	player.global_position = Vector3(0.7, 1.0, 0.95)
	door.call("_update_player_push", 1.0)
	if not is_equal_approx(absf(hinge.rotation.y), deg_to_rad(open_angle)):
		push_error("The door lost its push angle while a slow player was still in the doorway.")
		quit(1)
		return
	player.global_position = Vector3(0.7, 1.0, -1.0)
	door.call("_update_player_push", 1.0)
	if not is_equal_approx(absf(hinge.rotation.y), deg_to_rad(open_angle)):
		push_error("The door started closing before the player had cleared the far side.")
		quit(1)
		return
	player.global_position = Vector3(0.7, 1.0, 2.0)
	door.call("_update_player_push", 1.0)
	if int(door.get("state")) != 0 or not is_zero_approx(hinge.rotation.y):
		push_error("A player leaving a pushed door did not let it settle closed.")
		quit(1)
		return

	var target: Node = player.call("get_interaction_target")
	if target != door:
		push_error("Interaction ray did not resolve the Door node.")
		quit(1)
		return

	player.call("_try_interact")
	if int(door.get("state")) != 1: # OPENING
		push_error("Door did not enter OPENING state after interaction.")
		quit(1)
		return

	print("Door interaction smoke test passed.")
	quit()

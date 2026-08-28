extends SceneTree

## Player-driven Interactable tests using tests/player_test.tscn's existing
## Player and TestInteractableObject (a generic double, not a light switch),
## so these prove the reusable contract itself rather than one object's
## behavior, entirely through the same player/raycast environment the other
## smoke tests already share - no dedicated test map. Covers: enabled
## toggling, lock enforcement, range boundary handling, and
## repeated-interaction-while-locked, all through the actual raycast +
## interact() path the game uses.

const HALF_DEPTH := 0.15 # half of test_interactable_object.tscn's BoxShape3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://tests/player_test.tscn") as PackedScene
	var test_scene := packed_scene.instantiate()
	root.add_child(test_scene)

	var player := test_scene.get_node("Player") as CharacterBody3D
	var object_a := test_scene.get_node("TestInteractableObject")

	# Offset from TestDoor (at the scene origin) so the raycast in this test
	# never crosses it while object_a is repositioned for the range checks.
	player.global_position = Vector3(3.0, 1.0, 2.0)
	player.global_rotation = Vector3.ZERO
	object_a.global_position = Vector3(3.0, 1.62, 0.5)

	var interactable_a: Node = object_a.get_node("Interactable")
	var interaction_range: float = interactable_a.interaction_range
	var ray: RayCast3D = player.get_node("CameraPivot/Camera3D/InteractRay")

	await physics_frame
	await physics_frame

	# 1. Disabled: target resolution still finds the component (that is not
	# what enabled gates), but the player cannot actually interact with it.
	interactable_a.enabled = false
	var target: Node = player.call("get_interaction_target")
	if target != interactable_a:
		push_error("Target resolution should not depend on enabled.")
		quit(1)
		return
	if bool(player.call("can_interact_with", target)):
		push_error("can_interact_with() should be false while Interactable.enabled is false.")
		quit(1)
		return
	player.call("_try_interact")
	if object_a.interaction_count != 0:
		push_error("A disabled Interactable fired interacted() through the player.")
		quit(1)
		return

	# 2. Restoring enabled = true restores interaction through the player.
	interactable_a.enabled = true
	player.call("_try_interact")
	if object_a.interaction_count != 1:
		push_error("Re-enabling Interactable did not restore player interaction.")
		quit(1)
		return

	# 3. Lock behavior: interacting locked the object (test double locks
	# itself, mirroring LightSwitch). While locked, the player cannot
	# interact with it, even though the raycast still resolves it.
	if bool(player.call("can_interact_with", interactable_a)):
		push_error("can_interact_with() should be false while locked.")
		quit(1)
		return
	player.call("_try_interact")
	if object_a.interaction_count != 1:
		push_error("A locked Interactable fired interacted() through the player.")
		quit(1)
		return

	# 4. Repeated E while locked never causes a second state change.
	player.call("_try_interact")
	player.call("_try_interact")
	if object_a.interaction_count != 1:
		push_error("Repeated E while locked caused an extra interaction.")
		quit(1)
		return

	# 5. Unlock restores interaction through the player; the next E changes state.
	interactable_a.unlock()
	player.call("_try_interact")
	if object_a.interaction_count != 2:
		push_error("unlock() did not restore player interaction on the next E.")
		quit(1)
		return
	interactable_a.unlock() # undo the self-lock from step 5's interact for the range tests below

	# 6. Range boundary. Position object_a purely in front of the ray origin
	# (matching its X/Z) at controlled distances from the ray's actual origin,
	# using the same distance-to-collision-point math can_interact_with() uses.
	var ray_origin: Vector3 = ray.global_position

	# Clearly inside range.
	_place_at_distance(object_a, ray_origin, interaction_range * 0.5)
	await physics_frame
	ray.force_raycast_update()
	var inside_target: Node = player.call("get_interaction_target")
	if not inside_target:
		push_error("Setup error: raycast did not hit a target clearly inside range.")
		quit(1)
		return
	if not bool(player.call("can_interact_with", inside_target)):
		push_error("A target clearly inside interaction_range was rejected.")
		quit(1)
		return

	# Just inside the boundary.
	_place_at_distance(object_a, ray_origin, interaction_range - 0.05)
	await physics_frame
	ray.force_raycast_update()
	var near_target: Node = player.call("get_interaction_target")
	if not near_target:
		push_error("Setup error: raycast did not hit a target just inside range.")
		quit(1)
		return
	if not bool(player.call("can_interact_with", near_target)):
		push_error("A target just inside interaction_range was rejected.")
		quit(1)
		return

	# Just outside the boundary.
	_place_at_distance(object_a, ray_origin, interaction_range + 0.05)
	await physics_frame
	ray.force_raycast_update()
	var boundary_target: Node = player.call("get_interaction_target")
	if not boundary_target:
		push_error("Setup error: raycast did not hit a target just outside range.")
		quit(1)
		return
	if bool(player.call("can_interact_with", boundary_target)):
		push_error("A target just outside interaction_range was accepted.")
		quit(1)
		return

	# Clearly outside range.
	_place_at_distance(object_a, ray_origin, interaction_range + 3.0)
	await physics_frame
	ray.force_raycast_update()
	var far_target: Node = player.call("get_interaction_target")
	if not far_target:
		push_error("Setup error: raycast did not hit a target clearly outside range.")
		quit(1)
		return
	if bool(player.call("can_interact_with", far_target)):
		push_error("A target clearly outside interaction_range was accepted.")
		quit(1)
		return

	print("Interactable player smoke test passed.")
	quit()


## Places `object` directly along the ray's forward (-Z) axis so its near
## face sits exactly `distance` away from `ray_origin` - the same distance
## can_interact_with() measures via the raycast's collision point.
func _place_at_distance(object: Node3D, ray_origin: Vector3, distance: float) -> void:
	object.global_position = Vector3(
		ray_origin.x,
		ray_origin.y,
		ray_origin.z - HALF_DEPTH - distance
	)

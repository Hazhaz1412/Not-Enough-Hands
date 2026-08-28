extends SceneTree

## Player-driven pickup/drop/equipment smoke test, running inside
## tests/player_test.tscn's existing Player + PickupItemA/B/C. Pickup goes
## through the real interaction pipeline (raycast -> get_interaction_target
## -> Interactable -> interact() -> try_pick_up_item), matching the other
## interactable smoke tests; drop/select-slot call the player's own methods
## directly since they aren't part of that raycast pipeline.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://tests/player_test.tscn") as PackedScene
	var test_scene := packed_scene.instantiate()
	root.add_child(test_scene)

	var player := test_scene.get_node("Player") as CharacterBody3D
	var item_a := test_scene.get_node("PickupItemA")
	var item_b := test_scene.get_node("PickupItemB")
	var item_c := test_scene.get_node("PickupItemC")
	var equipment: PlayerEquipment = player.equipment

	player.global_position = Vector3(6.0, 1.0, 2.0)
	player.global_rotation = Vector3.ZERO
	item_a.global_position = Vector3(6.0, 1.62, 0.5)

	await physics_frame
	await physics_frame

	# 1. Pickup through the existing raycast + E path.
	var target: Node = player.call("get_interaction_target")
	if target != item_a.get_node("Interactable"):
		push_error("Player did not target PickupItemA's Interactable.")
		quit(1)
		return
	player.call("_try_interact")
	if equipment.get_slot_item(0) != item_a:
		push_error("Picking up PickupItemA did not fill slot 0.")
		quit(1)
		return
	if item_a.visible:
		push_error("Picked-up item is still visible in the world.")
		quit(1)
		return
	if not item_a.get_node("CollisionShape3D").disabled:
		push_error("Picked-up item's collision was not disabled.")
		quit(1)
		return

	# 2. Full inventory: fill slot 1 with item_b, then item_c must be refused
	# without touching the existing slots.
	item_b.global_position = Vector3(6.0, 1.62, 0.5)
	await physics_frame
	player.call("_try_interact")
	if equipment.get_slot_item(1) != item_b:
		push_error("Picking up PickupItemB did not fill slot 1.")
		quit(1)
		return

	item_c.global_position = Vector3(6.0, 1.62, 0.5)
	await physics_frame
	player.call("_try_interact")
	if not item_c.visible:
		push_error("PickupItemC should remain in the world when inventory is full.")
		quit(1)
		return
	if equipment.get_slot_item(0) != item_a or equipment.get_slot_item(1) != item_b:
		push_error("Existing slots were overwritten while the inventory was full.")
		quit(1)
		return

	# 3. Slot selection.
	if equipment.selected_slot != 0:
		push_error("Equipment should default to slot 0 selected.")
		quit(1)
		return
	equipment.select_slot(1)
	if equipment.selected_slot != 1:
		push_error("select_slot(1) did not change the selected slot.")
		quit(1)
		return
	equipment.select_slot(0)
	if equipment.selected_slot != 0:
		push_error("select_slot(0) did not change the selected slot back.")
		quit(1)
		return

	# 4. Drop with Q (slot 0 holds item_a) - clears the slot and puts the item
	# back in the world, no longer parented under the player.
	player.call("_drop_selected_item")
	if equipment.get_slot_item(0) != null:
		push_error("Dropping did not clear the selected slot.")
		quit(1)
		return
	if not item_a.visible:
		push_error("Dropped item is not visible in the world.")
		quit(1)
		return
	if item_a.get_node("CollisionShape3D").disabled:
		push_error("Dropped item's collision was not re-enabled.")
		quit(1)
		return
	if item_a.get_parent() == player:
		push_error("Dropped item is still parented under the player.")
		quit(1)
		return
	if item_a.freeze:
		push_error("Dropped item is still frozen; it will not fall under gravity.")
		quit(1)
		return

	# 4b. Physics: a dropped item actually falls and settles on the floor
	# instead of being teleported there. Ground's top surface sits at y=0.0
	# (tests/player_test.tscn), so a 0.25m box should come to rest with its
	# center around y=0.125.
	var drop_height: float = item_a.global_position.y
	for i in 90:
		await physics_frame
	if item_a.global_position.y >= drop_height - 0.5:
		push_error("Dropped item did not fall - still near its drop height.")
		quit(1)
		return
	if item_a.global_position.y < 0.0 or item_a.global_position.y > 0.35:
		push_error("Dropped item did not settle on the floor (y=%f)." % item_a.global_position.y)
		quit(1)
		return
	if item_a.linear_velocity.length() > 0.1:
		push_error("Dropped item has not settled - still moving after falling.")
		quit(1)
		return

	# 5. Q on an already-empty slot does nothing.
	player.call("_drop_selected_item")
	if equipment.get_slot_item(0) != null:
		push_error("Dropping an empty slot should have no effect.")
		quit(1)
		return

	# 6. Re-pickup: the dropped item can be picked up again into an available slot.
	item_a.global_position = Vector3(6.0, 1.62, 1.0)
	await physics_frame
	await physics_frame
	player.call("_try_interact")
	if equipment.get_slot_item(0) != item_a:
		push_error("Dropped item could not be picked up again.")
		quit(1)
		return

	print("Pickup smoke test passed.")
	quit()

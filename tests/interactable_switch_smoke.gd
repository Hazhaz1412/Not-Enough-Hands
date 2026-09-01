extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_scene := load("res://player/player.tscn") as PackedScene
	var switch_scene := load("res://switches/light_switch.tscn") as PackedScene

	var player := player_scene.instantiate() as CharacterBody3D
	var switch_a := switch_scene.instantiate() as StaticBody3D
	var switch_b := switch_scene.instantiate() as StaticBody3D
	var power_manager := PowerManager.new()
	power_manager.enable_power_drain = false

	root.add_child(power_manager)
	root.add_child(player)
	root.add_child(switch_a)
	root.add_child(switch_b)

	player.global_position = Vector3(0.0, 1.0, 2.0)
	player.global_rotation = Vector3.ZERO
	# CameraPivot sits 0.62 above the player origin; align both switches with
	# that height so the forward raycast actually intersects their colliders.
	switch_a.global_position = Vector3(0.0, 1.62, 0.5)
	switch_b.global_position = Vector3(5.0, 1.62, 0.5)

	var interactable_a: Node = switch_a.get_node("Interactable")
	var light_a := switch_a.get_node("Light") as OmniLight3D
	var light_b := switch_b.get_node("Light") as OmniLight3D
	var device_a := switch_a.get_node(switch_a.get("controlled_device")) as ElectricalDevice
	var device_b := switch_b.get_node(switch_b.get("controlled_device")) as ElectricalDevice
	if device_a != light_a or device_b != light_b:
		push_error("Inspector device references do not point each switch to its own light.")
		quit(1)
		return

	await physics_frame
	await physics_frame

	# 1. The raycast resolves the Interactable component itself, not the
	# LightSwitch parent - the player never learns it is a "LightSwitch".
	var target: Node = player.call("get_interaction_target")
	if target != interactable_a:
		push_error("Interaction ray did not resolve SwitchA's Interactable component.")
		quit(1)
		return

	# 2. can_interact_with() respects interaction_range.
	player.global_position = Vector3(0.0, 1.0, 8.0)
	await physics_frame
	await physics_frame
	var far_target: Node = player.call("get_interaction_target")
	if not far_target or bool(player.call("can_interact_with", far_target)):
		push_error("can_interact_with() did not reject a target outside interaction_range.")
		quit(1)
		return

	player.global_position = Vector3(0.0, 1.0, 2.0)
	await physics_frame
	await physics_frame

	# 3. Pressing E triggers only the targeted interactable.
	var initial_state: bool = light_a.visible
	player.call("_try_interact")
	if light_a.visible == initial_state:
		push_error("Interacting with SwitchA did not toggle its light.")
		quit(1)
		return
	if not light_b.visible:
		push_error("Interacting with SwitchA affected SwitchB, which the raycast never targeted.")
		quit(1)
		return

	# 4. The lock is enforced by the component itself, even if interact() is
	# called directly, bypassing the player entirely.
	if bool(interactable_a.call("can_interact")):
		push_error("Interactable did not lock itself after interacting.")
		quit(1)
		return
	var locked_state: bool = light_a.visible
	interactable_a.call("interact", player)
	if light_a.visible != locked_state:
		push_error("A locked Interactable emitted interacted() when called directly.")
		quit(1)
		return

	# 5. Repeated E during the lock window does not cause a second toggle.
	player.call("_try_interact")
	if light_a.visible != locked_state:
		push_error("Repeated E during the lock window caused a second toggle.")
		quit(1)
		return

	# 6. Unlock restores interaction.
	interactable_a.call("unlock")
	if not bool(interactable_a.call("can_interact")):
		push_error("unlock() did not restore can_interact().")
		quit(1)
		return
	player.call("_try_interact")
	if light_a.visible == locked_state:
		push_error("Interaction did not work again after unlock().")
		quit(1)
		return

	print("Interactable switch smoke test passed.")
	quit()

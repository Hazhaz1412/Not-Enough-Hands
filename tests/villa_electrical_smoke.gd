extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var house := (load("res://house3/villa_house.tscn") as PackedScene).instantiate() as VillaHouse
	house.build_furniture = false
	var manager := PowerManager.new()
	house.add_child(manager)
	root.add_child(house)
	await process_frame
	await process_frame

	if manager.get_house_light_count() != 56:
		_fail("Expected 56 generated Villa lights, found %d." % manager.get_house_light_count())
		return
	if manager.devices.size() != 56:
		_fail("Expected 56 registered Villa light devices, found %d." % manager.devices.size())
		return
	var device_ids: Dictionary = {}
	for node: Node in manager.devices:
		var device := node as ElectricalDevice
		if not device or device.device_id.is_empty() or device_ids.has(device.device_id):
			_fail("Villa light devices must have non-empty, unique stable IDs.")
			return
		device_ids[device.device_id] = true

	var living_device := manager.get_device_by_id(&"R_LIVING")
	if not living_device or not living_device.powered_light:
		_fail("Stable device ID R_LIVING did not resolve to its generated light.")
		return

	var switch := (load("res://switches/imported_light_switch.tscn") as PackedScene).instantiate() as StaticBody3D
	switch.controlled_device_id = &"R_LIVING"
	house.add_child(switch)
	await process_frame
	var interactable := switch.get_node_or_null("Interactable") as Interactable
	interactable.interact(null)
	if living_device.is_on or living_device.powered_light.visible:
		_fail("ID-linked Villa switch did not turn off R_LIVING.")
		return
	if not is_equal_approx(manager.get_total_load(), 55.0 * manager.default_light_consumption):
		_fail("Villa total load did not update after switching one room off.")
		return

	print("Villa electrical smoke test passed: 56 generated devices and stable ID link.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

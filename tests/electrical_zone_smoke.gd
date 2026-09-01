extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var test_root := Node3D.new()
	root.add_child(test_root)

	var manager := PowerManager.new()
	manager.enable_power_drain = false
	manager.auto_register_house_lights = false
	test_root.add_child(manager)

	var light_a := _create_light(test_root, &"A")
	var light_b := _create_light(test_root, &"B")

	var zones := (load("res://power/electrical_zone_controller.gd") as Script).new() as Node
	test_root.add_child(zones)
	var zone_a := ElectricalZone.new()
	zone_a.zone_id = &"ZONE_A"
	zone_a.device_ids = PackedStringArray(["A"])
	zones.add_child(zone_a)
	var zone_b := ElectricalZone.new()
	zone_b.zone_id = &"ZONE_B"
	zone_b.device_ids = PackedStringArray(["B"])
	zones.add_child(zone_b)

	await process_frame
	await process_frame
	_assert(manager.devices.size() == 2, "Both zone devices must register")

	zone_a.set_powered(false)
	await process_frame
	_assert(not light_a.visible, "Zone A outage did not switch off light A")
	_assert(light_b.visible, "Zone A outage incorrectly switched off light B")
	_assert(is_equal_approx(manager.get_total_load(), 60.0), "Zone A outage did not update total load")

	manager.trigger_global_blackout()
	await process_frame
	_assert(not light_a.visible and not light_b.visible, "Global blackout did not switch off all zones")
	manager.restore_power()
	await process_frame
	_assert(not light_a.visible, "Restoring global power bypassed Zone A outage")
	_assert(light_b.visible, "Restoring global power did not restore powered Zone B")

	zone_a.set_powered(true)
	await process_frame
	_assert(light_a.visible and light_b.visible, "Restoring a zone did not restore only its fixture")
	_assert(is_equal_approx(manager.get_total_load(), 120.0), "Restored zones have incorrect total load")

	zone_a.set_powered(false)
	zone_b.set_powered(false)
	await process_frame
	_assert(manager.is_blackout, "All zones OFF must enter full-house blackout")
	zone_a.set_powered(true)
	await process_frame
	_assert(not manager.is_blackout, "Restoring one zone must leave the all-zones blackout")
	_assert(light_a.visible and not light_b.visible, "Only the restored zone should regain power")

	print("Electrical zone smoke test passed: independent zone outage and global blackout overlap.")
	test_root.queue_free()
	quit(0)


func _create_light(parent: Node3D, device_id: StringName) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = String(device_id) + "Light"
	parent.add_child(light)
	var device := ElectricalDevice.new()
	device.device_id = device_id
	device.power_consumption = 60.0
	device.powered_light = light
	light.add_child(device)
	return light


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

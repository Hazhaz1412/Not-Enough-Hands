extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var house_scene := load("res://house2/house2.tscn") as PackedScene
	var house := house_scene.instantiate() as Node3D
	root.add_child(house)
	await process_frame
	await process_frame

	var manager := house.get_node_or_null("PowerManager") as PowerManager
	if not manager or manager.get_house_light_count() != 10:
		_fail("House power manager did not collect all 10 House2 lights.")
		return

	var lights := get_nodes_in_group("flickering_house_lights")
	manager.set_random_seed(27)
	var regional_count := manager.trigger_random_regional_blackout(10.0)
	if regional_count <= 0 or regional_count >= lights.size():
		_fail("Regional blackout must affect some, but not all, house lights.")
		return
	var expected_regional_load := (lights.size() - regional_count) * manager.default_light_consumption
	if not is_equal_approx(manager.get_total_load(), expected_regional_load):
		_fail("Regional blackout did not remove its affected devices from total load.")
		return
	for light: Light3D in manager.get_regional_blackout_lights():
		if light.visible:
			_fail("A light in the regional blackout remained visible.")
			return

	manager.trigger_global_blackout()
	if not is_zero_approx(manager.get_total_load()):
		_fail("Global blackout did not reduce total device load to zero.")
		return
	for node: Node in lights:
		if (node as Light3D).visible:
			_fail("Global blackout did not turn off every house light.")
			return

	manager.restore_power()
	for light: Light3D in manager.get_regional_blackout_lights():
		if light.visible:
			_fail("Restoring global power incorrectly cleared the regional outage.")
			return

	manager.end_regional_blackout()
	for node: Node in lights:
		if not (node as Light3D).visible:
			var device := node.get_node_or_null("ElectricalDevice") as ElectricalDevice
			_fail(
				"Ending all outages left %s off (device_on=%s, forced=%s)." % [
					node.name,
					device.is_on if device else false,
					device.is_forced_off() if device else false,
				]
			)
			return

	print("House power smoke test passed: regional and global blackouts overlap and restore correctly.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

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

	zone_b.apply_network_state(false, true, PackedStringArray())
	var replicated_state := zone_b.get_network_state()
	_assert(replicated_state.size() == 5, "Electrical zone network state has the wrong shape")
	_assert(
		not bool(replicated_state[1]) and bool(replicated_state[2]),
		"Electrical zone did not retain the replicated outage/restore gate"
	)
	zone_b.apply_network_state(true, false, PackedStringArray())
	await process_frame
	_assert(light_b.visible, "Replicated zone restore did not restore its fixture")
	_assert(not zone_b.requires_switch_restore, "Replicated zone restore left the switch gate set")

	await _test_darkness_hunt_outage(test_root, zones)

	print("Electrical zone smoke test passed: outages, global overlap, network state apply, jammed fixtures and hunt-end restore.")
	test_root.queue_free()
	quit(0)


## The three halves of a darkness outage that are not plain zone power: a share
## of the fixtures come back jammed for the hunt, that share travels to clients
## instead of being re-rolled there, and the whole pocket comes back on when the
## hunt ends rather than waiting on 56 hand-flipped switches.
func _test_darkness_hunt_outage(test_root: Node3D, zones: Node) -> void:
	var hunt_zone := ElectricalZone.new()
	hunt_zone.zone_id = &"ZONE_HUNT"
	hunt_zone.device_ids = PackedStringArray(["H0", "H1", "H2", "H3"])
	zones.add_child(hunt_zone)
	var hunt_lights: Array[OmniLight3D] = []
	for index: int in 4:
		hunt_lights.append(_create_light(test_root, StringName("H%d" % index)))
	await process_frame
	await process_frame

	var effect := DarknessEntityPowerEffect.new()
	# The shipped villa neighbour graph would warn about every zone in this
	# fixture; the expansion graph is not what this test is about.
	effect.zone_neighbours = {
		&"ZONE_A": PackedStringArray(),
		&"ZONE_B": PackedStringArray(),
		&"ZONE_HUNT": PackedStringArray(),
	}
	test_root.add_child(effect)
	# lock_chance 1.0 is the worst roll there is; the zone still has to leave one
	# fixture restorable, or a player standing in the dark has nothing to try.
	_assert(effect.cause_zone_outage(hunt_zone, 1.0) == hunt_zone, "Darkness could not cut a powered zone")
	_assert(not hunt_zone.is_powered and hunt_zone.requires_switch_restore, "Cut zone did not enter switch-restore")
	var devices := hunt_zone.get_devices()
	var free_devices: Array[ElectricalDevice] = []
	for device: ElectricalDevice in devices:
		if not hunt_zone.is_device_restore_locked(device):
			free_devices.append(device)
	_assert(free_devices.size() == 1, "A fully jammed roll must still leave exactly one fixture restorable")
	for device: ElectricalDevice in devices:
		var restored := hunt_zone.restore_device_from_switch(device)
		_assert(
			restored == (device == free_devices[0]),
			"Switch restore ignored the fixture jam on %s" % device.device_id
		)
	await process_frame
	_assert(free_devices[0].powered_light.visible, "The one unjammed fixture did not come back on")

	# A client re-rolling its own jam list is what made a restored light snap
	# back off a fifth of a second later, so the list has to survive the wire.
	var replicated := hunt_zone.get_network_state()
	var mirror := ElectricalZone.new()
	mirror.zone_id = &"ZONE_HUNT_MIRROR"
	# Deliberately owns no devices: this stands in for the client's copy of the
	# zone, and binding the same fixtures twice would force them off under a
	# second reason that nothing in this test ever releases.
	zones.add_child(mirror)
	await process_frame
	mirror.apply_network_state(bool(replicated[1]), bool(replicated[2]), replicated[3], replicated[4])
	for device: ElectricalDevice in devices:
		_assert(
			mirror.is_device_restore_locked(device) == hunt_zone.is_device_restore_locked(device),
			"Replicated zone disagreed with the server about jammed fixture %s" % device.device_id
		)

	effect.clear_zone_outage()
	await process_frame
	_assert(hunt_zone.is_powered, "The end of a hunt did not restore the zone it darkened")
	_assert(not hunt_zone.requires_switch_restore, "Hunt-end restore left the switch gate set")
	for light: OmniLight3D in hunt_lights:
		_assert(light.visible, "Hunt-end restore left a fixture dark")


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

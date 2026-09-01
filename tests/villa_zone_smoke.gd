extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var villa_scene := load("res://house3/villa_main.tscn") as PackedScene
	_assert(villa_scene != null, "Could not load villa_main.tscn")
	var villa := villa_scene.instantiate() as Node3D
	root.add_child(villa)
	await process_frame
	await process_frame
	await process_frame

	var manager := villa.get_node_or_null("PowerManager") as PowerManager
	var zones := villa.get_node_or_null("ElectricalZones") as Node
	var dev_tools := villa.get_node_or_null("DevTools") as DevTools
	_assert(manager != null, "villa_main is missing PowerManager")
	_assert(zones != null and zones.get_child_count() == 13, "villa_main must define 13 electrical zones")
	_assert(dev_tools != null, "villa_main is missing DevTools")
	_assert(manager.get_house_light_count() == 56, "Expected 56 Villa room/junction lights")
	_assert(manager.devices.size() == 56, "Expected 56 registered Villa electrical devices")
	_assert(manager.enable_power_drain, "Villa PowerManager must consume total power")
	var initial_total_load := manager.get_total_load()
	_assert(initial_total_load > 0.0, "Powered Villa fixtures must contribute to total load")
	var fixtures := villa.get_node_or_null("VillaElectrical/RoomLights")
	var switches := villa.get_node_or_null("VillaElectrical/RoomSwitches")
	_assert(dev_tools.zone_controls.get_child_count() == 13, "DevTools must expose one control per electrical zone")
	var darkness_ghost := villa.get_node_or_null("DarknessGhost") as DarknessGhost
	_assert(darkness_ghost != null, "villa_main is missing DarknessGhost")
	_assert(not darkness_ghost.is_manifested(), "DarknessGhost must begin hidden")
	_assert(dev_tools.spawn_darkness_ghost(), "DevTools could not manifest DarknessGhost")
	await process_frame
	_assert(darkness_ghost.is_manifested(), "DarknessGhost did not enter its hunt state")
	_assert(darkness_ghost.get_node("AnimatedModel").visible, "DarknessGhost model did not become visible")
	dev_tools.ghost_box_picker.select(0)
	dev_tools.set_ghost_box_enabled(true)
	_assert(
		darkness_ghost.get_node_or_null("DevGhostCollisionBox") != null,
		"DevTools did not add a collision box marker to DarknessGhost"
	)
	dev_tools.set_ghost_box_enabled(false)
	var removed_marker := darkness_ghost.get_node_or_null("DevGhostCollisionBox")
	_assert(
		removed_marker == null or removed_marker.is_queued_for_deletion(),
		"DevTools did not remove the collision box marker"
	)
	_assert(dev_tools.teleport_to_selected_ghost(), "DevTools could not teleport to the selected ghost")
	var teleported_player := villa.get_node("Player") as Node3D
	var teleport_offset := teleported_player.global_position - darkness_ghost.global_position
	teleport_offset.y = 0.0
	_assert(
		is_equal_approx(teleport_offset.length(), 2.4),
		"DevTools teleported the player to an unsafe distance from the selected ghost"
	)
	_assert(
		Vector2(
			darkness_ghost.global_position.x - (villa.get_node("Player") as Node3D).global_position.x,
			darkness_ghost.global_position.z - (villa.get_node("Player") as Node3D).global_position.z,
		).length() <= 6.0,
		"DevTools must place DarknessGhost near the player"
	)
	var dark_zone := darkness_ghost.get_node("DarknessEntityPowerEffect") as DarknessEntityPowerEffect
	_assert(dark_zone.active_zone != null and not dark_zone.active_zone.is_powered, "DarknessGhost did not cut one zone")
	var first_dark_zone := dark_zone.active_zone
	var expected_next_zone_ids := dark_zone.zone_neighbours.get(first_dark_zone.zone_id, PackedStringArray()) as PackedStringArray
	var load_after_darkness := manager.get_total_load()
	_assert(load_after_darkness < initial_total_load, "DarknessGhost outage did not reduce whole-house load")
	darkness_ghost._process(darkness_ghost.zone_expansion_seconds + 1.0)
	_assert(darkness_ghost.is_manifested(), "DarknessGhost must persist until its dark zones are restored")
	_assert(dark_zone.darkened_zones.size() == 1, "Next zone must stay lit while DarknessGhost walks to it")
	_assert(
		darkness_ghost._pending_expansion_zone != null
		and darkness_ghost._pending_expansion_zone.zone_id == StringName(expected_next_zone_ids[0]),
		"DarknessGhost did not choose the first authored neighbouring zone to approach"
	)
	darkness_ghost.global_position = darkness_ghost._pending_expansion_position
	darkness_ghost._physics_process(0.016)
	_assert(dark_zone.darkened_zones.size() >= 2, "DarknessGhost did not expand into an adjacent zone")
	_assert(
		dark_zone.active_zone.zone_id == StringName(expected_next_zone_ids[0]),
		"DarknessGhost did not expand to the first authored neighbouring zone"
	)
	for device: ElectricalDevice in dark_zone.active_zone.get_devices():
		_assert(not device.powered_light.visible, "DarknessGhost outage did not turn off its fixture light")
	var darkened_zone := dark_zone.active_zone
	darkness_ghost.retreat()
	await process_frame
	_assert(not darkness_ghost.is_manifested(), "DarknessGhost did not retreat")
	_assert(dark_zone.active_zone == null, "DarknessGhost did not release its zone outage")
	_assert(not darkened_zone.is_powered and darkened_zone.requires_switch_restore, "DarknessGhost zone must remain off after retreat")
	var reset_device := darkened_zone.get_devices()[0]
	var other_dark_device := darkened_zone.get_devices()[1]
	var reset_switch := switches.get_node_or_null(String(reset_device.device_id) + "LightSwitch") as StaticBody3D
	_assert(reset_switch != null, "Darkened zone has no usable reset switch")
	var load_before_switch_restore := manager.get_total_load()
	(reset_switch.get_node("Interactable") as Interactable).interact(villa)
	await process_frame
	_assert(reset_device.powered_light.visible, "Switch did not restore its own fixture")
	_assert(manager.get_total_load() > load_before_switch_restore, "Restored fixture did not return its consumption to total load")
	_assert(not other_dark_device.powered_light.visible, "One switch incorrectly restored another zone fixture")
	_assert(not darkened_zone.is_powered and darkened_zone.requires_switch_restore, "One switch incorrectly restored the entire zone")
	dev_tools.set_all_zones_powered(false)
	await process_frame
	_assert(manager.is_blackout, "DevTools all-zones-off must cause full blackout")
	dev_tools.toggle_electrical_zone(zones.get_node("Z07_F00_EAST") as ElectricalZone)
	await process_frame
	_assert(not manager.is_blackout, "DevTools individual zone toggle must restore only that zone")
	_assert(not (zones.get_node("Z03_F00_NORTH") as ElectricalZone).is_powered, "DevTools toggle affected another zone")
	dev_tools.set_all_zones_powered(true)
	await process_frame
	_assert(fixtures != null and fixtures.get_child_count() == 56, "Expected 56 physical ceiling-lamp fixtures")
	_assert(switches != null and switches.get_child_count() == 56, "Expected one interactive switch per room/junction")
	_assert(
		fixtures.get_node_or_null("R_KITCHENFixture/CeilingLamp2") != null,
		"Kitchen fixture is missing the Ceiling Lamp 2 model"
	)
	_assert(
		fixtures.get_node_or_null("R_KITCHENFixture/BulbGlow") == null,
		"Villa fixtures must not show a separate glowing sphere"
	)
	var kitchen_switch := switches.get_node_or_null("R_KITCHENLightSwitch") as StaticBody3D
	_assert(kitchen_switch != null, "Kitchen interactive switch is missing")
	_assert(kitchen_switch.controlled_device_id == &"R_KITCHEN", "Kitchen switch controls the wrong device")
	_assert(kitchen_switch.get_node_or_null("Visual") != null, "Kitchen switch model is missing")
	_assert(kitchen_switch.get_node_or_null("CollisionShape3D") != null, "Kitchen switch needs a raycast collider")
	var kitchen_interactable := kitchen_switch.get_node_or_null("Interactable") as Interactable
	_assert(kitchen_interactable != null, "Kitchen switch is not using the shared Interactable contract")
	kitchen_interactable.interact(villa)
	await process_frame
	_assert(not manager.get_device_by_id(&"R_KITCHEN").is_on, "Kitchen switch did not turn its room light off")
	kitchen_interactable.unlock()
	kitchen_interactable.interact(villa)
	await process_frame
	_assert(manager.get_device_by_id(&"R_KITCHEN").is_on, "Kitchen switch did not restore its room light")

	var mapped_ids: Dictionary = {}
	for zone_node: Node in zones.get_children():
		var zone := zone_node as ElectricalZone
		_assert(zone != null, "ElectricalZones contains a non-zone node")
		for device_id: String in zone.device_ids:
			_assert(not mapped_ids.has(device_id), "Device %s belongs to more than one zone" % device_id)
			mapped_ids[device_id] = true
	_assert(mapped_ids.size() == 56, "All 56 devices must be assigned to a zone")

	var central_north := zones.get_node("Z05_F00_CENTRAL_NORTH") as ElectricalZone
	var east := zones.get_node("Z07_F00_EAST") as ElectricalZone
	_assert(central_north.contains_device_id(&"R_GALLERY"), "Z05 must contain Gallery")
	_assert(central_north.contains_device_id(&"R_ATRIUM"), "Z05 must contain Atrium")
	_assert(not central_north.contains_device_id(&"R_BILLIARD"), "Z05 must not contain Billiard")

	central_north.set_powered(false)
	await process_frame
	_assert(not manager.get_device_by_id(&"R_GALLERY").powered_light.visible, "Z05 did not turn off Gallery")
	_assert(not manager.get_device_by_id(&"R_ATRIUM").powered_light.visible, "Z05 did not turn off Atrium")
	_assert(manager.get_device_by_id(&"R_KITCHEN").powered_light.visible, "Z05 outage affected Z07 Kitchen")
	_assert(east.is_powered, "Z07 lost state when Z05 turned off")

	for zone_node: Node in zones.get_children():
		(zone_node as ElectricalZone).set_powered(false)
	await process_frame
	_assert(manager.is_blackout, "All zones OFF must cause a full house blackout")
	_assert(is_zero_approx(manager.get_total_load()), "Full zone blackout must remove all load")

	central_north.set_powered(true)
	await process_frame
	_assert(not manager.is_blackout, "Restoring one zone must leave all-zone blackout")
	_assert(manager.get_device_by_id(&"R_GALLERY").powered_light.visible, "Restored zone did not recover Gallery")
	_assert(not manager.get_device_by_id(&"R_KITCHEN").powered_light.visible, "Unrestored zone recovered during blackout exit")

	print("Villa zone smoke test passed: 56 fixtures, 13 zones, independent outage and full blackout.")
	villa.queue_free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

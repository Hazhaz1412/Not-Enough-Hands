extends SceneTree


class TestLivingPlayer extends CharacterBody3D:
	var is_alive := true
	var is_downed := false
	var is_spectator := false


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
	var first_fixture := manager.devices[0] as ElectricalDevice
	var electrical_setup := villa.get_node_or_null("VillaElectrical") as VillaElectricalSetup
	_assert(
		first_fixture != null and is_equal_approx(first_fixture.powered_light.light_energy, 1.25),
		"Villa fixtures must use the brighter 1.25 energy setting"
	)
	_assert(
		electrical_setup != null
			and is_equal_approx(electrical_setup.fixture_range_multiplier, 1.4),
		"Villa fixtures must use the wider 1.4 range multiplier"
	)
	var player_flashlight := (villa.get_node("Player") as Node3D).get_node(
		"CameraPivot/Camera3D/Flashlight"
	) as SpotLight3D
	_assert(
		is_equal_approx(player_flashlight.light_energy, 2.4)
			and is_equal_approx(player_flashlight.spot_range, 15.0)
			and is_equal_approx(player_flashlight.spot_angle, 31.0),
		"Player flashlight did not receive the small visibility increase"
	)
	var villa_environment := (villa.get_node("WorldEnvironment") as WorldEnvironment).environment
	_assert(
		is_equal_approx(villa_environment.ambient_light_energy, 0.28)
			and is_equal_approx(villa_environment.tonemap_exposure, 0.9),
		"Villa ambient visibility did not receive the requested increase"
	)
	_assert(manager.enable_power_drain, "Villa PowerManager must consume total power")
	var initial_total_load := manager.get_total_load()
	_assert(initial_total_load > 0.0, "Powered Villa fixtures must contribute to total load")
	var fixtures := villa.get_node_or_null("VillaElectrical/RoomLights")
	var switches := villa.get_node_or_null("VillaElectrical/RoomSwitches")
	_assert(dev_tools.zone_controls.get_child_count() == 13, "DevTools must expose one control per electrical zone")
	var darkness_ghost := villa.get_node_or_null("DarknessGhost") as DarknessGhost
	_assert(darkness_ghost != null, "villa_main is missing DarknessGhost")
	_assert(
		is_equal_approx(darkness_ghost.manifest_interval, 110.0),
		"DarknessGhost must wait 110 seconds between attacks"
	)
	_assert(not darkness_ghost.is_manifested(), "DarknessGhost must begin hidden")
	var target_player := villa.get_node("Player") as CharacterBody3D
	# Simulate a prior hunt's sighting latch; every new manifestation must clear
	# it so the next approach is protected from off-screen room lights again.
	darkness_ghost._has_been_seen = true
	_assert(dev_tools.spawn_darkness_ghost(), "DevTools could not manifest DarknessGhost")
	_assert(
		not darkness_ghost.has_been_seen(),
		"A new DarknessGhost encounter inherited the previous hunt's sighting latch"
	)
	await process_frame
	_assert(darkness_ghost.is_manifested(), "DarknessGhost did not enter its hunt state")
	_assert(darkness_ghost.get_node("AnimatedModel").visible, "DarknessGhost model did not become visible")
	_assert(
		darkness_ghost.encounter_phase == DarknessGhost.EncounterPhase.WARNING,
		"DarknessGhost must warn before cutting power"
	)
	_assert(is_equal_approx(darkness_ghost.warning_duration, 4.0), "DarknessGhost warning must last four seconds")
	_assert(
		darkness_ghost.global_position.distance_to(target_player.global_position)
			>= darkness_ghost.minimum_spawn_distance,
		"DarknessGhost spawned within the 15m safety radius"
	)
	_assert(
		is_equal_approx(darkness_ghost.normal_speed, 4.0)
			and is_equal_approx(darkness_ghost.darkness_speed, 5.25)
			and is_equal_approx(darkness_ghost.patrol_speed, 3.25),
		"DarknessGhost must move at 4m/s normally and 5.25m/s without direct light"
	)
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
	var dark_zone := darkness_ghost.get_node("DarknessEntityPowerEffect") as DarknessEntityPowerEffect
	_assert(darkness_ghost._encounter_zones.size() >= 2, "DarknessGhost warning must cover neighbouring zones")
	for warning_zone: ElectricalZone in darkness_ghost._encounter_zones:
		_assert(warning_zone.is_powered, "Warning flicker cut a zone before four seconds elapsed")
	var warning_device := darkness_ghost._encounter_zones[0].get_devices()[0] as ElectricalDevice
	darkness_ghost._warning_time_left = 0.15
	darkness_ghost._update_warning_visuals()
	var light_probe := warning_device.powered_light.global_position + Vector3.DOWN
	_assert(
		darkness_ghost._is_position_locally_lit(light_probe),
		"Powered room light was not recognised as a speed-limiting light source"
	)
	_assert(
		is_equal_approx(darkness_ghost._chase_speed_at(light_probe), 4.0),
		"DarknessGhost did not stay at 4m/s under a powered room light"
	)
	darkness_ghost._warning_time_left = 0.05
	darkness_ghost._update_warning_visuals()
	_assert(not warning_device.powered_light.visible, "Four-second warning did not flicker its lights off")
	darkness_ghost._warning_time_left = 0.15
	darkness_ghost._update_warning_visuals()
	_assert(warning_device.powered_light.visible, "Four-second warning did not flicker its lights back on")
	darkness_ghost._warning_time_left = darkness_ghost.warning_duration
	darkness_ghost._process(darkness_ghost.warning_duration + 0.01)
	await process_frame
	_assert(
		darkness_ghost.encounter_phase == DarknessGhost.EncounterPhase.CHASING,
		"DarknessGhost did not begin chasing after its warning"
	)
	_assert(
		dark_zone.darkened_zones.size() == darkness_ghost._encounter_zones.size()
			and dark_zone.darkened_zones.size() >= 2,
		"DarknessGhost did not cut its whole neighbouring-zone cluster together"
	)
	for cut_zone: ElectricalZone in dark_zone.darkened_zones:
		_assert(not cut_zone.is_powered, "A warned DarknessGhost zone remained powered")
		for device: ElectricalDevice in cut_zone.get_devices():
			_assert(not device.powered_light.visible, "A warned fixture remained visible after blackout")
	_assert(
		not darkness_ghost._is_position_locally_lit(light_probe),
		"Blackout position was still treated as directly lit"
	)
	_assert(
		is_equal_approx(darkness_ghost._chase_speed_at(light_probe), 5.25),
		"DarknessGhost did not accelerate to 5.25m/s in unlit space"
	)
	_assert(manager.get_total_load() < initial_total_load, "DarknessGhost outage did not reduce whole-house load")

	# Restoring a cut circuit is a gamble on which fixture you reached, not a
	# question of who you are: the chased player may work any switch the hunt did
	# not jam, and nobody can work one it did.
	var darkened_zone := dark_zone.active_zone
	var free_device: ElectricalDevice
	var locked_device: ElectricalDevice
	for device: ElectricalDevice in darkened_zone.get_devices():
		if darkened_zone.is_device_restore_locked(device):
			if locked_device == null:
				locked_device = device
		elif free_device == null:
			free_device = device
	_assert(free_device != null, "A cut zone must always leave at least one fixture restorable")
	if locked_device:
		var locked_switch := switches.get_node_or_null(
			String(locked_device.device_id) + "LightSwitch"
		) as StaticBody3D
		_assert(locked_switch != null, "Jammed fixture has no switch to refuse")
		locked_switch._on_interacted(target_player)
		await process_frame
		_assert(
			not locked_device.powered_light.visible,
			"A fixture the hunt jammed was restored by its switch anyway"
		)
	var reset_switch := switches.get_node_or_null(String(free_device.device_id) + "LightSwitch") as StaticBody3D
	_assert(reset_switch != null, "Darkened zone has no usable reset switch")
	var load_before_switch_restore := manager.get_total_load()
	reset_switch._on_interacted(target_player)
	await process_frame
	_assert(free_device.powered_light.visible, "Switch did not restore its own fixture")
	_assert(manager.get_total_load() > load_before_switch_restore, "Restored fixture did not return its consumption to total load")
	_assert(not darkened_zone.is_powered and darkened_zone.requires_switch_restore, "One switch incorrectly restored the entire zone")

	# Aggro is recomputed from the ghost every frame, never held by the player it
	# first marked.
	var closer_player := TestLivingPlayer.new()
	villa.add_child(closer_player)
	closer_player.global_position = darkness_ghost.global_position + Vector3(3.0, 0.0, 0.0)
	closer_player.add_to_group(&"players")
	darkness_ghost._physics_process(0.016)
	_assert(darkness_ghost._target_player == closer_player, "DarknessGhost did not switch to the closer player")
	closer_player.queue_free()

	darkness_ghost.retreat()
	await process_frame
	_assert(not darkness_ghost.is_manifested(), "DarknessGhost did not retreat")
	_assert(dark_zone.active_zone == null, "DarknessGhost did not release its zone outage")
	# The pocket comes back with the hunt. Leaving it off retired those zones for
	# the rest of the night: the next manifest can only cut a *powered* zone.
	_assert(
		darkened_zone.is_powered and not darkened_zone.requires_switch_restore,
		"DarknessGhost did not give its zones back when the hunt ended"
	)
	if locked_device:
		_assert(
			not darkened_zone.is_device_restore_locked(locked_device),
			"The end of a hunt did not lift the fixture jam it caused"
		)

	# Integration regression: use a generated Villa fixture, not a synthetic
	# test light. It may cross the light while unseen, but after a player sees it,
	# half a second continuously under the fixture must end only this hunt.
	_assert(
		is_equal_approx(darkness_ghost.light_death_seconds, 0.5),
		"Villa DarknessGhost environmental-light death time must be 0.5 seconds"
	)
	_assert(
		darkness_ghost._is_position_environmentally_lit(light_probe),
		"Powered Villa room light was not recognised as environmental light"
	)
	darkness_ghost.global_position = light_probe
	darkness_ghost._has_been_seen = false
	darkness_ghost._is_dead = false
	darkness_ghost.auto_manifest = true
	darkness_ghost._set_manifested(true)
	darkness_ghost.encounter_phase = DarknessGhost.EncounterPhase.CHASING
	darkness_ghost._update_light_exposure(1.5)
	_assert(
		darkness_ghost.is_manifested()
			and not darkness_ghost.is_dead()
			and is_equal_approx(darkness_ghost._environment_light_exposure, 0.0),
		"Unseen DarknessGhost did not remain immune while crossing a powered Villa room"
	)
	darkness_ghost._has_been_seen = true
	darkness_ghost._update_light_exposure(0.49)
	_assert(
		darkness_ghost.is_manifested() and not darkness_ghost.is_dead(),
		"Villa room light ended the Darkness hunt before 0.5 seconds"
	)
	darkness_ghost._update_light_exposure(0.02)
	_assert(
		not darkness_ghost.is_dead()
			and not darkness_ghost.is_manifested()
			and darkness_ghost.auto_manifest
			and is_equal_approx(darkness_ghost._next_manifest_in, darkness_ghost.manifest_interval),
		"Villa room light did not end only the current hunt and schedule its cooldown"
	)

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

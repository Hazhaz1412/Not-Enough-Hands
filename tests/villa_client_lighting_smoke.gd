extends SceneTree

## Verifies the per-client Villa lighting budget without booting or baking the
## full map. A local camera may promote only the nearest configured number of
## fixtures, and no fixture may inject into volumetric fog.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var manager := PowerManager.new()
	world.add_child(manager)

	var setup := VillaElectricalSetup.new()
	setup.rebuild_on_ready = false
	setup.max_shadow_lights = 6
	setup.shadow_max_distance = 100.0
	world.add_child(setup)
	var lights_root := Node3D.new()
	lights_root.name = "RoomLights"
	setup.add_child(lights_root)
	var switches_root := Node3D.new()
	switches_root.name = "RoomSwitches"
	setup.add_child(switches_root)

	for index: int in 10:
		var marker := Marker3D.new()
		marker.name = "TEST_%02d" % index
		marker.position = Vector3(float(index) * 2.0, 0.0, 0.0)
		marker.set_meta("room_id", marker.name)
		marker.set_meta("room_size", Vector3(4.0, 3.5, 4.0))
		marker.add_to_group("villa_rooms")
		world.add_child(marker)

	setup.build_fixtures()
	var camera := Camera3D.new()
	camera.position = Vector3.ZERO
	world.add_child(camera)
	camera.current = true
	await process_frame
	setup.call("_update_shadow_budget")

	var shadow_count := 0
	var fixture_count := 0
	for node: Node in get_nodes_in_group("flickering_house_lights"):
		var light := node as OmniLight3D
		if not light:
			continue
		fixture_count += 1
		if light.shadow_enabled:
			shadow_count += 1
		if not is_zero_approx(light.light_volumetric_fog_energy):
			return _fail("Villa fixture %s still injects into volumetric fog." % light.name)

	if fixture_count != 10:
		return _fail("Expected 10 fixture lights, found %d." % fixture_count)
	if shadow_count != setup.max_shadow_lights:
		return _fail("Shadow budget enabled %d lights, expected %d."
			% [shadow_count, setup.max_shadow_lights])

	print("Villa client lighting smoke test passed: 6/10 shadows, fixture fog injection disabled.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

extends SceneTree

## Confirms that the procedural window pass opens visual bays without removing
## wall collision, and keeps the dynamic moonlight budget bounded.
##
##   godot --headless --script tests/villa_windows_smoke.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _main_scene_has_windows():
		_fail("VillaMain does not contain the VillaWindows module.")
		return

	var stage := Node3D.new()
	root.add_child(stage)

	var house := VillaHouse.new()
	house.name = "VillaHouse"
	house.detail = VillaHouse.Detail.BLOCKOUT
	house.authoring_granularity = VillaHouse.AuthoringGranularity.EDITABLE_MODULES
	house.build_furniture = false
	stage.add_child(house)

	var windows := (load("res://house3/villa_windows.gd") as Script).new() as Node3D
	windows.name = "VillaWindows"
	windows.set("active_lights", 3)
	windows.set("shadowed_lights", 2)
	stage.add_child(windows)

	var camera := Camera3D.new()
	camera.position = Vector3(40.0, 2.0, 30.0)
	camera.current = true
	stage.add_child(camera)

	await process_frame
	await process_frame

	var generated := windows.get_node_or_null("Generated") as Node3D
	if not generated or not generated.is_in_group("villa_windows"):
		_fail("VillaWindows generated no grouped output.")
		return

	var panes := int(generated.get_meta("glazed_count", 0))
	var boarded := int(generated.get_meta("boarded_count", 0))
	var lights := generated.find_children("Moonlight_*", "SpotLight3D", true, false)
	if panes == 0:
		_fail("No glazed window bays were generated.")
		return
	if boarded == 0:
		_fail("No boarded window variation was generated.")
		return
	if lights.size() != panes + boarded:
		_fail(
			"Expected one moonlight per bay, got %d lights for %d glazed and %d boarded bays."
			% [lights.size(), panes, boarded]
		)
		return
	var batches := generated.find_children("*", "MultiMeshInstance3D", true, false)
	if batches.is_empty() or batches.size() > 10:
		_fail("Window geometry was not efficiently batched: %d render batches." % batches.size())
		return
	var logical_meshes := int(generated.get_meta("logical_mesh_count", 0))
	if logical_meshes < 500:
		_fail("Window batching lost authored geometry.")
		return

	var opened_wall := _find_opened_wall(house)
	if not opened_wall:
		_fail("The window pass did not hide any wall panel.")
		return
	var collision := opened_wall.get_node_or_null("Collision") as CollisionShape3D
	if not collision or collision.disabled or not collision.shape:
		_fail("Opening a visual window removed or disabled its wall collision.")
		return

	windows.call("_process", 1.0)
	var visible_count := 0
	var shadow_count := 0
	for node: Node in lights:
		var light := node as SpotLight3D
		visible_count += int(light.visible)
		shadow_count += int(light.shadow_enabled)
	if visible_count != 3 or shadow_count != 2:
		_fail(
			"Moonlight budget mismatch: %d visible, %d shadowed."
			% [visible_count, shadow_count]
		)
		return

	print(
		"Villa windows smoke test passed: %d glazed, %d boarded, %d pieces in %d batches, %d active lights."
		% [panes, boarded, logical_meshes, batches.size(), visible_count]
	)
	stage.queue_free()
	await process_frame
	quit(0)


func _main_scene_has_windows() -> bool:
	var packed := load("res://house3/villa_main.tscn") as PackedScene
	if not packed:
		return false
	var state := packed.get_state()
	for index: int in state.get_node_count():
		if state.get_node_name(index) == &"VillaWindows":
			return true
	return false


func _find_opened_wall(house: Node3D) -> StaticBody3D:
	for node: Node in house.find_children("ExteriorWall_*", "StaticBody3D", true, false):
		for child: Node in node.get_children():
			if child is Node3D and not child is CollisionShape3D and not (child as Node3D).visible:
				return node as StaticBody3D
	return null


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

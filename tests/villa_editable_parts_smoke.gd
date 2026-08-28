extends SceneTree

const PACKED_PATH := "res://.godot/villa_editable_parts_test.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var house := (load("res://house3/villa_house.tscn") as PackedScene).instantiate() as VillaHouse
	house.detail = VillaHouse.Detail.BLOCKOUT
	house.build_furniture = false
	house.build_lighting = false
	house.authoring_granularity = VillaHouse.AuthoringGranularity.EDITABLE_MODULES
	root.add_child(house)
	await process_frame

	var checked := 0
	for pattern: String in ["FloorSlab_*", "CeilingSlab_*", "InteriorWall_*", "ExteriorWall_*", "ShaftWall_*"]:
		for node: Node in house.find_children(pattern, "StaticBody3D", true, false):
			var collision := node.get_node_or_null("Collision") as CollisionShape3D
			if not collision or not collision.shape is BoxShape3D:
				_fail("%s has no box collision." % node.get_path())
				return
			var size := (collision.shape as BoxShape3D).size
			if size.x > 2.001 or size.z > 2.001:
				_fail("%s is still merged: %s." % [node.get_path(), size])
				return
			checked += 1
	if checked < 1000:
		_fail("Only %d editable architecture pieces were generated." % checked)
		return

	var generated := house.get_node("Generated")
	house.call("_make_scene_owned", generated, house)
	var packed := PackedScene.new()
	if packed.pack(house) != OK or ResourceSaver.save(packed, PACKED_PATH) != OK:
		_fail("Editable villa could not be packed.")
		return
	var restored := (load(PACKED_PATH) as PackedScene).instantiate()
	house.queue_free()
	await process_frame
	root.add_child(restored)
	await process_frame
	if not restored.has_node("Generated"):
		_fail("Generated parts disappeared after pack/load.")
		return
	var rooms := restored.get_tree().get_nodes_in_group("villa_rooms")
	if rooms.size() != 37:
		_fail("Persistent villa room groups were lost after pack/load: %d." % rooms.size())
		return
	print("Villa editable-parts smoke test passed: %d cell-sized parts survived pack/load." % checked)
	restored.queue_free()
	await process_frame
	_cleanup()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)


func _cleanup() -> void:
	if FileAccess.file_exists(PACKED_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PACKED_PATH))

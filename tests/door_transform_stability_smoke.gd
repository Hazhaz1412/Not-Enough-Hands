extends SceneTree

## A door leaf must be authored at the opening width rather than shrinking the
## rotating Door node. A non-uniform parent scale combines with Hinge yaw into
## a sheared transform, which is especially visible after rapid toggles.

const DOOR_SCENE := preload("res://door/door.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var door := DOOR_SCENE.instantiate() as Node3D
	root.add_child(door)
	door.open_duration = 0.001
	door.close_duration = 0.001
	door.ghost_shoulder_enabled = false

	var mesh := door.get_node("Hinge/DoorMesh") as MeshInstance3D
	var leaf_mesh := mesh.mesh as BoxMesh
	if not door.scale.is_equal_approx(Vector3.ONE) \
		or not leaf_mesh.size.is_equal_approx(Vector3(2.0, 2.3, 0.12)):
		_fail("Door leaf still relies on non-uniform node scale.")
		return

	for _toggle in 24:
		door.interact()
		await physics_frame
		await physics_frame
		door.interact()
		await physics_frame
		await physics_frame

	var hinge := door.get_node("Hinge") as Node3D
	if not hinge.scale.is_equal_approx(Vector3.ONE) \
		or not hinge.rotation.is_equal_approx(Vector3.ZERO):
		_fail("Rapid door toggles changed the leaf transform.")
		return

	print("Door transform stability smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

## Guards the imported statue model: it stands in for the stone body, and the
## pivot rotations that used to drive that body still pose its skeleton - the
## model ships without a single animation clip, so nothing else would.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var statue := (load('res://ghosts/statue_ghost.tscn') as PackedScene).instantiate()
	statue.set('active', false)
	root.add_child(statue)
	await physics_frame

	var visual_root: Node3D = statue.get_node('VisualRoot')
	var model: Node3D = visual_root.get_node_or_null('Model')
	if model == null:
		_fail('Statue scene is missing its VisualRoot/Model instance.')
		return

	for node: Node in visual_root.find_children('*', 'MeshInstance3D', true, false):
		if not model.is_ancestor_of(node) and (node as MeshInstance3D).visible:
			_fail('Procedural mesh %s is still visible under the model.' % node.name)
			return

	var skeleton: Skeleton3D = statue.get('model_skeleton')
	if skeleton == null:
		_fail('Statue model exposed no Skeleton3D to pose.')
		return
	var drivers: Array = statue.get('model_bone_drivers')
	if drivers.size() != 10:
		_fail('Expected 10 posed bones, found %d.' % drivers.size())
		return

	# Vigil: arms at its sides. A T-posing model would hold its hands level
	# with the shoulders instead of hanging them well below.
	statue.call('_apply_idle_pose', 0)
	var shoulder := _bone_position(statue, skeleton, 'mixamorig_LeftArm_017')
	var left_hand := _bone_position(statue, skeleton, 'mixamorig_LeftHand_019')
	var right_hand := _bone_position(statue, skeleton, 'mixamorig_RightHand_08')
	if shoulder.y - left_hand.y < 0.4 or shoulder.y - right_hand.y < 0.4:
		_fail('Vigil pose left the model in its bind pose: hands are not hanging.')
		return

	# Reaching: the right hand is already out for your throat, so it has to end
	# up ahead of the body (-Z), which only holds if the model faces forward.
	statue.call('_apply_idle_pose', 2)
	var reach := _bone_position(statue, skeleton, 'mixamorig_RightHand_08')
	if reach.z > -0.5:
		_fail('Reaching pose did not throw the right hand forward (z = %.2f).' % reach.z)
		return

	var toe := _bone_position(statue, skeleton, 'mixamorig_LeftToe_End_027')
	var heel := _bone_position(statue, skeleton, 'mixamorig_LeftFoot_026')
	if toe.z > heel.z:
		_fail('Model is facing backwards: its toes point behind its ankles.')
		return

	print('Statue model smoke test passed: stone body hidden, %d bones posed.' % drivers.size())
	quit()


func _bone_position(statue: Node3D, skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	return statue.to_local(skeleton.to_global(skeleton.get_bone_global_pose(bone).origin))


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

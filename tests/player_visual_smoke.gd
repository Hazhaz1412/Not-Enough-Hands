extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_scene := load("res://player/player.tscn") as PackedScene
	if not player_scene:
		_fail("Player scene could not be loaded.")
		return

	var player := player_scene.instantiate() as CharacterBody3D
	root.add_child(player)
	player.set_physics_process(false)
	var visual := player.get_node_or_null("PlayerVisual") as Node3D
	var character := player.get_node_or_null("PlayerVisual/Character") as Node3D
	var skeleton := player.get_node_or_null(
		"PlayerVisual/Character/simple_character/GeneralSkeleton"
	) as Skeleton3D
	var mesh := player.get_node_or_null(
		"PlayerVisual/Character/simple_character/GeneralSkeleton/body"
	) as MeshInstance3D
	var animation_player := player.get_node_or_null(
		"PlayerVisual/Character/CharacterAnimationPlayer"
	) as AnimationPlayer
	var name_tag := player.get_node_or_null("PlayerVisual/NameTag") as Label3D
	var flashlight := player.get_node_or_null(
		"CameraPivot/Camera3D/Flashlight"
	) as SpotLight3D
	if not visual or not character or not skeleton or not mesh \
			or not animation_player or not name_tag or not flashlight:
		_fail("Player visual, body mesh, name tag, or runtime AnimationPlayer is missing.")
		return
	if absf(wrapf(character.rotation.y - PI, -PI, PI)) > 0.001:
		_fail("The model must be yaw-corrected 180 degrees to face camera forward.")
		return

	for animation_name: StringName in [&"idle", &"run", &"jump"]:
		if not animation_player.has_animation(animation_name):
			_fail("Player visual is missing the %s animation." % animation_name)
			return

	var material := mesh.get_active_material(0) as BaseMaterial3D
	if not material or not material.albedo_texture:
		_fail("The player model lost its baked texture.")
		return
	var local_body_mask := 1 << (20 - 1)
	var rig_geometry := character.find_children("*", "GeometryInstance3D", true, false)
	if rig_geometry.is_empty():
		_fail("The local player rig has no render geometry.")
		return
	for node: Node in rig_geometry:
		var geometry := node as GeometryInstance3D
		if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("Every local first-person body part must stop casting flashlight shadows.")
			return
		if geometry.layers != local_body_mask:
			_fail(
				"Local body part %s still shares a world layer with its flashlight."
				% geometry.name
			)
			return
	if flashlight.light_cull_mask & local_body_mask:
		_fail("The local flashlight still illuminates and shadows the local body layer.")
		return
	if character.visible:
		_fail("The owning camera is still inside a visible local player model.")
		return
	if name_tag.visible:
		_fail("The local player should not see their own name tag.")
		return
	var death_ui := player.get_node_or_null("DeathUI") as CanvasLayer
	var door_minigame := player.get_node_or_null("DoorGhostMinigame/Overlay") as CanvasLayer
	if not death_ui or death_ui.visible:
		_fail("The local player's death jumpscare must start hidden.")
		return
	if not door_minigame or door_minigame.visible:
		_fail("The local player's door minigame must start hidden.")
		return

	# The importer bakes the rig's node transforms into the skeleton, so every
	# mesh AABB is already metres in skeleton space. Their union is the body the
	# other players see, and it has to fit the capsule it rides in: a head
	# sticking out of the capsule is a head sticking through ceilings and
	# doorframes that same capsule walks under.
	var to_player := player.global_transform.affine_inverse() * skeleton.global_transform
	var bounds := to_player * mesh.mesh.get_aabb()
	for part_name: String in ["arms", "head"]:
		var part := skeleton.get_node_or_null(part_name) as MeshInstance3D
		if part:
			bounds = bounds.merge(to_player * part.mesh.get_aabb())
	var model_height := bounds.size.y
	var expected_floor: float = -player.standing_height * 0.5
	if model_height < 1.5 or model_height > player.standing_height:
		_fail(
			"Player model is %.2f m tall; it has to fit the %.2f m capsule."
			% [model_height, player.standing_height]
		)
		return
	if absf(bounds.position.y - expected_floor) > 0.12:
		_fail(
			"Player model feet are at %.2f m; capsule floor is %.2f m."
			% [bounds.position.y, expected_floor]
		)
		return

	# The Kenney clips were authored against a different rig and carry hip
	# position tracks to match: the jump one parked this body a metre under the
	# floor, which read in game as sinking through the ground on every jump,
	# fall and step-up. No clip may drive the skeleton below its own capsule.
	for animation_name: StringName in [&"idle", &"run", &"jump"]:
		var clip := animation_player.get_animation(animation_name)
		animation_player.play(animation_name)
		var sample := 0.0
		while sample <= clip.length:
			animation_player.seek(sample, true)
			skeleton.force_update_all_bone_transforms()
			for bone_index: int in skeleton.get_bone_count():
				var bone_y: float = (
					to_player * skeleton.get_bone_global_pose(bone_index).origin
				).y
				if bone_y < expected_floor - 0.05:
					_fail(
						"The %s animation drives the rig %.2f m under the capsule floor."
						% [animation_name, expected_floor - bone_y]
					)
					return
			sample += 0.05
	animation_player.play(&"idle")

	var standing_scale_y: float = visual.scale.y
	player.is_crouching = true
	visual.call("_physics_process", 1.0)
	if visual.scale.y >= standing_scale_y:
		_fail("Player visual did not lower its silhouette for crouching.")
		return

	player.is_crouching = false
	player.is_alive = false
	player.is_downed = false
	player.is_spectator = false
	visual.call("_physics_process", 1.0)
	if absf(character.rotation.x + PI * 0.5) > 0.01:
		_fail("A final-dead remote body stayed upright instead of using the fallen pose.")
		return

	print(
		"Player visual smoke test passed: model textured, idle/run/jump retargeted, "
		+ "%.2f m body aligned to capsule, local body cannot shadow flashlight, crouch lowers, death falls."
		% model_height
	)
	quit()


func _fail(message: String) -> void:
	push_error("Player visual smoke test failed: " + message)
	print("Player visual smoke test FAILED: " + message)
	quit(1)

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
	var mesh := player.get_node_or_null(
		"PlayerVisual/Character/Root/Skeleton3D/characterMedium"
	) as MeshInstance3D
	var animation_player := player.get_node_or_null(
		"PlayerVisual/Character/CharacterAnimationPlayer"
	) as AnimationPlayer
	var name_tag := player.get_node_or_null("PlayerVisual/NameTag") as Label3D
	if not visual or not character or not mesh or not animation_player or not name_tag:
		_fail("Player visual, body mesh, name tag, or runtime AnimationPlayer is missing.")
		return
	if absf(wrapf(character.rotation.y - PI, -PI, PI)) > 0.001:
		_fail("The Kenney model must be yaw-corrected 180 degrees to face camera forward.")
		return

	for animation_name: StringName in [&"idle", &"run", &"jump"]:
		if not animation_player.has_animation(animation_name):
			_fail("Player visual is missing the %s animation." % animation_name)
			return

	var material := mesh.get_active_material(0) as BaseMaterial3D
	if not material or not material.albedo_texture:
		_fail("Kenney player skin was not applied to the body mesh.")
		return
	if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		_fail("The local first-person body should render as shadows only.")
		return
	if name_tag.visible:
		_fail("The local player should not see their own name tag.")
		return
	var death_ui := player.get_node_or_null("DeathUI") as CanvasLayer
	var door_minigame := player.get_node_or_null("DoorGhostMinigame") as CanvasLayer
	if not death_ui or death_ui.visible:
		_fail("The local player's death jumpscare must start hidden.")
		return
	if not door_minigame or door_minigame.visible:
		_fail("The local player's door minigame must start hidden.")
		return

	var bounds: AABB = player.global_transform.affine_inverse() * mesh.global_transform * mesh.mesh.get_aabb()
	var expected_floor: float = -player.standing_height * 0.5
	if bounds.size.y < 1.55 or bounds.size.y > 1.9:
		_fail("Player model is %.2f m tall; expected it to fit the 1.75 m capsule." % bounds.size.y)
		return
	if absf(bounds.position.y - expected_floor) > 0.12:
		_fail(
			"Player model feet are at %.2f m; capsule floor is %.2f m."
			% [bounds.position.y, expected_floor]
		)
		return

	var standing_scale_y: float = visual.scale.y
	player.is_crouching = true
	visual.call("_physics_process", 1.0)
	if visual.scale.y >= standing_scale_y:
		_fail("Player visual did not lower its silhouette for crouching.")
		return

	print(
		"Player visual smoke test passed: Kenney skin applied, idle/run/jump loaded, "
		+ "%.2f m body aligned to capsule, local body shadows-only, crouch silhouette lowers."
		% bounds.size.y
	)
	quit()


func _fail(message: String) -> void:
	push_error("Player visual smoke test failed: " + message)
	print("Player visual smoke test FAILED: " + message)
	quit(1)

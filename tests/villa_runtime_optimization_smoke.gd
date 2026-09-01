extends SceneTree

## Focused contract for the Villa load-time optimization. This intentionally
## avoids unrelated furnishing assertions in villa_boot_smoke.gd.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame: int in 4:
		await process_frame
	await physics_frame

	var house := game.get_node_or_null("VillaHouse") as Node3D
	if not house:
		return _fail("VillaHouse is missing.")
	var player := game.get_node_or_null("Player") as CharacterBody3D
	var flashlight := game.get_node_or_null(
		"Player/CameraPivot/Camera3D/Flashlight"
	) as SpotLight3D
	if not player or not flashlight or not flashlight.visible \
			or not flashlight.is_visible_in_tree() or flashlight.light_energy <= 0.0 \
			or flashlight.spot_range <= 0.0:
		return _fail("The offline Villa player spawned without a working visible flashlight.")
	for node: Node in player.get_node("PlayerVisual/Character").find_children(
		"*", "GeometryInstance3D", true, false
	):
		var geometry := node as GeometryInstance3D
		if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return _fail("The Villa player's local rig can still shadow its flashlight.")

	var expected_roots: Dictionary = {}
	for node: Node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance.mesh or bool(game.call("_has_authored_collision", mesh_instance)):
			continue
		var asset_root := game.call("_source_asset_root", mesh_instance) as Node3D
		if not asset_root:
			asset_root = mesh_instance
		if bool(game.call("_is_non_solid_furniture", asset_root)):
			continue
		expected_roots[asset_root] = true

	if expected_roots.is_empty():
		return _fail("The fixture found no uncollided Villa props to validate.")
	for root_variant: Variant in expected_roots:
		var asset_root := root_variant as Node3D
		var body := asset_root.get_node_or_null("SimplifiedCollision") as StaticBody3D
		if not body:
			return _fail("%s has neither authored collision nor a simplified box." % asset_root.name)
		var collision := body.get_node_or_null("Collision") as CollisionShape3D
		if not collision or not collision.shape is BoxShape3D:
			return _fail("%s did not receive a BoxShape3D collider." % asset_root.name)

	var region := game.get_node_or_null("VillaNavigationRegion") as NavigationRegion3D
	if not region or not region.navigation_mesh or region.navigation_mesh.get_polygon_count() <= 0:
		return _fail("World authority no longer bakes a usable Villa navmesh.")

	print("Villa runtime optimization smoke test passed: %d simplified prop colliders, navmesh preserved."
		% expected_roots.size())
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

extends SceneTree

## Verifies the villa's Classic64 suburban exterior without booting gameplay or
## baking navigation. The full villa tests cover the combined scene.
##
##   godot --headless --script tests/villa_exterior_smoke.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _main_scene_has_exterior():
		_fail("VillaMain does not contain the VillaExterior module.")
		return

	var stage := Node3D.new()
	root.add_child(stage)
	var exterior := (load("res://house3/villa_exterior.gd") as Script).new() as Node3D
	exterior.name = "VillaExterior"
	stage.add_child(exterior)
	await process_frame

	var generated := exterior.get_node_or_null("Generated") as Node3D
	if not generated or not generated.is_in_group("villa_exterior"):
		_fail("VillaExterior generated no grouped output.")
		return

	for section: String in [
		"Terrain", "RingRoad", "Boundary", "FrontCourt", "ServiceYard",
		"CellarTrench", "BackGarden", "Backdrop", "Atmosphere",
	]:
		if not generated.has_node(section):
			_fail("Exterior section %s was not generated." % section)
			return

	var meshes := generated.find_children("*", "MeshInstance3D", true, false)
	var batches := generated.find_children("*", "MultiMeshInstance3D", true, false)
	var static_bodies := generated.find_children("*", "StaticBody3D", true, false)
	var lights := generated.find_children("*", "Light3D", true, false)
	var fog := generated.find_children("*", "FogVolume", true, false)
	var logical_meshes := int(generated.get_meta("logical_mesh_count", 0))
	if logical_meshes < 1000:
		_fail("Exterior detail is unexpectedly sparse: %d logical meshes." % logical_meshes)
		return
	if batches.is_empty() or meshes.size() + batches.size() > 320:
		_fail(
			"Exterior geometry was not efficiently batched: %d meshes + %d batches."
			% [meshes.size(), batches.size()]
		)
		return
	var rendered_instances := meshes.size()
	for node: Node in batches:
		var multimesh := (node as MultiMeshInstance3D).multimesh
		if not multimesh or multimesh.instance_count == 0:
			_fail("Exterior contains an empty render batch.")
			return
		rendered_instances += multimesh.instance_count
	if rendered_instances != logical_meshes:
		_fail(
			"Batching lost geometry: %d rendered instances for %d authored meshes."
			% [rendered_instances, logical_meshes]
		)
		return
	if static_bodies.size() < 80:
		_fail("Exterior collision is unexpectedly sparse: %d bodies." % static_bodies.size())
		return
	if lights.size() < 7 or fog.size() != 4:
		_fail("Exterior atmosphere is incomplete: %d lights, %d fog volumes." % [lights.size(), fog.size()])
		return

	var logical_counts := generated.get_meta("logical_counts", {}) as Dictionary
	for detail: String in ["LeafLitter", "DeadGrass", "FallenBranch", "GardenRock"]:
		if int(logical_counts.get(detail, 0)) == 0:
			_fail("Exterior is missing ground detail %s." % detail)
			return
	if int(logical_counts.get("SicklyLeaves", 0)) == 0:
		_fail("Exterior treeline has no remaining foliage.")
		return
	if int(logical_counts.get("LeafyShrub", 0)) < 16:
		_fail("Exterior garden has too few leafy shrub cards.")
		return

	var texture_paths: Dictionary = {}
	for node: Node in meshes:
		var mesh_instance := node as MeshInstance3D
		var material := mesh_instance.mesh.material as StandardMaterial3D if mesh_instance.mesh else null
		if not material or not material.albedo_texture:
			continue
		texture_paths[material.albedo_texture.resource_path] = true
	for node: Node in batches:
		var batch_instance := node as MultiMeshInstance3D
		var batch_mesh := batch_instance.multimesh.mesh if batch_instance.multimesh else null
		var material := batch_mesh.material as StandardMaterial3D if batch_mesh else null
		if material and material.albedo_texture:
			texture_paths[material.albedo_texture.resource_path] = true
	if texture_paths.size() < 15:
		_fail("Exterior uses only %d Classic64 textures; expected a dressed environment." % texture_paths.size())
		return

	for node: Node in static_bodies:
		var at := (node as Node3D).global_position
		if at.x < -24.01 or at.x > 104.01 or at.z < -24.01 or at.z > 84.01:
			_fail("Collider %s escaped the navigation apron at %s." % [node.name, at])
			return

	var barriers := generated.find_children("RoadEdgeBarrier_*", "StaticBody3D", true, false)
	if barriers.size() != 14:
		_fail("Far road edge needs 14 barriers, found %d." % barriers.size())
		return

	print(
		"Villa exterior smoke test passed: %d logical meshes in %d render nodes, %d colliders, %d Classic64 textures."
		% [logical_meshes, meshes.size() + batches.size(), static_bodies.size(), texture_paths.size()]
	)
	stage.queue_free()
	await process_frame
	quit(0)


func _main_scene_has_exterior() -> bool:
	var packed := load("res://house3/villa_main.tscn") as PackedScene
	if not packed:
		return false
	var state := packed.get_state()
	for index: int in state.get_node_count():
		if state.get_node_name(index) == &"VillaExterior":
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

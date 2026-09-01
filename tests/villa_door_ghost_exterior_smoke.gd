extends SceneTree

## Reproduces the villa-specific failure where the player could see the door
## ghost after deleting a wall mesh, but the baked wall collider still stopped
## the gameplay flashlight ray at 0/5.

const STEP := 0.05


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame: int in 3:
		await process_frame
	await physics_frame

	var cutouts := get_nodes_in_group("villa_entrance_wall_cutouts")
	if cutouts.size() != 12:
		_fail("Expected 12 baked wall modules to be cleared, found %d." % cutouts.size())
		return
	for node: Node in cutouts:
		var wall := node as StaticBody3D
		if wall.visible or wall.collision_layer != 0:
			_fail("Entrance wall %s is still visible or collidable." % wall.name)
			return
		for child: Node in wall.get_children():
			if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
				_fail("Entrance wall %s kept an enabled CollisionShape3D." % wall.name)
				return

	var player := scene.get_node("Player") as CharacterBody3D
	var minigame := player.get_node("DoorGhostMinigame") as DoorGhostMinigame
	var door: DefenseDoor
	for node: Node in get_nodes_in_group("defense_doors"):
		if int(node.get("entrance_id")) == 1:
			door = node as DefenseDoor
			break
	if not player or not minigame or not door:
		_fail("Villa E01, player or DoorGhostMinigame is missing.")
		return

	player.set_physics_process(false)
	minigame.set_process(false)
	# The unit smoke test forces and verifies the 30% dodge path. Keep this
	# courtyard geometry regression deterministic while it checks every hit.
	minigame.dodge_chance = 0.0
	door.set_physics_process(false)
	door.get_node("WarningAudio").set("stream", null)
	door.get_node("StrongAttackAudio").set("stream", null)
	if not door.begin_targeting(true, 30.0):
		_fail("Villa E01 could not enter its stalking phase.")
		return
	door.interact(player)
	if not minigame.is_running():
		_fail("Villa E01 did not start DoorGhostMinigame.")
		return

	var outward: Vector3 = door.get_meta("exterior_outward", Vector3.ZERO)
	var camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	if (-camera.global_basis.z).dot(outward) < 0.999:
		_fail("Villa door camera is not looking outside.")
		return
	for spot: Vector3 in minigame.spots:
		if outward.dot(spot - door.global_position) <= 0.0:
			_fail("Villa door ghost was placed inside the house.")
			return
	var checked_phases: Array[bool] = [false, false, false]
	if not _check_phase_distance(minigame):
		return
	checked_phases[0] = true

	var before := minigame.get_total_hits()
	for _step: int in int(ceil(minigame.flashlight_confirm_time / STEP)) + 4:
		minigame.debug_aim_at_ghost()
		minigame.debug_step(STEP)
		if minigame.get_total_hits() > before:
			break
	if minigame.get_total_hits() != before + 1:
		_fail("Villa wall still blocks a centered flashlight hit on the door ghost.")
		return

	# Finish the real E01 encounter so the medium and far bands are tested
	# against the villa's actual courtyard geometry, not only an empty unit map.
	var step_budget := 1200
	while minigame.get_total_hits() < minigame.get_hits_required() and step_budget > 0:
		step_budget -= 1
		if minigame.state == DoorGhostMinigame.State.RETREAT:
			minigame.debug_look_away()
			minigame.debug_step(STEP)
			continue
		if minigame.state in [DoorGhostMinigame.State.SEARCH, DoorGhostMinigame.State.STARE]:
			var phase := minigame.get_phase_index()
			if not checked_phases[phase]:
				if not _check_phase_distance(minigame):
					return
				checked_phases[phase] = true
			minigame.debug_aim_at_ghost()
			minigame.debug_step(STEP)
			continue
		minigame.debug_step(STEP)
	if minigame.get_total_hits() != minigame.get_hits_required() \
		or checked_phases != [true, true, true]:
		_fail("Villa E01 did not complete all three near/medium/far phases.")
		return

	# The runtime migration above protects the currently baked scene. A fresh
	# procedural build must also omit the wall so pressing Rebuild Preview does
	# not bring the bug back.
	var procedural := VillaHouse.new()
	procedural.detail = VillaHouse.Detail.BLOCKOUT
	procedural.authoring_granularity = VillaHouse.AuthoringGranularity.OPTIMIZED
	procedural.build_furniture = false
	root.add_child(procedural)
	await process_frame
	var blocked_anchors := 0
	for anchor_node: Node in procedural.find_children("*Anchor", "Marker3D", true, false):
		var anchor := anchor_node as Marker3D
		if bool(anchor.get_meta("overhead", false)):
			continue
		if _has_entrance_wall(procedural, anchor):
			blocked_anchors += 1
	if blocked_anchors != 0:
		_fail("A fresh VillaHouse build regenerated %d blocked entrance(s)." % blocked_anchors)
		return

	print("Villa door ghost exterior smoke test passed: camera outside, 12 wall cutouts, all 3 distance phases and all %d flashlight hits registered." % minigame.get_hits_required())
	quit(0)


func _has_entrance_wall(house: VillaHouse, anchor: Marker3D) -> bool:
	var outward := anchor.global_basis.z.normalized()
	var tangent := anchor.global_basis.x.normalized()
	var expected := anchor.global_position \
		+ outward * (1.0 + VillaHouse.WALL_THICKNESS * 0.5) \
		+ Vector3.UP * 1.75
	for node: Node in house.find_children("InteriorWall_*", "StaticBody3D", true, false):
		var delta := (node as Node3D).global_position - expected
		if absf(delta.y) < 0.1 and absf(delta.dot(outward)) < 0.05 \
			and absf(delta.dot(tangent)) < 1.05:
			return true
	return false


func _check_phase_distance(minigame: DoorGhostMinigame) -> bool:
	var phase := minigame.get_phase_index()
	var eye: Vector3 = minigame.call("_view_position", minigame.phase_view_offsets[phase])
	var offset := minigame.ghost.global_position - eye
	offset.y = 0.0
	var required: float = minigame.phase_minimum_spot_distances[phase]
	if offset.length() < required - 0.05:
		_fail(
			"Villa phase %d spawned at %.2f m instead of at least %.2f m."
			% [phase + 1, offset.length(), required]
		)
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

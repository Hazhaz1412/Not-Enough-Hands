extends SceneTree

## ToiletGhost placement smoke test, run against the real House2 bathroom
## rather than a bare test scene - the bug this guards only existed because
## a real room has walls and furniture where a flat test plane has none.
##
## Regression: every spawn used to land inside the floor slab (the toilet
## minigame seats the player ~0.3 m below standing height, so the old
## capsule-derived _floor_y() sat under the real floor), which failed the
## clearance check on all of them and pushed every single spawn through an
## unvalidated fallback that placed the ghost wherever it liked - routinely
## inside a wall, where it could never be seen and so crept to the kill
## unopposed. What is asserted here is the property that was violated: the
## ghost is always in the room with the player, and always visible from the
## seat, at spawn and at every step of its lurch rail.

## House2's Bathroom is centred on (6, 3) and is 6 x 6 m - see house2.gd
## _add_room(). Read as bounds rather than re-derived so a moved room fails
## loudly here instead of silently widening the test.
const ROOM_MIN := Vector2(3.0, 0.0)
const ROOM_MAX := Vector2(9.0, 6.0)
const TRIALS := 120
const ADVANCE_STEP := 0.05


func _initialize() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _in_room(p: Vector3) -> bool:
	return p.x >= ROOM_MIN.x and p.x <= ROOM_MAX.x and p.z >= ROOM_MIN.y and p.z <= ROOM_MAX.y


func _run() -> void:
	var main: Node3D = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame

	var toilet: Node3D = null
	for n in root.find_children("*", "StaticBody3D", true, false):
		if n.name.begins_with("ToiletInteractable"):
			toilet = n
			break
	if not toilet:
		_fail("No ToiletInteractable in House2 to place a ghost around.")
		return
	var ghost: Node = toilet.get_node("ToiletMinigame").toilet_ghost
	var player: CharacterBody3D = root.find_children("Player", "CharacterBody3D", true, false)[0]
	var pivot: Node3D = player.get_node("CameraPivot")
	var camera: Camera3D = pivot.get_node("Camera3D")
	var viewpoint: Marker3D = toilet.get_node("MinigameViewPoint")

	# Seat the player exactly the way ToiletMinigame.start_session() does -
	# including the drop below standing height, which is the condition that
	# broke the old floor derivation.
	player.set_physics_process(false)
	player.global_position = viewpoint.global_position - Vector3(0, pivot.position.y, 0)
	player.rotation = Vector3(0, viewpoint.global_rotation.y, 0)
	pivot.rotation.x = viewpoint.global_rotation.x
	player.accumulated_yaw = 0.0
	await physics_frame

	if not _in_room(player.global_position):
		_fail("The toilet viewpoint is not inside the bathroom bounds this test checks against.")
		return
	# The floor has to be found under the seated player, not under their
	# capsule - this is the specific regression.
	var seated_floor: float = ghost._floor_y(player)
	var capsule_bottom: float = player.global_position.y - 0.875
	if seated_floor < capsule_bottom + 0.1:
		_fail("_floor_y() returned %.3f, at or below the seated capsule bottom %.3f - it is being derived from the capsule again, which puts every spawn inside the floor." % [
			seated_floor, capsule_bottom
		])
		return

	var deferred_spawns := 0
	var min_distance := 1000.0
	var max_distance := 0.0

	for trial in TRIALS:
		ghost.initial_spawn_delay = 0.0
		ghost.arm()
		ghost.update(0.01, player, camera)
		if ghost.phase != ghost.GhostPhase.HOLDING:
			deferred_spawns += 1
			continue

		var spawn_position: Vector3 = ghost.global_position
		if not _in_room(spawn_position):
			_fail("Trial %d spawned the ghost outside the bathroom at %v." % [trial, spawn_position])
			return
		if ghost._is_path_blocked(camera.global_position, spawn_position + Vector3(0, ghost.head_height, 0), player):
			_fail("Trial %d spawned a ghost with no line of sight from the seat (%v) - it could never be caught." % [trial, spawn_position])
			return
		var flat: Vector3 = spawn_position - player.global_position
		flat.y = 0.0
		if flat.length() < ghost.contact_distance:
			_fail("Trial %d spawned the ghost %.2f m away, inside contact_distance %.2f." % [
				trial, flat.length(), ghost.contact_distance
			])
			return
		# Every appearance has to be in a rear diagonal: outside the camera's
		# FOV and more than 90 degrees from the seated player's facing.
		var seat_forward: Vector3 = -camera.global_basis.z
		seat_forward.y = 0.0
		var offset_angle := rad_to_deg(seat_forward.normalized().angle_to(flat.normalized()))
		if offset_angle < ghost.min_spawn_offset_angle - 1.0:
			_fail("Trial %d spawned the ghost only %.1f degrees off the seat facing, inside the %.1f-degree rear minimum." % [
				trial, offset_angle, ghost.min_spawn_offset_angle
			])
			return
		min_distance = minf(min_distance, flat.length())
		max_distance = maxf(max_distance, flat.length())

		# Walk the whole lurch rail: it must never leave the room either, and
		# never lose line of sight - the rail sweeps toward the blind edge and
		# would otherwise slide straight through a side wall.
		var advance := 0.0
		while advance <= 1.0:
			ghost.advance = advance
			ghost._apply_advance(player)
			var rail_position: Vector3 = ghost.global_position
			if not _in_room(rail_position):
				_fail("Trial %d let the rail leave the bathroom at advance %.2f (%v)." % [
					trial, advance, rail_position
				])
				return
			if ghost._is_path_blocked(camera.global_position, rail_position + Vector3(0, ghost.head_height, 0), player):
				_fail("Trial %d let the rail move the ghost out of sight at advance %.2f (%v)." % [
					trial, advance, rail_position
				])
				return
			advance += ADVANCE_STEP
		ghost.reset()

	# Deferring is the correct answer when a room genuinely cannot host the
	# ghost, but a normal bathroom must not be hitting it - if it is, the
	# placement rules have become too strict to ever put a ghost anywhere.
	if deferred_spawns > TRIALS / 10:
		_fail("%d of %d spawns found nowhere to go in an ordinary bathroom - placement is too strict." % [
			deferred_spawns, TRIALS
		])
		return

	print("Toilet ghost placement smoke test passed: %d/%d spawned in-room and visible, %.2f-%.2f m out, %d deferred." % [
		TRIALS - deferred_spawns, TRIALS, min_distance, max_distance, deferred_spawns
	])
	quit()

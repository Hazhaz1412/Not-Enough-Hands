extends SceneTree

const GHOST_SCENE := preload("res://ghosts/darkness_ghost.tscn")
const GHOST_POSITION := Vector3(0.0, 1.0, -5.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ghost := GHOST_SCENE.instantiate() as DarknessGhost
	world.add_child(ghost)
	ghost.global_position = GHOST_POSITION
	ghost.auto_manifest = false
	ghost._set_manifested(true)
	ghost.encounter_phase = DarknessGhost.EncounterPhase.CHASING
	ghost.velocity = Vector3(2.6, 0.0, 0.0)
	ghost._update_footsteps(0.1)
	var footstep_audio := ghost.get_node_or_null("FootstepAudio") as AudioStreamPlayer3D
	if not footstep_audio or not footstep_audio.playing:
		_fail("A moving Darkness Ghost did not play a spatial footstep.")
		return
	ghost.velocity = Vector3.ZERO
	ghost._update_footsteps(0.1)
	if footstep_audio.playing:
		_fail("Darkness Ghost footsteps continued after it stopped moving.")
		return

	var flashlights: Array[SpotLight3D] = []
	for index: int in 3:
		flashlights.append(_add_player_with_flashlight(world, index))
	await physics_frame

	for count: int in 4:
		for index: int in flashlights.size():
			flashlights[index].visible = index < count
		await process_frame
		var expected_speed := maxf(
			ghost.minimum_illuminated_speed,
			ghost.darkness_speed - count * ghost.flashlight_speed_penalty
		)
		if not is_equal_approx(ghost._chase_speed_at(GHOST_POSITION), expected_speed):
			_fail("Flashlight slowdown did not stack once per illuminating player.")
			return

	ghost._update_light_exposure(4.9)
	if not ghost.is_manifested() or ghost._flashlight_player_count != 3:
		_fail("Three flashlights caused an early retreat or were not counted distinctly.")
		return
	ghost._update_light_exposure(0.11)
	if ghost.is_manifested() or ghost.is_dead():
		_fail("Three continuous flashlights did not retreat the ghost without killing it.")
		return

	ghost._set_manifested(true)
	ghost.encounter_phase = DarknessGhost.EncounterPhase.CHASING
	ghost._update_light_exposure(2.6)
	flashlights[0].visible = false
	await process_frame
	ghost._update_light_exposure(0.1)
	flashlights[0].visible = true
	await process_frame
	ghost._update_light_exposure(2.6)
	if not ghost.is_manifested():
		_fail("Flashlight retreat timer did not reset when fewer than three beams remained.")
		return

	for flashlight: SpotLight3D in flashlights:
		flashlight.visible = false
	await process_frame

	# A hunt that only ends on a kill, three flashlights or a light death is a
	# hunt that usually never ends - which left a whole night holding exactly one
	# encounter. It now gives up on its own, and that is what paces the next one.
	ghost._hunt_time_left = ghost.hunt_duration
	ghost._process(ghost.hunt_duration - 0.1)
	if not ghost.is_manifested():
		_fail("Darkness Ghost abandoned its hunt before hunt_duration elapsed.")
		return
	ghost._process(0.2)
	if ghost.is_manifested() or ghost.is_dead():
		_fail("Darkness Ghost did not end its hunt after hunt_duration and retreat.")
		return
	if not is_equal_approx(ghost._next_manifest_in, ghost.manifest_interval):
		_fail("A timed-out hunt did not schedule the next manifest.")
		return
	ghost._set_manifested(true)
	ghost.encounter_phase = DarknessGhost.EncounterPhase.CHASING

	var room_light := OmniLight3D.new()
	room_light.omni_range = 8.0
	room_light.light_energy = 1.0
	room_light.add_to_group(&"local_light_sources")
	world.add_child(room_light)
	room_light.global_position = GHOST_POSITION + Vector3.UP
	await process_frame
	ghost._update_light_exposure(2.9)
	if ghost.is_dead():
		_fail("Environmental light killed the ghost before three continuous seconds.")
		return
	room_light.visible = false
	await process_frame
	ghost._update_light_exposure(0.1)
	room_light.visible = true
	await process_frame
	ghost._update_light_exposure(3.01)
	if not ghost.is_dead() or ghost.is_manifested() or ghost.auto_manifest:
		_fail("Three continuous seconds of environmental light did not permanently kill the ghost.")
		return

	print("Darkness light response smoke test passed: nerfed chase speeds, spatial footsteps, stacked per-flashlight slowdown, 3-player 5s retreat, continuous 3s environmental-light death.")
	quit()


func _add_player_with_flashlight(parent: Node3D, index: int) -> SpotLight3D:
	var player := Node3D.new()
	player.name = "Player%d" % index
	player.add_to_group(&"players")
	parent.add_child(player)
	player.global_position = Vector3(float(index - 1) * 0.5, 1.0, 0.0)
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	player.add_child(pivot)
	var camera := Node3D.new()
	camera.name = "Camera3D"
	pivot.add_child(camera)
	var flashlight := SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.spot_range = 15.0
	flashlight.spot_angle = 40.0
	flashlight.light_energy = 2.4
	flashlight.add_to_group(&"local_light_sources")
	camera.add_child(flashlight)
	return flashlight


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

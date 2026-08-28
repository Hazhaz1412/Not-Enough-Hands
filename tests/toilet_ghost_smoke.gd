extends SceneTree

## ToiletGhost smoke test. Drives the ghost's arm()/update()/reset() API
## directly - the same functions ToiletMinigame calls from
## start_session()/_process()/_cleanup() - rather than waiting on real
## timing, matching this suite's existing convention (see
## tests/toilet_minigame_smoke.gd) of calling internal methods directly for
## determinism instead of simulating real input/time.
##
## The contract under test is the lurch cycle (see minigames/toilet_ghost.gd's
## class doc): the ghost stands still, lurches closer on its own clock, and
## what a sighting is worth depends entirely on which of the two it was doing.
## Every assertion reads the ghost's own exports rather than hardcoding tuning
## numbers, except the explicit spec block at the top - a regressed default
## would otherwise pass everything else silently.

const STEP_DELTA := 0.05
## Distance ahead of the camera used to park the ghost's head for the
## deterministic "is being looked at" cases. Kept well short of the toilet
## (1.5 m ahead, 0.5x0.8x0.7 collision box) so the occlusion raycast in
## _camera_can_see_point() doesn't clip its geometry.
const LOOK_DISTANCE := 0.8


func _initialize() -> void:
	_run.call_deferred()


## Parks the ghost so its head - the point every sighting is checked against -
## sits directly in front of the camera. Re-applied before every update() in
## the "being watched" cases, because a lurch moves the ghost back onto its
## rail at the end of the frame; the sighting check runs first, so the forced
## position is what that frame observes.
func _park_in_view(ghost: Node, camera: Camera3D) -> void:
	var head_target: Vector3 = camera.global_position + (-camera.global_basis.z).normalized() * LOOK_DISTANCE
	ghost.global_position = head_target - Vector3(0, ghost.visual.position.y + ghost.head_height, 0)


## The opposite: parks the ghost's head behind the camera, so the player is
## unambiguously not looking at it whatever the rail would otherwise do.
func _park_out_of_view(ghost: Node, camera: Camera3D) -> void:
	var head_target: Vector3 = camera.global_position + camera.global_basis.z.normalized() * LOOK_DISTANCE
	ghost.global_position = head_target - Vector3(0, ghost.visual.position.y + ghost.head_height, 0)


## Runs updates with the ghost held out of sight until it leaves `from_phase`
## or `max_frames` is spent. Returns the frames used.
func _ignore_until_phase_change(ghost: Node, player: Node3D, camera: Camera3D, from_phase: int, max_frames: int) -> int:
	for i in max_frames:
		_park_out_of_view(ghost, camera)
		ghost.update(STEP_DELTA, player, camera)
		if ghost.phase != from_phase:
			return i + 1
	return max_frames


## Runs `frames` updates with the ghost held out of sight.
func _ignore_for(ghost: Node, player: Node3D, camera: Camera3D, frames: int) -> void:
	for i in frames:
		_park_out_of_view(ghost, camera)
		ghost.update(STEP_DELTA, player, camera)


## Runs `frames` updates with the ghost held in plain view.
func _watch_for(ghost: Node, player: Node3D, camera: Camera3D, frames: int) -> void:
	for i in frames:
		_park_in_view(ghost, camera)
		ghost.update(STEP_DELTA, player, camera)


## Drives the ghost from HOLDING through one complete lurch without ever
## looking at it, leaving it standing still again one step further in.
func _complete_one_lurch(ghost: Node, player: Node3D, camera: Camera3D) -> bool:
	_ignore_until_phase_change(ghost, player, camera, ghost.GhostPhase.HOLDING, 400)
	if ghost.phase != ghost.GhostPhase.MOVING:
		return false
	_ignore_until_phase_change(ghost, player, camera, ghost.GhostPhase.MOVING, 400)
	return true


func _run() -> void:
	var packed_scene := load("res://tests/player_test.tscn") as PackedScene
	var test_scene := packed_scene.instantiate()
	root.add_child(test_scene)

	var player := test_scene.get_node("Player") as CharacterBody3D
	var toilet := test_scene.get_node("TestToilet")
	var minigame: Node = toilet.get_node("ToiletMinigame")
	var ghost: Node = minigame.toilet_ghost
	if not ghost:
		push_error("ToiletMinigame has no ToiletGhost child to test.")
		quit(1)
		return
	var camera: Camera3D = player.get_node("CameraPivot/Camera3D")

	player.global_position = Vector3(12.0, 1.0, 2.0)
	player.global_rotation = Vector3.ZERO
	toilet.global_position = Vector3(12.0, 1.22, 0.5)
	player.bladder.bladder_fill_rate = 0.0

	await physics_frame
	await physics_frame

	# --- Configured values match the required spec exactly. Every other check
	# reads these exports dynamically, so a regressed default would otherwise
	# pass every assertion silently. ---
	var spec := {
		"initial_spawn_delay": 4.0,
		"min_respawn_delay": 7.0,
		"max_respawn_delay": 10.0,
		"hold_duration": 3.0,
		"move_duration": 0.7,
		"stare_tolerance": 3.0,
		"contact_distance": 1.15,
		"spawn_yaw_range": 165.0,
		"min_spawn_offset_angle": 120.0,
	}
	for key: String in spec:
		if not is_equal_approx(float(ghost.get(key)), float(spec[key])):
			push_error("%s is %.3f, not the required %.3f." % [key, float(ghost.get(key)), float(spec[key])])
			quit(1)
			return
	if ghost.spots_to_banish != 3:
		push_error("spots_to_banish is %d, not the required 3." % ghost.spots_to_banish)
		quit(1)
		return
	if ghost.steps_to_reach != 5:
		push_error("steps_to_reach is %d, not the required 5." % ghost.steps_to_reach)
		quit(1)
		return
	# A spawn has to land somewhere the player can physically turn to, behind
	# the seat, and alternate rear shoulders after every appearance.
	if ghost.spawn_yaw_range > minigame.max_camera_rotation_y:
		push_error("spawn_yaw_range (%.1f) exceeds the minigame's camera yaw clamp (%.1f) - a spawn could be unreachable." % [
			ghost.spawn_yaw_range, minigame.max_camera_rotation_y
		])
		quit(1)
		return
	if ghost.min_spawn_offset_angle >= ghost.spawn_yaw_range:
		push_error("min_spawn_offset_angle (%.1f) leaves no arc to spawn in below spawn_yaw_range (%.1f)." % [
			ghost.min_spawn_offset_angle, ghost.spawn_yaw_range
		])
		quit(1)
		return
	ghost.arm()
	var previous_angle := 0.0
	for spawn_index in 8:
		var spawn_pick: Dictionary = ghost._next_zone_angle()
		var spawn_angle: float = spawn_pick["angle"]
		if absf(spawn_angle) <= 90.0:
			push_error("Toilet Ghost spawned at %.1f degrees, which is not behind the player." % spawn_angle)
			quit(1)
			return
		if spawn_index > 0 and signf(spawn_angle) == signf(previous_angle):
			push_error("Toilet Ghost repeated the same rear shoulder (%.1f then %.1f) instead of forcing a turn back." % [previous_angle, spawn_angle])
			quit(1)
			return
		ghost._record_spawn(int(spawn_pick["zone"]), spawn_angle)
		previous_angle = spawn_angle
	ghost.reset()
	# The lurch has to be catchable at the rate the minigame actually ticks.
	if ghost.move_duration < STEP_DELTA * 3.0:
		push_error("move_duration %.2fs is too short to ever be caught in the act." % ghost.move_duration)
		quit(1)
		return
	# A lurch must never announce itself. It is the moving silhouette, not a
	# sound cue, that creates the player's chance to catch the ghost.
	ghost.teleport_audio.stop()
	ghost._begin_move(1.0, false)
	if ghost.teleport_audio.playing:
		push_error("Toilet Ghost lurch played an audio cue, making the event free to win by sound.")
		quit(1)
		return
	ghost.reset()

	# --- Initial delay, then it arrives standing still. ---
	ghost.arm()
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("arm() did not put the ghost into WAITING.")
		quit(1)
		return
	var elapsed := 0.0
	while elapsed < ghost.initial_spawn_delay - STEP_DELTA:
		ghost.update(STEP_DELTA, player, camera)
		elapsed += STEP_DELTA
		if ghost.phase != ghost.GhostPhase.WAITING:
			push_error("Ghost spawned after %.2fs, before its %.2fs initial delay." % [elapsed, ghost.initial_spawn_delay])
			quit(1)
			return
	ghost.update(STEP_DELTA * 2.0, player, camera)
	if ghost.phase != ghost.GhostPhase.HOLDING:
		push_error("Ghost did not arrive standing still (phase=%d)." % ghost.phase)
		quit(1)
		return
	if not is_zero_approx(ghost.advance) or ghost.step_index != 0 or ghost.spot_count != 0:
		push_error("A fresh ghost should start at advance 0 with no steps or spots (%.2f/%d/%d)." % [
			ghost.advance, ghost.step_index, ghost.spot_count
		])
		quit(1)
		return
	if not ghost.visual.visible:
		push_error("Ghost is holding but its visual is hidden.")
		quit(1)
		return
	var flashlight := player.get_node("CameraPivot/Camera3D/Flashlight") as SpotLight3D
	if not is_equal_approx(
			flashlight.light_energy,
			player._flashlight_base_energy * player.toilet_ghost_flashlight_energy_multiplier
	) or not is_equal_approx(
			flashlight.spot_range,
			player._flashlight_base_range * player.toilet_ghost_flashlight_range_multiplier
	):
		push_error("A manifested Toilet Ghost did not narrow and dim the player's flashlight.")
		quit(1)
		return
	var overlay_material := player.horror_overlay_rect.material as ShaderMaterial
	if not is_equal_approx(float(overlay_material.get_shader_parameter("toilet_presence")), 1.0):
		push_error("A manifested Toilet Ghost did not enable its reduced-vision overlay.")
		quit(1)
		return
	# It starts at the far end of the room it could find, not on top of you.
	var spawn_offset: Vector3 = ghost.global_position - player.global_position
	spawn_offset.y = 0.0
	if spawn_offset.length() < ghost.contact_distance:
		push_error("Ghost arrived %.2f m away, inside contact_distance %.2f." % [
			spawn_offset.length(), ghost.contact_distance
		])
		quit(1)
		return
	var facing_error := _ghost_facing_error(ghost, player)
	if facing_error != "":
		push_error(facing_error)
		quit(1)
		return

	# --- Seen while standing still: worth exactly ONE tally, and only one,
	# no matter how long or how often the player looks. This is the rule that
	# stops "hold the camera on it until it leaves" from being a strategy. ---
	_watch_for(ghost, player, camera, 1)
	if ghost.spot_count != 1:
		push_error("Seeing the standing ghost banked %d spots, expected 1." % ghost.spot_count)
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.HOLDING:
		push_error("A single sighting of a standing ghost resolved it (phase=%d) - only the last tally should." % ghost.phase)
		quit(1)
		return
	# Keep staring, but stay under stare_tolerance: still exactly one, and it
	# must NOT take its ordinary timed lurch while being watched - if the hold
	# clock ran under observation, a staring player would be handed a free
	# mid-lurch catch and staring would be the dominant strategy.
	var stare_frames := int(floor(ghost.stare_tolerance / STEP_DELTA)) - 6
	_watch_for(ghost, player, camera, stare_frames)
	if ghost.spot_count != 1:
		push_error("Staring at the same standing ghost banked %d spots - a lurch cycle is worth one, however long the look." % ghost.spot_count)
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.HOLDING:
		push_error("The ghost left HOLDING (phase=%d) while under continuous observation and still inside stare_tolerance." % ghost.phase)
		quit(1)
		return
	# ...and looking away and back does not bank another either.
	_ignore_for(ghost, player, camera, 3)
	_watch_for(ghost, player, camera, 2)
	if ghost.spot_count != 1:
		push_error("Looking away and back at the same standing ghost banked %d spots, expected still 1." % ghost.spot_count)
		quit(1)
		return

	# --- Staring past stare_tolerance is punished with a long lunge. The
	# budget accumulates across separate looks and never decays, which is why
	# the frames above already spent most of it. ---
	_watch_for(ghost, player, camera, 10)
	if ghost.phase != ghost.GhostPhase.MOVING:
		push_error("Watching for over stare_tolerance (%.1fs) did not provoke a lunge (phase=%d, stare=%.2f)." % [
			ghost.stare_tolerance, ghost.phase, ghost._stare_time
		])
		quit(1)
		return
	if not ghost._move_is_punishment:
		push_error("The stare provoked an ordinary lurch, not a punishment lunge.")
		quit(1)
		return
	var punished_target: float = ghost._move_to
	var normal_step: float = 1.0 / float(ghost.steps_to_reach)
	if punished_target < normal_step * ghost.stare_step_multiplier - 0.001:
		push_error("The stare punishment advanced to %.3f, short of a %.1fx stride (%.3f)." % [
			punished_target, ghost.stare_step_multiplier, normal_step * ghost.stare_step_multiplier
		])
		quit(1)
		return

	# --- A punishment lunge is NOT catchable. Otherwise staring would still
	# win, just from the other direction: stare, get lunged at, catch the
	# lunge for free. Watch it the whole way through and it must survive. ---
	var spots_before_lunge: int = ghost.spot_count
	var lunge_guard := 0
	while ghost.phase == ghost.GhostPhase.MOVING and lunge_guard < 400:
		_park_in_view(ghost, camera)
		ghost.update(STEP_DELTA, player, camera)
		lunge_guard += 1
	if ghost.phase == ghost.GhostPhase.STUTTER:
		push_error("Watching the punishment lunge caught it - staring is a winning strategy again.")
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.HOLDING:
		push_error("The punishment lunge did not settle back into HOLDING (phase=%d)." % ghost.phase)
		quit(1)
		return
	# ...and it does not hand back a fresh tally either.
	if ghost._spotted_this_cycle == false and ghost.spot_count == spots_before_lunge:
		var re_armed := true
		_watch_for(ghost, player, camera, 1)
		if ghost.spot_count > spots_before_lunge:
			push_error("A punishment lunge re-armed the tally - a staring player could bank spots off their own punishment.")
			quit(1)
			return

	# --- Caught mid-lurch: gone at once, whatever the tally says. This is the
	# skill play - the reward for timing a look rather than repeating one. ---
	if ghost.spot_count >= ghost.spots_to_banish - 1:
		ghost.spot_count = 0
		ghost._spotted_this_cycle = true
	_ignore_until_phase_change(ghost, player, camera, ghost.GhostPhase.HOLDING, 400)
	if ghost.phase != ghost.GhostPhase.MOVING:
		push_error("Could not reach an ordinary lurch for the mid-lurch catch (phase=%d)." % ghost.phase)
		quit(1)
		return
	if ghost._move_is_punishment:
		push_error("Reached a punishment lunge where an ordinary lurch was expected.")
		quit(1)
		return
	_watch_for(ghost, player, camera, 1)
	if ghost.phase != ghost.GhostPhase.STUTTER:
		push_error("Seeing the ghost mid-lurch produced phase %d, not the STUTTER catch." % ghost.phase)
		quit(1)
		return
	if not ghost.visual.visible:
		push_error("The ghost vanished instantly on being caught - the stutter beat exists so it does not pop.")
		quit(1)
		return

	# --- The catch resolves: stutter, vanish, forced blink, re-arm. ---
	var seen_count := [0]
	ghost.ghost_seen.connect(func(): seen_count[0] += 1)
	var guard := 0
	while ghost.phase == ghost.GhostPhase.STUTTER and guard < 400:
		ghost.update(STEP_DELTA, player, camera)
		guard += 1
	if ghost.phase != ghost.GhostPhase.DISAPPEARING:
		push_error("The stutter did not resolve into DISAPPEARING (phase=%d)." % ghost.phase)
		quit(1)
		return
	if player.forced_blink_remaining <= 0.0:
		push_error("Catching the ghost did not force the player's blink.")
		quit(1)
		return
	while ghost.phase == ghost.GhostPhase.DISAPPEARING and guard < 800:
		ghost.update(STEP_DELTA, player, camera)
		guard += 1
	if seen_count[0] != 1:
		push_error("ghost_seen fired %d times across one catch, expected exactly 1." % seen_count[0])
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("A caught ghost did not re-arm the spawn loop (phase=%d)." % ghost.phase)
		quit(1)
		return
	if ghost._spawn_timer < ghost.min_respawn_delay - 0.001 or ghost._spawn_timer > ghost.max_respawn_delay + 0.001:
		push_error("Respawn delay %.2fs is outside the configured %.1f-%.1fs window." % [
			ghost._spawn_timer, ghost.min_respawn_delay, ghost.max_respawn_delay
		])
		quit(1)
		return
	if player.forced_blink_remaining > 0.0:
		push_error("The forced blink was never ended - the player's eyes are stranded shut.")
		quit(1)
		return
	if player.threat_sources.has(ghost.THREAT_SOURCE):
		push_error("A caught ghost left its threat entry behind - the overlay would stay lit.")
		quit(1)
		return

	# --- Three tallies, one per lurch, and the third banishes it. This is the
	# patient route: it works, it just costs three well-spent looks instead of
	# one well-timed one. Each tally has to come from a SEPARATE lurch cycle -
	# that is the whole point of the once-per-cycle guard. ---
	ghost.initial_spawn_delay = 0.0
	ghost.arm()
	ghost.update(0.01, player, camera)
	if ghost.phase != ghost.GhostPhase.HOLDING:
		push_error("Ghost did not arrive for the three-tally case.")
		quit(1)
		return
	for expected_spots in [1, 2]:
		_watch_for(ghost, player, camera, 1)
		if ghost.spot_count != expected_spots:
			push_error("Expected %d tallies at this point, have %d." % [expected_spots, ghost.spot_count])
			quit(1)
			return
		if ghost.phase != ghost.GhostPhase.HOLDING:
			push_error("Tally %d resolved the ghost early (phase=%d)." % [expected_spots, ghost.phase])
			quit(1)
			return
		if not _complete_one_lurch(ghost, player, camera):
			push_error("Could not drive a clean lurch after tally %d (phase=%d)." % [expected_spots, ghost.phase])
			quit(1)
			return
		if ghost._spotted_this_cycle:
			push_error("A completed lurch did not re-arm the tally for the next cycle.")
			quit(1)
			return
	var steps_before_banish: int = ghost.step_index
	_watch_for(ghost, player, camera, 1)
	if ghost.spot_count != ghost.spots_to_banish:
		push_error("Expected the tally to reach %d, got %d." % [ghost.spots_to_banish, ghost.spot_count])
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.STUTTER:
		push_error("The %drd tally on a STANDING ghost did not banish it (phase=%d) - the patient route is broken." % [
			ghost.spots_to_banish, ghost.phase
		])
		quit(1)
		return
	if steps_before_banish < 2:
		push_error("The ghost only took %d lurches to give up three tallies - the once-per-cycle guard is not holding." % steps_before_banish)
		quit(1)
		return
	ghost.reset()

	# --- Lurches close the distance, monotonically, and never overshoot the
	# player. Driven on an explicit rail so this measures the mapping from
	# advance to position, not whatever bearing the spawn roll picked. ---
	ghost.initial_spawn_delay = 0.0
	ghost.arm()
	ghost.update(0.01, player, camera)
	ghost._rail_origin = player.global_position
	ghost._rail_eye = camera.global_position
	ghost._rail_floor_y = ghost._floor_y(player)
	# Angled away from the test scene's own toilet: a rail pointed straight
	# down -Z runs the line of sight through it, and _apply_advance()
	# correctly refuses to move the ghost somewhere the player cannot see.
	ghost._rail_direction = Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(60.0))
	ghost._rail_far_distance = 3.0

	ghost.advance = 0.0
	ghost._apply_advance(player)
	var far_offset: Vector3 = ghost.global_position - player.global_position
	far_offset.y = 0.0
	if absf(far_offset.length() - ghost._rail_far_distance) > 0.05:
		push_error("At advance 0 the ghost sits %.2f m out, not the rail's far end %.2f m." % [
			far_offset.length(), ghost._rail_far_distance
		])
		quit(1)
		return
	var previous_distance: float = far_offset.length()
	var sweep := 0.05
	while sweep <= 1.0:
		ghost.advance = sweep
		ghost._apply_advance(player)
		var step_offset: Vector3 = ghost.global_position - player.global_position
		step_offset.y = 0.0
		if step_offset.length() > previous_distance + 0.01:
			push_error("Advance %.2f moved the ghost outward (%.2f m from %.2f m)." % [
				sweep, step_offset.length(), previous_distance
			])
			quit(1)
			return
		previous_distance = step_offset.length()
		sweep += 0.05
	# Explicitly, rather than trusting the sweep to land on 1.0: twenty
	# additions of 0.05 stop fractionally short of it.
	ghost.advance = 1.0
	ghost._apply_advance(player)
	var contact_offset: Vector3 = ghost.global_position - player.global_position
	contact_offset.y = 0.0
	previous_distance = contact_offset.length()
	if absf(previous_distance - ghost.contact_distance) > 0.05:
		push_error("At advance 1 the ghost is %.2f m away, not contact_distance %.2f m." % [
			previous_distance, ghost.contact_distance
		])
		quit(1)
		return

	# --- The looming axis, and with it the small-room contract. Advance the
	# room had no space to express as movement is spent on lean/lift instead,
	# so a ghost pinned against a wall still escalates. Asserted directly on
	# _apply_lean() because the alternative - building a sealed box around the
	# ghost mid-test - would prove the same arithmetic far less legibly. ---
	ghost.advance = 0.0
	ghost._expressed_advance = 0.0
	ghost._apply_lean()
	if not is_zero_approx(ghost.visual.rotation.x) or not is_equal_approx(ghost.visual.position.y, ghost._visual_base_y):
		push_error("A ghost at advance 0 is already leaning (rot.x=%.3f, y=%.3f)." % [
			ghost.visual.rotation.x, ghost.visual.position.y
		])
		quit(1)
		return
	ghost.advance = 1.0
	ghost._expressed_advance = 1.0
	ghost._apply_lean()
	if not is_equal_approx(ghost.visual.rotation.x, -deg_to_rad(ghost.lean_max_degrees)):
		push_error("A fully-advanced ghost leans %.1f degrees, not lean_max_degrees %.1f." % [
			rad_to_deg(-ghost.visual.rotation.x), ghost.lean_max_degrees
		])
		quit(1)
		return
	# The cramped case: half the advance, none of it expressible as movement.
	# It must read as far along as the ghost that had the floor to walk it.
	ghost.advance = 0.5
	ghost._expressed_advance = 0.0
	ghost._apply_lean()
	if not is_equal_approx(ghost.visual.rotation.x, -deg_to_rad(ghost.lean_max_degrees)):
		push_error("A ghost with 0.5 blocked advance leans only %.1f degrees - blocked advance is not reaching the looming axis." % rad_to_deg(-ghost.visual.rotation.x))
		quit(1)
		return
	ghost.reset()

	# --- Noise brings the next lurch forward, but can never interrupt one
	# already under way - that would rob the player of the window they are
	# playing for. Asserted through the real ToiletMinigame call group. ---
	if not ghost.is_in_group(&"toilet_ghosts"):
		push_error("Ghost is not in the toilet_ghosts group - danger noise would never reach it.")
		quit(1)
		return
	ghost.initial_spawn_delay = 0.0
	ghost.arm()
	ghost.update(0.01, player, camera)
	minigame.player = player
	var hold_before: float = ghost._hold_timer
	minigame._emit_danger_noise()
	var expected_hold: float = maxf(
		hold_before - ghost.hold_duration * ghost.noise_hold_penalty * minigame.danger_noise_loudness,
		0.0
	)
	if not is_equal_approx(snappedf(ghost._hold_timer, 0.0001), snappedf(expected_hold, 0.0001)):
		push_error("Danger noise left the hold at %.4f, expected %.4f." % [ghost._hold_timer, expected_hold])
		quit(1)
		return
	ghost.phase = ghost.GhostPhase.MOVING
	var mid_lurch_hold: float = ghost._hold_timer
	minigame._emit_danger_noise()
	if not is_equal_approx(ghost._hold_timer, mid_lurch_hold):
		push_error("Danger noise altered a lurch already in progress.")
		quit(1)
		return
	ghost.reset()

	# --- Cleanup: reset() is unconditional, from any phase. The mid-blink case
	# is the critical one - force_blink_now() has fired and nothing else is
	# left to reopen the eyes once the ghost stops being driven. ---
	ghost.initial_spawn_delay = 0.0
	ghost.arm()
	ghost.update(0.01, player, camera)
	ghost.spot_count = ghost.spots_to_banish - 1
	_watch_for(ghost, player, camera, 1)
	var to_blink := 0
	while ghost.phase != ghost.GhostPhase.DISAPPEARING and to_blink < 400:
		ghost.update(STEP_DELTA, player, camera)
		to_blink += 1
	if ghost.phase != ghost.GhostPhase.DISAPPEARING:
		push_error("Could not drive the ghost into DISAPPEARING for the mid-blink cleanup case.")
		quit(1)
		return
	ghost.reset()
	if ghost.phase != ghost.GhostPhase.IDLE:
		push_error("reset() left the ghost in phase %d." % ghost.phase)
		quit(1)
		return
	if player.forced_blink_remaining > 0.0:
		push_error("Exiting mid-blink stranded the player's eyes shut.")
		quit(1)
		return
	if player.threat_sources.has(ghost.THREAT_SOURCE):
		push_error("reset() left a threat entry behind - the overlay would stay lit after leaving the toilet.")
		quit(1)
		return
	if ghost.visual.visible or ghost.teleport_audio.playing:
		push_error("reset() left the ghost visible or still sounding.")
		quit(1)
		return
	var reset_flashlight := player.get_node("CameraPivot/Camera3D/Flashlight") as SpotLight3D
	if not is_equal_approx(reset_flashlight.light_energy, player._flashlight_base_energy) \
			or not is_equal_approx(reset_flashlight.spot_range, player._flashlight_base_range):
		push_error("reset() did not restore the player's flashlight after the Toilet Ghost vanished.")
		quit(1)
		return
	if not is_zero_approx(ghost.visual.rotation.x) or not ghost.visual.position.is_equal_approx(Vector3(0, ghost._visual_base_y, 0)):
		push_error("reset() left the ghost mid-lean or mid-stutter, so the next arrival would start askew.")
		quit(1)
		return

	# --- Failure: steps_to_reach lurches with the player never once looking
	# fires the caught signal and cleans up, but is no longer lethal. The owning
	# minigame converts this into a temporary player stun. ---
	var timed_out := [0]
	ghost.ghost_timed_out.connect(func(): timed_out[0] += 1)
	ghost.initial_spawn_delay = 0.0
	ghost.arm()
	ghost.update(0.01, player, camera)
	if ghost.phase != ghost.GhostPhase.HOLDING:
		push_error("Ghost did not arrive for the failure case.")
		quit(1)
		return
	var lurches := 0
	while lurches < ghost.steps_to_reach and player.is_alive:
		if not _complete_one_lurch(ghost, player, camera):
			break
		lurches += 1
	if timed_out[0] != 1:
		push_error("ghost_timed_out fired %d times after %d lurches, expected exactly 1." % [timed_out[0], lurches])
		quit(1)
		return
	if not player.is_alive:
		push_error("The Toilet Ghost killed the player instead of leaving them stunned.")
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.IDLE or ghost.visual.visible:
		push_error("The ghost did not clean itself up after catching the player.")
		quit(1)
		return
	if player.threat_sources.has(ghost.THREAT_SOURCE):
		push_error("The catch left a threat entry behind.")
		quit(1)
		return
	if ghost.teleport_audio.playing:
		push_error("Teleport audio kept playing after the catch.")
		quit(1)
		return

	print("Toilet ghost smoke test passed.")
	quit()


## Returns "" if the ghost's horizontal forward points at the player (within
## a tight tolerance) with no unwanted pitch/roll introduced, otherwise a
## message describing what's wrong. The lean and the stutter both live on the
## Visual child, not the root, precisely so this stays true throughout.
func _ghost_facing_error(ghost: Node, player: Node3D) -> String:
	var ghost_position: Vector3 = ghost.global_position
	var to_player: Vector3 = player.global_position - ghost_position
	to_player.y = 0.0
	var ghost_basis: Basis = ghost.global_transform.basis
	var ghost_forward: Vector3 = -ghost_basis.z
	ghost_forward.y = 0.0
	var angle_deg := rad_to_deg(ghost_forward.normalized().angle_to(to_player.normalized()))
	if angle_deg > 1.0:
		return "Ghost is not facing the player (angle=%.1f deg)." % angle_deg
	if not is_zero_approx(ghost.rotation.x) or not is_zero_approx(ghost.rotation.z):
		return "Facing the player introduced unwanted pitch/roll instead of staying horizontal-only."
	return ""

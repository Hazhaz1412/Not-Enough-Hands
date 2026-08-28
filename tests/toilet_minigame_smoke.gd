extends SceneTree

## Toilet + bathroom minigame smoke test for the ported (from
## feat/game-character-hoang) nozzle-balance minigame. ToiletMinigame is now
## owned per-toilet (a child of TestToilet), not per-player, so it's fetched
## via toilet.get_node("ToiletMinigame") rather than a fixed player property.
## Interaction goes through the real pipeline (raycast ->
## get_interaction_target -> Interactable -> interact() -> Toilet ->
## Player.start_toilet_minigame); the balance/drain step is driven
## deterministically by calling the minigame's own per-frame helper
## functions directly (with oscillation zeroed out) instead of waiting on
## real oscillation timing. succeed()/cancel() use real Godot timers
## internally, so this test does actually wait on them (~1-2s of wall time).

const STEP_DELTA := 0.05


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://tests/player_test.tscn") as PackedScene
	var test_scene := packed_scene.instantiate()
	root.add_child(test_scene)

	var player := test_scene.get_node("Player") as CharacterBody3D
	var toilet := test_scene.get_node("TestToilet")
	var minigame: Node = toilet.get_node("ToiletMinigame")

	var player_scene := load("res://player/player.tscn") as PackedScene
	var player_b := player_scene.instantiate()
	root.add_child(player_b)
	player_b.global_position = Vector3(50.0, 1.0, 50.0)
	var full_fill_time: float = player.bladder.bladder_max / player.bladder.bladder_fill_rate
	var full_drain_time: float = player.bladder.bladder_max / minigame.bladder_drain_rate
	if not is_equal_approx(minigame.pee_ramp_duration, 1.5):
		push_error("Every toilet entry must rebuild flow over 1.5 seconds.")
		quit(1)
		return
	if not is_equal_approx(full_fill_time, full_drain_time * 5.0):
		push_error(
			"A full bladder should take five times longer to fill than to drain "
			+ "(fill=%.2fs, drain=%.2fs)." % [full_fill_time, full_drain_time]
		)
		quit(1)
		return
	player_b.bladder.bladder_fill_rate = 0.0
	player.bladder.bladder_fill_rate = 0.0

	player.global_position = Vector3(12.0, 1.0, 2.0)
	player.global_rotation = Vector3.ZERO
	toilet.global_position = Vector3(12.0, 1.22, 0.5)

	# Zero drift/tremors for deterministic driving. Individual checks below
	# briefly re-enable the forces they are intended to isolate.
	minigame.oscillation_amplitude = 0.0
	minigame.oscillation_amplitude_end = 0.0
	minigame.tremor_force = 0.0

	await physics_frame
	await physics_frame

	# --- Toilet interaction: prompt exists, E starts the minigame. ---
	var target: Node = player.call("get_interaction_target")
	if target != toilet.get_node("Interactable"):
		push_error("Player did not target the Toilet's Interactable.")
		quit(1)
		return
	var prompt_before: String = toilet.get_node("Interactable").get_interaction_prompt("E")
	if not prompt_before.contains("DÙNG BỒN CẦU"):
		push_error("Toilet prompt text was not the expected 'use toilet' prompt.")
		quit(1)
		return

	player.bladder.current_value = 30.0
	player_b.bladder.current_value = 42.0
	player.call("_try_interact")
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Interacting with the toilet did not start the minigame (state=%s)." % minigame.current_state)
		quit(1)
		return
	# The same E press that begins a session must not be interpreted as an
	# immediate request to leave it. Only E presses after its release may cancel.
	minigame._unhandled_input(_make_interact_event())
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("The E press that started the toilet minigame immediately cancelled it.")
		quit(1)
		return
	minigame._unhandled_input(_make_interact_release_event())
	if not player.is_toilet_minigame_active():
		push_error("Player.is_toilet_minigame_active() should be true once the minigame starts.")
		quit(1)
		return
	if not player_b.bladder: # sanity: player_b has its own independent component
		push_error("player_b unexpectedly has no bladder.")
		quit(1)
		return
	if player_b.is_toilet_minigame_active():
		push_error("player_b incorrectly inherited the toilet minigame state.")
		quit(1)
		return

	# --- Camera clamp state: armed correctly while PLAYING. ---
	# Godot's headless mode has no real DisplayServer, so
	# Input.set_mouse_mode() is a no-op and get_mouse_mode() always reports
	# MOUSE_MODE_VISIBLE - the mouse-look branch this feeds
	# (`if ... and Input.get_mouse_mode() == MOUSE_MODE_CAPTURED`) is
	# therefore unreachable in a headless test, exactly like the rest of
	# player.gd's pre-existing mouse-look code (no test in this project has
	# ever simulated real mouse-drag rotation for the same reason - see the
	# task's own manual_tests for that). What's verified here instead is the
	# part that *is* automatable: the clamp fields are armed with the right
	# bounds on entry and fully disarmed on exit (checked further below,
	# after cancel).
	await create_timer(0.35).timeout # let the entry tween settle
	if not player.yaw_clamp_active:
		push_error("yaw_clamp_active was not enabled while the toilet minigame is playing.")
		quit(1)
		return
	if not is_equal_approx(player.yaw_clamp_max - player.yaw_clamp_min, TAU):
		push_error("Yaw clamp range is not a full turn for checking both rear shoulders.")
		quit(1)
		return
	if not is_equal_approx(player.pitch_clamp_max - player.pitch_clamp_min, deg_to_rad(180.0)):
		push_error("Pitch clamp range is not +-90 degrees around the entry orientation.")
		quit(1)
		return
	if not is_equal_approx(player.accumulated_yaw, 0.0):
		push_error("accumulated_yaw should start at 0 relative to the freshly-established toilet-facing orientation.")
		quit(1)
		return

	# --- The moving equilibrium pulls the nozzle off center if ignored. ---
	minigame.oscillation_amplitude = 0.18
	minigame.oscillation_amplitude_end = 0.18
	minigame.asset_anchor.position.x = 0.0
	minigame.player_offset = 0.0
	minigame.nozzle_velocity = 0.0
	minigame.time_passed = 0.0
	for i in 20:
		minigame._handle_input(STEP_DELTA)
		minigame._update_visuals(STEP_DELTA)
	if is_equal_approx(minigame.asset_anchor.position.x, 0.0):
		push_error("Ignoring the minigame did not pull the nozzle away from center.")
		quit(1)
		return
	minigame.oscillation_amplitude = 0.0
	minigame.oscillation_amplitude_end = 0.0
	minigame.player_offset = 0.0
	minigame.nozzle_velocity = 0.0
	minigame.asset_anchor.position.x = 0.0

	# --- Mouse motion adds velocity, while A/D remains a real fallback. ---
	minigame.apply_mouse_motion(24.0)
	minigame._handle_input(STEP_DELTA)
	if minigame.nozzle_velocity <= 0.0 or minigame.player_offset <= 0.0:
		push_error("Moving the mouse right did not push the nozzle right with inertia.")
		quit(1)
		return
	minigame.player_offset = 0.0
	minigame.nozzle_velocity = 0.0
	Input.action_press("move_right")
	for i in 10:
		minigame._handle_input(STEP_DELTA)
	Input.action_release("move_right")
	if minigame.player_offset <= 0.0:
		push_error("Holding move_right (D) did not move the nozzle offset positive.")
		quit(1)
		return
	var offset_after_d: float = minigame.player_offset
	Input.action_press("move_left")
	for i in 20:
		minigame._handle_input(STEP_DELTA)
	Input.action_release("move_left")
	if minigame.player_offset >= offset_after_d:
		push_error("Holding move_left (A) did not move the nozzle offset back down.")
		quit(1)
		return
	minigame.player_offset = 0.0 # reset for the deterministic success drive below
	minigame.nozzle_velocity = 0.0

	# --- Sustained danger creates noise instead of silently doing nothing. ---
	var noise_effects := [0]
	minigame.minigame_effect_requested.connect(func(effect: String) -> void:
		if effect == "noise_created":
			noise_effects[0] += 1
	)
	minigame.asset_anchor.position.x = 0.36
	minigame._evaluate_balance(minigame.danger_noise_delay + 0.01)
	if noise_effects[0] != 1:
		push_error("Sustained danger did not emit exactly one noise consequence.")
		quit(1)
		return
	minigame.asset_anchor.position.x = 0.0
	minigame.damage_timer = 0.0
	minigame.noise_cooldown = 0.0

	# --- The yellow warning zone now drains, but only at its slower rate. ---
	player.bladder.current_value = 50.0
	minigame.session_start_bladder = 50.0
	minigame.asset_anchor.position.x = 0.12
	minigame._flow_ramp_elapsed = 0.0
	minigame._evaluate_balance(minigame.pee_ramp_duration)
	var bladder_before_warning: float = player.get_bladder()
	minigame._evaluate_balance(1.0)
	var expected_warning_drain: float = (
		minigame.bladder_drain_rate * minigame.warning_drain_multiplier
	)
	if not is_equal_approx(
		bladder_before_warning - player.get_bladder(),
		expected_warning_drain
	):
		push_error("The yellow zone did not drain bladder at its configured slow rate.")
		quit(1)
		return
	# Flow starts automatically, but its first 0.1 seconds are near-zero. The
	# ramp must reach maximum only after the configured 0.75 seconds.
	player.bladder.current_value = 50.0
	minigame._flow_ramp_elapsed = 0.0
	var bladder_before_short_flow: float = player.get_bladder()
	minigame._evaluate_balance(0.1)
	if bladder_before_short_flow - player.get_bladder() >= 0.01:
		push_error("A fresh 0.1-second automatic flow drained too quickly; the 0.75-second ramp was bypassed.")
		quit(1)
		return
	minigame._evaluate_balance(0.65)
	if minigame._flow_ramp_elapsed < minigame.pee_ramp_duration:
		push_error("Automatic flow did not reach full pressure after 0.75 seconds.")
		quit(1)
		return
	minigame.asset_anchor.position.x = 0.0

	# --- The original exploit was winning by doing nothing. Twelve simulated
	# seconds with a full bladder must now leave the session unfinished, and
	# the unattended drift must eventually enter danger and create noise.
	noise_effects[0] = 0
	player.bladder.current_value = 100.0
	minigame.session_start_bladder = 100.0
	minigame.oscillation_amplitude = 0.18
	minigame.oscillation_amplitude_end = 0.31
	minigame.player_offset = 0.0
	minigame.nozzle_velocity = 0.0
	minigame.asset_anchor.position.x = 0.0
	minigame.safe_streak_time = 0.0
	minigame.time_passed = 0.0
	for i in 240:
		minigame._handle_input(STEP_DELTA)
		minigame._update_visuals(STEP_DELTA)
		minigame._evaluate_balance(STEP_DELTA)
		if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
			break
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Doing nothing still completed the toilet minigame within 12 seconds.")
		quit(1)
		return
	if noise_effects[0] <= 0:
		push_error("Unattended drift never reached the danger/noise consequence.")
		quit(1)
		return
	minigame.oscillation_amplitude = 0.0
	minigame.oscillation_amplitude_end = 0.0
	minigame.player_offset = 0.0
	minigame.nozzle_velocity = 0.0
	minigame.asset_anchor.position.x = 0.0
	minigame.safe_streak_time = 0.0
	minigame.damage_timer = 0.0
	minigame.noise_cooldown = 0.0

	# --- Repeated interact while active must not create a second session. ---
	player.call("_try_interact")
	player.call("_try_interact")
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Spamming interact disturbed the in-progress session.")
		quit(1)
		return
	if toilet._active_player != player:
		push_error("Spamming interact changed the toilet's active player.")
		quit(1)
		return

	# --- Cancel before completion: bladder unchanged, state restored. ---
	# Set fresh right before cancelling: real time has passed above (the
	# camera-tween-settle wait), during which dwelling centered in the safe
	# zone was for-real draining bladder via the actual _process() loop -
	# correct gameplay behavior, just not what this specific assertion
	# means to isolate.
	player.bladder.current_value = 30.0
	minigame._unhandled_input(_make_interact_event())
	if minigame.current_state != ToiletMinigame.MinigameState.CANCELLED:
		push_error("E/interact did not move the minigame into CANCELLED.")
		quit(1)
		return
	await create_timer(1.0).timeout # cancel's own 0.5s delay + cleanup tween
	if minigame.current_state != ToiletMinigame.MinigameState.IDLE:
		push_error("Minigame did not return to IDLE after cancel's cleanup finished.")
		quit(1)
		return
	if player.bladder.current_value != 30.0:
		push_error("Cancel changed the bladder value; it must stay untouched (got %f)." % player.bladder.current_value)
		quit(1)
		return
	var saved_ghost_advance := float(player.get_meta(ToiletMinigame.GHOST_ADVANCE_META, 0.0))
	var expected_cancel_step := 1.0 / float(minigame.toilet_ghost.steps_to_reach)
	if not is_equal_approx(saved_ghost_advance, expected_cancel_step):
		push_error("Cancel saved ghost advance %.3f, expected one step (%.3f)." % [
			saved_ghost_advance, expected_cancel_step
		])
		quit(1)
		return
	if player.is_toilet_minigame_active() or player.is_door_minigame_active():
		push_error("Player minigame-lock flag did not clear after cancel.")
		quit(1)
		return
	if player.yaw_clamp_active:
		push_error("yaw_clamp_active was not cleared after cancel.")
		quit(1)
		return
	if not is_equal_approx(player.pitch_clamp_min, -PI / 2.0) or not is_equal_approx(player.pitch_clamp_max, PI / 2.0):
		push_error("Pitch clamp was not restored to the normal +-90 degree range after cancel.")
		quit(1)
		return
	if not player.is_physics_processing():
		push_error("Player movement was not restored after cancel.")
		quit(1)
		return

	# Toilet must be interactable again after cancel.
	await physics_frame
	player.call("_try_interact")
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Toilet did not accept a new session after the previous one was cancelled.")
		quit(1)
		return
	if not is_equal_approx(minigame.toilet_ghost._pending_start_advance, expected_cancel_step):
		push_error("The next session did not restore the cancelled ghost's advance.")
		quit(1)
		return
	if minigame.toilet_ghost._spawn_timer > minigame.toilet_ghost.resumed_spawn_delay + 0.001:
		push_error("A carried-over ghost used the normal initial spawn delay.")
		quit(1)
		return

	# --- Success: drive bladder to 0 while parked in the safe zone. ---
	player.bladder.current_value = 5.0 # small on purpose - fast, deterministic drain
	minigame.asset_anchor.position.x = 0.0
	minigame._flow_ramp_elapsed = minigame.pee_ramp_duration
	var iterations := 0
	while minigame.current_state == ToiletMinigame.MinigameState.PLAYING and iterations < 2000:
		minigame._evaluate_balance(STEP_DELTA)
		iterations += 1
	if minigame.current_state != ToiletMinigame.MinigameState.SUCCESS:
		push_error("Minigame never reached SUCCESS while parked in the safe zone.")
		quit(1)
		return
	await create_timer(1.5).timeout # success's own 1.0s delay + cleanup tween
	if minigame.current_state != ToiletMinigame.MinigameState.IDLE:
		push_error("Minigame did not return to IDLE after success's cleanup finished.")
		quit(1)
		return
	if player.bladder.current_value != 0.0:
		push_error("Success did not leave the interacting player's bladder at 0.")
		quit(1)
		return
	if player.has_meta(ToiletMinigame.GHOST_ADVANCE_META):
		push_error("Success did not clear the player's Toilet Ghost advance debt.")
		quit(1)
		return
	if player_b.bladder.current_value != 42.0:
		push_error("player_b's bladder was touched by player's success.")
		quit(1)
		return
	if not player.is_physics_processing():
		push_error("Player movement was not restored after success.")
		quit(1)
		return
	if player.yaw_clamp_active:
		push_error("yaw_clamp_active was not cleared after success.")
		quit(1)
		return
	if not is_equal_approx(player.pitch_clamp_min, -PI / 2.0) or not is_equal_approx(player.pitch_clamp_max, PI / 2.0):
		push_error("Pitch clamp was not restored to the normal +-90 degree range after success.")
		quit(1)
		return
	if player.is_toilet_minigame_active():
		push_error("Player minigame-lock flag did not clear after success.")
		quit(1)
		return

	# --- Toilet Ghost catch consequence: alive, 80% slower, blurred/flickering
	# overlay for exactly seven seconds, then a complete automatic recovery. ---
	var stun_started := [0]
	var stun_finished := [0]
	player.toilet_ghost_stun_changed.connect(func(active: bool) -> void:
		if active:
			stun_started[0] += 1
		else:
			stun_finished[0] += 1
	)
	await physics_frame
	player.call("_try_interact")
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Could not start a session for the Toilet Ghost catch integration check.")
		quit(1)
		return
	minigame._on_toilet_ghost_caught()
	if minigame.current_state != ToiletMinigame.MinigameState.CANCELLED:
		push_error("Toilet Ghost catch did not cancel and release its minigame.")
		quit(1)
		return
	if not player.is_alive or not player.is_toilet_ghost_stunned():
		push_error("Toilet Ghost stun killed the player or failed to become active.")
		quit(1)
		return
	if not is_equal_approx(player.toilet_ghost_stun_remaining, 7.0) \
			or not is_equal_approx(player.get_toilet_ghost_speed_multiplier(), 0.2):
		push_error("Toilet Ghost stun is not seven seconds at 20% movement speed.")
		quit(1)
		return
	var player_overlay := player.horror_overlay_rect.material as ShaderMaterial
	var player_b_overlay := player_b.horror_overlay_rect.material as ShaderMaterial
	if not is_equal_approx(float(player_overlay.get_shader_parameter("stun_strength")), 1.0):
		push_error("Toilet Ghost stun did not enable the concussion overlay.")
		quit(1)
		return
	if not is_zero_approx(float(player_b_overlay.get_shader_parameter("stun_strength"))):
		push_error("One player's stun leaked into another player's overlay material.")
		quit(1)
		return
	player._update_toilet_ghost_stun(7.0)
	if player.is_toilet_ghost_stunned() \
			or not is_zero_approx(float(player_overlay.get_shader_parameter("stun_strength"))):
		push_error("Toilet Ghost stun did not fully clear after seven seconds.")
		quit(1)
		return
	if stun_started[0] != 1 or stun_finished[0] != 1:
		push_error("Toilet Ghost stun lifecycle signals were not emitted exactly once.")
		quit(1)
		return
	await create_timer(1.4).timeout # cancel cleanup + 3D caught overlay cleanup

	# --- Player invalidation mid-session (e.g. death): safe cleanup via
	# cancel, no success, no bladder change.
	#
	# Note: toilet invalidation can no longer be tested by freeing the
	# toilet mid-session. ToiletMinigame is now a *child* of Toilet (per
	# the ported node structure), so toilet.queue_free() frees the minigame
	# with it in the same GC pass - there is no reachable state where the
	# minigame outlives its own toilet to detect and clean up; Godot's own
	# node-tree lifecycle already makes that scenario impossible. (Verified
	# directly: is_instance_valid(minigame) is false immediately after
	# freeing its parent toilet - calling into it from there would be
	# invoking a method on an already-freed Node, which is a genuine
	# use-after-free, not something the minigame needs to guard against.)
	await physics_frame
	player.call("_try_interact")
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Toilet did not start a fresh session for the player-invalidation test.")
		quit(1)
		return
	player.bladder.current_value = 33.0
	player.is_alive = false
	minigame._process(STEP_DELTA) # the real per-frame validity check lives here
	if minigame.current_state == ToiletMinigame.MinigameState.PLAYING:
		push_error("Minigame kept running after its player became invalid.")
		quit(1)
		return
	if minigame.current_state == ToiletMinigame.MinigameState.SUCCESS:
		push_error("Player invalidation must not count as a success.")
		quit(1)
		return
	if player.bladder.current_value != 33.0:
		push_error("Player invalidation must not change the bladder value.")
		quit(1)
		return
	player.is_alive = true

	print("Toilet minigame smoke test passed.")
	quit()


func _make_interact_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	return event


func _make_interact_release_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = false
	return event

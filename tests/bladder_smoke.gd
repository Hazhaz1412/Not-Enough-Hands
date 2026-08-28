extends SceneTree

## PlayerBladder + bladder HUD smoke test. Loads player/player.tscn directly
## (not through player_test.tscn) so the embedded StatusUI/BladderPanel/
## Margin/VBox/BladderBar node - the real deployed HUD, not a test double -
## is exercised exactly as players will see it.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_scene := load("res://player/player.tscn") as PackedScene
	var player := player_scene.instantiate()
	root.add_child(player)

	var bladder: PlayerBladder = player.bladder
	var hud: ProgressBar = player.get_node("StatusUI/BladderPanel/Margin/VBox/BladderBar")
	var default_full_duration := bladder.bladder_max / bladder.bladder_fill_rate
	if not is_equal_approx(default_full_duration, 45.0 * 1.5):
		push_error("An empty bladder should fill after 45 game minutes / 67.5 real seconds; got %.3fs." % default_full_duration)
		quit(1)
		return

	await physics_frame
	await physics_frame

	# --- Test 1: 0 -> max, driven by elapsed time, not frame count. ---
	bladder.current_value = 0.0
	bladder.bladder_fill_rate = 40.0 # fast for the test; behavior is the same math either way
	var elapsed := 0.0
	while bladder.get_bladder() < bladder.bladder_max and elapsed < 10.0:
		bladder._physics_process(0.1)
		elapsed += 0.1
	if bladder.get_bladder() != bladder.bladder_max:
		push_error("Bladder did not reach max by advancing time.")
		quit(1)
		return
	if bladder.get_bladder() <= 0.0:
		push_error("Bladder never increased from 0.")
		quit(1)
		return

	# --- Test 2: warning threshold fires exactly once on the way up. ---
	bladder.current_value = 0.0
	var warning_count := [0]
	bladder.bladder_warning_started.connect(func(): warning_count[0] += 1)
	bladder.add_bladder(bladder.bladder_warning_threshold - 5.0) # still below threshold
	if warning_count[0] != 0:
		push_error("bladder_warning_started fired before reaching the threshold.")
		quit(1)
		return
	bladder.add_bladder(10.0) # crosses the threshold
	if warning_count[0] != 1:
		push_error("bladder_warning_started should have fired exactly once; fired %d times." % warning_count[0])
		quit(1)
		return
	bladder.add_bladder(1.0) # staying above threshold must not re-fire
	if warning_count[0] != 1:
		push_error("bladder_warning_started fired again while already in the warning band.")
		quit(1)
		return
	# HUD must reflect the warning state once bladder_changed has propagated.
	hud._on_bladder_changed(bladder.get_bladder(), bladder.bladder_max)
	if not hud._is_warning:
		push_error("HUD did not register the warning state from the bladder signal.")
		quit(1)
		return

	# --- Test 3: max clamp, bladder_full only once per fill event. ---
	var full_count := [0]
	bladder.bladder_full.connect(func(): full_count[0] += 1)
	bladder.add_bladder(1000.0) # massively overshoot on purpose
	if bladder.get_bladder() != bladder.bladder_max:
		push_error("Bladder exceeded bladder_max: %f." % bladder.get_bladder())
		quit(1)
		return
	if full_count[0] != 1:
		push_error("bladder_full should fire exactly once when reaching max; fired %d times." % full_count[0])
		quit(1)
		return
	# Already at max: further overflow attempts must not re-fire it.
	bladder.add_bladder(50.0)
	bladder.add_bladder(50.0)
	if full_count[0] != 1:
		push_error("bladder_full fired again every call while already at max.")
		quit(1)
		return
	if bladder.get_bladder() > bladder.bladder_max:
		push_error("Bladder overflowed past bladder_max.")
		quit(1)
		return

	# Reduced below max and refilled to max again: bladder_full may re-fire.
	bladder.reduce_bladder(20.0)
	bladder.add_bladder(20.0)
	if full_count[0] != 2:
		push_error("bladder_full should fire again after a later refill to max; count=%d." % full_count[0])
		quit(1)
		return

	# --- Test 4: reset. ---
	bladder.current_value = 88.0
	var changed_count := [0]
	bladder.bladder_changed.connect(func(_v, _m): changed_count[0] += 1)
	bladder.reset_bladder()
	if bladder.get_bladder() != 0.0:
		push_error("reset_bladder() did not zero the bladder.")
		quit(1)
		return
	if changed_count[0] != 1:
		push_error("reset_bladder() should emit bladder_changed exactly once; emitted %d times." % changed_count[0])
		quit(1)
		return

	# --- Test 5: reduce, never below zero. ---
	bladder.current_value = 30.0
	bladder.reduce_bladder(10.0)
	if bladder.get_bladder() != 20.0:
		push_error("reduce_bladder(10) from 30 should leave 20; got %f." % bladder.get_bladder())
		quit(1)
		return
	bladder.reduce_bladder(1000.0)
	if bladder.get_bladder() != 0.0:
		push_error("reduce_bladder() past zero should clamp to 0; got %f." % bladder.get_bladder())
		quit(1)
		return

	# --- Test 6: pause safety - no separate Timer, so pausing the tree via
	# the engine's normal mechanism must stop the fill outright. ---
	bladder.current_value = 10.0
	bladder.bladder_fill_rate = 5.0
	paused = true
	await process_frame
	await process_frame
	await process_frame
	if bladder.get_bladder() != 10.0:
		push_error("Bladder increased while the tree was paused: %f." % bladder.get_bladder())
		quit(1)
		return
	paused = false
	await physics_frame

	# --- Test 7: HUD ownership - reflects the player's value, never writes it. ---
	bladder.current_value = 42.0
	hud._on_bladder_changed(bladder.get_bladder(), bladder.bladder_max)
	for i in 200: # let the smoothing lerp catch up
		hud._process(1.0 / 60.0)
	if not is_equal_approx(hud.value, 42.0):
		push_error("HUD did not converge to the player's bladder value; got %f." % hud.value)
		quit(1)
		return
	if bladder.get_bladder() != 42.0:
		push_error("HUD mutated the authoritative bladder value.")
		quit(1)
		return

	print("Bladder smoke test passed.")
	quit()

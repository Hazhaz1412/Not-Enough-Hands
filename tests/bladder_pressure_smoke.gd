extends SceneTree

## The bladder as a pressure system rather than a bar: how long it takes to
## fill, what it costs above the debuff threshold, and what happens when it is
## ignored all the way to the top.
##
## Driven by calling _physics_process() directly with a fixed delta rather than
## by waiting - a 135-second fill is not something a smoke test can sit through,
## and the arithmetic is the contract anyway.

const STEP := 1.0 / 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bladder := PlayerBladder.new()
	root.add_child(bladder)
	bladder.set_physics_process(false)

	if not _test_fill_takes_one_hundred_eighty_game_minutes(bladder):
		return
	if not _test_the_debuff_band_is_the_top_quarter():
		return
	if not _test_a_full_bladder_empties_itself_slowly(bladder):
		return
	if not _test_reaching_a_toilet_still_ends_an_accident(bladder):
		return
	if not _test_a_networked_accident_can_end_without_the_local_drain(bladder):
		return

	print(
		"Bladder pressure smoke test passed: 180-minute fill, debuff band, "
		+ "self-emptying over a flat 20s, a toilet cancelling it, "
		+ "and a server-driven value ending one."
	)
	quit()


## A client never runs the drain - its value arrives from the server - so an
## accident has to be able to end from an assigned value alone. While the end
## lived in the drain loop, every peer but the host stayed slowed and half blind
## for the rest of the night after one accident.
func _test_a_networked_accident_can_end_without_the_local_drain(
	bladder: PlayerBladder
) -> bool:
	bladder.set_bladder(bladder.bladder_max)
	if not bladder.is_wetting:
		return _fail("A full bladder did not start an accident.")
	# Exactly what apply_network_state() does on a client: assign, never drain.
	bladder.set_bladder(bladder.bladder_max * 0.5)
	if not bladder.is_wetting:
		return _fail("A half-drained accident ended early.")
	bladder.set_bladder(0.0)
	if bladder.is_wetting:
		return _fail("A server-driven empty did not end the accident.")
	return true


## 180 in-game minutes at the clock's 1.5 real seconds per minute.
func _test_fill_takes_one_hundred_eighty_game_minutes(bladder: PlayerBladder) -> bool:
	var fill_seconds := bladder.bladder_max / bladder.bladder_fill_rate
	if not is_equal_approx(fill_seconds, 180.0 * 1.5):
		return _fail("An empty bladder should fill in 270s, got %.2fs." % fill_seconds)
	return true


## The penalty ramps across the top quarter instead of switching on, so it
## arrives as pressure rather than as a cliff. Everything that punishes a full
## bladder reads this one curve.
func _test_the_debuff_band_is_the_top_quarter() -> bool:
	var threshold := 0.75
	for probe: Array in [[0.0, 0.0], [0.75, 0.0], [0.875, 0.5], [1.0, 1.0]]:
		var ratio := float(probe[0])
		var expected := float(probe[1])
		var pressure := clampf((ratio - threshold) / maxf(1.0 - threshold, 0.001), 0.0, 1.0)
		if not is_equal_approx(pressure, expected):
			return _fail(
				"At %.0f%% full the debuff should read %.2f, got %.2f."
				% [ratio * 100.0, expected, pressure]
			)
	return true


## Ignore it long enough and it goes on its own, wherever the player happens to
## be standing - and it takes `wetting_duration_seconds`, far longer than walking
## to a toilet would have, which is the entire reason not to ignore it.
func _test_a_full_bladder_empties_itself_slowly(bladder: PlayerBladder) -> bool:
	var started := [0]
	var ended := [0]
	bladder.wetting_started.connect(func() -> void: started[0] += 1)
	bladder.wetting_ended.connect(func() -> void: ended[0] += 1)

	bladder.set_bladder(bladder.bladder_max)
	if not bladder.is_wetting or started[0] != 1:
		return _fail("A full bladder did not start emptying itself.")

	var expected_seconds := bladder.wetting_duration_seconds
	var toilet_seconds := PlayerBladder.CONTROLLED_EMPTY_SECONDS
	if expected_seconds <= toilet_seconds:
		return _fail(
			"Losing control (%.1fs) has to cost more than a controlled session (%.1fs), "
			% [expected_seconds, toilet_seconds]
			+ "or the debuff is a shortcut."
		)

	var elapsed := 0.0
	var guard := 0
	while bladder.is_wetting and guard < 100000:
		guard += 1
		bladder._physics_process(STEP)
		elapsed += STEP
	if bladder.is_wetting:
		return _fail("The bladder never finished emptying itself.")
	if absf(elapsed - expected_seconds) > 0.2:
		return _fail(
			"Wetting should take %.1fs, took %.2fs." % [expected_seconds, elapsed]
		)
	if ended[0] != 1:
		return _fail("wetting_ended did not fire exactly once.")
	if bladder.get_bladder() > 0.0:
		return _fail("Wetting stopped before the bladder was actually empty.")

	# Nothing refills while it is emptying: a player is not fighting the fill
	# rate and the accident at the same time.
	if bladder.bladder_fill_rate <= 0.0:
		return _fail("This test proves nothing with the passive fill disabled.")
	return true


## Making it to a toilet mid-accident has to stop the accident, or a player who
## reached one in time is left draining on the bathroom floor anyway.
func _test_reaching_a_toilet_still_ends_an_accident(bladder: PlayerBladder) -> bool:
	bladder.set_bladder(bladder.bladder_max)
	if not bladder.is_wetting:
		return _fail("Refilling to full did not re-arm the accident.")
	bladder.reset_bladder()
	if bladder.is_wetting:
		return _fail("A toilet did not cancel an accident already in progress.")
	if bladder.get_bladder() != 0.0:
		return _fail("reset_bladder() left something behind.")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false

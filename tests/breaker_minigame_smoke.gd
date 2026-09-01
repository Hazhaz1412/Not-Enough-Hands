extends SceneTree

## Mechanics of the main breaker's repair wheel, driven deterministically: the
## minigame's own _process() is called with a fixed delta (engine processing is
## switched off right after start()) and attempts are resolved by placing the
## needle exactly on or off the mark before calling press(). Nothing here needs
## a PowerManager - tests/main_breaker_smoke.gd covers the wiring to the house.

const STEP := 0.1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var stand_in_player := Node3D.new()
	host.add_child(stand_in_player)
	var stand_in_breaker := Node3D.new()
	host.add_child(stand_in_breaker)

	var minigame := (load("res://minigames/breaker_minigame.tscn") as PackedScene).instantiate() as BreakerMinigame
	host.add_child(minigame)
	await process_frame

	# --- The tuning the design is stated in. ---
	_assert(is_equal_approx(minigame.repair_duration, 10.0), "A repair should cost 10 seconds by default.")
	_assert(is_equal_approx(minigame.fail_penalty, 1.5), "Each failure should add 1.5 seconds.")
	_assert(
		minigame.needle_max_speed > minigame.needle_start_speed,
		"The needle must have room to speed up before its ceiling."
	)

	_assert(minigame.start(stand_in_player, stand_in_breaker), "The repair minigame refused to start.")
	minigame.set_process(false)
	_assert(minigame.is_running(), "The repair minigame did not report itself running.")
	_assert(
		is_equal_approx(minigame.get_repair_remaining(), 10.0),
		"A fresh repair should owe the full duration, got %.2f." % minigame.get_repair_remaining()
	)

	# --- A landed press costs no time; a mistimed one costs exactly 1.5s. ---
	var before_hit: float = minigame._remaining
	var speed_before_hit: float = minigame._speed
	var direction_before_hit: float = minigame._direction
	_place_needle_on_mark(minigame)
	minigame.press()
	_assert(
		is_equal_approx(minigame._remaining, before_hit),
		"A landed press must not add repair time (%.2f -> %.2f)." % [before_hit, minigame._remaining]
	)
	_assert(minigame._direction == -direction_before_hit, "A press must reverse the needle's sweep.")
	_assert(minigame._speed > speed_before_hit, "The needle must speed up after an attempt.")
	_assert_mark_is_reactable(minigame)

	var before_miss: float = minigame._remaining
	var direction_before_miss: float = minigame._direction
	_place_needle_off_mark(minigame)
	minigame.press()
	_assert(
		is_equal_approx(minigame._remaining, before_miss + minigame.fail_penalty),
		"A mistimed press must add exactly %.2fs (%.2f -> %.2f)."
			% [minigame.fail_penalty, before_miss, minigame._remaining]
	)
	_assert(minigame._direction == -direction_before_miss, "A missed press must still reverse the sweep.")
	_assert_mark_is_reactable(minigame)

	# --- Ignoring the mark entirely is a failure too, not a free pass. The
	# needle has to clear the whole forgiveness window first, so the mark is
	# parked with only its far edge just ahead of the needle. ---
	var before_sweep: float = minigame._remaining
	var window: float = minigame.target_half_width + minigame.hit_forgiveness
	minigame._target_angle = fposmod(
		minigame._needle_angle + minigame._direction * (4.0 - window), 360.0
	)
	minigame._process(STEP)
	_assert(
		is_equal_approx(minigame._remaining, before_sweep + minigame.fail_penalty - STEP),
		"Sweeping past the mark without pressing must cost the same %.2fs penalty." % minigame.fail_penalty
	)

	# --- Forgiveness: a press just outside the drawn mark still lands. ---
	_assert(minigame.hit_forgiveness > 0.0, "The wheel should allow some slack around the mark.")
	minigame._needle_angle = fposmod(
		minigame._target_angle + minigame.target_half_width + minigame.hit_forgiveness * 0.5, 360.0
	)
	var before_forgiven: float = minigame._remaining
	minigame.press()
	_assert(
		is_equal_approx(minigame._remaining, before_forgiven),
		"A press just past the mark should still count, but it cost %.2fs."
			% (minigame._remaining - before_forgiven)
	)
	# ...but not an arbitrarily late one, or the mark stops meaning anything.
	minigame._needle_angle = fposmod(
		minigame._target_angle + minigame.target_half_width + minigame.hit_forgiveness + 6.0, 360.0
	)
	var before_late: float = minigame._remaining
	minigame.press()
	_assert(
		minigame._remaining > before_late,
		"A press well outside the forgiveness window still counted as a hit."
	)

	# --- The needle keeps accelerating, but stops at its ceiling. ---
	for _i in range(200):
		_place_needle_on_mark(minigame)
		minigame.press()
	_assert(
		is_equal_approx(minigame._speed, minigame.needle_max_speed),
		"The needle should settle at needle_max_speed (%.1f), got %.1f."
			% [minigame.needle_max_speed, minigame._speed]
	)
	_assert_mark_is_reactable(minigame)

	# --- However badly it goes, one repair is capped at max_repair_seconds. ---
	_assert(
		is_equal_approx(minigame.max_repair_seconds, 20.0),
		"A repair should be capped at 20 seconds by default."
	)
	for _i in range(50):
		_place_needle_off_mark(minigame)
		minigame.press()
	_assert(
		minigame._remaining <= minigame.max_repair_seconds + 0.001,
		"Fifty failures pushed the repair to %.2fs, past its %.1fs cap."
			% [minigame._remaining, minigame.max_repair_seconds]
	)

	# ...and spending that long on the wheel finishes it whatever the countdown
	# still reads, so a bad run can never trap the player at the cabinet.
	var forced := [0]
	minigame.repair_completed.connect(func() -> void: forced[0] += 1)
	_assert(
		minigame._remaining > 1.0,
		"Setup error: the countdown should still owe time for this check to mean anything."
	)
	minigame._elapsed = minigame.max_repair_seconds - 0.05
	minigame._target_angle = fposmod(minigame._needle_angle + minigame._direction * 180.0, 360.0)
	minigame._process(STEP)
	_assert(
		forced[0] == 1 and not minigame.is_running(),
		"Reaching the %.1fs cap did not auto-complete the repair (countdown still %.2fs)."
			% [minigame.max_repair_seconds, minigame._remaining]
	)
	minigame.reset_progress()
	_assert(minigame.start(stand_in_player, stand_in_breaker), "Could not restart after the cap.")
	minigame.set_process(false)

	# --- Cancelling keeps the seconds already served and every penalty. ---
	minigame._remaining = 4.25
	minigame.cancel()
	_assert(not minigame.is_running(), "Cancelling did not end the repair session.")
	_assert(
		is_equal_approx(minigame.get_repair_remaining(), 4.25),
		"A cancelled repair must resume where it stopped, got %.2f." % minigame.get_repair_remaining()
	)
	_assert(minigame.start(stand_in_player, stand_in_breaker), "The repair minigame refused to resume.")
	minigame.set_process(false)
	_assert(
		is_equal_approx(minigame._remaining, 4.25),
		"Resuming a repair restarted its countdown (%.2f)." % minigame._remaining
	)

	# --- Serving the countdown completes the repair exactly once. ---
	var completions := [0]
	minigame.repair_completed.connect(func() -> void: completions[0] += 1)
	minigame._remaining = 0.05
	# Park the mark half a turn away so this frame is a clean run-out rather
	# than an accidental sweep-past.
	minigame._target_angle = fposmod(minigame._needle_angle + minigame._direction * 180.0, 360.0)
	minigame._process(STEP)
	_assert(completions[0] == 1, "Serving the countdown did not complete the repair exactly once.")
	_assert(not minigame.is_running(), "The repair session stayed open after completing.")

	minigame.reset_progress()
	_assert(
		is_equal_approx(minigame.get_repair_remaining(), 10.0),
		"reset_progress() must put the next outage back to a full-length repair."
	)

	print("Breaker minigame smoke test passed: 10s repair, +1.5s per failure capped at 20s, 20s of play auto-completes, forgiving hit window, reversing needle, capped speed-up.")
	quit()


## Puts the needle exactly on the mark so the next press is a guaranteed hit.
func _place_needle_on_mark(minigame: BreakerMinigame) -> void:
	minigame._needle_angle = minigame._target_angle


## Puts the needle half a turn from the mark so the next press cannot land.
func _place_needle_off_mark(minigame: BreakerMinigame) -> void:
	minigame._needle_angle = fposmod(minigame._target_angle + 180.0, 360.0)


## Every new mark must sit ahead of the needle along the current sweep, far
## enough that the player still has time to react to it.
func _assert_mark_is_reactable(minigame: BreakerMinigame) -> void:
	var ahead := fposmod(
		(minigame._target_angle - minigame._needle_angle) * signf(minigame._direction), 360.0
	)
	_assert(
		ahead >= minigame.target_lead_min_degrees - 0.001
			and ahead <= minigame.target_lead_max_degrees + 0.001,
		"A new mark was placed %.1f degrees ahead, outside the reactable %.1f-%.1f range."
			% [ahead, minigame.target_lead_min_degrees, minigame.target_lead_max_degrees]
	)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)

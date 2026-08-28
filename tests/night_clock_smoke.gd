extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://ui/night_clock.tscn") as PackedScene
	if not packed:
		_fail("Night clock scene could not be loaded.")
		return

	var clock := packed.instantiate() as NightClock
	clock.pause_on_victory = false
	root.add_child(clock)
	clock.set_process(false)
	if not is_equal_approx(clock.real_seconds_per_game_minute, 1.5):
		_fail("Night clock should default to 1.5 real seconds per game minute.")
		return
	if clock.get_formatted_time() != "11:55 PM":
		_fail("Night clock did not start at 11:55 PM.")
		return

	clock.advance_real_seconds(1.499)
	if clock.get_formatted_time() != "11:55 PM":
		_fail("Clock advanced before a full 1.5 real seconds elapsed.")
		return
	clock.advance_real_seconds(0.001)
	if clock.get_formatted_time() != "11:56 PM":
		_fail("1.5 real seconds did not advance exactly one game minute.")
		return

	clock.advance_real_seconds(1.5 * 5.0)
	if clock.get_formatted_time() != "12:01 AM":
		_fail("Clock did not roll from 11:59 PM to 12:00 AM correctly.")
		return
	clock.advance_real_seconds(1.5)
	if clock.get_formatted_time() != "12:02 AM":
		_fail("12:01 AM to 12:02 AM did not take exactly 1.5 seconds.")
		return

	var victory_count := [0]
	clock.victory_reached.connect(func() -> void: victory_count[0] += 1)
	clock.advance_real_seconds(float(clock.get_minutes_remaining()) * 1.5)
	if clock.get_formatted_time() != "6:00 AM" or not clock.won:
		_fail("Night clock did not declare victory at 6:00 AM.")
		return
	if victory_count[0] != 1 or not clock.victory_overlay.visible:
		_fail("Victory signal/overlay did not fire exactly once at dawn.")
		return

	print("Night clock smoke test passed: 1.5-second tick, midnight rollover, and 6:00 AM victory.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

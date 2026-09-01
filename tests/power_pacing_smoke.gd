extends SceneTree

## How often a fully-lit house goes dark on its own over one night.
##
## Device wattages are art-side numbers (House2's lights alone total ~2900/s),
## so spending the reserve against them directly emptied a 1000-unit battery in
## under half a second. The reserve is spent against
## `full_load_reserve_seconds` instead, and this test is what keeps that pacing
## honest: it drains the real House2 map at a fixed timestep for exactly one
## night and counts the outages.

## 23:55 -> 06:00 is 365 in-game minutes at 1.5 real seconds each.
const NIGHT_SECONDS := 365.0 * 1.5
const STEP := 0.25


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var house := (load("res://house2/house2.tscn") as PackedScene).instantiate()
	root.add_child(house)
	var manager := house.get_node("PowerManager") as PowerManager
	var breaker := house.get_node("MainBreaker") as MainBreaker
	await process_frame
	await process_frame

	_assert(manager.enable_power_drain, "House2 must actually drain power or no outage ever happens.")
	_assert(manager.get_total_load() > 0.0, "House2 registered no power draw to drain.")

	# One night, driven at a fixed step so the count does not depend on frame
	# rate. Each outage is repaired the way a player would: at the breaker.
	var outages := 0
	var elapsed := 0.0
	manager.set_process(false)
	while elapsed < NIGHT_SECONDS:
		manager._process(STEP)
		elapsed += STEP
		if manager.is_blackout:
			outages += 1
			_assert(
				breaker.outline.visible,
				"Outage %d left the breaker unlit, so nobody could find it." % outages
			)
			breaker._restore_power()
			_assert(not manager.is_blackout, "Repairing at the breaker did not bring the lights back.")

	_assert(
		outages >= 1 and outages <= 3,
		"A fully-lit night should go dark about twice, got %d outages in %.0f seconds."
			% [outages, NIGHT_SECONDS]
	)

	# Running the house dark has to buy real time, or switching lights off is
	# not a decision. Half the load must last meaningfully longer than full.
	var full_drain := manager.get_drain_per_second()
	var lights := manager.devices.duplicate()
	for index: int in range(lights.size() / 2):
		(lights[index] as ElectricalDevice).turn_off()
	await process_frame
	var half_drain := manager.get_drain_per_second()
	_assert(
		half_drain < full_drain * 0.75,
		"Switching half the house off barely changed the drain (%.2f -> %.2f)."
			% [full_drain, half_drain]
	)

	print("Power pacing smoke test passed: %d outage(s) in one fully-lit night, and going dark slows the drain."
		% outages)
	quit()


func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)

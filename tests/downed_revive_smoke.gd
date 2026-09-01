extends SceneTree

## Covers the co-op downed contract from README.md: a ghost kill with a
## teammate still standing puts a player on the floor instead of ending their
## run, ghosts stop targeting them there, the bleed-out clock pauses for the
## whole ten-second rescue, and the 180-second budget - charged 60 per death -
## is what eventually turns them into a spectator.

## Loaded at run time, never preloaded: preload resolves while this script is
## compiled, which is before the NetworkManager autoload exists, and player.gd
## then fails to compile out from under the test.
const PLAYER_SCENE_PATH := "res://player/player.tscn"
const STEP := 1.0 / 60.0

var player_scene: PackedScene
var downed: CharacterBody3D
var mate: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	player_scene = load(PLAYER_SCENE_PATH) as PackedScene
	if not player_scene:
		_fail("Player scene could not be loaded.")
		return
	downed = player_scene.instantiate() as CharacterBody3D
	mate = player_scene.instantiate() as CharacterBody3D
	root.add_child(downed)
	root.add_child(mate)
	downed.global_position = Vector3.ZERO
	mate.global_position = Vector3(1.2, 0.0, 0.0)

	if not is_equal_approx(downed.downed_time_budget, 180.0) \
		or not is_equal_approx(downed.downed_death_cost, 60.0) \
		or not is_equal_approx(downed.revive_duration, 10.0):
		_fail("Downed budget must be 180 s, 60 s per death, 10 s to revive.")
		return
	if not is_equal_approx(downed.downed_time_remaining, downed.downed_time_budget):
		_fail("A fresh player should start on the full downed budget.")
		return

	if not _expect_downed_after_kill("first"):
		return
	if not _expect_ghosts_ignore_downed():
		return
	if not _expect_revive_pauses_the_clock():
		return
	if not _expect_downed_after_kill("second"):
		return
	if not _expect_solo_kill_still_ends_the_run():
		return

	# Third death spends the last 60 seconds of the budget outright, so there is
	# no floor to lie on and no rescue window: straight to spectating.
	downed.revive()
	mate.is_alive = true
	mate.is_downed = false
	mate.is_spectator = false
	downed.kill_by_ghost(null)
	if downed.is_downed or not downed.is_spectator:
		_fail("Spending the last 60 s of the budget must go straight to spectator.")
		return
	if not downed.collision_shape.disabled:
		_fail("A spectator must not keep a solid capsule in the world.")
		return
	if downed.can_be_targeted_by_ghosts():
		_fail("Ghosts must not target a spectator.")
		return

	print(
		"Downed revive smoke test passed: kill with a teammate downs instead of "
		+ "killing, ghosts drop the target, rescue pauses the clock and takes "
		+ "10 s, and 180 s spent at 60 s per death ends in spectator."
	)
	quit()


func _expect_downed_after_kill(label: String) -> bool:
	var before: float = downed.downed_time_remaining
	var expected_remaining: float = before - downed.downed_death_cost
	downed.kill_by_ghost(null)
	if not downed.is_downed:
		_fail("The %s kill should have downed the player, not killed them." % label)
		return false
	if downed.is_alive:
		_fail("A downed player must not still count as alive.")
		return false
	if downed.get_node("DeathUI").visible:
		_fail("The death jumpscare must not run while a rescue is still possible.")
		return false
	if not is_equal_approx(downed.downed_time_remaining, expected_remaining):
		_fail(
			"The %s death should charge 60 s and leave %.1f s, left %.1f s."
			% [label, expected_remaining, downed.downed_time_remaining]
		)
		return false
	return true


func _expect_ghosts_ignore_downed() -> bool:
	if downed.can_be_targeted_by_ghosts():
		_fail("Ghosts must drop a downed player as a target.")
		return false
	if not mate.can_be_targeted_by_ghosts():
		_fail("The standing teammate should still be a valid ghost target.")
		return false
	return true


func _expect_revive_pauses_the_clock() -> bool:
	var before: float = downed.downed_time_remaining

	# Nobody holding the key: the clock runs and no rescue accumulates.
	downed._update_downed(1.0)
	if is_equal_approx(downed.downed_time_remaining, before):
		_fail("The bleed-out clock must run while nobody is reviving.")
		return false
	if downed.revive_progress > 0.0:
		_fail("Rescue progress must not build with nobody holding the key.")
		return false
	before = downed.downed_time_remaining

	# Out of range, key held: still no rescue.
	mate.global_position = Vector3(6.0, 0.0, 0.0)
	if mate.can_revive(downed):
		_fail("A teammate %.1f m away must be out of revive range." % 6.0)
		return false
	mate.global_position = Vector3(1.2, 0.0, 0.0)
	if not mate.can_revive(downed):
		_fail("A teammate standing next to the body should be able to revive.")
		return false

	Input.action_press("interact")
	var elapsed := 0.0
	while elapsed < downed.revive_duration - STEP and downed.is_downed:
		downed._update_downed(STEP)
		elapsed += STEP
	if not downed.is_downed:
		_fail("The rescue finished in %.2f s; it must take a full 10 s." % elapsed)
		Input.action_release("interact")
		return false
	if not is_equal_approx(downed.downed_time_remaining, before):
		_fail(
			"The clock must be frozen during a rescue, but %.1f s drained."
			% (before - downed.downed_time_remaining)
		)
		Input.action_release("interact")
		return false
	if downed.get_revive_ratio() < 0.95:
		_fail("Rescue progress should be nearly complete after 10 s of holding.")
		Input.action_release("interact")
		return false

	downed._update_downed(STEP * 2.0)
	Input.action_release("interact")
	if downed.is_downed or not downed.is_alive:
		_fail("Ten seconds of holding must put the player back on their feet.")
		return false
	if not is_equal_approx(downed.downed_time_remaining, before):
		_fail("A rescue must not refill the downed budget.")
		return false
	if not downed.can_be_targeted_by_ghosts():
		_fail("A revived player must become a ghost target again.")
		return false
	return true


## Without a teammate left standing there is nobody to come back for, so the
## original jumpscare and game-over path has to be untouched.
func _expect_solo_kill_still_ends_the_run() -> bool:
	var solo := player_scene.instantiate() as CharacterBody3D
	root.add_child(solo)
	mate.is_alive = false
	downed.is_alive = false
	solo.kill_by_ghost(null)
	var still_running: bool = not solo.is_downed and not solo.is_alive and solo.get_node("DeathUI").visible
	solo.queue_free()
	mate.is_alive = true
	downed.is_alive = false
	if not still_running:
		_fail("With no teammate left, a kill must still show the death screen.")
		return false
	return true


func _fail(message: String) -> void:
	push_error("Downed revive smoke test failed: " + message)
	print("Downed revive smoke test FAILED: " + message)
	quit(1)

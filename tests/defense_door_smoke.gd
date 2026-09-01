extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://door/defense_door.tscn") as PackedScene
	var door := packed_scene.instantiate() as DefenseDoor
	root.add_child(door)
	door.set_physics_process(false)
	door.get_node("WarningAudio").stream = null
	door.get_node("StrongAttackAudio").stream = null
	door.set_random_seed(42)

	var damaged := door.take_damage(10.0)
	if not is_equal_approx(damaged, 10.0):
		_fail("Defense door did not accept ten damage.")
		return
	if not is_equal_approx(door.current_durability, 90.0):
		_fail("Defense door durability was not reduced to 90.")
		return
	if not is_equal_approx(door.repair_cap, 97.0):
		_fail("Ten damage must leave exactly seven repairable HP.")
		return
	door.repair(100.0)
	if not is_equal_approx(door.current_durability, 97.0):
		_fail("Repair exceeded the permanent 70 percent repair ceiling.")
		return

	door.reset_door()
	if not door.begin_targeting(false, 0.1):
		_fail("Defense door could not begin a false target event.")
		return
	door._physics_process(0.1)
	if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
		_fail("False target event did not leave without attacking.")
		return
	if not is_equal_approx(door.current_durability, 100.0):
		_fail("False target event damaged the door.")
		return

	if not door.begin_targeting(true, 0.1):
		_fail("Defense door could not begin a real target event.")
		return
	door._physics_process(0.1)
	if door.attack_phase != DefenseDoor.AttackPhase.WEAK_ATTACK:
		_fail("Real target event did not enter the weak attack phase.")
		return
	if not door.get_interaction_prompt("E").contains("MINIGAME"):
		_fail("Weak door attack prompt did not offer the E minigame interaction.")
		return
	if not door.begin_exorcism() or not door.complete_exorcism():
		_fail("The weak door attack could not be repelled through the minigame API.")
		return
	if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
		_fail("Winning during a weak door attack did not drive the ghost away.")
		return

	if not door.begin_targeting(true, 0.1):
		_fail("Door could not begin a second attack for the strong-phase test.")
		return
	door.attack_damage_min = 30.0
	door.attack_damage_max = 30.0
	door.damage_tick_interval = 2.0
	# Restart so this apparition rolls the deterministic 30 HP budget above.
	door.drive_ghost_away()
	if not door.begin_targeting(true, 0.1):
		_fail("Door could not begin the bounded-damage attack test.")
		return
	door._physics_process(0.1)
	door._physics_process(1.0)
	if not is_equal_approx(door.current_durability, 100.0):
		_fail("The door ghost scratched sooner than the two-second interval.")
		return
	var attack_seconds := 1
	while door.attack_phase != DefenseDoor.AttackPhase.IDLE and attack_seconds < 30:
		door._physics_process(1.0)
		attack_seconds += 1
	if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
		_fail("The bounded door attack did not end on its own.")
		return
	if not is_equal_approx(door.current_durability, 70.0):
		_fail("One apparition must deal exactly its rolled 30 HP budget, not destroy the door.")
		return
	if attack_seconds < 8:
		_fail("The longer scratch spacing let a 30 HP attack finish too quickly.")
		return

	door.reset_door()
	door.take_damage(100.0, true)
	await physics_frame
	if door.attack_phase != DefenseDoor.AttackPhase.BREACHED:
		_fail("Zero durability did not breach the defense door.")
		return
	if not (door.get_node("DoorCollision") as CollisionShape3D).disabled:
		_fail("Breached door still blocked the entrance.")
		return
	if not is_equal_approx(door.repair_cap, 70.0):
		_fail("A fully breached door must only rebuild to 70 durability.")
		return
	if not is_zero_approx(door.repair(7.0)):
		_fail("A breached door was repairable before its exorcism minigame.")
		return
	if not door.begin_exorcism():
		_fail("A breached door could not begin its exorcism minigame.")
		return
	if not is_zero_approx(door.take_damage(20.0, true)):
		_fail("A door took normal damage while its minigame was active.")
		return
	var penalized_cap := door.apply_exorcism_failure()
	if not is_equal_approx(penalized_cap, 50.0):
		_fail("A failed minigame did not remove exactly 20 repairable HP.")
		return
	if not door.complete_exorcism():
		_fail("A successful minigame did not unlock the breached door.")
		return
	door.repair(7.0)
	await physics_frame
	if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
		_fail("Repairing a breach did not rebuild the door.")
		return
	if (door.get_node("DoorCollision") as CollisionShape3D).disabled:
		_fail("Rebuilt door did not block the entrance again.")
		return

	print("Defense door smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

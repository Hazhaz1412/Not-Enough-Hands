extends SceneTree

## Regression for the DarknessGhost wedging beside V01's bannister while a
## player waits on the upper landing.

const V01_FOOT := Vector3(40.0, 0.2, 5.0)
const V01_LANDING := Vector3(44.5, 4.3, 5.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var villa := (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(villa)
	for _attempt: int in 600:
		if bool(villa.get("navigation_is_ready")):
			break
		await physics_frame
	if not bool(villa.get("navigation_is_ready")):
		return _fail("Villa navigation never became ready.")

	var player := villa.get_node("Player") as CharacterBody3D
	var ghost := villa.get_node("DarknessGhost") as DarknessGhost
	player.global_position = V01_LANDING
	ghost.auto_manifest = false
	ghost.set_process(false)
	ghost.global_position = V01_FOOT
	ghost.encounter_phase = DarknessGhost.EncounterPhase.CHASING
	ghost._set_manifested(true)
	await physics_frame

	var highest := ghost.global_position.y
	var closest := ghost.global_position.distance_to(player.global_position)
	var climbed := false
	for _frame: int in 60 * 15:
		await physics_frame
		highest = maxf(highest, ghost.global_position.y)
		closest = minf(closest, ghost.global_position.distance_to(player.global_position))
		if ghost.global_position.y >= V01_LANDING.y - 1.0 and closest <= 2.5:
			climbed = true
			break
	if not climbed:
		return _fail(
			"DarknessGhost wedged climbing V01: highest y=%.2f, closest=%.2f, ended at %s."
			% [highest, closest, ghost.global_position]
		)

	player.global_position = V01_FOOT
	ghost.global_position = V01_LANDING
	ghost.velocity = Vector3.ZERO
	await physics_frame
	var lowest := ghost.global_position.y
	for _frame: int in 60 * 15:
		await physics_frame
		lowest = minf(lowest, ghost.global_position.y)
		if lowest <= 0.8:
			print("Villa Darkness stair smoke passed: V01 climb and descent are clear.")
			quit(0)
			return
	_fail("DarknessGhost wedged descending V01: lowest y=%.2f, ended at %s."
		% [lowest, ghost.global_position])


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

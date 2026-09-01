extends SceneTree

## The two ways the villa used to swallow a hunt, both of which look identical
## from the hallway: the statue manifests, then wanders off and never arrives.
##
##   godot --headless --script tests/villa_ghost_chase_smoke.gd
##
## 1. V01, the grand staircase in the room the player spawns in, baked as a
##    navigation island joined to the landing above and to nothing below. A
##    route from the foyer to the landing five metres up went 152 m around the
##    whole building, and the statue - which only ever hunts a target on its
##    own storey - never took the stairs at all.
## 2. Every internal doorway in the villa carries a closed door leaf. The
##    navmesh is deliberately baked with those leaves lifted out, so ghost
##    routes run straight through doorways; nothing then opened them, and the
##    first door on the route held the hunt for the rest of the night.

## Foot and head of V01, and the foyer floor either side of the door on its
## south wall. Read off the spec rather than the scene so a re-bake cannot
## silently move the test.
const FOYER_FLOOR := Vector3(40.0, 0.15, 5.0)
const V01_LANDING := Vector3(44.5, 4.3, 5.0)
const CORRIDOR_NORTH := Vector3(19.0, 0.15, 13.0)
const FOYER_TARGET := Vector3(33.0, 1.0, 5.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main_scene := (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	if not await _navigation_ready(main_scene):
		_fail("The villa navigation map never came up.")
		return

	var player := main_scene.get_node("Player") as CharacterBody3D
	var statue := main_scene.get_node("StatueGhost") as CharacterBody3D
	# A statue that can see a player freezes, which does not belong in a test
	# about whether it can get there at all.
	statue.set("intermittent_hunts_enabled", false)
	statue.set("unseen_grace_time", 0.0)
	await physics_frame

	if not await _stairs(player, statue):
		return
	if not await _doors(main_scene, player, statue):
		return

	print(
		"Villa ghost chase smoke test passed: the statue climbed V01 out of the "
		+ "foyer and shouldered an interior door open to reach a player behind it."
	)
	quit()


## Player on the upper landing, statue at the bottom of the same staircase.
func _stairs(player: CharacterBody3D, statue: CharacterBody3D) -> bool:
	player.global_position = V01_LANDING
	statue.global_position = FOYER_FLOOR
	await physics_frame

	var highest := statue.global_position.y
	for _frame: int in 60 * 15:
		await physics_frame
		highest = maxf(highest, statue.global_position.y)
		if highest >= V01_LANDING.y - 1.2:
			return true
	_fail(
		"The statue never climbed V01: it reached y=%.2f from y=%.2f, ending at %s."
		% [highest, FOYER_FLOOR.y, statue.global_position]
	)
	return false


## Player in the foyer, statue in the corridor behind it, one shut door between.
func _doors(main_scene: Node, player: CharacterBody3D, statue: CharacterBody3D) -> bool:
	var doors := get_nodes_in_group("villa_interior_doors")
	if doors.size() < 40:
		_fail("The villa built %d interior doors; expected the spec's full set." % doors.size())
		return false
	for door: Node in doors:
		if not door.get("ghost_shoulder_enabled"):
			_fail("%s cannot be shouldered open, so no ghost can pass it." % door.name)
			return false

	player.global_position = FOYER_TARGET
	statue.global_position = CORRIDOR_NORTH
	await physics_frame

	var closest := INF
	for _frame: int in 60 * 20:
		await physics_frame
		closest = minf(closest, statue.global_position.distance_to(player.global_position))
		if closest <= 2.0:
			return true
	_fail(
		"The statue got no closer than %.1f m to a player one doorway away, "
		% closest
		+ "stopping at %s." % statue.global_position
	)
	return false


func _navigation_ready(main_scene: Node) -> bool:
	for _attempt: int in 600:
		if bool(main_scene.get("navigation_is_ready")):
			return true
		await physics_frame
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

extends SceneTree

## The flat-room smoke test proves the huntsman's rules; this proves it can
## actually apply them inside House2. It is dropped into the main hall with
## nothing to track, and has to quarter the real building - which means routing
## across the baked navmesh, through doorways and between rooms - rather than
## grinding against the first wall it meets.

## How near a sweep marker counts as having searched that room.
const VISIT_DISTANCE := 2.5
const SWEEP_SECONDS := 18.0
const REQUIRED_VISITS := 2
## Second half: how long a motionless player upstairs may go un-found, and how
## close counts as found.
const HUNT_SECONDS := 45.0
const REACH_DISTANCE := 3.0
## Third: how long a player may stand at the head of the stairs, in plain sight,
## with a bannister between them, and live.
const RAIL_SECONDS := 12.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load('res://main.tscn') as PackedScene
	if not packed:
		_fail('Main scene could not be loaded.')
		return

	var game := packed.instantiate()
	root.add_child(game)
	# Two physics frames so main.gd's deferred collision and navmesh bake, and the
	# hunter's deferred route resolution, have both completed.
	await physics_frame
	await physics_frame

	var hunter := game.get_node('HunterGhost') as CharacterBody3D
	var player := game.get_node('Player') as CharacterBody3D
	if not hunter or not player:
		_fail('Main scene is missing the huntsman or the player.')
		return

	# Isolate the sweep: the other two ghosts stay still, no doors are attacked,
	# and the huntsman is given nothing to smell and nothing to see, so the only
	# thing that can move it is its own search route.
	(game.get_node('DoorAttackDirector') as Node).set('automatic_waves', false)
	(game.get_node('StatueGhost') as Node).set_physics_process(false)
	(game.get_node('CrawlerGhost') as Node).set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 100.0, 0.0)
	hunter.set('entry_enabled', false)
	hunter.set('nose_range', 0.0)
	hunter.set('sight_range', 0.0)
	hunter.set('cast_duration', 0.4)
	# Faster than it walks in the game, purely so the test does not have to run
	# for a minute to observe two rooms.
	hunter.set('walk_speed', 3.2)
	for node_name: String in [
		'FootstepAudio',
		'HookAudio',
		'BreathAudio',
		'SniffAudio',
		'HornAudio',
		'SeizeAudio',
		'BreachAudio',
	]:
		var audio_player := hunter.get_node_or_null(node_name) as AudioStreamPlayer3D
		if audio_player:
			audio_player.stop()
			audio_player.stream = null

	var markers: Array[Node3D] = []
	for node: Node in get_nodes_in_group('hunter_sweep_points'):
		var marker := node as Node3D
		if marker:
			markers.append(marker)
	if markers.size() < 4:
		_fail('House2 does not carry a hunter sweep route (%d markers).' % markers.size())
		return

	hunter.global_position = Vector3(0.0, 0.4, 0.0)
	await physics_frame
	if not bool(hunter.call('dev_force_spawn', null)):
		_fail('The huntsman could not be placed in the house.')
		return

	var start := hunter.global_position
	var visited: Dictionary = {}
	var elapsed := 0.0
	while elapsed < SWEEP_SECONDS:
		await create_timer(0.2).timeout
		elapsed += 0.2
		for index: int in markers.size():
			if hunter.global_position.distance_to(markers[index].global_position) <= VISIT_DISTANCE:
				visited[markers[index].name] = true

	var travelled := start.distance_to(hunter.global_position)
	if visited.size() < REQUIRED_VISITS:
		_fail(
			'Huntsman searched %d of %d rooms in %.0f s (moved %.2f m from %s to %s).' % [
				visited.size(),
				markers.size(),
				SWEEP_SECONDS,
				travelled,
				start,
				hunter.global_position,
			]
		)
		return

	# Second half: give it its senses back, put a motionless player upstairs, and
	# require it to arrive. Standing still is the counterplay to the crawler and
	# it must not work here - and "it never came" is the exact way this creature
	# fails when its search or its pathing quietly breaks.
	hunter.set('nose_range', 8.5)
	hunter.set('sight_range', 15.0)
	# Player upstairs in the west bedroom, motionless; huntsman two floors below
	# in the boiler room with its memory wiped. It has to search its way there.
	player.global_position = Vector3(-4.0, 3.9, 3.0)
	player.velocity = Vector3.ZERO
	await physics_frame
	hunter.global_position = Vector3(4.0, -2.6, 2.0)
	hunter.call('dev_force_spawn', null)
	await physics_frame
	var hunt_start := hunter.global_position

	var hunt_elapsed := 0.0
	var closest := INF
	while hunt_elapsed < HUNT_SECONDS:
		await create_timer(0.25).timeout
		hunt_elapsed += 0.25
		closest = minf(closest, hunter.global_position.distance_to(player.global_position))
		if closest <= REACH_DISTANCE:
			break

	if closest > REACH_DISTANCE:
		_fail(
			'A player who stood perfectly still upstairs was never reached from %s: closest %.2f m in %.0f s (huntsman at %s, state %d).' % [
				hunt_start,
				closest,
				HUNT_SECONDS,
				hunter.global_position,
				int(hunter.get('state')),
			]
		)
		return

	# Third: the stairwell head, which is where it kept failing in play. The
	# player stands on the second floor a couple of metres from a huntsman that
	# has arrived at the top of the stairs with the bannister between them. It has
	# them in plain sight the whole time, so standing there must be fatal - this
	# is the case where it used to press against the rail, slide back and forth,
	# and then quietly go back to sniffing.
	player.global_position = Vector3(1.5, 3.9, 3.0)
	await physics_frame
	hunter.global_position = Vector3(0.0, 3.2, 4.6)
	hunter.call('dev_force_spawn', null)
	hunter.global_position = Vector3(0.0, 3.2, 4.6)
	await physics_frame

	var rail_elapsed := 0.0
	while rail_elapsed < RAIL_SECONDS and bool(player.get('is_alive')):
		await create_timer(0.25).timeout
		rail_elapsed += 0.25

	if bool(player.get('is_alive')):
		_fail(
			'A player standing at the head of the stairs survived %.0f s in plain sight: huntsman at %s, state %d, %.2f m away.' % [
				RAIL_SECONDS,
				hunter.global_position,
				int(hunter.get('state')),
				hunter.global_position.distance_to(player.global_position),
			]
		)
		return

	game.queue_free()
	await process_frame
	await physics_frame
	print(
		'House hunter sweep smoke test passed: %d rooms searched in %.0f s %s (%.1f m from start); a motionless player two floors up reached from %s at %.2f m in %.1f s; a player at the head of the stairs taken in %.1f s.'
			% [
				visited.size(),
				SWEEP_SECONDS,
				visited.keys(),
				travelled,
				hunt_start,
				closest,
				hunt_elapsed,
				rail_elapsed,
			]
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

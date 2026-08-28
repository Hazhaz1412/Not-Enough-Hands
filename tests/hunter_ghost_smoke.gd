extends SceneTree

## Covers the things that define the huntsman and would silently rot: it only
## gets in through a breached door, it follows the trail a player leaves on the
## floor, it hears a player who is upright but not one who is crouched, it locks
## on the instant it sees you and its grab kills, losing you makes it walk away
## rather than straight back onto you, sealing the last breach traps it inside -
## and once it is in, it never leaves.

const FLOOR_Y := 0.0
const DOOR_Z := 6.0

# HunterState lives on the hunter's script, which this SceneTree script has no
# static handle on. These mirror the enum's declaration order.
const HunterState_DORMANT := 0
const HunterState_ENTERING := 1
const HunterState_TRACKING := 2
const HunterState_LOCKED := 5
const HunterState_ROARING := 8
const HunterState_DISENGAGING := 9

var hunter_scene: PackedScene
var door_scene: PackedScene


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_room()
	hunter_scene = load('res://ghosts/hunter_ghost.tscn') as PackedScene
	door_scene = load('res://door/defense_door.tscn') as PackedScene

	if not await _test_enters_through_a_breach():
		return
	if not await _test_sealing_before_arrival_keeps_it_out():
		return
	if not await _test_follows_the_trail():
		return
	if not await _test_unreachable_mark_does_not_freeze_it():
		return
	if not await _test_sight_lock_and_seize():
		return
	if not await _test_chase_override_and_five_second_memory():
		return
	if not await _test_minigame_safety_blocks_the_grab():
		return
	if not await _test_sealing_the_last_breach_traps_it():
		return
	if not await _test_it_never_leaves():
		return
	if not await _test_hearing_range_scales_with_loudness():
		return

	print(
		'Hunter ghost smoke test passed: breach entry, sealed-out, trail following, '
		+ 'unreachable-mark recovery, sight lock and seize, chase override, '
		+ 'five-second sight memory, fair-play disengage, attack safety, sealed-in, '
		+ 'never leaves, hearing.'
	)
	quit()


## A bare floor slab. Everything this creature does is on the ground, so there is
## deliberately no ceiling or wall geometry to confuse the navigation fallback.
func _build_room() -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 60.0)
	shape_node.shape = box
	body.add_child(shape_node)
	root.add_child(body)
	body.global_position = Vector3(0.0, FLOOR_Y - 0.1, 0.0)


func _add_sight_blocker(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.0, 0.3)
	shape_node.shape = box
	body.add_child(shape_node)
	root.add_child(body)
	body.global_position = at
	return body


## The house centre is derived from the sweep route, so the route is what tells
## the huntsman which side of a doorway is indoors.
func _add_sweep_markers() -> Array[Node3D]:
	var markers: Array[Node3D] = []
	for point: Vector3 in [Vector3(0.0, 0.2, 0.0), Vector3(3.0, 0.2, -3.0), Vector3(-3.0, 0.2, -3.0)]:
		var marker := Marker3D.new()
		marker.add_to_group('hunter_sweep_points')
		root.add_child(marker)
		marker.global_position = point
		markers.append(marker)
	return markers


func _add_door() -> Node3D:
	var door := door_scene.instantiate() as Node3D
	root.add_child(door)
	door.global_position = Vector3(0.0, FLOOR_Y, DOOR_Z)
	for node_name: String in ['WarningAudio', 'StrongAttackAudio']:
		var audio_player := door.get_node_or_null(node_name) as AudioStreamPlayer3D
		if audio_player:
			audio_player.stop()
			audio_player.stream = null
	return door


func _spawn_hunter(at: Vector3, overrides: Dictionary = {}) -> CharacterBody3D:
	var hunter := hunter_scene.instantiate() as CharacterBody3D
	hunter.set('entry_delay_min', 0.4)
	hunter.set('entry_delay_max', 0.4)
	for key: String in overrides:
		hunter.set(key, overrides[key])
	root.add_child(hunter)
	hunter.global_position = at
	_silence(hunter)
	# Route and door subscriptions are resolved one deferred call after _ready.
	await process_frame
	await physics_frame
	return hunter


func _spawn_player(at: Vector3) -> CharacterBody3D:
	var player := (load('res://player/player.tscn') as PackedScene).instantiate() as CharacterBody3D
	player.set('automatic_blink_enabled', false)
	root.add_child(player)
	player.global_position = at
	return player


## queue_free only takes effect at the end of the idle frame, so a bare
## `await physics_frame` would leave the previous actor in the world and the next
## one spawns embedded in it.
func _despawn(node: Node) -> void:
	node.queue_free()
	await process_frame
	await physics_frame


func _despawn_all(nodes: Array) -> void:
	for node: Node in nodes:
		await _despawn(node)


## The audio streams are irrelevant to the behaviour under test and a headless
## run has nowhere to play them.
func _silence(hunter: Node) -> void:
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


## The entry contract: it is not in the world at all until a door actually
## breaks, and then it walks in through that doorway on foot.
func _test_enters_through_a_breach() -> bool:
	var markers := _add_sweep_markers()
	var door := _add_door()
	var hunter := await _spawn_hunter(Vector3(0.0, 0.15, 20.0))

	if hunter.get('manifested'):
		return _fail('Huntsman was already in the world with every door intact.', hunter)

	door.call('take_damage', 999.0, true)
	await create_timer(0.8).timeout

	if not hunter.get('manifested'):
		return _fail('A breached door did not bring the huntsman to the doorway.', hunter)
	if hunter.global_position.z <= DOOR_Z:
		return _fail(
			'Huntsman appeared inside the house instead of outside the breach (z %.2f).'
				% hunter.global_position.z,
			hunter
		)

	await create_timer(4.0).timeout

	if not hunter.get('inside_house'):
		return _fail('Huntsman never finished walking in through the breach.', hunter)
	if hunter.global_position.z > DOOR_Z - 1.0:
		return _fail(
			'Huntsman is still in the doorway rather than in the house (z %.2f).'
				% hunter.global_position.z,
			hunter
		)

	await _despawn(hunter)
	await _despawn(door)
	await _despawn_all(markers)
	return true


## Rebuilding the door inside the entry delay is the whole reward for repairing
## fast: nothing ever comes in.
func _test_sealing_before_arrival_keeps_it_out() -> bool:
	var markers := _add_sweep_markers()
	var door := _add_door()
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 20.0),
		{'entry_delay_min': 3.0, 'entry_delay_max': 3.0}
	)

	door.call('take_damage', 999.0, true)
	await physics_frame
	door.set('repair_unlocked_after_breach', true)
	door.call('repair', 100.0)
	await create_timer(4.0).timeout

	if hunter.get('manifested') or hunter.get('inside_house'):
		return _fail('A door rebuilt before the huntsman arrived still let it in.', hunter)
	if int(hunter.get('state')) != HunterState_DORMANT:
		return _fail('Huntsman left its dormant state without a standing breach.', hunter)

	await _despawn(hunter)
	await _despawn(door)
	await _despawn_all(markers)
	return true


## The signature behaviour: it is given no noise, no sight and no target, only
## the marks a player left walking across the floor, and it has to follow them.
func _test_follows_the_trail() -> bool:
	var markers := _add_sweep_markers()
	# Sight off, so nothing here can be explained by it seeing them.
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 0.0),
		{
			'entry_enabled': false,
			'sight_range': 0.0,
			'cast_duration': 0.2,
			'hearing_range': 0.0,
		}
	)
	var player := _spawn_player(Vector3(1.5, 0.9, 0.0))
	await physics_frame

	hunter.call('dev_force_spawn', null)
	var start_x: float = hunter.global_position.x
	# Lay a trail out along +x by walking the player away one step at a time. The
	# huntsman is already following it while the trail is still being laid, which
	# is exactly the intended behaviour, so travel is measured from here.
	for step: int in 18:
		player.global_position = Vector3(1.5 + step * 0.55, 0.9, 0.0)
		await create_timer(0.2).timeout

	if hunter.call('get_trail_size') <= 0:
		return _fail('No trail was recorded for a player walking around the house.', hunter)
	if not hunter.call('has_trail_lead') \
		and hunter.global_position.distance_to(player.global_position) > 3.5:
		return _fail('Huntsman neither held the fresh trail nor already reached its owner.', hunter)

	await create_timer(6.0).timeout
	var travelled: float = hunter.global_position.x - start_x

	if travelled < 5.0:
		return _fail(
			'Huntsman did not follow the trail: moved %.2f m along it.' % travelled,
			hunter
		)
	# Following the marks has to actually deliver it to whoever left them.
	var reached: float = hunter.global_position.distance_to(player.global_position)
	if reached > 3.5:
		return _fail(
			'Huntsman followed the trail but never closed on the player (%.2f m away).' % reached,
			hunter
		)

	await _despawn(hunter)
	await _despawn(player)
	await _despawn_all(markers)
	return true


## The failure this creature is most prone to: a mark it can smell but cannot
## walk to - one left above its head, or behind a wall it has no way through -
## used to fixate it forever, and the whole hunt ended with it standing in place.
## It has to notice it is getting nowhere, drop that mark, and carry on hunting.
func _test_unreachable_mark_does_not_freeze_it() -> bool:
	var markers := _add_sweep_markers()
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 0.0),
		{
			'entry_enabled': false,
			'sight_range': 0.0,
			# This isolated test deliberately makes the impossible airborne mark
			# readable. Normal gameplay keeps the close nose to the current floor.
			'nose_height_range': 5.0,
			'cast_duration': 0.2,
			'stuck_release_time': 1.0,
			'trail_point_timeout': 3.0,
		}
	)
	# Standing on nothing, four metres up: readable, and completely unreachable.
	var player := _spawn_player(Vector3(0.0, 4.0, 3.0))
	player.set_physics_process(false)
	await physics_frame

	hunter.call('dev_force_spawn', null)
	await create_timer(1.5).timeout
	if not hunter.call('has_trail_lead'):
		return _fail('Huntsman could not smell the marks it is supposed to fixate on.', hunter)

	# Long enough that a fixated huntsman would still be standing under them.
	await create_timer(8.0).timeout

	if int(hunter.get('state')) == HunterState_TRACKING and hunter.call('has_trail_lead'):
		return _fail(
			'Huntsman is still reading a mark it has had eight seconds to fail to reach.',
			hunter
		)
	if hunter.global_position.distance_to(Vector3(0.0, 0.15, 0.0)) < 1.0:
		return _fail(
			'Huntsman never moved off the spot under an unreachable mark.',
			hunter
		)

	await _despawn(hunter)
	await _despawn(player)
	await _despawn_all(markers)
	return true


## Sight into a roar, roar into a charge, charge into a grab that kills. The
## roar is the whole warning the player gets, so "it stood still and screamed
## before it moved" is a contract and not a flourish.
func _test_sight_lock_and_seize() -> bool:
	var markers := _add_sweep_markers()
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 0.0),
		{'entry_enabled': false, 'seize_windup': 0.2}
	)
	# Standing behind it: it is covered in eyes, so facing has nothing to do
	# with whether it sees you.
	var player := _spawn_player(Vector3(0.0, 0.9, 4.0))
	await physics_frame

	hunter.call('dev_force_spawn', null)
	hunter.rotation.y = 0.0

	var locked := [false]
	hunter.locked_on.connect(func(_target: Node3D) -> void: locked[0] = true)
	await physics_frame
	await physics_frame
	if not locked[0]:
		return _fail('Huntsman did not see a player standing behind it in the open.', hunter)
	if int(hunter.get('state')) != HunterState_ROARING:
		return _fail('Huntsman started moving without roaring first.', hunter)
	if Vector2(hunter.velocity.x, hunter.velocity.z).length() > 0.5:
		return _fail('Huntsman moved during its roar; the warning has to be a full stop.', hunter)

	# Held for the full roar: the warning is the head start, so a roar that ends
	# early is the difference between escapable and not.
	await create_timer(2.0).timeout
	if int(hunter.get('state')) != HunterState_ROARING:
		return _fail('Huntsman cut its roar short and started moving early.', hunter)
	await create_timer(0.9).timeout
	if int(hunter.get('state')) != HunterState_LOCKED:
		return _fail('Huntsman never came out of its roar into the charge.', hunter)

	await create_timer(3.0).timeout
	if player.get('is_alive'):
		return _fail('Huntsman charged a locked player without ever seizing them.', hunter)

	await _despawn(hunter)
	await _despawn(player)
	await _despawn_all(markers)
	return true


## A sighting owns the state machine. Even a forced tracking transition is
## overwritten on the next frame, and a wall must hide the player continuously
## for the complete five-second grace before the target is released.
func _test_chase_override_and_five_second_memory() -> bool:
	var markers := _add_sweep_markers()
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 0.0),
		{
			'entry_enabled': false,
			'charge_speed': 0.0,
			'seize_range': 0.0,
			'lose_sight_time': 5.0,
		}
	)
	var player := _spawn_player(Vector3(0.0, 0.9, -6.0))
	await physics_frame
	hunter.call('dev_force_spawn', null)
	hunter.call('_lock_on', player)
	hunter.call('_set_state', HunterState_TRACKING)
	await physics_frame
	if int(hunter.get('state')) != HunterState_LOCKED:
		return _fail('A lower-priority tracking state overwrote a live chase.', hunter)

	var blocker := _add_sight_blocker(Vector3(0.0, 1.5, -3.0))
	await physics_frame
	await create_timer(4.6).timeout
	if int(hunter.get('state')) != HunterState_LOCKED or hunter.get('current_target') != player:
		return _fail('Huntsman dropped an occluded target before five seconds elapsed.', hunter)
	await create_timer(0.7).timeout
	if int(hunter.get('state')) == HunterState_LOCKED or hunter.get('current_target') != null:
		return _fail('Huntsman kept chasing after five uninterrupted seconds without sight.', hunter)

	# Fair play: having genuinely lost them it turns around and walks away from
	# where they went, rather than reading the very fresh trail it is standing on
	# and coming straight back. The trail clock is reset to the moment it gave up
	# for the same reason.
	if int(hunter.get('state')) != HunterState_DISENGAGING:
		return _fail('Huntsman did not disengage after losing its target.', hunter)
	var seen_at: Vector3 = hunter.get('last_seen_position')
	var away_from_prey: Vector3 = hunter.get('_disengage_point') - seen_at
	var hunter_from_prey := hunter.global_position - seen_at
	away_from_prey.y = 0.0
	hunter_from_prey.y = 0.0
	if away_from_prey.length() <= hunter_from_prey.length():
		return _fail('Huntsman "walked away" to somewhere no further from its prey.', hunter)

	var before := hunter.global_position
	await create_timer(2.0).timeout
	if hunter.global_position.distance_to(seen_at) <= before.distance_to(seen_at):
		return _fail('Huntsman is disengaging but is not actually getting further away.', hunter)
	if hunter.get('_has_last_seen_lead'):
		return _fail('Huntsman is still holding the corner it lost them at.', hunter)

	# Nothing it does short of a charge is faster than its patrol pace, and that
	# pace is slower than a walking player: while it has not seen you, it is
	# beatable on foot.
	var patrol_speed := float(hunter.call('_non_chase_speed', float(hunter.get('walk_speed'))))
	if not is_equal_approx(patrol_speed, 2.0):
		return _fail('Patrol pace is not 2 m/s (%.2f).' % patrol_speed, hunter)

	await _despawn(blocker)
	await _despawn(hunter)
	await _despawn(player)
	await _despawn_all(markers)
	return true


## The shared ghost safety contract: while the door minigame owns the screen no
## hostile ghost may land an attack, and this one is no exception.
func _test_minigame_safety_blocks_the_grab() -> bool:
	var markers := _add_sweep_markers()
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 0.0),
		{'entry_enabled': false, 'seize_windup': 0.2}
	)
	var player := _spawn_player(Vector3(0.0, 0.9, -2.5))
	await physics_frame

	hunter.call('dev_force_spawn', null)
	hunter.rotation.y = 0.0
	hunter.call('set_dev_attack_suspended', true)
	await create_timer(3.0).timeout

	if not player.get('is_alive'):
		return _fail('Huntsman killed a player while its attacks were suspended.', hunter)

	await _despawn(hunter)
	await _despawn(player)
	await _despawn_all(markers)
	return true


## The bargain the whole creature is built around: repair every breach while it
## is inside and it has nowhere left to go - which no longer means it wanted to.
func _test_sealing_the_last_breach_traps_it() -> bool:
	var markers := _add_sweep_markers()
	var door := _add_door()
	var hunter := await _spawn_hunter(Vector3(0.0, 0.15, 20.0), {'entry_enabled': true})

	door.call('take_damage', 999.0, true)
	await create_timer(4.0).timeout
	if not hunter.get('inside_house'):
		return _fail('Huntsman never got inside, so it cannot be sealed in.', hunter)

	var sealed := [false]
	hunter.sealed_inside.connect(func() -> void: sealed[0] = true)
	door.set('repair_unlocked_after_breach', true)
	door.call('repair', 100.0)
	await physics_frame

	if not sealed[0]:
		return _fail('Rebuilding the last breach did not seal the huntsman in.', hunter)
	if not hunter.get('trapped'):
		return _fail('Huntsman is sealed in but does not know it.', hunter)

	await _despawn(hunter)
	await _despawn(door)
	await _despawn_all(markers)
	return true


## It never leaves. There is no hunt timer to run out and no walking back out
## through the hole it came in by, so a wide-open breach and a long quiet stretch
## still finds it inside.
func _test_it_never_leaves() -> bool:
	var markers := _add_sweep_markers()
	var door := _add_door()
	var hunter := await _spawn_hunter(Vector3(0.0, 0.15, 20.0))

	door.call('take_damage', 999.0, true)
	await create_timer(4.0).timeout
	if not hunter.get('inside_house'):
		return _fail('Huntsman never got inside, so it cannot be shown to stay.', hunter)

	# The breach it walked in through is still a hole and nothing is hunting it
	# out. Twelve seconds of that used to be a full exit.
	await create_timer(12.0).timeout
	if not hunter.get('inside_house'):
		return _fail('Huntsman left the house; it is supposed to be in there until dawn.', hunter)
	if not hunter.get('manifested'):
		return _fail('Huntsman is still flagged as inside but has left the world.', hunter)
	if int(hunter.get('state')) == HunterState_DORMANT:
		return _fail('Huntsman went dormant while inside the house.', hunter)

	await _despawn(hunter)
	await _despawn(door)
	await _despawn_all(markers)
	return true


## Its ears. Louder carries further on the same curve as the crawler's, on a
## smaller radius - and crouch-walking is under the floor at any distance, which
## is the one movement it cannot hear.
func _test_hearing_range_scales_with_loudness() -> bool:
	var markers := _add_sweep_markers()
	var hunter := await _spawn_hunter(Vector3(0.0, 0.15, 0.0), {'entry_enabled': false})
	hunter.call('dev_force_spawn', null)
	await physics_frame

	var reach: float = hunter.get('hearing_range')
	var cases := [
		# [label, loudness, distance, should_hear]
		['a crouched player right next to it', 0.09, 2.0, false],
		['a player walking upright a room away', 0.43, reach * 0.35, true],
		['a player walking upright across the house', 0.43, reach * 0.9, false],
		['a sprinting player across the house', 1.0, reach * 0.9, true],
	]
	for entry: Array in cases:
		hunter.set('_has_noise_lead', false)
		hunter.call(
			'report_noise', Vector3(float(entry[2]), 0.15, 0.0), float(entry[1]), null
		)
		var heard: bool = hunter.get('_has_noise_lead')
		if heard != bool(entry[3]):
			return _fail(
				'It %s %s.' % ['heard' if heard else 'did not hear', entry[0]],
				hunter
			)

	await _despawn(hunter)
	await _despawn_all(markers)
	return true


func _fail(message: String, hunter: Node = null) -> bool:
	if hunter:
		push_error('%s (state %s, position %s)' % [
			message,
			hunter.get('state'),
			hunter.global_position,
		])
	else:
		push_error(message)
	quit(1)
	return false

extends SceneTree

## Covers the three things that define the crawler and would silently rot:
## it grips walls and ceilings, it hunts noise rather than sight, and going
## quiet actually loses it.

const FLOOR_Y := 0.0
const CEILING_Y := 3.0

# CrawlerState lives on the crawler's script, which this SceneTree script has no
# static handle on. These mirror the enum's declaration order.
const CrawlerState_HIDDEN := 1
const CrawlerState_OMEN := 2
const CrawlerState_PATROL := 3
const CrawlerState_POUNCING := 7
const CrawlerState_RETREATING := 9
const CrawlerState_LEAVING := 10


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_room()

	var crawler_scene := load('res://ghosts/crawler_ghost.tscn') as PackedScene

	if not await _test_floor_hunt(crawler_scene):
		return
	if not await _test_ceiling_cling(crawler_scene):
		return
	if not await _test_wall_climb(crawler_scene):
		return
	if not await _test_silence_breaks_the_trail(crawler_scene):
		return
	if not await _test_pounce_kill(crawler_scene):
		return
	if not await _test_maul_at_contact(crawler_scene):
		return
	if not await _test_a_distant_noise_is_walked_down(crawler_scene):
		return
	if not await _test_loitering_hands_the_room_back(crawler_scene):
		return
	if not await _test_a_kill_does_not_leave_it_standing_on_the_body(crawler_scene):
		return
	if not await _test_containment_recovers_escape(crawler_scene):
		return
	if not await _test_hunt_cycle(crawler_scene):
		return
	if not await _test_hidden_is_harmless(crawler_scene):
		return

	print(
		'Crawler ghost smoke test passed: noise hunt, ceiling cling, wall climb, '
		+ 'silence, pounce, contact kill, leap line, loiter timeout, kill disengage, '
		+ 'containment, hunt cycle, harmless while hidden.'
	)
	quit()


## A closed box: floor, ceiling and one wall at x = 6, all static bodies on the
## world layer the crawler probes for.
func _build_room() -> void:
	_add_slab(Vector3(0.0, FLOOR_Y - 0.1, 0.0), Vector3(24.0, 0.2, 24.0))
	_add_slab(Vector3(0.0, CEILING_Y + 0.1, 0.0), Vector3(24.0, 0.2, 24.0))
	_add_slab(Vector3(6.1, 1.5, 0.0), Vector3(0.2, 3.0, 24.0))


func _add_slab(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	root.add_child(body)
	body.global_position = center


## Spawns a crawler with the hunt cycle switched off, so it starts already
## patrolling and reacts to noise immediately. The cycle itself is covered
## separately by _test_hunt_cycle.
func _spawn_crawler(scene: PackedScene, at: Vector3) -> CharacterBody3D:
	var crawler := scene.instantiate() as CharacterBody3D
	crawler.set('hunt_cycle_enabled', false)
	crawler.set('start_hidden', false)
	root.add_child(crawler)
	crawler.global_position = at
	_silence(crawler)
	return crawler


## queue_free only takes effect at the end of the idle frame, so a bare
## `await physics_frame` leaves the corpse of the previous crawler in the world
## - and the next actor spawned at the same spot starts the frame embedded in a
## solid body and gets flung across the room by depenetration.
func _despawn(node: Node) -> void:
	node.queue_free()
	await process_frame
	await physics_frame


## The audio streams are irrelevant to the behaviour under test and a headless
## run has nowhere to play them.
func _silence(crawler: Node) -> void:
	for node_name: String in ['CrawlAudio', 'ChitterAudio', 'BreathAudio', 'ScreamAudio', 'BoneAudio']:
		var audio_player := crawler.get_node_or_null(node_name) as AudioStreamPlayer3D
		if audio_player:
			audio_player.stop()
			audio_player.stream = null


func _test_floor_hunt(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(0.0, 0.4, 0.0))
	await physics_frame
	await physics_frame

	if not crawler.get('has_surface'):
		return _fail('Crawler did not grip the floor it was dropped onto.', crawler)

	var start := crawler.global_position
	crawler.call('report_noise', Vector3(-8.0, 0.35, 0.0), 1.0)
	await create_timer(0.9).timeout

	var travelled := start.x - crawler.global_position.x
	if travelled < 1.0:
		return _fail(
			'Crawler did not crawl toward a reported noise: moved %.2f m.' % travelled,
			crawler
		)
	await _despawn(crawler)
	return true


## Dropped against the ceiling it must stay there under its own adhesion rather
## than falling, which is the whole point of the surface locomotion.
func _test_ceiling_cling(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(0.0, CEILING_Y - 0.3, 0.0))
	crawler.set('surface_normal', Vector3.DOWN)
	await physics_frame
	await physics_frame

	if not crawler.get('has_surface'):
		return _fail('Crawler did not grip the ceiling.', crawler)

	var clung_y: float = crawler.global_position.y
	crawler.call('report_noise', Vector3(-7.0, 0.35, 0.0), 1.0)
	await create_timer(1.0).timeout

	var drop: float = clung_y - crawler.global_position.y
	if drop > 0.35:
		return _fail('Crawler fell off the ceiling: dropped %.2f m.' % drop, crawler)

	var normal: Vector3 = crawler.get('surface_normal')
	if normal.dot(Vector3.DOWN) < 0.7:
		return _fail('Crawler stopped treating the ceiling as its surface.', crawler)
	await _despawn(crawler)
	return true


## Sent at a noise on the far side of a wall it has to leave the floor and take
## the wall, rather than grinding into it forever.
func _test_wall_climb(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(4.0, 0.4, 0.0))
	await physics_frame
	await physics_frame

	# Noise beyond and above the wall: the only route is up the face of it.
	crawler.call('report_noise', Vector3(6.0, 2.6, 0.0), 1.0)
	await create_timer(2.5).timeout

	var climbed: float = crawler.global_position.y - 0.4
	if climbed < 0.5:
		return _fail(
			'Crawler never left the floor for the wall: climbed %.2f m.' % climbed,
			crawler
		)

	# Anything that is not a floor counts. It reliably takes the wall, but if it
	# gets there fast enough it carries on over the top lip onto the ceiling,
	# and demanding a specifically vertical normal would fail that better run.
	var normal: Vector3 = crawler.get('surface_normal')
	if normal.dot(Vector3.UP) > 0.6:
		return _fail(
			'Crawler gained height but is still anchored to a floor (normal %s).' % normal,
			crawler
		)
	await _despawn(crawler)
	return true


## The stealth contract: a fix on a noise decays, so a player who stops making
## any decays out of its attention entirely.
func _test_silence_breaks_the_trail(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(0.0, 0.4, 0.0))
	crawler.set('trail_decay', 2.0)
	await physics_frame

	crawler.call('report_noise', Vector3(-5.0, 0.35, 0.0), 1.0)
	if not crawler.get('has_noise_fix'):
		return _fail('Crawler ignored a noise well inside its hearing range.', crawler)

	await create_timer(1.2).timeout
	if crawler.get('has_noise_fix'):
		return _fail('Crawler kept its fix on a noise that stopped over a second ago.', crawler)

	# Far outside hearing range even at full loudness: it must not react at all.
	crawler.call('report_noise', Vector3(0.0, 0.35, -200.0), 1.0)
	if crawler.get('has_noise_fix'):
		return _fail('Crawler heard a noise 200 m away.', crawler)
	await _despawn(crawler)
	return true


func _spawn_player(at: Vector3) -> CharacterBody3D:
	var player := (load('res://player/player.tscn') as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	player.global_position = at
	return player


func _test_pounce_kill(scene: PackedScene) -> bool:
	var player := _spawn_player(Vector3(-4.0, 0.9, 4.0))
	var crawler := _spawn_crawler(scene, Vector3(-4.0, 0.4, 0.8))
	crawler.set('pounce_windup', 0.15)
	crawler.set('pounce_recovery', 0.1)
	await physics_frame
	await physics_frame

	crawler.call('report_noise', player.global_position, 1.0, player)
	await create_timer(2.0).timeout

	if player.get('is_alive'):
		return _fail('Crawler never pounced on a loud player standing three metres away.', crawler)

	await _despawn(crawler)
	await _despawn(player)
	return true


## A pounce has a minimum range, so contact range needs its own kill or the
## creature is safe to stand next to. Spawned just inside that minimum and just
## outside contact range: the only way this can resolve is by crawling the last
## half-metre and mauling.
func _test_maul_at_contact(scene: PackedScene) -> bool:
	var player := _spawn_player(Vector3(3.0, 0.9, -4.0))
	var crawler := _spawn_crawler(scene, Vector3(3.0, 0.4, -5.2))
	await physics_frame
	await physics_frame

	crawler.call('report_noise', player.global_position, 1.0, player)
	await create_timer(1.2).timeout

	if player.get('is_alive'):
		return _fail('Crawler reached a player at contact range without killing them.', crawler)

	await _despawn(crawler)
	await _despawn(player)
	return true


## The leap line. Outside pounce_range there is no leap at all - it walks the
## noise down - and the same player inside it is a valid candidate, so this
## pins the boundary itself rather than just the far side of it. Read off the
## export rather than hardcoded, because where the line sits is a balance dial.
func _test_a_distant_noise_is_walked_down(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(-5.0, 0.4, 0.0))
	var pounce_range: float = crawler.get('pounce_range')
	var player := _spawn_player(crawler.global_position + Vector3(0.0, 0.5, pounce_range + 2.0))
	await physics_frame
	await physics_frame

	crawler.call('report_noise', player.global_position, 1.0, player)
	await physics_frame
	if crawler.call('_pounce_candidate') != null:
		return _fail('Crawler was willing to leap at a player beyond pounce_range.', crawler)

	var start := crawler.global_position
	await create_timer(0.8).timeout
	if crawler.global_position.distance_to(start) < 0.5:
		return _fail('Crawler neither leapt nor closed on a noise outside pounce_range.', crawler)

	# Same player, same fix, now inside the line: the leap has to be back on.
	player.global_position = crawler.global_position + Vector3(0.0, 0.5, pounce_range - 3.0)
	crawler.call('report_noise', player.global_position, 1.0, player)
	await physics_frame
	if crawler.call('_pounce_candidate') == null:
		return _fail('Crawler refused to leap at a player well inside pounce_range.', crawler)

	await _despawn(crawler)
	await _despawn(player)
	return true


## It may not camp on somebody. Held next to a player with every attack
## suspended - the state that used to leave it orbiting them for the whole hunt
## - it has to give the room back once loiter_tolerance is up, and to actually
## put distance between them rather than just changing state.
func _test_loitering_hands_the_room_back(scene: PackedScene) -> bool:
	var player := _spawn_player(Vector3(-4.0, 0.9, -4.0))
	var crawler := _spawn_crawler(scene, Vector3(-4.0, 0.4, -2.5))
	crawler.set('loiter_tolerance', 0.5)
	crawler.set('leave_distance', 6.0)
	# Suspended attacks are the honest way to hold it in the "next to a player
	# and unable to resolve it" state this watchdog exists for; without it the
	# maul simply kills them and the other test below is what runs.
	crawler.call('set_dev_attack_suspended', true)
	await physics_frame
	await physics_frame

	crawler.call('report_noise', player.global_position, 1.0, player)
	await create_timer(1.2).timeout
	if int(crawler.get('state')) != CrawlerState_LEAVING:
		return _fail(
			'Crawler sat next to a player past loiter_tolerance instead of leaving (state=%d).'
				% int(crawler.get('state')),
			crawler
		)

	# Measured from where it turned round rather than from the player: the
	# retreat is a route to a destination chosen away from everyone, and a
	# surface crawler takes that route around and over things rather than
	# straight, so the straight line back to the player is not what moves.
	# Polled rather than sampled once for the same reason - a single slice can
	# land on a wall transition, which is slow and is not a failure.
	var turned_at := crawler.global_position
	var travelled := 0.0
	for _sample: int in 40:
		await create_timer(0.1).timeout
		travelled = maxf(travelled, crawler.global_position.distance_to(turned_at))
		if travelled >= 3.0:
			break
	if travelled < 3.0:
		return _fail(
			'Crawler entered LEAVING but only ever got %.2f m from where it turned.' % travelled,
			crawler
		)

	await _despawn(crawler)
	await _despawn(player)
	return true


## The corpse is the one body guaranteed to still be underneath it, and folding
## up on top of one is how the creature used to wedge itself for the rest of a
## hunt. A kill has to end with it walking away.
func _test_a_kill_does_not_leave_it_standing_on_the_body(scene: PackedScene) -> bool:
	var player := _spawn_player(Vector3(0.0, 0.9, 8.0))
	var crawler := _spawn_crawler(scene, Vector3(0.0, 0.4, 6.8))
	crawler.set('leave_distance', 6.0)
	await physics_frame
	await physics_frame

	crawler.call('report_noise', player.global_position, 1.0, player)
	await create_timer(1.2).timeout
	if player.get('is_alive'):
		return _fail('Crawler did not kill the player this check is about.', crawler)
	if int(crawler.get('state')) != CrawlerState_LEAVING:
		return _fail(
			'Crawler stayed on the body after a kill (state=%d).' % int(crawler.get('state')),
			crawler
		)

	var killed_at := crawler.global_position
	await create_timer(1.5).timeout
	if crawler.global_position.distance_to(killed_at) < 1.0:
		return _fail('Crawler is leaving after a kill but never left the kill site.', crawler)

	await _despawn(crawler)
	await _despawn(player)
	return true


## Wall crawling and pouncing deliberately ignore navigation, so the authored
## level volume is the final guard against crossing a doorway and gripping the
## outside wall forever.
func _test_containment_recovers_escape(scene: PackedScene) -> bool:
	var crawler := scene.instantiate() as CharacterBody3D
	crawler.set('hunt_cycle_enabled', false)
	crawler.set('start_hidden', false)
	crawler.set('containment_enabled', true)
	crawler.set('containment_min', Vector3(-2.0, -0.5, -2.0))
	crawler.set('containment_max', Vector3(2.0, 3.5, 2.0))
	root.add_child(crawler)
	crawler.global_position = Vector3(0.0, 0.4, 0.0)
	_silence(crawler)
	await physics_frame
	await physics_frame

	var recovery_count := [0]
	crawler.containment_recovered.connect(
		func(_escaped: Vector3, _recovered: Vector3) -> void: recovery_count[0] += 1
	)
	crawler.set('state', CrawlerState_POUNCING)
	crawler.global_position = Vector3(3.0, 0.4, 0.0)
	crawler.velocity = Vector3(12.0, 0.0, 0.0)
	await physics_frame

	if absf(crawler.global_position.x) > 2.0 or absf(crawler.global_position.z) > 2.0:
		return _fail('Crawler escaped its authored containment volume.', crawler)
	if recovery_count[0] != 1:
		return _fail('Crawler escape did not trigger exactly one containment recovery.', crawler)
	if int(crawler.get('state')) == CrawlerState_POUNCING:
		return _fail('Crawler remained in pounce state after boundary recovery.', crawler)

	crawler.set('has_noise_fix', false)
	crawler.call('report_noise', Vector3(3.0, 0.4, 0.0), 1.0)
	if crawler.get('has_noise_fix'):
		return _fail('Noise outside containment lured the crawler out of the house.', crawler)

	await _despawn(crawler)
	return true


## The whole announced cycle: hidden, then a fly-past, then a patrol of the
## route, then a scream and gone. Every stage has to be reachable without a
## player ever making a sound.
func _test_hunt_cycle(scene: PackedScene) -> bool:
	var lair := Node3D.new()
	lair.add_to_group('crawler_lair')
	root.add_child(lair)
	lair.global_position = Vector3(-8.0, 0.4, -8.0)

	var route: Array[Vector3] = [
		Vector3(-8.0, 0.4, 8.0),
		Vector3(0.0, 0.4, 8.0),
		Vector3(0.0, 0.4, -8.0),
	]
	var markers: Array[Node3D] = []
	for point: Vector3 in route:
		var marker := Node3D.new()
		marker.add_to_group('crawler_patrol_points')
		root.add_child(marker)
		marker.global_position = point
		markers.append(marker)

	# Well clear of the wall at x = 6.1 and of the slab edges, so the fly-past
	# has standable floor on both sides of this player's sightline.
	var player := _spawn_player(Vector3(-4.0, 0.9, 6.0))

	var crawler := scene.instantiate() as CharacterBody3D
	crawler.set('initial_hidden_delay_min', 0.3)
	crawler.set('initial_hidden_delay_max', 0.3)
	crawler.set('patrol_laps', 1)
	crawler.set('patrol_point_timeout', 2.5)
	crawler.set('crawl_speed', 9.0)  # a patrol at its real pace outlasts a test
	crawler.set('retreat_scream_duration', 0.2)
	crawler.set('hidden_delay_min', 99.0)
	crawler.set('hidden_delay_max', 99.0)
	root.add_child(crawler)
	crawler.global_position = Vector3(-8.0, 0.4, -8.0)
	_silence(crawler)

	var seen: Array[int] = []
	crawler.state_changed.connect(func(new_state: int) -> void: seen.append(new_state))

	await physics_frame
	if crawler.get('state') != CrawlerState_HIDDEN:
		return _fail('Crawler did not start its cycle hidden.', crawler)
	if crawler.get_node('VisualRoot').visible:
		return _fail('Hidden crawler was still visible.', crawler)

	await create_timer(14.0).timeout

	if not seen.has(CrawlerState_OMEN):
		return _fail('Cycle never played the fly-past omen (states seen: %s).' % [seen], crawler)
	if not seen.has(CrawlerState_PATROL):
		return _fail('Cycle never reached a patrol (states seen: %s).' % [seen], crawler)
	if not seen.has(CrawlerState_RETREATING):
		return _fail('Cycle never gave up and retreated (states seen: %s).' % [seen], crawler)
	if crawler.get('state') != CrawlerState_HIDDEN:
		return _fail('Crawler did not go back into hiding after retreating.', crawler)
	if not player.get('is_alive'):
		return _fail('A full unprovoked cycle killed a player who made no noise.', crawler)

	await _despawn(crawler)
	await _despawn(player)
	for marker: Node3D in markers:
		await _despawn(marker)
	await _despawn(lair)
	return true


## While hidden it is not in the world at all, so noise cannot summon it
## straight into a hunt - the omen always comes first.
func _test_hidden_is_harmless(scene: PackedScene) -> bool:
	var crawler := scene.instantiate() as CharacterBody3D
	crawler.set('initial_hidden_delay_min', 60.0)
	crawler.set('initial_hidden_delay_max', 60.0)
	root.add_child(crawler)
	crawler.global_position = Vector3(0.0, 0.4, 0.0)
	_silence(crawler)

	var player := _spawn_player(Vector3(0.6, 0.9, 0.0))
	await create_timer(0.6).timeout

	crawler.call('report_noise', player.global_position, 1.0, player)
	await create_timer(0.5).timeout

	if crawler.get('state') != CrawlerState_HIDDEN:
		return _fail('A noise pulled the crawler straight out of hiding.', crawler)
	if not player.get('is_alive'):
		return _fail('A hidden crawler killed a player standing on top of it.', crawler)

	await _despawn(crawler)
	await _despawn(player)
	return true


func _fail(message: String, crawler: Node = null) -> bool:
	if crawler:
		push_error('%s (state %s, position %s)' % [
			message,
			crawler.get('state'),
			crawler.global_position,
		])
	else:
		push_error(message)
	quit(1)
	return false

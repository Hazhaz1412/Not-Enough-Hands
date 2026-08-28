extends SceneTree

## Covers how the crawler actually gets about, which is the half of it the
## behavioural smoke test takes for granted: that it works its way round an
## obstruction instead of shoving at the face of it, that a moving player cannot
## blind it to being wedged, that its search sweeps pick somewhere real, and
## that in a house with a baked navigation mesh it still leaves the floor for
## the walls and the ceiling.
##
## The escape tests run in floor-only mode (`wall_crawling_enabled = false`),
## the same control the main smoke test uses. Climbing an obstruction is the
## crawler's own answer to most of these and a perfectly good one, but it is the
## answer that already worked; switching it off isolates the ground steering,
## which is what was grinding. The last two tests switch it back on.

## Mirrors the crawler script's enum declaration order.
const CrawlerState_PATROL := 3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var crawler_scene := load('res://ghosts/crawler_ghost.tscn') as PackedScene

	# Navigation is added only once the escape tests are done, so those measure
	# the straight-line steering and the climb test measures the interaction
	# with a navigation mesh. The two areas sit far enough apart not to see one
	# another's geometry.
	_build_panel_room()
	if not await _test_rounds_an_obstruction(crawler_scene):
		return
	if not await _test_sidesteps_toward_the_open_side(crawler_scene):
		return
	if not await _test_stalling_in_the_open_is_not_a_sidestep(crawler_scene):
		return
	if not await _test_search_points_stay_out_of_walls(crawler_scene):
		return
	if not await _test_moving_player_cannot_hide_a_wedge(crawler_scene):
		return

	_build_climb_room()
	_add_navigation_floor()
	await physics_frame
	await physics_frame
	if not await _test_takes_the_wall_despite_navigation(crawler_scene):
		return

	print(
		'Crawler locomotion smoke test passed: rounds an obstruction, sidesteps '
		+ 'toward the open side, no sidestep in open floor, search points stay '
		+ 'on the near side of a wall, a moving player cannot hide a wedge, '
		+ 'patrol leaves the floor with a navmesh present.'
	)
	quit()


# --- World --------------------------------------------------------------------


## Open floor and one lopsided obstruction. The panel reaches only to z = +1 on
## one side and to z = -4 on the other, so exactly one of the two sidesteps
## leads anywhere and a coin flip cannot be scored as a pass.
func _build_panel_room() -> void:
	_add_slab(Vector3(0.0, -0.1, 0.0), Vector3(40.0, 0.2, 40.0))
	_add_slab(Vector3(1.0, 1.5, -1.5), Vector3(0.3, 3.0, 5.0))


## A room with a ceiling and a wall with no way round it, well away from the
## panel. Crossing it means going up.
func _build_climb_room() -> void:
	_add_slab(Vector3(60.0, -0.1, 0.0), Vector3(24.0, 0.2, 24.0))
	_add_slab(Vector3(60.0, 3.1, 0.0), Vector3(24.0, 0.2, 24.0))
	_add_slab(Vector3(63.0, 1.5, 0.0), Vector3(0.3, 3.0, 24.0))

	# Grouped after it is in the tree: the crawler reads its route out of the
	# scene tree's group index, which only knows about nodes that are in it.
	var marker := Marker3D.new()
	root.add_child(marker)
	marker.global_position = Vector3(66.0, 0.2, 0.0)
	marker.add_to_group('crawler_patrol_points')


## A hand-authored floor polygon rather than a bake: all the crawler asks is
## whether its map has any region at all, and baking would drag the whole
## navigation generation setup into a test that is not about navigation quality.
func _add_navigation_floor() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.vertices = PackedVector3Array([
		Vector3(48.0, 0.0, -12.0),
		Vector3(48.0, 0.0, 12.0),
		Vector3(72.0, 0.0, 12.0),
		Vector3(72.0, 0.0, -12.0),
	])
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nav_mesh
	root.add_child(region)


func _add_slab(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	root.add_child(body)
	body.global_position = center


func _spawn_crawler(scene: PackedScene, at: Vector3, climbing: bool = false) -> CharacterBody3D:
	var crawler := scene.instantiate() as CharacterBody3D
	crawler.set('hunt_cycle_enabled', false)
	crawler.set('start_hidden', false)
	crawler.set('wall_crawling_enabled', climbing)
	root.add_child(crawler)
	crawler.global_position = at
	_silence(crawler)
	return crawler


func _despawn(node: Node) -> void:
	node.queue_free()
	await process_frame
	await physics_frame


func _silence(crawler: Node) -> void:
	for node_name: String in ['CrawlAudio', 'ChitterAudio', 'BreathAudio', 'ScreamAudio', 'BoneAudio']:
		var audio_player := crawler.get_node_or_null(node_name) as AudioStreamPlayer3D
		if audio_player:
			audio_player.stop()
			audio_player.stream = null


## Holds the fix on the noise open. A real player keeps making noise while the
## crawler works its way over; `trail_decay` would otherwise drop it into a
## search sweep mid-detour and the run would be measuring the sweep instead.
func _keep_noise_alive(crawler: CharacterBody3D, at: Vector3) -> void:
	crawler.call('report_noise', at, 1.0)


# --- Escape -------------------------------------------------------------------


## The outcome. Noise straight through the panel, and the only route to it is
## round the short end.
func _test_rounds_an_obstruction(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(0.0, 0.4, 0.0))
	await physics_frame
	await physics_frame

	var noise := Vector3(4.0, 0.35, 0.0)
	var elapsed := 0.0
	var best_x: float = crawler.global_position.x
	while elapsed < 8.0:
		_keep_noise_alive(crawler, noise)
		await physics_frame
		elapsed += root.get_process_delta_time()
		best_x = maxf(best_x, crawler.global_position.x)
		if best_x > 1.6:
			break

	if best_x <= 1.6:
		return _fail(
			'Crawler never got past the panel: best x %.2f after %.1f s.' % [best_x, elapsed],
			crawler
		)
	await _despawn(crawler)
	return true


## The decision, asserted on its own rather than through a run.
##
## Which way it goes is the whole of what the sidestep adds, and it is not
## something an outcome test can pin down: a crawler pinned against a panel for
## long enough drifts round the end of it by accident often enough that "did it
## eventually get past" passes with the choice removed. So the choice is made
## here directly, against known geometry, with no physics race in it.
func _test_sidesteps_toward_the_open_side(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(0.45, 0.4, 0.0))
	await physics_frame
	await physics_frame

	# Re-planted rather than driven here, so the probes see exactly the setup
	# this is reasoning about: hard against the panel face, level with its near
	# end at z = +1, with the far end four metres the other way.
	crawler.global_position = Vector3(0.45, crawler.global_position.y, 0.0)
	crawler.set('surface_normal', Vector3.UP)
	crawler.set('steering_goal', Vector3(4.0, 0.35, 0.0))
	crawler.call('_begin_wedge_escape')

	if crawler.get('wedge_escape_timer') <= 0.0:
		return _fail('Crawler found no way out of a panel it could walk round.', crawler)
	var chosen: Vector3 = crawler.get('wedge_escape_direction')
	if chosen.z <= 0.5:
		return _fail(
			'Crawler sidestepped along the length of the panel instead of round '
			+ 'the near end of it: %s.' % chosen,
			crawler
		)
	await _despawn(crawler)
	return true


## A crawler that is simply braked - arrived, nothing in the way - must not
## decide it is wedged and slide off sideways. The sidestep is an answer to
## geometry, not to standing still.
func _test_stalling_in_the_open_is_not_a_sidestep(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(-12.0, 0.4, 12.0))
	await physics_frame
	await physics_frame

	# Noise right where it already is: it arrives immediately and has no reason
	# to travel, but it never gets anywhere either, which is the exact reading
	# the wedge detector acts on. Sweeping away over open floor is the correct
	# answer here and is not measured; starting a sidestep is not.
	var elapsed := 0.0
	while elapsed < 3.0:
		_keep_noise_alive(crawler, crawler.global_position)
		await physics_frame
		elapsed += root.get_process_delta_time()
		if crawler.get('wedge_escape_timer') > 0.0:
			return _fail('Crawler sidestepped with nothing in its way.', crawler)
	await _despawn(crawler)
	return true


## Search sweeps used to pick a random point on a disc around the noise with no
## check at all, which put points inside walls and in the next room - and a
## point inside a wall is one the crawler shoves at for a full search interval
## before it is handed another. Every point it picks must now have clear line of
## sight from the noise it is sweeping around.
func _test_search_points_stay_out_of_walls(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(0.0, 0.4, -1.5))
	await physics_frame

	# Beside the panel and at body height, so the disc of candidates straddles
	# it and the probes are not grazing the floor.
	var noise := Vector3(0.0, 0.6, -1.5)
	var space := root.get_world_3d().direct_space_state
	var swept := 0
	for _attempt: int in 40:
		# Re-asserted every iteration because _pick_search_point reads the
		# crawler's own fix, and a patrol with no route sweeps the lair instead.
		crawler.set('last_noise_position', noise)
		var point: Vector3 = crawler.call('_pick_search_point')
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(noise, point)
		)
		if not hit.is_empty():
			return _fail(
				'Search sweep picked a point through the panel: %s (blocked at %s).'
				% [point, hit['position']],
				crawler
			)
		if noise.distance_to(point) > 1.0:
			swept += 1

	# Rejecting everything and standing on the noise would pass the check above
	# while being a worse sweep than the one it replaced.
	if swept < 20:
		return _fail(
			'Search sweep collapsed onto the noise: only %d of 40 points were a '
			% swept + 'sweep at all.',
			crawler
		)
	await _despawn(crawler)
	return true


## The reported failure, reproduced: pinned on a ceiling with the player walking
## about behind a wall, shoving into the same corner indefinitely.
##
## The cause was that the wedge detector measured progress as "am I nearer the
## goal than I have ever been", and rebased itself whenever the goal moved more
## than half a metre. During a hunt the goal is the player's last noise, so it
## moves constantly, and the detector was handed a clean slate several times a
## second - it could never accumulate enough to conclude anything, and the
## release that would have dropped the crawler back onto the floor, where
## navigation knows about the door, never fired.
##
## So the noise here deliberately walks about, which is what defeated the old
## code, and the crawler must still work out that it is going nowhere.
func _test_moving_player_cannot_hide_a_wedge(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(0.45, 0.4, -1.5), true)
	await physics_frame
	await physics_frame

	var released := false
	crawler.connect('surface_changed', func(_normal: Vector3) -> void: released = true)

	var elapsed := 0.0
	var wandered := 0.0
	while elapsed < 4.0:
		# Behind the panel throughout, and never twice in the same place - a
		# metre of travel between frames, far more than the half metre that used
		# to rebase the detector.
		wandered += 0.6
		_keep_noise_alive(crawler, Vector3(4.0, 0.35, -1.5 + sin(wandered) * 3.0))
		await physics_frame
		elapsed += root.get_process_delta_time()
		if crawler.get('no_progress_time') >= crawler.get('wedge_probe_time'):
			await _despawn(crawler)
			return true

	return _fail(
		'Crawler shoved at the panel for %.1f s without ever noticing, because '
		% elapsed + 'the noise it was chasing kept moving.',
		crawler
	)


# --- Climbing -----------------------------------------------------------------


## The wall and ceiling crawling is the creature's whole identity, and it was
## unreachable in both shipping maps.
##
## The climb bias is only ever added to the straight line to the marker, and
## straight-line steering was skipped entirely whenever the crawler stood on
## walkable ground and the level had a navigation mesh - which is every patrol
## step in both houses, since both bake one at runtime. So it routed politely
## round the floor plan and never once left the floor, while the same crawler in
## a bare test box climbed exactly as designed. This puts a navigation mesh
## under it and a wall in front of it and insists it still goes up.
func _test_takes_the_wall_despite_navigation(scene: PackedScene) -> bool:
	var crawler := _spawn_crawler(scene, Vector3(60.0, 0.4, 0.0), true)
	await process_frame
	await physics_frame

	if not crawler.call('_has_navigation'):
		return _fail('Test never got a navigation mesh in place to steer against.', crawler)
	var route: Array = crawler.get('patrol_points')
	if route.is_empty():
		return _fail('Crawler never picked up the patrol marker.', crawler)

	# Restarted on the route deliberately. Route resolution is deferred, so a
	# crawler that gets a physics frame before that lands sees an empty route,
	# drops into a sweep, and stays there for the whole of `search_duration` -
	# which is a spawn-ordering detail of the test harness and nothing to do
	# with climbing, but would otherwise silently decide what this measures.
	crawler.call('_begin_patrol')
	if crawler.get('state') != CrawlerState_PATROL:
		return _fail('Crawler is not patrolling, so no climb bias applies.', crawler)

	var elapsed := 0.0
	var best_height: float = crawler.global_position.y
	var clung := 0.0
	while elapsed < 8.0:
		await physics_frame
		var step := root.get_process_delta_time()
		elapsed += step
		best_height = maxf(best_height, crawler.global_position.y)
		var normal: Vector3 = crawler.get('surface_normal')
		if crawler.get('has_surface') and normal.dot(Vector3.UP) <= 0.6:
			clung += step

	if best_height < 1.2:
		return _fail(
			'Crawler stayed on the floor for the whole patrol: highest point %.2f m.'
			% best_height,
			crawler
		)
	# Height on its own could be a bounce or a shove up the face of the wall.
	# Time spent actually holding onto something that is not a floor is what
	# distinguishes crawling over the wall from climbing at it. Measured across
	# the run rather than at the end, because arriving at the marker on the far
	# side means coming back down, and that arrival is a success.
	if clung < 0.75:
		return _fail(
			'Crawler gained height without ever holding a wall or ceiling: %.2f s clung.'
			% clung,
			crawler
		)
	await _despawn(crawler)
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

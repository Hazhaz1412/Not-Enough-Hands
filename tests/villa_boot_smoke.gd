extends SceneTree

## Boots the villa map exactly as a player would get it: full kit detail,
## defense doors placed from the spec anchors, and a baked navmesh that has to
## carry an agent from the front hall down to the cellar door and up to the
## attic skylight - the two ends of spec section 4's travel-time table.
##
##   godot --headless --script tests/villa_boot_smoke.gd

const MAX_BUILD_SECONDS := 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var started := Time.get_ticks_msec()
	var main_scene := (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	for _frame: int in 6:
		await process_frame
	await physics_frame
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	if elapsed > MAX_BUILD_SECONDS:
		_fail("Villa took %.1f s to build and bake; budget is %.0f s." % [elapsed, MAX_BUILD_SECONDS])
		return

	var house := main_scene.get_node_or_null("VillaHouse") as Node3D
	if not house or not house.has_node("Generated"):
		_fail("villa_main.tscn did not build the villa.")
		return
	if not _restrooms_are_furnished(house):
		return

	var entrance_ids: Array[int] = []
	var authored_outward: Dictionary = {}
	for anchor_node: Node in get_nodes_in_group("villa_entrance_anchors"):
		var anchor := anchor_node as Marker3D
		if not bool(anchor.get_meta("overhead", false)):
			authored_outward[int(anchor.get_meta("entrance_id"))] = anchor.global_basis.z.normalized()
	# Entrance 07 is the attic skylight, so it sits in the ceiling above the
	# attic floor rather than on it.
	var elevations := {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: -3.5, 6: 3.5, 7: 10.5}
	for node: Node in get_nodes_in_group("defense_doors"):
		var entrance_id := int(node.get("entrance_id"))
		entrance_ids.append(entrance_id)
		if not elevations.has(entrance_id):
			_fail("Unexpected entrance id %d." % entrance_id)
			return
		if absf((node as Node3D).global_position.y - elevations[entrance_id]) > 0.01:
			_fail("Entrance %02d sits at y=%.2f, expected %.2f."
				% [entrance_id, (node as Node3D).global_position.y, elevations[entrance_id]])
			return
		if entrance_id != 7:
			var exterior: Vector3 = (node as Node3D).get_meta("exterior_outward", Vector3.ZERO)
			if exterior.dot(authored_outward.get(entrance_id, Vector3.ZERO)) < 0.999:
				_fail("Entrance %02d did not preserve its authored exterior direction." % entrance_id)
				return
	entrance_ids.sort()
	if entrance_ids != [1, 2, 3, 4, 5, 6, 7]:
		_fail("Villa entrances are incomplete or duplicated: %s." % [entrance_ids])
		return

	var region := main_scene.get_node_or_null("VillaNavigationRegion") as NavigationRegion3D
	if not region or region.navigation_mesh.get_polygon_count() == 0:
		_fail("The villa baked an empty navmesh.")
		return

	var player := main_scene.get_node_or_null("Player") as Node3D
	var spawn := (get_nodes_in_group("villa_spawn_points")[0] as Node3D).global_position
	if not player or player.global_position.distance_to(spawn) > 2.0:
		_fail("The player was not placed on SP_PLAYER_1.")
		return

	if not await _navigation_map_ready(main_scene, spawn):
		_fail("The navigation map never came up around the player spawn.")
		return
	if not _crawler_can_spawn(main_scene, player):
		return

	if not _reaches("R_FOYER", "R_COAL"):
		return
	if not _reaches("R_FOYER", "R_ATTIC"):
		return
	if not _reaches("R_LIBRARY", "R_KITCHEN"):
		return
	if not _routes_are_usable(spawn):
		return
	if not _stairs_meet_their_floors():
		return

	print(
		"Villa boot smoke test passed in %.1f s: 7 defense doors, %d navmesh polygons, "
		% [elapsed, region.navigation_mesh.get_polygon_count()]
		+ "hall to cellar, hall to attic and library to kitchen all routable."
	)
	quit()


## The crawler scene defaults to House2's small -9..9 m containment box.  The
## villa occupies 0..80 by 0..60 m, so carrying those defaults over clamps a
## forced spawn to (8.45, 8.45) outside the playable rooms and rejects every
## noise made by a player in the villa.
func _crawler_can_spawn(main_scene: Node, player: Node3D) -> bool:
	var crawler := main_scene.get_node_or_null("CrawlerGhost") as CharacterBody3D
	if not crawler:
		_fail("villa_main.tscn has no crawler instance for Dev Tools to spawn.")
		return false

	for group: String in ["crawler_patrol_points", "crawler_lair"]:
		for node: Node in get_nodes_in_group(group):
			var marker := node as Node3D
			if marker and not bool(crawler.call("_is_inside_containment", marker.global_position)):
				_fail("Crawler containment excludes villa route marker %s at %s."
					% [marker.name, marker.global_position])
				return false

	if not bool(crawler.call("dev_force_spawn", player)) \
			or not bool(crawler.get("manifested")) \
			or not bool(crawler.call("_is_inside_containment", crawler.global_position)):
		_fail("Dev Tools could not manifest the crawler inside the villa.")
		return false

	# Keep the boot test about wiring and navigation after the spawn contract is
	# established; crawler behaviour has its own focused smoke tests.
	crawler.set_physics_process(false)
	return true


func _restrooms_are_furnished(house: Node3D) -> bool:
	var restroom_paths := [
		"Generated/Level_F_00/Props/R_WC_GROUND_NORTHProps",
		"Generated/Level_F_00/Props/R_WC_GROUND_SOUTHProps",
		"Generated/Level_F_01/Props/R_WC_UP_NORTHProps",
		"Generated/Level_F_01/Props/R_WC_UP_SOUTHProps",
	]
	for restroom_path: String in restroom_paths:
		var props := house.get_node_or_null(restroom_path)
		if not props:
			_fail("Missing furnished restroom %s." % restroom_path)
			return false
		for fixture: String in ["Toilet", "Sink", "Mirror"]:
			var expected_path := VillaHouse.FURNITURE_ROOT + fixture + ".fbx"
			var count := 0
			for node: Node in props.find_children("*", "Node3D", true, false):
				if String(node.get_meta("source_asset", "")) == expected_path:
					count += 1
			if count != 1:
				_fail("%s has %d %s fixture(s), expected exactly one."
					% [restroom_path, count, fixture])
				return false
	var toilets := get_nodes_in_group("villa_toilets")
	if toilets.size() != 5:
		_fail("Villa has %d interactive toilets; expected four WCs plus the main bath."
			% toilets.size())
		return false
	return true


## The imported stair's railing is taller than its treads. This measures the
## tread mesh itself so accidentally scaling from the full railing AABB cannot
## leave the final step floating below its landing again.
func _stairs_meet_their_floors() -> bool:
	var visuals := get_nodes_in_group("smooth_stair_visual")
	if visuals.size() != 7:
		_fail("Expected 7 stair visuals, found %d." % visuals.size())
		return false
	for node: Node in visuals:
		var visual := node as Node3D
		var tread: MeshInstance3D
		for child: Node in visual.find_children("*", "MeshInstance3D", true, false):
			var candidate := child as MeshInstance3D
			var candidate_bounds := candidate.mesh.get_aabb()
			if absf(candidate_bounds.position.y) < 0.01 \
					and absf(candidate_bounds.size.y - VillaHouse.KIT_STAIR_RISE) < 0.01:
				tread = candidate
				break
		if not tread:
			_fail("Stair %s has no measurable tread mesh." % visual.name)
			return false

		var bounds := tread.mesh.get_aabb()
		var bottom := INF
		var top := -INF
		for x: int in 2:
			for y: int in 2:
				for z: int in 2:
					var corner := bounds.position + bounds.size * Vector3(x, y, z)
					var world_y := tread.to_global(corner).y
					bottom = minf(bottom, world_y)
					top = maxf(top, world_y)
		var expected_bottom := float(visual.get_meta("stair_base_y"))
		var expected_top := float(visual.get_meta("stair_top_y"))
		if absf(bottom - expected_bottom) > 0.02 or absf(top - expected_top) > 0.02:
			_fail(
				"Stair %s spans y %.2f..%.2f, expected %.2f..%.2f."
				% [visual.name, bottom, top, expected_bottom, expected_top]
			)
			return false
	return true


## Baking a navmesh is synchronous, but the server only folds the new region
## into the map on one of its own sync steps. How many physics frames that
## takes is not fixed, so wait for the map to answer instead of counting
## frames and hoping - that guess made this test fail about one run in three.
func _navigation_map_ready(main_scene: Node, spawn: Vector3) -> bool:
	var map := root.get_world_3d().navigation_map
	for _attempt: int in 240:
		# Both halves matter. The region answers "where is the nearest floor"
		# a sync step or two before the stair links exist, and a route asked
		# for in that window walks around every staircase in the villa.
		if bool(main_scene.get("navigation_is_ready")) 				and NavigationServer3D.map_get_closest_point(map, spawn).distance_to(spawn) < 2.0:
			return true
		await physics_frame
	return false


## Every ghost route marker has to be somewhere a ghost can actually get to.
## This is the guard against furnishing a room shut: a wardrobe dropped across
## a doorway shows up here as an unreachable patrol point long before it shows
## up as a ghost standing still in a corner all night.
func _routes_are_usable(spawn: Vector3) -> bool:
	var map := root.get_world_3d().navigation_map
	var start := NavigationServer3D.map_get_closest_point(map, spawn)
	for group: String in ["crawler_patrol_points", "hunter_sweep_points", "crawler_lair"]:
		for node: Node in get_nodes_in_group(group):
			var point := (node as Node3D).global_position
			var closest := NavigationServer3D.map_get_closest_point(map, point)
			if closest.distance_to(point) > 1.5:
				_fail("Route marker %s has no navmesh within 1.5 m." % node.name)
				return false
			var path := NavigationServer3D.map_get_path(map, start, closest, true)
			if path.size() < 2 or path[-1].distance_to(closest) > 2.0:
				_fail("Route marker %s is unreachable from the player spawn." % node.name)
				return false
	return true


## Asks the navigation server for a real path between two room markers. The map
## is only worth anything if the ghosts can actually cross it.
func _reaches(from_room: String, to_room: String) -> bool:
	var from_marker := _room(from_room)
	var to_marker := _room(to_room)
	if not from_marker or not to_marker:
		_fail("Missing room marker for %s or %s." % [from_room, to_room])
		return false

	var map := root.get_world_3d().navigation_map
	# Probe the furniture-free tile each room publishes, not its geometric
	# centre: that is usually occupied by the room's own table.
	var from_point: Vector3 = from_marker.get_meta("clear_point", from_marker.global_position)
	var to_point: Vector3 = to_marker.get_meta("clear_point", to_marker.global_position)
	var start := NavigationServer3D.map_get_closest_point(map, from_point)
	var goal := NavigationServer3D.map_get_closest_point(map, to_point)
	if start.distance_to(from_point) > 4.0:
		_fail("%s has no navmesh under it." % from_room)
		return false
	if goal.distance_to(to_point) > 4.0:
		_fail("%s has no navmesh under it." % to_room)
		return false

	var path := NavigationServer3D.map_get_path(map, start, goal, true)
	if path.size() < 2 or path[-1].distance_to(goal) > 2.0:
		_fail("No navigation path from %s to %s." % [from_room, to_room])
		return false
	return true


func _room(room_id: String) -> Node3D:
	for node: Node in get_nodes_in_group("villa_rooms"):
		if String(node.get_meta("room_id", "")) == room_id:
			return node as Node3D
	return null


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

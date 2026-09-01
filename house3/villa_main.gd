extends Node3D

## Playable wiring for the Vanh Dai villa map.
##
## It plays the same role main.gd plays for House2, but the villa is roughly
## four times the floor area, so two things differ: the house authors its own
## box colliders (only loose props still need generated trimesh bodies), and
## the navmesh is baked at a coarser voxel size that Recast can actually chew
## through at 80 x 60 m.
##
## Everything downstream - player, ghosts, defense doors, power, audio - is
## driven off the same node groups House2 publishes, so nothing else changed.

## Emitted once the baked region *and* the stair links are both live in the
## NavigationServer. A region only enters the map on one of the server's own
## sync steps and a link needs another one after that, so until this fires the
## villa can answer "where is the nearest floor" while still having no route up
## any staircase.
signal navigation_ready

@export_category("Development")
@export var development_lighting: bool = false

var navigation_is_ready: bool = false

@onready var house: Node3D = $VillaHouse
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var moon_light: DirectionalLight3D = get_node_or_null("DirectionalLight3D")
const DEFENSE_DOOR: PackedScene = preload("res://door/defense_door.tscn")
const HUNTER_GHOST: PackedScene = preload("res://ghosts/hunter_ghost.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const PLAYER_SPAWN_OFFSETS: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(1.1, 0.0, 0.0),
	Vector3(-1.1, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.1),
]

## The stock defense door is built for House2's 3 m storey and 2.2 m opening.
## A villa entrance is two 2 m cells wide in a 3.5 m wall.
const DEFENSE_DOOR_SCALE := Vector3(1.55, 1.2, 1.0)
const VILLA_CELL := 2.0
const VILLA_STOREY := 3.5

## Height of the leaf's centre above the door node's own origin.
const DEFENSE_DOOR_LEAF_RISE := 1.15

## The villa has seven entrances and every one of them can break, so "one hunter
## per breach" had no ceiling at all. It matters more now than it used to for two
## reasons: a huntsman never leaves the house any more, so they only ever
## accumulate; and each one is a three-hundred-part body, so the fourth is a
## frame-rate problem before it is a difficulty problem. Three of them in a
## building this size is already everywhere at once.
const MAX_BREACH_HUNTERS := 3

## Mirrors NetworkManager.SERVER_PEER_ID, which cannot be named here: see _net().
const NETWORK_SERVER_PEER_ID := 1

## How long the Game Over card or the dawn overlay stands before the room is
## returned to the lobby.
const RUN_OVER_DELAY := 4.0

var _two_sided_cache: Dictionary = {}
## A breach can happen before Recast has finished baking.  Those hunters wait
## at the opening instead of trying to search without a navigation map.
var _hunters_waiting_for_navigation: Array[CharacterBody3D] = []
var _breach_hunter_serial: int = 0
## Every huntsman this level has spawned at a breach and not since freed.
var _breach_hunters: Array[CharacterBody3D] = []
## Set once the run has been decided, so the several things that can notice it
## in the same frame only end it once.
var _run_over_pending: bool = false


func _ready() -> void:
	navigation_ready.connect(_activate_waiting_hunters)
	if not development_lighting:
		_apply_horror_lighting()

	_place_defense_doors()
	_watch_breached_entrances()
	_setup_player_replication()
	_place_ghosts()

	for node: Node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			_make_mesh_two_sided(mesh_instance)
			if not _has_authored_collision(mesh_instance):
				mesh_instance.create_trimesh_collision()
				_enable_backface_collision(mesh_instance)

	_bake_navigation()


# --- map wiring --------------------------------------------------------------

## VillaHouse emits one anchor per spec entrance; the defense doors themselves
## belong to the game scene, exactly as they do in main.tscn.
func _place_defense_doors() -> void:
	var entrances := Node3D.new()
	entrances.name = "Entrances"
	add_child(entrances)

	var anchors := get_tree().get_nodes_in_group("villa_entrance_anchors")
	anchors.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get_meta("entrance_id")) < int(b.get_meta("entrance_id"))
	)
	for anchor_node: Node in anchors:
		var anchor := anchor_node as Marker3D
		_clear_baked_entrance_wall(anchor)
		var door := DEFENSE_DOOR.instantiate() as Node3D
		door.name = "Entrance%02d%s" % [
			int(anchor.get_meta("entrance_id")),
			String(anchor.get_meta("spec_id")),
		]
		door.set("entrance_id", int(anchor.get_meta("entrance_id")))
		entrances.add_child(door)
		door.scale = DEFENSE_DOOR_SCALE
		# The stock door scene was authored for House2, where local -Z means
		# outside. Villa entrance anchors use +Z for their authored outward
		# normal. Publish that map-specific direction instead of forcing the
		# minigame to guess it from a reused mesh's local axes.
		if not bool(anchor.get_meta("overhead", false)):
			door.set_meta("exterior_outward", anchor.global_basis.z.normalized())
		if bool(anchor.get_meta("overhead", false)):
			# Entrance 07 is a skylight. Tipping the leaf onto its back turns
			# the stock door into a boarded roof hatch in the attic ceiling,
			# instead of a slab standing in the middle of the floor. The leaf
			# is modelled upward from its origin, so it also needs shifting
			# back under the anchor once it is lying down.
			door.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			door.global_position = anchor.global_position + Vector3(
				0.0, 0.0, DEFENSE_DOOR_LEAF_RISE * DEFENSE_DOOR_SCALE.y
			)
		else:
			door.global_position = anchor.global_position
			door.global_rotation = anchor.global_rotation
		# Spec section 7 gives each entrance its own boarding budget; carry it
		# through so the far cellar door really is the one worth abandoning.
		door.set("max_durability", float(anchor.get_meta("layers")) * 40.0)
		door.set("repair_per_interaction", 60.0 / float(anchor.get_meta("repair_seconds")))


## villa_main.tscn contains artist-baked editable architecture. Older bakes
## include two full-height InteriorWall bodies across each BREACH opening: an
## artist can delete their visible modules and see outside, but the invisible
## CollisionShape3D still blocks the flashlight ray and the eventual breach.
## Disable those exact modules at runtime as a migration for existing bakes;
## VillaHouse now omits them when geometry is rebuilt.
func _clear_baked_entrance_wall(anchor: Marker3D) -> void:
	if bool(anchor.get_meta("overhead", false)):
		return
	var outward := anchor.global_basis.z.normalized()
	var tangent := anchor.global_basis.x.normalized()
	var expected_centre := anchor.global_position \
		+ outward * (VILLA_CELL * 0.5 + VillaHouse.WALL_THICKNESS * 0.5) \
		+ Vector3.UP * (VILLA_STOREY * 0.5)
	for node: Node in house.find_children("InteriorWall_*", "StaticBody3D", true, false):
		var wall := node as StaticBody3D
		var delta := wall.global_position - expected_centre
		if absf(delta.y) > 0.1 \
			or absf(delta.dot(outward)) > 0.05 \
			or absf(delta.dot(tangent)) > VILLA_CELL * 0.5 + 0.05:
			continue
		wall.add_to_group("villa_entrance_wall_cutouts")
		wall.collision_layer = 0
		wall.collision_mask = 0
		wall.visible = false
		for child: Node in wall.get_children():
			var collision := child as CollisionShape3D
			if collision:
				collision.disabled = true


## Every broken entrance adds one hunter at that breach, up to
## `MAX_BREACH_HUNTERS`.  The dormant hunter in the scene remains for DevTools
## only, so a door event produces one new threat rather than waking a global
## singleton as well.
func _watch_breached_entrances() -> void:
	for node: Node in get_tree().get_nodes_in_group("defense_doors"):
		if node.has_signal("breached") and not node.is_connected("breached", _on_entrance_breached):
			node.connect("breached", _on_entrance_breached)


func _on_entrance_breached(door: Node) -> void:
	# DefenseDoor disables its collider deferred during this signal.  Spawn on
	# the next idle step so the CharacterBody enters an actually open doorway.
	_spawn_hunter_at_breach.call_deferred(door)


func _spawn_hunter_at_breach(door: Node) -> void:
	var doorway := door as Node3D
	if not is_instance_valid(doorway) or not HUNTER_GHOST:
		return
	# A client hears `breached` too - apply_network_state() emits it when the
	# server's durability arrives - but the huntsman that answers it is one
	# body for the whole session, spawned here and replicated to everyone.
	if not WorldNet.is_world_authority():
		return
	if live_breach_hunter_count() >= MAX_BREACH_HUNTERS:
		# The house is already full. Every further breach is still a hole the
		# player has to live with - it just does not add a fourth body.
		return

	_breach_hunter_serial += 1
	var hunter := WorldNet.spawn(
		HUNTER_GHOST,
		self,
		doorway.global_position,
		0.0,
		"BreachHunter%02d" % _breach_hunter_serial
	) as CharacterBody3D
	if not hunter:
		return
	# This hunter belongs to one particular breach and must never let itself back
	# in through a different one, which would put it outside the cap.
	hunter.set("entry_enabled", false)
	if not hunter.has_method("spawn_from_breached_door") \
		or not bool(hunter.call("spawn_from_breached_door", doorway)):
		hunter.queue_free()
		return
	_breach_hunters.append(hunter)

	if navigation_is_ready:
		return
	hunter.set("active", false)
	_hunters_waiting_for_navigation.append(hunter)


## How many breach huntsmen are actually still in the world. Prunes as it counts,
## so a hunter that was freed for any reason gives its slot back.
func live_breach_hunter_count() -> int:
	for index: int in range(_breach_hunters.size() - 1, -1, -1):
		var hunter := _breach_hunters[index]
		if not is_instance_valid(hunter) or hunter.is_queued_for_deletion():
			_breach_hunters.remove_at(index)
	return _breach_hunters.size()


func _activate_waiting_hunters() -> void:
	for hunter: CharacterBody3D in _hunters_waiting_for_navigation:
		if is_instance_valid(hunter):
			hunter.set("active", true)
	_hunters_waiting_for_navigation.clear()


## The NetworkManager autoload, reached through the tree rather than by name.
##
## An autoload's identifier only resolves once the project's main loop is
## running, and the `--script` smoke tests compile this file as a dependency
## before that point - naming it directly stops the villa scene loading in them
## at all. Same reason player.gd and world_net.gd do the lookup this way.
func _net() -> Node:
	return get_node_or_null("/root/NetworkManager")


func _network_session_active() -> bool:
	var manager := _net()
	return manager != null and bool(manager.get("session_active"))


func _setup_player_replication() -> void:
	if _network_session_active():
		_net().player_spawn_requested.connect(_spawn_player_replica)
		_net().player_left.connect(_remove_network_player)
		if multiplayer.is_server():
			_net().player_world_ready.connect(_synchronize_room_players)
			for ready_peer: int in _net().world_ready_peers:
				_synchronize_room_players(ready_peer)
			# Dawn is the third way a night ends, and it leaves the session just
			# as stuck as a wipe does if nothing hands the room back.
			var clock := get_tree().get_first_node_in_group(&"night_clock")
			if clock and clock.has_signal(&"victory_reached"):
				clock.connect(
					&"victory_reached",
					func() -> void: _end_run_after_pause("Sống sót tới bình minh!")
				)
		_net().notify_world_ready()
	else:
		# F6 and the existing villa smoke tests retain a root node called Player.
		var offline_player := _build_player_from_spawn_data({
			"peer_id": 1,
			"display_name": "Player",
			"spawn_index": 0,
		})
		add_child(offline_player)


func _on_replicated_player_spawned(node: Node) -> void:
	var player := node as CharacterBody3D
	if not player or player.owner_peer_id != multiplayer.get_unique_id():
		return
	print(
		"NETWORK_LOCAL_PLAYER_SPAWNED peer=%d name=%s"
		% [player.owner_peer_id, player.display_name]
	)
	var manager := _net()
	if manager:
		manager.notify_replication_ready()
	if "--network-smoke" in OS.get_cmdline_user_args():
		_finish_network_smoke.call_deferred()


func _finish_network_smoke() -> void:
	# Give the reliable roster messages time to add players that were already in
	# the room before this client finished loading the Villa.
	await get_tree().process_frame
	await get_tree().process_frame
	var replicated_players := get_tree().get_nodes_in_group(&"players").size()
	var roster_players: int = _net().players.size()
	if replicated_players < roster_players:
		push_error(
			"Network smoke expected %d player(s), but only %d replicated."
			% [roster_players, replicated_players]
		)
		get_tree().quit(1)
		return
	print("NETWORK_ROSTER_REPLICATED count=%d" % replicated_players)
	get_tree().quit()


func _synchronize_room_players(_newly_ready_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_ids: Array = _net().players.keys()
	peer_ids.sort()
	for peer_id: int in peer_ids:
		_spawn_player_replica(
			peer_id,
			_net().get_player_name(peer_id),
			maxi(peer_ids.find(peer_id), 0)
		)
	# At four players a full idempotent roster sync is cheap, and it guarantees
	# that every ready client also receives players who joined before it.
	for target_peer_id: int in _net().world_ready_peers:
		if target_peer_id == NETWORK_SERVER_PEER_ID:
			continue
		for player_peer_id: int in peer_ids:
			_net().send_player_spawn(
				target_peer_id,
				player_peer_id,
				_net().get_player_name(player_peer_id),
				maxi(peer_ids.find(player_peer_id), 0)
			)


func _spawn_player_replica(peer_id: int, player_name: String, spawn_index: int) -> void:
	if _get_player_for_peer(peer_id):
		return
	var player := _build_player_from_spawn_data({
		"peer_id": peer_id,
		"display_name": player_name,
		"spawn_index": spawn_index,
	}) as CharacterBody3D
	add_child(player)
	_on_replicated_player_spawned(player)


func _build_player_from_spawn_data(data: Variant) -> Node:
	var spawn_data: Dictionary = data
	var peer_id := int(spawn_data.get("peer_id", 1))
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "Player" if peer_id == 1 else "Player_%d" % peer_id
	player.owner_peer_id = peer_id
	player.display_name = str(spawn_data.get("display_name", "Player"))
	# VillaMain has an identity transform, so this world-space marker position
	# is also the direct-child local position. The spawner has not added the
	# returned player to the tree yet, so assigning global_position here would
	# query an invalid global transform.
	player.position = _player_spawn_position(int(spawn_data.get("spawn_index", 0)))
	if _network_session_active() and multiplayer.is_server():
		# Both ways out of the run for a body: killed outright, or the downed
		# timer running out. Either can be the one that empties the house.
		player.killed_by_ghost.connect(func(_ghost: Node3D) -> void: _check_run_over())
		player.became_spectator.connect(_check_run_over)
	player.walk_speed = 2.6
	player.crouch_speed = 1.45
	player.sprint_speed_multiplier = 1.35
	player.forced_blink_duration = 0.25
	_configure_player_lighting.call_deferred(player)
	return player


func _player_spawn_position(spawn_index: int) -> Vector3:
	var spawn_nodes := get_tree().get_nodes_in_group("villa_spawn_points")
	var base_position := Vector3(33.0, 0.0, 7.0)
	if not spawn_nodes.is_empty():
		base_position = (spawn_nodes[spawn_index % spawn_nodes.size()] as Node3D).global_position
	var offset := PLAYER_SPAWN_OFFSETS[spawn_index % PLAYER_SPAWN_OFFSETS.size()]
	return base_position + offset + Vector3.UP


func _remove_network_player(peer_id: int) -> void:
	var player := _get_player_for_peer(peer_id)
	if player:
		player.queue_free()
	# Somebody quitting can be what leaves the survivors all dead, so the same
	# question is asked here. Deferred because the body above is only freed at
	# the end of the frame and would otherwise still be counted.
	_check_run_over.call_deferred()


## Is anybody still in the night?
##
## Asked here rather than in NetworkManager because "still in the run" is a
## gameplay question - a downed player is still in it and can be picked back up,
## a spectator is not - and this is where the session's players are made and
## unmade. NetworkManager owns what to *do* about it; the same split as the
## breaker and its minigame.
func _check_run_over() -> void:
	if _run_over_pending or not _network_session_active() or not multiplayer.is_server():
		return
	if not bool(_net().game_started):
		return
	var players := get_tree().get_nodes_in_group(&"players")
	if players.is_empty():
		return
	for node: Node in players:
		if node.is_queued_for_deletion():
			continue
		if bool(node.get("is_alive")) or bool(node.get("is_downed")):
			return
	_end_run_after_pause("Cả đội đã ngã xuống. Về phòng chờ để chơi lại.")


## The run does not end on the same frame it is decided. The last death plays a
## jumpscare and a Game Over card, and dawn draws its own overlay; yanking the
## room to the lobby underneath either would leave nobody knowing what happened.
## The timer is process_always because those screens pause the tree.
func _end_run_after_pause(reason: String) -> void:
	if _run_over_pending:
		return
	_run_over_pending = true
	await get_tree().create_timer(RUN_OVER_DELAY).timeout
	_net().end_run(reason)


func _get_player_for_peer(peer_id: int) -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as CharacterBody3D
		if player and player.owner_peer_id == peer_id:
			return player
	return null


func get_local_player() -> CharacterBody3D:
	var local_peer_id := multiplayer.get_unique_id() if _network_session_active() else 1
	return _get_player_for_peer(local_peer_id)


func _configure_player_lighting(player: CharacterBody3D) -> void:
	if not development_lighting or not is_instance_valid(player) or not player.is_inside_tree():
		return
	if player.is_local_player():
		var horror_overlay := player.get_node_or_null("HorrorOverlay") as CanvasLayer
		var flashlight := player.get_node_or_null("CameraPivot/Camera3D/Flashlight") as SpotLight3D
		if horror_overlay:
			horror_overlay.visible = false
		if flashlight:
			flashlight.visible = false


func _place_ghosts() -> void:
	var lairs := get_tree().get_nodes_in_group("crawler_lair")
	var crawler := get_node_or_null("CrawlerGhost") as Node3D
	if crawler and not lairs.is_empty():
		crawler.global_position = (lairs[0] as Node3D).global_position

	var statue := get_node_or_null("StatueGhost") as Node3D
	var chapel := _room_marker("R_CHAPEL")
	if statue and chapel:
		# Rooms publish a furniture-free tile; the geometric centre is usually
		# where that room's own table stands.
		statue.global_position = chapel.get_meta("clear_point", chapel.global_position)

	# Keep the authored huntsman outside as a dormant DevTools template.  Live
	# villa breaches create a fresh hunter at the affected door instead.
	var hunter := get_node_or_null("HunterGhost") as Node3D
	if hunter:
		hunter.global_position = Vector3(40.0, 0.0, -12.0)
		hunter.set("entry_enabled", false)


func _room_marker(room_id: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("villa_rooms"):
		if String(node.get_meta("room_id", "")) == room_id:
			return node as Node3D
	return null


# --- navigation --------------------------------------------------------------

func _bake_navigation() -> void:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_height = 1.75
	navigation_mesh.agent_radius = 0.4
	navigation_mesh.agent_max_climb = 0.5
	navigation_mesh.agent_max_slope = 50.0
	# House2 bakes at 10 cm. The villa covers about four times the area, and a
	# 10 cm voxel grid over 80 x 60 m of building plus garden is minutes of
	# work for detail no 40 cm agent can use. 20 cm still resolves the 2 m
	# doorways and the 4 m corridors cleanly.
	navigation_mesh.cell_size = 0.2
	navigation_mesh.cell_height = 0.125
	navigation_mesh.filter_low_hanging_obstacles = true
	navigation_mesh.filter_ledge_spans = true
	navigation_mesh.filter_walkable_low_height_spans = true
	# Same reasoning as House2: parse the collision shapes movement actually
	# uses, so the route graph and physics cannot disagree about a wall.
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS

	# A closed interior door still blocks movement through physics, but baking
	# it would freeze it into the route graph as a permanent wall and cut the
	# floor into one island per room. Lift them out for the duration of the
	# parse only.
	var door_shapes := _interior_door_shapes()
	for shape: CollisionShape3D in door_shapes:
		shape.disabled = true

	var source_geometry_data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, source_geometry_data, self)

	for shape: CollisionShape3D in door_shapes:
		shape.disabled = false

	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source_geometry_data)

	var navigation_region := NavigationRegion3D.new()
	navigation_region.name = "VillaNavigationRegion"
	navigation_region.navigation_mesh = navigation_mesh
	add_child(navigation_region)
	_link_stairs_when_navigation_is_ready(navigation_region)


func _interior_door_shapes() -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	for door: Node in get_tree().get_nodes_in_group("villa_interior_doors"):
		for node: Node in door.find_children("*", "CollisionShape3D", true, false):
			shapes.append(node as CollisionShape3D)
	return shapes


## The NavigationServer folds a new region into its map on one of its own sync
## steps, so on the frame the villa bakes, that map still answers every query
## with nothing. These links have to measure it to find their ends, so they
## wait for it rather than being placed blind.
func _link_stairs_when_navigation_is_ready(region: NavigationRegion3D) -> void:
	var map := region.get_navigation_map()
	var probe := region.navigation_mesh.get_vertices()[0]
	# The region was added this frame, but NavigationServer only folds it into
	# the map on its next sync. Never query closest_point against iteration 0:
	# Godot reports that as an error, even though the map is expected to be
	# temporarily empty while it is being registered.
	await get_tree().physics_frame
	for _attempt: int in 120:
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			await get_tree().physics_frame
			continue
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 2.0:
			_add_stair_navigation_links(map)
			await _stair_links_registered(map)
			navigation_is_ready = true
			navigation_ready.emit()
			return
		await get_tree().physics_frame
	push_error("The villa navigation map never came up; its stairs are unlinked.")


## Links reach the server on the sync step after the one that accepted the
## region, so a route asked for in between still walks around the staircase it
## needs. Wait for the server to report them before saying the map is usable.
func _stair_links_registered(map: RID) -> void:
	var expected := (
		get_tree().get_nodes_in_group("smooth_stair_navigation_links").size()
		+ get_tree().get_nodes_in_group("smooth_stair_landing_links").size()
	)
	for _attempt: int in 60:
		if NavigationServer3D.map_get_links(map).size() >= expected:
			# Registered is not yet routable: the map folds the new links into
			# its graph on its next iteration, and a path asked for in between
			# still walks around the staircase.
			var iteration := NavigationServer3D.map_get_iteration_id(map)
			while NavigationServer3D.map_get_iteration_id(map) == iteration:
				await get_tree().physics_frame
			return
		await get_tree().physics_frame
	push_warning("Only %d of the villa's %d stair links reached the navigation map."
		% [NavigationServer3D.map_get_links(map).size(), expected])


## Recast erodes every walkable surface by the agent radius, and a 45-degree
## ramp is narrow enough that the erosion regularly lifts a whole run clear of
## the floor it starts on. The villa bakes V01's grand staircase as an island
## joined to the upper landing and to nothing else: walking from the foyer to
## the landing directly above it cost 152 m around the entire building, so the
## statue - which only ever hunts a target on its own storey - never once took
## the stairs, and the crawler and huntsman took the long way round.
##
## Every seam is bridged with a NavigationLink3D, across a hop a body can
## physically walk. A link is not a teleport: NavigationAgent3D hands its far
## end over as the next path position and the body steers straight at it. The
## single link this replaces spanned the whole run, floor below to landing
## above, so anything given one walked into the underside of the staircase and
## stayed there.
func _add_stair_navigation_links(map: RID) -> void:
	for ramp_node: Node in get_tree().get_nodes_in_group("smooth_stair_ramps"):
		var ramp := ramp_node as StaticBody3D
		if not ramp:
			continue
		var rise := float(ramp.get_meta("rise", 3.5))
		var uphill := ramp.global_basis.x.normalized()
		var run := Vector3(uphill.x, 0.0, uphill.z).normalized()
		if run.is_zero_approx():
			continue

		var half_width := _ramp_half_width(ramp)
		var foot := ramp.global_position - run * rise * 0.5 - Vector3.UP * rise * 0.5
		var head := ramp.global_position + run * rise * 0.5 + Vector3.UP * rise * 0.5
		var stem := ramp.name.trim_suffix("SmoothRamp")

		# Three hops rather than one span, because a single link from the floor
		# below to the landing above is only walkable when it happens to lie
		# along the run - and V01's does not, because its bottom step has no
		# run-out to anchor to. Each hop here is either along the staircase or a
		# single step onto it.
		var toe := _ramp_surface_point(map, foot + run * 0.3 + Vector3.UP * 0.3)
		var crest := _ramp_surface_point(map, head - run * 0.3 - Vector3.UP * 0.3)
		_add_navigation_link(
			stem + "FootNavigationLink",
			_stair_link_anchor(map, foot, -run, half_width),
			toe,
			# Spec section 8 gives each link a traversal time; charging it on
			# the way in is what keeps a route over flat floor cheaper than one
			# that uses two staircases to save a few metres.
			float(ramp.get_meta("enter_cost", 0.0)) * 10.0,
			&"smooth_stair_navigation_links"
		)
		# The run's own polygons are not reliably continuous either: V03 comes
		# out of the bake with a metre-wide hole halfway down, where the ground
		# floor's slab edge clips its headroom.
		_add_navigation_link(
			stem + "RunNavigationLink", toe, crest, 0.0, &"smooth_stair_navigation_links"
		)
		_add_navigation_link(
			stem + "HeadNavigationLink",
			crest,
			_stair_link_anchor(map, head, run, half_width),
			0.0,
			&"smooth_stair_landing_links"
		)


## How far navigation may sit from a probe before that probe counts as having
## missed the floor. The bake lifts polygons about 0.2 m above the surface they
## came from, so anything inside half a cell is still "on" it.
const STAIR_LINK_SNAP := 0.45

## Distances tried along the run, then out to the sides of it. A staircase with
## a generous run-out resolves on the first entry; V01, whose bottom step stops
## half a metre from the foyer's east wall, has to be entered from beside it.
const STAIR_LINK_RUN_OUT: Array[float] = [0.6, 1.0, 1.5, 2.0]
const STAIR_LINK_SIDE_STEP: Array[float] = [0.6, 1.2]


## Half the ramp's width, read off the collider rather than the spec so it also
## holds for the site stairs, which have no vertical-link entry to read.
func _ramp_half_width(ramp: StaticBody3D) -> float:
	var collision := ramp.get_node_or_null("SmoothRampCollision") as CollisionShape3D
	var box := collision.shape as BoxShape3D if collision else null
	return (box.size.z if box else 1.8) * 0.5


## The nearest point that is really on the navigation mesh and really at
## `origin`'s height, searched outward along `outward` and then to either side
## of it. Vector3.INF when the whole neighbourhood misses.
func _stair_link_anchor(
	map: RID, origin: Vector3, outward: Vector3, half_width: float
) -> Vector3:
	var sideways := Vector3.UP.cross(outward).normalized()
	var probes: Array[Vector3] = []
	for run_out: float in STAIR_LINK_RUN_OUT:
		probes.append(origin + outward * run_out)
	# Sideways probes have to clear the run itself or they land on the ramp.
	for side_step: float in STAIR_LINK_SIDE_STEP:
		var across := half_width + side_step
		for side: float in [1.0, -1.0]:
			probes.append(origin + sideways * across * side)
			probes.append(origin + outward * 0.5 + sideways * across * side)

	for probe: Vector3 in probes:
		var closest := NavigationServer3D.map_get_closest_point(map, probe)
		if probe.distance_to(closest) > STAIR_LINK_SNAP:
			continue
		if absf(closest.y - origin.y) > STAIR_LINK_SNAP:
			continue
		return closest
	return Vector3.INF


## Where the run's own navigation actually starts. Erosion eats the last step
## or two, so this is asked for rather than assumed.
func _ramp_surface_point(map: RID, probe: Vector3) -> Vector3:
	var closest := NavigationServer3D.map_get_closest_point(map, probe)
	return closest if probe.distance_to(closest) <= 0.6 else Vector3.INF


## Both ends are stated even when the bake happens to have joined them already:
## a duplicate link is only a little extra work for the pathfinder, while a
## missing one is a storey the ghosts cannot reach, and "are these two points
## already connected" cannot be asked honestly here - the anchors are placed
## before the server has seen any of this frame's links.
func _add_navigation_link(
	link_name: String,
	from: Vector3,
	to: Vector3,
	enter_cost: float,
	group: StringName
) -> void:
	if from == Vector3.INF or to == Vector3.INF:
		push_warning("%s found no navigation to anchor to." % link_name)
		return
	var link := NavigationLink3D.new()
	link.name = link_name
	link.bidirectional = true
	link.start_position = from
	link.end_position = to
	link.enter_cost = enter_cost
	link.add_to_group(group)
	add_child(link)


# --- rendering helpers -------------------------------------------------------

## Props keep the collider they ship with; the architecture is already boxed by
## VillaHouse, so only free-standing kit meshes need a generated trimesh body.
func _has_authored_collision(mesh_instance: MeshInstance3D) -> bool:
	var ancestor := mesh_instance.get_parent()
	while ancestor and ancestor != house:
		if ancestor is CollisionObject3D or ancestor.is_in_group("smooth_stair_visual"):
			return true
		ancestor = ancestor.get_parent()
	return false


## The kit's wall and floor panels are single-sided, and half of them are seen
## from inside. Cache by source material so 2000 panels share a few overrides
## instead of allocating one StandardMaterial3D each.
func _make_mesh_two_sided(mesh_instance: MeshInstance3D) -> void:
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var source_material := mesh_instance.get_active_material(surface_index)
		var key: Variant = source_material if source_material else 0
		if not _two_sided_cache.has(key):
			var two_sided: BaseMaterial3D
			if source_material is BaseMaterial3D:
				two_sided = (source_material as BaseMaterial3D).duplicate() as BaseMaterial3D
			else:
				two_sided = StandardMaterial3D.new()
			two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
			_two_sided_cache[key] = two_sided
		mesh_instance.set_surface_override_material(surface_index, _two_sided_cache[key])


func _enable_backface_collision(mesh_instance: MeshInstance3D) -> void:
	for node: Node in mesh_instance.find_children("*", "CollisionShape3D", true, false):
		var collision_shape := node as CollisionShape3D
		var concave_shape := collision_shape.shape as ConcavePolygonShape3D
		if concave_shape:
			concave_shape.backface_collision = true


func _apply_horror_lighting() -> void:
	var environment := world_environment.environment
	environment.ambient_light_color = Color(0.075, 0.105, 0.15)
	environment.ambient_light_energy = 0.22
	environment.tonemap_exposure = 0.84
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.86
	environment.adjustment_contrast = 1.14
	environment.adjustment_saturation = 0.68
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.075, 0.105, 0.13)
	environment.fog_light_energy = 0.42
	environment.fog_density = 0.042
	environment.fog_height = 2.0
	environment.fog_height_density = 0.08
	environment.fog_aerial_perspective = 0.8
	environment.fog_sky_affect = 1.0
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.038
	environment.volumetric_fog_albedo = Color(0.38, 0.46, 0.5)
	environment.volumetric_fog_emission = Color(0.008, 0.012, 0.016)
	environment.volumetric_fog_emission_energy = 0.48
	environment.volumetric_fog_length = 42.0
	environment.volumetric_fog_detail_spread = 1.8
	environment.volumetric_fog_ambient_inject = 0.35
	environment.volumetric_fog_sky_affect = 0.15

	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	if sky_material:
		sky_material.sky_top_color = Color(0.004, 0.008, 0.018)
		sky_material.sky_horizon_color = Color(0.025, 0.04, 0.055)
		sky_material.ground_bottom_color = Color(0.002, 0.003, 0.006)
		sky_material.ground_horizon_color = Color(0.012, 0.018, 0.024)

	if moon_light:
		moon_light.light_color = Color(0.34, 0.43, 0.62)
		moon_light.light_energy = 0.3

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
@onready var moon_light: DirectionalLight3D = $DirectionalLight3D
@onready var horror_overlay: CanvasLayer = $Player/HorrorOverlay
@onready var flashlight: SpotLight3D = $Player/CameraPivot/Camera3D/Flashlight

const DEFENSE_DOOR: PackedScene = preload("res://door/defense_door.tscn")
const HUNTER_GHOST: PackedScene = preload("res://ghosts/hunter_ghost.tscn")

## The stock defense door is built for House2's 3 m storey and 2.2 m opening.
## A villa entrance is two 2 m cells wide in a 3.5 m wall.
const DEFENSE_DOOR_SCALE := Vector3(1.55, 1.2, 1.0)

## Height of the leaf's centre above the door node's own origin.
const DEFENSE_DOOR_LEAF_RISE := 1.15

## The villa has seven entrances and every one of them can break, so "one hunter
## per breach" had no ceiling at all. It matters more now than it used to for two
## reasons: a huntsman never leaves the house any more, so they only ever
## accumulate; and each one is a three-hundred-part body, so the fourth is a
## frame-rate problem before it is a difficulty problem. Three of them in a
## building this size is already everywhere at once.
const MAX_BREACH_HUNTERS := 3

var _two_sided_cache: Dictionary = {}
## A breach can happen before Recast has finished baking.  Those hunters wait
## at the opening instead of trying to search without a navigation map.
var _hunters_waiting_for_navigation: Array[CharacterBody3D] = []
var _breach_hunter_serial: int = 0
## Every huntsman this level has spawned at a breach and not since freed.
var _breach_hunters: Array[CharacterBody3D] = []


func _ready() -> void:
	navigation_ready.connect(_activate_waiting_hunters)
	if development_lighting:
		horror_overlay.visible = false
		flashlight.visible = false
	else:
		_apply_horror_lighting()

	_place_defense_doors()
	_watch_breached_entrances()
	_place_player()
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
		var door := DEFENSE_DOOR.instantiate() as Node3D
		door.name = "Entrance%02d%s" % [
			int(anchor.get_meta("entrance_id")),
			String(anchor.get_meta("spec_id")),
		]
		door.set("entrance_id", int(anchor.get_meta("entrance_id")))
		entrances.add_child(door)
		door.scale = DEFENSE_DOOR_SCALE
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
	if live_breach_hunter_count() >= MAX_BREACH_HUNTERS:
		# The house is already full. Every further breach is still a hole the
		# player has to live with - it just does not add a fourth body.
		return

	_breach_hunter_serial += 1
	var hunter := HUNTER_GHOST.instantiate() as CharacterBody3D
	if not hunter:
		return
	hunter.name = "BreachHunter%02d" % _breach_hunter_serial
	# This hunter belongs to one particular breach and must never let itself back
	# in through a different one, which would put it outside the cap.
	hunter.set("entry_enabled", false)
	add_child(hunter)
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


func _place_player() -> void:
	var spawns := get_tree().get_nodes_in_group("villa_spawn_points")
	if spawns.is_empty():
		return
	var player := get_node_or_null("Player") as Node3D
	if player:
		player.global_position = (spawns[0] as Node3D).global_position + Vector3(0, 1.0, 0)


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
	for _attempt: int in 120:
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

	moon_light.light_color = Color(0.34, 0.43, 0.62)
	moon_light.light_energy = 0.3

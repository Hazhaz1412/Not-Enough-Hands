extends SceneTree

## Validates the Vanh Dai villa map against NEH_map_spec_v2 section 10.6, then
## builds it once to prove the generator agrees with the validated spec.
##
##   godot --headless --script tests/villa_layout_smoke.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var spec := VillaSpec.load_default()
	if spec.data.is_empty():
		_fail("The villa spec could not be loaded.")
		return
	if spec.grid_width != 40 or spec.grid_height != 30:
		_fail("Grid must be 40x30, got %dx%d." % [spec.grid_width, spec.grid_height])
		return
	if not is_equal_approx(spec.cell_size, 2.0) or not is_equal_approx(spec.floor_height, 3.5):
		_fail("Cell size / floor height do not match section 1.")
		return

	var levels: Dictionary = {}
	for level: int in spec.level_ids():
		levels[level] = spec.build_level(level)

	if not _check_reachability(spec, levels):
		return
	if not _check_shaft_is_solid(spec, levels):
		return
	if not _check_entrances_touch_their_room(spec, levels):
		return
	if not _check_junction_graph(spec):
		return
	if not _check_room_connections(spec, levels):
		return
	if not _check_restrooms(spec, levels):
		return
	if not await _check_generated_scene(spec):
		return

	print(
		"Villa layout smoke test passed: %d levels, %d rooms, %d junctions, 7 entrances."
		% [spec.level_ids().size(), spec.data["rooms"].size(), spec.data["junctions"].size()]
	)
	quit()


## Rule 1. Every floor cell on every level must be reachable from SP_PLAYER_1,
## counting the vertical links as edges.
func _check_reachability(spec: VillaSpec, levels: Dictionary) -> bool:
	var total := 0
	for level: int in levels:
		total += (levels[level]["walkable"] as Dictionary).size()

	var spawn: Dictionary = spec.spawn_points()[0]
	var start := _key(int(spawn["level"]), VillaSpec.to_cell(spawn["cell"]))
	var stairs := _link_edges(spec, levels)

	var seen: Dictionary = {start: true}
	var frontier: Array[String] = [start]
	while not frontier.is_empty():
		var current: String = frontier.pop_back()
		for neighbour: String in _neighbours(current, levels, stairs):
			if seen.has(neighbour):
				continue
			seen[neighbour] = true
			frontier.append(neighbour)

	if seen.size() != total:
		var unreached := PackedStringArray()
		for level: int in levels:
			for cell: Vector2i in levels[level]["walkable"]:
				if not seen.has(_key(level, cell)) and unreached.size() < 12:
					unreached.append("L%d%s" % [level, cell])
		_fail(
			"Flood fill from SP_PLAYER_1 reached %d of %d floor cells. Stranded: %s."
			% [seen.size(), total, ", ".join(unreached)]
		)
		return false
	return true


func _link_edges(spec: VillaSpec, levels: Dictionary) -> Dictionary:
	var edges: Dictionary = {}
	for link: Dictionary in spec.vertical_links():
		if String(link["type"]) == "shaft":
			continue
		var low: int = mini(int(link["from"]), int(link["to"]))
		var high: int = maxi(int(link["from"]), int(link["to"]))
		var rect := VillaSpec.to_rect(link["rect"])
		for col: int in range(rect.position.x, rect.position.x + rect.size.x):
			for row: int in range(rect.position.y, rect.position.y + rect.size.y):
				var cell := Vector2i(col, row)
				if not (levels[low]["walkable"] as Dictionary).has(cell):
					continue
				if not (levels[high]["walkable"] as Dictionary).has(cell):
					continue
				var low_key := _key(low, cell)
				var high_key := _key(high, cell)
				edges.get_or_add(low_key, [] as Array[String]).append(high_key)
				edges.get_or_add(high_key, [] as Array[String]).append(low_key)
	return edges


func _neighbours(key: String, levels: Dictionary, stairs: Dictionary) -> Array[String]:
	var parts := key.split(":")
	var level := int(parts[0])
	var cell := Vector2i(int(parts[1]), int(parts[2]))
	var result: Array[String] = []
	for direction: Vector2i in VillaSpec.DIRECTIONS:
		if (levels[level]["walkable"] as Dictionary).has(cell + direction):
			result.append(_key(level, cell + direction))
	for linked: String in stairs.get(key, []):
		result.append(linked)
	return result


static func _key(level: int, cell: Vector2i) -> String:
	return "%d:%d:%d" % [level, cell.x, cell.y]


## Rule 2. The light shaft must not be walkable on the storey above it.
func _check_shaft_is_solid(spec: VillaSpec, levels: Dictionary) -> bool:
	for link: Dictionary in spec.vertical_links():
		if String(link["type"]) != "shaft":
			continue
		var rect := VillaSpec.to_rect(link["rect"])
		var walkable: Dictionary = levels[int(link["to"])]["walkable"]
		for col: int in range(rect.position.x, rect.position.x + rect.size.x):
			for row: int in range(rect.position.y, rect.position.y + rect.size.y):
				if walkable.has(Vector2i(col, row)):
					_fail("Shaft %s is walkable at (%d,%d) on the upper level."
						% [link["id"], col, row])
					return false
	return true


## Rule 3. Every entrance must sit against a floor cell of the room it claims.
func _check_entrances_touch_their_room(spec: VillaSpec, levels: Dictionary) -> bool:
	var found_ids: Array[int] = []
	for entrance: Dictionary in spec.entrances():
		found_ids.append(int(entrance["entrance_id"]))
		var level := int(entrance["level"])
		var room_rect := VillaSpec.to_rect(spec.room(String(entrance["room"]))["rect"])
		var touches := false
		for cell_pair: Variant in entrance["cells"]:
			var cell := VillaSpec.to_cell(cell_pair)
			if room_rect.has_point(cell):
				touches = true
			for direction: Vector2i in VillaSpec.DIRECTIONS:
				var probe := cell + direction
				if room_rect.has_point(probe) and (levels[level]["walkable"] as Dictionary).has(probe):
					touches = true
		if not touches:
			_fail("Entrance %s does not touch %s." % [entrance["id"], entrance["room"]])
			return false
	found_ids.sort()
	if found_ids != [1, 2, 3, 4, 5, 6, 7]:
		_fail("Entrance ids are incomplete or duplicated: %s." % [found_ids])
		return false
	return true


## Rule 4. The junction graph must be connected and must still contain a cycle:
## no cycle means the ring corridor has been broken somewhere.
func _check_junction_graph(spec: VillaSpec) -> bool:
	var adjacency: Dictionary = {}
	for junction: Dictionary in spec.data["junctions"]:
		adjacency[String(junction["id"])] = [] as Array[String]
	var edge_count := 0
	for edge: Array in spec.data["junction_edges"]:
		var a := String(edge[0])
		var b := String(edge[1])
		if not adjacency.has(a) or not adjacency.has(b):
			_fail("Junction edge %s-%s names an undeclared junction." % [a, b])
			return false
		(adjacency[a] as Array).append(b)
		(adjacency[b] as Array).append(a)
		edge_count += 1

	# B1 is the basement's only junction and is reached by stair, not corridor,
	# so connectivity is checked per level rather than over the whole graph.
	for level: int in [0, 1]:
		var ids: Array[String] = []
		for junction: Dictionary in spec.junctions_on(level):
			ids.append(String(junction["id"]))
		if ids.is_empty():
			continue
		var seen: Dictionary = {ids[0]: true}
		var frontier: Array[String] = [ids[0]]
		var component_edges := 0
		while not frontier.is_empty():
			var current: String = frontier.pop_back()
			for neighbour: String in adjacency[current]:
				component_edges += 1
				if seen.has(neighbour):
					continue
				seen[neighbour] = true
				frontier.append(neighbour)
		if seen.size() != ids.size():
			_fail("Junction ring on level %d is not connected (%d of %d)."
				% [level, seen.size(), ids.size()])
			return false
		if component_edges / 2 < seen.size():
			_fail("Junction ring on level %d has no cycle; the belt is broken." % level)
			return false
	return true


## Rule 5. A room with a single way in is a trap, and only the rooms the spec
## names as exceptions are allowed to be one.
func _check_room_connections(spec: VillaSpec, levels: Dictionary) -> bool:
	var allowed := spec.single_door_rooms()
	var connections: Dictionary = {}
	for room: Dictionary in spec.data["rooms"]:
		if bool(room.get("void", false)):
			continue
		# A door cell belongs to both spaces it separates, so credit it by
		# geometry rather than by whichever room's table happens to list it.
		var rect := VillaSpec.to_rect(room["rect"])
		var count := 0
		for door: Dictionary in levels[int(room["level"])]["doors"]:
			for direction: Vector2i in VillaSpec.DIRECTIONS:
				if rect.has_point((door["cell"] as Vector2i) + direction):
					count += 1
					break
		connections[String(room["id"])] = count

	for entrance: Dictionary in spec.entrances():
		var room_id := String(entrance["room"])
		connections[room_id] = int(connections.get(room_id, 0)) + 1

	for link: Dictionary in spec.vertical_links():
		if String(link["type"]) == "shaft":
			continue
		var rect := VillaSpec.to_rect(link["rect"])
		for level: int in [int(link["from"]), int(link["to"])]:
			for room: Dictionary in spec.rooms_on(level):
				if VillaSpec.to_rect(room["rect"]).intersects(rect):
					var room_id := String(room["id"])
					connections[room_id] = int(connections.get(room_id, 0)) + 1

	for room_id: String in connections:
		if int(connections[room_id]) >= 2 or allowed.has(room_id):
			continue
		_fail("Room %s has only %d connection(s) and is not a declared exception."
			% [room_id, connections[room_id]])
		return false
	return true


## The four added WCs are intentionally small dead ends distributed over the
## two occupied storeys. Their one-door topology is part of the requested map
## design, rather than an accidental room trap.
func _check_restrooms(spec: VillaSpec, levels: Dictionary) -> bool:
	var expected := {
		"R_WC_GROUND_NORTH": 0,
		"R_WC_GROUND_SOUTH": 0,
		"R_WC_UP_NORTH": 1,
		"R_WC_UP_SOUTH": 1,
	}
	for room_id: String in expected:
		var room := spec.room(room_id)
		if room.is_empty():
			_fail("Missing restroom %s." % room_id)
			return false
		if int(room["level"]) != int(expected[room_id]) or String(room.get("kind", "")) != "wc":
			_fail("Restroom %s has the wrong level or room kind." % room_id)
			return false
		var rect := VillaSpec.to_rect(room["rect"])
		if rect.size != Vector2i(2, 2):
			_fail("Restroom %s must stay compact at 2x2 cells, got %s." % [room_id, rect.size])
			return false
		var doors: Array = room.get("doors", [])
		if doors.size() != 1:
			_fail("Restroom %s must be a one-door dead end." % room_id)
			return false
		var door_cell := VillaSpec.to_cell(doors[0])
		var generated_doors: Array = levels[int(expected[room_id])]["doors"]
		if not generated_doors.any(func(door: Dictionary) -> bool: return door["cell"] == door_cell):
			_fail("Restroom %s door was not carved into the generated level." % room_id)
			return false
	return true


## Finally build the thing, in blockout detail so the test stays quick, and
## confirm it publishes the contract the game systems read.
func _check_generated_scene(spec: VillaSpec) -> bool:
	var house := VillaHouse.new()
	house.detail = VillaHouse.Detail.BLOCKOUT
	house.build_furniture = false
	house.build_lighting = false
	root.add_child(house)
	await process_frame

	if not house.has_node("Generated"):
		_fail("VillaHouse did not generate any geometry.")
		return false

	var anchor_ids: Array[int] = []
	for anchor: Node in get_nodes_in_group("villa_entrance_anchors"):
		anchor_ids.append(int(anchor.get_meta("entrance_id")))
	anchor_ids.sort()
	if anchor_ids != [1, 2, 3, 4, 5, 6, 7]:
		_fail("Generated entrance anchors are wrong: %s." % [anchor_ids])
		return false

	var expected_rooms := 0
	for room: Dictionary in spec.data["rooms"]:
		if not bool(room.get("void", false)):
			expected_rooms += 1
	if get_nodes_in_group("villa_rooms").size() != expected_rooms:
		_fail("Expected %d room markers, found %d."
			% [expected_rooms, get_nodes_in_group("villa_rooms").size()])
		return false

	if get_nodes_in_group("villa_junctions").size() != spec.data["junctions"].size():
		_fail("Junction markers do not match the spec table.")
		return false

	# Four internal ramps (three stairs plus the attic companionway) and the
	# three outdoor ones that make the upper and cellar entrances approachable.
	var ramps := get_nodes_in_group("villa_stair_ramps")
	if ramps.size() != 7:
		_fail("Expected 7 authored ramps, found %d." % ramps.size())
		return false
	for ramp: Node in ramps:
		if not (ramp as Node3D).has_node("SmoothRampCollision"):
			_fail("Ramp %s has no smooth collision." % ramp.name)
			return false

	if get_nodes_in_group("villa_spawn_points").size() != spec.spawn_points().size():
		_fail("Spawn markers do not match the spec table.")
		return false
	if get_nodes_in_group("hunter_sweep_points").is_empty():
		_fail("The villa publishes no hunter sweep route.")
		return false
	if get_nodes_in_group("crawler_patrol_points").is_empty():
		_fail("The villa publishes no crawler patrol route.")
		return false
	if get_nodes_in_group("crawler_lair").is_empty():
		_fail("The villa publishes no crawler lair.")
		return false

	var doors := get_nodes_in_group("villa_interior_doors")
	if doors.size() < 40:
		_fail("Only %d interior doors were placed; the door table is incomplete." % doors.size())
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

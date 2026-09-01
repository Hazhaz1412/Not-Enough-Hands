extends SceneTree

## Fires rays out of every walkable cell of the villa and insists that each one
## that escapes is an opening the spec asked for. This is the test that caught
## the storey's worth of walls stacked at y=0, the untiled floor strips and the
## unlined light shaft - none of which any layout check could see.
##
##   godot --headless --script tests/villa_seal_smoke.gd

const WAIST := 1.2
## Just under a 3.5 m storey, where a gap above a lintel or between two wall
## runs would hide from a waist-height ray.
const HEAD := 3.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main_scene := (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	for _frame: int in 6:
		await process_frame
	await physics_frame

	var space: PhysicsDirectSpaceState3D = main_scene.get_world_3d().direct_space_state
	var spec := VillaSpec.load_default()
	var checked := 0

	for level: int in spec.level_ids():
		var data := spec.build_level(level)
		var walkable: Dictionary = data["walkable"]
		var open_floor := _stairwell_cells(spec, level)
		var open_ceiling := _sky_cells(spec, level)
		var open_wall := _shaft_cells(spec, level)
		var entrance_faces := _entrance_faces(spec, level, data["extent"] as Rect2i)

		for cell: Vector2i in walkable:
			checked += 1
			var centre := spec.grid_to_world(cell.x, cell.y, level)

			# A ramp under a stairwell opening sits below the ray, so the
			# opening cells are allowed to report no floor.
			if not open_floor.has(cell):
				if not _hits(space, centre + Vector3(0, 0.4, 0), Vector3(0, -1.2, 0)):
					_fail("L%d %s has no floor under it." % [level, cell])
					return
			if not open_ceiling.has(cell):
				if not _hits(space, centre + Vector3(0, 0.4, 0), Vector3(0, spec.floor_height, 0)):
					_fail("L%d %s is open to the sky." % [level, cell])
					return

			for direction: Vector2i in VillaSpec.DIRECTIONS:
				var neighbour := cell + direction
				if walkable.has(neighbour) or open_wall.has(neighbour):
					continue
				if entrance_faces.get(cell, Vector2i.ZERO) == direction:
					continue
				var outward := Vector3(direction.x, 0, direction.y) * 1.6
				for height: float in [WAIST, HEAD]:
					if _hits(space, centre + Vector3(0, height, 0), outward):
						continue
					_fail("L%d %s has no wall towards %s at %.1f m."
						% [level, cell, neighbour, height])
					return

	print("Villa seal smoke test passed: %d cells enclosed, only the shaft, the "
		% checked + "stairwells and the skylight left open.")
	quit()


## Non-overhead defense doors replace the wall on exactly one exterior face.
## Their collider starts on the cell centre, so a ray starting there cannot be
## used to prove enclosure; the breach opening itself is intentional anyway.
func _entrance_faces(spec: VillaSpec, level: int, extent: Rect2i) -> Dictionary:
	var faces: Dictionary = {}
	for entrance: Dictionary in spec.entrances():
		if int(entrance["level"]) != level or bool(entrance.get("overhead", false)):
			continue
		for cell_pair: Variant in entrance["cells"]:
			var cell := VillaSpec.to_cell(cell_pair)
			var direction := Vector2i.DOWN
			if cell.x == extent.position.x:
				direction = Vector2i.LEFT
			elif cell.x == extent.position.x + extent.size.x - 1:
				direction = Vector2i.RIGHT
			elif cell.y == extent.position.y:
				direction = Vector2i.UP
			faces[cell] = direction
	return faces


## Cells the floor is deliberately missing from: a stair coming up from below
## has to come up through something.
func _stairwell_cells(spec: VillaSpec, level: int) -> Dictionary:
	var cells: Dictionary = {}
	for link: Dictionary in spec.vertical_links():
		if String(link["type"]) == "shaft":
			continue
		if maxi(int(link["from"]), int(link["to"])) != level:
			continue
		_mark_footprint(spec, link, cells)
	return cells


## Cells with nothing overhead: the light shaft, and the stairwell openings in
## the floor of the storey above.
func _sky_cells(spec: VillaSpec, level: int) -> Dictionary:
	var cells := _shaft_cells(spec, level)
	for link: Dictionary in spec.vertical_links():
		if String(link["type"]) == "shaft":
			continue
		if maxi(int(link["from"]), int(link["to"])) != level + 1:
			continue
		_mark_footprint(spec, link, cells)
	return cells


func _shaft_cells(spec: VillaSpec, level: int) -> Dictionary:
	var cells: Dictionary = {}
	for link: Dictionary in spec.vertical_links():
		if String(link["type"]) != "shaft" or level < mini(int(link["from"]), int(link["to"])):
			continue
		var rect := VillaSpec.to_rect(link["rect"])
		for col: int in range(rect.position.x, rect.position.x + rect.size.x):
			for row: int in range(rect.position.y, rect.position.y + rect.size.y):
				cells[Vector2i(col, row)] = true
	return cells


## The run of cells a ramp passes beneath, walking downhill from its landing.
func _mark_footprint(spec: VillaSpec, link: Dictionary, cells: Dictionary) -> void:
	var low: int = mini(int(link["from"]), int(link["to"]))
	var high: int = maxi(int(link["from"]), int(link["to"]))
	var rise := (high - low) * spec.floor_height
	var rect := VillaSpec.to_rect(link["rect"])
	var heading := String(link.get("heading", "north"))
	var along_x := heading in ["east", "west"]
	var positive := heading in ["east", "south"]
	var landing := (
		(rect.position.x + rect.size.x - 1 if positive else rect.position.x) if along_x
		else (rect.position.y + rect.size.y - 1 if positive else rect.position.y)
	)
	var step := -1 if positive else 1
	var lateral_start := rect.position.y if along_x else rect.position.x
	var lateral_size := rect.size.y if along_x else rect.size.x

	for offset: int in range(1, ceili(rise / spec.cell_size) + 1):
		var along := landing + step * offset
		for lateral: int in range(lateral_start, lateral_start + lateral_size):
			cells[Vector2i(along, lateral) if along_x else Vector2i(lateral, along)] = true


func _hits(space: PhysicsDirectSpaceState3D, from: Vector3, offset: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, from + offset)
	query.hit_back_faces = true
	return not space.intersect_ray(query).is_empty()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

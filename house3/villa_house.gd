@tool
class_name VillaHouse
extends Node3D

## Runtime/editor builder for the "Biet thu Vanh Dai" map (NEH_map_spec_v2).
##
## This is a second, larger map that lives beside House2 rather than replacing
## it: it publishes the same node groups and the same defense-door contract, so
## the existing player, ghosts, doors, power and audio systems drive it without
## a single change on their side.
##
## Geometry is generated only from house3/neh_map_spec_v2.json, per spec
## section 10.2. The ASCII plans in the design document are never parsed.

const ASSET_ROOT := "res://assets/map/retro_modular_house/retro_modular_house/models/"
const FURNITURE_ROOT := "res://assets/map/Furniture/FBX/Separated/"

const FLOOR_2X2: PackedScene = preload(ASSET_ROOT + "floors/floor_2x2.fbx")
const FLOOR_4X4: PackedScene = preload(ASSET_ROOT + "floors/floor_4x4.fbx")
const WALL_3X2: PackedScene = preload(ASSET_ROOT + "walls/wall_3x2.fbx")
const BIG_STAIR: PackedScene = preload(ASSET_ROOT + "misc/stairs/stair_big_01.fbx")
const BALCONY_RAIL: PackedScene = preload(ASSET_ROOT + "railings/railing_balcony_02.fbx")
const TOILET_INTERACTABLE: PackedScene = preload("res://toilet/toilet.tscn")

## Measured from the kit itself: the treads run and rise 3 m, while the railings
## continue to 4.2 m (1.2 m above the upper landing). The stair is 1 m wide and
## one standalone railing panel spans exactly 1 m.
const KIT_STAIR_RUN := 3.0
const KIT_STAIR_RISE := 3.0
const KIT_STAIR_WIDTH := 1.0
const KIT_RAIL_WIDTH := 1.0

## What goes in a room of each kind.
##
##   unique - the pieces a room has exactly one of, placed first
##   large  - carcass furniture, cycled to fill most of the remaining wall
##   small  - accents and wall-hung pieces, every third slot
##   table / seat / seats - the centre group, for rooms built around one
##
## Two thirds of the slots go to `large` on purpose: a 26 m room furnished out
## of vases and lamps still reads as an empty room.
const FURNITURE_PLANS := {
	"bedroom": {
		"unique": ["Bed Base 1 1", "Wardrobe", "Mirror"],
		"large": ["Drawer-Cabinet", "Drawer 1", "Chair 2"],
		"small": ["Bed Table", "Lamp 1", "Painting", "Simple Curtains Closed"],
	},
	"master": {
		"unique": ["Bed Base 1 1", "Wardrobe", "Mirror", "Puff"],
		"large": ["Drawer-Cabinet", "Drawer 1", "Sofa 2"],
		"small": ["Bed Table", "Lamp 2", "Painting 2", "Simple Curtains Closed"],
	},
	"lounge": {
		"unique": ["Sofa 1", "TV 1", "Sofa 2"],
		"large": ["Drawer-Cabinet", "Modern Shelves", "Puff", "Drawer 1"],
		"small": ["Lamp 2", "Painting", "Plant Deco 1", "Vase 1"],
		"table": "Coffee Table",
	},
	"hall": {
		"unique": ["Mirror", "Drawer-Cabinet"],
		"large": ["Puff", "Stool", "Modern Shelves"],
		"small": ["Painting 2", "Vase 1", "Plant Deco 1", "Lamp 3"],
		"table": "Round Table",
		"seat": "Chair 3",
		"seats": 3,
	},
	"study": {
		"unique": ["Modern Shelves", "Drawer-Cabinet"],
		"large": ["Modern Shelves", "Simple Shelf", "Drawer 1", "Chair 2"],
		"small": ["Painting", "Lamp 3", "Vase 2"],
		"table": "Table Curved",
		"seat": "Chair 2",
		"seats": 2,
	},
	"gallery": {
		"unique": ["Stool"],
		"large": ["Plant Deco 1", "Drawer 1", "Puff"],
		"small": ["Painting", "Painting 2", "Painting 3", "Poster 1", "Vase 2"],
	},
	"kitchen": {
		"unique": ["Fridge", "Oven", "Microwave", "Toaster"],
		"large": ["Counter Connected", "Counter Connected - Sink", "Drawer 2 Old"],
		"small": ["Simple Shelf", "TrashBin"],
	},
	"dining": {
		"unique": ["Drawer-Cabinet", "Mirror"],
		"large": ["Drawer 1", "Drawer-Cabinet", "Modern Shelves"],
		"small": ["Painting 2", "Vase 1", "Lamp 2", "Simple Shelf"],
		"table": "Dining Table",
		"seat": "Chair",
		"seats": 6,
	},
	"storage": {
		"unique": ["Ladder 1", "TrashBin"],
		"large": ["Box", "Box Ac", "Drawer 2 Old", "Modern Shelves"],
		"small": ["SimpleSmall Box", "Plastic Basket", "Towel Pile"],
	},
	"utility": {
		"unique": ["Washing Machine", "Dryer Machine", "Sink", "Toolbox Base"],
		"large": ["Box", "Tire", "Drawer 2 Old", "Modern Shelves"],
		"small": ["Simple Shelf", "TrashBin", "Plastic Basket"],
	},
	"bath": {
		"unique": ["Bathtub", "Toilet", "Sink", "Simple Shower", "Mirror"],
		"large": ["Drawer 1", "Drawer-Cabinet"],
		"small": ["Towel Pile", "Simple Shelf"],
	},
	"wc": {
		# These are deliberately compact dead-end rooms: one usable toilet and
		# one hand basin, with a mirror that does not consume floor space.
		"unique": ["Toilet", "Sink", "Mirror"],
		"large": [],
		"small": [],
	},
	"chapel": {
		"unique": ["Modern Shelves"],
		"large": ["Chair 3", "Chair 3", "Stool"],
		"small": ["Painting 3", "Vase 2", "Lamp 1"],
		"table": "Round Table",
		"seat": "Chair 3",
		"seats": 4,
	},
	"attic": {
		"unique": ["Ladder 1", "Toy House", "Tire"],
		"large": ["Box", "Box Ac", "Drawer 2 Old", "Wardrobe"],
		"small": ["SimpleSmall Box", "Plastic Basket", "TrashBin"],
	},
	"atrium": {
		"unique": ["Bush"],
		"large": ["Plant Deco 1", "Stool", "Bush"],
		"small": ["Vase 1", "Flower Pot Ac"],
		"table": "Round Table",
		"seat": "Chair Outside",
		"seats": 3,
	},
	"balcony": {
		"unique": ["Plant Deco 1"],
		"large": ["Plant Deco 1"],
		"small": ["Vase 2"],
	},
}

## Pieces that belong flat on the plaster at eye height, not on the floor.
const WALL_HUNG := [
	"Painting", "Painting 2", "Painting 3", "Poster 1", "Mirror",
	"Simple Curtains Closed",
]

## Native height of the kit's wall modules, which the 3.5 m storey stretches.
const KIT_WALL_HEIGHT := 3.0
const SLAB_THICKNESS := 0.3
const WALL_THICKNESS := 0.3
const DOOR_CLEAR_HEIGHT := 2.4

enum Detail {
	## Untextured boxes only. Builds in a fraction of the time, which is what
	## the headless smoke tests want; the layout is bit-identical either way.
	BLOCKOUT,
	## Boxes plus the modular kit dressing and furniture.
	FULL,
}

enum AuthoringGranularity {
	## Long straight walls and contiguous slabs share one collider. This is the
	## normal runtime layout: fewer physics bodies and a much smaller scene tree.
	OPTIMIZED,
	## Walls, floors and ceilings are split into one 2 m grid module apiece. Use
	## this before baking when an artist needs to move individual architecture.
	EDITABLE_MODULES,
}

@export var editor_preview: bool = true
@export var detail: Detail = Detail.FULL
@export var build_furniture: bool = true
@export var build_lighting: bool = true

@export_category("Villa Authoring")
@export var authoring_granularity: AuthoringGranularity = AuthoringGranularity.OPTIMIZED
@export_tool_button("Rebuild Preview") var _rebuild_preview_button: Callable = rebuild_preview
@export_tool_button("Bake Editable Parts") var _bake_editable_button: Callable = bake_editable_parts
@export_tool_button("Clear Generated Parts") var _clear_generated_button: Callable = clear_generated_parts

var spec: VillaSpec
var levels: Dictionary = {}

var _module_index := 0
var _furniture_cache: Dictionary = {}
## Cells a piece of furniture stands on, keyed "level:col:row". Room markers,
## ghost routes and anything else that wants somewhere to stand read this.
var _occupied: Dictionary = {}
var _floor_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _ceiling_material: StandardMaterial3D
var _ground_material: StandardMaterial3D


func _ready() -> void:
	if Engine.is_editor_hint() and not editor_preview:
		return
	if has_node("Generated"):
		return
	build()


## Replaces the disposable editor preview using the current Inspector options.
## Preview children deliberately remain unowned, so merely opening a scene never
## writes thousands of generated nodes into it.
func rebuild_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_clear_generated_immediately()
	build()


## Generates cell-sized architecture and gives every generated root a scene
## owner. Save the scene after pressing this button and the parts become ordinary
## editable nodes; _ready() sees Generated on later loads and will not overwrite
## the artist's transforms.
func bake_editable_parts() -> void:
	if not Engine.is_editor_hint():
		return
	authoring_granularity = AuthoringGranularity.EDITABLE_MODULES
	_clear_generated_immediately()
	build()
	var generated := get_node_or_null("Generated")
	var edited_root := get_tree().edited_scene_root if get_tree() else null
	if not generated or not edited_root:
		push_error("Open a scene containing VillaHouse before baking editable parts.")
		return
	_make_scene_owned(generated, edited_root)


## Removes either a disposable preview or baked parts. Saving after this returns
## villa_house.tscn to procedural runtime generation.
func clear_generated_parts() -> void:
	if not Engine.is_editor_hint():
		return
	_clear_generated_immediately()


func _clear_generated_immediately() -> void:
	var generated := get_node_or_null("Generated")
	if generated:
		generated.free()
	_module_index = 0
	levels.clear()
	_occupied.clear()


## Imported FBX scenes and door scenes stay packed instances: their root is
## editable, but their implementation subtree is not flattened into this scene.
func _make_scene_owned(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	_make_groups_persistent(node)
	for child: Node in node.get_children():
		child.owner = scene_owner
		_make_groups_persistent(child)
		if child.scene_file_path.is_empty():
			_make_scene_owned(child, scene_owner)


func _make_groups_persistent(node: Node) -> void:
	for group: StringName in node.get_groups():
		if String(group).begins_with("_"):
			continue
		# add_to_group() is a no-op when membership already exists; remove first
		# so the persistent flag really changes and survives PackedScene.save().
		node.remove_from_group(group)
		node.add_to_group(group, true)


func build() -> void:
	if has_node("Generated"):
		push_warning("VillaHouse already has Generated parts; clear or rebuild them first.")
		return
	_module_index = 0
	levels.clear()
	_occupied.clear()
	spec = VillaSpec.load_default()
	if spec.data.is_empty():
		push_error("VillaHouse has no spec to build from.")
		return

	# The kit's plaster reads near-white, so the procedural surfaces that sit
	# beside it - ceilings, lintels, the roof deck - have to be a plaster tone
	# too. Anything much darker reads as an opening rather than a surface.
	_floor_material = _material(Color(0.34, 0.3, 0.26), 0.92)
	_wall_material = _material(Color(0.46, 0.45, 0.42), 0.95)
	_ceiling_material = _material(Color(0.5, 0.49, 0.46), 0.96)
	_ground_material = _material(Color(0.075, 0.09, 0.075), 0.97)

	var generated := _container(self, "Generated")
	generated.add_to_group("villa_geometry")
	generated.add_to_group("house2_geometry")

	for level: int in spec.level_ids():
		levels[level] = spec.build_level(level)

	_build_site(_container(generated, "Site"))

	for level: int in spec.level_ids():
		var level_root := _container(generated, "Level_%s" % spec.level_id(level))
		level_root.set_meta("elevation", level * spec.floor_height)
		level_root.set_meta("level", level)
		_build_level(level_root, levels[level])

	_build_vertical_links(_container(generated, "Links"))
	_build_entrance_anchors(_container(generated, "Entrances"))
	_build_spawn_points(_container(generated, "Spawns"))
	_build_ghost_routes(_container(generated, "Routes"))


# --- one storey --------------------------------------------------------------

func _build_level(root: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	var architecture := _container(root, "Architecture")

	_build_floors(architecture, level_data)
	_build_walls(architecture, level_data)
	_build_ceiling(architecture, level_data)
	_build_doors(_container(root, "Doors"), level_data)
	_build_junction_markers(_container(root, "Junctions"), level)
	if build_lighting:
		_build_level_lighting(_container(root, "Lighting"), level_data)
	# Props run before the room markers so each room can publish a standing
	# point that is not inside its own dining table.
	if build_furniture and detail == Detail.FULL:
		_build_level_props(_container(root, "Props"), level_data)
	_build_room_markers(_container(root, "Rooms"), level_data)


func _build_floors(parent: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	var y := level * spec.floor_height
	var openings := _floor_openings(level)
	var walkable: Dictionary = {}
	for cell: Vector2i in level_data["walkable"]:
		if not openings.has(cell):
			walkable[cell] = true
	for rect: Rect2i in _architecture_rects(walkable):
		var size := spec.rect_world_size(rect)
		var centre := spec.rect_to_world(rect, level)
		var slab := _static_box(
			parent,
			"FloorSlab",
			Vector3(centre.x, y - SLAB_THICKNESS * 0.5, centre.z),
			Vector3(size.x, SLAB_THICKNESS, size.y),
			_floor_material,
			detail == Detail.BLOCKOUT
		)
		if detail == Detail.FULL:
			_dress_floor(slab, rect, y)


## Lays the kit's 4x4 m tiles over each slab, falling back to 2x2 m wherever a
## 2x2 block of cells does not fit. Tiling straight from the cell grid would
## cost four times the instances for the same picture on an 80x60 m map.
func _dress_floor(parent: Node3D, rect: Rect2i, y: float) -> void:
	var end_col := rect.position.x + rect.size.x
	var end_row := rect.position.y + rect.size.y
	var covered: Dictionary = {}
	for col: int in range(rect.position.x, end_col):
		for row: int in range(rect.position.y, end_row):
			var cell := Vector2i(col, row)
			if covered.has(cell):
				continue
			# A big tile needs all four cells free, so it is decided per block,
			# never per column: an odd row count used to leave a bare strip.
			if col + 1 < end_col and row + 1 < end_row \
					and not covered.has(Vector2i(col + 1, row)) \
					and not covered.has(Vector2i(col, row + 1)) \
					and not covered.has(Vector2i(col + 1, row + 1)):
				_asset(FLOOR_4X4, parent, "FloorTile", Vector3(
					(col + 1) * spec.cell_size, y, (row + 1) * spec.cell_size
				))
				for offset_x: int in 2:
					for offset_y: int in 2:
						covered[cell + Vector2i(offset_x, offset_y)] = true
			else:
				var centre := spec.grid_to_world(col, row, 0)
				_asset(FLOOR_2X2, parent, "FloorTile", Vector3(centre.x, y, centre.z))
				covered[cell] = true


func _build_walls(parent: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	var walkable: Dictionary = level_data["walkable"]
	var shaft := _shaft_cells(level)
	var railings := _container(parent, "Railings")

	for run: Dictionary in VillaSpec.wall_runs(walkable):
		var neighbour_cell := _run_neighbour(run)
		if shaft.has(neighbour_cell):
			_build_railing_run(railings, run, level)
			continue
		_build_wall_run(parent, run, level, "InteriorWall")

	_build_shaft_lining(parent, level_data)
	_build_exterior_shell(parent, level_data)


## The light shaft is solid grid on the storeys it rises through, so no room
## borders it and the wall pass above produces nothing: looking up from the
## atrium used to show an unlined cavity. Line the opening from inside.
func _build_shaft_lining(parent: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	var shaft := _shaft_cells(level)
	if shaft.is_empty():
		return
	var walkable: Dictionary = level_data["walkable"]
	var lining := _container(parent, "ShaftLining")
	for run: Dictionary in VillaSpec.wall_runs(shaft):
		# The gallery side is already open, with a railing standing in for the
		# wall; every other side gets a full-height lining.
		if walkable.has(_run_neighbour(run)):
			continue
		_build_wall_run(lining, run, level, "ShaftWall")


## The interior faces above stop at the inner side of each wall block, so the
## building also needs an outward-facing skin along the level footprint. Cells
## an entrance occupies stay open: that hole is the breach point.
func _build_exterior_shell(parent: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	var extent: Rect2i = level_data["extent"]
	var cells: Dictionary = level_data["cells"]
	var shell: Dictionary = {}
	for cell: Vector2i in cells:
		var on_border := (
			cell.x == extent.position.x
			or cell.x == extent.position.x + extent.size.x - 1
			or cell.y == extent.position.y
			or cell.y == extent.position.y + extent.size.y - 1
		)
		if on_border and cells[cell] != VillaSpec.BREACH:
			shell[cell] = true

	for run: Dictionary in VillaSpec.wall_runs(shell):
		# Only the faces that look out of the footprint belong to the skin.
		if cells.has(_run_neighbour(run)):
			continue
		_build_wall_run(parent, run, level, "ExteriorWall")


func _build_wall_run(parent: Node3D, run: Dictionary, level: int, wall_name: String) -> void:
	var direction: Vector2i = run["dir"]
	var span: int = int(run["to"]) - int(run["from"]) + 1
	if authoring_granularity == AuthoringGranularity.EDITABLE_MODULES and span > 1:
		for value: int in range(int(run["from"]), int(run["to"]) + 1):
			var module_run := run.duplicate()
			module_run["from"] = value
			module_run["to"] = value
			_build_wall_run(parent, module_run, level, wall_name)
		return
	var length := span * spec.cell_size
	var y := level * spec.floor_height
	var plane := _run_plane(run)
	var along_z := direction.x != 0

	var centre := plane + Vector3(
		direction.x * WALL_THICKNESS * 0.5,
		y + spec.floor_height * 0.5,
		direction.y * WALL_THICKNESS * 0.5
	)
	var size := (
		Vector3(WALL_THICKNESS, spec.floor_height, length)
		if along_z
		else Vector3(length, spec.floor_height, WALL_THICKNESS)
	)
	var body := _static_box(
		parent, wall_name, centre, size, _wall_material, detail == Detail.BLOCKOUT
	)
	if detail != Detail.FULL:
		return

	var rotation_y := PI * 0.5 if along_z else 0.0
	var stretch := Vector3(1, spec.floor_height / KIT_WALL_HEIGHT, 1)
	for index: int in span:
		var offset := (index + 0.5) * spec.cell_size - length * 0.5
		var module_position := plane + Vector3(
			0.0 if along_z else offset,
			0.0,
			offset if along_z else 0.0
		)
		module_position.y = y
		_asset(WALL_3X2, body, wall_name + "Module", module_position, rotation_y, stretch)


func _build_railing_run(parent: Node3D, run: Dictionary, level: int) -> void:
	var direction: Vector2i = run["dir"]
	var span: int = int(run["to"]) - int(run["from"]) + 1
	if authoring_granularity == AuthoringGranularity.EDITABLE_MODULES and span > 1:
		for value: int in range(int(run["from"]), int(run["to"]) + 1):
			var module_run := run.duplicate()
			module_run["from"] = value
			module_run["to"] = value
			_build_railing_run(parent, module_run, level)
		return
	var length := span * spec.cell_size
	var y := level * spec.floor_height
	var plane := _run_plane(run)
	var along_z := direction.x != 0

	# A waist-high barrier: it must stop a sprinting capsule without hiding the
	# storey below, which is the whole point of the light shaft.
	var size := (
		Vector3(0.16, 1.1, length) if along_z else Vector3(length, 1.1, 0.16)
	)
	var body := _static_box(
		parent,
		"AtriumRailing",
		plane + Vector3(direction.x * 0.08, y + 0.55, direction.y * 0.08),
		size,
		_wall_material,
		detail == Detail.BLOCKOUT
	)
	if detail != Detail.FULL:
		return
	var rotation_y := PI * 0.5 if along_z else 0.0
	# One panel spans 1 m, not one 2 m cell. Placing a single panel per cell
	# left a metre of open air between every section - a row of loose fences
	# rather than a balustrade.
	var panels := int(round(length / KIT_RAIL_WIDTH))
	for index: int in panels:
		var offset := (index + 0.5) * KIT_RAIL_WIDTH - length * 0.5
		var rail_position := plane + Vector3(
			0.0 if along_z else offset, 0.0, offset if along_z else 0.0
		)
		rail_position.y = y
		_asset(BALCONY_RAIL, body, "AtriumRail", rail_position, rotation_y)


## Every storey needs a lid over the cells the storey above does not floor,
## otherwise the wall blocks between rooms are open to the sky. Vertical links
## and the light shaft are punched back out.
func _build_ceiling(parent: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	var above: Dictionary = levels.get(level + 1, {})
	var above_walkable: Dictionary = above.get("walkable", {}) if above else {}
	var punched := _ceiling_openings(level)

	var lid: Dictionary = {}
	for cell: Vector2i in level_data["cells"]:
		if above_walkable.has(cell) or punched.has(cell):
			continue
		lid[cell] = true
	if lid.is_empty():
		return

	var y := (level + 1) * spec.floor_height
	var container := _container(parent, "Ceiling")
	for rect: Rect2i in _architecture_rects(lid):
		var size := spec.rect_world_size(rect)
		var centre := spec.rect_to_world(rect, level)
		_static_box(
			container,
			"CeilingSlab",
			Vector3(centre.x, y - SLAB_THICKNESS * 0.5, centre.z),
			Vector3(size.x, SLAB_THICKNESS, size.y),
			_ceiling_material,
			true
		)


## A stair arriving from below has to come up through a hole. Everything the
## run passes beneath is cut out of the upper floor; the landing tile itself
## stays solid, because that is where the climber steps off.
func _floor_openings(level: int) -> Dictionary:
	var openings: Dictionary = {}
	for link: Dictionary in spec.vertical_links():
		if String(link["type"]) == "shaft":
			continue
		if maxi(int(link["from"]), int(link["to"])) != level:
			continue
		for cell: Vector2i in _link_footprint(link):
			openings[cell] = true
	return openings


## The cells a ramp runs beneath, walking downhill from the landing for as far
## as the rise carries it.
func _link_footprint(link: Dictionary) -> Array[Vector2i]:
	var low: int = mini(int(link["from"]), int(link["to"]))
	var high: int = maxi(int(link["from"]), int(link["to"]))
	var rise := (high - low) * spec.floor_height
	var uphill := _heading_vector(String(link.get("heading", "north")))
	var along_x := uphill.x != 0
	var step := -1 if (uphill.x + uphill.z) > 0.0 else 1
	var landing := _link_landing_index(link)
	var depth := ceili(rise / spec.cell_size)

	var footprint: Array[Vector2i] = []
	for lateral_value: int in _link_lateral_cells(link):
		for index: int in range(1, depth + 1):
			var along := landing + step * index
			footprint.append(
				Vector2i(along, lateral_value) if along_x else Vector2i(lateral_value, along)
			)
	return footprint


func _ceiling_openings(level: int) -> Dictionary:
	var punched: Dictionary = {}
	for link: Dictionary in spec.vertical_links():
		var low: int = mini(int(link["from"]), int(link["to"]))
		if String(link["type"]) == "shaft":
			# The shaft is open all the way to the roof, so both lids give way.
			if level >= low:
				_mark(punched, VillaSpec.to_rect(link["rect"]))
			continue
		if low == level:
			_mark(punched, VillaSpec.to_rect(link["rect"]))
	for entrance: Dictionary in spec.entrances():
		if int(entrance["level"]) == level and bool(entrance.get("overhead", false)):
			for cell_pair: Variant in entrance["cells"]:
				punched[VillaSpec.to_cell(cell_pair)] = true
	return punched


func _build_doors(parent: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	var interior_door: PackedScene = load("res://door/door.tscn")
	for door: Dictionary in level_data["doors"]:
		var cell: Vector2i = door["cell"]
		var travels_x: bool = String(door["axis"]) == "x"
		var origin := spec.grid_to_world(cell.x, cell.y, level)

		# Header beam over the opening so the doorway reads as a doorway from
		# both sides and the navmesh bake sees a capped hole, not a slot.
		var header_height := spec.floor_height - DOOR_CLEAR_HEIGHT
		var header := _static_box(
			parent,
			"DoorHeader",
			Vector3(origin.x, origin.y + DOOR_CLEAR_HEIGHT + header_height * 0.5, origin.z),
			Vector3(spec.cell_size, header_height, spec.cell_size),
			_wall_material,
			detail == Detail.BLOCKOUT
		)
		if detail == Detail.FULL:
			_dress_door_header(header, cell, level, travels_x, header_height)

		var leaf := interior_door.instantiate() as Node3D
		leaf.name = "Door_%d_%d" % [cell.x, cell.y]
		# The leaf is authored at the spec's 2 m width and hinges on its local
		# origin. Do not non-uniformly scale this rotating node: combining that
		# scale with the Hinge yaw introduces shear and can inflate the leaf when
		# its tween is interrupted and restarted.
		if travels_x:
			# Yawing by 90 degrees sends the leaf's local +X to world -Z, so it
			# has to hang from the far jamb to close across the opening.
			leaf.rotation.y = PI * 0.5
			leaf.position = Vector3(origin.x, origin.y, origin.z + spec.cell_size * 0.5)
		else:
			leaf.position = Vector3(origin.x - spec.cell_size * 0.5, origin.y, origin.z)
		leaf.add_to_group("villa_interior_doors")
		parent.add_child(leaf)


## A lintel on each face of the 2 m deep opening, cut from the same kit panel
## as the wall it interrupts. A bare box here read as a dark patch against the
## kit's near-white plaster - which is exactly what "a hole" looks like.
func _dress_door_header(
	header: Node3D, cell: Vector2i, level: int, travels_x: bool, header_height: float
) -> void:
	var lintel_y := level * spec.floor_height + DOOR_CLEAR_HEIGHT
	var stretch := Vector3(1, header_height / KIT_WALL_HEIGHT, 1)
	var rotation_y := PI * 0.5 if travels_x else 0.0
	for side: int in 2:
		var face := (cell.x + side) * spec.cell_size if travels_x \
			else (cell.y + side) * spec.cell_size
		var origin := spec.grid_to_world(cell.x, cell.y, level)
		var position := (
			Vector3(face, lintel_y, origin.z) if travels_x
			else Vector3(origin.x, lintel_y, face)
		)
		_asset(WALL_3X2, header, "DoorLintel", position, rotation_y, stretch)


func _occupy(level: int, cell: Vector2i) -> void:
	_occupied["%d:%d:%d" % [level, cell.x, cell.y]] = true


## The tile nearest a room's middle that something could actually stand on:
## floor, not a stairwell opening, and not under a wardrobe. Ghost routes and
## anything else that needs a point in a room use this rather than the raw
## centre, which is frequently occupied by that room's own table.
func _clear_point(rect: Rect2i, level: int) -> Vector3:
	var walkable: Dictionary = levels.get(level, {}).get("walkable", {})
	var openings := _floor_openings(level)
	var middle := Vector2(rect.position) + Vector2(rect.size) * 0.5
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for col: int in range(rect.position.x, rect.position.x + rect.size.x):
		for row: int in range(rect.position.y, rect.position.y + rect.size.y):
			var cell := Vector2i(col, row)
			if not walkable.has(cell) or openings.has(cell):
				continue
			if _occupied.has("%d:%d:%d" % [level, col, row]):
				continue
			var distance := (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(middle)
			if distance < best_distance:
				best_distance = distance
				best = cell
	if best.x < 0:
		return spec.rect_to_world(rect, level)
	return spec.grid_to_world(best.x, best.y, level)


func _build_room_markers(parent: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	for room: Dictionary in level_data["rooms"]:
		var rect := VillaSpec.to_rect(room["rect"])
		var size := spec.rect_world_size(rect)
		var marker := Marker3D.new()
		marker.name = String(room["id"])
		marker.position = spec.rect_to_world(rect, level)
		marker.set_meta("clear_point", _clear_point(rect, level))
		marker.set_meta("room_id", String(room["id"]))
		marker.set_meta("room_name", String(room["name"]))
		marker.set_meta("room_kind", String(room.get("kind", "empty")))
		marker.set_meta("room_size", Vector3(size.x, spec.floor_height, size.y))
		marker.add_to_group("villa_rooms")
		marker.add_to_group("house2_rooms")
		parent.add_child(marker)


func _build_junction_markers(parent: Node3D, level: int) -> void:
	for junction: Dictionary in spec.junctions_on(level):
		var rect := VillaSpec.to_rect(junction["rect"])
		var marker := Marker3D.new()
		marker.name = String(junction["id"])
		marker.position = spec.rect_to_world(rect, level)
		marker.set_meta("junction_id", String(junction["id"]))
		marker.set_meta("degree", int(junction["degree"]))
		marker.add_to_group("villa_junctions")
		parent.add_child(marker)


# --- vertical circulation (spec section 8) -----------------------------------

func _build_vertical_links(parent: Node3D) -> void:
	for link: Dictionary in spec.vertical_links():
		var type := String(link["type"])
		if type == "shaft":
			_build_shaft_parapet(parent, link)
			continue
		_build_ramp_link(parent, link)
		_build_stairwell_railing(parent, link)


## The hole a stair comes up through is left open in the floor above. Without a
## balustrade around the three sides you do not arrive on, it reads as damage
## rather than as a stairwell - and it is a 3.5 m drop nobody asked for.
func _build_stairwell_railing(parent: Node3D, link: Dictionary) -> void:
	var upper: int = maxi(int(link["from"]), int(link["to"]))
	var walkable: Dictionary = levels.get(upper, {}).get("walkable", {})
	var opening: Dictionary = {}
	for cell: Vector2i in _link_footprint(link):
		opening[cell] = true
	if opening.is_empty():
		return

	var landing := _link_landing_index(link)
	var along_x := _heading_vector(String(link.get("heading", "north"))).x != 0
	var rails := _container(parent, String(link["id"]) + "Railing")
	for run: Dictionary in VillaSpec.wall_runs(opening):
		var neighbour := _run_neighbour(run)
		if not walkable.has(neighbour):
			continue
		# Leave the arrival side open, or the stair would be railed shut.
		if (neighbour.x if along_x else neighbour.y) == landing:
			continue
		_build_railing_run(rails, run, upper)


## Where the shaft breaks through the roof deck it needs a kerb, both so the
## opening reads as a skylight from above and so nothing walks off the edge.
func _build_shaft_parapet(parent: Node3D, link: Dictionary) -> void:
	var rect := VillaSpec.to_rect(link["rect"])
	var roof_y := (int(link["to"]) + 1) * spec.floor_height
	var size := spec.rect_world_size(rect)
	var centre := spec.rect_to_world(rect, 0)
	var kerb := _container(parent, String(link["id"]) + "Parapet")
	for axis: int in 2:
		for side: float in [-1.0, 1.0]:
			var along := size.y if axis == 0 else size.x
			var offset := (size.x if axis == 0 else size.y) * 0.5 + 0.15
			_static_box(
				kerb,
				"ShaftParapet",
				Vector3(
					centre.x + (offset * side if axis == 0 else 0.0),
					roof_y + 0.55,
					centre.z + (0.0 if axis == 0 else offset * side)
				),
				Vector3(0.3, 1.1, along + 0.6) if axis == 0
					else Vector3(along + 0.6, 1.1, 0.3),
				_ceiling_material,
				true
			)


## Both the grand stairs and the attic companionway are built as one authored
## 45-degree ramp, the same trick House2 uses: the capsule glides instead of
## stepping tread by tread, and Recast gets a single continuous surface.
func _build_ramp_link(parent: Node3D, link: Dictionary) -> void:
	var low: int = mini(int(link["from"]), int(link["to"]))
	var high: int = maxi(int(link["from"]), int(link["to"]))
	var rise := (high - low) * spec.floor_height
	var rect := VillaSpec.to_rect(link["rect"])
	var heading := String(link.get("heading", "north"))
	var uphill := _heading_vector(heading)

	var along_x := uphill.x != 0
	var lateral := _link_lateral_cells(link)
	if lateral.is_empty():
		push_error("Vertical link %s has no cell walkable on both levels." % link["id"])
		return

	# A 45-degree run of 3.5 m needs 3.5 m of floor plus somewhere to step off,
	# and the spec's link rectangles are only 4 m deep. So the rectangle fixes
	# where the stair *head* is, and the run itself continues downhill past it.
	var landing := _link_landing_index(link)
	var sign := 1.0 if (uphill.x + uphill.z) > 0.0 else -1.0
	var top := (landing + (0 if sign > 0.0 else 1)) * spec.cell_size
	var centre_along := top - sign * rise * 0.5
	var lateral_centre := (lateral[0] + lateral[-1] + 1) * 0.5 * spec.cell_size

	var centre := (
		Vector3(centre_along, 0.0, lateral_centre)
		if along_x
		else Vector3(lateral_centre, 0.0, centre_along)
	)
	centre.y = low * spec.floor_height

	var body := _add_ramp(
		parent,
		String(link["id"]),
		centre - uphill * rise * 0.5,
		uphill,
		rise,
		float(link.get("width", 1.8))
	)
	body.set_meta("link_id", String(link["id"]))
	body.set_meta("link_type", String(link["type"]))
	body.set_meta("enter_cost", float(link.get("cost", 3.5)))
	body.set_meta("hands_required", int(link.get("hands_required", 0)))


## One 45-degree ramp: a box collider the capsule glides up, plus the kit's
## stair mesh stretched onto exactly that box.
##
## `base` is the foot of the run, at the lower storey's floor height.
func _add_ramp(
	parent: Node3D,
	ramp_name: String,
	base: Vector3,
	uphill: Vector3,
	rise: float,
	width: float
) -> StaticBody3D:
	# The ramp's local +X is its uphill axis, so solve for the yaw that sends
	# +X onto the heading rather than the usual look-along-Z yaw.
	var rotation_y := atan2(-uphill.z, uphill.x)
	var middle := base + uphill * rise * 0.5

	var body := StaticBody3D.new()
	body.name = ramp_name + "SmoothRamp"
	body.position = middle + Vector3(0, rise * 0.5, 0)
	body.basis = Basis(Vector3.UP, rotation_y) * Basis(Vector3.BACK, PI * 0.25)
	body.add_to_group("smooth_stair_ramps")
	body.add_to_group("villa_stair_ramps")
	body.set_meta("rise", rise)
	parent.add_child(body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(rise * sqrt(2.0), 0.16, width)
	var collision := CollisionShape3D.new()
	collision.name = "SmoothRampCollision"
	collision.shape = shape
	body.add_child(collision)

	if detail != Detail.FULL:
		return body
	# The kit's *treads* are a 3 x 3 m staircase; its 4.2 m total AABB includes
	# the handrail continuing 1.2 m above the landing. Scaling Y from that total
	# height used to leave the top tread a metre below a 3.5 m villa floor. X and
	# Y must use the same factor so the visible stair stays at the ramp's 45°.
	var visual := _asset(
		BIG_STAIR, parent, ramp_name + "Visual", middle, rotation_y,
		Vector3(rise / KIT_STAIR_RUN, rise / KIT_STAIR_RISE, width / KIT_STAIR_WIDTH)
	)
	visual.add_to_group("smooth_stair_visual")
	visual.set_meta("stair_base_y", base.y)
	visual.set_meta("stair_top_y", base.y + rise)
	return body


## The cell line across a link's width that is floor on both levels it joins,
## so a ramp is never centred half inside a wall. V03 needs this: its 2-cell
## rectangle reaches a column that only exists on the ground floor.
func _link_lateral_cells(link: Dictionary) -> Array[int]:
	var low: int = mini(int(link["from"]), int(link["to"]))
	var high: int = maxi(int(link["from"]), int(link["to"]))
	var rect := VillaSpec.to_rect(link["rect"])
	var along_x := _heading_vector(String(link.get("heading", "north"))).x != 0
	var low_walkable: Dictionary = levels.get(low, {}).get("walkable", {})
	var high_walkable: Dictionary = levels.get(high, {}).get("walkable", {})

	var lateral: Array[int] = []
	for col: int in range(rect.position.x, rect.position.x + rect.size.x):
		for row: int in range(rect.position.y, rect.position.y + rect.size.y):
			var cell := Vector2i(col, row)
			if not (low_walkable.has(cell) and high_walkable.has(cell)):
				continue
			var value := cell.y if along_x else cell.x
			if not lateral.has(value):
				lateral.append(value)
	lateral.sort()
	return lateral


## Cell index, along the heading axis, of the tile a climber steps off onto.
func _link_landing_index(link: Dictionary) -> int:
	var rect := VillaSpec.to_rect(link["rect"])
	var uphill := _heading_vector(String(link.get("heading", "north")))
	if uphill.x > 0:
		return rect.position.x + rect.size.x - 1
	if uphill.x < 0:
		return rect.position.x
	if uphill.z > 0:
		return rect.position.y + rect.size.y - 1
	return rect.position.y


static func _heading_vector(heading: String) -> Vector3:
	match heading:
		"north": return Vector3(0, 0, -1)
		"south": return Vector3(0, 0, 1)
		"east": return Vector3(1, 0, 0)
		_: return Vector3(-1, 0, 0)


# --- entrances, spawns, ghost routes -----------------------------------------

func _build_entrance_anchors(parent: Node3D) -> void:
	for entrance: Dictionary in spec.entrances():
		var level := int(entrance["level"])
		var cells: Array = entrance["cells"]
		var centre := Vector3.ZERO
		for cell_pair: Variant in cells:
			var cell := VillaSpec.to_cell(cell_pair)
			centre += spec.grid_to_world(cell.x, cell.y, level)
		centre /= float(cells.size())

		var anchor := Marker3D.new()
		anchor.name = String(entrance["id"]) + "Anchor"
		anchor.position = centre
		anchor.set_meta("entrance_id", int(entrance["entrance_id"]))
		anchor.set_meta("spec_id", String(entrance["id"]))
		anchor.set_meta("layers", int(entrance["layers"]))
		anchor.set_meta("break_seconds", float(entrance["break"]))
		anchor.set_meta("repair_seconds", float(entrance["repair"]))
		anchor.set_meta("room", String(entrance["room"]))
		anchor.set_meta("overhead", bool(entrance.get("overhead", false)))

		if bool(entrance.get("overhead", false)):
			# A roof light sits in the ceiling, not in a wall, so the anchor
			# rises to the skylight itself; villa_main lays its door flat there.
			anchor.position.y += spec.floor_height
		else:
			var outward := _entrance_outward(entrance)
			anchor.rotation.y = atan2(outward.x, outward.z)
		anchor.add_to_group("villa_entrance_anchors")
		parent.add_child(anchor)


func _entrance_outward(entrance: Dictionary) -> Vector3:
	var extent := spec.level_extent(int(entrance["level"]))
	var cell := VillaSpec.to_cell(entrance["cells"][0])
	if cell.x == extent.position.x:
		return Vector3(-1, 0, 0)
	if cell.x == extent.position.x + extent.size.x - 1:
		return Vector3(1, 0, 0)
	if cell.y == extent.position.y:
		return Vector3(0, 0, -1)
	return Vector3(0, 0, 1)


func _build_spawn_points(parent: Node3D) -> void:
	for spawn: Dictionary in spec.spawn_points():
		var cell := VillaSpec.to_cell(spawn["cell"])
		var marker := Marker3D.new()
		marker.name = String(spawn["id"])
		marker.position = spec.grid_to_world(cell.x, cell.y, int(spawn["level"]))
		marker.add_to_group("villa_spawn_points")
		parent.add_child(marker)


## Hunter sweeps the ring by junction, then the rooms; the crawler patrols the
## rooms and lairs in the attic. Both read their route from groups, so filling
## those groups here is all the ghosts need from a new map.
func _build_ghost_routes(parent: Node3D) -> void:
	var sweeps := _container(parent, "HunterRoute")
	var index := 0
	for junction: Dictionary in spec.data.get("junctions", []):
		var rect := VillaSpec.to_rect(junction["rect"])
		index += 1
		_route_marker(
			sweeps,
			"Sweep%02d%s" % [index, String(junction["id"])],
			spec.rect_to_world(rect, int(junction["level"])),
			"hunter_sweep_points"
		)

	var patrol := _container(parent, "CrawlerRoute")
	var patrol_index := 0
	for level: int in spec.level_ids():
		for room: Dictionary in levels[level]["rooms"]:
			var rect := VillaSpec.to_rect(room["rect"])
			var centre := _clear_point(rect, level)
			patrol_index += 1
			_route_marker(
				patrol,
				"Patrol%02d%s" % [patrol_index, String(room["id"])],
				centre,
				"crawler_patrol_points"
			)
			index += 1
			_route_marker(
				sweeps,
				"Sweep%02d%s" % [index, String(room["id"])],
				centre,
				"hunter_sweep_points"
			)

	var attic := spec.room("R_ATTIC")
	if not attic.is_empty():
		_route_marker(
			patrol,
			"Lair",
			_clear_point(VillaSpec.to_rect(attic["rect"]), int(attic["level"])),
			"crawler_lair"
		)


func _route_marker(parent: Node3D, marker_name: String, position: Vector3, group: String) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	# Ghost navigation agents want a point just above the walking surface.
	marker.position = position + Vector3(0, 0.4, 0)
	marker.add_to_group(group)
	parent.add_child(marker)


# --- lighting and props ------------------------------------------------------

func _build_level_lighting(parent: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	var y := level * spec.floor_height + spec.floor_height - 0.7
	for room: Dictionary in level_data["rooms"]:
		var rect := VillaSpec.to_rect(room["rect"])
		var centre := spec.rect_to_world(rect, level)
		_add_light(
			parent,
			String(room["id"]) + "Light",
			Vector3(centre.x, y, centre.z),
			Color(0.62, 0.47, 0.29),
			0.55,
			maxf(6.0, minf(float(rect.size.x), float(rect.size.y)) * spec.cell_size * 0.9)
		)
		if detail == Detail.FULL:
			_asset(_furniture("Ceiling Lamp 2"), parent, "CeilingFixture",
				Vector3(centre.x, y + 0.42, centre.z))
	for junction: Dictionary in spec.junctions_on(level):
		var rect := VillaSpec.to_rect(junction["rect"])
		var centre := spec.rect_to_world(rect, level)
		_add_light(
			parent,
			String(junction["id"]) + "Light",
			Vector3(centre.x, y, centre.z),
			Color(0.55, 0.44, 0.32),
			0.5,
			8.0,
			true
		)


func _build_level_props(parent: Node3D, level_data: Dictionary) -> void:
	var level: int = level_data["level"]
	var reserved := _reserved_cells(level_data)
	for room: Dictionary in level_data["rooms"]:
		var kind := String(room.get("kind", "empty"))
		var plan: Dictionary = FURNITURE_PLANS.get(kind, {})
		if plan.is_empty():
			continue
		var room_node := _container(parent, String(room["id"]) + "Props")
		var rect := VillaSpec.to_rect(room["rect"])
		# Seeded per room, so a room is furnished the same way every launch and
		# players can learn where the cover is.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(room["id"]))
		_furnish_walls(room_node, rect, level_data, plan, reserved, rng)
		_furnish_middle(room_node, rect, level, plan)
		_furnish_interior(room_node, rect, level_data, plan, reserved, rng)


## Cells furniture must stay out of: doorways and the tile either side of them,
## and anything a staircase runs through.
func _reserved_cells(level_data: Dictionary) -> Dictionary:
	var reserved: Dictionary = {}
	for door: Dictionary in level_data["doors"]:
		var cell: Vector2i = door["cell"]
		reserved[cell] = true
		for direction: Vector2i in VillaSpec.DIRECTIONS:
			reserved[cell + direction] = true
	for breach: Dictionary in level_data["breaches"]:
		var cell: Vector2i = breach["cell"]
		reserved[cell] = true
		for direction: Vector2i in VillaSpec.DIRECTIONS:
			reserved[cell + direction] = true
	# A stair needs its approach kept clear too, not just its footprint: a
	# wardrobe on the tile in front of a landing cuts the floor off the ramp.
	var stair_cells: Dictionary = {}
	for link: Dictionary in spec.vertical_links():
		if String(link["type"]) == "shaft":
			continue
		if not int(level_data["level"]) in [int(link["from"]), int(link["to"])]:
			continue
		_mark(stair_cells, VillaSpec.to_rect(link["rect"]))
		for cell: Vector2i in _link_footprint(link):
			stair_cells[cell] = true
	for cell: Vector2i in stair_cells:
		reserved[cell] = true
		for direction: Vector2i in VillaSpec.DIRECTIONS:
			reserved[cell + direction] = true
	return reserved


## Every cell of a room that has a wall on one side and is free to build
## against, in perimeter order so that spacing them out is a matter of stride.
func _wall_slots(
	rect: Rect2i, level_data: Dictionary, reserved: Dictionary
) -> Array[Dictionary]:
	var level: int = level_data["level"]
	var walkable: Dictionary = level_data["walkable"]
	var slots: Array[Dictionary] = []
	for col: int in range(rect.position.x, rect.position.x + rect.size.x):
		for row: int in range(rect.position.y, rect.position.y + rect.size.y):
			var cell := Vector2i(col, row)
			if reserved.has(cell) or not walkable.has(cell):
				continue
			for direction: Vector2i in VillaSpec.DIRECTIONS:
				if walkable.has(cell + direction):
					continue
				slots.append({
					"cell": cell,
					"wall": direction,
					"centre": spec.grid_to_world(cell.x, cell.y, level),
					# Assets in this kit face -Z, so this yaw turns a back-to-
					# the-wall piece around to look into the room.
					"facing": atan2(direction.x, direction.y),
				})
				break
	return slots


func _furnish_walls(
	parent: Node3D,
	rect: Rect2i,
	level_data: Dictionary,
	plan: Dictionary,
	reserved: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	var slots := _wall_slots(rect, level_data, reserved)
	var unique: Array = plan.get("unique", [])
	var large := _shuffled(plan.get("large", []), rng)
	var small := _shuffled(plan.get("small", []), rng)
	if slots.is_empty() or (unique.is_empty() and large.is_empty() and small.is_empty()):
		return

	# One piece per four cells of floor fills a room without turning it into a
	# warehouse; the number of free wall slots is the hard ceiling.
	# Compact rooms still need every required fixture. Without this floor, a
	# 2x2 WC only requested two slots and silently lost its mirror.
	var wanted := maxi(unique.size(), clampi(roundi(rect.size.x * rect.size.y / 4.0), 2, 18))
	var count := mini(wanted, slots.size())
	var stride := float(slots.size()) / float(count)
	var large_index := 0
	var small_index := 0

	for index: int in count:
		var slot: Dictionary = slots[mini(int(index * stride), slots.size() - 1)]
		var item := ""
		if index < unique.size():
			item = String(unique[index])
		elif (index % 3 == 2 or large.is_empty()) and not small.is_empty():
			item = String(small[small_index % small.size()])
			small_index += 1
		elif not large.is_empty():
			item = String(large[large_index % large.size()])
			large_index += 1
		if item.is_empty():
			continue
		_place_against_wall(parent, item, slot)
		if not item in WALL_HUNG:
			_occupy(int(level_data["level"]), slot["cell"])


## A 24 m attic furnished only round its walls still looks abandoned. Drop a
## few pieces into the middle of the bigger rooms, on a three-cell lattice so
## there is always a 4 m lane between them and nothing can wall a route off.
func _furnish_interior(
	parent: Node3D,
	rect: Rect2i,
	level_data: Dictionary,
	plan: Dictionary,
	reserved: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	var items := _shuffled(plan.get("large", []), rng)
	if items.is_empty() or rect.size.x < 4 or rect.size.y < 4:
		return
	var level: int = level_data["level"]
	var walkable: Dictionary = level_data["walkable"]
	var index := 0
	for col: int in range(rect.position.x + 1, rect.position.x + rect.size.x - 1, 3):
		for row: int in range(rect.position.y + 1, rect.position.y + rect.size.y - 1, 3):
			var cell := Vector2i(col, row)
			if reserved.has(cell) or not walkable.has(cell):
				continue
			if _occupied.has("%d:%d:%d" % [level, col, row]):
				continue
			var item := String(items[index % items.size()])
			index += 1
			_asset(
				_furniture(item), parent, item,
				spec.grid_to_world(col, row, level),
				rng.randf_range(-PI, PI)
			)
			_occupy(level, cell)


func _shuffled(source: Array, rng: RandomNumberGenerator) -> Array:
	var result := source.duplicate()
	for index: int in range(result.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held: Variant = result[index]
		result[index] = result[swap]
		result[swap] = held
	return result


func _place_against_wall(parent: Node3D, item: String, slot: Dictionary) -> void:
	var wall: Vector2i = slot["wall"]
	var centre: Vector3 = slot["centre"]
	var facing: float = slot["facing"]
	var toward_wall := Vector3(wall.x, 0.0, wall.y)

	if item in WALL_HUNG:
		# Hangs flat on the plaster at eye height rather than standing on the
		# floor in front of it.
		var plane := centre + toward_wall * (spec.cell_size * 0.5 - 0.06)
		_asset(_furniture(item), parent, item, Vector3(plane.x, centre.y + 1.7, plane.z), facing)
		return

	var against := centre + toward_wall * (spec.cell_size * 0.5 - 0.55)
	_asset(_furniture(item), parent, item, against, facing)
	if item == "Toilet":
		_place_toilet_interactable(parent, against, facing)
	if item.begins_with("Bed Base"):
		_asset(
			_furniture("Bed 1 Sheets"), parent, "BedSheets",
			against + Vector3(0, 0.52, 0), facing
		)


## The furniture FBX supplies the visible bowl; this colocated gameplay scene
## supplies interaction, collision and the per-toilet minigame used in House2.
func _place_toilet_interactable(parent: Node3D, position: Vector3, rotation_y: float) -> void:
	var toilet := TOILET_INTERACTABLE.instantiate() as Node3D
	_module_index += 1
	toilet.name = "ToiletInteractable_%04d" % _module_index
	toilet.position = position - _world_offset(parent)
	toilet.rotation.y = rotation_y
	toilet.add_to_group("villa_toilets")
	parent.add_child(toilet)


## A centre piece plus its seating, for the rooms that are built around one:
## the dining table, the altar, the billiard room's lounge set.
func _furnish_middle(parent: Node3D, rect: Rect2i, level: int, plan: Dictionary) -> void:
	var table := String(plan.get("table", ""))
	if table.is_empty():
		return
	var centre := spec.rect_to_world(rect, level)
	centre.y = level * spec.floor_height
	_asset(_furniture(table), parent, table, centre)

	# The table and its ring of seats take a 3x3 bite out of the middle.
	var middle_cell := Vector2i(
		rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2
	)
	_occupy(level, middle_cell)
	for direction: Vector2i in VillaSpec.DIRECTIONS:
		_occupy(level, middle_cell + direction)
		_occupy(level, middle_cell - Vector2i(1, 1) + direction)

	var seat := String(plan.get("seat", ""))
	if seat.is_empty():
		return
	# Seats face the table, so each one's yaw points from itself back to it.
	for index: int in int(plan.get("seats", 4)):
		var angle := TAU * index / float(plan.get("seats", 4))
		var offset := Vector3(sin(angle), 0.0, cos(angle)) * 1.5
		_asset(_furniture(seat), parent, seat, centre + offset, angle + PI)


# --- outside -----------------------------------------------------------------

## Distance west of the facade at which the cellar trench comes back up to
## garden level; the ramp occupies the last 3.5 m of it.
const TRENCH_FAR_X := -13.5


func _build_site(site: Node3D) -> void:
	var width := spec.grid_width * spec.cell_size
	var depth := spec.grid_height * spec.cell_size
	var margin := 24.0
	var trench := _trench_rect()

	# Ground aprons ring the footprint. The west apron is split around the open
	# trench that leads down to the cellar door.
	_ground_slab(site, "GroundNorth", Rect2(-margin, -margin, width + margin * 2, margin))
	_ground_slab(site, "GroundSouth", Rect2(-margin, depth, width + margin * 2, margin))
	_ground_slab(site, "GroundEast", Rect2(width, 0, margin, depth))
	_ground_slab(site, "GroundWestNorth", Rect2(-margin, 0, margin, trench.position.y))
	_ground_slab(site, "GroundWestSouth", Rect2(
		-margin, trench.end.y, margin, depth - trench.end.y
	))
	_ground_slab(site, "GroundWestFar", Rect2(
		-margin, trench.position.y, -margin - TRENCH_FAR_X, trench.size.y
	))

	_build_cellar_culvert(_container(site, "CellarCulvert"), trench)
	_build_west_terrace(_container(site, "WestTerrace"))


## Entrance 05 is on the basement's west wall, and the basement only reaches
## column 19 - so its "outdoor" door actually opens under the west wing. The
## coal chute therefore runs west as a service culvert and surfaces in the
## garden, which is also what keeps E05 the 30-42 s outlier section 4 wants.
func _trench_rect() -> Rect2:
	var cells: Array = []
	for entrance: Dictionary in spec.entrances():
		if String(entrance["id"]) == "E05":
			cells = entrance["cells"]
	if cells.is_empty():
		return Rect2(TRENCH_FAR_X, 34.0, 38.0 - TRENCH_FAR_X, 4.0)
	var rows: Array[int] = []
	var face_col := VillaSpec.to_cell(cells[0]).x
	for cell_pair: Variant in cells:
		rows.append(VillaSpec.to_cell(cell_pair).y)
	rows.sort()
	var z0 := rows[0] * spec.cell_size
	var z1 := (rows[-1] + 1) * spec.cell_size
	return Rect2(TRENCH_FAR_X, z0, face_col * spec.cell_size - TRENCH_FAR_X, z1 - z0)


func _build_cellar_culvert(parent: Node3D, trench: Rect2) -> void:
	var floor_y := -spec.floor_height
	var centre := trench.get_center()
	var ramp_foot := TRENCH_FAR_X + spec.floor_height

	_static_box(
		parent, "CulvertFloor",
		Vector3(
			(ramp_foot + trench.end.x) * 0.5, floor_y - SLAB_THICKNESS * 0.5, centre.y
		),
		Vector3(trench.end.x - ramp_foot, SLAB_THICKNESS, trench.size.y),
		_ground_material, true
	)
	for side: float in [-1.0, 1.0]:
		_static_box(
			parent, "CulvertRetaining",
			Vector3(
				centre.x,
				floor_y + spec.floor_height * 0.5,
				centre.y + side * (trench.size.y * 0.5 + 0.25)
			),
			Vector3(trench.size.x, spec.floor_height, 0.5),
			_ground_material, true
		)
	# Roofed only where it passes beneath the house; west of the facade it is
	# an open trench, so the moon still reaches the cellar door.
	_static_box(
		parent, "CulvertRoof",
		Vector3(trench.end.x * 0.5, -SLAB_THICKNESS * 0.5, centre.y),
		Vector3(trench.end.x, SLAB_THICKNESS, trench.size.y),
		_ceiling_material, true
	)
	_exterior_ramp(
		parent, "CulvertStair",
		Vector3(ramp_foot, floor_y, centre.y),
		Vector3(-1, 0, 0), spec.floor_height, 3.0
	)


## Entrance 06 opens onto a porch roof and entrance 07 onto the main roof deck.
## Both need a route down to the garden, or whatever comes through them has
## nowhere to have come from.
func _build_west_terrace(parent: Node3D) -> void:
	var depth := spec.grid_height * spec.cell_size
	var porch_y := spec.floor_height
	# The porch starts north of the stair head: a roof over the run would take
	# the headroom Recast needs to bake the ramp at all.
	var porch_z0 := 18.0
	var porch_z1 := depth - 6.0
	_static_box(
		parent, "PorchRoof",
		Vector3(-2.5, porch_y - SLAB_THICKNESS * 0.5, (porch_z0 + porch_z1) * 0.5),
		Vector3(5.0, SLAB_THICKNESS, porch_z1 - porch_z0),
		_ceiling_material, true
	)
	_exterior_ramp(
		parent, "PorchStair",
		Vector3(-2.5, 0.0, porch_z0 - porch_y), Vector3(0, 0, 1), porch_y, 2.0
	)
	# Climbs eastward so it lands on the roof deck rather than beside it.
	_exterior_ramp(
		parent, "RoofStair",
		Vector3(-spec.floor_height, porch_y, 30.0), Vector3(1, 0, 0),
		spec.floor_height, 2.0
	)


func _exterior_ramp(
	parent: Node3D,
	ramp_name: String,
	base: Vector3,
	uphill: Vector3,
	rise: float,
	width: float
) -> void:
	_add_ramp(parent, ramp_name, base, uphill, rise, width)


func _ground_slab(parent: Node3D, slab_name: String, area: Rect2) -> void:
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	_static_box(
		parent, slab_name,
		Vector3(area.get_center().x, -0.2, area.get_center().y),
		Vector3(area.size.x, 0.4, area.size.y),
		_ground_material, true
	)


# --- primitives --------------------------------------------------------------

## Optimized builds greedily merge adjacent cells. Editable builds intentionally
## keep one collider per cell so moving a visible module never leaves a large,
## invisible collider behind at its old position.
func _architecture_rects(cells: Dictionary) -> Array[Rect2i]:
	if authoring_granularity == AuthoringGranularity.OPTIMIZED:
		return VillaSpec.decompose_rects(cells)
	var rects: Array[Rect2i] = []
	for cell: Vector2i in cells:
		rects.append(Rect2i(cell, Vector2i.ONE))
	return rects

func _shaft_cells(level: int) -> Dictionary:
	var cells: Dictionary = {}
	for link: Dictionary in spec.vertical_links():
		if String(link["type"]) != "shaft" or int(link["to"]) != level:
			continue
		_mark(cells, VillaSpec.to_rect(link["rect"]))
	return cells


static func _mark(cells: Dictionary, rect: Rect2i) -> void:
	for col: int in range(rect.position.x, rect.position.x + rect.size.x):
		for row: int in range(rect.position.y, rect.position.y + rect.size.y):
			cells[Vector2i(col, row)] = true


## The cell immediately outside a wall run, used to ask what the run faces.
static func _run_neighbour(run: Dictionary) -> Vector2i:
	var direction: Vector2i = run["dir"]
	var fixed: int = run["fixed"]
	var value: int = run["from"]
	var cell := (
		Vector2i(fixed, value) if direction.x != 0 else Vector2i(value, fixed)
	)
	return cell + direction


## Mid-point of a run's boundary plane, at the level's floor height.
func _run_plane(run: Dictionary) -> Vector3:
	var direction: Vector2i = run["dir"]
	var fixed: int = run["fixed"]
	var from: int = run["from"]
	var to: int = run["to"]
	var centre_along := (from + to + 1) * 0.5 * spec.cell_size
	# The face sits on the far edge of the walkable cell in `dir`.
	var face := (fixed + (1 if direction.x > 0 or direction.y > 0 else 0)) * spec.cell_size
	if direction.x != 0:
		return Vector3(face, 0.0, centre_along)
	return Vector3(centre_along, 0.0, face)


func _static_box(
	parent: Node3D,
	body_name: String,
	centre: Vector3,
	size: Vector3,
	material: Material,
	with_mesh: bool
) -> StaticBody3D:
	var body := StaticBody3D.new()
	_module_index += 1
	body.name = "%s_%04d" % [body_name, _module_index]
	body.position = centre
	parent.add_child(body)

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)

	if with_mesh:
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = material
		var instance := MeshInstance3D.new()
		instance.name = "Mesh"
		instance.mesh = mesh
		body.add_child(instance)
	return body


func _asset(
	scene: PackedScene,
	parent: Node3D,
	asset_name: String,
	position: Vector3,
	rotation_y: float = 0.0,
	scale_value: Vector3 = Vector3.ONE
) -> Node3D:
	var instance := scene.instantiate() as Node3D
	_module_index += 1
	instance.name = "%s_%04d" % [asset_name, _module_index]
	# Assets hang off collider bodies, so undo the parent's world offset.
	instance.position = position - _world_offset(parent)
	instance.rotation.y = rotation_y
	instance.scale = scale_value
	instance.set_meta("source_asset", scene.resource_path)
	instance.add_to_group("modular_house_asset")
	instance.add_to_group("villa_house_asset")
	parent.add_child(instance)
	return instance


func _world_offset(node: Node3D) -> Vector3:
	var offset := Vector3.ZERO
	var current := node
	while current and current != self:
		offset += current.position
		current = current.get_parent() as Node3D
	return offset


## Furniture is picked by name from data tables, so it is loaded on demand
## rather than through fifty preload constants. The loader caches, and so does
## this, to keep the per-room lookups off the resource server.
func _furniture(item: String) -> PackedScene:
	if not _furniture_cache.has(item):
		_furniture_cache[item] = load(FURNITURE_ROOT + item + ".fbx") as PackedScene
	return _furniture_cache[item]


func _container(parent: Node3D, container_name: String) -> Node3D:
	var container := Node3D.new()
	container.name = container_name
	parent.add_child(container)
	return container


func _add_light(
	parent: Node3D,
	light_name: String,
	position: Vector3,
	color: Color,
	energy: float,
	range_value: float,
	shadows := false
) -> void:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.omni_attenuation = 1.35
	light.shadow_enabled = shadows
	light.add_to_group("flickering_house_lights")
	parent.add_child(light)


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

@tool
class_name House2
extends Node3D

## Runtime/editor builder for the second house layout.  The architecture is
## assembled from Elegant Crow's Retro Modular House kit in assets/map.

const ASSET_ROOT := "res://assets/map/retro_modular_house/retro_modular_house/models/"
const FURNITURE_ROOT := "res://assets/map/Furniture/FBX/Separated/"

const FLOOR_2X2: PackedScene = preload(ASSET_ROOT + "floors/floor_2x2.fbx")
const FLOOR_4X4: PackedScene = preload(ASSET_ROOT + "floors/floor_4x4.fbx")
const FOUNDATION_PILLAR: PackedScene = preload(
	ASSET_ROOT + "floors/foundation/foundation_pillar.fbx"
)
const WALL_3X1: PackedScene = preload(ASSET_ROOT + "walls/wall_3x1.fbx")
const DOOR_FRAME: PackedScene = preload(
	ASSET_ROOT + "doors/single_doors/door_single_frame.fbx"
)
const GARAGE_DOOR: PackedScene = preload(
	ASSET_ROOT + "doors/double_doors/door_double_blocked.fbx"
)
const WINDOW: PackedScene = preload(
	ASSET_ROOT + "windows/single_windows/window_single_01.fbx"
)
const BLOCKED_WINDOW: PackedScene = preload(
	ASSET_ROOT + "windows/single_windows/window_single_blocked.fbx"
)
const BIG_STAIR: PackedScene = preload(ASSET_ROOT + "misc/stairs/stair_big_01.fbx")
const LOOSE_PLANK_A: PackedScene = preload(
	ASSET_ROOT + "misc/loose_planks/plank_loose_01.fbx"
)
const LOOSE_PLANK_B: PackedScene = preload(
	ASSET_ROOT + "misc/loose_planks/plank_loose_03.fbx"
)
const BALCONY_RAIL: PackedScene = preload(ASSET_ROOT + "railings/railing_balcony_01.fbx")
const ROOF_LEFT_END: PackedScene = preload(ASSET_ROOT + "roofs/roof_01/roof_01_L.fbx")
const ROOF_MIDDLE: PackedScene = preload(ASSET_ROOT + "roofs/roof_01/roof_01_middle.fbx")
const ROOF_RIGHT_END: PackedScene = preload(ASSET_ROOT + "roofs/roof_01/roof_01_R.fbx")

const FURNITURE_BED_BASE: PackedScene = preload(FURNITURE_ROOT + "Bed Base 1 1.fbx")
const FURNITURE_BED_SHEETS: PackedScene = preload(FURNITURE_ROOT + "Bed 1 Sheets.fbx")
const FURNITURE_SOFA: PackedScene = preload(FURNITURE_ROOT + "Sofa 1.fbx")
const FURNITURE_COFFEE_TABLE: PackedScene = preload(FURNITURE_ROOT + "Coffee Table.fbx")
const FURNITURE_DINING_TABLE: PackedScene = preload(FURNITURE_ROOT + "Dining Table.fbx")
const FURNITURE_CHAIR: PackedScene = preload(FURNITURE_ROOT + "Chair.fbx")
const FURNITURE_BATHTUB: PackedScene = preload(FURNITURE_ROOT + "Bathtub.fbx")
const FURNITURE_TOILET: PackedScene = preload(FURNITURE_ROOT + "Toilet.fbx")
const FURNITURE_FRIDGE: PackedScene = preload(FURNITURE_ROOT + "Fridge.fbx")
const FURNITURE_OVEN: PackedScene = preload(FURNITURE_ROOT + "Oven.fbx")
const FURNITURE_COUNTER: PackedScene = preload(FURNITURE_ROOT + "Counter Connected.fbx")
const FURNITURE_COUNTER_SINK: PackedScene = preload(
	FURNITURE_ROOT + "Counter Connected - Sink.fbx"
)
const FURNITURE_SHELVES: PackedScene = preload(FURNITURE_ROOT + "Modern Shelves.fbx")
const FURNITURE_BOX: PackedScene = preload(FURNITURE_ROOT + "Box.fbx")
const FURNITURE_BED_TABLE: PackedScene = preload(FURNITURE_ROOT + "Bed Table.fbx")
const FURNITURE_WARDROBE: PackedScene = preload(FURNITURE_ROOT + "Wardrobe.fbx")
const FURNITURE_TV: PackedScene = preload(FURNITURE_ROOT + "TV 1.fbx")
const FURNITURE_LOUNGE_CHAIR: PackedScene = preload(FURNITURE_ROOT + "Chair 2.fbx")
const FURNITURE_WASHER: PackedScene = preload(FURNITURE_ROOT + "Washing Machine.fbx")
const FURNITURE_SINK: PackedScene = preload(FURNITURE_ROOT + "Sink.fbx")
const FURNITURE_MIRROR: PackedScene = preload(FURNITURE_ROOT + "Mirror 2.fbx")
const FURNITURE_LADDER: PackedScene = preload(FURNITURE_ROOT + "Ladder 2.fbx")
const FURNITURE_RADIO: PackedScene = preload(FURNITURE_ROOT + "Radio.fbx")
const FURNITURE_TIRE: PackedScene = preload(FURNITURE_ROOT + "Tire.fbx")
const FURNITURE_TABLE_LAMP: PackedScene = preload(FURNITURE_ROOT + "Table Lamp 1.fbx")
const FURNITURE_CEILING_LAMP: PackedScene = preload(FURNITURE_ROOT + "Ceiling Lamp 2.fbx")

const LIGHT_SOURCE: PackedScene = preload("res://props/light_source.tscn")

const HOUSE_X_MIN := -9.0
const HOUSE_X_MAX := 9.0
const HOUSE_Z_MIN := -6.0
const HOUSE_Z_MAX := 6.0
const FLOOR_HEIGHT := 3.0

@export var editor_preview: bool = true

var _module_index := 0


func _ready() -> void:
	if Engine.is_editor_hint() and not editor_preview:
		return
	if has_node("Generated"):
		return
	_build_house()


func _build_house() -> void:
	var generated := _add_container(self, "Generated")
	generated.add_to_group("house2_geometry")

	var site := _add_container(generated, "Site")
	var basement := _add_level(generated, "Basement", -FLOOR_HEIGHT)
	var ground := _add_level(generated, "GroundFloor", 0.0)
	var upper := _add_level(generated, "SecondFloor", FLOOR_HEIGHT)
	var attic := _add_level(generated, "Attic", FLOOR_HEIGHT * 2.0)

	_build_site(site)
	_build_basement(basement)
	_build_ground_floor(ground)
	_build_second_floor(upper)
	_build_attic(attic)
	_build_roof(generated)
	_build_room_props(basement, ground, upper, attic)
	_build_lighting(generated)


func _add_level(parent: Node3D, level_name: String, elevation: float) -> Node3D:
	var level := _add_container(parent, level_name)
	level.set_meta("elevation", elevation)
	return level


func _build_site(site: Node3D) -> void:
	var ground_material := _material(Color(0.075, 0.09, 0.075), 0.97)
	# Four broad slabs surround the footprint.  The east edge is split around
	# the cellar areaway so entrance 06 is physically reachable below grade.
	_add_box(site, "BackGround", Vector3(0, -0.2, -18), Vector3(60, 0.35, 24), ground_material)
	_add_box(site, "FrontGround", Vector3(0, -0.2, 18), Vector3(60, 0.35, 24), ground_material)
	_add_box(site, "WestGround", Vector3(-19.5, -0.2, 0), Vector3(21, 0.35, 12), ground_material)
	_add_box(site, "EastGround", Vector3(21.5, -0.2, 0), Vector3(17, 0.35, 12), ground_material)
	_add_box(site, "EastGroundBack", Vector3(11, -0.2, -4), Vector3(4, 0.35, 4), ground_material)
	_add_box(site, "EastGroundFront", Vector3(11, -0.2, 4), Vector3(4, 0.35, 4), ground_material)

	# Sunken cellar exit and a real 3 m stair back to the garden.
	_add_floor_grid(site, -FLOOR_HEIGHT, Rect2(9, -2, 4, 4))
	_add_stair(site, "CellarExteriorStair", Vector3(11, -FLOOR_HEIGHT, 0), 0.0)
	_add_wall_x(site, -2.0, -FLOOR_HEIGHT, 9.0, 13.0, [], "CellarRetainingBack")
	_add_wall_x(site, 2.0, -FLOOR_HEIGHT, 9.0, 13.0, [], "CellarRetainingFront")

	# Front path and the ground-floor patio attached to entrance 03.
	_add_floor_grid(site, 0.0, Rect2(-1, 6, 2, 6))
	_add_floor_grid(site, 0.0, Rect2(4, -10, 4, 4))


func _build_basement(level: Node3D) -> void:
	var architecture := _add_container(level, "Architecture")
	_add_floor_grid(architecture, -FLOOR_HEIGHT, Rect2(HOUSE_X_MIN, HOUSE_Z_MIN, 18, 12))

	_add_wall_x(architecture, HOUSE_Z_MIN, -FLOOR_HEIGHT, HOUSE_X_MIN, HOUSE_X_MAX, [], "BackWall")
	_add_wall_x(architecture, HOUSE_Z_MAX, -FLOOR_HEIGHT, HOUSE_X_MIN, HOUSE_X_MAX, [], "FrontWall")
	_add_wall_z(architecture, HOUSE_X_MIN, -FLOOR_HEIGHT, HOUSE_Z_MIN, HOUSE_Z_MAX, [], "WestWall")
	_add_wall_z(
		architecture,
		HOUSE_X_MAX,
		-FLOOR_HEIGHT,
		HOUSE_Z_MIN,
		HOUSE_Z_MAX,
		[Vector2(0, 3)],
		"EastWall"
	)

	_add_stair(
		architecture,
		"StairBasementToGround",
		Vector3(-8, -FLOOR_HEIGHT, 2.75),
		-PI * 0.5
	)
	# Continue the ground-floor enclosure down into the basement. The stair now
	# runs against the west foundation wall and exits cleanly at its lower end.
	_add_wall_z(
		architecture, -7.0, -FLOOR_HEIGHT, 0.0, 4.0, [],
		"BasementStairwellWall"
	)
	for x: float in [-8.0, 8.0]:
		for z: float in [-5.0, 5.0]:
			_add_asset(FOUNDATION_PILLAR, architecture, "FoundationPillar", Vector3(x, -FLOOR_HEIGHT, z))

	_add_room(level, "BoilerAndStorage", Vector3(0, -FLOOR_HEIGHT, 0), Vector3(18, 3, 12))


func _build_ground_floor(level: Node3D) -> void:
	var architecture := _add_container(level, "Architecture")
	_add_floor_grid(
		architecture,
		0.0,
		Rect2(HOUSE_X_MIN, HOUSE_Z_MIN, 18, 12),
		[Rect2(-9, 0, 2, 6)]
	)
	# A half-metre of extra head/foot clearance lets the capsule transfer from
	# the ramp onto the landing without catching the vertical floor-tile edge.
	_add_asset(
		FLOOR_2X2, architecture, "BasementStairLanding",
		Vector3(-8, 0, 5.25), 0.0, Vector3(1, 1, 0.75)
	)
	# A full-height inner wall turns the run into a believable stairwell along
	# the garage exterior wall. It stops before the upper landing, which opens
	# laterally into Garage instead of pointing at another room.
	_add_wall_z(
		architecture, -7.0, 0.0, 0.0, 4.0, [],
		"GarageStairwellWall"
	)
	_add_asset(
		DOOR_FRAME,
		architecture,
		"GarageStairwellDoorFrame",
		Vector3(-8.0, 0.0, 4.45)
	)

	# Exterior shell.  Gaps are entrance, window, or garage modules.
	_add_wall_x(
		architecture, HOUSE_Z_MAX, 0.0, HOUSE_X_MIN, HOUSE_X_MAX,
		[Vector2(-6, 3), Vector2(0, 3), Vector2(6, 2)], "FrontWall"
	)
	_add_asset(GARAGE_DOOR, architecture, "SealedGarageDoor", Vector3(-6, 0, HOUSE_Z_MAX), PI)
	_add_asset(WINDOW, architecture, "StorageFrontWindow", Vector3(6, 0, HOUSE_Z_MAX), PI)

	_add_wall_x(
		architecture, HOUSE_Z_MIN, 0.0, HOUSE_X_MIN, HOUSE_X_MAX,
		[Vector2(0, 2), Vector2(6, 3)], "BackWall"
	)
	_add_asset(WINDOW, architecture, "LivingBackWindow", Vector3(0, 0, HOUSE_Z_MIN))

	_add_wall_z(
		architecture, HOUSE_X_MIN, 0.0, HOUSE_Z_MIN, HOUSE_Z_MAX,
		[Vector2(-3, 3), Vector2(3, 2)], "WestWall"
	)
	_add_asset(WINDOW, architecture, "GarageSideWindow", Vector3(HOUSE_X_MIN, 0, 3), PI * 0.5)

	_add_wall_z(
		architecture, HOUSE_X_MAX, 0.0, HOUSE_Z_MIN, HOUSE_Z_MAX,
		[Vector2(-3, 2), Vector2(3, 2)], "EastWall"
	)
	_add_asset(WINDOW, architecture, "DiningSideWindow", Vector3(HOUSE_X_MAX, 0, -3), -PI * 0.5)
	_add_asset(BLOCKED_WINDOW, architecture, "StorageSideWindow", Vector3(HOUSE_X_MAX, 0, 3), -PI * 0.5)

	# The garage/basement stairwell must terminate against a proper wall, not
	# continue straight through into the kitchen and entrance #2. Kitchen is
	# reached naturally through Living; Garage connects through Main Hall.
	_add_partition_x(architecture, 0.0, 0.0, [Vector2(0, 2), Vector2(6, 2)], "MiddlePartition")
	_add_partition_z(architecture, -3.0, 0.0, [Vector2(-3, 2), Vector2(3, 2)], "WestPartition")
	_add_partition_z(architecture, 3.0, 0.0, [Vector2(-3, 2), Vector2(3, 2)], "EastPartition")

	_add_stair(
		architecture,
		"StairGroundToSecond",
		Vector3(0, 0, 2.75),
		-PI * 0.5
	)

	_add_room(level, "Kitchen", Vector3(-6, 0, -3), Vector3(6, 3, 6))
	_add_room(level, "LivingRoom", Vector3(0, 0, -3), Vector3(6, 3, 6))
	_add_room(level, "DiningRoom", Vector3(6, 0, -3), Vector3(6, 3, 6))
	_add_room(level, "Garage", Vector3(-6, 0, 3), Vector3(6, 3, 6))
	_add_room(level, "MainHall", Vector3(0, 0, 3), Vector3(6, 3, 6))
	_add_room(level, "Storage", Vector3(6, 0, 3), Vector3(6, 3, 6))


func _build_second_floor(level: Node3D) -> void:
	var architecture := _add_container(level, "Architecture")
	_add_floor_grid(
		architecture,
		FLOOR_HEIGHT,
		Rect2(HOUSE_X_MIN, HOUSE_Z_MIN, 18, 12),
		[Rect2(-1, 0, 2, 6)]
	)
	_add_asset(
		FLOOR_2X2, architecture, "GroundStairLanding",
		Vector3(0, FLOOR_HEIGHT, 5.25), 0.0, Vector3(1, 1, 0.75)
	)

	_add_wall_x(
		architecture, HOUSE_Z_MIN, FLOOR_HEIGHT, HOUSE_X_MIN, HOUSE_X_MAX,
		[Vector2(-6, 3), Vector2(1.5, 2)], "BackWall"
	)
	_add_asset(WINDOW, architecture, "BedroomBackWindow", Vector3(1.5, FLOOR_HEIGHT, HOUSE_Z_MIN))

	_add_wall_x(
		architecture, HOUSE_Z_MAX, FLOOR_HEIGHT, HOUSE_X_MIN, HOUSE_X_MAX,
		[Vector2(-6, 2), Vector2(0, 2), Vector2(6, 2)], "FrontWall"
	)
	_add_asset(WINDOW, architecture, "HallFrontWindowWest", Vector3(-6, FLOOR_HEIGHT, HOUSE_Z_MAX), PI)
	_add_asset(WINDOW, architecture, "HallFrontWindow", Vector3(0, FLOOR_HEIGHT, HOUSE_Z_MAX), PI)
	_add_asset(WINDOW, architecture, "BathFrontWindow", Vector3(6, FLOOR_HEIGHT, HOUSE_Z_MAX), PI)

	_add_wall_z(
		architecture, HOUSE_X_MIN, FLOOR_HEIGHT, HOUSE_Z_MIN, HOUSE_Z_MAX,
		[Vector2(-3, 2), Vector2(3, 2)], "WestWall"
	)
	_add_asset(WINDOW, architecture, "BedroomWestWindow", Vector3(HOUSE_X_MIN, FLOOR_HEIGHT, -3), PI * 0.5)
	_add_asset(WINDOW, architecture, "HallWestWindow", Vector3(HOUSE_X_MIN, FLOOR_HEIGHT, 3), PI * 0.5)

	_add_wall_z(
		architecture, HOUSE_X_MAX, FLOOR_HEIGHT, HOUSE_Z_MIN, HOUSE_Z_MAX,
		[Vector2(-3, 3), Vector2(3, 2)], "EastWall"
	)
	_add_asset(WINDOW, architecture, "BathEastWindow", Vector3(HOUSE_X_MAX, FLOOR_HEIGHT, 3), -PI * 0.5)

	# Bedroom row over a large front hall/stair landing, with the bath at east.
	_add_partition_x(architecture, 0.0, FLOOR_HEIGHT, [Vector2(-5, 2), Vector2(4, 2)], "BedroomHallPartition")
	_add_wall_z(architecture, 0.0, FLOOR_HEIGHT, HOUSE_Z_MIN, 0.0, [], "BedroomDivider")
	_add_wall_z(architecture, 3.0, FLOOR_HEIGHT, 0.0, HOUSE_Z_MAX, [Vector2(3, 2)], "BathDivider")

	_add_stair(
		architecture,
		"StairSecondToAttic",
		Vector3(-4, FLOOR_HEIGHT, 2.75),
		-PI * 0.5
	)

	_add_room(level, "BedroomWest", Vector3(-4.5, FLOOR_HEIGHT, -3), Vector3(9, 3, 6))
	_add_room(level, "BedroomEast", Vector3(4.5, FLOOR_HEIGHT, -3), Vector3(9, 3, 6))
	_add_room(level, "HallAndStairs", Vector3(-3, FLOOR_HEIGHT, 3), Vector3(12, 3, 6))
	_add_room(level, "Bathroom", Vector3(6, FLOOR_HEIGHT, 3), Vector3(6, 3, 6))

	_build_back_balcony(architecture, "BedroomBalcony", -6.0, FLOOR_HEIGHT, HOUSE_Z_MIN)
	_build_side_balcony(architecture, "EastBedroomBalcony", -3.0, FLOOR_HEIGHT)


func _build_attic(level: Node3D) -> void:
	var architecture := _add_container(level, "Architecture")
	_add_floor_grid(
		architecture,
		FLOOR_HEIGHT * 2.0,
		Rect2(HOUSE_X_MIN, HOUSE_Z_MIN, 18, 12),
		[Rect2(-5, 0, 2, 6)]
	)
	_add_asset(
		FLOOR_2X2, architecture, "SecondStairLanding",
		Vector3(-4, FLOOR_HEIGHT * 2.0, 5.25), 0.0, Vector3(1, 1, 0.75)
	)
	_add_wall_x(
		architecture,
		HOUSE_Z_MIN,
		FLOOR_HEIGHT * 2.0,
		HOUSE_X_MIN,
		HOUSE_X_MAX,
		[Vector2(0, 3)],
		"BackWall"
	)
	_add_wall_x(
		architecture,
		HOUSE_Z_MAX,
		FLOOR_HEIGHT * 2.0,
		HOUSE_X_MIN,
		HOUSE_X_MAX,
		[Vector2(0, 2)],
		"FrontWall"
	)
	_add_wall_z(
		architecture,
		HOUSE_X_MIN,
		FLOOR_HEIGHT * 2.0,
		HOUSE_Z_MIN,
		HOUSE_Z_MAX,
		[],
		"WestWall"
	)
	_add_wall_z(
		architecture,
		HOUSE_X_MAX,
		FLOOR_HEIGHT * 2.0,
		HOUSE_Z_MIN,
		HOUSE_Z_MAX,
		[],
		"EastWall"
	)
	_add_asset(
		WINDOW,
		architecture,
		"AtticFrontWindow",
		Vector3(0, FLOOR_HEIGHT * 2.0, HOUSE_Z_MAX),
		PI
	)
	_add_room(level, "AtticStorage", Vector3(0, FLOOR_HEIGHT * 2.0, 0), Vector3(18, 3, 12))
	_build_back_balcony(
		architecture,
		"RoofEntryDeck",
		0.0,
		FLOOR_HEIGHT * 2.0,
		HOUSE_Z_MIN
	)


func _build_roof(parent: Node3D) -> void:
	var roof := _add_container(parent, "Roof")
	# One textured roof strip per metre of attic depth.  Mirroring the same
	# modular slope gives a closed ridge while preserving the kit's material.
	for index: int in 12:
		var roof_scene := ROOF_MIDDLE
		if index == 0:
			roof_scene = ROOF_LEFT_END
		elif index == 11:
			roof_scene = ROOF_RIGHT_END
		var z := -5.5 + index
		_add_asset(
			roof_scene,
			roof,
			"RoofSlopeWest",
			Vector3(-3.6, 9.5, z),
			0.0,
			Vector3(3.6, 1, 1)
		)
		_add_asset(
			roof_scene,
			roof,
			"RoofSlopeEast",
			Vector3(3.6, 9.5, z),
			0.0,
			Vector3(-3.6, 1, 1)
		)


func _build_room_props(basement: Node3D, ground: Node3D, upper: Node3D, attic: Node3D) -> void:
	var dark_wood := _material(Color(0.095, 0.05, 0.028), 0.9)
	var metal := _material(Color(0.14, 0.16, 0.17), 0.46, 0.58)

	var basement_props := _add_container(basement, "Props")
	_add_cylinder(basement_props, "Boiler", Vector3(5.8, -1.8, -3.7), 0.72, 2.3, metal)
	_add_box(basement_props, "BoilerBase", Vector3(5.8, -2.85, -3.7), Vector3(1.8, 0.25, 1.8), metal)
	for index: int in 4:
		_add_asset(
			FURNITURE_BOX,
			basement_props,
			"StorageCrate",
			Vector3(-7.7 + (index % 2) * 0.8, -3.0 + (index / 2) * 0.66, -4.6),
			0.08 * index
		)
	_add_asset(FURNITURE_SHELVES, basement_props, "BasementShelvesA", Vector3(7.7, -3.0, 3.7), -PI * 0.5)
	_add_asset(FURNITURE_SHELVES, basement_props, "BasementShelvesB", Vector3(7.7, -3.0, 1.9), -PI * 0.5)
	for position: Vector3 in [
		Vector3(-8.0, -3.0, 4.6),
		Vector3(-7.2, -3.0, 4.6),
		Vector3(3.2, -3.0, -5.0),
	]:
		_add_asset(FURNITURE_BOX, basement_props, "StorageCrate", position)
	_add_asset(LOOSE_PLANK_A, basement_props, "LoosePlanks", Vector3(2.8, -2.85, 4.8), -0.18)

	var ground_props := _add_container(ground, "Props")
	# Keep the whole counter run on the back wall. The old side counter/sink sat
	# directly in entrance #2's approach corridor on the west kitchen wall.
	_add_asset(FURNITURE_COUNTER, ground_props, "KitchenCounterA", Vector3(-7.7, 0, -5.4))
	_add_asset(FURNITURE_COUNTER_SINK, ground_props, "KitchenSink", Vector3(-6.65, 0, -5.4))
	_add_asset(FURNITURE_COUNTER, ground_props, "KitchenCounterB", Vector3(-5.6, 0, -5.4))
	_add_asset(FURNITURE_FRIDGE, ground_props, "KitchenFridge", Vector3(-3.55, 0, -1.1), -PI * 0.5)
	_add_asset(FURNITURE_OVEN, ground_props, "KitchenOven", Vector3(-4.0, 0, -5.35))
	_add_asset(FURNITURE_SOFA, ground_props, "LivingSofa", Vector3(-0.8, 0, -4.7))
	_add_asset(FURNITURE_COFFEE_TABLE, ground_props, "CoffeeTable", Vector3(0, 0, -2.8))
	# The centre of this wall is the Living Room -> Main Hall doorway. Keep the
	# TV grouping on the solid wall section instead of disguising the door.
	_add_asset(FURNITURE_BED_TABLE, ground_props, "LivingTVStand", Vector3(1.8, 0, -0.48), PI)
	_add_asset(FURNITURE_TV, ground_props, "LivingTV", Vector3(1.8, 1.0, -0.24), PI)
	_add_asset(FURNITURE_LOUNGE_CHAIR, ground_props, "LivingChair", Vector3(1.7, 0, -5.05), -0.25)
	_add_asset(FURNITURE_DINING_TABLE, ground_props, "DiningTable", Vector3(6.3, 0, -3))
	for chair_data: Vector3 in [
		Vector3(4.75, -3, -PI * 0.5),
		Vector3(7.85, -3, PI * 0.5),
		Vector3(6.3, -4.25, 0),
		Vector3(6.3, -1.75, PI),
	]:
		_add_asset(
			FURNITURE_CHAIR,
			ground_props,
			"DiningChair",
			Vector3(chair_data.x, 0, chair_data.y),
			chair_data.z
		)
	_add_box(ground_props, "GarageWorkbench", Vector3(-5.0, 0.75, 0.45), Vector3(2.4, 1.5, 0.65), dark_wood)
	# Keep the narrow bridge beside the stairwell open; this machine previously
	# sealed the only capsule-width route from the garage landing to the hall.
	_add_asset(FURNITURE_WASHER, ground_props, "GarageWasher", Vector3(-3.75, 0, 5.15), PI)
	for position: Vector3 in [
		Vector3(-5.2, 0.12, 5.1),
		Vector3(-5.2, 0.35, 5.1),
		Vector3(-6.0, 0.12, 5.15),
	]:
		_add_asset(FURNITURE_TIRE, ground_props, "GarageTire", position)
	_add_asset(FURNITURE_SHELVES, ground_props, "StorageShelvesA", Vector3(7.8, 0, 4.8))
	_add_asset(FURNITURE_SHELVES, ground_props, "StorageShelvesB", Vector3(4.3, 0, 4.8))
	_add_asset(FURNITURE_SHELVES, ground_props, "StorageShelvesC", Vector3(8.65, 0, 2.0), PI * 0.5)
	for position: Vector3 in [Vector3(5.2, 0, 1.85), Vector3(6.8, 0, 1.85), Vector3(7.7, 0, 1.85)]:
		_add_asset(FURNITURE_BOX, ground_props, "StorageBox", position)
	_add_asset(FURNITURE_BED_TABLE, ground_props, "HallConsole", Vector3(2.35, 0, 5.35), PI)
	_add_asset(FURNITURE_TABLE_LAMP, ground_props, "HallTableLamp", Vector3(2.35, 0.98, 5.35), PI)

	var upper_props := _add_container(upper, "Props")
	_add_furniture_bed(upper_props, "WestBed", Vector3(-2.1, FLOOR_HEIGHT, -4.15))
	_add_asset(FURNITURE_BED_TABLE, upper_props, "WestBedTableA", Vector3(-3.2, FLOOR_HEIGHT, -4.2))
	_add_asset(FURNITURE_BED_TABLE, upper_props, "WestBedTableB", Vector3(-1.05, FLOOR_HEIGHT, -4.2))
	_add_asset(FURNITURE_WARDROBE, upper_props, "WestWardrobe", Vector3(-8.65, FLOOR_HEIGHT, -1.5), PI * 0.5)
	_add_asset(FURNITURE_LOUNGE_CHAIR, upper_props, "WestReadingChair", Vector3(-7.6, FLOOR_HEIGHT, -3.5), 0.35)
	_add_asset(FURNITURE_BED_TABLE, upper_props, "WestLowCabinet", Vector3(-7.2, FLOOR_HEIGHT, -0.45), PI)
	_add_furniture_bed(upper_props, "EastBed", Vector3(5.2, FLOOR_HEIGHT, -4.2))
	_add_asset(FURNITURE_BED_TABLE, upper_props, "EastBedTableA", Vector3(4.15, FLOOR_HEIGHT, -4.2))
	_add_asset(FURNITURE_BED_TABLE, upper_props, "EastBedTableB", Vector3(6.25, FLOOR_HEIGHT, -4.2))
	_add_asset(FURNITURE_WARDROBE, upper_props, "EastWardrobe", Vector3(8.65, FLOOR_HEIGHT, -0.9), -PI * 0.5)
	_add_asset(FURNITURE_LOUNGE_CHAIR, upper_props, "EastReadingChair", Vector3(7.25, FLOOR_HEIGHT, -2.7), -0.7)
	_add_asset(FURNITURE_BED_TABLE, upper_props, "EastTVStand", Vector3(7.0, FLOOR_HEIGHT, -0.45), PI)
	_add_asset(FURNITURE_TV, upper_props, "EastBedroomTV", Vector3(7.0, FLOOR_HEIGHT + 0.98, -0.28), PI)
	_add_asset(FURNITURE_BATHTUB, upper_props, "BathTub", Vector3(7.4, FLOOR_HEIGHT, 4.4), PI * 0.5)
	# Keep the bathroom's door-to-tub aisle open. The toilet used to sit around
	# the middle of that approach; tuck its cistern against the south wall and
	# turn the bowl into the room like a normal fixture.
	_add_asset(FURNITURE_TOILET, upper_props, "Toilet", Vector3(5.1, FLOOR_HEIGHT, 0.65), PI)
	_add_asset(FURNITURE_SINK, upper_props, "BathroomSink", Vector3(5.2, FLOOR_HEIGHT, 5.5))
	_add_asset(FURNITURE_MIRROR, upper_props, "BathroomMirror", Vector3(5.2, FLOOR_HEIGHT + 1.5, 5.88))
	_add_asset(FURNITURE_WASHER, upper_props, "BathroomWasher", Vector3(8.1, FLOOR_HEIGHT, 1.2), PI)
	# Keep the stair-head turn clear for full-size navigation capsules. This
	# console used to begin only 24 cm from the stair opening after accounting
	# for its real mesh bounds, so the Huntsman could climb successfully and then
	# fall back into the well while trying to squeeze between it and the rail.
	# Tuck the whole grouping into the front/bathroom-wall corner instead.
	_add_asset(
		FURNITURE_BED_TABLE,
		upper_props,
		"UpperHallConsole",
		Vector3(2.55, FLOOR_HEIGHT, 5.59),
		PI
	)
	_add_asset(
		FURNITURE_TABLE_LAMP,
		upper_props,
		"UpperHallLamp",
		Vector3(2.55, FLOOR_HEIGHT + 0.98, 5.59),
		PI
	)

	var attic_props := _add_container(attic, "Props")
	for position: Vector3 in [
		Vector3(6.8, 6.0, 3.2),
		Vector3(6.0, 6.0, 3.2),
		Vector3(6.4, 6.65, 2.8),
		Vector3(-7.8, 6.0, 4.7),
		Vector3(-7.0, 6.0, 4.7),
		Vector3(-7.4, 6.65, 4.3),
		Vector3(7.6, 6.0, -4.8),
		Vector3(6.8, 6.0, -4.8),
	]:
		_add_asset(FURNITURE_BOX, attic_props, "AtticCrate", position)
	_add_asset(FURNITURE_SHELVES, attic_props, "AtticShelvesEastA", Vector3(8.65, 6.0, 4.5), PI * 0.5)
	_add_asset(FURNITURE_SHELVES, attic_props, "AtticShelvesEastB", Vector3(8.65, 6.0, 2.7), PI * 0.5)
	_add_asset(FURNITURE_SHELVES, attic_props, "AtticShelvesBack", Vector3(4.5, 6.0, -5.65))
	_add_asset(FURNITURE_SHELVES, attic_props, "AtticShelvesWestA", Vector3(-8.65, 6.0, 1.2), PI * 0.5)
	_add_asset(FURNITURE_SHELVES, attic_props, "AtticShelvesWestB", Vector3(-8.65, 6.0, 3.1), PI * 0.5)
	_add_asset(FURNITURE_WARDROBE, attic_props, "OldWardrobe", Vector3(-8.65, 6.0, -3.0), PI * 0.5)
	_add_asset(FURNITURE_LADDER, attic_props, "AtticLadder", Vector3(-4.0, 6.0, -5.86))
	_add_asset(FURNITURE_SOFA, attic_props, "StoredSofa", Vector3(-6.0, 6.0, -4.8))
	_add_furniture_bed(attic_props, "StoredBed", Vector3(5.7, 6.0, -4.35))
	_add_asset(FURNITURE_WASHER, attic_props, "OldWasher", Vector3(8.15, 6.0, -1.2), -PI * 0.5)
	_add_asset(FURNITURE_DINING_TABLE, attic_props, "AtticWorkTable", Vector3(1.0, 6.0, -2.0))
	_add_asset(FURNITURE_LOUNGE_CHAIR, attic_props, "AtticChair", Vector3(3.0, 6.0, -2.0), PI * 0.5)
	_add_asset(FURNITURE_RADIO, attic_props, "OldRadio", Vector3(1.0, 7.02, -2.0))
	_add_asset(LOOSE_PLANK_A, attic_props, "AtticPlanksA", Vector3(-1.2, 6.12, -2.7), 0.24)
	_add_asset(LOOSE_PLANK_B, attic_props, "AtticPlanksB", Vector3(1.0, 6.12, -4.2), -0.36)
	for position: Vector3 in [
		Vector3(-7.9, 6.0, -0.8), Vector3(-7.1, 6.0, -0.8),
		Vector3(-7.5, 6.65, -1.1), Vector3(7.9, 6.0, 0.5),
		Vector3(7.1, 6.0, 0.5), Vector3(7.5, 6.65, 0.2),
	]:
		_add_asset(FURNITURE_BOX, attic_props, "AtticCrate", position)
	for position: Vector3 in [
		Vector3(-7.8, 6.12, 5.0), Vector3(-7.1, 6.12, 5.0),
		Vector3(7.7, 6.12, -2.8),
	]:
		_add_asset(FURNITURE_TIRE, attic_props, "StoredTire", position)


func _build_lighting(parent: Node3D) -> void:
	var lighting := _add_container(parent, "InteriorLighting")
	_add_light(lighting, "BasementBulb", Vector3(0, -0.55, 0), Color(0.67, 0.48, 0.28), 0.85, 6.5, true)
	_add_light(lighting, "KitchenLight", Vector3(-6, 2.35, -3), Color(0.68, 0.52, 0.31), 0.62, 4.6)
	_add_light(lighting, "LivingLight", Vector3(0, 2.3, -3), Color(0.57, 0.46, 0.34), 0.55, 4.8)
	_add_light(lighting, "DiningLight", Vector3(6, 2.3, -3), Color(0.7, 0.49, 0.27), 0.62, 4.6)
	_add_light(lighting, "HallLight", Vector3(2.2, 2.35, 3), Color(0.59, 0.46, 0.3), 0.58, 4.6, true)
	_add_light(lighting, "UpperHallLight", Vector3(0, 5.35, 3), Color(0.55, 0.43, 0.31), 0.55, 5.0)
	_add_light(lighting, "WestBedroomLight", Vector3(-5, 5.3, -3), Color(0.48, 0.4, 0.32), 0.38, 4.2)
	_add_light(lighting, "EastBedroomLight", Vector3(5, 5.3, -3), Color(0.48, 0.4, 0.32), 0.38, 4.2)
	_add_light(lighting, "BathroomLight", Vector3(6, 5.4, 3.5), Color(0.47, 0.54, 0.55), 0.48, 4.0)
	_add_light(lighting, "AtticBulb", Vector3(0, 8.35, 0), Color(0.63, 0.43, 0.24), 0.5, 5.2, true)

	for fixture_position: Vector3 in [
		Vector3(0, -0.2, 0),
		Vector3(-6, 2.78, -3), Vector3(0, 2.78, -3),
		Vector3(6, 2.78, -3), Vector3(2.2, 2.78, 3),
		Vector3(-5, 5.78, -3), Vector3(5, 5.78, -3),
		Vector3(0, 5.78, 3), Vector3(6, 5.78, 3.5),
		Vector3(0, 8.78, 0),
	]:
		_add_asset(FURNITURE_CEILING_LAMP, lighting, "CeilingFixture", fixture_position)


func _add_partition_x(parent: Node3D, z: float, y: float, gaps: Array[Vector2], prefix: String) -> void:
	_add_wall_x(parent, z, y, HOUSE_X_MIN, HOUSE_X_MAX, gaps, prefix)
	for gap: Vector2 in gaps:
		_add_asset(DOOR_FRAME, parent, prefix + "DoorFrame", Vector3(gap.x, y, z))


func _add_partition_z(parent: Node3D, x: float, y: float, gaps: Array[Vector2], prefix: String) -> void:
	_add_wall_z(parent, x, y, HOUSE_Z_MIN, HOUSE_Z_MAX, gaps, prefix)
	for gap: Vector2 in gaps:
		_add_asset(DOOR_FRAME, parent, prefix + "DoorFrame", Vector3(x, y, gap.x), PI * 0.5)


func _add_wall_x(
	parent: Node3D,
	z: float,
	y: float,
	x_min: float,
	x_max: float,
	gaps: Array[Vector2],
	prefix: String
) -> void:
	for index: int in int(x_max - x_min):
		var x := x_min + index + 0.5
		if _point_is_in_gap(x, gaps):
			continue
		_add_asset(WALL_3X1, parent, prefix + "Module", Vector3(x, y, z))


func _add_wall_z(
	parent: Node3D,
	x: float,
	y: float,
	z_min: float,
	z_max: float,
	gaps: Array[Vector2],
	prefix: String
) -> void:
	for index: int in int(z_max - z_min):
		var z := z_min + index + 0.5
		if _point_is_in_gap(z, gaps):
			continue
		_add_asset(WALL_3X1, parent, prefix + "Module", Vector3(x, y, z), PI * 0.5)


func _point_is_in_gap(value: float, gaps: Array[Vector2]) -> bool:
	for gap: Vector2 in gaps:
		if absf(value - gap.x) < gap.y * 0.5:
			return true
	return false


func _add_floor_grid(
	parent: Node3D,
	y: float,
	bounds: Rect2,
	holes: Array[Rect2] = []
) -> void:
	var columns := int(bounds.size.x / 2.0)
	var rows := int(bounds.size.y / 2.0)
	for column: int in columns:
		for row: int in rows:
			var center := Vector2(
				bounds.position.x + column * 2.0 + 1.0,
				bounds.position.y + row * 2.0 + 1.0
			)
			var inside_hole := false
			for hole: Rect2 in holes:
				if hole.has_point(center):
					inside_hole = true
					break
			if not inside_hole:
				_add_asset(FLOOR_2X2, parent, "FloorTile", Vector3(center.x, y, center.y))


func _build_back_balcony(
	parent: Node3D,
	balcony_name: String,
	center_x: float,
	y: float,
	back_wall_z: float
) -> void:
	var balcony := _add_container(parent, balcony_name)
	var outer_z := back_wall_z - 2.0
	_add_floor_grid(balcony, y, Rect2(center_x - 2, outer_z, 4, 2))
	_add_railing_x(balcony, center_x - 2, center_x + 2, outer_z, y)
	_add_railing_z(balcony, center_x - 2, outer_z, back_wall_z, y)
	_add_railing_z(balcony, center_x + 2, outer_z, back_wall_z, y)


func _build_side_balcony(parent: Node3D, balcony_name: String, center_z: float, y: float) -> void:
	var balcony := _add_container(parent, balcony_name)
	_add_floor_grid(balcony, y, Rect2(9, center_z - 2, 2, 4))
	_add_railing_z(balcony, 11.0, center_z - 2, center_z + 2, y)
	_add_railing_x(balcony, 9.0, 11.0, center_z - 2, y)
	_add_railing_x(balcony, 9.0, 11.0, center_z + 2, y)


func _add_railing_x(parent: Node3D, x_min: float, x_max: float, z: float, y: float) -> void:
	for index: int in int(ceilf(x_max - x_min)):
		_add_asset(BALCONY_RAIL, parent, "BalconyRail", Vector3(x_min + index + 0.5, y, z))


func _add_railing_z(parent: Node3D, x: float, z_min: float, z_max: float, y: float) -> void:
	for index: int in int(ceilf(z_max - z_min)):
		_add_asset(BALCONY_RAIL, parent, "BalconyRail", Vector3(x, y, z_min + index + 0.5), PI * 0.5)


func _add_room(parent: Node3D, room_name: String, floor_center: Vector3, room_size: Vector3) -> void:
	var room := Marker3D.new()
	room.name = room_name
	room.position = floor_center
	room.set_meta("room_size", room_size)
	room.add_to_group("house2_rooms")
	parent.add_child(room)


func _add_stair(
	parent: Node3D,
	stair_name: String,
	position: Vector3,
	rotation_y: float
) -> void:
	var visual := _add_asset(
		BIG_STAIR,
		parent,
		stair_name,
		position,
		rotation_y,
		Vector3(1, 1, 1.8)
	)
	visual.add_to_group("smooth_stair_visual")

	# The detailed mesh keeps its individual treads for appearance, while this
	# 45-degree ramp supplies a continuous floor to move_and_slide() and Recast.
	# This removes the repeated capsule step-up/down that caused camera judder.
	var ramp_body := StaticBody3D.new()
	ramp_body.name = stair_name + "SmoothRamp"
	ramp_body.position = position + Vector3(0, FLOOR_HEIGHT * 0.5, 0)
	ramp_body.basis = (
		Basis(Vector3.UP, rotation_y)
		* Basis(Vector3.BACK, PI * 0.25)
	)
	ramp_body.add_to_group("smooth_stair_ramps")
	parent.add_child(ramp_body)

	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(sqrt(18.0), 0.16, 1.5)
	var collision := CollisionShape3D.new()
	collision.name = "SmoothRampCollision"
	collision.shape = ramp_shape
	ramp_body.add_child(collision)


func _add_asset(
	scene: PackedScene,
	parent: Node3D,
	asset_name: String,
	position: Vector3,
	rotation_y: float = 0.0,
	scale_value: Vector3 = Vector3.ONE
) -> Node3D:
	var instance := scene.instantiate() as Node3D
	_module_index += 1
	instance.name = "%s_%03d" % [asset_name, _module_index]
	instance.position = position
	instance.rotation.y = rotation_y
	instance.scale = scale_value
	instance.set_meta("source_asset", scene.resource_path)
	instance.add_to_group("modular_house_asset")
	parent.add_child(instance)
	return instance


func _add_container(parent: Node3D, container_name: String) -> Node3D:
	var container := Node3D.new()
	container.name = container_name
	parent.add_child(container)
	return container


func _add_box(
	parent: Node3D,
	box_name: String,
	position: Vector3,
	size: Vector3,
	material: Material
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = box_name
	instance.position = position
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _add_cylinder(
	parent: Node3D,
	cylinder_name: String,
	position: Vector3,
	radius: float,
	height: float,
	material: Material
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = cylinder_name
	instance.position = position
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _add_furniture_bed(parent: Node3D, bed_name: String, origin: Vector3) -> void:
	_add_asset(FURNITURE_BED_BASE, parent, bed_name + "Base", origin)
	_add_asset(
		FURNITURE_BED_SHEETS,
		parent,
		bed_name + "Sheets",
		origin + Vector3(0, 0.52, 0)
	)
## Every authored room light is a LightSource instance rather than a bare
## OmniLight3D, so each one can be switched off directly and goes dark on its
## own during a PowerManager blackout - the fusebox/blackout system now has
## something real to darken. The inner Light3D still joins
## "flickering_house_lights" exactly as before, so HouseLightFlicker keeps
## working unchanged (light_flicker_smoke.gd asserts this).
func _add_light(
	parent: Node3D,
	light_name: String,
	position: Vector3,
	color: Color,
	energy: float,
	range_value: float,
	shadows := false
) -> void:
	var light_source := LIGHT_SOURCE.instantiate()
	light_source.name = light_name
	light_source.position = position
	light_source.directly_toggleable = true

	var light := light_source.get_node("Light") as OmniLight3D
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.omni_attenuation = 1.35
	light.shadow_enabled = shadows
	light.add_to_group("flickering_house_lights")

	# The fixture loop below already places a proper Ceiling Lamp/wall-bulb
	# mesh near this exact position - LightSource's own placeholder bulb
	# would just double up on top of it, and would otherwise pick up a
	# redundant trimesh collider from main.gd's generated-collision pass.
	var placeholder_bulb := light_source.get_node("Bulb")
	light_source.remove_child(placeholder_bulb)
	placeholder_bulb.free()

	parent.add_child(light_source)


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

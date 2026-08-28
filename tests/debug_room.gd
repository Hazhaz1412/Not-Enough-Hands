extends Node3D

## Sandbox scene for eyeballing ghost, door, and power-system behaviour
## without loading the real house. Player, StatueGhost, CrawlerGhost,
## HunterGhost, DoorAttackDirector and WorldEnvironment all sit at the same
## relative paths DevTools already defaults to (see ui/dev_tools.gd), so the
## F1 panel works here with no export overrides - including "NGẮT ĐIỆN NGAY",
## which forces a blackout on demand instead of waiting for the one load on
## the Power node to drain it out on its own (~30s).

@onready var room: Node3D = $Room


func _ready() -> void:
	_bake_room_navigation()


## Same recipe as House2's runtime bake (house2.gd _bake_house_navigation):
## parse the room's own static colliders, not its render meshes, so the
## navmesh the ghosts path on can never disagree with what the player
## actually collides with.
func _bake_room_navigation() -> void:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_height = 1.75
	navigation_mesh.agent_radius = 0.4
	navigation_mesh.agent_max_climb = 0.6
	navigation_mesh.agent_max_slope = 50.0
	navigation_mesh.cell_size = 0.1
	navigation_mesh.cell_height = 0.05
	navigation_mesh.filter_low_hanging_obstacles = true
	navigation_mesh.filter_ledge_spans = true
	navigation_mesh.filter_walkable_low_height_spans = true
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS

	var source_geometry_data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, source_geometry_data, room)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source_geometry_data)

	var navigation_region := NavigationRegion3D.new()
	navigation_region.name = "RoomNavigationRegion"
	navigation_region.navigation_mesh = navigation_mesh
	room.add_child(navigation_region)

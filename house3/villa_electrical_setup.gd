@tool
class_name VillaElectricalSetup
extends Node3D

## Builds the Villa's light fixtures from its already-authored room and
## junction markers. The mapping from fixture IDs to electrical zones remains
## explicit in villa_main.tscn, so designers can rebalance a zone in Inspector.

@export var fixture_root: NodePath = NodePath("RoomLights")
@export var switch_root: NodePath = NodePath("RoomSwitches")
## Creates visible, persistent switch instances in the editor. Move an
## individual switch in the 3D viewport and that transform is kept at runtime.
@export var generate_editor_switch_preview := true
## Villa ceilings are 0.30 m thick. Keep the lamp mount just below their
## underside so its canopy touches the ceiling instead of floating below it.
@export_range(0.0, 0.30, 0.01) var ceiling_fixture_clearance := 0.04
## Local position of the bulb inside Ceiling Lamp 2. Kept exposed so it can be
## fine-tuned once against the imported lamp mesh in the 3D viewport.
@export var ceiling_lamp_light_offset := Vector3(0.0, -0.35, 0.0)
@export_range(0.0, 10000.0, 1.0) var room_light_consumption := 60.0
@export_range(0.0, 10000.0, 1.0) var junction_light_consumption := 35.0
@export_range(0.1, 5.0, 0.05) var fixture_light_energy := 1.25
@export_range(0.5, 2.0, 0.05) var fixture_range_multiplier := 1.15
@export var rebuild_on_ready := true

@export_category("Client Lighting Budget")
## Shadow maps are a per-view rendering cost, so each peer budgets only the
## fixtures relevant to its own camera. The lights themselves remain powered
## and visible; only their expensive shadow pass is culled.
@export_range(0, 16, 1) var max_shadow_lights := 6
@export_range(2.0, 40.0, 0.5) var shadow_max_distance := 18.0
@export_range(0.05, 1.0, 0.05) var shadow_budget_interval := 0.25
## The global environment still supplies the Villa's fog. Local Omni lights do
## not need to inject into its volumetric grid as well.
@export var disable_fixture_volumetric_fog := true

const ROOM_LIGHT_COLOR := Color(1.0, 0.69, 0.39, 1.0)
const JUNCTION_LIGHT_COLOR := Color(0.72, 0.82, 1.0, 1.0)
const CEILING_LAMP_MODEL: PackedScene = preload("res://assets/map/Furniture/FBX/Separated/Ceiling Lamp 2.fbx")
const LIGHT_SWITCH_SCENE: PackedScene = preload("res://switches/imported_light_switch_2.tscn")
const SWITCH_HEIGHT := 1.35
const SWITCH_WALL_INSET := 0.16

var _villa_spec: VillaSpec
var _fixture_lights: Array[OmniLight3D] = []
var _shadow_budget_timer := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		if generate_editor_switch_preview:
			build_switch_preview.call_deferred()
	elif rebuild_on_ready:
		build_fixtures.call_deferred()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _fixture_lights.is_empty():
		return
	_shadow_budget_timer -= delta
	if _shadow_budget_timer > 0.0:
		return
	_shadow_budget_timer = maxf(shadow_budget_interval, 0.05)
	_update_shadow_budget()


func build_fixtures() -> void:
	var root := get_node_or_null(fixture_root) as Node3D
	if not root:
		push_warning("VillaElectricalSetup: fixture_root is not assigned")
		return
	var switches := get_node_or_null(switch_root) as Node3D
	if not switches:
		push_warning("VillaElectricalSetup: switch_root is not assigned")
		return
	for child: Node in root.get_children():
		child.queue_free()
	_fixture_lights.clear()

	var rooms := get_tree().get_nodes_in_group("villa_rooms")
	rooms.sort_custom(_sort_by_name)
	for room_node: Node in rooms:
		var room := room_node as Marker3D
		if not room:
			continue
		var room_id := StringName(room.get_meta("room_id", room.name))
		if room_id.is_empty():
			continue
		var room_size := room.get_meta("room_size", Vector3(8.0, 3.5, 8.0)) as Vector3
		var light_range := clampf(
			maxf(room_size.x, room_size.z) * 0.55 * fixture_range_multiplier,
			5.0,
			13.5
		)
		_create_fixture(
			root,
			switches,
			room_id,
			room.global_position,
			ROOM_LIGHT_COLOR,
			light_range,
			room_light_consumption,
			room_size
		)

	var junctions := get_tree().get_nodes_in_group("villa_junctions")
	junctions.sort_custom(_sort_by_name)
	for junction_node: Node in junctions:
		var junction := junction_node as Marker3D
		if not junction:
			continue
		_create_fixture(
			root,
			switches,
			StringName(junction.get_meta("junction_id", junction.name)),
			junction.global_position,
			JUNCTION_LIGHT_COLOR,
			5.5 * fixture_range_multiplier,
			junction_light_consumption,
			Vector3(4.0, 3.5, 4.0)
		)
	_shadow_budget_timer = 0.0
	_update_shadow_budget.call_deferred()


func _create_fixture(
	root: Node3D,
	switches: Node3D,
	device_id: StringName,
	marker_position: Vector3,
	color: Color,
	light_range: float,
	consumption: float,
	area_size: Vector3
) -> void:
	# Keep the lamp mesh separate from the Light3D. Turning a device off must
	# darken the bulb but leave its physical ceiling fixture in the world.
	var fixture := Node3D.new()
	fixture.name = String(device_id) + "Fixture"
	root.add_child(fixture)
	var ceiling_underside := area_size.y - 0.30
	fixture.global_position = marker_position + Vector3.UP * (
		ceiling_underside - ceiling_fixture_clearance
	)

	var lamp_visual := CEILING_LAMP_MODEL.instantiate() as Node3D
	lamp_visual.name = "CeilingLamp2"
	fixture.add_child(lamp_visual)

	var light := OmniLight3D.new()
	light.name = String(device_id) + "Light"
	# The light belongs under the lamp shade, not at the ceiling attachment.
	light.position = ceiling_lamp_light_offset
	light.light_color = color
	light.light_energy = fixture_light_energy
	light.omni_range = light_range
	light.omni_attenuation = 1.35
	# Start cheap. _update_shadow_budget() promotes only the nearest useful
	# fixtures after a camera exists on this peer.
	light.shadow_enabled = false
	if disable_fixture_volumetric_fog:
		light.light_volumetric_fog_energy = 0.0
	light.add_to_group("flickering_house_lights")
	light.add_to_group("local_light_sources")
	light.set_meta("electrical_device_id", device_id)
	fixture.add_child(light)
	_fixture_lights.append(light)

	var device := ElectricalDevice.new()
	device.name = "ElectricalDevice"
	device.device_id = device_id
	device.power_consumption = consumption
	device.powered_light = light
	fixture.add_child(device)

	_ensure_switch(switches, device_id, marker_position, area_size)


func _update_shadow_budget() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera or max_shadow_lights <= 0:
		_set_all_fixture_shadows(false)
		return

	var camera_position := camera.global_position
	var max_distance_squared := shadow_max_distance * shadow_max_distance
	var candidates: Array[OmniLight3D] = []
	for light: OmniLight3D in _fixture_lights:
		if not is_instance_valid(light):
			continue
		if light.is_visible_in_tree() \
				and light.global_position.distance_squared_to(camera_position) <= max_distance_squared:
			candidates.append(light)

	candidates.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
		return a.global_position.distance_squared_to(camera_position) \
			< b.global_position.distance_squared_to(camera_position)
	)
	var shadowed: Dictionary = {}
	for index: int in mini(max_shadow_lights, candidates.size()):
		shadowed[candidates[index]] = true
	for light: OmniLight3D in _fixture_lights:
		if is_instance_valid(light):
			light.shadow_enabled = shadowed.has(light)


func _set_all_fixture_shadows(enabled: bool) -> void:
	for light: OmniLight3D in _fixture_lights:
		if is_instance_valid(light):
			light.shadow_enabled = enabled


## Editor-only authoring pass. The generated switches are given an owner, so
## Godot saves them into villa_main.tscn and exposes each transform in Inspector.
## At runtime they bind themselves to the ElectricalDevice with the same ID.
func build_switch_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var switches := get_node_or_null(switch_root) as Node3D
	if not switches:
		return
	for room_node: Node in get_tree().get_nodes_in_group("villa_rooms"):
		var room := room_node as Marker3D
		if room:
			_ensure_switch(
				switches,
				StringName(room.get_meta("room_id", room.name)),
				room.global_position,
				room.get_meta("room_size", Vector3(8.0, 3.5, 8.0)) as Vector3
			)
	for junction_node: Node in get_tree().get_nodes_in_group("villa_junctions"):
		var junction := junction_node as Marker3D
		if junction:
			_ensure_switch(
				switches,
				StringName(junction.get_meta("junction_id", junction.name)),
				junction.global_position,
				Vector3(4.0, 3.5, 4.0)
			)


func _ensure_switch(
	switches: Node3D,
	device_id: StringName,
	marker_position: Vector3,
	area_size: Vector3
) -> StaticBody3D:
	var switch_name := String(device_id) + "LightSwitch"
	var existing := switches.get_node_or_null(NodePath(switch_name)) as StaticBody3D
	if existing:
		if not existing.keep_authored_transform and _has_generated_transform(existing):
			_apply_wall_placement(existing, device_id, marker_position, area_size)
		return existing
	var light_switch := LIGHT_SWITCH_SCENE.instantiate() as StaticBody3D
	light_switch.name = switch_name
	light_switch.controlled_device_id = device_id
	switches.add_child(light_switch)
	_apply_wall_placement(light_switch, device_id, marker_position, area_size)
	if Engine.is_editor_hint():
		light_switch.owner = get_tree().edited_scene_root
	return light_switch


## Finds an accessible wall face from the same map grid that creates the
## villa's architecture. Doorway/breach cells are never valid switch faces.
## This is also used for junctions: it searches nearby corridor cells until it
## finds an actual wall rather than leaving a switch in a crossing.
func _apply_wall_placement(
	light_switch: StaticBody3D,
	device_id: StringName,
	marker_position: Vector3,
	fallback_area_size: Vector3
) -> void:
	var placement := _find_wall_placement(device_id, marker_position)
	if placement.is_empty():
		# Only a safety fallback for a malformed/missing map-spec entry.
		var half_depth := maxf(fallback_area_size.z * 0.5 - SWITCH_WALL_INSET, 0.45)
		light_switch.global_position = marker_position + Vector3(0.0, SWITCH_HEIGHT, -half_depth)
		light_switch.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)
		_remember_generated_transform(light_switch)
		return
	light_switch.global_position = placement["position"] as Vector3
	light_switch.global_rotation = Vector3(0.0, float(placement["rotation_y"]), 0.0)
	_remember_generated_transform(light_switch)


func _has_generated_transform(light_switch: StaticBody3D) -> bool:
	# Switches created before this metadata was introduced are safely treated as
	# generated once, so the former "south wall" placement is corrected.
	if not light_switch.has_meta("generated_switch_position"):
		return true
	var generated_position := light_switch.get_meta("generated_switch_position") as Vector3
	var generated_yaw := float(light_switch.get_meta("generated_switch_yaw", light_switch.rotation.y))
	return light_switch.position.is_equal_approx(generated_position) \
		and is_equal_approx(light_switch.rotation.y, generated_yaw)


func _remember_generated_transform(light_switch: StaticBody3D) -> void:
	light_switch.set_meta("generated_switch_position", light_switch.position)
	light_switch.set_meta("generated_switch_yaw", light_switch.rotation.y)


func _find_wall_placement(device_id: StringName, marker_position: Vector3) -> Dictionary:
	var spec := _get_villa_spec()
	var room := spec.room(String(device_id))
	var junction := spec.junction(String(device_id))
	if room.is_empty() and junction.is_empty():
		return {}

	var level := int(room.get("level", junction.get("level", 0)))
	var level_data := spec.build_level(level)
	var cells: Dictionary = level_data["cells"]
	var candidate_cells: Array[Vector2i] = []
	if not room.is_empty():
		var rect := VillaSpec.to_rect(room["rect"] as Array)
		for column: int in range(rect.position.x, rect.end.x):
			for row: int in range(rect.position.y, rect.end.y):
				candidate_cells.append(Vector2i(column, row))
	else:
		# A junction can be open on all four immediate sides. Search a compact
		# ring of corridor cells, retaining only cells that share a real wall.
		var junction_rect := VillaSpec.to_rect(junction["rect"] as Array)
		var centre := Vector2i(junction_rect.get_center())
		for radius: int in range(0, 5):
			for column: int in range(centre.x - radius, centre.x + radius + 1):
				for row: int in range(centre.y - radius, centre.y + radius + 1):
					var cell := Vector2i(column, row)
					if cell not in candidate_cells:
						candidate_cells.append(cell)

	var doorway_positions := _doorway_positions(spec, level_data, level)
	var best_score := -INF
	var best: Dictionary = {}
	for cell: Vector2i in candidate_cells:
		if int(cells.get(cell, VillaSpec.WALL)) < VillaSpec.ROOM:
			continue
		for outward: Vector2i in VillaSpec.DIRECTIONS:
			var neighbour := cell + outward
			# A non-walkable neighbour is a generated wall cell. Doorways and
			# breached entrances count as walkable, so they cannot be chosen.
			if int(cells.get(neighbour, VillaSpec.WALL)) >= VillaSpec.ROOM:
				continue
			var cell_world := spec.grid_to_world(cell.x, cell.y, level)
			var position := cell_world + Vector3(
				float(outward.x) * (spec.cell_size * 0.5 - SWITCH_WALL_INSET),
				SWITCH_HEIGHT,
				float(outward.y) * (spec.cell_size * 0.5 - SWITCH_WALL_INSET)
			)
			var nearest_door := 99.0
			for doorway: Vector3 in doorway_positions:
				nearest_door = minf(nearest_door, Vector2(position.x, position.z).distance_to(Vector2(doorway.x, doorway.z)))
			# Door clearance is the main criterion; keeping a junction switch near
			# its junction avoids placing it at the far end of a corridor.
			var score := minf(nearest_door, 8.0) * 10.0
			score -= Vector2(position.x, position.z).distance_to(Vector2(marker_position.x, marker_position.z)) * 0.35
			if score <= best_score:
				continue
			best_score = score
			best = {
				"position": position,
				"rotation_y": _yaw_facing_inward(-outward),
			}
	return best


func _doorway_positions(spec: VillaSpec, level_data: Dictionary, level: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for door: Dictionary in level_data["doors"]:
		var cell := door["cell"] as Vector2i
		positions.append(spec.grid_to_world(cell.x, cell.y, level))
	for breach: Dictionary in level_data["breaches"]:
		var cell := breach["cell"] as Vector2i
		positions.append(spec.grid_to_world(cell.x, cell.y, level))
	return positions


func _yaw_facing_inward(direction: Vector2i) -> float:
	# The imported switch model's front points along local +X.
	if direction.x > 0:
		return 0.0
	if direction.x < 0:
		return PI
	if direction.y > 0:
		return -PI * 0.5
	return PI * 0.5


func _get_villa_spec() -> VillaSpec:
	if not _villa_spec:
		_villa_spec = VillaSpec.load_default()
	return _villa_spec


func _sort_by_name(a: Node, b: Node) -> bool:
	return a.name.naturalnocasecmp_to(b.name) < 0

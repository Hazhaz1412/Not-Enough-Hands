extends Node3D
class_name VillaWindows

## Glazes the villa and lets the moon in.
##
## VillaHouse builds the perimeter as two separate skins two metres apart: an
## `ExteriorWall` shell on the outer face of the border cells, and the rooms'
## own `InteriorWall` runs one cell further in. Between them is an unlit,
## unfloored two-metre band. This pass finds pairs of those skins that face
## each other, hides the kit panel on both, and drops a single masonry block
## with a hole through it into the band - so the opening reads as a deep
## window reveal instead of a gap into a cavity.
##
## Nothing here touches a collider. Every wall body keeps the box shape it was
## baked with, which means:
##
##   * villa_seal_smoke.gd still finds a solid wall at every waist- and
##     head-height ray, because physically there still is one;
##   * the navmesh villa_main.gd bakes from static colliders is bit-identical
##     to the one it baked before, so nothing here costs bake time;
##   * and the player can see out but not climb out, which is the point.
##
## The light is one SpotLight3D per window, aimed in through the reveal. Only
## the handful nearest the camera are switched on, and an even smaller exported
## subset casts shadows, so the rendering cost stays bounded as bays are added.

const PACK := "res://assets/map/- Classic 64 Asset Pack 0.6/"

const T_SURROUND := PACK + "Walls/Materials/wall_stucco_03.jpg"
const T_REVEAL := PACK + "Concrete/Materials/concrete_13.jpg"
const T_SILL := PACK + "Rocks/Materials/rock_wall_02.jpg"
const T_FRAME := PACK + "Wood/Materials/wood_rustic_3.png"
const T_BOARD := PACK + "Wood/Materials/wood_plank_charred.jpg"

## Mirrors house3/villa_house.gd: cell size, wall thickness, storey height and
## the ceiling slab that caps each storey.
const CELL := 2.0
const WALL_THICKNESS := 0.3
const STOREY := 3.5
const SLAB := 0.3
## Width of the band of wall cells between the two skins.
const BAND := 2.0

const OPENING_WIDTH := 1.3
const SILL_HEIGHT := 0.95
const HEAD_HEIGHT := 2.45

## The four faces of the footprint, as the plane each shell wall's centre sits
## on and the direction that wall looks out along.
const FACES: Array[Dictionary] = [
	{"axis": Vector3.RIGHT, "plane": -0.15, "outward": Vector3.LEFT},
	{"axis": Vector3.RIGHT, "plane": 80.15, "outward": Vector3.RIGHT},
	{"axis": Vector3.BACK, "plane": -0.15, "outward": Vector3.FORWARD},
	{"axis": Vector3.BACK, "plane": 60.15, "outward": Vector3.BACK},
]

@export_category("Layout")
## One window per this many perimeter cells. 2 gives a bay every 4 m.
@export_range(1, 6, 1) var cells_per_window: int = 2
## Storeys to glaze, as villa level numbers. The cellar has no outside wall
## worth glazing and the attic is lit through entrance 07's skylight.
@export var glazed_levels: Array[int] = [0, 1]
## Every nth window is boarded over instead of glazed. The moon still gets
## through, in stripes.
@export_range(0, 12, 1) var boarded_every: int = 4

@export_category("Moonlight")
## Deliberately low: this is a dark blue wash that shows where a window is,
## not a light to read the room by.
@export var moonlight_energy: float = 1.35
@export var moonlight_colour: Color = Color(0.46, 0.58, 0.92)
@export_range(0, 40, 1) var active_lights: int = 6
@export_range(0, 12, 1) var shadowed_lights: int = 2

var _materials: Dictionary = {}
var _index: int = 0
var _lights: Array[SpotLight3D] = []
var _cooldown: float = 0.0
var _box_batches: Dictionary = {}
var _logical_counts: Dictionary = {}


func _ready() -> void:
	set_process(false)
	# Deferred so the pass also works if VillaHouse generated itself this frame
	# rather than being loaded from villa_main.tscn's baked parts.
	_build.call_deferred()


func _build() -> void:
	var house := _villa_house()
	if not house:
		push_warning("VillaWindows found no villa to glaze.")
		return

	var root := Node3D.new()
	root.name = "Generated"
	root.add_to_group("villa_windows")
	add_child(root)

	var bays := _window_bays(house)
	for index: int in bays.size():
		_build_window(root, bays[index], index % maxi(boarded_every, 1) == boarded_every - 1)
	_flush_box_batches(root)
	root.set_meta("window_count", bays.size())
	root.set_meta("glazed_count", int(_logical_counts.get("WindowPane", 0)))
	root.set_meta("boarded_count", int(_logical_counts.get("WindowBoardStub", 0)))
	root.set_meta("logical_mesh_count", _logical_mesh_count())
	root.set_meta("render_batch_count", root.find_children("*", "MultiMeshInstance3D", true, false).size())

	set_process(not _lights.is_empty())


func _villa_house() -> Node3D:
	var parent := get_parent()
	var house := parent.get_node_or_null("VillaHouse") as Node3D if parent else null
	if house:
		return house
	for node: Node in get_tree().get_nodes_in_group("villa_geometry"):
		return (node as Node3D).get_parent() as Node3D
	return null


# --- finding the bays ---------------------------------------------------------

## A bay is one perimeter cell whose outer shell has a room wall directly
## opposite it, one cell in. Cells that back onto more solid wall - the corners
## of the footprint, the thickness around a stair core - never produce one,
## which is why the search is for pairs rather than for shell walls.
func _window_bays(house: Node3D) -> Array[Dictionary]:
	var inner_walls: Dictionary = {}
	for node: Node in house.find_children("InteriorWall_*", "StaticBody3D", true, false):
		inner_walls[_grid_key((node as Node3D).global_position)] = node

	var candidates: Dictionary = {}
	for node: Node in house.find_children("ExteriorWall_*", "StaticBody3D", true, false):
		var shell := node as Node3D
		var face := _face_of(shell.global_position)
		if face.is_empty():
			continue
		var level := int(round((shell.global_position.y - STOREY * 0.5) / STOREY))
		if not glazed_levels.has(level):
			continue
		var outward: Vector3 = face["outward"]
		var inner: Variant = inner_walls.get(_grid_key(shell.global_position - outward * BAND))
		if inner == null:
			continue

		# Group by face and storey, then order along the wall, so which cells
		# become windows is a property of the building and not of node order.
		var group := "%d|%s" % [level, outward]
		var tangent := shell.global_position.dot(Vector3(absf(outward.z), 0.0, absf(outward.x)))
		if not candidates.has(group):
			candidates[group] = []
		candidates[group].append({
			"shell": shell,
			"inner": inner as Node3D,
			"outward": outward,
			"tangent": tangent,
			"base": shell.global_position.y - STOREY * 0.5,
		})

	var bays: Array[Dictionary] = []
	var groups: Array = candidates.keys()
	groups.sort()
	for group: String in groups:
		var run: Array = candidates[group]
		run.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["tangent"]) < float(b["tangent"])
		)
		var pitch := maxi(cells_per_window, 1)
		for index: int in run.size():
			# Offset by one so a run never starts with a window in the cell
			# hard against the corner pier.
			if index % pitch == 1 % pitch and index > 0:
				bays.append(run[index])
	return bays


func _face_of(at: Vector3) -> Dictionary:
	for face: Dictionary in FACES:
		var axis: Vector3 = face["axis"]
		if absf(at.dot(axis) - float(face["plane"])) < 0.05:
			return face
	return {}


func _grid_key(at: Vector3) -> Vector3i:
	return Vector3i(roundi(at.x * 10.0), roundi(at.y * 10.0), roundi(at.z * 10.0))


# --- building one window ------------------------------------------------------

func _build_window(parent: Node3D, bay: Dictionary, boarded: bool) -> void:
	var shell := bay["shell"] as Node3D
	var inner := bay["inner"] as Node3D
	var outward: Vector3 = bay["outward"]
	var inward := -outward
	var base: float = bay["base"]
	# Unit vector along the wall, and the sign-free helper that turns
	# (along-wall, up, through-wall) sizes into a world-space Vector3.
	var tangent_is_x := absf(outward.z) > 0.5

	_hide_panels(shell)
	_hide_panels(inner)

	var outer_face := shell.global_position + outward * (WALL_THICKNESS * 0.5)
	var inner_face := inner.global_position + inward * (WALL_THICKNESS * 0.5)
	var depth := outer_face.distance_to(inner_face)
	var through := (outer_face + inner_face) * 0.5
	var head := minf(HEAD_HEIGHT, STOREY - SLAB - 0.05)

	var surround := _material(T_SURROUND, 2.0, Color(0.46, 0.46, 0.44))
	var reveal := _material(T_REVEAL, 1.4, Color(0.38, 0.39, 0.38))

	# The reveal is one solid block with a hole through it, in four pieces:
	# under the sill, over the head, and a jamb either side. Built this way it
	# also caps the unfloored wall band, which the player would otherwise look
	# straight down into.
	_box(
		parent, "WindowApron",
		_at(through, base + SILL_HEIGHT * 0.5),
		_size(CELL, SILL_HEIGHT, depth, tangent_is_x),
		reveal
	)
	var lintel_top := STOREY - SLAB
	_box(
		parent, "WindowLintel",
		_at(through, base + (head + lintel_top) * 0.5),
		_size(CELL, lintel_top - head, depth, tangent_is_x),
		reveal
	)
	var jamb := (CELL - OPENING_WIDTH) * 0.5
	var along := Vector3(1.0, 0.0, 0.0) if tangent_is_x else Vector3(0.0, 0.0, 1.0)
	for side: float in [-1.0, 1.0]:
		_box(
			parent, "WindowJamb",
			_at(through + along * side * (CELL - jamb) * 0.5, base + (SILL_HEIGHT + head) * 0.5),
			_size(jamb, head - SILL_HEIGHT, depth, tangent_is_x),
			reveal
		)

	# Three raised stones frame the opening on the facade. Keep the centre
	# empty: a single full-size surround box here would look correct from far
	# away, but it would also occlude both the view and the moonlight.
	var trim := 0.16
	var opening_middle := base + (SILL_HEIGHT + head) * 0.5
	for side: float in [-1.0, 1.0]:
		_box(
			parent, "WindowSurround",
			_at(
				outer_face + outward * 0.06
					+ along * side * (OPENING_WIDTH + trim) * 0.5,
				opening_middle
			),
			_size(trim, head - SILL_HEIGHT + trim * 2.0, 0.12, tangent_is_x),
			surround
		)
	_box(
		parent, "WindowSurround",
		_at(outer_face + outward * 0.06, base + head + trim * 0.5),
		_size(OPENING_WIDTH + trim * 2.0, trim, 0.12, tangent_is_x),
		surround
	)
	_box(
		parent, "WindowSill",
		_at(outer_face + outward * 0.11, base + SILL_HEIGHT - 0.05),
		_size(CELL + 0.1, 0.14, 0.34, tangent_is_x),
		_material(T_SILL, 1.0, Color(0.44, 0.44, 0.42))
	)

	if boarded:
		_board_over(parent, inner_face + inward * 0.06, base, tangent_is_x, along)
	else:
		_glaze(parent, inner_face + inward * 0.06, base, tangent_is_x, along)

	_add_moonlight(parent, outer_face + inward * 0.45, base, inward)


## The kit wall panel is the only visible part of a wall body; the collision
## shape beside it is what actually stops anything, and it stays.
func _hide_panels(wall: Node3D) -> void:
	for child: Node in wall.get_children():
		if child is CollisionShape3D:
			continue
		var visual := child as Node3D
		if visual:
			visual.visible = false


func _glaze(
	parent: Node3D, plane: Vector3, base: float, tangent_is_x: bool, along: Vector3
) -> void:
	var timber := _material(T_FRAME, 0.9, Color(0.34, 0.31, 0.28))
	var height := HEAD_HEIGHT - SILL_HEIGHT
	var middle := base + (SILL_HEIGHT + HEAD_HEIGHT) * 0.5
	for edge: float in [SILL_HEIGHT - 0.05, HEAD_HEIGHT + 0.05]:
		_box(
			parent, "WindowFrame", _at(plane, base + edge),
			_size(OPENING_WIDTH + 0.2, 0.1, 0.12, tangent_is_x), timber
		)
	for side: float in [-1.0, 1.0]:
		_box(
			parent, "WindowFrame",
			_at(plane + along * side * (OPENING_WIDTH + 0.1) * 0.5, middle),
			_size(0.1, height + 0.2, 0.12, tangent_is_x), timber
		)
	# The mullion and transom are what actually draw the cross on the floor
	# when the moonlight behind them is shadowed.
	_box(parent, "WindowMullion", _at(plane, middle), _size(0.07, height, 0.09, tangent_is_x), timber)
	_box(
		parent, "WindowTransom", _at(plane, middle),
		_size(OPENING_WIDTH, 0.07, 0.09, tangent_is_x), timber
	)

	_box(
		parent, "WindowPane", _at(plane, middle),
		_size(OPENING_WIDTH, height, 0.03, tangent_is_x), _glass(), Vector3.ZERO, false
	)


func _board_over(
	parent: Node3D, plane: Vector3, base: float, tangent_is_x: bool, along: Vector3
) -> void:
	var board := _material(T_BOARD, 0.8, Color(0.33, 0.3, 0.27))
	var middle := base + (SILL_HEIGHT + HEAD_HEIGHT) * 0.5
	var tilts: Array[float] = [-0.14, 0.09, -0.05]
	for index: int in tilts.size():
		var offset := (index - 1) * 0.46
		var rotation := Vector3(0.0, 0.0, tilts[index]) if tangent_is_x \
			else Vector3(tilts[index], 0.0, 0.0)
		_box(
			parent, "WindowBoard", _at(plane, middle + offset),
			_size(OPENING_WIDTH + 0.24, 0.24, 0.06, tangent_is_x), board, rotation
		)
	# A plank is missing at the bottom, which is the gap the moon comes through.
	_box(
		parent, "WindowBoardStub",
		_at(plane + along * 0.42, base + SILL_HEIGHT + 0.18),
		_size(0.4, 0.22, 0.06, tangent_is_x), board
	)


func _add_moonlight(parent: Node3D, at: Vector3, base: float, inward: Vector3) -> void:
	var light := SpotLight3D.new()
	_index += 1
	light.name = "Moonlight_%04d" % _index
	light.position = Vector3(at.x, base + 1.85, at.z)
	# Down the reveal and onto the floor, the way a low moon would come in.
	light.basis = Basis.looking_at((inward - Vector3.UP * 0.62).normalized())
	light.light_color = moonlight_colour
	light.light_energy = moonlight_energy
	light.light_specular = 0.12
	light.light_volumetric_fog_energy = 1.1
	light.spot_range = 11.0
	light.spot_angle = 38.0
	light.spot_angle_attenuation = 1.3
	light.shadow_enabled = false
	light.shadow_bias = 0.02
	light.shadow_normal_bias = 1.5
	light.visible = false
	parent.add_child(light)
	_lights.append(light)


# --- keeping the light affordable ---------------------------------------------

## Windows outnumber the lights a scene can afford, so the villa only ever runs
## the nearest few and shadows fewer still. Everything else is dark glass,
## which at these fog densities is what a distant window looks like anyway.
func _process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = 0.35
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var eye := camera.global_position
	var ordered := _lights.duplicate()
	ordered.sort_custom(func(a: SpotLight3D, b: SpotLight3D) -> bool:
		return (
			a.global_position.distance_squared_to(eye)
			< b.global_position.distance_squared_to(eye)
		)
	)
	for index: int in ordered.size():
		var light := ordered[index] as SpotLight3D
		light.visible = index < active_lights
		light.shadow_enabled = index < mini(active_lights, shadowed_lights)


# --- primitives ---------------------------------------------------------------

## Composes a world-space box size from measurements taken along the wall, up,
## and through it, so every piece above can be written once for all four faces.
func _size(along: float, up: float, through: float, tangent_is_x: bool) -> Vector3:
	return Vector3(along, up, through) if tangent_is_x else Vector3(through, up, along)


func _at(plane: Vector3, y: float) -> Vector3:
	return Vector3(plane.x, y, plane.z)


func _box(
	_parent: Node3D,
	box_name: String,
	centre: Vector3,
	size: Vector3,
	material: Material,
	rotation: Vector3 = Vector3.ZERO,
	cast_shadow: bool = true
) -> void:
	_index += 1
	_logical_counts[box_name] = int(_logical_counts.get(box_name, 0)) + 1
	var key := "%d|%s" % [material.get_instance_id(), cast_shadow]
	if not _box_batches.has(key):
		_box_batches[key] = {
			"material": material,
			"cast_shadow": cast_shadow,
			"transforms": [],
		}
	var batch: Dictionary = _box_batches[key]
	var basis := Basis.from_euler(rotation) * Basis.from_scale(size)
	(batch["transforms"] as Array).append(Transform3D(basis, centre))


func _flush_box_batches(parent: Node3D) -> void:
	var keys: Array = _box_batches.keys()
	keys.sort()
	for key: String in keys:
		var batch: Dictionary = _box_batches[key]
		var transforms: Array = batch["transforms"]
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = batch["material"] as Material
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		for index: int in transforms.size():
			multimesh.set_instance_transform(index, transforms[index] as Transform3D)
		var instance := MultiMeshInstance3D.new()
		instance.name = "WindowBatch_%02d" % parent.get_child_count()
		instance.multimesh = multimesh
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if bool(batch["cast_shadow"])
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		parent.add_child(instance)
	_box_batches.clear()


func _logical_mesh_count() -> int:
	var total := 0
	for count: Variant in _logical_counts.values():
		total += int(count)
	return total


func _material(
	path: String, tile: float, tint: Color, roughness: float = 0.93
) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [path, tile, tint]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(path)
	material.albedo_color = tint
	material.roughness = roughness
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / maxf(tile, 0.01)
	_materials[key] = material
	return material


func _glass() -> StandardMaterial3D:
	if _materials.has("glass"):
		return _materials["glass"]
	var material := StandardMaterial3D.new()
	# Old, dirty glass: enough of a sheen to catch the flashlight, not enough
	# to hide what is outside.
	material.albedo_color = Color(0.3, 0.38, 0.45, 0.14)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.12
	material.metallic = 0.4
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials["glass"] = material
	return material

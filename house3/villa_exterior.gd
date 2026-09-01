extends Node3D
class_name VillaExterior

## Night-time suburban surroundings for the Vanh Dai villa.
##
## villa_house.gd only builds the villa itself plus a flat 24 m ground apron,
## so everything the player sees once they step out of E01-E04 - the ring road
## the estate is named after, the boundary wall and gate, the front court, the
## service yard behind the kitchen door, the back garden and the dead treeline
## that closes off the horizon - is built here.
##
## Every surface is dressed with Craig Snedeker's CC0 "Classic64 Asset Library"
## textures in assets/map. The pack ships its models as .blend files and
## project.godot has `import/blender/enabled=false`, so its meshes cannot be
## instanced: the geometry below is primitives wearing the pack's materials.
##
## Two rules keep this inside the villa's runtime budget - villa_boot_smoke.gd
## gives the whole map 60 s to build *and* bake its navmesh:
##
##   * Ground skins are decoration laid a centimetre over the site slabs
##     VillaHouse already built, so they carry no collider of their own.
##   * Nothing outside the site aprons (x -24..104, z -24..84) is ever given a
##     collider. villa_main.gd bakes navigation from static colliders and
##     Recast voxelises exactly their bounding box, so a backdrop house with a
##     collider would enlarge the bake for scenery no agent can ever reach.

# --- Classic64 Asset Library (CC0, Craig Snedeker) ---------------------------

const PACK := "res://assets/map/- Classic 64 Asset Pack 0.6/"

const T_LAWN := PACK + "Ground/Materials/grass_dead_02.png"
const T_LITTER := PACK + "Ground/Materials/grass_dead_03.png"
const T_STONY_GRASS := PACK + "Ground/Materials/rocks_grass_01.png"
const T_DIRT := PACK + "Ground/Materials/dirt_muddy_1.jpg"
const T_GRAVEL := PACK + "Ground/Materials/gravel_11.jpg"
const T_FLAGSTONE := PACK + "Ground/Materials/stone_path_grass_01.jpg"
const T_ASPHALT := PACK + "Road/Materials/road_01.png"
const T_KERB := PACK + "Concrete/Materials/concrete_floor_03.jpg"
const T_CONCRETE := PACK + "Concrete/Materials/concrete_wall_02.jpg"
const T_PLASTER := PACK + "Walls/Materials/wall_plaster_pealing.png"
const T_BRICK := PACK + "Bricks/Materials/brick_medium_mossy.png"
const T_SIDING := PACK + "Walls/Materials/siding_gray_01.jpg"
const T_SIDING_WOOD := PACK + "Walls/Materials/siding_wood_03.jpg"
const T_SHINGLE := PACK + "Roof/Materials/shingles_old_01.jpg"
const T_PLANK := PACK + "Wood/Materials/wood_plank_charred.jpg"
const T_TIMBER := PACK + "Wood/Materials/wood_rustic_3.png"
const T_POLE := PACK + "Wood/Materials/wood_pole_01.jpg"
const T_BARK := PACK + "Nature/Materials/bark_3.png"
const T_BARK_DARK := PACK + "Nature/Materials/bark_05.png"
const T_HEDGE := PACK + "Nature/Materials/bush_03.png"
const T_GRASS_CLUMP := PACK + "Nature/Materials/grass_bush_2.png"
const T_FALLEN_BRANCH := PACK + "Nature/Materials/branches_leaves.png"
const T_TREE_CROWN := PACK + "Nature/Materials/branches_small_leaves.png"
const T_RUST := PACK + "Metal/Materials/metal_rusty_05.jpg"
const T_GALVANISED := PACK + "Metal/Materials/metal_galvanized_silver.png"
const T_IRON := PACK + "Metal/Materials/metal_painted_gray.png"
const T_STONE := PACK + "Rocks/Materials/rock_wall_02.jpg"
const T_CRATE := PACK + "Misc/Materials/crate_old_01.jpg"
const T_TARP := PACK + "Misc/Materials/tarp_01.jpg"
const T_CHAINLINK := PACK + "Misc/Materials/fence_chain_rusty.png"
const T_LINEN := PACK + "Misc/Colors/Color_OffWhite.png"
const T_WINDOW_BOARDED := PACK + "Windows/Materials/window_boarded.png"
const T_WINDOW_DARK := PACK + "Windows/Materials/window_old_02.jpg"
const T_SIGN_TRESPASS := PACK + "Signs/Materials/sign_notrespassing_01.png"
const T_SIGN_WARNING := PACK + "Signs/Materials/sign_warning_01.png"
const T_GUARD_RAIL := PACK + "Road/Materials/guard_rail.png"

# --- site metrics (mirror house3/villa_house.gd _build_site) -----------------

## The villa footprint. Its own geometry owns everything inside this.
const HOUSE_MIN := Vector2(0.0, 0.0)
const HOUSE_MAX := Vector2(80.0, 60.0)
## The ground apron VillaHouse lays around the footprint; also the outer limit
## of anything this scene is allowed to give a collider to.
const SITE_MIN := Vector2(-24.0, -24.0)
const SITE_MAX := Vector2(104.0, 84.0)

## The estate wall. "Vanh Dai" is the ring road it fronts onto.
const WALL_MIN := Vector2(-16.0, -16.0)
const WALL_MAX := Vector2(96.0, 76.0)
const WALL_HEIGHT := 2.4
const WALL_THICKNESS := 0.45
const WALL_PANEL := 8.0
## Gap in the north wall, centred on entrance 01.
const GATE_MIN := 34.0
const GATE_MAX := 46.0

const ROAD_NEAR := -17.6
const ROAD_FAR := -22.8
const KERB_Z := -17.4
const PAVEMENT_Z := -16.3
const PAVEMENT_Y := 0.16

## The open cellar trench, from villa_house.gd _trench_rect(): the west apron
## is missing across this band and the ramp surfaces at TRENCH_FAR_X.
const TRENCH_Z0 := 34.0
const TRENCH_Z1 := 38.0
const TRENCH_FAR_X := -13.5

## Ground skins sit above the site slabs (top y = 0) and below the villa's own
## floor tiles, so nothing z-fights and nothing forms a step.
const Y_LAWN := 0.01
const Y_PAVING := 0.02

## Fixed so every client in a multiplayer session dresses the garden the same
## way; the layout is decoration, and none of it is replicated.
const LAYOUT_SEED := 0x4E454830

@export var build_backdrop: bool = true
@export var build_atmosphere: bool = true

var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}
var _index: int = 0
var _flicker_lights: Array[Light3D] = []
var _flicker_energy: Array[float] = []
var _time: float = 0.0
var _batches: Dictionary = {}
var _logical_counts: Dictionary = {}
var _batch_root: Node3D


func _ready() -> void:
	if has_node("Generated"):
		return
	_rng.seed = LAYOUT_SEED
	var root := _container(self, "Generated")
	root.add_to_group("villa_exterior")
	_batch_root = _container(root, "BatchedGeometry")

	_build_terrain(_container(root, "Terrain"))
	_build_road(_container(root, "RingRoad"))
	_build_boundary(_container(root, "Boundary"))
	_build_front_court(_container(root, "FrontCourt"))
	_build_service_yard(_container(root, "ServiceYard"))
	_build_cellar_trench(_container(root, "CellarTrench"))
	_build_back_garden(_container(root, "BackGarden"))
	if build_backdrop:
		_build_backdrop(_container(root, "Backdrop"))
	_flush_batches()
	root.set_meta("logical_counts", _logical_counts.duplicate(true))
	root.set_meta("logical_mesh_count", _logical_mesh_count())
	root.set_meta("render_batch_count", _batch_root.get_child_count())
	if build_atmosphere:
		_build_atmosphere(_container(root, "Atmosphere"))

	set_process(not _flicker_lights.is_empty())


## A failing sodium lamp is the one thing out here that moves, so it is worth
## the single _process. The waveform is a product of two primes rather than
## noise: no allocation, and identical on every client.
func _process(delta: float) -> void:
	_time += delta
	for index: int in _flicker_lights.size():
		var wave := (
			sin(_time * 13.7 + index * 2.1) * sin(_time * 5.3 + index * 0.7)
		)
		_flicker_lights[index].light_energy = (
			_flicker_energy[index] * clampf(0.5 + 0.6 * wave, 0.04, 1.15)
		)


# --- primitives ---------------------------------------------------------------

func _container(parent: Node3D, container_name: String) -> Node3D:
	var container := Node3D.new()
	container.name = container_name
	parent.add_child(container)
	return container


## Textures in this pack are 64-128 px and meant to be seen as pixels, so they
## are sampled nearest. Mapping is world triplanar: a run of wall panels or a
## row of ground quads then shares one material *and* one continuous texture,
## whatever each piece's size or rotation.
func _material(
	path: String,
	tile: float,
	tint: Color = Color.WHITE,
	roughness: float = 0.95,
	alpha_cut: bool = false
) -> StandardMaterial3D:
	var key := "%s|%.2f|%s|%.2f|%s" % [path, tile, tint, roughness, alpha_cut]
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
	if alpha_cut:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	return material


## For a texture that has to appear exactly once across the surface it is on -
## a sign face, a boarded window, a hanging sheet - which triplanar mapping
## cannot do.
func _decal_material(
	path: String, tint: Color = Color.WHITE, alpha_cut: bool = true
) -> StandardMaterial3D:
	var key := "decal|%s|%s|%s" % [path, tint, alpha_cut]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(path)
	material.albedo_color = tint
	material.roughness = 0.9
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha_cut:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.4
	_materials[key] = material
	return material


## A flat skin over the site slabs. Two triangles, no collider: the ground the
## player actually stands on is the villa's own apron, a centimetre below.
func _ground(
	parent: Node3D,
	skin_name: String,
	area: Rect2,
	y: float,
	material: Material,
	rotation_y: float = 0.0
) -> void:
	var basis := Basis.from_euler(Vector3(0.0, rotation_y, 0.0)) \
		* Basis.from_scale(Vector3(area.size.x, 1.0, area.size.y))
	_queue_batch(
		"plane", parent, skin_name,
		Transform3D(basis, Vector3(area.get_center().x, y, area.get_center().y)),
		material, false
	)


func _box(
	parent: Node3D,
	box_name: String,
	centre: Vector3,
	size: Vector3,
	material: Material,
	collide: bool = false,
	rotation: Vector3 = Vector3.ZERO
) -> void:
	_record_logical(box_name)
	if not collide:
		_queue_batch(
			"box", parent, box_name,
			Transform3D(Basis.from_euler(rotation) * Basis.from_scale(size), centre),
			material, true, false
		)
		return

	var body := _static_root(parent, box_name, centre, rotation)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)
	body.add_child(instance)


func _cylinder(
	parent: Node3D,
	cylinder_name: String,
	centre: Vector3,
	radius: float,
	height: float,
	material: Material,
	collide: bool = false,
	rotation: Vector3 = Vector3.ZERO,
	segments: int = 10,
	basis_override: Basis = Basis.IDENTITY
) -> void:
	_record_logical(cylinder_name)
	if not collide:
		var orientation := basis_override if basis_override != Basis.IDENTITY else Basis.from_euler(rotation)
		_queue_batch(
			"cylinder_%d" % segments, parent, cylinder_name,
			Transform3D(
				orientation * Basis.from_scale(Vector3(radius, height * 0.5, radius)),
				centre
			),
			material, true, false, segments
		)
		return

	var body := _static_root(parent, cylinder_name, centre, rotation)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 0
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)
	body.add_child(instance)


## Colliders are only ever legitimate inside the aprons - see the file header.
func _static_root(
	parent: Node3D, body_name: String, centre: Vector3, rotation: Vector3
) -> StaticBody3D:
	assert(
		centre.x >= SITE_MIN.x and centre.x <= SITE_MAX.x
		and centre.z >= SITE_MIN.y and centre.z <= SITE_MAX.y,
		"%s would put a collider outside the villa site and grow the navmesh bake."
			% body_name
	)
	var body := StaticBody3D.new()
	_index += 1
	body.name = "%s_%04d" % [body_name, _index]
	body.position = centre
	body.rotation = rotation
	parent.add_child(body)
	return body


## A bare collision box for something whose visible shell is assembled from
## loose panels - one shape for the vehicle or the shed, rather than one per
## panel, which is also one collider for Recast instead of a dozen.
func _collider(
	parent: Node3D,
	body_name: String,
	centre: Vector3,
	size: Vector3,
	rotation: Vector3 = Vector3.ZERO
) -> StaticBody3D:
	var body := _static_root(parent, body_name, centre, rotation)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)
	return body


func _quad(
	parent: Node3D,
	quad_name: String,
	centre: Vector3,
	size: Vector2,
	material: Material,
	rotation: Vector3 = Vector3.ZERO
) -> void:
	var basis := Basis.from_euler(rotation) * Basis.from_scale(Vector3(size.x, size.y, 1.0))
	_queue_batch("quad", parent, quad_name, Transform3D(basis, centre), material, false)


## A deliberately low-poly stone. Small ones are only visual clutter; the few
## large boulders get one coarse box collider so they feel solid without making
## Recast process every pebble in the lawn.
func _rock(
	parent: Node3D,
	at: Vector3,
	scale: Vector3,
	material: Material,
	collide: bool = false
) -> Node3D:
	_record_logical("GardenBoulder" if collide else "GardenRock")
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	instance.scale = scale
	instance.rotation = Vector3(
		_rng.randf_range(-0.18, 0.18),
		_rng.randf_range(0.0, TAU),
		_rng.randf_range(-0.18, 0.18)
	)
	if not collide:
		_index += 1
		instance.name = "GardenRock_%04d" % _index
		instance.position = at
		parent.add_child(instance)
		return instance

	var body := _static_root(parent, "GardenBoulder", at, Vector3.ZERO)
	var shape := BoxShape3D.new()
	shape.size = scale * Vector3(1.65, 1.45, 1.65)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)
	body.add_child(instance)
	return body


func _crossed_cards(
	parent: Node3D,
	card_name: String,
	at: Vector3,
	size: Vector2,
	material: Material,
	yaw: float = 0.0
) -> void:
	for offset: float in [0.0, PI * 0.5]:
		_quad(parent, card_name, at, size, material, Vector3(0.0, yaw + offset, 0.0))


## Static decoration uses a handful of shared unit meshes. This turns more
## than a thousand tiny MeshInstance3D draw submissions into a few dozen
## MultiMesh batches without touching any authored collider or navigation
## surface.
func _queue_batch(
	kind: String,
	parent: Node3D,
	logical_name: String,
	local_transform: Transform3D,
	material: Material,
	cast_shadow: bool,
	record_count: bool = true,
	segments: int = 10
) -> void:
	if record_count:
		_record_logical(logical_name)
	var key := "%s|%d|%s" % [kind, material.get_instance_id(), cast_shadow]
	if not _batches.has(key):
		_batches[key] = {
			"kind": kind,
			"material": material,
			"cast_shadow": cast_shadow,
			"segments": segments,
			"transforms": [],
		}
	var relative := _batch_root.global_transform.affine_inverse() \
		* parent.global_transform * local_transform
	((_batches[key] as Dictionary)["transforms"] as Array).append(relative)


func _record_logical(logical_name: String) -> void:
	_logical_counts[logical_name] = int(_logical_counts.get(logical_name, 0)) + 1


func _logical_mesh_count() -> int:
	var total := 0
	for count: Variant in _logical_counts.values():
		total += int(count)
	return total


func _flush_batches() -> void:
	var keys: Array = _batches.keys()
	keys.sort()
	for key: String in keys:
		var batch: Dictionary = _batches[key]
		var transforms: Array = batch["transforms"]
		var mesh: PrimitiveMesh
		match String(batch["kind"]).get_slice("_", 0):
			"box":
				var box := BoxMesh.new()
				box.size = Vector3.ONE
				mesh = box
			"plane":
				var plane := PlaneMesh.new()
				plane.size = Vector2.ONE
				mesh = plane
			"quad":
				var quad := QuadMesh.new()
				quad.size = Vector2.ONE
				mesh = quad
			"cylinder":
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = 1.0
				cylinder.bottom_radius = 1.0
				cylinder.height = 2.0
				cylinder.radial_segments = int(batch["segments"])
				cylinder.rings = 0
				mesh = cylinder
		mesh.material = batch["material"] as Material
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		for index: int in transforms.size():
			multimesh.set_instance_transform(index, transforms[index] as Transform3D)
		var instance := MultiMeshInstance3D.new()
		instance.name = "ExteriorBatch_%03d" % _batch_root.get_child_count()
		instance.multimesh = multimesh
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if bool(batch["cast_shadow"])
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		_batch_root.add_child(instance)
	_batches.clear()


## An orthonormal basis whose +Y runs along `up`; lets a cylinder be a branch
## or a leaning post without a pivot node per piece.
static func _basis_along(up: Vector3) -> Basis:
	var y := up.normalized()
	var reference := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := reference.cross(y).normalized()
	return Basis(x, y, x.cross(y))


func _random_point(area: Rect2) -> Vector2:
	return Vector2(
		_rng.randf_range(area.position.x, area.end.x),
		_rng.randf_range(area.position.y, area.end.y)
	)


# --- ground -------------------------------------------------------------------

func _build_terrain(parent: Node3D) -> void:
	var lawn := _material(T_LAWN, 5.0, Color(0.6, 0.64, 0.56))
	var aprons: Array[Rect2] = [
		Rect2(SITE_MIN.x, SITE_MIN.y, 128.0, 24.0),
		Rect2(SITE_MIN.x, HOUSE_MAX.y, 128.0, 24.0),
		Rect2(HOUSE_MAX.x, HOUSE_MIN.y, 24.0, 60.0),
		# Split around the open cellar trench, which is a hole in the apron and
		# must not be skinned over.
		Rect2(SITE_MIN.x, HOUSE_MIN.y, 24.0, TRENCH_Z0 - 0.6),
		Rect2(SITE_MIN.x, TRENCH_Z1 + 0.6, 24.0, HOUSE_MAX.y - TRENCH_Z1 - 0.6),
	]
	for area: Rect2 in aprons:
		_ground(parent, "Lawn", area, Y_LAWN, lawn)

	# villa_house.gd asks for its GroundWestFar slab with a negative-width
	# Rect2, so _ground_slab() drops it and the strip between the boundary wall
	# and the head of the cellar ramp has no floor at all. The wall needs
	# something to stand on, and the player needs somewhere to land.
	_box(
		parent,
		"TrenchHeadGround",
		Vector3((WALL_MIN.x - 0.8 + TRENCH_FAR_X) * 0.5, -0.15, (TRENCH_Z0 + TRENCH_Z1) * 0.5),
		Vector3(TRENCH_FAR_X - WALL_MIN.x + 0.8, 0.3, TRENCH_Z1 - TRENCH_Z0 + 1.4),
		_material(T_DIRT, 3.0, Color(0.45, 0.44, 0.4)),
		true
	)

	# Worn patches break up a texture that would otherwise tile across 108 m of
	# garden in one unbroken grid.
	var dirt := _material(T_DIRT, 3.5, Color(0.44, 0.42, 0.37))
	for _patch: int in 18:
		var area: Rect2 = aprons[_rng.randi() % aprons.size()]
		var size := Vector2(_rng.randf_range(4.0, 11.0), _rng.randf_range(4.0, 11.0))
		var at := _random_point(area.grow(-6.0)) if area.size.x > 14.0 and area.size.y > 14.0 \
			else area.get_center()
		_ground(
			parent,
			"WornPatch",
			Rect2(at - size * 0.5, size),
			Y_LAWN + 0.004,
			dirt,
			_rng.randf_range(0.0, TAU)
		)

	_add_ground_scatter(parent)


## The large lawn skins establish colour, while these small overlays and cards
## provide the readable ground detail the flashlight catches: dead leaf mats,
## stony patches, tufts, fallen branches and irregular rocks. They stay outside
## door approaches and the cellar trench by drawing only from safe garden beds.
func _add_ground_scatter(parent: Node3D) -> void:
	var beds: Array[Rect2] = [
		Rect2(-14.0, -13.0, 34.0, 10.0),
		Rect2(24.0, -12.0, 10.0, 6.0),
		Rect2(46.0, -12.0, 10.0, 6.0),
		Rect2(60.0, -13.0, 34.0, 10.0),
		Rect2(-14.0, 2.0, 10.0, 29.0),
		Rect2(-14.0, 42.0, 10.0, 18.0),
		Rect2(84.0, 41.0, 10.0, 19.0),
		Rect2(-10.0, 68.0, 38.0, 6.0),
		Rect2(56.0, 68.0, 38.0, 6.0),
	]
	var litter := _material(T_LITTER, 2.2, Color(0.48, 0.45, 0.38))
	var stony := _material(T_STONY_GRASS, 2.0, Color(0.48, 0.49, 0.45))
	for index: int in 28:
		var at := _random_point(beds[index % beds.size()].grow(-0.8))
		var size := Vector2(_rng.randf_range(1.4, 3.8), _rng.randf_range(1.0, 2.8))
		_ground(
			parent,
			"LeafLitter" if index % 3 != 0 else "StonyPatch",
			Rect2(at - size * 0.5, size),
			Y_LAWN + 0.009,
			litter if index % 3 != 0 else stony,
			_rng.randf_range(0.0, TAU)
		)

	var grass := _decal_material(T_GRASS_CLUMP, Color(0.38, 0.42, 0.32))
	for index: int in 96:
		var at := _random_point(beds[index % beds.size()].grow(-0.5))
		var height := _rng.randf_range(0.65, 1.35)
		_crossed_cards(
			parent, "DeadGrass", Vector3(at.x, height * 0.5, at.y),
			Vector2(_rng.randf_range(0.75, 1.3), height), grass,
			_rng.randf_range(0.0, TAU)
		)

	var branches := _decal_material(T_FALLEN_BRANCH, Color(0.42, 0.4, 0.32))
	for index: int in 16:
		var at := _random_point(beds[index % beds.size()].grow(-0.7))
		_quad(
			parent, "FallenBranch", Vector3(at.x, Y_LAWN + 0.025, at.y),
			Vector2(_rng.randf_range(0.8, 1.5), _rng.randf_range(0.65, 1.2)), branches,
			Vector3(-PI * 0.5, _rng.randf_range(0.0, TAU), 0.0)
		)

	var stone := _material(T_STONE, 0.85, Color(0.42, 0.43, 0.41))
	for index: int in 30:
		var at := _random_point(beds[index % beds.size()].grow(-0.8))
		var radius := _rng.randf_range(0.18, 0.58)
		var large := index % 10 == 0
		if large:
			radius = _rng.randf_range(0.75, 1.15)
		var scale := Vector3(radius, radius * _rng.randf_range(0.45, 0.72), radius * _rng.randf_range(0.75, 1.25))
		_rock(parent, Vector3(at.x, scale.y * 0.62, at.y), scale, stone, large)

	# Fixed clusters frame the major views, so procedural scatter can never
	# accidentally leave the gate or the back garden reading as an empty plane.
	for at: Vector2 in [
		Vector2(-8.5, -8.0), Vector2(13.0, -10.5), Vector2(68.0, -9.0),
		Vector2(88.0, -7.5), Vector2(-9.0, 54.0), Vector2(91.0, 52.0),
		Vector2(8.0, 71.0), Vector2(72.0, 71.5),
	]:
		var scale := Vector3(
			_rng.randf_range(0.7, 1.25),
			_rng.randf_range(0.45, 0.8),
			_rng.randf_range(0.75, 1.35)
		)
		_rock(parent, Vector3(at.x, scale.y * 0.62, at.y), scale, stone, true)

	var shrub := _decal_material(T_HEDGE, Color(0.3, 0.35, 0.25))
	for at: Vector2 in [
		Vector2(18.0, -5.0), Vector2(62.0, -4.5), Vector2(-8.0, 15.0),
		Vector2(-7.0, 51.0), Vector2(88.0, 47.0), Vector2(19.0, 70.0),
		Vector2(61.0, 70.5), Vector2(88.0, 67.0),
	]:
		var height := _rng.randf_range(1.1, 1.8)
		_crossed_cards(
			parent, "LeafyShrub", Vector3(at.x, height * 0.5, at.y),
			Vector2(_rng.randf_range(1.4, 2.2), height), shrub,
			_rng.randf_range(0.0, TAU)
		)


# --- the ring road ------------------------------------------------------------

func _build_road(parent: Node3D) -> void:
	var asphalt := _material(T_ASPHALT, 4.0, Color(0.46, 0.48, 0.5))
	var kerb := _material(T_KERB, 2.0, Color(0.5, 0.52, 0.5))
	_ground(
		parent,
		"Asphalt",
		Rect2(SITE_MIN.x, ROAD_FAR, 128.0, ROAD_NEAR - ROAD_FAR),
		Y_PAVING,
		asphalt
	)

	var centre_line := _material(T_KERB, 1.0, Color(0.62, 0.6, 0.5))
	for index: int in 15:
		_box(
			parent,
			"RoadDash",
			Vector3(SITE_MIN.x + 4.0 + index * 8.5, Y_PAVING + 0.004, (ROAD_NEAR + ROAD_FAR) * 0.5),
			Vector3(2.6, 0.008, 0.18),
			centre_line
		)

	# The kerb is the one raised edge out here, so it is also the one piece of
	# road furniture that needs a collider.
	for run: Vector2 in [Vector2(SITE_MIN.x, GATE_MIN), Vector2(GATE_MAX, SITE_MAX.x)]:
		_box(
			parent,
			"Kerb",
			Vector3((run.x + run.y) * 0.5, PAVEMENT_Y * 0.5, KERB_Z - 0.15),
			Vector3(run.y - run.x, PAVEMENT_Y, 0.3),
			kerb,
			true
		)
	_ground(
		parent,
		"Pavement",
		Rect2(SITE_MIN.x, KERB_Z, 128.0, PAVEMENT_Z - KERB_Z),
		PAVEMENT_Y,
		kerb
	)

	# Four lamps for 128 m of road, and only two of them still work.
	_add_street_lamp(parent, Vector2(6.0, KERB_Z - 0.55), true, false)
	_add_street_lamp(parent, Vector2(30.0, KERB_Z - 0.55), true, true)
	_add_street_lamp(parent, Vector2(58.0, KERB_Z - 0.55), false, false)
	_add_street_lamp(parent, Vector2(86.0, KERB_Z - 0.55), true, false)

	_add_power_line(parent)
	_add_guard_rail(parent)


func _add_street_lamp(parent: Node3D, at: Vector2, lit: bool, failing: bool) -> void:
	var metal := _material(T_IRON, 1.2, Color(0.34, 0.35, 0.36), 0.6)
	var rust := _material(T_RUST, 1.0, Color(0.45, 0.4, 0.35), 0.8)
	_cylinder(
		parent, "LampBase", Vector3(at.x, 0.2, at.y), 0.3, 0.4,
		_material(T_CONCRETE, 0.8, Color(0.45, 0.46, 0.45)), true, Vector3.ZERO, 8
	)
	_cylinder(parent, "LampPole", Vector3(at.x, 3.05, at.y), 0.11, 5.3, metal, true, Vector3.ZERO, 8)
	# The arm reaches out over the carriageway, as a real one would.
	_box(
		parent, "LampArm",
		Vector3(at.x, 5.6, at.y - 1.1), Vector3(0.12, 0.12, 2.2), metal
	)
	var head := Vector3(at.x, 5.48, at.y - 2.1)
	_box(parent, "LampHead", head, Vector3(0.46, 0.2, 0.86), rust)
	if not lit:
		# A dead lamp is still worth building: it tells the player the estate
		# has been dark for a while.
		_box(
			parent, "LampGlassDead", head + Vector3(0.0, -0.11, 0.0),
			Vector3(0.36, 0.03, 0.7), _material(T_CONCRETE, 0.5, Color(0.18, 0.18, 0.17))
		)
		return

	var glass := _material(T_CONCRETE, 0.5, Color(1.0, 0.82, 0.55))
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.72, 0.38)
	glass.emission_energy_multiplier = 1.6
	_box(
		parent, "LampGlass", head + Vector3(0.0, -0.11, 0.0),
		Vector3(0.36, 0.03, 0.7), glass
	)

	var light := SpotLight3D.new()
	light.name = "LampLight_%04d" % _index
	light.position = head + Vector3(0.0, -0.16, 0.0)
	light.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = 2.6
	light.light_volumetric_fog_energy = 1.4
	light.spot_range = 15.0
	light.spot_angle = 58.0
	light.spot_angle_attenuation = 1.4
	light.shadow_enabled = false
	parent.add_child(light)
	if failing:
		_flicker_lights.append(light)
		_flicker_energy.append(light.light_energy)


## Poles and a slack span across the far verge. The wires are the only thing
## above the treeline the player can use to tell which way the road runs.
func _add_power_line(parent: Node3D) -> void:
	var timber := _material(T_POLE, 2.0, Color(0.4, 0.37, 0.33))
	var wire := _material(T_IRON, 1.0, Color(0.08, 0.08, 0.09), 0.7)
	var poles: Array[float] = [-14.0, 26.0, 66.0, 100.0]
	for x: float in poles:
		_cylinder(
			parent, "PowerPole", Vector3(x, 4.1, ROAD_FAR - 0.9), 0.19, 8.2,
			timber, true, Vector3(0.0, 0.0, _rng.randf_range(-0.03, 0.03)), 8
		)
		_box(
			parent, "PoleCrossArm", Vector3(x, 7.5, ROAD_FAR - 0.9),
			Vector3(2.4, 0.14, 0.14), timber
		)
	for index: int in poles.size() - 1:
		var from := Vector3(poles[index], 7.4, ROAD_FAR - 0.9)
		var to := Vector3(poles[index + 1], 7.4, ROAD_FAR - 0.9)
		# Three chords stand in for the catenary; a straight span between two
		# 40 m poles reads as a cable car, not a power line.
		var sag: Array[float] = [0.0, -1.1, -1.5, -1.1, 0.0]
		for segment: int in sag.size() - 1:
			var a := from.lerp(to, float(segment) / (sag.size() - 1)) + Vector3.UP * sag[segment]
			var b := from.lerp(to, float(segment + 1) / (sag.size() - 1)) \
				+ Vector3.UP * sag[segment + 1]
			_cylinder(
				parent, "PowerWire", (a + b) * 0.5, 0.035, a.distance_to(b), wire,
				false, Vector3.ZERO, 10, _basis_along(b - a)
			)


func _add_guard_rail(parent: Node3D) -> void:
	var rail := _decal_material(T_GUARD_RAIL)
	var post := _material(T_IRON, 0.8, Color(0.3, 0.31, 0.32), 0.7)
	var z := ROAD_FAR - 0.5
	for index: int in 15:
		var x := SITE_MIN.x + 2.0 + index * 8.5
		_box(parent, "RailPost", Vector3(x, 0.4, z), Vector3(0.14, 0.8, 0.14), post)
		if index < 14:
			_quad(
				parent, "GuardRail", Vector3(x + 4.25, 0.65, z + 0.06),
				Vector2(8.5, 0.55), rail
			)
			# Stops players crossing the decorative far ground and falling out of
			# the collision apron. The textured quad above remains the visible rail.
			_collider(
				parent, "RoadEdgeBarrier", Vector3(x + 4.25, 0.65, z),
				Vector3(8.5, 1.3, 0.12)
			)


# --- the estate wall ----------------------------------------------------------

func _build_boundary(parent: Node3D) -> void:
	# Left open on the E01 axis; every other side is closed, which is what
	# keeps the only way off the estate the one the gate lamps light.
	_add_wall_run(parent, Vector2(WALL_MIN.x, WALL_MIN.y), Vector2(GATE_MIN, WALL_MIN.y))
	_add_wall_run(parent, Vector2(GATE_MAX, WALL_MIN.y), Vector2(WALL_MAX.x, WALL_MIN.y))
	_add_wall_run(parent, Vector2(WALL_MAX.x, WALL_MIN.y), Vector2(WALL_MAX.x, WALL_MAX.y))
	_add_wall_run(parent, Vector2(WALL_MAX.x, WALL_MAX.y), Vector2(WALL_MIN.x, WALL_MAX.y))
	_add_wall_run(parent, Vector2(WALL_MIN.x, WALL_MAX.y), Vector2(WALL_MIN.x, WALL_MIN.y))
	_add_gate(parent)


func _add_wall_run(parent: Node3D, from: Vector2, to: Vector2) -> void:
	var span := from.distance_to(to)
	if span < 1.0:
		return
	var along := (to - from) / span
	var count := maxi(1, int(round(span / WALL_PANEL)))
	var panel := span / count
	var along_x := absf(along.x) > 0.5
	var render := _material(T_PLASTER, 2.4, Color(0.47, 0.48, 0.45))
	var coping := _material(T_CONCRETE, 1.2, Color(0.42, 0.43, 0.42))
	var pier := _material(T_BRICK, 1.6, Color(0.46, 0.43, 0.4))

	for index: int in count:
		var at := from + along * (panel * (index + 0.5))
		# One length in seven has come down far enough to see over, but never
		# far enough to climb: the estate stays sealed, it just stops looking
		# maintained.
		var height := 1.55 if index % 7 == 3 else WALL_HEIGHT - _rng.randf_range(0.0, 0.3)
		var size := (
			Vector3(panel, height, WALL_THICKNESS)
			if along_x
			else Vector3(WALL_THICKNESS, height, panel)
		)
		_box(parent, "EstateWall", Vector3(at.x, height * 0.5, at.y), size, render, true)
		_box(
			parent,
			"EstateWallCoping",
			Vector3(at.x, height + 0.06, at.y),
			Vector3(size.x, 0.12, size.z) + Vector3(0.1, 0.0, 0.1),
			coping
		)

	for index: int in count + 1:
		var at := from + along * (panel * index)
		var height := WALL_HEIGHT + 0.35
		_box(
			parent, "EstatePier", Vector3(at.x, height * 0.5, at.y),
			Vector3(0.75, height, 0.75), pier
		)
		_box(
			parent, "EstatePierCap", Vector3(at.x, height + 0.07, at.y),
			Vector3(0.92, 0.14, 0.92), coping
		)


func _add_gate(parent: Node3D) -> void:
	var pier := _material(T_BRICK, 1.6, Color(0.48, 0.45, 0.41))
	var coping := _material(T_CONCRETE, 1.0, Color(0.42, 0.43, 0.42))
	var iron := _material(T_IRON, 0.9, Color(0.12, 0.13, 0.14), 0.65)

	for side: float in [GATE_MIN, GATE_MAX]:
		_box(
			parent, "GatePier", Vector3(side, 1.75, WALL_MIN.y),
			Vector3(1.3, 3.5, 1.3), pier, true
		)
		_box(
			parent, "GatePierCap", Vector3(side, 3.62, WALL_MIN.y),
			Vector3(1.6, 0.24, 1.6), coping
		)
		var lantern := _material(T_CONCRETE, 0.4, Color(0.95, 0.78, 0.5))
		lantern.emission_enabled = true
		lantern.emission = Color(0.95, 0.7, 0.4)
		lantern.emission_energy_multiplier = 1.3
		_box(
			parent, "GateLantern", Vector3(side, 3.95, WALL_MIN.y),
			Vector3(0.32, 0.42, 0.32), lantern
		)
		var lamp := OmniLight3D.new()
		lamp.name = "GateLamp_%04d" % _index
		lamp.position = Vector3(side, 3.95, WALL_MIN.y)
		lamp.light_color = Color(0.95, 0.74, 0.46)
		lamp.light_energy = 1.1
		lamp.light_volumetric_fog_energy = 1.2
		lamp.omni_range = 9.0
		lamp.shadow_enabled = false
		parent.add_child(lamp)

	# One leaf stands half open and the other is jammed nearly shut, the way an
	# abandoned gate is always found.
	_add_gate_leaf(parent, Vector2(GATE_MIN + 0.6, WALL_MIN.y), 1.0, -1.15, iron)
	_add_gate_leaf(parent, Vector2(GATE_MAX - 0.6, WALL_MIN.y), -1.0, 0.22, iron)

	_quad(
		parent, "GateSign", Vector3(GATE_MIN, 2.1, WALL_MIN.y - 0.68),
		Vector2(0.95, 0.7), _decal_material(T_SIGN_TRESPASS), Vector3(0.0, PI, 0.0)
	)


func _add_gate_leaf(
	parent: Node3D, hinge: Vector2, direction: float, swing: float, iron: Material
) -> void:
	var leaf := _container(parent, "GateLeaf")
	leaf.position = Vector3(hinge.x, 0.0, hinge.y)
	leaf.rotation.y = swing
	var length := 5.4
	for rail_y: float in [0.3, 2.45]:
		_box(
			leaf, "GateRail", Vector3(direction * length * 0.5, rail_y, 0.0),
			Vector3(length, 0.12, 0.07), iron
		)
	var bars := 12
	for index: int in bars:
		var offset := direction * length * (float(index) + 0.5) / bars
		_box(leaf, "GateBar", Vector3(offset, 1.38, 0.0), Vector3(0.055, 2.25, 0.055), iron)


# --- the front court ----------------------------------------------------------

func _build_front_court(parent: Node3D) -> void:
	var gravel := _material(T_GRAVEL, 3.0, Color(0.47, 0.47, 0.45))
	var flagstone := _material(T_FLAGSTONE, 2.5, Color(0.5, 0.51, 0.48))
	_ground(parent, "Drive", Rect2(GATE_MIN + 1.0, WALL_MIN.y - 1.2, 10.0, 4.4), Y_PAVING, gravel)
	_ground(parent, "Forecourt", Rect2(24.0, -13.0, 32.0, 13.0), Y_PAVING, gravel)
	# The apron entrance 01 actually opens onto stays clear of everything.
	_ground(parent, "DoorApron", Rect2(33.0, -4.5, 14.0, 4.5), Y_PAVING + 0.006, flagstone)

	_add_dry_fountain(parent, Vector2(40.0, -7.6))

	_add_hedge_run(parent, Vector2(WALL_MIN.x + 2.0, -14.2), Vector2(31.0, -14.2))
	_add_hedge_run(parent, Vector2(49.0, -14.2), Vector2(WALL_MAX.x - 2.0, -14.2))
	_add_hedge_run(parent, Vector2(23.0, -12.6), Vector2(23.0, -1.5))
	_add_hedge_run(parent, Vector2(57.0, -12.6), Vector2(57.0, -1.5))

	for side: float in [36.2, 43.8]:
		_cylinder(
			parent, "DoorUrn", Vector3(side, 0.42, -1.4), 0.42, 0.84,
			_material(T_STONE, 1.0, Color(0.46, 0.46, 0.44)), true, Vector3.ZERO, 10
		)
		_cylinder(
			parent, "DoorUrnPlanting", Vector3(side, 0.95, -1.4), 0.5, 0.6,
			_material(T_HEDGE, 1.1, Color(0.3, 0.34, 0.26), 1.0, true), false, Vector3.ZERO, 8
		)
		# Two failing porch lanterns: the only light the facade still gets.
		_add_wall_lantern(parent, Vector3(side - 0.6, 2.7, -0.45))

	for at: Vector2 in [
		Vector2(9.0, -7.0), Vector2(18.5, -13.0), Vector2(62.0, -5.5),
		Vector2(74.0, -12.0), Vector2(88.0, -8.0), Vector2(-8.0, -11.0),
	]:
		_add_dead_tree(parent, at, _rng.randf_range(5.5, 8.5), true)

	var stone := _material(T_STONE, 1.2, Color(0.45, 0.45, 0.43))
	_box(parent, "GardenBench", Vector3(64.0, 0.44, -3.2), Vector3(2.2, 0.16, 0.5), stone, true)
	for leg: float in [-0.85, 0.85]:
		_box(parent, "BenchLeg", Vector3(64.0 + leg, 0.18, -3.2), Vector3(0.22, 0.36, 0.45), stone)


func _add_dry_fountain(parent: Node3D, at: Vector2) -> void:
	var stone := _material(T_STONE, 1.4, Color(0.44, 0.45, 0.43))
	var silt := _material(T_DIRT, 1.6, Color(0.22, 0.24, 0.2))
	_cylinder(
		parent, "FountainRim", Vector3(at.x, 0.3, at.y), 3.0, 0.6, stone, true, Vector3.ZERO, 16
	)
	_cylinder(
		parent, "FountainSilt", Vector3(at.x, 0.56, at.y), 2.65, 0.12, silt,
		false, Vector3.ZERO, 16
	)
	_cylinder(
		parent, "FountainPedestal", Vector3(at.x, 1.05, at.y), 0.45, 1.1, stone,
		true, Vector3.ZERO, 10
	)
	# Whatever stood on the pedestal came off it a long time ago.
	_box(
		parent, "FountainStatueStump", Vector3(at.x, 1.75, at.y),
		Vector3(0.42, 0.45, 0.42), stone, false, Vector3(0.0, 0.6, 0.13)
	)
	_box(
		parent, "FountainRubble", Vector3(at.x + 2.1, 0.78, at.y + 1.6),
		Vector3(0.5, 0.9, 0.4), stone, false, Vector3(0.35, 1.1, 0.8)
	)


func _add_wall_lantern(parent: Node3D, at: Vector3) -> void:
	var iron := _material(T_IRON, 0.6, Color(0.16, 0.17, 0.18), 0.7)
	var glow := _material(T_CONCRETE, 0.3, Color(0.9, 0.72, 0.48))
	glow.emission_enabled = true
	glow.emission = Color(0.9, 0.62, 0.34)
	glow.emission_energy_multiplier = 1.1
	_box(parent, "LanternBracket", at + Vector3(0.0, 0.0, 0.1), Vector3(0.09, 0.09, 0.22), iron)
	_box(parent, "LanternBody", at, Vector3(0.26, 0.38, 0.26), iron)
	_box(parent, "LanternGlass", at, Vector3(0.19, 0.29, 0.19), glow)
	var light := OmniLight3D.new()
	light.name = "LanternLight_%04d" % _index
	light.position = at
	light.light_color = Color(0.94, 0.68, 0.4)
	light.light_energy = 0.85
	light.light_volumetric_fog_energy = 1.0
	light.omni_range = 6.5
	light.shadow_enabled = false
	parent.add_child(light)


## A leggy, half-dead hedge: 2.6 m lengths with the odd one missing, so it
## screens the wall without ever looking like a planted box.
func _add_hedge_run(parent: Node3D, from: Vector2, to: Vector2) -> void:
	var span := from.distance_to(to)
	var along := (to - from) / span
	var along_x := absf(along.x) > 0.5
	var count := maxi(1, int(round(span / 2.6)))
	var segment := span / count
	var foliage := _material(T_HEDGE, 1.1, Color(0.26, 0.3, 0.23), 1.0, true)
	for index: int in count:
		if _rng.randf() < 0.18:
			continue
		var at := from + along * (segment * (index + 0.5))
		var height := _rng.randf_range(1.2, 1.9)
		var depth := _rng.randf_range(0.9, 1.3)
		_box(
			parent,
			"Hedge",
			Vector3(at.x, height * 0.5, at.y),
			(
				Vector3(segment * 0.96, height, depth)
				if along_x
				else Vector3(depth, height, segment * 0.96)
			),
			foliage,
			true
		)


## Bare trunk, bare limbs. Only the trunk is solid: a branch collider would be
## navigation Recast has to erode around for a silhouette in the fog.
func _add_dead_tree(parent: Node3D, at: Vector2, height: float, collide: bool) -> void:
	var bark := _material(
		T_BARK if _rng.randf() < 0.6 else T_BARK_DARK, 1.6, Color(0.34, 0.32, 0.29)
	)
	var radius := 0.18 + height * 0.028
	var lean := Vector3(_rng.randf_range(-0.05, 0.05), 0.0, _rng.randf_range(-0.05, 0.05))
	_cylinder(
		parent, "TreeTrunk", Vector3(at.x, height * 0.5, at.y), radius, height,
		bark, collide, lean, 8
	)
	var limbs := _rng.randi_range(3, 5)
	for index: int in limbs:
		var angle := TAU * index / limbs + _rng.randf_range(-0.4, 0.4)
		var length := _rng.randf_range(1.4, 2.9)
		var base := Vector3(at.x, height * _rng.randf_range(0.62, 0.94), at.y)
		var direction := Vector3(cos(angle), _rng.randf_range(0.5, 1.1), sin(angle)).normalized()
		_cylinder(
			parent, "TreeLimb", base + direction * length * 0.5,
			radius * 0.38, length, bark, false, Vector3.ZERO, 6, _basis_along(direction)
		)

	# A minority still carries thin, sickly foliage. Crossed cards preserve the
	# Classic64 silhouette without turning the treeline into opaque green blobs.
	if _rng.randf() < 0.42:
		var crown := _decal_material(T_TREE_CROWN, Color(0.34, 0.38, 0.29))
		for index: int in _rng.randi_range(1, 3):
			var angle := _rng.randf_range(0.0, TAU)
			var radius_from_trunk := _rng.randf_range(0.15, 0.75)
			var crown_at := Vector3(
				at.x + cos(angle) * radius_from_trunk,
				height * _rng.randf_range(0.68, 0.9),
				at.y + sin(angle) * radius_from_trunk
			)
			_crossed_cards(
				parent, "SicklyLeaves", crown_at,
				Vector2(_rng.randf_range(1.5, 2.4), _rng.randf_range(2.0, 3.2)),
				crown, angle
			)


# --- the service yard, behind the kitchen door ---------------------------------

func _build_service_yard(parent: Node3D) -> void:
	var gravel := _material(T_GRAVEL, 3.0, Color(0.44, 0.45, 0.43))
	var concrete := _material(T_CONCRETE, 2.0, Color(0.44, 0.45, 0.44))
	var rust := _material(T_RUST, 1.2, Color(0.42, 0.36, 0.31), 0.85)
	var galvanised := _material(T_GALVANISED, 1.0, Color(0.42, 0.44, 0.45), 0.7)
	var crate := _material(T_CRATE, 1.0, Color(0.42, 0.38, 0.32))

	_ground(parent, "YardGravel", Rect2(HOUSE_MAX.x, 8.0, 16.0, 30.0), Y_PAVING, gravel)
	# Entrance 02 has to stay walkable: nothing is placed in this pad, it only
	# marks the delivery apron.
	_ground(parent, "KitchenApron", Rect2(HOUSE_MAX.x, 18.0, 7.0, 8.0), Y_PAVING + 0.006, concrete)

	_box(parent, "Dumpster", Vector3(90.0, 0.78, 30.5), Vector3(2.7, 1.56, 1.5), rust, true)
	_box(
		parent, "DumpsterLid", Vector3(90.0, 1.62, 30.9), Vector3(2.7, 0.12, 1.6),
		rust, false, Vector3(-0.22, 0.0, 0.0)
	)
	for index: int in 3:
		var tipped := index == 2
		_cylinder(
			parent, "WasteBin",
			Vector3(87.5 + index * 1.2, 0.55 if not tipped else 0.42, 33.5 + index * 0.4),
			0.42, 1.05, galvanised, true,
			Vector3.ZERO if not tipped else Vector3(0.0, 0.0, PI * 0.5), 10
		)
	for index: int in 4:
		_box(
			parent, "PalletStack", Vector3(93.0, 0.09 + index * 0.16, 14.0),
			Vector3(1.2, 0.14, 1.0), _material(T_PLANK, 1.0, Color(0.4, 0.37, 0.33))
		)
	for index: int in 3:
		_box(
			parent, "ServiceCrate",
			Vector3(92.0 + _rng.randf_range(-0.6, 0.6), 0.45, 27.0 + index * 1.1),
			Vector3(0.9, 0.9, 0.9), crate, true,
			Vector3(0.0, _rng.randf_range(-0.5, 0.5), 0.0)
		)
	for index: int in 2:
		_cylinder(
			parent, "PropaneTank", Vector3(83.0 + index * 1.1, 0.8, 12.5), 0.42, 1.6,
			_material(T_GALVANISED, 1.0, Color(0.5, 0.5, 0.46), 0.6), true, Vector3.ZERO, 10
		)
	# The estate generator, long dead. It is the reason the house has a fuse
	# board and not a supply.
	_box(parent, "StandbyGenerator", Vector3(88.5, 0.6, 12.0), Vector3(2.4, 1.2, 1.3), rust, true)
	_box(
		parent, "GeneratorExhaust", Vector3(89.4, 1.75, 12.0), Vector3(0.16, 1.1, 0.16), rust
	)
	_quad(
		parent, "GeneratorWarning", Vector3(88.5, 0.95, 11.32),
		Vector2(0.6, 0.45), _decal_material(T_SIGN_WARNING), Vector3(0.0, PI, 0.0)
	)

	_add_derelict_van(parent, Vector2(91.0, 21.5), PI * 0.5)

	# A run of chain link screens the yard from the front court.
	var chain := _decal_material(T_CHAINLINK)
	var post := _material(T_IRON, 0.8, Color(0.3, 0.3, 0.3), 0.7)
	for index: int in 5:
		var x := HOUSE_MAX.x + 1.5 + index * 3.5
		_box(parent, "YardFencePost", Vector3(x, 0.95, 7.0), Vector3(0.1, 1.9, 0.1), post)
		if index < 4:
			_quad(parent, "YardFenceMesh", Vector3(x + 1.75, 0.95, 7.0), Vector2(3.5, 1.8), chain)


func _add_derelict_van(parent: Node3D, at: Vector2, heading: float) -> void:
	var body := _material(T_RUST, 1.4, Color(0.38, 0.36, 0.34), 0.8)
	var glass := _material(T_WINDOW_DARK, 1.0, Color(0.16, 0.18, 0.2), 0.4)
	var tyre := _material(T_IRON, 0.5, Color(0.09, 0.09, 0.1), 0.95)
	var van := _container(parent, "DerelictVan")
	van.position = Vector3(at.x, 0.0, at.y)
	van.rotation.y = heading
	_box(van, "VanBox", Vector3(0.0, 1.25, -0.4), Vector3(2.1, 1.9, 3.4), body)
	_box(van, "VanCab", Vector3(0.0, 1.05, 1.85), Vector3(2.0, 1.4, 1.3), body)
	_box(van, "VanScreen", Vector3(0.0, 1.35, 2.48), Vector3(1.7, 0.7, 0.06), glass)
	_box(van, "VanChassis", Vector3(0.0, 0.4, 0.2), Vector3(1.9, 0.3, 4.6), body)
	for side: float in [-0.95, 0.95]:
		for axle: float in [1.6, -1.4]:
			_cylinder(
				van, "VanWheel", Vector3(side, 0.42, axle), 0.42, 0.28, tyre,
				false, Vector3(0.0, 0.0, PI * 0.5), 10
			)
	# One collider for the whole vehicle; the panels above are decoration.
	_collider(
		parent, "VanHull", Vector3(at.x, 1.1, at.y), Vector3(2.1, 2.2, 5.2),
		Vector3(0.0, heading, 0.0)
	)


# --- the open cellar trench ---------------------------------------------------

func _build_cellar_trench(parent: Node3D) -> void:
	var post := _material(T_IRON, 0.8, Color(0.28, 0.29, 0.3), 0.7)
	var rail := _material(T_RUST, 1.0, Color(0.4, 0.35, 0.31), 0.85)
	# The trench is a 3.5 m drop in the middle of the west garden. Rail it, or
	# the first thing the villa does to a player running for entrance 05 in the
	# dark is drop them into it.
	for edge: float in [TRENCH_Z0 - 0.85, TRENCH_Z1 + 0.85]:
		for index: int in 7:
			var x := TRENCH_FAR_X + 0.5 + index * 2.1
			_box(parent, "TrenchPost", Vector3(x, 0.55, edge), Vector3(0.09, 1.1, 0.09), post)
		for height: float in [0.5, 1.0]:
			_box(
				parent, "TrenchRail",
				Vector3(TRENCH_FAR_X + 6.8, height, edge), Vector3(13.0, 0.07, 0.07), rail
			)
	_quad(
		parent, "TrenchWarning", Vector3(TRENCH_FAR_X + 1.2, 0.85, TRENCH_Z0 - 0.9),
		Vector2(0.7, 0.5), _decal_material(T_SIGN_WARNING), Vector3(0.0, PI, 0.0)
	)
	for index: int in 3:
		_box(
			parent, "CoalCrate",
			Vector3(-5.0 - index * 1.3, 0.45, TRENCH_Z0 - 3.2),
			Vector3(0.9, 0.9, 0.9), _material(T_CRATE, 1.0, Color(0.36, 0.33, 0.29)), true,
			Vector3(0.0, _rng.randf_range(-0.4, 0.4), 0.0)
		)
	for at: Vector2 in [Vector2(-10.0, 8.0), Vector2(-8.5, 24.0), Vector2(-11.0, 48.0)]:
		_add_dead_tree(parent, at, _rng.randf_range(6.0, 9.0), true)


# --- the back garden ----------------------------------------------------------

func _build_back_garden(parent: Node3D) -> void:
	var flagstone := _material(T_FLAGSTONE, 2.5, Color(0.48, 0.49, 0.46))
	# Entrance 04 is a glass door onto the terrace, so the terrace is the one
	# piece of paving back here that stays swept.
	_ground(parent, "BallroomTerrace", Rect2(32.0, HOUSE_MAX.y, 16.0, 7.0), Y_PAVING, flagstone)
	for step: int in 2:
		_box(
			parent, "TerraceStep", Vector3(40.0, 0.06 + step * 0.04, 67.4 + step * 0.5),
			Vector3(16.0 - step * 1.2, 0.12, 1.0), flagstone
		)

	_add_garden_shed(parent, Vector2(66.0, 69.5), -0.35)
	_add_family_plot(parent, Vector2(13.0, 70.0))
	_add_clothes_line(parent, Vector2(28.0, 70.5))

	# A stone basin that has not held water in years.
	_cylinder(
		parent, "GardenBasin", Vector3(52.0, 0.28, 66.5), 1.5, 0.56,
		_material(T_STONE, 1.2, Color(0.44, 0.45, 0.42)), true, Vector3.ZERO, 12
	)
	_cylinder(
		parent, "GardenBasinSilt", Vector3(52.0, 0.53, 66.5), 1.25, 0.1,
		_material(T_DIRT, 1.4, Color(0.2, 0.22, 0.18)), false, Vector3.ZERO, 12
	)

	for index: int in 7:
		_box(
			parent, "FireWood",
			Vector3(80.0, 0.14 + (index / 3) * 0.28, 62.5 + (index % 3) * 0.3),
			Vector3(1.6, 0.26, 0.26), _material(T_PLANK, 0.8, Color(0.36, 0.33, 0.29)),
			false, Vector3(0.0, _rng.randf_range(-0.05, 0.05), 0.0)
		)

	for at: Vector2 in [
		Vector2(8.0, 66.0), Vector2(24.0, 73.0), Vector2(48.0, 72.5),
		Vector2(70.0, 63.5), Vector2(90.0, 70.0), Vector2(4.0, 62.0),
		Vector2(-6.0, 64.0), Vector2(58.0, 66.0),
	]:
		_add_dead_tree(parent, at, _rng.randf_range(5.5, 9.5), true)


func _add_garden_shed(parent: Node3D, at: Vector2, heading: float) -> void:
	var boards := _material(T_SIDING_WOOD, 1.6, Color(0.38, 0.36, 0.32))
	var shingle := _material(T_SHINGLE, 1.2, Color(0.3, 0.3, 0.29))
	var shed := _container(parent, "GardenShed")
	shed.position = Vector3(at.x, 0.0, at.y)
	shed.rotation.y = heading
	_box(shed, "ShedWalls", Vector3(0.0, 1.3, 0.0), Vector3(4.4, 2.6, 3.2), boards)
	_add_gable_roof(shed, Vector3(0.0, 2.6, 0.0), 4.8, 3.6, 0.9, shingle)
	_quad(
		shed, "ShedDoor", Vector3(-0.9, 1.0, 1.61), Vector2(1.0, 2.0),
		_decal_material(PACK + "Doors/Materials/door_shed_a.png", Color(0.6, 0.58, 0.54))
	)
	_quad(
		shed, "ShedWindow", Vector3(1.1, 1.6, 1.61), Vector2(0.9, 0.9),
		_decal_material(T_WINDOW_BOARDED, Color(0.5, 0.5, 0.48))
	)
	# The shell above is decoration around one box collider.
	_collider(
		parent, "ShedHull", Vector3(at.x, 1.55, at.y), Vector3(4.4, 3.1, 3.2),
		Vector3(0.0, heading, 0.0)
	)


## Five headstones under the back wall. Villas in this part of the world often
## do keep a family plot; this one has not been tended since the lights went.
func _add_family_plot(parent: Node3D, at: Vector2) -> void:
	var stone := _material(T_CONCRETE, 0.9, Color(0.43, 0.44, 0.43))
	var kerb := _material(T_STONE, 1.0, Color(0.4, 0.41, 0.39))
	for side: int in 4:
		var along_x := side % 2 == 0
		var offset := 3.4 * (1.0 if side < 2 else -1.0)
		_box(
			parent, "PlotKerb",
			Vector3(at.x + (0.0 if along_x else offset), 0.12, at.y + (offset if along_x else 0.0)),
			Vector3(6.8, 0.24, 0.3) if along_x else Vector3(0.3, 0.24, 6.8),
			kerb
		)
	for index: int in 5:
		var lean := _rng.randf_range(-0.22, 0.22)
		_box(
			parent, "HeadStone",
			Vector3(at.x - 2.4 + index * 1.2, 0.46, at.y + _rng.randf_range(-0.5, 0.5)),
			Vector3(0.58, 0.92, 0.16), stone, true,
			Vector3(0.0, _rng.randf_range(-0.3, 0.3), lean)
		)
	_add_dead_tree(parent, at + Vector2(0.0, -3.0), 8.5, true)


func _add_clothes_line(parent: Node3D, at: Vector2) -> void:
	var timber := _material(T_POLE, 1.4, Color(0.38, 0.35, 0.31))
	var linen := _decal_material(T_LINEN, Color(0.62, 0.63, 0.6, 0.85), false)
	linen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for side: float in [-4.0, 4.0]:
		_cylinder(
			parent, "LinePost", Vector3(at.x + side, 1.1, at.y), 0.09, 2.2, timber,
			true, Vector3.ZERO, 8
		)
		_box(parent, "LineCrossArm", Vector3(at.x + side, 2.1, at.y), Vector3(0.08, 0.08, 1.2), timber)
	for offset: float in [-0.45, 0.45]:
		_box(
			parent, "ClothesLine", Vector3(at.x, 2.02, at.y + offset),
			Vector3(8.0, 0.025, 0.025), timber
		)
	# Three sheets left out, and the only thing on the estate that moves in
	# the fog when the flashlight sweeps past.
	for index: int in 3:
		_quad(
			parent, "HangingSheet",
			Vector3(at.x - 2.4 + index * 2.4, 1.35, at.y - 0.45),
			Vector2(1.5, 1.3), linen, Vector3(0.0, _rng.randf_range(-0.15, 0.15), 0.0)
		)


## Two tilted slabs meeting at a ridge that runs along local X.
func _add_gable_roof(
	parent: Node3D, eaves: Vector3, width: float, depth: float, rise: float, material: Material
) -> void:
	var half := depth * 0.5
	var pitch := atan2(rise, half)
	var slope := sqrt(half * half + rise * rise)
	for side: float in [-1.0, 1.0]:
		_box(
			parent, "RoofSlope",
			eaves + Vector3(0.0, rise * 0.5, side * half * 0.5),
			Vector3(width, 0.22, slope),
			material,
			false,
			Vector3(pitch * side, 0.0, 0.0)
		)


# --- the horizon --------------------------------------------------------------

## Nothing in here is ever given a collider: see the file header. The whole
## backdrop exists to stop the site aprons ending in visible nothing, and the
## fog reaches most of it, so it is built as silhouettes rather than buildings.
func _build_backdrop(parent: Node3D) -> void:
	var far_ground := _material(T_LAWN, 6.0, Color(0.28, 0.31, 0.27))
	for area: Rect2 in [
		Rect2(-90.0, -90.0, 300.0, 66.0),
		Rect2(-90.0, SITE_MAX.y, 300.0, 66.0),
		Rect2(-90.0, SITE_MIN.y, 66.0, 108.0),
		Rect2(SITE_MAX.x, SITE_MIN.y, 66.0, 108.0),
	]:
		_ground(parent, "FarGround", area, Y_LAWN - 0.002, far_ground)

	# Four neighbours across the ring road. One of them still has a light on,
	# and someone standing in it.
	_add_backdrop_house(parent, Vector2(-14.0, -35.0), 14.0, 10.0, 6.4, false)
	_add_backdrop_house(parent, Vector2(18.0, -38.0), 12.0, 9.0, 5.8, true)
	_add_backdrop_house(parent, Vector2(56.0, -36.0), 15.0, 11.0, 6.8, false)
	_add_backdrop_house(parent, Vector2(92.0, -34.0), 13.0, 9.5, 6.0, false)

	var bands: Array[Rect2] = [
		Rect2(-88.0, -76.0, 296.0, 44.0),
		Rect2(-88.0, 92.0, 296.0, 44.0),
		Rect2(-88.0, -32.0, 56.0, 124.0),
		Rect2(SITE_MAX.x + 8.0, -32.0, 56.0, 124.0),
	]
	for band: Rect2 in bands:
		for _tree: int in 16:
			_add_dead_tree(parent, _random_point(band), _rng.randf_range(7.0, 13.0), false)


func _add_backdrop_house(
	parent: Node3D, at: Vector2, width: float, depth: float, height: float, lit: bool
) -> void:
	var siding := _material(T_SIDING, 1.8, Color(0.24, 0.26, 0.27))
	var shingle := _material(T_SHINGLE, 1.6, Color(0.17, 0.18, 0.19))
	var house := _container(parent, "NeighbourHouse")
	house.position = Vector3(at.x, 0.0, at.y)
	_box(house, "NeighbourWalls", Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth), siding)
	_add_gable_roof(house, Vector3(0.0, height, 0.0), width + 0.8, depth + 1.2, 2.2, shingle)
	_box(
		house, "NeighbourChimney", Vector3(width * 0.3, height + 1.9, -depth * 0.2),
		Vector3(0.8, 2.4, 0.8), _material(T_BRICK, 1.2, Color(0.22, 0.21, 0.2))
	)

	# The facing wall is the south one: these houses look back across the road
	# at the villa.
	var facade := depth * 0.5 + 0.04
	var boarded := _decal_material(T_WINDOW_BOARDED, Color(0.3, 0.31, 0.31))
	var dark := _decal_material(T_WINDOW_DARK, Color(0.12, 0.14, 0.16), false)
	var columns := maxi(2, int(width / 4.0))
	for column: int in columns:
		var x := -width * 0.5 + width * (column + 0.5) / columns
		for row: int in 2:
			var y := 1.5 + row * 2.4
			if y > height - 0.9:
				continue
			var pane: Material = boarded if _rng.randf() < 0.45 else dark
			_quad(house, "NeighbourWindow", Vector3(x, y, facade), Vector2(1.1, 1.4), pane)

	if not lit:
		return
	var glow := _decal_material(T_WINDOW_DARK, Color(0.85, 0.72, 0.45), false)
	glow.emission_enabled = true
	glow.emission = Color(0.9, 0.66, 0.36)
	glow.emission_energy_multiplier = 1.5
	var window := Vector3(-width * 0.5 + width * 0.5 / maxi(2, columns), 3.9, facade)
	_quad(house, "NeighbourLitWindow", window, Vector2(1.1, 1.4), glow)
	# Someone is standing in it. They are still there the next time the player
	# looks; that is the whole trick.
	_box(
		house, "NeighbourWatcher", window + Vector3(0.0, -0.15, -0.35),
		Vector3(0.42, 1.15, 0.2), _material(T_IRON, 0.5, Color(0.02, 0.02, 0.03), 1.0)
	)


# --- ground mist --------------------------------------------------------------

## The world environment already carries volumetric fog for the whole map;
## these only thicken it where the player walks, so the garden reads as damp
## and the lamp cones have something to stand in.
func _build_atmosphere(parent: Node3D) -> void:
	_add_mist(parent, "FrontCourtMist", Vector3(40.0, 1.1, -8.0), Vector3(120.0, 3.4, 20.0), 0.035)
	_add_mist(parent, "RingRoadMist", Vector3(40.0, 1.0, -20.0), Vector3(128.0, 3.0, 8.0), 0.028)
	_add_mist(parent, "BackGardenMist", Vector3(40.0, 1.1, 70.0), Vector3(120.0, 3.4, 22.0), 0.04)
	_add_mist(parent, "WestGardenMist", Vector3(-11.0, 1.1, 30.0), Vector3(22.0, 3.4, 76.0), 0.032)


func _add_mist(
	parent: Node3D, mist_name: String, centre: Vector3, size: Vector3, density: float
) -> void:
	var fog_material := FogMaterial.new()
	fog_material.density = density
	fog_material.albedo = Color(0.6, 0.66, 0.7)
	fog_material.emission = Color(0.01, 0.014, 0.02)
	fog_material.height_falloff = 2.4
	var volume := FogVolume.new()
	volume.name = mist_name
	volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	volume.size = size
	volume.position = centre
	volume.material = fog_material
	parent.add_child(volume)

@tool
class_name StalkerRig
extends Node3D

## "Kẻ Đi Săn" / The Abyssal Stalker - the huntsman's body.
##
## The huntsman used to be a man in a coat with a lantern. It is not that any
## more. What walks in through a broken door now is a skeleton stretched past
## the point a skeleton works: arms longer than its legs, a crown of thin jointed
## arms writhing around a hole where a face should be, and eyes scattered over
## its chest, ribs, joints and tail so it never has to turn to look at you.
##
## Why this is built in code and not laid out in the .tscn:
## the creature is ~310 parts and almost every one of them is a *chain* - two
## rings of crown arms, twelve tail vertebrae, ten fingers, two legs' worth of
## digitigrade joints. Written out as scene nodes that is thousands of lines
## nobody can retune; written as a builder, the proportions are twenty constants
## at the top of this file and every joint that exists is automatically a joint
## that animates. `hunter_ghost.gd` keeps the AI and never touches a bone: it
## sets `locomotion_speed` / `agitation` / `searching` / `charging` / the look
## point, calls `advance()`, and the body does the rest.
##
## It is `@tool` purely so the creature is visible in the editor. Opening
## `hunter_ghost.tscn` would otherwise show one empty `VisualRoot` node, because
## every part of the body is made at `_ready()`. The parts it builds are added
## without an owner, so they show up in the viewport and are still never written
## into the `.tscn`. To look at it properly, run `tests/stalker_devshot.gd`,
## which renders it from the concept sheet's own angles.
##
## Conventions, so the chain code stays readable:
##   * -Z is forward, matching the rest of the project and the gaze cone.
##   * Every limb segment grows out of its pivot along local +Y, or local -Y for
##     anything that hangs (legs, arms, fingers). `_limb()` returns the pivot at
##     the far end, so a chain is just "keep parenting to what you got back".
##   * A positive `rotation.x` swings a hanging limb *forward*.

signal foot_planted(speed: float)

# --- Proportions -------------------------------------------------------------

const HIP_Y := 1.195
const HIP_X := 0.205
const FEMUR_LEN := 0.47
const TIBIA_LEN := 0.45
const META_LEN := 0.258
## Digitigrade rest pose: thigh forward, shin back, a raised heel, flat toes.
const FEMUR_REST := 0.36
const TIBIA_REST := -0.78
const META_REST := 0.66
const FOOT_REST := -0.24

const SPINE_SEGMENTS := 5
const SPINE_LEN := 0.135
## Every vertebra leans this much further forward than the one below it, which
## is what makes the whole thing hunch instead of stand.
const SPINE_REST := -0.27

## By the top of the spine the hunch has accumulated to a full 1.35 rad. The
## shoulder girdle unwinds all but this much of it, so the arms hang from
## something near vertical instead of inheriting the lean and pointing backwards
## out of its back.
const SHOULDER_LEAN := -0.38

const NECK_LEN := 0.095
## Measured from the unwound girdle, so these are small: the head sits almost
## upright on top of a body bent right over.
const NECK_REST: Array[float] = [0.14, 0.12]

const SHOULDER_X := 0.235
const HUMERUS_LEN := 0.52
const RADIUS_LEN := 0.56
const ARM_REST_X := 0.30
const ARM_REST_Z := 0.20
const FOREARM_REST := -0.52
const HAND_REST := 0.18
const FINGER_COUNT := 4

const CROWN_SPINES := 13
## A second, shorter ring slotted between the outer spines. Density is the whole
## point of the crown: sparse spokes read as a cartoon sun, a thicket reads as
## the hole in the concept art.
const CROWN_INNER_SPINES := 8
## Segments per crown arm. Three plus two knuckles is the fewest that reads as a
## jointed limb rather than a bent spike.
const CROWN_ARM_SEGMENTS := 3
const CROWN_REST_TILT := 0.92
const CROWN_OPEN_TILT := 0.14
const VOID_RADIUS := 0.145

const TAIL_SEGMENTS := 12
## Points the tail back and down out of the pelvis before it curls up again.
const TAIL_ROOT_REST := 2.15
const TAIL_REST := -0.22

const DRIP_COUNT := 9

# --- Animation inputs, written by hunter_ghost.gd -----------------------------

var locomotion_speed: float = 0.0
var agitation: float = 0.0
var searching: bool = false
var charging: bool = false
var stride_length: float = 0.95
var look_point: Vector3 = Vector3.ZERO
var has_look_point: bool = false

# --- Performance ---------------------------------------------------------------

## Whether the gaze light casts real-time shadows. See `_build_crown()`: this is
## the single most expensive thing the creature can do, so it is opt-in.
@export var gaze_casts_shadows: bool = false
## Past this from whoever it is watching, the eyes stop aiming individually and
## the drips stop running. Neither is legible at that range and between them
## they are most of the per-frame cost of the body.
@export var detail_distance: float = 16.0
## Eyes are aimed one in every `EYE_AIM_STRIDE` frames, round-robin. Aiming one
## costs a global-transform query and a basis inverse, and there are forty-odd of
## them; spreading that over three frames is invisible and cuts it to a third.
const EYE_AIM_STRIDE := 3

# --- Exposed joints the AI needs ---------------------------------------------

var gaze_light: SpotLight3D
var gaze_pivot: Node3D
var head_pivot: Node3D
var jaw_pivot: Node3D

# --- Internals ---------------------------------------------------------------

var _built: bool = false
var _clock: float = 0.0
var _stride_phase: float = 0.0
var _jaw_open: float = 0.0
var _crown_flare: float = CROWN_REST_TILT
var _reach: float = 0.0
var _eye_cursor: int = 0
## Distance from whatever the body is currently watching, used only to decide how
## much per-frame detail this creature is worth. Set from `look_point`.
var _watcher_distance: float = 0.0

var _body: Node3D
var _hips: Node3D
var _thorax: Node3D
var _shoulders: Node3D
var _crown_hub: Node3D
var _void_core: MeshInstance3D

## [{hip, knee, meta, foot, side}] - index 0 left, 1 right.
var _legs: Array[Dictionary] = []
var _spine_pivots: Array[Node3D] = []
var _neck_pivots: Array[Node3D] = []
## [{shoulder, forearm, hand, fingers, side}]
var _arms: Array[Dictionary] = []
## [{root, tilt, joints, eye, angle, index}]
var _crown: Array[Dictionary] = []
var _tail_pivots: Array[Node3D] = []
## [{pivot, mesh, rest, phase, speed, blink_in, blink_t}]
var _eyes: Array[Dictionary] = []
## [{mesh, joint, length, phase}] - anything that can telescope.
var _stretchers: Array[Dictionary] = []
## [{node, mesh, origin, fall, speed, t}]
var _drips: Array[Dictionary] = []

var _mat_flesh: ShaderMaterial
var _mat_bone: ShaderMaterial
var _mat_eye: ShaderMaterial
var _mat_void: StandardMaterial3D
var _mat_slime: StandardMaterial3D
var _mesh_cache: Dictionary = {}

## Set by `_limb()`, so a caller that wants a telescoping segment can pick up
## the mesh and the joint it just made without every builder returning a tuple.
var _last_mesh: MeshInstance3D
var _last_joint: Node3D
var _last_length: float


func _ready() -> void:
	build()


## Idempotent, so a smoke test can force the body to exist before the node has
## finished entering the tree.
func build() -> void:
	if _built:
		return
	_built = true
	_build_materials()
	_body = _pivot(self, 'Body')
	_hips = _pivot(_body, 'Hips', Vector3(0.0, HIP_Y, 0.0))
	_build_pelvis()
	_legs.append(_build_leg(-1.0))
	_legs.append(_build_leg(1.0))
	_build_tail()
	_build_spine()
	_build_thorax()
	_build_arms()
	_build_head()
	_build_drips()
	_apply_shadow_budget()


## Shadow casters are the expensive half of a moving spotlight: every one of them
## is re-rendered into a shadow map each frame it is lit. This body is three
## hundred parts and almost none of them change the shape of the shadow it throws
## down a corridor - a finger bone costs exactly as much as a thigh and is
## invisible in the result. So the silhouette is paid for by twenty-odd big
## masses and nothing else, applied in one pass here rather than tracked
## flag-by-flag through thirty builder calls.
const SHADOW_CASTERS: Array[String] = [
	'Femur', 'Tibia', 'Metatarsus', 'Sole',
	'Pelvis', 'ChestMass', 'Skull', 'Occiput',
	'Humerus', 'Radius', 'Palm',
	'Vertebra00', 'Vertebra01', 'Vertebra02', 'Vertebra03', 'Vertebra04',
	'Caudal00', 'Caudal01', 'Caudal02', 'Caudal03', 'Caudal04',
]


func _apply_shadow_budget() -> void:
	for node: Node in find_children('*', 'MeshInstance3D', true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if SHADOW_CASTERS.has(String(mesh_instance.name)) \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Build helpers -----------------------------------------------------------


func _pivot(parent: Node3D, part_name: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = part_name
	node.position = pos
	node.rotation = rot
	parent.add_child(node)
	return node


func _part(
	parent: Node3D,
	part_name: String,
	mesh: Mesh,
	pos := Vector3.ZERO,
	rot := Vector3.ZERO,
	scl := Vector3.ONE,
	shadows := true
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = pos
	instance.rotation = rot
	instance.scale = scl
	if not shadows:
		# Eyes, claws, teeth, barbs and drips are too small to read in a shadow
		# and there are well over a hundred of them; the gaze light only pays
		# for the parts that actually change the silhouette.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## One tapered bone growing out of `parent`. Returns the joint pivot sitting at
## its far end, which is what the next segment in the chain parents to.
func _limb(
	parent: Node3D,
	part_name: String,
	base_radius: float,
	tip_radius: float,
	length: float,
	material: Material,
	down := false,
	segments := 6,
	shadows := true
) -> Node3D:
	var facing := -1.0 if down else 1.0
	var top := base_radius if down else tip_radius
	var bottom := tip_radius if down else base_radius
	_last_mesh = _part(
		parent,
		part_name,
		_cone(top, bottom, length, material, segments),
		Vector3(0.0, facing * length * 0.5, 0.0),
		Vector3.ZERO,
		Vector3.ONE,
		shadows
	)
	_last_length = facing * length
	_last_joint = _pivot(parent, part_name + 'Joint', Vector3(0.0, _last_length, 0.0))
	return _last_joint


## Registers whatever `_limb()` built last as a segment that can telescope: the
## mesh stretches and the joint at its end slides out with it, so everything
## further down the chain comes along.
func _telescope(phase: float) -> void:
	_stretchers.append({
		'mesh': _last_mesh,
		'joint': _last_joint,
		'length': _last_length,
		'phase': phase,
	})


func _ball(parent: Node3D, part_name: String, radius: float, material: Material) -> MeshInstance3D:
	return _part(parent, part_name, _sphere(radius, material))


func _cone(top: float, bottom: float, height: float, material: Material, segments := 6) -> CylinderMesh:
	var key := 'c%.4f_%.4f_%.4f_%d_%d' % [top, bottom, height, segments, material.get_instance_id()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = material
	_mesh_cache[key] = mesh
	return mesh


func _sphere(radius: float, material: Material, segments := 7, rings := 4) -> SphereMesh:
	var key := 's%.4f_%d_%d_%d' % [radius, segments, rings, material.get_instance_id()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	mesh.material = material
	_mesh_cache[key] = mesh
	return mesh


func _box(size: Vector3, material: Material) -> BoxMesh:
	var key := 'b%.4f_%.4f_%.4f_%d' % [size.x, size.y, size.z, material.get_instance_id()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	_mesh_cache[key] = mesh
	return mesh


func _ring(inner: float, outer: float, material: Material) -> TorusMesh:
	var key := 't%.4f_%.4f_%d' % [inner, outer, material.get_instance_id()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	# Six rings of four is the coarsest that still reads as a round band, and
	# there are sixty of these on the body.
	mesh.rings = 6
	mesh.ring_segments = 4
	mesh.material = material
	_mesh_cache[key] = mesh
	return mesh


## One eye: one node, one draw. The shader puts the pupil down the pivot's own
## -Z, so aiming the pivot aims the eye and nothing else has to move. That is
## the only reason the creature can afford to wear thirty of them.
func _eye(parent: Node3D, pos: Vector3, rot: Vector3, radius: float) -> Node3D:
	var pivot := _pivot(parent, 'EyePivot', pos, rot)
	var mesh := _part(
		pivot, 'Eye', _sphere(radius, _mat_eye, 8, 5), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false
	)
	# A shallow bone socket, so the eye reads as set into the body rather than
	# glued onto it. Only the big ones get it: at two centimetres across the ring
	# is a couple of pixels, and there are forty of these - forty draw calls and
	# four thousand triangles for something nobody can see.
	if radius >= 0.024:
		_part(
			pivot,
			'Socket',
			_ring(radius * 0.88, radius * 1.30, _mat_bone),
			Vector3(0.0, 0.0, radius * 0.30),
			Vector3(PI * 0.5, 0.0, 0.0),
			Vector3.ONE,
			false
		)
	_eyes.append({
		'pivot': pivot,
		'mesh': mesh,
		'rest': Basis.from_euler(rot),
		'phase': randf() * TAU,
		'speed': randf_range(0.55, 1.35),
		'blink_in': randf_range(0.8, 6.0),
		'blink_t': -1.0,
	})
	return pivot


func _build_materials() -> void:
	var flesh_shader: Shader = load('res://ghosts/stalker_flesh.gdshader')
	_mat_flesh = ShaderMaterial.new()
	_mat_flesh.shader = flesh_shader
	_mat_flesh.set_shader_parameter('bone_amount', 0.0)
	_mat_flesh.set_shader_parameter('wetness', 0.90)
	_mat_flesh.set_shader_parameter('drip_amount', 0.78)

	_mat_bone = ShaderMaterial.new()
	_mat_bone.shader = flesh_shader
	_mat_bone.set_shader_parameter('bone_amount', 1.0)
	_mat_bone.set_shader_parameter('wetness', 0.45)
	_mat_bone.set_shader_parameter('drip_amount', 0.35)
	_mat_bone.set_shader_parameter('plate_scale', 44.0)

	_mat_eye = ShaderMaterial.new()
	_mat_eye.shader = load('res://ghosts/stalker_eye.gdshader')

	# Not a dark colour - a hole. Unshaded, so no light in the house can ever
	# put a highlight in it.
	_mat_void = StandardMaterial3D.new()
	_mat_void.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_void.albedo_color = Color(0.002, 0.002, 0.003)

	_mat_slime = StandardMaterial3D.new()
	_mat_slime.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_slime.albedo_color = Color(0.030, 0.026, 0.022, 0.72)
	_mat_slime.roughness = 0.06
	_mat_slime.metallic_specular = 0.9


# --- Anatomy -----------------------------------------------------------------


func _build_pelvis() -> void:
	_part(_hips, 'Pelvis', _sphere(0.15, _mat_flesh), Vector3(0.0, -0.02, 0.0),
		Vector3.ZERO, Vector3(1.0, 0.72, 0.78))
	_part(_hips, 'SacrumPlate', _box(Vector3(0.20, 0.13, 0.07), _mat_bone),
		Vector3(0.0, 0.02, 0.10), Vector3(0.28, 0.0, 0.0))
	for side: float in [-1.0, 1.0]:
		# Iliac blades, flared up and back the way a starved animal's are.
		_part(_hips, 'Ilium', _cone(0.012, 0.055, 0.24, _mat_bone, 5),
			Vector3(side * 0.13, 0.10, 0.05), Vector3(0.55, 0.0, side * 0.42))
		_eye(_hips, Vector3(side * 0.145, 0.02, -0.05), Vector3(0.0, side * 1.05, 0.0), 0.021)


func _build_leg(side: float) -> Dictionary:
	var hip := _pivot(_hips, 'Hip', Vector3(side * HIP_X, -0.03, 0.0),
		Vector3(FEMUR_REST, 0.0, side * 0.05))
	_ball(hip, 'HipBall', 0.090, _mat_flesh)
	var knee := _limb(hip, 'Femur', 0.105, 0.070, FEMUR_LEN, _mat_flesh, true)
	# An eye on the thigh, facing out to the side. There is no angle on this
	# creature that is not already covered.
	_eye(hip, Vector3(side * 0.085, -0.20, 0.0), Vector3(0.0, side * 1.35, 0.0), 0.023)
	_ball(knee, 'KneeCap', 0.076, _mat_bone)
	_part(knee, 'KneeSpur', _cone(0.004, 0.030, 0.16, _mat_bone, 5),
		Vector3(0.0, 0.02, 0.055), Vector3(2.05, 0.0, 0.0), Vector3.ONE, false)

	var shin := _pivot(knee, 'ShinPivot', Vector3.ZERO, Vector3(TIBIA_REST, 0.0, 0.0))
	var ankle := _limb(shin, 'Tibia', 0.070, 0.046, TIBIA_LEN, _mat_flesh, true)
	_ball(ankle, 'Ankle', 0.052, _mat_bone)

	var meta := _pivot(ankle, 'MetaPivot', Vector3.ZERO, Vector3(META_REST, 0.0, 0.0))
	var heel := _limb(meta, 'Metatarsus', 0.046, 0.040, META_LEN, _mat_flesh, true)

	var foot := _pivot(heel, 'FootPivot', Vector3.ZERO, Vector3(FOOT_REST, 0.0, 0.0))
	_part(foot, 'Sole', _box(Vector3(0.115, 0.050, 0.150), _mat_flesh), Vector3(0.0, -0.026, -0.045))
	# Three forward toes and a back spur: it walks on its fingertips. The toes
	# lie almost flat and only the claws reach the floor, which is what the
	# `_test_it_stands_on_the_floor()` smoke test is pinning down.
	for toe: int in range(3):
		var spread := float(toe) - 1.0
		var toe_root := _pivot(
			foot,
			'Toe%d' % toe,
			Vector3(spread * 0.052, -0.038, -0.105),
			Vector3(1.50, spread * 0.30, spread * 0.16)
		)
		var toe_knuckle := _limb(toe_root, 'ToeBone', 0.022, 0.016, 0.125, _mat_flesh, true, 5, false)
		var toe_claw := _pivot(toe_knuckle, 'ToeClawPivot', Vector3.ZERO, Vector3(-0.62, 0.0, 0.0))
		_limb(toe_claw, 'ToeClaw', 0.016, 0.001, 0.115, _mat_bone, true, 5, false)
	var spur := _pivot(foot, 'HeelSpur', Vector3(0.0, -0.030, 0.050), Vector3(-1.15, 0.0, 0.0))
	_limb(spur, 'SpurClaw', 0.016, 0.001, 0.130, _mat_bone, true, 5, false)

	return {'hip': hip, 'knee': shin, 'meta': meta, 'foot': foot, 'side': side}


func _build_spine() -> void:
	var node := _pivot(_hips, 'SpineRoot', Vector3(0.0, 0.06, 0.0))
	for i: int in range(SPINE_SEGMENTS):
		var ratio := float(i) / float(SPINE_SEGMENTS - 1)
		var segment := _pivot(node, 'Spine%02d' % i, Vector3.ZERO, Vector3(SPINE_REST, 0.0, 0.0))
		_spine_pivots.append(segment)
		node = _limb(
			segment,
			'Vertebra%02d' % i,
			lerpf(0.082, 0.068, ratio),
			lerpf(0.076, 0.062, ratio),
			SPINE_LEN,
			_mat_flesh
		)
		# One dorsal barb per vertebra, raked back along the spine.
		_part(
			segment,
			'DorsalBarb%02d' % i,
			_cone(0.003, 0.024, lerpf(0.19, 0.12, ratio), _mat_bone, 5),
			Vector3(0.0, SPINE_LEN * 0.55, 0.055),
			Vector3(2.25, 0.0, 0.0),
			Vector3.ONE,
			false
		)
		if i == 1 or i == 3:
			# Eyes down its back, looking behind it. Nothing follows this thing
			# without being seen doing it.
			_eye(segment, Vector3(0.0, SPINE_LEN * 0.5, 0.085), Vector3(-0.20, PI, 0.0), 0.024)
	# Everything above the ribcage hangs off this, and it undoes the accumulated
	# hunch so the arms, neck and crown are all measured from near-vertical. It
	# is also the joint that leans when the creature commits, because the spine
	# animation feeds straight into it.
	_shoulders = _pivot(node, 'ShoulderGirdle', Vector3.ZERO,
		Vector3(-SPINE_REST * float(SPINE_SEGMENTS) + SHOULDER_LEAN, 0.0, 0.0))


func _build_thorax() -> void:
	_thorax = _pivot(_spine_pivots[2], 'Thorax', Vector3(0.0, 0.055, 0.0))
	_part(_thorax, 'ChestMass', _sphere(0.16, _mat_flesh, 8, 5), Vector3(0.0, 0.05, -0.015),
		Vector3.ZERO, Vector3(0.92, 1.28, 0.72))
	# Rib bands. A torus is already a ring around a vertical axis, so flattening
	# it front to back is the whole trick.
	var band_radii: Array[float] = [0.150, 0.176, 0.186, 0.170, 0.140]
	for i: int in range(band_radii.size()):
		var radius: float = band_radii[i]
		_part(
			_thorax,
			'RibBand%d' % i,
			_ring(radius - 0.020, radius, _mat_bone),
			Vector3(0.0, -0.070 + float(i) * 0.072, -0.015),
			Vector3(0.10 - float(i) * 0.05, 0.0, 0.0),
			Vector3(1.0, 1.0, 0.74)
		)
	_part(_thorax, 'Sternum', _box(Vector3(0.075, 0.30, 0.035), _mat_bone),
		Vector3(0.0, 0.06, -0.135), Vector3(-0.08, 0.0, 0.0))
	# Floating ribs, hanging off the bottom of the cage and joined to nothing at
	# the front. They have to sweep down and *around* the belly - anything less
	# than horizontal and they read as antennae growing out of its chest.
	for side: float in [-1.0, 1.0]:
		for i: int in range(2):
			_part(
				_thorax,
				'FloatRib',
				_cone(0.006, 0.019, 0.26, _mat_bone, 5),
				Vector3(side * 0.115, -0.090 - float(i) * 0.070, -0.010),
				Vector3(-0.45 - float(i) * 0.12, side * 0.28, side * 2.55),
				Vector3.ONE,
				false
			)
	# The chest and flank cluster: the eyes the concept art puts front and centre.
	_eye(_thorax, Vector3(-0.055, 0.130, -0.140), Vector3(-0.10, 0.22, 0.0), 0.028)
	_eye(_thorax, Vector3(0.062, 0.190, -0.130), Vector3(-0.16, -0.20, 0.0), 0.024)
	_eye(_thorax, Vector3(-0.020, 0.010, -0.150), Vector3(0.14, 0.06, 0.0), 0.031)
	for side: float in [-1.0, 1.0]:
		_eye(_thorax, Vector3(side * 0.155, 0.09, -0.045), Vector3(-0.05, side * 1.25, 0.0), 0.022)


func _build_arms() -> void:
	# Clavicles rather than a plate. A box across the shoulders reads as a shelf
	# bolted to the creature; two bones running out to the joints read as a
	# starved animal.
	for side: float in [-1.0, 1.0]:
		_part(_shoulders, 'Clavicle', _cone(0.026, 0.014, 0.24, _mat_bone, 5),
			Vector3(side * 0.115, -0.010, -0.020), Vector3(0.20, 0.0, side * 1.42))
		_part(_shoulders, 'ScapulaBlade', _cone(0.010, 0.038, 0.16, _mat_bone, 5),
			Vector3(side * 0.115, 0.010, 0.055), Vector3(1.05, side * 0.35, side * 0.75),
			Vector3.ONE, false)
	for side: float in [-1.0, 1.0]:
		_arms.append(_build_arm(side))


func _build_arm(side: float) -> Dictionary:
	var shoulder := _pivot(
		_shoulders,
		'Shoulder',
		Vector3(side * SHOULDER_X, -0.02, 0.015),
		Vector3(ARM_REST_X, 0.0, side * ARM_REST_Z)
	)
	_ball(shoulder, 'ShoulderBall', 0.082, _mat_flesh)
	_part(shoulder, 'ScapulaSpur', _cone(0.004, 0.026, 0.20, _mat_bone, 5),
		Vector3(side * 0.02, 0.02, 0.06), Vector3(2.35, 0.0, side * 0.30), Vector3.ONE, false)
	var elbow := _limb(shoulder, 'Humerus', 0.082, 0.056, HUMERUS_LEN, _mat_flesh, true)
	_eye(shoulder, Vector3(side * 0.070, -0.170, -0.020), Vector3(-0.10, side * 1.15, 0.0), 0.022)
	_ball(elbow, 'ElbowCap', 0.058, _mat_bone)
	# The joints watch too - this is the "mắt ở khớp" detail panel.
	_eye(elbow, Vector3(side * 0.045, -0.010, -0.030), Vector3(0.0, side * 0.85, 0.0), 0.020)

	var forearm := _pivot(elbow, 'ForearmPivot', Vector3.ZERO, Vector3(FOREARM_REST, 0.0, 0.0))
	var wrist := _limb(forearm, 'Radius', 0.056, 0.038, RADIUS_LEN, _mat_flesh, true)
	# An ulna running alongside, so the forearm reads as two bones under skin
	# rather than one tube.
	_part(forearm, 'Ulna', _cone(0.020, 0.030, RADIUS_LEN * 0.92, _mat_bone, 5),
		Vector3(side * 0.030, -RADIUS_LEN * 0.48, 0.022), Vector3(0.04, 0.0, side * 0.05))
	_eye(forearm, Vector3(side * 0.048, -0.340, -0.012), Vector3(0.0, side * 1.00, 0.0), 0.018)

	var hand := _pivot(wrist, 'HandPivot', Vector3.ZERO, Vector3(HAND_REST, 0.0, 0.0))
	_part(hand, 'Palm', _box(Vector3(0.098, 0.135, 0.048), _mat_flesh), Vector3(0.0, -0.062, 0.0))
	_ball(hand, 'WristBall', 0.040, _mat_bone)

	var fingers: Array[Dictionary] = []
	for f: int in range(FINGER_COUNT):
		var spread := lerpf(-1.0, 1.0, float(f) / float(FINGER_COUNT - 1))
		var base := _pivot(
			hand,
			'Finger%d' % f,
			Vector3(spread * 0.040, -0.128, -0.008),
			Vector3(0.16 + absf(spread) * 0.10, spread * 0.34, spread * 0.42)
		)
		var mid := _limb(base, 'Phalanx0', 0.021, 0.015, 0.165, _mat_flesh, true, 5)
		_telescope(float(f) * 0.5)
		# The knuckle bends the wrong way. It is the cheapest possible tell that
		# the hand was never a hand.
		var mid_pivot := _pivot(mid, 'Knuckle0', Vector3.ZERO, Vector3(-0.62, 0.0, 0.0))
		var tip := _limb(mid_pivot, 'Phalanx1', 0.015, 0.010, 0.145, _mat_flesh, true, 5)
		_telescope(float(f) * 0.5 + 0.9)
		var tip_pivot := _pivot(tip, 'Knuckle1', Vector3.ZERO, Vector3(0.88, 0.0, 0.0))
		_limb(tip_pivot, 'Claw', 0.010, 0.001, 0.115, _mat_bone, true, 5, false)
		fingers.append({'base': base, 'mid': mid_pivot, 'tip': tip_pivot, 'index': f})

	# A thumb spur, set high on the palm and hooked back on itself.
	var thumb := _pivot(hand, 'Thumb', Vector3(side * 0.052, -0.055, 0.010),
		Vector3(0.35, side * -0.60, side * -1.15))
	var thumb_knuckle := _limb(thumb, 'ThumbBone', 0.018, 0.012, 0.115, _mat_flesh, true, 5)
	var thumb_claw := _pivot(thumb_knuckle, 'ThumbClawPivot', Vector3.ZERO, Vector3(-0.75, 0.0, 0.0))
	_limb(thumb_claw, 'ThumbClaw', 0.012, 0.001, 0.095, _mat_bone, true, 5, false)
	fingers.append({'base': thumb, 'mid': thumb_claw, 'tip': thumb_claw, 'index': FINGER_COUNT})

	return {'shoulder': shoulder, 'forearm': forearm, 'hand': hand, 'fingers': fingers, 'side': side}


func _build_head() -> void:
	var node := _pivot(_shoulders, 'NeckRoot', Vector3(0.0, 0.02, -0.02))
	for i: int in range(NECK_REST.size()):
		var segment := _pivot(node, 'Neck%d' % i, Vector3.ZERO, Vector3(NECK_REST[i], 0.0, 0.0))
		_neck_pivots.append(segment)
		node = _limb(segment, 'NeckBone%d' % i, 0.060, 0.050, NECK_LEN, _mat_flesh)
		# The neck telescopes: when it commits to a grab, the head arrives
		# before the body does.
		_telescope(float(i) * 1.4)
		_part(segment, 'NeckBarb', _cone(0.003, 0.016, 0.11, _mat_bone, 5),
			Vector3(0.0, NECK_LEN * 0.5, 0.045), Vector3(2.30, 0.0, 0.0), Vector3.ONE, false)

	head_pivot = _pivot(node, 'HeadPivot', Vector3(0.0, 0.025, 0.0))
	# Small, narrow and shrivelled - the concept art's head is barely a head. It
	# is a tall thin wedge of bone with one big wet eye on each side and a short
	# pointed snout, and it sits *under* the crown rather than in front of it.
	# The reason it must stay small: the hole is the face. Anything long enough
	# to read as a beak turns the creature into a bird and the crown into a hat.
	_part(head_pivot, 'Skull', _sphere(0.095, _mat_bone, 8, 5), Vector3(0.0, 0.010, -0.030),
		Vector3.ZERO, Vector3(0.70, 1.12, 1.20))
	_part(head_pivot, 'Occiput', _sphere(0.082, _mat_flesh, 7, 4), Vector3(0.0, 0.02, 0.045),
		Vector3.ZERO, Vector3(0.92, 1.0, 0.90))
	# Cheekbones, so the narrow skull reads as starved rather than smooth.
	for side: float in [-1.0, 1.0]:
		_part(head_pivot, 'Cheek', _cone(0.010, 0.026, 0.10, _mat_bone, 5),
			Vector3(side * 0.048, -0.010, -0.055), Vector3(-1.15, side * 0.30, side * 0.55),
			Vector3.ONE, false)
	var snout := _pivot(head_pivot, 'SnoutPivot', Vector3(0.0, -0.020, -0.078), Vector3(-2.05, 0.0, 0.0))
	_limb(snout, 'Snout', 0.036, 0.003, 0.150, _mat_bone, false, 6)
	for side: float in [-1.0, 1.0]:
		_part(head_pivot, 'BrowRidge', _cone(0.004, 0.018, 0.10, _mat_bone, 5),
			Vector3(side * 0.048, 0.062, -0.070), Vector3(-1.20, side * 0.25, 0.0), Vector3.ONE, false)
		# The one pair of eyes in roughly the place a face would put them, which
		# is what makes the other forty worse. Big, wet and glassy: in the
		# concept sheet they are the only part of the head you actually read.
		_eye(head_pivot, Vector3(side * 0.058, 0.022, -0.072), Vector3(-0.05, side * 0.78, 0.0), 0.034)

	jaw_pivot = _pivot(head_pivot, 'JawPivot', Vector3(0.0, -0.048, -0.052))
	var jaw := _pivot(jaw_pivot, 'JawAim', Vector3.ZERO, Vector3(-1.90, 0.0, 0.0))
	_limb(jaw, 'Mandible', 0.030, 0.004, 0.125, _mat_bone, false, 5)
	for t: int in range(3):
		_part(
			jaw,
			'Tooth%d' % t,
			_cone(0.0008, 0.008, 0.032 - float(t) * 0.006, _mat_bone, 4),
			Vector3(0.0, 0.030 + float(t) * 0.033, -0.014),
			Vector3(-0.45, 0.0, 0.0),
			Vector3.ONE,
			false
		)

	_build_crown()


## The crown: a ring of bone spines around a hole, tilted forward so it faces
## whatever the creature is walking at. The gaze cone the AI tests against comes
## out of the middle of it, so the thing on screen that is looking at you is
## exactly the thing that can catch you.
func _build_crown() -> void:
	var root := _pivot(head_pivot, 'CrownRoot', Vector3(0.0, 0.076, 0.052), Vector3(-0.34, 0.0, 0.0))
	_crown_hub = _pivot(root, 'CrownHub')
	_part(_crown_hub, 'VoidRim', _ring(VOID_RADIUS * 0.94, VOID_RADIUS * 1.30, _mat_flesh),
		Vector3(0.0, 0.0, 0.020), Vector3(PI * 0.5, 0.0, 0.0), Vector3(1.0, 1.0, 0.55))
	_void_core = _part(
		_crown_hub,
		'Void',
		_sphere(VOID_RADIUS, _mat_void, 10, 6),
		Vector3(0.0, 0.0, 0.055),
		Vector3.ZERO,
		Vector3(1.0, 1.0, 0.62),
		false
	)

	gaze_pivot = _pivot(_crown_hub, 'GazePivot', Vector3(0.0, 0.0, -0.020))
	gaze_light = SpotLight3D.new()
	gaze_light.name = 'GazeLight'
	gaze_light.light_color = Color(0.62, 0.70, 0.82)
	gaze_light.light_energy = 3.2
	gaze_light.light_indirect_energy = 0.6
	# Off by default, and it is the first thing to turn back on if the frame
	# budget ever allows it. A *moving* shadow-casting spotlight re-renders every
	# lit caster in range - the creature and a good chunk of the house - into a
	# shadow map every single frame, which made it far and away the most
	# expensive thing about having this thing in the building.
	gaze_light.shadow_enabled = gaze_casts_shadows
	gaze_light.spot_range = 15.0
	gaze_light.spot_attenuation = 1.35
	gaze_light.spot_angle = 34.0
	gaze_light.spot_angle_attenuation = 0.55
	gaze_pivot.add_child(gaze_light)

	# Two rings, offset from each other, because the concept sheet's crown is
	# *dense*: a thicket of thin jointed arms, not ten spokes on a wheel. The
	# inner ring is shorter and sits between the outer ones, which is what fills
	# the gaps and stops the whole thing reading as a cartoon sun.
	for i: int in range(CROWN_SPINES):
		_build_crown_arm(i, TAU * float(i) / float(CROWN_SPINES), 1.0, true)
	for i: int in range(CROWN_INNER_SPINES):
		var offset := TAU / float(CROWN_INNER_SPINES) * 0.5
		_build_crown_arm(
			CROWN_SPINES + i, TAU * float(i) / float(CROWN_INNER_SPINES) + offset, 0.66, false
		)


## One crown limb. These are not spikes: in the concept sheet they are *arms* -
## thin, jointed, barbed, three segments with a knuckle between each, and they
## never stop moving. Building them as a chain is what lets every joint bend on
## its own clock in `_animate_crown`, which is the whole difference between a
## crown and a hairstyle.
##
## `length_scale` shortens the inner ring; only the outer ring gets an eye and
## side hooks, which keeps the part count sane while the silhouette still reads
## as barbed all the way round.
func _build_crown_arm(index: int, angle: float, length_scale: float, outer: bool) -> void:
	var arm_root := _pivot(
		_crown_hub, 'CrownArm%02d' % index, Vector3.ZERO, Vector3(0.0, 0.0, angle)
	)
	# Once the root has spun the arm around the ring, its own local X tips it out
	# of that plane - so one angle opens or closes the whole crown.
	var tilt := _pivot(
		arm_root,
		'Tilt',
		Vector3(0.0, VOID_RADIUS * (0.92 if outer else 0.72), 0.0),
		Vector3(CROWN_REST_TILT + (0.0 if outer else 0.22), 0.0, 0.0)
	)

	var joints: Array[Node3D] = []
	var node := tilt
	var radii: Array[float] = [0.016, 0.011, 0.007, 0.002]
	var lengths: Array[float] = [0.125, 0.105, 0.082]
	for segment: int in range(CROWN_ARM_SEGMENTS):
		if segment > 0:
			# A knuckle. The rest bends alternate direction down the limb, so
			# even standing still each arm is a crooked, insect-like thing
			# rather than a bent stick.
			node = _pivot(
				node,
				'Knuckle%d' % segment,
				Vector3.ZERO,
				Vector3(0.34 if segment == 1 else -0.26, 0.0, 0.0)
			)
			joints.append(node)
		node = _limb(
			node,
			'Bone%d' % segment,
			radii[segment],
			radii[segment + 1],
			lengths[segment] * length_scale,
			_mat_bone,
			false,
			5,
			false
		)
		if outer and segment == CROWN_ARM_SEGMENTS - 1:
			_telescope(float(index) * 0.63)

	var eye_pivot: Node3D = null
	if outer:
		# One hook off the first segment, so the ring stays barbed in silhouette
		# even when the arms are folded shut. Two looked marginally better and
		# cost thirteen more draw calls on a creature that already has three
		# hundred.
		_part(
			tilt,
			'Hook',
			_cone(0.001, 0.006, 0.040, _mat_bone, 4),
			Vector3(0.0, 0.055, 0.0),
			Vector3(-1.75, 0.0, 0.0),
			Vector3.ONE,
			false
		)
		eye_pivot = _eye(node, Vector3(0.0, 0.003, 0.0), Vector3(-1.30, 0.0, 0.0), 0.014)
	_crown.append({
		'root': arm_root,
		'tilt': tilt,
		'joints': joints,
		'eye': eye_pivot,
		'angle': angle,
		'index': index,
	})


func _build_tail() -> void:
	var node := _pivot(_hips, 'TailRoot', Vector3(0.0, 0.015, 0.125), Vector3(TAIL_ROOT_REST, 0.0, 0.0))
	for i: int in range(TAIL_SEGMENTS):
		var ratio := float(i) / float(TAIL_SEGMENTS - 1)
		var segment := _pivot(node, 'Tail%02d' % i, Vector3.ZERO, Vector3(TAIL_REST, 0.0, 0.0))
		_tail_pivots.append(segment)
		var length := lerpf(0.150, 0.060, ratio)
		var base_radius := lerpf(0.078, 0.018, ratio)
		node = _limb(
			segment,
			'Caudal%02d' % i,
			base_radius,
			lerpf(0.070, 0.013, ratio),
			length,
			_mat_flesh,
			false,
			6,
			i < 8
		)
		_part(
			segment,
			'CaudalBarb%02d' % i,
			_cone(0.002, base_radius * 0.42, lerpf(0.15, 0.075, ratio), _mat_bone, 5),
			Vector3(0.0, length * 0.55, 0.0),
			Vector3(-1.15, 0.0, 0.0),
			Vector3.ONE,
			false
		)
		# Banded on every other vertebra rather than all twelve: at a glance the
		# tail reads exactly the same and it is six fewer draw calls.
		if i % 2 == 0:
			_part(
				segment,
				'CaudalRing%02d' % i,
				_ring(base_radius * 1.02, base_radius * 1.34, _mat_bone),
				Vector3(0.0, length * 0.18, 0.0),
				Vector3.ZERO,
				Vector3.ONE,
				false
			)
		if i % 3 == 1:
			_eye(segment, Vector3(0.0, length * 0.5, -base_radius * 0.95),
				Vector3(1.35, 0.0, 0.0), lerpf(0.021, 0.014, ratio))
	# The scythe: the last thing on it, and the part the concept art hooks
	# ceilings with.
	var sting := _pivot(node, 'StingPivot', Vector3.ZERO, Vector3(-0.55, 0.0, 0.0))
	_limb(sting, 'Sting', 0.014, 0.001, 0.24, _mat_bone, false, 5, false)


func _build_drips() -> void:
	var anchors: Array[Node3D] = [_thorax, _thorax, _hips, _shoulders, jaw_pivot, _crown_hub]
	for arm: Dictionary in _arms:
		anchors.append(arm['hand'])
		anchors.append(arm['forearm'])
	for i: int in range(DRIP_COUNT):
		var parent: Node3D = anchors[i % anchors.size()]
		var origin := Vector3(
			randf_range(-0.09, 0.09), randf_range(-0.10, 0.02), randf_range(-0.06, 0.06)
		)
		var node := _pivot(parent, 'Drip%d' % i, origin)
		var mesh := _part(node, 'Bead', _sphere(0.020, _mat_slime, 6, 4),
			Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		_drips.append({
			'node': node,
			'mesh': mesh,
			'origin': origin,
			'fall': randf_range(0.16, 0.34),
			'speed': randf_range(0.35, 0.85),
			't': randf(),
		})


# --- Animation ---------------------------------------------------------------


## One frame of the whole body. Called from `hunter_ghost.gd` after it has set
## the inputs at the top of this file.
func advance(delta: float) -> void:
	if not _built:
		return
	_clock += delta
	_reach = move_toward(_reach, 1.0 if charging else 0.0, delta * 2.4)
	_watcher_distance = global_position.distance_to(look_point) if has_look_point else INF
	_animate_gait(delta)
	_animate_spine(delta)
	_animate_arms(delta)
	_animate_head(delta)
	_animate_crown(delta)
	_animate_tail(delta)
	_animate_eyes(delta)
	# Beads of slime a centimetre across are not resolvable from across a room,
	# and they are nine transform writes a frame.
	if _watcher_distance <= detail_distance:
		_animate_drips(delta)
	_animate_stretch()
	_update_materials()


## The gait is driven by ground covered, not by time: one stride per
## `stride_length` of travel, so the feet always land where the legs are.
func _animate_gait(delta: float) -> void:
	var previous := _stride_phase
	_stride_phase += locomotion_speed / maxf(stride_length, 0.05) * delta * TAU * 0.5
	# It never stands still. Even stopped, the weight shifts from foot to foot.
	var idle := maxf(0.0, 1.0 - locomotion_speed * 1.6)
	var idle_sway := sin(_clock * 0.9) * 0.05 * idle

	for i: int in range(_legs.size()):
		var leg: Dictionary = _legs[i]
		var side: float = leg['side']
		var swing := sin(_stride_phase + (PI if i == 1 else 0.0))
		var lift := maxf(swing, 0.0)
		var hip: Node3D = leg['hip']
		var knee: Node3D = leg['knee']
		var meta: Node3D = leg['meta']
		var foot: Node3D = leg['foot']
		hip.rotation.x = FEMUR_REST + swing * 0.46 + idle_sway * side
		hip.rotation.z = side * (0.05 + lift * 0.07)
		# The shin tucks hard on the lift and snaps out for the plant, which is
		# what makes a digitigrade leg read as a leg and not a stilt.
		knee.rotation.x = TIBIA_REST - lift * 0.66 - idle * 0.04
		meta.rotation.x = META_REST + maxf(-swing, 0.0) * 0.46 + lift * 0.18
		foot.rotation.x = FOOT_REST - swing * 0.30

	# The whole body drops onto each planted foot: a long, uneven stalk rather
	# than a walk cycle. The charge lean lives on the spine instead of here -
	# leaning at the root would pivot around the floor and drive the feet
	# through it.
	_body.position.y = -absf(sin(_stride_phase)) * 0.038
	_body.rotation.z = sin(_stride_phase) * 0.055 + sin(_clock * 0.7) * 0.012 * idle
	_body.rotation.x = sin(_stride_phase * 2.0) * 0.014
	_body.rotation.y = sin(_stride_phase * 0.5) * 0.045

	if int(previous / PI) != int(_stride_phase / PI) and locomotion_speed > 0.25:
		foot_planted.emit(locomotion_speed)


func _animate_spine(_delta: float) -> void:
	# Breathing runs down the spine as a travelling wave rather than a uniform
	# scale, so the ribcage swells a beat after the belly does.
	var breath_rate := lerpf(1.1, 3.4, agitation)
	var moving := clampf(locomotion_speed * 0.5, 0.0, 1.0)
	for i: int in range(_spine_pivots.size()):
		var segment := _spine_pivots[i]
		var wave := sin(_clock * breath_rate - float(i) * 0.55)
		# The lean into a charge is spread over all five vertebrae, so the whole
		# torso folds down over the legs instead of the creature tipping.
		segment.rotation.x = SPINE_REST + wave * 0.030 - agitation * 0.062
		segment.rotation.y = sin(_stride_phase * 0.5 + float(i) * 0.40) * 0.040 * moving
		segment.rotation.z = sin(_stride_phase + float(i) * 0.30) * 0.022 * moving
	var swell := 1.0 + sin(_clock * breath_rate - 1.1) * (0.030 + agitation * 0.025)
	_thorax.scale = Vector3(swell, 1.0 + (swell - 1.0) * 0.45, swell)


func _animate_arms(_delta: float) -> void:
	for i: int in range(_arms.size()):
		var arm: Dictionary = _arms[i]
		var side: float = arm['side']
		# Arms counter-swing against the legs.
		var swing := sin(_stride_phase + (0.0 if i == 1 else PI))
		var shoulder: Node3D = arm['shoulder']
		var forearm: Node3D = arm['forearm']
		var hand: Node3D = arm['hand']
		shoulder.rotation.x = ARM_REST_X + swing * 0.32 - agitation * 0.22
		shoulder.rotation.z = side * (ARM_REST_Z + agitation * 0.18) \
			+ sin(_clock * 0.8 + side) * 0.035
		shoulder.rotation.y = side * sin(_clock * 0.5 + side * 1.3) * 0.06
		# Hanging at rest, cocked back and ready when it is charging.
		forearm.rotation.x = FOREARM_REST - absf(swing) * 0.18 - _reach * 0.55
		hand.rotation.x = HAND_REST + sin(_clock * 1.3 + side) * 0.10 + _reach * 0.35
		hand.rotation.z = side * sin(_clock * 1.7) * 0.08

		for finger: Dictionary in arm['fingers']:
			var index: float = float(finger['index'])
			var twitch := sin(_clock * (1.7 + index * 0.31) + index * 1.9 + side)
			# Fingers curl into a grab as it commits, and never stop working
			# even when they are not.
			var curl := _reach * 0.55 + maxf(twitch, 0.0) * 0.13
			var base: Node3D = finger['base']
			var mid: Node3D = finger['mid']
			var tip: Node3D = finger['tip']
			base.rotation.x = 0.16 + absf(index - 1.5) * 0.05 + twitch * 0.14 + curl * 0.45
			if mid != tip:
				mid.rotation.x = -0.62 - curl * 0.70 + sin(_clock * (2.3 + index * 0.17)) * 0.11
				tip.rotation.x = 0.88 + curl * 0.80
			else:
				mid.rotation.x = -0.75 - curl * 0.40


func _animate_head(delta: float) -> void:
	var blend := minf(delta * 4.0, 1.0)
	for i: int in range(_neck_pivots.size()):
		var segment := _neck_pivots[i]
		var scan := sin(_clock * (1.4 if searching else 0.45) - float(i) * 0.7)
		segment.rotation.x = lerpf(
			segment.rotation.x,
			NECK_REST[i] + (0.10 if searching else -0.06) - _reach * 0.14,
			blend
		)
		segment.rotation.y = scan * (0.22 if searching else 0.06)
		segment.rotation.z = sin(_clock * 0.8 - float(i)) * 0.03

	# Nose down and reading the floor while it searches; level the instant it
	# is charging something.
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, 0.30 if searching else -0.10, blend)
	head_pivot.rotation.y = sin(_clock * (1.6 if searching else 0.4)) * (0.40 if searching else 0.08)
	# A bird's head-cock. Nothing about it is a bird.
	head_pivot.rotation.z = sin(_clock * 0.55) * (0.20 if searching else 0.07)

	_jaw_open = move_toward(_jaw_open, 1.0 if charging else 0.10, delta * 3.0)
	jaw_pivot.rotation.x = _jaw_open * 0.52 + sin(_clock * 9.0) * 0.02 * agitation


## The crown is a nest of arms and it never holds still: every limb, and every
## knuckle inside every limb, runs on its own frequency and its own phase, so
## the ring is never symmetrical for a single frame and never repeats. Over the
## top of that the whole crown breathes - the arms fold in and drag air toward
## the hole in the middle, then flare. Fully open is what a charge looks like
## from the front.
func _animate_crown(delta: float) -> void:
	var target := lerpf(CROWN_REST_TILT, CROWN_OPEN_TILT, agitation)
	_crown_flare = lerpf(_crown_flare, target, minf(delta * 3.0, 1.0))
	var inhale := sin(_clock * lerpf(1.5, 4.2, agitation)) * (0.07 + agitation * 0.05)
	# They work faster the closer it is to committing, which turns the crown
	# into the tell: a ring that starts thrashing means it has seen something.
	var writhe := 1.0 + agitation * 1.3
	for entry: Dictionary in _crown:
		var index := float(entry['index'])
		var tilt: Node3D = entry['tilt']
		var root: Node3D = entry['root']
		tilt.rotation.x = _crown_flare + inhale \
			+ sin(_clock * writhe * (2.1 + index * 0.23) + index) * 0.11
		tilt.rotation.z = sin(_clock * writhe * (1.7 + index * 0.13) + index * 2.2) * 0.10
		root.rotation.z = entry['angle'] + sin(_clock * (0.8 + index * 0.11)) * 0.055
		root.rotation.y = sin(_clock * (1.3 + index * 0.17) + index) * 0.07

		var joints: Array[Node3D] = entry['joints']
		for j: int in range(joints.size()):
			var joint := joints[j]
			var rest := 0.34 if j == 0 else -0.26
			var offset := index * 0.7 + float(j) * 1.9
			# Each knuckle lags the one before it, so the movement travels out
			# along the arm instead of the whole limb waving as one piece.
			joint.rotation.x = rest \
				+ sin(_clock * writhe * (2.6 + index * 0.19 + float(j) * 0.53) + offset) * 0.30
			joint.rotation.y = sin(_clock * writhe * (2.1 + float(j) * 0.37) + offset * 1.4) * 0.22

	if searching:
		gaze_pivot.rotation.y = sin(_clock * 1.1) * 0.28
	else:
		gaze_pivot.rotation.y = lerpf(gaze_pivot.rotation.y, 0.0, minf(delta * 5.0, 1.0))
	# The hole widens before it moves.
	var dilate := 1.0 + agitation * 0.30 + sin(_clock * 2.6) * 0.04
	_void_core.scale = Vector3(dilate, dilate, 0.62 * dilate)


## A wave travelling from the base to the tip, plus a curl that pulls the whole
## tail up over its back as it commits - the tell that a charge is coming.
func _animate_tail(_delta: float) -> void:
	var count := float(_tail_pivots.size())
	var rate := lerpf(1.3, 3.6, agitation) + clampf(locomotion_speed * 0.35, 0.0, 1.2)
	for i: int in range(_tail_pivots.size()):
		var segment := _tail_pivots[i]
		var ratio := float(i) / maxf(count - 1.0, 1.0)
		# Amplitude grows toward the tip: the base steers, the tip whips.
		var amplitude := 0.035 + ratio * ratio * 0.16
		var wave := sin(_clock * rate - float(i) * 0.46)
		segment.rotation.x = TAIL_REST - agitation * 0.075 * ratio + wave * amplitude * 0.55
		segment.rotation.y = sin(_clock * rate * 0.8 - float(i) * 0.55) * amplitude
		segment.rotation.z = sin(_clock * rate * 0.6 - float(i) * 0.33) * amplitude * 0.5


func _animate_eyes(delta: float) -> void:
	# Aiming is the expensive branch - a global-transform query and a basis
	# inverse per eye - so it is spread round-robin over EYE_AIM_STRIDE frames and
	# given a proportionally larger step. Blinking is a scale write and stays on
	# every frame for every eye, because that is what actually reads as alive.
	_eye_cursor += 1
	var aim_weight := minf(delta * 3.0 * float(EYE_AIM_STRIDE), 1.0)
	var wander_weight := minf(delta * 1.5 * float(EYE_AIM_STRIDE), 1.0)
	var tracking := has_look_point and _watcher_distance <= detail_distance
	for index: int in range(_eyes.size()):
		var entry: Dictionary = _eyes[index]
		var pivot: Node3D = entry['pivot']
		var mesh: MeshInstance3D = entry['mesh']
		var aim_this_frame := (index + _eye_cursor) % EYE_AIM_STRIDE == 0

		if not aim_this_frame:
			pass
		elif tracking:
			# Every eye finds you on its own schedule, so they arrive raggedly
			# instead of snapping to attention together.
			var to_point := look_point - pivot.global_position
			if to_point.length_squared() > 0.0009:
				var up := Vector3.UP
				if absf(to_point.normalized().y) > 0.999:
					up = Vector3.FORWARD
				var wanted := Basis.looking_at(to_point, up)
				var local := pivot.get_parent_node_3d().global_basis.inverse() * wanted
				pivot.basis = pivot.basis.orthonormalized().slerp(
					local.orthonormalized(), minf(aim_weight * float(entry['speed']), 1.0)
				).orthonormalized()
		else:
			# Nothing to look at: they drift, independently, through their full
			# range. The concept art's "xoay độc lập 360°".
			var phase: float = entry['phase']
			var speed: float = entry['speed']
			var wander := Basis.from_euler(Vector3(
				sin(_clock * speed * 0.7 + phase) * 0.55,
				sin(_clock * speed * 0.5 + phase * 1.7) * 1.20,
				0.0
			))
			var rest: Basis = entry['rest']
			pivot.basis = pivot.basis.orthonormalized().slerp(
				(rest * wander).orthonormalized(), wander_weight
			).orthonormalized()

		# Blinks are per-eye and never synchronised, which is most of why a
		# body covered in eyes reads as alive rather than as decoration.
		var blink_t: float = entry['blink_t']
		if blink_t >= 0.0:
			blink_t += delta
			if blink_t >= 0.16:
				entry['blink_t'] = -1.0
				entry['blink_in'] = randf_range(1.2, 7.0) / lerpf(1.0, 2.4, agitation)
				mesh.scale = Vector3.ONE
			else:
				entry['blink_t'] = blink_t
				# Down and back up inside a sixth of a second.
				mesh.scale = Vector3(1.0, 1.0 - sin(blink_t / 0.16 * PI) * 0.94, 1.0)
		else:
			var blink_in: float = float(entry['blink_in']) - delta
			entry['blink_in'] = blink_in
			if blink_in <= 0.0:
				entry['blink_t'] = 0.0


func _animate_drips(delta: float) -> void:
	for entry: Dictionary in _drips:
		var t: float = float(entry['t']) + delta * float(entry['speed'])
		if t >= 1.0:
			t -= 1.0
			entry['speed'] = randf_range(0.35, 0.85)
			entry['fall'] = randf_range(0.16, 0.34)
		entry['t'] = t
		var node: Node3D = entry['node']
		var mesh: MeshInstance3D = entry['mesh']
		var origin: Vector3 = entry['origin']
		node.position = origin + Vector3(0.0, -float(entry['fall']) * t * t, 0.0)
		# Gathers, stretches as it lets go, then it is simply gone.
		var swell := sin(clampf(t, 0.0, 1.0) * PI)
		mesh.scale = Vector3(swell * 0.9, swell * (0.7 + t * 1.6), swell * 0.9)


## Telescoping segments: the mesh stretches and the joint at its end slides out
## with it, carrying everything further down the chain.
func _animate_stretch() -> void:
	for entry: Dictionary in _stretchers:
		var phase: float = entry['phase']
		var amount := 1.0 + _reach * 0.28 + sin(_clock * 1.9 + phase) * 0.035
		var mesh: MeshInstance3D = entry['mesh']
		var joint: Node3D = entry['joint']
		var length: float = entry['length']
		mesh.scale.y = amount
		mesh.position.y = length * 0.5 * amount
		joint.position.y = length * amount


func _update_materials() -> void:
	var glow := lerpf(0.25, 0.85, agitation)
	for material: ShaderMaterial in [_mat_flesh, _mat_bone]:
		material.set_shader_parameter('agitation', agitation)
		material.set_shader_parameter('gaze_glow', glow)
	_mat_eye.set_shader_parameter('agitation', agitation)
	# The pupils pin the moment it has something to charge at.
	_mat_eye.set_shader_parameter('pupil_size', lerpf(0.22, 0.055, agitation))
	_mat_eye.set_shader_parameter('iris_glow', lerpf(0.9, 3.2, agitation))

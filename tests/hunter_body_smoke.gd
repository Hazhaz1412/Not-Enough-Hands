extends SceneTree

## Covers the huntsman's body rather than its hunt (`hunter_ghost_smoke.gd` owns
## that). The body is `ghosts/ghost_visual.tscn` - the Midnight Grin biped, the
## same one file the door encounter wears - and it is reached only through the
## surface `hunter_ghost.gd` drives. Three things rot silently across a model
## swap:
##
##   1. the body stops fitting through the house - the doors are 2.35 m and the
##      ceilings 3.0 m, so a rig imported at the wrong unit scale walks through
##      every lintel;
##   2. its feet stop meeting the floor the collision capsule is standing on;
##   3. a clip `_clip_for_state()` can return is not in the library, so the
##      Huntsman silently holds whichever pose it was already in.
##
## The gaze light is checked too, because detection is tested against its cone:
## if it stops being at head height, the player sees the creature look somewhere
## other than where it is actually looking.
##
## What is deliberately *not* here: the identity, height, material and
## uprightness of the shared body, which `door_ghost_minigame_smoke.gd` already
## asserts once for both ghosts.

## Matches villa_house.gd's DOOR_CLEAR_HEIGHT: anything taller cannot follow a
## player through a doorway without clipping the frame.
const DOOR_CLEAR_HEIGHT := 2.4
## The widest defense door opening in the project.
const DOOR_CLEAR_WIDTH := 2.0
const FRAME := 1.0 / 60.0

## Every clip `hunter_ghost.gd::_clip_for_state()` can name, and nothing else.
const HUNT_CLIPS := [&"Idle", &"Walk", &"Run", &"Attack", &"Skill 3"]

var hunter: Node3D
var rig: GhostVisual


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load('res://ghosts/hunter_ghost.tscn') as PackedScene
	hunter = scene.instantiate()
	root.add_child(hunter)
	rig = hunter.get_node('VisualRoot') as GhostVisual
	if rig == null:
		_fail('The huntsman VisualRoot is not a GhostVisual.')
		return

	if not _test_it_is_the_shared_body():
		return
	if not _test_it_fits_through_the_house():
		return
	if not _test_it_stands_on_the_floor():
		return
	if not _test_every_hunt_clip_exists():
		return
	if not _test_the_gaze_is_at_head_height():
		return

	var bounds := _bounds()
	print(
		'Hunter body smoke test passed: Midnight Grin body %.2f m tall and %.2f m wide, '
		% [bounds.position.y + bounds.size.y, bounds.size.x]
		+ 'feet on the floor, %d hunt clips resolved, gaze at head height.'
		% HUNT_CLIPS.size()
	)
	quit()


## The Huntsman must wear the imported model itself, not merely reference it:
## the live tree has to contain its skinned mesh under a real skeleton.
func _test_it_is_the_shared_body() -> bool:
	var meshes := _meshes()
	if meshes.size() != 1 or meshes[0].skin == null:
		return _fail(
			'Expected the one skinned Midnight Grin mesh under VisualRoot, found %d: %s'
			% [meshes.size(), str(meshes.map(func(m: Node) -> String: return m.name))]
		)
	if rig.find_child('Skeleton3D', true, false) == null:
		return _fail('The body has no Skeleton3D, so no clip can reach it.')
	return true


## Checked in every pose it can be in while it is in the house. The clips are
## rotation-only, so the sway in `advance()` is the only thing that can widen
## the silhouette - and lean is exactly the sort of thing that grows in a retune.
func _test_it_fits_through_the_house() -> bool:
	var poses := {
		'built': [0.0, 0.0, false, false],
		'searching': [1.2, 0.35, true, false],
		'walking': [1.6, 0.0, false, false],
		'charging': [3.4, 1.0, false, true],
	}
	for label: String in poses:
		var pose: Array = poses[label]
		if label != 'built':
			for step: int in range(120):
				_drive(pose[0], pose[1], pose[2], pose[3], FRAME)
		var bounds := _bounds()
		# The top of the creature above the floor, not its total extent: a heel
		# that sinks a centimetre into the boards does not have to clear a lintel.
		var top := bounds.position.y + bounds.size.y
		if top > DOOR_CLEAR_HEIGHT:
			return _fail(
				'%s silhouette is %.2f m tall and will not clear a %.2f m doorway.'
				% [label, top, DOOR_CLEAR_HEIGHT]
			)
		if bounds.size.x > DOOR_CLEAR_WIDTH:
			return _fail(
				'%s silhouette is %.2f m wide and will not clear a %.2f m doorway.'
				% [label, bounds.size.x, DOOR_CLEAR_WIDTH]
			)
	return true


## The collision capsule stands with its base on y = 0, so the feet have to as
## well - through the whole stride, not just in the rest pose.
func _test_it_stands_on_the_floor() -> bool:
	var lowest := INF
	var highest_low := -INF
	for step: int in range(180):
		_drive(1.6, 0.0, true, false, FRAME)
		var floor_y := _bounds().position.y
		lowest = minf(lowest, floor_y)
		highest_low = maxf(highest_low, floor_y)
	if lowest < -0.09:
		return _fail('Feet sink %.3f m through the floor mid-stride.' % -lowest)
	if highest_low > 0.09:
		return _fail('Creature floats %.3f m above the floor mid-stride.' % highest_low)
	return true


## `_clip_for_state()` names five clips off the hunt's own states. A name the
## library does not have is the one failure with no symptom: `play_clip()`
## reports false and the creature keeps whatever pose it was already holding.
func _test_every_hunt_clip_exists() -> bool:
	for clip: StringName in HUNT_CLIPS:
		if not rig.has_clip(clip):
			return _fail(
				"The hunt asks for clip '%s'; the library has %s."
				% [clip, str(rig.get_clip_names())]
			)
		if not rig.play_clip(clip, not hunter.ONE_SHOT_CLIPS.has(clip)):
			return _fail("Clip '%s' is in the library but would not play." % clip)
		if rig.get_current_clip() != clip:
			return _fail(
				"Asked for '%s' and the body is holding '%s'."
				% [clip, rig.get_current_clip()]
			)
	return true


## Detection is tested against this light's cone, so the player has to see it
## coming out of the creature's head rather than its knees or the ceiling.
func _test_the_gaze_is_at_head_height() -> bool:
	var light := rig.gaze_light
	if light == null:
		return _fail('Rig exposes no gaze_light; detection has nothing to test against.')
	var skeleton := rig.find_child('Skeleton3D', true, false) as Skeleton3D
	var head_bone := skeleton.find_bone('Head')
	if head_bone == -1:
		return _fail('The rig has no Head bone - the humanoid retarget did not run.')
	var head: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone).origin
	if absf(light.global_position.y - head.y) > 0.35:
		return _fail(
			'Gaze light is at %.2f m and the head bone at %.2f m.'
			% [light.global_position.y, head.y]
		)
	return true


func _drive(speed: float, agitation: float, searching: bool, charging: bool, delta: float) -> void:
	rig.locomotion_speed = speed
	rig.agitation = agitation
	rig.searching = searching
	rig.charging = charging
	rig.advance(delta)


func _skeleton() -> Skeleton3D:
	return rig.find_child('Skeleton3D', true, false) as Skeleton3D


func _meshes() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node: Node in rig.find_children('*', 'MeshInstance3D', true, false):
		found.append(node as MeshInstance3D)
	return found


## The posed skeleton's extent, in the rig's own space, so the numbers read as
## "how big is it" rather than "where is it standing".
##
## Taken off the bones rather than the mesh AABB, for two reasons. A mesh AABB
## is static - it does not move when the rig is posed or swayed, which is the
## whole thing this file is watching. And on this rig it is not even in the same
## space as the body: the GLB's `Armature` node carries a 0.01 scale and the
## skin's bind poses carry the inverse 100x, so `mesh.get_aabb()` describes a
## 0.017 m object while the skinned body really stands 1.70 m. Measured through
## the mesh, every size assertion below would pass on anything at all.
##
## This is the skeleton's envelope, so it sits inside the silhouette by the
## thickness of the skin - a little under the crown, a good deal narrower than
## the shoulders. Both limits it is tested against have far more headroom than
## that, and a rig imported at the wrong unit scale, or swaying itself into a
## door frame, moves the bones just as much as the skin.
func _bounds() -> AABB:
	var skeleton := _skeleton()
	if skeleton == null:
		return AABB()
	var to_local := rig.global_transform.affine_inverse() * skeleton.global_transform
	var bounds := AABB()
	for i: int in skeleton.get_bone_count():
		var point := to_local * skeleton.get_bone_global_pose(i).origin
		if i == 0:
			bounds = AABB(point, Vector3.ZERO)
		else:
			bounds = bounds.expand(point)
	return bounds


func _fail(message: String) -> bool:
	push_error('Hunter body smoke test failed: ' + message)
	print('Hunter body smoke test FAILED: ' + message)
	quit(1)
	return false

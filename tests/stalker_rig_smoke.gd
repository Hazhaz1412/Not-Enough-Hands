extends SceneTree

## Covers the huntsman's body rather than its hunt (`hunter_ghost_smoke.gd` owns
## that). Four things about a procedurally built creature rot silently:
##
##   1. it stops fitting through the house - the doors are 2.35 m and the
##      ceilings 3.0 m, and a crown of spines is exactly the sort of thing that
##      quietly grows past both;
##   2. its feet stop meeting the floor the collision capsule is standing on;
##   3. a chain gets built but never wired into `advance()`, so a limb that
##      exists silently never moves again;
##   4. the gaze light stops being where the eyes are, which would put detection
##      somewhere other than where the player sees it looking.

## Matches villa_house.gd's DOOR_CLEAR_HEIGHT: anything taller cannot follow a
## player through a doorway without clipping the frame.
const DOOR_CLEAR_HEIGHT := 2.4
## The widest defense door opening in the project.
const DOOR_CLEAR_WIDTH := 2.0
const FRAME := 1.0 / 60.0

var rig: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load('res://ghosts/hunter_ghost.tscn') as PackedScene
	var hunter := scene.instantiate()
	root.add_child(hunter)
	rig = hunter.get_node('VisualRoot')

	if not _test_it_was_actually_built():
		return
	if not _test_it_fits_through_the_house():
		return
	if not _test_it_stands_on_the_floor():
		return
	if not _test_every_part_moves():
		return
	if not _test_the_gaze_comes_out_of_the_crown():
		return

	print(
		'Stalker rig smoke test passed: %d parts built, silhouette %.2f m tall and '
		% [_meshes().size(), _bounds().position.y + _bounds().size.y]
		+ '%.2f m wide, feet on the floor, every chain animating, gaze from the crown.'
		% _bounds().size.x
	)
	quit()


## A builder that half-runs is the failure mode with no symptom: the creature
## simply arrives missing a limb. Count what it made.
func _test_it_was_actually_built() -> bool:
	var meshes := _meshes()
	if meshes.size() < 150:
		return _fail('Rig built only %d parts; expected the full ~200.' % meshes.size())
	var eyes := 0
	for mesh: MeshInstance3D in meshes:
		if mesh.name.begins_with('Eye'):
			eyes += 1
	if eyes < 25:
		return _fail('Rig built %d eyes; the concept art wants them everywhere.' % eyes)
	return true


## Checked in every pose it can be in while it is in the house, including the
## un-animated build pose, because the crown and the tail are both the sort of
## thing that quietly grows an extra ten centimetres during a retune.
func _test_it_fits_through_the_house() -> bool:
	var poses := {
		'built': [0.0, 0.0, false, false],
		'searching': [1.2, 0.35, true, false],
		'walking': [1.6, 0.0, false, false],
		'charging': [3.4, 1.0, false, true],
	}
	var tallest := 0.0
	for label: String in poses:
		var pose: Array = poses[label]
		if label != 'built':
			for step: int in range(120):
				_drive(pose[0], pose[1], pose[2], pose[3], FRAME)
		var bounds := _bounds()
		# The top of the creature above the floor, not its total extent: claws
		# that sink a centimetre into the boards do not have to clear a lintel.
		var top := bounds.position.y + bounds.size.y
		tallest = maxf(tallest, top)
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
	if tallest < 2.0:
		return _fail('Tallest pose is only %.2f m; it has to loom.' % tallest)
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


## Every chain the builder made has to be reachable from `advance()`. Sampling
## world positions catches a pivot that was built and then forgotten, which is
## the one bug a screenshot will not show.
func _test_every_part_moves() -> bool:
	var meshes := _meshes()
	var before: Array[Vector3] = []
	for mesh: MeshInstance3D in meshes:
		before.append(mesh.global_position)

	# Walk, then charge, so both the gait and the agitation poses get exercised.
	for step: int in range(60):
		_drive(1.4, 0.0, true, false, FRAME)
	for step: int in range(60):
		_drive(3.2, 1.0, false, true, FRAME)

	var moved := 0
	var stalled: Array[String] = []
	for i: int in range(meshes.size()):
		var mesh: MeshInstance3D = meshes[i]
		if mesh.global_position.distance_to(before[i]) > 0.004:
			moved += 1
		elif stalled.size() < 8:
			stalled.append(str(rig.get_path_to(mesh)))
	if moved < meshes.size():
		return _fail(
			'%d of %d parts never moved. First few: %s'
			% [meshes.size() - moved, meshes.size(), ', '.join(stalled)]
		)
	return true


## Detection is tested against this light's cone, so it has to sit in the middle
## of the ring of spines the player can see scanning the corridor.
func _test_the_gaze_comes_out_of_the_crown() -> bool:
	var light := rig.get('gaze_light') as SpotLight3D
	if light == null:
		return _fail('Rig exposes no gaze_light; detection has nothing to test against.')
	var crown := rig.find_child('CrownHub', true, false) as Node3D
	if crown == null:
		return _fail('Rig has no CrownHub.')
	var offset := light.global_position.distance_to(crown.global_position)
	if offset > 0.15:
		return _fail('Gaze light sits %.2f m from the crown it is supposed to be in.' % offset)
	if light.global_position.y < 1.4:
		return _fail(
			'Gaze light is only %.2f m up; it should be at head height.'
			% light.global_position.y
		)
	return true


func _drive(speed: float, agitation: float, searching: bool, charging: bool, delta: float) -> void:
	rig.set('locomotion_speed', speed)
	rig.set('agitation', agitation)
	rig.set('searching', searching)
	rig.set('charging', charging)
	rig.call('advance', delta)


func _meshes() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node: Node in rig.find_children('*', 'MeshInstance3D', true, false):
		found.append(node as MeshInstance3D)
	return found


## The whole creature's extent, in the rig's own space, so the numbers read as
## "how big is it" rather than "where is it standing".
func _bounds() -> AABB:
	var to_local := rig.global_transform.affine_inverse()
	var bounds := AABB()
	var started := false
	for mesh: MeshInstance3D in _meshes():
		if mesh.mesh == null:
			continue
		var local := to_local * mesh.global_transform * mesh.mesh.get_aabb()
		if started:
			bounds = bounds.merge(local)
		else:
			bounds = local
			started = true
	return bounds


func _fail(message: String) -> bool:
	push_error('Stalker rig smoke test failed: ' + message)
	print('Stalker rig smoke test FAILED: ' + message)
	quit(1)
	return false

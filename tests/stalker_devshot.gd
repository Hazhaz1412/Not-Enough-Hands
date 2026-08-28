extends SceneTree

## Diagnostic, not a test: renders the huntsman's body from the same angles the
## concept sheet uses - front, three-quarter, side, back, hunting pose - so the
## silhouette can be looked at instead of guessed about after a retune of
## `stalker_rig.gd`'s proportions.
##
## Run it with a real window, since headless has no renderer:
##   godot --script tests/stalker_devshot.gd --path .
## PNGs land in `user://stalker_shots` and the path is printed at the end.

const OUT_DIR := 'user://stalker_shots'
const FRAME := 1.0 / 60.0

## [name, camera yaw around the creature, pose]. Pose is
## [speed, agitation, searching, charging].
const SHOTS := [
	['01_front', 0.0, [1.2, 0.35, true, false]],
	['02_three_quarter', 0.7, [1.2, 0.35, true, false]],
	['03_side', 1.5708, [1.4, 0.0, false, false]],
	['04_back', 3.1416, [1.4, 0.0, false, false]],
	['05_charging', 0.5, [3.4, 1.0, false, true]],
	['06_idle_close', 0.35, [0.0, 0.0, true, false]],
]

var rig: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var hunter := (load('res://ghosts/hunter_ghost.tscn') as PackedScene).instantiate()
	root.add_child(hunter)
	rig = hunter.get_node('VisualRoot')
	rig.visible = true

	# A dark floor, so the creature is not floating in a void and the feet can
	# be checked against something.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.06, 0.055, 0.05)
	floor_material.roughness = 0.95
	plane.material = floor_material
	floor_mesh.mesh = plane
	root.add_child(floor_mesh)

	var camera := Camera3D.new()
	camera.fov = 42.0
	root.add_child(camera)
	camera.make_current()

	# Two lamps: a cold key raking one side the way the concept art is lit, and
	# a dim fill so the far side is not solid black.
	var key := OmniLight3D.new()
	key.light_energy = 4.0
	key.omni_range = 14.0
	key.light_color = Color(0.72, 0.80, 0.95)
	root.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_energy = 0.9
	fill.omni_range = 14.0
	fill.light_color = Color(0.95, 0.60, 0.35)
	root.add_child(fill)

	for shot: Array in SHOTS:
		var yaw: float = shot[1]
		var pose: Array = shot[2]
		for step: int in range(150):
			rig.set('locomotion_speed', pose[0])
			rig.set('agitation', pose[1])
			rig.set('searching', pose[2])
			rig.set('charging', pose[3])
			rig.call('advance', FRAME)

		var distance := 2.6 if str(shot[0]).ends_with('close') else 4.1
		# The creature faces -Z, so yaw 0 has to put the camera in front of it.
		var eye := Vector3(sin(yaw) * distance, 1.45, -cos(yaw) * distance)
		camera.global_position = eye
		camera.look_at(Vector3(0.0, 1.15, 0.0), Vector3.UP)
		key.global_position = eye + Vector3(1.9, 1.7, 0.6)
		fill.global_position = eye + Vector3(-2.4, 0.4, -1.2)

		for _frame: int in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png('%s/%s.png' % [OUT_DIR, shot[0]])
		print('wrote %s' % shot[0])

	print('shots in %s' % ProjectSettings.globalize_path(OUT_DIR))
	quit()

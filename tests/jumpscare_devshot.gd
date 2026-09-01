extends SceneTree

## Diagnostic, not a test: renders the jumpscare at a handful of instants so the
## face can be looked at rather than argued about - the one acceptance criterion
## tests/jumpscare_smoke.gd can only measure geometrically.
##
## Run it with a real window, since headless has no renderer:
##   godot --script tests/jumpscare_devshot.gd --path .
## PNGs land in `user://jumpscare_shots` and the path is printed at the end.

const OUT_DIR := "user://jumpscare_shots"

## Fractions of the whole sequence to capture.
const SHOTS := [
	["01_spawn", 0.0],
	["02_launch", 0.22],
	["03_rushing", 0.45],
	["04_closing", 0.62],
	["05_impact", 0.76],
	["06_hold", 0.95],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# A lit room behind the overlay, so the transparent viewport is proved to
	# composite over the world instead of onto a convenient black screen.
	var backdrop := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(14.0, 6.0, 14.0)
	box.flip_faces = true
	backdrop.mesh = box
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.16, 0.15, 0.17)
	backdrop.mesh.material = wall
	backdrop.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(backdrop)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 2.0
	lamp.omni_range = 16.0
	lamp.position = Vector3(1.5, 2.4, 1.0)
	root.add_child(lamp)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 0.0)
	root.add_child(camera)
	camera.make_current()

	var controller := JumpscareController.new()
	root.add_child(controller)
	controller.play_jumpscare(null)
	# This script owns the clock; the sequence must not also advance itself
	# while the renderer is being waited on.
	controller.set_process(false)
	await process_frame

	var total := controller.get_total_duration()
	var played := 0.0
	for shot: Array in SHOTS:
		var target: float = float(shot[1]) * total
		controller.debug_step(maxf(target - played, 0.0))
		played = target
		for _frame: int in 3:
			await process_frame
		# The animation applies its pose a frame behind the step, and this
		# script has taken the controller's own _process away - so re-pin the
		# framing to the pose that is about to be drawn.
		controller.debug_step(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot[0]])
		print("wrote %s at t=%.2fs" % [shot[0], target])

	print("shots in %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit()

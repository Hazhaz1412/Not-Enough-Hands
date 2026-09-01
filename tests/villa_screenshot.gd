extends SceneTree

## Diagnostic: park a camera at a few vantage points in the villa and write
## PNGs, so the geometry can be looked at instead of guessed about.

const OUT_DIR := "user://villa_shots"

const SHOTS := [
	{"name": "01_foyer", "pos": Vector3(33, 1.7, 7), "look": Vector3(45, 1.5, 7)},
	{"name": "02_stair_foot", "pos": Vector3(49, 1.7, 8.6), "look": Vector3(45, 2.6, 5.0)},
	{"name": "02b_stair_head", "pos": Vector3(36, 5.2, 5), "look": Vector3(48, 4.2, 5)},
	{"name": "02c_stairwell", "pos": Vector3(40, 5.2, 9), "look": Vector3(47, 3.2, 4)},
	{"name": "03_corridor_west", "pos": Vector3(15, 1.7, 13), "look": Vector3(15, 1.6, 45)},
	{"name": "04_corridor_north", "pos": Vector3(20, 1.7, 13), "look": Vector3(60, 1.6, 13)},
	{"name": "05_atrium", "pos": Vector3(52, 1.7, 22), "look": Vector3(52, 8.0, 22)},
	{"name": "06_gallery", "pos": Vector3(28, 1.7, 22), "look": Vector3(28, 1.6, 10)},
	{"name": "07_dining", "pos": Vector3(15, 1.7, 54), "look": Vector3(40, 1.6, 54)},
	{"name": "08_kitchen", "pos": Vector3(73, 1.7, 21), "look": Vector3(73, 1.6, 8)},
	{"name": "09_bed1", "pos": Vector3(15, 5.2, 6), "look": Vector3(40, 5.1, 6)},
	{"name": "10_attic", "pos": Vector3(24, 8.7, 30), "look": Vector3(40, 8.4, 30)},
	{"name": "11_boiler", "pos": Vector3(60, -1.8, 36), "look": Vector3(44, -1.9, 36)},
	{"name": "12_outside", "pos": Vector3(40, 14.0, -22), "look": Vector3(40, 4.0, 20)},
	{"name": "13_gate", "pos": Vector3(40, 1.7, -23), "look": Vector3(40, 1.4, -4)},
	{"name": "14_front_court", "pos": Vector3(27, 1.7, -12), "look": Vector3(40, 1.2, -7)},
	{"name": "15_back_garden", "pos": Vector3(38, 1.7, 73), "look": Vector3(64, 1.3, 68)},
	{"name": "16_service_yard", "pos": Vector3(96, 1.7, 23), "look": Vector3(83, 1.2, 23)},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var main_scene := (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	for _frame: int in 10:
		await process_frame

	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.far = 400.0
	root.add_child(camera)
	camera.make_current()

	# A bright roaming lamp, otherwise the horror grade makes every shot black.
	var lamp := OmniLight3D.new()
	lamp.light_energy = 14.0
	lamp.omni_range = 40.0
	root.add_child(lamp)

	for shot: Dictionary in SHOTS:
		camera.global_position = shot["pos"]
		camera.look_at(shot["look"], Vector3.UP)
		lamp.global_position = shot["pos"] as Vector3 + Vector3(0, 1.0, 0)
		for _frame: int in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("%s/%s.png" % [OUT_DIR, shot["name"]])
		print("wrote %s" % shot["name"])

	print("shots in %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit()

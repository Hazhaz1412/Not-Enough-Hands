extends Node3D

## The game's front door: four choices over a corridor you are holding a torch
## in. The corridor is built here rather than authored as a scene because it is
## made of boxes - and because a menu must never be the thing that fails to load
## when an art pack is missing.
##
## Routing lives in `NetworkManager` (it owns every other scene change), so this
## screen only decides *which* of its entry points to call.

const TAGLINES := {
	&"solo": "Một mình trong ngôi nhà nhỏ. Ba con ma, và không ai đến kéo bạn dậy.",
	&"online": "Tối đa 4 người trong Biệt thự Vành Đai. Chia nhau việc, hoặc chia nhau chết.",
	&"settings": "Chỉnh hình ảnh, âm thanh, phím tắt và góc nhìn.",
	&"quit": "Đóng cửa lại. Ngôi nhà vẫn ở đó khi bạn quay về.",
	&"": "Ba con ma. Một cái nhà. Không đủ tay để giữ tất cả.",
}

const DETAILS := {
	&"solo": "BẢN ĐỒ: NHÀ NHỎ  ·  1 NGƯỜI",
	&"online": "BẢN ĐỒ: BIỆT THỰ VÀNH ĐAI  ·  2-4 NGƯỜI",
	&"settings": "LƯU VÀO user://settings.cfg",
	&"quit": "ALT+F4 CŨNG ĐƯỢC, NHƯNG THÔ QUÁ",
	&"": "Di chuột để rọi đèn",
}

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var torch: SpotLight3D = $CameraRig/Camera3D/Torch
@onready var title: Label = %Title
@onready var title_second: Label = %TitleSecond
@onready var tagline: Label = %Tagline
@onready var detail: Label = %Detail
@onready var solo_button: Button = %SoloButton
@onready var online_button: Button = %OnlineButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: Control = %SettingsMenu

var _lamp: OmniLight3D
var _lamp_energy: float = 1.0
var _lamp_flicker_timer: float = 0.0
var _watcher: Node3D
var _watcher_timer: float = 6.0
var _watcher_visible_time: float = 0.0
var _title_flicker_timer: float = 1.5
var _look: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _hovered: StringName = &""


## `-- --server` and `-- --join=…` are answered by the multiplayer menu, which
## used to be the boot scene. Now that this one is, those runs have to be handed
## straight over or a dedicated server would sit here forever.
static func has_automation_arguments(args: PackedStringArray) -> bool:
	for argument: String in args:
		if argument == "--server" or argument.begins_with("--join="):
			return true
	return false


func _ready() -> void:
	if OS.has_feature("dedicated_server") \
			or has_automation_arguments(OS.get_cmdline_user_args()):
		set_process(false)
		get_tree().change_scene_to_file.call_deferred(NetworkManager.MENU_SCENE)
		return
	# Coming back from a run: the death screen and the pause menu both pause the
	# tree, and the villa leaves the mouse captured.
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_corridor()
	_build_watcher()
	_connect_buttons()
	settings_menu.closed.connect(_on_settings_closed)
	solo_button.grab_focus()


func _process(delta: float) -> void:
	_time += delta
	_update_look(delta)
	_update_lamp(delta)
	_update_watcher(delta)
	_update_title_flicker(delta)


## The torch follows the cursor much further than the camera does: the point is
## that moving the mouse lights a different piece of the corridor, while the
## framing barely moves.
func _update_look(delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse := get_viewport().get_mouse_position()
	# A cursor that is not over the window (including before it is ever moved,
	# which reads as 0,0) must not park the beam in a corner.
	var target := Vector2.ZERO
	if viewport_size.x > 0.0 and viewport_size.y > 0.0 \
			and Rect2(Vector2.ZERO, viewport_size).has_point(mouse):
		target = ((mouse / viewport_size) * 2.0 - Vector2.ONE).clampf(-1.0, 1.0)
	_look = _look.lerp(target, clampf(delta * 3.2, 0.0, 1.0))

	var breath := sin(_time * 0.9) * 0.012 + sin(_time * 2.3) * 0.004
	camera_rig.position.y = 1.62 + breath
	camera_rig.rotation.y = deg_to_rad(-_look.x * 3.4)
	camera_rig.rotation.x = deg_to_rad(-_look.y * 2.0)
	camera.rotation.z = deg_to_rad(sin(_time * 0.63) * 0.4)
	torch.rotation.y = deg_to_rad(-_look.x * 13.0)
	torch.rotation.x = deg_to_rad(-_look.y * 9.0)


## One bulb, badly wired. Hovering THOÁT is what makes it worse - the menu's
## only jump scare is that the light stops agreeing with you.
func _update_lamp(delta: float) -> void:
	if _lamp == null:
		return
	var base := 0.45 if _hovered == &"quit" else 1.0
	_lamp_flicker_timer -= delta
	if _lamp_flicker_timer <= 0.0:
		var dark := randf() < (0.55 if _hovered == &"quit" else 0.3)
		_lamp_energy = randf_range(0.05, 0.3) if dark else randf_range(0.85, 1.15)
		_lamp_flicker_timer = randf_range(0.04, 0.16) if dark else randf_range(0.4, 2.6)
	_lamp.light_energy = lerpf(_lamp.light_energy, 2.6 * base * _lamp_energy, delta * 18.0)


func _update_watcher(delta: float) -> void:
	if _watcher == null:
		return
	if _watcher.visible:
		_watcher_visible_time -= delta
		# It never walks. It is a little further to one side every frame, which
		# reads as movement only once you look back at it.
		_watcher.position.x += delta * 0.09
		_watcher.rotation.y = deg_to_rad(sin(_time * 0.7) * 4.0)
		if _watcher_visible_time <= 0.0:
			_watcher.visible = false
			_watcher_timer = randf_range(11.0, 21.0)
		return
	_watcher_timer -= delta * (2.4 if _hovered == &"quit" else 1.0)
	if _watcher_timer > 0.0:
		return
	_watcher.position = Vector3(
		randf_range(-0.5, 0.5),
		0.0,
		-5.9 if _hovered != &"quit" else -3.5
	)
	_watcher.visible = true
	_watcher_visible_time = randf_range(1.3, 2.4)
	# Whatever it is, it arrives with the light going out.
	_lamp_energy = 0.06
	_lamp_flicker_timer = 0.12


func _update_title_flicker(delta: float) -> void:
	_title_flicker_timer -= delta
	if _title_flicker_timer > 0.0:
		return
	var dip := randf() < 0.45
	var alpha := randf_range(0.25, 0.55) if dip else 1.0
	title.modulate.a = alpha
	title_second.modulate.a = clampf(alpha + 0.15, 0.0, 1.0)
	_title_flicker_timer = randf_range(0.05, 0.14) if dip else randf_range(1.2, 4.5)


func _connect_buttons() -> void:
	var actions := {
		solo_button: &"solo",
		online_button: &"online",
		settings_button: &"settings",
		quit_button: &"quit",
	}
	for button: Button in actions:
		var key: StringName = actions[button]
		button.mouse_entered.connect(_on_button_hovered.bind(key))
		button.focus_entered.connect(_on_button_hovered.bind(key))
		button.mouse_exited.connect(_on_button_unhovered.bind(key))
	solo_button.pressed.connect(_on_solo_pressed)
	online_button.pressed.connect(_on_online_pressed)
	settings_button.pressed.connect(settings_menu.open)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_button_hovered(key: StringName) -> void:
	_hovered = key
	tagline.text = str(TAGLINES.get(key, TAGLINES[&""]))
	detail.text = str(DETAILS.get(key, DETAILS[&""]))


func _on_button_unhovered(key: StringName) -> void:
	if _hovered != key:
		return
	_hovered = &""
	tagline.text = str(TAGLINES[&""])
	detail.text = str(DETAILS[&""])


func _on_solo_pressed() -> void:
	NetworkManager.start_single_player()


func _on_online_pressed() -> void:
	get_tree().change_scene_to_file(NetworkManager.MENU_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_settings_closed() -> void:
	settings_button.grab_focus()


## Geometry, in boxes. The corridor runs down -Z from the camera and ends at a
## shut door with a light under it.
func _build_corridor() -> void:
	var world := Node3D.new()
	world.name = "Corridor"
	add_child(world)

	var wall_material := _matte(Color(0.09, 0.095, 0.1), 0.95)
	var floor_material := _matte(Color(0.055, 0.05, 0.048), 0.9)
	var trim_material := _matte(Color(0.13, 0.12, 0.11), 0.8)

	_add_box(world, Vector3(3.4, 0.2, 24.0), Vector3(0.0, -0.1, -5.0), floor_material)
	_add_box(world, Vector3(3.4, 0.2, 24.0), Vector3(0.0, 2.85, -5.0), wall_material)
	_add_box(world, Vector3(0.2, 3.0, 24.0), Vector3(-1.7, 1.35, -5.0), wall_material)
	_add_box(world, Vector3(0.2, 3.0, 24.0), Vector3(1.7, 1.35, -5.0), wall_material)
	# Skirting, so the wall/floor seam is not one flat value in the torch beam.
	_add_box(world, Vector3(0.08, 0.16, 24.0), Vector3(-1.58, 0.08, -5.0), trim_material)
	_add_box(world, Vector3(0.08, 0.16, 24.0), Vector3(1.58, 0.08, -5.0), trim_material)

	# The far door: a frame, a shut panel, and the one warm thing in the shot.
	_add_box(world, Vector3(3.4, 3.0, 0.2), Vector3(0.0, 1.35, -6.7), wall_material)
	_add_box(world, Vector3(1.42, 2.4, 0.12), Vector3(0.0, 1.2, -6.56), trim_material)
	_add_box(
		world,
		Vector3(1.16, 2.2, 0.08),
		Vector3(0.0, 1.1, -6.5),
		_matte(Color(0.075, 0.06, 0.05), 0.7)
	)
	var door_glow := _matte(Color(0.9, 0.62, 0.3), 1.0)
	door_glow.emission_enabled = true
	door_glow.emission = Color(1.0, 0.66, 0.32)
	door_glow.emission_energy_multiplier = 2.4
	_add_box(world, Vector3(1.06, 0.025, 0.06), Vector3(0.0, 0.018, -6.44), door_glow)

	# A few shapes to catch the beam on the way down.
	var crate_material := _matte(Color(0.11, 0.1, 0.085), 0.85)
	_add_box(world, Vector3(0.7, 0.7, 0.7), Vector3(-1.2, 0.35, -2.6), crate_material)
	_add_box(world, Vector3(0.6, 0.6, 0.6), Vector3(-1.25, 0.95, -2.75), crate_material)
	_add_box(world, Vector3(0.8, 0.5, 0.9), Vector3(1.15, 0.25, -5.2), crate_material)
	_add_box(world, Vector3(0.06, 0.9, 0.7), Vector3(1.63, 1.7, -3.9), trim_material)

	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0.0, 2.5, -3.0)
	_lamp.light_color = Color(1.0, 0.86, 0.68)
	_lamp.light_energy = 2.6
	_lamp.omni_range = 7.5
	_lamp.shadow_enabled = true
	world.add_child(_lamp)
	_add_box(
		world,
		Vector3(0.34, 0.1, 0.34),
		Vector3(0.0, 2.72, -3.0),
		_matte(Color(0.16, 0.15, 0.14), 0.6)
	)

	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 90
	dust.lifetime = 9.0
	dust.position = Vector3(0.0, 1.6, -3.4)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.5, 1.3, 5.0)
	dust.gravity = Vector3(0.0, -0.012, 0.0)
	dust.initial_velocity_min = 0.01
	dust.initial_velocity_max = 0.05
	dust.scale_amount_min = 0.008
	dust.scale_amount_max = 0.022
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.5
	dust_mesh.height = 1.0
	dust_mesh.radial_segments = 4
	dust_mesh.rings = 2
	dust.mesh = dust_mesh
	var dust_material := _matte(Color(0.8, 0.85, 0.9), 1.0)
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.albedo_color = Color(0.8, 0.85, 0.9, 0.22)
	dust.mesh.surface_set_material(0, dust_material)
	world.add_child(dust)


## Unshaded, so the torch cannot light it and it stays a shape rather than a
## model. Two eyes are the only part of it that returns any light at all.
func _build_watcher() -> void:
	_watcher = Node3D.new()
	_watcher.name = "Watcher"
	_watcher.visible = false
	add_child(_watcher)

	# Dark, but still lit: the lamp is between the camera and the doorway, so a
	# fully unshaded black shape would be invisible rather than frightening.
	var silhouette := _matte(Color(0.028, 0.032, 0.038), 1.0)

	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.height = 1.5
	body_mesh.radius = 0.24
	body.mesh = body_mesh
	body.material_override = silhouette
	body.position = Vector3(0.0, 0.78, 0.0)
	_watcher.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.155
	head_mesh.height = 0.34
	head.mesh = head_mesh
	head.material_override = silhouette
	head.position = Vector3(0.0, 1.66, 0.0)
	_watcher.add_child(head)

	var eye_material := _matte(Color(0.75, 0.95, 0.95), 1.0)
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.62, 0.95, 0.92)
	eye_material.emission_energy_multiplier = 6.0
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.028
		eye_mesh.height = 0.056
		eye.mesh = eye_mesh
		eye.material_override = eye_material
		eye.position = Vector3(side * 0.055, 1.69, 0.135)
		_watcher.add_child(eye)


func _matte(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material


func _add_box(
	parent: Node3D,
	size: Vector3,
	position: Vector3,
	material: Material
) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = material
	box.position = position
	parent.add_child(box)
	return box

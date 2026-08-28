class_name DevTools
extends CanvasLayer

signal panel_toggled(open: bool)

@export var player_path: NodePath = NodePath("../Player")
@export var statue_path: NodePath = NodePath("../StatueGhost")
@export var crawler_path: NodePath = NodePath("../CrawlerGhost")
@export var hunter_path: NodePath = NodePath("../HunterGhost")
@export var door_director_path: NodePath = NodePath("../DoorAttackDirector")
@export var world_environment_path: NodePath = NodePath("../WorldEnvironment")

## Colour of the through-wall entrance markers. Bright enough to read against
## the horror grade, transparent enough not to hide the door behind it.
const XRAY_TINT := Color(0.15, 1.0, 0.72, 0.85)
const XRAY_MARKER_NAME := "DevEntranceXray"

var panel_open: bool = false
var entrance_xray: bool = false
var bright_vision: bool = false
var _environment_before_bright: Environment
var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

@onready var panel: PanelContainer = $Panel
@onready var invincible_toggle: CheckButton = $Panel/Margin/Scroll/Content/Invincible
@onready var fast_toggle: CheckButton = $Panel/Margin/Scroll/Content/FastMovement
@onready var noclip_toggle: CheckButton = $Panel/Margin/Scroll/Content/Noclip
@onready var xray_toggle: CheckButton = $Panel/Margin/Scroll/Content/EntranceXray
@onready var bright_toggle: CheckButton = $Panel/Margin/Scroll/Content/BrightVision
@onready var bladder_slider: HSlider = $Panel/Margin/Scroll/Content/BladderRow/BladderSlider
@onready var bladder_value: Label = $Panel/Margin/Scroll/Content/BladderRow/BladderValue
@onready var entrance_picker: OptionButton = $Panel/Margin/Scroll/Content/DoorRow/Entrance
@onready var status_label: Label = $Panel/Margin/Scroll/Content/Status


func _ready() -> void:
	for entrance_id: int in range(1, 8):
		entrance_picker.add_item("Cửa %02d" % entrance_id, entrance_id)
	invincible_toggle.toggled.connect(set_invincibility_enabled)
	fast_toggle.toggled.connect(set_fast_movement_enabled)
	noclip_toggle.toggled.connect(set_noclip_enabled)
	xray_toggle.toggled.connect(set_entrance_xray_enabled)
	bright_toggle.toggled.connect(set_bright_vision_enabled)
	bladder_slider.value_changed.connect(set_bladder_level)
	$Panel/Margin/Scroll/Content/SpawnStatue.pressed.connect(spawn_statue)
	$Panel/Margin/Scroll/Content/SpawnCrawler.pressed.connect(spawn_crawler)
	$Panel/Margin/Scroll/Content/SpawnHunter.pressed.connect(spawn_hunter)
	$Panel/Margin/Scroll/Content/DoorRow/AttackDoor.pressed.connect(force_selected_door_attack)
	$Panel/Margin/Scroll/Content/ForceBlackout.pressed.connect(force_blackout)
	$Panel/Margin/Scroll/Content/Close.pressed.connect(func() -> void: set_panel_open(false))
	_bind_bladder_slider()
	set_panel_open(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey \
		and event.pressed \
		and not event.echo \
		and (event.keycode == KEY_F1 or event.physical_keycode == KEY_F1):
		set_panel_open(not panel_open)
		get_viewport().set_input_as_handled()


func set_panel_open(open: bool) -> void:
	if open == panel_open and panel.visible == open:
		return
	panel_open = open
	panel.visible = open
	if open:
		_mouse_mode_before_open = Input.get_mouse_mode()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_bind_bladder_slider()
		_sync_bladder_from_player()
		status_label.text = "Sẵn sàng. Các thay đổi chỉ dành cho dev."
	else:
		Input.set_mouse_mode(_mouse_mode_before_open)
	panel_toggled.emit(open)


func set_invincibility_enabled(enabled: bool) -> void:
	var player := _player()
	if player and player.has_method("set_dev_invincible"):
		player.call("set_dev_invincible", enabled)
		status_label.text = "Bất tử: %s" % ("BẬT" if enabled else "TẮT")


func set_fast_movement_enabled(enabled: bool) -> void:
	var player := _player()
	if player and player.has_method("set_dev_fast_movement"):
		player.call("set_dev_fast_movement", enabled)
		status_label.text = "Chạy nhanh x3: %s" % ("BẬT" if enabled else "TẮT")


func set_noclip_enabled(enabled: bool) -> void:
	var player := _player()
	if player and player.has_method("set_dev_noclip"):
		player.call("set_dev_noclip", enabled)
		status_label.text = (
			"Bay xuyên tường: BẬT. WASD theo hướng nhìn, Space lên, Ctrl xuống, Shift nhanh."
			if enabled
			else "Bay xuyên tường: TẮT."
		)


func set_bladder_level(value: float) -> void:
	_bind_bladder_slider()
	var player := _player()
	if not player or not player.has_method("set_bladder"):
		return
	player.call("set_bladder", value)
	_sync_bladder_from_player()
	status_label.text = "Bladder: %d%%" % roundi(bladder_slider.value)


func _bind_bladder_slider() -> void:
	var player := _player()
	if not player or not ("bladder" in player):
		return
	var bladder_node := player.get("bladder") as PlayerBladder
	if not bladder_node:
		return
	if not bladder_node.bladder_changed.is_connected(_on_bladder_changed):
		bladder_node.bladder_changed.connect(_on_bladder_changed)
	_on_bladder_changed(bladder_node.get_bladder(), bladder_node.bladder_max)


func _sync_bladder_from_player() -> void:
	var player := _player()
	if not player or not ("bladder" in player):
		return
	var bladder_node := player.get("bladder") as PlayerBladder
	if bladder_node:
		_on_bladder_changed(bladder_node.get_bladder(), bladder_node.bladder_max)


func _on_bladder_changed(value: float, max_value: float) -> void:
	bladder_slider.max_value = maxf(max_value, 1.0)
	bladder_slider.set_value_no_signal(clampf(value, 0.0, bladder_slider.max_value))
	bladder_value.text = "%d%%" % roundi(bladder_slider.value)


## Turns the night off. The player owns the overlays and the blinking; the
## darkness itself lives in the scene's Environment, so both halves are flipped
## together and the original Environment is kept for putting back.
func set_bright_vision_enabled(enabled: bool) -> void:
	bright_vision = enabled
	var player := _player()
	if player and player.has_method("set_dev_clear_vision"):
		player.call("set_dev_clear_vision", enabled)

	var world := get_node_or_null(world_environment_path) as WorldEnvironment
	if world and world.environment:
		if enabled:
			if not _environment_before_bright:
				_environment_before_bright = world.environment
			var bright := _environment_before_bright.duplicate() as Environment
			bright.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			# Enough to read every surface, not enough to blow the kit's near-white
			# plaster out to a flat sheet - which a full-strength white ambient did.
			bright.ambient_light_color = Color(0.78, 0.83, 0.92)
			bright.ambient_light_energy = 0.3
			bright.fog_enabled = false
			bright.volumetric_fog_enabled = false
			bright.adjustment_enabled = false
			bright.tonemap_exposure = 1.0
			world.environment = bright
		elif _environment_before_bright:
			world.environment = _environment_before_bright
			_environment_before_bright = null

	status_label.text = (
		"Sáng tối đa: BẬT. Không sương mù, không vignette, không bị ép nháy mắt."
		if enabled
		else "Sáng tối đa: TẮT."
	)


## Hangs a see-through-walls marker on every defense door, so all seven
## entrances can be found and counted from anywhere in the house. The marker
## is a child of the door, so it inherits the door's placement and scale and
## needs no separate bookkeeping when doors move.
func set_entrance_xray_enabled(enabled: bool) -> void:
	entrance_xray = enabled
	var doors := get_tree().get_nodes_in_group("defense_doors")
	for door_node: Node in doors:
		var door := door_node as Node3D
		var existing := door.get_node_or_null(XRAY_MARKER_NAME)
		if not enabled:
			if existing:
				existing.queue_free()
			continue
		if not existing:
			door.add_child(_build_xray_marker(int(door.get("entrance_id"))))
	status_label.text = (
		"Soi %d cửa xuyên tường: BẬT." % doors.size()
		if enabled
		else "Soi cửa xuyên tường: TẮT."
	)


func _build_xray_marker(entrance_id: int) -> Node3D:
	var marker := Node3D.new()
	marker.name = XRAY_MARKER_NAME

	var material := StandardMaterial3D.new()
	material.albedo_color = XRAY_TINT
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The whole point is to be visible through the house, so skip the depth
	# test and draw last.
	material.no_depth_test = true
	material.render_priority = 100

	# An outline, not a slab. A filled box this size sits across a third of the
	# screen once you are inside the room with it, and hides the door it is
	# supposed to be pointing at.
	var width := 2.4
	var height := 2.7
	var bar := 0.12
	var frame := Node3D.new()
	frame.name = "Volume"
	for edge: Array in [
		[Vector3(0.0, height, 0.0), Vector3(width + bar, bar, bar)],
		[Vector3(0.0, 0.0, 0.0), Vector3(width + bar, bar, bar)],
		[Vector3(-width * 0.5, height * 0.5, 0.0), Vector3(bar, height, bar)],
		[Vector3(width * 0.5, height * 0.5, 0.0), Vector3(bar, height, bar)],
	]:
		var mesh := BoxMesh.new()
		mesh.size = edge[1]
		mesh.material = material
		var edge_node := MeshInstance3D.new()
		edge_node.mesh = mesh
		edge_node.position = edge[0]
		frame.add_child(edge_node)
	marker.add_child(frame)

	var label := Label3D.new()
	label.name = "Tag"
	label.text = "%02d" % entrance_id
	# fixed_size keeps a tag the same size however far away the door is, which
	# is what makes it findable - but it also means font_size is measured in
	# fractions of the screen, not metres. 160 filled a third of the viewport.
	label.font_size = 48
	label.pixel_size = 0.002
	label.modulate = Color(0.35, 1.0, 0.78)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 101
	label.fixed_size = true
	label.position = Vector3(0.0, 2.9, 0.0)
	marker.add_child(label)
	return marker


## Keeps the range on each tag current, so the panel answers "which door is
## nearest" without walking the ring.
func _process(_delta: float) -> void:
	if not entrance_xray:
		return
	var player := _player() as Node3D
	if not player:
		return
	for door_node: Node in get_tree().get_nodes_in_group("defense_doors"):
		var door := door_node as Node3D
		var label := door.get_node_or_null("%s/Tag" % XRAY_MARKER_NAME) as Label3D
		if label:
			label.text = "%02d · %dm" % [
				int(door.get("entrance_id")),
				roundi(player.global_position.distance_to(door.global_position)),
			]


func spawn_statue() -> bool:
	var statue := get_node_or_null(statue_path)
	var player := _player() as CharacterBody3D
	var spawned := statue != null \
		and statue.has_method("dev_force_spawn") \
		and bool(statue.call("dev_force_spawn", player))
	status_label.text = "Statue đã xuất hiện." if spawned else "Không thể gọi Statue."
	return spawned


func spawn_crawler() -> bool:
	var crawler := get_node_or_null(crawler_path)
	var player := _player() as CharacterBody3D
	var spawned := crawler != null \
		and crawler.has_method("dev_force_spawn") \
		and bool(crawler.call("dev_force_spawn", player))
	status_label.text = "Crawler đã xuất hiện." if spawned else "Không thể gọi Crawler."
	return spawned


## Puts the huntsman in the house without waiting for a door to break. It still
## needs a real breach to ever walk back out, so a forced spawn into an intact
## house seals it in on purpose - which is the state worth testing.
func spawn_hunter() -> bool:
	var hunter := get_node_or_null(hunter_path)
	var player := _player() as CharacterBody3D
	var spawned := hunter != null \
		and hunter.has_method("dev_force_spawn") \
		and bool(hunter.call("dev_force_spawn", player))
	status_label.text = "Thợ Săn đã vào nhà." if spawned else "Không thể gọi Thợ Săn."
	return spawned


func set_selected_entrance(entrance_id: int) -> void:
	for index: int in entrance_picker.item_count:
		if entrance_picker.get_item_id(index) == entrance_id:
			entrance_picker.select(index)
			return


func force_selected_door_attack() -> bool:
	var entrance_id := entrance_picker.get_selected_id()
	var director := get_node_or_null(door_director_path)
	var door: Node = null
	if director and director.has_method("start_attack_at_entrance"):
		door = director.call("start_attack_at_entrance", entrance_id) as Node
	var started := is_instance_valid(door)
	status_label.text = (
		"Ma đang tấn công cửa %02d." % entrance_id
		if started
		else "Không thể tấn công cửa %02d (cửa có thể đã vỡ)." % entrance_id
	)
	return started


## Zeroes current_power and leaves PowerManager's own _process() to raise the
## real blackout signal/state on the next frame, rather than poking
## is_blackout directly and risking it disagreeing with current_power.
func force_blackout() -> bool:
	var power_manager := get_tree().get_first_node_in_group("power_manager")
	if not power_manager:
		status_label.text = "Không có PowerManager trong scene này."
		return false
	if bool(power_manager.get("is_blackout")):
		status_label.text = "Đã mất điện rồi."
		return false
	power_manager.set("current_power", 0.0)
	status_label.text = "Đã ngắt điện (dev)."
	return true


func _player() -> Node:
	return get_node_or_null(player_path)

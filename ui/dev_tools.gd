class_name DevTools
extends CanvasLayer

signal panel_toggled(open: bool)

@export var player_path: NodePath = NodePath("../Player")
@export var statue_path: NodePath = NodePath("../StatueGhost")
@export var crawler_path: NodePath = NodePath("../CrawlerGhost")
@export var hunter_path: NodePath = NodePath("../HunterGhost")
@export var darkness_ghost_path: NodePath = NodePath("../DarknessGhost")
@export var door_director_path: NodePath = NodePath("../DoorAttackDirector")
@export var world_environment_path: NodePath = NodePath("../WorldEnvironment")
@export var electrical_zones_path: NodePath = NodePath("../ElectricalZones")

## Colour of the through-wall entrance markers. Bright enough to read against
## the horror grade, transparent enough not to hide the door behind it.
const XRAY_TINT := Color(0.15, 1.0, 0.72, 0.85)
const XRAY_MARKER_NAME := "DevEntranceXray"
const GHOST_BOX_TINT := Color(1.0, 0.22, 0.68, 0.95)
const GHOST_BOX_MARKER_NAME := "DevGhostCollisionBox"

var panel_open: bool = false
var entrance_xray: bool = false
var bright_vision: bool = false
var _environment_before_bright: Environment
var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _zone_buttons: Dictionary = {}
## drain_house_power() switches the manager's drain on to empty the reserve.
## Remembered here so recharging puts the map's own setting back - otherwise a
## recharged house silently drains to black again a second later.
var _forced_power_drain: bool = false
var _power_drain_before_force: bool = false
var ghost_box_enabled := false

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
@onready var zone_controls: VBoxContainer = $Panel/Margin/Scroll/Content/ZoneControls
@onready var power_readout: Label = $Panel/Margin/Scroll/Content/PowerReadout
@onready var ghost_box_picker: OptionButton = $Panel/Margin/Scroll/Content/GhostBoxRow/Ghost
@onready var ghost_box_toggle: CheckButton = $Panel/Margin/Scroll/Content/GhostBoxRow/ShowBox
@onready var teleport_to_ghost_button: Button = $Panel/Margin/Scroll/Content/TeleportToGhost


func _ready() -> void:
	for entrance_id: int in range(1, 8):
		entrance_picker.add_item("Cửa %02d" % entrance_id, entrance_id)
	ghost_box_picker.add_item("Ma Bóng Tối")
	ghost_box_picker.add_item("Statue")
	ghost_box_picker.add_item("Crawler")
	ghost_box_picker.add_item("Thợ Săn")
	invincible_toggle.toggled.connect(set_invincibility_enabled)
	fast_toggle.toggled.connect(set_fast_movement_enabled)
	noclip_toggle.toggled.connect(set_noclip_enabled)
	xray_toggle.toggled.connect(set_entrance_xray_enabled)
	bright_toggle.toggled.connect(set_bright_vision_enabled)
	ghost_box_picker.item_selected.connect(_on_ghost_box_selected)
	ghost_box_toggle.toggled.connect(set_ghost_box_enabled)
	teleport_to_ghost_button.pressed.connect(teleport_to_selected_ghost)
	bladder_slider.value_changed.connect(set_bladder_level)
	$Panel/Margin/Scroll/Content/SpawnStatue.pressed.connect(spawn_statue)
	$Panel/Margin/Scroll/Content/SpawnCrawler.pressed.connect(spawn_crawler)
	$Panel/Margin/Scroll/Content/SpawnHunter.pressed.connect(spawn_hunter)
	$Panel/Margin/Scroll/Content/SpawnDarknessGhost.pressed.connect(spawn_darkness_ghost)
	$Panel/Margin/Scroll/Content/DoorRow/AttackDoor.pressed.connect(force_selected_door_attack)
	$Panel/Margin/Scroll/Content/ForceBlackout.pressed.connect(force_blackout)
	$Panel/Margin/Scroll/Content/AllZonesOn.pressed.connect(func() -> void: set_all_zones_powered(true))
	$Panel/Margin/Scroll/Content/AllZonesOff.pressed.connect(func() -> void: set_all_zones_powered(false))
	$Panel/Margin/Scroll/Content/RechargePower.pressed.connect(recharge_house_power)
	$Panel/Margin/Scroll/Content/DrainPower.pressed.connect(drain_house_power)
	$Panel/Margin/Scroll/Content/Close.pressed.connect(func() -> void: set_panel_open(false))
	_bind_bladder_slider()
	_build_zone_controls.call_deferred()
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
		refresh_power_zone_controls()
		_refresh_power_readout()
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


## Turns the night off. The player owns the overlays; the
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
	if panel_open:
		_refresh_power_readout()
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


## Draws a through-wall wire box around the selected ghost's real
## CollisionShape3D. This is deliberately a hitbox marker, rather than a box
## around the imported model, so designers can verify actual player contact.
func set_ghost_box_enabled(enabled: bool) -> void:
	ghost_box_enabled = enabled
	_clear_ghost_box_markers()
	if not enabled:
		status_label.text = "Đã ẩn khung va chạm của ma."
		return
	var ghost := _selected_ghost_for_box()
	if not ghost or not _add_ghost_box_marker(ghost):
		status_label.text = "Không tìm thấy CollisionShape3D của ma đã chọn."
		ghost_box_toggle.set_pressed_no_signal(false)
		ghost_box_enabled = false
		return
	status_label.text = "Đang đánh dấu hitbox của %s." % ghost_box_picker.get_item_text(ghost_box_picker.selected)


func _on_ghost_box_selected(_index: int) -> void:
	if ghost_box_enabled:
		set_ghost_box_enabled(true)


## Places the player beside the chosen entity, never inside its collision
## shape. This shares the selector used for the hitbox marker so a developer
## can first find a ghost through the map, then immediately travel to it.
func teleport_to_selected_ghost() -> bool:
	var player := _player() as CharacterBody3D
	var ghost := _selected_ghost_for_box()
	if not player or not ghost:
		status_label.text = "Không tìm thấy Player hoặc thực thể đã chọn."
		return false
	var direction := player.global_position - ghost.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		direction = ghost.global_basis.z
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	# Player's root is roughly one metre above the floor, whereas the ghosts'
	# roots sit on their floor. Keep a two-metre horizontal gap for safety.
	player.global_position = ghost.global_position + direction * 2.4 + Vector3.UP * 0.95
	player.velocity = Vector3.ZERO
	status_label.text = "Đã dịch chuyển đến gần %s." % ghost_box_picker.get_item_text(ghost_box_picker.selected)
	return true


func _selected_ghost_for_box() -> Node3D:
	var target_path := darkness_ghost_path
	match ghost_box_picker.selected:
		1:
			target_path = statue_path
		2:
			target_path = crawler_path
		3:
			target_path = hunter_path
	return get_node_or_null(target_path) as Node3D


func _ghosts_with_box_targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for target_path: NodePath in [darkness_ghost_path, statue_path, crawler_path, hunter_path]:
		var ghost := get_node_or_null(target_path) as Node3D
		if ghost and ghost not in result:
			result.append(ghost)
	return result


func _clear_ghost_box_markers() -> void:
	for ghost: Node3D in _ghosts_with_box_targets():
		var marker := ghost.get_node_or_null(GHOST_BOX_MARKER_NAME)
		if marker:
			marker.queue_free()


func _add_ghost_box_marker(ghost: Node3D) -> bool:
	var collision := ghost.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if not collision or not collision.shape:
		return false
	var debug_mesh := collision.shape.get_debug_mesh()
	if not debug_mesh:
		return false
	var bounds := debug_mesh.get_aabb()
	if bounds.size.length_squared() <= 0.0001:
		return false

	var marker := Node3D.new()
	marker.name = GHOST_BOX_MARKER_NAME
	# CollisionShape3D can be hidden at runtime. Parent the visual marker to the
	# ghost itself, then copy the collider's local transform; it follows the
	# exact hitbox without inheriting a hidden collision-node visibility state.
	ghost.add_child(marker)
	marker.global_transform = collision.global_transform
	marker.visible = true

	var line_mesh := ImmediateMesh.new()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var start := bounds.position
	var end := bounds.end
	var corners: Array[Vector3] = [
		Vector3(start.x, start.y, start.z), Vector3(end.x, start.y, start.z),
		Vector3(end.x, start.y, end.z), Vector3(start.x, start.y, end.z),
		Vector3(start.x, end.y, start.z), Vector3(end.x, end.y, start.z),
		Vector3(end.x, end.y, end.z), Vector3(start.x, end.y, end.z),
	]
	for edge: Vector2i in [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]:
		line_mesh.surface_add_vertex(corners[edge.x])
		line_mesh.surface_add_vertex(corners[edge.y])
	line_mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.albedo_color = GHOST_BOX_TINT
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 110
	var lines := MeshInstance3D.new()
	lines.mesh = line_mesh
	lines.material_override = material
	# Keep the X-ray marker alive even when the real ghost is behind a wall or
	# at the far side of the villa. no_depth_test draws above the map; the large
	# cull margin prevents the tiny collision box from being discarded early.
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lines.extra_cull_margin = 1000.0
	lines.ignore_occlusion_culling = true
	marker.add_child(lines)

	var label := Label3D.new()
	label.text = "%s HITBOX" % ghost.name.to_upper()
	label.position = Vector3(0.0, end.y + 0.18, 0.0)
	label.font_size = 40
	label.pixel_size = 0.003
	label.modulate = GHOST_BOX_TINT
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 111
	label.fixed_size = true
	marker.add_child(label)
	return true


func recharge_house_power() -> void:
	var manager := get_tree().get_first_node_in_group("power_manager") as PowerManager
	if not manager:
		status_label.text = "Map hiện tại không có PowerManager."
		return
	manager.restore_power()
	if _forced_power_drain:
		manager.enable_power_drain = _power_drain_before_force
		_forced_power_drain = false
	_refresh_power_readout()
	status_label.text = "Đã nạp đầy điện tổng của căn nhà."


## Empties the house battery instead of forcing an outage flag, so the blackout
## arrives down PowerManager's own drain path (`current_power` hits zero ->
## `_enter_blackout()`), exactly as it would in a real long night. Both maps
## ship `enable_power_drain = false`, so the reserve would otherwise just sit at
## 1 forever - switching drain on is what makes this reach zero.
func drain_house_power() -> void:
	var manager := get_tree().get_first_node_in_group("power_manager") as PowerManager
	if not manager:
		status_label.text = "Map hiện tại không có PowerManager."
		return
	if not _forced_power_drain:
		_power_drain_before_force = manager.enable_power_drain
		_forced_power_drain = true
	manager.enable_power_drain = true
	manager.current_power = 1.0
	if is_zero_approx(manager.get_total_load()):
		# Nothing is drawing power, so the reserve would never actually empty.
		manager.current_power = 0.0
		manager.trigger_global_blackout()
		_refresh_power_readout()
		status_label.text = "Không có thiết bị nào tiêu thụ điện — đã cắt điện trực tiếp."
		return
	_refresh_power_readout()
	status_label.text = "Điện tổng còn 1. Đang xả — nhà sẽ tối trong tích tắc."


func _refresh_power_readout() -> void:
	var manager := get_tree().get_first_node_in_group("power_manager") as PowerManager
	if not manager:
		power_readout.text = "ĐIỆN TỔNG: không có PowerManager"
		return
	# Raw wattage says nothing about when the lights go out - the remaining
	# seconds do, so the panel leads with those.
	var remaining := manager.get_seconds_until_blackout()
	power_readout.text = "ĐIỆN TỔNG: %d / %d  (%d%%)\nCòn sáng: %s   ·   Tải: %.0f W" % [
		roundi(manager.current_power),
		roundi(manager.max_power),
		roundi(manager.get_power_percentage() * 100.0),
		"đang tắt" if remaining < 0.0 else "%d:%02d" % [int(remaining) / 60, int(remaining) % 60],
		manager.get_total_load(),
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


func spawn_darkness_ghost() -> bool:
	var ghost := get_node_or_null(darkness_ghost_path)
	var spawned := ghost != null and ghost.has_method("manifest_for_dev") \
		and bool(ghost.call("manifest_for_dev"))
	var zone_name := ""
	if spawned and ghost.has_node("DarknessEntityPowerEffect"):
		var effect := ghost.get_node("DarknessEntityPowerEffect") as DarknessEntityPowerEffect
		if effect.active_zone:
			zone_name = " (%s)" % effect.active_zone.display_name
	status_label.text = (
		"Ma Bóng Tối đã làm tối zone gần bạn%s và bắt đầu săn đuổi." % zone_name
		if spawned
		else "Không thể gọi Ma Bóng Tối (không còn zone đang có điện hoặc nó đã xuất hiện)."
	)
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


# --- electrical-zone testing -------------------------------------------------

## Builds from the active map's zones rather than hard-coding Villa IDs into a
## shared UI scene. Maps without zones simply show the explanatory label.
func _build_zone_controls() -> void:
	for child: Node in zone_controls.get_children():
		child.queue_free()
	_zone_buttons.clear()
	var zones := _electrical_zones()
	if zones.is_empty():
		var unavailable := Label.new()
		unavailable.text = "Map hiện tại không có electrical zone để test."
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		zone_controls.add_child(unavailable)
		return
	for zone: ElectricalZone in zones:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 34.0)
		button.pressed.connect(func() -> void: toggle_electrical_zone(zone))
		zone_controls.add_child(button)
		_zone_buttons[zone.zone_id] = button
		if not zone.power_changed.is_connected(_on_zone_power_changed):
			zone.power_changed.connect(_on_zone_power_changed)
	refresh_power_zone_controls()


func toggle_electrical_zone(zone: ElectricalZone) -> void:
	if not is_instance_valid(zone):
		return
	zone.toggle_power()
	status_label.text = "%s: %s" % [
		zone.display_name,
		"CÓ ĐIỆN" if zone.is_powered else "MẤT ĐIỆN",
	]
	refresh_power_zone_controls()


func set_all_zones_powered(powered: bool) -> void:
	var zones := _electrical_zones()
	if zones.is_empty():
		# House2 ships no ElectricalZones at all, so on the default map this
		# button used to report "no zones" and do nothing - leaving that map
		# with no way to cut the power, and the main breaker's blackout state
		# impossible to reach. Fall back to the manager's own global outage.
		var manager := get_tree().get_first_node_in_group("power_manager") as PowerManager
		if not manager:
			status_label.text = "Map hiện tại không có PowerManager."
			return
		if powered:
			manager.restore_power()
		else:
			manager.trigger_global_blackout()
		_refresh_power_readout()
		status_label.text = "Map không có zone — đã %s điện toàn nhà qua PowerManager." % [
			"khôi phục" if powered else "cắt",
		]
		return
	for zone: ElectricalZone in zones:
		zone.set_powered(powered)
	status_label.text = "Tất cả %d zone: %s" % [
		zones.size(),
		"CÓ ĐIỆN" if powered else "MẤT ĐIỆN (BLACKOUT)",
	]
	refresh_power_zone_controls()


func refresh_power_zone_controls() -> void:
	for zone: ElectricalZone in _electrical_zones():
		var button := _zone_buttons.get(zone.zone_id) as Button
		if button:
			button.text = "%s  —  %s" % [
				zone.display_name,
				"CÓ ĐIỆN" if zone.is_powered else "MẤT ĐIỆN",
			]


func _on_zone_power_changed(_powered: bool) -> void:
	refresh_power_zone_controls()


func _electrical_zones() -> Array[ElectricalZone]:
	var container := get_node_or_null(electrical_zones_path)
	var zones: Array[ElectricalZone] = []
	if not container:
		return zones
	for child: Node in container.get_children():
		var zone := child as ElectricalZone
		if zone:
			zones.append(zone)
	return zones


func _player() -> Node:
	return get_node_or_null(player_path)

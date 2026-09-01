extends Node3D

## Compact visual test: ZONE 01 -> ZONE 02 -> ZONE 03.
@export_range(2.0, 30.0, 0.5) var test_expansion_seconds := 15.0
@export_category("Free Camera")
@export_range(1.0, 50.0, 0.5) var camera_move_speed := 11.0
@export_range(1.0, 8.0, 0.5) var camera_sprint_multiplier := 2.5
@export_range(0.0005, 0.01, 0.0005) var camera_mouse_sensitivity := 0.0025

@onready var ghost := $DarknessGhost as DarknessGhost
@onready var effect := $DarknessGhost/DarknessEntityPowerEffect as DarknessEntityPowerEffect
@onready var power_manager := $PowerManager as PowerManager
@onready var camera := $Camera3D as Camera3D
@onready var state_label := $TestUI/Panel/Margin/Content/State as Label
@onready var zone_01 := $ElectricalZones/Z01_B1_WEST as ElectricalZone
@onready var zone_02 := $ElectricalZones/Z02_B1_EAST as ElectricalZone
@onready var zone_03 := $ElectricalZones/Z07_F00_EAST as ElectricalZone

var _refresh_in := 0.0
var _camera_pitch := 0.0


func _ready() -> void:
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP, true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	ghost.auto_manifest = false
	ghost.zone_expansion_seconds = test_expansion_seconds
	$TestUI/Panel/Margin/Content/StartCycle.pressed.connect(start_cycle)
	$TestUI/Panel/Margin/Content/ApproachNow.pressed.connect(begin_approach_now)
	await get_tree().process_frame
	await get_tree().process_frame
	start_cycle()


func _process(delta: float) -> void:
	_update_free_camera(delta)
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = 0.15
		_refresh_state()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER:
			start_cycle()
		KEY_SPACE:
			begin_approach_now()
		KEY_TAB:
			_toggle_camera_mouse()
		KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_:
			return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mouse_event := event as InputEventMouseMotion
		camera.rotate_y(-mouse_event.relative.x * camera_mouse_sensitivity)
		var vertical: float = -mouse_event.relative.y * camera_mouse_sensitivity
		var next_pitch := clampf(_camera_pitch + vertical, deg_to_rad(-80.0), deg_to_rad(80.0))
		camera.rotate_object_local(Vector3.RIGHT, next_pitch - _camera_pitch)
		_camera_pitch = next_pitch
		get_viewport().set_input_as_handled()


func _update_free_camera(delta: float) -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direction -= camera.global_basis.z
	if Input.is_key_pressed(KEY_S):
		direction += camera.global_basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= camera.global_basis.x
	if Input.is_key_pressed(KEY_D):
		direction += camera.global_basis.x
	if Input.is_key_pressed(KEY_Q):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		direction.y += 1.0
	if direction.length_squared() <= 0.001:
		return
	var speed := camera_move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= camera_sprint_multiplier
	camera.global_position += direction.normalized() * speed * delta


func _toggle_camera_mouse() -> void:
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		else Input.MOUSE_MODE_CAPTURED
	)


func start_cycle() -> void:
	if ghost.is_manifested():
		ghost.retreat()
	for node: Node in get_tree().get_nodes_in_group("electrical_zones"):
		var zone := node as ElectricalZone
		if zone:
			zone.set_powered(true)
	ghost.zone_expansion_seconds = test_expansion_seconds
	ghost.manifest()
	_refresh_state()


## Skips only the wait. The ghost must still walk into the lit room first.
func begin_approach_now() -> void:
	if ghost.is_manifested() and not ghost._pending_expansion_zone:
		ghost._zone_expansion_in = 0.0
		ghost._process(0.01)
	_refresh_state()


func _refresh_state() -> void:
	if not is_instance_valid(effect):
		return
	var dark_names: PackedStringArray = []
	for zone: ElectricalZone in effect.darkened_zones:
		if is_instance_valid(zone):
			dark_names.append(zone.display_name)
	var next_name := "chưa có"
	if is_instance_valid(ghost._pending_expansion_zone):
		next_name = "%s (ma đang đi tới)" % ghost._pending_expansion_zone.display_name
	state_label.text = (
		"Vùng đã tối: %s\n" % ", ".join(dark_names)
		+ "Zone kế tiếp: %s\n" % next_name
		+ "Đếm ngược trước khi đi: %.1f giây\n" % maxf(ghost._zone_expansion_in, 0.0)
		+ "Tải điện hiện tại: %.0f W" % power_manager.get_total_load()
	)
	_refresh_zone_label($Zone01Label as Label3D, zone_01, "ZONE 01")
	_refresh_zone_label($Zone02Label as Label3D, zone_02, "ZONE 02")
	_refresh_zone_label($Zone03Label as Label3D, zone_03, "ZONE 03")


func _refresh_zone_label(label: Label3D, zone: ElectricalZone, title: String) -> void:
	var powered := zone.is_powered
	label.text = "%s\n%s" % [title, "SÁNG" if powered else "TỐI"]
	label.modulate = Color(0.5, 0.86, 1.0, 1.0) if powered else Color(1.0, 0.28, 0.6, 1.0)

extends Node3D

## Compact visual test: target -> four-second flicker -> broad blackout/chase.
@export_range(1.0, 10.0, 0.25) var test_warning_seconds := 4.0
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
	effect.zone_neighbours = {
		&"Z01_B1_WEST": PackedStringArray(["Z02_B1_EAST"]),
		&"Z02_B1_EAST": PackedStringArray(["Z01_B1_WEST", "Z07_F00_EAST"]),
		&"Z07_F00_EAST": PackedStringArray(["Z02_B1_EAST"]),
	}
	ghost.auto_manifest = false
	ghost.warning_duration = test_warning_seconds
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
	ghost.warning_duration = test_warning_seconds
	ghost.manifest()
	_refresh_state()


## Skips the four-second warning and starts the blackout/chase immediately.
func begin_approach_now() -> void:
	if ghost.is_manifested() and ghost.encounter_phase == DarknessGhost.EncounterPhase.WARNING:
		ghost._finish_warning()
	_refresh_state()


func _refresh_state() -> void:
	if not is_instance_valid(effect):
		return
	var phase_name := "HIDDEN"
	if ghost.encounter_phase == DarknessGhost.EncounterPhase.WARNING:
		phase_name = "WARNING - LIGHTS FLICKERING"
	elif ghost.encounter_phase == DarknessGhost.EncounterPhase.CHASING:
		phase_name = "CHASING PLAYER"
	state_label.text = (
		"Phase: %s\n" % phase_name
		+ "Warning remaining: %.1f s\n" % maxf(ghost._warning_time_left, 0.0)
		+ "Dark zones: %d\n" % effect.darkened_zones.size()
		+ "Current load: %.0f W\n" % power_manager.get_total_load()
		+ "Ghost speed: %.0f m/s" % (
			ghost.normal_speed if ghost._is_position_locally_lit(ghost.global_position)
			else ghost.darkness_speed
		)
	)
	_refresh_zone_label($Zone01Label as Label3D, zone_01, "ZONE 01")
	_refresh_zone_label($Zone02Label as Label3D, zone_02, "ZONE 02")
	_refresh_zone_label($Zone03Label as Label3D, zone_03, "ZONE 03")


func _refresh_zone_label(label: Label3D, zone: ElectricalZone, title: String) -> void:
	var powered := zone.is_powered
	label.text = "%s\n%s" % [title, "SÁNG" if powered else "TỐI"]
	label.modulate = Color(0.5, 0.86, 1.0, 1.0) if powered else Color(1.0, 0.28, 0.6, 1.0)

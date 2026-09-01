class_name ElectricalDevice
extends Node


signal state_changed(is_on: bool)
signal load_changed(current_load: float)


@export_category("Power Configuration")
## Stable identifier used by generated maps and Inspector-linked switches.
@export var device_id: StringName
@export_range(0.0, 100000.0, 1.0)
var power_consumption: float = 100.0:
	set(value):
		var sanitized_value := maxf(value, 0.0)
		if is_equal_approx(power_consumption, sanitized_value):
			return
		power_consumption = sanitized_value
		load_changed.emit(get_power_consumption())


@export_category("Device State")
@export var is_on: bool = true:
	set(value):
		if value == is_on:
			return
		if value and _forced_off_by_blackout:
			return
		is_on = value
		_apply_output_state()
		state_changed.emit(is_on)
		load_changed.emit(get_power_consumption())


@export_category("Optional Output")
## Leave empty when this script is attached directly to a Light3D. Assign a
## light here when ElectricalDevice is used as a child component instead.
@export var powered_light: Light3D
## Optional visible bulb/glow associated with powered_light. The fixture mesh
## itself stays visible when electricity is off; only this emissive detail and
## the actual Light3D switch state change.
@export var powered_emission: GeometryInstance3D


var power_manager: PowerManager
var _was_on_before_forced_off: bool = false
var _forced_off_by_blackout: bool = false
var _forced_off_reasons: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("electrical_device")


func _ready() -> void:
	_apply_output_state()
	power_manager = get_tree().get_first_node_in_group("power_manager")

	if power_manager:
		power_manager.register_device(self)

		power_manager.blackout.connect(_on_blackout)
		power_manager.power_restored.connect(_on_power_restored)
		if power_manager.is_blackout:
			_on_blackout()

	else:
		push_warning(name + ": PowerManager not found")


func _exit_tree() -> void:
	if power_manager:
		if power_manager.blackout.is_connected(_on_blackout):
			power_manager.blackout.disconnect(_on_blackout)

		if power_manager.power_restored.is_connected(_on_power_restored):
			power_manager.power_restored.disconnect(_on_power_restored)

		power_manager.unregister_device(self)


func get_power_consumption() -> float:
	if not is_on:
		return 0.0

	return power_consumption


func is_forced_off() -> bool:
	return _forced_off_by_blackout


func is_forced_off_for(reason: StringName) -> bool:
	return _forced_off_reasons.has(reason)


func force_off(reason: StringName) -> void:
	if _forced_off_reasons.has(reason):
		return
	if _forced_off_reasons.is_empty():
		_was_on_before_forced_off = is_on
	_forced_off_reasons[reason] = true
	_forced_off_by_blackout = true
	# Use the property setter so output visibility, load and switch prompts update
	# immediately when an individual electrical zone loses power.
	is_on = false


func release_forced_off(reason: StringName) -> void:
	_forced_off_reasons.erase(reason)
	if not _forced_off_reasons.is_empty():
		return
	_forced_off_by_blackout = false
	var restore_requested := _was_on_before_forced_off
	_was_on_before_forced_off = false
	if restore_requested:
		is_on = true
	else:
		_apply_output_state()


func _apply_output_state() -> void:
	var output: Node = powered_light if powered_light else self
	if output is Light3D:
		(output as Light3D).visible = is_on
	if powered_emission:
		powered_emission.visible = is_on


func turn_on() -> void:
	is_on = true


func turn_off() -> void:
	is_on = false


func toggle() -> void:
	if is_on:
		turn_off()
	else:
		turn_on()


func _on_blackout() -> void:
	force_off(&"global_blackout")


func _on_power_restored() -> void:
	release_forced_off(&"global_blackout")

class_name ElectricalZone
extends Node

## A reusable power domain. Devices may be forced off by more than one source
## (zone failure, regional outage, global blackout); each source uses its own
## reason so restoring one source never accidentally restores another.

signal power_changed(is_powered: bool)
signal switch_restore_required_changed(required: bool)

@export_category("Zone Configuration")
@export var zone_id: StringName
@export var display_name := "Electrical zone"
@export var device_ids: PackedStringArray
@export var is_powered := true:
	set(value):
		if is_powered == value:
			return
		is_powered = value
		_apply_power_state()
		power_changed.emit(is_powered)

var _power_manager: PowerManager
var _devices: Dictionary = {}
## A DarknessGhost outage is not a timed effect: it stays down until a player
## reaches one of this zone's switches and resets the circuit.
var requires_switch_restore := false
var _switch_reset_device_ids: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("electrical_zones")


func _ready() -> void:
	_power_manager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if not _power_manager:
		push_warning("ElectricalZone %s: PowerManager not found" % zone_id)
		return
	if not _power_manager.device_registered.is_connected(_on_device_registered):
		_power_manager.device_registered.connect(_on_device_registered)
	_bind_existing_devices.call_deferred()


func _exit_tree() -> void:
	if _power_manager and _power_manager.device_registered.is_connected(_on_device_registered):
		_power_manager.device_registered.disconnect(_on_device_registered)
	for device_value: Variant in _devices.values():
		var device := device_value as ElectricalDevice
		if device:
			device.release_forced_off(_force_reason())
	_devices.clear()


func toggle_power() -> void:
	is_powered = not is_powered


func set_powered(value: bool) -> void:
	if value:
		_set_switch_restore_required(false)
	is_powered = value


func begin_switch_restore_outage() -> bool:
	if not is_powered:
		return false
	_switch_reset_device_ids.clear()
	_set_switch_restore_required(true)
	is_powered = false
	return true


## Releases only the device operated by this switch. The rest of the zone
## remains dark until their own switches are used as well.
func restore_device_from_switch(device: ElectricalDevice) -> bool:
	if not requires_switch_restore or not device or not contains_device_id(device.device_id):
		return false
	if not device.is_forced_off_for(_force_reason()):
		return false
	device.release_forced_off(_force_reason())
	_switch_reset_device_ids[device.device_id] = true
	if _all_devices_reset_by_switch():
		_set_switch_restore_required(false)
		is_powered = true
	return true


func is_device_waiting_for_switch(device: ElectricalDevice) -> bool:
	return requires_switch_restore and device != null and device.is_forced_off_for(_force_reason())


func contains_device_id(device_id: StringName) -> bool:
	return device_ids.has(String(device_id))


func get_devices() -> Array[ElectricalDevice]:
	var result: Array[ElectricalDevice] = []
	for device_value: Variant in _devices.values():
		var device := device_value as ElectricalDevice
		if is_instance_valid(device):
			result.append(device)
	return result


func _bind_existing_devices() -> void:
	if not _power_manager:
		return
	for node: Node in _power_manager.devices:
		_bind_device(node as ElectricalDevice)


func _on_device_registered(device: ElectricalDevice) -> void:
	_bind_device(device)


func _bind_device(device: ElectricalDevice) -> void:
	if not device or not contains_device_id(device.device_id):
		return
	if _devices.has(device.get_instance_id()):
		return
	_devices[device.get_instance_id()] = device
	_apply_to_device(device)


func _apply_power_state() -> void:
	for device_value: Variant in _devices.values():
		var device := device_value as ElectricalDevice
		if device:
			_apply_to_device(device)


func _apply_to_device(device: ElectricalDevice) -> void:
	if is_powered:
		device.release_forced_off(_force_reason())
	else:
		device.force_off(_force_reason())


func _force_reason() -> StringName:
	return StringName("zone:" + String(zone_id))


func _set_switch_restore_required(value: bool) -> void:
	if requires_switch_restore == value:
		return
	requires_switch_restore = value
	if not value:
		_switch_reset_device_ids.clear()
	switch_restore_required_changed.emit(value)


func _all_devices_reset_by_switch() -> bool:
	if _devices.is_empty():
		return false
	for device_value: Variant in _devices.values():
		var device := device_value as ElectricalDevice
		if device and not _switch_reset_device_ids.has(device.device_id):
			return false
	return true

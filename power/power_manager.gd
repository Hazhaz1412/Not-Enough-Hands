class_name PowerManager
extends Node


signal blackout
signal power_restored
signal total_load_changed(total_load: float)
signal device_registered(device: ElectricalDevice)
signal regional_blackout_started(center: Vector3, affected_light_count: int)
signal regional_blackout_ended


@export_category("Power Configuration")
@export_range(1.0, 100000.0, 1.0)
var max_power: float = 1000.0

@export_range(0.0, 100000.0, 1.0)
var current_power: float = 1000.0


@export_category("Debug")
@export var enable_power_drain: bool = true

## How long a full reserve lasts with the whole house lit, in real seconds.
##
## Device wattages are art-side flavour - House2's lights alone come to ~2900 a
## second, which against any readable `max_power` empties the battery instantly.
## So the reserve is spent against *this* number instead: a full battery always
## lasts this long at the house's peak load, whatever that load happens to be,
## and proportionally longer once players switch rooms off.
##
## One night is 547.5 real seconds (23:55 -> 06:00 at 1.5 s per game minute), so
## 220 puts two outages in a fully-lit night - at roughly 3:40 and 7:20 in - and
## fewer if the house is run dark on purpose.
@export_range(10.0, 3600.0, 5.0) var full_load_reserve_seconds: float = 220.0


@export_category("House Lighting")
@export var house_light_group: StringName = &"flickering_house_lights"
@export var auto_register_house_lights: bool = true
@export_range(0.0, 10000.0, 1.0) var default_light_consumption: float = 60.0
@export_range(0.5, 100.0, 0.5) var regional_radius: float = 8.0
@export_range(0.5, 20.0, 0.5) var regional_floor_tolerance: float = 2.0
@export_range(0.1, 300.0, 0.5) var default_regional_duration: float = 10.0


var devices: Array[Node] = []
var is_blackout: bool = false
var is_regional_blackout: bool = false
## Where the current regional outage is centred, so it can be replicated: the
## affected lights are chosen by position, not by name.
var regional_blackout_center: Vector3 = Vector3.ZERO
var _total_load: float = 0.0
## Peak total load ever observed - the stand-in for "the whole house is on".
var _reference_load: float = 0.0

var _house_lights: Array[Light3D] = []
var _regional_lights: Array[Light3D] = []
var _visibility_before_outage: Dictionary = {}
var _global_time_remaining: float = -1.0
var _regional_time_remaining: float = -1.0
var _rng := RandomNumberGenerator.new()
var _manual_blackout_forced := false
var _zone_blackout_forced := false


func _enter_tree() -> void:
	add_to_group("power_manager")


func _ready() -> void:
	_rng.randomize()
	current_power = clamp(current_power, 0.0, max_power)

	if current_power <= 0.0:
		is_blackout = true

	print("PowerManager ready")
	print("Max power: ", max_power)
	print("Current power: ", current_power)
	_initialize_house_lights.call_deferred()


func _exit_tree() -> void:
	_restore_all_house_lights()


func _process(delta: float) -> void:
	# There is one battery for the house. A client neither drains it nor times
	# its own outages: the reserve and both blackout flags arrive through
	# apply_network_state(), so everyone goes dark on the same second.
	if not WorldNet.is_world_authority():
		return

	_update_outage_timers(delta)

	if is_blackout:
		return

	if not enable_power_drain:
		return

	var total_load := _total_load

	if total_load <= 0.0:
		return

	current_power -= _calculate_drain(total_load) * delta
	current_power = clamp(current_power, 0.0, max_power)

	if current_power <= 0.0:
		_enter_blackout()


func register_device(device: Node) -> void:
	if device == null:
		return
	if not device.has_method("get_power_consumption"):
		push_warning(device.name + ": electrical device has no power-consumption contract")
		return

	if device not in devices:
		devices.append(device)
		if device.has_signal("load_changed"):
			var callback := Callable(self, "_on_device_load_changed")
			if not device.is_connected("load_changed", callback):
				device.connect("load_changed", callback)
		_refresh_total_load()
		if device is ElectricalDevice:
			device_registered.emit(device as ElectricalDevice)


func unregister_device(device: Node) -> void:
	if is_instance_valid(device) and device.has_signal("load_changed"):
		var callback := Callable(self, "_on_device_load_changed")
		if device.is_connected("load_changed", callback):
			device.disconnect("load_changed", callback)
	devices.erase(device)
	_refresh_total_load()


func get_total_load() -> float:
	return _total_load


## Reserve units spent per second at the current load. The peak load ever seen
## is the reference for "the whole house is on", so this is simply the fraction
## of the house that is lit, spread over `full_load_reserve_seconds`. Devices
## can register late (the villa builds its lights at runtime), which is why the
## reference is tracked as a running peak rather than sampled once.
func get_drain_per_second() -> float:
	return _calculate_drain(_total_load)


func _calculate_drain(total_load: float) -> float:
	if full_load_reserve_seconds <= 0.0 or _reference_load <= 0.0:
		return total_load
	return max_power / full_load_reserve_seconds * (total_load / _reference_load)


## Real seconds of light left at the current load, or -1 when nothing is
## draining. Used by the dev readout so the panel states the number that
## actually matters instead of a raw wattage.
func get_seconds_until_blackout() -> float:
	if is_blackout:
		return 0.0
	var drain := get_drain_per_second()
	if not enable_power_drain or drain <= 0.0:
		return -1.0
	return current_power / drain


func get_device_by_id(device_id: StringName) -> ElectricalDevice:
	if device_id.is_empty():
		return null
	for node: Node in devices:
		var device := node as ElectricalDevice
		if device and device.device_id == device_id:
			return device
	return null


func _on_device_load_changed(_current_load: float) -> void:
	_refresh_total_load()


func _refresh_total_load() -> void:
	var valid_devices: Array[Node] = []
	var updated_load := 0.0
	for device: Node in devices:
		if not is_instance_valid(device):
			continue
		valid_devices.append(device)
		updated_load += maxf(float(device.get_power_consumption()), 0.0)
	devices = valid_devices
	_reference_load = maxf(_reference_load, updated_load)
	if is_equal_approx(_total_load, updated_load):
		return
	_total_load = updated_load
	total_load_changed.emit(_total_load)


func get_power_percentage() -> float:
	if max_power <= 0.0:
		return 0.0

	return current_power / max_power


func restore_power(amount: float = -1.0) -> void:
	if amount < 0.0:
		current_power = max_power
	else:
		current_power = clamp(
			current_power + amount,
			0.0,
			max_power
		)

	_manual_blackout_forced = false
	if is_blackout and current_power > 0.0 and not _zone_blackout_forced:
		_leave_global_blackout()


## Takes the server's reserve and both outage states.
##
## Only the transitions are acted on, through the same two private calls the
## authority uses, so a client suppresses and releases exactly the lights the
## server did. The regional centre travels because the affected lights are
## picked by position: a bool alone would tell a client that *somewhere* went
## dark without saying where.
func apply_network_state(
	reserve: float,
	blackout_active: bool,
	regional_active: bool,
	regional_center: Vector3 = Vector3.ZERO
) -> void:
	current_power = clampf(reserve, 0.0, max_power)

	if blackout_active and not is_blackout:
		_enter_blackout()
	elif not blackout_active and is_blackout:
		_leave_global_blackout()

	if regional_active and not is_regional_blackout:
		trigger_regional_blackout_at(regional_center, -1.0)
	elif not regional_active and is_regional_blackout:
		_end_regional_blackout()


## Turns off every authored light in this house. A negative duration keeps the
## outage active until restore_power() is called.
func trigger_global_blackout(duration: float = -1.0) -> void:
	_collect_house_lights()
	_global_time_remaining = duration
	_manual_blackout_forced = true
	if is_blackout:
		_suppress_lights(_house_lights)
		return
	_enter_blackout()


## Used by ElectricalZoneController. This reason is independent from manual
## blackouts and battery depletion, so restoring one powered zone does not
## cancel a separately triggered global blackout.
func set_zone_blackout(active: bool) -> void:
	if _zone_blackout_forced == active:
		return
	_zone_blackout_forced = active
	if active:
		_enter_blackout()
	elif is_blackout and current_power > 0.0 and not _manual_blackout_forced:
		_leave_global_blackout()


## Used by the darkness entity: picks one light as the centre of an outage and
## turns off the nearby lights on the same floor. Returns the number affected.
func trigger_random_regional_blackout(duration: float = -1.0) -> int:
	_collect_house_lights()
	if _house_lights.is_empty():
		return 0

	var anchor := _house_lights[_rng.randi_range(0, _house_lights.size() - 1)]
	return trigger_regional_blackout_at(anchor.global_position, duration)


## Lets an entity darken the area around a known world position instead of a
## random room. This does not change the house's global power reserve.
func trigger_regional_blackout_at(center: Vector3, duration: float = -1.0) -> int:
	_collect_house_lights()
	_end_regional_blackout()

	for light: Light3D in _house_lights:
		if not is_instance_valid(light):
			continue
		var offset := light.global_position - center
		if absf(offset.y) > regional_floor_tolerance:
			continue
		if Vector2(offset.x, offset.z).length() <= regional_radius:
			_regional_lights.append(light)

	if _regional_lights.is_empty():
		return 0

	is_regional_blackout = true
	regional_blackout_center = center
	_regional_time_remaining = default_regional_duration if duration < 0.0 else duration
	_suppress_lights(_regional_lights)
	_set_regional_devices_forced_off(true)
	regional_blackout_started.emit(center, _regional_lights.size())
	return _regional_lights.size()


func end_regional_blackout() -> void:
	_end_regional_blackout()


func get_regional_blackout_lights() -> Array[Light3D]:
	return _regional_lights.duplicate()


func get_house_light_count() -> int:
	_collect_house_lights()
	return _house_lights.size()


func set_random_seed(value: int) -> void:
	_rng.seed = value


func _enter_blackout() -> void:
	if is_blackout:
		return

	is_blackout = true
	_collect_house_lights()
	_suppress_lights(_house_lights)
	blackout.emit()


func _leave_global_blackout() -> void:
	if not is_blackout:
		return
	is_blackout = false
	_global_time_remaining = -1.0
	for light: Light3D in _house_lights:
		_release_light_if_powered(light)
	power_restored.emit()


func _initialize_house_lights() -> void:
	_collect_house_lights()
	if auto_register_house_lights:
		_ensure_house_light_devices()
	if is_blackout:
		_suppress_lights(_house_lights)


func _collect_house_lights() -> void:
	_house_lights.clear()
	var house := get_parent()
	for node: Node in get_tree().get_nodes_in_group(house_light_group):
		var light := node as Light3D
		if not light:
			continue
		if house and not house.is_ancestor_of(light):
			continue
		_house_lights.append(light)


func _ensure_house_light_devices() -> void:
	for light: Light3D in _house_lights:
		if not is_instance_valid(light):
			continue
		var direct_node: Node = light
		if direct_node as ElectricalDevice:
			continue
		var device := light.get_node_or_null("ElectricalDevice") as ElectricalDevice
		if device:
			continue
		device = ElectricalDevice.new()
		device.name = "ElectricalDevice"
		device.device_id = _light_device_id(light)
		device.power_consumption = default_light_consumption
		device.powered_light = light
		light.add_child(device)


func _light_device_id(light: Light3D) -> StringName:
	var identifier := String(light.name)
	if identifier.ends_with("Light"):
		identifier = identifier.trim_suffix("Light")
	return StringName(identifier)


func _device_for_light(light: Light3D) -> ElectricalDevice:
	var direct_node: Node = light
	var direct_device := direct_node as ElectricalDevice
	if direct_device:
		return direct_device
	return light.get_node_or_null("ElectricalDevice") as ElectricalDevice


func _set_regional_devices_forced_off(forced_off: bool) -> void:
	for light: Light3D in _regional_lights:
		var device := _device_for_light(light)
		if not device:
			continue
		if forced_off:
			device.force_off(&"regional_blackout")
		else:
			device.release_forced_off(&"regional_blackout")


func _suppress_lights(lights: Array[Light3D]) -> void:
	for light: Light3D in lights:
		if not is_instance_valid(light):
			continue
		if not _visibility_before_outage.has(light):
			_visibility_before_outage[light] = light.visible
		light.visible = false


func _release_light_if_powered(light: Light3D) -> void:
	if not is_instance_valid(light):
		_visibility_before_outage.erase(light)
		return
	if is_blackout or _regional_lights.has(light):
		return
	var device := _device_for_light(light)
	if device and device.is_forced_off():
		return
	if _visibility_before_outage.has(light):
		light.visible = bool(_visibility_before_outage[light])
		_visibility_before_outage.erase(light)


func _end_regional_blackout() -> void:
	if not is_regional_blackout and _regional_lights.is_empty():
		return
	var lights_to_restore: Array[Light3D] = _regional_lights.duplicate()
	_set_regional_devices_forced_off(false)
	_regional_lights.clear()
	is_regional_blackout = false
	_regional_time_remaining = -1.0
	for light: Light3D in lights_to_restore:
		_release_light_if_powered(light)
	regional_blackout_ended.emit()


func _update_outage_timers(delta: float) -> void:
	if is_blackout and _global_time_remaining >= 0.0:
		_global_time_remaining -= delta
		if _global_time_remaining <= 0.0:
			restore_power()

	if is_regional_blackout and _regional_time_remaining >= 0.0:
		_regional_time_remaining -= delta
		if _regional_time_remaining <= 0.0:
			_end_regional_blackout()


func _restore_all_house_lights() -> void:
	for entry: Variant in _visibility_before_outage.keys():
		var light := entry as Light3D
		if is_instance_valid(light):
			light.visible = bool(_visibility_before_outage[light])
	_visibility_before_outage.clear()

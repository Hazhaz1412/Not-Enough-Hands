class_name ElectricalZoneController
extends Node

## Bridges independent zone failures with the house-wide blackout contract.
## A full blackout is active only while every configured zone is unpowered.

signal all_zones_lost_power
signal at_least_one_zone_powered

@export var control_global_blackout_when_all_zones_off := true

var _power_manager: PowerManager
var _zones: Array[ElectricalZone] = []
var _all_zones_off := false


func _ready() -> void:
	_power_manager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	_collect_zones.call_deferred()


func _collect_zones() -> void:
	for child: Node in get_children():
		var zone := child as ElectricalZone
		if not zone:
			continue
		_zones.append(zone)
		zone.power_changed.connect(_on_zone_power_changed)
	_refresh_house_blackout()


func _exit_tree() -> void:
	for zone: ElectricalZone in _zones:
		if zone.power_changed.is_connected(_on_zone_power_changed):
			zone.power_changed.disconnect(_on_zone_power_changed)
	_zones.clear()


func get_zones() -> Array[ElectricalZone]:
	return _zones.duplicate()


func _on_zone_power_changed(_is_powered: bool) -> void:
	_refresh_house_blackout()


func _refresh_house_blackout() -> void:
	var all_off := not _zones.is_empty()
	for zone: ElectricalZone in _zones:
		if zone.is_powered:
			all_off = false
			break
	if all_off == _all_zones_off:
		return
	_all_zones_off = all_off
	if _all_zones_off:
		all_zones_lost_power.emit()
	else:
		at_least_one_zone_powered.emit()
	if control_global_blackout_when_all_zones_off and _power_manager:
		_power_manager.set_zone_blackout(_all_zones_off)

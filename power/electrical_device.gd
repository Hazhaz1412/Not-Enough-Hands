class_name ElectricalDevice
extends Node


signal state_changed(is_on: bool)


@export_category("Power Configuration")
@export_range(0.0, 100000.0, 1.0)
var power_consumption: float = 100.0


@export_category("Device State")
@export var is_on: bool = true


var power_manager: PowerManager
var _was_on_before_blackout: bool = false
var _forced_off_by_blackout: bool = false


func _enter_tree() -> void:
	add_to_group("electrical_device")


func _ready() -> void:
	power_manager = get_tree().get_first_node_in_group("power_manager")

	if power_manager:
		power_manager.register_device(self)

		power_manager.blackout.connect(_on_blackout)
		power_manager.power_restored.connect(_on_power_restored)

		print(name, " registered to PowerManager")
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


func turn_on() -> void:
	if _forced_off_by_blackout:
		return

	if is_on:
		return

	is_on = true
	state_changed.emit(is_on)


func turn_off() -> void:
	if not is_on:
		return

	is_on = false
	state_changed.emit(is_on)


func toggle() -> void:
	if is_on:
		turn_off()
	else:
		turn_on()


func _on_blackout() -> void:
	if is_on:
		_was_on_before_blackout = true
	else:
		_was_on_before_blackout = false

	_forced_off_by_blackout = true

	if is_on:
		is_on = false
		state_changed.emit(is_on)


func _on_power_restored() -> void:
	if not _forced_off_by_blackout:
		return

	_forced_off_by_blackout = false

	if _was_on_before_blackout:
		is_on = true
		state_changed.emit(is_on)

	_was_on_before_blackout = false

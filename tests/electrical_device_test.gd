extends Node


@onready var power_manager: PowerManager = $PowerManager
@onready var device_a: ElectricalDevice = $DeviceA
@onready var device_b: ElectricalDevice = $DeviceB


func _ready() -> void:
	print("========== ELECTRICAL DEVICE TEST ==========")

	test_initial_state()
	test_turn_off()
	test_turn_on()
	test_multiple_devices()
	test_blackout()

	print("========== ELECTRICAL DEVICE TEST PASSED ==========")


func test_initial_state() -> void:
	assert(
		device_a.is_on,
		"Device A should start ON"
	)

	assert(
		device_a.get_power_consumption() == device_a.power_consumption,
		"ON device should consume configured power"
	)


func test_turn_off() -> void:
	var original_load := power_manager.get_total_load()

	device_a.turn_off()

	assert(
		not device_a.is_on,
		"Device should be OFF after turn_off()"
	)

	assert(
		device_a.get_power_consumption() == 0.0,
		"OFF device should consume 0 power"
	)

	assert(
		power_manager.get_total_load() < original_load,
		"PowerManager load should decrease when device turns OFF"
	)


func test_turn_on() -> void:
	device_a.turn_on()

	assert(
		device_a.is_on,
		"Device should be ON after turn_on()"
	)

	assert(
		device_a.get_power_consumption() == device_a.power_consumption,
		"ON device should consume configured power"
	)


func test_multiple_devices() -> void:
	var expected_load := (
		device_a.power_consumption
		+ device_b.power_consumption
	)

	assert(
		power_manager.get_total_load() == expected_load,
		"PowerManager should calculate total load from multiple devices"
	)


func test_blackout() -> void:
	device_a.turn_on()
	device_b.turn_on()

	power_manager.current_power = 1.0
	power_manager.is_blackout = false
	power_manager.enable_power_drain = true

	power_manager._process(1.0)

	assert(
		power_manager.is_blackout,
		"PowerManager should enter blackout"
	)

	assert(
		not device_a.is_on,
		"Device A should turn OFF during blackout"
	)

	assert(
		not device_b.is_on,
		"Device B should turn OFF during blackout"
	)

	power_manager.restore_power()

	assert(
		device_a.is_on,
		"Device A should restore its previous ON state"
	)

	assert(
		device_b.is_on,
		"Device B should restore its previous ON state"
	)

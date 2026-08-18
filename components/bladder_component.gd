class_name BladderComponent
extends Node

enum ThresholdState { NORMAL, WARNING, CRITICAL, FULL }

signal value_changed(current_value: float, max_value: float)
signal threshold_changed(previous_state: ThresholdState, current_state: ThresholdState)
signal max_reached

@export var max_value: float = 100.0
@export var increase_rate: float = 2.0
@export var warning_threshold: float = 60.0
@export var critical_threshold: float = 85.0

var current_value: float = 0.0
var _current_threshold: ThresholdState = ThresholdState.NORMAL

func _ready() -> void:
	_update_threshold_state(true)

func _physics_process(delta: float) -> void:
	if increase_rate > 0 and current_value < max_value:
		add(increase_rate * delta)

func add(amount: float) -> void:
	if amount <= 0: return
	_set_value_internal(current_value + amount)

func reduce(amount: float) -> void:
	if amount <= 0: return
	_set_value_internal(current_value - amount)

func set_value(value: float) -> void:
	_set_value_internal(value)

func reset() -> void:
	_set_value_internal(0.0)

func get_value() -> float:
	return current_value

func get_normalized_value() -> float:
	if max_value <= 0: return 0.0
	return current_value / max_value

func is_full() -> bool:
	return current_value >= max_value

func get_threshold_state() -> ThresholdState:
	return _current_threshold

func _set_value_internal(new_value: float) -> void:
	var old_value = current_value
	current_value = clamp(new_value, 0.0, max_value)
	
	if current_value != old_value:
		value_changed.emit(current_value, max_value)
	
	_update_threshold_state()

func _update_threshold_state(force: bool = false) -> void:
	var new_state = ThresholdState.NORMAL
	if current_value >= max_value:
		new_state = ThresholdState.FULL
	elif current_value >= critical_threshold:
		new_state = ThresholdState.CRITICAL
	elif current_value >= warning_threshold:
		new_state = ThresholdState.WARNING
		
	var old_state = _current_threshold
	if new_state != old_state or force:
		_current_threshold = new_state
		if not force:
			threshold_changed.emit(old_state, new_state)
			
		if new_state == ThresholdState.FULL and old_state != ThresholdState.FULL:
			max_reached.emit()

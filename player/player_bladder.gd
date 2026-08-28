class_name PlayerBladder
extends Node

## Tracks the player's bladder level. Fills passively over time (via the
## engine's normal _physics_process, so it automatically respects
## get_tree().paused like everything else - no separate Timer needed).
## The toilet minigame drives it through add_bladder()/reduce_bladder()/
## reset_bladder(); everything else just reads get_bladder()/
## get_bladder_ratio() or reacts to bladder_changed.

signal bladder_changed(value: float, max_value: float)
signal bladder_warning_started
signal bladder_full

## At the default clock speed (1.5 real seconds per game minute), this makes
## an empty bladder full after 45 in-game minutes / 67.5 real seconds.
const DEFAULT_FULL_DURATION_REAL_SECONDS: float = 45.0 * 1.5

@export var bladder_max: float = 100.0
@export var bladder_fill_rate: float = 100.0 / DEFAULT_FULL_DURATION_REAL_SECONDS
@export var bladder_warning_threshold: float = 70.0
@export var bladder_full_threshold: float = 100.0

var current_value: float = 0.0

var _warning_active: bool = false
var _full_active: bool = false


func _physics_process(delta: float) -> void:
	if bladder_fill_rate > 0.0 and current_value < bladder_max:
		add_bladder(bladder_fill_rate * delta)


func add_bladder(amount: float) -> void:
	if amount <= 0.0:
		return
	_set_value(current_value + amount)


func reduce_bladder(amount: float) -> void:
	if amount <= 0.0:
		return
	_set_value(current_value - amount)


func reset_bladder() -> void:
	_set_value(0.0)


func set_bladder(value: float) -> void:
	_set_value(value)


func get_bladder() -> float:
	return current_value


func get_bladder_ratio() -> float:
	return current_value / bladder_max if bladder_max > 0.0 else 0.0


func _set_value(new_value: float) -> void:
	var old_value := current_value
	current_value = clampf(new_value, 0.0, bladder_max)
	if current_value == old_value:
		return
	bladder_changed.emit(current_value, bladder_max)
	_update_thresholds()


## Edge-detected against the *current* boolean state (not the signal
## history) so warning/full each fire once per crossing and re-arm as soon
## as the value drops back below their threshold - satisfies both "only
## once per fill event" and "may fire again after a later reduce()".
func _update_thresholds() -> void:
	var is_warning := current_value >= bladder_warning_threshold
	if is_warning and not _warning_active:
		bladder_warning_started.emit()
	_warning_active = is_warning

	var is_full := current_value >= bladder_full_threshold
	if is_full and not _full_active:
		bladder_full.emit()
	_full_active = is_full

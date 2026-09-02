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
## Control is gone and it is emptying itself wherever the player is standing.
signal wetting_started
signal wetting_ended

## At the default clock speed (1.5 real seconds per game minute), this makes an
## empty bladder full after 180 in-game minutes / 270 real seconds. The longer
## runway keeps toilet pressure meaningful without interrupting every trip.
const DEFAULT_FULL_DURATION_REAL_SECONDS: float = 180.0 * 1.5
## What a controlled session at the toilet costs, and the number the loss of
## control below is measured against. Kept here rather than read off
## ToiletMinigame so the bladder does not depend on a minigame it never sees.
const CONTROLLED_EMPTY_SECONDS: float = 13.5

@export var bladder_max: float = 100.0
@export var bladder_fill_rate: float = 100.0 / DEFAULT_FULL_DURATION_REAL_SECONDS
@export var bladder_warning_threshold: float = 70.0
@export var bladder_full_threshold: float = 100.0
## Once it is full it goes on its own, and this is how long that takes, flat, in
## seconds. Deliberately an absolute number rather than a multiple of
## `CONTROLLED_EMPTY_SECONDS`: what matters is how long the player spends slowed
## and half blind, and that should not silently move every time the toilet
## minigame is retuned. It must stay above `CONTROLLED_EMPTY_SECONDS` or losing
## control would be the *fast* way to empty a bladder and the debuff would be a
## reward - `tests/bladder_pressure_smoke.gd` pins that.
@export_range(1.0, 120.0, 0.5) var wetting_duration_seconds: float = 20.0

var current_value: float = 0.0
## True from the moment it fills to the moment it is empty again. Not the same
## as "is full": it stays true all the way down, which is what makes wetting a
## long punishment rather than an instant reset.
var is_wetting: bool = false

var _warning_active: bool = false
var _full_active: bool = false


func _physics_process(delta: float) -> void:
	if is_wetting:
		_process_wetting(delta)
		return
	if bladder_fill_rate > 0.0 and current_value < bladder_max:
		add_bladder(bladder_fill_rate * delta)


## Draining on its own. Nothing refills while this runs, so the player is not
## fighting the fill rate at the same time. The *end* of it is decided in
## `_update_thresholds()` rather than here, because a client never runs this
## function at all - its value arrives from the server - and an accident that
## could only be ended by the code that drains it stayed switched on forever on
## every peer but the host.
func _process_wetting(delta: float) -> void:
	var seconds := maxf(wetting_duration_seconds, 0.1)
	_set_value(current_value - (bladder_max / seconds) * delta)


## Rate a controlled session drains at, for anything that wants to compare
## against it (the toilet minigame owns its own copy of the same number).
func get_controlled_drain_rate() -> float:
	return bladder_max / CONTROLLED_EMPTY_SECONDS


func add_bladder(amount: float) -> void:
	if amount <= 0.0:
		return
	_set_value(current_value + amount)


func reduce_bladder(amount: float) -> void:
	if amount <= 0.0:
		return
	_set_value(current_value - amount)


## Reaching the toilet in time is the way out of an accident in progress as well
## as the way to avoid one. Emptying it is all this has to do: `_set_value()`
## is where an accident is ended, so a player who made it is not left draining
## on the floor of a bathroom.
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
		if not is_wetting:
			is_wetting = true
			wetting_started.emit()
	_full_active = is_full

	# Ends wherever the value came from - the local drain, a snapshot from the
	# server, or a toilet reached in time - so every peer agrees about when the
	# accident is over and nobody is left permanently slowed.
	if is_wetting and current_value <= 0.0:
		is_wetting = false
		wetting_ended.emit()

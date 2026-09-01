class_name NightClock
extends CanvasLayer

signal minute_changed(minutes_of_day: int, formatted_time: String)
signal victory_reached()

@export_category("Clock")
@export_range(0, 23, 1) var start_hour: int = 23
@export_range(0, 59, 1) var start_minute: int = 55
@export_range(0, 23, 1) var victory_hour: int = 6
@export_range(0, 59, 1) var victory_minute: int = 0
## Ceiling for skip_minutes(). Time granted by the totem ritual stops here:
## the night can still run past 4:00 AM on its own, but nothing can be burned
## to jump it there.
@export_range(0, 23, 1) var skip_limit_hour: int = 4
@export_range(0, 59, 1) var skip_limit_minute: int = 0
## The night advances one in-game minute every 1.5 seconds of real time.
@export var real_seconds_per_game_minute: float = 1.5

@export_category("Game state")
@export var player_path: NodePath = NodePath("../Player")
@export var pause_on_victory: bool = true

var running: bool = true
var won: bool = false
var current_minutes_of_day: int = 0
var elapsed_game_minutes: int = 0
var _real_time_accumulator: float = 0.0
var _minutes_until_victory: int = 0
var _player: Node

@onready var clock_panel: PanelContainer = $ClockPanel
@onready var time_label: Label = $ClockPanel/Margin/VBox/Time
@onready var victory_overlay: ColorRect = $VictoryOverlay


func _ready() -> void:
	add_to_group(&"night_clock")
	_player = get_node_or_null(player_path)
	reset_clock()


func _process(delta: float) -> void:
	if _player and "is_alive" in _player and not bool(_player.get("is_alive")):
		running = false
		clock_panel.visible = false
		return
	clock_panel.visible = running and not won and not _player_is_in_door_minigame()
	advance_real_seconds(delta)


func reset_clock() -> void:
	running = true
	won = false
	elapsed_game_minutes = 0
	_real_time_accumulator = 0.0
	current_minutes_of_day = _clock_minutes(start_hour, start_minute)
	var target := _clock_minutes(victory_hour, victory_minute)
	_minutes_until_victory = target - current_minutes_of_day
	if _minutes_until_victory <= 0:
		_minutes_until_victory += 24 * 60
	victory_overlay.visible = false
	clock_panel.visible = true
	_update_time_label()


## The night is one clock for the whole house, so only the authority runs it.
## A client's copy is driven by apply_network_time() instead - otherwise four
## machines would each count their own 6:00 AM.
func advance_real_seconds(seconds: float) -> void:
	if not WorldNet.is_world_authority():
		return
	if not running or won or seconds <= 0.0:
		return
	_real_time_accumulator += seconds
	var tick_duration := maxf(real_seconds_per_game_minute, 0.001)
	while _real_time_accumulator >= tick_duration and not won:
		_real_time_accumulator -= tick_duration
		_advance_one_game_minute()


func get_formatted_time() -> String:
	return _format_minutes(current_minutes_of_day)


func get_minutes_remaining() -> int:
	return maxi(_minutes_until_victory - elapsed_game_minutes, 0)


## In-game minutes that skip_minutes() can still hand out before the night hits
## its skip ceiling (4:00 AM by default, and never past dawn).
func get_minutes_until_skip_limit() -> int:
	var ceiling := mini(_skip_limit_elapsed(), _minutes_until_victory)
	return maxi(ceiling - elapsed_game_minutes, 0)


## Jumps the night forward by up to `minutes`, stopping dead at the skip
## ceiling, and returns how many minutes were actually granted. A 30-minute
## burn at 3:50 AM is handed 10. One at 4:00 AM is handed nothing.
## Every minute is stepped through rather than assigned, so minute_changed
## listeners see the jump the same way they see the night pass.
##
## A client is granted nothing: the burn it just made is reported to the server,
## which advances the one real clock and sends the result back. Returning 0 here
## is what stops a totem being worth thirty minutes on every machine at once.
func skip_minutes(minutes: int) -> int:
	if not WorldNet.is_world_authority():
		return 0
	if not running or won or minutes <= 0:
		return 0
	var granted := mini(minutes, get_minutes_until_skip_limit())
	for i: int in granted:
		_advance_one_game_minute()
	return granted


## Takes the server's night wholesale.
##
## The jump is assigned rather than stepped - a peer that joins at 2:00 AM would
## otherwise run a few hundred iterations of _advance_one_game_minute() before
## it could draw a frame - but minute_changed still fires once, because the
## ritual's completion check and the HUD both hang off it and a jump they never
## heard would leave them showing the old night.
func apply_network_time(elapsed: int, minutes_of_day: int, server_won: bool) -> void:
	elapsed_game_minutes = elapsed
	current_minutes_of_day = posmod(minutes_of_day, 24 * 60)
	_real_time_accumulator = 0.0
	_update_time_label()
	minute_changed.emit(current_minutes_of_day, get_formatted_time())
	if server_won and not won:
		_reach_victory()


func _advance_one_game_minute() -> void:
	elapsed_game_minutes += 1
	current_minutes_of_day = (current_minutes_of_day + 1) % (24 * 60)
	_update_time_label()
	minute_changed.emit(current_minutes_of_day, get_formatted_time())
	if elapsed_game_minutes >= _minutes_until_victory:
		_reach_victory()


func _reach_victory() -> void:
	if won:
		return
	current_minutes_of_day = _clock_minutes(victory_hour, victory_minute)
	_update_time_label()
	running = false
	won = true
	clock_panel.visible = false
	victory_overlay.visible = true
	get_tree().call_group("hostile_ghosts", "set_dev_attack_suspended", true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	victory_reached.emit()
	if pause_on_victory:
		get_tree().paused = true


func _update_time_label() -> void:
	if time_label:
		time_label.text = get_formatted_time()


func _player_is_in_door_minigame() -> bool:
	if _player == null:
		return false
	if _player.has_method("is_any_minigame_active"):
		return bool(_player.call("is_any_minigame_active"))
	return _player.has_method("is_door_minigame_active") \
		and bool(_player.call("is_door_minigame_active"))


## The skip ceiling expressed the way elapsed_game_minutes is - minutes since
## the night started - so a ceiling after midnight compares cleanly.
func _skip_limit_elapsed() -> int:
	var delta := (
		_clock_minutes(skip_limit_hour, skip_limit_minute)
		- _clock_minutes(start_hour, start_minute)
	)
	if delta <= 0:
		delta += 24 * 60
	return delta


func _clock_minutes(hour: int, minute: int) -> int:
	return clampi(hour, 0, 23) * 60 + clampi(minute, 0, 59)


func _format_minutes(value: int) -> String:
	var normalized := posmod(value, 24 * 60)
	var hour_24 := int(normalized / 60)
	var minute := normalized % 60
	var suffix := "AM" if hour_24 < 12 else "PM"
	var hour_12 := hour_24 % 12
	if hour_12 == 0:
		hour_12 = 12
	return "%d:%02d %s" % [hour_12, minute, suffix]

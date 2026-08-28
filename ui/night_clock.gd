class_name NightClock
extends CanvasLayer

signal minute_changed(minutes_of_day: int, formatted_time: String)
signal victory_reached()

@export_category("Clock")
@export_range(0, 23, 1) var start_hour: int = 23
@export_range(0, 59, 1) var start_minute: int = 55
@export_range(0, 23, 1) var victory_hour: int = 6
@export_range(0, 59, 1) var victory_minute: int = 0
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


func advance_real_seconds(seconds: float) -> void:
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

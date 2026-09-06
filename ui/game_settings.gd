extends Node

## Every option the game can actually honour, in one file, applied the moment
## it changes and again on the next boot.
##
## Only settings with a real consumer live here: each key below is read by
## DisplayServer, AudioServer, InputMap, or `player/player.gd`. An option that
## nothing consumes is worse than no option at all, so the consumer comes first
## and the key second.
##
## `player/player.gd` reaches this through `/root/GameSettings` rather than by
## name, for the same reason `WorldNet` exists: the smoke tests load that script
## with `--script`, where an autoload identifier is not guaranteed to resolve.

signal changed(key: String, value: Variant)
signal binds_changed()

const SETTINGS_PATH := "user://settings.cfg"

const WINDOW_MODE_WINDOWED := 0
const WINDOW_MODE_FULLSCREEN := 1
const WINDOW_MODE_EXCLUSIVE := 2

## `<section>/<name>` doubles as the ConfigFile address, so a new option is one
## line here plus one row in `ui/settings_menu.gd`.
const DEFAULTS := {
	"display/window_mode": WINDOW_MODE_WINDOWED,
	"display/vsync": true,
	"display/max_fps": 0,
	"display/render_scale": 1.0,
	"audio/master_volume": 0.85,
	"audio/muted": false,
	"controls/mouse_sensitivity": 0.002,
	"controls/invert_look_y": false,
	"gameplay/field_of_view": 70.0,
	"gameplay/head_bob": 1.0,
	"player/name": "Player",
}

## The keys a player can rebind, in the order the settings screen lists them.
## Anything not here keeps the binding shipped in `project.godot`.
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_backward",
	&"move_left",
	&"move_right",
	&"run",
	&"crouch",
	&"jump",
	&"interact",
	&"drop_item",
	&"flashlight_toggle",
	&"flashlight_focus",
	&"lean_left",
	&"lean_right",
	&"select_slot_1",
	&"select_slot_2",
]

const ACTION_LABELS := {
	&"move_forward": "Đi tới",
	&"move_backward": "Đi lùi",
	&"move_left": "Sang trái",
	&"move_right": "Sang phải",
	&"run": "Chạy",
	&"crouch": "Ngồi xuống",
	&"jump": "Nhảy",
	&"interact": "Tương tác",
	&"drop_item": "Bỏ vật phẩm",
	&"flashlight_toggle": "Bật/tắt đèn pin",
	&"flashlight_focus": "Hội tụ đèn pin",
	&"lean_left": "Nghiêng trái",
	&"lean_right": "Nghiêng phải",
	&"select_slot_1": "Ô đồ 1",
	&"select_slot_2": "Ô đồ 2",
}

var _values: Dictionary = {}
## Whatever `project.godot` shipped, captured before anything is rebound, so
## "khôi phục mặc định" restores the real defaults rather than a guess.
var _default_events: Dictionary = {}
var _binds: Dictionary = {}


func _ready() -> void:
	# Settings have to answer while the tree is paused - the pause menu is where
	# most of them get changed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_default_events()
	load_settings()
	apply_all()


func get_setting(key: String, fallback: Variant = null) -> Variant:
	if _values.has(key):
		return _values[key]
	return DEFAULTS.get(key, fallback)


func get_number(key: String, fallback: float = 0.0) -> float:
	return float(get_setting(key, fallback))


func get_flag(key: String, fallback: bool = false) -> bool:
	return bool(get_setting(key, fallback))


func set_setting(key: String, value: Variant, save: bool = true) -> void:
	if _values.get(key) != null and _values[key] == value:
		return
	_values[key] = value
	_apply_setting(key, value)
	changed.emit(key, value)
	if save:
		save_settings()


func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate(true)
	_binds.clear()
	apply_all()
	save_settings()
	for key: String in DEFAULTS:
		changed.emit(key, _values[key])
	binds_changed.emit()


## The one input event bound to `action`, or null while it still uses the
## shipped default. Rebinding replaces every event on the action, so a key and
## its mouse alternative cannot drift apart.
func set_bind(action: StringName, event: InputEvent) -> bool:
	if not REBINDABLE_ACTIONS.has(action):
		return false
	var record := _event_to_record(event)
	if record.is_empty():
		return false
	_binds[String(action)] = record
	_apply_binds()
	save_settings()
	binds_changed.emit()
	return true


func clear_binds() -> void:
	_binds.clear()
	_apply_binds()
	save_settings()
	binds_changed.emit()


## What the settings screen prints next to an action: the first event bound to
## it, however it got there.
func get_bind_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var keycode := key_event.physical_keycode \
				if key_event.keycode == KEY_NONE \
				else key_event.keycode
			return OS.get_keycode_string(keycode)
		if event is InputEventMouseButton:
			return _mouse_button_name((event as InputEventMouseButton).button_index)
	return "—"


func apply_all() -> void:
	for key: String in DEFAULTS:
		_apply_setting(key, get_setting(key))
	_apply_binds()


func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in DEFAULTS:
		var parts := key.split("/", false, 1)
		config.set_value(parts[0], parts[1], get_setting(key))
	config.set_value("controls", "binds", _binds)
	config.save(SETTINGS_PATH)


func load_settings() -> void:
	_values = DEFAULTS.duplicate(true)
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for key: String in DEFAULTS:
		var parts := key.split("/", false, 1)
		var stored: Variant = config.get_value(parts[0], parts[1], DEFAULTS[key])
		# A hand-edited or older config must not be able to change a setting's
		# type out from under its consumer.
		if typeof(stored) == typeof(DEFAULTS[key]):
			_values[key] = stored
	var stored_binds: Variant = config.get_value("controls", "binds", {})
	if stored_binds is Dictionary:
		_binds = (stored_binds as Dictionary).duplicate(true)


func _apply_setting(key: String, value: Variant) -> void:
	match key:
		"display/window_mode":
			_apply_window_mode(int(value))
		"display/vsync":
			if not _is_headless():
				DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED
				)
		"display/max_fps":
			Engine.max_fps = maxi(int(value), 0)
		"display/render_scale":
			var root_window := get_tree().root if is_inside_tree() else null
			if root_window:
				root_window.scaling_3d_scale = clampf(float(value), 0.5, 1.0)
		"audio/master_volume":
			AudioServer.set_bus_volume_db(
				0, linear_to_db(clampf(float(value), 0.0, 1.0))
			)
		"audio/muted":
			AudioServer.set_bus_mute(0, bool(value))


func _apply_window_mode(mode: int) -> void:
	if _is_headless():
		return
	match mode:
		WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WINDOW_MODE_EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## Every rebindable action is rebuilt from its shipped default and then
## overridden, so clearing one custom bind cannot leave the action empty.
func _apply_binds() -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		var record: Variant = _binds.get(String(action))
		var custom := _record_to_event(record) if record is Dictionary else null
		if custom:
			InputMap.action_add_event(action, custom)
			continue
		for default_event: InputEvent in _default_events.get(action, [] as Array[InputEvent]):
			InputMap.action_add_event(action, default_event)


func _capture_default_events() -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var events: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.duplicate() as InputEvent)
		_default_events[action] = events


## Keycodes and button indices, not serialized InputEvent objects: a config file
## that can only describe a key or a mouse button cannot be edited into
## something that fails to load.
func _event_to_record(event: InputEvent) -> Dictionary:
	var key_event := event as InputEventKey
	if key_event:
		var keycode := key_event.physical_keycode \
			if key_event.keycode == KEY_NONE \
			else key_event.keycode
		if keycode == KEY_NONE:
			return {}
		return {"device": "key", "code": int(keycode)}
	var mouse_event := event as InputEventMouseButton
	if mouse_event:
		return {"device": "mouse", "code": int(mouse_event.button_index)}
	return {}


func _record_to_event(record: Dictionary) -> InputEvent:
	var code := int(record.get("code", 0))
	if code <= 0:
		return null
	match str(record.get("device", "key")):
		"mouse":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = code as MouseButton
			return mouse_event
		_:
			var key_event := InputEventKey.new()
			key_event.keycode = code as Key
			return key_event


func _mouse_button_name(button_index: int) -> String:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return "Chuột trái"
		MOUSE_BUTTON_RIGHT:
			return "Chuột phải"
		MOUSE_BUTTON_MIDDLE:
			return "Chuột giữa"
		MOUSE_BUTTON_WHEEL_UP:
			return "Lăn lên"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Lăn xuống"
		MOUSE_BUTTON_XBUTTON1:
			return "Chuột phụ 1"
		MOUSE_BUTTON_XBUTTON2:
			return "Chuột phụ 2"
	return "Chuột %d" % button_index


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

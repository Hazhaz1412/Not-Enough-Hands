extends Control

const PROFILE_PATH := "user://multiplayer_profile.cfg"

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var port_spin: SpinBox = %PortSpin
@onready var status_label: Label = %StatusLabel
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var paste_button: Button = %PasteButton
@onready var back_button: Button = %BackButton

## Length of the address field after the last change, so a paste (many
## characters at once) can be told apart from typing (one at a time).
var _last_address_length: int = 0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	NetworkManager.status_changed.connect(_show_status)
	_load_profile()
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	paste_button.pressed.connect(_on_paste_pressed)
	back_button.pressed.connect(_on_back_pressed)
	name_edit.text_submitted.connect(func(_value: String) -> void: _on_host_pressed())
	address_edit.text_submitted.connect(func(_value: String) -> void: _on_join_pressed())
	address_edit.text_changed.connect(_on_address_changed)
	address_edit.focus_exited.connect(
		func() -> void: _apply_parsed_address(address_edit.text, true)
	)

	var args := OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or "--server" in args:
		visible = false
		NetworkManager.start_dedicated_server(_argument_port(args))
		return
	var auto_join := _argument_value(args, "--join=")
	if not auto_join.is_empty():
		port_spin.value = _argument_port(args)
		# `--join=host:port` is accepted for the same reason the field is: an
		# address handed out by a hosting panel arrives as one string.
		_apply_parsed_address(auto_join, false)
		var auto_name := _argument_value(args, "--name=")
		if not auto_name.is_empty():
			name_edit.text = auto_name
		_on_join_pressed()


## "890e3824ae79.pr.edgegap.net:31157" is what a hosting panel hands a player,
## and it is one string rather than a host and a port. Everything somebody can
## plausibly paste is reduced here to `{host, port}` - a scheme, a trailing
## path, stray quotes and bracketed IPv6 included. `port` is 0 when the text
## carries none, which leaves whatever the port field already holds alone.
static func parse_address(raw: String) -> Dictionary:
	var result := {"host": "", "port": 0}
	var text := raw.strip_edges().lstrip("\"'").rstrip("\"'").strip_edges()
	if text.is_empty():
		return result
	var scheme := text.find("://")
	if scheme >= 0:
		text = text.substr(scheme + 3)
	for separator: String in ["/", "?", "#"]:
		var cut := text.find(separator)
		if cut >= 0:
			text = text.substr(0, cut)
	text = text.strip_edges()

	if text.begins_with("["):
		var close := text.find("]")
		if close > 0:
			result["host"] = text.substr(1, close - 1)
			var tail := text.substr(close + 1)
			if tail.begins_with(":"):
				result["port"] = _valid_port(tail.substr(1))
			return result

	# A bare IPv6 address is full of colons and carries no port; only a single
	# colon can be a host/port separator.
	var colon := text.rfind(":")
	if colon > 0 and text.count(":") == 1:
		var port := _valid_port(text.substr(colon + 1))
		if port > 0:
			result["host"] = text.substr(0, colon)
			result["port"] = port
			return result
	result["host"] = text
	return result


static func _valid_port(value: String) -> int:
	var trimmed := value.strip_edges()
	if not trimmed.is_valid_int():
		return 0
	var port := int(trimmed)
	return port if port > 0 and port <= 65535 else 0


## Splits whatever is in the field into the two controls that actually get used,
## so the player never has to know the port is a separate box.
func _apply_parsed_address(raw: String, announce: bool) -> void:
	var parsed := parse_address(raw)
	var host := str(parsed["host"])
	var port := int(parsed["port"])
	if host.is_empty():
		return
	address_edit.text = host
	_last_address_length = host.length()
	if port <= 0:
		return
	port_spin.value = port
	if announce:
		_show_status("Đã tách địa chỉ: %s  ·  cổng UDP %d." % [host, port])


func _on_address_changed(new_text: String) -> void:
	var pasted := new_text.length() - _last_address_length >= 2
	_last_address_length = new_text.length()
	if pasted and new_text.contains(":"):
		_apply_parsed_address(new_text, true)


func _on_paste_pressed() -> void:
	var clipboard := DisplayServer.clipboard_get()
	if clipboard.strip_edges().is_empty():
		_show_status("Bộ nhớ tạm đang trống.")
		return
	_apply_parsed_address(clipboard, true)
	join_button.grab_focus()


func _on_back_pressed() -> void:
	NetworkManager.return_to_main_menu()


func _on_host_pressed() -> void:
	_set_buttons_enabled(false)
	_save_profile()
	var result := NetworkManager.host_game(name_edit.text, int(port_spin.value))
	if result != OK:
		_set_buttons_enabled(true)


func _on_join_pressed() -> void:
	# Joining is the one moment the field must be split whether or not the
	# player ever left it: paste, Enter, done.
	_apply_parsed_address(address_edit.text, false)
	_set_buttons_enabled(false)
	_save_profile()
	var result := NetworkManager.join_game(
		address_edit.text,
		name_edit.text,
		int(port_spin.value)
	)
	if result != OK:
		_set_buttons_enabled(true)


func _show_status(message: String) -> void:
	status_label.text = message
	if message.contains("thất bại") or message.contains("Không thể"):
		_set_buttons_enabled(true)


func _set_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled


func _save_profile() -> void:
	var display_name := NetworkManager.sanitize_display_name(name_edit.text)
	GameSettings.set_setting("player/name", display_name)
	var profile := ConfigFile.new()
	profile.set_value("connection", "address", address_edit.text.strip_edges())
	profile.set_value("connection", "port", int(port_spin.value))
	profile.save(PROFILE_PATH)


func _load_profile() -> void:
	# The name lives in the settings file now, so one player has one name
	# everywhere; the address and port stay local to this screen.
	name_edit.text = str(GameSettings.get_setting("player/name", "Player"))
	var profile := ConfigFile.new()
	if profile.load(PROFILE_PATH) != OK:
		address_edit.text = "127.0.0.1"
		_last_address_length = address_edit.text.length()
		return
	address_edit.text = str(profile.get_value("connection", "address", "127.0.0.1"))
	port_spin.value = int(profile.get_value("connection", "port", NetworkManager.DEFAULT_PORT))
	_last_address_length = address_edit.text.length()


func _argument_value(args: PackedStringArray, prefix: String) -> String:
	for argument: String in args:
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _argument_port(args: PackedStringArray) -> int:
	var value := _argument_value(args, "--port=")
	if value.is_valid_int():
		return int(value)
	# Edgegap injects this variable when the App Version port is named
	# "gameport". A normal local run simply falls back to 7777.
	var edgegap_port := OS.get_environment("ARBITRIUM_PORT_GAMEPORT_INTERNAL")
	return int(edgegap_port) if edgegap_port.is_valid_int() else NetworkManager.DEFAULT_PORT

extends Control

const PROFILE_PATH := "user://multiplayer_profile.cfg"

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var port_spin: SpinBox = %PortSpin
@onready var status_label: Label = %StatusLabel
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	NetworkManager.status_changed.connect(_show_status)
	_load_profile()
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	name_edit.text_submitted.connect(func(_value: String) -> void: _on_host_pressed())
	address_edit.text_submitted.connect(func(_value: String) -> void: _on_join_pressed())

	var args := OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or "--server" in args:
		visible = false
		NetworkManager.start_dedicated_server(_argument_port(args))
		return
	var auto_join := _argument_value(args, "--join=")
	if not auto_join.is_empty():
		address_edit.text = auto_join
		port_spin.value = _argument_port(args)
		var auto_name := _argument_value(args, "--name=")
		if not auto_name.is_empty():
			name_edit.text = auto_name
		_on_join_pressed()


func _on_host_pressed() -> void:
	_set_buttons_enabled(false)
	_save_profile()
	var result := NetworkManager.host_game(name_edit.text, int(port_spin.value))
	if result != OK:
		_set_buttons_enabled(true)


func _on_join_pressed() -> void:
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
	var profile := ConfigFile.new()
	profile.set_value("player", "name", NetworkManager.sanitize_display_name(name_edit.text))
	profile.set_value("connection", "address", address_edit.text.strip_edges())
	profile.set_value("connection", "port", int(port_spin.value))
	profile.save(PROFILE_PATH)


func _load_profile() -> void:
	var profile := ConfigFile.new()
	if profile.load(PROFILE_PATH) != OK:
		name_edit.text = "Player"
		return
	name_edit.text = str(profile.get_value("player", "name", "Player"))
	address_edit.text = str(profile.get_value("connection", "address", "127.0.0.1"))
	port_spin.value = int(profile.get_value("connection", "port", NetworkManager.DEFAULT_PORT))


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

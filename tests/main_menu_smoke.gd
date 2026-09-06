extends SceneTree

## Covers the front of the game: the main menu's four routes, the settings
## autoload that persists and applies them, and the address field that has to
## accept a whole "host:port" string pasted out of a hosting panel.

const MENU_SCENE := "res://ui/main_menu.tscn"
const SETTINGS_SCENE := "res://ui/settings_menu.tscn"
const MULTIPLAYER_MENU := "res://network/multiplayer_menu.gd"
const MENU_SCENE_SCRIPT := "res://ui/main_menu.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_address_parsing()
	await _test_main_menu()
	await _test_settings_menu()
	_test_settings_autoload()
	await _test_solo_route()
	print("Main menu smoke test passed: routes, settings and address parsing.")
	quit()


## The whole point of the field: what a hosting panel hands out is one string.
func _test_address_parsing() -> void:
	var menu_script: GDScript = load(MULTIPLAYER_MENU)
	var cases := [
		{
			"input": "890e3824ae79.pr.edgegap.net:31157",
			"host": "890e3824ae79.pr.edgegap.net",
			"port": 31157,
		},
		{"input": "  127.0.0.1:7777  ", "host": "127.0.0.1", "port": 7777},
		{"input": "udp://host.example.com:9999/", "host": "host.example.com", "port": 9999},
		{"input": "\"10.0.0.4:47311\"", "host": "10.0.0.4", "port": 47311},
		# No port in the text leaves the port field alone, so it answers 0.
		{"input": "127.0.0.1", "host": "127.0.0.1", "port": 0},
		{"input": "::1", "host": "::1", "port": 0},
		{"input": "[::1]:7777", "host": "::1", "port": 7777},
		# 70000 is not a port, so the colon is not a separator.
		{"input": "weird:70000", "host": "weird:70000", "port": 0},
	]
	for case: Dictionary in cases:
		var parsed: Dictionary = menu_script.parse_address(str(case["input"]))
		if str(parsed["host"]) != str(case["host"]) or int(parsed["port"]) != int(case["port"]):
			_fail("\"%s\" parsed as %s, expected host=%s port=%d" % [
				case["input"], parsed, case["host"], case["port"],
			])
			return


func _test_main_menu() -> void:
	var menu := (load(MENU_SCENE) as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	for button_name: String in ["SoloButton", "OnlineButton", "SettingsButton", "QuitButton"]:
		if menu.get_node_or_null("%%%s" % button_name) == null:
			_fail("The main menu is missing %s." % button_name)
			return

	var manager: Node = root.get_node_or_null("NetworkManager")
	if manager == null:
		_fail("NetworkManager autoload is missing.")
		return
	# Single player is House2 and multiplayer is the villa: the two maps the
	# menu routes between must not have been swapped.
	if str(manager.get("SOLO_SCENE")) != "res://main.tscn":
		_fail("Single player must load main.tscn, got %s." % manager.get("SOLO_SCENE"))
		return
	if str(manager.get("GAME_SCENE")) != "res://house3/villa_main.tscn":
		_fail("Multiplayer must load the villa, got %s." % manager.get("GAME_SCENE"))
		return
	if not manager.has_method("start_single_player") \
			or not manager.has_method("return_to_main_menu"):
		_fail("NetworkManager is missing the menu's entry points.")
		return

	# The boot scene moved here, so the documented server/join flags have to be
	# forwarded or a dedicated server never starts.
	var menu_script: GDScript = load(MENU_SCENE_SCRIPT)
	var automation_cases := {
		"--server": true,
		"--join=127.0.0.1": true,
		"--lobby-auto-ready": false,
	}
	for argument: String in automation_cases:
		var forwarded: bool = menu_script.has_automation_arguments(
			PackedStringArray([argument])
		)
		if forwarded != bool(automation_cases[argument]):
			_fail("%s forwarding to the multiplayer menu is %s." % [argument, forwarded])
			return

	var settings_menu := menu.get_node_or_null("%SettingsMenu") as Control
	if settings_menu == null or settings_menu.visible:
		_fail("The settings screen must be present and start hidden.")
		return
	settings_menu.call("open")
	await process_frame
	if not settings_menu.visible:
		_fail("CÀI ĐẶT did not open the settings screen.")
		return

	menu.queue_free()
	await process_frame


func _test_settings_menu() -> void:
	var settings_menu := (load(SETTINGS_SCENE) as PackedScene).instantiate() as Control
	root.add_child(settings_menu)
	await process_frame

	# Every tab has to have built its rows: an empty tab is what a renamed
	# settings key looks like from the outside.
	for rows_name: String in ["%DisplayRows", "%AudioRows", "%ControlRows", "%GameRows"]:
		var rows := settings_menu.get_node_or_null(rows_name) as VBoxContainer
		if rows == null or rows.get_child_count() == 0:
			_fail("Settings tab %s built no rows." % rows_name)
			return

	var settings: Node = root.get_node_or_null("GameSettings")
	var bind_rows := settings_menu.get_node_or_null("%ControlRows") as VBoxContainer
	var bind_buttons := 0
	for row: Node in bind_rows.get_children():
		for child: Node in row.get_children():
			if child is Button and (child as Button).has_meta(&"action"):
				bind_buttons += 1
	if bind_buttons != settings.get("REBINDABLE_ACTIONS").size():
		_fail("Expected one rebind row per action, found %d." % bind_buttons)
		return

	settings_menu.queue_free()
	await process_frame


func _test_settings_autoload() -> void:
	var settings: Node = root.get_node_or_null("GameSettings")
	if settings == null:
		_fail("GameSettings autoload is missing.")
		return

	var original: float = settings.call("get_number", "controls/mouse_sensitivity", 0.0)
	settings.call("set_setting", "controls/mouse_sensitivity", 0.0031)
	if not is_equal_approx(settings.call("get_number", "controls/mouse_sensitivity", 0.0), 0.0031):
		_fail("A changed setting did not read back.")
		return

	# A rebind has to reach InputMap, not just the config file.
	var event := InputEventKey.new()
	event.keycode = KEY_H
	if not settings.call("set_bind", &"interact", event):
		_fail("Rebinding interact was rejected.")
		return
	if not InputMap.action_has_event(&"interact", event):
		_fail("Rebinding interact did not reach InputMap.")
		return
	if settings.call("get_bind_text", &"interact") != "H":
		_fail("The settings screen would print the wrong key for interact.")
		return

	settings.call("reset_to_defaults")
	if InputMap.action_has_event(&"interact", event):
		_fail("Restoring defaults left the custom bind in place.")
		return
	if not is_equal_approx(
		settings.call("get_number", "controls/mouse_sensitivity", 0.0),
		float(settings.get("DEFAULTS")["controls/mouse_sensitivity"])
	):
		_fail("Restoring defaults did not restore mouse sensitivity (was %f)." % original)
		return


## Pressing CHƠI ĐƠN has to end in a playable House2 with a way back out of it -
## a menu that can only be left through the window is not a hub.
func _test_solo_route() -> void:
	var manager: Node = root.get_node_or_null("NetworkManager")
	manager.call("start_single_player")
	for _frame: int in 8:
		await process_frame
	var scene := root.get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://main.tscn":
		_fail("CHƠI ĐƠN did not load main.tscn (got %s)." % [
			scene.scene_file_path if scene else "nothing",
		])
		return
	if bool(manager.get("session_active")):
		_fail("Single player must not leave a network session open.")
		return

	var pause_menu := scene.get_node_or_null("PauseMenu") as CanvasLayer
	if pause_menu == null or pause_menu.visible:
		_fail("House2 has no pause menu, or it does not start hidden.")
		return
	pause_menu.call("open")
	await process_frame
	if not pause_menu.visible or not root.get_tree().paused:
		_fail("The pause menu must pause a single-player run.")
		return
	pause_menu.call("close")
	await process_frame
	if pause_menu.visible or root.get_tree().paused:
		_fail("Closing the pause menu must resume the run.")
		return


func _fail(message: String) -> void:
	push_error("Main menu smoke test failed: " + message)
	print("Main menu smoke test FAILED: " + message)
	quit(1)

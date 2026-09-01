extends SceneTree


func _initialize() -> void:
	var menu_script := load("res://network/multiplayer_menu.gd") as GDScript
	var menu := menu_script.new() as Control
	var variable_name := "ARBITRIUM_PORT_GAMEPORT_INTERNAL"
	var previous_value := OS.get_environment(variable_name)
	OS.set_environment(variable_name, "28888")
	var edgegap_port := int(menu.call("_argument_port", PackedStringArray()))
	var explicit_port := int(menu.call(
		"_argument_port",
		PackedStringArray(["--port=29999"])
	))
	if previous_value.is_empty():
		OS.unset_environment(variable_name)
	else:
		OS.set_environment(variable_name, previous_value)
	menu.free()

	if edgegap_port != 28888:
		_fail("Edgegap internal gameport was not selected.")
		return
	if explicit_port != 29999:
		_fail("Explicit --port must override the Edgegap environment.")
		return
	print("Edgegap server smoke test passed: injected and explicit UDP ports are handled.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager: Node = root.get_node_or_null("NetworkManager")
	if not manager:
		_fail("NetworkManager autoload is missing.")
		return
	if manager.GAME_SCENE != "res://house3/villa_main.tscn":
		_fail("Multiplayer must enter villa_main, got %s." % manager.GAME_SCENE)
		return
	if manager.LOBBY_SCENE != "res://network/multiplayer_lobby.tscn":
		_fail("Multiplayer waiting room target is incorrect: %s." % manager.LOBBY_SCENE)
		return
	if manager.sanitize_display_name("   ") != "Player":
		_fail("Blank player names must fall back to Player.")
		return
	if manager.sanitize_display_name("abcdefghijklmnopqrstuvwxyz").length() != 24:
		_fail("Player names must be limited to 24 characters.")
		return
	if load(manager.MENU_SCENE) == null:
		_fail("Multiplayer menu scene cannot be loaded.")
		return
	if load(manager.LOBBY_SCENE) == null:
		_fail("Multiplayer lobby scene cannot be loaded.")
		return
	if load(manager.GAME_SCENE) == null:
		_fail("Villa multiplayer scene cannot be loaded.")
		return
	print("Network session smoke test passed: menu, lobby, and Villa load; player names are sanitized.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

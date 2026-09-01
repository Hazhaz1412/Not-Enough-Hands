extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager: Node = root.get_node_or_null("NetworkManager")
	if not manager:
		_fail("NetworkManager autoload is missing.")
		return

	manager.players = {
		1: {"name": "Lan", "ready": true},
		2: {"name": "Minh", "ready": false},
		3: {"name": "An", "ready": true},
	}
	var lobby_scene := load("res://network/multiplayer_lobby.tscn") as PackedScene
	var lobby := lobby_scene.instantiate()
	root.add_child(lobby)
	await process_frame

	var lineup := lobby.get_node_or_null("%Lineup") as Node3D
	if not lineup or lineup.get_child_count() != 3:
		_fail("A three-player roster must create exactly three lobby models.")
		return

	var expected_names := ["Lan", "Minh", "An"]
	for index: int in expected_names.size():
		var visual := lineup.get_child(index).get_node_or_null("PlayerVisual") as Node3D
		var name_tag := visual.get_node_or_null("NameTag") as Label3D if visual else null
		var ready_tag := visual.get_node_or_null("ReadyTag") as Label3D if visual else null
		var animation_player := (
			visual.get_node_or_null("Character/CharacterAnimationPlayer") as AnimationPlayer
			if visual else null
		)
		if not visual or not name_tag or name_tag.text != expected_names[index]:
			_fail("Lobby model %d does not show its roster name." % index)
			return
		if not ready_tag:
			_fail("Lobby model %d does not show its ready state overhead." % index)
			return
		var expected_state := "READY" if bool(manager.players[index + 1]["ready"]) else "NOT READY"
		if ready_tag.text != expected_state or ready_tag.font_size > 20:
			_fail("Lobby model %d uses an overlapping ready label." % index)
			return
		if not animation_player or not animation_player.is_playing():
			_fail("Lobby model %d is missing its live idle animation." % index)
			return

	manager.players[4] = {"name": "Vy", "ready": false}
	lobby.call("_render_roster")
	await process_frame
	if lineup.get_child_count() != 4:
		_fail("Adding a fourth roster entry must create the fourth model immediately.")
		return

	print("Lobby visual smoke test passed: roster count, names, ready tags, and idle models update.")
	quit()


func _fail(message: String) -> void:
	push_error("Lobby visual smoke test failed: " + message)
	print("Lobby visual smoke test FAILED: " + message)
	quit(1)

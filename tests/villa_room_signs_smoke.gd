extends SceneTree


func _init() -> void:
	var villa_scene := load("res://house3/villa_main.tscn") as PackedScene
	_assert(villa_scene != null, "Could not load villa_main.tscn")
	var villa := villa_scene.instantiate()
	var room_signs := villa.get_node_or_null("RoomSigns") as VillaRoomSigns
	_assert(room_signs != null, "villa_main is missing its RoomSigns controller")

	room_signs.build_signs()
	_assert(room_signs.signs_created >= 30, "Too few Villa room signs were created")
	_assert(room_signs.signs_created == room_signs.get_child_count(), "Room sign count is inconsistent")

	var foyer_sign_found := false
	for child: Node in room_signs.get_children():
		var sign := child as RoomSign
		_assert(sign != null, "RoomSigns contains a non-RoomSign child")
		_assert(not sign.room_name.is_empty(), "A room sign has no display name")
		_assert(sign.get_meta("room_id", "") != "", "A room sign has no room ID metadata")
		if String(sign.get_meta("room_id")) == "R_FOYER":
			foyer_sign_found = true
			_assert(sign.room_name == "ĐẠI SẢNH", "Foyer sign has the wrong display name")

	_assert(foyer_sign_found, "No sign was created for R_FOYER")
	print("Villa room signs smoke test passed: %d signs created above room doors." % room_signs.signs_created)
	villa.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

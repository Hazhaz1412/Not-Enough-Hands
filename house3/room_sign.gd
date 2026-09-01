@tool
class_name RoomSign
extends Node3D


@export var room_name: String = "TÊN PHÒNG":
	set(value):
		room_name = value
		_update_labels()


func _ready() -> void:
	_update_labels()


func _update_labels() -> void:
	var pixel_size := 0.0055
	if room_name.length() > 26:
		pixel_size = 0.0034
	elif room_name.length() > 19:
		pixel_size = 0.0042

	for path: NodePath in [NodePath("FrontLabel"), NodePath("BackLabel")]:
		var label := get_node_or_null(path) as Label3D
		if not label:
			continue
		label.text = room_name
		label.pixel_size = pixel_size

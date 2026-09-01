@tool
class_name VillaRoomSigns
extends Node3D


@export_file("*.json") var spec_path := "res://house3/neh_map_spec_v2.json"
@export var room_sign_scene: PackedScene
@export var create_on_ready := true
@export_range(2.4, 3.2, 0.01) var sign_height_above_floor := 2.68

var signs_created := 0

const DISPLAY_NAMES := {
	"R_COAL": "HẦM THAN",
	"R_WINE": "HẦM RƯỢU",
	"R_BOILER": "PHÒNG MÁY",
	"R_TUNNEL": "ĐƯỜNG HẦM",
	"R_PARLOR": "PHÒNG TIẾP KHÁCH",
	"R_WC_GROUND_NORTH": "WC TẦNG TRỆT - BẮC",
	"R_FOYER": "ĐẠI SẢNH",
	"R_STUDY": "PHÒNG LÀM VIỆC",
	"R_LIVING": "PHÒNG KHÁCH",
	"R_LIBRARY": "THƯ VIỆN",
	"R_KITCHEN": "BẾP",
	"R_PANTRY": "KHO THỰC PHẨM",
	"R_GALLERY": "PHÒNG TRANH",
	"R_ATRIUM": "SÂN TRONG",
	"R_BILLIARD": "PHÒNG BI-A",
	"R_CHAPEL": "NHÀ NGUYỆN",
	"R_WC_GROUND_SOUTH": "WC TẦNG TRỆT - NAM",
	"R_DINING": "PHÒNG ĂN",
	"R_BALLROOM": "PHÒNG KHIÊU VŨ",
	"R_UTILITY": "PHÒNG PHỤ TRỢ",
	"R_BED_1": "PHÒNG NGỦ 1",
	"R_UP_HALL": "SẢNH TRÊN",
	"R_WC_UP_NORTH": "WC TẦNG 1 - BẮC",
	"R_BED_2": "PHÒNG NGỦ 2",
	"R_MASTER": "PHÒNG NGỦ CHÍNH",
	"R_NURSERY": "PHÒNG TRẺ EM",
	"R_WC_UP_SOUTH": "WC TẦNG 1 - NAM",
	"R_BED_3": "PHÒNG NGỦ 3",
	"R_BATH_MAIN": "PHÒNG TẮM CHÍNH",
	"R_STUDY_UP": "THƯ PHÒNG",
	"R_LINEN": "KHO CHĂN MÀN",
	"R_SERVANT": "PHÒNG GIA NHÂN",
	"R_STORAGE": "KHO",
	"R_GALLERY_UP": "HÀNH LANG TRANH",
	"R_SERVICE_UP": "CẦU THANG PHỤC VỤ",
	"R_ATRIUM_BALCONY": "LAN CAN GIẾNG TRỜI",
	"R_ATTIC": "GÁC MÁI",
}


func _ready() -> void:
	if create_on_ready:
		build_signs.call_deferred()


func build_signs() -> void:
	clear_signs()
	if not room_sign_scene:
		push_warning("VillaRoomSigns: room_sign_scene is not assigned")
		return
	if not FileAccess.file_exists(spec_path):
		push_warning("VillaRoomSigns: spec file not found: " + spec_path)
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	if not parsed is Dictionary:
		push_warning("VillaRoomSigns: invalid Villa spec JSON")
		return
	var data := parsed as Dictionary
	var grid := data.get("grid", {}) as Dictionary
	var cell_size := float(grid.get("cell_size", 2.0))
	var floor_height := float(grid.get("floor_height", 3.5))
	var used_doors: Dictionary = {}

	for room_value: Variant in data.get("rooms", []):
		var room := room_value as Dictionary
		if bool(room.get("void", false)):
			continue
		var room_id := String(room.get("id", ""))
		var level := int(room.get("level", 0))
		var level_id := _level_id(level)
		var display_name := String(DISPLAY_NAMES.get(room_id, room.get("name", room_id)))

		for door_value: Variant in room.get("doors", []):
			var door_cell := door_value as Array
			if door_cell.size() < 2:
				continue
			var col := int(door_cell[0])
			var row := int(door_cell[1])
			var door_key := "%d:%d:%d" % [level, col, row]
			if used_doors.has(door_key):
				continue

			var door_path := NodePath(
				"VillaHouse/Generated/Level_%s/Doors/Door_%d_%d" % [level_id, col, row]
			)
			var door := get_parent().get_node_or_null(door_path) as Node3D
			if not door:
				push_warning("VillaRoomSigns: door not found: " + String(door_path))
				continue

			var sign := room_sign_scene.instantiate() as Node3D
			sign.name = "%sSign_%d_%d" % [room_id, col, row]
			sign.set("room_name", display_name)
			sign.position = Vector3(
				col * cell_size + cell_size * 0.5,
				level * floor_height + sign_height_above_floor,
				row * cell_size + cell_size * 0.5
			)
			sign.rotation.y = door.rotation.y
			sign.set_meta("room_id", room_id)
			sign.set_meta("door_cell", Vector2i(col, row))
			add_child(sign)
			used_doors[door_key] = true
			signs_created += 1


func clear_signs() -> void:
	for child: Node in get_children():
		child.queue_free()
	signs_created = 0


func _level_id(level: int) -> String:
	if level < 0:
		return "F_B1"
	return "F_%02d" % level

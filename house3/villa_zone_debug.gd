class_name VillaZoneDebug
extends CanvasLayer

## Development controls for testing the zone layout directly in VillaMain.
## 1..0 toggle Z01..Z10, - toggles Z11, = toggles Z12, Backspace toggles Z13.
## B toggles global blackout; A turns every zone off; R restores every zone.

@export var enabled := true
@export var zones_root: NodePath = NodePath("../ElectricalZones")

var _label: Label
var _zones: Array[ElectricalZone] = []
var _manager: PowerManager


func _ready() -> void:
	if not enabled:
		return
	_manager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	var root := get_node_or_null(zones_root)
	if root:
		for child: Node in root.get_children():
			var zone := child as ElectricalZone
			if zone:
				_zones.append(zone)
				zone.power_changed.connect(_refresh)
	_label = Label.new()
	_label.position = Vector2(18, 92)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0, 0.92))
	_label.add_theme_color_override("font_outline_color", Color(0.01, 0.01, 0.02, 1.0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: Key = (event as InputEventKey).keycode
	var index := _zone_index_for_key(key)
	if index >= 0 and index < _zones.size():
		_zones[index].toggle_power()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_A:
		for zone: ElectricalZone in _zones:
			zone.set_powered(false)
		get_viewport().set_input_as_handled()
	elif key == KEY_R:
		for zone: ElectricalZone in _zones:
			zone.set_powered(true)
		get_viewport().set_input_as_handled()
	elif key == KEY_B and _manager:
		if _manager.is_blackout:
			_manager.restore_power()
		else:
			_manager.trigger_global_blackout()
		get_viewport().set_input_as_handled()
	_refresh()


func _zone_index_for_key(key: Key) -> int:
	var keys: Array[Key] = [
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7,
		KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL, KEY_BACKSPACE,
	]
	return keys.find(key)


func _refresh(_is_powered: bool = true) -> void:
	if not _label:
		return
	var lines := ["ĐIỆN VILLA — 1..0, -, =, Backspace: bật/tắt zone | A: tắt hết | R: bật hết | B: blackout"]
	for index: int in _zones.size():
		var zone := _zones[index]
		var key_name := _key_name(index)
		lines.append("%s  %s  %s" % [key_name, "ON " if zone.is_powered else "OFF", zone.display_name])
	if _manager and _manager.is_blackout:
		lines.append("GLOBAL BLACKOUT")
	elif not _zones.any(func(zone: ElectricalZone) -> bool: return zone.is_powered):
		lines.append("BLACKOUT TOÀN NHÀ — tất cả zone đang OFF")
	_label.text = "\n".join(lines)


func _key_name(index: int) -> String:
	var names := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"]
	return names[index]

extends PanelContainer

## One slot in the equipment HUD. Purely presentational - EquipmentUI tells
## it what to show; it has no reference to the player or PlayerEquipment.

const NORMAL_SIZE := Vector2(64, 64)
const SELECTED_SIZE := Vector2(112, 112)

@export var slot_index: int = 0

@onready var number_label: Label = $Content/NumberLabel
@onready var item_label: Label = $Content/ItemLabel

var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat


func _ready() -> void:
	number_label.text = str(slot_index + 1)
	_style_normal = get_theme_stylebox("panel").duplicate()
	_style_selected = _style_normal.duplicate()
	_style_selected.border_color = Color(0.85, 0.7, 0.35, 0.95)
	_style_selected.border_width_left = 2
	_style_selected.border_width_top = 2
	_style_selected.border_width_right = 2
	_style_selected.border_width_bottom = 2
	set_selected(false)
	set_item_name("")


func set_selected(selected: bool) -> void:
	custom_minimum_size = SELECTED_SIZE if selected else NORMAL_SIZE
	add_theme_stylebox_override("panel", _style_selected if selected else _style_normal)


## `item_display_name` empty means the slot is unoccupied. No item icon
## system exists yet, so the item's initial stands in as a placeholder.
func set_item_name(item_display_name: String) -> void:
	item_label.text = item_display_name.left(1).to_upper() if item_display_name != "" else ""

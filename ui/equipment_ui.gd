extends HBoxContainer

## Bottom-left 2-slot equipment HUD. Mirrors ui/interaction_prompt.gd's
## player_path convention but reacts to PlayerEquipment's signals instead of
## polling, so slot/selection changes show up immediately.

@export var player_path: NodePath

var _equipment: PlayerEquipment
var _slots: Array = [null, null]


func _ready() -> void:
	# Indexed by each child's own slot_index, not by child/visual order - the
	# HUD may display Slot 2 to the left of Slot 1.
	for child in get_children():
		if child.has_method("set_selected") and "slot_index" in child:
			_slots[child.slot_index] = child
	# Player is our ancestor, so its _ready() (and the @onready `equipment`
	# it assigns) runs *after* ours - defer the bind until the tree has
	# settled instead of reading it here.
	call_deferred("_bind_to_player")


func _bind_to_player() -> void:
	var player := get_node_or_null(player_path)
	if not player or not ("equipment" in player):
		return
	_equipment = player.equipment
	if not _equipment:
		return

	_equipment.slot_changed.connect(_on_slot_changed)
	_equipment.selection_changed.connect(_on_selection_changed)
	for i in _slots.size():
		_on_slot_changed(i)
	_on_selection_changed(_equipment.selected_slot)


func _on_slot_changed(index: int) -> void:
	var item: Node = _equipment.get_slot_item(index)
	var item_display_name := ""
	if item:
		item_display_name = item.display_name if "display_name" in item else item.name
	_slots[index].set_item_name(item_display_name)


func _on_selection_changed(selected_index: int) -> void:
	for i in _slots.size():
		_slots[i].set_selected(i == selected_index)

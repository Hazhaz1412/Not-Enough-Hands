class_name PlayerEquipment
extends Node

## Reusable 2-slot equipment inventory owned by the player. Knows nothing
## about any specific item type or the world - Player itself performs the
## actual pickup/drop scene-tree work (reparenting, positioning); this
## component only tracks which slot holds what and which slot is selected.

const SLOT_COUNT := 2

signal slot_changed(slot_index: int)
signal selection_changed(slot_index: int)

var slots: Array = [null, null]
var selected_slot: int = 0


func select_slot(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT or index == selected_slot:
		return
	selected_slot = index
	selection_changed.emit(selected_slot)


## Fills the first empty slot with `item` and returns true, or returns false
## without touching any slot if both are already occupied.
func try_add_item(item: Node) -> bool:
	for i in SLOT_COUNT:
		if slots[i] == null:
			slots[i] = item
			slot_changed.emit(i)
			return true
	return false


func get_slot_item(index: int) -> Node:
	return slots[index]


func is_slot_empty(index: int) -> bool:
	return slots[index] == null


## Clears the selected slot and returns whatever item was in it (null if it
## was already empty).
func remove_selected() -> Node:
	var item: Node = slots[selected_slot]
	if item == null:
		return null
	slots[selected_slot] = null
	slot_changed.emit(selected_slot)
	return item

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


## How many of the two slots `item` takes up while carried. Anything that does
## not declare a `slot_cost` is a normal one-handed pickup; a ritual totem
## declares 2 and so needs both hands free.
static func get_item_slot_cost(item: Node) -> int:
	if item and "slot_cost" in item:
		return clampi(int(item.get("slot_cost")), 1, SLOT_COUNT)
	return 1


## Fills the slots `item` needs and returns true, or returns false without
## touching any slot if there is not that much room. A two-handed item needs
## both slots empty, not just one.
func try_add_item(item: Node) -> bool:
	if get_item_slot_cost(item) >= SLOT_COUNT:
		for i in SLOT_COUNT:
			if slots[i] != null:
				return false
		for i in SLOT_COUNT:
			slots[i] = item
			slot_changed.emit(i)
		return true
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
## was already empty). A two-handed item is released from both slots at once.
func remove_selected() -> Node:
	var item: Node = slots[selected_slot]
	if item == null:
		return null
	remove_item(item)
	return item


## Clears every slot holding `item`. Returns false if it was not being carried.
func remove_item(item: Node) -> bool:
	var removed := false
	for i in SLOT_COUNT:
		if item != null and slots[i] == item:
			slots[i] = null
			slot_changed.emit(i)
			removed = true
	return removed

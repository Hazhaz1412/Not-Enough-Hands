class_name InventoryComponent
extends Node

signal item_added(item_data: ItemData, amount: int)
signal item_removed(item_data: ItemData, amount: int)
signal inventory_changed

# Maps ItemData (or item ID) to amount. Let's use ItemData reference directly for simplicity,
# but we can also use dictionary keyed by item_data.id if needed.
# For this foundation, using the ItemData reference itself is fine.
var items: Dictionary = {}

func add_item(item_data: ItemData, amount: int) -> int:
	if amount <= 0 or not item_data:
		return 0
		
	if item_data.max_stack <= 0:
		push_error("ItemData max_stack is invalid (0 or negative) for: " + item_data.id)
		return 0
		
	var current_amount = items.get(item_data, 0)
	var available_space = item_data.max_stack - current_amount
	
	if available_space <= 0:
		return 0
		
	var amount_to_add = min(amount, available_space)
	
	items[item_data] = current_amount + amount_to_add
	
	item_added.emit(item_data, amount_to_add)
	inventory_changed.emit()
	
	return amount_to_add

func remove_item(item_data: ItemData, amount: int) -> int:
	if amount <= 0 or not item_data:
		return 0
		
	if not items.has(item_data):
		return 0
		
	var current_amount = items[item_data]
	var amount_to_remove = min(amount, current_amount)
	
	items[item_data] = current_amount - amount_to_remove
	
	if items[item_data] <= 0:
		items.erase(item_data)
		
	item_removed.emit(item_data, amount_to_remove)
	inventory_changed.emit()
	
	return amount_to_remove

func has_item(item_data: ItemData, min_amount: int = 1) -> bool:
	return items.get(item_data, 0) >= min_amount

func get_item_count(item_data: ItemData) -> int:
	return items.get(item_data, 0)

func clear() -> void:
	if items.is_empty():
		return
	items.clear()
	inventory_changed.emit()

class_name CarrySlotsComponent
extends Node

signal slots_changed
signal selected_slot_changed(slot_index: int)
signal item_dropped(item_data: ItemData, slot_index: int)

@export var max_slots: int = 2
var slots: Array[ItemData] = []
var selected_slot_index: int = 0

func _ready() -> void:
	slots.resize(max_slots)
	slots.fill(null)

func add_item(item_data: ItemData) -> bool:
	for i in range(max_slots):
		if slots[i] == null:
			slots[i] = item_data
			slots_changed.emit()
			
			# If everything was empty previously, select this newly filled slot
			var other_empty = true
			for j in range(max_slots):
				if i != j and slots[j] != null:
					other_empty = false
					break
			if other_empty:
				select_slot(i)
				
			return true
	return false

func remove_item(slot_index: int) -> ItemData:
	if slot_index < 0 or slot_index >= max_slots: return null
	var item = slots[slot_index]
	slots[slot_index] = null
	slots_changed.emit()
	return item

func get_item(slot_index: int) -> ItemData:
	if slot_index < 0 or slot_index >= max_slots: return null
	return slots[slot_index]

func get_slot_item(slot_index: int) -> ItemData:
	return get_item(slot_index)

func has_empty_slot() -> bool:
	for item in slots:
		if item == null: return true
	return false

func swap_slots(a: int, b: int) -> void:
	if a < 0 or a >= max_slots or b < 0 or b >= max_slots: return
	var temp = slots[a]
	slots[a] = slots[b]
	slots[b] = temp
	slots_changed.emit()

func clear_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= max_slots: return
	slots[slot_index] = null
	slots_changed.emit()

func select_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= max_slots: return
	selected_slot_index = slot_index
	selected_slot_changed.emit(selected_slot_index)

func get_selected_slot() -> int:
	return selected_slot_index

func get_selected_item() -> ItemData:
	return get_item(selected_slot_index)

func next_slot() -> void:
	var next_idx = (selected_slot_index + 1) % max_slots
	select_slot(next_idx)

func previous_slot() -> void:
	var prev_idx = selected_slot_index - 1
	if prev_idx < 0:
		prev_idx = max_slots - 1
	select_slot(prev_idx)

func drop_selected() -> void:
	var item = get_selected_item()
	if not item: return
	
	_spawn_world_item(item, 1)
	clear_slot(selected_slot_index)
	item_dropped.emit(item, selected_slot_index)
	
	# Automatically select the other occupied slot if it exists
	for i in range(max_slots):
		if slots[i] != null:
			select_slot(i)
			break

func _spawn_world_item(item_data: ItemData, amount: int) -> void:
	var pickup_scene = load("res://objects/item_pickup/item_pickup.tscn") as PackedScene
	if not pickup_scene: return
	
	var pickup = pickup_scene.instantiate()
	pickup.set("item_data", item_data)
	pickup.set("amount", amount)
	
	var player = get_parent() as Node3D
	# Place slightly in front of player
	var forward = -player.global_transform.basis.z.normalized()
	var spawn_pos = player.global_position + forward * 1.5 + Vector3(0, 1.0, 0)
	
	# Add to current scene tree root BEFORE setting global_position
	player.get_tree().current_scene.add_child(pickup)
	
	pickup.global_position = spawn_pos
	
	if pickup is RigidBody3D:
		pickup.apply_central_impulse(forward * 2.0)

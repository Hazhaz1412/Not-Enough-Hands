extends RigidBody3D
class_name ItemPickup

@export var item_data: ItemData
@export var amount: int = 1

@onready var interactable: Interactable3D = $Interactable3D

signal pickup_failed(reason: String)

func _ready() -> void:
	interactable.interacted.connect(_on_interact)
	_update_prompt()

func _update_prompt() -> void:
	if not item_data:
		interactable.set_prompt("Nhặt vật phẩm (Error: No Data)")
		return
		
	var display_text = item_data.display_name
	if amount > 1:
		display_text += " (x" + str(amount) + ")"
		
	interactable.set_prompt("Nhặt " + display_text)

func _on_interact(player: Node3D) -> void:
	interactable.lock_interaction()
	
	if not item_data:
		pickup_failed.emit("Missing ItemData")
		interactable.unlock_interaction()
		return
		
	var carry_slots = player.get_node_or_null("CarrySlotsComponent") as CarrySlotsComponent
	if not carry_slots:
		pickup_failed.emit("Player has no carry slots")
		interactable.unlock_interaction()
		return
		
	if carry_slots.add_item(item_data):
		amount -= 1
		if amount <= 0:
			# Fully picked up
			$CollisionShape3D.set_deferred("disabled", true)
			interactable.is_interactable = false
			queue_free()
		else:
			# Partially picked up
			_update_prompt()
			interactable.unlock_interaction()
	else:
		# Inventory full for this item
		pickup_failed.emit("Túi đồ đã đầy!")
		print("Inventory full! Cannot pick up ", item_data.display_name)
		interactable.unlock_interaction()

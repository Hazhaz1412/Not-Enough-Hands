class_name PickupItem
extends RigidBody3D

## Generic pickup-capable item. Reusable for any future item - it carries
## only a display name and relies entirely on the existing Interactable
## component for detection/interaction. The player never knows this is an
## "item"; it only knows the interacted signal's target had this method.
##
## A RigidBody3D rather than a StaticBody3D so a dropped item can actually
## fall and settle under gravity. It starts frozen (see the scene) so an
## undisturbed world item sits still like the old StaticBody3D did; freeze
## is only lifted for the ground-truth "loose in the world" state.

@export var display_name: String = "Item"

@onready var interactable: Interactable = $Interactable
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(player: Node) -> void:
	if player.has_method("try_pick_up_item"):
		player.try_pick_up_item(self)


## Applied by the player's equipment system on pickup/drop: hidden,
## non-colliding and frozen while carried; a normal falling physics object
## when dropped. The Interactable itself is disabled while held so it can't
## be targeted or interacted with mid-carry.
func set_held(held: bool) -> void:
	visible = not held
	collision_shape.disabled = held
	freeze = held
	if held:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	interactable.enabled = not held

extends StaticBody3D

## Generic Interactable double used only by tests. Deliberately knows nothing
## about switches/doors/etc - it exists to prove the reusable component drives
## arbitrary object behavior (a counter here) without the player or the
## component itself knowing what kind of object it is attached to.

@onready var interactable: Interactable = $Interactable

var interaction_count: int = 0
var last_player: Node = null


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(player: Node) -> void:
	interaction_count += 1
	last_player = player
	# Mirrors LightSwitch's own pattern: the owning object locks itself, the
	# component just enforces whatever lock state it is told to hold.
	interactable.lock()

class_name Interactable
extends Node

## Reusable interaction contract for the player's existing raycast + `interact`
## (E) input. Attach as a child node named "Interactable" under any object;
## that object's own script connects to `interacted` and drives lock()/
## unlock() itself - this component has no gameplay knowledge of what it is
## attached to.

signal interacted(player: Node)

@export var enabled: bool = true
@export var interaction_range: float = 2.5
@export var prompt_text: String = "TƯƠNG TÁC"

var _locked: bool = false


func can_interact() -> bool:
	return enabled and not _locked


## The enforcement point for the lock: re-checked here so a locked
## interactable cannot emit twice no matter who calls this, not only when
## gated upstream by Player.can_interact_with().
func interact(player: Node) -> void:
	if not can_interact():
		return
	interacted.emit(player)


func lock() -> void:
	_locked = true


func unlock() -> void:
	_locked = false


func get_interaction_prompt(key_name: String) -> String:
	return "[center][b]" + key_name + "[/b]  " + prompt_text + "[/center]"

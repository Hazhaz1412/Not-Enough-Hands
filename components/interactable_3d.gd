class_name Interactable3D
extends Node3D

signal interacted(player: Node3D)
signal prompt_updated(new_prompt: String)

@export var interaction_range: float = 2.5
@export var interaction_prompt: String = "Interact"

var is_interactable: bool = true
var locked: bool = false
var _current_dynamic_prompt: String = ""

func _ready() -> void:
	_current_dynamic_prompt = interaction_prompt

func can_interact(_player: Node3D) -> bool:
	return is_interactable and not locked

func interact(player: Node3D) -> void:
	if not can_interact(player):
		return
	interacted.emit(player)

func lock_interaction() -> void:
	locked = true

func unlock_interaction() -> void:
	locked = false

func get_prompt() -> String:
	return _current_dynamic_prompt

func set_prompt(new_prompt: String) -> void:
	_current_dynamic_prompt = new_prompt
	prompt_updated.emit(new_prompt)

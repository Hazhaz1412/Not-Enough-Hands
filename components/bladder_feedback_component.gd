class_name BladderFeedbackComponent
extends Node

@export var bladder_component: BladderComponent

func _ready() -> void:
	if not bladder_component:
		bladder_component = get_parent().get_node_or_null("BladderComponent")
		
	if bladder_component:
		bladder_component.threshold_changed.connect(_on_threshold_changed)
		bladder_component.max_reached.connect(_on_max_reached)

func _on_threshold_changed(old_state: int, new_state: int) -> void:
	match new_state:
		BladderComponent.ThresholdState.NORMAL:
			print("[BladderFeedback] Status: NORMAL")
		BladderComponent.ThresholdState.WARNING:
			print("[BladderFeedback] Status: WARNING - The player feels the need to go.")
		BladderComponent.ThresholdState.CRITICAL:
			print("[BladderFeedback] Status: CRITICAL - The player is struggling to hold it!")
		BladderComponent.ThresholdState.FULL:
			print("[BladderFeedback] Status: FULL - The player can't hold it anymore!")

func _on_max_reached() -> void:
	print("[BladderFeedback] EVENT: Bladder reached maximum capacity!")

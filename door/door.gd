extends Node3D

enum DoorState { CLOSED, OPENING, OPEN, CLOSING }
var state: DoorState = DoorState.CLOSED

@export var open_angle: float = 90.0 # Degrees
@export var open_duration: float = 0.5
@export var close_duration: float = 0.5
@export var hinge_direction: int = 1

@onready var hinge: AnimatableBody3D = $Hinge
@onready var interactable: Interactable3D = $Hinge/Interactable3D
var tween: Tween

func _ready() -> void:
	interactable.interacted.connect(_on_interact)
	interactable.set_prompt("Mở cửa")

func _on_interact(player: Node3D) -> void:
	if state == DoorState.OPENING or state == DoorState.CLOSING:
		return
		
	if state == DoorState.CLOSED:
		state = DoorState.OPENING
		interactable.lock_interaction()
		interactable.set_prompt("Đang mở...")
		
		# Determine player side relative to door's local Z-axis (FORWARD)
		var local_player_pos = to_local(player.global_position)
		# local_player_pos.z > 0 means the player is in front of the door's original Z axis.
		var dot = local_player_pos.z
		
		# If dot < 0 (player is behind), open towards +Z (target_sign = -1)
		# If dot > 0 (player is in front), open towards -Z (target_sign = 1)
		var target_sign = -1 if dot < 0 else 1
		var target_rot_y = deg_to_rad(open_angle) * target_sign * hinge_direction
		
		if tween and tween.is_running(): tween.kill()
		tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(hinge, "rotation:y", target_rot_y, open_duration)
		tween.tween_callback(func():
			state = DoorState.OPEN
			interactable.unlock_interaction()
			interactable.set_prompt("Đóng cửa")
		)
		
	elif state == DoorState.OPEN:
		state = DoorState.CLOSING
		interactable.lock_interaction()
		interactable.set_prompt("Đang đóng...")
		
		if tween and tween.is_running(): tween.kill()
		tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(hinge, "rotation:y", 0.0, close_duration)
		tween.tween_callback(func():
			state = DoorState.CLOSED
			interactable.unlock_interaction()
			interactable.set_prompt("Mở cửa")
		)

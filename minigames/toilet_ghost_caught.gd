class_name ToiletGhostCaught
extends CanvasLayer

## Brief 3D "you got caught" beat shown above the existing death flow. The
## transparent SubViewport renders the real Toilet Ghost model rather than a
## flat screen-space photo. It still owns no death/gameplay logic.

signal sequence_finished

const CAUGHT_ANIMATION := &"caught"

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var audio: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	if audio.stream:
		audio.play()
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.play(CAUGHT_ANIMATION)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != CAUGHT_ANIMATION:
		return
	sequence_finished.emit()
	queue_free()

extends StaticBody3D

@export var lock_duration: float = 0.3

@onready var light: OmniLight3D = $Light
@onready var interactable: Interactable = $Interactable

var _unlock_timer: Timer


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	_unlock_timer = Timer.new()
	_unlock_timer.one_shot = true
	_unlock_timer.wait_time = lock_duration
	_unlock_timer.timeout.connect(interactable.unlock)
	add_child(_unlock_timer)
	_update_prompt()


func _on_interacted(_player: Node) -> void:
	interactable.lock()
	light.visible = not light.visible
	_update_prompt()
	_unlock_timer.start()


func _update_prompt() -> void:
	interactable.prompt_text = "TẮT ĐÈN" if light.visible else "BẬT ĐÈN"

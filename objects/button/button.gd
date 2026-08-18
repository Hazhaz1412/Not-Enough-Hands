extends StaticBody3D

@onready var interactable: Interactable3D = $Interactable3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
var timer: Timer

signal pressed

func _ready() -> void:
	interactable.interacted.connect(_on_interact)
	interactable.set_prompt("Nhấn nút")
	
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_timeout)
	add_child(timer)

func _on_interact(_player: Node3D) -> void:
	interactable.lock_interaction()
	interactable.set_prompt("Đang xử lý...")
	
	# Visual change
	mesh.position.y -= 0.05
	
	pressed.emit()
	timer.start(0.5)

func _on_timeout() -> void:
	# Revert visual change
	mesh.position.y += 0.05
	
	interactable.unlock_interaction()
	interactable.set_prompt("Nhấn nút")

extends StaticBody3D

@onready var interactable: Interactable3D = $Interactable3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
var is_on: bool = false
var timer: Timer

signal state_changed(is_on: bool)

func _ready() -> void:
	interactable.interacted.connect(_on_interact)
	interactable.set_prompt("Bật đèn")
	
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_timeout)
	add_child(timer)
	
	_update_visuals()

func _on_interact(_player: Node3D) -> void:
	interactable.lock_interaction()
	interactable.set_prompt("Đang xử lý...")
	timer.start(0.5)
	
func _on_timeout() -> void:
	is_on = not is_on
	state_changed.emit(is_on)
	_update_visuals()
	
	interactable.unlock_interaction()
	if is_on:
		interactable.set_prompt("Tắt đèn")
	else:
		interactable.set_prompt("Bật đèn")
		
func _update_visuals() -> void:
	var mat = StandardMaterial3D.new()
	if is_on:
		mat.albedo_color = Color(0.0, 1.0, 0.0) # Green
	else:
		mat.albedo_color = Color(1.0, 0.0, 0.0) # Red
	mesh.set_surface_override_material(0, mat)

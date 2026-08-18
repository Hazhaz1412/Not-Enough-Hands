extends StaticBody3D

@onready var interactable: Interactable3D = $Interactable3D
@onready var minigame = $ToiletMinigame

var is_occupied: bool = false
signal session_started(player: Node3D)

func _ready() -> void:
	interactable.interacted.connect(_on_interact)
	interactable.set_prompt("Sử dụng bồn cầu")
	
	minigame.session_ended.connect(_on_minigame_ended)
	
func _on_interact(player: Node3D) -> void:
	if is_occupied: return
	
	is_occupied = true
	interactable.lock_interaction()
	interactable.set_prompt("Đang bận...")
	session_started.emit(player)
	
	# Start minigame session
	var viewpoint = $MinigameViewPoint as Marker3D
	minigame.start_session(player, viewpoint)

func _on_minigame_ended(success: bool) -> void:
	is_occupied = false
	interactable.unlock_interaction()
	interactable.set_prompt("Sử dụng bồn cầu")
	
	if success and minigame.player:
		var bladder = minigame.player.get_node_or_null("BladderComponent")
		if bladder:
			bladder.reset()


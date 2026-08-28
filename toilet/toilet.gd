class_name Toilet
extends StaticBody3D

## Invisible interaction hitbox placed over the decorative Toilet.fbx mesh
## (house2.gd), giving it the shared Interactable component plus a
## one-session-at-a-time gate. All minigame/bladder logic lives in
## ToiletMinigame (owned per-player); this script only owns the occupancy
## gate so spamming interact - or a second player - can't start a second
## session while one is running.

const PROMPT_AVAILABLE := "DÙNG BỒN CẦU"
const PROMPT_OCCUPIED := "ĐANG BẬN..."

@onready var interactable: Interactable = $Interactable

var _active_player: Node = null


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(player: Node) -> void:
	if _active_player != null:
		return
	if not player.has_method("start_toilet_minigame"):
		return
	if not player.call("start_toilet_minigame", self):
		return
	_active_player = player
	interactable.lock()
	interactable.prompt_text = PROMPT_OCCUPIED


## Called by ToiletMinigame once its session ends, on both success and
## cancel - the toilet becomes available again either way.
func end_session() -> void:
	_active_player = null
	interactable.unlock()
	interactable.prompt_text = PROMPT_AVAILABLE

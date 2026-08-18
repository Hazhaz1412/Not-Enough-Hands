extends CenterContainer

@export var player_path: NodePath
var player: CharacterBody3D
@onready var label: RichTextLabel = $RichTextLabel

var interact_key_name: String = "E"
var last_text: String = ""
var current_interactable: Interactable3D = null

func _ready() -> void:
	if not player_path.is_empty():
		player = get_node(player_path)
		if player and player.has_signal("interact_target_changed"):
			player.interact_target_changed.connect(_on_interact_target_changed)
			
	var events = InputMap.action_get_events("interact")
	if events.size() > 0:
		var ev = events[0]
		if ev is InputEventKey:
			interact_key_name = OS.get_keycode_string(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)
			if interact_key_name.is_empty():
				interact_key_name = ev.as_text().get_slice(" ", 0)
				
	visible = false

func _set_prompt_text(new_text: String) -> void:
	var final_text = "[center]" + interact_key_name + " - " + new_text + "[/center]"
	if last_text != final_text:
		last_text = final_text
		label.text = final_text

func _on_interact_target_changed(interactable: Interactable3D) -> void:
	if current_interactable:
		if current_interactable.prompt_updated.is_connected(_on_prompt_updated):
			current_interactable.prompt_updated.disconnect(_on_prompt_updated)
			
	current_interactable = interactable
	
	if current_interactable:
		current_interactable.prompt_updated.connect(_on_prompt_updated)
		_update_prompt_display()
	else:
		visible = false

func _on_prompt_updated(_new_prompt: String) -> void:
	_update_prompt_display()
	
func _update_prompt_display() -> void:
	if not current_interactable: return
	
	var text = current_interactable.get_prompt()
	if text.is_empty():
		visible = false
	else:
		visible = true
		_set_prompt_text(text)

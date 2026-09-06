extends CanvasLayer

## ESC, in either map. Without it the main menu would be a one-way door: a run
## could only be left by closing the window.
##
## The tree is paused in single player only. In a session the world belongs to
## the server and cannot stop for one person, so there this is just a screen
## over a night that keeps running - the same split `player/player.gd` already
## makes before pausing for a death.

const MINIGAME_CHECKS: Array[StringName] = [
	&"is_door_minigame_active",
	&"is_toilet_minigame_active",
	&"is_breaker_minigame_active",
]

@onready var state_label: Label = %StateLabel
@onready var resume_button: Button = %ResumeButton
@onready var settings_button: Button = %SettingsButton
@onready var menu_button: Button = %MenuButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: Control = %SettingsMenu

## Only the pause this menu caused is its to undo: a death screen pauses the
## tree too, and resuming out of one would hand the player back a night they
## already lost.
var _paused_here: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.pressed.connect(close)
	settings_button.pressed.connect(settings_menu.open)
	menu_button.pressed.connect(_on_menu_pressed)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	settings_menu.closed.connect(func() -> void: settings_button.grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		get_viewport().set_input_as_handled()
		close()
		return
	# A minigame owns the camera and answers ESC itself. This node sits later in
	# the map scene than the player, so it would otherwise take that press first.
	if _minigame_active():
		return
	get_viewport().set_input_as_handled()
	open()


func open() -> void:
	visible = true
	var networked := _is_network_session()
	if not networked and not get_tree().paused:
		get_tree().paused = true
		_paused_here = true
	state_label.text = (
		"Ván chơi mạng vẫn đang chạy - ma không chờ bạn đâu."
		if networked
		else "Đã dừng. Ngôi nhà đứng yên chờ bạn."
	)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	resume_button.grab_focus()


func close() -> void:
	settings_menu.visible = false
	visible = false
	if _paused_here:
		get_tree().paused = false
		_paused_here = false
	# A tree still paused after this closed is somebody else's screen - the death
	# card - and it wants a cursor. Only a run that is actually resuming gets the
	# mouse taken back.
	if DisplayServer.get_name() != "headless" and not get_tree().paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_menu_pressed() -> void:
	visible = false
	_paused_here = false
	NetworkManager.return_to_main_menu()


func _minigame_active() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if not node.has_method(&"is_local_player") or not bool(node.call(&"is_local_player")):
			continue
		for check: StringName in MINIGAME_CHECKS:
			if node.has_method(check) and bool(node.call(check)):
				return true
	return false


func _is_network_session() -> bool:
	var manager := get_node_or_null("/root/NetworkManager")
	return manager != null and bool(manager.get("session_active"))

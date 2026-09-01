extends Control

const PLAYER_VISUAL_SCENE: PackedScene = preload("res://player/player_visual.tscn")
const PLAYER_SKINS: Array[Texture2D] = [
	preload("res://assets/player/Skins/criminalMaleA.png"),
	preload("res://assets/player/Skins/skaterFemaleA.png"),
	preload("res://assets/player/Skins/cyborgFemaleA.png"),
	preload("res://assets/player/Skins/skaterMaleA.png"),
]

@onready var lineup: Node3D = %Lineup
@onready var lineup_camera: Camera3D = %LineupCamera
@onready var room_label: Label = %RoomLabel
@onready var ready_count_label: Label = %ReadyCountLabel
@onready var empty_slots_label: Label = %EmptySlotsLabel
@onready var hint_label: Label = %HintLabel
@onready var status_label: Label = %StatusLabel
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton

var _auto_start_player_count: int = 0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.status_changed.connect(_on_status_changed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	lineup_camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	_parse_automation_arguments()
	_render_roster()
	if _should_auto_ready():
		NetworkManager.set_local_ready.call_deferred(true)


func _on_roster_changed(_players: Dictionary) -> void:
	_render_roster()
	_maybe_auto_start.call_deferred()


func _on_status_changed(message: String) -> void:
	status_label.text = message


func _on_ready_pressed() -> void:
	var local_peer_id := multiplayer.get_unique_id()
	NetworkManager.set_local_ready(not NetworkManager.is_player_ready(local_peer_id))


func _on_start_pressed() -> void:
	NetworkManager.request_start_game()


func _on_leave_pressed() -> void:
	NetworkManager.leave_session(true)


func _render_roster() -> void:
	for old_avatar: Node in lineup.get_children():
		lineup.remove_child(old_avatar)
		old_avatar.queue_free()

	var peer_ids: Array = NetworkManager.players.keys()
	peer_ids.sort()
	var positions := _lineup_positions(peer_ids.size())
	for slot_index: int in peer_ids.size():
		var peer_id := int(peer_ids[slot_index])
		_add_lobby_avatar(
			slot_index,
			NetworkManager.get_player_name(peer_id),
			NetworkManager.is_player_ready(peer_id),
			positions[slot_index]
		)

	var ready_count := 0
	for peer_id: int in NetworkManager.players:
		if NetworkManager.is_player_ready(peer_id):
			ready_count += 1
	ready_count_label.text = "%d/%d ĐÃ SẴN SÀNG" % [ready_count, NetworkManager.players.size()]
	room_label.text = "UDP %d  ·  %d/%d NGƯỜI" % [
		NetworkManager.session_port,
		NetworkManager.players.size(),
		NetworkManager.MAX_PLAYERS,
	]
	var empty_slots := maxi(NetworkManager.MAX_PLAYERS - NetworkManager.players.size(), 0)
	empty_slots_label.text = (
		"PHÒNG ĐÃ ĐẦY" if empty_slots == 0 else "CÒN %d CHỖ TRỐNG" % empty_slots
	)

	var local_peer_id := multiplayer.get_unique_id()
	var local_ready := NetworkManager.is_player_ready(local_peer_id)
	ready_button.text = "HỦY SẴN SÀNG" if local_ready else "SẴN SÀNG"
	start_button.visible = NetworkManager.is_local_lobby_host()
	start_button.disabled = not NetworkManager.can_start_game()
	if NetworkManager.is_local_lobby_host():
		hint_label.text = (
			"Tất cả người chơi đã sẵn sàng. Bạn có thể bắt đầu."
			if NetworkManager.can_start_game()
			else "Chờ mọi người bấm SẴN SÀNG."
		)
	else:
		hint_label.text = "Đang chờ chủ phòng bắt đầu trận đấu."


func _add_lobby_avatar(
	slot_index: int,
	player_name: String,
	is_ready: bool,
	lineup_position: Vector3
) -> void:
	# PlayerVisual aligns itself around a gameplay capsule centre. This anchor
	# raises that centre so the preview model's feet land on the lobby floor.
	var anchor := Node3D.new()
	anchor.name = "LobbyPlayer%d" % (slot_index + 1)
	anchor.position = lineup_position + Vector3.UP * 0.875
	lineup.add_child(anchor)

	var visual := PLAYER_VISUAL_SCENE.instantiate()
	visual.call(
		"configure_lobby_preview",
		player_name,
		PLAYER_SKINS[slot_index % PLAYER_SKINS.size()],
		is_ready,
		slot_index
	)
	anchor.add_child(visual)


func _lineup_positions(player_count: int) -> Array[Vector3]:
	match player_count:
		1:
			return [Vector3.ZERO]
		2:
			return [Vector3(-1.05, 0.0, 0.0), Vector3(1.05, 0.0, 0.0)]
		3:
			return [
				Vector3(-1.65, 0.0, 0.08),
				Vector3(0.0, 0.0, -0.08),
				Vector3(1.65, 0.0, 0.08),
			]
		4:
			return [
				Vector3(-2.25, 0.0, 0.16),
				Vector3(-0.75, 0.0, -0.08),
				Vector3(0.75, 0.0, -0.08),
				Vector3(2.25, 0.0, 0.16),
			]
	return []


func _parse_automation_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--lobby-auto-start="):
			var value := argument.trim_prefix("--lobby-auto-start=")
			if value.is_valid_int():
				_auto_start_player_count = maxi(int(value), 1)


func _should_auto_ready() -> bool:
	var args := OS.get_cmdline_user_args()
	return (
		"--network-smoke" in args
		or "--lobby-auto-ready" in args
		or _auto_start_player_count > 0
	)


func _maybe_auto_start() -> void:
	if (
		_auto_start_player_count > 0
		and NetworkManager.is_local_lobby_host()
		and NetworkManager.players.size() >= _auto_start_player_count
		and NetworkManager.can_start_game()
	):
		NetworkManager.request_start_game()

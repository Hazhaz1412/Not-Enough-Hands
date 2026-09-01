extends Node

signal status_changed(message: String)
signal roster_changed(players: Dictionary)
signal game_starting()
signal player_spawn_requested(peer_id: int, display_name: String, spawn_index: int)
signal player_world_ready(peer_id: int)
signal player_replication_ready(peer_id: int)
signal player_left(peer_id: int)
signal run_ended(reason: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const SERVER_PEER_ID := 1
const GAME_SCENE := "res://house3/villa_main.tscn"
const LOBBY_SCENE := "res://network/multiplayer_lobby.tscn"
const MENU_SCENE := "res://network/multiplayer_menu.tscn"

var session_active: bool = false
var dedicated_server: bool = false
var game_started: bool = false
var lobby_host_peer_id: int = SERVER_PEER_ID
var session_port: int = DEFAULT_PORT
var local_display_name: String = "Player"
var players: Dictionary = {}
var world_ready_peers: Dictionary = {}
var replication_ready_peers: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(display_name: String, port: int = DEFAULT_PORT) -> Error:
	_reset_session_state()
	local_display_name = sanitize_display_name(display_name)
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		status_changed.emit("Không thể mở server UDP %d (lỗi %d)." % [port, result])
		return result
	multiplayer.multiplayer_peer = peer
	session_active = true
	dedicated_server = false
	game_started = false
	lobby_host_peer_id = SERVER_PEER_ID
	session_port = port
	players[SERVER_PEER_ID] = {"name": local_display_name, "ready": false}
	status_changed.emit("Đã tạo server local tại cổng UDP %d." % port)
	roster_changed.emit(players.duplicate(true))
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)
	return OK


func start_dedicated_server(port: int = DEFAULT_PORT) -> Error:
	_reset_session_state()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, MAX_PLAYERS)
	if result != OK:
		status_changed.emit("Dedicated server không mở được UDP %d (lỗi %d)." % [port, result])
		return result
	multiplayer.multiplayer_peer = peer
	session_active = true
	dedicated_server = true
	game_started = false
	lobby_host_peer_id = 0
	session_port = port
	status_changed.emit("Dedicated server đang nghe UDP %d." % port)
	print("NETWORK_SERVER_READY port=%d max_players=%d" % [port, MAX_PLAYERS])
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)
	return OK


func join_game(address: String, display_name: String, port: int = DEFAULT_PORT) -> Error:
	_reset_session_state()
	local_display_name = sanitize_display_name(display_name)
	var resolved_address := address.strip_edges()
	if resolved_address.is_empty():
		resolved_address = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(resolved_address, port)
	if result != OK:
		status_changed.emit("Không thể kết nối %s:%d (lỗi %d)." % [resolved_address, port, result])
		return result
	multiplayer.multiplayer_peer = peer
	session_active = true
	dedicated_server = false
	game_started = false
	session_port = port
	status_changed.emit("Đang kết nối %s:%d…" % [resolved_address, port])
	return OK


func leave_session(return_to_menu: bool = true) -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_session_state()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if return_to_menu and get_tree().current_scene:
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func notify_world_ready() -> void:
	if not session_active:
		return
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		if dedicated_server:
			# A headless dedicated process owns peer 1 but is not itself a player.
			return
		_mark_world_ready(peer_id)
	else:
		_notify_world_ready.rpc_id(SERVER_PEER_ID)


func notify_replication_ready() -> void:
	if not session_active:
		return
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_mark_replication_ready(peer_id)
	else:
		_notify_replication_ready.rpc_id(SERVER_PEER_ID)


func is_server() -> bool:
	return session_active and multiplayer.is_server()


## The one way out of a night, whichever way it went: everybody dead, dawn
## reached, or the last person leaving. Puts the whole room back in the lobby
## with every ready flag cleared, so the same group can simply ready up again.
##
## Server-only and idempotent - "everyone is out" can be noticed by more than
## one thing in the same frame, and `game_started` is what makes the second call
## a no-op.
##
## Clearing `game_started` is also what reopens the door: `_register_player()`
## turns away anyone who knocks during a run, so without this a finished session
## stayed locked to newcomers *and* to the people who had just been in it.
func end_run(reason: String) -> void:
	if not session_active or not multiplayer.is_server() or not game_started:
		return
	world_ready_peers.clear()
	replication_ready_peers.clear()
	for peer_id: int in players:
		var info: Dictionary = players[peer_id]
		info["ready"] = false
		players[peer_id] = info
	if dedicated_server and players.is_empty():
		# Nobody is left to inherit the room, so the next person to arrive gets it.
		lobby_host_peer_id = 0
	print("NETWORK_RUN_ENDED reason=%s" % reason)
	_sync_roster.rpc(players, lobby_host_peer_id)
	roster_changed.emit(players.duplicate(true))
	_return_to_lobby.rpc(reason)
	_return_to_lobby_locally(reason)


@rpc("authority", "call_remote", "reliable")
func _return_to_lobby(reason: String) -> void:
	_return_to_lobby_locally(reason)


func _return_to_lobby_locally(reason: String) -> void:
	game_started = false
	# The death screen and the victory overlay both pause the tree. Carrying that
	# pause into the lobby would leave it drawn but dead to input.
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	run_ended.emit(reason)
	status_changed.emit(reason)
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)


## True where world simulation is allowed to run: single-player and the server
## of a session. False only on a client, which takes the world from the server
## instead of running a second, divergent copy of it.
##
## `WorldNet.is_world_authority()` is the same predicate reached without naming
## this autoload, for the world scripts the smoke tests pull in.
func is_world_authority() -> bool:
	return not session_active or multiplayer.is_server()


func get_player_name(peer_id: int) -> String:
	var info: Dictionary = players.get(peer_id, {})
	return str(info.get("name", "Player"))


func is_player_ready(peer_id: int) -> bool:
	var info: Dictionary = players.get(peer_id, {})
	return bool(info.get("ready", false))


func is_local_lobby_host() -> bool:
	return session_active and multiplayer.get_unique_id() == lobby_host_peer_id


func can_start_game() -> bool:
	if players.is_empty() or game_started:
		return false
	for peer_id: int in players:
		if not is_player_ready(peer_id):
			return false
	return true


func set_local_ready(ready: bool) -> void:
	if not session_active or game_started:
		return
	if multiplayer.is_server():
		_set_player_ready(SERVER_PEER_ID, ready)
	else:
		_request_ready.rpc_id(SERVER_PEER_ID, ready)


func request_start_game() -> void:
	if not session_active or game_started:
		return
	if multiplayer.is_server():
		_try_start_game(SERVER_PEER_ID)
	else:
		_request_start_game.rpc_id(SERVER_PEER_ID)


func send_player_spawn(
	target_peer_id: int,
	player_peer_id: int,
	display_name: String,
	spawn_index: int
) -> void:
	if not multiplayer.is_server() or not world_ready_peers.has(target_peer_id):
		return
	_receive_player_spawn.rpc_id(target_peer_id, player_peer_id, display_name, spawn_index)


func sanitize_display_name(value: String) -> String:
	var cleaned := ""
	for character: String in value.strip_edges():
		if character.unicode_at(0) >= 32:
			cleaned += character
		if cleaned.length() >= 24:
			break
	cleaned = cleaned.strip_edges()
	return cleaned if not cleaned.is_empty() else "Player"


@rpc("any_peer", "call_remote", "reliable")
func _register_player(requested_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if game_started:
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	if dedicated_server and lobby_host_peer_id == 0:
		lobby_host_peer_id = sender_id
	players[sender_id] = {
		"name": _unique_name(sanitize_display_name(requested_name), sender_id),
		"ready": false,
	}
	_sync_roster.rpc(players, lobby_host_peer_id)
	roster_changed.emit(players.duplicate(true))
	_enter_lobby.rpc_id(sender_id, players, lobby_host_peer_id, session_port)
	print("NETWORK_PLAYER_REGISTERED peer=%d name=%s" % [sender_id, get_player_name(sender_id)])


@rpc("authority", "call_remote", "reliable")
func _sync_roster(server_players: Dictionary, server_lobby_host_peer_id: int) -> void:
	players = server_players.duplicate(true)
	lobby_host_peer_id = server_lobby_host_peer_id
	roster_changed.emit(players.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _enter_lobby(
	server_players: Dictionary,
	server_lobby_host_peer_id: int,
	server_port: int
) -> void:
	players = server_players.duplicate(true)
	lobby_host_peer_id = server_lobby_host_peer_id
	session_port = server_port
	roster_changed.emit(players.duplicate(true))
	status_changed.emit("Đã vào phòng chờ.")
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)


@rpc("any_peer", "call_remote", "reliable")
func _request_ready(ready: bool) -> void:
	if not multiplayer.is_server() or game_started:
		return
	_set_player_ready(multiplayer.get_remote_sender_id(), ready)


@rpc("any_peer", "call_remote", "reliable")
func _request_start_game() -> void:
	if not multiplayer.is_server():
		return
	_try_start_game(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func _begin_game() -> void:
	_begin_game_locally()


@rpc("any_peer", "call_remote", "reliable")
func _notify_world_ready() -> void:
	if not multiplayer.is_server():
		return
	_mark_world_ready(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _notify_replication_ready() -> void:
	if not multiplayer.is_server():
		return
	_mark_replication_ready(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func _receive_player_spawn(peer_id: int, player_name: String, spawn_index: int) -> void:
	player_spawn_requested.emit(peer_id, player_name, spawn_index)


@rpc("authority", "call_remote", "reliable")
func _receive_player_left(peer_id: int) -> void:
	player_left.emit(peer_id)


func _mark_world_ready(peer_id: int) -> void:
	if peer_id <= 0 or world_ready_peers.has(peer_id):
		return
	world_ready_peers[peer_id] = true
	player_world_ready.emit(peer_id)
	print("NETWORK_WORLD_READY peer=%d" % peer_id)


func _mark_replication_ready(peer_id: int) -> void:
	if peer_id <= 0 or replication_ready_peers.has(peer_id):
		return
	replication_ready_peers[peer_id] = true
	player_replication_ready.emit(peer_id)
	print("NETWORK_REPLICATION_READY peer=%d" % peer_id)


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		status_changed.emit("Peer %d đã kết nối; đang chờ tên người chơi." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(peer_id)
	# Whoever inherits the room has to be picked whether or not a night is
	# running: the point of choosing one is the lobby that comes after it.
	if dedicated_server and peer_id == lobby_host_peer_id:
		lobby_host_peer_id = _first_player_peer_id()
	world_ready_peers.erase(peer_id)
	replication_ready_peers.erase(peer_id)
	_sync_roster.rpc(players, lobby_host_peer_id)
	_receive_player_left.rpc(peer_id)
	roster_changed.emit(players.duplicate(true))
	player_left.emit(peer_id)
	print("NETWORK_PLAYER_LEFT peer=%d" % peer_id)
	# The last person walked out of a night nobody is playing any more. A
	# dedicated server that stayed in the villa would keep turning the next
	# group away at _register_player(), so it goes back to an open lobby.
	# A listen host always holds a seat of its own, so this cannot fire there.
	if game_started and players.is_empty():
		end_run("Phòng đã trống. Sẵn sàng cho ván mới.")


func _on_connected_to_server() -> void:
	status_changed.emit("Đã kết nối server. Đang đăng ký người chơi…")
	_register_player.rpc_id(SERVER_PEER_ID, local_display_name)


func _on_connection_failed() -> void:
	status_changed.emit("Kết nối thất bại. Kiểm tra địa chỉ và UDP port.")
	leave_session(false)


func _on_server_disconnected() -> void:
	status_changed.emit("Server đã ngắt kết nối.")
	leave_session(true)


func _unique_name(base_name: String, peer_id: int) -> String:
	var used_names: Dictionary = {}
	for existing_peer: int in players:
		if existing_peer != peer_id:
			used_names[get_player_name(existing_peer).to_lower()] = true
	if not used_names.has(base_name.to_lower()):
		return base_name
	var suffix := 2
	while used_names.has((base_name + " %d" % suffix).to_lower()):
		suffix += 1
	return (base_name.left(20) + " %d" % suffix).left(24)


func _set_player_ready(peer_id: int, ready: bool) -> void:
	if not players.has(peer_id):
		return
	var info: Dictionary = players[peer_id]
	info["ready"] = ready
	players[peer_id] = info
	_sync_roster.rpc(players, lobby_host_peer_id)
	roster_changed.emit(players.duplicate(true))
	print("NETWORK_PLAYER_READY peer=%d ready=%s" % [peer_id, ready])


func _try_start_game(requesting_peer_id: int) -> void:
	if requesting_peer_id != lobby_host_peer_id or not can_start_game():
		return
	game_started = true
	world_ready_peers.clear()
	replication_ready_peers.clear()
	_begin_game.rpc()
	_begin_game_locally()


func _begin_game_locally() -> void:
	game_started = true
	game_starting.emit()
	status_changed.emit("Đang tải Villa…")
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


func _first_player_peer_id() -> int:
	var peer_ids: Array = players.keys()
	peer_ids.sort()
	return int(peer_ids[0]) if not peer_ids.is_empty() else 0


func _reset_session_state() -> void:
	session_active = false
	dedicated_server = false
	game_started = false
	lobby_host_peer_id = SERVER_PEER_ID
	session_port = DEFAULT_PORT
	players.clear()
	world_ready_peers.clear()
	replication_ready_peers.clear()

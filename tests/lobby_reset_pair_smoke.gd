extends SceneTree

## The locked-door bug, over a real socket: once a night had started, nobody
## could get back in.
##
## `_register_player()` hangs up on anyone who knocks while `game_started` is
## true - which is right during a run and wrong the moment it ends, because
## nothing ever cleared the flag. A wiped team, or a room everyone had quit,
## left a server that turned away the very people who had just been in it. The
## only cure was restarting the process, which on Edgegap means losing the
## allocation.
##
## So this drives the whole arc against a real NetworkManager in two processes:
## knock during the run and get refused, end the run, knock again and get in -
## with the ready flags cleared, because the lobby is there to be readied up in.
##
## Runs itself: started normally it is the server and spawns its own client.
## See world_replication_pair_smoke.gd for the same harness in more detail.

const PORT := 47312
const RESULT_PATH := "user://lobby_reset_pair_result.txt"

const RUN_ENDS_AT := 6.0
const SERVER_SECONDS := 22.0
const FIRST_KNOCK_AT := 1.0
const REFUSAL_CHECKED_AT := 4.0
const SECOND_KNOCK_AT := 9.0
const ADMISSION_CHECKED_AT := 14.0

var _is_client := false
var _elapsed := 0.0
var _done := false
var _stage := 0
var _manager: Node
var _refused := false
var _failures: Array[String] = []


func _initialize() -> void:
	_is_client = "--client" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_manager = root.get_node_or_null(^"/root/NetworkManager")
	if _manager == null:
		return _fail("NetworkManager must be an autoload.")
	if _is_client:
		# The refusal arrives as a server disconnect; NetworkManager's own
		# handler also runs and takes this peer back to the menu, which is
		# exactly what a refused player sees.
		get_multiplayer().server_disconnected.connect(func() -> void: _refused = true)
		return

	if FileAccess.file_exists(RESULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))
	if _manager.call("host_game", "Host", PORT) != OK:
		return _fail("The server could not host on UDP %d." % PORT)
	# Stand in for a night already under way, which is the state that refuses
	# newcomers. Reaching it for real would mean baking the villa twice.
	_manager.set("game_started", true)
	if OS.create_process(OS.get_executable_path(), [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "tests/lobby_reset_pair_smoke.gd",
		"--", "--client",
	]) <= 0:
		return _fail("Could not start the second process.")


func _process(delta: float) -> bool:
	if _done:
		return false
	_elapsed += delta
	if _is_client:
		_client_tick()
	else:
		_server_tick()
	return false


func _server_tick() -> void:
	if _stage == 0 and _elapsed > RUN_ENDS_AT:
		_stage = 1
		_manager.call("end_run", "Cả đội đã ngã xuống.")
		if bool(_manager.get("game_started")):
			_fail("end_run() left the run started, so the door stays shut.")
	elif _elapsed > SERVER_SECONDS:
		_done = true
		_read_client_verdict()


func _client_tick() -> void:
	match _stage:
		0 when _elapsed > FIRST_KNOCK_AT:
			_stage = 1
			_manager.call("join_game", "127.0.0.1", "Latecomer", PORT)
		1 when _elapsed > REFUSAL_CHECKED_AT:
			_stage = 2
			if not _refused:
				_failures.append("a peer was let into a run that was still going")
		2 when _elapsed > SECOND_KNOCK_AT:
			_stage = 3
			_refused = false
			_manager.call("join_game", "127.0.0.1", "Latecomer", PORT)
		3 when _elapsed > ADMISSION_CHECKED_AT:
			_stage = 4
			_check_admission()
			_write_verdict()
			_done = true
			quit()


func _check_admission() -> void:
	if _refused:
		_failures.append("the server was still refusing peers after the run ended")
		return
	var players: Dictionary = _manager.get("players")
	if players.size() < 2:
		_failures.append(
			"the roster came back with %d player(s); the rejoin never landed" % players.size()
		)
		return
	if bool(_manager.get("game_started")):
		_failures.append("the client still believes a run is going, so it cannot ready up")
	for peer_id: int in players:
		if bool((players[peer_id] as Dictionary).get("ready", false)):
			_failures.append("a stale ready flag survived the run; the lobby would restart itself")
			break


func _write_verdict() -> void:
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("The client could not write its verdict.")
		return
	file.store_string("PASS" if _failures.is_empty() else "FAIL: " + ", ".join(_failures))
	file.close()


func _read_client_verdict() -> void:
	if not FileAccess.file_exists(RESULT_PATH):
		return _fail("The client never reported; it died before it could check anything.")
	var verdict := FileAccess.open(RESULT_PATH, FileAccess.READ).get_as_text().strip_edges()
	if verdict != "PASS":
		return _fail("the second process reported: " + verdict)
	print(
		"Lobby reset pair smoke test passed: a run refuses newcomers, ending it reopens "
		+ "the room over a real socket, and everyone comes back un-readied."
	)
	quit()


func _fail(message: String) -> void:
	push_error("Lobby reset pair smoke test failed: " + message)
	print("Lobby reset pair smoke test FAILED: " + message)
	quit(1)

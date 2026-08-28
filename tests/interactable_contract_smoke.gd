extends SceneTree

## Pure component-level tests for Interactable, independent of any player,
## raycast, or owning object. These exercise the reusable contract directly
## so a bug in Interactable itself can't hide behind LightSwitch happening
## to work.

var _signal_count: int = 0
var _signal_player: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_contract()
	_test_disabled()
	_test_lock()

	print("Interactable contract smoke test passed.")
	quit()


func _test_contract() -> void:
	var interactable := Interactable.new()
	interactable.interaction_range = 3.7
	interactable.prompt_text = "MO CUA"
	root.add_child(interactable)

	if not interactable.enabled:
		push_error("Interactable should default to enabled = true.")
		quit(1)
		return
	if not interactable.can_interact():
		push_error("can_interact() should be true for a freshly created, enabled Interactable.")
		quit(1)
		return
	if interactable.interaction_range != 3.7:
		push_error("interaction_range did not expose the configured value.")
		quit(1)
		return

	var prompt := interactable.get_interaction_prompt("E")
	if not prompt.contains("MO CUA") or not prompt.contains("E"):
		push_error("get_interaction_prompt() did not expose the configured prompt text/key.")
		quit(1)
		return

	_reset_signal_probe()
	interactable.interacted.connect(_on_interacted)
	var dummy_player := Node.new()
	root.add_child(dummy_player)

	interactable.interact(dummy_player)

	if _signal_count != 1:
		push_error("interact() should emit interacted() exactly once; emitted %d times." % _signal_count)
		quit(1)
		return
	if _signal_player != dummy_player:
		push_error("interacted signal did not pass through the interacting player.")
		quit(1)
		return

	dummy_player.queue_free()
	interactable.queue_free()


func _test_disabled() -> void:
	var interactable := Interactable.new()
	root.add_child(interactable)
	var dummy_player := Node.new()
	root.add_child(dummy_player)

	interactable.enabled = false
	if interactable.can_interact():
		push_error("can_interact() should be false when enabled = false.")
		quit(1)
		return

	_reset_signal_probe()
	interactable.interacted.connect(_on_interacted)
	interactable.interact(dummy_player)
	if _signal_count != 0:
		push_error("A disabled Interactable emitted interacted() from a direct interact() call.")
		quit(1)
		return

	interactable.enabled = true
	if not interactable.can_interact():
		push_error("Restoring enabled = true did not restore can_interact().")
		quit(1)
		return
	interactable.interact(dummy_player)
	if _signal_count != 1:
		push_error("Re-enabled Interactable did not emit interacted() again.")
		quit(1)
		return

	dummy_player.queue_free()
	interactable.queue_free()


func _test_lock() -> void:
	var interactable := Interactable.new()
	root.add_child(interactable)
	var dummy_player := Node.new()
	root.add_child(dummy_player)

	interactable.lock()
	if interactable.can_interact():
		push_error("can_interact() should be false after lock().")
		quit(1)
		return

	_reset_signal_probe()
	interactable.interacted.connect(_on_interacted)
	interactable.interact(dummy_player)
	if _signal_count != 0:
		push_error("A locked Interactable emitted interacted() from a direct interact() call.")
		quit(1)
		return

	interactable.unlock()
	if not interactable.can_interact():
		push_error("unlock() did not restore can_interact().")
		quit(1)
		return
	interactable.interact(dummy_player)
	if _signal_count != 1:
		push_error("Unlocked Interactable did not emit interacted() again.")
		quit(1)
		return

	dummy_player.queue_free()
	interactable.queue_free()


func _reset_signal_probe() -> void:
	_signal_count = 0
	_signal_player = null


func _on_interacted(player: Node) -> void:
	_signal_count += 1
	_signal_player = player

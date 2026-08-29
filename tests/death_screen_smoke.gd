extends SceneTree

const TEST_SCENE := "res://tests/death_screen_test_scene.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var change_error := change_scene_to_file(TEST_SCENE)
	if change_error != OK:
		_fail("Could not load the death-screen test scene.")
		return
	await scene_changed

	var first_scene := current_scene
	var player := first_scene.get_node("Player") as CharacterBody3D
	var statue := first_scene.get_node("StatueKiller") as Node3D
	var death_ui := player.get_node("DeathUI") as CanvasLayer
	player.call("kill_by_ghost", statue)

	if bool(player.get("is_alive")):
		_fail("A ghost kill did not mark the player dead.")
		return
	if not paused or not death_ui.visible:
		_fail("The jumpscare did not pause and cover the game world.")
		return
	if int(death_ui.get("phase")) != 1: # IMPACT
		_fail("The death sequence did not begin with its impact phase.")
		return

	death_ui.call("debug_finish_jumpscare")
	if not bool(death_ui.call("is_showing_game_over")):
		_fail("The jumpscare did not transition to Game Over.")
		return
	var cause := death_ui.get_node("GameOver/Card/Content/Cause") as Label
	if "TƯỢNG ĐÁ" not in cause.text:
		_fail("The statue death did not receive statue-specific Game Over copy.")
		return

	# Activate the real button and confirm reload_current_scene creates a fresh,
	# alive player instead of only hiding the overlay.
	var old_scene_id := first_scene.get_instance_id()
	var restart_button := death_ui.get_node("GameOver/Card/Content/RestartButton") as Button
	restart_button.pressed.emit()
	await scene_changed
	if paused:
		_fail("Restart left the new game paused.")
		return
	if current_scene.get_instance_id() == old_scene_id:
		_fail("Restart did not reload the current scene.")
		return

	var reset_player := current_scene.get_node("Player") as CharacterBody3D
	if not bool(reset_player.get("is_alive")) or reset_player.get_node("DeathUI").visible:
		_fail("Restart did not reset the player's death state and overlay.")
		return

	# The second killer exercises the alternate portrait/copy/audio route.
	var crawler := current_scene.get_node("CrawlerKiller") as Node3D
	var crawler_death_ui := reset_player.get_node("DeathUI") as CanvasLayer
	reset_player.call("kill_by_ghost", crawler)
	crawler_death_ui.call("debug_finish_jumpscare")
	var crawler_cause := crawler_death_ui.get_node("GameOver/Card/Content/Cause") as Label
	if "BÒ TRÊN TRẦN" not in crawler_cause.text:
		_fail("The crawler death did not receive crawler-specific presentation.")
		return

	# Hunter and Darkness have distinct portraits, timing/audio routes and copy.
	# The second player is already dead, so exercise the presentation routing
	# directly rather than attempting another gameplay kill on it.
	var hunter := current_scene.get_node("HunterKiller") as Node3D
	var darkness := current_scene.get_node("DarknessKiller") as Node3D
	if crawler_death_ui.call("_identify_killer", hunter) != &"hunter":
		_fail("The Hunter was not routed to its remade jumpscare variant.")
		return
	if crawler_death_ui.call("_identify_killer", darkness) != &"darkness":
		_fail("The Darkness Ghost was not routed to its own jumpscare variant.")
		return
	crawler_death_ui.set("killer_variant", &"darkness")
	crawler_death_ui.call("_configure_copy")
	if "MA BÓNG TỐI" not in crawler_cause.text:
		_fail("The Darkness Ghost did not receive darkness-specific Game Over copy.")
		return
	var visage := crawler_death_ui.get_node("Visage") as Control
	visage.call("configure", &"hunter")
	visage.call("set_scare_progress", 0.75)
	if visage.get("killer_variant") != &"hunter":
		_fail("The remade Hunter portrait could not be configured.")
		return
	visage.call("configure", &"darkness")
	visage.call("set_scare_progress", 0.75)
	if visage.get("killer_variant") != &"darkness":
		_fail("The Darkness Ghost portrait could not be configured.")
		return

	paused = false
	print("Death screen smoke test passed: all killer jumpscares, Game Over, and full scene reset.")
	current_scene.queue_free()
	await process_frame
	quit()


func _fail(message: String) -> void:
	paused = false
	push_error(message)
	quit(1)

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
	var scare := player.get_node("Jumpscare") as JumpscareController
	player.call("kill_by_ghost", statue)

	if bool(player.get("is_alive")):
		_fail("A ghost kill did not mark the player dead.")
		return
	if not paused or not scare.is_playing():
		_fail("The 3D jumpscare did not pause and cover the game world.")
		return
	if death_ui.visible or int(death_ui.get("phase")) != 0:
		_fail("The legacy drawn death screen appeared underneath the 3D jumpscare.")
		return

	scare.set_process(false)
	scare.debug_step(scare.get_total_duration())
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

	# The second killer exercises the alternate 3D identity and Game Over copy.
	var crawler := current_scene.get_node("CrawlerKiller") as Node3D
	var crawler_death_ui := reset_player.get_node("DeathUI") as CanvasLayer
	var crawler_scare := reset_player.get_node("Jumpscare") as JumpscareController
	reset_player.call("kill_by_ghost", crawler)
	if not crawler_scare.is_playing() or crawler_scare.get_killer_variant() != &"crawler":
		_fail("The crawler kill did not start the Crawler's 3D jumpscare.")
		return
	crawler_scare.set_process(false)
	crawler_scare.debug_step(crawler_scare.get_total_duration())
	var crawler_cause := crawler_death_ui.get_node("GameOver/Card/Content/Cause") as Label
	if "BÒ TRÊN TRẦN" not in crawler_cause.text:
		_fail("The crawler death did not receive crawler-specific presentation.")
		return

	var darkness := current_scene.get_node("DarknessKiller") as Node3D
	if crawler_death_ui.call("_identify_killer", darkness) != &"darkness":
		_fail("The Darkness Ghost was not routed to its own jumpscare.")
		return
	crawler_death_ui.set("killer_variant", &"darkness")
	crawler_death_ui.call("_configure_copy")
	if "MA BÓNG TỐI" not in crawler_cause.text:
		_fail("The Darkness Ghost did not receive darkness-specific Game Over copy.")
		return
	paused = false
	print("Death screen smoke test passed: 3D ghost identity, killer copy, Game Over, and full scene reset.")
	current_scene.queue_free()
	await process_frame
	quit()


func _fail(message: String) -> void:
	paused = false
	push_error(message)
	quit(1)

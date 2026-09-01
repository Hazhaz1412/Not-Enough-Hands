extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if not packed:
		_fail("Main scene with Dev Tools could not be loaded.")
		return

	var game := packed.instantiate()
	root.add_child(game)
	var dev_tools := game.get_node("DevTools") as DevTools
	var player := game.get_node("Player") as CharacterBody3D
	var statue := game.get_node("StatueGhost") as CharacterBody3D
	var crawler := game.get_node("CrawlerGhost") as CharacterBody3D
	var hunter := game.get_node("HunterGhost") as CharacterBody3D
	var director := game.get_node("DoorAttackDirector") as DoorAttackDirector
	if not dev_tools or not player or not statue or not crawler or not hunter or not director:
		_fail("Dev Tools could not resolve its main-scene dependencies.")
		return

	director.automatic_waves = false
	statue.set_physics_process(false)
	crawler.set_physics_process(false)
	hunter.set_physics_process(false)
	for door: Node in get_nodes_in_group("defense_doors"):
		door.set_physics_process(false)

	dev_tools.set_panel_open(true)
	if not dev_tools.panel_open or not dev_tools.panel.visible:
		_fail("F1 panel API did not show Dev Tools.")
		return
	if dev_tools.panel.get_combined_minimum_size().y > dev_tools.panel.size.y:
		_fail("Dev Tools controls overflow the panel (minimum %.1f, panel %.1f)." % [
			dev_tools.panel.get_combined_minimum_size().y,
			dev_tools.panel.size.y,
		])
		return
	dev_tools.set_invincibility_enabled(true)
	if not bool(player.get("dev_invincible")) \
		or bool(player.call("can_be_targeted_by_ghosts")):
		_fail("Invincibility did not protect the player from ghost targeting.")
		return
	player.call("kill_by_ghost", statue)
	if not bool(player.get("is_alive")):
		_fail("A ghost killed the player while Dev Tools invincibility was enabled.")
		return

	dev_tools.set_fast_movement_enabled(true)
	if not bool(player.get("dev_fast_movement")) \
		or not is_equal_approx(float(player.get("current_stamina")), float(player.get("max_stamina"))):
		_fail("Fast movement did not enable or refill development stamina.")
		return

	# The bladder slider is both a setter and a live monitor: changing it must
	# mutate the authoritative PlayerBladder through Player's public API, while
	# later gameplay changes must immediately flow back into the control.
	dev_tools.set_bladder_level(73.0)
	if not is_equal_approx(player.get_bladder(), 73.0) \
		or not is_equal_approx(dev_tools.bladder_slider.value, 73.0) \
		or dev_tools.bladder_value.text != "73%":
		_fail("Dev Tools bladder slider did not set and display 73%.")
		return
	player.reduce_bladder(13.0)
	if not is_equal_approx(dev_tools.bladder_slider.value, 60.0) \
		or dev_tools.bladder_value.text != "60%":
		_fail("Dev Tools bladder slider did not follow a gameplay-side bladder change.")
		return
	dev_tools.set_bladder_level(1000.0)
	if not is_equal_approx(player.get_bladder(), player.bladder.bladder_max) \
		or not is_equal_approx(dev_tools.bladder_slider.value, player.bladder.bladder_max):
		_fail("Dev Tools bladder slider bypassed the normal maximum clamp.")
		return
	dev_tools.set_bladder_level(0.0)

	# Noclip has to switch off the capsule as well as gravity, or the player
	# flies while still being shoved around by whatever they are inside of.
	var before_flight := player.global_position
	dev_tools.set_noclip_enabled(true)
	if not bool(player.get("dev_noclip")) or not player.get_node("CollisionShape3D").disabled:
		_fail("Noclip did not disable the player capsule.")
		return
	player.global_position = before_flight + Vector3(0, 40.0, 0)
	await physics_frame
	if player.global_position.y < before_flight.y + 39.0:
		_fail("Noclip did not stop gravity pulling the player back down.")
		return
	dev_tools.set_noclip_enabled(false)
	if bool(player.get("dev_noclip")) or player.get_node("CollisionShape3D").disabled:
		_fail("Turning noclip off did not restore the player capsule.")
		return
	player.global_position = before_flight

	# Clear vision has to switch the overlays off, or the house stays as hard to
	# read as it was for a player who asked for it not to be.
	var environment_before: Environment = (game.get_node("WorldEnvironment") as WorldEnvironment).environment
	dev_tools.set_bright_vision_enabled(true)
	if not bool(player.get("dev_clear_vision")) \
		or player.get_node("HorrorOverlay/VignetteAndGrain").visible:
		_fail("Clear vision left an adverse effect switched on.")
		return
	var bright_environment: Environment = (game.get_node("WorldEnvironment") as WorldEnvironment).environment
	if bright_environment.fog_enabled or bright_environment.volumetric_fog_enabled:
		_fail("Clear vision did not clear the fog.")
		return
	dev_tools.set_bright_vision_enabled(false)
	if (game.get_node("WorldEnvironment") as WorldEnvironment).environment != environment_before:
		_fail("Turning clear vision off did not restore the original environment.")
		return

	# The entrance x-ray has to reach all seven doors and clean up after itself.
	dev_tools.set_entrance_xray_enabled(true)
	var tagged: Array[int] = []
	for door: Node in get_nodes_in_group("defense_doors"):
		var marker := door.get_node_or_null(DevTools.XRAY_MARKER_NAME)
		if not marker:
			_fail("Entrance %02d got no x-ray marker." % int(door.get("entrance_id")))
			return
		var label := marker.get_node("Tag") as Label3D
		if not label.no_depth_test or label.text != "%02d" % int(door.get("entrance_id")):
			_fail("Entrance %02d's x-ray tag is wrong or not drawn through walls."
				% int(door.get("entrance_id")))
			return
		tagged.append(int(door.get("entrance_id")))
	tagged.sort()
	if tagged != [1, 2, 3, 4, 5, 6, 7]:
		_fail("Entrance x-ray covered %s, not all seven doors." % [tagged])
		return
	dev_tools.set_entrance_xray_enabled(false)
	await process_frame
	for door: Node in get_nodes_in_group("defense_doors"):
		if door.get_node_or_null(DevTools.XRAY_MARKER_NAME):
			_fail("Entrance x-ray left a marker behind when switched off.")
			return

	if not dev_tools.spawn_statue() or not statue.get_node("VisualRoot").visible:
		_fail("Dev Tools did not force the statue to manifest.")
		return
	if not dev_tools.spawn_crawler() or not bool(crawler.get("manifested")):
		_fail("Dev Tools did not force the crawler to manifest.")
		return
	# The huntsman normally needs a breached door, so the forced spawn also has
	# to put it in the "already inside" state rather than only making it visible.
	if not dev_tools.spawn_hunter() \
		or not bool(hunter.get("manifested")) \
		or not bool(hunter.get("inside_house")):
		_fail("Dev Tools did not put the huntsman inside the house.")
		return

	dev_tools.set_selected_entrance(4)
	if not dev_tools.force_selected_door_attack():
		_fail("Dev Tools could not start an attack at entrance 04.")
		return
	var attacked_door: DefenseDoor
	for door: Node in get_nodes_in_group("defense_doors"):
		if int(door.get("entrance_id")) == 4:
			attacked_door = door as DefenseDoor
			break
	if not attacked_door \
		or attacked_door.attack_phase != DefenseDoor.AttackPhase.STALKING \
		or not attacked_door.planned_attack:
		_fail("The selected entrance did not receive the forced real attack.")
		return

	dev_tools.set_panel_open(false)
	if dev_tools.panel_open or dev_tools.panel.visible:
		_fail("Dev Tools panel did not close.")
		return

	# House2 has no ElectricalZones, so the blackout button has to fall through
	# to PowerManager's global outage - otherwise the default map has no way to
	# cut the power at all and the main breaker can never be seen lit.
	var manager := get_first_node_in_group("power_manager") as PowerManager
	var breaker := get_first_node_in_group("main_breakers") as MainBreaker
	if not manager or not breaker:
		_fail("Main scene is missing its PowerManager or MainBreaker.")
		return
	if not get_nodes_in_group("electrical_zones").is_empty():
		_fail("This check is about the no-zone fallback; House2 gained zones.")
		return
	dev_tools.set_all_zones_powered(false)
	await process_frame
	if not manager.is_blackout:
		_fail("The blackout button did nothing on a map without electrical zones.")
		return
	if not breaker.outline.visible:
		_fail("The main breaker did not light up during a dev-triggered blackout.")
		return
	dev_tools.set_all_zones_powered(true)
	await process_frame
	if manager.is_blackout or breaker.outline.visible:
		_fail("Restoring power left the house dark or the breaker still lit.")
		return

	# The second route to a dark house: empty the battery and let PowerManager's
	# own drain reach zero, rather than forcing the outage flag. Both maps ship
	# enable_power_drain = false, so the button has to switch drain on or the
	# reserve just sits at 1 and the house never goes dark.
	if manager.get_total_load() <= 0.0:
		_fail("House2 has no power draw, so the drain route cannot be tested.")
		return
	dev_tools.drain_house_power()
	if not manager.enable_power_drain or manager.current_power > 1.0:
		_fail("Draining the house power did not arm the reserve for an outage.")
		return
	# The reserve now drains at a designed pace rather than instantly, so 1 unit
	# takes a fraction of a second - a few frames is not enough to see it land.
	var drained := false
	for _frame: int in 120:
		await process_frame
		if manager.is_blackout:
			drained = true
			break
	if not drained:
		_fail("Draining the reserve to 1 never reached a blackout (power=%.2f)." % manager.current_power)
		return
	if not breaker.outline.visible:
		_fail("The main breaker did not light up for a drained-battery blackout.")
		return
	dev_tools.recharge_house_power()
	manager.enable_power_drain = false
	await process_frame
	if manager.is_blackout or breaker.outline.visible:
		_fail("Recharging did not clear the drained-battery blackout.")
		return

	for audio: AudioStreamPlayer3D in [
		statue.get_node("TeleportAudio"),
		statue.get_node("AttackAudio"),
		statue.get_node("SpottedJumpscareAudio"),
		crawler.get_node("CrawlAudio"),
		crawler.get_node("ChitterAudio"),
		crawler.get_node("BreathAudio"),
		crawler.get_node("ScreamAudio"),
		crawler.get_node("BoneAudio"),
		hunter.get_node("FootstepAudio"),
		hunter.get_node("HookAudio"),
		hunter.get_node("BreathAudio"),
		hunter.get_node("SniffAudio"),
		hunter.get_node("HornAudio"),
		hunter.get_node("SeizeAudio"),
		hunter.get_node("BreachAudio"),
	]:
		audio.stop()
	game.queue_free()
	await process_frame
	print("Dev Tools smoke test passed: bladder slider, invincibility, x3 speed, noclip flight, clear vision, seven-door x-ray, all three ghosts, and selected-door attack.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

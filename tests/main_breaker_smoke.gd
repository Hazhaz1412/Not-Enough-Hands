extends SceneTree

## The main breaker's wiring to the house: it glows during a blackout, hands
## the player the repair minigame instead of restoring instantly, and only
## clears the outage once that repair is served. The wheel's own rules (10s,
## +1.5s per failure, reversing and accelerating needle) live in
## tests/breaker_minigame_smoke.gd.

const STEP := 0.1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var manager := PowerManager.new()
	manager.enable_power_drain = false
	manager.auto_register_house_lights = false
	root_node.add_child(manager)
	var controller := ElectricalZoneController.new()
	root_node.add_child(controller)
	for id: StringName in [&"A", &"B"]:
		var light := OmniLight3D.new()
		light.name = String(id) + "Light"
		root_node.add_child(light)
		var device := ElectricalDevice.new()
		device.device_id = id
		device.powered_light = light
		light.add_child(device)
		var zone := ElectricalZone.new()
		zone.zone_id = StringName("ZONE_" + String(id))
		zone.device_ids = PackedStringArray([String(id)])
		controller.add_child(zone)
	var breaker_scene := load("res://power/main_breaker.tscn") as PackedScene
	var breaker := breaker_scene.instantiate() as MainBreaker
	root_node.add_child(breaker)
	var player := (load("res://player/player.tscn") as PackedScene).instantiate()
	root_node.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 3.0)
	await process_frame
	await process_frame

	var minigame := breaker.minigame
	_assert(minigame != null, "The main breaker is missing its BreakerMinigame child.")
	_assert(not breaker.outline.visible, "The breaker outline must stay dark while the house has power.")

	# A DarknessGhost darkens one zone at a time, which emits neither
	# PowerManager.blackout nor power_restored. The cabinet still has to notice:
	# it is what _needs_repair() reports, so it is what the glow must show.
	var zones := get_nodes_in_group("electrical_zones")
	(zones[0] as ElectricalZone).begin_switch_restore_outage()
	await process_frame
	_assert(not manager.is_blackout, "One dark zone must not read as a house-wide blackout.")
	_assert(breaker.outline.visible, "The glow outline ignored a single-zone outage.")
	_assert(
		breaker.interactable.prompt_text.begins_with("SỬA CẦU DAO TỔNG"),
		"The prompt went stale on a single-zone outage: '%s'." % breaker.interactable.prompt_text
	)

	for index: int in range(1, zones.size()):
		(zones[index] as ElectricalZone).begin_switch_restore_outage()
	await process_frame
	_assert(manager.is_blackout, "All persistent zone failures must cause a full-house blackout.")

	# --- Blackout: the cabinet advertises and lights itself up. ---
	_assert(
		breaker.interactable.prompt_text.begins_with("SỬA CẦU DAO TỔNG"),
		"Breaker did not advertise the repair, prompt was '%s'." % breaker.interactable.prompt_text
	)
	_assert(breaker.outline.visible, "The breaker outline must be visible during a blackout.")
	_assert(breaker.is_processing(), "The breaker's blackout highlight pulse is not running.")

	# The rim is a stencil effect, not a depth effect. The cabinet stamps its
	# silhouette into the stencil with WRITE *and* WRITE_DEPTH_FAIL - so the mark
	# is there even when a wall is in front - and the shell reads it back with
	# NOT_EQUAL. That pairing is the whole trick: it lets the shell run with
	# no_depth_test (visible from anywhere, through anything) while still being
	# carved back into a rim instead of a solid slab over the cabinet. Break
	# either half and the highlight becomes an orange block, so both are pinned.
	var cabinet_material := (breaker.get_node("Cabinet") as MeshInstance3D).material_override \
		as StandardMaterial3D
	_assert(cabinet_material != null, "The cabinet has no StandardMaterial3D to stencil with.")
	_assert(
		cabinet_material.stencil_flags
			== BaseMaterial3D.STENCIL_FLAG_WRITE | BaseMaterial3D.STENCIL_FLAG_WRITE_DEPTH_FAIL,
		"The cabinet must stamp the stencil on depth fail too, or the rim fills in through walls."
	)
	_assert(cabinet_material.stencil_reference == 1, "Cabinet stencil reference must be 1.")

	var outline_material := breaker.outline.material_override as StandardMaterial3D
	_assert(outline_material != null, "The breaker outline has no StandardMaterial3D.")
	_assert(
		outline_material.no_depth_test,
		"The outline must ignore depth, or it stops being visible through walls."
	)
	_assert(
		outline_material.stencil_flags == BaseMaterial3D.STENCIL_FLAG_READ
			and outline_material.stencil_compare == BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
			and outline_material.stencil_reference == cabinet_material.stencil_reference,
		"The outline must read the cabinet's stencil with NOT_EQUAL or it paints a solid slab."
	)
	var alpha_before := outline_material.albedo_color.a
	breaker._process(0.6)
	_assert(
		not is_equal_approx(outline_material.albedo_color.a, alpha_before),
		"The outline glow is not pulsing (alpha stayed at %.3f)." % alpha_before
	)

	# A fixed metre-wide rim shrinks to nothing across a room, so it is grown
	# with viewing distance - that is what "visible from any distance" rests on.
	# A throwaway camera, not the player's: moving the player's camera detaches
	# it from the head rig and takes the InteractRay with it, which would break
	# the aiming check below.
	var player_camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	var probe_camera := Camera3D.new()
	root_node.add_child(probe_camera)
	probe_camera.global_position = breaker.global_position + Vector3(0.0, 0.0, 4.0)
	probe_camera.make_current()
	breaker._process(0.0)
	var near_scale := breaker.outline.scale
	probe_camera.global_position = breaker.global_position + Vector3(0.0, 0.0, 40.0)
	breaker._process(0.0)
	_assert(
		breaker.outline.scale.x > near_scale.x,
		"The outline rim did not grow with viewing distance (%.3f -> %.3f)."
			% [near_scale.x, breaker.outline.scale.x]
	)
	probe_camera.queue_free()
	await process_frame
	player_camera.make_current()

	# --- Using it opens the repair; it restores nothing on its own. ---
	# Driven through the real pipeline (raycast -> get_interaction_target ->
	# Interactable), not by calling interact() directly. Calling it directly
	# hides whether the player can actually aim at the cabinet at all: the
	# interact ray only sees collision layer 2, and this scene shipped on the
	# default layer 1, so E did nothing in either map while every direct-call
	# assertion below still passed.
	player.set_physics_process(false)
	player.global_position = breaker.global_position + Vector3(0.0, -1.25, 1.5)
	player.global_rotation = Vector3.ZERO
	await physics_frame
	var ray: RayCast3D = player.get_node("CameraPivot/Camera3D/InteractRay")
	ray.force_raycast_update()
	_assert(
		ray.is_colliding() and ray.get_collider() == breaker,
		"The player's interact ray cannot even reach the cabinet (hit %s) - check collision_layer."
			% [ray.get_collider() if ray.is_colliding() else "nothing"]
	)
	_assert(
		player.call("get_interaction_target") == breaker.interactable,
		"Aiming at the cabinet did not resolve to its Interactable."
	)
	player.call("_try_interact")
	_assert(minigame.is_running(), "Interacting with the breaker did not start the repair minigame.")
	_assert(manager.is_blackout, "The breaker restored power without the repair being served.")
	_assert(not breaker.interactable.can_interact(), "The breaker stayed interactable during its repair.")
	_assert(not player.is_physics_processing(), "The repair minigame did not pin the player in place.")
	_assert(player.is_breaker_minigame_active(), "Player did not report the breaker minigame as active.")
	minigame.set_process(false)

	# --- A failure is carried out of the session and back into the prompt. ---
	minigame._needle_angle = fposmod(minigame._target_angle + 180.0, 360.0)
	minigame.press()
	minigame.cancel()
	await process_frame
	_assert(manager.is_blackout, "Cancelling a repair must leave the house dark.")
	_assert(breaker.interactable.can_interact(), "The breaker stayed locked after a cancelled repair.")
	_assert(player.is_physics_processing(), "The player was not released by a cancelled repair.")
	var expected_seconds := ceilf(minigame.repair_duration + minigame.fail_penalty)
	_assert(
		breaker.interactable.prompt_text == "SỬA CẦU DAO TỔNG (%.0f GIÂY)" % expected_seconds,
		"The failed attempt was not carried into the prompt, got '%s'." % breaker.interactable.prompt_text
	)

	# --- Serving the countdown is what restores the house. ---
	breaker.interactable.interact(player)
	_assert(minigame.is_running(), "The breaker did not reopen its repair after a cancel.")
	minigame.set_process(false)
	minigame._remaining = 0.05
	minigame._target_angle = fposmod(minigame._needle_angle + minigame._direction * 180.0, 360.0)
	minigame._process(STEP)
	await process_frame

	_assert(not manager.is_blackout, "A completed repair did not clear the global blackout.")
	for node: Node in get_nodes_in_group("electrical_zones"):
		_assert((node as ElectricalZone).is_powered, "A completed repair left an electrical zone disabled.")
	_assert(
		breaker.interactable.prompt_text == "CẦU DAO ĐANG ỔN ĐỊNH",
		"Breaker prompt did not return to its healthy state."
	)
	_assert(not breaker.outline.visible, "The breaker outline stayed lit after power came back.")
	_assert(not breaker.is_processing(), "The breaker kept pulsing after power came back.")
	_assert(breaker.interactable.can_interact(), "The breaker stayed locked after a completed repair.")
	_assert(player.is_physics_processing(), "The player was not released by a completed repair.")
	_assert(
		is_equal_approx(minigame.get_repair_remaining(), minigame.repair_duration),
		"The next outage must start from a full-length repair, got %.2f." % minigame.get_repair_remaining()
	)

	print("Main breaker smoke test passed: blackout outline, minigame-gated repair, one restore of every zone.")
	quit()


func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)

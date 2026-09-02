extends SceneTree

## Pins the two per-instance guarantees multiplayer depends on: changing one
## player's crouch capsule must not mutate another player's collider, and a
## remote replica entering the viewport must not take over the local camera.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager := root.get_node_or_null(^"/root/NetworkManager")
	if manager == null:
		return _fail("NetworkManager autoload is missing.")
	manager.set("session_active", true)

	var player_scene := load("res://player/player.tscn") as PackedScene
	if player_scene == null:
		return _fail("Player scene could not be loaded.")

	var world := Node3D.new()
	world.name = "PlayerIsolationWorld"
	root.add_child(world)
	current_scene = world

	var local_player := player_scene.instantiate() as CharacterBody3D
	local_player.name = "Player"
	local_player.owner_peer_id = 1
	world.add_child(local_player)
	local_player.set_physics_process(false)

	var remote_player := player_scene.instantiate() as CharacterBody3D
	remote_player.name = "Player_2"
	remote_player.owner_peer_id = 2
	world.add_child(remote_player)
	remote_player.set_physics_process(false)

	var local_camera := local_player.get_node("CameraPivot/Camera3D") as Camera3D
	var remote_camera := remote_player.get_node("CameraPivot/Camera3D") as Camera3D
	if not local_camera.current or remote_camera.current:
		return _fail("A remote player replica stole the local viewport camera.")

	# Network identity zero is a transient/malformed replica, never an alias for
	# the local peer. Letting it through gives it input and makes its Camera3D an
	# automatic viewport fallback candidate.
	var unowned_player := player_scene.instantiate() as CharacterBody3D
	unowned_player.name = "Player_Unowned"
	unowned_player.owner_peer_id = 0
	world.add_child(unowned_player)
	unowned_player.set_physics_process(false)
	var unowned_camera := unowned_player.get_node("CameraPivot/Camera3D") as Camera3D
	if unowned_player.is_local_player() or unowned_camera.current \
		or unowned_player.is_processing_unhandled_input():
		return _fail("An identity-less network replica was allowed to own local controls.")

	# Simulate a viewport fallback selecting a remote camera after startup. The
	# continuous ownership guard must disable it and put the local camera back.
	remote_camera.make_current()
	if not remote_camera.current:
		return _fail("The camera-theft setup did not make the remote camera current.")
	remote_player.call("_guard_local_control_ownership")
	local_player.call("_guard_local_control_ownership")
	if not local_camera.current or remote_camera.current:
		return _fail("The runtime ownership guard did not recover the local camera.")

	# Movement is body-relative, so the current camera and owning body must share
	# their horizontal right axis. If a PI-rotated remote camera is current this
	# exact check flips sign, matching the reported A/right and D/left symptom.
	local_player.rotation.y = 0.63
	remote_player.rotation.y = local_player.rotation.y + PI
	var a_direction := (
		local_player.global_basis * Vector3.LEFT
	).slide(Vector3.UP).normalized()
	var screen_right := local_camera.global_basis.x.slide(Vector3.UP).normalized()
	if a_direction.dot(screen_right) > -0.99:
		return _fail("The owning camera and A/D movement basis are no longer aligned.")

	# Alt alone still toggles capture, but the Alt part of Alt+Tab is cancelled so
	# coming back to the game cannot leave mouse-look silently released.
	var alt_press := InputEventKey.new()
	alt_press.keycode = KEY_ALT
	alt_press.pressed = true
	if not bool(local_player.call("_handle_mouse_capture_shortcut", alt_press)) \
		or not bool(local_player.get("_alt_toggle_pending")):
		return _fail("Bare Alt did not arm the mouse-capture shortcut.")
	var tab_press := InputEventKey.new()
	tab_press.keycode = KEY_TAB
	tab_press.pressed = true
	local_player.call("_handle_mouse_capture_shortcut", tab_press)
	if bool(local_player.get("_alt_toggle_pending")):
		return _fail("Alt+Tab was mistaken for the bare-Alt mouse shortcut.")

	# The owning camera sits inside its own rig. That rig must live exclusively
	# on the private body layer or its head and arms still match the flashlight
	# through world layer 1 and cast a broken silhouette across the whole beam.
	var local_body_mask := 1 << (20 - 1)
	var local_character := local_player.get_node("PlayerVisual/Character") as Node3D
	var local_flashlight := local_player.get_node(
		"CameraPivot/Camera3D/Flashlight"
	) as SpotLight3D
	for node: Node in local_character.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry.layers != local_body_mask:
			return _fail("The owning player's body still shares a layer with its flashlight.")
		if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return _fail("The owning player's body still casts a shadow into its flashlight.")
	if local_flashlight.light_cull_mask & local_body_mask:
		return _fail("The owning player's flashlight still includes its private body layer.")
	var remote_character := remote_player.get_node("PlayerVisual/Character") as Node3D
	if local_character.visible:
		return _fail("The local camera is still trapped inside its visible player model.")
	if not remote_character.visible:
		return _fail("The remote player's body was hidden together with the local body.")
	for node: Node in remote_character.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry.layers & 1 == 0:
			return _fail("A remote player's visible body was moved off the world layer.")

	var local_collision := local_player.get_node("CollisionShape3D") as CollisionShape3D
	var remote_collision := remote_player.get_node("CollisionShape3D") as CollisionShape3D
	var local_shape := local_collision.shape as CapsuleShape3D
	var remote_shape := remote_collision.shape as CapsuleShape3D
	if local_shape == remote_shape:
		return _fail("Two player instances still share one CapsuleShape3D resource.")

	var local_height := local_shape.height
	remote_player.call("_crouch")
	if not is_equal_approx(local_shape.height, local_height):
		return _fail("Crouching the remote player changed the local player's capsule.")
	if not is_equal_approx(remote_shape.height, remote_player.crouch_height):
		return _fail("The remote player's own capsule did not enter crouch height.")

	# A new authoritative correction replaces an old pending one, and applying it
	# moves every unacknowledged prediction into the same coordinate space. This
	# prevents the same error being rediscovered and accumulated every snapshot.
	local_player.global_position = Vector3(10.0, 0.0, 0.0)
	local_player.set("_prediction_history", {
		10: Vector3(8.0, 0.0, 0.0),
		11: Vector3(10.0, 0.0, 0.0),
	})
	local_player.set("_pending_reconciliation", Vector3(50.0, 0.0, 0.0))
	local_player.call(
		"_reconcile_predicted_position",
		Vector3(8.25, 0.0, 0.0),
		Vector3.ZERO,
		10
	)
	var pending: Vector3 = local_player.get("_pending_reconciliation")
	if not pending.is_equal_approx(Vector3(0.25, 0.0, 0.0)):
		return _fail("A fresh prediction correction accumulated the stale pending error.")
	local_player.call("_apply_pending_reconciliation", 0.1)
	var history: Dictionary = local_player.get("_prediction_history")
	if not local_player.global_position.is_equal_approx(Vector3(10.25, 0.0, 0.0)):
		return _fail("Smooth reconciliation did not move the local player correctly.")
	if not (history[11] as Vector3).is_equal_approx(Vector3(10.25, 0.0, 0.0)):
		return _fail("Smooth reconciliation left future prediction history stale.")
	local_player.call(
		"_reconcile_predicted_position",
		Vector3(10.25, 0.0, 0.0),
		Vector3.ZERO,
		11
	)
	pending = local_player.get("_pending_reconciliation")
	if not pending.is_zero_approx():
		return _fail("The next matching snapshot rediscovered an already-applied correction.")

	local_player.global_position = Vector3(20.0, 0.0, 0.0)
	local_player.set("_prediction_history", {
		12: Vector3(20.0, 0.0, 0.0),
		13: Vector3(21.0, 0.0, 0.0),
	})
	local_player.call(
		"_reconcile_predicted_position",
		Vector3.ZERO,
		Vector3(1.0, 0.0, 0.0),
		12
	)
	history = local_player.get("_prediction_history")
	if not local_player.global_position.is_equal_approx(Vector3.ZERO):
		return _fail("A large authoritative correction did not hard-snap the player.")
	if not (history[13] as Vector3).is_equal_approx(Vector3(1.0, 0.0, 0.0)):
		return _fail("Hard reconciliation left future prediction history stale.")

	# A networked first-person minigame owns the local camera/body transform.
	# The server parks its replica at the interaction point, so reconciling to
	# that position during the encounter used to drag the flashlight off-door.
	var door_minigame := local_player.get_node("DoorGhostMinigame") as DoorGhostMinigame
	door_minigame.active = true
	local_player.global_position = Vector3(12.0, 0.0, 3.0)
	local_player.set("_prediction_history", {20: local_player.global_position})
	local_player.set("_pending_reconciliation", Vector3(4.0, 0.0, 0.0))
	local_player.call(
		"_reconcile_predicted_position",
		Vector3.ZERO,
		Vector3.ZERO,
		20
	)
	if not local_player.global_position.is_equal_approx(Vector3(12.0, 0.0, 3.0)):
		return _fail("Server reconciliation pulled a running door minigame away from its camera.")
	if not (local_player.get("_pending_reconciliation") as Vector3).is_zero_approx() \
		or not (local_player.get("_prediction_history") as Dictionary).is_empty():
		return _fail("A door minigame kept stale prediction corrections queued for its exit.")
	door_minigame.active = false

	# A replica is placed rather than simulated, so get_real_velocity() and
	# is_on_floor() both read empty on it. Deriving its footsteps from anything
	# else leaves every teammate walking the house in total silence.
	remote_player.set("_has_network_snapshot", true)
	remote_player.set("_snapshot_position", remote_player.global_position)
	remote_player.set("_snapshot_velocity", Vector3(2.4, 0.0, 0.0))
	remote_player.call("_interpolate_network_snapshot", 0.05)
	var stop_times: Array = remote_player.get("_footstep_stop_times")
	if float(stop_times[0]) <= 0.0:
		return _fail("A moving remote replica made no footstep sound.")

	manager.set("session_active", false)
	print(
		"Player instance isolation smoke test passed: crouch capsules are unique, "
		+ "remote/unowned replicas cannot steal the local camera, A/D stays aligned, "
		+ "remote players remain audible walking; "
		+ "reconciliation stays bounded."
	)
	quit()


func _fail(message: String) -> void:
	var manager := root.get_node_or_null(^"/root/NetworkManager")
	if manager:
		manager.set("session_active", false)
	push_error("Player instance isolation smoke test failed: " + message)
	print("Player instance isolation smoke test FAILED: " + message)
	quit(1)

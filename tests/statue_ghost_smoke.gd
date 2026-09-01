extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not InputMap.has_action('blink'):
		_fail('Blink input action is missing.')
		return

	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(20.0, 0.2, 20.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.1
	ground.add_child(ground_shape)
	root.add_child(ground)

	var player_scene := load('res://player/player.tscn') as PackedScene
	var player := player_scene.instantiate() as CharacterBody3D
	player.set('automatic_blink_enabled', false)
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.9, 0.0)
	player.global_rotation = Vector3.ZERO

	var statue_scene := load('res://ghosts/statue_ghost.tscn') as PackedScene
	var statue := statue_scene.instantiate() as CharacterBody3D
	statue.set('intermittent_hunts_enabled', false)
	statue.set('unseen_grace_time', 0.0)
	# This test measures how far a blink lets the statue lunge, which means
	# blinking it right up next to the player - keep the point-blank blink kill
	# out of it, tests/statue_blink_kill_smoke.gd covers that.
	statue.set('blink_kill_distance', 0.0)
	root.add_child(statue)
	statue.global_position = Vector3(0.0, 0.02, -5.0)

	await physics_frame
	await physics_frame
	await physics_frame

	if not statue.get('is_observed'):
		_fail('Statue was not frozen while the player looked at it.')
		return

	var frozen_position := statue.global_position
	await create_timer(0.25).timeout
	if statue.global_position.distance_to(frozen_position) > 0.04:
		_fail('Observed statue moved instead of freezing.')
		return

	player.rotation.y = PI
	var look_away_position := statue.global_position
	await create_timer(0.35).timeout
	if statue.global_position.distance_to(look_away_position) < 0.2:
		_fail('Statue did not move while the player looked away.')
		return

	player.rotation.y = 0.0
	await physics_frame
	await physics_frame
	if not statue.get('is_observed'):
		_fail('Statue did not freeze again when the player looked back.')
		return

	# The look-away check above runs with unseen_grace_time forced to 0.0 so it
	# stays fast; restore the real default here so this check actually
	# exercises the grace-period gate a normal automatic blink runs into.
	statue.set('unseen_grace_time', 0.32)
	await create_timer(0.2).timeout
	if not statue.get('is_observed'):
		_fail('Statue was not observed before the default-duration blink check.')
		return

	var default_blink_start_position := statue.global_position
	player.call('force_blink')  # no override: exercises the default 0.22s duration
	await physics_frame
	if not player.get('eyes_closed'):
		_fail('Player did not close their eyes during a default-length forced blink.')
		return

	await create_timer(float(player.get('forced_blink_duration')) + 0.05).timeout
	var default_blink_distance := statue.global_position.distance_to(default_blink_start_position)
	if default_blink_distance < 0.12:
		_fail('Statue barely moved during a normal-length automatic blink: moved %.3f m.' % default_blink_distance)
		return

	# The signature lunge now scales with distance. Put it at the far end of the
	# same clear room and verify one identical blink covers substantially more
	# ground than the nearer blink above.
	statue.global_position = Vector3(0.0, 0.02, -8.0)
	statue.velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	if not statue.get('is_observed'):
		_fail('Far statue was not observed before the distance-scaled blink check.')
		return
	var far_blink_start_position := statue.global_position
	player.call('force_blink')
	await create_timer(float(player.get('forced_blink_duration')) + 0.05).timeout
	var far_blink_distance := statue.global_position.distance_to(far_blink_start_position)
	if far_blink_distance < 1.5 or far_blink_distance < default_blink_distance * 1.65:
		_fail(
			'Far blink lunge was not meaningfully stronger: near %.3f m, far %.3f m.' % [
				default_blink_distance,
				far_blink_distance,
			]
		)
		return

	# Restore the pre-check position/baseline so the creep from this check
	# doesn't carry the statue closer to the player than the rest of this
	# test expects.
	statue.global_position = default_blink_start_position
	await physics_frame
	await physics_frame
	if not statue.get('is_observed'):
		_fail('Statue was not observed again after the default-duration blink check.')
		return

	player.call('force_blink', 0.8)
	await physics_frame
	if not player.get('eyes_closed'):
		_fail('Player did not close their eyes during forced blink.')
		return

	var unseen_position := statue.global_position
	await create_timer(0.45).timeout
	if statue.global_position.distance_to(unseen_position) < 0.2:
		_fail('Statue did not move while the player eyes were closed.')
		return

	statue.global_position = Vector3(0.0, 0.02, -0.85)
	statue.set('attack_windup', 0.12)
	player.call('force_blink', 0.8)
	await create_timer(0.35).timeout
	if player.get('is_alive'):
		_fail('Statue attack did not kill an unobserving nearby player.')
		return

	statue.get_node('TeleportAudio').stop()
	statue.get_node('AttackAudio').stop()
	statue.get_node('SpottedJumpscareAudio').stop()
	statue.get_node('TeleportAudio').stream = null
	statue.get_node('AttackAudio').stream = null
	statue.get_node('SpottedJumpscareAudio').stream = null
	print(
		'Statue ghost smoke test passed: freeze, near blink %.2f m, far blink %.2f m, and attack.' % [
			default_blink_distance,
			far_blink_distance,
		]
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

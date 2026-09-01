extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.9, 0.0)
	player.global_rotation = Vector3.ZERO

	var statue_scene := load('res://ghosts/statue_ghost.tscn') as PackedScene
	var statue := statue_scene.instantiate() as CharacterBody3D
	statue.set('intermittent_hunts_enabled', false)
	statue.set('unseen_grace_time', 0.0)
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
	# stays fast; restore the real default here so this check exercises the
	# grace-period gate a genuine glance away runs into.
	statue.set('unseen_grace_time', 0.32)
	await create_timer(0.2).timeout
	if not statue.get('is_observed'):
		_fail('Statue was not observed before the grace-period check.')
		return

	# Shorter than the grace period: a flinch away and back is not an opening.
	var flinch_start_position := statue.global_position
	player.rotation.y = PI
	await create_timer(0.2).timeout
	player.rotation.y = 0.0
	await physics_frame
	if statue.global_position.distance_to(flinch_start_position) > 0.08:
		_fail('Statue advanced during a look-away shorter than unseen_grace_time.')
		return

	await create_timer(0.2).timeout
	if not statue.get('is_observed'):
		_fail('Statue was not observed again after the grace-period check.')
		return

	# Long enough to clear the grace period: this is the whole opening now that
	# the blink is gone, so it has to be worth real ground.
	var unseen_position := statue.global_position
	player.rotation.y = PI
	await create_timer(0.8).timeout
	var unseen_distance := statue.global_position.distance_to(unseen_position)
	if unseen_distance < 0.5:
		_fail('Statue barely moved across a sustained look-away: moved %.3f m.' % unseen_distance)
		return

	statue.global_position = Vector3(0.0, 0.02, -0.85)
	statue.set('attack_windup', 0.12)
	await create_timer(1.5).timeout
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
		'Statue ghost smoke test passed: freeze, grace period, %.2f m gained on a look-away, and attack.'
			% unseen_distance
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

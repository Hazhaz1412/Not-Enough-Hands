## Point-blank blink kill: inside blink_kill_distance the statue does not wind
## up an attack, the blink itself is the kill. Set up so the ordinary attack
## can never explain a death - the statue stays outside attack_range the whole
## test, and the kill has to land in the first frames of a blink, far inside
## the 0.48 s wind-up.
extends SceneTree

const STATUE_DISTANCE := 1.7


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

	var player := (load('res://player/player.tscn') as PackedScene).instantiate() as CharacterBody3D
	player.set('automatic_blink_enabled', false)
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.9, 0.0)
	player.global_rotation = Vector3.ZERO

	var statue := (load('res://ghosts/statue_ghost.tscn') as PackedScene).instantiate() as CharacterBody3D
	statue.set('intermittent_hunts_enabled', false)
	root.add_child(statue)
	statue.global_position = Vector3(0.0, 0.02, -STATUE_DISTANCE)

	await physics_frame
	await physics_frame
	await physics_frame
	if STATUE_DISTANCE <= float(statue.get('attack_range')):
		_fail('Test setup is inside attack_range: an ordinary swing could explain the kill.')
		return
	if not statue.get('is_observed'):
		_fail('Statue did not freeze while the player looked straight at it.')
		return

	# Standing this close is not fatal on its own. Only closing your eyes is.
	await create_timer(0.3).timeout
	if not player.get('is_alive'):
		_fail('Player died with their eyes open and the statue frozen.')
		return

	# With the kill switched off, the same blink at the same range has to leave
	# the player standing - the wind-up is far longer than these two frames.
	statue.set('blink_kill_distance', 0.0)
	player.call('force_blink', 0.2)
	await physics_frame
	await physics_frame
	if not player.get('is_alive'):
		_fail('Player died at blink_kill_distance = 0, so the kill is not what this range gate does.')
		return

	await create_timer(0.3).timeout
	statue.global_position = Vector3(0.0, 0.02, -STATUE_DISTANCE)
	statue.velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	if not statue.get('is_observed'):
		_fail('Statue was not frozen again before the lethal blink.')
		return

	statue.set('blink_kill_distance', 2.0)
	player.call('force_blink', 0.4)
	await physics_frame
	await physics_frame
	if player.get('is_alive'):
		_fail('Blinking inside blink_kill_distance did not kill the player on the spot.')
		return

	var kill_distance := statue.global_position.distance_to(player.global_position)
	if kill_distance <= float(statue.get('attack_range')):
		_fail('Statue closed inside attack_range (%.2f m): the kill may have been a normal swing.' % kill_distance)
		return

	statue.get_node('TeleportAudio').stop()
	statue.get_node('AttackAudio').stop()
	statue.get_node('SpottedJumpscareAudio').stop()
	statue.get_node('TeleportAudio').stream = null
	statue.get_node('AttackAudio').stream = null
	statue.get_node('SpottedJumpscareAudio').stream = null
	print('Statue blink kill smoke test passed: killed at %.2f m, two frames into the blink.' % kill_distance)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

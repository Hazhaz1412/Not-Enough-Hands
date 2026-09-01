extends SceneTree

## The Huntsman's slash, and only the slash.
##
## tests/hunter_ghost_smoke.gd already covers the hunt around it - the breach,
## the trail, the roar, the lock, the fact that a grab kills at all - so nothing
## here re-tests any of that. What this pins is the three things that make the
## grab feel like a grab instead of a slow reach, and that would rot silently
## the moment somebody retuned a number:
##
##   * the grab plays the attack clip, and the body's own animation rate is left
##     alone the whole way through - the slash is a clip change, not a rate
##     change, because nothing in hunter_ghost.gd drives set_clip_speed();
##   * commitment to contact is exactly the `seize_windup` half-second, so a
##     quiet retune of the only dodge window this creature has fails here;
##   * a player who simply holds the back key cannot walk out of a grab that has
##     already committed, while a player who sprints still can.
##
## The two retreats are driven by moving the body directly rather than through
## input, which headless has none of. Both use the player's own speeds so the
## test cannot pass by disagreeing with player.gd about how fast a person is.

const FLOOR_Y := 0.0
## SceneTree has no delta of its own; this is the tick everything here advances
## by, and the same one the hunter's own _physics_process() runs on.
var _tick: float = 1.0 / float(Engine.physics_ticks_per_second)
## Mirrors HunterState's declaration order; the enum lives on the hunter's own
## script, which a SceneTree script has no static handle on.
const HunterState_LOCKED := 5
const HunterState_SEIZING := 6

var hunter_scene: PackedScene


func _initialize() -> void:
	_run.call_deferred()


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false


func _run() -> void:
	_build_floor()
	hunter_scene = load("res://ghosts/hunter_ghost.tscn") as PackedScene
	if hunter_scene == null:
		_fail("Failed to load the hunter scene.")
		return

	if not await _test_the_grab_plays_the_attack_clip():
		return
	if not await _test_commitment_to_contact_is_the_windup():
		return
	if not await _test_backpedal_cannot_escape_a_committed_grab():
		return
	if not await _test_a_sprint_still_escapes():
		return

	print("Hunter slash smoke test passed: attack clip with the body rate left "
		+ "alone, commit timing, backpedal is caught, sprint still escapes.")
	quit()


# ------------------------------------------------------------------- tests ---

## The whole body runs off one AnimationPlayer, so anything that touched its rate
## for the slash would be speeding up the idle and the walk too unless it put the
## rate back. Nothing does touch it today - the grab is selected by clip, in
## _clip_for_state() - so the rate is pinned at both ends and in the middle, and
## a future speed-up that forgets to restore it fails here.
func _test_the_grab_plays_the_attack_clip() -> bool:
	var hunter := await _spawn_hunter(Vector3.ZERO)
	var player := _spawn_player(Vector3(0.0, 0.9, -2.0))
	await physics_frame

	var animation := _animation_player(hunter)
	if animation == null:
		return _fail("The Huntsman's body has no AnimationPlayer to speed up.")
	if not is_equal_approx(animation.speed_scale, 1.0):
		return _fail("The body was already running at %.2f before any grab." % animation.speed_scale)

	hunter.call("dev_force_spawn", null)
	hunter.set("roar_duration", 0.05)
	if not await _wait_for_state(hunter, HunterState_SEIZING, 6.0):
		return _fail("The Huntsman never reached its grab.")

	if not is_equal_approx(animation.speed_scale, 1.0):
		return _fail(
			"The body ran at %.2f during the grab; nothing should be driving its rate."
			% animation.speed_scale
		)
	if hunter.get_node("VisualRoot").get_current_clip() != &"Attack":
		return _fail("The grab did not play the attack clip.")

	# Out the far side of the grab: everything else runs at its own rate again.
	await create_timer(1.2).timeout
	if int(hunter.get("state")) == HunterState_SEIZING:
		return _fail("The grab never ended.")
	if not is_equal_approx(animation.speed_scale, 1.0):
		return _fail("The body was left running at %.2f after the grab." % animation.speed_scale)

	await _despawn(hunter)
	await _despawn(player)
	return true


## Commit to contact, measured off the creature's own signals and then checked
## twice: against the export, which says the wind-up timer really is what gates
## the kill, and against the value the export is meant to hold, which is what
## makes a quiet retune of the only dodge window in the creature fail here
## instead of only in play.
##
## Counted in physics frames, not wall clock: headless runs the loop as fast as
## it can, so half a second of gameplay goes by in a fraction of that in real
## time and a clock-based check would read whatever the machine felt like.
func _test_commitment_to_contact_is_the_windup() -> bool:
	var hunter := await _spawn_hunter(Vector3.ZERO)
	var player := _spawn_player(Vector3(0.0, 0.9, -2.0))
	await physics_frame

	var committed := [-1]
	var landed := [-1]
	hunter.seize_started.connect(func(_target: Node3D) -> void:
		committed[0] = Engine.get_physics_frames())
	hunter.killed_player.connect(func(_target: Node3D) -> void:
		landed[0] = Engine.get_physics_frames())

	hunter.call("dev_force_spawn", null)
	hunter.set("roar_duration", 0.05)
	if not await _wait_for(func() -> bool: return landed[0] > 0, 8.0):
		return _fail("The Huntsman never landed its grab on a stationary player.")

	var elapsed := float(landed[0] - committed[0]) * _tick
	var windup: float = hunter.get("seize_windup")
	if not is_equal_approx(windup, 0.5):
		return _fail(
			("seize_windup is %.2fs, not the 0.5s the class docstring calls the only " % windup)
			+ "dodge window there is. If that retune is deliberate, move this number with it."
		)
	# A frame either side: the resolve happens on the physics tick the timer runs
	# out on, not on the exact instant.
	if absf(elapsed - windup) > _tick * 2.0:
		return _fail(
			"Commitment to contact took %.3fs against a %.2fs wind-up." % [elapsed, windup]
		)

	await _despawn(hunter)
	await _despawn(player)
	return true


## The behaviour the retune exists for. Held back-key, at the player's own walk
## speed, from the far edge of the grab's reach.
func _test_backpedal_cannot_escape_a_committed_grab() -> bool:
	if await _retreat_survives(1.0):
		return _fail(
			"A player walking straight backwards out-ran a grab the Huntsman had "
			+ "already committed to."
		)
	return true


## And the other half of the bargain: it is still a window, not a death
## sentence. Same retreat, at a sprint.
func _test_a_sprint_still_escapes() -> bool:
	if not await _retreat_survives(0.0):
		return _fail(
			"A sprinting player could not escape a committed grab; the slash has "
			+ "become unavoidable."
		)
	return true


# ----------------------------------------------------------------- harness ---

## Runs one grab against a player retreating in a straight line and reports
## whether they lived. `sprint` picks between the player's own walk speed and
## its own sprint multiple of it, so this test never invents a speed.
func _retreat_survives(walk_fraction: float) -> bool:
	var hunter := await _spawn_hunter(Vector3.ZERO)
	var player := _spawn_player(Vector3(0.0, 0.9, -2.3))
	await physics_frame

	var walk: float = player.get("walk_speed")
	var speed: float = walk if walk_fraction > 0.5 else walk * float(player.get("sprint_speed_multiplier"))

	hunter.call("dev_force_spawn", null)
	hunter.set("roar_duration", 0.05)
	if not await _wait_for_state(hunter, HunterState_SEIZING, 8.0):
		_fail("The Huntsman never committed to a grab to retreat from.")
		return false

	# Straight away from it, starting on the frame it commits.
	var elapsed := 0.0
	while elapsed < 1.0 and bool(player.get("is_alive")):
		var away := player.global_position - hunter.global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			player.global_position += away.normalized() * speed * _tick
		await physics_frame
		elapsed += _tick

	var survived := bool(player.get("is_alive"))
	await _despawn(hunter)
	await _despawn(player)
	return survived


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 60.0)
	shape_node.shape = box
	body.add_child(shape_node)
	root.add_child(body)
	body.global_position = Vector3(0.0, FLOOR_Y - 0.1, 0.0)


func _spawn_hunter(at: Vector3) -> CharacterBody3D:
	var hunter := hunter_scene.instantiate() as CharacterBody3D
	hunter.set("entry_enabled", false)
	root.add_child(hunter)
	hunter.global_position = at
	for node_name: String in [
		"FootstepAudio", "HookAudio", "BreathAudio", "SniffAudio",
		"HornAudio", "SeizeAudio", "BreachAudio",
	]:
		var audio_player := hunter.get_node_or_null(node_name) as AudioStreamPlayer3D
		if audio_player:
			audio_player.stop()
	await process_frame
	await physics_frame
	return hunter


func _spawn_player(at: Vector3) -> CharacterBody3D:
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	player.global_position = at
	return player


func _despawn(node: Node) -> void:
	node.queue_free()
	await process_frame
	await physics_frame


func _animation_player(hunter: Node) -> AnimationPlayer:
	var body := hunter.get_node_or_null("VisualRoot")
	if body == null:
		return null
	return body.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _wait_for_state(hunter: Node, wanted: int, timeout: float) -> bool:
	return await _wait_for(func() -> bool: return int(hunter.get("state")) == wanted, timeout)


func _wait_for(predicate: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if predicate.call():
			return true
		await physics_frame
		waited += _tick
	return false

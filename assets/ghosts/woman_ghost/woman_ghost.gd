class_name WomanGhost
extends CharacterBody3D

## Reusable animated ghost. Drag woman_ghost.tscn into any 3D scene.
@export var transition_seconds := 0.35
@export var start_walking := false
@export var auto_cycle := false
@export var idle_seconds := 4.0
@export var walk_seconds := 6.0
@export_category("Enemy Movement")
@export var chase_enabled := true
@export var chase_speed := 2.25
@export var acceleration := 7.0
@export var stopping_distance := 1.35

var _idle_player: AnimationPlayer
var _animation_player: AnimationPlayer
var _idle_animation := StringName()
var _walk_animation := StringName()
var _installed_idle_animation := &"Idle"
var _walking := false
var _phase_time_left := 0.0
var _target: Node3D

func _ready() -> void:
	_idle_player = _find_animation_player($IdleAnimationSource)
	_animation_player = _find_animation_player($AnimatedModel)
	_idle_animation = _find_loopable_animation(_idle_player)
	_walk_animation = _find_loopable_animation(_animation_player)
	_install_idle_on_animated_model()
	$IdleAnimationSource.visible = false
	$AnimatedModel.visible = true
	add_to_group("hostile_ghosts")
	set_walking(start_walking)

## The seam WorldReplicator animates a replicated copy through, matching the
## other three ghosts: on a client this body is placed rather than simulated, so
## the walk cycle is chosen from the velocity that arrived with the position.
func _update_presentation(_delta: float) -> void:
	set_walking(Vector2(velocity.x, velocity.z).length() > 0.05)

func _process(delta: float) -> void:
	if not WorldNet.is_world_authority():
		return
	if not auto_cycle or _target != null:
		return
	_phase_time_left -= delta
	if _phase_time_left <= 0.0:
		set_walking(not _walking)

func _physics_process(delta: float) -> void:
	if not WorldNet.is_world_authority():
		return
	_target = _nearest_player() if chase_enabled else null
	# The standalone preview owns animation and positioning while it has no
	# player to chase. In gameplay, auto_cycle is normally left disabled.
	if _target == null and auto_cycle:
		return
	var direction := Vector3.ZERO
	if _target != null:
		var distance := global_position.distance_to(_target.global_position)
		if distance > stopping_distance:
			$NavigationAgent3D.target_position = _target.global_position
			# Fallback to direct pursuit until a NavigationRegion3D is available
			# and has produced a path. This keeps the component useful in a blank
			# test scene as well as in the house navigation mesh.
			var next_position := _target.global_position
			if not $NavigationAgent3D.is_navigation_finished():
				next_position = $NavigationAgent3D.get_next_path_position()
			direction = next_position - global_position
			direction.y = 0.0

	if direction.length_squared() > 0.001:
		direction = direction.normalized()
		velocity.x = move_toward(velocity.x, direction.x * chase_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * chase_speed, acceleration * delta)
		look_at(global_position + direction, Vector3.UP, true)
		play_walk()
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		play_idle()

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()

## Starts the looping Idle clip with a short pose blend.
func play_idle() -> void:
	set_walking(false)

## Starts the looping Walk clip with a short pose blend.
func play_walk() -> void:
	set_walking(true)

func set_walking(value: bool) -> void:
	if _walking == value and _animation_player != null and _animation_player.is_playing():
		return
	_walking = value
	_phase_time_left = walk_seconds if _walking else idle_seconds
	var animation_name := _walk_animation if _walking else _installed_idle_animation
	if _animation_player != null and not animation_name.is_empty():
		_animation_player.play(animation_name, transition_seconds)

func is_walking() -> bool:
	return _walking

func _nearest_player() -> Node3D:
	var nearest: Node3D
	var nearest_distance := INF
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Node3D
		if player == null:
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < nearest_distance:
			nearest = player
			nearest_distance = distance
	return nearest

func _find_loopable_animation(player: AnimationPlayer) -> StringName:
	if player == null:
		push_warning("WomanGhost: AnimationPlayer not found.")
		return StringName()
	for animation_name in player.get_animation_list():
		if animation_name == &"RESET":
			continue
		var clip := player.get_animation(animation_name)
		if clip.length > 0.1:
			clip.loop_mode = Animation.LOOP_LINEAR
			return animation_name
	push_warning("WomanGhost: no playable animation was found.")
	return StringName()

func _install_idle_on_animated_model() -> void:
	if _idle_player == null or _animation_player == null or _idle_animation.is_empty():
		return
	var idle_clip := _idle_player.get_animation(_idle_animation).duplicate(true) as Animation
	idle_clip.loop_mode = Animation.LOOP_LINEAR
	var library := _animation_player.get_animation_library(&"")
	if library == null:
		push_warning("WomanGhost: default animation library was not found.")
		return
	if library.has_animation(_installed_idle_animation):
		library.remove_animation(_installed_idle_animation)
	library.add_animation(_installed_idle_animation, idle_clip)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

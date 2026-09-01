extends Node3D

enum DoorState { CLOSED, OPENING, OPEN, CLOSING, PUSHED }
var state: DoorState = DoorState.CLOSED

@export var interaction_range: float = 3.0
@export var open_angle: float = 90.0 # Degrees
@export var open_duration: float = 0.5
@export var close_duration: float = 0.5
@export var hinge_direction: int = 1

@export_category("Player Push")
## An ordinary interior door yields only when the player is actually near its
## leaf, not merely near the doorway. How close they press determines how far
## it swings, and it settles shut again after they pass.
@export var player_push_enabled: bool = true
@export var player_push_start_distance: float = 0.9
@export var player_push_full_distance: float = 0.2
## Once the player has touched the leaf, keep its last pushed angle until
## they have cleared this much space. This prevents slow walking and physics
## contact resolution from repeatedly lowering the target and trapping them.
@export var player_push_release_distance: float = 1.5
@export var player_push_width_padding: float = 0.28
## The broader doorway corridor that retains an already-started push. It is
## intentionally wider than the leaf itself so a capsule sliding around the
## edge cannot make the door stutter shut mid-passage.
@export var player_push_hold_width_padding: float = 0.65
@export var player_push_open_speed: float = 360.0
@export var player_push_close_speed: float = 420.0
const DOOR_LEAF_WIDTH := 2.0
const DOOR_LEAF_HEIGHT := 2.3

@onready var hinge: AnimatableBody3D = $Hinge
var tween: Tween

@export_category('Ghosts')
## A ghost has no hands and never presses E, so without this a closed interior
## door is a permanent wall to it. The villa's navmesh is deliberately baked
## with the door leaves lifted out - a closed door would otherwise freeze into
## the route graph and cut the floor into one island per room - so every ghost
## routes straight through doorways and used to jam against the leaf and stay
## there. House2 has no interior doors, which is why this only shows up on the
## villa. Ghosts shoulder the leaf open instead; it costs them the swing.
@export var ghost_shoulder_enabled: bool = true
## How close a ghost gets before it leans on the leaf.
@export var ghost_shoulder_distance: float = 1.5
## Ghosts on the storey above or below must not work this door.
@export var ghost_shoulder_height: float = 2.0
## How long a ghost-opened door stands open once nothing is near it any more.
## Leaving them open would quietly retire the "shut it behind you" tactic.
@export var ghost_shoulder_close_delay: float = 5.0

var _opened_by_ghost: bool = false
var _ghost_clear_time: float = 0.0
## Captured when the player first presses the leaf. It must not flip while
## they cross the threshold, or the leaf would swing back through them.
var _player_push_sign: int = 1
var _player_push_peak_openness: float = 0.0

## One group query per physics frame for the whole level rather than one per
## door: with 48 interior doors in the villa that is the difference between 48
## array allocations a frame and one.
static var _ghost_cache: Array[Node] = []
static var _ghost_cache_frame: int = -1

## Loudness of working a door, on the crawler's 0-1 hearing scale. Well above a
## sprint: shutting a door behind you buys cover from the thing that hunts by
## sight and hands your position to the thing that hunts by sound.
@export_range(0.0, 1.0) var noise_loudness: float = 0.7

func _ready() -> void:
	# Working the handle is an event only the server sees, so it is echoed to
	# every peer. The other two ways this leaf moves need no such call: the
	# ghost shoulder and the player push are both driven off ghost and player
	# positions, which are already replicated, so each peer reaches the same
	# angle on its own and the push stays smooth instead of arriving at 5 Hz.
	add_to_group(&"replicated_interactions")


func interact(player: Node3D = null) -> void:
	if state == DoorState.OPENING or state == DoorState.CLOSING:
		return

	get_tree().call_group(
		'crawler_ghosts',
		'report_noise',
		global_position,
		noise_loudness,
		self
	)

	if state == DoorState.CLOSED or state == DoorState.PUSHED:
		_open_fully(player)
		
	elif state == DoorState.OPEN:
		state = DoorState.CLOSING
		if tween and tween.is_running():
			tween.kill()
		tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(hinge, "rotation:y", 0.0, close_duration)
		tween.tween_callback(func(): state = DoorState.CLOSED)


func _open_fully(player: Node3D) -> void:
	state = DoorState.OPENING
	var target_rot_y := deg_to_rad(open_angle) * _opening_sign(player) * hinge_direction
	if tween and tween.is_running():
		tween.kill()
	tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(hinge, "rotation:y", target_rot_y, open_duration)
	tween.tween_callback(func(): state = DoorState.OPEN)


func _physics_process(delta: float) -> void:
	if state == DoorState.OPENING or state == DoorState.CLOSING:
		return

	var ghost := _ghost_at_the_door() if ghost_shoulder_enabled else null
	if state == DoorState.CLOSED:
		if ghost:
			_opened_by_ghost = true
			_ghost_clear_time = 0.0
			interact(ghost)
		elif _update_player_push(delta):
			return
		else:
			# Whoever shut it, it is shut: stop treating it as ghost-held.
			_opened_by_ghost = false
		return
	if state == DoorState.PUSHED:
		_update_player_push(delta)
		return

	# Open, and it was a ghost that opened it: swing it shut again once the
	# doorway has been clear for long enough.
	if not _opened_by_ghost:
		return
	if ghost:
		_ghost_clear_time = 0.0
		return
	_ghost_clear_time += delta
	if _ghost_clear_time >= ghost_shoulder_close_delay:
		_opened_by_ghost = false
		interact(null)


## Moves the leaf by the same fraction the player is pressing into it. Kept
## public-ish for the door smoke test; normal play enters through _physics_process.
func _update_player_push(delta: float) -> bool:
	if not player_push_enabled:
		return false
	var player := _nearest_player()
	var local_player := to_local(player.global_position) if is_instance_valid(player) else Vector3.ZERO
	var openness := _player_push_openness(player)
	if state == DoorState.PUSHED and _player_is_in_push_corridor(local_player):
		# Keep the strongest push made during this passage. Collision resolution
		# can nudge a slowly walking capsule a few centimetres away from the leaf;
		# following that jitter down would repeatedly close the door into it.
		_player_push_peak_openness = maxf(_player_push_peak_openness, openness)
		hinge.rotation.y = move_toward(
			hinge.rotation.y,
			deg_to_rad(open_angle) * _player_push_peak_openness * _player_push_sign * hinge_direction,
			deg_to_rad(player_push_open_speed) * maxf(delta, 0.0)
		)
		return true
	if openness > 0.0:
		_opened_by_ghost = false
		if state != DoorState.PUSHED:
			_player_push_sign = _opening_sign(player)
			_player_push_peak_openness = openness
		else:
			_player_push_peak_openness = maxf(_player_push_peak_openness, openness)
		var target_rotation := deg_to_rad(open_angle) * openness * _player_push_sign * hinge_direction
		hinge.rotation.y = move_toward(
			hinge.rotation.y,
			target_rotation,
			deg_to_rad(player_push_open_speed) * maxf(delta, 0.0)
		)
		state = DoorState.PUSHED
		return true
	if state != DoorState.PUSHED:
		return false
	hinge.rotation.y = move_toward(
		hinge.rotation.y,
		0.0,
		deg_to_rad(player_push_close_speed) * maxf(delta, 0.0)
	)
	if is_zero_approx(hinge.rotation.y):
		state = DoorState.CLOSED
		_player_push_sign = 1
		_player_push_peak_openness = 0.0
	return true


## The player this leaf answers to. It used to be whichever node the `players`
## group happened to list first, which in a four-player session meant three of
## them walked through a door that never moved - and, worse, that different
## peers could pick different players and disagree about the angle.
func _nearest_player() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if not is_instance_valid(player):
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < nearest_distance:
			nearest = player
			nearest_distance = distance
	return nearest


func _player_push_openness(player: Node3D) -> float:
	if not is_instance_valid(player):
		return 0.0
	var local_player := to_local(player.global_position)
	if local_player.y < -0.2 or local_player.y > DOOR_LEAF_HEIGHT + 0.2 \
			or local_player.x < -player_push_width_padding \
			or local_player.x > DOOR_LEAF_WIDTH + player_push_width_padding:
		return 0.0
	var start := maxf(player_push_start_distance, player_push_full_distance + 0.01)
	if absf(local_player.z) >= start:
		return 0.0
	return clampf(inverse_lerp(start, player_push_full_distance, absf(local_player.z)), 0.0, 1.0)


func _player_is_in_push_corridor(local_player: Vector3) -> bool:
	return local_player.y >= -0.2 and local_player.y <= DOOR_LEAF_HEIGHT + 0.2 \
		and local_player.x >= -player_push_hold_width_padding \
		and local_player.x <= DOOR_LEAF_WIDTH + player_push_hold_width_padding \
		and absf(local_player.z) < maxf(player_push_release_distance, player_push_start_distance)


func _opening_sign(player: Node3D) -> int:
	var local_player_z := to_local(player.global_position).z if is_instance_valid(player) else 1.0
	# Swing away from the side that is pushing it, never through the player.
	return -1 if local_player_z < 0.0 else 1


## The nearest manifested ghost this leaf is actually in the way of. A hidden
## ghost clears its own collision mask, so asking whether the leaf can block it
## is also asking whether it is really in the house yet.
func _ghost_at_the_door() -> Node3D:
	var frame := Engine.get_physics_frames()
	if frame != _ghost_cache_frame:
		_ghost_cache_frame = frame
		_ghost_cache = get_tree().get_nodes_in_group('hostile_ghosts')

	# The leaf hangs from a jamb, so the door node's own origin is a metre off
	# to one side of the opening it closes.
	var opening := to_global(Vector3(1.15, 0.0, 0.0))
	var nearest: Node3D = null
	var nearest_distance := ghost_shoulder_distance
	for node: Node in _ghost_cache:
		var ghost := node as CollisionObject3D
		if not ghost or (ghost.collision_mask & hinge.collision_layer) == 0:
			continue
		var offset := ghost.global_position - opening
		if absf(offset.y) > ghost_shoulder_height:
			continue
		var distance := Vector2(offset.x, offset.z).length()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = ghost
	return nearest

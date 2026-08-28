extends Node3D

enum DoorState { CLOSED, OPENING, OPEN, CLOSING }
var state: DoorState = DoorState.CLOSED

@export var interaction_range: float = 3.0
@export var open_angle: float = 90.0 # Degrees
@export var open_duration: float = 0.5
@export var close_duration: float = 0.5
@export var hinge_direction: int = 1

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

## One group query per physics frame for the whole level rather than one per
## door: with 48 interior doors in the villa that is the difference between 48
## array allocations a frame and one.
static var _ghost_cache: Array[Node] = []
static var _ghost_cache_frame: int = -1

## Loudness of working a door, on the crawler's 0-1 hearing scale. Well above a
## sprint: shutting a door behind you buys cover from the thing that hunts by
## sight and hands your position to the thing that hunts by sound.
@export_range(0.0, 1.0) var noise_loudness: float = 0.7

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

	if state == DoorState.CLOSED:
		state = DoorState.OPENING
		
		# Determine player side relative to door's local Z-axis (FORWARD)
		var local_player_pos := Vector3(0.0, 0.0, 1.0)
		if player:
			local_player_pos = to_local(player.global_position)
		# local_player_pos.z > 0 means the player is in front of the door's original Z axis.
		var dot := local_player_pos.z
		
		# If dot < 0 (player is behind), open towards +Z (target_sign = -1)
		# If dot > 0 (player is in front), open towards -Z (target_sign = 1)
		var target_sign = -1 if dot < 0 else 1
		var target_rot_y = deg_to_rad(open_angle) * target_sign * hinge_direction
		
		if tween and tween.is_running():
			tween.kill()
		tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(hinge, "rotation:y", target_rot_y, open_duration)
		tween.tween_callback(func(): state = DoorState.OPEN)
		
	elif state == DoorState.OPEN:
		state = DoorState.CLOSING
		if tween and tween.is_running():
			tween.kill()
		tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(hinge, "rotation:y", 0.0, close_duration)
		tween.tween_callback(func(): state = DoorState.CLOSED)


func _physics_process(delta: float) -> void:
	if not ghost_shoulder_enabled:
		return
	if state == DoorState.OPENING or state == DoorState.CLOSING:
		return

	var ghost := _ghost_at_the_door()
	if state == DoorState.CLOSED:
		if ghost:
			_opened_by_ghost = true
			_ghost_clear_time = 0.0
			interact(ghost)
		else:
			# Whoever shut it, it is shut: stop treating it as ghost-held.
			_opened_by_ghost = false
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
